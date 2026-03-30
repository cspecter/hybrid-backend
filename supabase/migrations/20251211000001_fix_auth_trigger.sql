-- Migration: Fix auth trigger function
-- Description: Fixes "relation profiles does not exist" error by schema qualifying the table
--              and fixing the INSERT statement to respect the integer ID column.

CREATE OR REPLACE FUNCTION public.fn_insert_update_or_delete_public_profile_from_auth() 
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF (NEW.phone IS NOT NULL) THEN
            UPDATE public.profiles
            SET phone = NEW.phone
            WHERE auth_id = NEW.id;
        END IF;
        RETURN NULL;
    ELSIF (TG_OP = 'INSERT') THEN
        -- Fix: Remove id (auto-increment), use schema qualified table, use default role_id
        INSERT INTO public.profiles (auth_id, phone, email, status)
        VALUES (NEW.id, NEW.phone, NEW.email, 'published');
        RETURN NULL;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM public.profiles WHERE auth_id = OLD.id;
        IF NOT FOUND THEN RETURN NULL; END IF;
        RETURN NULL;
    END IF;
    RETURN NULL;
END;
$$;
