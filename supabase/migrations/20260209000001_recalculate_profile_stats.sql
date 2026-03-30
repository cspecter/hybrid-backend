CREATE OR REPLACE FUNCTION public.recalculate_profile_stats(target_public_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    target_id INTEGER;
BEGIN
    -- Get internal integer ID
    SELECT id INTO target_id FROM profiles WHERE public_id = target_public_id;

    IF target_id IS NULL THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    -- Update counts
    UPDATE profiles
    SET
        follower_count = (SELECT count(*) FROM relationships WHERE followee_id = target_id),
        following_count = (SELECT count(*) FROM relationships WHERE follower_id = target_id),
        post_count = (SELECT count(*) FROM posts WHERE profile_id = target_id),
        stash_count = (SELECT count(*) FROM stash WHERE profile_id = target_id)
    WHERE id = target_id;
END;
$$;
