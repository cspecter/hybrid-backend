-- Add preview_images column to lists table
ALTER TABLE public.lists ADD COLUMN IF NOT EXISTS preview_images text[] DEFAULT '{}';

-- Function to update preview_images
CREATE OR REPLACE FUNCTION public.update_list_preview_images()
RETURNS TRIGGER AS $$
DECLARE
    target_list_id bigint;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        target_list_id := OLD.list_id;
    ELSE
        target_list_id := NEW.list_id;
    END IF;

    UPDATE public.lists
    SET preview_images = ARRAY(
        SELECT cf.secure_url
        FROM public.lists_products lp
        JOIN public.products p ON lp.product_id = p.id
        JOIN public.cloud_files cf ON p.thumbnail_id = cf.id
        WHERE lp.list_id = target_list_id
        AND p.thumbnail_id IS NOT NULL
        ORDER BY lp.created_at DESC
        LIMIT 4
    )
    WHERE id = target_list_id;
    
    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Trigger for insert/update/delete
DROP TRIGGER IF EXISTS update_list_preview_images_trigger ON public.lists_products;
CREATE TRIGGER update_list_preview_images_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.lists_products
FOR EACH ROW
EXECUTE FUNCTION public.update_list_preview_images();

-- Legacy Hybrid backfill archived in ../legacy_hybrid/20251221000005_add_list_preview_images.backfill.sql.
-- New backend bootstraps should not replay historical data backfills from the active migration chain.
