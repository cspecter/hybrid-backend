-- Entity Feed Helpers
-- Provides paginated access to related entities (Posts, Lists, Products, etc.)
-- Returns format compatible with get_feed_items: (id uuid, rank double precision, total_count bigint)

-- ============================================================================
-- ID RESOLUTION HELPERS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.resolve_product_id(p_input text)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_uuid uuid;
    v_id integer;
BEGIN
    IF p_input ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_uuid := p_input::uuid;
        SELECT id INTO v_id FROM public.products WHERE public_id = v_uuid LIMIT 1;
        RETURN v_id;
    ELSE
        BEGIN
            RETURN p_input::integer;
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_location_id(p_input text)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_uuid uuid;
    v_id integer;
BEGIN
    IF p_input ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_uuid := p_input::uuid;
        SELECT id INTO v_id FROM public.locations WHERE public_id = v_uuid LIMIT 1;
        RETURN v_id;
    ELSE
        BEGIN
            RETURN p_input::integer;
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_list_id(p_input text)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_uuid uuid;
    v_id integer;
BEGIN
    IF p_input ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_uuid := p_input::uuid;
        SELECT id INTO v_id FROM public.lists WHERE public_id = v_uuid LIMIT 1;
        RETURN v_id;
    ELSE
        BEGIN
            RETURN p_input::integer;
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    END IF;
END;
$$;

-- ============================================================================
-- PROFILE FEEDS
-- ============================================================================

-- 1. Profile Posts
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
        AND p.status = 'published' -- Assuming we only want published posts
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

-- 3. Profile Products (Brand)
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

-- 4. Profile Locations (Brand)
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

-- 5. Profile Stash (Products)
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

-- 6. Profile Likes (Posts)
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

-- ============================================================================
-- PRODUCT FEEDS
-- ============================================================================

-- 7. Product Posts (Tagged)
CREATE OR REPLACE FUNCTION public.get_product_posts(
    p_product_id text,
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
    v_target_id := public.resolve_product_id(p_product_id);
    
    RETURN QUERY
    WITH filtered_items AS (
        SELECT p.public_id, pp.created_at
        FROM public.posts_products pp
        JOIN public.posts p ON pp.post_id = p.id
        WHERE pp.product_id = v_target_id
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

-- 8. Product Lists
CREATE OR REPLACE FUNCTION public.get_product_lists(
    p_product_id text,
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
    v_target_id := public.resolve_product_id(p_product_id);
    
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

-- ============================================================================
-- LOCATION FEEDS
-- ============================================================================

-- 9. Location Posts (from employees)
CREATE OR REPLACE FUNCTION public.get_location_posts(
    p_location_id text,
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
    v_target_id := public.resolve_location_id(p_location_id);
    
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
        WHERE p.status = 'published'
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

-- 10. Location Lists (from employees)
CREATE OR REPLACE FUNCTION public.get_location_lists(
    p_location_id text,
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
    v_target_id := public.resolve_location_id(p_location_id);
    
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

-- ============================================================================
-- SUGGESTED HELPERS
-- ============================================================================

-- 11. Product Giveaways
CREATE OR REPLACE FUNCTION public.get_product_giveaways(
    p_product_id text,
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
    v_target_id := public.resolve_product_id(p_product_id);
    
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
    p_product_id text,
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
    v_target_id := public.resolve_product_id(p_product_id);
    
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

-- 13. Location Deals
CREATE OR REPLACE FUNCTION public.get_location_deals(
    p_location_id text,
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
    v_target_id := public.resolve_location_id(p_location_id);
    
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

-- Grant access to all new functions
GRANT EXECUTE ON FUNCTION public.resolve_product_id(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_location_id(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_list_id(text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_profile_posts(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_products(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_locations(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_stash(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_likes(text, int, int) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_product_posts(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_giveaways(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_product_deals(text, int, int) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_location_posts(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_location_lists(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_location_deals(text, int, int) TO authenticated;
