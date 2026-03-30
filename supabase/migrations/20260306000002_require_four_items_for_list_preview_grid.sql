-- Only generate stashlist preview grid URLs when a list has at least 4 preview images.

CREATE OR REPLACE FUNCTION public.build_list_preview_grid_url(p_urls text[])
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    first_url text;
    u1 text;
    u2 text;
    u3 text;
    u4 text;
BEGIN
    IF p_urls IS NULL OR coalesce(array_length(p_urls, 1), 0) < 4 THEN
        RETURN NULL;
    END IF;

    first_url := p_urls[1];
    u1 := public.urlsafe_base64(first_url);
    u2 := public.urlsafe_base64(p_urls[2]);
    u3 := public.urlsafe_base64(p_urls[3]);
    u4 := public.urlsafe_base64(p_urls[4]);

    RETURN
        'https://res.cloudinary.com/hybridapp/image/upload/' ||
        'c_fill,w_1200,h_1200,g_center/' ||
        'l_fetch:' || u1 || ',c_fill,w_600,h_600,g_north_west/' ||
        'l_fetch:' || u2 || ',c_fill,w_600,h_600,g_north_east/' ||
        'l_fetch:' || u3 || ',c_fill,w_600,h_600,g_south_west/' ||
        'l_fetch:' || u4 || ',c_fill,w_600,h_600,g_south_east/' ||
        'f_auto,q_auto/' ||
        'placeholders/Stashlist_Photo_h2uru9.jpg';
END;
$$;

-- Backfill list rows so preview grid URL is removed for lists with <4 items.
UPDATE public.lists l
SET preview_images = CASE
        WHEN g.grid_url IS NULL THEN g.raw_preview_images
        ELSE array_prepend(g.grid_url, g.raw_preview_images)
    END,
    preview_grid_url = g.grid_url,
    preview_grid_generated_at = CASE WHEN g.grid_url IS NULL THEN NULL ELSE now() END
FROM (
    SELECT
        x.id,
        public.compute_list_preview_images(x.id) AS raw_preview_images,
        public.build_list_preview_grid_url(public.compute_list_preview_images(x.id)) AS grid_url
    FROM public.lists x
) g
WHERE l.id = g.id;
