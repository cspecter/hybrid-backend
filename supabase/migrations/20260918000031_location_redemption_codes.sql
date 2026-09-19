-- A master code per store, so a budtender without an app account can still
-- redeem a deal at the register.
--
-- Today redeem_deal_code accepts exactly one secret: deals.code. That works when
-- the code is printed on the deal, but a store running several deals would have
-- to know a different code for each, and a budtender who has never installed the
-- app has no way to look any of them up. A single code per store solves both.
--
-- Where it cannot live: public.locations. It already has a `code` column --
-- populated on all 311 rows with distinct 6-digit values, evidently an external
-- identifier -- and locations is world-readable through the Data API. Anything
-- kept there is visible to anyone with the anon key, which makes it useless as
-- proof of standing at the counter. That is the same reasoning that put deal
-- redemption server-side in the first place: a code the client can read is a
-- code the client can forge.
--
-- So the codes get their own table with no grants to anon or authenticated at
-- all. Nothing reads it over the API. The only paths in are three SECURITY
-- DEFINER functions:
--
--   redeem_deal_code               already existed; now also accepts the store
--                                  code for the deal's own location
--   set_location_redemption_code   a manager sets or clears their store's code
--   get_location_redemption_code   a manager reads it back, because whoever runs
--                                  the store has to be able to tell their staff
--
-- All three defer to can_manage_location, so the same people who may edit a
-- location's deals may manage its code, and nobody else.
--
-- A platform-wide deal (location_id IS NULL) has no store behind it, so only its
-- own code redeems it. That is deliberate rather than an oversight: there is no
-- single store whose staff should be able to clear a company-wide promotion.

CREATE TABLE IF NOT EXISTS public.location_redemption_codes (
    location_id           integer PRIMARY KEY REFERENCES public.locations(id) ON DELETE CASCADE,
    code                  text NOT NULL CHECK (btrim(code) <> ''),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    updated_by_profile_id integer REFERENCES public.profiles(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.location_redemption_codes IS
    'Master redemption code per store. Deliberately not on public.locations, '
    'which is world-readable: a code the client can read is a code it can forge. '
    'No grants to anon or authenticated; reached only through SECURITY DEFINER.';

-- Unambiguous across stores, so a code identifies one store and a future
-- "type a code, find the deal" flow stays possible.
DROP INDEX IF EXISTS location_redemption_codes_code_key;
CREATE UNIQUE INDEX location_redemption_codes_code_key
    ON public.location_redemption_codes (upper(btrim(code)));

ALTER TABLE public.location_redemption_codes ENABLE ROW LEVEL SECURITY;
-- No policies on purpose. RLS with no permissive policy denies everything, and
-- the revoke below means the API roles cannot reach the table to begin with.
REVOKE ALL ON TABLE public.location_redemption_codes FROM PUBLIC, anon, authenticated;

-- ── Managing the code ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_location_redemption_code(p_location_id integer, p_code text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_profile_id integer;
    v_clean      text := btrim(coalesce(p_code, ''));
BEGIN
    IF NOT public.can_manage_location(p_location_id) THEN
        RAISE EXCEPTION 'You do not manage that location' USING ERRCODE = '42501';
    END IF;
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();

    IF v_clean = '' THEN
        DELETE FROM public.location_redemption_codes WHERE location_id = p_location_id;
        RETURN;
    END IF;

    INSERT INTO public.location_redemption_codes (location_id, code, updated_by_profile_id)
    VALUES (p_location_id, v_clean, v_profile_id)
    ON CONFLICT (location_id) DO UPDATE
        SET code = EXCLUDED.code,
            updated_at = now(),
            updated_by_profile_id = EXCLUDED.updated_by_profile_id;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Another store is already using that code' USING ERRCODE = 'P0001';
END;
$$;

CREATE OR REPLACE FUNCTION public.get_location_redemption_code(p_location_id integer)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_code text;
BEGIN
    IF NOT public.can_manage_location(p_location_id) THEN
        RAISE EXCEPTION 'You do not manage that location' USING ERRCODE = '42501';
    END IF;
    SELECT code INTO v_code FROM public.location_redemption_codes WHERE location_id = p_location_id;
    RETURN v_code;
END;
$$;

REVOKE ALL ON FUNCTION public.set_location_redemption_code(integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_location_redemption_code(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_location_redemption_code(integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_location_redemption_code(integer) TO authenticated;

-- ── Redemption accepts either code ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.redeem_deal_code(target_deal_id uuid, p_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_profile_id integer;
    v_deal       public.deals%ROWTYPE;
    v_claim_id   uuid;
    v_count      integer;
    v_entered    text := upper(btrim(coalesce(p_code, '')));
    v_store_code text;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'You must be signed in to redeem a deal' USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_deal FROM public.deals WHERE public_id = target_deal_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That deal does not exist' USING ERRCODE = 'P0002';
    END IF;
    IF v_deal.is_active IS NOT TRUE THEN
        RAISE EXCEPTION 'That deal is not currently available' USING ERRCODE = 'P0001';
    END IF;
    IF v_deal.start_date IS NOT NULL AND now() < v_deal.start_date THEN
        RAISE EXCEPTION 'That deal has not started yet' USING ERRCODE = 'P0001';
    END IF;
    IF v_deal.end_date IS NOT NULL AND now() > v_deal.end_date THEN
        RAISE EXCEPTION 'That deal has expired' USING ERRCODE = 'P0001';
    END IF;

    -- The deal's own code, or the master code of the store the deal belongs to.
    -- Both comparisons happen here, against columns the browser never receives.
    IF v_deal.location_id IS NOT NULL THEN
        SELECT code INTO v_store_code
          FROM public.location_redemption_codes
         WHERE location_id = v_deal.location_id;
    END IF;

    IF v_entered IS DISTINCT FROM upper(btrim(v_deal.code))
       AND (v_store_code IS NULL OR v_entered IS DISTINCT FROM upper(btrim(v_store_code)))
    THEN
        RAISE EXCEPTION 'That code is not valid for this deal' USING ERRCODE = 'P0001';
    END IF;

    BEGIN
        INSERT INTO public.claimed_deals (profile_id, deal_id, status, claimed_at, redemption_code, redeemed_at)
        VALUES (v_profile_id, v_deal.id, 'redeemed', now(), btrim(p_code), now())
        RETURNING public_id INTO v_claim_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'You have already redeemed that deal' USING ERRCODE = 'P0001';
    END;

    IF v_deal.max_claims IS NOT NULL THEN
        SELECT claim_count INTO v_count FROM public.deals WHERE id = v_deal.id;
        IF COALESCE(v_count, 0) > v_deal.max_claims THEN
            RAISE EXCEPTION 'That deal has been fully claimed' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    RETURN v_claim_id;
END;
$$;

COMMENT ON FUNCTION public.redeem_deal_code(uuid, text) IS
    'Redeems a deal by its own code or by the master code of its store. Both are '
    'compared server-side against values the browser never receives. Writes a '
    'claimed_deals row with status ''redeemed''.';

REVOKE ALL ON FUNCTION public.redeem_deal_code(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_deal_code(uuid, text) TO authenticated;
