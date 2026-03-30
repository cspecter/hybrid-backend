

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






CREATE EXTENSION IF NOT EXISTS "pgroonga" WITH SCHEMA "extensions";






CREATE SCHEMA IF NOT EXISTS "postgraphile_watch";


ALTER SCHEMA "postgraphile_watch" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "postgraphql_watch";


ALTER SCHEMA "postgraphql_watch" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "private";


ALTER SCHEMA "private" OWNER TO "postgres";




ALTER SCHEMA "public" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS '@graphql({"max_rows": 200, "inflect_names": true})';



CREATE EXTENSION IF NOT EXISTS "cube" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "earthdistance" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "fuzzystrmatch" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "http" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgroonga_database" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "unaccent" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."t" AS (
	"a" integer,
	"b" "text"
);


ALTER TYPE "public"."t" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "postgraphile_watch"."notify_watchers_ddl"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  perform pg_notify(
    'postgraphile_watch',
    json_build_object(
      'type',
      'ddl',
      'payload',
      (select json_agg(json_build_object('schema', schema_name, 'command', command_tag)) from pg_event_trigger_ddl_commands() as x)
    )::text
  );
end;
$$;


ALTER FUNCTION "postgraphile_watch"."notify_watchers_ddl"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "postgraphile_watch"."notify_watchers_drop"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  perform pg_notify(
    'postgraphile_watch',
    json_build_object(
      'type',
      'drop',
      'payload',
      (select json_agg(distinct x.schema_name) from pg_event_trigger_dropped_objects() as x)
    )::text
  );
end;
$$;


ALTER FUNCTION "postgraphile_watch"."notify_watchers_drop"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "postgraphql_watch"."notify_watchers_ddl"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  perform pg_notify(
    'postgraphql_watch',
    json_build_object(
      'type',
      'ddl',
      'payload',
      (select json_agg(json_build_object('schema', schema_name, 'command', command_tag)) from pg_event_trigger_ddl_commands() as x)
    )::text
  );
end;
$$;


ALTER FUNCTION "postgraphql_watch"."notify_watchers_ddl"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "postgraphql_watch"."notify_watchers_drop"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  perform pg_notify(
    'postgraphql_watch',
    json_build_object(
      'type',
      'drop',
      'payload',
      (select json_agg(distinct x.schema_name) from pg_event_trigger_dropped_objects() as x)
    )::text
  );
end;
$$;


ALTER FUNCTION "postgraphql_watch"."notify_watchers_drop"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_add_sort_to_products"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE

r record;

BEGIN

  FOR r in select id from products p where gallery_sort = '{}'::uuid[] and (select count(*) from products_cloud_files where products_id = p.id) > 0 limit 1000
  LOOP

  update products set gallery_sort = (select array_agg(cloud_files_id) from products_cloud_files where products_id = r.id);

  END LOOP;


END
$$;


ALTER FUNCTION "public"."_add_sort_to_products"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_clean_up_relationships"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
  BEGIN
       delete from stash where products_id is null or users_id is null;
       delete from products_brands where products_id is null or users_id is null;
       delete from posts_products where products_id is null or posts_id is null;
       delete from likes where posts_id is null or users_id is null;
       delete from lists_products where products_id is null or lists_id is null;
       delete from relationships where followee_id is null or follower_id is null;
       delete from subscriptions_lists where user_id is null or list_id is null;
       delete from products_brands where products_id is null or users_id is null;
       delete from analytics_posts where post_id is null or user_id is null;
    END;
$$;


ALTER FUNCTION "public"."_clean_up_relationships"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_categories_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'categories');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_categories_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_deals_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'deals');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_deals_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_dispensaries_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'dispensaries');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_dispensaries_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_giveaways_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'giveaways');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_giveaways_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_lists_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'lists');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;$$;


ALTER FUNCTION "public"."_delete_lists_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_postal_codes_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'postal_codes');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_postal_codes_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_posts_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'posts');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_posts_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_products_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'products');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_products_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_strains_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            select _typesense_delete(OLD.id::text, 'strains');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_strains_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_delete_users_from_typesense_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            PERFORM _typesense_delete(OLD.id::text, 'users');
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_delete_users_from_typesense_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_edge_employee_upgrade"("uid" "uuid", "email" "text", "name" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
 r record;
begin
SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/employee_upgrade',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('id', uid, 'email', email, 'name', name)::jsonb
        )::http_request);
end;
$$;


ALTER FUNCTION "public"."_edge_employee_upgrade"("uid" "uuid", "email" "text", "name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_edge_notification_runner"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
 r record;
begin
SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/notifications-runner',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('id', 'id')::jsonb
        )::http_request);
end;
$$;


ALTER FUNCTION "public"."_edge_notification_runner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_edge_push_notifications_runner"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
 r record;
begin
SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/push-notifications',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('id', 'id')::jsonb
        )::http_request);
end;
$$;


ALTER FUNCTION "public"."_edge_push_notifications_runner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_delete_product_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
        IF pg_trigger_depth() > 1 THEN
          RETURN OLD;
        END IF;
        IF (TG_OP = 'DELETE') THEN
          -- Remove from lists
          -- delete from lists_products where products_id = OLD.id;

          -- Remove from stash
          -- delete from stash where products_id = OLD.id;

          -- Remove from explore
          -- delete from explore_products where product_id = OLD.id;

          -- Remove from posts
          -- delete from posts_products where products_id = OLD.id;

          -- Remove from giveaways
          -- delete from giveaways where product_id = OLD.id;

          -- Remove from deals
          -- delete from deals where product_id = OLD.id;

          -- Remove sub products
          -- delete from products_products where products_id = OLD.id;
        END IF;
        RETURN OLD; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_delete_product_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_delete_user"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
        IF (TG_OP = 'DELETE') THEN
          -- Remove products
          -- delete from products where products.id in (select products_id from products_brands where users_id = OLD.id);

          delete from products_brands where users_id = OLD.id;

          -- Remove lists
          delete from lists where user_id = OLD.id;

          -- Remove posts
          delete from posts where user_id = OLD.id;

          -- Remove exmplre
          delete from explore_users where user_id = OLD.id;

          -- Delete locations
          delete from dispensary_locations where brand_id = OLD.id;

          -- Remove relationships
          delete from stash where users_id = OLD.id;
          delete from subscriptions_lists where user_id = OLD.id;
          delete from relationships where follower_id = OLD.id OR followee_id = OLD.id;
          delete from addresses where user_id = OLD.id;
          delete from user_brand_admins where user_id = OLD.id OR brand_id = OLD.id;
          delete from likes where users_id = OLD.id;
          delete from giveaway_entries where user_id = OLD.id;
          delete from deal_claims where user_id = OLD.id;
          delete from analytics_posts where user_id = OLD.id;

          RETURN OLD;
        END IF;
        RETURN OLD; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_delete_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_dispensary_on_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            UPDATE users u SET date_updated = now() WHERE u.id = NEW.brand_id;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_dispensary_on_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_likes_insert_tasks"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            -- insert new app notifications
              select name, id into r from users where users.id = (select posts.user_id from posts where posts.id = NEW.posts_id);

            
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_likes_insert_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_list_insert_tasks"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            if NEW.base = false then
              -- insert new app notifications
              select name, id into r from users where users.id = NEW.user_id;

            
            end if;
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_list_insert_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_deals"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            perform _typesense_import_uuid(NEW.id::uuid, 'deals'::text);
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_deals"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_dispensaries"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            perform _typesense_import_uuid(NEW.id::uuid, 'dispensaries'::text);
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_dispensaries"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_giveaways"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            perform _typesense_import_uuid(NEW.id::uuid, 'giveaways'::text);
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_giveaways"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_lists"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            perform _typesense_import_uuid(NEW.id::uuid, 'lists'::text);
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_lists"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_postal_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            -- select _typesense_import_int(NEW.id::int, 'postal_codes'::text);
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_postal_codes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_posts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            perform _typesense_import_uuid(NEW.id::uuid, 'posts'::text);
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_posts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_product_categories"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            perform _typesense_import_uuid(NEW.id::uuid, 'categories'::text);
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_product_categories"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_products"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            perform _typesense_import_uuid(NEW.id::uuid, 'products'::text);
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_products"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_strains"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') OR (TG_OP = 'UPDATE') THEN
            perform _typesense_import_int(NEW.id::int, 'strains');
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_strains"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_typesense_users"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            if (NEW.id is not null) then
                -- perform _typesense_import_uuid(NEW.id::uuid, 'users'::text);
            end IF;
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_typesense_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_fn_user_set_claimed"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
  declare
    r record;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            UPDATE users u SET claimed = true WHERE u.id = NEW.brand_id;
            UPDATE products p SET date_updated = now() where p.id = Any(select pb.products_id from products_brands pb where pb.users_id = NEW.brand_id);
            UPDATE dispensary_locations l SET date_updated = now() where l.brand_id = NEW.brand_id;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."_fn_user_set_claimed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_randome_code"() RETURNS character varying
    LANGUAGE "plpgsql"
    AS $$
declare
  icode varchar = CAST(FLOOR((RANDOM() * (899999) + 100000)) as varchar);
begin
  return iCode;
end;
$$;


ALTER FUNCTION "public"."generate_randome_code"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."dispensary_locations" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "status" character varying(255) DEFAULT 'draft'::character varying NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255),
    "slug" character varying(255),
    "address1" character varying(255),
    "address2" character varying(255),
    "zip_code_id" integer,
    "delivery_details" "text",
    "code" character varying DEFAULT "public"."generate_randome_code"(),
    "message" "text",
    "about_us" "text",
    "postal_code_id" integer,
    "location" "extensions"."geometry"(Point,4326),
    "licenses" "jsonb"[],
    "min_age" integer,
    "verified" boolean,
    "claimed" boolean,
    "social_equity" boolean,
    "has_storefront" boolean,
    "has_pickup" boolean,
    "has_curbside_pickup" boolean,
    "is_brand_preferred_listing" boolean,
    "has_handicap_access" boolean,
    "is_medical" boolean,
    "is_recreational" boolean,
    "has_testing" boolean,
    "has_atm" boolean,
    "has_security_guard" boolean,
    "has_lab_measured_items" boolean,
    "accepts_credit_cards" boolean,
    "member_since" integer,
    "has_delivery" boolean,
    "delivery_radius" real,
    "reviewed" boolean,
    "license_type" character varying(255),
    "brand_id" "uuid",
    "operating_hours" "json" DEFAULT '{"friday_open":"09:30:00","monday_open":"09:30:00","sunday_open":"09:30:00","friday_close":"20:00:00","monday_close":"20:00:00","sunday_close":"20:00:00","tuesday_open":"09:30:00","saturday_open":"10:00:00","thursday_open":"09:30:00","tuesday_close":"20:00:00","saturday_close":"19:00:00","thursday_close":"20:00:00","wednesday_open":"09:30:00","wednesday_close":"20:00:00"}'::"json",
    "contact_info" "json" DEFAULT '{"email":"","phone":"","tiktok":"","twitter":"","website":"","youtube":"","facebook":"","instagram":""}'::"json",
    "banner_id" "uuid" DEFAULT 'fd5bc7dc-55d2-49d0-b006-1c35171f6816'::"uuid",
    "region_id" integer,
    "fts_vector" "tsvector"
);


ALTER TABLE "public"."dispensary_locations" OWNER TO "postgres";


COMMENT ON TABLE "public"."dispensary_locations" IS '@graphql({"name": "DispensaryLocation", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_latitudeondispensary"("rec" "public"."dispensary_locations") RETURNS real
    LANGUAGE "sql" IMMUTABLE
    AS $$
    select st_y(rec.location)
$$;


ALTER FUNCTION "public"."_latitudeondispensary"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_latitudeondispensary"("rec" "public"."dispensary_locations") IS '@graphql({"name": "latitude"})';



CREATE TABLE IF NOT EXISTS "public"."posts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "message" "text",
    "live_time" timestamp with time zone,
    "status" character varying(255) DEFAULT NULL::character varying,
    "pinned" boolean DEFAULT false NOT NULL,
    "like_count" integer DEFAULT 0 NOT NULL,
    "user_id" "uuid",
    "promoted" boolean DEFAULT false NOT NULL,
    "flagged" boolean DEFAULT false,
    "file_id" "uuid",
    "location_id" integer,
    "geotag" "extensions"."geometry"(Point,4326),
    "view_count" integer DEFAULT 0,
    "share_count" integer DEFAULT 0,
    "total_watch_time" integer DEFAULT 0,
    "average_watch_time" integer DEFAULT 0,
    "watched_in_full_count" integer DEFAULT 0,
    "reach_count" integer DEFAULT 0,
    "url" character varying(255),
    "has_file" boolean,
    "flag_count" integer DEFAULT 0,
    "approval_only" boolean DEFAULT false,
    "fts_vector" "tsvector"
);


ALTER TABLE "public"."posts" OWNER TO "postgres";


COMMENT ON TABLE "public"."posts" IS '@graphql({"name": "Post", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_latitudeonpost"("rec" "public"."posts") RETURNS real
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select st_x(rec.geotag)
$$;


ALTER FUNCTION "public"."_latitudeonpost"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_latitudeonpost"("rec" "public"."posts") IS '@graphql({"name": "latitude"})';



CREATE OR REPLACE FUNCTION "public"."_location_on_dispensary"("rec" "public"."dispensary_locations") RETURNS double precision[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array[st_y(rec.location), st_x(rec.location)];
$$;


ALTER FUNCTION "public"."_location_on_dispensary"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_location_on_dispensary"("rec" "public"."dispensary_locations") IS '@graphql({"name": "latlng"})';



CREATE OR REPLACE FUNCTION "public"."_longitudeondispensary"("rec" "public"."dispensary_locations") RETURNS real
    LANGUAGE "sql" IMMUTABLE
    AS $$
    select st_x(rec.location)
$$;


ALTER FUNCTION "public"."_longitudeondispensary"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_longitudeondispensary"("rec" "public"."dispensary_locations") IS '@graphql({"name": "longitude"})';



CREATE OR REPLACE FUNCTION "public"."_longitudeonpost"("rec" "public"."posts") RETURNS real
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select st_y(rec.geotag)
$$;


ALTER FUNCTION "public"."_longitudeonpost"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_longitudeonpost"("rec" "public"."posts") IS '@graphql({"name": "longitude"})';



CREATE TABLE IF NOT EXISTS "public"."regions" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255)
);


ALTER TABLE "public"."regions" OWNER TO "postgres";


COMMENT ON TABLE "public"."regions" IS '@graphql({"name": "Region", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_postal_codes_on_region"("rec" "public"."regions") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(postal_code::TEXT) from postal_codes p left join region_postal_codes rp on rp.region_id = rec.id where rp.region_id = rec.id and p.id = rp.postal_code_id;
$$;


ALTER FUNCTION "public"."_postal_codes_on_region"("rec" "public"."regions") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_postal_codes_on_region"("rec" "public"."regions") IS '@graphql({"name": "s_postal_codes"})';



CREATE OR REPLACE FUNCTION "public"."_products_added_to_list_notification"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  list_r record;
  list_list record;
begin
  for list_r in select lists_id, count(products_id) from lists_products 
    where date_created > 'now'::timestamp - '30 minutes'::interval group by lists_id order by count desc
  loop
    if exists (select id from subscriptions_lists where list_id = list_r.lists_id) then
      select id, name into list_list from lists where lists.id = list_r.lists_id;
      insert into notifications (type_id, list_id, message, user_id) select 7, list_r.lists_id, '🎁 ' || list_r.count || ' new products added to ' || list_list.name || '.' , user_id from subscriptions_lists where list_id = list_r.lists_id;

      insert into notifications (type_id, list_id, message, user_id) select 7, list_r.lists_id, '🎁 You added ' || list_r.count || ' new products to ' || list_list.name || '.', user_id from lists where lists.id = list_r.lists_id;
    end if;
  end loop;
end;
$$;


ALTER FUNCTION "public"."_products_added_to_list_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_restash_notification"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  
end;
$$;


ALTER FUNCTION "public"."_restash_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_select_contest_winners"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  r record;
begin
  -- for g in select * from giveaways where selected_winner = false and end_time <= now() loop
  --   select * into p from select_giveaway_contest_winner(g.id); 
  -- end loop;
  SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/giveaway_winner',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('id', 'id')::jsonb
        )::http_request);
end;
$$;


ALTER FUNCTION "public"."_select_contest_winners"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255),
    "slug" character varying(255),
    "category_id" "uuid",
    "status" character varying(255) DEFAULT 'draft'::character varying,
    "description" "text",
    "stash_count" integer DEFAULT 0 NOT NULL,
    "list_count" integer DEFAULT 0 NOT NULL,
    "price" real,
    "release_date" timestamp with time zone,
    "url" "text",
    "fts" "tsvector" GENERATED ALWAYS AS (("setweight"("to_tsvector"('"english"'::"regconfig", (COALESCE("name", ''::character varying))::"text"), 'A'::"char") || "setweight"("to_tsvector"('"english"'::"regconfig", COALESCE("description", ''::"text")), 'B'::"char"))) STORED,
    "giveawayAmount" integer,
    "thumbnail_id" "uuid" DEFAULT 'c022c6eb-52c0-4a1c-bef5-a5eb6e1e873e'::"uuid",
    "cover_id" "uuid" DEFAULT '16942464-c682-4bcc-b8fe-3bc985541d48'::"uuid",
    "additional_information" "json" DEFAULT '{}'::"json",
    "post_id" "uuid",
    "post_count" integer DEFAULT 0,
    "verified" boolean,
    "reviewed" boolean DEFAULT true,
    "brand_count" integer DEFAULT 0,
    "gallery_sort" "uuid"[] DEFAULT '{}'::"uuid"[],
    "fts_vector" "tsvector",
    "cached_brand_names" "text"
);


ALTER TABLE "public"."products" OWNER TO "postgres";


COMMENT ON TABLE "public"."products" IS '@graphql({"name": "Product", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_sub_product_count"("rec" "public"."products") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select count(id) from products_products where products_id = rec.id;
$$;


ALTER FUNCTION "public"."_sub_product_count"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_sub_product_count"("rec" "public"."products") IS '@graphql({"name": "subProductCount"})';



CREATE TABLE IF NOT EXISTS "public"."cannabis_strains" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255),
    "slug" character varying(255),
    "type_id" integer,
    "thc" integer,
    "cbd" integer,
    "cbn" integer,
    "rating" real,
    "description" "text",
    "breeder_id" integer,
    "cultivation_description" "text",
    "aliases" character varying[],
    "avatar_id" "uuid",
    "banner_id" "uuid"
);


ALTER TABLE "public"."cannabis_strains" OWNER TO "postgres";


COMMENT ON TABLE "public"."cannabis_strains" IS '@graphql({"name": "Strain", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_ts_cannabis_strains_date_created"("rec" "public"."cannabis_strains") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_created);
$$;


ALTER FUNCTION "public"."_ts_cannabis_strains_date_created"("rec" "public"."cannabis_strains") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_cannabis_strains_date_created"("rec" "public"."cannabis_strains") IS '@graphql({"name": "s_dateCreated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_cannabis_strains_date_updated"("rec" "public"."cannabis_strains") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_updated);
$$;


ALTER FUNCTION "public"."_ts_cannabis_strains_date_updated"("rec" "public"."cannabis_strains") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_cannabis_strains_date_updated"("rec" "public"."cannabis_strains") IS '@graphql({"name": "s_dateUpdated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_cannabis_strains_id"("rec" "public"."cannabis_strains") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_cannabis_strains_id"("rec" "public"."cannabis_strains") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_cannabis_strains_id"("rec" "public"."cannabis_strains") IS '@graphql({"name": "_id"})';



CREATE TABLE IF NOT EXISTS "public"."deals" (
    "id" "uuid" NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "expiration_date" timestamp without time zone,
    "release_date" timestamp without time zone,
    "percent_off" real,
    "dollar_off" real,
    "product_id" "uuid",
    "total_deals" integer,
    "claimed_deals" integer DEFAULT 0,
    "expired" boolean DEFAULT false,
    "bogo_percent_off" numeric(10,5),
    "bogo_dollar_off" real,
    "conditions" "text",
    "header_message" character varying(60),
    "description" "text",
    "is_medical" boolean DEFAULT false,
    "is_recreational" boolean DEFAULT false
);


ALTER TABLE "public"."deals" OWNER TO "postgres";


COMMENT ON TABLE "public"."deals" IS '@graphql({"name": "Deal", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_brand_names"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct u.name) from deals_dispensary_locations left join dispensary_locations dl on dl.id = dispensary_locations_id left join users u on u.id = dl.brand_id where deals_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_deals_brand_names"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_brand_names"("rec" "public"."deals") IS '@graphql({"name": "s_brand_names"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_cities"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct pc.place_name) from deals_dispensary_locations left join dispensary_locations dl on dl.id = dispensary_locations_id left join postal_codes pc on pc.id = dl.postal_code where deals_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_deals_cities"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_cities"("rec" "public"."deals") IS '@graphql({"name": "s_cities"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_date_created"("rec" "public"."deals") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_created);
$$;


ALTER FUNCTION "public"."_ts_deals_date_created"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_date_created"("rec" "public"."deals") IS '@graphql({"name": "s_dateCreated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_date_updated"("rec" "public"."deals") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_updated);
$$;


ALTER FUNCTION "public"."_ts_deals_date_updated"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_date_updated"("rec" "public"."deals") IS '@graphql({"name": "s_dateUpdated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_expirationdate"("rec" "public"."deals") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.expiration_date);
$$;


ALTER FUNCTION "public"."_ts_deals_expirationdate"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_expirationdate"("rec" "public"."deals") IS '@graphql({"name": "s_expirationDate"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_id"("rec" "public"."deals") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_deals_id"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_id"("rec" "public"."deals") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_latlng"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(json_build_array(st_x(dl.location), st_y(dl.location))) from deals_dispensary_locations left join dispensary_locations dl on dl.id = dispensary_locations_id where deals_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_deals_latlng"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_latlng"("rec" "public"."deals") IS '@graphql({"name": "s_latlng"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_location_names"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct dl.name) from deals_dispensary_locations left join dispensary_locations dl on dl.id = dispensary_locations_id where deals_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_deals_location_names"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_location_names"("rec" "public"."deals") IS '@graphql({"name": "s_location_names"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_postal_codes"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct pc.postal_code) from deals_dispensary_locations left join dispensary_locations dl on dl.id = dispensary_locations_id left join postal_codes pc on pc.id = dl.postal_code where deals_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_deals_postal_codes"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_postal_codes"("rec" "public"."deals") IS '@graphql({"name": "s_postal_codes"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_product_category"("rec" "public"."deals") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.name from products p left join product_categories pc on pc.id = category_id where p.id = rec.product_id;
$$;


ALTER FUNCTION "public"."_ts_deals_product_category"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_product_category"("rec" "public"."deals") IS '@graphql({"name": "s_product_category"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_product_name"("rec" "public"."deals") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select name from products where id = rec.product_id;
$$;


ALTER FUNCTION "public"."_ts_deals_product_name"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_product_name"("rec" "public"."deals") IS '@graphql({"name": "s_product_name"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_releasedate"("rec" "public"."deals") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.release_date);
$$;


ALTER FUNCTION "public"."_ts_deals_releasedate"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_releasedate"("rec" "public"."deals") IS '@graphql({"name": "s_releaseDate"})';



CREATE OR REPLACE FUNCTION "public"."_ts_deals_states"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct pc.state) from deals_dispensary_locations left join dispensary_locations dl on dl.id = dispensary_locations_id left join postal_codes pc on pc.id = dl.postal_code where deals_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_deals_states"("rec" "public"."deals") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_deals_states"("rec" "public"."deals") IS '@graphql({"name": "s_states"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_brand_name"("rec" "public"."dispensary_locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select name from users where id = rec.brand_id;
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_brand_name"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_brand_name"("rec" "public"."dispensary_locations") IS '@graphql({"name": "s_brand_name"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_city"("rec" "public"."dispensary_locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.place_name from postal_codes pc where pc.id = rec.postal_code;
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_city"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_city"("rec" "public"."dispensary_locations") IS '@graphql({"name": "s_city"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_date_created"("rec" "public"."dispensary_locations") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_created);
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_date_created"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_date_created"("rec" "public"."dispensary_locations") IS '@graphql({"name": "s_dateCreated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_date_updated"("rec" "public"."dispensary_locations") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_updated);
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_date_updated"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_date_updated"("rec" "public"."dispensary_locations") IS '@graphql({"name": "s_dateUpdated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_employees"("rec" "public"."dispensary_locations") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(user_id) from dispensary_employees where dispensary_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_employees"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_employees"("rec" "public"."dispensary_locations") IS '@graphql({"name": "s_employees"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_id"("rec" "public"."dispensary_locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_id"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_id"("rec" "public"."dispensary_locations") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_latlng"("rec" "public"."dispensary_locations") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_build_array(st_x(rec.location), st_y(rec.location));
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_latlng"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_latlng"("rec" "public"."dispensary_locations") IS '@graphql({"name": "s_latlng"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_postal_code"("rec" "public"."dispensary_locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.postal_code from postal_codes pc where pc.id = rec.postal_code;
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_postal_code"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_postal_code"("rec" "public"."dispensary_locations") IS '@graphql({"name": "s_postal_code"})';



CREATE OR REPLACE FUNCTION "public"."_ts_dispensary_locations_state"("rec" "public"."dispensary_locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.state from postal_codes pc where pc.id = rec.postal_code;
$$;


ALTER FUNCTION "public"."_ts_dispensary_locations_state"("rec" "public"."dispensary_locations") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_dispensary_locations_state"("rec" "public"."dispensary_locations") IS '@graphql({"name": "s_state"})';



CREATE TABLE IF NOT EXISTS "public"."giveaways" (
    "id" "uuid" NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "start_time" timestamp with time zone,
    "end_time" timestamp with time zone,
    "total_prizes" integer,
    "product_id" "uuid",
    "terms_url" character varying(255) DEFAULT 'https://gethybrid.co/sweepstakes-terms-and-conditions'::character varying,
    "selected_winner" boolean DEFAULT false,
    "name" character varying(255),
    "description" "text",
    "cover_id" "uuid",
    "redeemed" boolean DEFAULT false,
    "entry_count" integer DEFAULT 0 NOT NULL,
    "winner_count" integer DEFAULT 0,
    "fts_vector" "tsvector"
);


ALTER TABLE "public"."giveaways" OWNER TO "postgres";


COMMENT ON TABLE "public"."giveaways" IS '@graphql({"name": "Giveaway", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_brand_names"("rec" "public"."giveaways") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(u.name) from products_brands left join users u on u.id = users_id where products_id = rec.product_id;
$$;


ALTER FUNCTION "public"."_ts_giveaways_brand_names"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_brand_names"("rec" "public"."giveaways") IS '@graphql({"name": "s_brand_names"})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_date_created"("rec" "public"."giveaways") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_created);
$$;


ALTER FUNCTION "public"."_ts_giveaways_date_created"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_date_created"("rec" "public"."giveaways") IS '@graphql({"name": "s_dateCreated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_date_updated"("rec" "public"."giveaways") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_updated);
$$;


ALTER FUNCTION "public"."_ts_giveaways_date_updated"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_date_updated"("rec" "public"."giveaways") IS '@graphql({"name": "s_dateUpdated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_end_time"("rec" "public"."giveaways") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.end_time);
$$;


ALTER FUNCTION "public"."_ts_giveaways_end_time"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_end_time"("rec" "public"."giveaways") IS '@graphql({"name": "s_endTime"})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_id"("rec" "public"."giveaways") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_giveaways_id"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_id"("rec" "public"."giveaways") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_postal_codes"("rec" "public"."giveaways") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select coalesce(array_agg(pc.postal_code), '{"00000"}'::text[]) from giveaways_regions g left join region_postal_codes rpc on rpc.region_id = g.region_id left join postal_codes pc on pc.id = rpc.postal_code_id where g.giveaway_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_giveaways_postal_codes"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_postal_codes"("rec" "public"."giveaways") IS '@graphql({"name": "s_postal_codes"})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_product_categories"("rec" "public"."giveaways") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.name from products p left join product_categories pc on pc.id = category_id where p.id = rec.product_id;
$$;


ALTER FUNCTION "public"."_ts_giveaways_product_categories"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_product_categories"("rec" "public"."giveaways") IS '@graphql({"name": "s_product_category"})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_product_name"("rec" "public"."giveaways") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select name from products where id = rec.product_id;
$$;


ALTER FUNCTION "public"."_ts_giveaways_product_name"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_product_name"("rec" "public"."giveaways") IS '@graphql({"name": "s_product_name"})';



CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_start_time"("rec" "public"."giveaways") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.start_time);
$$;


ALTER FUNCTION "public"."_ts_giveaways_start_time"("rec" "public"."giveaways") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_giveaways_start_time"("rec" "public"."giveaways") IS '@graphql({"name": "s_startTime"})';



CREATE TABLE IF NOT EXISTS "public"."lists" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255),
    "description" "text",
    "product_count" integer DEFAULT 0 NOT NULL,
    "user_id" "uuid",
    "base" boolean DEFAULT false,
    "thumbnail_id" "uuid" DEFAULT 'c022c6eb-52c0-4a1c-bef5-a5eb6e1e873e'::"uuid",
    "background_id" "uuid" DEFAULT 'fd5bc7dc-55d2-49d0-b006-1c35171f6816'::"uuid",
    "sort" "uuid"[] DEFAULT '{}'::"uuid"[],
    "fts_vector" "tsvector",
    "subscription_count" integer DEFAULT 0
);


ALTER TABLE "public"."lists" OWNER TO "postgres";


COMMENT ON TABLE "public"."lists" IS '@graphql({"name": "List", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_ts_lists_display_name"("rec" "public"."lists") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select name from users where users.id = rec.user_id;
$$;


ALTER FUNCTION "public"."_ts_lists_display_name"("rec" "public"."lists") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_lists_display_name"("rec" "public"."lists") IS '@graphql({"name": "s_display_name"})';



CREATE OR REPLACE FUNCTION "public"."_ts_lists_id"("rec" "public"."lists") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_lists_id"("rec" "public"."lists") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_lists_id"("rec" "public"."lists") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_lists_product_categories"("rec" "public"."lists") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(Distinct pc.name) from lists_products left join products p on p.id = products_id left join product_categories pc on pc.id = p.category_id where lists_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_lists_product_categories"("rec" "public"."lists") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_lists_product_categories"("rec" "public"."lists") IS '@graphql({"name": "s_product_categories"})';



CREATE OR REPLACE FUNCTION "public"."_ts_lists_product_category_ids"("rec" "public"."lists") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(Distinct pc.id) from lists_products left join products p on p.id = products_id left join product_categories pc on pc.id = p.category_id where lists_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_lists_product_category_ids"("rec" "public"."lists") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_lists_product_category_ids"("rec" "public"."lists") IS '@graphql({"name": "s_product_category_ids"})';



CREATE OR REPLACE FUNCTION "public"."_ts_lists_product_ids"("rec" "public"."lists") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(products_id) from lists_products where lists_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_lists_product_ids"("rec" "public"."lists") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_lists_product_ids"("rec" "public"."lists") IS '@graphql({"name": "s_product_ids"})';



CREATE OR REPLACE FUNCTION "public"."_ts_lists_product_names"("rec" "public"."lists") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(p.name) from lists_products left join products p on p.id = products_id where lists_id =rec.id;
$$;


ALTER FUNCTION "public"."_ts_lists_product_names"("rec" "public"."lists") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_lists_product_names"("rec" "public"."lists") IS '@graphql({"name": "s_product_names"})';



CREATE OR REPLACE FUNCTION "public"."_ts_lists_user_id"("rec" "public"."lists") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.user_id;
$$;


ALTER FUNCTION "public"."_ts_lists_user_id"("rec" "public"."lists") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_lists_user_id"("rec" "public"."lists") IS '@graphql({"name": "s_user_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_lists_username"("rec" "public"."lists") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select username from users where users.id = rec.user_id;
$$;


ALTER FUNCTION "public"."_ts_lists_username"("rec" "public"."lists") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_lists_username"("rec" "public"."lists") IS '@graphql({"name": "s_username"})';



CREATE TABLE IF NOT EXISTS "public"."postal_codes" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "country_code" character varying(255),
    "postal_code" character varying(255),
    "place_name" character varying(255),
    "state" character varying(255),
    "state_code" character varying(255),
    "county" character varying(255),
    "county_code" character varying(255),
    "community" character varying(255),
    "community_code" character varying(255),
    "latitude" real,
    "longitude" real,
    "accuracy" integer,
    "geom" "extensions"."geometry"
);


ALTER TABLE "public"."postal_codes" OWNER TO "postgres";


COMMENT ON TABLE "public"."postal_codes" IS '@graphql({"name": "PostalCode", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_ts_postal_codes_id"("rec" "public"."postal_codes") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_postal_codes_id"("rec" "public"."postal_codes") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_postal_codes_id"("rec" "public"."postal_codes") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_postal_codes_latlng"("rec" "public"."postal_codes") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array[rec.latitude, rec.latitude];
$$;


ALTER FUNCTION "public"."_ts_postal_codes_latlng"("rec" "public"."postal_codes") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_postal_codes_latlng"("rec" "public"."postal_codes") IS '@graphql({"name": "s_latlng"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_city"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select place_name from postal_codes where id = rec.location_id;
$$;


ALTER FUNCTION "public"."_ts_posts_city"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_city"("rec" "public"."posts") IS '@graphql({"name": "s_city"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_date_created"("rec" "public"."posts") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_created);
$$;


ALTER FUNCTION "public"."_ts_posts_date_created"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_date_created"("rec" "public"."posts") IS '@graphql({"name": "s_dateCreated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_date_updated"("rec" "public"."posts") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_updated);
$$;


ALTER FUNCTION "public"."_ts_posts_date_updated"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_date_updated"("rec" "public"."posts") IS '@graphql({"name": "s_dateUpdated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_display_name"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select name from users where users.id = rec.user_id;
$$;


ALTER FUNCTION "public"."_ts_posts_display_name"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_display_name"("rec" "public"."posts") IS '@graphql({"name": "s_display_name"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_id"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_id"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_id"("rec" "public"."posts") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_list_ids"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(list_id) from posts_lists where post_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_list_ids"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_list_ids"("rec" "public"."posts") IS '@graphql({"name": "s_list_ids"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_list_names"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(l.name) from posts_lists left join lists l on l.id = list_id where post_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_list_names"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_list_names"("rec" "public"."posts") IS '@graphql({"name": "s_list_names"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_location"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array[latitude, longitude] from postal_codes where id = rec.location_id;
$$;


ALTER FUNCTION "public"."_ts_posts_location"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_location"("rec" "public"."posts") IS '@graphql({"name": "s_latlng"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_product_categories"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(Distinct pc.name) from posts_products left join products p on p.id = products_id left join product_categories pc on pc.id = p.category_id where posts_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_product_categories"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_product_categories"("rec" "public"."posts") IS '@graphql({"name": "s_product_categories"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_product_category_ids"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(Distinct pc.id) from posts_products left join products p on p.id = products_id left join product_categories pc on pc.id = p.category_id where posts_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_product_category_ids"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_product_category_ids"("rec" "public"."posts") IS '@graphql({"name": "s_product_category_ids"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_product_ids"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(products_id) from posts_products where posts_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_product_ids"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_product_ids"("rec" "public"."posts") IS '@graphql({"name": "s_product_ids"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_product_names"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(p.name) from posts_products left join products p on p.id = products_id where posts_id =rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_product_names"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_product_names"("rec" "public"."posts") IS '@graphql({"name": "s_product_names"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_region"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select state from postal_codes where id = rec.location_id;
$$;


ALTER FUNCTION "public"."_ts_posts_region"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_region"("rec" "public"."posts") IS '@graphql({"name": "s_region"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_tags"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(distinct pt.tag) from posts_hashtags left join post_tags pt on pt.id = post_tags_id where posts_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_tags"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_tags"("rec" "public"."posts") IS '@graphql({"name": "s_tags"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_user_id"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.user_id;
$$;


ALTER FUNCTION "public"."_ts_posts_user_id"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_user_id"("rec" "public"."posts") IS '@graphql({"name": "s_user_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_user_ids"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(user_id) from posts_users where post_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_user_ids"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_user_ids"("rec" "public"."posts") IS '@graphql({"name": "s_user_ids"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_user_names"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(u.name) from posts_users left join users u on u.id = user_id where post_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_user_names"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_user_names"("rec" "public"."posts") IS '@graphql({"name": "s_user_names"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_user_usernames"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(u.username) from posts_users left join users u on u.id = user_id where post_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_posts_user_usernames"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_user_usernames"("rec" "public"."posts") IS '@graphql({"name": "s_user_usernames"})';



CREATE OR REPLACE FUNCTION "public"."_ts_posts_username"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select username from users where users.id = rec.user_id;
$$;


ALTER FUNCTION "public"."_ts_posts_username"("rec" "public"."posts") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_posts_username"("rec" "public"."posts") IS '@graphql({"name": "s_username"})';



CREATE TABLE IF NOT EXISTS "public"."product_categories" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" character varying(255),
    "parent_id" "uuid",
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fts" "tsvector" GENERATED ALWAYS AS ("to_tsvector"('"english"'::"regconfig", ("name")::"text")) STORED,
    "slug" character varying(255),
    "description" character varying(255),
    "image_id" "uuid",
    "product_count" integer DEFAULT 0,
    "hidden" boolean DEFAULT false
);


ALTER TABLE "public"."product_categories" OWNER TO "postgres";


COMMENT ON TABLE "public"."product_categories" IS '@graphql({"name": "ProductCategory"})';



CREATE OR REPLACE FUNCTION "public"."_ts_product_categories_id"("rec" "public"."product_categories") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_product_categories_id"("rec" "public"."product_categories") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_product_categories_id"("rec" "public"."product_categories") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_brand"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(u.name) from products_brands left join users u on u.id = users_id where products_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_products_brand"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_brand"("rec" "public"."products") IS '@graphql({"name": "s_brand"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_brand_ids"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(users_id) from products_brands where products_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_products_brand_ids"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_brand_ids"("rec" "public"."products") IS '@graphql({"name": "s_brand_ids"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_category"("rec" "public"."products") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select coalesce(id::text, '__NULL__') from product_categories where id = rec.category_id;
$$;


ALTER FUNCTION "public"."_ts_products_category"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_category"("rec" "public"."products") IS '@graphql({"name": "s_product_category_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_date_created"("rec" "public"."products") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_created);
$$;


ALTER FUNCTION "public"."_ts_products_date_created"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_date_created"("rec" "public"."products") IS '@graphql({"name": "s_dateCreated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_date_updated"("rec" "public"."products") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_updated);
$$;


ALTER FUNCTION "public"."_ts_products_date_updated"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_date_updated"("rec" "public"."products") IS '@graphql({"name": "s_dateUpdated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_features"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(f.name) from products_product_features_2 left join product_features f on f.id = product_feature_id where product_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_products_features"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_features"("rec" "public"."products") IS '@graphql({"name": "s_features"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_id"("rec" "public"."products") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_products_id"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_id"("rec" "public"."products") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_releasedate"("rec" "public"."products") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.release_date);
$$;


ALTER FUNCTION "public"."_ts_products_releasedate"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_releasedate"("rec" "public"."products") IS '@graphql({"name": "s_releaseDate"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_sub_product_ids"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(pa.id) from products_products left join products pa on pa.id = products_related_id where products_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_products_sub_product_ids"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_sub_product_ids"("rec" "public"."products") IS '@graphql({"name": "s_sub_product_ids"})';



CREATE OR REPLACE FUNCTION "public"."_ts_products_sub_products"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(pa.name) from products_products left join products pa on pa.id = products_related_id where products_id = rec.id;
$$;


ALTER FUNCTION "public"."_ts_products_sub_products"("rec" "public"."products") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_products_sub_products"("rec" "public"."products") IS '@graphql({"name": "s_sub_products"})';



CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "status" "text" DEFAULT 'published'::"text",
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255) DEFAULT NULL::character varying,
    "phone" character varying(255),
    "email" character varying(255),
    "slug" "text" DEFAULT "extensions"."uuid_generate_v4"(),
    "birthday" "date",
    "role_id" integer DEFAULT 10,
    "description" "text",
    "instagram" character varying(255),
    "twitter" character varying(255),
    "website" character varying(255),
    "follower_count" integer DEFAULT 0 NOT NULL,
    "like_count" integer DEFAULT 0 NOT NULL,
    "reminder_count" integer DEFAULT 0 NOT NULL,
    "post_count" integer DEFAULT 0 NOT NULL,
    "stash_count" integer DEFAULT 0 NOT NULL,
    "list_count" integer DEFAULT 0 NOT NULL,
    "following_count" integer DEFAULT 0 NOT NULL,
    "facebook" character varying(255),
    "founded_date" character varying(255),
    "home_location" character varying(255),
    "product_count" integer DEFAULT 0,
    "fts" "tsvector" GENERATED ALWAYS AS (("setweight"("to_tsvector"('"english"'::"regconfig", (COALESCE("name", ''::character varying))::"text"), 'A'::"char") || "setweight"("to_tsvector"('"english"'::"regconfig", COALESCE("description", ''::"text")), 'B'::"char"))) STORED,
    "profile_picture_id" "uuid" DEFAULT '015fbaac-57b0-4bd5-9c51-af6ab02cf741'::"uuid",
    "banner_id" "uuid" DEFAULT 'fd5bc7dc-55d2-49d0-b006-1c35171f6816'::"uuid",
    "home_locale_id" integer,
    "desktop_banner_id" "uuid",
    "verified" boolean,
    "claimed" boolean,
    "reviewed" boolean DEFAULT true,
    "youtube" character varying(255),
    "linkedin" character varying(255),
    "username" character varying(255),
    "contact_phone" character varying(255),
    "contact_email" character varying(255),
    "tiktok" character varying(255),
    "restash_count" integer DEFAULT 0,
    "last_location_id" integer,
    "last_login" timestamp without time zone,
    "dispensary_count" integer DEFAULT 0,
    "is_employee" boolean DEFAULT false,
    "is_private" boolean DEFAULT false,
    "online_shop_url" "text",
    "fts_vector" "tsvector"
);


ALTER TABLE "public"."users" OWNER TO "postgres";


COMMENT ON TABLE "public"."users" IS '@graphql({"name": "User", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_ts_users_date_created"("rec" "public"."users") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_created);
$$;


ALTER FUNCTION "public"."_ts_users_date_created"("rec" "public"."users") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_users_date_created"("rec" "public"."users") IS '@graphql({"name": "s_dateCreated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_users_date_updated"("rec" "public"."users") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.date_updated);
$$;


ALTER FUNCTION "public"."_ts_users_date_updated"("rec" "public"."users") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_users_date_updated"("rec" "public"."users") IS '@graphql({"name": "s_dateUpdated"})';



CREATE OR REPLACE FUNCTION "public"."_ts_users_id"("rec" "public"."users") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;


ALTER FUNCTION "public"."_ts_users_id"("rec" "public"."users") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_ts_users_id"("rec" "public"."users") IS '@graphql({"name": "_id"})';



CREATE OR REPLACE FUNCTION "public"."_typesense_delete"("id" "text", "collection" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
 r record;
begin
SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-delete',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('id', id::text, 'collection', collection)::jsonb
        )::http_request);
end;
$$;


ALTER FUNCTION "public"."_typesense_delete"("id" "text", "collection" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_typesense_import"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$declare
 r record;
begin
set statement_timeout to 600000;
SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-import',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('id', 'id')::jsonb
        )::http_request);
end;$$;


ALTER FUNCTION "public"."_typesense_import"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_typesense_import_int"("id" integer, "collection" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
 r record;
begin
select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-import',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('itemId', id, 'collection', collection)::jsonb
        )::http_request);
end;
$$;


ALTER FUNCTION "public"."_typesense_import_int"("id" integer, "collection" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_typesense_import_uuid"("id" "uuid", "collection" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
 r record;
begin
select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-import',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('itemId', id, 'collection', collection)::jsonb
        )::http_request);
end;
$$;


ALTER FUNCTION "public"."_typesense_import_uuid"("id" "uuid", "collection" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "message" character varying(255),
    "read" boolean DEFAULT false,
    "actor_id" "uuid",
    "post_id" "uuid",
    "product_id" "uuid",
    "giveaway_id" "uuid",
    "list_id" "uuid",
    "type_id" integer,
    "image_url" "text"
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


COMMENT ON TABLE "public"."notifications" IS '@graphql({"name": "Notification", "totalCount": {"enabled": true}})';



CREATE OR REPLACE FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select count(id) from notifications where read = false and user_id = rec.user_id;
$$;


ALTER FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") IS '@graphql({"name": "unreadNotificationCount"})';



CREATE OR REPLACE FUNCTION "public"."cascade_product_category_fts_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF OLD.name IS DISTINCT FROM NEW.name THEN
    -- Update products in this category
    UPDATE products SET fts_vector = fts_vector WHERE category_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."cascade_product_category_fts_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cascade_product_fts_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF OLD.name IS DISTINCT FROM NEW.name OR OLD.description IS DISTINCT FROM NEW.description THEN
    -- Update posts with this product
    UPDATE posts SET fts_vector = fts_vector 
    WHERE id IN (SELECT posts_id FROM posts_products WHERE products_id = NEW.id);
    
    -- Update lists with this product
    UPDATE lists SET fts_vector = fts_vector 
    WHERE id IN (SELECT lists_id FROM lists_products WHERE products_id = NEW.id);
    
    -- Update giveaways with this product
    UPDATE giveaways SET fts_vector = fts_vector WHERE product_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."cascade_product_fts_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cascade_products_brands_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM update_product_cached_brands(NEW.products_id);
    -- Update the product's FTS vector
    UPDATE products SET fts_vector = fts_vector WHERE id = NEW.products_id;
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM update_product_cached_brands(NEW.products_id);
    UPDATE products SET fts_vector = fts_vector WHERE id = NEW.products_id;
    IF OLD.products_id != NEW.products_id THEN
      PERFORM update_product_cached_brands(OLD.products_id);
      UPDATE products SET fts_vector = fts_vector WHERE id = OLD.products_id;
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM update_product_cached_brands(OLD.products_id);
    UPDATE products SET fts_vector = fts_vector WHERE id = OLD.products_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."cascade_products_brands_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cascade_user_fts_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF OLD.name IS DISTINCT FROM NEW.name OR OLD.username IS DISTINCT FROM NEW.username THEN
    -- Update posts
    UPDATE posts SET fts_vector = fts_vector WHERE user_id = NEW.id;
    -- Update lists
    UPDATE lists SET fts_vector = fts_vector WHERE user_id = NEW.id;
    -- Update dispensary_locations
    UPDATE dispensary_locations SET fts_vector = fts_vector WHERE brand_id = NEW.id;
    
    -- Update cached brand names for products where this user is a brand
    IF OLD.name IS DISTINCT FROM NEW.name THEN
      UPDATE products 
      SET cached_brand_names = COALESCE(
        (SELECT string_agg(u.name, ' ') 
         FROM products_brands pb 
         JOIN users u ON u.id = pb.users_id 
         WHERE pb.products_id = products.id), 
        ''
      )
      WHERE id IN (
        SELECT products_id FROM products_brands WHERE users_id = NEW.id
      );
      
      -- Update FTS vectors for affected products
      UPDATE products SET fts_vector = fts_vector 
      WHERE id IN (
        SELECT products_id FROM products_brands WHERE users_id = NEW.id
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."cascade_user_fts_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_if_deal_expired"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  update deals
  set deals.expired = true
  where deals.expiration_date < now();
end;
$$;


ALTER FUNCTION "public"."check_if_deal_expired"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_notifications"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
   DECLARE
   is_released_start    timestamp := now();
   is_released_end      timestamp := now() - make_interval(mins => 10);
   one_day_start    timestamp := now() + make_interval(days => 1);
   one_day_end      timestamp := now() + make_interval(days => 1, mins => 10);
   seven_day_start    timestamp := now() + make_interval(days => 7);
   seven_day_end      timestamp := now() + make_interval(days => 7, mins => 10);
   p record;
   st json;
   r json;
BEGIN 
   -- Just released
   for p in select id, name, release_date, slug from products where release_date <= is_released_start and is_released_end > one_day_end
   loop
      -- raise warning 'there is an item %', p.id;
      select json_build_array(users_id) into st from stash where products_id = p.id;
      if st is not null then
         -- raise warning 'records %', st || ' ' || to_char(p.release_date, 'Month DD at HH:MI AM');
         select * into r from send_push_noti(
            message => '🔥Out Now 🔥 ' || p.name || ' is available now on Hybrid. Tap to get it now.',
            devices => st,
            data_type => 'R',
            campaign => p.name || ' - Is released.',
            app_url => 'hybrid://gethybrid.co/products/product/' || p.slug
         );
         insert into notifications (type_id, product_id, message, user_id) select 1, p.id, p.name || ' is dropping in one week ' || to_char ( p.release_date, 'MONTH DD, YYYY' ) || '.' , users_id from stash where products_id = p.id;
      end if;
   end loop;

   -- One day
   for p in select id, name, release_date, slug from products where release_date >= one_day_start and release_date < one_day_end
   loop
      -- raise warning 'there is an item %', p.id;
      select json_build_array(users_id) into st from stash where products_id = p.id;
      if st is not null then
         -- raise warning 'records %', st || ' ' || to_char(p.release_date, 'Month DD at HH:MI AM');
         select * into r from send_push_noti(
            message => '👀 Get ready! ' || p.name || ' is dropping in just 24 hours.',
            devices => st,
            data_type => '1D',
            campaign => p.name || ' - Releasing in one day',
            app_url => 'hybrid://gethybrid.co/products/product/' || p.slug
         );
         insert into notifications (type_id, product_id, message, user_id) select 2, p.id, p.name || ' is dropping in one day at ' || to_char ( p.release_date, 'HH:MI AM' ) || '.' , users_id from stash where products_id = p.id;
      end if;
   end loop;

   -- Seven days
   for p in select id, name, release_date, slug from products where release_date >= seven_day_start and release_date < seven_day_end
   loop
      -- raise warning 'there is an item %', p.id;
      select json_build_array(users_id) into st from stash where products_id = p.id;
      if st is not null then
         -- raise warning 'records %', st || ' ' || to_char(p.release_date, 'Month DD at HH:MI AM');
         select * into r from send_push_noti(
            message => '⏰ ' || p.name || ' is one week away! Releasing on ' || to_char(p.release_date, 'Month DD at HH:MI AM') || '.',
            devices => st,
            data_type => '7D',
            campaign => p.name || ' - Releasing in one day',
            app_url => 'hybrid://gethybrid.co/products/product/' || p.slug
         );
         insert into notifications (type_id, product_id, message, user_id) select 3, p.id, p.name || ' is now available.' , users_id from stash where products_id = p.id;
      end if;
   end loop;
END;
$$;


ALTER FUNCTION "public"."check_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_update_permissions"() RETURNS TABLE("table_name" "text", "has_update_permission" boolean, "message" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  can_update boolean;
BEGIN
  -- Check products table update permission
  BEGIN
    -- Try to update a non-existent product (safe test)
    EXECUTE 'UPDATE products SET cached_brand_names = cached_brand_names WHERE id = ''00000000-0000-0000-0000-000000000000''';
    can_update := true;
    EXCEPTION WHEN OTHERS THEN
      can_update := false;
  END;
  
  table_name := 'products';
  has_update_permission := can_update;
  message := CASE WHEN can_update 
                 THEN 'You have permission to update the products table'
                 ELSE 'You do NOT have permission to update the products table. Use the generate_*_sql functions instead.'
            END;
  RETURN NEXT;
  
  -- Check products_brands table read permission
  BEGIN
    -- Try to select from products_brands
    EXECUTE 'SELECT COUNT(*) FROM products_brands LIMIT 1';
    can_update := true;
    EXCEPTION WHEN OTHERS THEN
      can_update := false;
  END;
  
  table_name := 'products_brands';
  has_update_permission := can_update;
  message := CASE WHEN can_update 
                 THEN 'You have permission to read from the products_brands table'
                 ELSE 'You do NOT have permission to read from the products_brands table. Brand name population will not work.'
            END;
  RETURN NEXT;
  
  -- Check product_categories table read permission
  BEGIN
    -- Try to select from product_categories
    EXECUTE 'SELECT COUNT(*) FROM product_categories LIMIT 1';
    can_update := true;
    EXCEPTION WHEN OTHERS THEN
      can_update := false;
  END;
  
  table_name := 'product_categories';
  has_update_permission := can_update;
  message := CASE WHEN can_update 
                 THEN 'You have permission to read from the product_categories table'
                 ELSE 'You do NOT have permission to read from the product_categories table. FTS vector updates will be incomplete.'
            END;
  RETURN NEXT;
END;
$$;


ALTER FUNCTION "public"."check_update_permissions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."count_estimate"("query" "text") RETURNS integer
    LANGUAGE "plpgsql" STRICT
    AS $$
DECLARE
  rec   record;
  rows  integer;
BEGIN
  FOR rec IN EXECUTE 'EXPLAIN ' || query LOOP
    rows := substring(rec."QUERY PLAN" FROM ' rows=([[:digit:]]+)');
    EXIT WHEN rows IS NOT NULL;
  END LOOP;
  RETURN rows;
END;
$$;


ALTER FUNCTION "public"."count_estimate"("query" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_file_on_update_related_table"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  DELETE FROM public.files where id = old.id;
  RETURN NULL;
END
$$;


ALTER FUNCTION "public"."delete_file_on_update_related_table"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_list"("lid" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  delete from lists_products l where l.lists_id = lid::uuid;
  delete from subscriptions_lists s where s.list_id = lid::uuid;
  delete from explore_lists e where e.list_id = lid::uuid;
  delete from notifications n where n.list_id = lid::uuid;
  delete from lists where id = lid::uuid;
end;
$$;


ALTER FUNCTION "public"."delete_list"("lid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_post"("pid" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        delete from posts_hashtags where posts_id = pid::uuid;
        delete from likes where posts_id = pid::uuid;
        delete from posts_products where posts_id = pid::uuid;
        delete from explore_posts where post_id = pid::uuid;
        delete from post_log where post_id = pid::uuid;
        delete from notifications where post_id = pid::uuid;
        delete from posts where id = pid::uuid;
    END;
$$;


ALTER FUNCTION "public"."delete_post"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."execute_brand_name_population"("test_limit" integer DEFAULT NULL::integer) RETURNS TABLE("status" "text", "message" "text", "products_processed" integer, "runtime_seconds" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  start_time timestamp;
  end_time timestamp;
  total_count integer;
  processed integer := 0;
  current_batch_size integer;
  batch_size integer := 50;
  error_message text;
BEGIN
  -- Set a longer statement timeout just for this function
  SET LOCAL statement_timeout = '300s';
  
  start_time := clock_timestamp();
  
  -- Get count of products needing updates
  SELECT COUNT(*) INTO total_count 
  FROM products 
  WHERE cached_brand_names IS NULL OR cached_brand_names = '';
  
  -- Apply test limit if provided
  IF test_limit IS NOT NULL AND test_limit > 0 THEN
    total_count := LEAST(total_count, test_limit);
  END IF;
  
  -- Return initial status
  status := 'starting';
  message := 'Starting brand name population for ' || total_count::text || ' products';
  products_processed := 0;
  runtime_seconds := 0;
  RETURN NEXT;
  
  BEGIN
    -- Process in batches to avoid timeouts
    WHILE processed < total_count LOOP
      -- Create a temporary table with the next batch of product IDs
      -- Using OFFSET instead of UUID comparison
      CREATE TEMP TABLE batch_products AS
      SELECT id
      FROM products
      WHERE (cached_brand_names IS NULL OR cached_brand_names = '')
      ORDER BY id
      LIMIT batch_size
      OFFSET processed;
      
      -- Get the number of products in this batch
      SELECT COUNT(*) INTO current_batch_size FROM batch_products;
      
      -- Exit if no more products to process or we've hit the test limit
      IF current_batch_size = 0 OR (test_limit IS NOT NULL AND processed >= test_limit) THEN
        EXIT;
      END IF;
      
      -- Pre-calculate brand names for all products in this batch
      CREATE TEMP TABLE batch_brand_names AS
      SELECT 
        pb.products_id,
        COALESCE(string_agg(u.name, ' '), '') AS brand_names
      FROM products_brands pb
      JOIN users u ON u.id = pb.users_id
      WHERE pb.products_id IN (SELECT id FROM batch_products)
      GROUP BY pb.products_id;
      
      -- Update all products in this batch at once
      WITH updates AS (
        UPDATE products p
        SET cached_brand_names = COALESCE(bn.brand_names, '')
        FROM batch_products bp
        LEFT JOIN batch_brand_names bn ON bn.products_id = bp.id
        WHERE p.id = bp.id
        RETURNING 1
      )
      SELECT COUNT(*) INTO current_batch_size FROM updates;
      
      -- Update progress
      processed := processed + current_batch_size;
      
      -- Drop temporary tables
      DROP TABLE batch_products;
      DROP TABLE batch_brand_names;
      
      -- Return progress
      status := 'progress';
      message := 'Processed ' || processed::text || ' of ' || total_count::text || 
                 ' products (' || round((processed::float / total_count * 100), 1)::text || '%)';
      products_processed := processed;
      runtime_seconds := EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
      RETURN NEXT;
      
      -- Small delay to prevent database overload
      PERFORM pg_sleep(0.1);
    END LOOP;
    
    -- Return completion status
    status := 'completed';
    message := 'Completed: ' || processed::text || ' products processed in ' || 
               round(EXTRACT(EPOCH FROM (clock_timestamp() - start_time)), 1)::text || ' seconds';
    products_processed := processed;
    runtime_seconds := EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RETURN NEXT;
    
  EXCEPTION WHEN OTHERS THEN
    -- Handle any errors
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    
    status := 'error';
    message := error_message;
    products_processed := processed;
    runtime_seconds := EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RETURN NEXT;
  END;
END;
$$;


ALTER FUNCTION "public"."execute_brand_name_population"("test_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fake_credentials"("phone_number" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    update auth.users
    set confirmation_sent_at=now(),
        confirmation_token=encode(sha224(concat(phone_number,'123456')::bytea), 'hex')
    where auth.users.phone = phone_number;

    RETURN 'done!';
END;
$$;


ALTER FUNCTION "public"."fake_credentials"("phone_number" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."flag_post"("pid" "uuid", "uid" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        insert into post_log (post_id, user_id, flagged) values (pid, uid, true);
    END;
$$;


ALTER FUNCTION "public"."flag_post"("pid" "uuid", "uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_add_or_change_list_on_user_name_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'UPDATE') THEN
            IF NEW.name != OLD.name THEN
              if EXISTS (select id from lists WHERE user_id = NEW.id AND base = true) then
                UPDATE lists SET name = NEW.name || '''s list' WHERE user_id = NEW.id AND base = true;
              else
                insert into public.lists(id, base, user_id, name, description)
                values (gen_random_uuid(), true, NEW.id, NEW.name || '''s list', 'A few of my favorite things.');
              end if;
            END IF;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            IF NEW.name IS NOT NULL THEN
              insert into public.lists(id, base, user_id, name, description)
              values (gen_random_uuid(), true, NEW.id, NEW.name || '''s list', 'A few of my favorite things.');
            else
              insert into public.lists(id, base, user_id, name, description)
              values (gen_random_uuid(), true, NEW.id, 'My list', 'A few of my favorite things.');
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_add_or_change_list_on_user_name_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_add_role_id_to_relationship"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$BEGIN
        IF (TG_OP = 'INSERT') THEN
            NEW.role_id = (select role_id from users where users.id = NEW.followee_id);
            
            RETURN NEW;
        END IF;
        RETURN NEW; -- result is ignored since this is an AFTER trigger
    END;$$;


ALTER FUNCTION "public"."fn_add_role_id_to_relationship"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_analytics_post"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    declare
      share_add int;
      exist_view record;
      reach_add int;
      avg_time int;
      avg_compute int;
      in_full_add int;
    BEGIN
        -- IF (TG_OP = 'DELETE') THEN
        --     IF OLD.posts_id IS NOT NULL THEN
        --     UPDATE product SET product.post_count = product.post_count - 1 WHERE id = OLD.products_id;
        --     END IF;
        --     RETURN OLD;
        IF (TG_OP = 'INSERT') THEN
            IF NEW.post_id IS NOT NULL THEN

            if NEW.share_date IS NOT NULL then
            share_add = 1;
            else
            share_add = 0;
            end if;

            select id into exist_view from analytics_posts where analytics_posts.user_id = NEW.user_id;
            if exist_view IS NOT NULL then
            reach_add = 1;
            else
            reach_add = 0;
            end if;

            select average_watch_time into avg_time from posts where id = NEW.post_id;

            if avg_time = 0 then
            avg_compute = NEW.watch_duration;
            else 
            avg_compute = avg_time;
            end if;

            if NEW.watch_in_full = true then
            in_full_add = 1;
            else 
            in_full_add = 0;
            end if;

            update posts set
              view_count = view_count + 1,
              share_count = share_count + share_add,
              total_watch_time = total_watch_time + NEW.watch_duration,
              reach_count = reach_count + reach_add,
              average_watch_time = (avg_compute + NEW.watch_duration) / 2,
              watched_in_full_count = watched_in_full_count + in_full_add
              where id = NEW.post_id;
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_analytics_post"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_brand_count_on_products"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            IF OLD.products_id IS NOT NULL THEN
            UPDATE products SET brand_count = brand_count - 1 WHERE id = OLD.products_id;
            END IF;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            IF NEW.products_id IS NOT NULL THEN
            UPDATE products SET brand_count = brand_count + 1 WHERE id = NEW.products_id;
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_brand_count_on_products"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_category_product_count_on_product"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            IF OLD.category_id IS NOT NULL THEN
            UPDATE product_categories SET product_count = product_count - 1 WHERE id = OLD.category_id;
            END IF;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            IF NEW.category_id IS NOT NULL THEN
            UPDATE product_categories SET product_count = product_count + 1 WHERE id = OLD.category_id;
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_category_product_count_on_product"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_deal_count_on_deals"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_deal_count_on_deals"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_drop_reminder_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE drops SET reminder_count = reminder_count - 1 WHERE id = OLD.drops_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE drops SET reminder_count = reminder_count + 1 WHERE id = NEW.drops_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_drop_reminder_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_follower_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE users SET follower_count = follower_count - 1 WHERE id = OLD.followee_id;
            UPDATE users SET following_count = following_count - 1 WHERE id = OLD.follower_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE users SET follower_count = follower_count + 1 WHERE id = NEW.followee_id;
            UPDATE users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_follower_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_following_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE users SET following_count = following_count - 1 WHERE id = OLD.follower_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_following_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_lists_product_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE lists SET date_updated = NOW(), product_count = product_count - 1 WHERE id = OLD.lists_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE lists SET date_updated = NOW(),product_count = product_count + 1 WHERE id = NEW.lists_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_lists_product_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_post_count_on_users"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            IF OLD.user_id IS NOT NULL THEN
            UPDATE users SET post_count = post_count - 1 WHERE id = OLD.user_id;
            END IF;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            IF NEW.user_id IS NOT NULL THEN
            UPDATE users SET post_count = post_count + 1 WHERE id = NEW.user_id;
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_post_count_on_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_post_product_count_on_product"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            IF OLD.products_id IS NOT NULL THEN
            UPDATE products SET post_count = post_count - 1 WHERE id = OLD.products_id;
            END IF;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            IF NEW.products_id IS NOT NULL THEN
            UPDATE products SET post_count = post_count + 1 WHERE id = NEW.products_id;
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_post_product_count_on_product"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_posts_like_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE posts SET like_count = like_count - 1 WHERE id = OLD.posts_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE posts SET like_count = like_count + 1 WHERE id = NEW.posts_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_posts_like_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_product_count_on_users"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            IF OLD.users_id IS NOT NULL THEN
            UPDATE users SET product_count = product_count - 1 WHERE id = OLD.users_id;
            END IF;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            IF NEW.users_id IS NOT NULL THEN
            UPDATE users SET product_count = product_count + 1 WHERE id = NEW.users_id;
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_product_count_on_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_product_list_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE products SET list_count = list_count - 1 WHERE id = OLD.products_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE products SET list_count = list_count + 1 WHERE id = NEW.products_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_product_list_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_product_stash_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE products SET stash_count = stash_count - 1 WHERE id = OLD.products_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE products SET stash_count = stash_count + 1 WHERE id = NEW.products_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_product_stash_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_tag_on_post_tags"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            IF OLD.post_tags_id IS NOT NULL THEN
            UPDATE post_tags SET post_tags.count = post_tags.count - 1 WHERE id = OLD.post_tags_id;
            END IF;
            RETURN OLD;
        -- ELSIF (TG_OP = 'INSERT') THEN
        --     IF NEW.posts_id IS NOT NULL THEN
        --     UPDATE deals SET deals.count = deals.count + 1 WHERE id = NEW.posts_id;
        --     END IF;
        --     RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;

$$;


ALTER FUNCTION "public"."fn_change_tag_on_post_tags"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_users2_post_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE users SET post_count = post_count - 1 WHERE id = OLD.user_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE users SET post_count = post_count + 1 WHERE id = NEW.user_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_users2_post_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_users_like_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE users SET like_count = like_count - 1 WHERE id = OLD.users_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE users SET like_count = like_count + 1 WHERE id = NEW.users_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_users_like_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_users_post_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE users SET post_count = post_count - 1 WHERE id = OLD.users_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE users SET post_count = post_count + 1 WHERE id = NEW.users_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_users_post_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_users_reminder_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE users SET reminder_count = reminder_count - 1 WHERE id = OLD.users_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE users SET reminder_count = reminder_count + 1 WHERE id = NEW.users_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_change_users_reminder_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_change_users_stash_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE users SET stash_count = stash_count - 1 WHERE id = OLD.users_id;
            update users set restash_count = restash_count - 1 where id = OLD.restash_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE users SET stash_count = stash_count + 1 WHERE id = NEW.users_id;
            update users set restash_count = restash_count + 1 where id = NEW.restash_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;$$;


ALTER FUNCTION "public"."fn_change_users_stash_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_clean_up_cloud_files"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
  BEGIN
       delete from cloud_files
       where
       user_id is null
       and id != '015fbaac-57b0-4bd5-9c51-af6ab02cf741'
       and id != 'fd5bc7dc-55d2-49d0-b006-1c35171f6816'
       and id != '0f2f36ad-7a80-4de2-9af4-7dd9ab767093'
       and id != 'c022c6eb-52c0-4a1c-bef5-a5eb6e1e873e'
       and id != 'c022c6eb-52c0-4a1c-bef5-a5eb6e1e873e'
       and NOT EXISTS (SELECT id FROM products p WHERE p.thumbnail_id = id OR p.cover_id = id) 
       and NOT EXISTS (SELECT id FROM lists l WHERE f.thumbnail_id = id OR f.background_id = id) 
       and NOT EXISTS (SELECT id FROM products_cloud_files gal WHERE gal.cloud_files_id = id) 
       and NOT EXISTS (SELECT id FROM posts post WHERE post.file = id)
       and NOT EXISTS (SELECT id FROM dispensaries WHERE dispensaries.profile_picture_id = id OR dispensaries.deal_header_logo_id = id)
       and NOT EXISTS (SELECT id FROM dispensary_locations_cloud_files dlc WHERE dl.cloud_files_id = id)
       and NOT EXISTS (SELECT id FROM users u WHERE u.profile_picture_id = id OR u.banner_id = id OR u.desktop_banner_id = id)
       and NOT EXISTS (SELECT id FROM cannabis_strains cs WHERE cs.avatar_id = id)
       and NOT EXISTS (SELECT id FROM product_categories pc WHERE pc.image_id = id)
       ;
    END;
$$;


ALTER FUNCTION "public"."fn_clean_up_cloud_files"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_create_admin_account_for_cms"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $_$
    declare
      user_record record;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            IF NEW.user_id IS NOT NULL THEN
              if exists (select * from users where users.id = NEW.user_id limit 1) then
                select * into user_record from users where users.id = NEW.user_id limit 1;
                if user_record.email is not null then
                  if NOT EXISTS (select * from directus_users where id = NEW.user_id) then
                    insert into directus_users (id, first_name, email, password, role)
                  values (user_record.id, user_record.name, user_record.email, '$argon2id$v=19$m=65536,t=3,p=4$p+f6wRlmSBupGmJuKmWOoQ$4DAqoj1wm+JhhOkVLVWuSWDNwIEh8sQZH+Bj5wQGKUU', 'b98bb58b-541e-454c-941c-88332808c814');
                  end if;
                else
                  RAISE EXCEPTION 'User is required to have a email address --> %', NEW.user_id;
                end if;
              else
                RAISE EXCEPTION 'User not found --> %', NEW.user_id;
              end if;
            else
              RAISE EXCEPTION 'There was a problem setting up the admin account --> %', NEW.user_id;            
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$_$;


ALTER FUNCTION "public"."fn_create_admin_account_for_cms"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_create_directus_user_on_admin_add"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $_$
    declare
      curr_user record;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
          select * into curr_user from users where id = NEW.user_id;
          if curr_user is NULL then
            insert into directus_users (id, first_name, email, password, role)
            values (NEW.id, NEW.name, NEW.email, '$argon2id$v=19$m=65536,t=3,p=4$p+f6wRlmSBupGmJuKmWOoQ$4DAqoj1wm+JhhOkVLVWuSWDNwIEh8sQZH+Bj5wQGKUU', 'b98bb58b-541e-454c-941c-88332808c814');
          end if;
          RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$_$;


ALTER FUNCTION "public"."fn_create_directus_user_on_admin_add"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_delete_post"("post_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    DECLARE 
      post_record record;
    BEGIN
        select * into post_record from posts where id = post_id;
        delete from analytics_posts where analytics_posts.post_id = post_id;
        delete from posts_hashtags where posts_id = post_id;
        delete from cloud_files where id = post_record.file_id;
        delete from posts where id = post_id;
    END;
$$;


ALTER FUNCTION "public"."fn_delete_post"("post_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_delete_remote_file_on_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  s text;
BEGIN
        IF (TG_OP = 'DELETE') THEN
          if OLD.public_id is not null then     
            SELECT status into s from http_delete(
              'https://651595363288454:6xMlUJRgQ50im9jPvJ8O8Bld97c@api.cloudinary.com/v1_1/hybridapp/resources/image/upload?public_ids[]=' || OLD.public_id);
          end if;
            RETURN OLD;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_delete_remote_file_on_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_dispensary_count_on_user"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            IF OLD.brand_id IS NOT NULL THEN
            UPDATE users SET dispensary_count = dispensary_count - 1 WHERE id = OLD.brand_id;
            END IF;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            IF NEW.brand_id IS NOT NULL THEN
            UPDATE users SET dispensary_count = dispensary_count + 1 WHERE id = NEW.brand_id;
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_dispensary_count_on_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_flag_count_on_posts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_flag_count_on_posts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_giveaway_entry_count_on_giveaway"() RETURNS "trigger"
    LANGUAGE "plpgsql"
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
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_giveaway_entry_count_on_giveaway"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_giveaway_entry_triggers"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    declare
      p record;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            select id, name into p from giveaways where id = NEW.giveaway_id limit 1;
            insert into notifications (type_id, giveaway_id, message, user_id) values (4, NEW.giveaway_id, 'You entered to win ' || p.name || '.', NEW.user_id);
            RETURN NEW;
        ELSIF (TG_OP = 'UPDATE') THEN
            if NEW.sent = true then
                update giveaways set redeemed = (select ((select count(id)::int from giveaway_entries where giveaway_id = NEW.giveaway_id AND won = true group by id) = (select count(id)::int from giveaway_entries where giveaway_id = NEW.giveaway_id AND won = true AND sent = true group by id)):: boolean) where giveaways.id = NEW.giveaway_id;
            end if;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_giveaway_entry_triggers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_giveaway_input_push"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    declare
      r record;
      g_ids text[];
    BEGIN
      select array_agg(giveaways.id) into g_ids from giveaways where giveaways.date_created >= now() - interval '5 minute' AND giveaways.date_created <= now();

      if found then
        SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
        select * into r from http((
                'POST',
                'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/create-giveaway',
                ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
                'application/json',
                jsonb_build_object('ids', (select array_agg(giveaways.id) from giveaways where giveaways.date_created >= now() - interval '6 minute' AND giveaways.date_created <= now()))::jsonb
              )::http_request);
        raise warning 'Sent notification %', r;
      END if; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_giveaway_input_push"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_giveaway_triggers"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$BEGIN
        IF (TG_OP = 'INSERT') THEN
            perform http((
                'POST',
                'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/create-giveaway',
                ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
                'application/json',
                jsonb_build_object('id', NEW.id, 'name', NEW.name, 'end_time', NEW.end_time)::jsonb
              )::http_request);
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;$$;


ALTER FUNCTION "public"."fn_giveaway_triggers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_id_dispensary_admin"("user_id" "uuid", "dispensary_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
      return  user_id = Any(select a.user_id from dispensary_locations d
              left join users b on b.id = d.brand_id
              left join user_brand_admins a on a.brand_id = b.id
              where d.id = dispensary_id);
    END;
$$;


ALTER FUNCTION "public"."fn_id_dispensary_admin"("user_id" "uuid", "dispensary_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_insert_update_or_delete_post_from_drop"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'UPDATE') THEN
            UPDATE posts
            SET cover_id = NEW.cover_id
            WHERE id = NEW.id;
            RETURN NULL;
        ELSIF (TG_OP = 'INSERT') THEN
            INSERT INTO posts (id, status, live_time, cover_id, drop_id)
            VALUES (NEW.id, 'published', NOW(), NEW.cover_id, NEW.id);
            RETURN NULL;
        ELSIF (TG_OP = 'DELETE') THEN
            delete from posts where id = OLD.id;
            IF NOT FOUND THEN RETURN NULL; END IF;
            RETURN NULL;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_insert_update_or_delete_post_from_drop"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_insert_update_or_delete_public_user_from_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$declare
        icount int = (select count(*) from users);
        newname varchar;
    BEGIN
        IF (TG_OP = 'UPDATE') THEN
        if (NEW.phone is not NULL) then
            UPDATE public.users
            SET phone = NEW.phone
            WHERE id = NEW.id;
            end if;
            RETURN NULL;
        ELSIF (TG_OP = 'INSERT') THEN
            --newname := concat('Hybrid ', icount);
            --raise notice 'Value: %', newname;
            INSERT INTO public.users (id, phone, email, role_id, status)
            VALUES (NEW.id, NEW.phone, NEW.email, 1, 'published');
            RETURN NULL;
        ELSIF (TG_OP = 'DELETE') THEN
            delete from public.users where id = OLD.id;
            IF NOT FOUND THEN RETURN NULL; END IF;
            RETURN NULL;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;$$;


ALTER FUNCTION "public"."fn_insert_update_or_delete_public_user_from_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_lists_products_sort"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
        IF (TG_OP = 'DELETE') THEN
            update lists set sort = array_remove(sort, OLD.products_id) where id = OLD.lists_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            update lists set sort = array_prepend(NEW.products_id, sort) where id = NEW.lists_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_lists_products_sort"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_lookup_dispensaries"("lat" double precision, "long" double precision, "ids" "uuid"[] DEFAULT '{}'::"uuid"[], "lim" integer DEFAULT 100) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
      return (SELECT json_agg(t) from (SELECT id,ST_Distance(location, ST_SetSRID(ST_MakePoint(long, lat),4326)) 
FROM dispensary_locations
WHERE NOT
(id = ANY(ids::uuid[]))
ORDER BY
location <-> ST_SetSRID(ST_MakePoint(long, lat),4326)
LIMIT lim) t);
    END;
$$;


ALTER FUNCTION "public"."fn_lookup_dispensaries"("lat" double precision, "long" double precision, "ids" "uuid"[], "lim" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_lookup_location_by_geometry"("locale_geom" "extensions"."geography") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
      return (SELECT json_agg(t) from (SELECT *
      FROM postal_codes
      ORDER BY geom <-> locale_geom::geography limit 1) t);
    END;
$$;


ALTER FUNCTION "public"."fn_lookup_location_by_geometry"("locale_geom" "extensions"."geography") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_lookup_location_for_post"("locale_geom" "extensions"."geography") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
    declare
      item_id int;
    BEGIN
      SELECT id into item_id
      FROM postal_codes
      ORDER BY geom <-> locale_geom::geography limit 1;
      return item_id;
    END;
$$;


ALTER FUNCTION "public"."fn_lookup_location_for_post"("locale_geom" "extensions"."geography") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_lookup_location_for_post"("post_id" "uuid", "locale_geom" "extensions"."geography") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    declare
      item_id int;
    BEGIN
      SELECT id into item_id
      FROM postal_codes
      ORDER BY geom <-> locale_geom::geography limit 1;
      update posts set location = id where id = post_id;
    END;
$$;


ALTER FUNCTION "public"."fn_lookup_location_for_post"("post_id" "uuid", "locale_geom" "extensions"."geography") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_message_template_count_on_types"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            IF OLD.type_id IS NOT NULL THEN
            UPDATE notification_types SET message_template_count = message_template_count - 1 WHERE id = OLD.type_id;
            END IF;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            IF NEW.type_id IS NOT NULL THEN
            UPDATE notification_types SET message_template_count = message_template_count + 1 WHERE id = NEW.type_id;
            END IF;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_message_template_count_on_types"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_new_user_from_brand"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        IF (TG_OP = 'UPDATE') THEN
            UPDATE users 
            SET profile_picture_id = NEW.logo_id
            WHERE id = NEW.id;
            RETURN NULL;
        ELSIF (TG_OP = 'INSERT') THEN
            INSERT INTO users (id, role, profile_picture_id, banner_id)
            VALUES (NEW.id, 4, NEW.logo_id, 'b8f63490-2c4f-4be7-bb96-f6d10460c264');
            RETURN NULL;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_new_user_from_brand"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_post_tasks"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    declare
      u record;
      postal_id int;
      tableIds int;
    BEGIN
    if pg_trigger_depth() < 1 then 
      IF (TG_OP = 'UPDATE') THEN
            if NEW.message is not null then
              PERFORM fn_postal_tasks(NEW.id, NEW.message);
            end if;
            if NEW.geotag is not null then
              NEW.location_id = fn_lookup_location_for_post(new.geotag);
            end if;
            NEW.has_file = NEW.file_id is not null;
            -- update posts set has_file = NEW.file_id is not null where id = NEW.id;
            RETURN NEW;
        ELSIF (TG_OP = 'INSERT') THEN
            if NEW.message is not null then
              PERFORM fn_postal_tasks(NEW.id, NEW.message);
            end if;
            if NEW.geotag is not null then
              NEW.location_id = fn_lookup_location_for_post(new.geotag);
            end if;

            select name, id into u from users where id = NEW.user_id;

            -- insert into notifications
            if NEW.id is not null then 
              insert into notifications (type_id, post_id, message, user_id) select 12, NEW.id, '✴️ ' || u.name || ' created a new post! ' , follower_id from relationships where followee_id = NEW.user_id;
            end if;
            NEW.has_file = NEW.file_id is not null;
            -- update posts set has_file = NEW.file_id is not null where id = NEW.id;
            RETURN NEW;
        END IF;
    end if;
        
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_post_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_postal_tasks"("post_id" "uuid", "message" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    DECLARE 
      tableIds int;
    BEGIN
        delete from posts_hashtags where posts_id = post_id;

        with rows as (
        insert into post_tags(tag) (select tag from unnest(string_to_array(regexp_replace(
          lower(message),
            '[^a-z#A-Z@0-9-]',
            ' ',
            'g'), ' ')) as data(tag) where LEFT(tag, 1) = '#') on conflict(tag) do update set tag = EXCLUDED.tag, count = post_tags.count + 1 returning id
        )
        INSERT INTO posts_hashtags (post_tags_id, posts_id)
        SELECT id, post_id 
        FROM rows;
    END;
$$;


ALTER FUNCTION "public"."fn_postal_tasks"("post_id" "uuid", "message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_postgis_encode"("long" double precision, "lat" double precision) RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        return ST_MakePoint(long, lat);
    END;
$$;


ALTER FUNCTION "public"."fn_postgis_encode"("long" double precision, "lat" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_prodcuts_gallery_sort"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
        IF (TG_OP = 'DELETE') THEN
            update products set sort = array_remove(sort, OLD.cloud_files_id) where id = OLD.products_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            update products set sort = array_prepend(NEW.cloud_files_id, sort) where id = NEW.products_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_prodcuts_gallery_sort"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_product_post_insert_tasks"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    declare
      post record;
      brand_id uuid;
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            delete from posts_products where posts_id = OLD.post_id;
            delete from posts where posts.id = OLD.post_id;
            delete from stash where products_id = OLD.id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            -- If this is a drop, we will create a post
            -- if NEW.post_id is not null then
            --   if NEW.release_date > NOW() then
            --     insert into posts_products (posts_id, products_id) values (NEW.post_id, NEW.id);
            --   end if;
            -- end if;
            RETURN NEW;
        END IF;
        -- RETURN NEW;
        RETURN coalesce(NEW, OLD); -- result is ignored since this is an AFTER trigger
    END;

$$;


ALTER FUNCTION "public"."fn_product_post_insert_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_product_tasks"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    declare
      post record;
      brand_id uuid;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            -- If this is a drop, we will create a post
            if NEW.release_date > NOW() then
              -- Get the first brand for this product
              select users_id into brand_id from products_brands where products_id = NEW.id limit 1;
              -- If no post is found, then create a new post
              if NEW.post_id is NULL then
                insert into posts (user_id) values (brand_id) returning * into post;
              -- Add this product to the post.
              -- insert into posts_products (posts_id, products_id) values (post.id, NEW.id);
              -- Set post id to this product.
              update products set post_id = post.id where products.id = NEW.id;
              NEW.post_id = post.id;
              end if;
            end if;
            RETURN NEW;
        END IF;
        -- RETURN NEW;
        RETURN coalesce(NEW, OLD); -- result is ignored since this is an AFTER trigger
    END;

$$;


ALTER FUNCTION "public"."fn_product_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_schema_fields"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        -- Field names
        comment on constraint users_profile_picture_id_foreign on users is E'@graphql({"foreign_name": "profilePicture", "local_name": "cloud_files"})';
        comment on constraint users_banner_id_foreign on users is E'@graphql({"foreign_name": "banner", "local_name": "cloud_files"})';
        comment on constraint users_role_id_fkey on users is E'@graphql({"foreign_name": "role", "local_name": "roles"})';
        comment on constraint relationships_follower_id_fkey on relationships is E'@graphql({"foreign_name": "follower", "local_name": "users"})';
        comment on constraint relationships_followee_id_fkey on relationships is E'@graphql({"foreign_name": "followee", "local_name": "users"})';
        comment on constraint users_admins_user_id_fkey on users_admins is E'@graphql({"foreign_name": "user", "local_name": "users"})';
        comment on constraint users_admins_admin_id_fkey on users_admins is E'@graphql({"foreign_name": "admin", "local_name": "users"})';
        comment on constraint lists_thumbnail_id_foreign on lists is E'@graphql({"foreign_name": "thumbnail", "local_name": "cloud_files"})';
        comment on constraint lists_background_id_foreign on lists is E'@graphql({"foreign_name": "background", "local_name": "cloud_files"})';
        comment on constraint fk_product_category_parent on product_categories is E'@graphql({"foreign_name": "parent", "local_name": "product_categories"})';
        comment on constraint products_category_id_fkey on products is E'@graphql({"foreign_name": "category", "local_name": "product_categories"})';
        comment on constraint dispensaries_profile_picture_id_foreign on dispensaries is E'@graphql({"foreign_name": "profilePicture", "local_name": "cloud_files"})';
        comment on constraint deals_deal_graphic_id_foreign on deals is E'@graphql({"foreign_name": "graphic", "local_name": "cloud_files"})';
        comment on constraint deals_background_image_id_foreign on deals is E'@graphql({"foreign_name": "background", "local_name": "cloud_files"})';
    END;
$$;


ALTER FUNCTION "public"."fn_schema_fields"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_schema_types"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        -- Type names
        comment on table users is e'@graphql({"name": "User", "totalCount": {"enabled": true}})';
        comment on table addresses is e'@graphql({"name": "Address", "totalCount": {"enabled": true}})';
        comment on table files is e'@graphql({"name": "File", "totalCount": {"enabled": true}})';
        comment on table likes is e'@graphql({"name": "Like", "totalCount": {"enabled": true}})';
        comment on table lists is e'@graphql({"name": "List", "totalCount": {"enabled": true}})';
        comment on table lists_products is e'@graphql({"name": "ListProduct", "totalCount": {"enabled": true}})';
        comment on table posts is e'@graphql({"name": "Post", "totalCount": {"enabled": true}})';
        comment on table posts_products is e'@graphql({"name": "PostProduct"})';
        comment on table product_categories is e'@graphql({"name": "ProductCategory"})';
        comment on table products is e'@graphql({"name": "Product", "totalCount": {"enabled": true}})';
        comment on table relationships is e'@graphql({"name": "Relationship", "totalCount": {"enabled": true}})';
        comment on table roles is e'@graphql({"name": "Role"})';
        comment on table stash is e'@graphql({"name": "Stash", "totalCount": {"enabled": true}})';
        comment on table states is e'@graphql({"name": "State", "totalCount": {"enabled": true}})';
        comment on table us_locations is e'@graphql({"name": "USLocation", "totalCount": {"enabled": true}})';
        comment on table users_admins is e'@graphql({"name": "UsersAdmin"})';
        comment on table deals is e'@graphql({"name": "Deal", "totalCount": {"enabled": true}})';
        comment on table deal_claims is e'@graphql({"name": "DealClaim", "totalCount": {"enabled": true}})';
        comment on table dispensaries is e'@graphql({"name": "Dispensary", "totalCount": {"enabled": true}})';
        comment on table dispensary_locations is e'@graphql({"name": "DispensaryLocation", "totalCount": {"enabled": true}})';
        comment on table cloud_files is e'@graphql({"name": "CloudFile", "totalCount": {"enabled": true}})';
        comment on table subscriptions_lists is e'@graphql({"name": "SubscriptionsLists", "totalCount": {"enabled": true}})';
        comment on table products_brands is e'@graphql({"name": "ProductBrand", "totalCount": {"enabled": true}})';
        comment on table postal_codes is e'@graphql({"name": "PostalCode", "totalCount": {"enabled": true}})';
        comment on table post_tags is e'@graphql({"name": "PostTag", "totalCount": {"enabled": true}})';
        comment on table product_feature_types is e'@graphql({"name": "ProductFeatureType", "totalCount": {"enabled": true}})';
        comment on table product_features is e'@graphql({"name": "ProductFeature", "totalCount": {"enabled": true}})';
        comment on table explore is e'@graphql({"name": "Explore", "totalCount": {"enabled": true}})';
        comment on table cannabis_strains is e'@graphql({"name": "Strain", "totalCount": {"enabled": true}})';
    END;
$$;


ALTER FUNCTION "public"."fn_schema_types"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_send_creator_notification_triggers"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    declare
      p record;
    BEGIN
        IF (TG_OP = 'UPDATE') THEN
            if (NEW.role_id <> OLD.role_id) then
              set statement_timeout to 60000;
              if (NEW.email is not null) then
                perform fn_send_creator_notifications(NEW.id, NEW.email);
              end if;
              perform _typesense_import_uuid(NEW.id, 'users');
            end if;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_send_creator_notification_triggers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_send_creator_notifications"("id" "uuid", "email" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    declare
      r record;
    BEGIN
        SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
        select * into r from http((
                'POST',
                'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/creator-notification',
                ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
                'application/json',
                jsonb_build_object('id', id, 'email', email)::jsonb
              )::http_request);
    END;
$$;


ALTER FUNCTION "public"."fn_send_creator_notifications"("id" "uuid", "email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_send_push_notifications"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    declare
      r record;
    BEGIN

        if (select count(*) from push_notifications_queue where sent = FALSE) > 0

        then

        SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
        select * into r from http((
                'POST',
                'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/send_push_notifications',
                ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
                'application/json',
                jsonb_build_object('ids', '{}')::jsonb
              )::http_request);

        end if;

    END;
$$;


ALTER FUNCTION "public"."fn_send_push_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_update_dispensary_date_on_employee_add"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
    declare
        email text;
        name text;
    BEGIN
        IF (TG_OP = 'DELETE') THEN
            UPDATE users u SET is_employee = false where u.id = NEW.user_id;
            UPDATE dispensary_locations set date_updated = now() where id = OLD.dispensary_id;
            RETURN OLD;
        ELSIF (TG_OP = 'INSERT') THEN
            UPDATE users u SET is_employee = true where u.id = NEW.user_id;
            UPDATE dispensary_locations set date_updated = now() where id = NEW.dispensary_id;
            select u.email into email from users u where u.id = NEW.user_id;
            select l.name into name from dispensary_locations l where l.id = NEW.dispensary_id;
            perform _edge_employee_upgrade(
                NEW.user_id,
                email,
                name
            );
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."fn_update_dispensary_date_on_employee_add"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_update_schema"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    BEGIN
        comment on schema public is E'@graphql({"inflect_names": true})';
        PERFORM fn_schema_types();
        PERFORM fn_schema_fields();
    END;
$$;


ALTER FUNCTION "public"."fn_update_schema"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_update_tasks"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
    declare
      product_item record;
      brand_id uuid;
      new_post_id uuid;
    BEGIN
        for product_item in select * from products where release_date > NOW() and post_id is null loop
          select users.id into brand_id from users join products_brands pb on (pb.products_id = product_item.id) limit 1;
          insert into posts (user_id) values (brand_id) returning posts.id into new_post_id;
          insert into posts_products (posts_id, products_id) values (new_post_id, product_item.id);
          update products set post_id = post_id where products.id = product_item.id;
        end loop;
    END;
$$;


ALTER FUNCTION "public"."fn_update_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fn_user_brand_admins_triggers"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$declare
      p record;
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            -- update users set claimed = true where id = NEW.brand_id;
            RETURN NEW;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;$$;


ALTER FUNCTION "public"."fn_user_brand_admins_triggers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_brand_update_sql"("batch_size" integer DEFAULT 50, "offset_value" integer DEFAULT 0) RETURNS TABLE("update_sql" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  r record;
BEGIN
  FOR r IN 
    SELECT * FROM get_product_brand_names(batch_size, offset_value)
  LOOP
    update_sql := format('UPDATE products SET cached_brand_names = %L WHERE id = %L;',
                        r.brand_names, r.product_id);
    RETURN NEXT;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."generate_brand_update_sql"("batch_size" integer, "offset_value" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_complete_fts_update_script"("batch_size" integer DEFAULT 50, "max_batches" integer DEFAULT 10) RETURNS TABLE("batch_number" integer, "sql_script" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  total_count integer;
  batch_count integer;
  i integer;
  offset_value integer;
  brand_sql text;
  fts_sql text;
  script_part text;
BEGIN
  -- Get total count of products
  SELECT COUNT(*) INTO total_count FROM products;
  
  -- Calculate number of batches
  batch_count := LEAST(CEILING(total_count::float / batch_size), max_batches);
  
  -- Generate SQL for each batch
  FOR i IN 0..batch_count-1 LOOP
    offset_value := i * batch_size;
    script_part := '';
    
    -- Add batch header
    script_part := script_part || '-- Batch ' || (i+1)::text || ' of ' || batch_count::text || 
                   ' (products ' || offset_value::text || ' to ' || 
                   LEAST(offset_value + batch_size, total_count)::text || ')\n\n';
    
    -- Add brand name updates
    script_part := script_part || '-- Brand name updates\n';
    FOR brand_sql IN SELECT update_sql FROM generate_brand_update_sql(batch_size, offset_value) LOOP
      script_part := script_part || brand_sql || '\n';
    END LOOP;
    
    -- Add FTS vector updates
    script_part := script_part || '\n-- FTS vector updates\n';
    FOR fts_sql IN SELECT update_sql FROM generate_fts_update_sql(batch_size, offset_value) LOOP
      script_part := script_part || fts_sql || '\n';
    END LOOP;
    
    -- Add batch footer
    script_part := script_part || '\n-- End of Batch ' || (i+1)::text || '\n\n';
    
    -- Return this batch
    batch_number := i + 1;
    sql_script := script_part;
    RETURN NEXT;
  END LOOP;
  
  -- Add index creation script as the final batch
  batch_number := batch_count + 1;
  sql_script := '-- Index creation script (run with owner permissions)\n' ||
                'CREATE INDEX IF NOT EXISTS idx_products_brands_products_id ON products_brands(products_id);\n' ||
                'CREATE INDEX IF NOT EXISTS idx_products_brands_users_id ON products_brands(users_id);\n' ||
                'CREATE INDEX IF NOT EXISTS idx_products_fts_vector ON products USING gin(fts_vector);\n';
  RETURN NEXT;
END;
$$;


ALTER FUNCTION "public"."generate_complete_fts_update_script"("batch_size" integer, "max_batches" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_fts_update_sql"("batch_size" integer DEFAULT 50, "offset_value" integer DEFAULT 0) RETURNS TABLE("update_sql" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  r record;
BEGIN
  FOR r IN 
    SELECT 
      product_id,
      COALESCE(product_name, '') AS product_name,
      COALESCE(product_description, '') AS product_description,
      COALESCE(category_name, '') AS category_name,
      COALESCE(cached_brand_names, '') AS cached_brand_names,
      COALESCE(product_slug, '') AS product_slug,
      COALESCE(product_url, '') AS product_url
    FROM get_product_fts_data(batch_size, offset_value)
  LOOP
    update_sql := format(
      'UPDATE products SET fts_vector = ' ||
      'setweight(to_tsvector(''english'', %L), ''A'') || ' ||
      'setweight(to_tsvector(''english'', %L), ''B'') || ' ||
      'setweight(to_tsvector(''english'', %L), ''B'') || ' ||
      'setweight(to_tsvector(''english'', %L), ''C'') || ' ||
      'setweight(to_tsvector(''english'', %L), ''D'') || ' ||
      'setweight(to_tsvector(''english'', %L), ''D'') ' ||
      'WHERE id = %L;',
      r.product_name,
      r.product_description,
      r.category_name,
      r.cached_brand_names,
      r.product_slug,
      r.product_url,
      r.product_id
    );
    RETURN NEXT;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."generate_fts_update_sql"("batch_size" integer, "offset_value" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_product_update_sql"("product_id" "uuid") RETURNS TABLE("update_type" "text", "update_sql" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  brand_names text;
  r record;
BEGIN
  -- Get brand names
  SELECT COALESCE(string_agg(u.name::text, ' '), '') INTO brand_names
  FROM products_brands pb 
  JOIN users u ON u.id = pb.users_id 
  WHERE pb.products_id = product_id;
  
  -- Generate brand update SQL
  update_type := 'brand_update';
  update_sql := format('UPDATE products SET cached_brand_names = %L WHERE id = %L;',
                      brand_names, product_id);
  RETURN NEXT;
  
  -- Get product data for FTS update
  SELECT 
    p.name::text AS name,
    p.description::text AS description,
    COALESCE(pc.name::text, '') AS category_name,
    p.cached_brand_names::text AS cached_brand_names,
    p.slug::text AS slug,
    p.url::text AS url
  INTO r
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id
  WHERE p.id = product_id;
  
  -- Generate FTS update SQL
  update_type := 'fts_update';
  update_sql := format(
    'UPDATE products SET fts_vector = ' ||
    'setweight(to_tsvector(''english'', %L), ''A'') || ' ||
    'setweight(to_tsvector(''english'', %L), ''B'') || ' ||
    'setweight(to_tsvector(''english'', %L), ''B'') || ' ||
    'setweight(to_tsvector(''english'', %L), ''C'') || ' ||
    'setweight(to_tsvector(''english'', %L), ''D'') || ' ||
    'setweight(to_tsvector(''english'', %L), ''D'') ' ||
    'WHERE id = %L;',
    COALESCE(r.name, ''),
    COALESCE(r.description, ''),
    COALESCE(r.category_name, ''),
    COALESCE(r.cached_brand_names, ''),
    COALESCE(r.slug, ''),
    COALESCE(r.url, ''),
    product_id
  );
  RETURN NEXT;
END;
$$;


ALTER FUNCTION "public"."generate_product_update_sql"("product_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_username"() RETURNS character varying
    LANGUAGE "plpgsql"
    AS $$
  declare
        icount int = (select count(*) from users);
        result varchar;
begin
  result := concat('Hybrid ', icount);
  return result;
end;
$$;


ALTER FUNCTION "public"."generate_username"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_active_categories"() RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  SELECT json_agg(t) from
  (select * from product_categories where id IN (
  SELECT
  DISTINCT category_id
  FROM
  products
  WHERE release_date > '2022-01-01'::date AND status = 'published')) t;
$$;


ALTER FUNCTION "public"."get_active_categories"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_drops_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select p.id, p.name, p.slug, p.release_date, jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug, 'settings', ns.settings), null)) as users 
  from products p 
  left join stash s on s.products_id = p.id 
  left join users u on u.id = s.users_id
  CROSS JOIN LATERAL (
     SELECT json_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = u.id and ns.notification_type_id = type
     ) ns
  where release_date >= startTime and release_date < endTime 
  group by p.id
  ) t; 
  $$;


ALTER FUNCTION "public"."get_drops_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_feed"("uid" "text", "ids" "text"[] DEFAULT '{}'::"text"[]) RETURNS "text"[]
    LANGUAGE "plpgsql"
    AS $$
  declare
    one_month timestamp;
    sels record;
  begin
    select now() - interval '1 MONTH' into one_month;
    select array_agg(id ORDER BY random()) as j, count(id) as c into sels from posts where file_id is not null AND id != ALL(select distinct post_id from analytics_posts where user_id = uid::uuid) 
    AND user_id != ALL(select distinct block_id from user_blocks where user_id = uid::uuid)
    AND date_created > now() - interval '1 WEEK' AND id != ALL(coalesce(ids::uuid[], array[]::uuid[])) order by random() limit 30;

    -- raise warning 'Feed: 1 Week has % items', sels.c;

    if sels.j is NULL OR sels.c < 30 then
      select array_agg(id ORDER BY random()) as j, count(id) as c into sels from posts where file_id is not null AND id != ALL(select distinct post_id from analytics_posts where user_id = uid::uuid) 
      AND user_id != ALL(select distinct block_id from user_blocks where user_id = uid::uuid)
      AND date_created > now() - interval '3 MONTH' AND id != ALL(coalesce(ids::uuid[], array[]::uuid[])) order by random() limit 30;
      -- raise warning 'Feed: 1 Month has % items', sels.c;
    end if;
    if sels.j is NULL OR sels.c < 30 then
      select array_agg(id ORDER BY random()) as j, count(id) as c into sels from posts where file_id is not null 
      AND user_id != ALL(select distinct block_id from user_blocks where user_id = uid::uuid)
      AND id != ALL(coalesce(ids::uuid[], array[]::uuid[])) order by random() limit 30;
      -- raise warning 'Feed: Any has % items', sels.c;
    end if;
    if sels.j is NULL OR sels.c < 30 then
      select array_agg(id ORDER BY random()) as j, count(id) as c into sels from posts where file_id is not null AND user_id != ALL(select distinct block_id from user_blocks where user_id = uid::uuid) order by random() limit 30;
    end if;
    return sels.j;
  end;
$$;


ALTER FUNCTION "public"."get_feed"("uid" "text", "ids" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_feed_items"("p_uid" "uuid") RETURNS "uuid"[]
    LANGUAGE "plpgsql"
    AS $$DECLARE
  post_ids uuid[];
  min_posts_needed CONSTANT int := 30; -- The number of posts you want to fetch
BEGIN
  -- Create a temporary table to hold all unseen post candidates.
  -- This is more efficient than running multiple large queries.
  CREATE TEMP TABLE unseen_posts AS
  SELECT p.id, p.date_created
  FROM posts AS p
  LEFT JOIN analytics_posts AS ap ON p.id = ap.post_id AND ap.user_id = p_uid
  LEFT JOIN user_blocks AS ub ON p.user_id = ub.block_id AND ub.user_id = p_uid
  WHERE p.file_id IS NOT NULL    -- Ensures it's a media post
    AND ap.post_id IS NULL       -- Filters out seen posts
    AND ub.block_id IS NULL;     -- Filters out blocked users

  -- Tier 1: Try to get posts from the last 1 month.
  SELECT array_agg(id) INTO post_ids FROM (
    SELECT id FROM unseen_posts
    WHERE date_created >= now() - interval '1 MONTH'
    ORDER BY random()
    LIMIT min_posts_needed
  ) as sub;

  -- If we found enough posts, return them.
  IF coalesce(array_length(post_ids, 1), 0) >= min_posts_needed THEN
    DROP TABLE unseen_posts;
    RETURN post_ids;
  END IF;

  -- Tier 2: If not, try to get posts from the last 3 months.
  SELECT array_agg(id) INTO post_ids FROM (
    SELECT id FROM unseen_posts
    WHERE date_created >= now() - interval '3 MONTH'
    ORDER BY random()
    LIMIT min_posts_needed
  ) as sub;

  IF coalesce(array_length(post_ids, 1), 0) >= min_posts_needed THEN
    DROP TABLE unseen_posts;
    RETURN post_ids;
  END IF;

  -- Tier 3: If not, try to get posts from the last 6 months.
  SELECT array_agg(id) INTO post_ids FROM (
    SELECT id FROM unseen_posts
    WHERE date_created >= now() - interval '6 MONTH'
    ORDER BY random()
    LIMIT min_posts_needed
  ) as sub;

  IF coalesce(array_length(post_ids, 1), 0) >= min_posts_needed THEN
    DROP TABLE unseen_posts;
    RETURN post_ids;
  END IF;

  -- Tier 4: If still not enough, get any posts regardless of date.
  SELECT array_agg(id) INTO post_ids FROM (
    SELECT id FROM unseen_posts
    ORDER BY random()
    LIMIT min_posts_needed
) as sub;

DROP TABLE unseen_posts;
RETURN post_ids;

END;$$;


ALTER FUNCTION "public"."get_feed_items"("p_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_followed_brands"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT r.followee_id 
  FROM relationships r
  JOIN users u ON u.id = r.followee_id
  WHERE r.follower_id = uid 
  AND u.role_id = 10;
END;
$$;


ALTER FUNCTION "public"."get_followed_brands"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_followed_users"("uid" "uuid") RETURNS SETOF "uuid"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT r.followee_id 
  FROM relationships r
  JOIN users u ON u.id = r.followee_id
  WHERE r.follower_id = uid 
  AND u.role_id IN (1, 2, 3, 4, 5, 6, 9);
END;
$$;


ALTER FUNCTION "public"."get_followed_users"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select g.id, g.name, g.start_time, g.end_time, g.total_prizes, p.name as product_name, p.slug as product_slug, f.secure_url as thumbnail, jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug, 'settings', ns.settings), null)) as users 
  from giveaways g 
  left join products p on p.id = g.product_id
  left join cloud_files f on f.id = p.thumbnail_id
  left join giveaway_entries ge on ge.giveaway_id = g.id 
  left join users u on u.id = ge.user_id
  CROSS JOIN LATERAL (
     SELECT json_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = u.id and ns.notification_type_id = Any(types)
     ) ns
  where end_time >= startTime and end_time < endTime 
  group by g.id, p.name, f.id, p.slug
  ) t;
  $$;


ALTER FUNCTION "public"."get_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_giveaways_winners_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
select jsonb_build_object('data', json_agg(t)) from (
  select g.id, g.name, g.start_time, g.end_time, g.total_prizes, p.name as product_name, p.slug as product_slug, f.secure_url as thumbnail, jsonb_agg(coalesce(jsonb_build_object('email', u.email, 'id', u.id, 'name', u.name, 'slug', u.slug, 'settings', ns.settings), null)) as users 
from giveaways g 
left join products p on p.id = g.product_id
left join cloud_files f on f.id = p.thumbnail_id
left join giveaway_entries ge on ge.giveaway_id = g.id 
left join users u on u.id = ge.user_id
CROSS JOIN LATERAL (
   SELECT json_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
   FROM   user_notifications_settings ns
   WHERE  ns.user_id = u.id and ns.notification_type_id = Any(types)
   ) ns
where end_time <= startTime and selected_winner = false and entry_count > 0 
group by g.id, p.name, f.id, p.slug
) t;
$$;


ALTER FUNCTION "public"."get_giveaways_winners_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_likes_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select l.posts_id as id, 
    count(l.posts_id) as count,
    p.user_id,
    pu.name,
    ns.settings as settings,
    jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug, 'settings', ns.settings), null)) as users
    from likes l
  left join posts p on p.id = l.posts_id
  left join users pu on pu.id = p.user_id
  left join users u on u.id = l.users_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = p.user_id and ns.notification_type_id = type
     ) ns
  where l.date_created >= startTime and l.date_created < endTime
  group by l.posts_id, p.user_id, ns.settings, pu.name
  ) t;
  $$;


ALTER FUNCTION "public"."get_likes_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_list_add_items_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select lp.lists_id as id, 
    l.user_id,
    count(lp.products_id) as count,
    l.name as name,
    jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug, 'settings', ns.settings), null)) as users
    from lists_products lp
  left join lists l on l.id = lp.lists_id
  left join subscriptions_lists sl on sl.list_id = l.id
  left join users u on u.id = sl.user_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = u.id and ns.notification_type_id = type
     ) ns
  where lp.date_created >= startTime and lp.date_created < endTime
  group by lp.products_id, lp.lists_id, l.name, l.user_id
  ) t; 
  $$;


ALTER FUNCTION "public"."get_list_add_items_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_new_followers_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select r.followee_id as id, fu.name, count(r.followee_id) as count, jsonb_agg(coalesce(jsonb_build_object('id', f.id, 'name', f.name, 'slug', f.slug), null)) as users, jsonb_agg(DISTINCT ns.settings) as settings
  from relationships r 
  left join users fu on fu.id = r.followee_id
  left join users f on f.id = r.follower_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(distinct jsonb_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = r.followee_id and ns.notification_type_id = type
     ) ns
  where r.date_created >= startTime and r.date_created < endTime 
  group by r.followee_id, fu.name
  ) t;
  $$;


ALTER FUNCTION "public"."get_new_followers_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_new_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$select jsonb_build_object('data', json_agg(t)) from (
    select g.id, g.name, g.start_time, g.end_time, g.total_prizes, p.name as product_name, p.slug as product_slug, f.secure_url as thumbnail, jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug, 'settings', ns.settings), null)) as users 
  from giveaways g 
  left join products p on p.id = g.product_id
  left join cloud_files f on f.id = p.thumbnail_id
  left join giveaway_entries ge on ge.giveaway_id = g.id 
  left join users u on u.id = ge.user_id
  CROSS JOIN LATERAL (
     SELECT json_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = u.id and ns.notification_type_id = Any(types)
     ) ns
  where g.start_time >= startTime and g.start_time < endTime 
  group by g.id, p.name, f.id, p.slug
  ) t;$$;


ALTER FUNCTION "public"."get_new_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_new_lists_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select l.id, l.name, pu.name as user_name, l.user_id, jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug, 'settings', ns.settings), null)) as users
  from lists l 
  left join users pu on pu.id = l.user_id
  left join relationships s on s.followee_id = l.user_id 
  left join users u on u.id = s.follower_id
  CROSS JOIN LATERAL (
     SELECT json_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = u.id and ns.notification_type_id = type
     ) ns
  where l.date_created >= startTime and l.date_created < endTime 
  group by l.id, l.user_id, pu.name
  ) t; 
  $$;


ALTER FUNCTION "public"."get_new_lists_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_new_posts_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select p.id, p.user_id, pu.name, jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug, 'settings', ns.settings), null)) as users
  from posts p
  left join users pu on pu.id = p.user_id
  left join relationships s on s.followee_id = p.user_id 
  left join users u on u.id = s.follower_id
  CROSS JOIN LATERAL (
     SELECT json_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = u.id and ns.notification_type_id = 2
     ) ns
  where p.date_created >= startTime and p.date_created < endTime 
  group by p.id, pu.name, pu.id
  ) t; 
  $$;


ALTER FUNCTION "public"."get_new_posts_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_popular_stashlists"("limit_count" integer) RETURNS TABLE("list_id" "uuid", "list_name" character varying, "author_id" "uuid", "author_name" character varying, "author_avatar_url" character varying, "stash_count" bigint, "product_details" "json", "stashed_users" "json")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  WITH stash_counts AS (
    SELECT
      sl.list_id,
      COUNT(*) as total_stashes,
      json_agg(
        json_build_object(
          'user_id', u.id,
          'avatar_url', cf_user.url
        )
      ) as stashed_users
    FROM subscriptions_lists sl
    JOIN users u ON sl.user_id = u.id
    LEFT JOIN cloud_files cf_user ON u.profile_picture_id = cf_user.id
    GROUP BY sl.list_id
  ),
  list_products AS (
    SELECT
      l.id as list_id,
      json_agg(
        json_build_object(
          'product_id', p.id,
          'name', p.name,
          'price', p.price,
          'thumbnail_url', cf_product.url,
          'brand_name', b.name
        )
      ) as products
    FROM lists l
    JOIN lists_products lp ON l.id = lp.lists_id
    JOIN products p ON lp.products_id = p.id
    LEFT JOIN cloud_files cf_product ON p.thumbnail_id = cf_product.id
    LEFT JOIN products_brands pb ON p.id = pb.products_id
    LEFT JOIN users b ON pb.users_id = b.id
    GROUP BY l.id
  )
  SELECT
    l.id as list_id,
    l.name as list_name,
    l.user_id as author_id,
    u.name as author_name,
    cf_author.url as author_avatar_url,
    COALESCE(sc.total_stashes, 0) as stash_count,
    lp.products as product_details,
    sc.stashed_users
  FROM lists l
  JOIN users u ON l.user_id = u.id
  LEFT JOIN cloud_files cf_author ON u.profile_picture_id = cf_author.id
  LEFT JOIN stash_counts sc ON l.id = sc.list_id
  JOIN list_products lp ON l.id = lp.list_id  -- Changed to INNER JOIN to ensure at least 1 product
  ORDER BY sc.total_stashes DESC NULLS LAST
  LIMIT limit_count;
END;
$$;


ALTER FUNCTION "public"."get_popular_stashlists"("limit_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_product_brand_names"("batch_size" integer DEFAULT 50, "offset_value" integer DEFAULT 0) RETURNS TABLE("product_id" "uuid", "brand_names" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  WITH product_batch AS (
    SELECT id
    FROM products
    ORDER BY id
    LIMIT batch_size
    OFFSET offset_value
  )
  SELECT 
    pb.products_id,
    COALESCE(string_agg(u.name, ' '), '') AS brand_names
  FROM product_batch p
  LEFT JOIN products_brands pb ON pb.products_id = p.id
  LEFT JOIN users u ON u.id = pb.users_id
  GROUP BY pb.products_id;
END;
$$;


ALTER FUNCTION "public"."get_product_brand_names"("batch_size" integer, "offset_value" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_product_fts_data"("batch_size" integer DEFAULT 50, "offset_value" integer DEFAULT 0) RETURNS TABLE("product_id" "uuid", "product_name" "text", "product_description" "text", "category_name" "text", "cached_brand_names" "text", "product_slug" "text", "product_url" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  WITH product_batch AS (
    SELECT 
      p.id,
      p.name::text,
      p.description::text,
      p.category_id,
      p.cached_brand_names::text,
      p.slug::text,
      p.url::text
    FROM products p
    ORDER BY p.id
    LIMIT batch_size
    OFFSET offset_value
  )
  SELECT 
    pb.id,
    pb.name,
    pb.description,
    COALESCE(pc.name::text, ''),
    pb.cached_brand_names,
    pb.slug,
    pb.url
  FROM product_batch pb
  LEFT JOIN product_categories pc ON pc.id = pb.category_id;
END;
$$;


ALTER FUNCTION "public"."get_product_fts_data"("batch_size" integer, "offset_value" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_product_stash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select s.products_id as id, 
    p.slug,
    p.name, count(s.products_id) as count, 
    jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug), null)) as users,
    jsonb_agg(DISTINCT jsonb_build_object('id', ua.id, 'name', ua.name, 'settings', ns.settings)) as brands
  from stash s
  left join products p on p.id = s.products_id 
  left join users u on u.id = s.users_id
  left join products_brands pb on pb.products_id = s.products_id
  left join user_brand_admins ba on ba.brand_id = pb.users_id
  left join users ua on ua.id = ba.user_id
  CROSS JOIN LATERAL (
     SELECT json_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = ua.id and ns.notification_type_id = type
     ) ns
  where p.date_created >= startTime and p.date_created < endTime 
  group by s.products_id, p.name, p.slug
  ) t; 
  $$;


ALTER FUNCTION "public"."get_product_stash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_product_tag_in_post_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select pp.products_id as id, 
    count(pp.posts_id) as count,
    p.name,
    p.slug, 
    jsonb_agg(coalesce(jsonb_build_object('id', a.id, 'name', a.name, 'slug', a.slug, 'settings', ns.settings), null)) as brands,
    jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug), null)) as users
    from posts_products pp
  left join products p on p.id = pp.products_id
  left join products_brands pb on pb.products_id = pp.products_id
  left join users a on a.id = pb.users_id
  left join posts po on po.id = pp.posts_id
  left join users u on u.id = po.user_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = a.id and ns.notification_type_id = type
     ) ns
  where pp.date_created >= startTime and pp.date_created < endTime
  group by pp.posts_id, pp.products_id, p.name, p.slug
  ) t; 
  $$;


ALTER FUNCTION "public"."get_product_tag_in_post_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_restash_list_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select s.restash_id, 
    count(s.restash_list_id) as count, 
    s.restash_list_id, 
    l.name as name,
    p.name as product_name,
    p.slug as product_slug,
    jsonb_agg(DISTINCT ns.settings) as settings,
    jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug), null)) as users
    from stash s
  left join users u on u.id = s.users_id
  left join lists l on l.id = s.restash_list_id
  left join products p on p.id = s.products_id
  left join users ua on ua.id = s.restash_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = ua.id and ns.notification_type_id = type
     ) ns
  where s.date_created >= startTime and s.date_created < endTime and s.restash_list_id is not null
  group by s.restash_id, s.restash_list_id, p.name, l.name, p.slug
  ) t;  
  $$;


ALTER FUNCTION "public"."get_restash_list_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_restash_post_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select s.restash_id, 
    count(s.restash_post_id) as count, 
    s.restash_post_id, 
    p.name as product_name,
    p.slug as product_slug,
    jsonb_agg(DISTINCT ns.settings) as settings,
    jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug), null)) as users
    from stash s
  left join users u on u.id = s.users_id
  left join products p on p.id = s.products_id
  left join users ua on ua.id = s.restash_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = ua.id and ns.notification_type_id = type
     ) ns
  where s.date_created >= startTime and s.date_created < endTime and s.restash_post_id is not null
  group by s.restash_id, s.restash_post_id, p.name, p.slug
  ) t;  
  $$;


ALTER FUNCTION "public"."get_restash_post_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_restash_profile_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select s.restash_id, 
    count(s.restash_profile_id) as count, 
    s.restash_profile_id, 
    p.name as product_name,
    p.slug as product_slug, 
    jsonb_agg(DISTINCT ns.settings) as settings,
    jsonb_agg(coalesce(jsonb_build_object('id', u.id, 'name', u.name, 'slug', u.slug), null)) as users
    from stash s
  left join users u on u.id = s.users_id
  left join products p on p.id = s.products_id
  left join users ua on ua.id = s.restash_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = ua.id and ns.notification_type_id = type
     ) ns
  where s.date_created >= startTime and s.date_created < endTime and s.restash_profile_id is not null
  group by s.restash_id, s.restash_profile_id, p.name, p.slug
  ) t;  
  $$;


ALTER FUNCTION "public"."get_restash_profile_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_sample_product_id"() RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  sample_id uuid;
BEGIN
  SELECT id INTO sample_id FROM products LIMIT 1;
  RETURN sample_id;
END;
$$;


ALTER FUNCTION "public"."get_sample_product_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_seen_post_ids"("uid" "uuid") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN (SELECT json_agg(DISTINCT post_id) FROM analytics_posts ap WHERE ap.user_id = uid group by ap.user_id);
END;
$$;


ALTER FUNCTION "public"."get_seen_post_ids"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_stashlists_by_ids"("list_ids" "uuid"[]) RETURNS TABLE("list_id" "uuid", "list_name" character varying, "author_id" "uuid", "author_name" character varying, "author_avatar_url" character varying, "stash_count" bigint, "product_details" "json", "stashed_users" "json")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  WITH stash_counts AS (
    SELECT
      sl.list_id,
      COUNT(*) as total_stashes,
      json_agg(
        json_build_object(
          'user_id', u.id,
          'avatar_url', cf_user.url
        )
      ) as stashed_users
    FROM subscriptions_lists sl
    JOIN users u ON sl.user_id = u.id
    LEFT JOIN cloud_files cf_user ON u.profile_picture_id = cf_user.id
    WHERE sl.list_id = ANY(list_ids)
    GROUP BY sl.list_id
  ),
  list_products AS (
    SELECT
      l.id as list_id,
      json_agg(
        json_build_object(
          'product_id', p.id,
          'name', p.name,
          'price', p.price,
          'thumbnail_url', cf_product.url,
          'brand_name', b.name
        )
      ) as products
    FROM lists l
    JOIN lists_products lp ON l.id = lp.lists_id
    JOIN products p ON lp.products_id = p.id
    LEFT JOIN cloud_files cf_product ON p.thumbnail_id = cf_product.id
    LEFT JOIN products_brands pb ON p.id = pb.products_id
    LEFT JOIN users b ON pb.users_id = b.id
    WHERE l.id = ANY(list_ids)
    GROUP BY l.id
  )
  SELECT
    l.id as list_id,
    l.name as list_name,
    l.user_id as author_id,
    u.name as author_name,
    cf_author.url as author_avatar_url,
    COALESCE(sc.total_stashes, 0) as stash_count,
    COALESCE(lp.products, '[]'::json) as product_details,
    COALESCE(sc.stashed_users, '[]'::json) as stashed_users
  FROM lists l
  JOIN users u ON l.user_id = u.id
  LEFT JOIN cloud_files cf_author ON u.profile_picture_id = cf_author.id
  LEFT JOIN stash_counts sc ON l.id = sc.list_id
  LEFT JOIN list_products lp ON l.id = lp.list_id
  WHERE l.id = ANY(list_ids)
  ORDER BY l.date_created DESC;
END;
$$;


ALTER FUNCTION "public"."get_stashlists_by_ids"("list_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_total_all_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select s.restash_id, 
    count(restash_id) as count, 
    jsonb_agg(DISTINCT ns.settings) as settings
    from stash s
  left join users ua on ua.id = s.restash_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = ua.id and ns.notification_type_id = type
     ) ns
  where s.date_created >= startTime and s.date_created < endTime and s.restash_id is not null
  group by s.restash_id
  ) t;  
  $$;


ALTER FUNCTION "public"."get_total_all_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_total_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) RETURNS "json"
    LANGUAGE "sql" IMMUTABLE
    AS $$ 
  select jsonb_build_object('data', json_agg(t)) from (
    select s.restash_id, 
    count(restash_id) as count, 
    jsonb_agg(DISTINCT ns.settings) as settings
    from stash s
  left join products p on p.id = s.products_id
  left join users ua on ua.id = s.restash_id
  CROSS JOIN LATERAL (
     SELECT jsonb_agg(json_build_object('id', ns.notification_type_id, 'setting', ns.setting)) AS settings
     FROM   user_notifications_settings ns
     WHERE  ns.user_id = ua.id and ns.notification_type_id = type
     ) ns
  where s.date_created >= startTime and s.date_created < endTime and s.restash_id is not null
  group by s.restash_id
  order by count desc
  ) t;  
  $$;


ALTER FUNCTION "public"."get_total_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trending_hashtags"() RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  SELECT json_agg(t) from
  (select post_tags_id, count(post_tags_id) from posts_hashtags where date_created > 'now'::timestamp - '1 month'::interval group by post_tags_id order by count desc limit 30) t;
$$;


ALTER FUNCTION "public"."get_trending_hashtags"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trending_lists"() RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  SELECT json_agg(t) from
  (select list_id, count(list_id) from subscriptions_lists where date_created > 'now'::timestamp - '1 month'::interval group by list_id order by count desc limit 30) t;
$$;


ALTER FUNCTION "public"."get_trending_lists"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trending_relations"() RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  select json_agg(t) from (select followee_id, count(followee_id) from relationships r where r.date_created > 'now'::timestamp - '1 month'::interval AND r.followee_id in (select id from users where users.role_id = 4) group by r.followee_id order by count desc limit 30) t;
$$;


ALTER FUNCTION "public"."get_trending_relations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trending_stash"() RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  SELECT json_agg(t) from
  (select products_id, count(products_id) from stash where date_created > 'now'::timestamp - '1 month'::interval group by products_id order by count desc limit 30) t;
$$;


ALTER FUNCTION "public"."get_trending_stash"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  select count(id)
  from public.notifications
  where
    user_id = p_user_id and read = false and actor_id <> p_user_id;
$$;


ALTER FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_follower_count"("uid" "text") RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  SELECT json_agg(t) from
  (select count(follower_id) from relationships where followee_id = uid::uuid) t;
$$;


ALTER FUNCTION "public"."get_user_follower_count"("uid" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_users_followed_brands"("user_ids" "uuid"[]) RETURNS SETOF "uuid"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT r.followee_id 
  FROM relationships r
  JOIN users u ON u.id = r.followee_id
  WHERE r.follower_id = ANY(user_ids)
  AND u.role_id = 10;
END;
$$;


ALTER FUNCTION "public"."get_users_followed_brands"("user_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_users_for_lists_products"() RETURNS SETOF "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    select id
    from lists
    where user_id = auth.uid()
$$;


ALTER FUNCTION "public"."get_users_for_lists_products"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_users_for_posts_products"() RETURNS SETOF "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    select id
    from posts
    where user_id = auth.uid()
$$;


ALTER FUNCTION "public"."get_users_for_posts_products"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."graphql_request"("query" "text", "variables" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
  begin
    return graphql.resolve(query, variables);
  end;
$$;


ALTER FUNCTION "public"."graphql_request"("query" "text", "variables" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_add_storage"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.files (id, name)
  values (new.id, new.name);
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_add_storage"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_json"("input_text" character varying) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
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


ALTER FUNCTION "public"."is_json"("input_text" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_deletion"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO deletion_log (table_name, record_id, deleted_data)
  VALUES (TG_TABLE_NAME, OLD.id, row_to_json(OLD));
  RETURN OLD;
END;
$$;


ALTER FUNCTION "public"."log_deletion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_notifications_as_read"("uid" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  update notifications set read = true where user_id = uid;
end;
$$;


ALTER FUNCTION "public"."mark_notifications_as_read"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_user_accounts"("from_id" "uuid", "to_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  -- Set all products to the new brand
  update products_brands set users_id = to_id where users_id = from_id;

  -- Set all locations to the new brand
  update dispensary_locations set brand_id = to_id where brand_id = from_id;

  -- Delete old account
  delete from users where id = from_id;
end;
$$;


ALTER FUNCTION "public"."merge_user_accounts"("from_id" "uuid", "to_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."nearby_dispensary_locations"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[] DEFAULT '{}'::"uuid"[], "lim" integer DEFAULT 100) RETURNS TABLE("id" "uuid", "distance_meters" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY -- Use RETURN QUERY for multiple rows
        SELECT
            dl.id,
            ST_Distance(dl.location::geography, ST_MakePoint(long, lat)::geography)
        FROM public.dispensary_locations AS dl
        WHERE
            ST_DWithin(
                dl.location::geography,
                ST_MakePoint(long, lat)::geography,
                range_meters
            )
            AND NOT (dl.id = ANY(ids_to_exclude))
        ORDER BY
            dl.location <-> ST_SetSRID(ST_MakePoint(long, lat), 4326)
        LIMIT lim;
END;
$$;


ALTER FUNCTION "public"."nearby_dispensary_locations"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[], "lim" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."nearby_postal_codes"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" integer[] DEFAULT '{}'::integer[], "lim" integer DEFAULT 100) RETURNS TABLE("id" integer, "distance_meters" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY -- Use RETURN QUERY for multiple rows
        SELECT
            pc.id,
            ST_Distance(pc.geom::geography, ST_MakePoint(long, lat)::geography)
        FROM public.postal_codes AS pc
        WHERE
            ST_DWithin(
                pc.geom::geography,
                ST_MakePoint(long, lat)::geography,
                range_meters
            )
            AND NOT (pc.id = ANY(ids_to_exclude))
        ORDER BY
            pc.geom <-> ST_SetSRID(ST_MakePoint(long, lat), 4326)
        LIMIT lim;
END;
$$;


ALTER FUNCTION "public"."nearby_postal_codes"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" integer[], "lim" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."nearby_posts"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[] DEFAULT '{}'::"uuid"[], "lim" integer DEFAULT 100) RETURNS TABLE("id" "uuid", "distance_meters" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY -- Use RETURN QUERY for multiple rows
        SELECT
            p.id,
            ST_Distance(p.geotag::geography, ST_MakePoint(long, lat)::geography)
        FROM public.posts AS p
        WHERE
            p.geotag IS NOT NULL AND
            ST_DWithin(
                p.geotag::geography,
                ST_MakePoint(long, lat)::geography,
                range_meters
            )
            AND NOT (p.id = ANY(ids_to_exclude))
        ORDER BY
            p.geotag <-> ST_SetSRID(ST_MakePoint(long, lat), 4326)
        LIMIT lim;
END;
$$;


ALTER FUNCTION "public"."nearby_posts"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[], "lim" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_brand_of_employee_request"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    brand_user_id uuid;
    dispensary_name text;
    r record;
BEGIN
    -- Get the brand_user_id and dispensary name
    SELECT dl.brand_id, dl.name 
    INTO brand_user_id, dispensary_name
    FROM dispensary_locations dl
    WHERE dl.id = NEW.dispensary_id;

    -- Set timeout
    SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
    
    -- Call the edge function
    SELECT * into r from http((
        'POST',
        'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/brand_notification',
        ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
        'application/json',
        jsonb_build_object(
            'brandUserId', brand_user_id,
            'dispensaryName', dispensary_name
        )::jsonb
    )::http_request);

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_brand_of_employee_request"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_employee_of_approval"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
 dispensary_name text;
 user_email text;
 r record;
BEGIN
 IF (TG_OP = 'UPDATE' AND NEW.is_approved = true AND (OLD.is_approved IS NULL OR OLD.is_approved = false)) THEN
  -- Get the dispensary name
  SELECT name
  INTO dispensary_name
  FROM dispensary_locations
  WHERE id = NEW.dispensary_id;

  -- Get the user's email
  SELECT email
  INTO user_email
  FROM users
  WHERE id = NEW.user_id;

  -- Set timeout
  SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  
  -- Call the edge function
  SELECT * into r from http((
  'POST',
  'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/employee_notification',
  ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
  'application/json',
   jsonb_build_object(
  'id', NEW.user_id,
  'email', user_email,
  'name', dispensary_name
  )::jsonb
  )::http_request);
 END IF;
 RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_employee_of_approval"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."populate_cached_brand_names_efficient"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  batch_size integer := 50;
  total_count integer;
  processed integer := 0;
  current_batch_size integer;
  start_time timestamp;
  end_time timestamp;
  duration interval;
BEGIN
  SELECT COUNT(*) INTO total_count 
  FROM products 
  WHERE cached_brand_names IS NULL OR cached_brand_names = '';
  
  RAISE NOTICE 'Populating cached brand names for % products with NULL or empty values...', total_count;
  
  -- Process in batches to avoid timeouts
  WHILE processed < total_count LOOP
    start_time := clock_timestamp();
    
    -- Create a temporary table with the next batch of product IDs
    -- Using OFFSET instead of UUID comparison
    CREATE TEMP TABLE batch_products AS
    SELECT id
    FROM products
    WHERE (cached_brand_names IS NULL OR cached_brand_names = '')
    ORDER BY id
    LIMIT batch_size
    OFFSET processed;
    
    -- Get the number of products in this batch
    SELECT COUNT(*) INTO current_batch_size FROM batch_products;
    
    -- Exit if no more products to process
    IF current_batch_size = 0 THEN
      EXIT;
    END IF;
    
    -- Pre-calculate brand names for all products in this batch
    CREATE TEMP TABLE batch_brand_names AS
    SELECT 
      pb.products_id,
      COALESCE(string_agg(u.name, ' '), '') AS brand_names
    FROM products_brands pb
    JOIN users u ON u.id = pb.users_id
    WHERE pb.products_id IN (SELECT id FROM batch_products)
    GROUP BY pb.products_id;
    
    -- Update all products in this batch at once
    WITH updates AS (
      UPDATE products p
      SET cached_brand_names = COALESCE(bn.brand_names, '')
      FROM batch_products bp
      LEFT JOIN batch_brand_names bn ON bn.products_id = bp.id
      WHERE p.id = bp.id
      RETURNING 1
    )
    SELECT COUNT(*) INTO current_batch_size FROM updates;
    
    -- Update progress
    processed := processed + current_batch_size;
    
    -- Drop temporary tables
    DROP TABLE batch_products;
    DROP TABLE batch_brand_names;
    
    -- Calculate duration and log progress
    end_time := clock_timestamp();
    duration := end_time - start_time;
    
    RAISE NOTICE 'Processed % of % products (%.1f%%) in %',
      processed, total_count, 
      (processed::float / total_count * 100),
      duration;
    
    -- Small delay to prevent database overload
    PERFORM pg_sleep(0.1);
  END LOOP;
  
  RAISE NOTICE 'Completed: % products processed', processed;
END;
$$;


ALTER FUNCTION "public"."populate_cached_brand_names_efficient"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."product_search"("search_terms" "text" DEFAULT NULL::"text", "brand_ids" "text" DEFAULT NULL::"text", "category_ids" "text" DEFAULT NULL::"text", "selected_ids" "text" DEFAULT NULL::"text", "s_limit" integer DEFAULT 50, "s_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$
  select json_agg(r) from (SELECT      products.date_created,
            products.date_updated,
            products.description,
            products.id,
            products.name,
            products.url,
            products.price,
            products.status,
            products.release_date,
            products.list_count,
            -- products.giveawayAmount,
            products.slug,
            products_products_brands._products_products_brands           AS brands,
            Row_to_json(products_category_id.*)                          AS category,
            Row_to_json(products_cover_id.*)                             AS cover,
            Row_to_json(products_thumbnail_id.*)                         AS thumbnail,
            products_products_cloud_files._products_products_cloud_files AS products_cloud_files
            from public.products
 inner join lateral
            (
                   SELECT json_agg(_products_products_brands) AS _products_products_brands from
                          (
                                    SELECT    PUBLIC.products_brands.id,
                                              PUBLIC.products_brands.products_id,
                                              row_to_json(products_brands_users_id.*) AS users_id from PUBLIC.products_brands
                                    left join lateral
                                              (
                                                        SELECT    PUBLIC.users.id,
                                                                  PUBLIC.users.name,
                                                                  PUBLIC.users.slug,
                                                                  PUBLIC.users.date_created,
                                                                  PUBLIC.users.date_updated,
                                                                  PUBLIC.users.description,
                                                                  PUBLIC.users.facebook,
                                                                  PUBLIC.users.follower_count,
                                                                  PUBLIC.users.following_count,
                                                                  PUBLIC.users.founded_date,
                                                                  PUBLIC.users.home_location,
                                                                  PUBLIC.users.instagram,
                                                                  PUBLIC.users.like_count,
                                                                  PUBLIC.users.list_count,
                                                                  PUBLIC.users.post_count,
                                                                  PUBLIC.users.reminder_count,
                                                                  PUBLIC.users.stash_count,
                                                                  PUBLIC.users.status,
                                                                  PUBLIC.users.twitter,
                                                                  PUBLIC.users.website,
                                                                  Row_to_json(users_role_id.*)            AS role_id,
                                                                  Row_to_json(users_profile_picture_id.*) AS profile_picture_id,
                                                                  Row_to_json(users_banner_id.*)          AS banner_id from PUBLIC.users
                                                        left join lateral
                                                                  (
                                                                         SELECT PUBLIC.ROLES.id,
                                                                                PUBLIC.ROLES.ROLE,
                                                                                PUBLIC.ROLES.date_created,
                                                                                PUBLIC.ROLES.date_updated from PUBLIC.ROLES
                                                                         WHERE  PUBLIC.users.role_id = PUBLIC.ROLES.id ) AS users_role_id
                                                        ON        TRUE
                                                        left join lateral
                                                                  (
                                                                         SELECT PUBLIC.cloud_files.asset_id,
                                                                                PUBLIC.cloud_files.date_created,
                                                                                PUBLIC.cloud_files.date_updated,
                                                                                PUBLIC.cloud_files.format,
                                                                                PUBLIC.cloud_files.height,
                                                                                PUBLIC.cloud_files.id,
                                                                                PUBLIC.cloud_files.public_id,
                                                                                PUBLIC.cloud_files.resource_type,
                                                                                PUBLIC.cloud_files.secure_url,
                                                                                PUBLIC.cloud_files.signature,
                                                                                PUBLIC.cloud_files.url,
                                                                                PUBLIC.cloud_files.user_id,
                                                                                PUBLIC.cloud_files.width from PUBLIC.cloud_files
                                                                         WHERE  PUBLIC.users.profile_picture_id = PUBLIC.cloud_files.id ) AS users_profile_picture_id
                                                        ON        TRUE
                                                        left join lateral
                                                                  (
                                                                         SELECT PUBLIC.cloud_files.asset_id,
                                                                                PUBLIC.cloud_files.date_created,
                                                                                PUBLIC.cloud_files.date_updated,
                                                                                PUBLIC.cloud_files.format,
                                                                                PUBLIC.cloud_files.height,
                                                                                PUBLIC.cloud_files.id,
                                                                                PUBLIC.cloud_files.public_id,
                                                                                PUBLIC.cloud_files.resource_type,
                                                                                PUBLIC.cloud_files.secure_url,
                                                                                PUBLIC.cloud_files.signature,
                                                                                PUBLIC.cloud_files.url,
                                                                                PUBLIC.cloud_files.user_id,
                                                                                PUBLIC.cloud_files.width from PUBLIC.cloud_files
                                                                         WHERE  PUBLIC.users.banner_id = PUBLIC.cloud_files.id ) AS users_banner_id
                                                        ON        TRUE
                                                        WHERE     PUBLIC.products_brands.users_id = PUBLIC.users.id ) AS products_brands_users_id
                                    ON        TRUE
                                    WHERE     PUBLIC.products.id = PUBLIC.products_brands.products_id ) AS _products_products_brands) AS products_products_brands
 ON         products_products_brands is NOT NULL
 left join  lateral
            (
                   SELECT PUBLIC.product_categories.date_created,
                          PUBLIC.product_categories.date_updated,
                          PUBLIC.product_categories.id,
                          PUBLIC.product_categories.name from PUBLIC.product_categories
                   WHERE  PUBLIC.products.category_id = PUBLIC.product_categories.id ) AS products_category_id
 ON         TRUE
 left join  lateral
            (
                   SELECT PUBLIC.cloud_files.asset_id,
                          PUBLIC.cloud_files.date_created,
                          PUBLIC.cloud_files.date_updated,
                          PUBLIC.cloud_files.format,
                          PUBLIC.cloud_files.height,
                          PUBLIC.cloud_files.id,
                          PUBLIC.cloud_files.public_id,
                          PUBLIC.cloud_files.resource_type,
                          PUBLIC.cloud_files.secure_url,
                          PUBLIC.cloud_files.signature,
                          PUBLIC.cloud_files.url,
                          PUBLIC.cloud_files.user_id,
                          PUBLIC.cloud_files.width from PUBLIC.cloud_files
                   WHERE  PUBLIC.products.cover_id = PUBLIC.cloud_files.id ) AS products_cover_id
 ON         TRUE
 left join  lateral
            (
                   SELECT PUBLIC.cloud_files.asset_id,
                          PUBLIC.cloud_files.date_created,
                          PUBLIC.cloud_files.date_updated,
                          PUBLIC.cloud_files.format,
                          PUBLIC.cloud_files.height,
                          PUBLIC.cloud_files.id,
                          PUBLIC.cloud_files.public_id,
                          PUBLIC.cloud_files.resource_type,
                          PUBLIC.cloud_files.secure_url,
                          PUBLIC.cloud_files.signature,
                          PUBLIC.cloud_files.url,
                          PUBLIC.cloud_files.user_id,
                          PUBLIC.cloud_files.width from PUBLIC.cloud_files
                   WHERE  PUBLIC.products.thumbnail_id = PUBLIC.cloud_files.id ) AS products_thumbnail_id
 ON         TRUE
 inner join lateral
            (
                   SELECT json_agg(_products_products_cloud_files) AS _products_products_cloud_files from
                          (
                                    SELECT    PUBLIC.products_cloud_files.id,
                                              PUBLIC.products_cloud_files.products_id,
                                              row_to_json(products_cloud_files_cloud_files_id.*) AS cloud_files_id from PUBLIC.products_cloud_files
                                    left join lateral
                                              (
                                                     SELECT PUBLIC.cloud_files.asset_id,
                                                            PUBLIC.cloud_files.date_created,
                                                            PUBLIC.cloud_files.date_updated,
                                                            PUBLIC.cloud_files.format,
                                                            PUBLIC.cloud_files.height,
                                                            PUBLIC.cloud_files.id,
                                                            PUBLIC.cloud_files.public_id,
                                                            PUBLIC.cloud_files.resource_type,
                                                            PUBLIC.cloud_files.secure_url,
                                                            PUBLIC.cloud_files.signature,
                                                            PUBLIC.cloud_files.url,
                                                            PUBLIC.cloud_files.user_id,
                                                            PUBLIC.cloud_files.width from PUBLIC.cloud_files
                                                     WHERE  PUBLIC.products_cloud_files.cloud_files_id = PUBLIC.cloud_files.id ) AS products_cloud_files_cloud_files_id
                                    ON        TRUE
                                    WHERE     PUBLIC.products.id = PUBLIC.products_cloud_files.products_id ) AS _products_products_cloud_files) AS products_products_cloud_files
 ON         products_products_cloud_files is NOT NULL
 WHERE  
 ((search_terms is null or products.fts @@ websearch_to_tsquery(search_terms)) or
        (search_terms is null or products.category_id = ANY (
          WITH RECURSIVE cte AS (
              SELECT name, id, parent_id FROM product_categories WHERE id = ANY (select id from product_categories pc1 where pc1.fts @@ websearch_to_tsquery(search_terms))
              UNION ALL
              SELECT dt.name, dt.id, dt.parent_id FROM product_categories dt INNER JOIN cte ON cte.parent_id = dt.id and cte.id <> dt.id
          )
          SELECT id FROM cte
        )) or
        (search_terms is null or products.id = ANY (select products_id from products_brands where users_id = ANY(select id from users u where u.fts @@ websearch_to_tsquery(search_terms))))) and
        ((brand_ids is null or products.id = ANY (select products_id from products_brands where users_id = ANY(brand_ids::uuid[]) )) and
        (category_ids is null or products.category_id = ANY (category_ids::uuid[]))) and
        selected_ids is null or products.id != ANY (selected_ids::uuid[])
 limit s_limit offset s_offset) r;
$$;


ALTER FUNCTION "public"."product_search"("search_terms" "text", "brand_ids" "text", "category_ids" "text", "selected_ids" "text", "s_limit" integer, "s_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rebuild_all_fts"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  batch_size integer := 1000;
  total_count integer;
  processed integer := 0;
BEGIN
  RAISE NOTICE 'Starting optimized FTS rebuild...';
  
  -- First, populate cached brand names for all products in batches
  SELECT COUNT(*) INTO total_count FROM products;
  RAISE NOTICE 'Updating cached brand names for % products...', total_count;
  
  processed := 0;
  LOOP
    UPDATE products 
    SET cached_brand_names = COALESCE(
      (SELECT string_agg(u.name, ' ') 
       FROM products_brands pb 
       JOIN users u ON u.id = pb.users_id 
       WHERE pb.products_id = products.id), 
      ''
    )
    WHERE id IN (
      SELECT id FROM products 
      WHERE cached_brand_names = '' OR cached_brand_names IS NULL
      LIMIT batch_size
    );
    
    GET DIAGNOSTICS processed = ROW_COUNT;
    EXIT WHEN processed = 0;
    
    RAISE NOTICE 'Updated cached brand names for % products...', processed;
    PERFORM pg_sleep(0.1); -- Small delay to prevent overwhelming the database
  END LOOP;
  
  -- Now update FTS vectors in batches for each table
  RAISE NOTICE 'Updating FTS vectors...';
  
  -- Users (usually fastest)
  UPDATE users SET fts_vector = fts_vector;
  RAISE NOTICE 'Users FTS updated';
  
  -- Products (now using cached brand names, much faster)
  SELECT COUNT(*) INTO total_count FROM products;
  processed := 0;
  
  LOOP
    UPDATE products 
    SET fts_vector = 
      setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
      setweight(to_tsvector('english', coalesce(
        (SELECT pc.name FROM product_categories pc WHERE pc.id = products.category_id), ''
      )), 'B') ||
      setweight(to_tsvector('english', coalesce(cached_brand_names, '')), 'C') ||
      setweight(to_tsvector('english', coalesce(slug, '')), 'D') ||
      setweight(to_tsvector('english', coalesce(url, '')), 'D')
    WHERE id IN (
      SELECT id FROM products 
      WHERE fts_vector IS NULL
      LIMIT batch_size
    );
    
    GET DIAGNOSTICS processed = ROW_COUNT;
    EXIT WHEN processed = 0;
    
    RAISE NOTICE 'Updated FTS for % products...', processed;
    PERFORM pg_sleep(0.1);
  END LOOP;
  
  RAISE NOTICE 'Products FTS updated';
  
  -- Other tables
  UPDATE posts SET fts_vector = fts_vector;
  RAISE NOTICE 'Posts FTS updated';
  
  UPDATE lists SET fts_vector = fts_vector;
  RAISE NOTICE 'Lists FTS updated';
  
  UPDATE giveaways SET fts_vector = fts_vector;
  RAISE NOTICE 'Giveaways FTS updated';
  
  UPDATE dispensary_locations SET fts_vector = fts_vector;
  RAISE NOTICE 'Dispensary locations FTS updated';
  
  RAISE NOTICE 'All FTS vectors have been rebuilt successfully';
END;
$$;


ALTER FUNCTION "public"."rebuild_all_fts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rebuild_all_fts_optimized"("batch_size" integer DEFAULT 50, "test_limit" integer DEFAULT NULL::integer) RETURNS TABLE("step" "text", "status" "text", "message" "text", "products_processed" integer, "runtime_seconds" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  start_time timestamp;
  total_runtime numeric;
  result_record record;
BEGIN
  start_time := clock_timestamp();
  
  -- Step 1: Suggest indexes but don't try to create them
  step := 'indexes';
  status := 'info';
  message := 'For best performance, ensure these indexes exist: idx_products_brands_products_id, idx_products_brands_users_id';
  products_processed := 0;
  runtime_seconds := EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
  RETURN NEXT;
  
  -- Step 2: Populate cached brand names
  FOR result_record IN SELECT * FROM execute_brand_name_population(test_limit) LOOP
    step := 'brand_names';
    status := result_record.status;
    message := result_record.message;
    products_processed := result_record.products_processed;
    runtime_seconds := result_record.runtime_seconds;
    RETURN NEXT;
    
    -- Stop if there was an error
    IF result_record.status = 'error' THEN
      RETURN;
    END IF;
  END LOOP;
  
  -- Step 3: Rebuild FTS vectors
  FOR result_record IN SELECT * FROM rebuild_fts_vectors_in_batches(test_limit) LOOP
    step := 'fts_vectors';
    status := result_record.status;
    message := result_record.message;
    products_processed := result_record.products_processed;
    runtime_seconds := result_record.runtime_seconds;
    RETURN NEXT;
    
    -- Stop if there was an error
    IF result_record.status = 'error' THEN
      RETURN;
    END IF;
  END LOOP;
  
  -- Final summary
  total_runtime := EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
  step := 'summary';
  status := 'completed';
  message := 'All FTS rebuild steps completed successfully in ' || round(total_runtime, 1)::text || ' seconds';
  products_processed := 0;
  runtime_seconds := total_runtime;
  RETURN NEXT;
END;
$$;


ALTER FUNCTION "public"."rebuild_all_fts_optimized"("batch_size" integer, "test_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rebuild_fts_except_products"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RAISE NOTICE 'Rebuilding FTS vectors for all tables except products...';
  
  -- Users
  UPDATE users SET fts_vector = fts_vector;
  RAISE NOTICE 'Users FTS updated';
  
  -- Posts
  UPDATE posts SET fts_vector = fts_vector;
  RAISE NOTICE 'Posts FTS updated';
  
  -- Lists
  UPDATE lists SET fts_vector = fts_vector;
  RAISE NOTICE 'Lists FTS updated';
  
  -- Giveaways
  UPDATE giveaways SET fts_vector = fts_vector;
  RAISE NOTICE 'Giveaways FTS updated';
  
  -- Dispensary locations
  UPDATE dispensary_locations SET fts_vector = fts_vector;
  RAISE NOTICE 'Dispensary locations FTS updated';
  
  RAISE NOTICE 'All FTS vectors (except for products) have been rebuilt successfully';
END;
$$;


ALTER FUNCTION "public"."rebuild_fts_except_products"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rebuild_fts_vectors_in_batches"("test_limit" integer DEFAULT NULL::integer) RETURNS TABLE("status" "text", "message" "text", "products_processed" integer, "runtime_seconds" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  start_time timestamp;
  total_count integer;
  processed integer := 0;
  current_batch_size integer;
  batch_size integer := 50;
  error_message text;
BEGIN
  -- Set a longer statement timeout just for this function
  SET LOCAL statement_timeout = '300s';
  
  start_time := clock_timestamp();
  
  -- Get count of products needing updates
  SELECT COUNT(*) INTO total_count FROM products;
  
  -- Apply test limit if provided
  IF test_limit IS NOT NULL AND test_limit > 0 THEN
    total_count := LEAST(total_count, test_limit);
  END IF;
  
  -- Return initial status
  status := 'starting';
  message := 'Starting FTS vector rebuild for ' || total_count::text || ' products';
  products_processed := 0;
  runtime_seconds := 0;
  RETURN NEXT;
  
  BEGIN
    -- Process in batches to avoid timeouts
    WHILE processed < total_count LOOP
      -- Create a temporary table with the next batch of product IDs
      -- Using OFFSET instead of UUID comparison
      CREATE TEMP TABLE batch_products AS
      SELECT id, name, description, category_id, cached_brand_names, slug, url
      FROM products
      ORDER BY id
      LIMIT batch_size
      OFFSET processed;
      
      -- Get the number of products in this batch
      SELECT COUNT(*) INTO current_batch_size FROM batch_products;
      
      -- Exit if no more products to process or we've hit the test limit
      IF current_batch_size = 0 OR (test_limit IS NOT NULL AND processed >= test_limit) THEN
        EXIT;
      END IF;
      
      -- Get category names for this batch
      CREATE TEMP TABLE batch_categories AS
      SELECT pc.id, pc.name
      FROM product_categories pc
      WHERE pc.id IN (SELECT category_id FROM batch_products WHERE category_id IS NOT NULL);
      
      -- Update FTS vectors for all products in this batch at once
      WITH updates AS (
        UPDATE products p
        SET fts_vector = 
          setweight(to_tsvector('english', COALESCE(bp.name, '')), 'A') ||
          setweight(to_tsvector('english', COALESCE(bp.description, '')), 'B') ||
          setweight(to_tsvector('english', COALESCE(
            (SELECT bc.name FROM batch_categories bc WHERE bc.id = bp.category_id), ''
          )), 'B') ||
          setweight(to_tsvector('english', COALESCE(bp.cached_brand_names, '')), 'C') ||
          setweight(to_tsvector('english', COALESCE(bp.slug, '')), 'D') ||
          setweight(to_tsvector('english', COALESCE(bp.url, '')), 'D')
        FROM batch_products bp
        WHERE p.id = bp.id
        RETURNING 1
      )
      SELECT COUNT(*) INTO current_batch_size FROM updates;
      
      -- Update progress
      processed := processed + current_batch_size;
      
      -- Drop temporary tables
      DROP TABLE batch_products;
      DROP TABLE batch_categories;
      
      -- Return progress
      status := 'progress';
      message := 'Processed ' || processed::text || ' of ' || total_count::text || 
                 ' products (' || round((processed::float / total_count * 100), 1)::text || '%)';
      products_processed := processed;
      runtime_seconds := EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
      RETURN NEXT;
      
      -- Small delay to prevent database overload
      PERFORM pg_sleep(0.1);
    END LOOP;
    
    -- Update other tables
    UPDATE users SET fts_vector = fts_vector;
    UPDATE posts SET fts_vector = fts_vector;
    UPDATE lists SET fts_vector = fts_vector;
    UPDATE giveaways SET fts_vector = fts_vector;
    UPDATE dispensary_locations SET fts_vector = fts_vector;
    
    -- Return completion status
    status := 'completed';
    message := 'Completed: ' || processed::text || ' products processed in ' || 
               round(EXTRACT(EPOCH FROM (clock_timestamp() - start_time)), 1)::text || 
               ' seconds. All FTS vectors rebuilt.';
    products_processed := processed;
    runtime_seconds := EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RETURN NEXT;
    
  EXCEPTION WHEN OTHERS THEN
    -- Handle any errors
    GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
    
    status := 'error';
    message := error_message;
    products_processed := processed;
    runtime_seconds := EXTRACT(EPOCH FROM (clock_timestamp() - start_time));
    RETURN NEXT;
  END;
END;
$$;


ALTER FUNCTION "public"."rebuild_fts_vectors_in_batches"("test_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reorder_featured_items"("p_item_type" "text", "p_ordered_item_ids" "uuid"[]) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    i INT;
BEGIN
    -- Loop through the provided array of item IDs and update their sort_order
    FOR i IN 1..array_length(p_ordered_item_ids, 1) LOOP
        UPDATE public.featured_items
        SET sort_order = i - 1 -- Use 0-based indexing for sort_order
        WHERE item_type = p_item_type AND item_id = p_ordered_item_ids[i];
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."reorder_featured_items"("p_item_type" "text", "p_ordered_item_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."repopulate_all_product_cached_brands"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  product_rec RECORD;
  total_count integer;
  processed integer := 0;
  batch_size integer := 50; -- Process 50 products per batch
  delay_interval real := 0.1; -- 100 milliseconds delay between batches
BEGIN
  -- Get the total number of products for progress reporting
  SELECT COUNT(*) INTO total_count FROM products;
  RAISE NOTICE 'Starting to populate cached brand names for % products...', total_count;

  -- Loop through all products using a cursor to avoid high memory usage
  FOR product_rec IN 
    SELECT id FROM products ORDER BY id
  LOOP
    -- Call the function to update the cached names for the current product
    UPDATE products 
	  SET cached_brand_names = COALESCE(
	    (SELECT string_agg(u.name, ' ') 
	     FROM products_brands pb 
	     JOIN users u ON u.id = pb.users_id 
	     WHERE pb.products_id = product_rec.id), 
	    ''
	  )
	  WHERE id = product_rec.id;
    
    processed := processed + 1;
    
    -- After each batch, report progress and pause briefly
    IF processed % batch_size = 0 THEN
      RAISE NOTICE 'Processed % of % products (%.1%% complete)', 
        processed, total_count, (processed::float / total_count * 100);
      
      -- Pause to prevent overwhelming the database and causing a timeout
      PERFORM pg_sleep(delay_interval);
    END IF;
  END LOOP;
  
  RAISE NOTICE 'Finished populating cached brand names. % products were processed.', processed;
END;
$$;


ALTER FUNCTION "public"."repopulate_all_product_cached_brands"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_brands"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0, "exclude_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS TABLE("id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
BEGIN
    -- If search query is empty, return featured items + newest items
    IF trim(search_query) = '' THEN
        RETURN QUERY
        WITH featured AS (
            SELECT fi.item_id, fi.sort_order
            FROM public.featured_items fi
            WHERE fi.item_type = 'brands'
        ),
        featured_brands AS (
            SELECT
                u.id,
                (1.0 / (f.sort_order + 1))::real as rank,
                u.name::text as headline,
                1 as is_featured
            FROM users u
            JOIN featured f ON u.id = f.item_id
            WHERE u.role_id = 10 AND u.id <> ALL(exclude_ids)
            ORDER BY f.sort_order ASC
        ),
        newest_brands AS (
            SELECT
                u.id,
                0.0::real as rank,
                u.name::text as headline,
                0 as is_featured
            FROM users u
            WHERE u.role_id = 10 AND u.id <> ALL(exclude_ids)
            AND u.id NOT IN (SELECT fb.id FROM featured_brands fb)
            ORDER BY u.date_created DESC
        ),
        combined AS (
            SELECT * FROM featured_brands
            UNION ALL
            SELECT * FROM newest_brands
        )
        SELECT
            c.id,
            c.rank,
            c.headline,
            (SELECT count(*) FROM combined)::bigint AS total_count
        FROM combined c
        ORDER BY c.is_featured DESC, c.rank DESC, c.id
        LIMIT result_limit
        OFFSET result_offset;
    ELSE
        -- Otherwise, perform full-text search
        query := websearch_to_tsquery('english', search_query);
        RETURN QUERY
        WITH search_results AS (
            SELECT
                u.id,
                ts_rank_cd(u.fts_vector, query) as rank,
                ts_headline('english', coalesce(u.name, ''), query) as headline
            FROM users u
            WHERE u.fts_vector @@ query AND u.role_id = 10 AND u.id <> ALL(exclude_ids)
        )
        SELECT
            s.id,
            s.rank,
            s.headline,
            (SELECT count(*) FROM search_results)::bigint AS total_count
        FROM search_results s
        ORDER BY s.rank DESC
        LIMIT result_limit
        OFFSET result_offset;
    END IF;
END;
$$;


ALTER FUNCTION "public"."search_brands"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_dispensary_locations"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0, "exclude_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS TABLE("id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
BEGIN
    -- If search query is empty, return featured items + newest items
    IF trim(search_query) = '' THEN
        RETURN QUERY
        WITH featured AS (
            SELECT fi.item_id, fi.sort_order
            FROM public.featured_items fi
            WHERE fi.item_type = 'dispensary_locations'
        ),
        featured_locations AS (
            SELECT
                dl.id,
                (1.0 / (f.sort_order + 1))::real as rank,
                dl.name::text as headline,
                1 as is_featured
            FROM dispensary_locations dl
            JOIN featured f ON dl.id = f.item_id
            WHERE dl.id <> ALL(exclude_ids)
            ORDER BY f.sort_order ASC
        ),
        newest_locations AS (
            SELECT
                dl.id,
                0.0::real as rank,
                dl.name::text as headline,
                0 as is_featured
            FROM dispensary_locations dl
            WHERE dl.id <> ALL(exclude_ids)
            AND dl.id NOT IN (SELECT fl.id FROM featured_locations fl)
            ORDER BY dl.date_created DESC
        ),
        combined AS (
            SELECT * FROM featured_locations
            UNION ALL
            SELECT * FROM newest_locations
        )
        SELECT
            c.id,
            c.rank,
            c.headline,
            (SELECT count(*) FROM combined)::bigint AS total_count
        FROM combined c
        ORDER BY c.is_featured DESC, c.rank DESC, c.id
        LIMIT result_limit
        OFFSET result_offset;
    ELSE
        -- Otherwise, perform full-text search
        query := websearch_to_tsquery('english', search_query);
        RETURN QUERY
        WITH search_results AS (
            SELECT
                dl.id,
                ts_rank_cd(dl.fts_vector, query) as rank,
                ts_headline('english', coalesce(dl.name, ''), query) as headline
            FROM dispensary_locations dl
            WHERE dl.fts_vector @@ query AND dl.id <> ALL(exclude_ids)
        )
        SELECT
            s.id,
            s.rank,
            s.headline,
            (SELECT count(*) FROM search_results)::bigint AS total_count
        FROM search_results s
        ORDER BY s.rank DESC
        LIMIT result_limit
        OFFSET result_offset;
    END IF;
END;
$$;


ALTER FUNCTION "public"."search_dispensary_locations"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_giveaways"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0, "exclude_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS TABLE("id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
BEGIN
    -- If search query is empty, return featured items + newest items
    IF trim(search_query) = '' THEN
        RETURN QUERY
        WITH featured AS (
            SELECT fi.item_id, fi.sort_order
            FROM public.featured_items fi
            WHERE fi.item_type = 'giveaways'
        ),
        featured_giveaways AS (
            SELECT
                g.id,
                (1.0 / (f.sort_order + 1))::real as rank,
                g.name::text as headline,
                1 as is_featured
            FROM giveaways g
            JOIN featured f ON g.id = f.item_id
            WHERE g.id <> ALL(exclude_ids)
            ORDER BY f.sort_order ASC
        ),
        newest_giveaways AS (
            SELECT
                g.id,
                0.0::real as rank,
                g.name::text as headline,
                0 as is_featured
            FROM giveaways g
            WHERE g.id <> ALL(exclude_ids)
            AND g.id NOT IN (SELECT fg.id FROM featured_giveaways fg)
            ORDER BY g.date_created DESC
        ),
        combined AS (
            SELECT * FROM featured_giveaways
            UNION ALL
            SELECT * FROM newest_giveaways
        )
        SELECT
            c.id,
            c.rank,
            c.headline,
            (SELECT count(*) FROM combined)::bigint AS total_count
        FROM combined c
        ORDER BY c.is_featured DESC, c.rank DESC, c.id
        LIMIT result_limit
        OFFSET result_offset;
    ELSE
        -- Otherwise, perform full-text search
        query := websearch_to_tsquery('english', search_query);
        RETURN QUERY
        WITH search_results AS (
            SELECT
                g.id,
                ts_rank_cd(g.fts_vector, query) as rank,
                ts_headline('english', coalesce(g.name, ''), query) as headline
            FROM giveaways g
            WHERE g.fts_vector @@ query AND g.id <> ALL(exclude_ids)
        )
        SELECT
            s.id,
            s.rank,
            s.headline,
            (SELECT count(*) FROM search_results)::bigint AS total_count
        FROM search_results s
        ORDER BY s.rank DESC
        LIMIT result_limit
        OFFSET result_offset;
    END IF;
END;
$$;


ALTER FUNCTION "public"."search_giveaways"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_lists"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0, "exclude_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS TABLE("id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
BEGIN
    -- If search query is empty, return featured items + newest items
    IF trim(search_query) = '' THEN
        RETURN QUERY
        WITH featured AS (
            SELECT fi.item_id, fi.sort_order
            FROM public.featured_items fi
            WHERE fi.item_type = 'lists'
        ),
        featured_lists AS (
            SELECT
                l.id,
                (1.0 / (f.sort_order + 1))::real as rank,
                l.name::text as headline,
                1 as is_featured
            FROM lists l
            JOIN featured f ON l.id = f.item_id
            WHERE l.id <> ALL(exclude_ids)
            ORDER BY f.sort_order ASC
        ),
        newest_lists AS (
            SELECT
                l.id,
                0.0::real as rank,
                l.name::text as headline,
                0 as is_featured
            FROM lists l
            WHERE l.id <> ALL(exclude_ids)
            AND l.id NOT IN (SELECT fl.id FROM featured_lists fl)
            ORDER BY l.date_created DESC
        ),
        combined AS (
            SELECT * FROM featured_lists
            UNION ALL
            SELECT * FROM newest_lists
        )
        SELECT
            c.id,
            c.rank,
            c.headline,
            (SELECT count(*) FROM combined)::bigint AS total_count
        FROM combined c
        ORDER BY c.is_featured DESC, c.rank DESC, c.id
        LIMIT result_limit
        OFFSET result_offset;
    ELSE
        -- Otherwise, perform full-text search
        query := websearch_to_tsquery('english', search_query);
        RETURN QUERY
        WITH search_results AS (
            SELECT
                l.id,
                ts_rank_cd(l.fts_vector, query) as rank,
                ts_headline('english', coalesce(l.name, ''), query) as headline
            FROM lists l
            WHERE l.fts_vector @@ query AND l.id <> ALL(exclude_ids)
        )
        SELECT
            s.id,
            s.rank,
            s.headline,
            (SELECT count(*) FROM search_results)::bigint AS total_count
        FROM search_results s
        ORDER BY s.rank DESC
        LIMIT result_limit
        OFFSET result_offset;
    END IF;
END;
$$;


ALTER FUNCTION "public"."search_lists"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_posts"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0, "exclude_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS TABLE("id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
BEGIN
    -- If search query is empty, return featured items + newest items
    IF trim(search_query) = '' THEN
        RETURN QUERY
        WITH featured AS (
            SELECT fi.item_id, fi.sort_order
            FROM public.featured_items fi
            WHERE fi.item_type = 'posts'
        ),
        featured_posts AS (
            SELECT
                p.id,
                (1.0 / (f.sort_order + 1))::real as rank,
                p.message::text as headline,
                1 as is_featured
            FROM posts p
            JOIN featured f ON p.id = f.item_id
            WHERE p.id <> ALL(exclude_ids)
            ORDER BY f.sort_order ASC
        ),
        newest_posts AS (
            SELECT
                p.id,
                0.0::real as rank,
                p.message::text as headline,
                0 as is_featured
            FROM posts p
            WHERE p.id <> ALL(exclude_ids)
            AND p.id NOT IN (SELECT fp.id FROM featured_posts fp)
            ORDER BY p.date_created DESC
        ),
        combined AS (
            SELECT * FROM featured_posts
            UNION ALL
            SELECT * FROM newest_posts
        )
        SELECT
            c.id,
            c.rank,
            c.headline,
            (SELECT count(*) FROM combined)::bigint AS total_count
        FROM combined c
        ORDER BY c.is_featured DESC, c.rank DESC, c.id
        LIMIT result_limit
        OFFSET result_offset;
    ELSE
        -- Otherwise, perform full-text search
        query := websearch_to_tsquery('english', search_query);
        RETURN QUERY
        WITH search_results AS (
            SELECT
                p.id,
                ts_rank_cd(p.fts_vector, query) as rank,
                ts_headline('english', coalesce(p.message, ''), query) as headline
            FROM posts p
            WHERE p.fts_vector @@ query AND p.id <> ALL(exclude_ids)
        )
        SELECT
            s.id,
            s.rank,
            s.headline,
            (SELECT count(*) FROM search_results)::bigint AS total_count
        FROM search_results s
        ORDER BY s.rank DESC
        LIMIT result_limit
        OFFSET result_offset;
    END IF;
END;
$$;


ALTER FUNCTION "public"."search_posts"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_products"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0, "exclude_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS TABLE("id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
BEGIN
    -- If search query is empty, return featured items + newest items
    IF trim(search_query) = '' THEN
        RETURN QUERY
        WITH featured AS (
            SELECT fi.item_id, fi.sort_order
            FROM public.featured_items fi
            WHERE fi.item_type = 'products'
        ),
        featured_products AS (
            SELECT
                p.id,
                (1.0 / (f.sort_order + 1))::real as rank,
                p.name::text as headline,
                1 as is_featured
            FROM products p
            JOIN featured f ON p.id = f.item_id
            WHERE p.id <> ALL(exclude_ids)
            ORDER BY f.sort_order ASC
        ),
        newest_products AS (
            SELECT
                p.id,
                0.0::real as rank,
                p.name::text as headline,
                0 as is_featured
            FROM products p
            WHERE p.id <> ALL(exclude_ids)
            AND p.id NOT IN (SELECT fp.id FROM featured_products fp)
            ORDER BY p.date_created DESC
        ),
        combined AS (
            SELECT * FROM featured_products
            UNION ALL
            SELECT * FROM newest_products
        )
        SELECT
            c.id,
            c.rank,
            c.headline,
            (SELECT count(*) FROM combined)::bigint AS total_count
        FROM combined c
        ORDER BY c.is_featured DESC, c.rank DESC, c.id
        LIMIT result_limit
        OFFSET result_offset;
    ELSE
        -- Otherwise, perform full-text search
        query := websearch_to_tsquery('english', search_query);
        RETURN QUERY
        WITH search_results AS (
            SELECT
                p.id,
                ts_rank_cd(p.fts_vector, query) as rank,
                ts_headline('english', coalesce(p.name, ''), query) as headline
            FROM products p
            WHERE p.fts_vector @@ query AND p.id <> ALL(exclude_ids)
        )
        SELECT
            s.id,
            s.rank,
            s.headline,
            (SELECT count(*) FROM search_results)::bigint AS total_count
        FROM search_results s
        ORDER BY s.rank DESC
        LIMIT result_limit
        OFFSET result_offset;
    END IF;
END;
$$;


ALTER FUNCTION "public"."search_products"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_users"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0, "exclude_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS TABLE("id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
BEGIN
    -- If search query is empty, return featured items + newest items
    IF trim(search_query) = '' THEN
        RETURN QUERY
        WITH featured AS (
            SELECT fi.item_id, fi.sort_order
            FROM public.featured_items fi
            WHERE fi.item_type = 'users'
        ),
        featured_users AS (
            SELECT
                u.id,
                (1.0 / (f.sort_order + 1))::real as rank,
                u.name::text as headline,
                1 as is_featured
            FROM users u
            JOIN featured f ON u.id = f.item_id
            WHERE u.role_id != 10 AND u.id <> ALL(exclude_ids)
            ORDER BY f.sort_order ASC
        ),
        newest_users AS (
            SELECT
                u.id,
                0.0::real as rank,
                u.name::text as headline,
                0 as is_featured
            FROM users u
            WHERE u.role_id != 10 AND u.id <> ALL(exclude_ids)
            AND u.id NOT IN (SELECT fu.id FROM featured_users fu)
            ORDER BY u.date_created DESC
        ),
        combined AS (
            SELECT * FROM featured_users
            UNION ALL
            SELECT * FROM newest_users
        )
        SELECT
            c.id,
            c.rank,
            c.headline,
            (SELECT count(*) FROM combined)::bigint AS total_count
        FROM combined c
        ORDER BY c.is_featured DESC, c.rank DESC, c.id
        LIMIT result_limit
        OFFSET result_offset;
    ELSE
        -- Otherwise, perform full-text search
        query := websearch_to_tsquery('english', search_query);
        RETURN QUERY
        WITH search_results AS (
            SELECT
                u.id,
                ts_rank_cd(u.fts_vector, query) as rank,
                ts_headline('english', coalesce(u.name, ''), query) as headline
            FROM users u
            WHERE u.fts_vector @@ query AND u.role_id != 10 AND u.id <> ALL(exclude_ids)
        )
        SELECT
            s.id,
            s.rank,
            s.headline,
            (SELECT count(*) FROM search_results)::bigint AS total_count
        FROM search_results s
        ORDER BY s.rank DESC
        LIMIT result_limit
        OFFSET result_offset;
    END IF;
END;
$$;


ALTER FUNCTION "public"."search_users"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."select_giveaway_contest_winner"("gid" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
declare
  c_check record; 
  g record;
  p record;
  th record;
  st1 json;
  st2 json;
  winner record;
  winners text[];
  losers text[];
  r json;
  res json;
begin
  select * into g from giveaways where giveaways.id = gid;

  if exists (select id from giveaway_entries where giveaway_id = g.id) then
    -- Get product
    select id, name, thumbnail_id into p from products where id = g.product_id;

    select id, secure_url into th from cloud_files where id = p.thumbnail_id;

    raise warning 'Selecting winners for giveaway id %', g.id;

    raise warning 'Total prises %', g.total_prizes;

    -- Select winners
    update giveaway_entries set won = true where id = ANY(select id from giveaway_entries order by random() limit g.total_prizes::int);

    -- Send push notifications
    select json_build_array(user_id) into st1 from giveaway_entries where giveaway_id = g.id and won = true;

    raise warning 'Selected winners ids %', st1;

    select array_agg(u1.email) into winners from giveaway_entries left join users u1 on u1.id = user_id where giveaway_id = g.id and won = true;

    raise warning 'Selected winners emails %', winners;

    select * into r from send_push_noti(
            message => 'Congrats! 🎁 You won a ' || p.name || '. Tap to check your status.',
            devices => st1,
            data_type => 'GW',
            campaign => p.name || ' - contest winners.',
            app_url => 'hybrid://gethybrid.co/products/giveaway/' || g.id
        );

    -- insert new app notifications
    insert into notifications (type_id, giveaway_id, message, user_id) select 5, g.id, 'You won a giveaway for: ' || p.name || ' .' , user_id from giveaway_entries where giveaway_id = g.id and won = true;

    -- Send push notification to other users to check if they won
    select json_build_array(user_id) into st2 from giveaway_entries where giveaway_id = g.id and won = false;
    
    raise warning 'Selected losers ids %', st2;
    
    select array_agg(u2.email) into losers from giveaway_entries left join users u2 on u2.id = user_id  where giveaway_id = g.id and won = false;
    
    raise warning 'Selected losers emails %', losers;
    
    select * into r from send_push_noti(
            message => 'Giveaway for ' || p.name || ' just ended. Tap to check if you won.',
            devices => st2,
            data_type => 'GE',
            campaign => p.name || ' - contest losers.',
            app_url => 'hybrid://gethybrid.co/products/giveaway/' || g.id
        );

    -- send emails to the winners

    update giveaways set winner_count = (select count(id) from giveaway_entries where giveaway_id = g.id and won = true group by giveaway_id) where giveaways.id = g.id;

    for winner in (select email from giveaway_entries left join users u1 on u1.id = user_id where giveaway_id = g.id and won = true) loop
      
    select * into res from public.send_email_message(
    jsonb_build_object(
      'sender', 'info@gethybrid.co',
      'recipient', winner.email,
      'subject', 'Winners for the ' || g.name || ' giveaway.',
      'template', 'giveaway_winner',
      'variables', jsonb_build_object(
        'giveawayName', g.name,
        'productName', p.name,
        'thumbnail', th.secure_url
      )
      --  'html_body', '<html><body>' || winners::text || '</body></html>'
    )
    );
    end loop;

        -- Send email to Nadir about the winnners
        select * into res from send_email_message(
          jsonb_build_object(
            'sender', 'sender@gethybrid.co',
            'recipient', 'nadir@gethybrid.co',
            'subject', 'Winners for the ' || g.name || ' giveaway.',
            'html_body', '<html><body>' || winners::text || '</body></html>'
          )
        );
  end if;
  
  -- update giveaway
    update giveaways set selected_winner = true where id = g.id;
end;
$$;


ALTER FUNCTION "public"."select_giveaway_contest_winner"("gid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_email_mailgun"("message" "jsonb") RETURNS "json"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  retval json;
  MAILGUN_DOMAIN text;
  MAILGUN_API_KEY text;
BEGIN
  
  SELECT value::text INTO MAILGUN_DOMAIN FROM private.keys WHERE key = 'MAILGUN_DOMAIN';
  IF NOT found THEN RAISE warning 'MAILGUN %', 'missing entry in private.keys: MAILGUN_DOMAIN'; END IF;
  SELECT value::text INTO MAILGUN_API_KEY FROM private.keys WHERE key = 'MAILGUN_API_KEY';
  IF NOT found THEN RAISE warning 'MAILGUN %', 'missing entry in private.keys: MAILGUN_API_KEY'; END IF;

  raise warning 'vals %', ('POST', 
      'https://api.mailgun.net/v3/' || MAILGUN_DOMAIN || '/messages', 
      ARRAY[http_header ('Authorization', 
      'Basic ' || encode(MAILGUN_API_KEY::bytea, 'base64'::text))], 
      'application/x-www-form-urlencoded', 
      'from=' || urlencode (message->>'sender') || 
      '&to=' || urlencode (message->>'recipient') ||
      CASE WHEN message->>'cc' IS NOT NULL THEN '&cc=' || urlencode(message->>'cc') ELSE '' END || 
      CASE WHEN message->>'bcc' IS NOT NULL THEN '&bcc=' || urlencode(message->>'bcc') ELSE '' END || 
      CASE WHEN message->>'messageid' IS NOT NULL THEN '&v:messageid=' || urlencode(message->>'messageid') ELSE '' END || 
      '&subject=' || urlencode(message->>'subject') || 
      CASE WHEN message->>'text_body' IS NOT NULL THEN '&text=' || urlencode(message->>'text_body') ELSE '' END || 
      CASE WHEN message->>'template' IS NOT NULL THEN '&template=' || urlencode(message->>'template') ELSE '' END ||
      CASE WHEN message->>'variables' IS NOT NULL THEN '&h:X-Mailgun-Variables=' || urlencode(message->>'variables') ELSE '' END || 
      CASE WHEN message->>'html_body' IS NOT NULL THEN '&html=' || urlencode(message->>'html_body') ELSE '' END 
    );

  SELECT
    * INTO retval
  FROM
    http (('POST', 
      'https://api.mailgun.net/v3/' || MAILGUN_DOMAIN || '/messages', 
      ARRAY[http_header ('Authorization', 
      'Basic ' || encode(MAILGUN_API_KEY::bytea, 'base64'::text))], 
      'application/x-www-form-urlencoded', 
      'from=' || urlencode (message->>'sender') || 
      '&to=' || urlencode (message->>'recipient') ||
      CASE WHEN message->>'cc' IS NOT NULL THEN '&cc=' || urlencode(message->>'cc') ELSE '' END || 
      CASE WHEN message->>'bcc' IS NOT NULL THEN '&bcc=' || urlencode(message->>'bcc') ELSE '' END || 
      CASE WHEN message->>'messageid' IS NOT NULL THEN '&v:messageid=' || urlencode(message->>'messageid') ELSE '' END || 
      '&subject=' || urlencode(message->>'subject') || 
      CASE WHEN message->>'text_body' IS NOT NULL THEN '&text=' || urlencode(message->>'text_body') ELSE '' END || 
      CASE WHEN message->>'template' IS NOT NULL THEN '&template=' || urlencode(message->>'template') ELSE '' END ||
      CASE WHEN message->>'variables' IS NOT NULL THEN '&h:X-Mailgun-Variables=' || urlencode(message->>'variables') ELSE '' END || 
      CASE WHEN message->>'html_body' IS NOT NULL THEN '&html=' || urlencode(message->>'html_body') ELSE '' END 
    ));
      -- if the message table exists, 
      -- and the response from the mail server contains an id
      -- and the message from the mail server starts wtih 'Queued'
      -- mark this message as 'queued' in our message table, otherwise leave it as 'ready'
      IF  (SELECT to_regclass('public.messages')) IS NOT NULL AND 
          retval->'id' IS NOT NULL 
          AND substring(retval->>'message',1,6) = 'Queued' THEN
        UPDATE public.messages SET status = 'queued' WHERE id = (message->>'messageid')::UUID;
      END IF;

  RETURN retval;
END;
$$;


ALTER FUNCTION "public"."send_email_mailgun"("message" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_email_message"("message" "jsonb") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $_$
DECLARE
  -- variable declaration
  email_provider text := 'mailgun'; -- 'mailgun', 'sendgrid', 'sendinblue', 'mailjet', 'mailersend'
  retval json;
  messageid text;
BEGIN


  IF message->'text_body' IS NULL AND message->'html_body' IS NULL AND message->'template' IS NULL THEN RAISE 'message.text_body or message.html_body is required'; END IF;
  
  IF message->'text_body' IS NULL AND message->'html_body' IS NULL AND message->'template' IS NULL THEN RAISE 'message.template is required'; END IF;

  IF message->'text_body' IS NULL AND message->'template' IS NULL THEN     
     select message || jsonb_build_object('text_body',message->>'html_body') into message;
  END IF;
  
  IF message->'html_body' IS NULL AND message->'template' IS NULL THEN 
     select message || jsonb_build_object('html_body',message->>'text_body') into message;
  END IF;  

  IF message->'recipient' IS NULL THEN RAISE 'message.recipient is required'; END IF;
  IF message->'sender' IS NULL THEN RAISE 'message.sender is required'; END IF;
  IF message->'subject' IS NULL THEN RAISE 'message.subject is required'; END IF;

  -- IF message->'messageid' IS NULL AND (SELECT to_regclass('public.messages')) IS NOT NULL THEN
  --   -- messages table exists, so save this message in the messages table
  --   INSERT INTO public.messages(recipient, sender, cc, bcc, subject, text_body, html_body, status, log)
  --   VALUES (message->'recipient', message->'sender', message->'cc', message->'bcc', message->'subject', message->'text_body', message->'html_body', 'ready', '[]'::jsonb) RETURNING id INTO messageid;
  --   select message || jsonb_build_object('messageid',messageid) into message;
  -- END IF;

  RAISE WARNING 'Message %', message;

  EXECUTE 'SELECT send_email_' || email_provider || '($1)' INTO retval USING message;
  -- SELECT send_email_mailgun(message) INTO retval;
  -- SELECT send_email_sendgrid(message) INTO retval;

  RETURN retval;
END;
$_$;


ALTER FUNCTION "public"."send_email_message"("message" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_push_noti"("message" "text", "devices" "json", "data_type" "text", "campaign" "text", "app_url" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
   BEGIN
        return (SELECT status from http((
                     'POST',
                     'https://onesignal.com/api/v1/notifications',
                     ARRAY[
                        http_header('Authorization','Bearer NzRlNzg5OTctOWIzYy00NjgyLThiZTYtYWJkOWJlYmE0YjE3')
                     ],
                     'application/json',
                     jsonb_build_object(
                        'app_id','1aa58377-7be7-4a0d-a6bc-41437a2f4c08',
                        'include_external_user_ids', devices,
                        'external_id', gen_random_uuid(),
                        'contents', jsonb_build_object('en', message),
                        -- 'headings', jsonb_build_object('en', 'Test Message.'),
                        'content_available', 1,
                        'data', jsonb_build_object('type', data_type),
                        'name', campaign,
                        'app_url', app_url
                        )::jsonb
                  )::http_request));
      --   RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


ALTER FUNCTION "public"."send_push_noti"("message" "text", "devices" "json", "data_type" "text", "campaign" "text", "app_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_initial_featured_item_sort_order"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- If sort_order is not provided, place it at the end of the list for its type
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


ALTER FUNCTION "public"."set_initial_featured_item_sort_order"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_slug_from_name"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$declare
  newslug text;
BEGIN
  IF (NEW.name IS DISTINCT FROM OLD.name) THEN
  raise info 'Name %', NEW.name;
  newslug := slugify(NEW.name);
  
  NEW.slug := newslug;
  END IF;
  RETURN NEW;
END
$$;


ALTER FUNCTION "public"."set_slug_from_name"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_slug_from_username"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.slug := slugify(NEW.username);
  RETURN NEW;
END
$$;


ALTER FUNCTION "public"."set_slug_from_username"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."slugify"("value" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $_$
  -- removes accents (diacritic signs) from a given string --
  WITH "unaccented" AS (
    SELECT unaccent("value") AS "value"
  ),
  -- lowercases the string
  "lowercase" AS (
    SELECT lower("value") AS "value"
    FROM "unaccented"
  ),
  -- replaces anything that's not a letter, number, hyphen('-'), or underscore('_') with a hyphen('-')
  "hyphenated" AS (
    SELECT regexp_replace("value", '[^a-z0-9\\-_]+', '-', 'gi') AS "value"
    FROM "lowercase"
  ),
  -- trims hyphens('-') if they exist on the head or tail of the string
  "trimmed" AS (
    SELECT regexp_replace(regexp_replace("value", '\\-+$', ''), '^\\-', '') AS "value"
    FROM "hyphenated"
  )
  SELECT "value" FROM "trimmed";
$_$;


ALTER FUNCTION "public"."slugify"("value" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."slugify_varchar"("v" character varying) RETURNS character varying
    LANGUAGE "plpgsql" IMMUTABLE STRICT
    AS $$
BEGIN
  -- 1. trim trailing and leading whitespaces from text
  -- 2. remove accents (diacritic signs) from a given text
  -- 3. lowercase unaccented text
  -- 4. replace non-alphanumeric (excluding hyphen, underscore) with a hyphen
  -- 5. trim leading and trailing hyphens
  RETURN trim(BOTH '-' FROM regexp_replace(lower(unaccent(trim(v))), '[^a-z0-9\\-_]+', '-', 'gi'));
END;
$$;


ALTER FUNCTION "public"."slugify_varchar"("v" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_credentials"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF (NEW.phone = ANY(array['+12125551212', '+15185551212'])) THEN
        NEW.confirmation_token := '123456';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."test_credentials"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_product_brand_names"("product_id" bigint) RETURNS TABLE("product_name" "text", "brand_count" bigint, "brand_names" "text", "query_time_ms" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  start_time timestamp;
  end_time timestamp;
  p_name text;
BEGIN
  -- Get product name
  SELECT name INTO p_name FROM products WHERE id = product_id;
  
  -- Time the brand names query
  start_time := clock_timestamp();
  
  -- Get brand information
  SELECT 
    p_name,
    COUNT(pb.users_id),
    COALESCE(string_agg(u.name, ' '), ''),
    EXTRACT(MILLISECONDS FROM (clock_timestamp() - start_time))
  INTO product_name, brand_count, brand_names, query_time_ms
  FROM products p
  LEFT JOIN products_brands pb ON pb.products_id = product_id
  LEFT JOIN users u ON u.id = pb.users_id
  WHERE p.id = product_id
  GROUP BY p.id;
  
  RETURN NEXT;
END;
$$;


ALTER FUNCTION "public"."test_product_brand_names"("product_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_product_brand_names"("product_id" "uuid") RETURNS TABLE("product_name" "text", "brand_count" bigint, "brand_names" "text", "query_time_ms" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  start_time timestamp;
  end_time timestamp;
  p_name text;
BEGIN
  -- Get product name
  SELECT name INTO p_name FROM products WHERE id = product_id;
  
  -- Time the brand names query
  start_time := clock_timestamp();
  
  -- Get brand information
  SELECT 
    p_name,
    COUNT(pb.users_id),
    COALESCE(string_agg(u.name, ' '), ''),
    EXTRACT(MILLISECONDS FROM (clock_timestamp() - start_time))
  INTO product_name, brand_count, brand_names, query_time_ms
  FROM products p
  LEFT JOIN products_brands pb ON pb.products_id = product_id
  LEFT JOIN users u ON u.id = pb.users_id
  WHERE p.id = product_id
  GROUP BY p.id;
  
  RETURN NEXT;
END;
$$;


ALTER FUNCTION "public"."test_product_brand_names"("product_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_set_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.date_updated = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_set_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_set_updated_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
IF (TG_OP = 'UPDATE') THEN
             NEW.date_updated = NOW();
              RETURN NEW;
            RETURN NEW;
        END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_set_updated_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."typeahead_dispensary_locations"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "address1" "text", "address2" "text", "brand_name" "text", "place_name" "text", "state" "text", "postal_code" "text", "rank" real)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    dl.id,
    dl.name::text,
    dl.address1::text,
    dl.address2::text,
    coalesce(u.name, '')::text as brand_name,
    coalesce(pc.place_name, '')::text as place_name,
    coalesce(pc.state, '')::text as state,
    coalesce(pc.postal_code, '')::text as postal_code,
    CASE 
      WHEN dl.name ILIKE (query_prefix || '%') THEN 100
      WHEN dl.address1 ILIKE (query_prefix || '%') THEN 95
      WHEN pc.place_name ILIKE (query_prefix || '%') THEN 90
      WHEN pc.state ILIKE (query_prefix || '%') THEN 85
      ELSE ts_rank(dl.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM dispensary_locations dl
  LEFT JOIN users u ON u.id = dl.brand_id
  LEFT JOIN postal_codes pc ON pc.id = dl.postal_code_id
  WHERE 
    dl.name ILIKE (query_prefix || '%')
    OR dl.address1 ILIKE (query_prefix || '%')
    OR pc.place_name ILIKE (query_prefix || '%')
    OR pc.state ILIKE (query_prefix || '%')
    OR dl.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, dl.name
  LIMIT limit_results;
END;
$$;


ALTER FUNCTION "public"."typeahead_dispensary_locations"("search_query" "text", "limit_results" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."typeahead_giveaways"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "description" "text", "product_name" "text", "end_time" timestamp with time zone, "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    g.id,
    g.name::text,
    g.description::text,
    coalesce(p.name::text, '') as product_name,
    g.end_time,
    CASE 
      WHEN g.name ILIKE (query_prefix || '%') THEN 100
      WHEN g.description ILIKE (query_prefix || '%') THEN 90
      ELSE ts_rank(g.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM giveaways g
  LEFT JOIN products p ON p.id = g.product_id
  WHERE 
    g.name ILIKE (query_prefix || '%')
    OR g.description ILIKE (query_prefix || '%')
    OR g.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, g.end_time DESC
  LIMIT limit_results;
END;$$;


ALTER FUNCTION "public"."typeahead_giveaways"("search_query" "text", "limit_results" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."typeahead_lists"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "description" "text", "user_name" "text", "user_username" "text", "date_created" timestamp with time zone, "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    l.id,
    l.name::text,
    l.description::text,
    coalesce(u.name::text, '') as user_name,
    coalesce(u.username::text, '') as user_username,
    l.date_created,
    CASE 
      WHEN l.name ILIKE (query_prefix || '%') THEN 100
      WHEN l.description ILIKE (query_prefix || '%') THEN 90
      ELSE ts_rank(l.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM lists l
  LEFT JOIN users u ON u.id = l.user_id
  WHERE 
    l.name ILIKE (query_prefix || '%')
    OR l.description ILIKE (query_prefix || '%')
    OR l.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, l.date_created DESC
  LIMIT limit_results;
END;$$;


ALTER FUNCTION "public"."typeahead_lists"("search_query" "text", "limit_results" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."typeahead_posts"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "message" "text", "user_name" "text", "user_username" "text", "date_created" timestamp with time zone, "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    p.id,
    p.message::text,
    coalesce(u.name::text, '') as user_name,
    coalesce(u.username::text, '') as user_username,
    p.date_created,
    CASE 
      WHEN p.message ILIKE (query_prefix || '%') THEN 100
      ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM posts p
  LEFT JOIN users u ON u.id = p.user_id
  WHERE 
    p.message ILIKE (query_prefix || '%')
    OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, p.date_created DESC
  LIMIT limit_results;
END;$$;


ALTER FUNCTION "public"."typeahead_posts"("search_query" "text", "limit_results" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."typeahead_products"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "category_name" "text", "thumbnail_url" "text", "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    p.id,
    p.name::text,
    coalesce(pc.name::text, '') as category_name,
    coalesce(cf.secure_url::text, '') as thumbnail_url,
    CASE 
      WHEN p.name ILIKE (query_prefix || '%') THEN 100
      ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id
  LEFT JOIN cloud_files cf ON cf.id = p.thumbnail_id
  WHERE 
    p.name ILIKE (query_prefix || '%')
    OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, p.name
  LIMIT limit_results;
END;$$;


ALTER FUNCTION "public"."typeahead_products"("search_query" "text", "limit_results" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."typeahead_universal"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("table_name" "text", "id" "uuid", "display_name" "text", "secondary_text" "text", "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  (
    -- Users
    SELECT 
      'users'::text,
      u.id,
      u.name::text as display_name,
      '@' || coalesce(u.username::text, '') as secondary_text,
      CASE 
        WHEN u.username ILIKE (query_prefix || '%') THEN 100
        WHEN u.name ILIKE (query_prefix || '%') THEN 90
        ELSE ts_rank(u.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM users u
    WHERE 
      u.name ILIKE (query_prefix || '%')
      OR u.username ILIKE (query_prefix || '%')
      OR u.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Products
    SELECT 
      'products'::text,
      p.id,
      p.name as display_name,
      coalesce(pc.name, '') as secondary_text,
      CASE 
        WHEN p.name ILIKE (query_prefix || '%') THEN 100
        ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM products p
    LEFT JOIN product_categories pc ON pc.id = p.category_id
    WHERE 
      p.name ILIKE (query_prefix || '%')
      OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Posts
    SELECT 
      'posts'::text,
      p.id,
      coalesce(left(p.message, 50), '') as display_name,
      coalesce(u.name, '') as secondary_text,
      CASE 
        WHEN p.message ILIKE (query_prefix || '%') THEN 100
        ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM posts p
    LEFT JOIN users u ON u.id = p.user_id
    WHERE 
      p.message ILIKE (query_prefix || '%')
      OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Lists
    SELECT 
      'lists'::text,
      l.id,
      l.name as display_name,
      coalesce(u.name, '') as secondary_text,
      CASE 
        WHEN l.name ILIKE (query_prefix || '%') THEN 100
        WHEN l.description ILIKE (query_prefix || '%') THEN 90
        ELSE ts_rank(l.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM lists l
    LEFT JOIN users u ON u.id = l.user_id
    WHERE 
      l.name ILIKE (query_prefix || '%')
      OR l.description ILIKE (query_prefix || '%')
      OR l.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Giveaways
    SELECT 
      'giveaways'::text,
      g.id,
      coalesce(g.name, '') as display_name,
      coalesce(p.name, '') as secondary_text,
      CASE 
        WHEN g.name ILIKE (query_prefix || '%') THEN 100
        WHEN g.description ILIKE (query_prefix || '%') THEN 90
        ELSE ts_rank(g.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM giveaways g
    LEFT JOIN products p ON p.id = g.product_id
    WHERE 
      g.name ILIKE (query_prefix || '%')
      OR g.description ILIKE (query_prefix || '%')
      OR g.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Dispensary Locations
    SELECT 
      'dispensary_locations'::text,
      dl.id,
      dl.name as display_name,
      coalesce(pc.place_name || ', ' || pc.state, dl.address1) as secondary_text,
      CASE 
        WHEN dl.name ILIKE (query_prefix || '%') THEN 100
        WHEN dl.address1 ILIKE (query_prefix || '%') THEN 95
        WHEN pc.place_name ILIKE (query_prefix || '%') THEN 90
        WHEN pc.state ILIKE (query_prefix || '%') THEN 85
        ELSE ts_rank(dl.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM dispensary_locations dl
    LEFT JOIN postal_codes pc ON pc.id = dl.postal_code
    WHERE 
      dl.name ILIKE (query_prefix || '%')
      OR dl.address1 ILIKE (query_prefix || '%')
      OR pc.place_name ILIKE (query_prefix || '%')
      OR pc.state ILIKE (query_prefix || '%')
      OR dl.fts_vector @@ plainto_tsquery('english', query_prefix)
  )
  ORDER BY rank DESC
  LIMIT limit_results;
END;$$;


ALTER FUNCTION "public"."typeahead_universal"("search_query" "text", "limit_results" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."typeahead_users"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "username" "text", "profile_picture_url" "text", "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    u.id,
    u.name::text,
    u.username::text,
    coalesce(cf.secure_url, '') as profile_picture_url,
    CASE 
      WHEN u.username ILIKE (query_prefix || '%') THEN 100
      WHEN u.name ILIKE (query_prefix || '%') THEN 90
      ELSE ts_rank(u.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM users u
  LEFT JOIN cloud_files cf ON cf.id = u.profile_picture_id
  WHERE 
    u.name ILIKE (query_prefix || '%')
    OR u.username ILIKE (query_prefix || '%')
    OR u.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, u.name
  LIMIT limit_results;
END;$$;


ALTER FUNCTION "public"."typeahead_users"("search_query" "text", "limit_results" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."universal_search"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0) RETURNS TABLE("table_name" "text", "id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
    total_rows bigint;
BEGIN
    query := to_tsquery('english', search_query);

    -- Calculate total count across all tables
    SELECT sum(count)
    INTO total_rows
    FROM (
        SELECT count(*) FROM posts WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM products WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM users WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM lists WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM giveaways WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM dispensary_locations WHERE fts_vector @@ query
    ) as counts;

    RETURN QUERY
    WITH all_results AS (
        SELECT 'posts'::text as table_name, p.id, ts_rank(p.fts_vector, query) as rank,
               ts_headline('english', coalesce(p.message, ''), query) as headline
        FROM posts p
        WHERE p.fts_vector @@ query

        UNION ALL

        SELECT 'products'::text, p.id, ts_rank(p.fts_vector, query) as rank,
               ts_headline('english', coalesce(p.name, ''), query) as headline
        FROM products p
        WHERE p.fts_vector @@ query

        UNION ALL

        SELECT 'users'::text, u.id, ts_rank(u.fts_vector, query) as rank,
               ts_headline('english', coalesce(u.name, ''), query) as headline
        FROM users u
        WHERE u.fts_vector @@ query

        UNION ALL

        SELECT 'lists'::text, l.id, ts_rank(l.fts_vector, query) as rank,
               ts_headline('english', coalesce(l.name, ''), query) as headline
        FROM lists l
        WHERE l.fts_vector @@ query

        UNION ALL

        SELECT 'giveaways'::text, g.id, ts_rank(g.fts_vector, query) as rank,
               ts_headline('english', coalesce(g.name, ''), query) as headline
        FROM giveaways g
        WHERE g.fts_vector @@ query

        UNION ALL

        SELECT 'dispensary_locations'::text, dl.id, ts_rank(dl.fts_vector, query) as rank,
               ts_headline('english', coalesce(dl.name, ''), query) as headline
        FROM dispensary_locations dl
        WHERE dl.fts_vector @@ query
    )
    SELECT r.table_name, r.id, r.rank, r.headline, total_rows
    FROM all_results r
    ORDER BY r.rank DESC
    LIMIT result_limit
    OFFSET result_offset;
END;
$$;


ALTER FUNCTION "public"."universal_search"("search_query" "text", "result_limit" integer, "result_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_associated_data"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    UPDATE products SET date_updated = NOW() WHERE products.id = ANY(select products_id from products_brands where users_id = NEW.id);
    UPDATE posts SET date_updated = NOW() WHERE user_id = NEW.id;
    UPDATE dispensary_locations SET date_updated = NOW() WHERE brand_id = NEW.id;
    UPDATE lists SET date_updated = NOW() WHERE user_id = NEW.id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_associated_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_dispensary_locations_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.about_us, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT u.name FROM users u WHERE u.id = NEW.brand_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.address1, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.address2, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.delivery_details, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.place_name FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.state FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'D') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.postal_code FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_dispensary_locations_fts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_employee_approval"("p_dispensary_id" "uuid", "p_user_id" "uuid", "p_is_approved" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE dispensary_employees
  SET 
    has_been_reviewed = TRUE,
    is_approved = p_is_approved
  WHERE 
    dispensary_id = p_dispensary_id
    AND user_id = p_user_id;
END;
$$;


ALTER FUNCTION "public"."update_employee_approval"("p_dispensary_id" "uuid", "p_user_id" "uuid", "p_is_approved" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_fts_vector"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.about_us, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT u.name FROM users u WHERE u.id = NEW.brand_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.address1, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.address2, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.delivery_details, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.place_name FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.state FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'D') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.postal_code FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_fts_vector"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_giveaways_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.terms_url, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.name FROM products p WHERE p.id = NEW.product_id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.name 
       FROM products p 
       JOIN product_categories pc ON pc.id = p.category_id 
       WHERE p.id = NEW.product_id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pc.postal_code, ' ')
       FROM giveaways_regions gr
       JOIN region_postal_codes rpc ON rpc.region_id = gr.region_id
       JOIN postal_codes pc ON pc.id = rpc.postal_code_id
       WHERE gr.giveaway_id = NEW.id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_giveaways_fts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_lists_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT u.name FROM users u WHERE u.id = NEW.user_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT u.username FROM users u WHERE u.id = NEW.user_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM lists_products lp 
       JOIN products p ON p.id = lp.products_id 
       WHERE lp.lists_id = NEW.id), ''
    )), 'C');
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_lists_fts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_notification_image_url"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Set search path to empty to prevent search path injection
    SET search_path = '';
    
    -- Check actor_id and get profile picture if available
    IF NEW.actor_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.users u
            ON u.profile_picture_id = f.id
            WHERE u.id = NEW.actor_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    -- Check product_id and get thumbnail if available
    IF NEW.product_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.products u
            ON u.thumbnail_id = f.id
            WHERE u.id = NEW.product_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    -- Check post_id and get image if available
    IF NEW.post_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.posts u
            ON u.file_id = f.id
            WHERE u.id = NEW.post_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    -- Check giveaway_id and get image if available
    IF NEW.giveaway_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.giveaways u
            ON u.cover_id = f.id
            WHERE u.id = NEW.giveaway_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    -- Check list_id and get image if available
    IF NEW.list_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.lists u
            ON u.thumbnail_id = f.id
            WHERE u.id = NEW.list_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_notification_image_url"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_null_cached_brand_names"() RETURNS TABLE("product_id" bigint, "product_name" "text", "old_cached_brand_names" "text", "new_cached_brand_names" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    product_record RECORD;
    new_brand_names text;
BEGIN
    FOR product_record IN SELECT * FROM products WHERE cached_brand_names IS NULL
    LOOP
        -- Get the new brand names
        SELECT string_agg(u.name, ' ') INTO new_brand_names
        FROM products_brands pb 
        JOIN users u ON u.id = pb.users_id 
        WHERE pb.products_id = product_record.id;
        
        -- Update cached_brand_names and fts_vector
        UPDATE products
        SET cached_brand_names = new_brand_names,
        fts_vector = 
            setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
            setweight(to_tsvector('english', coalesce(
                (SELECT pc.name FROM product_categories pc WHERE pc.id = product_record.category_id), ''
            )), 'B') ||
            setweight(to_tsvector('english', coalesce(new_brand_names, '')), 'C') ||
            setweight(to_tsvector('english', coalesce(product_record.slug, '')), 'D') ||
            setweight(to_tsvector('english', coalesce(product_record.url, '')), 'D')
        WHERE id = product_record.id;
        
        -- Return this record's information
        product_id := product_record.id;
        product_name := product_record.name;
        old_cached_brand_names := product_record.cached_brand_names;
        new_cached_brand_names := new_brand_names;
        RETURN NEXT;
    END LOOP;
    
    RETURN;
END;
$$;


ALTER FUNCTION "public"."update_null_cached_brand_names"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_posts_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.url, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT u.name FROM users u WHERE u.id = NEW.user_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT u.username FROM users u WHERE u.id = NEW.user_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM posts_products pp 
       JOIN products p ON p.id = pp.products_id 
       WHERE pp.posts_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pc.name, ' ') 
       FROM posts_products pp 
       JOIN products p ON p.id = pp.products_id 
       JOIN product_categories pc ON pc.id = p.category_id 
       WHERE pp.posts_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pt.tag, ' ') 
       FROM posts_hashtags ph 
       JOIN post_tags pt ON pt.id = ph.post_tags_id 
       WHERE ph.posts_id = NEW.id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_posts_fts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_product_cached_brands"("product_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  brand_names text;
BEGIN
  -- Get brand names for this product
  SELECT COALESCE(string_agg(u.name, ' '), '') INTO brand_names
  FROM products_brands pb 
  JOIN users u ON u.id = pb.users_id 
  WHERE pb.products_id = product_id;
  
  -- Update the product
  UPDATE products 
  SET cached_brand_names = brand_names
  WHERE id = product_id;
END;
$$;


ALTER FUNCTION "public"."update_product_cached_brands"("product_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_products_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.cached_brand_names := (
    SELECT string_agg(u.name, ' ') 
    FROM products_brands pb 
    JOIN users u ON u.id = pb.users_id 
    WHERE pb.products_id = NEW.id
  );
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.name FROM product_categories pc WHERE pc.id = NEW.category_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(u.name, ' ') 
       FROM products_brands pb 
       JOIN users u ON u.id = pb.users_id 
       WHERE pb.products_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.slug, '')), 'D') ||
    setweight(to_tsvector('english', coalesce(NEW.url, '')), 'D');
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_products_fts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_products_fts_data"() RETURNS TABLE("product_id" bigint, "product_name" "text", "was_null" boolean, "old_value" "text", "new_value" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    product_record RECORD;
    new_brand_names text;
BEGIN
    -- Process all products or just those with NULL cached_brand_names
    -- Change "WHERE cached_brand_names IS NULL" to "LIMIT 10" to test with any records
    FOR product_record IN SELECT * FROM products WHERE cached_brand_names IS NULL
    LOOP
        -- Get the new brand names
        SELECT string_agg(u.name, ' ') INTO new_brand_names
        FROM products_brands pb 
        JOIN users u ON u.id = pb.users_id 
        WHERE pb.products_id = product_record.id;
        
        -- Only update if we have brand names to set or if cached_brand_names is NULL
        IF new_brand_names IS NOT NULL OR product_record.cached_brand_names IS NULL THEN
            -- Update cached_brand_names and fts_vector
            UPDATE products
            SET cached_brand_names = new_brand_names,
            fts_vector = 
                setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
                setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
                setweight(to_tsvector('english', coalesce(
                    (SELECT pc.name FROM product_categories pc WHERE pc.id = product_record.category_id), ''
                )), 'B') ||
                setweight(to_tsvector('english', coalesce(new_brand_names, '')), 'C') ||
                setweight(to_tsvector('english', coalesce(product_record.slug, '')), 'D') ||
                setweight(to_tsvector('english', coalesce(product_record.url, '')), 'D')
            WHERE id = product_record.id;
            
            -- Return this record's information
            product_id := product_record.id;
            product_name := product_record.name;
            was_null := product_record.cached_brand_names IS NULL;
            old_value := product_record.cached_brand_names;
            new_value := new_brand_names;
            RETURN NEXT;
        END IF;
    END LOOP;
    
    -- If no rows were processed, return a single informational row
    IF NOT FOUND THEN
        product_id := NULL;
        product_name := 'No products with NULL cached_brand_names were found';
        was_null := NULL;
        old_value := NULL;
        new_value := NULL;
        RETURN NEXT;
    END IF;
    
    RETURN;
END;
$$;


ALTER FUNCTION "public"."update_products_fts_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_products_fts_manual"("product_row" "public"."products") RETURNS "tsvector"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN
    setweight(to_tsvector('english', coalesce(product_row.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(product_row.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.name FROM product_categories pc WHERE pc.id = product_row.category_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(product_row.cached_brand_names, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(product_row.slug, '')), 'D') ||
    setweight(to_tsvector('english', coalesce(product_row.url, '')), 'D');
END;
$$;


ALTER FUNCTION "public"."update_products_fts_manual"("product_row" "public"."products") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_subscription_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE lists
        SET subscription_count = subscription_count + 1
        WHERE id = NEW.list_id;  -- Assuming list_id is the foreign key in subscription_lists
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE lists
        SET subscription_count = subscription_count - 1
        WHERE id = OLD.list_id;  -- Assuming list_id is the foreign key in subscription_lists
    END IF;
    RETURN NULL;  -- No need to return anything
END;
$$;


ALTER FUNCTION "public"."update_subscription_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_users_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.username, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.slug, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.instagram, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.twitter, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.website, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.email, '')), 'D');
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_users_fts"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."keys" (
    "key" "text" NOT NULL,
    "value" "text"
);


ALTER TABLE "private"."keys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."addresses" (
    "id" "uuid" NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255),
    "address1" character varying(255),
    "address2" character varying(255),
    "location_id" integer,
    "user_id" "uuid"
);


ALTER TABLE "public"."addresses" OWNER TO "postgres";


COMMENT ON TABLE "public"."addresses" IS '@graphql({"name": "Address", "totalCount": {"enabled": true}})';



CREATE TABLE IF NOT EXISTS "public"."analytics_posts" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "post_id" "uuid",
    "user_id" "uuid",
    "share_date" timestamp without time zone,
    "like_date" timestamp without time zone,
    "start_watching" timestamp without time zone,
    "end_watching" timestamp without time zone,
    "watch_duration" integer,
    "watch_in_full" boolean DEFAULT false,
    "view_section" character varying(255)
);


ALTER TABLE "public"."analytics_posts" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."analytics_posts_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."analytics_posts_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."analytics_posts_id_seq" OWNED BY "public"."analytics_posts"."id";



CREATE TABLE IF NOT EXISTS "public"."breeders" (
    "id" integer NOT NULL,
    "name" character varying(255),
    "slug" character varying(255),
    "date_created" timestamp without time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp without time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."breeders" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."breeders_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."breeders_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."breeders_id_seq" OWNED BY "public"."breeders"."id";



CREATE TABLE IF NOT EXISTS "public"."cannabis_strain_relations" (
    "id" integer NOT NULL,
    "child_id" integer,
    "parent_id" integer,
    "date_created" timestamp without time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp without time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cannabis_strain_relations" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."cannabis_strain_relations_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."cannabis_strain_relations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."cannabis_strain_relations_id_seq" OWNED BY "public"."cannabis_strain_relations"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."cannabis_strains_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."cannabis_strains_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."cannabis_strains_id_seq" OWNED BY "public"."cannabis_strains"."id";



CREATE TABLE IF NOT EXISTS "public"."cannabis_strains_product_features" (
    "id" integer NOT NULL,
    "cannabis_strain_id" integer,
    "product_feature_id" integer
);


ALTER TABLE "public"."cannabis_strains_product_features" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."cannabis_strains_product_features_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."cannabis_strains_product_features_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."cannabis_strains_product_features_id_seq" OWNED BY "public"."cannabis_strains_product_features"."id";



CREATE TABLE IF NOT EXISTS "public"."cannabis_types" (
    "id" integer NOT NULL,
    "name" character varying(255),
    "date_created" timestamp without time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp without time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cannabis_types" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."cannabis_types_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."cannabis_types_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."cannabis_types_id_seq" OWNED BY "public"."cannabis_types"."id";



CREATE TABLE IF NOT EXISTS "public"."cloud_files" (
    "id" "uuid" NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "public_id" character varying(255),
    "signature" character varying(255),
    "format" character varying(255),
    "resource_type" character varying(255),
    "width" integer,
    "height" integer,
    "url" character varying(255),
    "secure_url" character varying(255),
    "asset_id" character varying(255),
    "user_id" "uuid"
);


ALTER TABLE "public"."cloud_files" OWNER TO "postgres";


COMMENT ON TABLE "public"."cloud_files" IS '@graphql({"name": "CloudFile", "totalCount": {"enabled": true}})';



CREATE TABLE IF NOT EXISTS "public"."deal_claims" (
    "id" "uuid" NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "deal_id" "uuid",
    "redeemed" boolean DEFAULT false
);


ALTER TABLE "public"."deal_claims" OWNER TO "postgres";


COMMENT ON TABLE "public"."deal_claims" IS '@graphql({"name": "DealClaim", "totalCount": {"enabled": true}})';



CREATE TABLE IF NOT EXISTS "public"."deals_dispensary_locations" (
    "id" integer NOT NULL,
    "deals_id" "uuid",
    "dispensary_locations_id" "uuid"
);


ALTER TABLE "public"."deals_dispensary_locations" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."deals_dispensary_locations_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."deals_dispensary_locations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."deals_dispensary_locations_id_seq" OWNED BY "public"."deals_dispensary_locations"."id";



CREATE TABLE IF NOT EXISTS "public"."deletion_log" (
    "id" integer NOT NULL,
    "table_name" "text",
    "record_id" "uuid",
    "deleted_at" timestamp with time zone,
    "deleted_data" "jsonb"
);


ALTER TABLE "public"."deletion_log" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."deletion_log_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."deletion_log_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."deletion_log_id_seq" OWNED BY "public"."deletion_log"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_activity" (
    "id" integer NOT NULL,
    "action" character varying(45) NOT NULL,
    "user" "uuid",
    "timestamp" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "ip" character varying(50),
    "user_agent" "text",
    "collection" character varying(64) NOT NULL,
    "item" character varying(255) NOT NULL,
    "comment" "text",
    "origin" character varying(255)
);


ALTER TABLE "public"."directus_activity" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_activity_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_activity_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_activity_id_seq" OWNED BY "public"."directus_activity"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_collections" (
    "collection" character varying(64) NOT NULL,
    "icon" character varying(30),
    "note" "text",
    "display_template" character varying(255),
    "hidden" boolean DEFAULT false NOT NULL,
    "singleton" boolean DEFAULT false NOT NULL,
    "translations" "json",
    "archive_field" character varying(64),
    "archive_app_filter" boolean DEFAULT true NOT NULL,
    "archive_value" character varying(255),
    "unarchive_value" character varying(255),
    "sort_field" character varying(64),
    "accountability" character varying(255) DEFAULT 'all'::character varying,
    "color" character varying(255),
    "item_duplication_fields" "json",
    "sort" integer,
    "group" character varying(64),
    "collapse" character varying(255) DEFAULT 'open'::character varying NOT NULL,
    "preview_url" character varying(255),
    "versioning" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."directus_collections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_dashboards" (
    "id" "uuid" NOT NULL,
    "name" character varying(255) NOT NULL,
    "icon" character varying(30) DEFAULT 'dashboard'::character varying NOT NULL,
    "note" "text",
    "date_created" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "user_created" "uuid",
    "color" character varying(255)
);


ALTER TABLE "public"."directus_dashboards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_extensions" (
    "enabled" boolean DEFAULT true NOT NULL,
    "id" "uuid" NOT NULL,
    "folder" character varying(255) NOT NULL,
    "source" character varying(255) NOT NULL,
    "bundle" "uuid"
);


ALTER TABLE "public"."directus_extensions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_fields" (
    "id" integer NOT NULL,
    "collection" character varying(64) NOT NULL,
    "field" character varying(64) NOT NULL,
    "special" character varying(64),
    "interface" character varying(64),
    "options" "json",
    "display" character varying(64),
    "display_options" "json",
    "readonly" boolean DEFAULT false NOT NULL,
    "hidden" boolean DEFAULT false NOT NULL,
    "sort" integer,
    "width" character varying(30) DEFAULT 'full'::character varying,
    "translations" "json",
    "note" "text",
    "conditions" "json",
    "required" boolean DEFAULT false,
    "group" character varying(64),
    "validation" "json",
    "validation_message" "text"
);


ALTER TABLE "public"."directus_fields" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_fields_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_fields_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_fields_id_seq" OWNED BY "public"."directus_fields"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_files" (
    "id" "uuid" NOT NULL,
    "storage" character varying(255) NOT NULL,
    "filename_disk" character varying(255),
    "filename_download" character varying(255) NOT NULL,
    "title" character varying(255),
    "type" character varying(255),
    "folder" "uuid",
    "uploaded_by" "uuid",
    "uploaded_on" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "modified_by" "uuid",
    "modified_on" timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "charset" character varying(50),
    "filesize" bigint,
    "width" integer,
    "height" integer,
    "duration" integer,
    "embed" character varying(200),
    "description" "text",
    "location" "text",
    "tags" "text",
    "metadata" "json",
    "focal_point_x" integer,
    "focal_point_y" integer,
    "tus_id" character varying(64),
    "tus_data" "json"
);


ALTER TABLE "public"."directus_files" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_flows" (
    "id" "uuid" NOT NULL,
    "name" character varying(255) NOT NULL,
    "icon" character varying(30),
    "color" character varying(255),
    "description" "text",
    "status" character varying(255) DEFAULT 'active'::character varying NOT NULL,
    "trigger" character varying(255),
    "accountability" character varying(255) DEFAULT 'all'::character varying,
    "options" "json",
    "operation" "uuid",
    "date_created" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "user_created" "uuid"
);


ALTER TABLE "public"."directus_flows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_folders" (
    "id" "uuid" NOT NULL,
    "name" character varying(255) NOT NULL,
    "parent" "uuid"
);


ALTER TABLE "public"."directus_folders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_migrations" (
    "version" character varying(255) NOT NULL,
    "name" character varying(255) NOT NULL,
    "timestamp" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."directus_migrations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_notifications" (
    "id" integer NOT NULL,
    "timestamp" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "status" character varying(255) DEFAULT 'inbox'::character varying,
    "recipient" "uuid" NOT NULL,
    "sender" "uuid",
    "subject" character varying(255) NOT NULL,
    "message" "text",
    "collection" character varying(64),
    "item" character varying(255)
);


ALTER TABLE "public"."directus_notifications" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_notifications_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_notifications_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_notifications_id_seq" OWNED BY "public"."directus_notifications"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_operations" (
    "id" "uuid" NOT NULL,
    "name" character varying(255),
    "key" character varying(255) NOT NULL,
    "type" character varying(255) NOT NULL,
    "position_x" integer NOT NULL,
    "position_y" integer NOT NULL,
    "options" "json",
    "resolve" "uuid",
    "reject" "uuid",
    "flow" "uuid" NOT NULL,
    "date_created" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "user_created" "uuid"
);


ALTER TABLE "public"."directus_operations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_panels" (
    "id" "uuid" NOT NULL,
    "dashboard" "uuid" NOT NULL,
    "name" character varying(255),
    "icon" character varying(30) DEFAULT NULL::character varying,
    "color" character varying(10),
    "show_header" boolean DEFAULT false NOT NULL,
    "note" "text",
    "type" character varying(255) NOT NULL,
    "position_x" integer NOT NULL,
    "position_y" integer NOT NULL,
    "width" integer NOT NULL,
    "height" integer NOT NULL,
    "options" "json",
    "date_created" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "user_created" "uuid"
);


ALTER TABLE "public"."directus_panels" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_permissions" (
    "id" integer NOT NULL,
    "role" "uuid",
    "collection" character varying(64) NOT NULL,
    "action" character varying(10) NOT NULL,
    "permissions" "json",
    "validation" "json",
    "presets" "json",
    "fields" "text"
);


ALTER TABLE "public"."directus_permissions" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_permissions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_permissions_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_permissions_id_seq" OWNED BY "public"."directus_permissions"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_presets" (
    "id" integer NOT NULL,
    "bookmark" character varying(255),
    "user" "uuid",
    "role" "uuid",
    "collection" character varying(64),
    "search" character varying(100),
    "layout" character varying(100) DEFAULT 'tabular'::character varying,
    "layout_query" "json",
    "layout_options" "json",
    "refresh_interval" integer,
    "filter" "json",
    "icon" character varying(30) DEFAULT 'bookmark'::character varying,
    "color" character varying(255)
);


ALTER TABLE "public"."directus_presets" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_presets_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_presets_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_presets_id_seq" OWNED BY "public"."directus_presets"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_relations" (
    "id" integer NOT NULL,
    "many_collection" character varying(64) NOT NULL,
    "many_field" character varying(64) NOT NULL,
    "one_collection" character varying(64),
    "one_field" character varying(64),
    "one_collection_field" character varying(64),
    "one_allowed_collections" "text",
    "junction_field" character varying(64),
    "sort_field" character varying(64),
    "one_deselect_action" character varying(255) DEFAULT 'nullify'::character varying NOT NULL
);


ALTER TABLE "public"."directus_relations" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_relations_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_relations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_relations_id_seq" OWNED BY "public"."directus_relations"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_revisions" (
    "id" integer NOT NULL,
    "activity" integer NOT NULL,
    "collection" character varying(64) NOT NULL,
    "item" character varying(255) NOT NULL,
    "data" "json",
    "delta" "json",
    "parent" integer,
    "version" "uuid"
);


ALTER TABLE "public"."directus_revisions" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_revisions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_revisions_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_revisions_id_seq" OWNED BY "public"."directus_revisions"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_roles" (
    "id" "uuid" NOT NULL,
    "name" character varying(100) NOT NULL,
    "icon" character varying(30) DEFAULT 'supervised_user_circle'::character varying NOT NULL,
    "description" "text",
    "ip_access" "text",
    "enforce_tfa" boolean DEFAULT false NOT NULL,
    "admin_access" boolean DEFAULT false NOT NULL,
    "app_access" boolean DEFAULT true NOT NULL,
    "module_list" "json",
    "collection_list" "json"
);


ALTER TABLE "public"."directus_roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_sessions" (
    "token" character varying(64) NOT NULL,
    "user" "uuid",
    "expires" timestamp with time zone NOT NULL,
    "ip" character varying(255),
    "user_agent" "text",
    "share" "uuid",
    "origin" character varying(255),
    "next_token" character varying(64)
);


ALTER TABLE "public"."directus_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_settings" (
    "id" integer NOT NULL,
    "project_name" character varying(100) DEFAULT 'Directus'::character varying NOT NULL,
    "project_url" character varying(255),
    "project_color" character varying(255) DEFAULT '#6644FF'::character varying NOT NULL,
    "project_logo" "uuid",
    "public_foreground" "uuid",
    "public_background" "uuid",
    "public_note" "text",
    "auth_login_attempts" integer DEFAULT 25,
    "auth_password_policy" character varying(100),
    "storage_asset_transform" character varying(7) DEFAULT 'all'::character varying,
    "storage_asset_presets" "json",
    "custom_css" "text",
    "storage_default_folder" "uuid",
    "basemaps" "json",
    "mapbox_key" character varying(255),
    "module_bar" "json",
    "project_descriptor" character varying(100),
    "default_language" character varying(255) DEFAULT 'en-US'::character varying NOT NULL,
    "custom_aspect_ratios" "json",
    "public_favicon" "uuid",
    "default_appearance" character varying(255) DEFAULT 'auto'::character varying NOT NULL,
    "default_theme_light" character varying(255),
    "theme_light_overrides" "json",
    "default_theme_dark" character varying(255),
    "theme_dark_overrides" "json",
    "report_error_url" character varying(255),
    "report_bug_url" character varying(255),
    "report_feature_url" character varying(255),
    "public_registration" boolean DEFAULT false NOT NULL,
    "public_registration_verify_email" boolean DEFAULT true NOT NULL,
    "public_registration_role" "uuid",
    "public_registration_email_filter" "json"
);


ALTER TABLE "public"."directus_settings" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_settings_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_settings_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_settings_id_seq" OWNED BY "public"."directus_settings"."id";



CREATE TABLE IF NOT EXISTS "public"."directus_shares" (
    "id" "uuid" NOT NULL,
    "name" character varying(255),
    "collection" character varying(64) NOT NULL,
    "item" character varying(255) NOT NULL,
    "role" "uuid",
    "password" character varying(255),
    "user_created" "uuid",
    "date_created" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "date_start" timestamp with time zone,
    "date_end" timestamp with time zone,
    "times_used" integer DEFAULT 0,
    "max_uses" integer
);


ALTER TABLE "public"."directus_shares" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_translations" (
    "id" "uuid" NOT NULL,
    "language" character varying(255) NOT NULL,
    "key" character varying(255) NOT NULL,
    "value" "text" NOT NULL
);


ALTER TABLE "public"."directus_translations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_users" (
    "id" "uuid" NOT NULL,
    "first_name" character varying(50),
    "last_name" character varying(50),
    "email" character varying(128),
    "password" character varying(255),
    "location" character varying(255),
    "title" character varying(50),
    "description" "text",
    "tags" "json",
    "avatar" "uuid",
    "language" character varying(255) DEFAULT NULL::character varying,
    "tfa_secret" character varying(255),
    "status" character varying(16) DEFAULT 'active'::character varying NOT NULL,
    "role" "uuid",
    "token" character varying(255),
    "last_access" timestamp with time zone,
    "last_page" character varying(255),
    "provider" character varying(128) DEFAULT 'default'::character varying NOT NULL,
    "external_identifier" character varying(255),
    "auth_data" "json",
    "email_notifications" boolean DEFAULT true,
    "appearance" character varying(255),
    "theme_dark" character varying(255),
    "theme_light" character varying(255),
    "theme_light_overrides" "json",
    "theme_dark_overrides" "json"
);


ALTER TABLE "public"."directus_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_versions" (
    "id" "uuid" NOT NULL,
    "key" character varying(64) NOT NULL,
    "name" character varying(255),
    "collection" character varying(64) NOT NULL,
    "item" character varying(255) NOT NULL,
    "hash" character varying(255),
    "date_created" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "date_updated" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "user_created" "uuid",
    "user_updated" "uuid"
);


ALTER TABLE "public"."directus_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."directus_webhooks" (
    "id" integer NOT NULL,
    "name" character varying(255) NOT NULL,
    "method" character varying(10) DEFAULT 'POST'::character varying NOT NULL,
    "url" "text" NOT NULL,
    "status" character varying(10) DEFAULT 'active'::character varying NOT NULL,
    "data" boolean DEFAULT true NOT NULL,
    "actions" character varying(100) NOT NULL,
    "collections" "text" NOT NULL,
    "headers" "json",
    "was_active_before_deprecation" boolean DEFAULT false NOT NULL,
    "migrated_flow" "uuid"
);


ALTER TABLE "public"."directus_webhooks" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."directus_webhooks_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."directus_webhooks_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."directus_webhooks_id_seq" OWNED BY "public"."directus_webhooks"."id";



CREATE TABLE IF NOT EXISTS "public"."dispensary_employees" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_modified" timestamp with time zone DEFAULT "now"(),
    "dispensary_id" "uuid",
    "user_id" "uuid",
    "is_admin" boolean,
    "is_approved" boolean,
    "has_been_reviewed" boolean
);


ALTER TABLE "public"."dispensary_employees" OWNER TO "postgres";


COMMENT ON COLUMN "public"."dispensary_employees"."is_approved" IS 'whether the brand of the dispensary has approved this employee';



COMMENT ON COLUMN "public"."dispensary_employees"."has_been_reviewed" IS 'whether the brand has reviewed the employee''s request';



ALTER TABLE "public"."dispensary_employees" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."dispensary_employees_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."dispensary_locations_cloud_files" (
    "id" integer NOT NULL,
    "dispensary_locations_id" "uuid",
    "cloud_files_id" "uuid",
    "sort" integer DEFAULT 0
);


ALTER TABLE "public"."dispensary_locations_cloud_files" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."dispensary_locations_cloud_files_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."dispensary_locations_cloud_files_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."dispensary_locations_cloud_files_id_seq" OWNED BY "public"."dispensary_locations_cloud_files"."id";



CREATE TABLE IF NOT EXISTS "public"."dispensary_stashlists" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "dispensary_id" "uuid",
    "list_id" "uuid",
    "user_id" "uuid"
);


ALTER TABLE "public"."dispensary_stashlists" OWNER TO "postgres";


COMMENT ON TABLE "public"."dispensary_stashlists" IS 'stashlists created for particular dispensaries';



CREATE TABLE IF NOT EXISTS "public"."explore" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255),
    "description" "text",
    "thumbnail_id" "uuid" DEFAULT '0f2f36ad-7a80-4de2-9af4-7dd9ab767093'::"uuid",
    "start_date" timestamp without time zone DEFAULT '2020-01-01 15:38:19.340007'::timestamp without time zone,
    "end_date" timestamp without time zone DEFAULT '2060-12-15 15:38:19.340007'::timestamp without time zone,
    "default" boolean DEFAULT false,
    "slug" character varying(255)
);


ALTER TABLE "public"."explore" OWNER TO "postgres";


COMMENT ON TABLE "public"."explore" IS '@graphql({"name": "Explore", "totalCount": {"enabled": true}})';



CREATE TABLE IF NOT EXISTS "public"."explore_dispensary_locations" (
    "id" integer NOT NULL,
    "explore_id" integer,
    "dispensary_location_id" "uuid"
);


ALTER TABLE "public"."explore_dispensary_locations" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."explore_dispensary_locations_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_dispensary_locations_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_dispensary_locations_id_seq" OWNED BY "public"."explore_dispensary_locations"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."explore_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_id_seq" OWNED BY "public"."explore"."id";



CREATE TABLE IF NOT EXISTS "public"."explore_lists" (
    "id" integer NOT NULL,
    "explore_id" integer,
    "list_id" "uuid"
);


ALTER TABLE "public"."explore_lists" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."explore_lists_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_lists_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_lists_id_seq" OWNED BY "public"."explore_lists"."id";



CREATE TABLE IF NOT EXISTS "public"."explore_page" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone
);


ALTER TABLE "public"."explore_page" OWNER TO "postgres";


COMMENT ON TABLE "public"."explore_page" IS '@graphql({"name": "ExplorePage", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."explore_page_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_page_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_page_id_seq" OWNED BY "public"."explore_page"."id";



CREATE TABLE IF NOT EXISTS "public"."explore_page_sections" (
    "id" integer NOT NULL,
    "explore_page_id" integer,
    "item" character varying(255),
    "sort" integer,
    "collection" character varying(255)
);


ALTER TABLE "public"."explore_page_sections" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."explore_page_sections_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_page_sections_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_page_sections_id_seq" OWNED BY "public"."explore_page_sections"."id";



CREATE TABLE IF NOT EXISTS "public"."explore_posts" (
    "id" integer NOT NULL,
    "explore_id" integer,
    "post_id" "uuid"
);


ALTER TABLE "public"."explore_posts" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."explore_posts_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_posts_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_posts_id_seq" OWNED BY "public"."explore_posts"."id";



CREATE TABLE IF NOT EXISTS "public"."explore_products" (
    "id" integer NOT NULL,
    "explore_id" integer,
    "product_id" "uuid"
);


ALTER TABLE "public"."explore_products" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."explore_products_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_products_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_products_id_seq" OWNED BY "public"."explore_products"."id";



CREATE TABLE IF NOT EXISTS "public"."explore_trending" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone,
    "name" character varying(255)
);


ALTER TABLE "public"."explore_trending" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."explore_trending_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_trending_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_trending_id_seq" OWNED BY "public"."explore_trending"."id";



CREATE TABLE IF NOT EXISTS "public"."explore_users" (
    "id" integer NOT NULL,
    "explore_id" integer,
    "user_id" "uuid"
);


ALTER TABLE "public"."explore_users" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."explore_users_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."explore_users_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."explore_users_id_seq" OWNED BY "public"."explore_users"."id";



CREATE TABLE IF NOT EXISTS "public"."favorite_dispensaries" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "dispensary_location_id" "uuid",
    "user_id" "uuid"
);


ALTER TABLE "public"."favorite_dispensaries" OWNER TO "postgres";


ALTER TABLE "public"."favorite_dispensaries" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."favorite_dispensaries_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."featured_items" (
    "id" bigint NOT NULL,
    "item_id" "uuid" NOT NULL,
    "item_type" "text" NOT NULL,
    "sort_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    CONSTRAINT "featured_items_item_type_check" CHECK (("item_type" = ANY (ARRAY['products'::"text", 'users'::"text", 'brands'::"text", 'posts'::"text", 'lists'::"text", 'giveaways'::"text", 'dispensary_locations'::"text"])))
);


ALTER TABLE "public"."featured_items" OWNER TO "postgres";


COMMENT ON COLUMN "public"."featured_items"."item_id" IS 'The UUID of the featured item (from products, users, etc.)';



COMMENT ON COLUMN "public"."featured_items"."item_type" IS 'The table the item belongs to (e.g., ''products'', ''users'').';



COMMENT ON COLUMN "public"."featured_items"."sort_order" IS 'Manual sort order set by an admin. Lower numbers appear first.';



ALTER TABLE "public"."featured_items" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."featured_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."files" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text",
    "date_created" timestamp without time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp without time zone DEFAULT "now"() NOT NULL,
    "signed_url" "text"
);


ALTER TABLE "public"."files" OWNER TO "postgres";


COMMENT ON TABLE "public"."files" IS '@graphql({"name": "File", "totalCount": {"enabled": true}})';



COMMENT ON COLUMN "public"."files"."signed_url" IS '@name url';



CREATE TABLE IF NOT EXISTS "public"."g_ids" (
    "array_agg" "uuid"[]
);


ALTER TABLE "public"."g_ids" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."giveaway_entries" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "giveaway_id" "uuid",
    "won" boolean DEFAULT false,
    "sent" boolean DEFAULT false,
    "shipping_notes" "text"
);


ALTER TABLE "public"."giveaway_entries" OWNER TO "postgres";


COMMENT ON TABLE "public"."giveaway_entries" IS '@graphql({"name": "GiveawayEntry", "totalCount": {"enabled": true}})';



CREATE TABLE IF NOT EXISTS "public"."giveaway_entries_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "giveaway_entry_id" "uuid",
    "message" "text"
);


ALTER TABLE "public"."giveaway_entries_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."giveaways_regions" (
    "id" integer NOT NULL,
    "giveaway_id" "uuid",
    "region_id" integer
);


ALTER TABLE "public"."giveaways_regions" OWNER TO "postgres";


COMMENT ON TABLE "public"."giveaways_regions" IS '@graphql({"name": "GiveawayRegion", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."giveaways_regions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."giveaways_regions_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."giveaways_regions_id_seq" OWNED BY "public"."giveaways_regions"."id";



CREATE TABLE IF NOT EXISTS "public"."growers" (
    "id" integer NOT NULL,
    "name" character varying(255),
    "slug" character varying(255),
    "date_created" timestamp without time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp without time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."growers" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."growers_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."growers_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."growers_id_seq" OWNED BY "public"."growers"."id";



CREATE TABLE IF NOT EXISTS "public"."likes" (
    "posts_id" "uuid",
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" integer NOT NULL,
    "users_id" "uuid"
);


ALTER TABLE "public"."likes" OWNER TO "postgres";


COMMENT ON TABLE "public"."likes" IS '@graphql({"name": "Like", "totalCount": {"enabled": true}})';



ALTER TABLE "public"."likes" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."likes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."lists_products" (
    "lists_id" "uuid" NOT NULL,
    "products_id" "uuid" NOT NULL,
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."lists_products" OWNER TO "postgres";


COMMENT ON TABLE "public"."lists_products" IS '@graphql({"name": "ListProduct", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."lists_products_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."lists_products_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."lists_products_id_seq" OWNED BY "public"."lists_products"."id";



CREATE TABLE IF NOT EXISTS "public"."notification_messages" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "template" character varying(255),
    "last_used" timestamp with time zone,
    "type_id" integer
);


ALTER TABLE "public"."notification_messages" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."notification_messages_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."notification_messages_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."notification_messages_id_seq" OWNED BY "public"."notification_messages"."id";



CREATE TABLE IF NOT EXISTS "public"."notification_types" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "name" character varying(255),
    "message_template_count" integer DEFAULT 0,
    "default_push_setting" boolean DEFAULT true,
    "run_time" integer DEFAULT 5,
    "message" "text",
    "can_push" boolean DEFAULT true,
    "title" "text",
    "description" "text"
);


ALTER TABLE "public"."notification_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_types" IS '@graphql({"name": "NotificationType", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."notification_types_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."notification_types_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."notification_types_id_seq" OWNED BY "public"."notification_types"."id";



CREATE TABLE IF NOT EXISTS "public"."post_flags" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "post_id" "uuid",
    "user_id" "uuid",
    "reason" "text"
);


ALTER TABLE "public"."post_flags" OWNER TO "postgres";


ALTER TABLE "public"."post_flags" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."post_flags_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."post_log" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "post_id" "uuid",
    "flagged" boolean,
    "user_id" "uuid"
);


ALTER TABLE "public"."post_log" OWNER TO "postgres";


ALTER TABLE "public"."post_log" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."post_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."post_tags" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "tag" character varying(255),
    "count" integer DEFAULT 1
);


ALTER TABLE "public"."post_tags" OWNER TO "postgres";


COMMENT ON TABLE "public"."post_tags" IS '@graphql({"name": "PostTag", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."post_tags_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."post_tags_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."post_tags_id_seq" OWNED BY "public"."post_tags"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."postal_codes_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."postal_codes_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."postal_codes_id_seq" OWNED BY "public"."postal_codes"."id";



CREATE TABLE IF NOT EXISTS "public"."posts_hashtags" (
    "id" integer NOT NULL,
    "posts_id" "uuid",
    "post_tags_id" integer,
    "date_created" timestamp with time zone DEFAULT ("now"() AT TIME ZONE 'utc'::"text"),
    "date_updated" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."posts_hashtags" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."posts_hashtags_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."posts_hashtags_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."posts_hashtags_id_seq" OWNED BY "public"."posts_hashtags"."id";



CREATE TABLE IF NOT EXISTS "public"."posts_lists" (
    "id" integer NOT NULL,
    "post_id" "uuid",
    "list_id" "uuid",
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."posts_lists" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."posts_lists_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."posts_lists_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."posts_lists_id_seq" OWNED BY "public"."posts_lists"."id";



CREATE TABLE IF NOT EXISTS "public"."posts_products" (
    "id" integer NOT NULL,
    "posts_id" "uuid",
    "products_id" "uuid",
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."posts_products" OWNER TO "postgres";


COMMENT ON TABLE "public"."posts_products" IS '@graphql({"name": "PostProduct", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."posts_products_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."posts_products_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."posts_products_id_seq" OWNED BY "public"."posts_products"."id";



CREATE TABLE IF NOT EXISTS "public"."posts_users" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "post_id" "uuid",
    "user_id" "uuid",
    "date_updated" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."posts_users" OWNER TO "postgres";


ALTER TABLE "public"."posts_users" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."posts_users_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."product_feature_types" (
    "id" integer NOT NULL,
    "name" character varying(255)
);


ALTER TABLE "public"."product_feature_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."product_feature_types" IS '@graphql({"name": "ProductFeatureType", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."product_feature_types_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."product_feature_types_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."product_feature_types_id_seq" OWNED BY "public"."product_feature_types"."id";



CREATE TABLE IF NOT EXISTS "public"."product_features" (
    "id" integer NOT NULL,
    "name" character varying(255),
    "type_id" integer
);


ALTER TABLE "public"."product_features" OWNER TO "postgres";


COMMENT ON TABLE "public"."product_features" IS '@graphql({"name": "ProductFeature", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."product_features_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."product_features_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."product_features_id_seq" OWNED BY "public"."product_features"."id";



CREATE TABLE IF NOT EXISTS "public"."products_brands" (
    "id" integer NOT NULL,
    "products_id" "uuid",
    "users_id" "uuid"
);


ALTER TABLE "public"."products_brands" OWNER TO "postgres";


COMMENT ON TABLE "public"."products_brands" IS '@graphql({"name": "ProductBrand", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."products_brands_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."products_brands_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."products_brands_id_seq" OWNED BY "public"."products_brands"."id";



CREATE TABLE IF NOT EXISTS "public"."products_cannabis_strains" (
    "id" integer NOT NULL,
    "products_id" "uuid",
    "cannabis_strains_id" integer,
    "date_created" timestamp with time zone NOT NULL,
    "date_updated" timestamp with time zone NOT NULL
);


ALTER TABLE "public"."products_cannabis_strains" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products_cannabis_strains_1" (
    "id" integer NOT NULL,
    "product_id" "uuid",
    "cannabis_strain_id" integer
);


ALTER TABLE "public"."products_cannabis_strains_1" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."products_cannabis_strains_1_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."products_cannabis_strains_1_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."products_cannabis_strains_1_id_seq" OWNED BY "public"."products_cannabis_strains_1"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."products_cannabis_strains_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."products_cannabis_strains_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."products_cannabis_strains_id_seq" OWNED BY "public"."products_cannabis_strains"."id";



CREATE TABLE IF NOT EXISTS "public"."products_cloud_files" (
    "id" integer NOT NULL,
    "products_id" "uuid",
    "cloud_files_id" "uuid",
    "sort" integer DEFAULT 0
);


ALTER TABLE "public"."products_cloud_files" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."products_cloud_files_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."products_cloud_files_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."products_cloud_files_id_seq" OWNED BY "public"."products_cloud_files"."id";



CREATE TABLE IF NOT EXISTS "public"."products_product_features_2" (
    "id" integer NOT NULL,
    "product_id" "uuid",
    "product_feature_id" integer
);


ALTER TABLE "public"."products_product_features_2" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."products_product_features_2_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."products_product_features_2_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."products_product_features_2_id_seq" OWNED BY "public"."products_product_features_2"."id";



CREATE TABLE IF NOT EXISTS "public"."products_products" (
    "id" integer NOT NULL,
    "products_id" "uuid",
    "products_related_id" "uuid",
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."products_products" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."products_products_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."products_products_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."products_products_id_seq" OWNED BY "public"."products_products"."id";



CREATE TABLE IF NOT EXISTS "public"."products_states" (
    "id" integer NOT NULL,
    "products_id" "uuid",
    "states_id" integer,
    "date_created" timestamp with time zone NOT NULL,
    "date_updated" timestamp with time zone NOT NULL
);


ALTER TABLE "public"."products_states" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."products_states_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."products_states_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."products_states_id_seq" OWNED BY "public"."products_states"."id";



CREATE TABLE IF NOT EXISTS "public"."push_notifications_queue" (
    "id" integer NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "type_id" integer,
    "user_ids" "text"[],
    "item_details" "jsonb",
    "sent" boolean DEFAULT false,
    "message" "text",
    "url" "text"
);


ALTER TABLE "public"."push_notifications_queue" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."push_notifications_queue_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."push_notifications_queue_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."push_notifications_queue_id_seq" OWNED BY "public"."push_notifications_queue"."id";



CREATE TABLE IF NOT EXISTS "public"."region_postal_codes" (
    "id" integer NOT NULL,
    "region_id" integer,
    "postal_code_id" integer
);


ALTER TABLE "public"."region_postal_codes" OWNER TO "postgres";


COMMENT ON TABLE "public"."region_postal_codes" IS '@graphql({"name": "RegionsPostalCodes", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."region_postal_codes_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."region_postal_codes_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."region_postal_codes_id_seq" OWNED BY "public"."region_postal_codes"."id";



CREATE SEQUENCE IF NOT EXISTS "public"."regions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."regions_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."regions_id_seq" OWNED BY "public"."regions"."id";



CREATE TABLE IF NOT EXISTS "public"."relationships" (
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" integer NOT NULL,
    "follower_id" "uuid" NOT NULL,
    "followee_id" "uuid" NOT NULL,
    "role_id" integer
);


ALTER TABLE "public"."relationships" OWNER TO "postgres";


COMMENT ON TABLE "public"."relationships" IS '@graphql({"name": "Relationship", "totalCount": {"enabled": true}})';



ALTER TABLE "public"."relationships" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."relationships_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."roles" (
    "id" integer NOT NULL,
    "role" character varying(255) NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."roles" OWNER TO "postgres";


COMMENT ON TABLE "public"."roles" IS '@graphql({"name": "Role"})';



CREATE SEQUENCE IF NOT EXISTS "public"."roles_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."roles_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."roles_id_seq" OWNED BY "public"."roles"."id";



CREATE TABLE IF NOT EXISTS "public"."sels" (
    "j" "uuid"[],
    "c" bigint
);


ALTER TABLE "public"."sels" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_now" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "product_id" "uuid",
    "rank" smallint
);


ALTER TABLE "public"."shop_now" OWNER TO "postgres";


COMMENT ON TABLE "public"."shop_now" IS 'Specific to the Shop Now section in Discover View';



CREATE TABLE IF NOT EXISTS "public"."stash" (
    "id" integer NOT NULL,
    "products_id" "uuid",
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp with time zone DEFAULT "now"() NOT NULL,
    "users_id" "uuid",
    "restash_id" "uuid",
    "restash_list_id" "uuid",
    "restash_post_id" "uuid",
    "restash_profile_id" "uuid"
);


ALTER TABLE "public"."stash" OWNER TO "postgres";


COMMENT ON TABLE "public"."stash" IS '@graphql({"name": "Stash", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."stash_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."stash_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."stash_id_seq" OWNED BY "public"."stash"."id";



CREATE TABLE IF NOT EXISTS "public"."states" (
    "id" integer NOT NULL,
    "abbr" "text",
    "name" "text",
    "date_created" timestamp without time zone DEFAULT "now"() NOT NULL,
    "date_updated" timestamp without time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."states" OWNER TO "postgres";


COMMENT ON TABLE "public"."states" IS '@graphql({"name": "State", "totalCount": {"enabled": true}})';



ALTER TABLE "public"."states" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."states_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."subscriptions_lists" (
    "id" integer NOT NULL,
    "user_id" "uuid",
    "list_id" "uuid",
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."subscriptions_lists" OWNER TO "postgres";


COMMENT ON TABLE "public"."subscriptions_lists" IS '@graphql({"name": "SubscriptionsLists", "totalCount": {"enabled": true}})';



CREATE SEQUENCE IF NOT EXISTS "public"."subscriptions_lists_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."subscriptions_lists_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."subscriptions_lists_id_seq" OWNED BY "public"."subscriptions_lists"."id";



CREATE TABLE IF NOT EXISTS "public"."typesense_import_log" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"(),
    "date_updated" timestamp with time zone DEFAULT "now"(),
    "user_count" integer DEFAULT 0,
    "post_count" integer DEFAULT 0,
    "deal_count" integer DEFAULT 0,
    "dispensary_count" integer DEFAULT 0,
    "postal_code_count" integer DEFAULT 0,
    "category_count" integer DEFAULT 0,
    "list_count" integer DEFAULT 0,
    "strain_count" integer DEFAULT 0,
    "giveaway_count" integer DEFAULT 0,
    "product_count" integer DEFAULT 0,
    "time_run" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."typesense_import_log" OWNER TO "postgres";


ALTER TABLE "public"."typesense_import_log" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."typesense_import_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."us_locations" (
    "zip_code" "text",
    "city" "text",
    "state" "text",
    "latitude" real,
    "longitude" real,
    "classification" "text",
    "population" integer,
    "id" integer NOT NULL,
    "date_created" timestamp with time zone NOT NULL,
    "date_updated" timestamp with time zone NOT NULL
);


ALTER TABLE "public"."us_locations" OWNER TO "postgres";


COMMENT ON TABLE "public"."us_locations" IS '@graphql({"name": "USLocation", "totalCount": {"enabled": true}})';



ALTER TABLE "public"."us_locations" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."us_locations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."user_blocks" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    "block_id" "uuid"
);


ALTER TABLE "public"."user_blocks" OWNER TO "postgres";


ALTER TABLE "public"."user_blocks" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."user_blocks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."user_brand_admins" (
    "id" integer NOT NULL,
    "user_id" "uuid",
    "brand_id" "uuid"
);


ALTER TABLE "public"."user_brand_admins" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."user_brand_admins_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "public"."user_brand_admins_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."user_brand_admins_id_seq" OWNED BY "public"."user_brand_admins"."id";



CREATE TABLE IF NOT EXISTS "public"."user_delete_requests" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    "email" "text"
);


ALTER TABLE "public"."user_delete_requests" OWNER TO "postgres";


ALTER TABLE "public"."user_delete_requests" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."user_delete_requests_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."user_notifications_settings" (
    "id" bigint NOT NULL,
    "date_created" timestamp with time zone DEFAULT "now"() NOT NULL,
    "setting" boolean DEFAULT true,
    "user_id" "uuid",
    "notification_type_id" integer
);


ALTER TABLE "public"."user_notifications_settings" OWNER TO "postgres";


ALTER TABLE "public"."user_notifications_settings" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."user_notifications_settings_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."analytics_posts" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."analytics_posts_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."breeders" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."breeders_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."cannabis_strain_relations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cannabis_strain_relations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."cannabis_strains" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cannabis_strains_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."cannabis_strains_product_features" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cannabis_strains_product_features_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."cannabis_types" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cannabis_types_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."deals_dispensary_locations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."deals_dispensary_locations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."deletion_log" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."deletion_log_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_activity" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_activity_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_fields" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_fields_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_notifications" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_notifications_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_permissions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_permissions_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_presets" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_presets_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_relations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_relations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_revisions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_revisions_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_settings" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_settings_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."directus_webhooks" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."directus_webhooks_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."dispensary_locations_cloud_files" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."dispensary_locations_cloud_files_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore_dispensary_locations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_dispensary_locations_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore_lists" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_lists_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore_page" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_page_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore_page_sections" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_page_sections_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore_posts" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_posts_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore_products" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_products_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore_trending" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_trending_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."explore_users" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."explore_users_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."giveaways_regions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."giveaways_regions_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."growers" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."growers_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."lists_products" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."lists_products_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."notification_messages" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."notification_messages_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."notification_types" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."notification_types_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."post_tags" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."post_tags_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."postal_codes" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."postal_codes_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."posts_hashtags" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."posts_hashtags_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."posts_lists" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."posts_lists_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."posts_products" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."posts_products_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."product_feature_types" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."product_feature_types_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."product_features" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."product_features_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."products_brands" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."products_brands_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."products_cannabis_strains" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."products_cannabis_strains_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."products_cannabis_strains_1" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."products_cannabis_strains_1_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."products_cloud_files" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."products_cloud_files_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."products_product_features_2" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."products_product_features_2_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."products_products" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."products_products_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."products_states" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."products_states_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."push_notifications_queue" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."push_notifications_queue_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."region_postal_codes" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."region_postal_codes_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."regions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."regions_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."roles" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."roles_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."stash" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."stash_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."subscriptions_lists" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."subscriptions_lists_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."user_brand_admins" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."user_brand_admins_id_seq"'::"regclass");



ALTER TABLE ONLY "private"."keys"
    ADD CONSTRAINT "keys_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "addresses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."analytics_posts"
    ADD CONSTRAINT "analytics_posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."breeders"
    ADD CONSTRAINT "breeders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cannabis_strain_relations"
    ADD CONSTRAINT "cannabis_strain_relations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cannabis_strains"
    ADD CONSTRAINT "cannabis_strains_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."cannabis_strains"
    ADD CONSTRAINT "cannabis_strains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cannabis_strains_product_features"
    ADD CONSTRAINT "cannabis_strains_product_features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cannabis_types"
    ADD CONSTRAINT "cannabis_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cloud_files"
    ADD CONSTRAINT "cloud_files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deal_claims"
    ADD CONSTRAINT "deal_claims_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deals_dispensary_locations"
    ADD CONSTRAINT "deals_dispensary_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deals"
    ADD CONSTRAINT "deals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deletion_log"
    ADD CONSTRAINT "deletion_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_activity"
    ADD CONSTRAINT "directus_activity_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_collections"
    ADD CONSTRAINT "directus_collections_pkey" PRIMARY KEY ("collection");



ALTER TABLE ONLY "public"."directus_dashboards"
    ADD CONSTRAINT "directus_dashboards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_extensions"
    ADD CONSTRAINT "directus_extensions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_fields"
    ADD CONSTRAINT "directus_fields_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_files"
    ADD CONSTRAINT "directus_files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_flows"
    ADD CONSTRAINT "directus_flows_operation_unique" UNIQUE ("operation");



ALTER TABLE ONLY "public"."directus_flows"
    ADD CONSTRAINT "directus_flows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_folders"
    ADD CONSTRAINT "directus_folders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_migrations"
    ADD CONSTRAINT "directus_migrations_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "public"."directus_notifications"
    ADD CONSTRAINT "directus_notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_operations"
    ADD CONSTRAINT "directus_operations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_operations"
    ADD CONSTRAINT "directus_operations_reject_unique" UNIQUE ("reject");



ALTER TABLE ONLY "public"."directus_operations"
    ADD CONSTRAINT "directus_operations_resolve_unique" UNIQUE ("resolve");



ALTER TABLE ONLY "public"."directus_panels"
    ADD CONSTRAINT "directus_panels_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_permissions"
    ADD CONSTRAINT "directus_permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_presets"
    ADD CONSTRAINT "directus_presets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_relations"
    ADD CONSTRAINT "directus_relations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_revisions"
    ADD CONSTRAINT "directus_revisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_roles"
    ADD CONSTRAINT "directus_roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_sessions"
    ADD CONSTRAINT "directus_sessions_pkey" PRIMARY KEY ("token");



ALTER TABLE ONLY "public"."directus_settings"
    ADD CONSTRAINT "directus_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_shares"
    ADD CONSTRAINT "directus_shares_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_translations"
    ADD CONSTRAINT "directus_translations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_users"
    ADD CONSTRAINT "directus_users_email_unique" UNIQUE ("email");



ALTER TABLE ONLY "public"."directus_users"
    ADD CONSTRAINT "directus_users_external_identifier_unique" UNIQUE ("external_identifier");



ALTER TABLE ONLY "public"."directus_users"
    ADD CONSTRAINT "directus_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_users"
    ADD CONSTRAINT "directus_users_token_unique" UNIQUE ("token");



ALTER TABLE ONLY "public"."directus_versions"
    ADD CONSTRAINT "directus_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."directus_webhooks"
    ADD CONSTRAINT "directus_webhooks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dispensary_employees"
    ADD CONSTRAINT "dispensary_employees_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dispensary_locations_cloud_files"
    ADD CONSTRAINT "dispensary_locations_cloud_files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dispensary_locations"
    ADD CONSTRAINT "dispensary_locations_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."dispensary_locations"
    ADD CONSTRAINT "dispensary_locations_name_unique" UNIQUE ("name");



ALTER TABLE ONLY "public"."dispensary_locations"
    ADD CONSTRAINT "dispensary_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dispensary_stashlists"
    ADD CONSTRAINT "dispensary_stashlists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore_dispensary_locations"
    ADD CONSTRAINT "explore_dispensary_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore_lists"
    ADD CONSTRAINT "explore_lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore_page"
    ADD CONSTRAINT "explore_page_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore_page_sections"
    ADD CONSTRAINT "explore_page_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore"
    ADD CONSTRAINT "explore_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore_posts"
    ADD CONSTRAINT "explore_posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore_products"
    ADD CONSTRAINT "explore_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore_trending"
    ADD CONSTRAINT "explore_trending_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."explore_users"
    ADD CONSTRAINT "explore_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favorite_dispensaries"
    ADD CONSTRAINT "favorite_dispensaries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."featured_items"
    ADD CONSTRAINT "featured_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."files"
    ADD CONSTRAINT "files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."giveaway_entries_messages"
    ADD CONSTRAINT "giveaway_entries_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."giveaway_entries"
    ADD CONSTRAINT "giveaway_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."giveaways"
    ADD CONSTRAINT "giveaways_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."giveaways_regions"
    ADD CONSTRAINT "giveaways_regions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."growers"
    ADD CONSTRAINT "growers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lists_products"
    ADD CONSTRAINT "lists_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_messages"
    ADD CONSTRAINT "notification_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_types"
    ADD CONSTRAINT "notification_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."post_flags"
    ADD CONSTRAINT "post_flags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."post_log"
    ADD CONSTRAINT "post_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."post_tags"
    ADD CONSTRAINT "post_tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."post_tags"
    ADD CONSTRAINT "post_tags_tag_key" UNIQUE ("tag");



ALTER TABLE ONLY "public"."postal_codes"
    ADD CONSTRAINT "postal_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."posts_hashtags"
    ADD CONSTRAINT "posts_hashtags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."posts_lists"
    ADD CONSTRAINT "posts_lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."posts_products"
    ADD CONSTRAINT "posts_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."posts_users"
    ADD CONSTRAINT "posts_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_feature_types"
    ADD CONSTRAINT "product_feature_types_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."product_feature_types"
    ADD CONSTRAINT "product_feature_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_features"
    ADD CONSTRAINT "product_features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products_brands"
    ADD CONSTRAINT "products_brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products_cannabis_strains_1"
    ADD CONSTRAINT "products_cannabis_strains_1_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products_cannabis_strains"
    ADD CONSTRAINT "products_cannabis_strains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products_cloud_files"
    ADD CONSTRAINT "products_cloud_files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products_product_features_2"
    ADD CONSTRAINT "products_product_features_2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products_products"
    ADD CONSTRAINT "products_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products_states"
    ADD CONSTRAINT "products_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_notifications_queue"
    ADD CONSTRAINT "push_notifications_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."region_postal_codes"
    ADD CONSTRAINT "region_postal_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."regions"
    ADD CONSTRAINT "regions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."relationships"
    ADD CONSTRAINT "relationships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_role_unique" UNIQUE ("role");



ALTER TABLE ONLY "public"."shop_now"
    ADD CONSTRAINT "shop_now_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stash"
    ADD CONSTRAINT "stash_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."states"
    ADD CONSTRAINT "states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions_lists"
    ADD CONSTRAINT "subscriptions_lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."typesense_import_log"
    ADD CONSTRAINT "typesense_import_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."us_locations"
    ADD CONSTRAINT "us_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_blocks"
    ADD CONSTRAINT "user_blocks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_brand_admins"
    ADD CONSTRAINT "user_brand_admins_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_delete_requests"
    ADD CONSTRAINT "user_delete_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_notifications_settings"
    ADD CONSTRAINT "user_notifications_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "cannabis_strain_relations_child_id_parent_id_idx" ON "public"."cannabis_strain_relations" USING "btree" ("child_id", "parent_id");



CREATE INDEX "dispensary_locations_address1_trgm_idx" ON "public"."dispensary_locations" USING "gin" ("address1" "extensions"."gin_trgm_ops");



CREATE INDEX "dispensary_locations_fts_idx" ON "public"."dispensary_locations" USING "gin" ("fts_vector");



CREATE INDEX "dispensary_locations_location_idx" ON "public"."dispensary_locations" USING "gist" ("location");



CREATE INDEX "dispensary_locations_name_trgm_idx" ON "public"."dispensary_locations" USING "gin" ("name" "extensions"."gin_trgm_ops");



CREATE UNIQUE INDEX "featured_items_item_id_type_unique_idx" ON "public"."featured_items" USING "btree" ("item_id", "item_type");



CREATE INDEX "featured_items_type_order_idx" ON "public"."featured_items" USING "btree" ("item_type", "sort_order");



CREATE UNIQUE INDEX "follow_ids_idx" ON "public"."relationships" USING "btree" ("followee_id", "follower_id");



CREATE UNIQUE INDEX "giveaway_entry_idx" ON "public"."giveaway_entries" USING "btree" ("user_id", "giveaway_id");



CREATE INDEX "giveaways_description_trgm_idx" ON "public"."giveaways" USING "gin" ("description" "extensions"."gin_trgm_ops");



CREATE INDEX "giveaways_fts_idx" ON "public"."giveaways" USING "gin" ("fts_vector");



CREATE INDEX "giveaways_name_trgm_idx" ON "public"."giveaways" USING "gin" ("name" "extensions"."gin_trgm_ops");



CREATE INDEX "idx_dispensary_locations_location" ON "public"."dispensary_locations" USING "gist" ("location");



CREATE UNIQUE INDEX "idx_lists_products_unique_list_product" ON "public"."lists_products" USING "btree" ("lists_id", "products_id");



CREATE INDEX "idx_products_brands_products_id" ON "public"."products_brands" USING "btree" ("products_id");



CREATE INDEX "idx_products_brands_users_id" ON "public"."products_brands" USING "btree" ("users_id");



CREATE UNIQUE INDEX "idx_stash_product_user" ON "public"."stash" USING "btree" ("products_id", "users_id");



CREATE INDEX "lists_description_trgm_idx" ON "public"."lists" USING "gin" ("description" "extensions"."gin_trgm_ops");



CREATE INDEX "lists_fts_idx" ON "public"."lists" USING "gin" ("fts_vector");



CREATE INDEX "lists_name_trgm_idx" ON "public"."lists" USING "gin" ("name" "extensions"."gin_trgm_ops");



CREATE INDEX "lists_users_id" ON "public"."lists" USING "btree" ("user_id");



CREATE INDEX "locations_zip_code" ON "public"."us_locations" USING "btree" ("zip_code");



CREATE INDEX "postal_code_idx" ON "public"."postal_codes" USING "btree" ("postal_code");



CREATE INDEX "postal_code_location_idx" ON "public"."postal_codes" USING "btree" ("latitude", "longitude");



CREATE INDEX "postal_codes_geom_idx" ON "public"."postal_codes" USING "gist" ("geom");



CREATE INDEX "posts_fts_idx" ON "public"."posts" USING "gin" ("fts_vector");



CREATE INDEX "posts_message_trgm_idx" ON "public"."posts" USING "gin" ("message" "extensions"."gin_trgm_ops");



CREATE UNIQUE INDEX "posts_products_posts_id_products_id_idx" ON "public"."posts_products" USING "btree" ("posts_id", "products_id");



CREATE INDEX "product_categories_fts" ON "public"."product_categories" USING "gin" ("fts");



CREATE INDEX "product_category_name_idx" ON "public"."product_categories" USING "btree" ("name");



CREATE UNIQUE INDEX "product_feature_plus_types_idx" ON "public"."product_features" USING "btree" ("name", "type_id");



CREATE UNIQUE INDEX "product_feature_type_name_idx" ON "public"."product_feature_types" USING "btree" ("name");



CREATE INDEX "products_cached_brand_names_idx" ON "public"."products" USING "btree" ("cached_brand_names");



CREATE UNIQUE INDEX "products_cannabis_strains_products_id_cannabis_strains_id_idx" ON "public"."products_cannabis_strains" USING "btree" ("products_id", "cannabis_strains_id");



CREATE INDEX "products_category_id_idx" ON "public"."products" USING "btree" ("category_id");



CREATE INDEX "products_fts" ON "public"."products" USING "gin" ("fts");



CREATE INDEX "products_fts_idx" ON "public"."products" USING "gin" ("fts_vector");



CREATE INDEX "products_name_idx" ON "public"."products" USING "btree" ("name");



CREATE INDEX "products_name_trgm_idx" ON "public"."products" USING "gin" ("name" "extensions"."gin_trgm_ops");



CREATE UNIQUE INDEX "products_products_products_id_products_related_id_idx" ON "public"."products_products" USING "btree" ("products_id", "products_related_id");



CREATE INDEX "products_slug" ON "public"."products" USING "btree" ("slug");



CREATE UNIQUE INDEX "products_states_products_id_states_id_idx" ON "public"."products_states" USING "btree" ("products_id", "states_id");



CREATE INDEX "relationships_followee_id" ON "public"."relationships" USING "btree" ("followee_id");



CREATE INDEX "relationships_follower_id" ON "public"."relationships" USING "btree" ("follower_id");



CREATE INDEX "release_date_products_idx" ON "public"."products" USING "btree" ("release_date");



CREATE INDEX "stash_product_id_idx" ON "public"."stash" USING "btree" ("products_id");



CREATE UNIQUE INDEX "stash_user_product_idx" ON "public"."stash" USING "btree" ("users_id", "products_id");



CREATE INDEX "stash_users_id" ON "public"."stash" USING "btree" ("users_id");



CREATE INDEX "sub_products" ON "public"."products_products" USING "btree" ("products_id");



CREATE INDEX "users_fts" ON "public"."users" USING "gin" ("fts");



CREATE INDEX "users_fts_idx" ON "public"."users" USING "gin" ("fts_vector");



CREATE INDEX "users_name" ON "public"."users" USING "btree" ("name");



CREATE INDEX "users_name_trgm_idx" ON "public"."users" USING "gin" ("name" "extensions"."gin_trgm_ops");



CREATE INDEX "users_role_id_idx" ON "public"."users" USING "btree" ("role_id");



CREATE INDEX "users_slug" ON "public"."users" USING "btree" ("slug");



CREATE INDEX "users_username_trgm_idx" ON "public"."users" USING "gin" ("username" "extensions"."gin_trgm_ops");



CREATE OR REPLACE TRIGGER "dispensary_locations_fts_update" BEFORE INSERT OR UPDATE ON "public"."dispensary_locations" FOR EACH ROW EXECUTE FUNCTION "public"."update_dispensary_locations_fts"();



CREATE OR REPLACE TRIGGER "giveaways_fts_update" BEFORE INSERT OR UPDATE ON "public"."giveaways" FOR EACH ROW EXECUTE FUNCTION "public"."update_giveaways_fts"();



CREATE OR REPLACE TRIGGER "lists_fts_update" BEFORE INSERT OR UPDATE ON "public"."lists" FOR EACH ROW EXECUTE FUNCTION "public"."update_lists_fts"();



CREATE OR REPLACE TRIGGER "log_giveaways_deletions" AFTER DELETE ON "public"."giveaways" FOR EACH ROW EXECUTE FUNCTION "public"."log_deletion"();



CREATE OR REPLACE TRIGGER "log_lists_deletions" AFTER DELETE ON "public"."lists" FOR EACH ROW EXECUTE FUNCTION "public"."log_deletion"();



CREATE OR REPLACE TRIGGER "log_posts_deletions" AFTER DELETE ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."log_deletion"();



CREATE OR REPLACE TRIGGER "log_products_deletions" AFTER DELETE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."log_deletion"();



CREATE OR REPLACE TRIGGER "log_user_deletions" AFTER DELETE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."log_deletion"();



CREATE OR REPLACE TRIGGER "on_employee_approval" AFTER UPDATE ON "public"."dispensary_employees" FOR EACH ROW EXECUTE FUNCTION "public"."notify_employee_of_approval"();



CREATE OR REPLACE TRIGGER "on_employee_request" AFTER INSERT ON "public"."dispensary_employees" FOR EACH ROW EXECUTE FUNCTION "public"."notify_brand_of_employee_request"();



CREATE OR REPLACE TRIGGER "posts_fts_update" BEFORE INSERT OR UPDATE ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."update_posts_fts"();



CREATE OR REPLACE TRIGGER "product_categories_cascade_fts_update" AFTER UPDATE ON "public"."product_categories" FOR EACH ROW EXECUTE FUNCTION "public"."cascade_product_category_fts_update"();



CREATE OR REPLACE TRIGGER "products_brands_cache_update" AFTER INSERT OR DELETE OR UPDATE ON "public"."products_brands" FOR EACH ROW EXECUTE FUNCTION "public"."cascade_products_brands_update"();



CREATE OR REPLACE TRIGGER "products_cascade_fts_update" AFTER UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."cascade_product_fts_update"();



CREATE OR REPLACE TRIGGER "products_fts_update" BEFORE INSERT OR UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."update_products_fts"();



CREATE OR REPLACE TRIGGER "set_featured_item_sort_order_before_insert" BEFORE INSERT ON "public"."featured_items" FOR EACH ROW EXECUTE FUNCTION "public"."set_initial_featured_item_sort_order"();



CREATE OR REPLACE TRIGGER "set_notification_image_url" AFTER INSERT ON "public"."notifications" FOR EACH ROW EXECUTE FUNCTION "public"."update_notification_image_url"();



CREATE OR REPLACE TRIGGER "subscription_count_trigger" AFTER INSERT OR DELETE ON "public"."subscriptions_lists" FOR EACH ROW EXECUTE FUNCTION "public"."update_subscription_count"();



CREATE OR REPLACE TRIGGER "trg__user_set_claimed" AFTER INSERT ON "public"."user_brand_admins" FOR EACH ROW EXECUTE FUNCTION "public"."_fn_user_set_claimed"();



CREATE OR REPLACE TRIGGER "trg_add_role_id_to_relationship" BEFORE INSERT ON "public"."relationships" FOR EACH ROW EXECUTE FUNCTION "public"."fn_add_role_id_to_relationship"();



CREATE OR REPLACE TRIGGER "trg_analytics_post" AFTER INSERT ON "public"."analytics_posts" FOR EACH ROW EXECUTE FUNCTION "public"."fn_analytics_post"();



CREATE OR REPLACE TRIGGER "trg_brand_count_on_products" AFTER INSERT OR DELETE ON "public"."products_brands" FOR EACH ROW EXECUTE FUNCTION "public"."fn_brand_count_on_products"();



CREATE OR REPLACE TRIGGER "trg_change_category_product_count_on_product" AFTER INSERT OR DELETE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_category_product_count_on_product"();



CREATE OR REPLACE TRIGGER "trg_change_claimed_deals_count_on_deals" AFTER INSERT OR DELETE ON "public"."deal_claims" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_deal_count_on_deals"();



CREATE OR REPLACE TRIGGER "trg_change_post_count_on_users" AFTER INSERT OR DELETE ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_post_count_on_users"();



CREATE OR REPLACE TRIGGER "trg_change_post_product_count_on_product" AFTER INSERT OR DELETE ON "public"."posts_products" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_post_product_count_on_product"();



CREATE OR REPLACE TRIGGER "trg_change_product_count_on_users" AFTER INSERT OR DELETE ON "public"."products_brands" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_product_count_on_users"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_addresses" BEFORE UPDATE ON "public"."addresses" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_analytics_posts" BEFORE UPDATE ON "public"."analytics_posts" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_breeders" BEFORE UPDATE ON "public"."breeders" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_cannabis_strain_relations" BEFORE UPDATE ON "public"."cannabis_strain_relations" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_cannabis_strains" BEFORE UPDATE ON "public"."cannabis_strains" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_cloud_files" BEFORE UPDATE ON "public"."cloud_files" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_deal_claims" BEFORE UPDATE ON "public"."deal_claims" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_deals" BEFORE UPDATE ON "public"."deals" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_explore" BEFORE UPDATE ON "public"."explore" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_giveaway_entries" BEFORE UPDATE ON "public"."giveaway_entries" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_giveaways" BEFORE UPDATE ON "public"."giveaways" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_likes" BEFORE UPDATE ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_lists" BEFORE UPDATE ON "public"."lists" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_post_log" BEFORE UPDATE ON "public"."post_log" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_post_tags" BEFORE UPDATE ON "public"."post_tags" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_postal_codes" BEFORE UPDATE ON "public"."postal_codes" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_posts" BEFORE UPDATE ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_posts_hashtags" BEFORE UPDATE ON "public"."posts_hashtags" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_posts_products" BEFORE UPDATE ON "public"."posts_products" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_product" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_product_categories" BEFORE UPDATE ON "public"."product_categories" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_regions" BEFORE UPDATE ON "public"."regions" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_relationships" BEFORE UPDATE ON "public"."relationships" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_roles" BEFORE UPDATE ON "public"."roles" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_stash" BEFORE UPDATE ON "public"."stash" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_subscriptions_lists" BEFORE UPDATE ON "public"."subscriptions_lists" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_date_updated_on_users" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_delete_product" BEFORE DELETE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."_fn_delete_product_trigger"();



CREATE OR REPLACE TRIGGER "trg_delete_remote_file_on_delete_from_cloud_files" AFTER DELETE ON "public"."cloud_files" FOR EACH ROW EXECUTE FUNCTION "public"."fn_delete_remote_file_on_delete"();



CREATE OR REPLACE TRIGGER "trg_dispensary_count_on_user" AFTER INSERT OR DELETE ON "public"."dispensary_locations" FOR EACH ROW EXECUTE FUNCTION "public"."fn_dispensary_count_on_user"();



CREATE OR REPLACE TRIGGER "trg_dispensary_on_update" AFTER INSERT OR UPDATE ON "public"."dispensary_locations" FOR EACH ROW EXECUTE FUNCTION "public"."_fn_dispensary_on_update"();



CREATE OR REPLACE TRIGGER "trg_flag_count_on_posts" AFTER INSERT OR DELETE ON "public"."post_flags" FOR EACH ROW EXECUTE FUNCTION "public"."fn_flag_count_on_posts"();



CREATE OR REPLACE TRIGGER "trg_giveaway_entry_count_on_giveaway" AFTER INSERT OR DELETE ON "public"."giveaway_entries" FOR EACH ROW EXECUTE FUNCTION "public"."fn_giveaway_entry_count_on_giveaway"();



CREATE OR REPLACE TRIGGER "trg_giveaway_entry_triggers" AFTER INSERT OR UPDATE ON "public"."giveaway_entries" FOR EACH ROW EXECUTE FUNCTION "public"."fn_giveaway_entry_triggers"();



CREATE OR REPLACE TRIGGER "trg_giveaway_triggers" AFTER INSERT ON "public"."giveaways" FOR EACH ROW EXECUTE FUNCTION "public"."fn_giveaway_triggers"();



CREATE OR REPLACE TRIGGER "trg_likes_insert_tasks" AFTER INSERT ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."_fn_likes_insert_tasks"();



CREATE OR REPLACE TRIGGER "trg_lists_products_sort" AFTER INSERT OR DELETE ON "public"."lists_products" FOR EACH ROW EXECUTE FUNCTION "public"."fn_lists_products_sort"();



CREATE OR REPLACE TRIGGER "trg_message_template_count_on_types" AFTER INSERT OR DELETE ON "public"."notification_messages" FOR EACH ROW EXECUTE FUNCTION "public"."fn_message_template_count_on_types"();



CREATE OR REPLACE TRIGGER "trg_post_tasks" AFTER INSERT OR UPDATE ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."fn_post_tasks"();



CREATE OR REPLACE TRIGGER "trg_product_post_insert_tasks" AFTER INSERT OR DELETE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."fn_product_post_insert_tasks"();



CREATE OR REPLACE TRIGGER "trg_set_update_date_on_deal_claims" AFTER INSERT OR DELETE OR UPDATE ON "public"."deal_claims" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_set_update_date_on_deals" AFTER INSERT OR DELETE OR UPDATE ON "public"."deals" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_set_update_date_on_dispensary_locations" AFTER INSERT OR DELETE OR UPDATE ON "public"."dispensary_locations" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_set_updated_timestamp"();



CREATE OR REPLACE TRIGGER "trg_slug_breeder_insert" BEFORE INSERT ON "public"."breeders" FOR EACH ROW WHEN ((("new"."name" IS NOT NULL) AND ("new"."slug" IS NULL))) EXECUTE FUNCTION "public"."set_slug_from_name"();



CREATE OR REPLACE TRIGGER "trg_slug_grower_insert" BEFORE INSERT ON "public"."growers" FOR EACH ROW WHEN ((("new"."name" IS NOT NULL) AND ("new"."slug" IS NULL))) EXECUTE FUNCTION "public"."set_slug_from_name"();



CREATE OR REPLACE TRIGGER "trg_slug_on_name_on_cannabis_strains" AFTER INSERT ON "public"."cannabis_strains" FOR EACH ROW EXECUTE FUNCTION "public"."set_slug_from_name"();



CREATE OR REPLACE TRIGGER "trg_slug_on_name_on_explore" AFTER INSERT OR UPDATE ON "public"."dispensary_locations" FOR EACH ROW EXECUTE FUNCTION "public"."set_slug_from_name"();



CREATE OR REPLACE TRIGGER "trg_slug_on_name_on_explore" AFTER INSERT ON "public"."explore" FOR EACH ROW EXECUTE FUNCTION "public"."set_slug_from_name"();



CREATE OR REPLACE TRIGGER "trg_slug_on_name_on_prodcut_category" AFTER INSERT ON "public"."product_categories" FOR EACH ROW EXECUTE FUNCTION "public"."set_slug_from_name"();



CREATE OR REPLACE TRIGGER "trg_slug_product_insert" BEFORE INSERT ON "public"."products" FOR EACH ROW WHEN ((("new"."name" IS NOT NULL) AND ("new"."slug" IS NULL))) EXECUTE FUNCTION "public"."set_slug_from_name"();



CREATE OR REPLACE TRIGGER "trg_update_dispensary_date_on_employee_add" AFTER INSERT OR DELETE ON "public"."dispensary_employees" FOR EACH ROW EXECUTE FUNCTION "public"."fn_update_dispensary_date_on_employee_add"();



CREATE OR REPLACE TRIGGER "trg_user_brand_admins_triggers" AFTER INSERT ON "public"."user_brand_admins" FOR EACH ROW EXECUTE FUNCTION "public"."fn_user_brand_admins_triggers"();



CREATE OR REPLACE TRIGGER "update_associated_data_trigger" AFTER UPDATE ON "public"."users" FOR EACH ROW WHEN (("pg_trigger_depth"() = 0)) EXECUTE FUNCTION "public"."update_associated_data"();



CREATE OR REPLACE TRIGGER "update_follower_counr_on_users" AFTER INSERT OR DELETE ON "public"."relationships" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_follower_count"();



CREATE OR REPLACE TRIGGER "update_like_count_on_posts" AFTER INSERT OR DELETE ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_posts_like_count"();



CREATE OR REPLACE TRIGGER "update_like_count_on_users" AFTER INSERT OR DELETE ON "public"."likes" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_users_like_count"();



CREATE OR REPLACE TRIGGER "update_list_count_on_products" AFTER INSERT OR DELETE ON "public"."lists_products" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_product_list_count"();



CREATE OR REPLACE TRIGGER "update_product_count_on_list" AFTER INSERT OR DELETE ON "public"."lists_products" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_lists_product_count"();



CREATE OR REPLACE TRIGGER "update_stash_count_on_products" AFTER INSERT OR DELETE ON "public"."stash" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_product_stash_count"();



CREATE OR REPLACE TRIGGER "update_stash_count_on_users" AFTER INSERT OR DELETE ON "public"."stash" FOR EACH ROW EXECUTE FUNCTION "public"."fn_change_users_stash_count"();



CREATE OR REPLACE TRIGGER "user_slug_on_name_inerst_update" BEFORE INSERT OR UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."set_slug_from_name"();



CREATE OR REPLACE TRIGGER "users_cascade_fts_update" AFTER UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."cascade_user_fts_update"();



CREATE OR REPLACE TRIGGER "users_fts_update" BEFORE INSERT OR UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."update_users_fts"();



ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "addresses_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."postal_codes"("id");



ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "addresses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."analytics_posts"
    ADD CONSTRAINT "analytics_posts_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."analytics_posts"
    ADD CONSTRAINT "analytics_posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cannabis_strain_relations"
    ADD CONSTRAINT "cannabis_strain_relations_child_id_fkey" FOREIGN KEY ("child_id") REFERENCES "public"."cannabis_strains"("id");



ALTER TABLE ONLY "public"."cannabis_strain_relations"
    ADD CONSTRAINT "cannabis_strain_relations_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."cannabis_strains"("id");



ALTER TABLE ONLY "public"."cannabis_strains"
    ADD CONSTRAINT "cannabis_strains_avatar_id_foreign" FOREIGN KEY ("avatar_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cannabis_strains"
    ADD CONSTRAINT "cannabis_strains_banner_id_foreign" FOREIGN KEY ("banner_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cannabis_strains"
    ADD CONSTRAINT "cannabis_strains_breeder_fkey" FOREIGN KEY ("breeder_id") REFERENCES "public"."breeders"("id");



ALTER TABLE ONLY "public"."cannabis_strains_product_features"
    ADD CONSTRAINT "cannabis_strains_product_features_cannabis_strain_id_foreign" FOREIGN KEY ("cannabis_strain_id") REFERENCES "public"."cannabis_strains"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cannabis_strains_product_features"
    ADD CONSTRAINT "cannabis_strains_product_features_product_feature_id_foreign" FOREIGN KEY ("product_feature_id") REFERENCES "public"."product_features"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."cannabis_strains"
    ADD CONSTRAINT "cannabis_strains_type_fkey" FOREIGN KEY ("type_id") REFERENCES "public"."cannabis_types"("id");



ALTER TABLE ONLY "public"."cloud_files"
    ADD CONSTRAINT "cloud_files_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deal_claims"
    ADD CONSTRAINT "deal_claims_deal_id_foreign" FOREIGN KEY ("deal_id") REFERENCES "public"."deals"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."deal_claims"
    ADD CONSTRAINT "deal_claims_user_id_foreign" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."deals_dispensary_locations"
    ADD CONSTRAINT "deals_dispensary_locations_deals_id_fkey" FOREIGN KEY ("deals_id") REFERENCES "public"."deals"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deals"
    ADD CONSTRAINT "deals_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_collections"
    ADD CONSTRAINT "directus_collections_group_foreign" FOREIGN KEY ("group") REFERENCES "public"."directus_collections"("collection");



ALTER TABLE ONLY "public"."directus_dashboards"
    ADD CONSTRAINT "directus_dashboards_user_created_foreign" FOREIGN KEY ("user_created") REFERENCES "public"."directus_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_files"
    ADD CONSTRAINT "directus_files_folder_foreign" FOREIGN KEY ("folder") REFERENCES "public"."directus_folders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_files"
    ADD CONSTRAINT "directus_files_modified_by_foreign" FOREIGN KEY ("modified_by") REFERENCES "public"."directus_users"("id");



ALTER TABLE ONLY "public"."directus_files"
    ADD CONSTRAINT "directus_files_uploaded_by_foreign" FOREIGN KEY ("uploaded_by") REFERENCES "public"."directus_users"("id");



ALTER TABLE ONLY "public"."directus_flows"
    ADD CONSTRAINT "directus_flows_user_created_foreign" FOREIGN KEY ("user_created") REFERENCES "public"."directus_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_folders"
    ADD CONSTRAINT "directus_folders_parent_foreign" FOREIGN KEY ("parent") REFERENCES "public"."directus_folders"("id");



ALTER TABLE ONLY "public"."directus_notifications"
    ADD CONSTRAINT "directus_notifications_recipient_foreign" FOREIGN KEY ("recipient") REFERENCES "public"."directus_users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_notifications"
    ADD CONSTRAINT "directus_notifications_sender_foreign" FOREIGN KEY ("sender") REFERENCES "public"."directus_users"("id");



ALTER TABLE ONLY "public"."directus_operations"
    ADD CONSTRAINT "directus_operations_flow_foreign" FOREIGN KEY ("flow") REFERENCES "public"."directus_flows"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_operations"
    ADD CONSTRAINT "directus_operations_reject_foreign" FOREIGN KEY ("reject") REFERENCES "public"."directus_operations"("id");



ALTER TABLE ONLY "public"."directus_operations"
    ADD CONSTRAINT "directus_operations_resolve_foreign" FOREIGN KEY ("resolve") REFERENCES "public"."directus_operations"("id");



ALTER TABLE ONLY "public"."directus_operations"
    ADD CONSTRAINT "directus_operations_user_created_foreign" FOREIGN KEY ("user_created") REFERENCES "public"."directus_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_panels"
    ADD CONSTRAINT "directus_panels_dashboard_foreign" FOREIGN KEY ("dashboard") REFERENCES "public"."directus_dashboards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_panels"
    ADD CONSTRAINT "directus_panels_user_created_foreign" FOREIGN KEY ("user_created") REFERENCES "public"."directus_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_permissions"
    ADD CONSTRAINT "directus_permissions_role_foreign" FOREIGN KEY ("role") REFERENCES "public"."directus_roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_presets"
    ADD CONSTRAINT "directus_presets_role_foreign" FOREIGN KEY ("role") REFERENCES "public"."directus_roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_presets"
    ADD CONSTRAINT "directus_presets_user_foreign" FOREIGN KEY ("user") REFERENCES "public"."directus_users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_revisions"
    ADD CONSTRAINT "directus_revisions_activity_foreign" FOREIGN KEY ("activity") REFERENCES "public"."directus_activity"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_revisions"
    ADD CONSTRAINT "directus_revisions_parent_foreign" FOREIGN KEY ("parent") REFERENCES "public"."directus_revisions"("id");



ALTER TABLE ONLY "public"."directus_revisions"
    ADD CONSTRAINT "directus_revisions_version_foreign" FOREIGN KEY ("version") REFERENCES "public"."directus_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_sessions"
    ADD CONSTRAINT "directus_sessions_share_foreign" FOREIGN KEY ("share") REFERENCES "public"."directus_shares"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_sessions"
    ADD CONSTRAINT "directus_sessions_user_foreign" FOREIGN KEY ("user") REFERENCES "public"."directus_users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_settings"
    ADD CONSTRAINT "directus_settings_project_logo_foreign" FOREIGN KEY ("project_logo") REFERENCES "public"."directus_files"("id");



ALTER TABLE ONLY "public"."directus_settings"
    ADD CONSTRAINT "directus_settings_public_background_foreign" FOREIGN KEY ("public_background") REFERENCES "public"."directus_files"("id");



ALTER TABLE ONLY "public"."directus_settings"
    ADD CONSTRAINT "directus_settings_public_favicon_foreign" FOREIGN KEY ("public_favicon") REFERENCES "public"."directus_files"("id");



ALTER TABLE ONLY "public"."directus_settings"
    ADD CONSTRAINT "directus_settings_public_foreground_foreign" FOREIGN KEY ("public_foreground") REFERENCES "public"."directus_files"("id");



ALTER TABLE ONLY "public"."directus_settings"
    ADD CONSTRAINT "directus_settings_public_registration_role_foreign" FOREIGN KEY ("public_registration_role") REFERENCES "public"."directus_roles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_settings"
    ADD CONSTRAINT "directus_settings_storage_default_folder_foreign" FOREIGN KEY ("storage_default_folder") REFERENCES "public"."directus_folders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_shares"
    ADD CONSTRAINT "directus_shares_collection_foreign" FOREIGN KEY ("collection") REFERENCES "public"."directus_collections"("collection") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_shares"
    ADD CONSTRAINT "directus_shares_role_foreign" FOREIGN KEY ("role") REFERENCES "public"."directus_roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_shares"
    ADD CONSTRAINT "directus_shares_user_created_foreign" FOREIGN KEY ("user_created") REFERENCES "public"."directus_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_users"
    ADD CONSTRAINT "directus_users_role_foreign" FOREIGN KEY ("role") REFERENCES "public"."directus_roles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_versions"
    ADD CONSTRAINT "directus_versions_collection_foreign" FOREIGN KEY ("collection") REFERENCES "public"."directus_collections"("collection") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."directus_versions"
    ADD CONSTRAINT "directus_versions_user_created_foreign" FOREIGN KEY ("user_created") REFERENCES "public"."directus_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."directus_versions"
    ADD CONSTRAINT "directus_versions_user_updated_foreign" FOREIGN KEY ("user_updated") REFERENCES "public"."directus_users"("id");



ALTER TABLE ONLY "public"."directus_webhooks"
    ADD CONSTRAINT "directus_webhooks_migrated_flow_foreign" FOREIGN KEY ("migrated_flow") REFERENCES "public"."directus_flows"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dispensary_employees"
    ADD CONSTRAINT "dispensary_employees_dispensary_id_fkey" FOREIGN KEY ("dispensary_id") REFERENCES "public"."dispensary_locations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dispensary_employees"
    ADD CONSTRAINT "dispensary_employees_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dispensary_locations"
    ADD CONSTRAINT "dispensary_locations_banner_id_fkey" FOREIGN KEY ("banner_id") REFERENCES "public"."cloud_files"("id");



ALTER TABLE ONLY "public"."dispensary_locations"
    ADD CONSTRAINT "dispensary_locations_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dispensary_locations_cloud_files"
    ADD CONSTRAINT "dispensary_locations_cloud_files_cloud_files_id_foreign" FOREIGN KEY ("cloud_files_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dispensary_locations_cloud_files"
    ADD CONSTRAINT "dispensary_locations_cloud_files_dispensary_locations_id_fkey" FOREIGN KEY ("dispensary_locations_id") REFERENCES "public"."dispensary_locations"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dispensary_locations"
    ADD CONSTRAINT "dispensary_locations_postal_code_foreign" FOREIGN KEY ("postal_code_id") REFERENCES "public"."postal_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."dispensary_locations"
    ADD CONSTRAINT "dispensary_locations_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id");



ALTER TABLE ONLY "public"."dispensary_locations"
    ADD CONSTRAINT "dispensary_locations_zip_code_foreign" FOREIGN KEY ("zip_code_id") REFERENCES "public"."us_locations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."explore_dispensary_locations"
    ADD CONSTRAINT "explore_dispensary_locations_dispensary_location_id_fkey" FOREIGN KEY ("dispensary_location_id") REFERENCES "public"."dispensary_locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_dispensary_locations"
    ADD CONSTRAINT "explore_dispensary_locations_explore_id_fkey" FOREIGN KEY ("explore_id") REFERENCES "public"."explore"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_lists"
    ADD CONSTRAINT "explore_lists_explore_id_fkey" FOREIGN KEY ("explore_id") REFERENCES "public"."explore"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_lists"
    ADD CONSTRAINT "explore_lists_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_page_sections"
    ADD CONSTRAINT "explore_page_sections_explore_page_id_fkey" FOREIGN KEY ("explore_page_id") REFERENCES "public"."explore_page"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_posts"
    ADD CONSTRAINT "explore_posts_explore_id_fkey" FOREIGN KEY ("explore_id") REFERENCES "public"."explore"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_posts"
    ADD CONSTRAINT "explore_posts_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_products"
    ADD CONSTRAINT "explore_products_explore_id_fkey" FOREIGN KEY ("explore_id") REFERENCES "public"."explore"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_products"
    ADD CONSTRAINT "explore_products_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore"
    ADD CONSTRAINT "explore_thumbnail_id_foreign" FOREIGN KEY ("thumbnail_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."explore_users"
    ADD CONSTRAINT "explore_users_explore_id_fkey" FOREIGN KEY ("explore_id") REFERENCES "public"."explore"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."explore_users"
    ADD CONSTRAINT "explore_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favorite_dispensaries"
    ADD CONSTRAINT "favorite_dispensaries_dispensary_location_id_fkey" FOREIGN KEY ("dispensary_location_id") REFERENCES "public"."dispensary_locations"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."favorite_dispensaries"
    ADD CONSTRAINT "favorite_dispensaries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."featured_items"
    ADD CONSTRAINT "featured_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "fk_product_category_parent" FOREIGN KEY ("parent_id") REFERENCES "public"."product_categories"("id");



COMMENT ON CONSTRAINT "fk_product_category_parent" ON "public"."product_categories" IS '@graphql({"foreign_name": "parent", "local_name": "product_categories"})';



ALTER TABLE ONLY "public"."giveaway_entries"
    ADD CONSTRAINT "giveaway_entries_giveaway_id_fkey" FOREIGN KEY ("giveaway_id") REFERENCES "public"."giveaways"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."giveaway_entries_messages"
    ADD CONSTRAINT "giveaway_entries_messages_giveaway_entry_id_fkey" FOREIGN KEY ("giveaway_entry_id") REFERENCES "public"."giveaway_entries"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."giveaway_entries_messages"
    ADD CONSTRAINT "giveaway_entries_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."giveaway_entries"
    ADD CONSTRAINT "giveaway_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."giveaways"
    ADD CONSTRAINT "giveaways_cover_id_fkey" FOREIGN KEY ("cover_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."giveaways"
    ADD CONSTRAINT "giveaways_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."giveaways_regions"
    ADD CONSTRAINT "giveaways_regions_giveaway_id_fkey" FOREIGN KEY ("giveaway_id") REFERENCES "public"."giveaways"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."giveaways_regions"
    ADD CONSTRAINT "giveaways_regions_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_posts_id_fkey" FOREIGN KEY ("posts_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."likes"
    ADD CONSTRAINT "likes_users_id_fkey" FOREIGN KEY ("users_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_background_id_foreign" FOREIGN KEY ("background_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



COMMENT ON CONSTRAINT "lists_background_id_foreign" ON "public"."lists" IS '@graphql({"foreign_name": "background", "local_name": "cloud_files"})';



ALTER TABLE ONLY "public"."lists_products"
    ADD CONSTRAINT "lists_products_lists_id_fkey" FOREIGN KEY ("lists_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lists_products"
    ADD CONSTRAINT "lists_products_products_id_fkey" FOREIGN KEY ("products_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_thumbnail_id_foreign" FOREIGN KEY ("thumbnail_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



COMMENT ON CONSTRAINT "lists_thumbnail_id_foreign" ON "public"."lists" IS '@graphql({"foreign_name": "thumbnail", "local_name": "cloud_files"})';



ALTER TABLE ONLY "public"."lists"
    ADD CONSTRAINT "lists_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_messages"
    ADD CONSTRAINT "notification_messages_type_id_foreign" FOREIGN KEY ("type_id") REFERENCES "public"."notification_types"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_giveaway_id_fkey" FOREIGN KEY ("giveaway_id") REFERENCES "public"."giveaways"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_type_id_foreign" FOREIGN KEY ("type_id") REFERENCES "public"."notification_types"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."post_flags"
    ADD CONSTRAINT "post_flags_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."post_flags"
    ADD CONSTRAINT "post_flags_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."post_log"
    ADD CONSTRAINT "post_log_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id");



ALTER TABLE ONLY "public"."post_log"
    ADD CONSTRAINT "post_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_file_id_fkey" FOREIGN KEY ("file_id") REFERENCES "public"."cloud_files"("id");



ALTER TABLE ONLY "public"."posts_hashtags"
    ADD CONSTRAINT "posts_hashtags_post_tags_id_fkey" FOREIGN KEY ("post_tags_id") REFERENCES "public"."post_tags"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posts_hashtags"
    ADD CONSTRAINT "posts_hashtags_posts_id_fkey" FOREIGN KEY ("posts_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posts_lists"
    ADD CONSTRAINT "posts_lists_list_id_foreign" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."posts_lists"
    ADD CONSTRAINT "posts_lists_post_id_foreign" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."postal_codes"("id");



ALTER TABLE ONLY "public"."posts_products"
    ADD CONSTRAINT "posts_products_posts_id_fkey" FOREIGN KEY ("posts_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posts_products"
    ADD CONSTRAINT "posts_products_products_id_fkey" FOREIGN KEY ("products_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posts_users"
    ADD CONSTRAINT "posts_users_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posts_users"
    ADD CONSTRAINT "posts_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_image_id_foreign" FOREIGN KEY ("image_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."product_features"
    ADD CONSTRAINT "product_features_type_id_foreign" FOREIGN KEY ("type_id") REFERENCES "public"."product_feature_types"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products_brands"
    ADD CONSTRAINT "products_brands_products_id_fkey" FOREIGN KEY ("products_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_brands"
    ADD CONSTRAINT "products_brands_users_id_fkey" FOREIGN KEY ("users_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_cannabis_strains_1"
    ADD CONSTRAINT "products_cannabis_strains_1_cannabis_strain_id_fkey" FOREIGN KEY ("cannabis_strain_id") REFERENCES "public"."cannabis_strains"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_cannabis_strains_1"
    ADD CONSTRAINT "products_cannabis_strains_1_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_cannabis_strains"
    ADD CONSTRAINT "products_cannabis_strains_cannabis_strains_id_fkey" FOREIGN KEY ("cannabis_strains_id") REFERENCES "public"."cannabis_strains"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_cannabis_strains"
    ADD CONSTRAINT "products_cannabis_strains_products_id_fkey" FOREIGN KEY ("products_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."product_categories"("id");



COMMENT ON CONSTRAINT "products_category_id_fkey" ON "public"."products" IS '@graphql({"foreign_name": "category", "local_name": "product_categories"})';



ALTER TABLE ONLY "public"."products_cloud_files"
    ADD CONSTRAINT "products_cloud_files_cloud_files_id_fkey" FOREIGN KEY ("cloud_files_id") REFERENCES "public"."cloud_files"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_cloud_files"
    ADD CONSTRAINT "products_cloud_files_products_id_fkey" FOREIGN KEY ("products_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_cover_id_foreign" FOREIGN KEY ("cover_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products_product_features_2"
    ADD CONSTRAINT "products_product_features_2_product_feature_id_fkey" FOREIGN KEY ("product_feature_id") REFERENCES "public"."product_features"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_product_features_2"
    ADD CONSTRAINT "products_product_features_2_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_products"
    ADD CONSTRAINT "products_products_products_id_fkey" FOREIGN KEY ("products_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_products"
    ADD CONSTRAINT "products_products_products_related_id_fkey" FOREIGN KEY ("products_related_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_states"
    ADD CONSTRAINT "products_states_products_id_fkey" FOREIGN KEY ("products_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products_states"
    ADD CONSTRAINT "products_states_states_id_fkey" FOREIGN KEY ("states_id") REFERENCES "public"."states"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_thumbnail_id_foreign" FOREIGN KEY ("thumbnail_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."stash"
    ADD CONSTRAINT "public_stash_restash_profile_id_fkey" FOREIGN KEY ("restash_profile_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_notifications_settings"
    ADD CONSTRAINT "public_user_notifications_settings_notification_type_id_fkey" FOREIGN KEY ("notification_type_id") REFERENCES "public"."notification_types"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_notifications_settings"
    ADD CONSTRAINT "public_user_notifications_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_notifications_queue"
    ADD CONSTRAINT "push_notifications_queue_type_id_foreign" FOREIGN KEY ("type_id") REFERENCES "public"."notification_types"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."region_postal_codes"
    ADD CONSTRAINT "region_postal_codes_postal_code_id_foreign" FOREIGN KEY ("postal_code_id") REFERENCES "public"."postal_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."region_postal_codes"
    ADD CONSTRAINT "region_postal_codes_region_id_foreign" FOREIGN KEY ("region_id") REFERENCES "public"."regions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."relationships"
    ADD CONSTRAINT "relationships_followee_id_fkey" FOREIGN KEY ("followee_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."relationships"
    ADD CONSTRAINT "relationships_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_now"
    ADD CONSTRAINT "shop_now_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."stash"
    ADD CONSTRAINT "stash_products_id_fkey" FOREIGN KEY ("products_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stash"
    ADD CONSTRAINT "stash_restash_id_fkey" FOREIGN KEY ("restash_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."stash"
    ADD CONSTRAINT "stash_restash_list_id_fkey" FOREIGN KEY ("restash_list_id") REFERENCES "public"."lists"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."stash"
    ADD CONSTRAINT "stash_restash_post_id_fkey" FOREIGN KEY ("restash_post_id") REFERENCES "public"."posts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."stash"
    ADD CONSTRAINT "stash_users_id_fkey" FOREIGN KEY ("users_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscriptions_lists"
    ADD CONSTRAINT "subscriptions_lists_list_id_fkey" FOREIGN KEY ("list_id") REFERENCES "public"."lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscriptions_lists"
    ADD CONSTRAINT "subscriptions_lists_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_blocks"
    ADD CONSTRAINT "user_blocks_block_id_fkey" FOREIGN KEY ("block_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_blocks"
    ADD CONSTRAINT "user_blocks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_brand_admins"
    ADD CONSTRAINT "user_brand_admins_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_brand_admins"
    ADD CONSTRAINT "user_brand_admins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_delete_requests"
    ADD CONSTRAINT "user_delete_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_banner_id_foreign" FOREIGN KEY ("banner_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



COMMENT ON CONSTRAINT "users_banner_id_foreign" ON "public"."users" IS '@graphql({"foreign_name": "banner", "local_name": "cloud_files"})';



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_desktop_banner_id_foreign" FOREIGN KEY ("desktop_banner_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_home_locale_id_fkey" FOREIGN KEY ("home_locale_id") REFERENCES "public"."postal_codes"("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_last_location_foreign" FOREIGN KEY ("last_location_id") REFERENCES "public"."postal_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_profile_picture_id_foreign" FOREIGN KEY ("profile_picture_id") REFERENCES "public"."cloud_files"("id") ON DELETE SET NULL;



COMMENT ON CONSTRAINT "users_profile_picture_id_foreign" ON "public"."users" IS '@graphql({"foreign_name": "profilePicture", "local_name": "cloud_files"})';



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id");



CREATE POLICY "All users can select" ON "public"."favorite_dispensaries" FOR SELECT USING (true);



CREATE POLICY "Allow authenticated read access" ON "public"."featured_items" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow super admins full access" ON "public"."featured_items" USING ((( SELECT "users"."role_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 9));



CREATE POLICY "Breeders are viewable by everyone." ON "public"."breeders" FOR SELECT USING (true);



CREATE POLICY "Cannabis Strains Product Features are viewable by everyone." ON "public"."cannabis_strains_product_features" FOR SELECT USING (true);



CREATE POLICY "Cannabis Strains Relations are viewable by everyone." ON "public"."cannabis_strain_relations" FOR SELECT USING (true);



CREATE POLICY "Cannabis Strains are viewable by everyone." ON "public"."cannabis_strains" FOR SELECT USING (true);



CREATE POLICY "Cannabis Types are viewable by everyone." ON "public"."cannabis_types" FOR SELECT USING (true);



CREATE POLICY "Enable addresses insert for authenticated users only" ON "public"."addresses" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable all access for all owners" ON "public"."posts_lists" TO "authenticated" USING ((("auth"."uid"() IN ( SELECT "posts"."user_id"
   FROM "public"."posts"
  WHERE ("posts"."id" = "posts_lists"."post_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "posts"."user_id"
           FROM "public"."posts"
          WHERE ("posts"."id" = "posts_lists"."post_id"))))))) WITH CHECK ((("auth"."uid"() IN ( SELECT "posts"."user_id"
   FROM "public"."posts"
  WHERE ("posts"."id" = "posts_lists"."post_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "posts"."user_id"
           FROM "public"."posts"
          WHERE ("posts"."id" = "posts_lists"."post_id")))))));



CREATE POLICY "Enable all for user" ON "public"."posts_users" USING ((("auth"."uid"() IN ( SELECT "posts"."user_id"
   FROM "public"."posts"
  WHERE ("posts"."id" = "posts_users"."post_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "posts"."user_id"
           FROM "public"."posts"
          WHERE ("posts"."id" = "posts_users"."post_id"))))))) WITH CHECK ((("auth"."uid"() IN ( SELECT "posts"."user_id"
   FROM "public"."posts"
  WHERE ("posts"."id" = "posts_users"."post_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "posts"."user_id"
           FROM "public"."posts"
          WHERE ("posts"."id" = "posts_users"."post_id")))))));



CREATE POLICY "Enable delete for users" ON "public"."post_tags" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Enable delete for users based on role id" ON "public"."giveaways" FOR DELETE USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" >= 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."addresses" FOR DELETE USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "addresses"."user_id")))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."dispensary_employees" FOR DELETE USING ((("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = ( SELECT "dispensary_locations"."brand_id"
           FROM "public"."dispensary_locations"
          WHERE ("dispensary_locations"."id" = "dispensary_employees"."dispensary_id"))))) OR ( SELECT "de1"."is_admin"
   FROM "public"."dispensary_employees" "de1"
  WHERE (("de1"."user_id" = "auth"."uid"()) AND ("de1"."dispensary_id" = "dispensary_employees"."dispensary_id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."dispensary_locations" FOR DELETE USING ((("auth"."uid"() = "id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "dispensary_locations"."brand_id"))) OR ( SELECT "dispensary_employees"."is_admin"
   FROM "public"."dispensary_employees"
  WHERE (("dispensary_employees"."user_id" = "auth"."uid"()) AND ("dispensary_employees"."dispensary_id" = "dispensary_locations"."id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."dispensary_locations_cloud_files" FOR DELETE USING ((("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "dispensary_locations_cloud_files"."dispensary_locations_id"))) OR ( SELECT "dispensary_employees"."is_admin"
   FROM "public"."dispensary_employees"
  WHERE (("dispensary_employees"."user_id" = "auth"."uid"()) AND ("dispensary_employees"."dispensary_id" = "dispensary_locations_cloud_files"."dispensary_locations_id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."dispensary_stashlists" FOR DELETE USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."notification_messages" FOR DELETE USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."post_flags" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."posts_hashtags" FOR DELETE USING ((("auth"."uid"() IN ( SELECT "posts"."user_id"
   FROM "public"."posts"
  WHERE ("posts"."id" = "posts_hashtags"."posts_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "posts"."user_id"
           FROM "public"."posts"
          WHERE ("posts"."id" = "posts_hashtags"."posts_id")))))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."products" FOR DELETE USING ((("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "products_brands"."users_id"
           FROM "public"."products_brands"
          WHERE ("products_brands"."products_id" = "products"."id"))))) OR ( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."products_brands" FOR DELETE USING ((("auth"."uid"() = "users_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "products_brands"."users_id")))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."products_cannabis_strains_1" FOR DELETE USING (("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "products_brands"."users_id"
           FROM "public"."products_brands"
          WHERE ("products_brands"."products_id" = "products_cannabis_strains_1"."product_id"))))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."products_cloud_files" FOR DELETE USING (("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "products_brands"."users_id"
           FROM "public"."products_brands"
          WHERE ("products_brands"."products_id" = "products_cloud_files"."products_id"))))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."products_product_features_2" FOR DELETE USING (("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "products_brands"."users_id"
           FROM "public"."products_brands"
          WHERE ("products_brands"."products_id" = "products_product_features_2"."product_id"))))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."products_products" FOR DELETE USING (("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "products_brands"."users_id"
           FROM "public"."products_brands"
          WHERE ("products_brands"."products_id" = "products_products"."products_id"))))));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."push_notifications_queue" FOR DELETE USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."user_blocks" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."user_brand_admins" FOR DELETE USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" >= 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable delete for users based on user_id" ON "public"."user_notifications_settings" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Enable delete for users based on user_id form lists" ON "public"."lists_products" FOR DELETE USING ((("auth"."uid"() IN ( SELECT "lists"."user_id"
   FROM "public"."lists"
  WHERE ("lists"."id" = "lists_products"."lists_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "lists"."user_id"
           FROM "public"."lists"
          WHERE ("lists"."id" = "lists_products"."lists_id")))))));



CREATE POLICY "Enable delete for users based on user_id on lists" ON "public"."lists" FOR DELETE USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "lists"."user_id")))));



CREATE POLICY "Enable insert for admin users only" ON "public"."giveaways" FOR INSERT TO "authenticated" WITH CHECK (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" >= 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable insert for authenticated users only" ON "public"."dispensary_employees" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = ( SELECT "dispensary_locations"."brand_id"
           FROM "public"."dispensary_locations"
          WHERE ("dispensary_locations"."id" = "dispensary_employees"."dispensary_id"))))) OR ( SELECT "de1"."is_admin"
   FROM "public"."dispensary_employees" "de1"
  WHERE (("de1"."user_id" = "auth"."uid"()) AND ("de1"."dispensary_id" = "dispensary_employees"."dispensary_id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))));



CREATE POLICY "Enable insert for authenticated users only" ON "public"."dispensary_locations" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."dispensary_locations_cloud_files" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."dispensary_stashlists" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."giveaway_entries" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."giveaways_regions" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."lists_products" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."notification_messages" FOR INSERT TO "authenticated" WITH CHECK (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable insert for authenticated users only" ON "public"."post_flags" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."post_tags" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."posts_lists" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."posts_users" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."product_categories" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."product_feature_types" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."product_features" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."products" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."products_brands" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."products_cannabis_strains_1" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."products_cloud_files" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."products_product_features_2" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."products_products" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."push_notifications_queue" FOR INSERT TO "authenticated" WITH CHECK (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable insert for authenticated users only" ON "public"."typesense_import_log" FOR INSERT TO "anon", "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."user_blocks" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."user_brand_admins" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."user_delete_requests" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."user_notifications_settings" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."users" FOR INSERT TO "anon", "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only analytics" ON "public"."analytics_posts" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only cloud_files" ON "public"."cloud_files" FOR INSERT TO "anon", "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only deal_claims" ON "public"."deal_claims" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only likes" ON "public"."likes" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only lists" ON "public"."lists" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only post_logs" ON "public"."post_log" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only posts" ON "public"."posts" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only posts_hashtags" ON "public"."posts_hashtags" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only posts_products" ON "public"."posts_products" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only relationships" ON "public"."relationships" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only subscriptions_lists" ON "public"."subscriptions_lists" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for users based on user_id" ON "public"."notifications" FOR INSERT WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Enable read access for all owner" ON "public"."analytics_posts" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Enable read access for all users" ON "public"."dispensary_employees" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."dispensary_stashlists" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."explore" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."explore_dispensary_locations" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."explore_lists" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."explore_posts" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."explore_products" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."explore_users" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."giveaways" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."giveaways_regions" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."notification_messages" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."notification_types" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."notifications" FOR SELECT USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "notifications"."user_id")))));



CREATE POLICY "Enable read access for all users" ON "public"."posts" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."posts_lists" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."posts_users" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."product_categories" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."push_notifications_queue" FOR SELECT USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable read access for all users" ON "public"."region_postal_codes" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."regions" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."shop_now" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."user_brand_admins" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."users" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users on lists" ON "public"."lists" FOR SELECT USING (true);



CREATE POLICY "Enable read access for authenticated users" ON "public"."user_notifications_settings" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Enable read access to a users entries" ON "public"."giveaway_entries" FOR SELECT USING (true);



CREATE POLICY "Enable select for users based on user_id on addresses" ON "public"."addresses" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Enable update for admins only" ON "public"."notification_messages" FOR UPDATE USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))) WITH CHECK (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable update for users based on brand admin" ON "public"."users" FOR UPDATE USING ((("auth"."uid"() = "id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "users"."id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"())))) WITH CHECK ((("auth"."uid"() = "id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "users"."id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))));



CREATE POLICY "Enable update for users based on email" ON "public"."dispensary_employees" FOR UPDATE USING ((("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = ( SELECT "dispensary_locations"."brand_id"
           FROM "public"."dispensary_locations"
          WHERE ("dispensary_locations"."id" = "dispensary_employees"."dispensary_id"))))) OR ( SELECT "de1"."is_admin"
   FROM "public"."dispensary_employees" "de1"
  WHERE (("de1"."user_id" = "auth"."uid"()) AND ("de1"."dispensary_id" = "dispensary_employees"."dispensary_id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"())))) WITH CHECK ((("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = ( SELECT "dispensary_locations"."brand_id"
           FROM "public"."dispensary_locations"
          WHERE ("dispensary_locations"."id" = "dispensary_employees"."dispensary_id"))))) OR ( SELECT "de1"."is_admin"
   FROM "public"."dispensary_employees" "de1"
  WHERE (("de1"."user_id" = "auth"."uid"()) AND ("de1"."dispensary_id" = "dispensary_employees"."dispensary_id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))));



CREATE POLICY "Enable update for users based on email" ON "public"."dispensary_locations" FOR UPDATE USING ((("auth"."uid"() = "id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "dispensary_locations"."brand_id"))) OR ( SELECT "dispensary_employees"."is_admin"
   FROM "public"."dispensary_employees"
  WHERE (("dispensary_employees"."user_id" = "auth"."uid"()) AND ("dispensary_employees"."dispensary_id" = "dispensary_locations"."id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"())))) WITH CHECK ((("auth"."uid"() = "id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "dispensary_locations"."brand_id"))) OR ( SELECT "dispensary_employees"."is_admin"
   FROM "public"."dispensary_employees"
  WHERE (("dispensary_employees"."user_id" = "auth"."uid"()) AND ("dispensary_employees"."dispensary_id" = "dispensary_locations"."id"))) OR ( SELECT (("users_1"."role_id" <= 9) OR ("users_1"."role_id" >= 3)) AS "bool"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))));



CREATE POLICY "Enable update for users based on email" ON "public"."lists" FOR UPDATE USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "lists"."user_id"))))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "lists"."user_id")))));



CREATE POLICY "Enable update for users based on email" ON "public"."post_tags" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Enable update for users based on email" ON "public"."products" FOR UPDATE USING ((("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "products_brands"."users_id"
           FROM "public"."products_brands"
          WHERE ("products_brands"."products_id" = "products"."id"))))) OR ( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())))) WITH CHECK ((("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "products_brands"."users_id"
           FROM "public"."products_brands"
          WHERE ("products_brands"."products_id" = "products"."id"))))) OR ( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Enable update for users based on email" ON "public"."push_notifications_queue" FOR UPDATE USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))) WITH CHECK (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable update for users based on email" ON "public"."user_notifications_settings" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Enable update for users based on role id" ON "public"."giveaway_entries" FOR UPDATE USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" >= 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))) WITH CHECK (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" >= 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable update for users based on role id" ON "public"."giveaways" FOR UPDATE USING (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" >= 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))) WITH CHECK (( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" >= 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));



CREATE POLICY "Enable update for users based on uid" ON "public"."addresses" FOR UPDATE USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "addresses"."user_id"))))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "addresses"."user_id")))));



CREATE POLICY "Enable update for users based on uid" ON "public"."notifications" FOR UPDATE USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "notifications"."user_id"))))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "notifications"."user_id")))));



CREATE POLICY "Enable update for users based on uid" ON "public"."posts" FOR UPDATE USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "posts"."user_id"))) OR ( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "posts"."user_id"))) OR ( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Enable update for users based on user_id" ON "public"."dispensary_stashlists" FOR UPDATE USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "User has all rights" ON "public"."favorite_dispensaries" USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "favorite_dispensaries"."user_id"))))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "favorite_dispensaries"."user_id")))));



CREATE POLICY "Users can add and remove lists_products." ON "public"."lists_products" USING ((("auth"."uid"() IN ( SELECT "lists"."user_id"
   FROM "public"."lists"
  WHERE ("lists"."id" = "lists_products"."lists_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "lists"."user_id"
           FROM "public"."lists"
          WHERE ("lists"."id" = "lists_products"."lists_id"))))))) WITH CHECK ((("auth"."uid"() IN ( SELECT "lists"."user_id"
   FROM "public"."lists"
  WHERE ("lists"."id" = "lists_products"."lists_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "lists"."user_id"
           FROM "public"."lists"
          WHERE ("lists"."id" = "lists_products"."lists_id")))))));



CREATE POLICY "Users can add and remove posts_products." ON "public"."posts_products" USING ((("auth"."uid"() IN ( SELECT "posts"."user_id"
   FROM "public"."posts"
  WHERE ("posts"."id" = "posts_products"."posts_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "posts"."user_id"
           FROM "public"."posts"
          WHERE ("posts"."id" = "posts_products"."posts_id"))))))) WITH CHECK ((("auth"."uid"() IN ( SELECT "posts"."user_id"
   FROM "public"."posts"
  WHERE ("posts"."id" = "posts_products"."posts_id"))) OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" IN ( SELECT "posts"."user_id"
           FROM "public"."posts"
          WHERE ("posts"."id" = "posts_products"."posts_id")))))));



CREATE POLICY "Users can have all permissions for cloud files." ON "public"."cloud_files" USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "cloud_files"."user_id"))))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "cloud_files"."user_id")))));



CREATE POLICY "Users can have all permissions for deal_claims." ON "public"."deal_claims" USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "deal_claims"."user_id"))))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "deal_claims"."user_id")))));



CREATE POLICY "Users can have all permissions for likes." ON "public"."likes" USING ((("auth"."uid"() = "users_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "likes"."users_id"))))) WITH CHECK ((("auth"."uid"() = "users_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "likes"."users_id")))));



CREATE POLICY "Users can have all permissions for posts." ON "public"."posts" USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "posts"."user_id"))) OR ( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "posts"."user_id"))) OR ( SELECT (("users"."role_id" <= 9) OR ("users"."role_id" > 3)) AS "bool"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Users can have all permissions for relationships." ON "public"."relationships" USING ((("auth"."uid"() = "follower_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "relationships"."follower_id"))))) WITH CHECK ((("auth"."uid"() = "follower_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "relationships"."follower_id")))));



CREATE POLICY "Users can have all permissions for stash." ON "public"."stash" USING ((("auth"."uid"() = "users_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "stash"."users_id"))))) WITH CHECK ((("auth"."uid"() = "users_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "stash"."users_id")))));



CREATE POLICY "Users can have all permissions for subscriptions_lists." ON "public"."subscriptions_lists" USING ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "subscriptions_lists"."user_id"))))) WITH CHECK ((("auth"."uid"() = "user_id") OR ("auth"."uid"() IN ( SELECT "user_brand_admins"."user_id"
   FROM "public"."user_brand_admins"
  WHERE ("user_brand_admins"."brand_id" = "subscriptions_lists"."user_id")))));



ALTER TABLE "public"."addresses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."analytics_posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."breeders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cannabis_strain_relations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cannabis_strains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cannabis_strains_product_features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cannabis_types" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cloud_files" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cloud_files are viewable by everyone." ON "public"."cloud_files" FOR SELECT USING (true);



ALTER TABLE "public"."deal_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "deals are viewable by everyone." ON "public"."deals" FOR SELECT USING (true);



ALTER TABLE "public"."deals_dispensary_locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "deals_dispensary_locations are viewable by everyone." ON "public"."deals_dispensary_locations" FOR SELECT USING (true);



ALTER TABLE "public"."directus_activity" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_collections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_dashboards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_fields" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_files" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_flows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_folders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_operations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_panels" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_presets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_relations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_revisions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_shares" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."directus_webhooks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dispensary_employees" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dispensary_locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dispensary_locations are viewable by everyone." ON "public"."dispensary_locations" FOR SELECT USING (true);



ALTER TABLE "public"."dispensary_locations_cloud_files" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "dispensary_locations_cloud_files are viewable by everyone." ON "public"."dispensary_locations_cloud_files" FOR SELECT USING (true);



ALTER TABLE "public"."dispensary_stashlists" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."explore" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."favorite_dispensaries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."featured_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."files" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."g_ids" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."giveaway_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."giveaways" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."giveaways_regions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."growers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "growers are viewable by everyone." ON "public"."growers" FOR SELECT USING (true);



ALTER TABLE "public"."likes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "likes are viewable by everyone." ON "public"."deal_claims" FOR SELECT TO "anon", "authenticated" USING (true);



CREATE POLICY "likes are viewable by everyone." ON "public"."likes" FOR SELECT TO "anon", "authenticated" USING (true);



ALTER TABLE "public"."lists" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lists_products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lists_products are viewable by everyone." ON "public"."lists_products" FOR SELECT USING (true);



ALTER TABLE "public"."notification_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_types" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."post_flags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."post_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."post_tags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "post_tags are viewable by everyone." ON "public"."post_tags" FOR SELECT USING (true);



ALTER TABLE "public"."postal_codes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "postal_codes are viewable by everyone." ON "public"."postal_codes" FOR SELECT USING (true);



ALTER TABLE "public"."posts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "posts are viewable by everyone." ON "public"."posts" FOR SELECT USING (true);



ALTER TABLE "public"."posts_hashtags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "posts_hashtags are viewable by everyone." ON "public"."posts_hashtags" FOR SELECT USING (true);



ALTER TABLE "public"."posts_lists" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."posts_products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "posts_products are viewable by everyone." ON "public"."posts_products" FOR SELECT USING (true);



ALTER TABLE "public"."posts_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_feature_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "product_feature_types are viewable by everyone." ON "public"."product_feature_types" FOR SELECT USING (true);



ALTER TABLE "public"."product_features" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "product_features are viewable by everyone." ON "public"."product_features" FOR SELECT USING (true);



ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products are viewable by everyone." ON "public"."products" FOR SELECT USING (true);



ALTER TABLE "public"."products_brands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_brands are viewable by everyone." ON "public"."products_brands" FOR SELECT USING (true);



ALTER TABLE "public"."products_cannabis_strains" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_cannabis_strains are viewable by everyone." ON "public"."products_cannabis_strains" FOR SELECT USING (true);



ALTER TABLE "public"."products_cannabis_strains_1" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_cannabis_strains_1 are viewable by everyone." ON "public"."products_cannabis_strains_1" FOR SELECT USING (true);



ALTER TABLE "public"."products_cloud_files" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_cloud_files are viewable by everyone." ON "public"."products_cloud_files" FOR SELECT USING (true);



ALTER TABLE "public"."products_product_features_2" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_product_features_2 are viewable by everyone." ON "public"."products_product_features_2" FOR SELECT USING (true);



ALTER TABLE "public"."products_products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_products are viewable by everyone." ON "public"."products_products" FOR SELECT USING (true);



ALTER TABLE "public"."products_states" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_states are viewable by everyone." ON "public"."products_states" FOR SELECT USING (true);



ALTER TABLE "public"."push_notifications_queue" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."relationships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "relationships are viewable by everyone." ON "public"."relationships" FOR SELECT TO "anon", "authenticated" USING (true);



ALTER TABLE "public"."roles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "roles are viewable by everyone." ON "public"."roles" FOR SELECT USING (true);



ALTER TABLE "public"."shop_now" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."stash" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stash are viewable by everyone." ON "public"."stash" FOR SELECT TO "anon", "authenticated" USING (true);



ALTER TABLE "public"."states" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "states are viewable by everyone." ON "public"."states" FOR SELECT USING (true);



ALTER TABLE "public"."subscriptions_lists" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscriptions_lists are viewable by everyone." ON "public"."subscriptions_lists" FOR SELECT TO "anon", "authenticated" USING (true);



ALTER TABLE "public"."typesense_import_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."us_locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "us_locations are viewable by everyone." ON "public"."us_locations" FOR SELECT USING (true);



ALTER TABLE "public"."user_blocks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_brand_admins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_delete_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_notifications_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notifications";






REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

















































































GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_out"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_recv"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_send"("public"."cube") TO "service_role";

























































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































GRANT ALL ON FUNCTION "public"."_add_sort_to_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."_add_sort_to_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_add_sort_to_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_clean_up_relationships"() TO "anon";
GRANT ALL ON FUNCTION "public"."_clean_up_relationships"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_clean_up_relationships"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_categories_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_categories_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_categories_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_deals_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_deals_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_deals_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_dispensaries_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_dispensaries_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_dispensaries_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_giveaways_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_giveaways_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_giveaways_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_lists_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_lists_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_lists_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_postal_codes_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_postal_codes_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_postal_codes_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_posts_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_posts_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_posts_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_products_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_products_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_products_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_strains_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_strains_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_strains_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_delete_users_from_typesense_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_delete_users_from_typesense_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_delete_users_from_typesense_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_edge_employee_upgrade"("uid" "uuid", "email" "text", "name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_edge_employee_upgrade"("uid" "uuid", "email" "text", "name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_edge_employee_upgrade"("uid" "uuid", "email" "text", "name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_edge_notification_runner"() TO "anon";
GRANT ALL ON FUNCTION "public"."_edge_notification_runner"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_edge_notification_runner"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_edge_push_notifications_runner"() TO "anon";
GRANT ALL ON FUNCTION "public"."_edge_push_notifications_runner"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_edge_push_notifications_runner"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_delete_product_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_delete_product_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_delete_product_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_delete_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_delete_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_delete_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_dispensary_on_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_dispensary_on_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_dispensary_on_update"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_likes_insert_tasks"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_likes_insert_tasks"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_likes_insert_tasks"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_list_insert_tasks"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_list_insert_tasks"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_list_insert_tasks"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_deals"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_deals"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_deals"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_dispensaries"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_dispensaries"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_dispensaries"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_giveaways"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_giveaways"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_giveaways"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_lists"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_lists"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_lists"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_postal_codes"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_postal_codes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_postal_codes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_posts"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_posts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_posts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_product_categories"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_product_categories"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_product_categories"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_strains"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_strains"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_strains"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_typesense_users"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_typesense_users"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_typesense_users"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_fn_user_set_claimed"() TO "anon";
GRANT ALL ON FUNCTION "public"."_fn_user_set_claimed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_fn_user_set_claimed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_randome_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_randome_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_randome_code"() TO "service_role";



GRANT ALL ON TABLE "public"."dispensary_locations" TO "anon";
GRANT ALL ON TABLE "public"."dispensary_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."dispensary_locations" TO "service_role";



GRANT ALL ON FUNCTION "public"."_latitudeondispensary"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_latitudeondispensary"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_latitudeondispensary"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON TABLE "public"."posts" TO "anon";
GRANT ALL ON TABLE "public"."posts" TO "authenticated";
GRANT ALL ON TABLE "public"."posts" TO "service_role";



GRANT ALL ON FUNCTION "public"."_latitudeonpost"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_latitudeonpost"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_latitudeonpost"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_location_on_dispensary"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_location_on_dispensary"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_location_on_dispensary"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_longitudeondispensary"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_longitudeondispensary"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_longitudeondispensary"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_longitudeonpost"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_longitudeonpost"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_longitudeonpost"("rec" "public"."posts") TO "service_role";



GRANT ALL ON TABLE "public"."regions" TO "anon";
GRANT ALL ON TABLE "public"."regions" TO "authenticated";
GRANT ALL ON TABLE "public"."regions" TO "service_role";



GRANT ALL ON FUNCTION "public"."_postal_codes_on_region"("rec" "public"."regions") TO "anon";
GRANT ALL ON FUNCTION "public"."_postal_codes_on_region"("rec" "public"."regions") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_postal_codes_on_region"("rec" "public"."regions") TO "service_role";



GRANT ALL ON FUNCTION "public"."_products_added_to_list_notification"() TO "anon";
GRANT ALL ON FUNCTION "public"."_products_added_to_list_notification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_products_added_to_list_notification"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_restash_notification"() TO "anon";
GRANT ALL ON FUNCTION "public"."_restash_notification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_restash_notification"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_select_contest_winners"() TO "anon";
GRANT ALL ON FUNCTION "public"."_select_contest_winners"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_select_contest_winners"() TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON FUNCTION "public"."_sub_product_count"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_sub_product_count"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_sub_product_count"("rec" "public"."products") TO "service_role";



GRANT ALL ON TABLE "public"."cannabis_strains" TO "anon";
GRANT ALL ON TABLE "public"."cannabis_strains" TO "authenticated";
GRANT ALL ON TABLE "public"."cannabis_strains" TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_date_created"("rec" "public"."cannabis_strains") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_date_created"("rec" "public"."cannabis_strains") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_date_created"("rec" "public"."cannabis_strains") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_date_updated"("rec" "public"."cannabis_strains") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_date_updated"("rec" "public"."cannabis_strains") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_date_updated"("rec" "public"."cannabis_strains") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_id"("rec" "public"."cannabis_strains") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_id"("rec" "public"."cannabis_strains") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_cannabis_strains_id"("rec" "public"."cannabis_strains") TO "service_role";



GRANT ALL ON TABLE "public"."deals" TO "anon";
GRANT ALL ON TABLE "public"."deals" TO "authenticated";
GRANT ALL ON TABLE "public"."deals" TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_brand_names"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_brand_names"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_brand_names"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_cities"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_cities"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_cities"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_date_created"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_date_created"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_date_created"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_date_updated"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_date_updated"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_date_updated"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_expirationdate"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_expirationdate"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_expirationdate"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_id"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_id"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_id"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_latlng"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_latlng"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_latlng"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_location_names"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_location_names"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_location_names"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_postal_codes"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_postal_codes"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_postal_codes"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_product_category"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_product_category"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_product_category"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_product_name"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_product_name"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_product_name"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_releasedate"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_releasedate"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_releasedate"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_deals_states"("rec" "public"."deals") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_deals_states"("rec" "public"."deals") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_deals_states"("rec" "public"."deals") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_brand_name"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_brand_name"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_brand_name"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_city"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_city"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_city"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_date_created"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_date_created"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_date_created"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_date_updated"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_date_updated"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_date_updated"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_employees"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_employees"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_employees"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_id"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_id"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_id"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_latlng"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_latlng"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_latlng"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_postal_code"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_postal_code"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_postal_code"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_state"("rec" "public"."dispensary_locations") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_state"("rec" "public"."dispensary_locations") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_dispensary_locations_state"("rec" "public"."dispensary_locations") TO "service_role";



GRANT ALL ON TABLE "public"."giveaways" TO "anon";
GRANT ALL ON TABLE "public"."giveaways" TO "authenticated";
GRANT ALL ON TABLE "public"."giveaways" TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_brand_names"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_brand_names"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_brand_names"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_date_created"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_date_created"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_date_created"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_date_updated"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_date_updated"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_date_updated"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_end_time"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_end_time"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_end_time"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_id"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_id"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_id"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_postal_codes"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_postal_codes"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_postal_codes"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_product_categories"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_product_categories"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_product_categories"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_product_name"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_product_name"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_product_name"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_giveaways_start_time"("rec" "public"."giveaways") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_start_time"("rec" "public"."giveaways") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_giveaways_start_time"("rec" "public"."giveaways") TO "service_role";



GRANT ALL ON TABLE "public"."lists" TO "anon";
GRANT ALL ON TABLE "public"."lists" TO "authenticated";
GRANT ALL ON TABLE "public"."lists" TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_lists_display_name"("rec" "public"."lists") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_lists_display_name"("rec" "public"."lists") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_lists_display_name"("rec" "public"."lists") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_lists_id"("rec" "public"."lists") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_lists_id"("rec" "public"."lists") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_lists_id"("rec" "public"."lists") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_lists_product_categories"("rec" "public"."lists") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_lists_product_categories"("rec" "public"."lists") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_lists_product_categories"("rec" "public"."lists") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_lists_product_category_ids"("rec" "public"."lists") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_lists_product_category_ids"("rec" "public"."lists") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_lists_product_category_ids"("rec" "public"."lists") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_lists_product_ids"("rec" "public"."lists") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_lists_product_ids"("rec" "public"."lists") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_lists_product_ids"("rec" "public"."lists") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_lists_product_names"("rec" "public"."lists") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_lists_product_names"("rec" "public"."lists") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_lists_product_names"("rec" "public"."lists") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_lists_user_id"("rec" "public"."lists") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_lists_user_id"("rec" "public"."lists") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_lists_user_id"("rec" "public"."lists") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_lists_username"("rec" "public"."lists") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_lists_username"("rec" "public"."lists") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_lists_username"("rec" "public"."lists") TO "service_role";



GRANT ALL ON TABLE "public"."postal_codes" TO "anon";
GRANT ALL ON TABLE "public"."postal_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."postal_codes" TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_postal_codes_id"("rec" "public"."postal_codes") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_postal_codes_id"("rec" "public"."postal_codes") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_postal_codes_id"("rec" "public"."postal_codes") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_postal_codes_latlng"("rec" "public"."postal_codes") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_postal_codes_latlng"("rec" "public"."postal_codes") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_postal_codes_latlng"("rec" "public"."postal_codes") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_city"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_city"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_city"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_date_created"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_date_created"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_date_created"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_date_updated"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_date_updated"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_date_updated"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_display_name"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_display_name"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_display_name"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_id"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_id"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_id"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_list_ids"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_list_ids"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_list_ids"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_list_names"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_list_names"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_list_names"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_location"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_location"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_location"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_product_categories"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_product_categories"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_product_categories"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_product_category_ids"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_product_category_ids"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_product_category_ids"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_product_ids"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_product_ids"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_product_ids"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_product_names"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_product_names"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_product_names"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_region"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_region"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_region"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_tags"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_tags"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_tags"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_user_id"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_user_id"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_user_id"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_user_ids"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_user_ids"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_user_ids"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_user_names"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_user_names"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_user_names"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_user_usernames"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_user_usernames"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_user_usernames"("rec" "public"."posts") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_posts_username"("rec" "public"."posts") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_posts_username"("rec" "public"."posts") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_posts_username"("rec" "public"."posts") TO "service_role";



GRANT ALL ON TABLE "public"."product_categories" TO "anon";
GRANT ALL ON TABLE "public"."product_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."product_categories" TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_product_categories_id"("rec" "public"."product_categories") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_product_categories_id"("rec" "public"."product_categories") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_product_categories_id"("rec" "public"."product_categories") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_brand"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_brand"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_brand"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_brand_ids"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_brand_ids"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_brand_ids"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_category"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_category"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_category"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_date_created"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_date_created"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_date_created"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_date_updated"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_date_updated"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_date_updated"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_features"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_features"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_features"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_id"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_id"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_id"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_releasedate"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_releasedate"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_releasedate"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_sub_product_ids"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_sub_product_ids"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_sub_product_ids"("rec" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_products_sub_products"("rec" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_products_sub_products"("rec" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_products_sub_products"("rec" "public"."products") TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_users_date_created"("rec" "public"."users") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_users_date_created"("rec" "public"."users") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_users_date_created"("rec" "public"."users") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_users_date_updated"("rec" "public"."users") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_users_date_updated"("rec" "public"."users") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_users_date_updated"("rec" "public"."users") TO "service_role";



GRANT ALL ON FUNCTION "public"."_ts_users_id"("rec" "public"."users") TO "anon";
GRANT ALL ON FUNCTION "public"."_ts_users_id"("rec" "public"."users") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_ts_users_id"("rec" "public"."users") TO "service_role";



GRANT ALL ON FUNCTION "public"."_typesense_delete"("id" "text", "collection" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_typesense_delete"("id" "text", "collection" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_typesense_delete"("id" "text", "collection" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_typesense_import"() TO "anon";
GRANT ALL ON FUNCTION "public"."_typesense_import"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_typesense_import"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_typesense_import_int"("id" integer, "collection" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_typesense_import_int"("id" integer, "collection" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_typesense_import_int"("id" integer, "collection" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_typesense_import_uuid"("id" "uuid", "collection" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_typesense_import_uuid"("id" "uuid", "collection" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_typesense_import_uuid"("id" "uuid", "collection" "text") TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") TO "anon";
GRANT ALL ON FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") TO "service_role";



GRANT ALL ON FUNCTION "public"."cascade_product_category_fts_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."cascade_product_category_fts_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cascade_product_category_fts_update"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cascade_product_fts_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."cascade_product_fts_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cascade_product_fts_update"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cascade_products_brands_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."cascade_products_brands_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cascade_products_brands_update"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cascade_user_fts_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."cascade_user_fts_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cascade_user_fts_update"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_if_deal_expired"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_if_deal_expired"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_if_deal_expired"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_notifications"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_notifications"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_notifications"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_update_permissions"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_update_permissions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_update_permissions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."count_estimate"("query" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."count_estimate"("query" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."count_estimate"("query" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube"("public"."cube", double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_cmp"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_contained"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_contains"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_coord"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_coord_llur"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_dim"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_distance"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_enlarge"("public"."cube", double precision, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_eq"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ge"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_gt"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_inter"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_is_point"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_le"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ll_coord"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_lt"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ne"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_overlap"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_size"("public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_subset"("public"."cube", integer[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_union"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cube_ur_coord"("public"."cube", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_file_on_update_related_table"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_file_on_update_related_table"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_file_on_update_related_table"() TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_list"("lid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_list"("lid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_list"("lid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_post"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_post"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_post"("pid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."distance_chebyshev"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "anon";
GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "authenticated";
GRANT ALL ON FUNCTION "public"."distance_taxicab"("public"."cube", "public"."cube") TO "service_role";



GRANT ALL ON FUNCTION "public"."earth"() TO "anon";
GRANT ALL ON FUNCTION "public"."earth"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth"() TO "service_role";



GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth_box"("public"."earth", double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."earth_distance"("public"."earth", "public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."execute_brand_name_population"("test_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."execute_brand_name_population"("test_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."execute_brand_name_population"("test_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."fake_credentials"("phone_number" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fake_credentials"("phone_number" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fake_credentials"("phone_number" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."flag_post"("pid" "uuid", "uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."flag_post"("pid" "uuid", "uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."flag_post"("pid" "uuid", "uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_add_or_change_list_on_user_name_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_add_or_change_list_on_user_name_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_add_or_change_list_on_user_name_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_add_role_id_to_relationship"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_add_role_id_to_relationship"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_add_role_id_to_relationship"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_analytics_post"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_analytics_post"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_analytics_post"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_brand_count_on_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_brand_count_on_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_brand_count_on_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_category_product_count_on_product"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_category_product_count_on_product"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_category_product_count_on_product"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_deal_count_on_deals"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_deal_count_on_deals"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_deal_count_on_deals"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_drop_reminder_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_drop_reminder_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_drop_reminder_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_follower_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_follower_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_follower_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_following_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_following_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_following_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_lists_product_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_lists_product_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_lists_product_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_post_count_on_users"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_post_count_on_users"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_post_count_on_users"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_post_product_count_on_product"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_post_product_count_on_product"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_post_product_count_on_product"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_posts_like_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_posts_like_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_posts_like_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_product_count_on_users"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_product_count_on_users"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_product_count_on_users"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_product_list_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_product_list_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_product_list_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_product_stash_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_product_stash_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_product_stash_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_tag_on_post_tags"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_tag_on_post_tags"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_tag_on_post_tags"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_users2_post_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_users2_post_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_users2_post_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_users_like_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_users_like_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_users_like_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_users_post_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_users_post_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_users_post_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_users_reminder_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_users_reminder_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_users_reminder_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_change_users_stash_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_change_users_stash_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_change_users_stash_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_clean_up_cloud_files"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_clean_up_cloud_files"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_clean_up_cloud_files"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_create_admin_account_for_cms"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_create_admin_account_for_cms"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_create_admin_account_for_cms"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_create_directus_user_on_admin_add"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_create_directus_user_on_admin_add"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_create_directus_user_on_admin_add"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_delete_post"("post_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_delete_post"("post_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_delete_post"("post_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_delete_remote_file_on_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_delete_remote_file_on_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_delete_remote_file_on_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_dispensary_count_on_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_dispensary_count_on_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_dispensary_count_on_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_flag_count_on_posts"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_flag_count_on_posts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_flag_count_on_posts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_giveaway_entry_count_on_giveaway"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_giveaway_entry_count_on_giveaway"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_giveaway_entry_count_on_giveaway"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_giveaway_entry_triggers"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_giveaway_entry_triggers"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_giveaway_entry_triggers"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_giveaway_input_push"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_giveaway_input_push"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_giveaway_input_push"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_giveaway_triggers"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_giveaway_triggers"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_giveaway_triggers"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_id_dispensary_admin"("user_id" "uuid", "dispensary_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_id_dispensary_admin"("user_id" "uuid", "dispensary_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_id_dispensary_admin"("user_id" "uuid", "dispensary_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_insert_update_or_delete_post_from_drop"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_insert_update_or_delete_post_from_drop"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_insert_update_or_delete_post_from_drop"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_insert_update_or_delete_public_user_from_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_insert_update_or_delete_public_user_from_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_insert_update_or_delete_public_user_from_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_lists_products_sort"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_lists_products_sort"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_lists_products_sort"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_lookup_dispensaries"("lat" double precision, "long" double precision, "ids" "uuid"[], "lim" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_lookup_dispensaries"("lat" double precision, "long" double precision, "ids" "uuid"[], "lim" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_lookup_dispensaries"("lat" double precision, "long" double precision, "ids" "uuid"[], "lim" integer) TO "service_role";












GRANT ALL ON FUNCTION "public"."fn_message_template_count_on_types"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_message_template_count_on_types"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_message_template_count_on_types"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_new_user_from_brand"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_new_user_from_brand"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_new_user_from_brand"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_post_tasks"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_post_tasks"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_post_tasks"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_postal_tasks"("post_id" "uuid", "message" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_postal_tasks"("post_id" "uuid", "message" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_postal_tasks"("post_id" "uuid", "message" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_postgis_encode"("long" double precision, "lat" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."fn_postgis_encode"("long" double precision, "lat" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_postgis_encode"("long" double precision, "lat" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_prodcuts_gallery_sort"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_prodcuts_gallery_sort"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_prodcuts_gallery_sort"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_product_post_insert_tasks"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_product_post_insert_tasks"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_product_post_insert_tasks"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_product_tasks"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_product_tasks"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_product_tasks"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_schema_fields"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_schema_fields"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_schema_fields"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_schema_types"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_schema_types"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_schema_types"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_send_creator_notification_triggers"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_send_creator_notification_triggers"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_send_creator_notification_triggers"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_send_creator_notifications"("id" "uuid", "email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."fn_send_creator_notifications"("id" "uuid", "email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_send_creator_notifications"("id" "uuid", "email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_send_push_notifications"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_send_push_notifications"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_send_push_notifications"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_update_dispensary_date_on_employee_add"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_update_dispensary_date_on_employee_add"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_update_dispensary_date_on_employee_add"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_update_schema"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_update_schema"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_update_schema"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_update_tasks"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_update_tasks"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_update_tasks"() TO "service_role";



GRANT ALL ON FUNCTION "public"."fn_user_brand_admins_triggers"() TO "anon";
GRANT ALL ON FUNCTION "public"."fn_user_brand_admins_triggers"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fn_user_brand_admins_triggers"() TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_consistent"("internal", "public"."cube", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_distance"("internal", "public"."cube", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_same"("public"."cube", "public"."cube", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."g_cube_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."gc_to_sec"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_brand_update_sql"("batch_size" integer, "offset_value" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."generate_brand_update_sql"("batch_size" integer, "offset_value" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_brand_update_sql"("batch_size" integer, "offset_value" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_complete_fts_update_script"("batch_size" integer, "max_batches" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."generate_complete_fts_update_script"("batch_size" integer, "max_batches" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_complete_fts_update_script"("batch_size" integer, "max_batches" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_fts_update_sql"("batch_size" integer, "offset_value" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."generate_fts_update_sql"("batch_size" integer, "offset_value" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_fts_update_sql"("batch_size" integer, "offset_value" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_product_update_sql"("product_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_product_update_sql"("product_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_product_update_sql"("product_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_username"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_username"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_username"() TO "service_role";



GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "anon";
GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "authenticated";
GRANT ALL ON FUNCTION "public"."geo_distance"("point", "point") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_active_categories"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_active_categories"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_active_categories"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_drops_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_drops_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_drops_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_feed"("uid" "text", "ids" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_feed"("uid" "text", "ids" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_feed"("uid" "text", "ids" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_feed_items"("p_uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_feed_items"("p_uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_feed_items"("p_uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_followed_brands"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_followed_brands"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_followed_brands"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_followed_users"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_followed_users"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_followed_users"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_giveaways_winners_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_giveaways_winners_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_giveaways_winners_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_likes_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_likes_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_likes_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_list_add_items_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_list_add_items_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_list_add_items_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_new_followers_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_new_followers_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_new_followers_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_new_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_new_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_new_giveaways_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "types" integer[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_new_lists_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_new_lists_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_new_lists_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_new_posts_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_new_posts_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_new_posts_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_popular_stashlists"("limit_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_popular_stashlists"("limit_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_popular_stashlists"("limit_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_product_brand_names"("batch_size" integer, "offset_value" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_product_brand_names"("batch_size" integer, "offset_value" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_product_brand_names"("batch_size" integer, "offset_value" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_product_fts_data"("batch_size" integer, "offset_value" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_product_fts_data"("batch_size" integer, "offset_value" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_product_fts_data"("batch_size" integer, "offset_value" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_product_stash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_product_stash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_product_stash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_product_tag_in_post_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_product_tag_in_post_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_product_tag_in_post_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_restash_list_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_restash_list_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_restash_list_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_restash_post_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_restash_post_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_restash_post_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_restash_profile_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_restash_profile_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_restash_profile_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_sample_product_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_sample_product_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_sample_product_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_seen_post_ids"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_seen_post_ids"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_seen_post_ids"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_stashlists_by_ids"("list_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_stashlists_by_ids"("list_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_stashlists_by_ids"("list_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_total_all_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_total_all_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_total_all_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_total_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_total_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_total_restash_count_for_notifications"("starttime" timestamp without time zone, "endtime" timestamp without time zone, "type" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trending_hashtags"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_trending_hashtags"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trending_hashtags"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trending_lists"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_trending_lists"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trending_lists"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trending_relations"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_trending_relations"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trending_relations"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trending_stash"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_trending_stash"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trending_stash"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unread_notification_count"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_follower_count"("uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_follower_count"("uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_follower_count"("uid" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_users_followed_brands"("user_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_users_followed_brands"("user_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_users_followed_brands"("user_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_users_for_lists_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_users_for_lists_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_users_for_lists_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_users_for_posts_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_users_for_posts_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_users_for_posts_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."graphql_request"("query" "text", "variables" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."graphql_request"("query" "text", "variables" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."graphql_request"("query" "text", "variables" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_add_storage"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_add_storage"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_add_storage"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_json"("input_text" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."is_json"("input_text" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_json"("input_text" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."latitude"("public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ll_to_earth"(double precision, double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."log_deletion"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_deletion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_deletion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "anon";
GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "authenticated";
GRANT ALL ON FUNCTION "public"."longitude"("public"."earth") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_notifications_as_read"("uid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_notifications_as_read"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_notifications_as_read"("uid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."merge_user_accounts"("from_id" "uuid", "to_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."merge_user_accounts"("from_id" "uuid", "to_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."merge_user_accounts"("from_id" "uuid", "to_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."nearby_dispensary_locations"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[], "lim" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."nearby_dispensary_locations"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[], "lim" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."nearby_dispensary_locations"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[], "lim" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."nearby_postal_codes"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" integer[], "lim" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."nearby_postal_codes"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" integer[], "lim" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."nearby_postal_codes"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" integer[], "lim" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."nearby_posts"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[], "lim" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."nearby_posts"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[], "lim" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."nearby_posts"("lat" double precision, "long" double precision, "range_meters" double precision, "ids_to_exclude" "uuid"[], "lim" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_brand_of_employee_request"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_brand_of_employee_request"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_brand_of_employee_request"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_employee_of_approval"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_employee_of_approval"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_employee_of_approval"() TO "service_role";



GRANT ALL ON FUNCTION "public"."populate_cached_brand_names_efficient"() TO "anon";
GRANT ALL ON FUNCTION "public"."populate_cached_brand_names_efficient"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."populate_cached_brand_names_efficient"() TO "service_role";



GRANT ALL ON FUNCTION "public"."product_search"("search_terms" "text", "brand_ids" "text", "category_ids" "text", "selected_ids" "text", "s_limit" integer, "s_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."product_search"("search_terms" "text", "brand_ids" "text", "category_ids" "text", "selected_ids" "text", "s_limit" integer, "s_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."product_search"("search_terms" "text", "brand_ids" "text", "category_ids" "text", "selected_ids" "text", "s_limit" integer, "s_offset" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."rebuild_all_fts"() TO "anon";
GRANT ALL ON FUNCTION "public"."rebuild_all_fts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rebuild_all_fts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rebuild_all_fts_optimized"("batch_size" integer, "test_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."rebuild_all_fts_optimized"("batch_size" integer, "test_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."rebuild_all_fts_optimized"("batch_size" integer, "test_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."rebuild_fts_except_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."rebuild_fts_except_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rebuild_fts_except_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rebuild_fts_vectors_in_batches"("test_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."rebuild_fts_vectors_in_batches"("test_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."rebuild_fts_vectors_in_batches"("test_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."reorder_featured_items"("p_item_type" "text", "p_ordered_item_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."reorder_featured_items"("p_item_type" "text", "p_ordered_item_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."reorder_featured_items"("p_item_type" "text", "p_ordered_item_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."repopulate_all_product_cached_brands"() TO "anon";
GRANT ALL ON FUNCTION "public"."repopulate_all_product_cached_brands"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."repopulate_all_product_cached_brands"() TO "service_role";



GRANT ALL ON FUNCTION "public"."search_brands"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."search_brands"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_brands"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."search_dispensary_locations"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."search_dispensary_locations"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_dispensary_locations"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."search_giveaways"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."search_giveaways"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_giveaways"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."search_lists"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."search_lists"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_lists"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."search_posts"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."search_posts"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_posts"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."search_products"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."search_products"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_products"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."search_users"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."search_users"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."search_users"("search_query" "text", "result_limit" integer, "result_offset" integer, "exclude_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sec_to_gc"(double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."select_giveaway_contest_winner"("gid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."select_giveaway_contest_winner"("gid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."select_giveaway_contest_winner"("gid" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."send_email_mailgun"("message" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."send_email_mailgun"("message" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."send_email_mailgun"("message" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_email_mailgun"("message" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."send_email_message"("message" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."send_email_message"("message" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."send_email_message"("message" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_email_message"("message" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_push_noti"("message" "text", "devices" "json", "data_type" "text", "campaign" "text", "app_url" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."send_push_noti"("message" "text", "devices" "json", "data_type" "text", "campaign" "text", "app_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_push_noti"("message" "text", "devices" "json", "data_type" "text", "campaign" "text", "app_url" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_initial_featured_item_sort_order"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_initial_featured_item_sort_order"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_initial_featured_item_sort_order"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_slug_from_name"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_slug_from_name"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_slug_from_name"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_slug_from_username"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_slug_from_username"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_slug_from_username"() TO "service_role";



GRANT ALL ON FUNCTION "public"."slugify"("value" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."slugify"("value" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."slugify"("value" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."slugify_varchar"("v" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."slugify_varchar"("v" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."slugify_varchar"("v" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."test_credentials"() TO "anon";
GRANT ALL ON FUNCTION "public"."test_credentials"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_credentials"() TO "service_role";



GRANT ALL ON FUNCTION "public"."test_product_brand_names"("product_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."test_product_brand_names"("product_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_product_brand_names"("product_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."test_product_brand_names"("product_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."test_product_brand_names"("product_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_product_brand_names"("product_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_set_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_set_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_set_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_set_updated_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_set_updated_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_set_updated_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."typeahead_dispensary_locations"("search_query" "text", "limit_results" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."typeahead_dispensary_locations"("search_query" "text", "limit_results" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."typeahead_dispensary_locations"("search_query" "text", "limit_results" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."typeahead_giveaways"("search_query" "text", "limit_results" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."typeahead_giveaways"("search_query" "text", "limit_results" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."typeahead_giveaways"("search_query" "text", "limit_results" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."typeahead_lists"("search_query" "text", "limit_results" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."typeahead_lists"("search_query" "text", "limit_results" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."typeahead_lists"("search_query" "text", "limit_results" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."typeahead_posts"("search_query" "text", "limit_results" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."typeahead_posts"("search_query" "text", "limit_results" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."typeahead_posts"("search_query" "text", "limit_results" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."typeahead_products"("search_query" "text", "limit_results" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."typeahead_products"("search_query" "text", "limit_results" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."typeahead_products"("search_query" "text", "limit_results" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."typeahead_universal"("search_query" "text", "limit_results" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."typeahead_universal"("search_query" "text", "limit_results" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."typeahead_universal"("search_query" "text", "limit_results" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."typeahead_users"("search_query" "text", "limit_results" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."typeahead_users"("search_query" "text", "limit_results" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."typeahead_users"("search_query" "text", "limit_results" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."unaccent"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."unaccent"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unaccent"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."unaccent"("regdictionary", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."unaccent"("regdictionary", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unaccent"("regdictionary", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."unaccent_init"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."unaccent_init"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unaccent_init"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."unaccent_lexize"("internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."unaccent_lexize"("internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unaccent_lexize"("internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."universal_search"("search_query" "text", "result_limit" integer, "result_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."universal_search"("search_query" "text", "result_limit" integer, "result_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."universal_search"("search_query" "text", "result_limit" integer, "result_offset" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_associated_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_associated_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_associated_data"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_dispensary_locations_fts"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_dispensary_locations_fts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_dispensary_locations_fts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_employee_approval"("p_dispensary_id" "uuid", "p_user_id" "uuid", "p_is_approved" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."update_employee_approval"("p_dispensary_id" "uuid", "p_user_id" "uuid", "p_is_approved" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_employee_approval"("p_dispensary_id" "uuid", "p_user_id" "uuid", "p_is_approved" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_fts_vector"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_fts_vector"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_fts_vector"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_giveaways_fts"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_giveaways_fts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_giveaways_fts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_lists_fts"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_lists_fts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_lists_fts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_notification_image_url"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_notification_image_url"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_notification_image_url"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_null_cached_brand_names"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_null_cached_brand_names"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_null_cached_brand_names"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_posts_fts"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_posts_fts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_posts_fts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_product_cached_brands"("product_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_product_cached_brands"("product_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_product_cached_brands"("product_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_products_fts"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_products_fts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_products_fts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_products_fts_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_products_fts_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_products_fts_data"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_products_fts_manual"("product_row" "public"."products") TO "anon";
GRANT ALL ON FUNCTION "public"."update_products_fts_manual"("product_row" "public"."products") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_products_fts_manual"("product_row" "public"."products") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_subscription_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_subscription_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_subscription_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_users_fts"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_users_fts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_users_fts"() TO "service_role";














































































GRANT ALL ON TABLE "public"."addresses" TO "anon";
GRANT ALL ON TABLE "public"."addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."addresses" TO "service_role";



GRANT ALL ON TABLE "public"."analytics_posts" TO "anon";
GRANT ALL ON TABLE "public"."analytics_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."analytics_posts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."analytics_posts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."analytics_posts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."analytics_posts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."breeders" TO "anon";
GRANT ALL ON TABLE "public"."breeders" TO "authenticated";
GRANT ALL ON TABLE "public"."breeders" TO "service_role";



GRANT ALL ON SEQUENCE "public"."breeders_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."breeders_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."breeders_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."cannabis_strain_relations" TO "anon";
GRANT ALL ON TABLE "public"."cannabis_strain_relations" TO "authenticated";
GRANT ALL ON TABLE "public"."cannabis_strain_relations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cannabis_strain_relations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cannabis_strain_relations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cannabis_strain_relations_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cannabis_strains_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cannabis_strains_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cannabis_strains_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."cannabis_strains_product_features" TO "anon";
GRANT ALL ON TABLE "public"."cannabis_strains_product_features" TO "authenticated";
GRANT ALL ON TABLE "public"."cannabis_strains_product_features" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cannabis_strains_product_features_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cannabis_strains_product_features_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cannabis_strains_product_features_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."cannabis_types" TO "anon";
GRANT ALL ON TABLE "public"."cannabis_types" TO "authenticated";
GRANT ALL ON TABLE "public"."cannabis_types" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cannabis_types_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cannabis_types_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cannabis_types_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."cloud_files" TO "anon";
GRANT ALL ON TABLE "public"."cloud_files" TO "authenticated";
GRANT ALL ON TABLE "public"."cloud_files" TO "service_role";



GRANT ALL ON TABLE "public"."deal_claims" TO "anon";
GRANT ALL ON TABLE "public"."deal_claims" TO "authenticated";
GRANT ALL ON TABLE "public"."deal_claims" TO "service_role";



GRANT ALL ON TABLE "public"."deals_dispensary_locations" TO "anon";
GRANT ALL ON TABLE "public"."deals_dispensary_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."deals_dispensary_locations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."deals_dispensary_locations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."deals_dispensary_locations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."deals_dispensary_locations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."deletion_log" TO "anon";
GRANT ALL ON TABLE "public"."deletion_log" TO "authenticated";
GRANT ALL ON TABLE "public"."deletion_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."deletion_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."deletion_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."deletion_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_activity" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_activity" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_activity_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_activity_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_activity_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_collections" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_collections" TO "service_role";



GRANT ALL ON TABLE "public"."directus_dashboards" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_dashboards" TO "service_role";



GRANT ALL ON TABLE "public"."directus_extensions" TO "anon";
GRANT ALL ON TABLE "public"."directus_extensions" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_extensions" TO "service_role";



GRANT ALL ON TABLE "public"."directus_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_fields" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_fields_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_fields_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_fields_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_files" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_files" TO "service_role";



GRANT ALL ON TABLE "public"."directus_flows" TO "anon";
GRANT ALL ON TABLE "public"."directus_flows" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_flows" TO "service_role";



GRANT ALL ON TABLE "public"."directus_folders" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_folders" TO "service_role";



GRANT ALL ON TABLE "public"."directus_migrations" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_migrations" TO "service_role";



GRANT ALL ON TABLE "public"."directus_notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_notifications" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_notifications_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_notifications_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_notifications_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_operations" TO "anon";
GRANT ALL ON TABLE "public"."directus_operations" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_operations" TO "service_role";



GRANT ALL ON TABLE "public"."directus_panels" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_panels" TO "service_role";



GRANT ALL ON TABLE "public"."directus_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_permissions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_permissions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_permissions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_permissions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_presets" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_presets" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_presets_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_presets_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_presets_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_relations" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_relations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_relations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_relations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_relations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_revisions" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_revisions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_revisions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_revisions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_revisions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_roles" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_roles" TO "service_role";



GRANT ALL ON TABLE "public"."directus_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."directus_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_settings" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_settings_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_settings_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_settings_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."directus_shares" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_shares" TO "service_role";



GRANT ALL ON TABLE "public"."directus_translations" TO "anon";
GRANT ALL ON TABLE "public"."directus_translations" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_translations" TO "service_role";



GRANT ALL ON TABLE "public"."directus_users" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_users" TO "service_role";



GRANT ALL ON TABLE "public"."directus_versions" TO "anon";
GRANT ALL ON TABLE "public"."directus_versions" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_versions" TO "service_role";



GRANT ALL ON TABLE "public"."directus_webhooks" TO "authenticated";
GRANT ALL ON TABLE "public"."directus_webhooks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."directus_webhooks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."directus_webhooks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."directus_webhooks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."dispensary_employees" TO "anon";
GRANT ALL ON TABLE "public"."dispensary_employees" TO "authenticated";
GRANT ALL ON TABLE "public"."dispensary_employees" TO "service_role";



GRANT ALL ON SEQUENCE "public"."dispensary_employees_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."dispensary_employees_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."dispensary_employees_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."dispensary_locations_cloud_files" TO "anon";
GRANT ALL ON TABLE "public"."dispensary_locations_cloud_files" TO "authenticated";
GRANT ALL ON TABLE "public"."dispensary_locations_cloud_files" TO "service_role";



GRANT ALL ON SEQUENCE "public"."dispensary_locations_cloud_files_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."dispensary_locations_cloud_files_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."dispensary_locations_cloud_files_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."dispensary_stashlists" TO "anon";
GRANT ALL ON TABLE "public"."dispensary_stashlists" TO "authenticated";
GRANT ALL ON TABLE "public"."dispensary_stashlists" TO "service_role";



GRANT ALL ON TABLE "public"."explore" TO "anon";
GRANT ALL ON TABLE "public"."explore" TO "authenticated";
GRANT ALL ON TABLE "public"."explore" TO "service_role";



GRANT ALL ON TABLE "public"."explore_dispensary_locations" TO "anon";
GRANT ALL ON TABLE "public"."explore_dispensary_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."explore_dispensary_locations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_dispensary_locations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_dispensary_locations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_dispensary_locations_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."explore_lists" TO "anon";
GRANT ALL ON TABLE "public"."explore_lists" TO "authenticated";
GRANT ALL ON TABLE "public"."explore_lists" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_lists_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_lists_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_lists_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."explore_page" TO "anon";
GRANT ALL ON TABLE "public"."explore_page" TO "authenticated";
GRANT ALL ON TABLE "public"."explore_page" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_page_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_page_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_page_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."explore_page_sections" TO "anon";
GRANT ALL ON TABLE "public"."explore_page_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."explore_page_sections" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_page_sections_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_page_sections_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_page_sections_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."explore_posts" TO "anon";
GRANT ALL ON TABLE "public"."explore_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."explore_posts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_posts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_posts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_posts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."explore_products" TO "anon";
GRANT ALL ON TABLE "public"."explore_products" TO "authenticated";
GRANT ALL ON TABLE "public"."explore_products" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_products_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_products_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_products_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."explore_trending" TO "anon";
GRANT ALL ON TABLE "public"."explore_trending" TO "authenticated";
GRANT ALL ON TABLE "public"."explore_trending" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_trending_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_trending_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_trending_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."explore_users" TO "anon";
GRANT ALL ON TABLE "public"."explore_users" TO "authenticated";
GRANT ALL ON TABLE "public"."explore_users" TO "service_role";



GRANT ALL ON SEQUENCE "public"."explore_users_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."explore_users_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."explore_users_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."favorite_dispensaries" TO "anon";
GRANT ALL ON TABLE "public"."favorite_dispensaries" TO "authenticated";
GRANT ALL ON TABLE "public"."favorite_dispensaries" TO "service_role";



GRANT ALL ON SEQUENCE "public"."favorite_dispensaries_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."favorite_dispensaries_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."favorite_dispensaries_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."featured_items" TO "anon";
GRANT ALL ON TABLE "public"."featured_items" TO "authenticated";
GRANT ALL ON TABLE "public"."featured_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."featured_items_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."featured_items_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."featured_items_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."files" TO "anon";
GRANT ALL ON TABLE "public"."files" TO "authenticated";
GRANT ALL ON TABLE "public"."files" TO "service_role";



GRANT ALL ON TABLE "public"."g_ids" TO "anon";
GRANT ALL ON TABLE "public"."g_ids" TO "authenticated";
GRANT ALL ON TABLE "public"."g_ids" TO "service_role";



GRANT ALL ON TABLE "public"."giveaway_entries" TO "anon";
GRANT ALL ON TABLE "public"."giveaway_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."giveaway_entries" TO "service_role";



GRANT ALL ON TABLE "public"."giveaway_entries_messages" TO "anon";
GRANT ALL ON TABLE "public"."giveaway_entries_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."giveaway_entries_messages" TO "service_role";



GRANT ALL ON TABLE "public"."giveaways_regions" TO "anon";
GRANT ALL ON TABLE "public"."giveaways_regions" TO "authenticated";
GRANT ALL ON TABLE "public"."giveaways_regions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."giveaways_regions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."giveaways_regions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."giveaways_regions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."growers" TO "anon";
GRANT ALL ON TABLE "public"."growers" TO "authenticated";
GRANT ALL ON TABLE "public"."growers" TO "service_role";



GRANT ALL ON SEQUENCE "public"."growers_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."growers_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."growers_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."likes" TO "anon";
GRANT ALL ON TABLE "public"."likes" TO "authenticated";
GRANT ALL ON TABLE "public"."likes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."likes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."likes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."likes_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."lists_products" TO "anon";
GRANT ALL ON TABLE "public"."lists_products" TO "authenticated";
GRANT ALL ON TABLE "public"."lists_products" TO "service_role";



GRANT ALL ON SEQUENCE "public"."lists_products_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."lists_products_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."lists_products_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."notification_messages" TO "anon";
GRANT ALL ON TABLE "public"."notification_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_messages" TO "service_role";



GRANT ALL ON SEQUENCE "public"."notification_messages_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."notification_messages_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."notification_messages_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."notification_types" TO "anon";
GRANT ALL ON TABLE "public"."notification_types" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_types" TO "service_role";



GRANT ALL ON SEQUENCE "public"."notification_types_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."notification_types_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."notification_types_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."post_flags" TO "anon";
GRANT ALL ON TABLE "public"."post_flags" TO "authenticated";
GRANT ALL ON TABLE "public"."post_flags" TO "service_role";



GRANT ALL ON SEQUENCE "public"."post_flags_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."post_flags_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."post_flags_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."post_log" TO "anon";
GRANT ALL ON TABLE "public"."post_log" TO "authenticated";
GRANT ALL ON TABLE "public"."post_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."post_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."post_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."post_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."post_tags" TO "anon";
GRANT ALL ON TABLE "public"."post_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."post_tags" TO "service_role";



GRANT ALL ON SEQUENCE "public"."post_tags_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."post_tags_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."post_tags_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."postal_codes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."postal_codes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."postal_codes_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."posts_hashtags" TO "anon";
GRANT ALL ON TABLE "public"."posts_hashtags" TO "authenticated";
GRANT ALL ON TABLE "public"."posts_hashtags" TO "service_role";



GRANT ALL ON SEQUENCE "public"."posts_hashtags_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."posts_hashtags_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."posts_hashtags_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."posts_lists" TO "anon";
GRANT ALL ON TABLE "public"."posts_lists" TO "authenticated";
GRANT ALL ON TABLE "public"."posts_lists" TO "service_role";



GRANT ALL ON SEQUENCE "public"."posts_lists_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."posts_lists_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."posts_lists_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."posts_products" TO "anon";
GRANT ALL ON TABLE "public"."posts_products" TO "authenticated";
GRANT ALL ON TABLE "public"."posts_products" TO "service_role";



GRANT ALL ON SEQUENCE "public"."posts_products_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."posts_products_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."posts_products_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."posts_users" TO "anon";
GRANT ALL ON TABLE "public"."posts_users" TO "authenticated";
GRANT ALL ON TABLE "public"."posts_users" TO "service_role";



GRANT ALL ON SEQUENCE "public"."posts_users_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."posts_users_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."posts_users_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."product_feature_types" TO "anon";
GRANT ALL ON TABLE "public"."product_feature_types" TO "authenticated";
GRANT ALL ON TABLE "public"."product_feature_types" TO "service_role";



GRANT ALL ON SEQUENCE "public"."product_feature_types_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."product_feature_types_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."product_feature_types_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."product_features" TO "anon";
GRANT ALL ON TABLE "public"."product_features" TO "authenticated";
GRANT ALL ON TABLE "public"."product_features" TO "service_role";



GRANT ALL ON SEQUENCE "public"."product_features_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."product_features_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."product_features_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products_brands" TO "anon";
GRANT ALL ON TABLE "public"."products_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."products_brands" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_brands_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_brands_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_brands_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products_cannabis_strains" TO "anon";
GRANT ALL ON TABLE "public"."products_cannabis_strains" TO "authenticated";
GRANT ALL ON TABLE "public"."products_cannabis_strains" TO "service_role";



GRANT ALL ON TABLE "public"."products_cannabis_strains_1" TO "anon";
GRANT ALL ON TABLE "public"."products_cannabis_strains_1" TO "authenticated";
GRANT ALL ON TABLE "public"."products_cannabis_strains_1" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_cannabis_strains_1_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_cannabis_strains_1_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_cannabis_strains_1_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_cannabis_strains_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_cannabis_strains_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_cannabis_strains_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products_cloud_files" TO "anon";
GRANT ALL ON TABLE "public"."products_cloud_files" TO "authenticated";
GRANT ALL ON TABLE "public"."products_cloud_files" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_cloud_files_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_cloud_files_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_cloud_files_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products_product_features_2" TO "anon";
GRANT ALL ON TABLE "public"."products_product_features_2" TO "authenticated";
GRANT ALL ON TABLE "public"."products_product_features_2" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_product_features_2_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_product_features_2_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_product_features_2_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products_products" TO "anon";
GRANT ALL ON TABLE "public"."products_products" TO "authenticated";
GRANT ALL ON TABLE "public"."products_products" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_products_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_products_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_products_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products_states" TO "anon";
GRANT ALL ON TABLE "public"."products_states" TO "authenticated";
GRANT ALL ON TABLE "public"."products_states" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_states_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_states_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_states_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."push_notifications_queue" TO "anon";
GRANT ALL ON TABLE "public"."push_notifications_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."push_notifications_queue" TO "service_role";



GRANT ALL ON SEQUENCE "public"."push_notifications_queue_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."push_notifications_queue_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."push_notifications_queue_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."region_postal_codes" TO "anon";
GRANT ALL ON TABLE "public"."region_postal_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."region_postal_codes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."region_postal_codes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."region_postal_codes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."region_postal_codes_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."regions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."regions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."regions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."relationships" TO "anon";
GRANT ALL ON TABLE "public"."relationships" TO "authenticated";
GRANT ALL ON TABLE "public"."relationships" TO "service_role";



GRANT ALL ON SEQUENCE "public"."relationships_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."relationships_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."relationships_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."roles" TO "anon";
GRANT ALL ON TABLE "public"."roles" TO "authenticated";
GRANT ALL ON TABLE "public"."roles" TO "service_role";



GRANT ALL ON SEQUENCE "public"."roles_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."roles_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."roles_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."sels" TO "anon";
GRANT ALL ON TABLE "public"."sels" TO "authenticated";
GRANT ALL ON TABLE "public"."sels" TO "service_role";



GRANT ALL ON TABLE "public"."shop_now" TO "anon";
GRANT ALL ON TABLE "public"."shop_now" TO "authenticated";
GRANT ALL ON TABLE "public"."shop_now" TO "service_role";



GRANT ALL ON TABLE "public"."stash" TO "anon";
GRANT ALL ON TABLE "public"."stash" TO "authenticated";
GRANT ALL ON TABLE "public"."stash" TO "service_role";



GRANT ALL ON SEQUENCE "public"."stash_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."stash_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."stash_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."states" TO "anon";
GRANT ALL ON TABLE "public"."states" TO "authenticated";
GRANT ALL ON TABLE "public"."states" TO "service_role";



GRANT ALL ON SEQUENCE "public"."states_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."states_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."states_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions_lists" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions_lists" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions_lists" TO "service_role";



GRANT ALL ON SEQUENCE "public"."subscriptions_lists_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."subscriptions_lists_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."subscriptions_lists_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."typesense_import_log" TO "anon";
GRANT ALL ON TABLE "public"."typesense_import_log" TO "authenticated";
GRANT ALL ON TABLE "public"."typesense_import_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."typesense_import_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."typesense_import_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."typesense_import_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."us_locations" TO "anon";
GRANT ALL ON TABLE "public"."us_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."us_locations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."us_locations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."us_locations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."us_locations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_blocks" TO "anon";
GRANT ALL ON TABLE "public"."user_blocks" TO "authenticated";
GRANT ALL ON TABLE "public"."user_blocks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."user_blocks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."user_blocks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."user_blocks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_brand_admins" TO "anon";
GRANT ALL ON TABLE "public"."user_brand_admins" TO "authenticated";
GRANT ALL ON TABLE "public"."user_brand_admins" TO "service_role";



GRANT ALL ON SEQUENCE "public"."user_brand_admins_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."user_brand_admins_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."user_brand_admins_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_delete_requests" TO "anon";
GRANT ALL ON TABLE "public"."user_delete_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."user_delete_requests" TO "service_role";



GRANT ALL ON SEQUENCE "public"."user_delete_requests_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."user_delete_requests_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."user_delete_requests_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_notifications_settings" TO "anon";
GRANT ALL ON TABLE "public"."user_notifications_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."user_notifications_settings" TO "service_role";



GRANT ALL ON SEQUENCE "public"."user_notifications_settings_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."user_notifications_settings_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."user_notifications_settings_id_seq" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";














































drop extension if exists "pg_net";

create sequence "public"."likes_id_seq";

revoke delete on table "public"."directus_activity" from "anon";

revoke insert on table "public"."directus_activity" from "anon";

revoke references on table "public"."directus_activity" from "anon";

revoke select on table "public"."directus_activity" from "anon";

revoke trigger on table "public"."directus_activity" from "anon";

revoke truncate on table "public"."directus_activity" from "anon";

revoke update on table "public"."directus_activity" from "anon";

revoke delete on table "public"."directus_collections" from "anon";

revoke insert on table "public"."directus_collections" from "anon";

revoke references on table "public"."directus_collections" from "anon";

revoke select on table "public"."directus_collections" from "anon";

revoke trigger on table "public"."directus_collections" from "anon";

revoke truncate on table "public"."directus_collections" from "anon";

revoke update on table "public"."directus_collections" from "anon";

revoke delete on table "public"."directus_dashboards" from "anon";

revoke insert on table "public"."directus_dashboards" from "anon";

revoke references on table "public"."directus_dashboards" from "anon";

revoke select on table "public"."directus_dashboards" from "anon";

revoke trigger on table "public"."directus_dashboards" from "anon";

revoke truncate on table "public"."directus_dashboards" from "anon";

revoke update on table "public"."directus_dashboards" from "anon";

revoke delete on table "public"."directus_fields" from "anon";

revoke insert on table "public"."directus_fields" from "anon";

revoke references on table "public"."directus_fields" from "anon";

revoke select on table "public"."directus_fields" from "anon";

revoke trigger on table "public"."directus_fields" from "anon";

revoke truncate on table "public"."directus_fields" from "anon";

revoke update on table "public"."directus_fields" from "anon";

revoke delete on table "public"."directus_files" from "anon";

revoke insert on table "public"."directus_files" from "anon";

revoke references on table "public"."directus_files" from "anon";

revoke select on table "public"."directus_files" from "anon";

revoke trigger on table "public"."directus_files" from "anon";

revoke truncate on table "public"."directus_files" from "anon";

revoke update on table "public"."directus_files" from "anon";

revoke delete on table "public"."directus_folders" from "anon";

revoke insert on table "public"."directus_folders" from "anon";

revoke references on table "public"."directus_folders" from "anon";

revoke select on table "public"."directus_folders" from "anon";

revoke trigger on table "public"."directus_folders" from "anon";

revoke truncate on table "public"."directus_folders" from "anon";

revoke update on table "public"."directus_folders" from "anon";

revoke delete on table "public"."directus_migrations" from "anon";

revoke insert on table "public"."directus_migrations" from "anon";

revoke references on table "public"."directus_migrations" from "anon";

revoke select on table "public"."directus_migrations" from "anon";

revoke trigger on table "public"."directus_migrations" from "anon";

revoke truncate on table "public"."directus_migrations" from "anon";

revoke update on table "public"."directus_migrations" from "anon";

revoke delete on table "public"."directus_notifications" from "anon";

revoke insert on table "public"."directus_notifications" from "anon";

revoke references on table "public"."directus_notifications" from "anon";

revoke select on table "public"."directus_notifications" from "anon";

revoke trigger on table "public"."directus_notifications" from "anon";

revoke truncate on table "public"."directus_notifications" from "anon";

revoke update on table "public"."directus_notifications" from "anon";

revoke delete on table "public"."directus_panels" from "anon";

revoke insert on table "public"."directus_panels" from "anon";

revoke references on table "public"."directus_panels" from "anon";

revoke select on table "public"."directus_panels" from "anon";

revoke trigger on table "public"."directus_panels" from "anon";

revoke truncate on table "public"."directus_panels" from "anon";

revoke update on table "public"."directus_panels" from "anon";

revoke delete on table "public"."directus_permissions" from "anon";

revoke insert on table "public"."directus_permissions" from "anon";

revoke references on table "public"."directus_permissions" from "anon";

revoke select on table "public"."directus_permissions" from "anon";

revoke trigger on table "public"."directus_permissions" from "anon";

revoke truncate on table "public"."directus_permissions" from "anon";

revoke update on table "public"."directus_permissions" from "anon";

revoke delete on table "public"."directus_presets" from "anon";

revoke insert on table "public"."directus_presets" from "anon";

revoke references on table "public"."directus_presets" from "anon";

revoke select on table "public"."directus_presets" from "anon";

revoke trigger on table "public"."directus_presets" from "anon";

revoke truncate on table "public"."directus_presets" from "anon";

revoke update on table "public"."directus_presets" from "anon";

revoke delete on table "public"."directus_relations" from "anon";

revoke insert on table "public"."directus_relations" from "anon";

revoke references on table "public"."directus_relations" from "anon";

revoke select on table "public"."directus_relations" from "anon";

revoke trigger on table "public"."directus_relations" from "anon";

revoke truncate on table "public"."directus_relations" from "anon";

revoke update on table "public"."directus_relations" from "anon";

revoke delete on table "public"."directus_revisions" from "anon";

revoke insert on table "public"."directus_revisions" from "anon";

revoke references on table "public"."directus_revisions" from "anon";

revoke select on table "public"."directus_revisions" from "anon";

revoke trigger on table "public"."directus_revisions" from "anon";

revoke truncate on table "public"."directus_revisions" from "anon";

revoke update on table "public"."directus_revisions" from "anon";

revoke delete on table "public"."directus_roles" from "anon";

revoke insert on table "public"."directus_roles" from "anon";

revoke references on table "public"."directus_roles" from "anon";

revoke select on table "public"."directus_roles" from "anon";

revoke trigger on table "public"."directus_roles" from "anon";

revoke truncate on table "public"."directus_roles" from "anon";

revoke update on table "public"."directus_roles" from "anon";

revoke delete on table "public"."directus_sessions" from "anon";

revoke insert on table "public"."directus_sessions" from "anon";

revoke references on table "public"."directus_sessions" from "anon";

revoke select on table "public"."directus_sessions" from "anon";

revoke trigger on table "public"."directus_sessions" from "anon";

revoke truncate on table "public"."directus_sessions" from "anon";

revoke update on table "public"."directus_sessions" from "anon";

revoke delete on table "public"."directus_settings" from "anon";

revoke insert on table "public"."directus_settings" from "anon";

revoke references on table "public"."directus_settings" from "anon";

revoke select on table "public"."directus_settings" from "anon";

revoke trigger on table "public"."directus_settings" from "anon";

revoke truncate on table "public"."directus_settings" from "anon";

revoke update on table "public"."directus_settings" from "anon";

revoke delete on table "public"."directus_shares" from "anon";

revoke insert on table "public"."directus_shares" from "anon";

revoke references on table "public"."directus_shares" from "anon";

revoke select on table "public"."directus_shares" from "anon";

revoke trigger on table "public"."directus_shares" from "anon";

revoke truncate on table "public"."directus_shares" from "anon";

revoke update on table "public"."directus_shares" from "anon";

revoke delete on table "public"."directus_users" from "anon";

revoke insert on table "public"."directus_users" from "anon";

revoke references on table "public"."directus_users" from "anon";

revoke select on table "public"."directus_users" from "anon";

revoke trigger on table "public"."directus_users" from "anon";

revoke truncate on table "public"."directus_users" from "anon";

revoke update on table "public"."directus_users" from "anon";

revoke delete on table "public"."directus_webhooks" from "anon";

revoke insert on table "public"."directus_webhooks" from "anon";

revoke references on table "public"."directus_webhooks" from "anon";

revoke select on table "public"."directus_webhooks" from "anon";

revoke trigger on table "public"."directus_webhooks" from "anon";

revoke truncate on table "public"."directus_webhooks" from "anon";

revoke update on table "public"."directus_webhooks" from "anon";

alter sequence "public"."cannabis_strain_relations_id_seq" owned by "public"."posts_lists"."id";

alter sequence "public"."directus_activity_id_seq" owned by "public"."keys"."key";

alter sequence "public"."directus_fields_id_seq" owned by "public"."directus_panels"."id";

alter sequence "public"."directus_presets_id_seq" owned by "public"."post_tags"."id";

alter sequence "public"."directus_relations_id_seq" owned by "public"."posts_users"."id";

alter sequence "public"."directus_revisions_id_seq" owned by "public"."products_brands"."id";

alter sequence "public"."directus_settings_id_seq" owned by "public"."users"."name";

alter sequence "public"."lists_products_id_seq" owned by none;

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public._select_contest_winners()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  r record;
--   p record;
begin
  -- for g in select * from giveaways where selected_winner = false and end_time <= now() loop
  --   select * into p from select_giveaway_contest_winner(g.id); 
  -- end loop;
  SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/giveaway_winner',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('id', 'id')::jsonb
        )::http_request);
end;
$function$
;

CREATE OR REPLACE FUNCTION public._typesense_import()
 RETURNS void
 LANGUAGE plpgsql
AS $function$declare
 r record;
begin
--   select
--       http_post(
--           uri:='https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-import',
--           headers:='{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog"}'::jsonb
--       );
set statement_timeout to 600000;
SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
select * into r from http((
          'POST',
           'https://axzdfdpwfsynrajqqoae.functions.supabase.co/typesense-import',
           ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
           'application/json',
           jsonb_build_object('id', 'id')::jsonb
        )::http_request);
end;$function$
;

CREATE OR REPLACE FUNCTION public.get_feed_items(p_uid uuid)
 RETURNS uuid[]
 LANGUAGE plpgsql
AS $function$DECLARE
  post_ids uuid[];
  min_posts_needed CONSTANT int := 30; -- The number of posts you want to fetch
BEGIN
  -- Create a temporary table to hold all unseen post candidates.
  -- This is more efficient than running multiple large queries.
  CREATE TEMP TABLE unseen_posts AS
  SELECT p.id, p.date_created
  FROM posts AS p
  LEFT JOIN analytics_posts AS ap ON p.id = ap.post_id AND ap.user_id = p_uid
  LEFT JOIN user_blocks AS ub ON p.user_id = ub.block_id AND ub.user_id = p_uid
  WHERE p.file_id IS NOT NULL    -- Ensures it's a media post
    AND ap.post_id IS NULL       -- Filters out seen posts
    AND ub.block_id IS NULL;     -- Filters out blocked users

  -- Tier 1: Try to get posts from the last 1 month.
  SELECT array_agg(id) INTO post_ids FROM (
    SELECT id FROM unseen_posts
    WHERE date_created >= now() - interval '1 MONTH'
    ORDER BY random()
    LIMIT min_posts_needed
  ) as sub;

  -- If we found enough posts, return them.
  IF coalesce(array_length(post_ids, 1), 0) >= min_posts_needed THEN
    DROP TABLE unseen_posts;
    RETURN post_ids;
  END IF;

  -- Tier 2: If not, try to get posts from the last 3 months.
  SELECT array_agg(id) INTO post_ids FROM (
    SELECT id FROM unseen_posts
    WHERE date_created >= now() - interval '3 MONTH'
    ORDER BY random()
    LIMIT min_posts_needed
  ) as sub;

  IF coalesce(array_length(post_ids, 1), 0) >= min_posts_needed THEN
    DROP TABLE unseen_posts;
    RETURN post_ids;
  END IF;

  -- Tier 3: If not, try to get posts from the last 6 months.
  SELECT array_agg(id) INTO post_ids FROM (
    SELECT id FROM unseen_posts
    WHERE date_created >= now() - interval '6 MONTH'
    ORDER BY random()
    LIMIT min_posts_needed
  ) as sub;

  IF coalesce(array_length(post_ids, 1), 0) >= min_posts_needed THEN
    DROP TABLE unseen_posts;
    RETURN post_ids;
  END IF;

  -- Tier 4: If still not enough, get any posts regardless of date.
  SELECT array_agg(id) INTO post_ids FROM (
    SELECT id FROM unseen_posts
    ORDER BY random()
    LIMIT min_posts_needed
) as sub;

-- Clean up and return whatever was found.
DROP TABLE unseen_posts;
RETURN post_ids;

END;$function$
;

CREATE OR REPLACE FUNCTION public.notify_employee_of_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
 dispensary_name text;
 user_email text;
 r record;
BEGIN
-- Only proceed if is_approved changed to true
 IF (TG_OP = 'UPDATE' AND NEW.is_approved = true AND (OLD.is_approved IS NULL OR OLD.is_approved = false)) THEN
  -- Get the dispensary name
  SELECT name
  INTO dispensary_name
  FROM dispensary_locations
  WHERE id = NEW.dispensary_id;

  -- Get the user's email
  SELECT email
  INTO user_email
  FROM users
  WHERE id = NEW.user_id;

  -- Set timeout
  SELECT * into r from extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  
  -- Call the edge function
  SELECT * into r from http((
  'POST',
  'https://axzdfdpwfsynrajqqoae.supabase.co/functions/v1/employee_notification',
  ARRAY[http_header('Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4emRmZHB3ZnN5bnJhanFxb2FlIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NTQ2MTQ0OTEsImV4cCI6MTk3MDE5MDQ5MX0.9vkStVCE_NcsPvGA1ebkeS-rZ3YGku8_Y9UKeHutUog')],
  'application/json',
   jsonb_build_object(
  'id', NEW.user_id,
  'email', user_email,
  'name', dispensary_name
  )::jsonb
  )::http_request);
 END IF;
 RETURN NEW;
END;
$function$
;

CREATE TRIGGER trg_create_or_update_public_user AFTER INSERT OR DELETE OR UPDATE ON auth.users FOR EACH ROW EXECUTE FUNCTION public.fn_insert_update_or_delete_public_user_from_user();


  create policy "Enable insert for authenticated users only"
  on "storage"."objects"
  as permissive
  for insert
  to public
with check ((auth.role() = 'authenticated'::text));



