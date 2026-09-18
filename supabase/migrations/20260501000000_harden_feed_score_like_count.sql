-- Harden the home feed scoring function against legacy negative/null counts.
-- Some production rows have like_count <= -1, which makes LN(like_count + 1)
-- invalid and causes the whole feed RPC to fail.

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
    IF p_public_id IS NOT NULL THEN
        v_profile_id := public.resolve_profile_id(p_public_id);
    END IF;

    RETURN QUERY
    WITH relevant_posts AS (
        SELECT
            p.id AS internal_id,
            p.public_id,
            p.created_at,
            COALESCE(p.like_count, 0) AS like_count,
            p.view_count,
            p.profile_id,
            CASE
                WHEN v_profile_id IS NOT NULL THEN
                    EXISTS (
                        SELECT 1
                        FROM public.analytics_posts ap
                        WHERE ap.post_id = p.id AND ap.profile_id = v_profile_id
                    )
                ELSE FALSE
            END AS is_seen
        FROM public.posts p
        JOIN public.cloud_files cf ON p.file_id = cf.id
        WHERE
            p.file_id IS NOT NULL
            AND (
                cf.resource_type IS NULL
                OR cf.resource_type IN ('video', 'image')
            )
            AND (
                v_profile_id IS NULL OR (
                    NOT EXISTS (
                        SELECT 1
                        FROM public.profile_blocks pb
                        WHERE pb.blocked_profile_id = p.profile_id
                          AND pb.profile_id = v_profile_id
                    )
                )
            )
    ),
    scored_posts AS (
        SELECT
            rp.public_id,
            CASE
                WHEN rp.is_seen THEN 2
                ELSE 1
            END AS priority,
            (
                CASE
                    WHEN rp.created_at > (now() - INTERVAL '1 week') THEN 1000000
                    WHEN rp.created_at > (now() - INTERVAL '1 month') THEN 800000
                    WHEN rp.created_at > (now() - INTERVAL '3 months') THEN 600000
                    WHEN rp.created_at > (now() - INTERVAL '1 year') THEN 400000
                    ELSE 200000
                END
            )
            + (LN(GREATEST(rp.like_count, 0) + 1) * 10)
            + (EXTRACT(EPOCH FROM rp.created_at) / 1000000000)
            + (random() * 5) AS score
        FROM relevant_posts rp
    ),
    total AS (
        SELECT count(*) AS cnt FROM scored_posts
    )
    SELECT
        sp.public_id AS id,
        sp.score AS rank,
        t.cnt AS total_count
    FROM scored_posts sp
    CROSS JOIN total t
    ORDER BY sp.priority ASC, sp.score DESC
    OFFSET p_offset
    LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_feed_items(text, int, int) TO authenticated;
