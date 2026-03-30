-- Resolve ambiguity for get_managed_profiles by using a single text parameter
-- This handles both UUID (auth_id) and Integer (profile_id) inputs
-- Fixes PGRST203 error where PostgREST cannot choose between overloads with same parameter name

DROP FUNCTION IF EXISTS public.get_managed_profiles(integer);
DROP FUNCTION IF EXISTS public.get_managed_profiles(uuid);

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
    v_auth_id uuid;
    v_profile_id integer;
BEGIN
    -- Case 1: Input is a UUID (Auth ID)
    IF p_admin_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_auth_id := p_admin_id::uuid;
        
        -- Security check: Users can only see their own managed profiles
        IF v_auth_id != auth.uid() AND NOT public.is_super_admin() THEN
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
        WHERE me.auth_id = v_auth_id;

    -- Case 2: Input is an Integer (Profile ID)
    ELSE
        BEGIN
            v_profile_id := p_admin_id::integer;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid admin ID format: %', p_admin_id;
        END;

        -- Security check: Verify the profile belongs to the current user
        IF NOT EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = v_profile_id AND auth_id = auth.uid()
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
        WHERE pa.admin_profile_id = v_profile_id;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_managed_profiles(text) TO authenticated;
