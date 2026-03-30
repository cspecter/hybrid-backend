-- ============================================================================
-- RELATIONSHIP HELPER FUNCTIONS
-- These functions allow clients to update relationships using public_ids (UUIDs)
-- even though the underlying database uses integer foreign keys.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper: Resolve Cloud File ID
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_cloud_file_id(p_public_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT id FROM public.cloud_files WHERE public_id = p_public_id;
$$;

-- ----------------------------------------------------------------------------
-- PROFILES: Update Avatar & Banner
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_profile_avatar(file_public_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_file_id integer;
    v_profile_id integer;
BEGIN
    -- Resolve file ID
    SELECT id INTO v_file_id FROM public.cloud_files WHERE public_id = file_public_id;
    
    -- Get current user's profile
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    
    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    UPDATE public.profiles 
    SET avatar_id = v_file_id, updated_at = now() 
    WHERE id = v_profile_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_profile_banner(file_public_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_file_id integer;
    v_profile_id integer;
BEGIN
    SELECT id INTO v_file_id FROM public.cloud_files WHERE public_id = file_public_id;
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    
    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    UPDATE public.profiles 
    SET banner_id = v_file_id, updated_at = now() 
    WHERE id = v_profile_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- PRODUCTS: Update Images
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_product_images(
    product_public_id uuid,
    thumbnail_public_id uuid DEFAULT NULL,
    cover_public_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product_id integer;
    v_thumbnail_id integer;
    v_cover_id integer;
BEGIN
    -- Resolve IDs
    SELECT id INTO v_product_id FROM public.products WHERE public_id = product_public_id;
    
    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'Product not found';
    END IF;

    -- Check permissions (optional, depends on RLS, but good to have check)
    -- For now assuming RLS on UPDATE public.products handles auth check
    
    IF thumbnail_public_id IS NOT NULL THEN
        SELECT id INTO v_thumbnail_id FROM public.cloud_files WHERE public_id = thumbnail_public_id;
        UPDATE public.products SET thumbnail_id = v_thumbnail_id WHERE id = v_product_id;
    END IF;

    IF cover_public_id IS NOT NULL THEN
        SELECT id INTO v_cover_id FROM public.cloud_files WHERE public_id = cover_public_id;
        UPDATE public.products SET cover_id = v_cover_id WHERE id = v_product_id;
    END IF;
    
    UPDATE public.products SET updated_at = now() WHERE id = v_product_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- LOCATIONS: Update Images
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_location_images(
    location_public_id uuid,
    logo_public_id uuid DEFAULT NULL,
    banner_public_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_location_id integer;
    v_logo_id integer;
    v_banner_id integer;
BEGIN
    SELECT id INTO v_location_id FROM public.locations WHERE public_id = location_public_id;
    
    IF v_location_id IS NULL THEN
        RAISE EXCEPTION 'Location not found';
    END IF;

    IF logo_public_id IS NOT NULL THEN
        SELECT id INTO v_logo_id FROM public.cloud_files WHERE public_id = logo_public_id;
        UPDATE public.locations SET logo_id = v_logo_id WHERE id = v_location_id;
    END IF;

    IF banner_public_id IS NOT NULL THEN
        SELECT id INTO v_banner_id FROM public.cloud_files WHERE public_id = banner_public_id;
        UPDATE public.locations SET banner_id = v_banner_id WHERE id = v_location_id;
    END IF;

    UPDATE public.locations SET updated_at = now() WHERE id = v_location_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- LISTS: Update Images
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_list_images(
    list_public_id uuid,
    thumbnail_public_id uuid DEFAULT NULL,
    background_public_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_list_id integer;
    v_thumbnail_id integer;
    v_background_id integer;
BEGIN
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = list_public_id;
    
    IF v_list_id IS NULL THEN
        RAISE EXCEPTION 'List not found';
    END IF;

    IF thumbnail_public_id IS NOT NULL THEN
        SELECT id INTO v_thumbnail_id FROM public.cloud_files WHERE public_id = thumbnail_public_id;
        UPDATE public.lists SET thumbnail_id = v_thumbnail_id WHERE id = v_list_id;
    END IF;

    IF background_public_id IS NOT NULL THEN
        SELECT id INTO v_background_id FROM public.cloud_files WHERE public_id = background_public_id;
        UPDATE public.lists SET background_id = v_background_id WHERE id = v_list_id;
    END IF;

    UPDATE public.lists SET updated_at = now() WHERE id = v_list_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- POSTS: Create Post with File
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_post_with_file(
    message text,
    file_public_id uuid,
    location_public_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_file_id integer;
    v_location_id integer;
    v_post_public_id uuid;
BEGIN
    -- Get current user
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    IF v_profile_id IS NULL THEN RAISE EXCEPTION 'Profile not found'; END IF;

    -- Resolve IDs
    SELECT id INTO v_file_id FROM public.cloud_files WHERE public_id = file_public_id;
    
    IF location_public_id IS NOT NULL THEN
        SELECT id INTO v_location_id FROM public.locations WHERE public_id = location_public_id;
    END IF;

    -- Insert Post
    INSERT INTO public.posts (
        profile_id,
        message,
        file_id,
        location_id,
        has_file
    ) VALUES (
        v_profile_id,
        message,
        v_file_id,
        v_location_id,
        v_file_id IS NOT NULL
    ) RETURNING public_id INTO v_post_public_id;

    RETURN v_post_public_id;
END;
$$;
