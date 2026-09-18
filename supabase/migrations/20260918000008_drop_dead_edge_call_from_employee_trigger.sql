-- Remove the dead _edge_employee_upgrade call from
-- fn_update_location_date_on_employee_add().
--
-- The second blocker on INSERT INTO public.location_employees:
--   ERROR 42883: function _edge_employee_upgrade(integer, text, text) does not exist
-- The trigger passes NEW.profile_id, which is integer; the only definition is
-- _edge_employee_upgrade(uid uuid, email text, name text). Same legacy uuid/integer
-- split as 20260918000007.
--
-- This one is NOT fixed by lining the types up, and that is worth being explicit
-- about, because "make the signature match" is the obvious move and it would have
-- made things worse. _edge_employee_upgrade performs a synchronous HTTP POST to
--
--     https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/employee_upgrade
--
-- which is a DIFFERENT Supabase project from this one (ujmisqstpmowanvivtcr), and
-- that hostname no longer resolves -- DNS returns NXDOMAIN. The http extension is
-- installed, so the call really would be attempted. Correcting the type would
-- therefore have turned a dormant 42883 into a live outbound request to a
-- decommissioned host, inside the INSERT's own transaction, against a 20 second
-- CURLOPT_TIMEOUT, and the DNS failure would still have aborted the INSERT. The
-- error message would change; the write would stay broken.
--
-- So the call is removed. The email and name lookups go with it -- they existed
-- only to build its payload. Everything the trigger does locally is preserved
-- verbatim: is_employee on the profile, and updated_at on the location, for both
-- the INSERT and DELETE branches.
--
-- NOT done here, flagged instead: _edge_employee_upgrade itself is left defined but
-- now unreferenced, and it still carries a hardcoded anon JWT for that dead project
-- in its body. Seven other functions in public do the same thing --
-- _typesense_delete, _typesense_import, _typesense_import_int,
-- _typesense_import_uuid, _edge_notification_runner,
-- _edge_push_notifications_runner and _select_contest_winners all reference the same
-- decommissioned project. Cleaning up all eight, and the credentials in them, is a
-- separate piece of work.
CREATE OR REPLACE FUNCTION public.fn_update_location_date_on_employee_add()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles p SET is_employee = false WHERE p.id = OLD.profile_id;
        UPDATE locations SET updated_at = now() WHERE id = OLD.location_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles p SET is_employee = true WHERE p.id = NEW.profile_id;
        UPDATE locations SET updated_at = now() WHERE id = NEW.location_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;
