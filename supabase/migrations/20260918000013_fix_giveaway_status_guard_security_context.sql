-- Fix 20260918000012: the guard it added never fired.
--
-- fn_guard_giveaway_status was written SECURITY DEFINER and gated on
--     current_user IN ('anon', 'authenticated')
-- but inside a SECURITY DEFINER function current_user is rebound to the function's
-- OWNER, not the calling role. Measured directly:
--
--     outer (SET ROLE authenticated)         current_user = authenticated
--     inside SECURITY DEFINER                current_user = postgres
--     inside SECURITY INVOKER                current_user = authenticated
--
-- So the condition was false for every caller and the trigger passed everything
-- through. The behavioural test caught it: a brand updating its own pending giveaway
-- to 'active' still reported 1 row.
--
-- The function becomes SECURITY INVOKER, which makes current_user the effective role
-- the statement is actually running as -- 'anon' or 'authenticated' for a PostgREST
-- request, 'service_role' for a server-side one, 'postgres' for a migration. That is
-- exactly the discriminator the guard wanted.
--
-- Trade-off, stated plainly: as SECURITY INVOKER the super-admin lookup now reads
-- public.profiles under the caller's own RLS. That works today because profiles has
-- a SELECT policy of USING (true). If that is ever tightened, the EXISTS returns no
-- row, NOT EXISTS becomes true, and the guard RAISES -- it fails closed, not open,
-- which is the right direction for a moderation check and would surface immediately
-- rather than silently.
--
-- Trigger privileges are checked at CREATE TRIGGER time, not when the trigger fires,
-- so the function stays revoked from PUBLIC, anon and authenticated: it still runs
-- on their UPDATEs, but none of them can call it directly over /rpc/.
CREATE OR REPLACE FUNCTION public.fn_guard_giveaway_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status
       AND current_user IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1
           FROM public.profiles p
           WHERE p.auth_id = auth.uid()
             AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION
            'Only a super admin can change a giveaway''s status (% -> %)',
            COALESCE(OLD.status, 'null'), COALESCE(NEW.status, 'null')
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION public.fn_guard_giveaway_status() FROM PUBLIC, anon, authenticated;
