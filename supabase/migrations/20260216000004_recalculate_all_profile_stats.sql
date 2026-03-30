-- Recalculate all denormalized counters on public.profiles.
-- This is intended for one-time repair and can be rerun safely.

-- Full-table recalculation function
CREATE OR REPLACE FUNCTION public.recalculate_all_profile_stats()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    updated_rows integer := 0;
BEGIN
    WITH
    follower_counts AS (
        SELECT followee_id AS profile_id, COUNT(*)::int AS cnt
        FROM public.relationships
        GROUP BY followee_id
    ),
    following_counts AS (
        SELECT follower_id AS profile_id, COUNT(*)::int AS cnt
        FROM public.relationships
        GROUP BY follower_id
    ),
    post_counts AS (
        SELECT profile_id, COUNT(*)::int AS cnt
        FROM public.posts
        GROUP BY profile_id
    ),
    like_counts AS (
        SELECT profile_id, COUNT(*)::int AS cnt
        FROM public.likes
        GROUP BY profile_id
    ),
    stash_counts AS (
        SELECT profile_id, COUNT(*)::int AS cnt
        FROM public.stash
        GROUP BY profile_id
    ),
    restash_counts AS (
        SELECT restash_id AS profile_id, COUNT(*)::int AS cnt
        FROM public.stash
        WHERE restash_id IS NOT NULL
        GROUP BY restash_id
    ),
    product_counts AS (
        SELECT brand_id AS profile_id, COUNT(DISTINCT product_id)::int AS cnt
        FROM public.product_brands
        GROUP BY brand_id
    ),
    location_counts AS (
        SELECT brand_id AS profile_id, COUNT(*)::int AS cnt
        FROM public.locations
        GROUP BY brand_id
    ),
    computed AS (
        SELECT
            p.id,
            COALESCE(fc.cnt, 0) AS follower_count,
            COALESCE(fgc.cnt, 0) AS following_count,
            COALESCE(pc.cnt, 0) AS post_count,
            COALESCE(lc.cnt, 0) AS like_count,
            COALESCE(sc.cnt, 0) AS stash_count,
            COALESCE(rsc.cnt, 0) AS restash_count,
            COALESCE(prc.cnt, 0) AS product_count,
            COALESCE(loc.cnt, 0) AS location_count
        FROM public.profiles p
        LEFT JOIN follower_counts fc ON fc.profile_id = p.id
        LEFT JOIN following_counts fgc ON fgc.profile_id = p.id
        LEFT JOIN post_counts pc ON pc.profile_id = p.id
        LEFT JOIN like_counts lc ON lc.profile_id = p.id
        LEFT JOIN stash_counts sc ON sc.profile_id = p.id
        LEFT JOIN restash_counts rsc ON rsc.profile_id = p.id
        LEFT JOIN product_counts prc ON prc.profile_id = p.id
        LEFT JOIN location_counts loc ON loc.profile_id = p.id
    )
    UPDATE public.profiles p
    SET
        follower_count = c.follower_count,
        following_count = c.following_count,
        post_count = c.post_count,
        like_count = c.like_count,
        stash_count = c.stash_count,
        restash_count = c.restash_count,
        product_count = c.product_count,
        location_count = c.location_count
    FROM computed c
    WHERE p.id = c.id;

    GET DIAGNOSTICS updated_rows = ROW_COUNT;
    RETURN updated_rows;
END;
$$;

-- Single-profile recalculation function (expanded to cover all counters).
CREATE OR REPLACE FUNCTION public.recalculate_profile_stats(target_public_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    target_id INTEGER;
BEGIN
    SELECT id INTO target_id
    FROM public.profiles
    WHERE public_id = target_public_id;

    IF target_id IS NULL THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    UPDATE public.profiles
    SET
        follower_count = (SELECT COUNT(*) FROM public.relationships WHERE followee_id = target_id),
        following_count = (SELECT COUNT(*) FROM public.relationships WHERE follower_id = target_id),
        post_count = (SELECT COUNT(*) FROM public.posts WHERE profile_id = target_id),
        like_count = (SELECT COUNT(*) FROM public.likes WHERE profile_id = target_id),
        stash_count = (SELECT COUNT(*) FROM public.stash WHERE profile_id = target_id),
        restash_count = (SELECT COUNT(*) FROM public.stash WHERE restash_id = target_id),
        product_count = (SELECT COUNT(DISTINCT product_id) FROM public.product_brands WHERE brand_id = target_id),
        location_count = (SELECT COUNT(*) FROM public.locations WHERE brand_id = target_id)
    WHERE id = target_id;
END;
$$;

-- Run once on migration apply to repair existing data.
SELECT public.recalculate_all_profile_stats();
