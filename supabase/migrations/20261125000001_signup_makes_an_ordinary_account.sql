-- A new signup becomes an ordinary account, not a brand.
--
-- profiles.role_id defaults to 10 — brand — which grants giveaways INSERT and makes
-- profile_can_post() true. This was recorded as a finding in the 21-23 Sep changelog:
-- "any insert path omitting it created a brand account". The fix at the time was
-- profiles_guard_privileged_columns, which forces role_id := 1 and profile_type :=
-- 'individual' on INSERT.
--
-- That guard cannot fire on the one path that matters. It exempts two cases, and the
-- signup path is both:
--
--   * pg_trigger_depth() > 1. The exemption is deliberately > 1 rather than > 0,
--     because inside a trigger fired by a direct statement the depth is already 1.
--     But this profiles INSERT happens inside trg_create_or_update_public_profile on
--     auth.users, so it runs at depth 2 and is exempt.
--   * A jwt role that is not anon or authenticated. The auth.users trigger carries no
--     such claim, so it is exempt on that test as well.
--
-- So the column default won and every account created through signup became a brand:
-- 57 of 57 in November 2026, 14 of 15 in October.
--
-- Fixed here rather than by changing the column default, because the default is also
-- what the admin and import paths lean on when they do mean to create a brand. The
-- trigger is the path that never means to. Rather than reproduce the guard's whole
-- list, this states the two columns the guard would have forced; the counters are
-- already zero on a fresh row and the other guarded columns are not set here.
create or replace function public.fn_insert_update_or_delete_public_profile_from_auth()
returns trigger
language plpgsql
security definer
as $function$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF (NEW.phone IS NOT NULL) THEN
            UPDATE public.profiles
            SET phone = NEW.phone
            WHERE auth_id = NEW.id;
        END IF;
        RETURN NULL;
    ELSIF (TG_OP = 'INSERT') THEN
        -- role_id and profile_type are stated, not left to the column default: see above.
        INSERT INTO public.profiles (auth_id, phone, email, status, role_id, profile_type)
        VALUES (NEW.id, NEW.phone, NEW.email, 'published', 1, 'individual');
        RETURN NULL;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM public.profiles WHERE auth_id = OLD.id;
        IF NOT FOUND THEN RETURN NULL; END IF;
        RETURN NULL;
    END IF;
    RETURN NULL;
END;
$function$;
