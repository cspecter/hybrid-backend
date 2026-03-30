-- ============================================================================
-- EXPORT OLD DATABASE DATA
-- Run this on your OLD Supabase database (axzdfdpwfsynrajqqoae)
-- ============================================================================
-- 
-- SCHEMA MAPPING:
-- - OLD DB uses UUID primary keys throughout
-- - NEW DB uses INTEGER primary keys with UUID public_id columns
-- - OLD UUID IDs will be stored as public_id in the new schema
-- 
-- TABLE RENAMES:
-- - users -> profiles
-- - dispensary_locations -> locations  
-- - dispensary_employees -> location_employees
-- - products_brands -> product_brands (note: old uses users_id, products_id)
-- - deals_dispensary_locations -> deals_locations
-- - user_blocks -> profile_blocks
-- - user_brand_admins -> profile_admins
-- - posts_users -> posts_profiles
-- 
-- COLUMN DIFFERENCES (OLD DB):
-- - likes: uses users_id, posts_id
-- - stash: uses users_id, products_id, has restash_* columns
-- - lists_products: uses lists_id, products_id
-- - posts_products: uses posts_id, products_id
-- - posts_hashtags: uses posts_id, post_tags_id
-- - lists: NO public/status/item_count - has user_id, product_count, subscription_count
-- - deals: NO name/discount_type - has percent_off, dollar_off, product_id
-- - giveaways: NO rules - has product_id, start_time, end_time, entry_count
-- - giveaway_entries: uses 'won' not 'is_winner', uses user_id, giveaway_id
-- ============================================================================

-- Clean up any previous export attempt
DROP SCHEMA IF EXISTS migration_export CASCADE;

-- Create a fresh schema for export staging
CREATE SCHEMA IF NOT EXISTS migration_export;

-- ============================================================================
-- UUID MAPPING TABLE
-- This maps old UUIDs to new integer IDs
-- ============================================================================

CREATE TABLE migration_export.uuid_to_int_mapping (
    table_name text NOT NULL,
    old_uuid uuid NOT NULL,
    new_int_id integer NOT NULL,
    PRIMARY KEY (table_name, old_uuid)
);

CREATE INDEX idx_uuid_mapping_lookup ON migration_export.uuid_to_int_mapping(table_name, old_uuid);

-- ============================================================================
-- EXPORT AUTH.USERS (Critical - includes passwords/auth)
-- ============================================================================

CREATE TABLE migration_export.auth_users AS
SELECT 
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    invited_at,
    confirmation_token,
    confirmation_sent_at,
    recovery_token,
    recovery_sent_at,
    email_change_token_new,
    email_change,
    email_change_sent_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    created_at,
    updated_at,
    phone,
    phone_confirmed_at,
    phone_change,
    phone_change_token,
    phone_change_sent_at,
    email_change_token_current,
    email_change_confirm_status,
    banned_until,
    reauthentication_token,
    reauthentication_sent_at,
    is_sso_user,
    deleted_at
FROM auth.users;

-- ============================================================================
-- EXPORT AUTH.IDENTITIES
-- ============================================================================

CREATE TABLE migration_export.auth_identities AS
SELECT * FROM auth.identities;

-- ============================================================================
-- EXPORT PROFILES (from users table)
-- OLD: users.id is UUID
-- NEW: profiles.id is INTEGER, public_id is the old UUID
-- ============================================================================

CREATE TABLE migration_export.profiles AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    id as auth_id,
    CASE 
        WHEN role_id IN (1, 2, 3, 4, 5) THEN 'brand'::text
        ELSE 'individual'::text
    END as profile_type,
    username,
    name as display_name,
    slug,
    email,
    phone,
    description as bio,
    profile_picture_id as original_avatar_uuid,
    banner_id as original_banner_uuid,
    website,
    role_id,
    status,
    verified as is_verified,
    is_private,
    CASE 
        WHEN role_id IN (1, 2, 3, 4, 5) THEN jsonb_build_object(
            'migrated_from_old_db', true,
            'original_role_id', role_id
        )
        ELSE NULL
    END as business_info,
    jsonb_build_object(
        'instagram', instagram,
        'twitter', twitter,
        'facebook', facebook,
        'youtube', youtube,
        'linkedin', linkedin,
        'tiktok', tiktok
    ) as social_links,
    follower_count,
    following_count,
    post_count,
    product_count,
    like_count,
    stash_count,
    0 as location_count,
    date_created as created_at,
    date_updated as updated_at,
    fts_vector as fts,
    home_location as original_home_location_uuid
FROM public.users;

-- Store profile UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'profiles', public_id, new_id FROM migration_export.profiles;

-- ============================================================================
-- EXPORT LOCATIONS (from dispensary_locations)
-- OLD: dispensary_locations.id is UUID
-- NEW: locations.id is INTEGER, public_id is the old UUID
-- ============================================================================

CREATE TABLE migration_export.locations AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    name,
    slug,
    address1 as address_line1,
    address2 as address_line2,
    NULL::text as city,
    NULL::text as state,
    postal_code_id,
    'US' as country,
    (contact_info->>'phone')::text as phone,
    (contact_info->>'email')::text as email,
    (contact_info->>'website')::text as website,
    about_us as description,
    operating_hours,
    location as coordinates,
    brand_id as original_brand_uuid,
    is_recreational,
    is_medical,
    has_delivery,
    has_pickup,
    has_storefront,
    verified as is_verified,
    claimed as is_claimed,
    status,
    region_id,
    jsonb_build_object(
        'amenities', COALESCE((
            SELECT jsonb_agg(x) FROM (
                SELECT 'atm' WHERE has_atm
                UNION ALL SELECT 'security' WHERE has_security_guard
                UNION ALL SELECT 'wheelchair_accessible' WHERE has_handicap_access
                UNION ALL SELECT 'lab_tested' WHERE has_lab_measured_items
            ) t(x)
        ), '[]'::jsonb),
        'services', COALESCE((
            SELECT jsonb_agg(x) FROM (
                SELECT 'delivery' WHERE has_delivery
                UNION ALL SELECT 'pickup' WHERE has_pickup
                UNION ALL SELECT 'curbside' WHERE has_curbside_pickup
                UNION ALL SELECT 'storefront' WHERE has_storefront
            ) t(x)
        ), '[]'::jsonb),
        'payment', COALESCE((
            SELECT jsonb_agg(x) FROM (
                SELECT 'credit' WHERE accepts_credit_cards
            ) t(x)
        ), '[]'::jsonb),
        'license_types', COALESCE((
            SELECT jsonb_agg(x) FROM (
                SELECT 'medical' WHERE is_medical
                UNION ALL SELECT 'recreational' WHERE is_recreational
            ) t(x)
        ), '[]'::jsonb),
        'certifications', COALESCE((
            SELECT jsonb_agg(x) FROM (
                SELECT 'social_equity' WHERE social_equity
            ) t(x)
        ), '[]'::jsonb)
    ) as features,
    jsonb_build_object(
        'instagram', contact_info->>'instagram',
        'twitter', contact_info->>'twitter'
    ) as social_links,
    banner_id as original_banner_uuid,
    NULL::uuid as original_logo_uuid,  -- logo_id doesn't exist in old schema
    date_created as created_at,
    date_updated as updated_at,
    fts_vector as fts
FROM public.dispensary_locations;

-- Store location UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'locations', public_id, new_id FROM migration_export.locations;

-- ============================================================================
-- EXPORT PRODUCTS
-- OLD: products.id is UUID
-- NEW: products.id is INTEGER, public_id is the old UUID
-- ============================================================================

CREATE TABLE migration_export.products AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    name,
    slug,
    description,
    category_id as original_category_uuid,
    status,
    verified as is_verified,
    stash_count,
    post_count,
    price,
    release_date,
    url,
    thumbnail_id as original_thumbnail_uuid,
    cover_id as original_cover_uuid,
    date_created as created_at,
    date_updated as updated_at,
    fts_vector as fts
FROM public.products;

-- Store product UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'products', public_id, new_id FROM migration_export.products;

-- ============================================================================
-- EXPORT POSTS
-- OLD: posts.id is UUID, uses user_id, file_id, location_id
-- NEW: posts.id is INTEGER, uses profile_id
-- ============================================================================

CREATE TABLE migration_export.posts AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    message,
    status,
    pinned,
    promoted,
    flagged,
    approval_only,
    like_count,
    view_count,
    share_count,
    flag_count,
    total_watch_time,
    average_watch_time,
    watched_in_full_count,
    reach_count,
    user_id as original_profile_uuid,
    file_id as original_file_uuid,
    location_id,
    geotag,
    url,
    has_file,
    live_time,
    fts_vector as fts,
    date_created as created_at,
    date_updated as updated_at
FROM public.posts;

-- Store post UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'posts', public_id, new_id FROM migration_export.posts;

-- ============================================================================
-- EXPORT LISTS
-- OLD: lists.id is UUID, uses user_id
-- NEW: lists.id is INTEGER, uses profile_id
-- Note: Old lists has: id, name, description, product_count, user_id, base,
--       thumbnail_id, background_id, sort, subscription_count
-- ============================================================================

CREATE TABLE migration_export.lists AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    name,
    description,
    user_id as original_profile_uuid,
    product_count,
    subscription_count,
    base,
    thumbnail_id as original_thumbnail_uuid,
    background_id as original_background_uuid,
    sort,
    fts_vector as fts,
    date_created as created_at,
    date_updated as updated_at
FROM public.lists;

-- Store list UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'lists', public_id, new_id FROM migration_export.lists;

-- ============================================================================
-- EXPORT DEALS
-- OLD: deals.id is UUID, uses product_id
-- NEW: deals.id is INTEGER
-- Note: Old deals has: id, product_id, expiration_date, release_date,
--       percent_off, dollar_off, bogo_percent_off, bogo_dollar_off,
--       total_deals, claimed_deals, expired, conditions, header_message,
--       description, is_medical, is_recreational
-- ============================================================================

CREATE TABLE migration_export.deals AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    product_id as original_product_uuid,
    expiration_date,
    release_date,
    percent_off,
    dollar_off,
    bogo_percent_off,
    bogo_dollar_off,
    total_deals,
    claimed_deals,
    expired,
    conditions,
    header_message,
    description,
    is_medical,
    is_recreational,
    date_created as created_at,
    date_updated as updated_at
FROM public.deals;

-- Store deal UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'deals', public_id, new_id FROM migration_export.deals;

-- ============================================================================
-- EXPORT GIVEAWAYS
-- OLD: giveaways.id is UUID, uses product_id, cover_id
-- NEW: giveaways.id is INTEGER
-- Note: Old giveaways has: id, product_id, cover_id, name, description,
--       start_time, end_time, total_prizes, terms_url, selected_winner,
--       redeemed, entry_count, winner_count
-- ============================================================================

CREATE TABLE migration_export.giveaways AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    product_id as original_product_uuid,
    cover_id as original_cover_uuid,
    name,
    description,
    start_time,
    end_time,
    total_prizes,
    terms_url,
    selected_winner,
    redeemed,
    entry_count,
    winner_count,
    fts_vector as fts,
    date_created as created_at,
    date_updated as updated_at
FROM public.giveaways;

-- Store giveaway UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'giveaways', public_id, new_id FROM migration_export.giveaways;

-- ============================================================================
-- EXPORT NOTIFICATIONS
-- OLD: notifications.id is UUID, uses user_id, actor_id, post_id, product_id, etc
-- NEW: notifications.id is INTEGER, uses profile_id, actor_id (as integers)
-- Note: Old notifications has: id, user_id, message, read, actor_id,
--       post_id, product_id, giveaway_id, list_id, type_id, image_url
-- ============================================================================

CREATE TABLE migration_export.notifications AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    user_id as original_profile_uuid,
    type_id,
    message as title,
    message as body,
    image_url,
    NULL as action_url,
    actor_id as original_actor_uuid,
    CASE 
        WHEN post_id IS NOT NULL THEN 'post'
        WHEN product_id IS NOT NULL THEN 'product'
        WHEN giveaway_id IS NOT NULL THEN 'giveaway'
        WHEN list_id IS NOT NULL THEN 'list'
        ELSE NULL
    END as related_type,
    COALESCE(post_id, product_id, giveaway_id, list_id) as original_related_uuid,
    jsonb_build_object(
        'post_id', post_id,
        'product_id', product_id,
        'giveaway_id', giveaway_id,
        'list_id', list_id
    ) as data,
    NULL as group_key,
    read as is_read,
    CASE WHEN read THEN date_updated ELSE NULL END as read_at,
    date_created as created_at
FROM public.notifications;

-- Store notification UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'notifications', public_id, new_id FROM migration_export.notifications;

-- ============================================================================
-- EXPORT LOCATION_EMPLOYEES (from dispensary_employees)
-- OLD: uses dispensary_id, user_id as UUIDs
-- NEW: uses location_id, profile_id as integers
-- ============================================================================

CREATE TABLE migration_export.location_employees AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    dispensary_id as original_location_uuid,
    user_id as original_profile_uuid,
    CASE WHEN is_admin THEN 'manager' ELSE 'staff' END as role,
    is_approved,
    has_been_reviewed,
    date_created as created_at,
    date_modified as updated_at
FROM public.dispensary_employees;

-- ============================================================================
-- EXPORT PRODUCT_BRANDS (from products_brands)
-- OLD: uses products_id, users_id as UUIDs
-- NEW: uses product_id, brand_id as integers
-- ============================================================================

CREATE TABLE migration_export.product_brands AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY id)::integer as new_id,
    products_id as original_product_uuid,
    users_id as original_brand_uuid,
    now() as created_at
FROM public.products_brands;

-- ============================================================================
-- EXPORT RELATED_PRODUCTS (from products_products)
-- OLD: uses products_id, related_products_id as UUIDs
-- NEW: uses product_id, related_product_id as integers
-- ============================================================================

-- Note: products_products table doesn't exist in old DB, create empty table structure
CREATE TABLE migration_export.related_products (
    new_id integer,
    original_product_uuid uuid,
    original_related_product_uuid uuid,
    created_at timestamptz
);
-- No data to insert

-- ============================================================================
-- EXPORT DEALS_LOCATIONS (from deals_dispensary_locations)
-- OLD: uses deals_id, dispensary_locations_id as UUIDs
-- NEW: uses deal_id, location_id as integers
-- ============================================================================

CREATE TABLE migration_export.deals_locations AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY id)::integer as new_id,
    deals_id as original_deal_uuid,
    dispensary_locations_id as original_location_uuid
FROM public.deals_dispensary_locations;

-- ============================================================================
-- EXPORT PROFILE_ADMINS (from user_brand_admins)
-- OLD: uses user_id, brand_id as UUIDs
-- NEW: uses admin_profile_id, managed_profile_id as integers
-- ============================================================================

CREATE TABLE migration_export.profile_admins AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY id)::integer as new_id,
    user_id as original_admin_uuid,
    brand_id as original_managed_uuid,
    now() as created_at
FROM public.user_brand_admins;

-- ============================================================================
-- EXPORT PROFILE_BLOCKS (from user_blocks)
-- OLD: uses user_id, block_id as UUIDs
-- NEW: uses profile_id, blocked_profile_id as integers
-- ============================================================================

CREATE TABLE migration_export.profile_blocks AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    user_id as original_blocker_uuid,
    block_id as original_blocked_uuid,
    date_created as created_at
FROM public.user_blocks;

-- ============================================================================
-- EXPORT RELATIONSHIPS
-- OLD: uses follower_id, followee_id as UUIDs
-- NEW: uses follower_id, followee_id as integers
-- ============================================================================

CREATE TABLE migration_export.relationships AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    follower_id as original_follower_uuid,
    followee_id as original_followee_uuid,
    role_id,
    date_created as created_at,
    date_updated as updated_at
FROM public.relationships;

-- ============================================================================
-- EXPORT POSTS_PROFILES (from posts_users)
-- OLD: uses posts_id, users_id as UUIDs
-- NEW: uses post_id, profile_id as integers
-- ============================================================================

CREATE TABLE migration_export.posts_profiles AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    post_id as original_post_uuid,
    user_id as original_profile_uuid,
    date_created as created_at,
    date_updated as updated_at
FROM public.posts_users;

-- ============================================================================
-- EXPORT POSTS_PRODUCTS
-- OLD: uses posts_id, products_id as UUIDs
-- NEW: uses post_id, product_id as integers
-- ============================================================================

CREATE TABLE migration_export.posts_products AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    posts_id as original_post_uuid,
    products_id as original_product_uuid,
    date_created as created_at
FROM public.posts_products;

-- ============================================================================
-- EXPORT POSTS_HASHTAGS
-- OLD: uses posts_id as UUID, post_tags_id as integer
-- NEW: uses post_id as integer, post_tag_id as integer
-- ============================================================================

CREATE TABLE migration_export.posts_hashtags AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    posts_id as original_post_uuid,
    post_tags_id as post_tag_id,
    date_created as created_at,
    date_updated as updated_at
FROM public.posts_hashtags;

-- ============================================================================
-- EXPORT POSTS_LISTS
-- OLD: uses post_id, list_id as UUIDs
-- NEW: uses post_id, list_id as integers
-- ============================================================================

CREATE TABLE migration_export.posts_lists AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    post_id as original_post_uuid,
    list_id as original_list_uuid,
    date_created as created_at,
    date_updated as updated_at
FROM public.posts_lists;

-- ============================================================================
-- EXPORT LISTS_PRODUCTS
-- OLD: uses lists_id, products_id as UUIDs
-- NEW: uses list_id, product_id as integers
-- ============================================================================

CREATE TABLE migration_export.lists_products AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    lists_id as original_list_uuid,
    products_id as original_product_uuid,
    date_created as created_at
FROM public.lists_products;

-- ============================================================================
-- EXPORT LIKES
-- OLD: uses users_id, posts_id as UUIDs
-- NEW: uses profile_id, post_id as integers
-- ============================================================================

CREATE TABLE migration_export.likes AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    users_id as original_profile_uuid,
    posts_id as original_post_uuid,
    date_created as created_at,
    date_updated as updated_at
FROM public.likes;

-- ============================================================================
-- EXPORT STASH
-- OLD: uses users_id, products_id as UUIDs, has restash_* columns
-- NEW: uses profile_id, product_id as integers
-- ============================================================================

CREATE TABLE migration_export.stash AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    users_id as original_profile_uuid,
    products_id as original_product_uuid,
    restash_id as original_restash_uuid,
    restash_list_id as original_restash_list_uuid,
    restash_post_id as original_restash_post_uuid,
    restash_profile_id as original_restash_profile_uuid,
    date_created as created_at,
    date_updated as updated_at
FROM public.stash;

-- ============================================================================
-- EXPORT GIVEAWAY_ENTRIES
-- OLD: uses user_id, giveaway_id as UUIDs, column is 'won' not 'is_winner'
-- NEW: uses profile_id, giveaway_id as integers
-- ============================================================================

CREATE TABLE migration_export.giveaway_entries AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    user_id as original_profile_uuid,
    giveaway_id as original_giveaway_uuid,
    won,
    sent,
    shipping_notes,
    date_created as created_at,
    date_updated as updated_at
FROM public.giveaway_entries;

-- Store giveaway_entry UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'giveaway_entries', public_id, new_id FROM migration_export.giveaway_entries;

-- ============================================================================
-- EXPORT GIVEAWAY_ENTRIES_MESSAGES
-- OLD: uses user_id, giveaway_entry_id as UUIDs
-- NEW: uses profile_id, giveaway_entry_id as integers
-- ============================================================================

CREATE TABLE migration_export.giveaway_entries_messages AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    user_id as original_profile_uuid,
    giveaway_entry_id as original_giveaway_entry_uuid,
    message,
    date_created as created_at,
    date_updated as updated_at
FROM public.giveaway_entries_messages;

-- ============================================================================
-- EXPORT SUBSCRIPTIONS_LISTS
-- OLD: uses user_id, list_id as UUIDs
-- NEW: uses profile_id, list_id as integers
-- ============================================================================

CREATE TABLE migration_export.subscriptions_lists AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    user_id as original_profile_uuid,
    list_id as original_list_uuid,
    date_created as created_at,
    date_updated as updated_at
FROM public.subscriptions_lists;

-- ============================================================================
-- EXPORT REFERENCE TABLES (already have integer IDs - copy directly)
-- ============================================================================

CREATE TABLE migration_export.roles AS SELECT * FROM public.roles;
CREATE TABLE migration_export.states AS SELECT * FROM public.states;
CREATE TABLE migration_export.regions AS SELECT * FROM public.regions;
CREATE TABLE migration_export.postal_codes AS SELECT * FROM public.postal_codes;
CREATE TABLE migration_export.region_postal_codes AS SELECT * FROM public.region_postal_codes;
CREATE TABLE migration_export.product_categories AS 
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as public_id,
    name,
    slug,
    description,
    parent_id as original_parent_uuid,
    image_id as original_image_uuid,
    product_count,
    COALESCE(hidden, false) as hidden,
    date_created as created_at,
    date_updated as updated_at
FROM public.product_categories;

-- Store product_category UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'product_categories', public_id, new_id FROM migration_export.product_categories;
CREATE TABLE migration_export.product_features AS SELECT * FROM public.product_features;
CREATE TABLE migration_export.product_feature_types AS SELECT * FROM public.product_feature_types;
CREATE TABLE migration_export.notification_types AS SELECT * FROM public.notification_types;
CREATE TABLE migration_export.post_tags AS SELECT * FROM public.post_tags;

-- ============================================================================
-- EXPORT CLOUD FILES
-- OLD: cloud_files.id is UUID
-- NEW: cloud_files.id is INTEGER, public_id is the old UUID
-- ============================================================================

CREATE TABLE migration_export.cloud_files AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY date_created, id)::integer as new_id,
    id as old_uuid,
    public_id as cloudinary_id,
    signature,
    format,
    resource_type,
    width,
    height,
    url,
    secure_url,
    asset_id,
    user_id as original_profile_uuid,
    date_created as created_at,
    date_updated as updated_at
FROM public.cloud_files;

-- Store cloud_file UUID to INT mapping
INSERT INTO migration_export.uuid_to_int_mapping (table_name, old_uuid, new_int_id)
SELECT 'cloud_files', old_uuid, new_id FROM migration_export.cloud_files;

-- ============================================================================
-- EXPORT GIVEAWAYS_REGIONS (already has integer IDs)
-- ============================================================================

CREATE TABLE migration_export.giveaways_regions AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY id)::integer as new_id,
    giveaway_id as original_giveaway_uuid,
    region_id
FROM public.giveaways_regions;

-- ============================================================================
-- EXPORT EXPLORE TABLES (already have integer IDs)
-- ============================================================================

CREATE TABLE migration_export.explore AS 
SELECT 
    id,
    date_created,
    date_updated,
    name,
    description,
    thumbnail_id as original_thumbnail_uuid,
    start_date,
    end_date,
    "default",
    slug
FROM public.explore;
CREATE TABLE migration_export.explore_page AS SELECT * FROM public.explore_page;
CREATE TABLE migration_export.explore_trending AS SELECT * FROM public.explore_trending;

-- ============================================================================
-- VERIFY EXPORT - Show row counts
-- ============================================================================

SELECT 'UUID Mappings' as table_name, COUNT(*) as count FROM migration_export.uuid_to_int_mapping
UNION ALL SELECT 'auth_users', COUNT(*) FROM migration_export.auth_users
UNION ALL SELECT 'profiles', COUNT(*) FROM migration_export.profiles
UNION ALL SELECT 'locations', COUNT(*) FROM migration_export.locations
UNION ALL SELECT 'products', COUNT(*) FROM migration_export.products
UNION ALL SELECT 'posts', COUNT(*) FROM migration_export.posts
UNION ALL SELECT 'lists', COUNT(*) FROM migration_export.lists
UNION ALL SELECT 'deals', COUNT(*) FROM migration_export.deals
UNION ALL SELECT 'giveaways', COUNT(*) FROM migration_export.giveaways
UNION ALL SELECT 'notifications', COUNT(*) FROM migration_export.notifications
UNION ALL SELECT 'relationships', COUNT(*) FROM migration_export.relationships
UNION ALL SELECT 'likes', COUNT(*) FROM migration_export.likes
UNION ALL SELECT 'stash', COUNT(*) FROM migration_export.stash
UNION ALL SELECT 'giveaway_entries', COUNT(*) FROM migration_export.giveaway_entries
UNION ALL SELECT 'cloud_files', COUNT(*) FROM migration_export.cloud_files
UNION ALL SELECT 'posts_products', COUNT(*) FROM migration_export.posts_products
UNION ALL SELECT 'posts_hashtags', COUNT(*) FROM migration_export.posts_hashtags
UNION ALL SELECT 'lists_products', COUNT(*) FROM migration_export.lists_products
UNION ALL SELECT 'product_brands', COUNT(*) FROM migration_export.product_brands
ORDER BY table_name;

-- ============================================================================
-- GENERATE EXPORT COMMANDS
-- ============================================================================

-- After running this script, use pg_dump to export the migration_export schema:
-- pg_dump -h <old-host> -U postgres -d postgres -n migration_export -F c -f migration_export.dump
