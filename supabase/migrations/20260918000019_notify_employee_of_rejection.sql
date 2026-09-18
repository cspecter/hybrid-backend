-- Send notification type 56 (employee_rejected) when an employment request is turned down.
--
-- notification_types 54, 55 and 56 all exist and 56 has a working body template --
-- "Your request to join {location_name} was not approved" -- but nothing ever wrote a
-- row with it. on_employee_request fires 54 to the store on INSERT and
-- notify_employee_of_approval fires 55 back on approval, so approval notifies and
-- rejection was silent. A requester whose application was declined saw a request that
-- stayed pending forever.
--
-- How rejection is encoded: the schema already answers this. update_employee_approval
-- sets has_been_reviewed = TRUE alongside is_approved, so a reviewed row with
-- is_approved false IS the rejected state. There is no separate status column to add.
--
-- The new branch fires on the TRANSITION into that state, not on its presence, so a
-- later no-op UPDATE on an already-rejected row does not re-notify:
--
--     NEW is reviewed AND not approved
--     AND NOT (OLD was already reviewed AND not approved)
--
-- COALESCE throughout because both columns are nullable and a pending row typically
-- holds NULL rather than false -- `NEW.has_been_reviewed = true` alone would be NULL,
-- not false, for the row this is meant to catch.
--
-- This deliberately also covers revocation: an approved employee being set back to
-- is_approved = false transitions into the same state and gets the same notification.
-- Type 56's title is the neutral "Employee request update" rather than a rejection
-- phrase, so it reads correctly for both. If revocation should later say something
-- different, it needs its own type rather than a branch here.
--
-- The approval branch is carried over verbatim. send_notification carries the
-- pg_trigger_depth() = 0 guard added in 20260918000015; this calls it from inside a
-- trigger, so depth is above zero and the guard exempts it.
CREATE OR REPLACE FUNCTION public.notify_employee_of_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    location_name text;
    user_email text;
BEGIN
    IF (TG_OP = 'UPDATE' AND NEW.is_approved = true AND (OLD.is_approved IS NULL OR OLD.is_approved = false)) THEN
        -- Get the location name
        SELECT name INTO location_name
        FROM locations
        WHERE id = NEW.location_id;

        -- Get the user's email
        SELECT email INTO user_email
        FROM profiles
        WHERE id = NEW.profile_id;

        -- Send notification using the new notification system
        PERFORM public.send_notification(
            NEW.profile_id,
            'employee_approved',
            NULL,  -- no actor
            'location',
            NEW.location_id,
            jsonb_build_object(
                'location_name', location_name,
                'role', COALESCE(NEW.role, 'budtender')
            )
        );

    ELSIF (TG_OP = 'UPDATE'
           AND COALESCE(NEW.has_been_reviewed, false) = true
           AND COALESCE(NEW.is_approved, false) = false
           AND NOT (COALESCE(OLD.has_been_reviewed, false) = true
                    AND COALESCE(OLD.is_approved, false) = false)) THEN

        SELECT name INTO location_name
        FROM locations
        WHERE id = NEW.location_id;

        PERFORM public.send_notification(
            NEW.profile_id,
            'employee_rejected',
            NULL,  -- no actor: the decision is the store's, not a named person's
            'location',
            NEW.location_id,
            jsonb_build_object(
                'location_name', location_name,
                'role', COALESCE(NEW.role, 'budtender')
            )
        );
    END IF;

    RETURN NEW;
END;
$$;
