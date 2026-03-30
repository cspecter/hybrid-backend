-- Rename p_profile_id to p_user_id in feed helpers
-- This migration re-defines the functions with the new parameter name.

-- Drop existing functions to allow parameter renaming
DROP FUNCTION IF EXISTS public.get_profile_posts(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_lists(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_products(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_locations(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_stash(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_likes(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_following(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_subscription_lists(text, int, int);

-- From 08
CREATE OR REPLACE FUNCTION public.get_profile_posts(
    p_user_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_profile_id(p_user_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, p.created_at
        FROM public.posts p
        WHERE p.profile_id = v_target_id
        AND p.status = 'published'
    ),
    total AS (SELECT count(*) as cnt FROM filtered_items)
    SELECT 
        fi.public_id as id,
        EXTRACT(EPOCH FROM fi.created_at)::double precision as rank,
        t.cnt as total_count
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_lists(
    p_user_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_profile_id(p_user_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT l.public_id, l.created_at
        FROM public.lists l
        WHERE l.profile_id = v_target_id
    ),
    total AS (SELECT count(*) as cnt FROM filtered_items)
    SELECT 
        fi.public_id as id,
        EXTRACT(EPOCH FROM fi.created_at)::double precision as rank,
        t.cnt as total_count
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_products(
    p_user_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_profile_id(p_user_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, p.created_at
        FROM public.product_brands pb
        JOIN public.products p ON pb.product_id = p.id
        WHERE pb.brand_id = v_target_id
        AND p.status = 'published'
    ),
    total AS (SELECT count(*) as cnt FROM filtered_items)
    SELECT 
        fi.public_id as id,
        EXTRACT(EPOCH FROM fi.created_at)::double precision as rank,
        t.cnt as total_count
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_locations(
    p_user_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_profile_id(p_user_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT l.public_id, l.created_at
        FROM public.locations l
        WHERE l.brand_id = v_target_id
        AND l.status = 'published'
    ),
    total AS (SELECT count(*) as cnt FROM filtered_items)
    SELECT 
        fi.public_id as id,
        EXTRACT(EPOCH FROM fi.created_at)::double precision as rank,
        t.cnt as total_count
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_stash(
    p_user_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_profile_id(p_user_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, s.created_at
        FROM public.stash s
        JOIN public.products p ON s.product_id = p.id
        WHERE s.profile_id = v_target_id
    ),
    total AS (SELECT count(*) as cnt FROM filtered_items)
    SELECT 
        fi.public_id as id,
        EXTRACT(EPOCH FROM fi.created_at)::double precision as rank,
        t.cnt as total_count
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_likes(
    p_user_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_profile_id(p_user_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, l.created_at
        FROM public.likes l
        JOIN public.posts p ON l.post_id = p.id
        WHERE l.profile_id = v_target_id
        AND p.status = 'published'
    ),
    total AS (SELECT count(*) as cnt FROM filtered_items)
    SELECT 
        fi.public_id as id,
        EXTRACT(EPOCH FROM fi.created_at)::double precision as rank,
        t.cnt as total_count
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

-- From 09
CREATE OR REPLACE FUNCTION public.get_profile_following(
    p_user_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_profile_id(p_user_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, r.created_at
        FROM public.relationships r
        JOIN public.profiles p ON r.followee_id = p.id
        WHERE r.follower_id = v_target_id
    ),
    total AS (SELECT count(*) as cnt FROM filtered_items)
    SELECT 
        fi.public_id as id,
        EXTRACT(EPOCH FROM fi.created_at)::double precision as rank,
        t.cnt as total_count
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_profile_subscription_lists(
    p_user_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_target_id integer;
BEGIN
    v_target_id := public.resolve_profile_id(p_user_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT l.public_id, sl.created_at
        FROM public.subscriptions_lists sl
        JOIN public.lists l ON sl.list_id = l.id
        WHERE sl.profile_id = v_target_id
    ),
    total AS (SELECT count(*) as cnt FROM filtered_items)
    SELECT 
        fi.public_id as id,
        EXTRACT(EPOCH FROM fi.created_at)::double precision as rank,
        t.cnt as total_count
    FROM filtered_items fi
    CROSS JOIN total t
    ORDER BY fi.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

-- Re-grant permissions (just in case)
GRANT EXECUTE ON FUNCTION public.get_profile_posts(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_products(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_locations(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_stash(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_likes(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_following(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_subscription_lists(text, int, int) TO authenticated;
