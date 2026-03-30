-- Fix Feed Sorting to strictly use created_at
-- Removes the complex scoring algorithm and sorts strictly by created_at DESC
-- while maintaining the unseen/seen priority.

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
            rp.created_at,
            -- Priority 1: Unseen, Priority 2: Seen
            CASE 
                WHEN rp.is_seen THEN 2 
                ELSE 1 
            END as priority
        FROM relevant_posts rp
    ),
    total AS (
        SELECT count(*) as cnt FROM scored_posts
    )
    SELECT 
        sp.public_id as id,
        -- Return epoch as rank for compatibility, though we sort by created_at directly
        EXTRACT(EPOCH FROM sp.created_at)::double precision as rank,
        t.cnt as total_count
    FROM scored_posts sp
    CROSS JOIN total t
    ORDER BY sp.priority ASC, sp.created_at DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_feed_items(text, int, int) TO authenticated;
