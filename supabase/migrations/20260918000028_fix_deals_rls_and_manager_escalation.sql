-- Put ownership behind deal writes -- and close the escalation that any
-- ownership check on a location currently rests on.
--
-- The deals policies were role checks, not ownership checks:
--
--   INSERT  WITH CHECK (auth.role() = 'authenticated')
--   UPDATE  USING      (auth.role() = 'authenticated')
--
-- which is to say anyone signed in could publish a deal, or rewrite anyone
-- else's. Confirmed by executing as that role, not by reading the policy: the
-- insert succeeded and the update rewrote a row belonging to no one.
--
-- Writing the obvious replacement -- defer to whoever manages the deal's
-- location -- turned out to be unsafe, because that check is already broken:
--
--   1. is_location_manager(integer) tests le.role = 'manager' and never
--      is_approved, so an unapproved row counts.
--   2. the self-request branch of the location_employees INSERT policy, added
--      in 20260918000018, constrains profile_id and is_approved but says
--      nothing about role.
--
-- Together those let any authenticated user hand themselves the manager role at
-- any location. Measured end to end, as an ordinary profile with no employment
-- and no admin rights:
--
--   is_location_manager(loc)                     false
--   insert (loc, me, 'manager', is_approved=false)  ALLOWED
--   is_location_manager(loc)                     true
--   update locations set name = ...              1 row rewritten
--
-- That is live against public.locations today, independent of deals. Since the
-- deals fix would inherit it, both are corrected here.
--
-- 1. is_location_manager now requires an approved row. An unapproved row is a
--    job application, not a job.
-- 2. the self-request branch may only ask for a non-privileged role. The list is
--    an allow-list rather than "not manager" so that a privileged role added
--    later fails closed instead of open. The client asks for 'budtender'; the
--    rows in the table today are 'staff'; both are covered.
-- 3. the locations UPDATE policy inlined the same unapproved-manager subquery,
--    so it is repointed at the corrected helper.
-- 4. deal writes go to can_manage_location(), new here: super admin, the brand
--    that owns the location, a profile_admin for that brand, or an approved
--    manager. Deals with no location are platform-wide and super-admin only.
--
-- SELECT on deals stays public and unfiltered, as it was. That means a deal with
-- is_active = false, or one whose window has not opened, is publicly readable --
-- worth deciding on, but it is a question about what people should see rather
-- than who may write, so it is not settled here.

-- ── 1. An unapproved employment row is not a manager ─────────────────────────

CREATE OR REPLACE FUNCTION public.is_location_manager(p_location_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.location_employees le
        JOIN public.profiles p ON p.id = le.profile_id
        WHERE p.auth_id = auth.uid()
          AND le.location_id = p_location_id
          AND le.role = 'manager'
          AND le.is_approved IS TRUE
    );
$$;

COMMENT ON FUNCTION public.is_location_manager(integer) IS
    'True when the caller holds an APPROVED manager row at that location. The '
    'is_approved test is load-bearing: a pending row is a request, and anyone '
    'may create one for themselves.';

-- ── 2. A self-request cannot ask for the privileged role ─────────────────────

DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.location_employees;
CREATE POLICY "Enable insert for authenticated users only" ON public.location_employees
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (
        (auth.uid() IN (
            SELECT p.auth_id
              FROM public.profile_admins pa
              JOIN public.profiles p ON p.id = pa.admin_profile_id
             WHERE pa.managed_profile_id = (
                 SELECT l.brand_id FROM public.locations l
                  WHERE l.id = location_employees.location_id)))
        OR public.is_location_manager(location_id)
        OR (
            profile_id = (SELECT p2.id FROM public.profiles p2 WHERE p2.auth_id = auth.uid())
            AND is_approved IS NOT TRUE
            AND role IN ('budtender', 'staff')
           )
    );

-- ── 3. locations UPDATE used its own copy of the broken check ────────────────

DROP POLICY IF EXISTS "Enable update for profiles based on email" ON public.locations;
CREATE POLICY "Enable update for profiles based on email" ON public.locations
    AS PERMISSIVE FOR UPDATE
    TO public
    USING (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = locations.brand_id)
        OR auth.uid() IN (
            SELECT p.auth_id
              FROM public.profile_admins pa
              JOIN public.profiles p ON p.id = pa.admin_profile_id
             WHERE pa.managed_profile_id = locations.brand_id)
        OR public.is_location_manager(locations.id)
    );

-- ── 4. Who may write a deal ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.can_manage_location(p_location_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT p_location_id IS NOT NULL
       AND (
            public.is_super_admin()
            OR EXISTS (
                SELECT 1 FROM public.locations l
                  JOIN public.profiles p ON p.id = l.brand_id
                 WHERE l.id = p_location_id AND p.auth_id = auth.uid())
            OR EXISTS (
                SELECT 1 FROM public.locations l
                  JOIN public.profile_admins pa ON pa.managed_profile_id = l.brand_id
                  JOIN public.profiles p ON p.id = pa.admin_profile_id
                 WHERE l.id = p_location_id AND p.auth_id = auth.uid())
            OR public.is_location_manager(p_location_id)
       );
$$;

COMMENT ON FUNCTION public.can_manage_location(integer) IS
    'True when the caller may administer that location: super admin, the owning '
    'brand, a profile_admin for that brand, or an approved location manager.';

REVOKE ALL ON FUNCTION public.can_manage_location(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_location(integer) TO authenticated, anon;

DROP POLICY IF EXISTS "Authenticated users can create deals" ON public.deals;
DROP POLICY IF EXISTS "Authenticated users can update deals" ON public.deals;
DROP POLICY IF EXISTS "Deals are manageable by the location" ON public.deals;
DROP POLICY IF EXISTS "Super admins can do everything" ON public.deals;

-- Unchanged in effect, restated so the whole policy set for this table reads in
-- one place: deals are public to read.
DROP POLICY IF EXISTS "Deals are viewable by everyone" ON public.deals;
CREATE POLICY "Deals are viewable by everyone" ON public.deals
    AS PERMISSIVE FOR SELECT TO public USING (true);

CREATE POLICY "Super admins can do everything" ON public.deals
    AS PERMISSIVE FOR ALL TO authenticated
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

CREATE POLICY "Deals are manageable by the location" ON public.deals
    AS PERMISSIVE FOR INSERT TO authenticated
    WITH CHECK (public.can_manage_location(location_id));

CREATE POLICY "Deals are updatable by the location" ON public.deals
    AS PERMISSIVE FOR UPDATE TO authenticated
    USING (public.can_manage_location(location_id))
    WITH CHECK (public.can_manage_location(location_id));

CREATE POLICY "Deals are deletable by the location" ON public.deals
    AS PERMISSIVE FOR DELETE TO authenticated
    USING (public.can_manage_location(location_id));
