-- Ensure Top Creators only returns user profiles (exclude brands role_id = 10)
CREATE OR REPLACE FUNCTION public.get_top_creators(limit_count integer DEFAULT 10)
RETURNS SETOF public.profiles
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    result_count integer;
BEGIN
    -- Primary ranking: engagement score (followers + post likes), users only.
    RETURN QUERY
    SELECT p.*
    FROM public.profiles p
    LEFT JOIN (
        SELECT profile_id, SUM(like_count) AS total_likes
        FROM public.posts
        GROUP BY profile_id
    ) post_likes ON p.id = post_likes.profile_id
    WHERE p.role_id IS DISTINCT FROM 10
    ORDER BY
        (p.follower_count + COALESCE(post_likes.total_likes, 0)) DESC,
        p.follower_count DESC,
        p.created_at DESC
    LIMIT limit_count;

    GET DIAGNOSTICS result_count = ROW_COUNT;

    -- Fallback fill: newest user profiles not already selected.
    IF result_count < limit_count THEN
        RETURN QUERY
        SELECT *
        FROM public.profiles
        WHERE role_id IS DISTINCT FROM 10
          AND id NOT IN (
              SELECT id FROM (
                  SELECT p.id
                  FROM public.profiles p
                  LEFT JOIN (
                      SELECT profile_id, SUM(like_count) AS total_likes
                      FROM public.posts
                      GROUP BY profile_id
                  ) post_likes ON p.id = post_likes.profile_id
                  WHERE p.role_id IS DISTINCT FROM 10
                  ORDER BY
                      (p.follower_count + COALESCE(post_likes.total_likes, 0)) DESC,
                      p.follower_count DESC,
                      p.created_at DESC
                  LIMIT limit_count
              ) AS existing
          )
        ORDER BY created_at DESC
        LIMIT (limit_count - result_count);
    END IF;
END;
$$;
