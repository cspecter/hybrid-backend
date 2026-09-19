-- Require ownership to create a location, and stop handing the API roles
-- privileges nothing uses.
--
-- The INSERT policy was WITH CHECK (true) for authenticated: anyone with an
-- account could add a dispensary to a table of 311 real ones, name it whatever,
-- and it would be publicly readable, because the SELECT policy is also true.
-- The same shape as the deals policies closed in 8d8a6b9 — a role check where an
-- ownership check belongs.
--
-- It also let a location be created with brand_id NULL, which nobody but a super
-- admin could then edit, since every other branch of the UPDATE policy resolves
-- through brand_id. An unowned, uneditable, publicly visible store.
--
-- Creation now needs one of:
--   * super admin
--   * the brand that will own it — brand_id is the caller's own profile
--   * a profile_admin acting for that brand
--
-- is_location_manager has no part in this one, unlike UPDATE: it asks whether
-- the caller manages an existing location, and on INSERT there is no row yet to
-- manage. A manager of one store is not thereby entitled to invent another.
--
-- Separately, both anon and authenticated held DELETE, TRUNCATE, REFERENCES and
-- TRIGGER on the table. TRUNCATE is not subject to RLS at all, so that grant was
-- the one thing on this table that could have emptied it outright. PostgREST
-- never issues TRUNCATE, so it was not reachable through the Data API, but it
-- had no business being granted. anon keeps SELECT, which is what makes the
-- store directory public; authenticated keeps the four verbs its policies gate.

DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.locations;
CREATE POLICY "Enable insert for authenticated users only" ON public.locations
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_super_admin()
        OR locations.brand_id = (SELECT p.id FROM public.profiles p WHERE p.auth_id = auth.uid())
        OR EXISTS (
            SELECT 1
              FROM public.profile_admins pa
              JOIN public.profiles p ON p.id = pa.admin_profile_id
             WHERE pa.managed_profile_id = locations.brand_id
               AND p.auth_id = auth.uid())
    );

REVOKE ALL ON TABLE public.locations FROM anon, authenticated;
GRANT SELECT ON TABLE public.locations TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.locations TO authenticated;

-- ── Publishing needs review ──────────────────────────────────────────────────
-- Requiring ownership to create a store is not on its own enough. Any profile
-- can name itself as the owning brand, and while status defaults to 'draft' and
-- the app only lists published/active, the UPDATE policy lets the owner change
-- any column on their own row -- including status. Measured end to end: an
-- ordinary user inserts a store as draft, updates it to 'published', and it is
-- in the public directory. Ownership was never the gate; review is.
--
-- A policy cannot express this. WITH CHECK only sees the new row, so "did status
-- change" is invisible to it, and a rule like "status must not be published"
-- would block an owner from making any edit at all to an already-published
-- store -- which is exactly what the locations manager does. That needs OLD, so
-- it needs a trigger.
--
-- SECURITY INVOKER deliberately. is_super_admin() reads auth.uid(), which comes
-- from the request's JWT rather than the executing role, so it works either way
-- -- but a DEFINER trigger here would run its checks as the owner for no reason.
-- A connection with no JWT at all is a server-side or admin path, not an API
-- caller, and is left alone: migrations and back-office jobs still publish.

CREATE OR REPLACE FUNCTION public.enforce_location_publish_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF coalesce(current_setting('request.jwt.claims', true), '') = '' THEN
        RETURN NEW;
    END IF;
    IF public.is_super_admin() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.status IN ('published', 'active') THEN
            RAISE EXCEPTION 'A new store starts as a draft and has to be reviewed before it goes live'
                USING ERRCODE = '42501';
        END IF;
    ELSIF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('published', 'active') THEN
        RAISE EXCEPTION 'Publishing a store has to be reviewed'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_location_publish_approval() IS
    'Stops a non-super-admin putting a location into published/active. Owners may '
    'still edit an already-published store; they just cannot promote one.';

DROP TRIGGER IF EXISTS trg_location_publish_approval ON public.locations;
CREATE TRIGGER trg_location_publish_approval
    BEFORE INSERT OR UPDATE ON public.locations
    FOR EACH ROW EXECUTE FUNCTION public.enforce_location_publish_approval();
