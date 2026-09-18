-- Repair drifted denormalized counters and stop the incremental triggers from
-- driving them below zero.
--
-- Follows the shape of 20260216000004_recalculate_all_profile_stats.sql: a
-- reusable, idempotent recalculation function that recomputes each counter from
-- the source relation its trigger reads, plus (here) CREATE OR REPLACE on every
-- trigger function whose decrement had no floor.
--
-- Measured against production before writing (2026-09-18):
--
--   counter                     negative   drifted   net stored-minus-actual
--   posts.like_count                   8       527                    -1714
--   lists.subscription_count           0        24                      +18
--   lists.product_count                0         2                       -1
--   giveaways.winner_count             0        37                      -55   (see Part 3)
--   everything else                    0         0                        0
--
-- No counter in scope held NULL. deals.* could not drift: deals, deal_claims and
-- claimed_deals are all empty.
--
-- Deliberately NOT recomputed here: posts.view_count. Its source relation is
-- inferred rather than declared -- fn_analytics_post increments it once per
-- analytics_posts INSERT and never decrements, so "count of analytics_posts rows
-- for this post" is a guess about intent, not a contract. It currently shows zero
-- drift, so there is nothing to repair and no reason to bake the guess in.


-- =====================================
-- PART 1: RECALCULATION
-- =====================================

-- Each UPDATE is restricted with IS DISTINCT FROM so the reported row count is
-- the number of rows actually corrected, not the size of the table.
CREATE OR REPLACE FUNCTION public.recalculate_all_denormalized_counters()
RETURNS TABLE(counter text, rows_repaired integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    n integer;
BEGIN
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

    -- deals.claim_count <- deal_claims.deal_id
    -- deal_claims is the relation the trigger fires on. See Part 3 for the
    -- second, unwired claim table.
    UPDATE public.deals d
    SET claim_count = c.fresh
    FROM (
        SELECT d2.id, COALESCE(dc.cnt, 0)::int AS fresh
        FROM public.deals d2
        LEFT JOIN (
            SELECT deal_id, COUNT(*)::int AS cnt FROM public.deal_claims GROUP BY deal_id
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
$$;


-- =====================================
-- PART 2: FLOOR EVERY UNGUARDED DECREMENT
-- =====================================
-- Each function below previously ran `SET x = x - 1` with nothing stopping it at
-- zero. The IF ... IS NOT NULL wrappers some of them already carry guard against
-- a null foreign key, not against underflow. Increments are left alone except
-- where the target column is nullable, in which case COALESCE is added so the
-- counter starts from 0 instead of staying null.

CREATE OR REPLACE FUNCTION public.fn_change_posts_like_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE posts SET like_count = GREATEST(0, like_count - 1) WHERE id = OLD.post_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE posts SET like_count = like_count + 1 WHERE id = NEW.post_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_profiles_like_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles SET like_count = GREATEST(0, like_count - 1) WHERE id = OLD.profile_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles SET like_count = like_count + 1 WHERE id = NEW.profile_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_profiles_stash_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles SET stash_count = GREATEST(0, stash_count - 1) WHERE id = OLD.profile_id;
        UPDATE profiles SET restash_count = GREATEST(0, restash_count - 1) WHERE id = OLD.restash_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles SET stash_count = stash_count + 1 WHERE id = NEW.profile_id;
        UPDATE profiles SET restash_count = restash_count + 1 WHERE id = NEW.restash_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_follower_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles SET follower_count = GREATEST(0, follower_count - 1) WHERE id = OLD.followee_id;
        UPDATE profiles SET following_count = GREATEST(0, following_count - 1) WHERE id = OLD.follower_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles SET follower_count = follower_count + 1 WHERE id = NEW.followee_id;
        UPDATE profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- Not attached to any trigger today (fn_change_follower_count maintains both
-- sides), but floored for the same reason 20260105000001 floored its own legacy
-- function: so it is safe if something ever wires it up.
CREATE OR REPLACE FUNCTION public.fn_change_following_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles SET following_count = GREATEST(0, following_count - 1) WHERE id = OLD.follower_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_post_count_on_profiles()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.profile_id IS NOT NULL THEN
            UPDATE profiles SET post_count = GREATEST(0, post_count - 1) WHERE id = OLD.profile_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.profile_id IS NOT NULL THEN
            UPDATE profiles SET post_count = post_count + 1 WHERE id = NEW.profile_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_product_count_on_profiles()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.brand_id IS NOT NULL THEN
            UPDATE profiles SET product_count = GREATEST(0, COALESCE(product_count, 0) - 1) WHERE id = OLD.brand_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.brand_id IS NOT NULL THEN
            UPDATE profiles SET product_count = COALESCE(product_count, 0) + 1 WHERE id = NEW.brand_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_location_count_on_profile()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.brand_id IS NOT NULL THEN
            UPDATE profiles SET location_count = GREATEST(0, COALESCE(location_count, 0) - 1) WHERE id = OLD.brand_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.brand_id IS NOT NULL THEN
            UPDATE profiles SET location_count = COALESCE(location_count, 0) + 1 WHERE id = NEW.brand_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- 20260105000001 already floored this one, but production is running the
-- unfloored body -- something replaced it out of band after that migration was
-- applied. Restated here so the floor is actually present.
CREATE OR REPLACE FUNCTION public.fn_change_lists_product_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE lists SET updated_at = NOW(), product_count = GREATEST(0, product_count - 1) WHERE id = OLD.list_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE lists SET updated_at = NOW(), product_count = product_count + 1 WHERE id = NEW.list_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_subscription_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE lists
        SET subscription_count = COALESCE(subscription_count, 0) + 1
        WHERE id = NEW.list_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE lists
        SET subscription_count = GREATEST(0, COALESCE(subscription_count, 0) - 1)
        WHERE id = OLD.list_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_giveaway_entry_count_on_giveaway()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.giveaway_id IS NOT NULL THEN
            UPDATE giveaways SET entry_count = GREATEST(0, entry_count - 1) WHERE id = OLD.giveaway_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.giveaway_id IS NOT NULL THEN
            UPDATE giveaways SET entry_count = entry_count + 1 WHERE id = NEW.giveaway_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- This one is not only unfloored, it is broken: it writes to deals.claimed_deals,
-- which does not exist. public.claimed_deals is a TABLE, not a column on deals.
-- The only counter column on deals is claim_count, so that is what the trigger is
-- retargeted at. Nothing has hit this yet because deals and deal_claims are both
-- empty; the first claim would have raised
--   column "claimed_deals" of relation "deals" does not exist.
CREATE OR REPLACE FUNCTION public.fn_change_deal_count_on_deals()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.deal_id IS NOT NULL THEN
            UPDATE deals SET claim_count = GREATEST(0, COALESCE(claim_count, 0) - 1) WHERE id = OLD.deal_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.deal_id IS NOT NULL THEN
            UPDATE deals SET claim_count = COALESCE(claim_count, 0) + 1 WHERE id = NEW.deal_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- Left alone deliberately:
--   update_product_list_count, update_product_stash_count,
--   update_product_post_count, update_product_brand_count
--     -- these recompute with count(*) instead of decrementing, so they cannot
--        go negative and have nothing to floor.
--   fn_analytics_post -- increments posts.view_count and never decrements.
--   auto_pick_giveaway_winner -- assigns giveaways.winner_count, never decrements.


-- =====================================
-- PART 3: DEFINED BUT NOT EXECUTED
-- =====================================
-- giveaways.winner_count disagrees with the count of giveaway_entries.won on 37
-- of 103 giveaways (35 of them sitting at 0 while won entries exist; never the
-- other way round). auto_pick_giveaway_winner sets winner_count to the number of
-- entries it flipped in that one call, so entries marked won by any other route
-- -- an admin marking a winner by hand -- never reach the counter.
--
-- Recomputing it is probably right, but it changes a number admins already read
-- on 37 giveaways, and whether winner_count is meant to track "entries that won"
-- or "winners this function drew" is a product call, not a technical one. So the
-- repair is defined and left uncalled. To apply it:
--
--   SELECT public.recalculate_giveaway_winner_counts();
CREATE OR REPLACE FUNCTION public.recalculate_giveaway_winner_counts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    n integer;
BEGIN
    UPDATE public.giveaways g
    SET winner_count = c.fresh
    FROM (
        SELECT g2.id, COALESCE(w.cnt, 0)::int AS fresh
        FROM public.giveaways g2
        LEFT JOIN (
            SELECT giveaway_id, COUNT(*)::int AS cnt
            FROM public.giveaway_entries
            WHERE won
            GROUP BY giveaway_id
        ) w ON w.giveaway_id = g2.id
    ) c
    WHERE g.id = c.id AND g.winner_count IS DISTINCT FROM c.fresh;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END;
$$;


-- =====================================
-- PART 4: RUN THE REPAIR
-- =====================================
-- Unlike the archived legacy repairs, this one carries no Hybrid-specific data:
-- every value is derived from the source relations, so on a fresh bootstrap it
-- visits empty tables and changes nothing. It is idempotent and safe to rerun.
--
-- Run as a plain SELECT rather than a DO block so the per-counter row counts land
-- in the output instead of being swallowed as notices.
--
-- Dry-run against production inside BEGIN/ROLLBACK returned:
--   posts.like_count           527
--   lists.product_count          2
--   lists.subscription_count    24
--   all others                   0
SELECT * FROM public.recalculate_all_denormalized_counters();
