-- Archived from active migration 20260305000001_refresh_list_preview_images_full_set.sql
-- Legacy Hybrid data backfill for existing lists.

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
);
