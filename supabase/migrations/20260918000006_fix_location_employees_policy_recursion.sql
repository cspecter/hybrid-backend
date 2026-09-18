-- Fix the infinite recursion in the location_employees write policies.
--
-- INSERT, UPDATE and DELETE on public.location_employees have been failing for
-- every role subject to RLS with
--   ERROR 42P17: infinite recursion detected in policy for relation "location_employees"
--
-- Cause: each of those three policies carries a disjunct that queries
-- location_employees from inside a policy ON location_employees --
--
--   ( SELECT (le1.role = 'manager'::text)
--       FROM location_employees le1
--       JOIN profiles p ON p.id = le1.profile_id
--      WHERE p.auth_id = auth.uid()
--        AND le1.location_id = location_employees.location_id )
--
-- Evaluating the policy requires reading the table, which requires evaluating the
-- policy. SELECT is unaffected -- its policy is USING (true) and touches nothing.
--
-- This is NOT a regression from 20260918000004. Verified by restoring the original
-- pre-migration policy, tautology disjunct and all, inside a rolled-back
-- transaction: the recursion still fired. It predates this week's work. Removing the
-- tautology only made it reachable on more query plans, since the always-true
-- disjunct could previously short-circuit ahead of the recursive one.
--
-- Fix: move the manager test into a SECURITY DEFINER helper. The function is owned
-- by postgres, which owns location_employees, and the table does not have FORCE ROW
-- LEVEL SECURITY, so the owner bypasses RLS inside the function body and the cycle
-- is broken.
--
-- Only the recursive disjunct is replaced. The profile_admins disjunct in each
-- policy is carried over verbatim from the live definition.


CREATE OR REPLACE FUNCTION public.is_location_manager(p_location_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.location_employees le
        JOIN public.profiles p ON p.id = le.profile_id
        WHERE p.auth_id = auth.uid()
          AND le.location_id = p_location_id
          AND le.role = 'manager'
    );
$$;

-- The DELETE and UPDATE policies below are TO public, so anon evaluates them too.
-- A policy expression runs as the CALLING role, so anon needs EXECUTE or the policy
-- raises 42501 instead of returning no rows -- exactly the regression 20260918000003
-- caused with is_super_admin and 20260918000005 had to undo. Granting to anon leaks
-- nothing: auth.uid() is NULL for anon, so the EXISTS is simply false.
-- PUBLIC stays revoked, per the default-privilege policy set in 20260918000004.
REVOKE ALL PRIVILEGES ON FUNCTION public.is_location_manager(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_location_manager(integer) TO anon, authenticated, postgres, service_role;


-- Semantics note: the original was a scalar subquery returning
-- (le1.role = 'manager') -- TRUE when the caller's row at that location is a
-- manager, FALSE when it exists but is not, NULL when there is no row, and an
-- error ("more than one row returned by a subquery") if the caller somehow had two
-- rows for one location. EXISTS collapses the non-TRUE cases to FALSE, which the
-- surrounding OR treats identically, and removes the multi-row error. No duplicate
-- (profile_id, location_id) pairs exist today.

DROP POLICY IF EXISTS "Enable delete for profiles based on profile_id" ON public.location_employees;
CREATE POLICY "Enable delete for profiles based on profile_id" ON public.location_employees
    AS PERMISSIVE FOR DELETE
    TO public
    USING (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id))))) OR public.is_location_manager(location_employees.location_id)));

DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.location_employees;
CREATE POLICY "Enable insert for authenticated users only" ON public.location_employees
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id))))) OR public.is_location_manager(location_employees.location_id)));

DROP POLICY IF EXISTS "Enable update for profiles based on email" ON public.location_employees;
CREATE POLICY "Enable update for profiles based on email" ON public.location_employees
    AS PERMISSIVE FOR UPDATE
    TO public
    USING (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id))))) OR public.is_location_manager(location_employees.location_id)))
    WITH CHECK (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id))))) OR public.is_location_manager(location_employees.location_id)));
