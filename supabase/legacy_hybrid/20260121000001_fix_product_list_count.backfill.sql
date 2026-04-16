-- Archived from active migration 20260121000001_fix_product_list_count.sql
-- Legacy Hybrid repair backfill for existing products.

UPDATE public.products p
SET
    list_count = (SELECT COUNT(*) FROM public.lists_products lp WHERE lp.product_id = p.id),
    stash_count = (SELECT COUNT(*) FROM public.stash s WHERE s.product_id = p.id),
    post_count = (SELECT COUNT(*) FROM public.posts_products pp WHERE pp.product_id = p.id),
    brand_count = (SELECT COUNT(*) FROM public.product_brands pb WHERE pb.product_id = p.id);
