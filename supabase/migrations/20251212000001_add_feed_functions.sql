-- Add feed functions
-- Ported from old_remote_schema.sql and adapted for new schema

-- Function to get feed items (public_ids) for a user
-- Replaces get_feed_items(p_uid uuid)
CREATE OR REPLACE FUNCTION public.get_feed_items(p_auth_id uuid)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    post_public_ids uuid[];
    min_posts_needed CONSTANT int := 30;
BEGIN
    -- Get profile_id from auth_id
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = p_auth_id;
    
    IF v_profile_id IS NULL THEN
        RETURN '{}'::uuid[];
    END IF;

    -- Create a temporary table to hold all unseen post candidates.
    -- This is more efficient than running multiple large queries.
    CREATE TEMP TABLE unseen_posts AS
    SELECT p.public_id, p.created_at
    FROM public.posts AS p
    LEFT JOIN public.analytics_posts AS ap ON p.id = ap.post_id AND ap.profile_id = v_profile_id
    LEFT JOIN public.profile_blocks AS pb ON p.profile_id = pb.blocked_profile_id AND pb.profile_id = v_profile_id
    WHERE p.file_id IS NOT NULL    -- Ensures it's a media post
      AND ap.post_id IS NULL       -- Filters out seen posts
      AND pb.blocked_profile_id IS NULL; -- Filters out blocked users

    -- Tier 1: Try to get posts from the last 1 month.
    SELECT array_agg(public_id) INTO post_public_ids FROM (
        SELECT public_id FROM unseen_posts
        WHERE created_at >= now() - interval '1 MONTH'
        ORDER BY random()
        LIMIT min_posts_needed
    ) as sub;

    IF coalesce(array_length(post_public_ids, 1), 0) >= min_posts_needed THEN
        DROP TABLE unseen_posts;
        RETURN post_public_ids;
    END IF;

    -- Tier 2: If not, try to get posts from the last 3 months.
    SELECT array_agg(public_id) INTO post_public_ids FROM (
        SELECT public_id FROM unseen_posts
        WHERE created_at >= now() - interval '3 MONTH'
        ORDER BY random()
        LIMIT min_posts_needed
    ) as sub;

    IF coalesce(array_length(post_public_ids, 1), 0) >= min_posts_needed THEN
        DROP TABLE unseen_posts;
        RETURN post_public_ids;
    END IF;

    -- Tier 3: If not, try to get posts from the last 6 months.
    SELECT array_agg(public_id) INTO post_public_ids FROM (
        SELECT public_id FROM unseen_posts
        WHERE created_at >= now() - interval '6 MONTH'
        ORDER BY random()
        LIMIT min_posts_needed
    ) as sub;

    IF coalesce(array_length(post_public_ids, 1), 0) >= min_posts_needed THEN
        DROP TABLE unseen_posts;
        RETURN post_public_ids;
    END IF;

    -- Tier 4: If still not enough, get any posts regardless of date.
    SELECT array_agg(public_id) INTO post_public_ids FROM (
        SELECT public_id FROM unseen_posts
        ORDER BY random()
        LIMIT min_posts_needed
    ) as sub;

    DROP TABLE unseen_posts;
    RETURN coalesce(post_public_ids, '{}'::uuid[]);
END;
$$;

ALTER FUNCTION public.get_feed_items(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_feed_items(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_feed_items(uuid) TO service_role;

-- Function to get feed (legacy wrapper or alternative)
-- Replaces get_feed(uid text, ids text[])
CREATE OR REPLACE FUNCTION public.get_feed(p_uid text, p_exclude_ids text[] DEFAULT '{}'::text[])
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_auth_id uuid;
    post_public_ids text[];
    min_posts_needed CONSTANT int := 30;
    exclude_uuids uuid[];
BEGIN
    -- Try to cast p_uid to uuid, if fails assume it is not a valid auth id
    BEGIN
        v_auth_id := p_uid::uuid;
    EXCEPTION WHEN OTHERS THEN
        RETURN '{}'::text[];
    END;

    -- Get profile_id
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = v_auth_id;
    
    IF v_profile_id IS NULL THEN
        RETURN '{}'::text[];
    END IF;

    -- Convert exclude ids to uuid array
    BEGIN
        exclude_uuids := p_exclude_ids::uuid[];
    EXCEPTION WHEN OTHERS THEN
        exclude_uuids := '{}'::uuid[];
    END;

    -- Create a temporary table to hold all unseen post candidates.
    CREATE TEMP TABLE unseen_posts_feed AS
    SELECT p.public_id, p.created_at
    FROM public.posts AS p
    LEFT JOIN public.analytics_posts AS ap ON p.id = ap.post_id AND ap.profile_id = v_profile_id
    LEFT JOIN public.profile_blocks AS pb ON p.profile_id = pb.blocked_profile_id AND pb.profile_id = v_profile_id
    WHERE p.file_id IS NOT NULL    -- Ensures it's a media post
      AND ap.post_id IS NULL       -- Filters out seen posts
      AND pb.blocked_profile_id IS NULL -- Filters out blocked users
      AND (exclude_uuids IS NULL OR NOT (p.public_id = ANY(exclude_uuids)));

    -- Tier 1: Last 1 week (matching original get_feed logic)
    SELECT array_agg(public_id::text) INTO post_public_ids FROM (
        SELECT public_id FROM unseen_posts_feed
        WHERE created_at >= now() - interval '1 WEEK'
        ORDER BY random()
        LIMIT min_posts_needed
    ) as sub;

    IF coalesce(array_length(post_public_ids, 1), 0) >= min_posts_needed THEN
        DROP TABLE unseen_posts_feed;
        RETURN post_public_ids;
    END IF;

    -- Tier 2: Last 1 month
    SELECT array_agg(public_id::text) INTO post_public_ids FROM (
        SELECT public_id FROM unseen_posts_feed
        WHERE created_at >= now() - interval '1 MONTH'
        ORDER BY random()
        LIMIT min_posts_needed
    ) as sub;

    IF coalesce(array_length(post_public_ids, 1), 0) >= min_posts_needed THEN
        DROP TABLE unseen_posts_feed;
        RETURN post_public_ids;
    END IF;

    -- Tier 3: Any time
    SELECT array_agg(public_id::text) INTO post_public_ids FROM (
        SELECT public_id FROM unseen_posts_feed
        ORDER BY random()
        LIMIT min_posts_needed
    ) as sub;

    DROP TABLE unseen_posts_feed;
    RETURN coalesce(post_public_ids, '{}'::text[]);
END;
$$;

ALTER FUNCTION public.get_feed(text, text[]) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_feed(text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_feed(text, text[]) TO service_role;
