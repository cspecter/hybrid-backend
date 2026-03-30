-- ============================================================================
-- TRIGGER-BASED SYNC: OLD DATABASE TRIGGERS
-- Run this on your OLD Supabase database
-- These triggers call Edge Functions to sync changes to new DB
-- ============================================================================
--
-- NEW SCHEMA CHANGES:
-- - New database uses INTEGER primary keys (auto-incrementing)
-- - OLD UUID IDs are stored as public_id in new schema
-- - The sync Edge Function handles UUID -> INT mapping
-- ============================================================================

-- ============================================================================
-- SYNC QUEUE TABLE
-- Stores changes to be synced (in case Edge Function is temporarily unavailable)
-- ============================================================================

-- Drop and recreate sync_queue to ensure correct schema
DROP TABLE IF EXISTS public.sync_queue CASCADE;

CREATE TABLE public.sync_queue (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    table_name text NOT NULL,
    operation text NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data jsonb,
    new_data jsonb,
    -- For mapping UUIDs to integers in new schema
    entity_uuid uuid,  -- The UUID of the entity being synced
    synced boolean DEFAULT false,
    sync_attempts integer DEFAULT 0,
    last_sync_attempt timestamptz,
    error_message text,
    created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_sync_queue_unsynced ON sync_queue(synced, created_at) WHERE NOT synced;
CREATE INDEX idx_sync_queue_entity ON sync_queue(table_name, entity_uuid);

-- ============================================================================
-- UUID TO INT MAPPING TABLE (cache of mappings from new DB)
-- This is populated by the sync Edge Function after successful syncs
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.uuid_int_mapping (
    table_name text NOT NULL,
    old_uuid uuid NOT NULL,
    new_int_id integer NOT NULL,
    created_at timestamptz DEFAULT now(),
    PRIMARY KEY (table_name, old_uuid)
);

CREATE INDEX IF NOT EXISTS idx_uuid_int_mapping_lookup ON uuid_int_mapping(table_name, old_uuid);

-- ============================================================================
-- HELPER: Get new INT ID from UUID
-- Returns NULL if not yet synced
-- ============================================================================

CREATE OR REPLACE FUNCTION get_new_int_id(p_table_name text, p_uuid uuid)
RETURNS integer AS $$
    SELECT new_int_id FROM uuid_int_mapping 
    WHERE table_name = p_table_name AND old_uuid = p_uuid;
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- GENERIC SYNC FUNCTION
-- Queues changes for sync with UUID tracking
-- ============================================================================

CREATE OR REPLACE FUNCTION sync_to_new_db()
RETURNS trigger AS $$
DECLARE
    v_entity_uuid uuid;
BEGIN
    -- Get the entity UUID (always from the id column in old schema)
    IF TG_OP = 'DELETE' THEN
        v_entity_uuid := OLD.id;
    ELSE
        v_entity_uuid := NEW.id;
    END IF;
    
    INSERT INTO sync_queue (table_name, operation, old_data, new_data, entity_uuid)
    VALUES (
        TG_TABLE_NAME,
        TG_OP,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
        v_entity_uuid
    );
    
    -- Optionally notify Edge Function immediately
    PERFORM pg_notify('sync_changes', json_build_object(
        'table', TG_TABLE_NAME,
        'operation', TG_OP,
        'uuid', v_entity_uuid,
        -- Include mapped INT id if available (for updates/deletes)
        'new_int_id', get_new_int_id(
            CASE TG_TABLE_NAME
                WHEN 'users' THEN 'profiles'
                WHEN 'dispensary_locations' THEN 'locations'
                WHEN 'dispensary_employees' THEN 'location_employees'
                WHEN 'products_brands' THEN 'product_brands'
                WHEN 'products_products' THEN 'related_products'
                WHEN 'deals_dispensary_locations' THEN 'deals_locations'
                WHEN 'user_blocks' THEN 'profile_blocks'
                WHEN 'user_brand_admins' THEN 'profile_admins'
                WHEN 'posts_users' THEN 'posts_profiles'
                ELSE TG_TABLE_NAME
            END,
            v_entity_uuid
        )
    )::text);
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- CREATE TRIGGERS ON KEY TABLES
-- ============================================================================

-- Users (syncs to profiles)
DROP TRIGGER IF EXISTS sync_users ON users;
CREATE TRIGGER sync_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Dispensary Locations (syncs to locations)
DROP TRIGGER IF EXISTS sync_dispensary_locations ON dispensary_locations;
CREATE TRIGGER sync_dispensary_locations
    AFTER INSERT OR UPDATE OR DELETE ON dispensary_locations
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Dispensary Employees (syncs to location_employees)
DROP TRIGGER IF EXISTS sync_dispensary_employees ON dispensary_employees;
CREATE TRIGGER sync_dispensary_employees
    AFTER INSERT OR UPDATE OR DELETE ON dispensary_employees
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Products
DROP TRIGGER IF EXISTS sync_products ON products;
CREATE TRIGGER sync_products
    AFTER INSERT OR UPDATE OR DELETE ON products
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Products Brands (syncs to product_brands)
DROP TRIGGER IF EXISTS sync_products_brands ON products_brands;
CREATE TRIGGER sync_products_brands
    AFTER INSERT OR UPDATE OR DELETE ON products_brands
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Products Products (syncs to related_products)
DROP TRIGGER IF EXISTS sync_products_products ON products_products;
CREATE TRIGGER sync_products_products
    AFTER INSERT OR UPDATE OR DELETE ON products_products
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Relationships
DROP TRIGGER IF EXISTS sync_relationships ON relationships;
CREATE TRIGGER sync_relationships
    AFTER INSERT OR UPDATE OR DELETE ON relationships
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Posts
DROP TRIGGER IF EXISTS sync_posts ON posts;
CREATE TRIGGER sync_posts
    AFTER INSERT OR UPDATE OR DELETE ON posts
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Posts Users (syncs to posts_profiles)
DROP TRIGGER IF EXISTS sync_posts_users ON posts_users;
CREATE TRIGGER sync_posts_users
    AFTER INSERT OR UPDATE OR DELETE ON posts_users
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Posts Products
DROP TRIGGER IF EXISTS sync_posts_products ON posts_products;
CREATE TRIGGER sync_posts_products
    AFTER INSERT OR UPDATE OR DELETE ON posts_products
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Posts Hashtags
DROP TRIGGER IF EXISTS sync_posts_hashtags ON posts_hashtags;
CREATE TRIGGER sync_posts_hashtags
    AFTER INSERT OR UPDATE OR DELETE ON posts_hashtags
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Likes
DROP TRIGGER IF EXISTS sync_likes ON likes;
CREATE TRIGGER sync_likes
    AFTER INSERT OR UPDATE OR DELETE ON likes
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Stash
DROP TRIGGER IF EXISTS sync_stash ON stash;
CREATE TRIGGER sync_stash
    AFTER INSERT OR UPDATE OR DELETE ON stash
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Deals
DROP TRIGGER IF EXISTS sync_deals ON deals;
CREATE TRIGGER sync_deals
    AFTER INSERT OR UPDATE OR DELETE ON deals
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Deals Dispensary Locations (syncs to deals_locations)
DROP TRIGGER IF EXISTS sync_deals_dispensary_locations ON deals_dispensary_locations;
CREATE TRIGGER sync_deals_dispensary_locations
    AFTER INSERT OR UPDATE OR DELETE ON deals_dispensary_locations
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Lists
DROP TRIGGER IF EXISTS sync_lists ON lists;
CREATE TRIGGER sync_lists
    AFTER INSERT OR UPDATE OR DELETE ON lists
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Lists Products
DROP TRIGGER IF EXISTS sync_lists_products ON lists_products;
CREATE TRIGGER sync_lists_products
    AFTER INSERT OR UPDATE OR DELETE ON lists_products
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Notifications
DROP TRIGGER IF EXISTS sync_notifications ON notifications;
CREATE TRIGGER sync_notifications
    AFTER INSERT OR UPDATE OR DELETE ON notifications
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Giveaways
DROP TRIGGER IF EXISTS sync_giveaways ON giveaways;
CREATE TRIGGER sync_giveaways
    AFTER INSERT OR UPDATE OR DELETE ON giveaways
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- Giveaway Entries
DROP TRIGGER IF EXISTS sync_giveaway_entries ON giveaway_entries;
CREATE TRIGGER sync_giveaway_entries
    AFTER INSERT OR UPDATE OR DELETE ON giveaway_entries
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- User Blocks (syncs to profile_blocks)
DROP TRIGGER IF EXISTS sync_user_blocks ON user_blocks;
CREATE TRIGGER sync_user_blocks
    AFTER INSERT OR UPDATE OR DELETE ON user_blocks
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- User Brand Admins (syncs to profile_admins)
DROP TRIGGER IF EXISTS sync_user_brand_admins ON user_brand_admins;
CREATE TRIGGER sync_user_brand_admins
    AFTER INSERT OR UPDATE OR DELETE ON user_brand_admins
    FOR EACH ROW EXECUTE FUNCTION sync_to_new_db();

-- ============================================================================
-- AUTH.USERS SYNC (Special handling)
-- ============================================================================

CREATE OR REPLACE FUNCTION auth.sync_auth_users()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.sync_queue (table_name, operation, old_data, new_data, entity_uuid)
    VALUES (
        'auth_users',
        TG_OP,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
        CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END
    );
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS sync_auth_users ON auth.users;
CREATE TRIGGER sync_auth_users
    AFTER INSERT OR UPDATE OR DELETE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION auth.sync_auth_users();

-- ============================================================================
-- FUNCTION: Mark queue items as synced and store mapping
-- Called by Edge Function after successful sync
-- ============================================================================

CREATE OR REPLACE FUNCTION mark_synced(
    p_queue_id uuid,
    p_table_name text,
    p_old_uuid uuid,
    p_new_int_id integer
)
RETURNS void AS $$
BEGIN
    -- Update sync queue
    UPDATE sync_queue SET synced = true WHERE id = p_queue_id;
    
    -- Store/update UUID to INT mapping
    INSERT INTO uuid_int_mapping (table_name, old_uuid, new_int_id)
    VALUES (p_table_name, p_old_uuid, p_new_int_id)
    ON CONFLICT (table_name, old_uuid) 
    DO UPDATE SET new_int_id = EXCLUDED.new_int_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Get pending sync items
-- Called by Edge Function to batch process syncs
-- ============================================================================

CREATE OR REPLACE FUNCTION get_pending_syncs(p_limit integer DEFAULT 100)
RETURNS TABLE (
    queue_id uuid,
    table_name text,
    operation text,
    old_data jsonb,
    new_data jsonb,
    entity_uuid uuid,
    -- Include resolved INT IDs for foreign keys
    resolved_fks jsonb
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sq.id as queue_id,
        sq.table_name,
        sq.operation,
        sq.old_data,
        sq.new_data,
        sq.entity_uuid,
        -- Resolve common FK UUIDs to INTs
        jsonb_build_object(
            'profile_int_id', CASE 
                WHEN sq.new_data->>'user_id' IS NOT NULL 
                THEN get_new_int_id('profiles', (sq.new_data->>'user_id')::uuid)
                ELSE NULL 
            END,
            'location_int_id', CASE 
                WHEN sq.new_data->>'dispensary_id' IS NOT NULL 
                THEN get_new_int_id('locations', (sq.new_data->>'dispensary_id')::uuid)
                ELSE NULL 
            END,
            'product_int_id', CASE 
                WHEN sq.new_data->>'product_id' IS NOT NULL 
                THEN get_new_int_id('products', (sq.new_data->>'product_id')::uuid)
                ELSE NULL 
            END,
            'post_int_id', CASE 
                WHEN sq.new_data->>'post_id' IS NOT NULL 
                THEN get_new_int_id('posts', (sq.new_data->>'post_id')::uuid)
                ELSE NULL 
            END,
            'list_int_id', CASE 
                WHEN sq.new_data->>'list_id' IS NOT NULL 
                THEN get_new_int_id('lists', (sq.new_data->>'list_id')::uuid)
                ELSE NULL 
            END,
            'deal_int_id', CASE 
                WHEN sq.new_data->>'deal_id' IS NOT NULL 
                THEN get_new_int_id('deals', (sq.new_data->>'deal_id')::uuid)
                WHEN sq.new_data->>'deals_id' IS NOT NULL 
                THEN get_new_int_id('deals', (sq.new_data->>'deals_id')::uuid)
                ELSE NULL 
            END,
            'giveaway_int_id', CASE 
                WHEN sq.new_data->>'giveaway_id' IS NOT NULL 
                THEN get_new_int_id('giveaways', (sq.new_data->>'giveaway_id')::uuid)
                ELSE NULL 
            END
        ) as resolved_fks
    FROM sync_queue sq
    WHERE sq.synced = false
    ORDER BY sq.created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- CRON JOB TO PROCESS SYNC QUEUE
-- Runs every minute to sync queued changes
-- ============================================================================

-- Make sure pg_cron is enabled
-- SELECT cron.schedule(
--     'process-sync-queue',
--     '* * * * *',  -- Every minute
--     $$
--     SELECT net.http_post(
--         'https://YOUR_NEW_PROJECT.supabase.co/functions/v1/sync-to-new-db',
--         '{}',
--         '{"Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'
--     );
--     $$
-- );

-- ============================================================================
-- CLEANUP OLD SYNCED ITEMS
-- Remove items older than 7 days that have been synced
-- ============================================================================

-- SELECT cron.schedule(
--     'cleanup-sync-queue',
--     '0 3 * * *',  -- Daily at 3am
--     $$
--     DELETE FROM sync_queue 
--     WHERE synced = true 
--     AND created_at < now() - interval '7 days';
--     $$
-- );
