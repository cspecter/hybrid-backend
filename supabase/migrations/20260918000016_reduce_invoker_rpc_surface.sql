-- Reduce the SECURITY INVOKER RPC surface exposed to anon and authenticated.
--
-- 247 SECURITY INVOKER functions in public were executable by anon. These are a
-- different and much lower risk class than the SECURITY DEFINER set closed in
-- 20260918000003 -- they run as the CALLER, so RLS and table grants still bind them,
-- and none makes an outbound HTTP call any more after 20260918000009. The exposure
-- is attack surface and amplification rather than privilege escalation.
--
-- Revoking all 247 would break the database. The set is split three ways:
--
--   53  extension-owned (cube 40, earthdistance 9, unaccent 4). KEPT. These are
--       installed in public and are used by geo lookups, search and their indexes.
--       Revoking them would break queries, not just RPC.
--
--   64  app functions reachable from a SECURITY INVOKER trigger function that is
--       attached to a live trigger. KEPT. This is the important one: an invoker
--       trigger function runs as whoever fired the trigger, so an ordinary
--       authenticated INSERT needs EXECUTE on everything that trigger calls,
--       transitively. Revoking these would fail writes at runtime rather than at the
--       door -- the same shape as the resolve_profile_id / get_profile_* coupling
--       found earlier. Computed as a transitive closure from the 58 invoker trigger
--       functions on live triggers, over a deliberately over-approximating
--       name-match edge set (it also matches names inside EXECUTE format() strings,
--       so dynamic calls are caught too).
--
--    1  generate_randome_code. KEPT. It is the DEFAULT on locations.code, and a
--       column default is evaluated as the INSERTing role.
--
--  128  everything else. Revoked below (129 overloads: 117 reachable over
--       /rpc/, 12 trigger-returning and never reachable).
--
-- Nothing in hybrid-raskin calls any of the 128 -- the client's only RPC on any
-- branch is auto_pick_giveaway_winner, which is SECURITY DEFINER and unaffected.
--
-- Verified before writing, against the live catalog, that none of the candidates is
-- referenced by a policy, check constraint, index expression, generated column, view,
-- materialized view or cron job. The single column-default hit is the exception
-- listed above.
--
-- Revokes from PUBLIC as well as the two roles: functions carry an EXECUTE grant to
-- PUBLIC by default, so revoking only anon and authenticated would change nothing
-- observable. postgres and service_role are re-granted explicitly. 12 of the 129 are
-- trigger-returning and were never reachable over /rpc/ at all; they are included for
-- hygiene, and trigger privileges are checked at CREATE TRIGGER time rather than when
-- the trigger fires, so their triggers keep working.

DO $$
DECLARE
    r record;
    n integer := 0;
    target text[] := ARRAY[
        '_add_sort_to_products',
        '_clean_up_relationships',
        '_fn_delete_profile',
        '_fn_list_insert_tasks',
        '_products_added_to_list_notification',
        '_ts_giveaways_brand_names',
        '_ts_giveaways_date_created',
        '_ts_giveaways_date_updated',
        '_ts_giveaways_end_time',
        '_ts_giveaways_id',
        '_ts_giveaways_postal_codes',
        '_ts_giveaways_product_categories',
        '_ts_giveaways_product_name',
        '_ts_giveaways_start_time',
        '_ts_lists_display_name',
        '_ts_lists_id',
        '_ts_lists_product_categories',
        '_ts_lists_product_category_ids',
        '_ts_lists_product_ids',
        '_ts_lists_product_names',
        '_ts_lists_profile_id',
        '_ts_lists_username',
        '_ts_locations_brand_name',
        '_ts_locations_city',
        '_ts_locations_date_created',
        '_ts_locations_date_updated',
        '_ts_locations_employees',
        '_ts_locations_id',
        '_ts_locations_latlng',
        '_ts_locations_postal_code',
        '_ts_locations_state',
        '_ts_postal_codes_id',
        '_ts_postal_codes_latlng',
        '_ts_posts_city',
        '_ts_posts_date_created',
        '_ts_posts_date_updated',
        '_ts_posts_display_name',
        '_ts_posts_id',
        '_ts_posts_list_ids',
        '_ts_posts_list_names',
        '_ts_posts_location',
        '_ts_posts_product_categories',
        '_ts_posts_product_category_ids',
        '_ts_posts_product_ids',
        '_ts_posts_product_names',
        '_ts_posts_profile_id',
        '_ts_posts_profile_ids',
        '_ts_posts_profile_names',
        '_ts_posts_profile_usernames',
        '_ts_posts_region',
        '_ts_posts_tags',
        '_ts_posts_username',
        '_ts_product_categories_id',
        '_ts_products_brand',
        '_ts_products_brand_ids',
        '_ts_products_category',
        '_ts_products_date_created',
        '_ts_products_date_updated',
        '_ts_products_features',
        '_ts_products_id',
        '_ts_products_releasedate',
        '_ts_products_sub_product_ids',
        '_ts_products_sub_products',
        '_ts_profiles_date_created',
        '_ts_profiles_date_updated',
        '_ts_profiles_id',
        '_unread_notification_count',
        'count_estimate',
        'create_timestamps_trigger',
        'delete_list',
        'delete_post',
        'flag_post',
        'fn_add_or_change_list_on_profile_name_change',
        'fn_brand_count_on_products',
        'fn_change_following_count',
        'fn_change_post_product_count_on_product',
        'fn_change_product_list_count',
        'fn_change_product_stash_count',
        'fn_delete_post',
        'fn_products_gallery_sort',
        'generate_username',
        'get_admin_giveaways',
        'get_giveaway_messages',
        'get_giveaway_winners',
        'get_list_products',
        'get_location_deals',
        'get_location_lists',
        'get_location_posts',
        'get_locations_nearby',
        'get_new_releases',
        'get_notifications',
        'get_popular_brands',
        'get_post_tag_count',
        'get_post_tag_preview_file_id',
        'get_product_deals',
        'get_product_giveaways',
        'get_product_lists',
        'get_product_posts',
        'get_search_analytics',
        'get_top_budtenders',
        'get_top_creators',
        'get_top_posts',
        'get_user_won_giveaways',
        'is_json',
        'mark_notifications_as_read',
        'merge_profiles',
        'resolve_list_id',
        'resolve_location_id',
        'resolve_product_id',
        'search_locations_by_features',
        'search_universal',
        'send_email_message',
        'send_giveaway_message',
        'slugify_varchar',
        'test_credentials',
        'test_product_brand_names',
        'touch_parent_updated_at',
        'typeahead_giveaways',
        'typeahead_lists',
        'typeahead_locations',
        'typeahead_posts',
        'typeahead_products',
        'typeahead_profiles',
        'typeahead_universal',
        'update_deals_fts_vector',
        'update_null_cached_brand_names',
        'update_products_fts_data',
        'update_products_fts_manual'
    ];
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace ns ON ns.oid = p.pronamespace
        WHERE ns.nspname = 'public'
          AND NOT p.prosecdef
          AND p.proname = ANY(target)
    LOOP
        EXECUTE format('REVOKE ALL PRIVILEGES ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres, service_role', r.sig);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'revoked client EXECUTE on % invoker function(s)', n;
END
$$;
