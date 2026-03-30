-- Fix trigger functions that reference non-existent 'name' column on profiles table
-- Replaces 'name' with 'display_name'

-- 1. Fix _fn_likes_insert_tasks
CREATE OR REPLACE FUNCTION public._fn_likes_insert_tasks() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        SELECT display_name, id INTO r FROM profiles WHERE profiles.id = (SELECT posts.profile_id FROM posts WHERE posts.id = NEW.post_id);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

-- 2. Fix _fn_list_insert_tasks
CREATE OR REPLACE FUNCTION public._fn_list_insert_tasks() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF NEW.base = false THEN
            SELECT display_name, id INTO r FROM profiles WHERE profiles.id = NEW.profile_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

-- 3. Fix fn_add_or_change_list_on_profile_name_change
CREATE OR REPLACE FUNCTION public.fn_add_or_change_list_on_profile_name_change() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.display_name != OLD.display_name THEN
            IF EXISTS (SELECT id FROM lists WHERE profile_id = NEW.id AND base = true) THEN
                UPDATE lists SET name = NEW.display_name || '''s list' WHERE profile_id = NEW.id AND base = true;
            ELSE
                INSERT INTO public.lists(id, base, profile_id, name, description)
                VALUES (gen_random_uuid(), true, NEW.id, NEW.display_name || '''s list', 'A few of my favorite things.');
            END IF;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.display_name IS NOT NULL THEN
            INSERT INTO public.lists(id, base, profile_id, name, description)
            VALUES (gen_random_uuid(), true, NEW.id, NEW.display_name || '''s list', 'A few of my favorite things.');
        ELSE
            INSERT INTO public.lists(id, base, profile_id, name, description)
            VALUES (gen_random_uuid(), true, NEW.id, 'My list', 'A few of my favorite things.');
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- 4. Fix cascade_profile_fts_update
CREATE OR REPLACE FUNCTION public.cascade_profile_fts_update() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.display_name IS DISTINCT FROM NEW.display_name OR OLD.username IS DISTINCT FROM NEW.username THEN
        UPDATE posts SET fts_vector = fts_vector WHERE profile_id = NEW.id;
        UPDATE lists SET fts_vector = fts_vector WHERE profile_id = NEW.id;
        UPDATE locations SET fts_vector = fts_vector WHERE brand_id = NEW.id;
        
        IF OLD.display_name IS DISTINCT FROM NEW.display_name THEN
            UPDATE products 
            SET cached_brand_names = COALESCE(
                (SELECT string_agg(p.display_name, ' ') 
                 FROM product_brands pb 
                 JOIN profiles p ON p.id = pb.brand_id 
                 WHERE pb.product_id = products.id), 
                ''
            )
            WHERE id IN (
                SELECT product_id FROM product_brands WHERE brand_id = NEW.id
            );
            
            UPDATE products SET fts_vector = fts_vector 
            WHERE id IN (
                SELECT product_id FROM product_brands WHERE brand_id = NEW.id
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- 5. Fix fn_profile_admins_triggers
CREATE OR REPLACE FUNCTION public.fn_profile_admins_triggers() 
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    brand_name text;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        -- Get brand name
        SELECT display_name INTO brand_name FROM profiles WHERE id = NEW.brand_id;
        
        -- Notify the admin that they've been added
        PERFORM public.send_notification(
            NEW.admin_id,
            'admin_added',
            NEW.brand_id,  -- actor is the brand
            'profile',
            NEW.brand_id,
            jsonb_build_object(
                'brand_name', brand_name,
                'role', COALESCE(NEW.role, 'admin')
            )
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;
