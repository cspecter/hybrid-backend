-- Fix RPC functions to accept UUIDs
-- The client is sending UUIDs (auth_id or public_id) instead of integer IDs
-- We'll add overloads to handle this gracefully

-- Helper to resolve UUID to Profile ID (checks both auth_id and public_id)
CREATE OR REPLACE FUNCTION public.get_profile_id_by_uuid(p_uuid uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id FROM public.profiles 
    WHERE auth_id = p_uuid OR public_id = p_uuid
    LIMIT 1;
$$;

-- 1. is_blocked overloads
-- UUID, UUID
CREATE OR REPLACE FUNCTION public.is_blocked(p_blocker_id uuid, p_blocked_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_blocker_int integer;
    v_blocked_int integer;
BEGIN
    v_blocker_int := public.get_profile_id_by_uuid(p_blocker_id);
    v_blocked_int := public.get_profile_id_by_uuid(p_blocked_id);
    
    -- If either profile doesn't exist, they can't be blocking/blocked
    IF v_blocker_int IS NULL OR v_blocked_int IS NULL THEN
        RETURN false;
    END IF;

    RETURN public.is_blocked(v_blocker_int, v_blocked_int);
END;
$$;

-- UUID, Integer
CREATE OR REPLACE FUNCTION public.is_blocked(p_blocker_id uuid, p_blocked_id integer)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_blocker_int integer;
BEGIN
    v_blocker_int := public.get_profile_id_by_uuid(p_blocker_id);
    
    IF v_blocker_int IS NULL THEN
        RETURN false;
    END IF;

    RETURN public.is_blocked(v_blocker_int, p_blocked_id);
END;
$$;

-- Integer, UUID
CREATE OR REPLACE FUNCTION public.is_blocked(p_blocker_id integer, p_blocked_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_blocked_int integer;
BEGIN
    v_blocked_int := public.get_profile_id_by_uuid(p_blocked_id);
    
    IF v_blocked_int IS NULL THEN
        RETURN false;
    END IF;

    RETURN public.is_blocked(p_blocker_id, v_blocked_int);
END;
$$;


-- 2. is_following overloads
-- UUID, UUID
CREATE OR REPLACE FUNCTION public.is_following(p_follower_id uuid, p_followee_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_follower_int integer;
    v_followee_int integer;
BEGIN
    v_follower_int := public.get_profile_id_by_uuid(p_follower_id);
    v_followee_int := public.get_profile_id_by_uuid(p_followee_id);
    
    IF v_follower_int IS NULL OR v_followee_int IS NULL THEN
        RETURN false;
    END IF;

    RETURN public.is_following(v_follower_int, v_followee_int);
END;
$$;

-- UUID, Integer
CREATE OR REPLACE FUNCTION public.is_following(p_follower_id uuid, p_followee_id integer)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_follower_int integer;
BEGIN
    v_follower_int := public.get_profile_id_by_uuid(p_follower_id);
    
    IF v_follower_int IS NULL THEN
        RETURN false;
    END IF;

    RETURN public.is_following(v_follower_int, p_followee_id);
END;
$$;

-- Integer, UUID
CREATE OR REPLACE FUNCTION public.is_following(p_follower_id integer, p_followee_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_followee_int integer;
BEGIN
    v_followee_int := public.get_profile_id_by_uuid(p_followee_id);
    
    IF v_followee_int IS NULL THEN
        RETURN false;
    END IF;

    RETURN public.is_following(p_follower_id, v_followee_int);
END;
$$;

-- Grant access to all new overloads
GRANT EXECUTE ON FUNCTION public.is_blocked(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_blocked(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_blocked(integer, uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_following(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_following(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_following(integer, uuid) TO authenticated;
