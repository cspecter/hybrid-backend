-- Add missing RPC functions for client app
-- These functions are required by the iOS client for profile management and social features

-- 1. get_managed_profiles (overload for integer ID if needed, though UUID is preferred)
-- The client seems to be calling it with p_admin_id, so we'll add an alias or overload
-- Note: The previous migration added get_managed_profiles(target_auth_id uuid), 
-- but the error says "Could not find the function public.get_managed_profiles(p_admin_id)"
-- which implies it might be trying to pass an integer ID or the parameter name is significant.

CREATE OR REPLACE FUNCTION public.get_managed_profiles(p_admin_id integer)
RETURNS TABLE (
    -- profile_admins info
    admin_record_id integer,
    admin_role text,
    admin_created_at timestamptz,
    -- managed profile info
    profile_id integer,
    public_id uuid,
    username varchar,
    display_name varchar,
    slug text,
    profile_type public.profile_type,
    avatar_url varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
    -- Security check: Users can only see their own managed profiles
    -- We need to verify that p_admin_id belongs to the current auth user
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = p_admin_id AND auth_id = auth.uid()
    ) AND NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN QUERY
    SELECT 
        pa.id,
        pa.role,
        pa.created_at,
        p.id,
        p.public_id,
        p.username,
        p.display_name,
        p.slug,
        p.profile_type,
        cf.url
    FROM public.profile_admins pa
    JOIN public.profiles p ON pa.managed_profile_id = p.id
    LEFT JOIN public.cloud_files cf ON p.avatar_id = cf.id
    WHERE pa.admin_profile_id = p_admin_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_managed_profiles(integer) TO authenticated;


-- 2. is_following
CREATE OR REPLACE FUNCTION public.is_following(p_follower_id integer, p_followee_id integer)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.relationships
        WHERE follower_id = p_follower_id
        AND followee_id = p_followee_id
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_following(integer, integer) TO authenticated;


-- 3. is_blocked
CREATE OR REPLACE FUNCTION public.is_blocked(p_blocker_id integer, p_blocked_id integer)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profile_blocks
        WHERE profile_id = p_blocker_id
        AND blocked_profile_id = p_blocked_id
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked(integer, integer) TO authenticated;
