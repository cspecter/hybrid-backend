-- ============================================================================
-- REAL-TIME SYNC SETUP USING LOGICAL REPLICATION
-- Run this to keep OLD and NEW databases in sync during transition
-- ============================================================================

-- ============================================================================
-- OPTION A: LOGICAL REPLICATION (Supabase Pro required on source)
-- Best for: High-volume, real-time sync
-- ============================================================================

-- ON OLD DATABASE (Publisher):
-- 1. Enable logical replication in Supabase dashboard
-- 2. Create publication

CREATE PUBLICATION hybrid_migration FOR TABLE
    auth.users,
    auth.identities,
    public.users,           -- Will need to map to profiles
    public.dispensary_locations,
    public.dispensary_employees,
    public.products,
    public.products_brands,
    public.products_products,
    public.deals,
    public.deals_dispensary_locations,
    public.posts,
    public.posts_products,
    public.posts_profiles,
    public.posts_hashtags,
    public.relationships,
    public.likes,
    public.stash,
    public.lists,
    public.lists_products,
    public.giveaways,
    public.giveaway_entries,
    public.notifications,
    public.user_blocks,
    public.user_admins;

-- ============================================================================
-- OPTION B: FOREIGN DATA WRAPPER (FDW)
-- Best for: Query old data directly from new DB
-- ============================================================================

-- ON NEW DATABASE:

-- 1. Install the extension
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- 2. Create the foreign server (use your OLD database connection string)
CREATE SERVER old_hybrid_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (
        host 'db.xxxxxxxxxx.supabase.co',  -- Replace with old DB host
        port '5432',
        dbname 'postgres'
    );

-- 3. Create user mapping
CREATE USER MAPPING FOR postgres
    SERVER old_hybrid_server
    OPTIONS (
        user 'postgres',
        password 'YOUR_OLD_DB_PASSWORD'  -- Replace with password
    );

-- 4. Import the foreign schema
CREATE SCHEMA IF NOT EXISTS old_db;

IMPORT FOREIGN SCHEMA public
    FROM SERVER old_hybrid_server
    INTO old_db;

-- ============================================================================
-- OPTION C: TRIGGER-BASED SYNC (via Edge Functions)
-- Best for: Custom transformation logic, works on all Supabase tiers
-- ============================================================================

-- This approach uses database triggers + Edge Functions to sync data

-- See: scripts/migration/sync-edge-function/ for implementation

