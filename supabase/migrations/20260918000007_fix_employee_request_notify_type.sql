-- Fix the uuid/integer mismatch in notify_brand_of_employee_request().
--
-- Every INSERT into public.location_employees failed with
--   ERROR 22P02: invalid input syntax for type uuid: "3400"
-- because the function declares
--     brand_profile_id uuid;
-- and then selects locations.brand_id into it. locations.brand_id is integer -- it
-- is a foreign key to profiles.id, which is integer. send_notification's first
-- parameter, p_recipient_id, is integer too, so uuid was wrong on both sides.
--
-- Legacy from the schema's move off uuid primary keys; this function was not
-- migrated with the rest.
--
-- Only the declared type changes. The body is otherwise carried over verbatim from
-- the live definition.
CREATE OR REPLACE FUNCTION public.notify_brand_of_employee_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    brand_profile_id integer;
    location_name text;
BEGIN
    -- Get the brand_id and location name
    SELECT l.brand_id, l.name 
    INTO brand_profile_id, location_name
    FROM locations l
    WHERE l.id = NEW.location_id;

    IF brand_profile_id IS NOT NULL THEN
        -- Send notification using the new notification system
        PERFORM public.send_notification(
            brand_profile_id,
            'employee_request',
            NEW.profile_id,  -- actor is the requesting employee
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
