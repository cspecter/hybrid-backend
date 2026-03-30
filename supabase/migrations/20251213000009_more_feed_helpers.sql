-- Additional Entity Feed Helpers
-- Adds support for Profile Following, Profile Subscriptions, and List Products

-- 14. Profile Following (Profiles the user follows)
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

-- 15. Profile Subscription Lists (Lists the user has saved)
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

-- 16. List Products (Products contained in a list)
CREATE OR REPLACE FUNCTION public.get_list_products(
    p_list_id text,
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
    v_target_id := public.resolve_list_id(p_list_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, lp.created_at
        FROM public.lists_products lp
        JOIN public.products p ON lp.product_id = p.id
        WHERE lp.list_id = v_target_id
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

GRANT EXECUTE ON FUNCTION public.get_profile_following(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_subscription_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_list_products(text, int, int) TO authenticated;
