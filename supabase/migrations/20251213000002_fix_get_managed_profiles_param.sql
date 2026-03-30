-- Fix get_managed_profiles parameter name to match client expectation
-- The client sends 'p_admin_id', but the function expected 'target_auth_id'
-- This caused the function to use the default value (auth.uid()) instead of the passed value

DROP FUNCTION IF EXISTS public.get_managed_profiles(uuid);

CREATE OR REPLACE FUNCTION public.get_managed_profiles(p_admin_id uuid DEFAULT auth.uid())
RETURNS TABLE (
    admin_record_id integer,
    admin_role text,
    admin_created_at timestamptz,
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
    -- Security check: Users can only see their own managed profiles, unless they are super admin
    IF p_admin_id != auth.uid() AND NOT public.is_super_admin() THEN
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
    JOIN public.profiles me ON pa.admin_profile_id = me.id
    JOIN public.profiles p ON pa.managed_profile_id = p.id
    LEFT JOIN public.cloud_files cf ON p.avatar_id = cf.id
    WHERE me.auth_id = p_admin_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_managed_profiles(uuid) TO authenticated;
