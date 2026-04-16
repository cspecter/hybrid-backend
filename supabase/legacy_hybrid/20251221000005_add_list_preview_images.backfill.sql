-- Archived from active migration 20251221000005_add_list_preview_images.sql
-- Legacy Hybrid data backfill for existing lists.

UPDATE public.lists l
SET preview_images = ARRAY(
    SELECT cf.secure_url
    FROM public.lists_products lp
    JOIN public.products p ON lp.product_id = p.id
    JOIN public.cloud_files cf ON p.thumbnail_id = cf.id
    WHERE lp.list_id = l.id
    AND p.thumbnail_id IS NOT NULL
    ORDER BY lp.created_at DESC
    LIMIT 4
);
