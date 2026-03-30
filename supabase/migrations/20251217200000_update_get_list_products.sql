-- Update get_list_products to show all products regardless of status
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
        -- Removed status check to allow list owners (and others) to see all items in the list
        -- AND p.status = 'published'
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
