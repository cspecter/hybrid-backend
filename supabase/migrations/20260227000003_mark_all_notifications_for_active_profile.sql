-- Mark all notifications as read for a specific profile the caller owns/manages.

CREATE OR REPLACE FUNCTION public.mark_all_notifications_as_read_for_profile(
  p_profile_id integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requester_profile_id integer;
  v_target_profile_id integer;
  v_updated_count integer := 0;
BEGIN
  SELECT p.id
  INTO v_requester_profile_id
  FROM public.profiles p
  WHERE p.auth_id = auth.uid();

  IF v_requester_profile_id IS NULL THEN
    RETURN 0;
  END IF;

  v_target_profile_id := COALESCE(p_profile_id, v_requester_profile_id);

  IF v_target_profile_id != v_requester_profile_id
     AND NOT public.is_super_admin()
     AND NOT EXISTS (
       SELECT 1
       FROM public.profile_admins pa
       WHERE pa.admin_profile_id = v_requester_profile_id
         AND pa.managed_profile_id = v_target_profile_id
     ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  UPDATE public.notifications n
  SET
    is_read = true,
    read_at = now()
  WHERE n.profile_id = v_target_profile_id
    AND COALESCE(n.is_read, false) = false;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN v_updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_all_notifications_as_read_for_profile(integer) TO authenticated;
