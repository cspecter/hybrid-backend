-- Behavioural check for 20261109000001_private_lists_are_private.sql.
--
-- Run this in the Supabase SQL editor AFTER applying the migration. It creates a
-- private list with one product, reads it as anon and as two different
-- authenticated users, and ROLLS BACK -- nothing it writes survives. Safe to run
-- against production.
--
-- Why it has to fake a row: all 1,189 lists currently hold is_private = false,
-- so nothing in the table distinguishes a working policy from the old
-- USING (true). A check that passes against today's data proves nothing.
--
-- Two things this script is careful about, both of which silently fake a pass:
--   * The SQL editor runs as a superuser, and RLS does not apply to superusers.
--     Without SET LOCAL ROLE every count comes back identical and all three
--     cases look correct.
--   * The probe's id is carried in a temp table that is granted to anon and
--     authenticated, rather than looked up by name. Looking it up by name would
--     route the lists_products check through the lists policy, so "contents
--     hidden" and "list hidden" would be indistinguishable.
--
-- No psql meta-commands (\gset, :vars) -- the dashboard editor does not support
-- them.

BEGIN;

CREATE TEMP TABLE _probe AS
WITH src AS (
    SELECT id AS owner_id, auth_id AS owner_auth
      FROM public.profiles WHERE auth_id IS NOT NULL ORDER BY id LIMIT 1
), ins AS (
    INSERT INTO public.lists (name, description, profile_id, is_private, product_count)
    SELECT 'RLS probe (rolled back)', '', owner_id, true, 0 FROM src
    RETURNING id
)
SELECT ins.id AS list_id,
       src.owner_auth,
       (SELECT auth_id FROM public.profiles
         WHERE auth_id IS NOT NULL AND auth_id <> src.owner_auth
         ORDER BY id DESC LIMIT 1)                                     AS other_auth,
       (SELECT count(*) FROM public.lists
         WHERE COALESCE(is_private, false) = false)                    AS public_lists
  FROM ins CROSS JOIN src;

INSERT INTO public.lists_products (list_id, product_id)
SELECT list_id, (SELECT id FROM public.products ORDER BY id LIMIT 1) FROM _probe;

GRANT SELECT ON _probe TO anon, authenticated;

-- 1. anon -- the published key. Must see neither the list nor its contents, and
--    must still see every public list, or a logged-out visitor's app is broken.
SET LOCAL ROLE anon;
SELECT 'anon sees the private list'   AS check,
       (SELECT count(*) FROM public.lists         WHERE id      = (SELECT list_id FROM _probe)) AS got,
       0                                                                                        AS want
UNION ALL SELECT 'anon sees its contents',
       (SELECT count(*) FROM public.lists_products WHERE list_id = (SELECT list_id FROM _probe)),
       0
UNION ALL SELECT 'anon still sees public lists',
       (SELECT count(*) FROM public.lists WHERE COALESCE(is_private,false) = false),
       (SELECT public_lists FROM _probe);
RESET ROLE;

-- 2. The owner. Must see both.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', (SELECT owner_auth FROM _probe), 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT 'owner sees own private list'  AS check,
       (SELECT count(*) FROM public.lists         WHERE id      = (SELECT list_id FROM _probe)) AS got,
       1                                                                                        AS want
UNION ALL SELECT 'owner sees its contents',
       (SELECT count(*) FROM public.lists_products WHERE list_id = (SELECT list_id FROM _probe)),
       1;
RESET ROLE;

-- 3. A different signed-in user. Must see neither. This is the case the client
--    cannot test and the one that matters: signing up is free.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', (SELECT other_auth FROM _probe), 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT 'other user sees the list'     AS check,
       (SELECT count(*) FROM public.lists         WHERE id      = (SELECT list_id FROM _probe)) AS got,
       0                                                                                        AS want
UNION ALL SELECT 'other user sees contents',
       (SELECT count(*) FROM public.lists_products WHERE list_id = (SELECT list_id FROM _probe)),
       0;
RESET ROLE;

ROLLBACK;
