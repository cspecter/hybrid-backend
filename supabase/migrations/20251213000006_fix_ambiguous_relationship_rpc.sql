-- Fix ambiguous RPC functions for relationships by using text parameters
-- This resolves PGRST203 errors by having a single function signature that handles both UUID and Integer inputs

-- Helper to resolve any ID format to internal Integer ID
CREATE OR REPLACE FUNCTION public.resolve_profile_id(p_input text)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uuid uuid;
    v_id integer;
BEGIN
    -- Check if input is UUID
    IF p_input ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_uuid := p_input::uuid;
        SELECT id INTO v_id FROM public.profiles WHERE auth_id = v_uuid OR public_id = v_uuid LIMIT 1;
        RETURN v_id;
    ELSE
        -- Assume Integer
        BEGIN
            RETURN p_input::integer;
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    END IF;
END;
$$;

-- 1. Fix is_following
DROP FUNCTION IF EXISTS public.is_following(integer, integer);
DROP FUNCTION IF EXISTS public.is_following(uuid, uuid);
DROP FUNCTION IF EXISTS public.is_following(integer, uuid);
DROP FUNCTION IF EXISTS public.is_following(uuid, integer);

CREATE OR REPLACE FUNCTION public.is_following(p_follower_id text, p_followee_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
    v_follower_int integer;
    v_followee_int integer;
BEGIN
    v_follower_int := public.resolve_profile_id(p_follower_id);
    v_followee_int := public.resolve_profile_id(p_followee_id);

    IF v_follower_int IS NULL OR v_followee_int IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.relationships
        WHERE follower_id = v_follower_int
        AND followee_id = v_followee_int
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_following(text, text) TO authenticated;

-- 2. Fix is_blocked
DROP FUNCTION IF EXISTS public.is_blocked(integer, integer);
DROP FUNCTION IF EXISTS public.is_blocked(uuid, uuid);
DROP FUNCTION IF EXISTS public.is_blocked(integer, uuid);
DROP FUNCTION IF EXISTS public.is_blocked(uuid, integer);

CREATE OR REPLACE FUNCTION public.is_blocked(p_blocker_id text, p_blocked_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
    v_blocker_int integer;
    v_blocked_int integer;
BEGIN
    v_blocker_int := public.resolve_profile_id(p_blocker_id);
    v_blocked_int := public.resolve_profile_id(p_blocked_id);

    IF v_blocker_int IS NULL OR v_blocked_int IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.profile_blocks
        WHERE profile_id = v_blocker_int
        AND blocked_profile_id = v_blocked_int
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked(text, text) TO authenticated;
