-- Keep lists.preview_images in sync with all list item thumbnails (not only top 4),
-- and rebuild all rows so Explore has a stable preview source set.

CREATE OR REPLACE FUNCTION public.update_list_preview_images()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_list_id integer;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_list_id := OLD.list_id;
    ELSE
        target_list_id := NEW.list_id;
    END IF;

    UPDATE public.lists l
    SET preview_images = COALESCE(
        (
            SELECT array_agg(d.preview_url ORDER BY d.sort_order ASC NULLS LAST, d.created_at DESC, d.id DESC)
            FROM (
                SELECT DISTINCT ON (u.preview_url)
                    u.preview_url,
                    u.sort_order,
                    u.created_at,
                    u.id
                FROM (
                    SELECT
                        public.normalize_list_preview_url(COALESCE(cf.secure_url, cf.url)) AS preview_url,
                        lp.sort_order,
                        lp.created_at,
                        lp.id
                    FROM public.lists_products lp
                    JOIN public.products p ON p.id = lp.product_id
                    JOIN public.cloud_files cf ON cf.id = p.thumbnail_id
                    WHERE lp.list_id = target_list_id
                      AND p.thumbnail_id IS NOT NULL
                ) u
                WHERE u.preview_url IS NOT NULL
                ORDER BY u.preview_url, u.sort_order ASC NULLS LAST, u.created_at DESC, u.id DESC
            ) d
        ),
        '{}'::text[]
    )
    WHERE l.id = target_list_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_list_preview_images_for_product()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- No-op if thumbnail did not change.
    IF COALESCE(NEW.thumbnail_id, -1) = COALESCE(OLD.thumbnail_id, -1) THEN
        RETURN NEW;
    END IF;

    UPDATE public.lists l
    SET preview_images = COALESCE(
        (
            SELECT array_agg(d.preview_url ORDER BY d.sort_order ASC NULLS LAST, d.created_at DESC, d.id DESC)
            FROM (
                SELECT DISTINCT ON (u.preview_url)
                    u.preview_url,
                    u.sort_order,
                    u.created_at,
                    u.id
                FROM (
                    SELECT
                        public.normalize_list_preview_url(COALESCE(cf.secure_url, cf.url)) AS preview_url,
                        lp.sort_order,
                        lp.created_at,
                        lp.id
                    FROM public.lists_products lp
                    JOIN public.products p ON p.id = lp.product_id
                    JOIN public.cloud_files cf ON cf.id = p.thumbnail_id
                    WHERE lp.list_id = l.id
                      AND p.thumbnail_id IS NOT NULL
                ) u
                WHERE u.preview_url IS NOT NULL
                ORDER BY u.preview_url, u.sort_order ASC NULLS LAST, u.created_at DESC, u.id DESC
            ) d
        ),
        '{}'::text[]
    )
    WHERE l.id IN (
        SELECT lp.list_id
        FROM public.lists_products lp
        WHERE lp.product_id = NEW.id
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_list_preview_images_trigger ON public.lists_products;
CREATE TRIGGER update_list_preview_images_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.lists_products
FOR EACH ROW
EXECUTE FUNCTION public.update_list_preview_images();

DROP TRIGGER IF EXISTS update_list_preview_images_on_product_thumbnail_trigger ON public.products;
CREATE TRIGGER update_list_preview_images_on_product_thumbnail_trigger
AFTER UPDATE OF thumbnail_id ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.refresh_list_preview_images_for_product();

-- Legacy Hybrid backfill archived in ../legacy_hybrid/20260305000001_refresh_list_preview_images_full_set.backfill.sql.
-- New backend bootstraps should not replay historical data backfills from the active migration chain.
