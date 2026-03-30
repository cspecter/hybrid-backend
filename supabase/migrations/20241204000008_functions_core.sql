-- Core Database Functions
-- Part 1: Utility functions, typesense integration, and edge function callers
-- Updated: Uses profiles instead of users, locations instead of dispensary_locations

-- =====================================
-- UTILITY FUNCTIONS
-- (generate_randome_code and generate_username are in 20241204000003a_utility_functions.sql)
-- =====================================

CREATE OR REPLACE FUNCTION public.count_estimate(query text) 
RETURNS integer
LANGUAGE plpgsql
STRICT
AS $$
DECLARE
    rec record;
    rows integer;
BEGIN
    FOR rec IN EXECUTE 'EXPLAIN ' || query LOOP
        rows := substring(rec."QUERY PLAN" FROM ' rows=([[:digit:]]+)');
        EXIT WHEN rows IS NOT NULL;
    END LOOP;
    RETURN rows;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_json(input_text varchar) 
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    maybe_json json;
BEGIN
    BEGIN
        maybe_json := input_text;
    EXCEPTION WHEN others THEN
        RETURN FALSE;
    END;
    RETURN TRUE;
END;
$$;

-- =====================================
-- TYPESENSE INTEGRATION FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION public._typesense_delete(id text, collection text) 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
    SELECT * INTO r FROM http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-delete',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object('id', id::text, 'collection', collection)::jsonb
    )::http_request);
END;
$$;

CREATE OR REPLACE FUNCTION public._typesense_import() 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    SET statement_timeout TO 600000;
    SELECT * INTO r FROM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
    SELECT * INTO r FROM http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-import',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object('id', 'id')::jsonb
    )::http_request);
END;
$$;

CREATE OR REPLACE FUNCTION public._typesense_import_int(id integer, collection text) 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-import',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object('itemId', id, 'collection', collection)::jsonb
    )::http_request);
END;
$$;

CREATE OR REPLACE FUNCTION public._typesense_import_uuid(id uuid, collection text) 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-import',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object('itemId', id, 'collection', collection)::jsonb
    )::http_request);
END;
$$;

-- =====================================
-- EDGE FUNCTION CALLERS
-- =====================================

CREATE OR REPLACE FUNCTION public._edge_employee_upgrade(uid uuid, email text, name text) 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
    SELECT * INTO r FROM http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/employee_upgrade',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object('id', uid, 'email', email, 'name', name)::jsonb
    )::http_request);
END;
$$;

CREATE OR REPLACE FUNCTION public._edge_notification_runner() 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
    SELECT * INTO r FROM http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/notifications-runner',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object('id', 'id')::jsonb
    )::http_request);
END;
$$;

CREATE OR REPLACE FUNCTION public._edge_push_notifications_runner() 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
    SELECT * INTO r FROM http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/push-notifications',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object('id', 'id')::jsonb
    )::http_request);
END;
$$;

-- =====================================
-- CLEANUP AND MAINTENANCE FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION public._add_sort_to_products() 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT id FROM products p 
        WHERE gallery_sort = '{}'::uuid[] 
        AND (SELECT count(*) FROM products_cloud_files WHERE product_id = p.id) > 0 
        LIMIT 1000
    LOOP
        UPDATE products SET gallery_sort = (
            SELECT array_agg(cloud_file_id) FROM products_cloud_files WHERE product_id = r.id
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public._clean_up_relationships() 
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM stash WHERE product_id IS NULL OR profile_id IS NULL;
    DELETE FROM product_brands WHERE product_id IS NULL OR brand_id IS NULL;
    DELETE FROM posts_products WHERE product_id IS NULL OR post_id IS NULL;
    DELETE FROM likes WHERE post_id IS NULL OR profile_id IS NULL;
    DELETE FROM lists_products WHERE product_id IS NULL OR list_id IS NULL;
    DELETE FROM relationships WHERE followee_id IS NULL OR follower_id IS NULL;
    DELETE FROM subscriptions_lists WHERE profile_id IS NULL OR list_id IS NULL;
    DELETE FROM analytics_posts WHERE post_id IS NULL OR profile_id IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._products_added_to_list_notification() 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    list_r record;
    list_list record;
BEGIN
    FOR list_r IN 
        SELECT list_id, count(product_id) 
        FROM lists_products 
        WHERE created_at > 'now'::timestamp - '30 minutes'::interval 
        GROUP BY list_id 
        ORDER BY count DESC
    LOOP
        IF EXISTS (SELECT id FROM subscriptions_lists WHERE list_id = list_r.list_id) THEN
            SELECT id, name INTO list_list FROM lists WHERE lists.id = list_r.list_id;
            
            -- Send notification to subscribers
            INSERT INTO notifications (type_id, related_type, related_id, title, body, profile_id) 
            SELECT 
                (SELECT id FROM notification_types WHERE code = 'new_product'),
                'list',
                list_r.list_id, 
                '🎁 New products added', 
                list_r.count || ' new products added to ' || list_list.name || '.', 
                profile_id 
            FROM subscriptions_lists WHERE list_id = list_r.list_id;
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public._select_contest_winners() 
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    SELECT * INTO r FROM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
    SELECT * INTO r FROM http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/giveaway_winner',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object('id', 'id')::jsonb
    )::http_request);
END;
$$;

-- =====================================
-- DELETE/MANAGEMENT FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION public.delete_list(lid uuid) 
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM lists_products l WHERE l.list_id = lid::uuid;
    DELETE FROM subscriptions_lists s WHERE s.list_id = lid::uuid;
    DELETE FROM explore_lists e WHERE e.list_id = lid::uuid;
    DELETE FROM notifications n WHERE n.related_type = 'list' AND n.related_id = lid::uuid;
    DELETE FROM lists WHERE id = lid::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_post(pid uuid) 
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM posts_hashtags WHERE post_id = pid::uuid;
    DELETE FROM likes WHERE post_id = pid::uuid;
    DELETE FROM posts_products WHERE post_id = pid::uuid;
    DELETE FROM explore_posts WHERE post_id = pid::uuid;
    DELETE FROM post_log WHERE post_id = pid::uuid;
    DELETE FROM notifications WHERE related_type = 'post' AND related_id = pid::uuid;
    DELETE FROM posts WHERE id = pid::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION public.flag_post(pid uuid, uid uuid) 
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO post_log (post_id, profile_id, flagged) VALUES (pid, uid, true);
END;
$$;

CREATE OR REPLACE FUNCTION public.merge_profiles(from_id uuid, to_id uuid) 
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Set all products to the new brand
    UPDATE product_brands SET brand_id = to_id WHERE brand_id = from_id;
    -- Set all locations to the new brand
    UPDATE locations SET brand_id = to_id WHERE brand_id = from_id;
    -- Delete old profile
    DELETE FROM profiles WHERE id = from_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_notifications_as_read(uid uuid) 
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE notifications SET is_read = true, read_at = now() WHERE profile_id = uid;
END;
$$;
