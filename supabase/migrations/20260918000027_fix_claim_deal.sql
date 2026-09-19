-- Make claim_deal work, and make it enforce the rules the deals table already models.
--
-- The function has never run to completion. Its last statement was
--
--     UPDATE public.deals SET claimed_deals = claimed_deals + 1 WHERE id = v_deal_id;
--
-- and there is no claimed_deals column -- the counter is claim_count. Called
-- against a real profile and a real deal it raises
--
--     42703: column "claimed_deals" does not exist
--
-- This was never noticed because public.deals has 0 rows and nothing in the
-- client calls the function; the deals UI is served entirely from a hardcoded
-- array. So this is a repair of something dormant, not of something in use.
--
-- Beyond the column name it accepted any deal at all. deals carries is_active,
-- start_date, end_date and max_claims, and the old body consulted none of them:
-- an expired, deactivated or fully-claimed deal was claimable, and a single
-- profile could claim the same deal without limit, which makes max_claims
-- meaningless -- one account could exhaust a deal on its own.
--
-- The function does not touch claim_count. deal_claims already carries
-- trg_change_claimed_deals_count_on_deals, an AFTER INSERT OR DELETE trigger
-- that maintains the counter in both directions with a floor on the decrement.
-- The original body incremented it as well, so a working version of the old code
-- would have counted every claim twice -- a first draft of this migration did
-- exactly that, and the rehearsal showed claim_count going 0 -> 2 on a single
-- claim. Same pattern as the seven functions corrected in 20260918000003.
--
-- So max_claims is enforced by inserting the claim, letting the trigger do the
-- increment, and then re-reading the counter: over the cap means this claim was
-- the one that broke it, and the RAISE takes the insert and the increment back
-- out. Concurrent claims serialise on the row lock the trigger's UPDATE takes
-- against the deals row, so the re-read cannot miss a competing claim.
--
-- Ordering: the insert comes first so a duplicate is rejected by the unique
-- index before the counter moves at all.
--
-- Left alone deliberately:
--
--   * public.claimed_deals, a second claim table with overlapping purpose and
--     different policies. Which of the two survives is a schema decision beyond
--     the scope of repairing this function.
--   * the RLS on public.deals, which lets any authenticated user INSERT a deal
--     and UPDATE anyone else's -- both confirmed by executing as that role. That
--     is a live hole and wants its own migration; it is not what this one is for.
--   * whether a deal may be claimed more than once by the same person. The
--     schema has no column for it -- no claims_per_user, no cooldown -- so one
--     claim per profile is the only rule it can express, and a repeatable deal
--     ("$5 off flower, daily 4-6pm") would need a schema change and a product
--     decision about what repeatable means.

-- One claim per profile per deal. The table is empty, so this adds cleanly.
-- Without it the max_claims guard below is defeatable by a single account.
ALTER TABLE public.deal_claims
    DROP CONSTRAINT IF EXISTS deal_claims_profile_deal_key;
ALTER TABLE public.deal_claims
    ADD CONSTRAINT deal_claims_profile_deal_key UNIQUE (profile_id, deal_id);

CREATE OR REPLACE FUNCTION public.claim_deal(target_deal_id uuid)
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
    SELECT id INTO v_profile_id
      FROM public.profiles
     WHERE auth_id = auth.uid();

    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'You must be signed in to claim a deal'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_deal
      FROM public.deals
     WHERE public_id = target_deal_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'That deal does not exist'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_deal.is_active IS NOT TRUE THEN
        RAISE EXCEPTION 'That deal is not currently available'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_deal.start_date IS NOT NULL AND now() < v_deal.start_date THEN
        RAISE EXCEPTION 'That deal has not started yet'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_deal.end_date IS NOT NULL AND now() > v_deal.end_date THEN
        RAISE EXCEPTION 'That deal has expired'
            USING ERRCODE = 'P0001';
    END IF;

    -- Insert before incrementing: a repeat claim is rejected here, by the unique
    -- index, and never touches the counter.
    BEGIN
        INSERT INTO public.deal_claims (profile_id, deal_id)
        VALUES (v_profile_id, v_deal.id)
        RETURNING public_id INTO v_claim_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'You have already claimed that deal'
            USING ERRCODE = 'P0001';
    END;

    -- trg_change_claimed_deals_count_on_deals has now incremented claim_count.
    -- Re-read it: past the cap means this claim was one too many.
    IF v_deal.max_claims IS NOT NULL THEN
        SELECT claim_count INTO v_count
          FROM public.deals
         WHERE id = v_deal.id;

        IF COALESCE(v_count, 0) > v_deal.max_claims THEN
            RAISE EXCEPTION 'That deal has been fully claimed'
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    RETURN v_claim_id;
END;
$$;

COMMENT ON FUNCTION public.claim_deal(uuid) IS
    'Claims a deal for the calling profile. Enforces is_active, the start/end '
    'window, max_claims and one claim per profile. claim_count is maintained by '
    'the trigger on deal_claims, not here. Returns the '
    'claim public_id.';

-- 20260918000003 revoked this along with every other definer function. Claiming
-- needs a signed-in profile, so authenticated gets it back and anon does not.
REVOKE ALL ON FUNCTION public.claim_deal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_deal(uuid) TO authenticated;
