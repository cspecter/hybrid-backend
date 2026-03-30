-- Migration: Fix profile slug trigger
-- Description: Replaces the incorrect set_slug_from_name trigger on profiles (which has no name column)
--              with a correct set_slug_from_username trigger.

-- 1. Drop the incorrect trigger
DROP TRIGGER IF EXISTS profile_slug_on_name_insert_update ON public.profiles;

-- 2. Ensure the correct function exists and handles updates efficiently
CREATE OR REPLACE FUNCTION public.set_slug_from_username() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Only update slug if username changes or if it's a new record with a username
    IF (TG_OP = 'INSERT' AND NEW.username IS NOT NULL) OR 
       (TG_OP = 'UPDATE' AND NEW.username IS DISTINCT FROM OLD.username AND NEW.username IS NOT NULL) THEN
        NEW.slug := slugify(NEW.username);
    END IF;
    RETURN NEW;
END;
$$;

-- 3. Create the new trigger
CREATE TRIGGER profile_slug_on_username_insert_update
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_slug_from_username();
