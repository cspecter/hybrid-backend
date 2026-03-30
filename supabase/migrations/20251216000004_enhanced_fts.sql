-- Enhanced Full-Text Search Migration
-- This migration replaces the generated FTS columns with trigger-maintained columns
-- to include data from related tables for better search results.

-- ============================================================================
-- 1. DROP EXISTING GENERATED COLUMNS
-- ============================================================================

ALTER TABLE public.products DROP COLUMN IF EXISTS fts_vector;
ALTER TABLE public.posts DROP COLUMN IF EXISTS fts_vector;
ALTER TABLE public.lists DROP COLUMN IF EXISTS fts_vector;
ALTER TABLE public.giveaways DROP COLUMN IF EXISTS fts_vector;
ALTER TABLE public.deals DROP COLUMN IF EXISTS fts_vector;
ALTER TABLE public.locations DROP COLUMN IF EXISTS fts_vector;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS fts_vector;

-- Also drop legacy 'fts' columns if they exist to ensure cleanup
ALTER TABLE public.products DROP COLUMN IF EXISTS fts;
ALTER TABLE public.posts DROP COLUMN IF EXISTS fts;
ALTER TABLE public.lists DROP COLUMN IF EXISTS fts;
ALTER TABLE public.giveaways DROP COLUMN IF EXISTS fts;
ALTER TABLE public.deals DROP COLUMN IF EXISTS fts;
ALTER TABLE public.locations DROP COLUMN IF EXISTS fts;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS fts;

-- Add FTS column to deals if it didn't exist
ALTER TABLE public.deals ADD COLUMN IF NOT EXISTS fts_vector tsvector;

-- Re-add columns as regular columns
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_vector tsvector;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS fts_vector tsvector;
ALTER TABLE public.lists ADD COLUMN IF NOT EXISTS fts_vector tsvector;
ALTER TABLE public.giveaways ADD COLUMN IF NOT EXISTS fts_vector tsvector;
ALTER TABLE public.locations ADD COLUMN IF NOT EXISTS fts_vector tsvector;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fts_vector tsvector;

-- ============================================================================
-- 2. CREATE UPDATE FUNCTIONS
-- ============================================================================

-- PRODUCTS
CREATE OR REPLACE FUNCTION public.update_products_fts_vector()
RETURNS TRIGGER AS $$
DECLARE
    v_category_name text;
    v_brand_names text;
    v_feature_names text;
BEGIN
    -- Get category
    SELECT name INTO v_category_name FROM public.product_categories WHERE id = NEW.category_id;
    
    -- Get brands
    SELECT string_agg(p.display_name, ' ') INTO v_brand_names
    FROM public.product_brands pb
    JOIN public.profiles p ON pb.brand_id = p.id
    WHERE pb.product_id = NEW.id;

    -- Get features
    SELECT string_agg(pf.name, ' ') INTO v_feature_names
    FROM public.products_product_features ppf
    JOIN public.product_features pf ON ppf.product_feature_id = pf.id
    WHERE ppf.product_id = NEW.id;

    NEW.fts_vector := 
        setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_category_name, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_brand_names, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_feature_names, '')), 'C');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- POSTS
CREATE OR REPLACE FUNCTION public.update_posts_fts_vector()
RETURNS TRIGGER AS $$
DECLARE
    v_profile_name text;
    v_profile_username text;
    v_location_name text;
BEGIN
    -- Get profile info
    SELECT display_name, username INTO v_profile_name, v_profile_username 
    FROM public.profiles WHERE id = NEW.profile_id;
    
    -- Get location info
    IF NEW.postal_code_id IS NOT NULL THEN
        SELECT coalesce(place_name, '') || ' ' || coalesce(state, '') 
        INTO v_location_name
        FROM public.postal_codes WHERE id = NEW.postal_code_id;
    END IF;

    NEW.fts_vector := 
        setweight(to_tsvector('english', coalesce(NEW.message, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(v_profile_name, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_profile_username, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_location_name, '')), 'C');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- LISTS
CREATE OR REPLACE FUNCTION public.update_lists_fts_vector()
RETURNS TRIGGER AS $$
DECLARE
    v_profile_name text;
    v_profile_username text;
    v_product_names text;
BEGIN
    -- Get profile info
    SELECT display_name, username INTO v_profile_name, v_profile_username 
    FROM public.profiles WHERE id = NEW.profile_id;
    
    -- Get top 10 product names
    SELECT string_agg(p.name, ' ') INTO v_product_names
    FROM (
        SELECT p.name
        FROM public.lists_products lp
        JOIN public.products p ON lp.product_id = p.id
        WHERE lp.list_id = NEW.id
        LIMIT 10
    ) p;

    NEW.fts_vector := 
        setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_profile_name, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_profile_username, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_product_names, '')), 'C');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- GIVEAWAYS
CREATE OR REPLACE FUNCTION public.update_giveaways_fts_vector()
RETURNS TRIGGER AS $$
DECLARE
    v_product_name text;
    v_brand_name text;
BEGIN
    -- Get product and brand info
    SELECT p.name, pr.display_name INTO v_product_name, v_brand_name
    FROM public.products p
    LEFT JOIN public.product_brands pb ON p.id = pb.product_id AND pb.is_primary = true
    LEFT JOIN public.profiles pr ON pb.brand_id = pr.id
    WHERE p.id = NEW.product_id;

    NEW.fts_vector := 
        setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_product_name, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_brand_name, '')), 'C');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- DEALS
CREATE OR REPLACE FUNCTION public.update_deals_fts_vector()
RETURNS TRIGGER AS $$
DECLARE
    v_product_name text;
    v_location_names text;
BEGIN
    -- Get product name
    SELECT name INTO v_product_name FROM public.products WHERE id = NEW.product_id;
    
    -- Get location names
    SELECT string_agg(l.name, ' ') INTO v_location_names
    FROM public.deals_locations dl
    JOIN public.locations l ON dl.location_id = l.id
    WHERE dl.deal_id = NEW.id;

    NEW.fts_vector := 
        setweight(to_tsvector('english', coalesce(NEW.header_message, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_product_name, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_location_names, '')), 'C');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- LOCATIONS
CREATE OR REPLACE FUNCTION public.update_locations_fts_vector()
RETURNS TRIGGER AS $$
DECLARE
    v_brand_name text;
BEGIN
    -- Get brand name
    SELECT display_name INTO v_brand_name FROM public.profiles WHERE id = NEW.brand_id;

    NEW.fts_vector := 
        setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.city, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'C') ||
        setweight(to_tsvector('english', coalesce(v_brand_name, '')), 'B');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- PROFILES
CREATE OR REPLACE FUNCTION public.update_profiles_fts_vector()
RETURNS TRIGGER AS $$
DECLARE
    v_location_name text;
BEGIN
    -- Get location info
    IF NEW.home_location_id IS NOT NULL THEN
        SELECT coalesce(place_name, '') || ' ' || coalesce(state, '') 
        INTO v_location_name
        FROM public.postal_codes WHERE id = NEW.home_location_id;
    END IF;

    NEW.fts_vector := 
        setweight(to_tsvector('english', coalesce(NEW.display_name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.username, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.bio, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(v_location_name, '')), 'C');
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. CREATE TRIGGERS
-- ============================================================================

-- Products
DROP TRIGGER IF EXISTS trg_update_products_fts_vector ON public.products;
CREATE TRIGGER trg_update_products_fts_vector
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.update_products_fts_vector();

-- Posts
DROP TRIGGER IF EXISTS trg_update_posts_fts_vector ON public.posts;
CREATE TRIGGER trg_update_posts_fts_vector
    BEFORE INSERT OR UPDATE ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.update_posts_fts_vector();

-- Lists
DROP TRIGGER IF EXISTS trg_update_lists_fts_vector ON public.lists;
CREATE TRIGGER trg_update_lists_fts_vector
    BEFORE INSERT OR UPDATE ON public.lists
    FOR EACH ROW EXECUTE FUNCTION public.update_lists_fts_vector();

-- Giveaways
DROP TRIGGER IF EXISTS trg_update_giveaways_fts_vector ON public.giveaways;
CREATE TRIGGER trg_update_giveaways_fts_vector
    BEFORE INSERT OR UPDATE ON public.giveaways
    FOR EACH ROW EXECUTE FUNCTION public.update_giveaways_fts_vector();

-- Deals
DROP TRIGGER IF EXISTS trg_update_deals_fts_vector ON public.deals;
CREATE TRIGGER trg_update_deals_fts_vector
    BEFORE INSERT OR UPDATE ON public.deals
    FOR EACH ROW EXECUTE FUNCTION public.update_deals_fts_vector();

-- Locations
DROP TRIGGER IF EXISTS trg_update_locations_fts_vector ON public.locations;
CREATE TRIGGER trg_update_locations_fts_vector
    BEFORE INSERT OR UPDATE ON public.locations
    FOR EACH ROW EXECUTE FUNCTION public.update_locations_fts_vector();

-- Profiles
DROP TRIGGER IF EXISTS trg_update_profiles_fts_vector ON public.profiles;
CREATE TRIGGER trg_update_profiles_fts_vector
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_profiles_fts_vector();

-- ============================================================================
-- 4. CREATE JUNCTION TRIGGERS (To update parent FTS when relations change)
-- ============================================================================

-- Helper function for junction updates
CREATE OR REPLACE FUNCTION public.touch_parent_updated_at()
RETURNS TRIGGER AS $$
DECLARE
    v_table_name text;
    v_id_column text;
    v_parent_id integer;
BEGIN
    v_table_name := TG_ARGV[0];
    v_id_column := TG_ARGV[1];
    
    IF TG_OP = 'DELETE' THEN
        EXECUTE format('UPDATE public.%I SET updated_at = now() WHERE id = $1', v_table_name) USING OLD.product_id; -- Assuming product_id for now, need to be dynamic or specific
    ELSE
        -- This is tricky to make generic because column names differ. 
        -- Let's make specific functions instead.
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Specific junction update functions

-- Product Brands -> Products
CREATE OR REPLACE FUNCTION public.trg_product_brands_update_product()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.products SET updated_at = now() WHERE id = OLD.product_id;
    ELSE
        UPDATE public.products SET updated_at = now() WHERE id = NEW.product_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_product_brands_fts_vector ON public.product_brands;
CREATE TRIGGER trg_product_brands_fts_vector
    AFTER INSERT OR UPDATE OR DELETE ON public.product_brands
    FOR EACH ROW EXECUTE FUNCTION public.trg_product_brands_update_product();

-- Product Features -> Products
CREATE OR REPLACE FUNCTION public.trg_product_features_update_product()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.products SET updated_at = now() WHERE id = OLD.product_id;
    ELSE
        UPDATE public.products SET updated_at = now() WHERE id = NEW.product_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_product_features_fts_vector ON public.products_product_features;
CREATE TRIGGER trg_product_features_fts_vector
    AFTER INSERT OR UPDATE OR DELETE ON public.products_product_features
    FOR EACH ROW EXECUTE FUNCTION public.trg_product_features_update_product();

-- Lists Products -> Lists
CREATE OR REPLACE FUNCTION public.trg_lists_products_update_list()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.lists SET updated_at = now() WHERE id = OLD.list_id;
    ELSE
        UPDATE public.lists SET updated_at = now() WHERE id = NEW.list_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_lists_products_fts_vector ON public.lists_products;
CREATE TRIGGER trg_lists_products_fts_vector
    AFTER INSERT OR UPDATE OR DELETE ON public.lists_products
    FOR EACH ROW EXECUTE FUNCTION public.trg_lists_products_update_list();

-- Deals Locations -> Deals
CREATE OR REPLACE FUNCTION public.trg_deals_locations_update_deal()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        UPDATE public.deals SET updated_at = now() WHERE id = OLD.deal_id;
    ELSE
        UPDATE public.deals SET updated_at = now() WHERE id = NEW.deal_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_deals_locations_fts_vector ON public.deals_locations;
CREATE TRIGGER trg_deals_locations_fts_vector
    AFTER INSERT OR UPDATE OR DELETE ON public.deals_locations
    FOR EACH ROW EXECUTE FUNCTION public.trg_deals_locations_update_deal();

-- ============================================================================
-- 5. REBUILD INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_products_fts_vector ON public.products USING gin(fts_vector);
CREATE INDEX IF NOT EXISTS idx_posts_fts_vector ON public.posts USING gin(fts_vector);
CREATE INDEX IF NOT EXISTS idx_lists_fts_vector ON public.lists USING gin(fts_vector);
CREATE INDEX IF NOT EXISTS idx_giveaways_fts_vector ON public.giveaways USING gin(fts_vector);
CREATE INDEX IF NOT EXISTS idx_deals_fts_vector ON public.deals USING gin(fts_vector);
CREATE INDEX IF NOT EXISTS idx_locations_fts_vector ON public.locations USING gin(fts_vector);
CREATE INDEX IF NOT EXISTS idx_profiles_fts_vector ON public.profiles USING gin(fts_vector);

-- ============================================================================
-- 6. BACKFILL DATA (Trigger updates)
-- ============================================================================

UPDATE public.products SET id = id;
UPDATE public.posts SET id = id;
UPDATE public.lists SET id = id;
UPDATE public.giveaways SET id = id;
UPDATE public.deals SET id = id;
UPDATE public.locations SET id = id;
UPDATE public.profiles SET id = id;
