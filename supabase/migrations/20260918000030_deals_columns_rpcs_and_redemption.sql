-- Give deals the columns its UI already renders, repair the two broken lookup
-- RPCs, and add the server-side redemption the client has been failing closed on.
--
-- 1. Six columns the deals page renders with nothing behind them. b248ce5 wired
--    the page to the table and had to default all six in the fetcher: category,
--    redemption_type, code, image_url, terms, long_description. Until they
--    exist, every live deal is uncategorised, in-store, and illustrated with an
--    emoji picked from deal_type.
--
-- 2. get_location_deals and get_product_deals are both broken, the same way
--    claim_deal was. Executed against production they raise:
--
--      get_location_deals   42703: column d.expiration_date does not exist
--      get_product_deals    42703: column d.product_id does not exist
--
--    The columns are end_date and product_ids (an integer[]). Neither function
--    has ever returned a row. Both also ignored is_active and start_date, so a
--    deactivated or not-yet-open deal would have been listed.
--
--    Note for anyone joining deal_products: its deal_id is a uuid referencing
--    deals(public_id), not deals(id). Joining it on d.id raises
--    "operator does not exist: uuid = integer". deals_locations, by contrast,
--    keys on the integer id -- and has no foreign key to deals at all.
--
-- 3. redeem_deal_code. The client's redeem box has accepted nothing since
--    3f44329, which removed three hardcoded codes from the bundle and said
--    plainly why: a code the client can check is a code the client can forge,
--    and no server-side endpoint existed to check it properly. This is that
--    endpoint. It needs no decision about what a code looks like, because the
--    code is not generated here -- an in-store deal carries a 6-digit code its
--    author sets, and the customer proves they are at the store by entering it.
--
-- 4. my_manageable_locations, so the admin UI can offer exactly the locations
--    the caller may attach a deal to instead of guessing, and get the same
--    answer the RLS on deals will give.

-- ── 1. The missing columns ───────────────────────────────────────────────────

ALTER TABLE public.deals
    ADD COLUMN IF NOT EXISTS category         text,
    ADD COLUMN IF NOT EXISTS redemption_type  text NOT NULL DEFAULT 'in_store',
    ADD COLUMN IF NOT EXISTS code             text,
    ADD COLUMN IF NOT EXISTS image_url        text,
    ADD COLUMN IF NOT EXISTS terms            text,
    ADD COLUMN IF NOT EXISTS long_description text;

ALTER TABLE public.deals DROP CONSTRAINT IF EXISTS deals_redemption_type_check;
ALTER TABLE public.deals
    ADD CONSTRAINT deals_redemption_type_check
        CHECK (redemption_type IN ('code', 'in_store'));

-- An in-store deal is redeemed by entering its code, so it must have one. A
-- code-type deal shows its code to the customer, so it must have one too --
-- the difference is who the code is for, not whether it exists.
ALTER TABLE public.deals DROP CONSTRAINT IF EXISTS deals_code_present_check;
ALTER TABLE public.deals
    ADD CONSTRAINT deals_code_present_check
        CHECK (code IS NOT NULL AND btrim(code) <> '');

COMMENT ON COLUMN public.deals.redemption_type IS
    '''in_store'': the customer enters `code` at the counter to claim. ''code'': '
    '`code` is shown to the customer to use elsewhere.';

-- Two deals must not share a code, or redeem_deal_code could not tell them apart.
DROP INDEX IF EXISTS deals_code_key;
CREATE UNIQUE INDEX deals_code_key ON public.deals (upper(btrim(code)));

-- ── 2. The two lookup RPCs, repaired ─────────────────────────────────────────
-- Same shape and signature as before, so nothing calling them needs to change.
-- deals.location_id is the primary location and deals_locations holds the rest;
-- the old version consulted only the join table and so missed every deal that
-- named its location directly.

CREATE OR REPLACE FUNCTION public.get_location_deals(p_public_id text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 10)
RETURNS TABLE(id uuid, rank double precision, total_count bigint)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_location_id(p_public_id);

    RETURN QUERY
    WITH filtered_items AS (
        SELECT DISTINCT d.public_id, d.created_at
        FROM public.deals d
        LEFT JOIN public.deals_locations dl ON dl.deal_id = d.id
        WHERE (d.location_id = v_target_id OR dl.location_id = v_target_id)
          AND d.is_active IS TRUE
          AND (d.start_date IS NULL OR d.start_date <= now())
          AND (d.end_date   IS NULL OR d.end_date   >  now())
    ),
    total AS (SELECT count(*) AS cnt FROM filtered_items)
    SELECT fi.public_id,
           EXTRACT(EPOCH FROM fi.created_at)::double precision,
           t.cnt
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_product_deals(p_public_id text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 10)
RETURNS TABLE(id uuid, rank double precision, total_count bigint)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_product_id(p_public_id);

    RETURN QUERY
    WITH filtered_items AS (
        SELECT DISTINCT d.public_id, d.created_at
        FROM public.deals d
        LEFT JOIN public.deal_products dp ON dp.deal_id = d.public_id
        WHERE (d.product_ids @> ARRAY[v_target_id] OR dp.product_id = v_target_id)
          AND d.is_active IS TRUE
          AND (d.start_date IS NULL OR d.start_date <= now())
          AND (d.end_date   IS NULL OR d.end_date   >  now())
    ),
    total AS (SELECT count(*) AS cnt FROM filtered_items)
    SELECT fi.public_id,
           EXTRACT(EPOCH FROM fi.created_at)::double precision,
           t.cnt
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

-- Both read only what the deals SELECT policy already makes public, and both are
-- SECURITY INVOKER, so RLS still applies to the caller. 20260918000016 revoked
-- them with the rest of the invoker surface; they are safe to hand back.
REVOKE ALL ON FUNCTION public.get_location_deals(text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_product_deals(text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_location_deals(text, integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_deals(text, integer, integer) TO anon, authenticated;

-- ── 3. Server-side redemption ────────────────────────────────────────────────
-- Takes the deal and the code the customer typed, and claims the deal only if
-- they match. The comparison happens here, against a column the browser never
-- receives for in_store deals, which is the whole point.

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

    -- The check the client is not allowed to make.
    IF upper(btrim(coalesce(p_code, ''))) IS DISTINCT FROM upper(btrim(v_deal.code)) THEN
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
    'Redeems a deal by its code. The code is compared server-side, so an '
    'in_store code never has to reach the browser. Writes a claimed_deals row '
    'with status ''redeemed''. Same guards as claim_deal.';

REVOKE ALL ON FUNCTION public.redeem_deal_code(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redeem_deal_code(uuid, text) TO authenticated;

-- claimed_deals.redemption_code is UNIQUE, and every claim of the same in-store
-- deal stores the same code. That constraint was written for per-claim generated
-- codes, which is not the model here, so it has to go -- the per-deal uniqueness
-- is on deals.code above, and one-claim-per-profile is the per-person limit.
ALTER TABLE public.claimed_deals DROP CONSTRAINT IF EXISTS claimed_deals_redemption_code_key;

-- ── 4. Which locations may the caller attach a deal to ───────────────────────

CREATE OR REPLACE FUNCTION public.my_manageable_locations()
RETURNS TABLE(id integer, name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT l.id, l.name
    FROM public.locations l
    WHERE public.can_manage_location(l.id)
    ORDER BY l.name;
$$;

COMMENT ON FUNCTION public.my_manageable_locations() IS
    'The locations the caller may administer, by the same rule the deals RLS '
    'uses, so an admin UI can offer exactly what will be accepted.';

REVOKE ALL ON FUNCTION public.my_manageable_locations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_manageable_locations() TO authenticated;
