-- ============================================================================
-- IMPORT DATA TO NEW DATABASE
-- Run this on your NEW Supabase database AFTER running migrations
-- ============================================================================
--
-- PREREQUISITES:
-- 1. Run all migrations first (supabase db reset)
-- 2. Restore the migration_export schema from the old database dump:
--    pg_restore -h <new-host> -U postgres -d postgres migration_export.dump
--
-- NEW SCHEMA CHANGES:
-- - All tables now use INTEGER primary keys (auto-incrementing)
-- - OLD UUID IDs are stored as public_id
-- - Uses uuid_to_int_mapping table to resolve foreign key references
--
-- IMPORT STRATEGY:
-- 1. Insert base records with NULLs for foreign keys that might cause circular dependencies
--    (especially media/cloud_files references)
-- 2. Insert Cloud Files (referencing base records)
-- 3. Update base records to link to Cloud Files
-- ============================================================================

-- ============================================================================
-- STEP 0: CLEAN UP EXISTING DATA (for re-runs)
-- This ensures we can re-run the migration without duplicate key errors
-- ============================================================================

-- Delete data in reverse dependency order (junction tables first, then entities)
TRUNCATE public.giveaway_entries_messages CASCADE;
TRUNCATE public.giveaway_entries CASCADE;
TRUNCATE public.giveaways_regions CASCADE;
TRUNCATE public.subscriptions_lists CASCADE;
TRUNCATE public.lists_products CASCADE;
TRUNCATE public.posts_profiles CASCADE;
TRUNCATE public.posts_products CASCADE;
TRUNCATE public.posts_hashtags CASCADE;
TRUNCATE public.posts_lists CASCADE;
TRUNCATE public.likes CASCADE;
TRUNCATE public.stash CASCADE;
TRUNCATE public.deals_locations CASCADE;
TRUNCATE public.product_brands CASCADE;
TRUNCATE public.related_products CASCADE;
TRUNCATE public.profile_admins CASCADE;
TRUNCATE public.profile_blocks CASCADE;
TRUNCATE public.relationships CASCADE;
TRUNCATE public.location_employees CASCADE;
TRUNCATE public.notifications CASCADE;
TRUNCATE public.giveaways CASCADE;
TRUNCATE public.deals CASCADE;
TRUNCATE public.lists CASCADE;
TRUNCATE public.posts CASCADE;
TRUNCATE public.products CASCADE;
TRUNCATE public.locations CASCADE;
TRUNCATE public.profiles CASCADE;
TRUNCATE public.cloud_files CASCADE;
TRUNCATE public.product_categories CASCADE;
-- Don't truncate reference tables that are stable: roles, states, regions, postal_codes, etc.

-- ============================================================================
-- STEP 1: DISABLE TRIGGERS TEMPORARILY
-- ============================================================================

SET session_replication_role = replica;

-- ============================================================================
-- STEP 2: HELPER FUNCTION TO RESOLVE UUID TO INT
-- ============================================================================

CREATE OR REPLACE FUNCTION migration_export.resolve_uuid(
    p_table_name text,
    p_uuid uuid
)
RETURNS integer AS $$
    SELECT new_int_id 
    FROM migration_export.uuid_to_int_mapping 
    WHERE table_name = p_table_name AND old_uuid = p_uuid;
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- STEP 3: IMPORT AUTH.USERS
-- This is the most critical step - preserves authentication
-- Note: In newer Supabase, 'email' is a generated column from auth.identities
-- We must NOT insert into 'email' - it will be populated when we insert identities
-- ============================================================================

INSERT INTO auth.users (
    id, instance_id, aud, role, encrypted_password,
    email_confirmed_at, invited_at, confirmation_token, confirmation_sent_at,
    recovery_token, recovery_sent_at, email_change_token_new, email_change,
    email_change_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
    is_super_admin, created_at, updated_at, phone, phone_confirmed_at,
    phone_change, phone_change_token, phone_change_sent_at,
    email_change_token_current, email_change_confirm_status, banned_until,
    reauthentication_token, reauthentication_sent_at, is_sso_user, deleted_at
)
SELECT 
    id, instance_id, aud, role, encrypted_password,
    email_confirmed_at, invited_at, confirmation_token, confirmation_sent_at,
    recovery_token, recovery_sent_at, email_change_token_new, email_change,
    email_change_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
    is_super_admin, created_at, updated_at, phone, phone_confirmed_at,
    phone_change, phone_change_token, phone_change_sent_at,
    email_change_token_current, email_change_confirm_status, banned_until,
    reauthentication_token, reauthentication_sent_at, is_sso_user, deleted_at
FROM migration_export.auth_users
ON CONFLICT (id) DO NOTHING;

-- Import auth.identities (exclude 'email' as it's a generated column in newer Supabase)
-- The email in auth.users will be populated from identity_data
INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id)
SELECT provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
FROM migration_export.auth_identities
ON CONFLICT DO NOTHING;

-- ============================================================================
-- STEP 4: IMPORT REFERENCE TABLES FIRST
-- Note: Cannot use SELECT * - schemas differ between old and new
-- ============================================================================

-- Roles (explicit columns)
INSERT INTO public.roles (id, role, created_at, updated_at)
SELECT id, role, 
    COALESCE(date_created, now())::timestamptz,
    COALESCE(date_updated, now())::timestamptz
FROM migration_export.roles 
ON CONFLICT (id) DO NOTHING;

-- States (explicit columns)
INSERT INTO public.states (id, abbr, name, created_at, updated_at)
SELECT id, abbr, name,
    COALESCE(date_created, now())::timestamptz,
    COALESCE(date_updated, now())::timestamptz
FROM migration_export.states
ON CONFLICT (id) DO NOTHING;

-- Regions (explicit columns)
INSERT INTO public.regions (id, name, created_at, updated_at)
SELECT id, name,
    COALESCE(date_created, now())::timestamptz,
    COALESCE(date_updated, now())::timestamptz
FROM migration_export.regions
ON CONFLICT (id) DO NOTHING;

-- Postal codes (explicit columns - match new schema)
INSERT INTO public.postal_codes (id, country_code, postal_code, place_name, state, state_code, 
    county, county_code, community, community_code, latitude, longitude, accuracy, created_at, updated_at)
SELECT id, country_code, postal_code, place_name, state, state_code,
    county, county_code, community, community_code, 
    latitude::real, longitude::real, accuracy,
    now()::timestamptz, now()::timestamptz
FROM migration_export.postal_codes
ON CONFLICT (id) DO NOTHING;

-- Region postal codes
INSERT INTO public.region_postal_codes (id, region_id, postal_code_id)
SELECT id, region_id, postal_code_id
FROM migration_export.region_postal_codes
ON CONFLICT (id) DO NOTHING;

-- Product feature types
INSERT INTO public.product_feature_types (id, name)
SELECT id, name
FROM migration_export.product_feature_types
ON CONFLICT (id) DO NOTHING;

-- Product features
INSERT INTO public.product_features (id, name, type_id)
SELECT id, name, type_id
FROM migration_export.product_features
ON CONFLICT (id) DO NOTHING;

-- Product categories (must be before products since products reference category_id)
-- NOTE: image_id is set to NULL initially to avoid circular dependency with cloud_files
INSERT INTO public.product_categories (id, public_id, name, slug, description, parent_id, image_id, product_count, hidden, created_at, updated_at)
SELECT 
    new_id,
    public_id,
    name,
    slug,
    description,
    migration_export.resolve_uuid('product_categories', original_parent_uuid),
    NULL, -- image_id set in update pass
    COALESCE(product_count, 0),
    COALESCE(hidden, false),
    created_at,
    updated_at
FROM migration_export.product_categories
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.product_categories_id_seq', COALESCE((SELECT MAX(id) FROM public.product_categories), 1));

-- Post tags (explicit columns)
INSERT INTO public.post_tags (id, tag, count, created_at, updated_at)
SELECT id, tag, COALESCE(count, 1),
    COALESCE(date_created, now())::timestamptz,
    COALESCE(date_updated, now())::timestamptz
FROM migration_export.post_tags
ON CONFLICT (id) DO NOTHING;

-- Explore (explicit columns)
-- NOTE: thumbnail_id is set to NULL initially
INSERT INTO public.explore (id, name, description, slug, thumbnail_id, start_date, end_date, "default", created_at, updated_at)
SELECT id, name, description, slug, 
    NULL, -- thumbnail_id set in update pass
    start_date, end_date, COALESCE("default", false),
    COALESCE(date_created, now())::timestamptz,
    COALESCE(date_updated, now())::timestamptz
FROM migration_export.explore
ON CONFLICT (id) DO NOTHING;

-- Explore page
INSERT INTO public.explore_page (id, created_at, updated_at)
SELECT id, 
    COALESCE(date_created, now())::timestamptz,
    COALESCE(date_updated, now())::timestamptz
FROM migration_export.explore_page
ON CONFLICT (id) DO NOTHING;

-- Explore trending
INSERT INTO public.explore_trending (id, name, created_at, updated_at)
SELECT id, name,
    COALESCE(date_created, now())::timestamptz,
    COALESCE(date_updated, now())::timestamptz
FROM migration_export.explore_trending
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- STEP 5: IMPORT PROFILES (Moved before Cloud Files)
-- NEW: id is integer, public_id is the old UUID
-- NOTE: avatar_id and banner_id are set to NULL initially
-- ============================================================================

-- First, create a temp table with deduplicated slugs AND usernames
CREATE TEMP TABLE profiles_with_unique_fields AS
SELECT 
    p.*,
    CASE 
        WHEN dup_slug.slug IS NOT NULL AND p.new_id > dup_slug.first_id 
        THEN p.slug || '-' || p.new_id::text
        ELSE p.slug
    END as unique_slug,
    CASE 
        WHEN dup_username.username IS NOT NULL AND p.new_id > dup_username.first_id 
        THEN p.username || '-' || p.new_id::text
        ELSE p.username
    END as unique_username
FROM migration_export.profiles p
LEFT JOIN (
    SELECT slug, MIN(new_id) as first_id
    FROM migration_export.profiles
    WHERE slug IS NOT NULL
    GROUP BY slug
    HAVING COUNT(*) > 1
) dup_slug ON p.slug = dup_slug.slug
LEFT JOIN (
    SELECT username, MIN(new_id) as first_id
    FROM migration_export.profiles
    WHERE username IS NOT NULL
    GROUP BY username
    HAVING COUNT(*) > 1
) dup_username ON p.username = dup_username.username;

INSERT INTO public.profiles (
    id,
    public_id,
    auth_id,
    profile_type,
    username,
    display_name,
    slug,
    phone,
    bio,
    avatar_id,
    banner_id,
    website,
    role_id,
    -- Map old status values to new valid values
    status,
    is_verified,
    is_private,
    business_info,
    social_links,
    follower_count,
    following_count,
    post_count,
    product_count,
    like_count,
    stash_count,
    location_count,
    created_at,
    updated_at
)
SELECT 
    new_id,
    public_id,
    auth_id,
    profile_type::public.profile_type,
    unique_username,
    display_name,
    unique_slug,
    phone,
    bio,
    NULL, -- avatar_id set in update pass
    NULL, -- banner_id set in update pass
    website,
    role_id,
    CASE 
        WHEN status IN ('active', 'suspended', 'deleted', 'published') THEN status
        WHEN status = 'draft' THEN 'active'
        WHEN status IS NULL THEN 'active'
        ELSE 'active'
    END,
    COALESCE(is_verified, false),
    COALESCE(is_private, false),
    business_info,
    social_links,
    COALESCE(follower_count, 0),
    COALESCE(following_count, 0),
    COALESCE(post_count, 0),
    COALESCE(product_count, 0),
    COALESCE(like_count, 0),
    COALESCE(stash_count, 0),
    COALESCE(location_count, 0),
    created_at,
    updated_at
FROM profiles_with_unique_fields
ON CONFLICT (id) DO NOTHING;

DROP TABLE profiles_with_unique_fields;

SELECT setval('public.profiles_id_seq', COALESCE((SELECT MAX(id) FROM public.profiles), 1));

-- ============================================================================
-- STEP 6: IMPORT CLOUD FILES (Moved after Profiles)
-- NEW: id is integer, public_id is the old UUID
-- ============================================================================

-- Check if cloud_files table exists in migration_export before importing
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'migration_export' AND table_name = 'cloud_files') THEN
        INSERT INTO public.cloud_files (
            id, public_id, cloudinary_id, signature, format, resource_type,
            width, height, url, secure_url, asset_id, profile_id, created_at, updated_at
        )
        SELECT 
            new_id, old_uuid, cloudinary_id, signature, format, resource_type,
            width, height, url, secure_url, asset_id,
            migration_export.resolve_uuid('profiles', original_profile_uuid),
            created_at, updated_at
        FROM migration_export.cloud_files
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;

SELECT setval('public.cloud_files_id_seq', COALESCE((SELECT MAX(id) FROM public.cloud_files), 1));

-- ============================================================================
-- STEP 7: IMPORT LOCATIONS
-- NEW: id is integer, public_id is the old UUID
-- NOTE: banner_id and logo_id are set to NULL initially
-- ============================================================================

INSERT INTO public.locations (
    id,
    public_id,
    name,
    slug,
    address_line1,
    address_line2,
    city,
    state,
    postal_code_id,
    country,
    phone,
    email,
    website,
    description,
    operating_hours,
    coordinates,
    brand_id,
    is_verified,
    status,
    region_id,
    features,
    social_links,
    banner_id,
    logo_id,
    created_at,
    updated_at
)
SELECT 
    new_id,
    public_id,
    name,
    slug,
    address_line1,
    address_line2,
    city,
    state,
    postal_code_id,
    country,
    phone,
    email,
    website,
    description,
    operating_hours,
    coordinates::extensions.geography(POINT, 4326),
    migration_export.resolve_uuid('profiles', original_brand_uuid),
    is_verified,
    COALESCE(status, 'draft'),
    region_id,
    features,
    social_links,
    NULL, -- banner_id set in update pass
    NULL, -- logo_id set in update pass
    created_at,
    updated_at
FROM migration_export.locations
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.locations_id_seq', COALESCE((SELECT MAX(id) FROM public.locations), 1));

-- ============================================================================
-- STEP 8: IMPORT PRODUCTS
-- NEW: id is integer, public_id is the old UUID
-- NOTE: thumbnail_id and cover_id are set to NULL initially
-- ============================================================================

INSERT INTO public.products (
    id,
    public_id,
    name,
    slug,
    description,
    category_id,
    status,
    is_verified,
    stash_count,
    post_count,
    price,
    release_date,
    url,
    thumbnail_id,
    cover_id,
    created_at,
    updated_at
)
SELECT 
    new_id,
    public_id,
    name,
    slug,
    description,
    migration_export.resolve_uuid('product_categories', original_category_uuid),
    COALESCE(status, 'draft'),
    COALESCE(is_verified, false),
    COALESCE(stash_count, 0),
    COALESCE(post_count, 0),
    price,
    release_date,
    url,
    NULL, -- thumbnail_id set in update pass
    NULL, -- cover_id set in update pass
    created_at,
    updated_at
FROM migration_export.products
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.products_id_seq', COALESCE((SELECT MAX(id) FROM public.products), 1));

-- ============================================================================
-- STEP 9: IMPORT POSTS
-- NEW: id is integer, public_id is the old UUID
-- NOTE: file_id is set to NULL initially
-- ============================================================================

INSERT INTO public.posts (
    id,
    public_id,
    message,
    status,
    profile_id,
    postal_code_id,
    file_id,
    url,
    created_at,
    updated_at
)
SELECT 
    p.new_id,
    p.public_id,
    p.message,
    p.status,
    migration_export.resolve_uuid('profiles', p.original_profile_uuid),
    p.location_id,
    NULL, -- file_id set in update pass
    p.url,
    p.created_at,
    p.updated_at
FROM migration_export.posts p
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.posts_id_seq', COALESCE((SELECT MAX(id) FROM public.posts), 1));

-- ============================================================================
-- STEP 10: IMPORT LISTS
-- NEW: id is integer, public_id is the old UUID
-- NOTE: thumbnail_id and background_id are set to NULL initially
-- ============================================================================

INSERT INTO public.lists (
    id,
    public_id,
    name,
    description,
    profile_id,
    product_count,
    subscription_count,
    base,
    thumbnail_id,
    background_id,
    created_at,
    updated_at
)
SELECT 
    new_id,
    public_id,
    name,
    description,
    migration_export.resolve_uuid('profiles', original_profile_uuid),
    COALESCE(product_count, 0),
    COALESCE(subscription_count, 0),
    COALESCE(base, false),
    NULL, -- thumbnail_id set in update pass
    NULL, -- background_id set in update pass
    created_at,
    updated_at
FROM migration_export.lists
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.lists_id_seq', COALESCE((SELECT MAX(id) FROM public.lists), 1));

-- ============================================================================
-- STEP 11: IMPORT DEALS
-- NEW: id is integer, public_id is the old UUID
-- ============================================================================

INSERT INTO public.deals (
    id,
    public_id,
    product_id,
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
    created_at,
    updated_at
)
SELECT 
    new_id,
    public_id,
    migration_export.resolve_uuid('products', original_product_uuid),
    expiration_date,
    release_date,
    percent_off,
    dollar_off,
    bogo_percent_off,
    bogo_dollar_off,
    total_deals,
    claimed_deals,
    COALESCE(expired, false),
    conditions,
    header_message,
    description,
    COALESCE(is_medical, false),
    COALESCE(is_recreational, false),
    created_at,
    updated_at
FROM migration_export.deals
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.deals_id_seq', COALESCE((SELECT MAX(id) FROM public.deals), 1));

-- ============================================================================
-- STEP 12: IMPORT GIVEAWAYS
-- NEW: id is integer, public_id is the old UUID
-- NOTE: cover_id is set to NULL initially
-- ============================================================================

INSERT INTO public.giveaways (
    id,
    public_id,
    product_id,
    cover_id,
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
    created_at,
    updated_at
)
SELECT 
    new_id,
    public_id,
    migration_export.resolve_uuid('products', original_product_uuid),
    NULL, -- cover_id set in update pass
    name,
    description,
    start_time,
    end_time,
    total_prizes,
    terms_url,
    COALESCE(selected_winner, false),
    COALESCE(redeemed, false),
    COALESCE(entry_count, 0),
    COALESCE(winner_count, 0),
    created_at,
    updated_at
FROM migration_export.giveaways
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.giveaways_id_seq', COALESCE((SELECT MAX(id) FROM public.giveaways), 1));

-- ============================================================================
-- STEP 13: IMPORT NOTIFICATIONS
-- ============================================================================

INSERT INTO public.notifications (
    id,
    public_id,
    profile_id,
    type_id,
    title,
    body,
    actor_id,
    related_type,
    data,
    is_read,
    created_at
)
SELECT 
    new_id,
    public_id,
    migration_export.resolve_uuid('profiles', original_profile_uuid),
    COALESCE((SELECT id FROM public.notification_types WHERE code = 'account_update' LIMIT 1), 1),
    COALESCE(title, 'Notification'),
    COALESCE(body, title, 'Notification'),
    migration_export.resolve_uuid('profiles', original_actor_uuid),
    related_type,
    COALESCE(data, '{}'::jsonb),
    COALESCE(is_read, false),
    created_at
FROM migration_export.notifications
WHERE migration_export.resolve_uuid('profiles', original_profile_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.notifications_id_seq', COALESCE((SELECT MAX(id) FROM public.notifications), 1));

-- ============================================================================
-- STEP 14: IMPORT JUNCTION TABLES
-- ============================================================================

-- Location employees
INSERT INTO public.location_employees (id, location_id, profile_id, role, is_approved, has_been_reviewed, created_at, updated_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('locations', original_location_uuid),
    migration_export.resolve_uuid('profiles', original_profile_uuid),
    CASE 
        WHEN role = 'employee' THEN 'staff'
        WHEN role IN ('manager', 'staff', 'budtender') THEN role
        ELSE 'staff'
    END,
    COALESCE(is_approved, false),
    COALESCE(has_been_reviewed, false),
    created_at,
    updated_at
FROM migration_export.location_employees
WHERE migration_export.resolve_uuid('locations', original_location_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('profiles', original_profile_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.location_employees_id_seq', COALESCE((SELECT MAX(id) FROM public.location_employees), 1));

-- Product brands
INSERT INTO public.product_brands (id, product_id, brand_id, created_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('products', original_product_uuid),
    migration_export.resolve_uuid('profiles', original_brand_uuid),
    created_at
FROM migration_export.product_brands
WHERE migration_export.resolve_uuid('products', original_product_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('profiles', original_brand_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.product_brands_id_seq', COALESCE((SELECT MAX(id) FROM public.product_brands), 1));

-- Related products
INSERT INTO public.related_products (id, product_id, related_product_id, created_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('products', original_product_uuid),
    migration_export.resolve_uuid('products', original_related_product_uuid),
    created_at
FROM migration_export.related_products
WHERE migration_export.resolve_uuid('products', original_product_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('products', original_related_product_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.related_products_id_seq', COALESCE((SELECT MAX(id) FROM public.related_products), 1));

-- Deals locations
INSERT INTO public.deals_locations (id, deal_id, location_id)
SELECT 
    new_id,
    migration_export.resolve_uuid('deals', original_deal_uuid),
    migration_export.resolve_uuid('locations', original_location_uuid)
FROM migration_export.deals_locations
WHERE migration_export.resolve_uuid('deals', original_deal_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('locations', original_location_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.deals_locations_id_seq', COALESCE((SELECT MAX(id) FROM public.deals_locations), 1));

-- Profile admins
INSERT INTO public.profile_admins (id, admin_profile_id, managed_profile_id, created_at)
SELECT DISTINCT ON (admin_id, managed_id)
    new_id,
    admin_id,
    managed_id,
    created_at
FROM (
    SELECT 
        new_id,
        migration_export.resolve_uuid('profiles', original_admin_uuid) as admin_id,
        migration_export.resolve_uuid('profiles', original_managed_uuid) as managed_id,
        created_at
    FROM migration_export.profile_admins
    WHERE migration_export.resolve_uuid('profiles', original_admin_uuid) IS NOT NULL
      AND migration_export.resolve_uuid('profiles', original_managed_uuid) IS NOT NULL
) sub
ORDER BY admin_id, managed_id, new_id
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.profile_admins_id_seq', COALESCE((SELECT MAX(id) FROM public.profile_admins), 1));

-- Profile blocks
INSERT INTO public.profile_blocks (id, profile_id, blocked_profile_id, created_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('profiles', original_blocker_uuid),
    migration_export.resolve_uuid('profiles', original_blocked_uuid),
    created_at
FROM migration_export.profile_blocks
WHERE migration_export.resolve_uuid('profiles', original_blocker_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('profiles', original_blocked_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.profile_blocks_id_seq', COALESCE((SELECT MAX(id) FROM public.profile_blocks), 1));

-- Relationships
INSERT INTO public.relationships (id, follower_id, followee_id, role_id, created_at, updated_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('profiles', original_follower_uuid),
    migration_export.resolve_uuid('profiles', original_followee_uuid),
    role_id,
    created_at,
    updated_at
FROM migration_export.relationships
WHERE migration_export.resolve_uuid('profiles', original_follower_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('profiles', original_followee_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.relationships_id_seq', COALESCE((SELECT MAX(id) FROM public.relationships), 1));

-- Posts profiles
INSERT INTO public.posts_profiles (id, post_id, profile_id, created_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('posts', original_post_uuid),
    migration_export.resolve_uuid('profiles', original_profile_uuid),
    created_at
FROM migration_export.posts_profiles
WHERE migration_export.resolve_uuid('posts', original_post_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('profiles', original_profile_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.posts_profiles_id_seq', COALESCE((SELECT MAX(id) FROM public.posts_profiles), 1));

-- Posts products
INSERT INTO public.posts_products (id, post_id, product_id, created_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('posts', original_post_uuid),
    migration_export.resolve_uuid('products', original_product_uuid),
    created_at
FROM migration_export.posts_products
WHERE migration_export.resolve_uuid('posts', original_post_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('products', original_product_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.posts_products_id_seq', COALESCE((SELECT MAX(id) FROM public.posts_products), 1));

-- Posts hashtags
INSERT INTO public.posts_hashtags (id, post_id, post_tag_id, created_at, updated_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('posts', original_post_uuid),
    post_tag_id,
    created_at,
    updated_at
FROM migration_export.posts_hashtags
WHERE migration_export.resolve_uuid('posts', original_post_uuid) IS NOT NULL
  AND post_tag_id IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.posts_hashtags_id_seq', COALESCE((SELECT MAX(id) FROM public.posts_hashtags), 1));

-- Posts lists
INSERT INTO public.posts_lists (id, post_id, list_id, created_at, updated_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('posts', original_post_uuid),
    migration_export.resolve_uuid('lists', original_list_uuid),
    created_at,
    updated_at
FROM migration_export.posts_lists
WHERE migration_export.resolve_uuid('posts', original_post_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('lists', original_list_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.posts_lists_id_seq', COALESCE((SELECT MAX(id) FROM public.posts_lists), 1));

-- Lists products
INSERT INTO public.lists_products (id, list_id, product_id, created_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('lists', original_list_uuid),
    migration_export.resolve_uuid('products', original_product_uuid),
    created_at
FROM migration_export.lists_products
WHERE migration_export.resolve_uuid('lists', original_list_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('products', original_product_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.lists_products_id_seq', COALESCE((SELECT MAX(id) FROM public.lists_products), 1));

-- Likes
INSERT INTO public.likes (id, post_id, profile_id, created_at, updated_at)
SELECT DISTINCT ON (post_id, profile_id)
    new_id,
    post_id,
    profile_id,
    created_at,
    updated_at
FROM (
    SELECT 
        new_id,
        migration_export.resolve_uuid('posts', original_post_uuid) as post_id,
        migration_export.resolve_uuid('profiles', original_profile_uuid) as profile_id,
        created_at,
        updated_at
    FROM migration_export.likes
    WHERE migration_export.resolve_uuid('posts', original_post_uuid) IS NOT NULL
      AND migration_export.resolve_uuid('profiles', original_profile_uuid) IS NOT NULL
) sub
ORDER BY post_id, profile_id, new_id
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.likes_id_seq', COALESCE((SELECT MAX(id) FROM public.likes), 1));

-- Stash
INSERT INTO public.stash (id, product_id, profile_id, restash_id, restash_list_id, restash_post_id, restash_profile_id, created_at, updated_at)
SELECT 
    new_id,
    migration_export.resolve_uuid('products', original_product_uuid),
    migration_export.resolve_uuid('profiles', original_profile_uuid),
    migration_export.resolve_uuid('stash', original_restash_uuid),
    migration_export.resolve_uuid('lists', original_restash_list_uuid),
    migration_export.resolve_uuid('posts', original_restash_post_uuid),
    migration_export.resolve_uuid('profiles', original_restash_profile_uuid),
    created_at,
    updated_at
FROM migration_export.stash
WHERE migration_export.resolve_uuid('products', original_product_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('profiles', original_profile_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.stash_id_seq', COALESCE((SELECT MAX(id) FROM public.stash), 1));

-- Giveaway entries
INSERT INTO public.giveaway_entries (id, public_id, profile_id, giveaway_id, won, sent, shipping_notes, created_at, updated_at)
SELECT 
    new_id,
    public_id,
    migration_export.resolve_uuid('profiles', original_profile_uuid),
    migration_export.resolve_uuid('giveaways', original_giveaway_uuid),
    COALESCE(won, false),
    COALESCE(sent, false),
    shipping_notes,
    created_at,
    updated_at
FROM migration_export.giveaway_entries
WHERE migration_export.resolve_uuid('profiles', original_profile_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('giveaways', original_giveaway_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.giveaway_entries_id_seq', COALESCE((SELECT MAX(id) FROM public.giveaway_entries), 1));

-- Giveaway entries messages
INSERT INTO public.giveaway_entries_messages (id, public_id, profile_id, giveaway_entry_id, message, created_at, updated_at)
SELECT 
    new_id,
    public_id,
    migration_export.resolve_uuid('profiles', original_profile_uuid),
    migration_export.resolve_uuid('giveaway_entries', original_giveaway_entry_uuid),
    message,
    created_at,
    updated_at
FROM migration_export.giveaway_entries_messages
WHERE migration_export.resolve_uuid('profiles', original_profile_uuid) IS NOT NULL
  AND migration_export.resolve_uuid('giveaway_entries', original_giveaway_entry_uuid) IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.giveaway_entries_messages_id_seq', COALESCE((SELECT MAX(id) FROM public.giveaway_entries_messages), 1));

-- Subscriptions lists
INSERT INTO public.subscriptions_lists (id, profile_id, list_id, created_at, updated_at)
SELECT DISTINCT ON (profile_id, list_id)
    new_id,
    profile_id,
    list_id,
    created_at,
    updated_at
FROM (
    SELECT 
        new_id,
        migration_export.resolve_uuid('profiles', original_profile_uuid) as profile_id,
        migration_export.resolve_uuid('lists', original_list_uuid) as list_id,
        created_at,
        updated_at
    FROM migration_export.subscriptions_lists
    WHERE migration_export.resolve_uuid('profiles', original_profile_uuid) IS NOT NULL
      AND migration_export.resolve_uuid('lists', original_list_uuid) IS NOT NULL
) sub
ORDER BY profile_id, list_id, new_id
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.subscriptions_lists_id_seq', COALESCE((SELECT MAX(id) FROM public.subscriptions_lists), 1));

-- Giveaways regions
INSERT INTO public.giveaways_regions (id, giveaway_id, region_id)
SELECT 
    new_id,
    migration_export.resolve_uuid('giveaways', original_giveaway_uuid),
    region_id
FROM migration_export.giveaways_regions
WHERE migration_export.resolve_uuid('giveaways', original_giveaway_uuid) IS NOT NULL
  AND region_id IS NOT NULL
ON CONFLICT (id) DO NOTHING;

SELECT setval('public.giveaways_regions_id_seq', COALESCE((SELECT MAX(id) FROM public.giveaways_regions), 1));

-- ============================================================================
-- STEP 15: UPDATE PASS - LINK MEDIA AND CIRCULAR REFERENCES
-- This runs after all entities are created, ensuring all IDs exist
-- ============================================================================

-- Update Profiles (avatar, banner)
UPDATE public.profiles p
SET 
    avatar_id = migration_export.resolve_uuid('cloud_files', mp.original_avatar_uuid),
    banner_id = migration_export.resolve_uuid('cloud_files', mp.original_banner_uuid)
FROM migration_export.profiles mp
WHERE p.id = mp.new_id;

-- Update Product Categories (image)
UPDATE public.product_categories pc
SET image_id = migration_export.resolve_uuid('cloud_files', mpc.original_image_uuid)
FROM migration_export.product_categories mpc
WHERE pc.id = mpc.new_id;

-- Update Products (thumbnail, cover)
UPDATE public.products p
SET 
    thumbnail_id = migration_export.resolve_uuid('cloud_files', mp.original_thumbnail_uuid),
    cover_id = migration_export.resolve_uuid('cloud_files', mp.original_cover_uuid)
FROM migration_export.products mp
WHERE p.id = mp.new_id;

-- Update Locations (banner, logo)
UPDATE public.locations l
SET 
    banner_id = migration_export.resolve_uuid('cloud_files', ml.original_banner_uuid),
    logo_id = migration_export.resolve_uuid('cloud_files', ml.original_logo_uuid)
FROM migration_export.locations ml
WHERE l.id = ml.new_id;

-- Update Lists (thumbnail, background)
UPDATE public.lists l
SET 
    thumbnail_id = migration_export.resolve_uuid('cloud_files', ml.original_thumbnail_uuid),
    background_id = migration_export.resolve_uuid('cloud_files', ml.original_background_uuid)
FROM migration_export.lists ml
WHERE l.id = ml.new_id;

-- Update Giveaways (cover)
UPDATE public.giveaways g
SET cover_id = migration_export.resolve_uuid('cloud_files', mg.original_cover_uuid)
FROM migration_export.giveaways mg
WHERE g.id = mg.new_id;

-- Update Posts (file)
UPDATE public.posts p
SET file_id = migration_export.resolve_uuid('cloud_files', mp.original_file_uuid)
FROM migration_export.posts mp
WHERE p.id = mp.new_id;

-- Update Explore (thumbnail)
UPDATE public.explore e
SET thumbnail_id = migration_export.resolve_uuid('cloud_files', me.original_thumbnail_uuid)
FROM migration_export.explore me
WHERE e.id = me.new_id;

-- ============================================================================
-- STEP 16: RE-ENABLE TRIGGERS
-- ============================================================================

SET session_replication_role = DEFAULT;

-- ============================================================================
-- STEP 17: VERIFY IMPORT
-- ============================================================================

SELECT 'auth.users' as table_name, COUNT(*) as count FROM auth.users
UNION ALL SELECT 'profiles', COUNT(*) FROM public.profiles
UNION ALL SELECT 'locations', COUNT(*) FROM public.locations
UNION ALL SELECT 'products', COUNT(*) FROM public.products
UNION ALL SELECT 'posts', COUNT(*) FROM public.posts
UNION ALL SELECT 'lists', COUNT(*) FROM public.lists
UNION ALL SELECT 'deals', COUNT(*) FROM public.deals
UNION ALL SELECT 'giveaways', COUNT(*) FROM public.giveaways
UNION ALL SELECT 'relationships', COUNT(*) FROM public.relationships
UNION ALL SELECT 'notifications', COUNT(*) FROM public.notifications
UNION ALL SELECT 'likes', COUNT(*) FROM public.likes
UNION ALL SELECT 'stash', COUNT(*) FROM public.stash
UNION ALL SELECT 'giveaway_entries', COUNT(*) FROM public.giveaway_entries
UNION ALL SELECT 'cloud_files', COUNT(*) FROM public.cloud_files
UNION ALL SELECT 'posts_products', COUNT(*) FROM public.posts_products
UNION ALL SELECT 'posts_hashtags', COUNT(*) FROM public.posts_hashtags
UNION ALL SELECT 'lists_products', COUNT(*) FROM public.lists_products
UNION ALL SELECT 'product_brands', COUNT(*) FROM public.product_brands
ORDER BY table_name;

-- ============================================================================
-- STEP 18: CLEANUP
-- ============================================================================

-- Optionally drop the migration_export schema when done
-- DROP SCHEMA migration_export CASCADE;
