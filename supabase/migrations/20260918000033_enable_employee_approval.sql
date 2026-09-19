-- Let the people who run a store actually approve someone who asks to work there.
--
-- Everything around this already worked. location_employees takes self-requests
-- since 20260918000018, on_employee_request notifies the brand, and
-- on_employee_approval notifies the requester either way — approved or rejected,
-- the latter added in 20260918000019. update_employee_approval resolves public
-- ids, checks authorisation and flips the row. What was missing is smaller and
-- completely blocking:
--
--   1. EXECUTE on update_employee_approval was revoked from anon and
--      authenticated by 20260918000016, along with the rest of the invoker and
--      definer surface. Nothing in the app could call it, so no request could
--      ever be actioned. The result is visible in the data: two requests, both
--      pending, neither reviewed, and not one approved employment row anywhere
--      in the system.
--
--   2. Its guard accepts a profile_admin for the owning brand, an approved
--      location manager, or a super admin -- but not the brand that owns the
--      location outright. Every one of the 311 locations has a brand profile
--      with an account, and those are the people who would actually be
--      approving. They were the one group locked out.
--
-- Both now defer to can_manage_location, the same test the deals and store-code
-- paths use, so "who may approve an employee here" and "who may edit this store"
-- are one answer rather than two that drift.
--
-- The first approved manager at any store has to come from the brand or a super
-- admin, since is_location_manager is one of the branches and nobody holds it
-- yet. That is the intended shape: managers are appointed from above, not
-- bootstrapped sideways.

CREATE OR REPLACE FUNCTION public.update_employee_approval(p_location_id uuid, p_profile_id uuid, p_is_approved boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_jwt_role    text;
    v_location_id integer;
    v_profile_id  integer;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    SELECT id INTO v_location_id FROM public.locations WHERE public_id = p_location_id;
    SELECT id INTO v_profile_id  FROM public.profiles  WHERE public_id = p_profile_id;
    IF v_location_id IS NULL OR v_profile_id IS NULL THEN
        RAISE EXCEPTION 'Location or profile not found' USING ERRCODE = 'P0002';
    END IF;

    -- Same rule as editing the store itself: super admin, the owning brand, a
    -- profile_admin for that brand, or an approved manager there.
    IF v_jwt_role IN ('anon', 'authenticated')
       AND NOT public.can_manage_location(v_location_id) THEN
        RAISE EXCEPTION 'You do not manage that location' USING ERRCODE = '42501';
    END IF;

    UPDATE public.location_employees
       SET has_been_reviewed = TRUE,
           is_approved       = p_is_approved
     WHERE location_id = v_location_id
       AND profile_id  = v_profile_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No employment request from that person at that store' USING ERRCODE = 'P0002';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.update_employee_approval(uuid, uuid, boolean) IS
    'Approves or rejects an employment request. Authorised by can_manage_location. '
    'The trigger on location_employees notifies the requester either way.';

REVOKE ALL ON FUNCTION public.update_employee_approval(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_employee_approval(uuid, uuid, boolean) TO authenticated;
