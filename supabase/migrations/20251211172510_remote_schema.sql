drop extension if exists "pg_net";

create schema if not exists "migration_export";


  create table "migration_export"."auth_identities" (
    "provider_id" text,
    "user_id" uuid,
    "identity_data" jsonb,
    "provider" text,
    "last_sign_in_at" timestamp with time zone,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "email" text,
    "id" uuid
      );



  create table "migration_export"."auth_users" (
    "id" uuid,
    "instance_id" uuid,
    "aud" character varying(255),
    "role" character varying(255),
    "email" character varying(255),
    "encrypted_password" character varying(255),
    "email_confirmed_at" timestamp with time zone,
    "invited_at" timestamp with time zone,
    "confirmation_token" character varying(255),
    "confirmation_sent_at" timestamp with time zone,
    "recovery_token" character varying(255),
    "recovery_sent_at" timestamp with time zone,
    "email_change_token_new" character varying(255),
    "email_change" character varying(255),
    "email_change_sent_at" timestamp with time zone,
    "last_sign_in_at" timestamp with time zone,
    "raw_app_meta_data" jsonb,
    "raw_user_meta_data" jsonb,
    "is_super_admin" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "phone" text,
    "phone_confirmed_at" timestamp with time zone,
    "phone_change" text,
    "phone_change_token" character varying(255),
    "phone_change_sent_at" timestamp with time zone,
    "email_change_token_current" character varying(255),
    "email_change_confirm_status" smallint,
    "banned_until" timestamp with time zone,
    "reauthentication_token" character varying(255),
    "reauthentication_sent_at" timestamp with time zone,
    "is_sso_user" boolean,
    "deleted_at" timestamp with time zone
      );



  create table "migration_export"."cloud_files" (
    "new_id" integer,
    "old_uuid" uuid,
    "cloudinary_id" character varying(255),
    "signature" character varying(255),
    "format" character varying(255),
    "resource_type" character varying(255),
    "width" integer,
    "height" integer,
    "url" character varying(255),
    "secure_url" character varying(255),
    "asset_id" character varying(255),
    "original_profile_uuid" uuid,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."deals" (
    "new_id" integer,
    "public_id" uuid,
    "original_product_uuid" uuid,
    "expiration_date" timestamp without time zone,
    "release_date" timestamp without time zone,
    "percent_off" real,
    "dollar_off" real,
    "bogo_percent_off" numeric(10,5),
    "bogo_dollar_off" real,
    "total_deals" integer,
    "claimed_deals" integer,
    "expired" boolean,
    "conditions" text,
    "header_message" character varying(60),
    "description" text,
    "is_medical" boolean,
    "is_recreational" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."deals_locations" (
    "new_id" integer,
    "original_deal_uuid" uuid,
    "original_location_uuid" uuid
      );



  create table "migration_export"."explore" (
    "id" integer,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone,
    "name" character varying(255),
    "description" text,
    "original_thumbnail_uuid" uuid,
    "start_date" timestamp without time zone,
    "end_date" timestamp without time zone,
    "default" boolean,
    "slug" character varying(255)
      );



  create table "migration_export"."explore_page" (
    "id" integer,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone
      );



  create table "migration_export"."explore_trending" (
    "id" integer,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone,
    "name" character varying(255)
      );



  create table "migration_export"."giveaway_entries" (
    "new_id" integer,
    "public_id" uuid,
    "original_profile_uuid" uuid,
    "original_giveaway_uuid" uuid,
    "won" boolean,
    "sent" boolean,
    "shipping_notes" text,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."giveaway_entries_messages" (
    "new_id" integer,
    "public_id" uuid,
    "original_profile_uuid" uuid,
    "original_giveaway_entry_uuid" uuid,
    "message" text,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."giveaways" (
    "new_id" integer,
    "public_id" uuid,
    "original_product_uuid" uuid,
    "original_cover_uuid" uuid,
    "name" character varying(255),
    "description" text,
    "start_time" timestamp with time zone,
    "end_time" timestamp with time zone,
    "total_prizes" integer,
    "terms_url" character varying(255),
    "selected_winner" boolean,
    "redeemed" boolean,
    "entry_count" integer,
    "winner_count" integer,
    "fts" tsvector,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."giveaways_regions" (
    "new_id" integer,
    "original_giveaway_uuid" uuid,
    "region_id" integer
      );



  create table "migration_export"."likes" (
    "new_id" integer,
    "original_profile_uuid" uuid,
    "original_post_uuid" uuid,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."lists" (
    "new_id" integer,
    "public_id" uuid,
    "name" character varying(255),
    "description" text,
    "original_profile_uuid" uuid,
    "product_count" integer,
    "subscription_count" integer,
    "base" boolean,
    "original_thumbnail_uuid" uuid,
    "original_background_uuid" uuid,
    "sort" uuid[],
    "fts" tsvector,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."lists_products" (
    "new_id" integer,
    "original_list_uuid" uuid,
    "original_product_uuid" uuid,
    "created_at" timestamp with time zone
      );



  create table "migration_export"."location_employees" (
    "new_id" integer,
    "public_id" bigint,
    "original_location_uuid" uuid,
    "original_profile_uuid" uuid,
    "role" text,
    "is_approved" boolean,
    "has_been_reviewed" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."locations" (
    "new_id" integer,
    "public_id" uuid,
    "name" character varying(255),
    "slug" character varying(255),
    "address_line1" character varying(255),
    "address_line2" character varying(255),
    "city" text,
    "state" text,
    "postal_code_id" integer,
    "country" text,
    "phone" text,
    "email" text,
    "website" text,
    "description" text,
    "operating_hours" json,
    "coordinates" extensions.geometry(Point,4326),
    "original_brand_uuid" uuid,
    "is_recreational" boolean,
    "is_medical" boolean,
    "has_delivery" boolean,
    "has_pickup" boolean,
    "has_storefront" boolean,
    "is_verified" boolean,
    "is_claimed" boolean,
    "status" character varying(255),
    "region_id" integer,
    "features" jsonb,
    "social_links" jsonb,
    "original_banner_uuid" uuid,
    "original_logo_uuid" uuid,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "fts" tsvector
      );



  create table "migration_export"."notification_types" (
    "id" integer,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone,
    "name" character varying(255),
    "message_template_count" integer,
    "default_push_setting" boolean,
    "run_time" integer,
    "message" text,
    "can_push" boolean,
    "title" text,
    "description" text
      );



  create table "migration_export"."notifications" (
    "new_id" integer,
    "public_id" uuid,
    "original_profile_uuid" uuid,
    "type_id" integer,
    "title" character varying(255),
    "body" character varying(255),
    "image_url" text,
    "action_url" text,
    "original_actor_uuid" uuid,
    "related_type" text,
    "original_related_uuid" uuid,
    "data" jsonb,
    "group_key" text,
    "is_read" boolean,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone
      );



  create table "migration_export"."post_tags" (
    "id" integer,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone,
    "tag" character varying(255),
    "count" integer
      );



  create table "migration_export"."postal_codes" (
    "id" integer,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone,
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
    "geom" extensions.geometry
      );



  create table "migration_export"."posts" (
    "new_id" integer,
    "public_id" uuid,
    "message" text,
    "status" character varying(255),
    "pinned" boolean,
    "promoted" boolean,
    "flagged" boolean,
    "approval_only" boolean,
    "like_count" integer,
    "view_count" integer,
    "share_count" integer,
    "flag_count" integer,
    "total_watch_time" integer,
    "average_watch_time" integer,
    "watched_in_full_count" integer,
    "reach_count" integer,
    "original_profile_uuid" uuid,
    "original_file_uuid" uuid,
    "location_id" integer,
    "geotag" extensions.geometry(Point,4326),
    "url" character varying(255),
    "has_file" boolean,
    "live_time" timestamp with time zone,
    "fts" tsvector,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."posts_hashtags" (
    "new_id" integer,
    "original_post_uuid" uuid,
    "post_tag_id" integer,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."posts_lists" (
    "new_id" integer,
    "original_post_uuid" uuid,
    "original_list_uuid" uuid,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."posts_products" (
    "new_id" integer,
    "original_post_uuid" uuid,
    "original_product_uuid" uuid,
    "created_at" timestamp with time zone
      );



  create table "migration_export"."posts_profiles" (
    "new_id" integer,
    "original_post_uuid" uuid,
    "original_profile_uuid" uuid,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."product_brands" (
    "new_id" integer,
    "original_product_uuid" uuid,
    "original_brand_uuid" uuid,
    "created_at" timestamp with time zone
      );



  create table "migration_export"."product_categories" (
    "new_id" integer,
    "public_id" uuid,
    "name" character varying(255),
    "slug" character varying(255),
    "description" character varying(255),
    "original_parent_uuid" uuid,
    "original_image_uuid" uuid,
    "product_count" integer,
    "hidden" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."product_feature_types" (
    "id" integer,
    "name" character varying(255)
      );



  create table "migration_export"."product_features" (
    "id" integer,
    "name" character varying(255),
    "type_id" integer
      );



  create table "migration_export"."products" (
    "new_id" integer,
    "public_id" uuid,
    "name" character varying(255),
    "slug" character varying(255),
    "description" text,
    "original_category_uuid" uuid,
    "status" character varying(255),
    "is_verified" boolean,
    "stash_count" integer,
    "post_count" integer,
    "price" real,
    "url" text,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "fts" tsvector
      );



  create table "migration_export"."profile_admins" (
    "new_id" integer,
    "original_admin_uuid" uuid,
    "original_managed_uuid" uuid,
    "created_at" timestamp with time zone
      );



  create table "migration_export"."profile_blocks" (
    "new_id" integer,
    "original_blocker_uuid" uuid,
    "original_blocked_uuid" uuid,
    "created_at" timestamp with time zone
      );



  create table "migration_export"."profiles" (
    "new_id" integer,
    "public_id" uuid,
    "auth_id" uuid,
    "profile_type" text,
    "username" character varying(255),
    "display_name" character varying(255),
    "slug" text,
    "email" character varying(255),
    "phone" character varying(255),
    "bio" text,
    "original_avatar_uuid" uuid,
    "original_banner_uuid" uuid,
    "website" character varying(255),
    "role_id" integer,
    "status" text,
    "is_verified" boolean,
    "is_private" boolean,
    "business_info" jsonb,
    "follower_count" integer,
    "following_count" integer,
    "post_count" integer,
    "product_count" integer,
    "like_count" integer,
    "stash_count" integer,
    "location_count" integer,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "fts" tsvector,
    "original_home_location_uuid" character varying(255)
      );



  create table "migration_export"."region_postal_codes" (
    "id" integer,
    "region_id" integer,
    "postal_code_id" integer
      );



  create table "migration_export"."regions" (
    "id" integer,
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone,
    "name" character varying(255)
      );



  create table "migration_export"."related_products" (
    "new_id" integer,
    "original_product_uuid" uuid,
    "original_related_product_uuid" uuid,
    "created_at" timestamp with time zone
      );



  create table "migration_export"."relationships" (
    "new_id" integer,
    "original_follower_uuid" uuid,
    "original_followee_uuid" uuid,
    "role_id" integer,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."roles" (
    "id" integer,
    "role" character varying(255),
    "date_created" timestamp with time zone,
    "date_updated" timestamp with time zone
      );



  create table "migration_export"."stash" (
    "new_id" integer,
    "original_profile_uuid" uuid,
    "original_product_uuid" uuid,
    "original_restash_uuid" uuid,
    "original_restash_list_uuid" uuid,
    "original_restash_post_uuid" uuid,
    "original_restash_profile_uuid" uuid,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."states" (
    "id" integer,
    "abbr" text,
    "name" text,
    "date_created" timestamp without time zone,
    "date_updated" timestamp without time zone
      );



  create table "migration_export"."subscriptions_lists" (
    "new_id" integer,
    "original_profile_uuid" uuid,
    "original_list_uuid" uuid,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
      );



  create table "migration_export"."uuid_to_int_mapping" (
    "table_name" text not null,
    "old_uuid" uuid not null,
    "new_int_id" integer not null
      );


CREATE INDEX idx_uuid_mapping_lookup ON migration_export.uuid_to_int_mapping USING btree (table_name, old_uuid);

CREATE UNIQUE INDEX uuid_to_int_mapping_pkey ON migration_export.uuid_to_int_mapping USING btree (table_name, old_uuid);

alter table "migration_export"."uuid_to_int_mapping" add constraint "uuid_to_int_mapping_pkey" PRIMARY KEY using index "uuid_to_int_mapping_pkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION migration_export.resolve_uuid(p_table_name text, p_uuid uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT new_int_id 
    FROM migration_export.uuid_to_int_mapping 
    WHERE table_name = p_table_name AND old_uuid = p_uuid;
$function$
;


