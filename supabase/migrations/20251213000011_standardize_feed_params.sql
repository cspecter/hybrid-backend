-- Standardize all feed helper parameters to p_public_id
-- This migration renames parameters in all feed functions to p_public_id for consistency.

-- ============================================================================
-- DROP EXISTING FUNCTIONS
-- ============================================================================

-- Drop get_feed_items (old signature)
DROP FUNCTION IF EXISTS public.get_feed_items(uuid, int, int);

-- Drop Profile Feeds (from previous migration)
DROP FUNCTION IF EXISTS public.get_profile_posts(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_lists(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_products(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_locations(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_stash(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_likes(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_following(text, int, int);
DROP FUNCTION IF EXISTS public.get_profile_subscription_lists(text, int, int);

-- Drop Product Feeds
DROP FUNCTION IF EXISTS public.get_product_posts(text, int, int);
DROP FUNCTION IF EXISTS public.get_product_lists(text, int, int);
DROP FUNCTION IF EXISTS public.get_product_giveaways(text, int, int);
DROP FUNCTION IF EXISTS public.get_product_deals(text, int, int);

-- Drop Location Feeds
DROP FUNCTION IF EXISTS public.get_location_posts(text, int, int);
DROP FUNCTION IF EXISTS public.get_location_lists(text, int, int);
DROP FUNCTION IF EXISTS public.get_location_deals(text, int, int);

-- Drop List Feeds
DROP FUNCTION IF EXISTS public.get_list_products(text, int, int);


-- ============================================================================
-- RECREATE FUNCTIONS WITH p_public_id
-- ============================================================================

-- 0. Main Feed
CREATE OR REPLACE FUNCTION public.get_feed_items(
    p_public_id text,
    p_offset int DEFAULT 0,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id uuid,
    rank double precision,
    total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
BEGIN
    -- Resolve profile_id from public_id (text)
    IF p_public_id IS NOT NULL THEN
        v_profile_id := public.resolve_profile_id(p_public_id);
    END IF;

    RETURN QUERY
    WITH relevant_posts AS (
        SELECT 
            p.id as internal_id,
            p.public_id,
            p.created_at,
            p.like_count,
            p.view_count,
            p.profile_id,
            -- Check if seen (only if user is logged in)
            CASE 
                WHEN v_profile_id IS NOT NULL THEN 
                    EXISTS (
                        SELECT 1 FROM public.analytics_posts ap 
                        WHERE ap.post_id = p.id AND ap.profile_id = v_profile_id
                    )
                ELSE FALSE 
            END as is_seen
        FROM public.posts p
        JOIN public.cloud_files cf ON p.file_id = cf.id
        WHERE 
            p.file_id IS NOT NULL
            AND cf.resource_type = 'video' -- Prioritize videos as requested
            AND (
                v_profile_id IS NULL OR (
                    -- Filter out posts from blocked users
                    NOT EXISTS (
                        SELECT 1 FROM public.profile_blocks pb 
                        WHERE pb.blocked_profile_id = p.profile_id AND pb.profile_id = v_profile_id
                    )
                    -- Filter out posts from the user themselves
                    AND p.profile_id != v_profile_id
                )
            )
    ),
    scored_posts AS (
        SELECT 
            rp.public_id,
            -- Priority 1: Unseen, Priority 2: Seen
            CASE 
                WHEN rp.is_seen THEN 2 
                ELSE 1 
            END as priority,
            -- Score calculation
            CASE 
                WHEN rp.is_seen THEN (random() * 100) -- Random score for seen posts (fallback)
                ELSE (EXTRACT(EPOCH FROM rp.created_at) / 86400) + (LN(rp.like_count + 1) * 2) + (random() * 0.5) -- Algo score for unseen
            END as score
        FROM relevant_posts rp
    ),
    total AS (
        SELECT count(*) as cnt FROM scored_posts
    )
    SELECT 
        sp.public_id as id,
        sp.score as rank,
        t.cnt as total_count
    FROM scored_posts sp
    CROSS JOIN total t
    ORDER BY sp.priority ASC, sp.score DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

-- 1. Profile Posts
CREATE OR REPLACE FUNCTION public.get_profile_posts(
    p_public_id text,
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
    v_target_id := public.resolve_profile_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, p.created_at
        FROM public.posts p
        WHERE p.profile_id = v_target_id
        AND p.status IN ('published', 'active')
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

-- 2. Profile Lists
CREATE OR REPLACE FUNCTION public.get_profile_lists(
    p_public_id text,
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
    v_target_id := public.resolve_profile_id(p_public_id);
    
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

-- 3. Profile Products (Brand)
CREATE OR REPLACE FUNCTION public.get_profile_products(
    p_public_id text,
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
    v_target_id := public.resolve_profile_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, p.created_at
        FROM public.product_brands pb
        JOIN public.products p ON pb.product_id = p.id
        WHERE pb.brand_id = v_target_id
        AND p.status IN ('published', 'active')
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

-- 4. Profile Locations (Brand)
CREATE OR REPLACE FUNCTION public.get_profile_locations(
    p_public_id text,
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
    v_target_id := public.resolve_profile_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT l.public_id, l.created_at
        FROM public.locations l
        WHERE l.brand_id = v_target_id
        AND l.status IN ('published', 'active')
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

-- 5. Profile Stash (Products)
CREATE OR REPLACE FUNCTION public.get_profile_stash(
    p_public_id text,
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
    v_target_id := public.resolve_profile_id(p_public_id);
    
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

-- 6. Profile Likes (Posts)
CREATE OR REPLACE FUNCTION public.get_profile_likes(
    p_public_id text,
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
    v_target_id := public.resolve_profile_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, l.created_at
        FROM public.likes l
        JOIN public.posts p ON l.post_id = p.id
        WHERE l.profile_id = v_target_id
        AND p.status IN ('published', 'active')
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

-- 7. Profile Following
CREATE OR REPLACE FUNCTION public.get_profile_following(
    p_public_id text,
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
    v_target_id := public.resolve_profile_id(p_public_id);
    
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

-- 8. Profile Subscription Lists
CREATE OR REPLACE FUNCTION public.get_profile_subscription_lists(
    p_public_id text,
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
    v_target_id := public.resolve_profile_id(p_public_id);
    
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

-- 9. Product Posts
CREATE OR REPLACE FUNCTION public.get_product_posts(
    p_public_id text,
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
    v_target_id := public.resolve_product_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, pp.created_at
        FROM public.posts_products pp
        JOIN public.posts p ON pp.post_id = p.id
        WHERE pp.product_id = v_target_id
        AND p.status IN ('published', 'active')
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

-- 10. Product Lists
CREATE OR REPLACE FUNCTION public.get_product_lists(
    p_public_id text,
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
    v_target_id := public.resolve_product_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT l.public_id, lp.created_at
        FROM public.lists_products lp
        JOIN public.lists l ON lp.list_id = l.id
        WHERE lp.product_id = v_target_id
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

-- 11. Product Giveaways
CREATE OR REPLACE FUNCTION public.get_product_giveaways(
    p_public_id text,
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
    v_target_id := public.resolve_product_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT g.public_id, g.created_at
        FROM public.giveaways g
        WHERE g.product_id = v_target_id
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

-- 12. Product Deals
CREATE OR REPLACE FUNCTION public.get_product_deals(
    p_public_id text,
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
    v_target_id := public.resolve_product_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT d.public_id, d.created_at
        FROM public.deals d
        WHERE d.product_id = v_target_id
        AND (d.expiration_date IS NULL OR d.expiration_date > now())
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

-- 13. Location Posts
CREATE OR REPLACE FUNCTION public.get_location_posts(
    p_public_id text,
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
    v_target_id := public.resolve_location_id(p_public_id);
    
    RETURN QUERY
    WITH location_employees AS (
        SELECT profile_id 
        FROM public.location_employees 
        WHERE location_id = v_target_id 
        AND is_approved = true
    ),
    filtered_items AS (
        SELECT p.public_id, p.created_at
        FROM public.posts p
        JOIN location_employees le ON p.profile_id = le.profile_id
        WHERE p.status IN ('published', 'active')
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

-- 14. Location Lists
CREATE OR REPLACE FUNCTION public.get_location_lists(
    p_public_id text,
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
    v_target_id := public.resolve_location_id(p_public_id);
    
    RETURN QUERY
    WITH location_employees AS (
        SELECT profile_id 
        FROM public.location_employees 
        WHERE location_id = v_target_id 
        AND is_approved = true
    ),
    filtered_items AS (
        SELECT l.public_id, l.created_at
        FROM public.lists l
        JOIN location_employees le ON l.profile_id = le.profile_id
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

-- 15. Location Deals
CREATE OR REPLACE FUNCTION public.get_location_deals(
    p_public_id text,
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
    v_target_id := public.resolve_location_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT d.public_id, d.created_at
        FROM public.deals_locations dl
        JOIN public.deals d ON dl.deal_id = d.id
        WHERE dl.location_id = v_target_id
        AND (d.expiration_date IS NULL OR d.expiration_date > now())
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

-- 16. List Products
CREATE OR REPLACE FUNCTION public.get_list_products(
    p_public_id text,
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
    v_target_id := public.resolve_list_id(p_public_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, lp.created_at
        FROM public.lists_products lp
        JOIN public.products p ON lp.product_id = p.id
        WHERE lp.list_id = v_target_id
        AND p.status IN ('published', 'active')
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

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_feed_items(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_posts(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_products(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_locations(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_stash(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_likes(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_following(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_subscription_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_posts(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_giveaways(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_deals(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_location_posts(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_location_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_location_deals(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_list_products(text, int, int) TO authenticated;
