-- Migration: Fix FTS columns and triggers
-- Description: Replaces GENERATED ALWAYS 'fts' columns with 'fts_vector' columns populated by triggers.
--              Fixes column references in FTS functions (products_id -> product_id, etc).
--              Fixes profile name references (name -> display_name).

-- ============================================================================
-- 1. MODIFY TABLES (Drop generated 'fts', add 'fts_vector')
-- ============================================================================

-- Posts
ALTER TABLE public.posts DROP COLUMN IF EXISTS fts;
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS fts_vector tsvector;
CREATE INDEX IF NOT EXISTS idx_posts_fts_vector ON public.posts USING gin(fts_vector);

-- Products
ALTER TABLE public.products DROP COLUMN IF EXISTS fts;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_vector tsvector;
CREATE INDEX IF NOT EXISTS idx_products_fts_vector ON public.products USING gin(fts_vector);

-- Profiles
ALTER TABLE public.profiles DROP COLUMN IF EXISTS fts;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fts_vector tsvector;
CREATE INDEX IF NOT EXISTS idx_profiles_fts_vector ON public.profiles USING gin(fts_vector);

-- Lists
ALTER TABLE public.lists DROP COLUMN IF EXISTS fts;
ALTER TABLE public.lists ADD COLUMN IF NOT EXISTS fts_vector tsvector;
CREATE INDEX IF NOT EXISTS idx_lists_fts_vector ON public.lists USING gin(fts_vector);

-- Locations
ALTER TABLE public.locations DROP COLUMN IF EXISTS fts;
ALTER TABLE public.locations ADD COLUMN IF NOT EXISTS fts_vector tsvector;
CREATE INDEX IF NOT EXISTS idx_locations_fts_vector ON public.locations USING gin(fts_vector);

-- Giveaways
ALTER TABLE public.giveaways DROP COLUMN IF EXISTS fts;
ALTER TABLE public.giveaways ADD COLUMN IF NOT EXISTS fts_vector tsvector;
CREATE INDEX IF NOT EXISTS idx_giveaways_fts_vector ON public.giveaways USING gin(fts_vector);

-- ============================================================================
-- 2. DEFINE UPDATE FUNCTIONS (Corrected for schema)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_locations_fts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.about_us, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.display_name FROM profiles p WHERE p.id = NEW.brand_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.address_line1, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.address_line2, '')), 'C') ||
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

CREATE OR REPLACE FUNCTION public.update_giveaways_fts() RETURNS trigger
    LANGUAGE plpgsql
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

CREATE OR REPLACE FUNCTION public.update_lists_fts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.display_name FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.username FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM lists_products lp 
       JOIN products p ON p.id = lp.product_id 
       WHERE lp.list_id = NEW.id), ''
    )), 'C');
  
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_posts_fts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.url, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.display_name FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.username FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM posts_products pp 
       JOIN products p ON p.id = pp.product_id 
       WHERE pp.post_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pc.name, ' ') 
       FROM posts_products pp 
       JOIN products p ON p.id = pp.product_id 
       JOIN product_categories pc ON pc.id = p.category_id 
       WHERE pp.post_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pt.tag, ' ') 
       FROM posts_hashtags ph 
       JOIN post_tags pt ON pt.id = ph.post_tag_id 
       WHERE ph.post_id = NEW.id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_products_fts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Update cached brand names first
  NEW.cached_brand_names := (
    SELECT string_agg(p.display_name, ' ') 
    FROM product_brands pb 
    JOIN profiles p ON p.id = pb.brand_id 
    WHERE pb.product_id = NEW.id
  );
  
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.name FROM product_categories pc WHERE pc.id = NEW.category_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.cached_brand_names, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.slug, '')), 'D') ||
    setweight(to_tsvector('english', coalesce(NEW.url, '')), 'D');
  
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_profiles_fts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.display_name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.username, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.slug, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.bio, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.website, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.email, '')), 'D');
  
  RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. FIX CASCADE FUNCTIONS (Fix column references)
-- ============================================================================

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
            -- Update cached brand names on products
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
            
            -- Trigger FTS update on products
            UPDATE products SET fts_vector = fts_vector 
            WHERE id IN (
                SELECT product_id FROM product_brands WHERE brand_id = NEW.id
            );
        END IF;
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

CREATE OR REPLACE FUNCTION public.update_product_cached_brands(p_product_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  brand_names text;
BEGIN
  SELECT COALESCE(string_agg(p.display_name, ' '), '') INTO brand_names
  FROM product_brands pb 
  JOIN profiles p ON p.id = pb.brand_id 
  WHERE pb.product_id = p_product_id;
  
  UPDATE products 
  SET cached_brand_names = brand_names
  WHERE id = p_product_id;
END;
$$;

-- ============================================================================
-- 4. FIX ASSOCIATED DATA FUNCTIONS (Fix column references)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_associated_data() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE products SET updated_at = NOW() WHERE products.id = ANY(select product_id from product_brands where brand_id = NEW.id);
    UPDATE posts SET updated_at = NOW() WHERE profile_id = NEW.id;
    UPDATE locations SET updated_at = NOW() WHERE brand_id = NEW.id;
    UPDATE lists SET updated_at = NOW() WHERE profile_id = NEW.id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_null_cached_brand_names() RETURNS TABLE("product_id" bigint, "product_name" "text", "old_cached_brand_names" "text", "new_cached_brand_names" "text")
    LANGUAGE plpgsql
    AS $$
DECLARE
    product_record RECORD;
    new_brand_names text;
BEGIN
    FOR product_record IN SELECT * FROM products WHERE cached_brand_names IS NULL
    LOOP
        SELECT string_agg(p.display_name, ' ') INTO new_brand_names
        FROM product_brands pb 
        JOIN profiles p ON p.id = pb.brand_id 
        WHERE pb.product_id = product_record.id;
        
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
        
        product_id := product_record.id;
        product_name := product_record.name;
        old_cached_brand_names := product_record.cached_brand_names;
        new_cached_brand_names := new_brand_names;
        RETURN NEXT;
    END LOOP;
    
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_products_fts_data() RETURNS TABLE("product_id" bigint, "product_name" "text", "was_null" boolean, "old_value" "text", "new_value" "text")
    LANGUAGE plpgsql
    AS $$
DECLARE
    product_record RECORD;
    new_brand_names text;
BEGIN
    FOR product_record IN SELECT * FROM products WHERE cached_brand_names IS NULL
    LOOP
        SELECT string_agg(p.display_name, ' ') INTO new_brand_names
        FROM product_brands pb 
        JOIN profiles p ON p.id = pb.brand_id 
        WHERE pb.product_id = product_record.id;
        
        IF new_brand_names IS NOT NULL OR product_record.cached_brand_names IS NULL THEN
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
            
            product_id := product_record.id;
            product_name := product_record.name;
            was_null := product_record.cached_brand_names IS NULL;
            old_value := product_record.cached_brand_names;
            new_value := new_brand_names;
            RETURN NEXT;
        END IF;
    END LOOP;
    
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

-- ============================================================================
-- 5. CREATE TRIGGERS
-- ============================================================================

DROP TRIGGER IF EXISTS posts_fts_update ON public.posts;
CREATE TRIGGER posts_fts_update
    BEFORE INSERT OR UPDATE ON public.posts
    FOR EACH ROW
    EXECUTE FUNCTION public.update_posts_fts();

DROP TRIGGER IF EXISTS products_fts_update ON public.products;
CREATE TRIGGER products_fts_update
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION public.update_products_fts();

DROP TRIGGER IF EXISTS profiles_fts_update ON public.profiles;
CREATE TRIGGER profiles_fts_update
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_profiles_fts();

DROP TRIGGER IF EXISTS lists_fts_update ON public.lists;
CREATE TRIGGER lists_fts_update
    BEFORE INSERT OR UPDATE ON public.lists
    FOR EACH ROW
    EXECUTE FUNCTION public.update_lists_fts();

DROP TRIGGER IF EXISTS locations_fts_update ON public.locations;
CREATE TRIGGER locations_fts_update
    BEFORE INSERT OR UPDATE ON public.locations
    FOR EACH ROW
    EXECUTE FUNCTION public.update_locations_fts();

DROP TRIGGER IF EXISTS giveaways_fts_update ON public.giveaways;
CREATE TRIGGER giveaways_fts_update
    BEFORE INSERT OR UPDATE ON public.giveaways
    FOR EACH ROW
    EXECUTE FUNCTION public.update_giveaways_fts();

-- ============================================================================
-- 6. BACKFILL DATA
-- ============================================================================

-- Update all rows to trigger FTS generation
-- Using a dummy update to fire triggers
UPDATE public.posts SET id = id;
UPDATE public.products SET id = id;
UPDATE public.profiles SET id = id;
UPDATE public.lists SET id = id;
UPDATE public.locations SET id = id;
UPDATE public.giveaways SET id = id;
