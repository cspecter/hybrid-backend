-- Archived from active migration 20260205000001_set_profile_type_from_role_id.sql
-- Legacy Hybrid data backfill for existing profiles.

UPDATE public.profiles
SET profile_type = CASE
    WHEN role_id = 10 THEN 'brand'
    ELSE 'individual'
END::public.enum_profiles_profile_type;
