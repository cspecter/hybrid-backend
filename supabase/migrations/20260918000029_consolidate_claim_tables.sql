-- Two tables recorded the same fact. Keep claimed_deals, drop deal_claims.
--
-- public.deal_claims and public.claimed_deals both model "this profile claimed
-- this deal". Both were empty. They differ in which half of the job they do
-- well:
--
--   deal_claims       wired but thin. claim_deal() writes to it, a trigger on it
--                     maintains deals.claim_count, _fn_delete_profile clears it,
--                     and recalculate_all_denormalized_counters rebuilds the
--                     counter from it. Its columns are profile_id, deal_id and a
--                     `redeemed` boolean -- and it has no foreign key to deals at
--                     all, so a claim could name a deal that does not exist.
--
--   claimed_deals     unwired but properly modelled. Foreign keys to both deals
--                     and profiles, ON DELETE CASCADE. status text CHECK'd to
--                     ('active','redeemed','expired') instead of a boolean.
--                     claimed_at and redeemed_at as separate timestamps. And a
--                     UNIQUE redemption_code, which is exactly the column the
--                     one genuinely missing piece of this feature needs: the
--                     server-side redemption that 3f44329 fails closed on,
--                     because "a code the client can check is a code the client
--                     can forge". Nothing referenced this table but its own
--                     policies.
--
-- The wiring is four small edits; the schema is not something to rebuild by
-- hand. So claimed_deals survives and inherits the wiring.
--
-- Moved onto claimed_deals: the UNIQUE (profile_id, deal_id) added in
-- 20260918000027, the timestamps trigger, and the claim_count trigger --
-- fn_change_deal_count_on_deals reads NEW.deal_id / OLD.deal_id, which both
-- tables have, so the function itself needs no change, only reattaching.
--
-- claim_deal, _fn_delete_profile and recalculate_all_denormalized_counters are
-- repointed. The latter two are reproduced from their live definitions with one
-- identifier changed each, rather than retyped.
--
-- One change to the surviving schema: redemption_code was NOT NULL with no
-- default, so a claim could not be written without one. The rehearsal failed on
-- exactly that. Generating a code here would mean inventing its user-facing
-- format -- length, charset, how it reads out loud at a counter -- and a uuid,
-- the only format needing no decision, is the wrong answer for something a
-- person reads to a budtender. So the column becomes nullable: a claim may exist
-- before a code is issued, the UNIQUE still applies to every code that is, and
-- the redemption feature can populate it and tighten this back up when someone
-- decides what a code looks like. Claims are written with redemption_code NULL
-- and status 'active'.

-- ── 1. Move the constraint and the triggers ──────────────────────────────────

ALTER TABLE public.claimed_deals
    ALTER COLUMN redemption_code DROP NOT NULL;

ALTER TABLE public.claimed_deals
    DROP CONSTRAINT IF EXISTS claimed_deals_profile_deal_key;
ALTER TABLE public.claimed_deals
    ADD CONSTRAINT claimed_deals_profile_deal_key UNIQUE (profile_id, deal_id);

DROP TRIGGER IF EXISTS trg_timestamps ON public.claimed_deals;
CREATE TRIGGER trg_timestamps
    BEFORE INSERT OR UPDATE ON public.claimed_deals
    FOR EACH ROW EXECUTE FUNCTION public.manage_timestamps();

DROP TRIGGER IF EXISTS trg_change_claimed_deals_count_on_deals ON public.claimed_deals;
CREATE TRIGGER trg_change_claimed_deals_count_on_deals
    AFTER INSERT OR DELETE ON public.claimed_deals
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_deal_count_on_deals();

-- ── 2. claim_deal writes to the surviving table ──────────────────────────────
-- Same guards as 20260918000027: signed in, deal exists, active, inside its
-- window, not already claimed, under max_claims. claim_count is still left to
-- the trigger, and max_claims is still enforced by re-reading it afterwards.

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
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'You must be signed in to claim a deal' USING ERRCODE = '28000';
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

    BEGIN
        INSERT INTO public.claimed_deals (profile_id, deal_id, status, claimed_at)
        VALUES (v_profile_id, v_deal.id, 'active', now())
        RETURNING public_id INTO v_claim_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'You have already claimed that deal' USING ERRCODE = 'P0001';
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

COMMENT ON FUNCTION public.claim_deal(uuid) IS
    'Claims a deal for the calling profile into claimed_deals. Enforces '
    'is_active, the start/end window, max_claims and one claim per profile. '
    'claim_count is maintained by the trigger. Returns the claim public_id.';

REVOKE ALL ON FUNCTION public.claim_deal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_deal(uuid) TO authenticated;

-- ── 3. The two other referencing functions, repointed ────────────────────────
-- Reproduced from pg_get_functiondef with `deal_claims` -> `claimed_deals` and
-- nothing else altered.

CREATE OR REPLACE FUNCTION public._fn_delete_profile()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        DELETE FROM product_brands WHERE brand_id = OLD.id;
        DELETE FROM lists WHERE profile_id = OLD.id;
        DELETE FROM posts WHERE profile_id = OLD.id;
        DELETE FROM explore_profiles WHERE profile_id = OLD.id;
        DELETE FROM locations WHERE brand_id = OLD.id;
        DELETE FROM stash WHERE profile_id = OLD.id;
        DELETE FROM subscriptions_lists WHERE profile_id = OLD.id;
        DELETE FROM relationships WHERE follower_id = OLD.id OR followee_id = OLD.id;
        DELETE FROM addresses WHERE profile_id = OLD.id;
        DELETE FROM profile_admins WHERE profile_id = OLD.id OR brand_id = OLD.id;
        DELETE FROM likes WHERE profile_id = OLD.id;
        DELETE FROM giveaway_entries WHERE profile_id = OLD.id;
        DELETE FROM claimed_deals WHERE profile_id = OLD.id;
        DELETE FROM analytics_posts WHERE profile_id = OLD.id;
        RETURN OLD;
    END IF;
    RETURN OLD;
END;
$function$;


CREATE OR REPLACE FUNCTION public.recalculate_all_denormalized_counters()
 RETURNS TABLE(counter text, rows_repaired integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    n integer;
BEGIN
    -- Caller guard; see the migration header for why pg_trigger_depth matters.
    IF pg_trigger_depth() = 0
       AND coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
           IN ('anon', 'authenticated')
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.auth_id = auth.uid() AND p.role_id = 9
       )
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    -- posts.like_count <- likes.post_id
    UPDATE public.posts p
    SET like_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(l.cnt, 0)::int AS fresh
        FROM public.posts p2
        LEFT JOIN (
            SELECT post_id, COUNT(*)::int AS cnt FROM public.likes GROUP BY post_id
        ) l ON l.post_id = p2.id
    ) c
    WHERE p.id = c.id AND p.like_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'posts.like_count'; rows_repaired := n; RETURN NEXT;

    -- lists.product_count <- lists_products.list_id
    UPDATE public.lists l
    SET product_count = c.fresh
    FROM (
        SELECT l2.id, COALESCE(lp.cnt, 0)::int AS fresh
        FROM public.lists l2
        LEFT JOIN (
            SELECT list_id, COUNT(*)::int AS cnt FROM public.lists_products GROUP BY list_id
        ) lp ON lp.list_id = l2.id
    ) c
    WHERE l.id = c.id AND l.product_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'lists.product_count'; rows_repaired := n; RETURN NEXT;

    -- lists.subscription_count <- subscriptions_lists.list_id
    UPDATE public.lists l
    SET subscription_count = c.fresh
    FROM (
        SELECT l2.id, COALESCE(sl.cnt, 0)::int AS fresh
        FROM public.lists l2
        LEFT JOIN (
            SELECT list_id, COUNT(*)::int AS cnt FROM public.subscriptions_lists GROUP BY list_id
        ) sl ON sl.list_id = l2.id
    ) c
    WHERE l.id = c.id AND l.subscription_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'lists.subscription_count'; rows_repaired := n; RETURN NEXT;

    -- products.stash_count <- stash.product_id
    UPDATE public.products p
    SET stash_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(s.cnt, 0)::int AS fresh
        FROM public.products p2
        LEFT JOIN (
            SELECT product_id, COUNT(*)::int AS cnt FROM public.stash GROUP BY product_id
        ) s ON s.product_id = p2.id
    ) c
    WHERE p.id = c.id AND p.stash_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'products.stash_count'; rows_repaired := n; RETURN NEXT;

    -- products.post_count <- posts_products.product_id
    UPDATE public.products p
    SET post_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(pp.cnt, 0)::int AS fresh
        FROM public.products p2
        LEFT JOIN (
            SELECT product_id, COUNT(*)::int AS cnt FROM public.posts_products GROUP BY product_id
        ) pp ON pp.product_id = p2.id
    ) c
    WHERE p.id = c.id AND p.post_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'products.post_count'; rows_repaired := n; RETURN NEXT;

    -- products.list_count <- lists_products.product_id
    UPDATE public.products p
    SET list_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(lp.cnt, 0)::int AS fresh
        FROM public.products p2
        LEFT JOIN (
            SELECT product_id, COUNT(*)::int AS cnt FROM public.lists_products GROUP BY product_id
        ) lp ON lp.product_id = p2.id
    ) c
    WHERE p.id = c.id AND p.list_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'products.list_count'; rows_repaired := n; RETURN NEXT;

    -- products.brand_count <- product_brands.product_id
    UPDATE public.products p
    SET brand_count = c.fresh
    FROM (
        SELECT p2.id, COALESCE(pb.cnt, 0)::int AS fresh
        FROM public.products p2
        LEFT JOIN (
            SELECT product_id, COUNT(*)::int AS cnt FROM public.product_brands GROUP BY product_id
        ) pb ON pb.product_id = p2.id
    ) c
    WHERE p.id = c.id AND p.brand_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'products.brand_count'; rows_repaired := n; RETURN NEXT;

    -- giveaways.entry_count <- giveaway_entries.giveaway_id
    UPDATE public.giveaways g
    SET entry_count = c.fresh
    FROM (
        SELECT g2.id, COALESCE(ge.cnt, 0)::int AS fresh
        FROM public.giveaways g2
        LEFT JOIN (
            SELECT giveaway_id, COUNT(*)::int AS cnt FROM public.giveaway_entries GROUP BY giveaway_id
        ) ge ON ge.giveaway_id = g2.id
    ) c
    WHERE g.id = c.id AND g.entry_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'giveaways.entry_count'; rows_repaired := n; RETURN NEXT;

    -- deals.claim_count <- claimed_deals.deal_id
    -- claimed_deals is the relation the trigger fires on. See Part 3 for the
    -- second, unwired claim table.
    UPDATE public.deals d
    SET claim_count = c.fresh
    FROM (
        SELECT d2.id, COALESCE(dc.cnt, 0)::int AS fresh
        FROM public.deals d2
        LEFT JOIN (
            SELECT deal_id, COUNT(*)::int AS cnt FROM public.claimed_deals GROUP BY deal_id
        ) dc ON dc.deal_id = d2.id
    ) c
    WHERE d.id = c.id AND d.claim_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    counter := 'deals.claim_count'; rows_repaired := n; RETURN NEXT;

    -- The eight profiles.* counters are deliberately not touched here. All eight
    -- measured clean, so there is nothing to repair, and delegating to
    -- recalculate_all_profile_stats() would mean depending on a return value
    -- this migration has not verified -- it reports rows visited, not rows
    -- changed, which would not mean the same thing as the counts above. Run it
    -- directly if those counters ever drift.

    RETURN;
END;
$function$;


-- ── 4. Grants on the survivor ────────────────────────────────────────────────
-- claimed_deals carried the same blanket grants as the rest of these tables,
-- TRUNCATE and REFERENCES and TRIGGER included, to both API roles. Its policies
-- are owner-scoped for select/insert/update, so those three are what
-- authenticated needs and anon needs nothing -- a claim is never anonymous.

REVOKE ALL ON TABLE public.claimed_deals FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.claimed_deals TO authenticated;

-- ── 5. Drop the other one ────────────────────────────────────────────────────
-- Empty, and nothing references it any more. Its trigger goes with it.

DROP TABLE IF EXISTS public.deal_claims;
