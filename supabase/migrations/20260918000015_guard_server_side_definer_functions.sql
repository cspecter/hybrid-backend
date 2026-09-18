-- Add a caller guard to the server-side SECURITY DEFINER functions.
--
-- These twelve do notification delivery, push batching, cron maintenance and counter
-- recalculation. None takes a caller identity into account, and several rewrite whole
-- tables. 20260918000003 revoked EXECUTE from anon and authenticated so none is
-- reachable today; this closes the bodies against a future re-grant, the same reason
-- as 20260918000014.
--
-- The guard differs from the one in 20260918000014, and the difference matters:
--
--     IF pg_trigger_depth() = 0
--        AND <jwt role> IN ('anon','authenticated')
--        AND NOT <super admin>
--     THEN RAISE
--
-- pg_trigger_depth() = 0 is the part 20260918000014 did not need. send_notification
-- has six trigger callers -- fn_notify_on_comment, fn_notify_on_comment_like,
-- fn_profile_admins_triggers, notify_brand_of_employee_request,
-- notify_employee_of_approval and process_scheduled_notifications -- and those
-- triggers fire during ORDINARY authenticated user actions. Commenting on a post runs
-- as the commenter, so a guard keyed only on the end user's identity would have broken
-- commenting, liking and employee requests for everyone who is not a super admin.
-- Inside a trigger pg_trigger_depth() is greater than zero, so those paths stay exempt.
-- The same applies to schedule_giveaway_pick, reached from fn_giveaway_schedule_trigger.
--
-- The jwt role test rather than current_user, for the reason recorded in
-- 20260918000013: inside a SECURITY DEFINER function current_user is rebound to the
-- owner and always reads 'postgres'. current_setting is unaffected by security context.
--
-- Branches: a PostgREST request carries role 'anon' or 'authenticated' and is checked;
-- a service_role key carries 'service_role' and is exempt; cron and psql have no such
-- setting and are exempt. cleanup_notifications and process_scheduled_notifications
-- both run from cron as postgres, so both keep working.
--
-- Each body below is the live definition with only the guard block inserted after
-- BEGIN -- generated, not retyped. search_path is pinned where it was not already.

CREATE OR REPLACE FUNCTION public.cleanup_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    -- Clean up old expired notifications (older than 30 days)
    DELETE FROM public.notifications 
    WHERE expires_at < (now() - interval '30 days')
    AND expires_at IS NOT NULL;
    
    -- Clean up old sent scheduled notifications (older than 7 days)
    DELETE FROM public.scheduled_notifications
    WHERE status = 'sent'
    AND sent_at < (now() - interval '7 days');
    
    -- Clean up old notification aggregates (older than 7 days with no activity)
    DELETE FROM public.notification_aggregates
    WHERE last_updated_at < (now() - interval '7 days');
END;
$$;

CREATE OR REPLACE FUNCTION public.process_scheduled_notifications()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_scheduled public.scheduled_notifications%ROWTYPE;
    v_processed integer := 0;
    v_notification_id integer;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    FOR v_scheduled IN 
        SELECT * FROM public.scheduled_notifications
        WHERE status = 'pending'
          AND scheduled_for <= now()
        ORDER BY scheduled_for
        LIMIT 100 -- Process in batches
        FOR UPDATE SKIP LOCKED
    LOOP
        BEGIN
            -- Send the notification
            v_notification_id := public.send_notification(
                v_scheduled.profile_id,
                v_scheduled.type_code,
                v_scheduled.actor_id,
                v_scheduled.related_type,
                v_scheduled.related_id,
                v_scheduled.extra_data
            );
            
            -- Mark as sent
            UPDATE public.scheduled_notifications
            SET status = 'sent', sent_at = now()
            WHERE id = v_scheduled.id;
            
            v_processed := v_processed + 1;
            
        EXCEPTION WHEN OTHERS THEN
            -- Mark as failed
            UPDATE public.scheduled_notifications
            SET status = 'failed', error_message = SQLERRM
            WHERE id = v_scheduled.id;
        END;
    END LOOP;
    
    RETURN v_processed;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_push_batch(p_max_messages integer DEFAULT 2000, p_provider text DEFAULT 'onesignal'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_batch_id integer;
    v_message_count integer;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    -- Create batch
    INSERT INTO public.push_batches (provider)
    VALUES (p_provider)
    RETURNING id INTO v_batch_id;
    
    -- Assign pending messages to this batch
    WITH assigned AS (
        UPDATE public.push_queue
        SET batch_id = v_batch_id
        WHERE id IN (
            SELECT id FROM public.push_queue
            WHERE status = 'pending'
              AND batch_id IS NULL
              AND (send_at IS NULL OR send_at <= now())
              AND (retry_after IS NULL OR retry_after <= now())
            ORDER BY priority ASC, created_at ASC
            LIMIT p_max_messages
            FOR UPDATE SKIP LOCKED
        )
        RETURNING id
    )
    SELECT count(*) INTO v_message_count FROM assigned;
    
    -- Update batch with count
    UPDATE public.push_batches
    SET message_count = v_message_count, started_at = now()
    WHERE id = v_batch_id;
    
    -- If no messages, clean up
    IF v_message_count = 0 THEN
        DELETE FROM public.push_batches WHERE id = v_batch_id;
        RETURN NULL;
    END IF;
    
    RETURN v_batch_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_notification(p_recipient_id integer, p_type_code text, p_actor_id integer DEFAULT NULL::integer, p_related_type text DEFAULT NULL::text, p_related_id integer DEFAULT NULL::integer, p_extra_data jsonb DEFAULT '{}'::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_notification_id integer;
    v_aggregate_id integer;
    v_type public.notification_types%ROWTYPE;
    v_prefs public.notification_preferences%ROWTYPE;
    v_actor public.profiles%ROWTYPE;
    v_title text;
    v_body text;
    v_action_url text;
    v_channels public.notification_channel[];
    v_aggregate_key text;
    v_existing_aggregate public.notification_aggregates%ROWTYPE;
    v_should_create_notification boolean := true;
    v_window_start timestamptz;
    v_key text;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    -- Get notification type
    SELECT * INTO v_type FROM public.notification_types WHERE code = p_type_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown notification type: %', p_type_code;
    END IF;
    
    -- Get user preferences
    SELECT * INTO v_prefs FROM public.notification_preferences WHERE profile_id = p_recipient_id;
    
    -- Check if this type is disabled
    IF v_prefs.disabled_types IS NOT NULL AND v_prefs.disabled_types @> ARRAY[p_type_code] THEN
        RETURN NULL;
    END IF;
    
    -- Check if user is muted
    IF v_prefs.is_muted_until IS NOT NULL AND v_prefs.is_muted_until > now() THEN
        RETURN NULL;
    END IF;
    
    -- Get actor info for template rendering
    IF p_actor_id IS NOT NULL THEN
        SELECT * INTO v_actor FROM public.profiles WHERE id = p_actor_id;
    END IF;
    
    -- Handle aggregation if this notification type is groupable
    IF v_type.is_groupable AND v_type.group_key IS NOT NULL THEN
        -- Build the aggregate key
        v_aggregate_key := v_type.group_key;
        IF p_related_id IS NOT NULL THEN
            v_aggregate_key := replace(v_aggregate_key, '{post_id}', coalesce(p_related_id::text, ''));
            v_aggregate_key := replace(v_aggregate_key, '{product_id}', coalesce(p_related_id::text, ''));
            v_aggregate_key := replace(v_aggregate_key, '{list_id}', coalesce(p_related_id::text, ''));
            v_aggregate_key := replace(v_aggregate_key, '{giveaway_id}', coalesce(p_related_id::text, ''));
        END IF;
        
        -- Calculate window start
        v_window_start := now() - coalesce(v_type.aggregation_window, '1 hour'::interval);
        
        -- Check for existing aggregate in the window
        SELECT * INTO v_existing_aggregate
        FROM public.notification_aggregates
        WHERE profile_id = p_recipient_id
          AND aggregate_key = v_aggregate_key
          AND window_start > v_window_start;
        
        IF v_existing_aggregate.id IS NOT NULL THEN
            -- Update existing aggregate
            UPDATE public.notification_aggregates
            SET 
                count = count + 1,
                actor_ids = CASE 
                    WHEN p_actor_id IS NOT NULL AND NOT (actor_ids @> ARRAY[p_actor_id])
                    THEN (actor_ids || p_actor_id)[1:max_display_actors + 2] -- Keep a few extra
                    ELSE actor_ids
                END,
                last_updated_at = now(),
                is_seen = false
            WHERE id = v_existing_aggregate.id;
            
            v_aggregate_id := v_existing_aggregate.id;
            
            -- Check if we should still create a notification based on max_per_window
            IF v_existing_aggregate.count >= coalesce(v_type.max_per_window, 1) THEN
                v_should_create_notification := false;
            END IF;
        ELSE
            -- Create new aggregate
            INSERT INTO public.notification_aggregates (
                profile_id, aggregate_key, type_code, related_type, related_id,
                actor_ids, window_start
            ) VALUES (
                p_recipient_id, v_aggregate_key, p_type_code, p_related_type, p_related_id,
                CASE WHEN p_actor_id IS NOT NULL THEN ARRAY[p_actor_id] ELSE '{}' END,
                now()
            ) RETURNING id INTO v_aggregate_id;
        END IF;
    END IF;
    
    -- Create the notification if we should
    IF v_should_create_notification THEN
        -- Render templates
        v_title := v_type.title_template;
        v_body := v_type.body_template;
        v_action_url := v_type.action_url_template;
        
        -- Replace actor placeholders (use public_id for URLs)
        IF v_actor.id IS NOT NULL THEN
            v_title := replace(v_title, '{actor_name}', coalesce(v_actor.display_name, v_actor.username, 'Someone'));
            v_body := replace(v_body, '{actor_name}', coalesce(v_actor.display_name, v_actor.username, 'Someone'));
            v_action_url := replace(v_action_url, '{actor_id}', v_actor.public_id::text);
        END IF;
        
        -- Replace related entity placeholders (use public_id for URLs)
        IF p_related_id IS NOT NULL AND p_related_type IS NOT NULL THEN
            -- Get public_id based on related_type
            v_action_url := replace(v_action_url, '{' || p_related_type || '_id}', 
                CASE p_related_type
                    WHEN 'post' THEN (SELECT public_id::text FROM posts WHERE id = p_related_id)
                    WHEN 'product' THEN (SELECT public_id::text FROM products WHERE id = p_related_id)
                    WHEN 'list' THEN (SELECT public_id::text FROM lists WHERE id = p_related_id)
                    WHEN 'giveaway' THEN (SELECT public_id::text FROM giveaways WHERE id = p_related_id)
                    WHEN 'deal' THEN (SELECT public_id::text FROM deals WHERE id = p_related_id)
                    WHEN 'location' THEN (SELECT public_id::text FROM locations WHERE id = p_related_id)
                    WHEN 'profile' THEN (SELECT public_id::text FROM profiles WHERE id = p_related_id)
                    ELSE p_related_id::text
                END
            );
        END IF;
        
        -- Replace any extra data placeholders
        IF p_extra_data IS NOT NULL AND p_extra_data != '{}' THEN
            FOR v_key IN SELECT jsonb_object_keys(p_extra_data) LOOP
                v_title := replace(v_title, '{' || v_key || '}', p_extra_data->>v_key);
                v_body := replace(v_body, '{' || v_key || '}', p_extra_data->>v_key);
                v_action_url := replace(v_action_url, '{' || v_key || '}', p_extra_data->>v_key);
            END LOOP;
        END IF;
        
        -- Determine channels based on preferences
        v_channels := CASE v_type.category
            WHEN 'social' THEN coalesce(v_prefs.social_channels, v_type.default_channels)
            WHEN 'activity' THEN coalesce(v_prefs.activity_channels, v_type.default_channels)
            WHEN 'promotions' THEN coalesce(v_prefs.promotions_channels, v_type.default_channels)
            WHEN 'system' THEN coalesce(v_prefs.system_channels, v_type.default_channels)
            ELSE v_type.default_channels
        END;
        
        -- Insert notification
        INSERT INTO public.notifications (
            profile_id, type_id, title, body, action_url, actor_id,
            related_type, related_id, data, group_key, aggregate_id, priority,
            post_id, product_id, giveaway_id, deal_id, list_id,
            expires_at
        ) VALUES (
            p_recipient_id, v_type.id, v_title, v_body, v_action_url, p_actor_id,
            p_related_type, p_related_id, p_extra_data, 
            v_aggregate_key, v_aggregate_id, v_type.priority,
            CASE WHEN p_related_type = 'post' THEN p_related_id ELSE NULL END,
            CASE WHEN p_related_type = 'product' THEN p_related_id ELSE NULL END,
            CASE WHEN p_related_type = 'giveaway' THEN p_related_id ELSE NULL END,
            CASE WHEN p_related_type = 'deal' THEN p_related_id ELSE NULL END,
            CASE WHEN p_related_type = 'list' THEN p_related_id ELSE NULL END,
            CASE WHEN v_type.auto_expire_after IS NOT NULL 
                 THEN now() + v_type.auto_expire_after 
                 ELSE NULL END
        ) RETURNING id INTO v_notification_id;
        
        -- Update aggregate with representative notification
        IF v_aggregate_id IS NOT NULL THEN
            UPDATE public.notification_aggregates
            SET notification_id = coalesce(notification_id, v_notification_id)
            WHERE id = v_aggregate_id;
        END IF;
        
        -- Queue push notification if channel is enabled
        IF 'push' = ANY(v_channels) THEN
            INSERT INTO public.push_queue (notification_id, push_token_id, payload, priority)
            SELECT 
                v_notification_id,
                pt.id,
                jsonb_build_object(
                    'title', v_title,
                    'body', v_body,
                    'sound', coalesce(v_type.sound_name, 'default'),
                    'badge', v_type.badge_increment,
                    'data', jsonb_build_object(
                        'notification_id', v_notification_id,
                        'action_url', v_action_url,
                        'type', p_type_code,
                        'related_type', p_related_type,
                        'related_id', p_related_id
                    ) || coalesce(p_extra_data, '{}')
                ),
                v_type.priority
            FROM public.push_tokens pt
            WHERE pt.profile_id = p_recipient_id
              AND pt.is_active = true;
        END IF;
    ELSE
        -- Just update the aggregate notification text if aggregating
        IF v_aggregate_id IS NOT NULL AND v_existing_aggregate.notification_id IS NOT NULL THEN
            UPDATE public.notifications
            SET 
                collapsed_count = v_existing_aggregate.count,
                is_aggregated = true,
                title = CASE 
                    WHEN v_existing_aggregate.count = 2 
                    THEN (SELECT coalesce(display_name, username, 'Someone') FROM public.profiles WHERE id = v_existing_aggregate.actor_ids[1])
                         || ' and 1 other'
                    ELSE (SELECT coalesce(display_name, username, 'Someone') FROM public.profiles WHERE id = v_existing_aggregate.actor_ids[1])
                         || ' and ' || (v_existing_aggregate.count - 1)::text || ' others'
                END || ' ' || split_part(title, ' ', 2), -- Append rest of original title
                updated_at = now()
            WHERE id = v_existing_aggregate.notification_id;
            
            v_notification_id := v_existing_aggregate.notification_id;
        END IF;
    END IF;
    
    RETURN v_notification_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.schedule_notification(p_recipient_id integer, p_type_code text, p_scheduled_for timestamp with time zone, p_actor_id integer DEFAULT NULL::integer, p_related_type text DEFAULT NULL::text, p_related_id integer DEFAULT NULL::integer, p_extra_data jsonb DEFAULT '{}'::jsonb, p_idempotency_key text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_scheduled_id integer;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    -- Check for existing scheduled notification with same idempotency key
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_scheduled_id
        FROM public.scheduled_notifications
        WHERE idempotency_key = p_idempotency_key;
        
        IF FOUND THEN
            RETURN v_scheduled_id;
        END IF;
    END IF;
    
    INSERT INTO public.scheduled_notifications (
        profile_id, type_code, scheduled_for, actor_id,
        related_type, related_id, extra_data, idempotency_key
    ) VALUES (
        p_recipient_id, p_type_code, p_scheduled_for, p_actor_id,
        p_related_type, p_related_id, p_extra_data, p_idempotency_key
    ) RETURNING id INTO v_scheduled_id;
    
    RETURN v_scheduled_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.schedule_giveaway_notifications(p_giveaway_id integer, p_end_time timestamp with time zone, p_entrant_profile_ids integer[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_giveaway public.giveaways%ROWTYPE;
    v_profile_id integer;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_giveaway FROM public.giveaways WHERE id = p_giveaway_id;
    
    FOREACH v_profile_id IN ARRAY p_entrant_profile_ids
    LOOP
        -- 3 day reminder
        IF p_end_time - interval '3 days' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'giveaway_drawing_3days',
                p_end_time - interval '3 days',
                NULL,
                'giveaway',
                p_giveaway_id,
                jsonb_build_object('giveaway_name', v_giveaway.name),
                'giveaway_3day_' || p_giveaway_id::text || '_' || v_profile_id::text
            );
        END IF;
        
        -- 1 day reminder
        IF p_end_time - interval '1 day' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'giveaway_drawing_1day',
                p_end_time - interval '1 day',
                NULL,
                'giveaway',
                p_giveaway_id,
                jsonb_build_object('giveaway_name', v_giveaway.name),
                'giveaway_1day_' || p_giveaway_id::text || '_' || v_profile_id::text
            );
        END IF;
        
        -- 1 hour reminder
        IF p_end_time - interval '1 hour' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'giveaway_drawing_1hour',
                p_end_time - interval '1 hour',
                NULL,
                'giveaway',
                p_giveaway_id,
                jsonb_build_object('giveaway_name', v_giveaway.name),
                'giveaway_1hour_' || p_giveaway_id::text || '_' || v_profile_id::text
            );
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.schedule_product_drop_notifications(p_product_id integer, p_release_date timestamp with time zone, p_follower_profile_ids integer[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_product public.products%ROWTYPE;
    v_profile_id integer;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_product FROM public.products WHERE id = p_product_id;
    
    FOREACH v_profile_id IN ARRAY p_follower_profile_ids
    LOOP
        -- 7 day reminder
        IF p_release_date - interval '7 days' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'product_dropping_7days',
                p_release_date - interval '7 days',
                NULL,
                'product',
                p_product_id,
                jsonb_build_object('product_name', v_product.name),
                'product_7day_' || p_product_id::text || '_' || v_profile_id::text
            );
        END IF;
        
        -- 1 day reminder
        IF p_release_date - interval '1 day' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'product_dropping_1day',
                p_release_date - interval '1 day',
                NULL,
                'product',
                p_product_id,
                jsonb_build_object('product_name', v_product.name),
                'product_1day_' || p_product_id::text || '_' || v_profile_id::text
            );
        END IF;
        
        -- Drop notification
        PERFORM public.schedule_notification(
            v_profile_id,
            'product_dropped',
            p_release_date,
            NULL,
            'product',
            p_product_id,
            jsonb_build_object('product_name', v_product.name),
            'product_dropped_' || p_product_id::text || '_' || v_profile_id::text
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.schedule_giveaway_pick(p_giveaway_id integer, p_end_time timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_jobname text := 'pick-giveaway-' || p_giveaway_id;
  v_cron_expr text;
  v_command text;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

  -- Unschedule any existing job for this giveaway (idempotent — silent if none)
  BEGIN
    PERFORM cron.unschedule(v_jobname);
  EXCEPTION WHEN OTHERS THEN
    NULL; -- no existing job, that's fine
  END;

  -- Don't schedule if end_time is in the past (we'll catch these with a manual sweep below)
  IF p_end_time <= now() THEN
    RETURN;
  END IF;

  -- Build cron expression: minute hour day month dow (UTC)
  -- e.g., end_time '2026-06-08 14:32:00+00' → '32 14 8 6 *'
  v_cron_expr := format('%s %s %s %s *',
    EXTRACT(MINUTE FROM p_end_time AT TIME ZONE 'UTC')::int,
    EXTRACT(HOUR FROM p_end_time AT TIME ZONE 'UTC')::int,
    EXTRACT(DAY FROM p_end_time AT TIME ZONE 'UTC')::int,
    EXTRACT(MONTH FROM p_end_time AT TIME ZONE 'UTC')::int
  );

  -- Command: call picker, then unschedule self
  v_command := format(
    'SELECT auto_pick_giveaway_winner(%s); SELECT cron.unschedule(%L);',
    p_giveaway_id, v_jobname
  );

  PERFORM cron.schedule(v_jobname, v_cron_expr, v_command);
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_all_profile_stats()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    updated_rows integer := 0;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    WITH
    follower_counts AS (
        SELECT followee_id AS profile_id, COUNT(*)::int AS cnt
        FROM public.relationships
        GROUP BY followee_id
    ),
    following_counts AS (
        SELECT follower_id AS profile_id, COUNT(*)::int AS cnt
        FROM public.relationships
        GROUP BY follower_id
    ),
    post_counts AS (
        SELECT profile_id, COUNT(*)::int AS cnt
        FROM public.posts
        GROUP BY profile_id
    ),
    like_counts AS (
        SELECT profile_id, COUNT(*)::int AS cnt
        FROM public.likes
        GROUP BY profile_id
    ),
    stash_counts AS (
        SELECT profile_id, COUNT(*)::int AS cnt
        FROM public.stash
        GROUP BY profile_id
    ),
    restash_counts AS (
        SELECT restash_id AS profile_id, COUNT(*)::int AS cnt
        FROM public.stash
        WHERE restash_id IS NOT NULL
        GROUP BY restash_id
    ),
    product_counts AS (
        SELECT brand_id AS profile_id, COUNT(DISTINCT product_id)::int AS cnt
        FROM public.product_brands
        GROUP BY brand_id
    ),
    location_counts AS (
        SELECT brand_id AS profile_id, COUNT(*)::int AS cnt
        FROM public.locations
        GROUP BY brand_id
    ),
    computed AS (
        SELECT
            p.id,
            COALESCE(fc.cnt, 0) AS follower_count,
            COALESCE(fgc.cnt, 0) AS following_count,
            COALESCE(pc.cnt, 0) AS post_count,
            COALESCE(lc.cnt, 0) AS like_count,
            COALESCE(sc.cnt, 0) AS stash_count,
            COALESCE(rsc.cnt, 0) AS restash_count,
            COALESCE(prc.cnt, 0) AS product_count,
            COALESCE(loc.cnt, 0) AS location_count
        FROM public.profiles p
        LEFT JOIN follower_counts fc ON fc.profile_id = p.id
        LEFT JOIN following_counts fgc ON fgc.profile_id = p.id
        LEFT JOIN post_counts pc ON pc.profile_id = p.id
        LEFT JOIN like_counts lc ON lc.profile_id = p.id
        LEFT JOIN stash_counts sc ON sc.profile_id = p.id
        LEFT JOIN restash_counts rsc ON rsc.profile_id = p.id
        LEFT JOIN product_counts prc ON prc.profile_id = p.id
        LEFT JOIN location_counts loc ON loc.profile_id = p.id
    )
    UPDATE public.profiles p
    SET
        follower_count = c.follower_count,
        following_count = c.following_count,
        post_count = c.post_count,
        like_count = c.like_count,
        stash_count = c.stash_count,
        restash_count = c.restash_count,
        product_count = c.product_count,
        location_count = c.location_count
    FROM computed c
    WHERE p.id = c.id;

    GET DIAGNOSTICS updated_rows = ROW_COUNT;
    RETURN updated_rows;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_profile_stats(target_public_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    target_id INTEGER;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    SELECT id INTO target_id
    FROM public.profiles
    WHERE public_id = target_public_id;

    IF target_id IS NULL THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    UPDATE public.profiles
    SET
        follower_count = (SELECT COUNT(*) FROM public.relationships WHERE followee_id = target_id),
        following_count = (SELECT COUNT(*) FROM public.relationships WHERE follower_id = target_id),
        post_count = (SELECT COUNT(*) FROM public.posts WHERE profile_id = target_id),
        like_count = (SELECT COUNT(*) FROM public.likes WHERE profile_id = target_id),
        stash_count = (SELECT COUNT(*) FROM public.stash WHERE profile_id = target_id),
        restash_count = (SELECT COUNT(*) FROM public.stash WHERE restash_id = target_id),
        product_count = (SELECT COUNT(DISTINCT product_id) FROM public.product_brands WHERE brand_id = target_id),
        location_count = (SELECT COUNT(*) FROM public.locations WHERE brand_id = target_id)
    WHERE id = target_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_all_denormalized_counters()
 RETURNS TABLE(counter text, rows_repaired integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    n integer;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    -- posts.like_count <- likes.post_id
    UPDATE public.posts p
    SET like_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(l.cnt, 0)::int AS fresh
        FROM public.posts p2
        LEFT JOIN (
            SELECT post_id, COUNT(*)::int AS cnt FROM public.likes GROUP BY post_id
        ) l ON l.post_id = p2.id
    ) c
    WHERE p.id = c.id AND p.like_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'posts.like_count'; rows_repaired := n; RETURN NEXT;

    -- lists.product_count <- lists_products.list_id
    UPDATE public.lists l
    SET product_count = c.fresh
    FROM (
        SELECT l2.id, COALESCE(lp.cnt, 0)::int AS fresh
        FROM public.lists l2
        LEFT JOIN (
            SELECT list_id, COUNT(*)::int AS cnt FROM public.lists_products GROUP BY list_id
        ) lp ON lp.list_id = l2.id
    ) c
    WHERE l.id = c.id AND l.product_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'lists.product_count'; rows_repaired := n; RETURN NEXT;

    -- lists.subscription_count <- subscriptions_lists.list_id
    UPDATE public.lists l
    SET subscription_count = c.fresh
    FROM (
        SELECT l2.id, COALESCE(sl.cnt, 0)::int AS fresh
        FROM public.lists l2
        LEFT JOIN (
            SELECT list_id, COUNT(*)::int AS cnt FROM public.subscriptions_lists GROUP BY list_id
        ) sl ON sl.list_id = l2.id
    ) c
    WHERE l.id = c.id AND l.subscription_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'lists.subscription_count'; rows_repaired := n; RETURN NEXT;

    -- products.stash_count <- stash.product_id
    UPDATE public.products p
    SET stash_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(s.cnt, 0)::int AS fresh
        FROM public.products p2
        LEFT JOIN (
            SELECT product_id, COUNT(*)::int AS cnt FROM public.stash GROUP BY product_id
        ) s ON s.product_id = p2.id
    ) c
    WHERE p.id = c.id AND p.stash_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'products.stash_count'; rows_repaired := n; RETURN NEXT;

    -- products.post_count <- posts_products.product_id
    UPDATE public.products p
    SET post_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(pp.cnt, 0)::int AS fresh
        FROM public.products p2
        LEFT JOIN (
            SELECT product_id, COUNT(*)::int AS cnt FROM public.posts_products GROUP BY product_id
        ) pp ON pp.product_id = p2.id
    ) c
    WHERE p.id = c.id AND p.post_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'products.post_count'; rows_repaired := n; RETURN NEXT;

    -- products.list_count <- lists_products.product_id
    UPDATE public.products p
    SET list_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(lp.cnt, 0)::int AS fresh
        FROM public.products p2
        LEFT JOIN (
            SELECT product_id, COUNT(*)::int AS cnt FROM public.lists_products GROUP BY product_id
        ) lp ON lp.product_id = p2.id
    ) c
    WHERE p.id = c.id AND p.list_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'products.list_count'; rows_repaired := n; RETURN NEXT;

    -- products.brand_count <- product_brands.product_id
    UPDATE public.products p
    SET brand_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(pb.cnt, 0)::int AS fresh
        FROM public.products p2
        LEFT JOIN (
            SELECT product_id, COUNT(*)::int AS cnt FROM public.product_brands GROUP BY product_id
        ) pb ON pb.product_id = p2.id
    ) c
    WHERE p.id = c.id AND p.brand_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'products.brand_count'; rows_repaired := n; RETURN NEXT;

    -- giveaways.entry_count <- giveaway_entries.giveaway_id
    UPDATE public.giveaways g
    SET entry_count = c.fresh
    FROM (
        SELECT g2.id, COALESCE(ge.cnt, 0)::int AS fresh
        FROM public.giveaways g2
        LEFT JOIN (
            SELECT giveaway_id, COUNT(*)::int AS cnt FROM public.giveaway_entries GROUP BY giveaway_id
        ) ge ON ge.giveaway_id = g2.id
    ) c
    WHERE g.id = c.id AND g.entry_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'giveaways.entry_count'; rows_repaired := n; RETURN NEXT;

    -- deals.claim_count <- deal_claims.deal_id
    -- deal_claims is the relation the trigger fires on. See Part 3 for the
    -- second, unwired claim table.
    UPDATE public.deals d
    SET claim_count = c.fresh
    FROM (
        SELECT d2.id, COALESCE(dc.cnt, 0)::int AS fresh
        FROM public.deals d2
        LEFT JOIN (
            SELECT deal_id, COUNT(*)::int AS cnt FROM public.deal_claims GROUP BY deal_id
        ) dc ON dc.deal_id = d2.id
    ) c
    WHERE d.id = c.id AND d.claim_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'deals.claim_count'; rows_repaired := n; RETURN NEXT;

    -- The eight profiles.* counters are deliberately not touched here. All eight
    -- measured clean, so there is nothing to repair, and delegating to
    -- recalculate_all_profile_stats() would mean depending on a return value
    -- this migration has not verified -- it reports rows visited, not rows
    -- changed, which would not mean the same thing as the counts above. Run it
    -- directly if those counters ever drift.

    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_giveaway_winner_counts()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    n integer;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    UPDATE public.giveaways g
    SET winner_count = c.fresh
    FROM (
        SELECT g2.id, COALESCE(w.cnt, 0)::int AS fresh
        FROM public.giveaways g2
        LEFT JOIN (
            SELECT giveaway_id, COUNT(*)::int AS cnt
            FROM public.giveaway_entries
            WHERE won
            GROUP BY giveaway_id
        ) w ON w.giveaway_id = g2.id
    ) c
    WHERE g.id = c.id AND g.winner_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END;
$$;
