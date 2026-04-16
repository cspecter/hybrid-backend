-- Archived from active migration 20260105000001_fix_list_product_count_negative.sql
-- Legacy Hybrid repair backfill for existing lists.

UPDATE public.lists l
SET product_count = (
    SELECT COUNT(*)
    FROM public.lists_products lp
    WHERE lp.list_id = l.id
);
