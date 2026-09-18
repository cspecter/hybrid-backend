-- Allow a profile to request to work at a location.
--
-- location_employees INSERT is currently restricted to admins of the location's brand and
-- to existing managers at that location, so the person who wants the job is the one role
-- that cannot create the row. That makes the budtender request flow impossible to build.
--
-- A third branch is added: you may insert a row for YOURSELF, and only unapproved.
--
--     profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid())
--     AND is_approved IS NOT TRUE
--
-- IS NOT TRUE rather than = false on purpose: is_approved is nullable, a client that omits
-- it inserts NULL, and `NULL = false` is NULL, which WITH CHECK treats as a failure. So
-- `= false` would have rejected exactly the well-behaved insert this branch exists to
-- allow. IS NOT TRUE accepts false and NULL and rejects true.
--
-- Self-APPROVAL is not granted. The UPDATE policy is untouched, so flipping is_approved
-- remains limited to the brand's admins and the location's managers, and the two existing
-- branches of this INSERT policy are carried over verbatim.
--
-- No client-side notification work is needed for this: on_employee_request (AFTER INSERT,
-- notify_brand_of_employee_request) and on_employee_approval (AFTER UPDATE,
-- notify_employee_of_approval) already fire notification types 54 and 55.
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.location_employees;
CREATE POLICY "Enable insert for authenticated users only" ON public.location_employees
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id = ( SELECT locations.brand_id
           FROM locations
          WHERE (locations.id = location_employees.location_id)))))
   OR is_location_manager(location_id)
   OR (
        profile_id = (SELECT p2.id FROM public.profiles p2 WHERE p2.auth_id = auth.uid())
        AND is_approved IS NOT TRUE
      )));
