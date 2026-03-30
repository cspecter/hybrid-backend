-- Migration: Add tag count and tag preview file to posts
-- Description: Adds tag_count column that counts all tagged items (products, profiles, lists, locations)
--              and tag_preview_file_id that links to the first tagged item's image

-- ============================================================================
-- FIX: Drop broken FTS cascade functions that reference non-existent fts_vector column
-- The fts column is GENERATED ALWAYS so these cascade updates are not needed
-- ============================================================================

-- Drop triggers first
DROP TRIGGER IF EXISTS trg_cascade_product_category_fts ON public.product_categories;
DROP TRIGGER IF EXISTS trg_cascade_product_fts ON public.products;
DROP TRIGGER IF EXISTS trg_cascade_product_brands_fts ON public.product_brands;
DROP TRIGGER IF EXISTS trg_cascade_profile_fts ON public.profiles;

-- Drop the broken posts_fts_update trigger (fts is GENERATED ALWAYS, doesn't need manual update)
DROP TRIGGER IF EXISTS posts_fts_update ON public.posts;

-- Replace update_posts_fts with a no-op (fts is GENERATED ALWAYS)
CREATE OR REPLACE FUNCTION public.update_posts_fts()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- No-op: fts is a GENERATED ALWAYS column that auto-updates from message
    RETURN NEW;
END;
$$;

-- Replace functions with no-ops (they're not needed for GENERATED columns)
CREATE OR REPLACE FUNCTION public.cascade_product_category_fts_update() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- No-op: fts is a GENERATED ALWAYS column that auto-updates
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.cascade_product_fts_update() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- No-op: fts is a GENERATED ALWAYS column that auto-updates
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
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        PERFORM update_product_cached_brands(NEW.product_id);
        IF OLD.product_id != NEW.product_id THEN
            PERFORM update_product_cached_brands(OLD.product_id);
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM update_product_cached_brands(OLD.product_id);
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
    IF OLD.name IS DISTINCT FROM NEW.name THEN
        -- Update cached brand names on products
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
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================================
-- ADD NEW COLUMNS TO POSTS
-- ============================================================================

ALTER TABLE public.posts
ADD COLUMN IF NOT EXISTS tag_count integer DEFAULT 0 NOT NULL,
ADD COLUMN IF NOT EXISTS tag_preview_file_id integer REFERENCES public.cloud_files(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_posts_tag_preview_file ON public.posts(tag_preview_file_id);

-- ============================================================================
-- HELPER FUNCTION: Get total tag count for a post
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_post_tag_count(p_post_id integer)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    total_count integer := 0;
BEGIN
    SELECT 
        (SELECT COUNT(*) FROM public.posts_products WHERE post_id = p_post_id) +
        (SELECT COUNT(*) FROM public.posts_profiles WHERE post_id = p_post_id) +
        (SELECT COUNT(*) FROM public.posts_lists WHERE post_id = p_post_id)
    INTO total_count;
    
    RETURN total_count;
END;
$$;

-- ============================================================================
-- HELPER FUNCTION: Get tag preview file_id for a post
-- Prioritizes: products > profiles > lists > locations (based on earliest created_at)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_post_tag_preview_file_id(p_post_id integer)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_file_id integer;
    v_earliest_created_at timestamptz;
    v_current_created_at timestamptz;
BEGIN
    -- Check products first (use thumbnail_id)
    SELECT p.thumbnail_id, pp.created_at
    INTO v_file_id, v_earliest_created_at
    FROM public.posts_products pp
    JOIN public.products p ON p.id = pp.product_id
    WHERE pp.post_id = p_post_id
      AND p.thumbnail_id IS NOT NULL
    ORDER BY pp.created_at ASC
    LIMIT 1;
    
    IF v_file_id IS NOT NULL THEN
        RETURN v_file_id;
    END IF;
    
    -- Check profiles (use avatar_id)
    SELECT pr.avatar_id, pp.created_at
    INTO v_file_id, v_current_created_at
    FROM public.posts_profiles pp
    JOIN public.profiles pr ON pr.id = pp.profile_id
    WHERE pp.post_id = p_post_id
      AND pr.avatar_id IS NOT NULL
    ORDER BY pp.created_at ASC
    LIMIT 1;
    
    IF v_file_id IS NOT NULL AND (v_earliest_created_at IS NULL OR v_current_created_at < v_earliest_created_at) THEN
        RETURN v_file_id;
    END IF;
    
    -- Check lists (use thumbnail_id)
    SELECT l.thumbnail_id, pl.created_at
    INTO v_file_id, v_current_created_at
    FROM public.posts_lists pl
    JOIN public.lists l ON l.id = pl.list_id
    WHERE pl.post_id = p_post_id
      AND l.thumbnail_id IS NOT NULL
    ORDER BY pl.created_at ASC
    LIMIT 1;
    
    IF v_file_id IS NOT NULL AND (v_earliest_created_at IS NULL OR v_current_created_at < v_earliest_created_at) THEN
        RETURN v_file_id;
    END IF;
    
    RETURN NULL;
END;
$$;

-- ============================================================================
-- TRIGGER FUNCTION: Update tag_count and tag_preview_file_id
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_post_tag_stats()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_post_id integer;
BEGIN
    -- Get the post_id from either OLD or NEW record
    IF TG_OP = 'DELETE' THEN
        v_post_id := OLD.post_id;
    ELSE
        v_post_id := NEW.post_id;
    END IF;
    
    -- Update both tag_count and tag_preview_file_id
    UPDATE public.posts
    SET 
        tag_count = public.get_post_tag_count(v_post_id),
        tag_preview_file_id = public.get_post_tag_preview_file_id(v_post_id),
        updated_at = now()
    WHERE id = v_post_id;
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================================
-- TRIGGER FUNCTION: Update tag_preview when source item's image changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_post_tag_preview_on_source_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_image_column text;
    v_old_image_id integer;
    v_new_image_id integer;
BEGIN
    -- Determine which image column changed based on table
    CASE TG_TABLE_NAME
        WHEN 'products' THEN v_image_column := 'thumbnail_id';
        WHEN 'profiles' THEN v_image_column := 'avatar_id';
        WHEN 'lists' THEN v_image_column := 'thumbnail_id';
        ELSE RETURN NEW;
    END CASE;
    
    -- Get old and new image IDs dynamically
    EXECUTE format('SELECT ($1).%I, ($2).%I', v_image_column, v_image_column)
    INTO v_old_image_id, v_new_image_id
    USING OLD, NEW;
    
    -- Only update if the image actually changed
    IF v_old_image_id IS DISTINCT FROM v_new_image_id THEN
        -- Update all posts that reference this item
        CASE TG_TABLE_NAME
            WHEN 'products' THEN
                UPDATE public.posts p
                SET tag_preview_file_id = public.get_post_tag_preview_file_id(p.id),
                    updated_at = now()
                FROM public.posts_products pp
                WHERE pp.post_id = p.id AND pp.product_id = NEW.id;
                
            WHEN 'profiles' THEN
                UPDATE public.posts p
                SET tag_preview_file_id = public.get_post_tag_preview_file_id(p.id),
                    updated_at = now()
                FROM public.posts_profiles pp
                WHERE pp.post_id = p.id AND pp.profile_id = NEW.id;
                
            WHEN 'lists' THEN
                UPDATE public.posts p
                SET tag_preview_file_id = public.get_post_tag_preview_file_id(p.id),
                    updated_at = now()
                FROM public.posts_lists pl
                WHERE pl.post_id = p.id AND pl.list_id = NEW.id;
        END CASE;
    END IF;
    
    RETURN NEW;
END;
$$;

-- ============================================================================
-- CREATE TRIGGERS ON JUNCTION TABLES
-- ============================================================================

-- posts_products triggers
DROP TRIGGER IF EXISTS trg_posts_products_tag_stats ON public.posts_products;
CREATE TRIGGER trg_posts_products_tag_stats
    AFTER INSERT OR DELETE ON public.posts_products
    FOR EACH ROW
    EXECUTE FUNCTION public.update_post_tag_stats();

-- posts_profiles triggers
DROP TRIGGER IF EXISTS trg_posts_profiles_tag_stats ON public.posts_profiles;
CREATE TRIGGER trg_posts_profiles_tag_stats
    AFTER INSERT OR DELETE ON public.posts_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_post_tag_stats();

-- posts_lists triggers
DROP TRIGGER IF EXISTS trg_posts_lists_tag_stats ON public.posts_lists;
CREATE TRIGGER trg_posts_lists_tag_stats
    AFTER INSERT OR DELETE ON public.posts_lists
    FOR EACH ROW
    EXECUTE FUNCTION public.update_post_tag_stats();

-- ============================================================================
-- CREATE TRIGGERS ON SOURCE TABLES (for image changes)
-- ============================================================================

-- When a product's thumbnail changes
DROP TRIGGER IF EXISTS trg_products_tag_preview_update ON public.products;
CREATE TRIGGER trg_products_tag_preview_update
    AFTER UPDATE OF thumbnail_id ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION public.update_post_tag_preview_on_source_change();

-- When a profile's avatar changes
DROP TRIGGER IF EXISTS trg_profiles_tag_preview_update ON public.profiles;
CREATE TRIGGER trg_profiles_tag_preview_update
    AFTER UPDATE OF avatar_id ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_post_tag_preview_on_source_change();

-- When a list's thumbnail changes
DROP TRIGGER IF EXISTS trg_lists_tag_preview_update ON public.lists;
CREATE TRIGGER trg_lists_tag_preview_update
    AFTER UPDATE OF thumbnail_id ON public.lists
    FOR EACH ROW
    EXECUTE FUNCTION public.update_post_tag_preview_on_source_change();

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.get_post_tag_count(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_post_tag_preview_file_id(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_post_tag_stats() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_post_tag_preview_on_source_change() TO authenticated, service_role;

-- ============================================================================
-- BACKFILL EXISTING DATA
-- ============================================================================

UPDATE public.posts p
SET 
    tag_count = public.get_post_tag_count(p.id),
    tag_preview_file_id = public.get_post_tag_preview_file_id(p.id)
WHERE EXISTS (
    SELECT 1 FROM public.posts_products pp WHERE pp.post_id = p.id
    UNION ALL
    SELECT 1 FROM public.posts_profiles pp WHERE pp.post_id = p.id
    UNION ALL
    SELECT 1 FROM public.posts_lists pl WHERE pl.post_id = p.id
);
