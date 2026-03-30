-- Ensure all profiles have notification settings for all types
-- This runs for all existing profiles to make sure no one was missed.

INSERT INTO public.profile_notification_type_settings (profile_id, notification_type_id, is_enabled)
SELECT p.id, nt.id, true
FROM public.profiles p
CROSS JOIN public.notification_types nt
ON CONFLICT (profile_id, notification_type_id) DO NOTHING;
