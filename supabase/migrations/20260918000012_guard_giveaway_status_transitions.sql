-- Close the moderation bypass left open by 20260918000011.
--
-- That migration scoped giveaways UPDATE to the row's creator, which is correct, but
-- it could not stop a creator from approving their own submission. RLS WITH CHECK
-- only ever sees the NEW row, so "status must not change" is not expressible as a
-- policy: pinning status = 'pending' in the check would instead block a brand from
-- editing a giveaway that had already been approved. Confirmed by test before
-- writing this -- a brand updating its own pending row to 'active' affected 1 row.
--
-- Comparing OLD to NEW needs a trigger, so that is what this is.
--
-- Who may change status: super admins only. That matches the client, where both
-- transitions are behind isSuperAdmin --
--   admin-dashboard.jsx:2429  status -> 'active'    (approve)
--   admin-dashboard.jsx:3563  status -> 'rejected'  (reject)
-- and the ordinary edit path (admin-dashboard.jsx:3030) builds updateRow without a
-- status key at all, so a brand editing its own giveaway never trips this.
--
-- Enforced only for the client roles. current_user is 'anon' or 'authenticated' for
-- a request arriving through PostgREST; service_role, postgres and supabase_admin
-- are left alone so Edge Functions, migrations and manual repair can still set
-- status. Gating on the database role rather than on auth.uid() being null matters:
-- a service_role JWT also carries no sub, so an auth.uid() test would not have
-- distinguished it from an anonymous caller.
--
-- BEFORE UPDATE OF status, not BEFORE UPDATE: the guard only needs to run when the
-- statement names the column. Verified that none of the three existing BEFORE UPDATE
-- triggers on this table (giveaways_fts_update, trg_timestamps,
-- trg_update_giveaways_fts_vector) assigns NEW.status, so there is no path that
-- changes status without naming it in the SET list.
--
-- SECURITY DEFINER so the role lookup reads profiles regardless of the caller's own
-- visibility, and search_path pinned so the lookup cannot be redirected.
--
-- Uses the inline role_id = 9 test that the policies on this table already use,
-- rather than is_super_admin(). A SECURITY DEFINER function runs as its owner, so
-- the grant trap that bit 20260918000003 does not apply here -- but staying with one
-- idiom per table is worth more than the brevity.
CREATE OR REPLACE FUNCTION public.fn_guard_giveaway_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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

DROP TRIGGER IF EXISTS trg_guard_giveaway_status ON public.giveaways;
CREATE TRIGGER trg_guard_giveaway_status
    BEFORE UPDATE OF status ON public.giveaways
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_guard_giveaway_status();
