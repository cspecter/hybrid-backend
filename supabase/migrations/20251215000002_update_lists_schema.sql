-- Add is_private to lists
ALTER TABLE public.lists ADD COLUMN IF NOT EXISTS is_private boolean DEFAULT false;

-- Create or replace create_list function
CREATE OR REPLACE FUNCTION public.create_list(
    p_profile_id uuid,
    p_name text,
    p_description text DEFAULT NULL,
    p_is_private boolean DEFAULT false,
    p_background_id integer DEFAULT NULL,
    p_thumbnail_id integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_list_id integer;
BEGIN
    -- Get internal profile id
    SELECT id INTO v_profile_id FROM public.profiles WHERE public_id = p_profile_id;
    
    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    INSERT INTO public.lists (
        profile_id,
        name,
        description,
        is_private,
        background_id,
        thumbnail_id
    ) VALUES (
        v_profile_id,
        p_name,
        p_description,
        p_is_private,
        p_background_id,
        p_thumbnail_id
    )
    RETURNING id INTO v_list_id;

    RETURN v_list_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_list(uuid, text, text, boolean, integer, integer) TO authenticated;
