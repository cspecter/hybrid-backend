-- Trigger Functions
-- Functions designed to be called by database triggers
-- Updated: Uses profiles instead of users, locations instead of dispensary_locations

-- =====================================
-- TYPESENSE SYNC TRIGGER FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION public._delete_categories_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'categories');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._delete_deals_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'deals');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._delete_locations_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'locations');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._delete_giveaways_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'giveaways');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._delete_lists_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'lists');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._delete_postal_codes_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'postal_codes');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._delete_posts_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'posts');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._delete_products_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'products');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._delete_profiles_from_typesense_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM _typesense_delete(OLD.id::text, 'profiles');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_deals() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
        PERFORM _typesense_import_uuid(NEW.id::uuid, 'deals'::text);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_locations() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
        PERFORM _typesense_import_uuid(NEW.id::uuid, 'locations'::text);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_giveaways() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
        PERFORM _typesense_import_uuid(NEW.id::uuid, 'giveaways'::text);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_lists() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
        PERFORM _typesense_import_uuid(NEW.id::uuid, 'lists'::text);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_postal_codes() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
        -- Disabled: postal codes sync
        -- PERFORM _typesense_import_int(NEW.id::int, 'postal_codes'::text);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_posts() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
        PERFORM _typesense_import_uuid(NEW.id::uuid, 'posts'::text);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_product_categories() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
        PERFORM _typesense_import_uuid(NEW.id::uuid, 'categories'::text);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_products() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
        PERFORM _typesense_import_uuid(NEW.id::uuid, 'products'::text);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_typesense_profiles() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF (NEW.id IS NOT NULL) THEN
            -- Disabled: profile sync on insert
            -- PERFORM _typesense_import_uuid(NEW.id::uuid, 'profiles'::text);
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

-- =====================================
-- ENTITY DELETE TRIGGER FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION public._fn_delete_product_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF pg_trigger_depth() > 1 THEN
        RETURN OLD;
    END IF;
    IF (TG_OP = 'DELETE') THEN
        -- Relationships are handled by cascade deletes
    END IF;
    RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_delete_profile() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        DELETE FROM product_brands WHERE brand_id = OLD.id;
        DELETE FROM lists WHERE profile_id = OLD.id;
        DELETE FROM posts WHERE profile_id = OLD.id;
        DELETE FROM explore_profiles WHERE profile_id = OLD.id;
        DELETE FROM locations WHERE brand_id = OLD.id;
        DELETE FROM stash WHERE profile_id = OLD.id;
        DELETE FROM subscriptions_lists WHERE profile_id = OLD.id;
        DELETE FROM relationships WHERE follower_id = OLD.id OR followee_id = OLD.id;
        DELETE FROM addresses WHERE profile_id = OLD.id;
        DELETE FROM profile_admins WHERE profile_id = OLD.id OR brand_id = OLD.id;
        DELETE FROM likes WHERE profile_id = OLD.id;
        DELETE FROM giveaway_entries WHERE profile_id = OLD.id;
        DELETE FROM deal_claims WHERE profile_id = OLD.id;
        DELETE FROM analytics_posts WHERE profile_id = OLD.id;
        RETURN OLD;
    END IF;
    RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_delete_post(post_id uuid) 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE 
    post_record record;
BEGIN
    SELECT * INTO post_record FROM posts WHERE id = post_id;
    DELETE FROM analytics_posts WHERE analytics_posts.post_id = post_id;
    DELETE FROM posts_hashtags WHERE posts_hashtags.post_id = post_id;
    DELETE FROM cloud_files WHERE id = post_record.file_id;
    DELETE FROM posts WHERE id = post_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_delete_remote_file_on_delete() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    s text;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.public_id IS NOT NULL THEN     
            SELECT status INTO s FROM http_delete(
                'https://651595363288454:6xMlUJRgQ50im9jPvJ8O8Bld97c@api.cloudinary.com/v1_1/hybridapp/resources/image/upload?public_ids[]=' || OLD.public_id
            );
        END IF;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_deletion() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO deletion_log (table_name, record_id, deleted_data)
    VALUES (TG_TABLE_NAME, OLD.id, row_to_json(OLD));
    RETURN OLD;
END;
$$;

-- =====================================
-- COUNT UPDATE TRIGGER FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION public.fn_brand_count_on_products() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.product_id IS NOT NULL THEN
            UPDATE products SET brand_count = brand_count - 1 WHERE id = OLD.product_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.product_id IS NOT NULL THEN
            UPDATE products SET brand_count = brand_count + 1 WHERE id = NEW.product_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_category_product_count_on_product() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.category_id IS NOT NULL THEN
            UPDATE product_categories SET product_count = product_count - 1 WHERE id = OLD.category_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.category_id IS NOT NULL THEN
            UPDATE product_categories SET product_count = product_count + 1 WHERE id = NEW.category_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_deal_count_on_deals() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.deal_id IS NOT NULL THEN
            UPDATE deals SET claimed_deals = claimed_deals - 1 WHERE id = OLD.deal_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.deal_id IS NOT NULL THEN
            UPDATE deals SET claimed_deals = claimed_deals + 1 WHERE id = NEW.deal_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_follower_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles SET follower_count = follower_count - 1 WHERE id = OLD.followee_id;
        UPDATE profiles SET following_count = following_count - 1 WHERE id = OLD.follower_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles SET follower_count = follower_count + 1 WHERE id = NEW.followee_id;
        UPDATE profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_following_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles SET following_count = following_count - 1 WHERE id = OLD.follower_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_lists_product_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE lists SET updated_at = NOW(), product_count = product_count - 1 WHERE id = OLD.list_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE lists SET updated_at = NOW(), product_count = product_count + 1 WHERE id = NEW.list_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_post_count_on_profiles() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.profile_id IS NOT NULL THEN
            UPDATE profiles SET post_count = post_count - 1 WHERE id = OLD.profile_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.profile_id IS NOT NULL THEN
            UPDATE profiles SET post_count = post_count + 1 WHERE id = NEW.profile_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_post_product_count_on_product() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.product_id IS NOT NULL THEN
            UPDATE products SET post_count = post_count - 1 WHERE id = OLD.product_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.product_id IS NOT NULL THEN
            UPDATE products SET post_count = post_count + 1 WHERE id = NEW.product_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_posts_like_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE posts SET like_count = like_count - 1 WHERE id = OLD.post_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE posts SET like_count = like_count + 1 WHERE id = NEW.post_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_product_count_on_profiles() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.brand_id IS NOT NULL THEN
            UPDATE profiles SET product_count = product_count - 1 WHERE id = OLD.brand_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.brand_id IS NOT NULL THEN
            UPDATE profiles SET product_count = product_count + 1 WHERE id = NEW.brand_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_product_list_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE products SET list_count = list_count - 1 WHERE id = OLD.product_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE products SET list_count = list_count + 1 WHERE id = NEW.product_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_product_stash_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE products SET stash_count = stash_count - 1 WHERE id = OLD.product_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE products SET stash_count = stash_count + 1 WHERE id = NEW.product_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_profiles_like_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles SET like_count = like_count - 1 WHERE id = OLD.profile_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles SET like_count = like_count + 1 WHERE id = NEW.profile_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_profiles_stash_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles SET stash_count = stash_count - 1 WHERE id = OLD.profile_id;
        UPDATE profiles SET restash_count = restash_count - 1 WHERE id = OLD.restash_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles SET stash_count = stash_count + 1 WHERE id = NEW.profile_id;
        UPDATE profiles SET restash_count = restash_count + 1 WHERE id = NEW.restash_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_location_count_on_profile() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.brand_id IS NOT NULL THEN
            UPDATE profiles SET location_count = location_count - 1 WHERE id = OLD.brand_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.brand_id IS NOT NULL THEN
            UPDATE profiles SET location_count = location_count + 1 WHERE id = NEW.brand_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_flag_count_on_posts() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.post_id IS NOT NULL THEN
            UPDATE posts SET flag_count = flag_count - 1 WHERE id = OLD.post_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.post_id IS NOT NULL THEN
            UPDATE posts SET flag_count = flag_count + 1 WHERE id = NEW.post_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_giveaway_entry_count_on_giveaway() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        IF OLD.giveaway_id IS NOT NULL THEN
            UPDATE giveaways SET entry_count = entry_count - 1 WHERE id = OLD.giveaway_id;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.giveaway_id IS NOT NULL THEN
            UPDATE giveaways SET entry_count = entry_count + 1 WHERE id = NEW.giveaway_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- =====================================
-- ENTITY LIFECYCLE TRIGGER FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION public._fn_location_on_update() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        UPDATE profiles p SET updated_at = now() WHERE p.id = NEW.brand_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_likes_insert_tasks() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        SELECT name, id INTO r FROM profiles WHERE profiles.id = (SELECT posts.profile_id FROM posts WHERE posts.id = NEW.post_id);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_list_insert_tasks() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF NEW.base = false THEN
            SELECT name, id INTO r FROM profiles WHERE profiles.id = NEW.profile_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._fn_profile_set_claimed() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        UPDATE profiles p SET claimed = true WHERE p.id = NEW.brand_id;
        UPDATE products p SET updated_at = now() WHERE p.id = ANY(SELECT pb.product_id FROM product_brands pb WHERE pb.brand_id = NEW.brand_id);
        UPDATE locations l SET updated_at = now() WHERE l.brand_id = NEW.brand_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_add_or_change_list_on_profile_name_change() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.name != OLD.name THEN
            IF EXISTS (SELECT id FROM lists WHERE profile_id = NEW.id AND base = true) THEN
                UPDATE lists SET name = NEW.name || '''s list' WHERE profile_id = NEW.id AND base = true;
            ELSE
                INSERT INTO public.lists(id, base, profile_id, name, description)
                VALUES (gen_random_uuid(), true, NEW.id, NEW.name || '''s list', 'A few of my favorite things.');
            END IF;
        END IF;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        IF NEW.name IS NOT NULL THEN
            INSERT INTO public.lists(id, base, profile_id, name, description)
            VALUES (gen_random_uuid(), true, NEW.id, NEW.name || '''s list', 'A few of my favorite things.');
        ELSE
            INSERT INTO public.lists(id, base, profile_id, name, description)
            VALUES (gen_random_uuid(), true, NEW.id, 'My list', 'A few of my favorite things.');
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_add_role_id_to_relationship() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        NEW.role_id = (SELECT role_id FROM profiles WHERE profiles.id = NEW.followee_id);
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_analytics_post() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    share_add int;
    exist_view record;
    reach_add int;
    avg_time int;
    avg_compute int;
    in_full_add int;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        IF NEW.post_id IS NOT NULL THEN
            IF NEW.share_date IS NOT NULL THEN
                share_add = 1;
            ELSE
                share_add = 0;
            END IF;

            SELECT id INTO exist_view FROM analytics_posts WHERE analytics_posts.profile_id = NEW.profile_id;
            IF exist_view IS NOT NULL THEN
                reach_add = 1;
            ELSE
                reach_add = 0;
            END IF;

            SELECT average_watch_time INTO avg_time FROM posts WHERE id = NEW.post_id;

            IF avg_time = 0 THEN
                avg_compute = NEW.watch_duration;
            ELSE 
                avg_compute = avg_time;
            END IF;

            IF NEW.watch_in_full = true THEN
                in_full_add = 1;
            ELSE 
                in_full_add = 0;
            END IF;

            UPDATE posts SET
                view_count = view_count + 1,
                share_count = share_count + share_add,
                total_watch_time = total_watch_time + NEW.watch_duration,
                reach_count = reach_count + reach_add,
                average_watch_time = (avg_compute + NEW.watch_duration) / 2,
                watched_in_full_count = watched_in_full_count + in_full_add
            WHERE id = NEW.post_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_giveaway_entry_triggers() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    p record;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        SELECT id, name INTO p FROM giveaways WHERE id = NEW.giveaway_id LIMIT 1;
        INSERT INTO notifications (type_id, related_type, related_id, title, body, profile_id) 
        VALUES (
            (SELECT id FROM notification_types WHERE code = 'giveaway_entry'),
            'giveaway',
            NEW.giveaway_id, 
            'Giveaway Entry',
            'You entered to win ' || p.name || '.', 
            NEW.profile_id
        );
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        IF NEW.sent = true THEN
            UPDATE giveaways SET redeemed = (
                SELECT (
                    (SELECT count(id)::int FROM giveaway_entries WHERE giveaway_id = NEW.giveaway_id AND won = true GROUP BY id) 
                    = 
                    (SELECT count(id)::int FROM giveaway_entries WHERE giveaway_id = NEW.giveaway_id AND won = true AND sent = true GROUP BY id)
                )::boolean
            ) WHERE giveaways.id = NEW.giveaway_id;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_lists_products_sort() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE lists SET sort = array_remove(sort, OLD.product_id) WHERE id = OLD.list_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE lists SET sort = array_prepend(NEW.product_id, sort) WHERE id = NEW.list_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_products_gallery_sort() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE products SET sort = array_remove(sort, OLD.cloud_file_id) WHERE id = OLD.product_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE products SET sort = array_prepend(NEW.cloud_file_id, sort) WHERE id = NEW.product_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_insert_update_or_delete_public_profile_from_auth() 
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    icount int = (SELECT count(*) FROM profiles);
    newname varchar;
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF (NEW.phone IS NOT NULL) THEN
            UPDATE public.profiles
            SET phone = NEW.phone
            WHERE auth_id = NEW.id;
        END IF;
        RETURN NULL;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO public.profiles (id, auth_id, phone, email, role_id, status)
        VALUES (gen_random_uuid(), NEW.id, NEW.phone, NEW.email, 1, 'published');
        RETURN NULL;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM public.profiles WHERE auth_id = OLD.id;
        IF NOT FOUND THEN RETURN NULL; END IF;
        RETURN NULL;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_update_location_date_on_employee_add() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    email text;
    name text;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE profiles p SET is_employee = false WHERE p.id = OLD.profile_id;
        UPDATE locations SET updated_at = now() WHERE id = OLD.location_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE profiles p SET is_employee = true WHERE p.id = NEW.profile_id;
        UPDATE locations SET updated_at = now() WHERE id = NEW.location_id;
        SELECT p.email INTO email FROM profiles p WHERE p.id = NEW.profile_id;
        SELECT l.name INTO name FROM locations l WHERE l.id = NEW.location_id;
        PERFORM _edge_employee_upgrade(
            NEW.profile_id,
            email,
            name
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- =====================================
-- FTS CASCADE UPDATE FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION public.cascade_product_category_fts_update() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.name IS DISTINCT FROM NEW.name THEN
        UPDATE products SET fts_vector = fts_vector WHERE category_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.cascade_product_fts_update() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.name IS DISTINCT FROM NEW.name OR OLD.description IS DISTINCT FROM NEW.description THEN
        UPDATE posts SET fts_vector = fts_vector 
        WHERE id IN (SELECT post_id FROM posts_products WHERE product_id = NEW.id);
        
        UPDATE lists SET fts_vector = fts_vector 
        WHERE id IN (SELECT list_id FROM lists_products WHERE product_id = NEW.id);
        
        UPDATE giveaways SET fts_vector = fts_vector WHERE product_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.cascade_product_brands_update() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM update_product_cached_brands(NEW.product_id);
        UPDATE products SET fts_vector = fts_vector WHERE id = NEW.product_id;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        PERFORM update_product_cached_brands(NEW.product_id);
        UPDATE products SET fts_vector = fts_vector WHERE id = NEW.product_id;
        IF OLD.product_id != NEW.product_id THEN
            PERFORM update_product_cached_brands(OLD.product_id);
            UPDATE products SET fts_vector = fts_vector WHERE id = OLD.product_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM update_product_cached_brands(OLD.product_id);
        UPDATE products SET fts_vector = fts_vector WHERE id = OLD.product_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.cascade_profile_fts_update() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.name IS DISTINCT FROM NEW.name OR OLD.username IS DISTINCT FROM NEW.username THEN
        UPDATE posts SET fts_vector = fts_vector WHERE profile_id = NEW.id;
        UPDATE lists SET fts_vector = fts_vector WHERE profile_id = NEW.id;
        UPDATE locations SET fts_vector = fts_vector WHERE brand_id = NEW.id;
        
        IF OLD.name IS DISTINCT FROM NEW.name THEN
            UPDATE products 
            SET cached_brand_names = COALESCE(
                (SELECT string_agg(p.name, ' ') 
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

-- =====================================
-- EMPLOYEE NOTIFICATION TRIGGER FUNCTION
-- =====================================

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
    END IF;
    RETURN NEW;
END;
$$;

-- =====================================
-- NOTIFY BRAND OF EMPLOYEE REQUEST
-- =====================================

CREATE OR REPLACE FUNCTION public.notify_brand_of_employee_request() 
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    brand_profile_id uuid;
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

-- =====================================
-- GIVEAWAY TRIGGERS (schedules notifications)
-- =====================================

CREATE OR REPLACE FUNCTION public.fn_giveaway_triggers() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        -- Schedule giveaway notifications for the creator
        -- The actual follower notifications will be handled by the app or a separate process
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- =====================================
-- POST TASKS (handles post creation side effects)
-- =====================================

CREATE OR REPLACE FUNCTION public.fn_post_tasks() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    profile_record record;
BEGIN
    IF pg_trigger_depth() < 1 THEN 
        IF (TG_OP = 'UPDATE') THEN
            -- Handle hashtags
            IF NEW.message IS NOT NULL THEN
                PERFORM fn_postal_tasks(NEW.id, NEW.message);
            END IF;
            -- Handle geotag
            IF NEW.geotag IS NOT NULL THEN
                NEW.location_id = fn_lookup_location_for_post(NEW.geotag);
            END IF;
            NEW.has_file = NEW.file_id IS NOT NULL;
            RETURN NEW;
        ELSIF (TG_OP = 'INSERT') THEN
            -- Handle hashtags
            IF NEW.message IS NOT NULL THEN
                PERFORM fn_postal_tasks(NEW.id, NEW.message);
            END IF;
            -- Handle geotag
            IF NEW.geotag IS NOT NULL THEN
                NEW.location_id = fn_lookup_location_for_post(NEW.geotag);
            END IF;
            NEW.has_file = NEW.file_id IS NOT NULL;
            RETURN NEW;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

-- =====================================
-- PRODUCT POST INSERT TASKS
-- =====================================

CREATE OR REPLACE FUNCTION public.fn_product_post_insert_tasks() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        DELETE FROM posts_products WHERE post_id = OLD.post_id;
        DELETE FROM posts WHERE id = OLD.post_id;
        DELETE FROM stash WHERE product_id = OLD.id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        RETURN NEW;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- =====================================
-- PROFILE ADMINS TRIGGERS
-- =====================================

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
        SELECT name INTO brand_name FROM profiles WHERE id = NEW.brand_id;
        
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

-- =====================================
-- SET INITIAL FEATURED ITEM SORT ORDER
-- =====================================

CREATE OR REPLACE FUNCTION public.set_initial_featured_item_sort_order() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.sort_order IS NULL THEN
        NEW.sort_order := (
            SELECT COALESCE(MAX(sort_order), -1) + 1
            FROM public.featured_items
            WHERE item_type = NEW.item_type
        );
    END IF;
    RETURN NEW;
END;
$$;

-- =====================================
-- UPDATE ASSOCIATED DATA (when profile updates)
-- =====================================

CREATE OR REPLACE FUNCTION public.update_associated_data() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE products SET updated_at = NOW() 
    WHERE id = ANY(SELECT product_id FROM product_brands WHERE brand_id = NEW.id);
    
    UPDATE posts SET updated_at = NOW() WHERE profile_id = NEW.id;
    UPDATE locations SET updated_at = NOW() WHERE brand_id = NEW.id;
    UPDATE lists SET updated_at = NOW() WHERE profile_id = NEW.id;
    RETURN NEW;
END;
$$;

-- =====================================
-- UPDATE NOTIFICATION IMAGE URL
-- =====================================

CREATE OR REPLACE FUNCTION public.update_notification_image_url() 
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check actor_id and get profile picture if available
    IF NEW.actor_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT avatar_url FROM public.profiles WHERE id = NEW.actor_id LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    -- Check product_id and get thumbnail if available
    IF NEW.product_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT thumbnail_url FROM public.products WHERE id = NEW.product_id LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    -- Check post_id and get image if available
    IF NEW.post_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT file_url FROM public.posts WHERE id = NEW.post_id LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    -- Check giveaway_id and get image if available
    IF NEW.giveaway_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT cover_url FROM public.giveaways WHERE id = NEW.giveaway_id LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    -- Check list_id and get image if available
    IF NEW.list_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT thumbnail_url FROM public.lists WHERE id = NEW.list_id LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    RETURN NEW;
END;
$$;

-- =====================================
-- UPDATE SUBSCRIPTION COUNT
-- =====================================

CREATE OR REPLACE FUNCTION public.update_subscription_count() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE lists
        SET subscription_count = subscription_count + 1
        WHERE id = NEW.list_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE lists
        SET subscription_count = subscription_count - 1
        WHERE id = OLD.list_id;
    END IF;
    RETURN NULL;
END;
$$;
