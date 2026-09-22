-- Two faults in send_notification()'s aggregation, both of which throw rather than
-- degrade. Because the employee-request notification fires from an AFTER INSERT
-- trigger, a throw takes the whole request INSERT down with it: hit while walking
-- the budtender request flow, where the second request at a store failed with
-- "duplicate key value violates notification_aggregates_profile_id_aggregate_key_key".
--
-- FOUND WHILE TESTING, NOT IN THE BRIEF, FIXED ANYWAY because it blocks the exact
-- path the brief is about. Both faults pre-date this work; the fan-out in
-- 20260922000004 only made them easier to reach by adding recipients.
--
-- Fault 1 — {location_id} was never substituted. The key is built from
-- notification_types.group_key with placeholders replaced, but the replace list
-- covered only {post_id}, {product_id}, {list_id} and {giveaway_id}. Live types
-- 52 location_favorited and 54 employee_request both key on {location_id}, so every
-- store collapsed into one aggregate row per recipient containing the literal text
-- '{location_id}' — a request at store A and one at store B counted as one pile.
--
-- Fault 2 — a stale aggregate was a permanent wall. The lookup is windowed
-- (window_start > now() - aggregation_window); the unique constraint on
-- (profile_id, aggregate_key) is not. Once a row aged out of its window the lookup
-- missed, the INSERT ran, and the constraint rejected it. For type 54 that is four
-- hours, so the first request ever sent to a recipient poisoned every later one.
--
-- This is the function's existing text with exactly those two edits applied — the
-- push_queue fan-out, the aggregate title rewrite and everything else are byte for
-- byte what was there. A rewrite from scratch was tried first and silently dropped
-- the push block; this is generated from the live definition instead.

CREATE OR REPLACE FUNCTION public.send_notification(p_recipient_id integer, p_type_code text, p_actor_id integer DEFAULT NULL::integer, p_related_type text DEFAULT NULL::text, p_related_id integer DEFAULT NULL::integer, p_extra_data jsonb DEFAULT '{}'::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            -- Fault 1: the placeholder three live types actually use.
            v_aggregate_key := replace(v_aggregate_key, '{location_id}', coalesce(p_related_id::text, ''));
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
            )
            -- Fault 2: the lookup above is windowed, this constraint is not, so a
            -- row that merely aged out of its window used to make the INSERT throw.
            -- Restarting the window is what the windowed lookup meant to express.
            ON CONFLICT (profile_id, aggregate_key) DO UPDATE
               SET count           = 1,
                   window_start    = now(),
                   last_updated_at = now(),
                   is_seen         = false,
                   type_code       = excluded.type_code,
                   related_type    = excluded.related_type,
                   related_id      = excluded.related_id,
                   actor_ids       = excluded.actor_ids
            RETURNING id INTO v_aggregate_id;
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
$function$
;

revoke execute on function public.send_notification(integer, text, integer, text, integer, jsonb) from public;
grant execute on function public.send_notification(integer, text, integer, text, integer, jsonb) to authenticated, service_role;
