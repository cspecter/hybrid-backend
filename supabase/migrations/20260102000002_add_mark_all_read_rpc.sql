-- Add mark_all_notifications_as_read RPC function
-- This function marks all unread notifications as read for the current user

CREATE OR REPLACE FUNCTION public.mark_all_notifications_as_read()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile_id integer;
BEGIN
    -- Get the profile ID for the current user
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    
    IF v_profile_id IS NOT NULL THEN
        UPDATE public.notifications
        SET is_read = true,
            read_at = now()
        WHERE profile_id = v_profile_id
        AND is_read = false;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_all_notifications_as_read() TO authenticated;
