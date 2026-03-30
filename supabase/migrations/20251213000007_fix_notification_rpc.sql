-- Fix missing RPCs and handle Cocoa timestamps

-- 1. get_unread_notification_count (no args)
-- Returns the unread count for the current authenticated user
CREATE OR REPLACE FUNCTION public.get_unread_notification_count()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
    v_profile_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    
    IF v_profile_id IS NULL THEN
        RETURN 0;
    END IF;

    RETURN (
        SELECT count(*)::integer
        FROM public.notifications
        WHERE profile_id = v_profile_id
        AND is_read = false
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_unread_notification_count() TO authenticated;


-- 2. mark_notification_read (RPC to handle Cocoa timestamp)
-- Accepts the notification ID and the Cocoa timestamp (seconds since 2001-01-01)
CREATE OR REPLACE FUNCTION public.mark_notification_read(
    p_notification_id integer,
    p_read_at double precision DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_timestamp timestamptz;
BEGIN
    -- Convert Cocoa timestamp (if provided) to Postgres timestamptz
    -- Cocoa epoch is 2001-01-01, Unix epoch is 1970-01-01
    -- Difference is 978307200 seconds
    IF p_read_at IS NOT NULL THEN
        v_timestamp := to_timestamp(p_read_at + 978307200);
    ELSE
        v_timestamp := now();
    END IF;

    UPDATE public.notifications
    SET is_read = true,
        read_at = v_timestamp
    WHERE id = p_notification_id
    AND profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid());

    RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_notification_read(integer, double precision) TO authenticated;
