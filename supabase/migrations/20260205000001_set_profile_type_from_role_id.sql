-- Set profile_type based on role_id
-- role_id 10 => brand, all others => individual

CREATE OR REPLACE FUNCTION public.fn_set_profile_type_from_role_id()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.role_id = 10 THEN
        NEW.profile_type := 'brand';
    ELSE
        NEW.profile_type := 'individual';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_profile_type_from_role_id ON public.profiles;

CREATE TRIGGER trg_set_profile_type_from_role_id
    BEFORE INSERT OR UPDATE OF role_id ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_profile_type_from_role_id();

-- Legacy Hybrid backfill archived in ../legacy_hybrid/20260205000001_set_profile_type_from_role_id.backfill.sql.
-- New backend bootstraps should not replay historical data backfills from the active migration chain.
