-- SECURITY: remove client access to the SECURITY DEFINER RPC surface, and fix the
-- three defects found while auditing it.
--
-- The public schema is exposed through the Data API, so every function with an
-- EXECUTE grant to anon is reachable at /rest/v1/rpc/<name> with nothing but the
-- public anon key. 82 SECURITY DEFINER functions were in that state; 25 of them
-- let an unauthenticated caller do something they should not (approve staff,
-- send arbitrary notifications, deface images, force giveaway draws, read other
-- users' search history, trigger full-table rewrites).
--
-- A grep of hybrid-raskin across main, fix-env-validation and upstream/main
-- found exactly ONE of the 82 called by the client: auto_pick_giveaway_winner,
-- from the admin dashboard's "Pick Winner" button. Everything else is an unused
-- parallel write API. That is why this revokes broadly and keeps one grant.
--
-- IMPORTANT -- why this revokes from PUBLIC and not just anon/authenticated:
-- 81 of the 82 carry an explicit EXECUTE grant to PUBLIC
--   proacl = {=X/postgres, postgres=X/postgres, anon=X/postgres, ...}
--            ^^^^^^^^^^^^ empty grantee = PUBLIC
-- Revoking from anon and authenticated alone would leave that entry standing and
-- change nothing observable -- has_function_privilege('anon', ...) would still
-- return true. (find_available_username is the lone exception: PUBLIC was already
-- revoked there, anon/authenticated were not.)
-- postgres and service_role are re-granted explicitly afterwards so that revoking
-- PUBLIC cannot take their access away.


-- =====================================
-- PART 1: auto_pick_giveaway_winner -- add the authorization check
-- =====================================
-- The only function the client calls, so it keeps a grant -- but it currently
-- accepts a caller-controlled giveaway id with no authorization whatsoever.
--
-- The check is is_super_admin() alone. A profile_admins branch was considered and
-- deliberately left out: giveaways.created_by_profile_id is populated on 4 of 103
-- rows, so that branch would cover almost nothing until it is backfilled, which is
-- a separate decision.
--
-- Requester resolution and the NULL guard come FIRST, in the order
-- mark_all_notifications_as_read_for_profile uses, so an anonymous caller fails
-- closed on an IS NULL test rather than falling through a NULL comparison the way
-- get_managed_profiles did.
--
-- is_super_admin() is itself revoked in Part 4. That is fine: this function is
-- SECURITY DEFINER owned by postgres, so the nested EXECUTE check is made against
-- postgres, not against the caller.
--
-- search_path is pinned. Without it a caller-supplied search_path could shadow
-- profiles or super_admins and defeat the check that is being added here.
CREATE OR REPLACE FUNCTION public.auto_pick_giveaway_winner(p_giveaway_id integer)
RETURNS TABLE(winners_picked integer, total_entries integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_requester_profile_id integer;
  v_total_prizes integer;
  v_entries_count integer;
  v_picked integer := 0;
  v_giveaway_name text;
  v_won_type_id integer;
  w record;
BEGIN
  -- Authorization, before anything else touches a row.
  SELECT p.id
  INTO v_requester_profile_id
  FROM public.profiles p
  WHERE p.auth_id = auth.uid();

  IF v_requester_profile_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  -- Optimistic lock: only proceed if winner hasn't already been selected
  SELECT COALESCE(total_prizes, 1), name INTO v_total_prizes, v_giveaway_name
  FROM giveaways
  WHERE id = p_giveaway_id AND selected_winner = false
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 0, 0;
    RETURN;
  END IF;

  -- Count available entries
  SELECT COUNT(*) INTO v_entries_count
  FROM giveaway_entries
  WHERE giveaway_id = p_giveaway_id AND won = false;

  IF v_entries_count = 0 THEN
    UPDATE giveaways SET selected_winner = true, winner_count = 0
    WHERE id = p_giveaway_id;
    RETURN QUERY SELECT 0, 0;
    RETURN;
  END IF;

  v_total_prizes := LEAST(v_total_prizes, v_entries_count);

  -- Pick winners
  WITH picked AS (
    SELECT id FROM giveaway_entries
    WHERE giveaway_id = p_giveaway_id AND won = false
    ORDER BY random()
    LIMIT v_total_prizes
  )
  UPDATE giveaway_entries SET won = true WHERE id IN (SELECT id FROM picked);

  GET DIAGNOSTICS v_picked = ROW_COUNT;

  UPDATE giveaways SET selected_winner = true, winner_count = v_picked
  WHERE id = p_giveaway_id;

  -- Send "You won!" notifications to each winner
  SELECT id INTO v_won_type_id FROM notification_types WHERE code = 'giveaway_won' LIMIT 1;
  IF v_won_type_id IS NOT NULL THEN
    FOR w IN
      SELECT profile_id FROM giveaway_entries
      WHERE giveaway_id = p_giveaway_id AND won = true
    LOOP
      INSERT INTO notifications (type_id, related_type, related_id, title, body, profile_id)
      VALUES (
        v_won_type_id, 'giveaway', p_giveaway_id,
        '🎉 You won!',
        'You won ' || v_giveaway_name || '! Check the giveaway page for details.',
        w.profile_id
      );
    END LOOP;
  END IF;

  RETURN QUERY SELECT v_picked, v_entries_count;
END;
$$;


-- =====================================
-- PART 2: get_managed_profiles -- close the NULL-comparison bypass
-- =====================================
-- The old guard was:
--     IF v_target_auth_id != auth.uid() AND NOT public.is_super_admin() THEN
--         RAISE EXCEPTION 'Access denied';
--     END IF;
-- For an anonymous caller auth.uid() is NULL, so `<uuid> != NULL` is NULL, and
-- `NULL AND TRUE` is NULL -- the IF takes the else branch and the exception never
-- fires. Anyone could read any admin's managed-brand list by passing that admin's
-- auth_id, which is itself readable from the open SELECT policy on profiles.
--
-- Rewritten in the same order as mark_all_notifications_as_read_for_profile:
-- resolve the requester, bail on NULL, then compare. IS DISTINCT FROM is used for
-- the comparison so it stays NULL-safe even if target resolution returns NULL.
--
-- This function is revoked in Part 4 as well. It is fixed anyway so the bug is not
-- lying in wait if the grant is ever restored.
CREATE OR REPLACE FUNCTION public.get_managed_profiles(p_admin_id text DEFAULT NULL::text)
RETURNS TABLE(public_id uuid)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_requester_auth_id uuid;
    v_target_auth_id uuid;
    v_admin_profile_id integer;
BEGIN
    -- 1. Resolve the requester first, and fail closed if there isn't one.
    v_requester_auth_id := auth.uid();

    IF v_requester_auth_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- 2. Determine the target Auth UUID
    IF p_admin_id IS NULL THEN
        v_target_auth_id := v_requester_auth_id;
    ELSIF p_admin_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_target_auth_id := p_admin_id::uuid;
    ELSE
        -- If passed as integer ID, resolve to Auth UUID first to check permissions
        BEGIN
            SELECT auth_id INTO v_target_auth_id
            FROM public.profiles
            WHERE id = p_admin_id::integer;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid admin ID format';
        END;
    END IF;

    -- 3. Security check. Both sides are now known non-NULL on the requester side,
    --    and IS DISTINCT FROM keeps this sound if the target did not resolve.
    IF v_target_auth_id IS DISTINCT FROM v_requester_auth_id
       AND NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    -- 4. Resolve the Profile ID for this Auth ID
    SELECT id INTO v_admin_profile_id
    FROM public.profiles
    WHERE auth_id = v_target_auth_id;

    IF v_admin_profile_id IS NULL THEN
        RETURN;
    END IF;

    -- 5. Return the public_ids of managed profiles
    RETURN QUERY
    SELECT p.public_id
    FROM public.profile_admins pa
    JOIN public.profiles p ON pa.managed_profile_id = p.id
    WHERE pa.admin_profile_id = v_admin_profile_id;
END;
$$;


-- =====================================
-- PART 3: stop the double-counting
-- =====================================
-- Seven functions updated a denormalized counter by hand on a table that already
-- has a trigger maintaining that same counter, so each successful call moved the
-- counter by 2. Three of them sat behind ON CONFLICT DO NOTHING, so a duplicate
-- call moved the counter by 1 with no row inserted at all.
--
-- The triggers are the source of truth, so the manual updates are removed outright
-- rather than made conditional. Verified against the live trigger list before
-- removing each one -- every counter below is maintained on both INSERT and DELETE:
--
--   relationships       update_follower_count_on_profiles -> fn_change_follower_count
--                       (maintains BOTH follower_count and following_count)
--   lists_products      update_product_count_on_list      -> fn_change_lists_product_count
--   subscriptions_lists subscription_count_trigger        -> update_subscription_count
--   stash               update_stash_count_on_profiles    -> fn_change_profiles_stash_count
--                       trg_update_product_stash_count    -> update_product_stash_count
--
-- No counter needed the fallback of keeping a floored manual update; all five are
-- genuinely trigger-maintained.
--
-- This matters because 20260918000001 just repaired these counters and floored the
-- trigger decrements. With the floors in place, a double decrement no longer shows
-- up as a negative value -- it silently clamps at zero. The drift would have become
-- invisible rather than absent.

CREATE OR REPLACE FUNCTION public.follow_profile(target_public_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_follower_id integer;
    v_followee_id integer;
BEGIN
    -- Get IDs
    SELECT id INTO v_follower_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_followee_id FROM public.profiles WHERE public_id = target_public_id;

    IF v_follower_id IS NULL THEN RAISE EXCEPTION 'Current profile not found'; END IF;
    IF v_followee_id IS NULL THEN RAISE EXCEPTION 'Target profile not found'; END IF;
    IF v_follower_id = v_followee_id THEN RAISE EXCEPTION 'Cannot follow yourself'; END IF;

    -- follower_count / following_count are maintained by fn_change_follower_count
    -- on relationships. Do not touch them here.
    INSERT INTO public.relationships (follower_id, followee_id)
    VALUES (v_follower_id, v_followee_id)
    ON CONFLICT (follower_id, followee_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unfollow_profile(target_public_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_follower_id integer;
    v_followee_id integer;
BEGIN
    SELECT id INTO v_follower_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_followee_id FROM public.profiles WHERE public_id = target_public_id;

    IF v_follower_id IS NULL OR v_followee_id IS NULL THEN RETURN; END IF;

    -- Counters are maintained by fn_change_follower_count on relationships.
    DELETE FROM public.relationships
    WHERE follower_id = v_follower_id AND followee_id = v_followee_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_to_list(target_list_id uuid, target_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_list_id integer;
    v_product_id integer;
BEGIN
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = target_list_id;
    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;

    IF v_list_id IS NULL OR v_product_id IS NULL THEN RETURN; END IF;

    -- Check ownership of list
    IF NOT EXISTS (SELECT 1 FROM public.lists WHERE id = v_list_id AND profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid())) THEN
        RAISE EXCEPTION 'You do not own this list';
    END IF;

    -- lists.product_count is maintained by fn_change_lists_product_count on
    -- lists_products. The old comment here guessed no trigger existed; there is one.
    INSERT INTO public.lists_products (list_id, product_id)
    VALUES (v_list_id, v_product_id)
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_from_list(target_list_id uuid, target_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_list_id integer;
    v_product_id integer;
BEGIN
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = target_list_id;
    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;

    IF v_list_id IS NULL OR v_product_id IS NULL THEN RETURN; END IF;

    -- Check ownership
    IF NOT EXISTS (SELECT 1 FROM public.lists WHERE id = v_list_id AND profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid())) THEN
        RAISE EXCEPTION 'You do not own this list';
    END IF;

    -- lists.product_count is maintained by fn_change_lists_product_count.
    DELETE FROM public.lists_products
    WHERE list_id = v_list_id AND product_id = v_product_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.subscribe_list(target_list_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_list_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = target_list_id;

    IF v_profile_id IS NULL OR v_list_id IS NULL THEN RETURN; END IF;

    -- lists.subscription_count is maintained by update_subscription_count on
    -- subscriptions_lists.
    INSERT INTO public.subscriptions_lists (profile_id, list_id)
    VALUES (v_profile_id, v_list_id)
    ON CONFLICT (profile_id, list_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unsubscribe_list(target_list_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_list_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = target_list_id;

    IF v_profile_id IS NULL OR v_list_id IS NULL THEN RETURN; END IF;

    -- lists.subscription_count is maintained by update_subscription_count.
    DELETE FROM public.subscriptions_lists
    WHERE profile_id = v_profile_id AND list_id = v_list_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.unstash_product(target_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_product_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;

    IF v_profile_id IS NULL OR v_product_id IS NULL THEN RETURN; END IF;

    -- profiles.stash_count is maintained by fn_change_profiles_stash_count and
    -- products.stash_count by update_product_stash_count, both on stash.
    DELETE FROM public.stash
    WHERE profile_id = v_profile_id AND product_id = v_product_id;
END;
$$;

-- stash_product is deliberately NOT changed here.
--
-- Its manual counter updates sit behind `IF NOT EXISTS (...)` which is always false
-- immediately after its own INSERT, so they never run and it does not double-count.
-- It has a different defect: public.stash has no unique constraint on
-- (profile_id, product_id) -- only stash_pkey on id -- so its ON CONFLICT DO NOTHING
-- can never fire and every repeat call inserts another row. The counters stay
-- consistent with the rows, because the triggers count rows; the rows themselves are
-- the problem.
--
-- Adding the constraint is the real fix and is NOT done here because it is a
-- different kind of change -- a table-level constraint with a lock, on a table
-- whose duplicates would have to be reconciled first. It would involve:
--   1. de-duplicating (0 duplicate (profile_id, product_id) pairs exist today, so
--      this is currently a no-op -- worth re-checking at apply time)
--   2. ALTER TABLE public.stash ADD CONSTRAINT stash_unique UNIQUE (profile_id, product_id)
--   3. then simplifying stash_product down to a single INSERT ... ON CONFLICT DO NOTHING,
--      dropping the redundant IF NOT EXISTS block
-- Track separately.


-- =====================================
-- PART 4: revoke the RPC surface
-- =====================================
-- Enumerated from the live catalog rather than a fixed list, so this covers every
-- SECURITY DEFINER function in public including the 18 trigger-returning ones
-- (which need no EXECUTE grant at all -- triggers fire as the table owner).
--
-- The eight SECURITY INVOKER get_profile_* functions are included deliberately.
-- They call resolve_profile_id, which is in the revoked set, and a SECURITY INVOKER
-- function runs as its caller -- so leaving them granted would make them fail at
-- runtime instead of failing at the door. They must move together.
--
-- auto_pick_giveaway_winner is excluded here and granted in Part 5.
DO $$
DECLARE
    r record;
    n integer := 0;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public'
          AND p.prokind IN ('f', 'p')
          AND (
                p.prosecdef
             OR (NOT p.prosecdef AND p.proname LIKE 'get\_profile\_%')
          )
          AND p.proname <> 'auto_pick_giveaway_winner'
    LOOP
        EXECUTE format('REVOKE ALL PRIVILEGES ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres, service_role', r.sig);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'revoked client EXECUTE on % function(s)', n;
END
$$;


-- =====================================
-- PART 5: the one grant that stays
-- =====================================
-- The admin dashboard's "Pick Winner" button, lib/giveaways.js -> selectGiveawayWinner.
-- authenticated only, and the body now requires super-admin on top of that.
REVOKE ALL PRIVILEGES ON FUNCTION public.auto_pick_giveaway_winner(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auto_pick_giveaway_winner(integer) TO authenticated, postgres, service_role;
