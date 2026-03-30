-- Update Top Posts RPC to strictly use last 3 months as fallback
-- This addresses the requirement: "If there is less than 20, then pull from the last 3 months."
-- Previously it fell back to all time.

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
    
    -- If not enough, get posts from last 3 months (excluding ones already found)
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
        AND created_at > (now() - interval '3 months')
        ORDER BY like_count DESC
        LIMIT (limit_count - result_count);
    END IF;
END;
$$;
