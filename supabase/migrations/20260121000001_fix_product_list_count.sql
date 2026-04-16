-- Fix product counts: list_count, stash_count, post_count, brand_count
-- Replaces incremental triggers with count(*) triggers to prevent drift.

-- 1. List Count
CREATE OR REPLACE FUNCTION public.update_product_list_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.products
        SET list_count = (SELECT count(*) FROM public.lists_products WHERE product_id = NEW.product_id)
        WHERE id = NEW.product_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.products
        SET list_count = (SELECT count(*) FROM public.lists_products WHERE product_id = OLD.product_id)
        WHERE id = OLD.product_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_product_list_count ON public.lists_products;
DROP TRIGGER IF EXISTS update_list_count_on_products ON public.lists_products; -- Drop legacy if exists

CREATE TRIGGER trg_update_product_list_count
AFTER INSERT OR DELETE ON public.lists_products
FOR EACH ROW
EXECUTE FUNCTION public.update_product_list_count();

-- 2. Stash Count
CREATE OR REPLACE FUNCTION public.update_product_stash_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.products
        SET stash_count = (SELECT count(*) FROM public.stash WHERE product_id = NEW.product_id)
        WHERE id = NEW.product_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.products
        SET stash_count = (SELECT count(*) FROM public.stash WHERE product_id = OLD.product_id)
        WHERE id = OLD.product_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_product_stash_count ON public.stash;
DROP TRIGGER IF EXISTS update_stash_count_on_products ON public.stash;

CREATE TRIGGER trg_update_product_stash_count
AFTER INSERT OR DELETE ON public.stash
FOR EACH ROW
EXECUTE FUNCTION public.update_product_stash_count();

-- 3. Post Count
CREATE OR REPLACE FUNCTION public.update_product_post_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.products
        SET post_count = (SELECT count(*) FROM public.posts_products WHERE product_id = NEW.product_id)
        WHERE id = NEW.product_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.products
        SET post_count = (SELECT count(*) FROM public.posts_products WHERE product_id = OLD.product_id)
        WHERE id = OLD.product_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_product_post_count ON public.posts_products;
DROP TRIGGER IF EXISTS trg_change_post_product_count_on_product ON public.posts_products;

CREATE TRIGGER trg_update_product_post_count
AFTER INSERT OR DELETE ON public.posts_products
FOR EACH ROW
EXECUTE FUNCTION public.update_product_post_count();

-- 4. Brand Count
CREATE OR REPLACE FUNCTION public.update_product_brand_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.products
        SET brand_count = (SELECT count(*) FROM public.product_brands WHERE product_id = NEW.product_id)
        WHERE id = NEW.product_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.products
        SET brand_count = (SELECT count(*) FROM public.product_brands WHERE product_id = OLD.product_id)
        WHERE id = OLD.product_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_product_brand_count ON public.product_brands;
DROP TRIGGER IF EXISTS trg_brand_count_on_products ON public.product_brands;

CREATE TRIGGER trg_update_product_brand_count
AFTER INSERT OR DELETE ON public.product_brands
FOR EACH ROW
EXECUTE FUNCTION public.update_product_brand_count();

-- Legacy Hybrid repair backfill archived in ../legacy_hybrid/20260121000001_fix_product_list_count.backfill.sql.
-- New backend bootstraps should not replay historical count repairs from the active migration chain.
