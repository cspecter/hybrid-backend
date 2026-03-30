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
                    -- ALLOW viewing own posts for now (removed p.profile_id != v_profile_id check)
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
            
            -- Time Bucket Score (Base Score)
            -- This ensures strict prioritization of time windows
            (
                CASE
                    WHEN rp.created_at > (now() - INTERVAL '1 week') THEN 1000000
                    WHEN rp.created_at > (now() - INTERVAL '1 month') THEN 800000
                    WHEN rp.created_at > (now() - INTERVAL '3 months') THEN 600000
                    WHEN rp.created_at > (now() - INTERVAL '1 year') THEN 400000
                    ELSE 200000
                END 
            )
            + 
            -- Engagement Score (Add to base)
            -- Logarithmic scale for likes to prevent massive outliers from jumping buckets
            -- (Max realistic bonus is ~200 points, well within the 200,000 bucket gap)
            (LN(rp.like_count + 1) * 10) 
            +
            -- Small recency boost within the bucket (0-10 points)
            -- Helps newer videos within the same bucket float up slightly
            (EXTRACT(EPOCH FROM rp.created_at) / 1000000000)
            + 
            -- Random factor for variety (0-5 points)
            (random() * 5)
            as score
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