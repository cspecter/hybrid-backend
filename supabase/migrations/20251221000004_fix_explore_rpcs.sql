-- Fix Explore RPCs with Fallback Logic

-- 1. Top Creators (Most follows + likes)
CREATE OR REPLACE FUNCTION public.get_top_creators(limit_count integer DEFAULT 10)
RETURNS SETOF public.profiles
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    result_count integer;
BEGIN
    -- Try to get top creators based on engagement
    RETURN QUERY
    SELECT p.*
    FROM public.profiles p
    LEFT JOIN (
        SELECT profile_id, SUM(like_count) as total_likes
        FROM public.posts
        GROUP BY profile_id
    ) post_likes ON p.id = post_likes.profile_id
    ORDER BY (p.follower_count + COALESCE(post_likes.total_likes, 0)) DESC
    LIMIT limit_count;
    
    GET DIAGNOSTICS result_count = ROW_COUNT;
    
    -- If not enough results, fill with random profiles
    IF result_count < limit_count THEN
        RETURN QUERY
        SELECT *
        FROM public.profiles
        WHERE id NOT IN (
            SELECT id FROM (
                SELECT p.id
                FROM public.profiles p
                LEFT JOIN (
                    SELECT profile_id, SUM(like_count) as total_likes
                    FROM public.posts
                    GROUP BY profile_id
                ) post_likes ON p.id = post_likes.profile_id
                ORDER BY (p.follower_count + COALESCE(post_likes.total_likes, 0)) DESC
                LIMIT limit_count
            ) as existing
        )
        ORDER BY created_at DESC
        LIMIT (limit_count - result_count);
    END IF;
END;
$$;

-- 2. New Releases (Products released in last month, fallback to recent)
CREATE OR REPLACE FUNCTION public.get_new_releases(limit_count integer DEFAULT 10)
RETURNS SETOF public.products
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    result_count integer;
BEGIN
    -- Try to get products from last month
    RETURN QUERY
    SELECT *
    FROM public.products
    WHERE release_date > (now() - interval '1 month')
    ORDER BY release_date ASC
    LIMIT limit_count;
    
    GET DIAGNOSTICS result_count = ROW_COUNT;
    
    -- If not enough, get most recent products overall
    IF result_count < limit_count THEN
        RETURN QUERY
        SELECT *
        FROM public.products
        WHERE id NOT IN (
            SELECT id FROM (
                SELECT id
                FROM public.products
                WHERE release_date > (now() - interval '1 month')
                ORDER BY release_date ASC
                LIMIT limit_count
            ) as existing
        )
        ORDER BY created_at DESC
        LIMIT (limit_count - result_count);
    END IF;
END;
$$;

-- 3. Top Posts (Most liked recently, fallback to most liked overall)
CREATE OR REPLACE FUNCTION public.get_top_posts(limit_count integer DEFAULT 10)
RETURNS SETOF public.posts
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    result_count integer;
BEGIN
    -- Try to get top posts from last month
    RETURN QUERY
    SELECT *
    FROM public.posts
    WHERE created_at > (now() - interval '1 month')
    ORDER BY like_count DESC
    LIMIT limit_count;
    
    GET DIAGNOSTICS result_count = ROW_COUNT;
    
    -- If not enough, get most liked posts overall
    IF result_count < limit_count THEN
        RETURN QUERY
        SELECT *
        FROM public.posts
        WHERE id NOT IN (
            SELECT id FROM (
                SELECT id
                FROM public.posts
                WHERE created_at > (now() - interval '1 month')
                ORDER BY like_count DESC
                LIMIT limit_count
            ) as existing
        )
        ORDER BY like_count DESC
        LIMIT (limit_count - result_count);
    END IF;
END;
$$;

-- 4. Top Budtenders (Role = 'budtender', fallback to active users)
CREATE OR REPLACE FUNCTION public.get_top_budtenders(limit_count integer DEFAULT 10)
RETURNS SETOF public.profiles
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    result_count integer;
BEGIN
    -- Try to get budtenders
    RETURN QUERY
    SELECT p.*
    FROM public.profiles p
    JOIN public.location_employees le ON p.id = le.profile_id
    LEFT JOIN (
        SELECT profile_id, SUM(like_count) as total_likes
        FROM public.posts
        GROUP BY profile_id
    ) post_likes ON p.id = post_likes.profile_id
    WHERE le.role = 'budtender'
    ORDER BY (p.follower_count + COALESCE(post_likes.total_likes, 0)) DESC
    LIMIT limit_count;
    
    GET DIAGNOSTICS result_count = ROW_COUNT;
    
    -- If not enough, fill with other profiles (e.g. most active)
    IF result_count < limit_count THEN
        RETURN QUERY
        SELECT *
        FROM public.profiles
        WHERE id NOT IN (
            SELECT id FROM (
                SELECT p.id
                FROM public.profiles p
                JOIN public.location_employees le ON p.id = le.profile_id
                WHERE le.role = 'budtender'
                LIMIT limit_count
            ) as existing
        )
        ORDER BY follower_count DESC
        LIMIT (limit_count - result_count);
    END IF;
END;
$$;

-- 5. Popular Brands (Most followed/liked brands, fallback to most followed profiles)
CREATE OR REPLACE FUNCTION public.get_popular_brands(limit_count integer DEFAULT 10)
RETURNS SETOF public.profiles
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    result_count integer;
BEGIN
    -- Try to get brands (assuming is_brand boolean or similar, but schema doesn't show it clearly on profiles)
    -- Assuming brands are profiles that own products or have 'brand' role if applicable.
    -- For now, let's assume profiles with products are brands.
    RETURN QUERY
    SELECT p.id, p.public_id, p.auth_id, p.profile_type, p.username, p.display_name, p.slug, p.bio, p.avatar_id, p.banner_id, p.desktop_banner_id, p.role_id, p.status, p.is_verified, p.is_private, p.email, p.phone, p.contact_email, p.contact_phone, p.website, p.social_links, p.business_info, p.home_location_id, p.last_location_id, p.birthday, p.founded_date, p.follower_count, p.following_count, p.post_count, p.like_count, p.stash_count, p.product_count, p.location_count, p.created_at, p.updated_at, p.last_seen_at, p.restash_count, p.fts_vector
    FROM public.profiles p
    -- Use product_brands junction table to find profiles that are brands
    JOIN public.product_brands pb ON p.id = pb.brand_id
    GROUP BY p.id
    ORDER BY p.follower_count DESC
    LIMIT limit_count;
    
    GET DIAGNOSTICS result_count = ROW_COUNT;
    
    -- If not enough, fill with most followed profiles
    IF result_count < limit_count THEN
        RETURN QUERY
        SELECT *
        FROM public.profiles
        WHERE id NOT IN (
            SELECT id FROM (
                SELECT p.id
                FROM public.profiles p
                JOIN public.product_brands pb ON p.id = pb.brand_id
                GROUP BY p.id
                LIMIT limit_count
            ) as existing
        )
        ORDER BY follower_count DESC
        LIMIT (limit_count - result_count);
    END IF;
END;
$$;
