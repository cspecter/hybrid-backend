-- SECURITY: remove the role_id tautology from the policies it defeats, drop the
-- policies that should never have been client-reachable, and stop new objects in
-- public from being granted to anon by default.
--
-- Background: 20 policies carried `(role_id <= 9 OR role_id >= 3)` -- true for every
-- integer -- inside a scalar subquery over the caller's profile. It appears as a
-- top-level disjunct in all 29 clauses, so each of those policies evaluates true for
-- any authenticated user with a profile row. All 2481 profiles qualify.
--
-- This migration handles the two classes where the answer is unambiguous:
--   Class C: the operation should not be client-reachable at all  -> DROP
--   Class A: other disjuncts already cover every legitimate user  -> remove the
--            tautology disjunct only, leave the rest byte-identical
--
-- Class B is NOT touched here. giveaways INSERT/UPDATE/DELETE and products
-- UPDATE/DELETE need a new ownership predicate written before their tautology can
-- go, because for those the tautology is the only thing making a legitimate
-- operation work. Removing it without a replacement would lock out brands.
--
-- The surviving disjuncts below were not retyped. Each policy's live predicate was
-- read from pg_policies, the tautology's enclosing scalar subquery and its joining
-- OR removed programmatically, and the remainder emitted verbatim.


-- =====================================
-- PART 1: CLASS C -- drop outright
-- =====================================

-- giveaway_entries.won is the prize-award flag and .sent is fulfilment state. Both
-- are server-side concerns: auto_pick_giveaway_winner sets won, and nothing else
-- should. This policy let any authenticated user set won = true on any entry, which
-- is the route by which 37 giveaways ended up with winner_count disagreeing with
-- their won entries. The super-admin ALL policy remains for admin correction.
DROP POLICY IF EXISTS "Enable update for profiles based on role id" ON public.giveaway_entries;

-- push_queue is the internal delivery queue. Edge Functions write it as service_role,
-- which bypasses RLS entirely, so none of these four policies serve any purpose --
-- they only exposed payload, push_token_id and provider_message_id to clients.
-- The super-admin ALL policy remains.
DROP POLICY IF EXISTS "Enable read access for all users" ON public.push_queue;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.push_queue;
DROP POLICY IF EXISTS "Enable update for profiles based on email" ON public.push_queue;
DROP POLICY IF EXISTS "Enable delete for profiles based on profile_id" ON public.push_queue;

-- profile_admins DELETE: the tautology WAS the whole predicate, so there is nothing
-- to recreate -- stripping it would leave an empty policy. Dropped instead, per the
-- classification. "Super admins can do everything" is the sibling that remains, so
-- revoking a brand-admin grant becomes a super-admin action.
DROP POLICY IF EXISTS "Enable delete for profiles based on profile_id" ON public.profile_admins;


-- =====================================
-- PART 2: profile_admins INSERT -- close the open grant
-- =====================================
-- Currently USING true / WITH CHECK true to authenticated, with no tautology
-- involved: any authenticated user could insert themselves as admin of any profile.
-- All 69 existing rows share one created_at (2025-12-08 18:24:13.164523+00), manage
-- role_id = 10 profiles, and contain no self-admin rows -- a single bulk backfill
-- with zero organic writes, so nothing is relying on the open grant.
--
-- Uses the same super-admin idiom the sibling policies on this table already use
-- (role_id = 9 via EXISTS), rather than is_super_admin(), so the table stays
-- internally consistent.
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.profile_admins;
CREATE POLICY "Enable insert for authenticated users only" ON public.profile_admins
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.auth_id = auth.uid()) AND (profiles.role_id = 9)))));


-- =====================================
-- PART 3: CLASS A -- drop the tautology disjunct, keep the rest
-- =====================================

DROP POLICY IF EXISTS "Enable update for profiles based on brand admin" ON public.profiles;
CREATE POLICY "Enable update for profiles based on brand admin" ON public.profiles
    AS PERMISSIVE FOR UPDATE
    TO public
    USING (((auth.uid() = auth_id) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = profiles.id)))))
    WITH CHECK (((auth.uid() = auth_id) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = profiles.id)))));

DROP POLICY IF EXISTS "Enable update for profiles based on uid" ON public.posts;
CREATE POLICY "Enable update for profiles based on uid" ON public.posts
    AS PERMISSIVE FOR UPDATE
    TO public
    USING (((auth.uid() = ( SELECT profiles.auth_id
   FROM profiles
  WHERE (profiles.id = posts.profile_id))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = posts.profile_id)))))
    WITH CHECK (((auth.uid() = ( SELECT profiles.auth_id
   FROM profiles
  WHERE (profiles.id = posts.profile_id))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = posts.profile_id)))));

DROP POLICY IF EXISTS "Profiles can have all permissions for posts." ON public.posts;
CREATE POLICY "Profiles can have all permissions for posts." ON public.posts
    AS PERMISSIVE FOR ALL
    TO public
    USING (((auth.uid() = ( SELECT profiles.auth_id
   FROM profiles
  WHERE (profiles.id = posts.profile_id))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = posts.profile_id)))))
    WITH CHECK (((auth.uid() = ( SELECT profiles.auth_id
   FROM profiles
  WHERE (profiles.id = posts.profile_id))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = posts.profile_id)))));

DROP POLICY IF EXISTS "Enable update for profiles based on email" ON public.locations;
CREATE POLICY "Enable update for profiles based on email" ON public.locations
    AS PERMISSIVE FOR UPDATE
    TO public
    USING (((auth.uid() = ( SELECT profiles.auth_id
   FROM profiles
  WHERE (profiles.id = locations.brand_id))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = locations.brand_id))) OR ( SELECT (location_employees.role = 'manager'::text)
   FROM (location_employees
     JOIN profiles p ON ((p.id = location_employees.profile_id)))
  WHERE ((p.auth_id = auth.uid()) AND (location_employees.location_id = locations.id)))))
    WITH CHECK (((auth.uid() = ( SELECT profiles.auth_id
   FROM profiles
  WHERE (profiles.id = locations.brand_id))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = locations.brand_id))) OR ( SELECT (location_employees.role = 'manager'::text)
   FROM (location_employees
     JOIN profiles p ON ((p.id = location_employees.profile_id)))
  WHERE ((p.auth_id = auth.uid()) AND (location_employees.location_id = locations.id)))));

DROP POLICY IF EXISTS "Enable delete for profiles based on profile_id" ON public.locations;
CREATE POLICY "Enable delete for profiles based on profile_id" ON public.locations
    AS PERMISSIVE FOR DELETE
    TO public
    USING (((auth.uid() = ( SELECT profiles.auth_id
   FROM profiles
  WHERE (profiles.id = locations.brand_id))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = locations.brand_id))) OR ( SELECT (location_employees.role = 'manager'::text)
   FROM (location_employees
     JOIN profiles p ON ((p.id = location_employees.profile_id)))
  WHERE ((p.auth_id = auth.uid()) AND (location_employees.location_id = locations.id)))));

DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.location_employees;
CREATE POLICY "Enable insert for authenticated users only" ON public.location_employees
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id))))) OR ( SELECT (le1.role = 'manager'::text)
   FROM (location_employees le1
     JOIN profiles p ON ((p.id = le1.profile_id)))
  WHERE ((p.auth_id = auth.uid()) AND (le1.location_id = location_employees.location_id)))));

DROP POLICY IF EXISTS "Enable update for profiles based on email" ON public.location_employees;
CREATE POLICY "Enable update for profiles based on email" ON public.location_employees
    AS PERMISSIVE FOR UPDATE
    TO public
    USING (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id))))) OR ( SELECT (le1.role = 'manager'::text)
   FROM (location_employees le1
     JOIN profiles p ON ((p.id = le1.profile_id)))
  WHERE ((p.auth_id = auth.uid()) AND (le1.location_id = location_employees.location_id)))))
    WITH CHECK (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id))))) OR ( SELECT (le1.role = 'manager'::text)
   FROM (location_employees le1
     JOIN profiles p ON ((p.id = le1.profile_id)))
  WHERE ((p.auth_id = auth.uid()) AND (le1.location_id = location_employees.location_id)))));

DROP POLICY IF EXISTS "Enable delete for profiles based on profile_id" ON public.location_employees;
CREATE POLICY "Enable delete for profiles based on profile_id" ON public.location_employees
    AS PERMISSIVE FOR DELETE
    TO public
    USING (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id))))) OR ( SELECT (le1.role = 'manager'::text)
   FROM (location_employees le1
     JOIN profiles p ON ((p.id = le1.profile_id)))
  WHERE ((p.auth_id = auth.uid()) AND (le1.location_id = location_employees.location_id)))));

DROP POLICY IF EXISTS "Enable delete for profiles based on profile_id" ON public.locations_cloud_files;
CREATE POLICY "Enable delete for profiles based on profile_id" ON public.locations_cloud_files
    AS PERMISSIVE FOR DELETE
    TO public
    USING (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = locations_cloud_files.location_id))))) OR ( SELECT (location_employees.role = 'manager'::text)
   FROM (location_employees
     JOIN profiles p ON ((p.id = location_employees.profile_id)))
  WHERE ((p.auth_id = auth.uid()) AND (location_employees.location_id = locations_cloud_files.location_id)))));


-- =====================================
-- PART 4: DEFAULT PRIVILEGES
-- =====================================
-- Why the RPC lockdown in 20260918000003 had to revoke from PUBLIC as well as anon:
-- PostgreSQL's built-in default grants EXECUTE on new functions to PUBLIC. That is
-- not visible in pg_default_acl, which only records deviations. Supabase adds its
-- own entries on top, granting anon/authenticated/service_role on new tables,
-- sequences and functions in public.
--
-- Existing defaults in schema public, by grantor:
--   postgres        tables    arwdDxtm to anon, authenticated, service_role
--                   sequences rwU      to anon, authenticated, service_role
--                   functions X        to anon, authenticated, service_role
--   supabase_admin  the same three, granted by supabase_admin
--
-- Only the postgres set is changed below, and only for schema public. Two reasons:
--   * migrations run as postgres (verified: current_user = session_user = postgres,
--     and public.profiles and the functions added this week are all owned by
--     postgres), so new objects pick up the postgres defaults
--   * postgres is NOT a member of supabase_admin (pg_has_role = false), so altering
--     supabase_admin's defaults is not possible from a migration. Those entries are
--     left as they are and would still apply to anything supabase_admin creates in
--     public, which in practice is nothing.
--
-- service_role keeps everything. Nothing here revokes a privilege on an existing
-- object -- ALTER DEFAULT PRIVILEGES only affects objects created from now on.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, authenticated;

-- The built-in PUBLIC grant on functions, which is what produced the 81 PUBLIC
-- EXECUTE entries 20260918000003 had to strip one by one.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
