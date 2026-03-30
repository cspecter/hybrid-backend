-- Run logic to populate tag_preview_file_id for posts with products
-- This matches the logic in trg_posts_products_tag_stats/update_post_tag_stats

UPDATE public.posts p
SET 
    tag_preview_file_id = public.get_post_tag_preview_file_id(p.id)
WHERE EXISTS (
    SELECT 1 FROM public.posts_products pp WHERE pp.post_id = p.id
);
