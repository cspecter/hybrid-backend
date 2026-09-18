-- Remove the dead Typesense / edge-function integration.
--
-- 26 functions in public exist only to POST to a Supabase project that is not this
-- one: axzdfdpwfsynrajqqoae, where this project is ujmisqstpmowanvivtcr. Eight of
-- them embed an Authorization bearer token for that project directly in their
-- function bodies. The other eighteen are trigger-shaped wrappers whose entire body
-- is a PERFORM of one of the eight.
--
-- Nothing reaches any of them. Verified against the live catalog:
--     attached to a trigger                                0
--     referenced by a cron job                             0
--     referenced by a function outside this set            0
--     referenced by a view                                 0
--     referenced by a policy                               0
--     referenced by a check constraint / default / index   0
-- and no reference in hybrid-raskin on main, fix-env-validation or upstream/main.
--
-- None of the eight does any local work -- each is set timeout, POST, return. There
-- is nothing to preserve, unlike fn_update_location_date_on_employee_add in
-- 20260918000008, which had real local behaviour wrapped around its dead call.
--
-- On the two hostnames, which differ and should not be conflated:
--   axzdfdpwfsynrajqqoae.supabase.co            -> NXDOMAIN, does not resolve.
--       Used by the four _edge_* / _select_contest_winners functions.
--   axzdfdpwfsynrajqqoae.functions.supabase.co  -> RESOLVES (shared Cloudflare edge
--       for *.functions.supabase.co). Used by the four _typesense_* functions.
-- So half of these would fail at DNS and half would actually reach Supabase's edge
-- carrying that project's bearer token. No request was made to either host.
--
-- Why this matters beyond dead code: all eight are SECURITY INVOKER and return
-- void, so they were never covered by the SECURITY DEFINER revoke in
-- 20260918000003, and anon still holds EXECUTE on every one. Any caller with the
-- public anon key could invoke them over /rpc/ and make this database open outbound
-- HTTP connections on demand, each with a 20 second CURLOPT_TIMEOUT.
-- _typesense_import() additionally runs `SET statement_timeout TO 600000` without
-- LOCAL, so it would leave a ten minute statement timeout on the pooled connection
-- after it returned.
--
-- The eighteen wrappers are dropped in the same migration rather than left behind.
-- PostgreSQL does not track function-to-function dependencies inside plpgsql bodies,
-- so dropping only the eight would leave eighteen functions silently referencing
-- functions that no longer exist -- landmines for whoever attaches one to a trigger
-- later.
--
-- The token values are not reproduced here. They are in the function bodies in
-- 20241204000009_functions_triggers.sql if they need to be revoked on that project.


-- Wrappers first: trigger-shaped, attached to nothing, each a single PERFORM.
DROP FUNCTION IF EXISTS _delete_categories_from_typesense_trigger();
DROP FUNCTION IF EXISTS _delete_deals_from_typesense_trigger();
DROP FUNCTION IF EXISTS _delete_giveaways_from_typesense_trigger();
DROP FUNCTION IF EXISTS _delete_lists_from_typesense_trigger();
DROP FUNCTION IF EXISTS _delete_locations_from_typesense_trigger();
DROP FUNCTION IF EXISTS _delete_postal_codes_from_typesense_trigger();
DROP FUNCTION IF EXISTS _delete_posts_from_typesense_trigger();
DROP FUNCTION IF EXISTS _delete_products_from_typesense_trigger();
DROP FUNCTION IF EXISTS _delete_profiles_from_typesense_trigger();
DROP FUNCTION IF EXISTS _fn_typesense_deals();
DROP FUNCTION IF EXISTS _fn_typesense_giveaways();
DROP FUNCTION IF EXISTS _fn_typesense_lists();
DROP FUNCTION IF EXISTS _fn_typesense_locations();
DROP FUNCTION IF EXISTS _fn_typesense_postal_codes();
DROP FUNCTION IF EXISTS _fn_typesense_posts();
DROP FUNCTION IF EXISTS _fn_typesense_product_categories();
DROP FUNCTION IF EXISTS _fn_typesense_products();
DROP FUNCTION IF EXISTS _fn_typesense_profiles();

-- The eight that embed the credential and make the HTTP call.
DROP FUNCTION IF EXISTS _edge_employee_upgrade(uuid,text,text);
DROP FUNCTION IF EXISTS _edge_notification_runner();
DROP FUNCTION IF EXISTS _edge_push_notifications_runner();
DROP FUNCTION IF EXISTS _select_contest_winners();
DROP FUNCTION IF EXISTS _typesense_delete(text,text);
DROP FUNCTION IF EXISTS _typesense_import();
DROP FUNCTION IF EXISTS _typesense_import_int(integer,text);
DROP FUNCTION IF EXISTS _typesense_import_uuid(uuid,text);
