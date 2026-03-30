-- Update get_managed_profiles to return only public_ids as requested
-- and ensure strict filtering by admin_profile_id.

DROP FUNCTION IF EXISTS public.get_managed_profiles(text);

CREATE OR REPLACE FUNCTION public.get_managed_profiles(p_admin_id text DEFAULT NULL)
RETURNS TABLE (public_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
    v_target_auth_id uuid;
    v_admin_profile_id integer;
BEGIN
    -- 1. Determine the target Auth UUID
    IF p_admin_id IS NULL THEN
        v_target_auth_id := auth.uid();
    ELSIF p_admin_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_target_auth_id := p_admin_id::uuid;
    ELSE
        -- If passed as integer ID, resolve to Auth UUID first to check permissions
        BEGIN
            SELECT auth_id INTO v_target_auth_id 
            FROM public.profiles 
            WHERE id = p_admin_id::integer;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid admin ID format';
        END;
    END IF;

    -- 2. Security Check
    -- The requesting user must be the target user OR a super admin
    IF v_target_auth_id != auth.uid() AND NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    -- 3. Resolve the Profile ID for this Auth ID
    SELECT id INTO v_admin_profile_id 
    FROM public.profiles 
    WHERE auth_id = v_target_auth_id;

    IF v_admin_profile_id IS NULL THEN
        RETURN;
    END IF;

    -- 4. Return the public_ids of managed profiles
    RETURN QUERY
    SELECT p.public_id
    FROM public.profile_admins pa
    JOIN public.profiles p ON pa.managed_profile_id = p.id
    WHERE pa.admin_profile_id = v_admin_profile_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_managed_profiles(text) TO authenticated;
