-- Fix get_managed_profiles to be more robust and explicit
-- 1. Resolves the target admin_profile_id first (from UUID or Int)
-- 2. Performs security check on that ID
-- 3. Queries profile_admins using the resolved ID directly
-- This avoids potential join ambiguities and ensures we are querying exactly what we expect.

DROP FUNCTION IF EXISTS public.get_managed_profiles(text);

CREATE OR REPLACE FUNCTION public.get_managed_profiles(p_admin_id text DEFAULT auth.uid()::text)
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
DECLARE
    v_admin_profile_id integer;
    v_target_auth_id uuid;
BEGIN
    -- 1. Resolve input to an integer profile_id
    -- Check if input is a UUID
    IF p_admin_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_target_auth_id := p_admin_id::uuid;
        SELECT id INTO v_admin_profile_id FROM public.profiles WHERE auth_id = v_target_auth_id;
    ELSE
        -- Assume integer
        BEGIN
            v_admin_profile_id := p_admin_id::integer;
            SELECT auth_id INTO v_target_auth_id FROM public.profiles WHERE id = v_admin_profile_id;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid admin ID format: %', p_admin_id;
        END;
    END IF;

    -- If no profile found, return empty set
    IF v_admin_profile_id IS NULL THEN
        RETURN;
    END IF;

    -- 2. Security Check
    -- Users can only see their own managed profiles, unless they are super admin
    -- We check if the resolved target_auth_id matches the current user
    IF v_target_auth_id != auth.uid() AND NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    -- 3. Return managed profiles
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
    WHERE pa.admin_profile_id = v_admin_profile_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_managed_profiles(text) TO authenticated;
