-- Precompute a single 2x2 grid preview URL for lists so clients can load one image
-- instead of four independent product thumbnails.

ALTER TABLE public.lists
ADD COLUMN IF NOT EXISTS preview_grid_url text,
ADD COLUMN IF NOT EXISTS preview_grid_generated_at timestamptz;

CREATE OR REPLACE FUNCTION public.urlsafe_base64(p_input text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT replace(
        replace(
            replace(
                replace(encode(convert_to(coalesce(p_input, ''), 'UTF8'), 'base64'), E'\n', ''),
                '+', '-'
            ),
            '/', '_'
        ),
        '=',''
    );
$$;

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
    IF p_urls IS NULL OR coalesce(array_length(p_urls, 1), 0) = 0 THEN
        RETURN NULL;
    END IF;

    first_url := p_urls[1];
    u1 := public.urlsafe_base64(first_url);
    u2 := public.urlsafe_base64(coalesce(p_urls[2], first_url));
    u3 := public.urlsafe_base64(coalesce(p_urls[3], first_url));
    u4 := public.urlsafe_base64(coalesce(p_urls[4], first_url));

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

CREATE OR REPLACE FUNCTION public.compute_list_preview_images(p_list_id integer)
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
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
                    WHERE lp.list_id = p_list_id
                      AND p.thumbnail_id IS NOT NULL
                ) u
                WHERE u.preview_url IS NOT NULL
                ORDER BY u.preview_url, u.sort_order ASC NULLS LAST, u.created_at DESC, u.id DESC
            ) d
        ),
        '{}'::text[]
    );
$$;

CREATE OR REPLACE FUNCTION public.update_list_preview_images()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_list_id integer;
    raw_preview_images text[];
    grid_url text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_list_id := OLD.list_id;
    ELSE
        target_list_id := NEW.list_id;
    END IF;

    raw_preview_images := public.compute_list_preview_images(target_list_id);
    grid_url := public.build_list_preview_grid_url(raw_preview_images);

    UPDATE public.lists l
    SET preview_images = CASE
            WHEN grid_url IS NULL THEN raw_preview_images
            ELSE array_prepend(grid_url, raw_preview_images)
        END,
        preview_grid_url = grid_url,
        preview_grid_generated_at = CASE WHEN grid_url IS NULL THEN NULL ELSE now() END
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
    IF COALESCE(NEW.thumbnail_id, -1) = COALESCE(OLD.thumbnail_id, -1) THEN
        RETURN NEW;
    END IF;

    UPDATE public.lists l
    SET preview_images = CASE
            WHEN g.grid_url IS NULL THEN g.raw_preview_images
            ELSE array_prepend(g.grid_url, g.raw_preview_images)
        END,
        preview_grid_url = g.grid_url,
        preview_grid_generated_at = CASE WHEN g.grid_url IS NULL THEN NULL ELSE now() END
    FROM (
        SELECT
            x.id AS list_id,
            public.compute_list_preview_images(x.id) AS raw_preview_images,
            public.build_list_preview_grid_url(public.compute_list_preview_images(x.id)) AS grid_url
        FROM public.lists x
        WHERE x.id IN (
            SELECT lp.list_id
            FROM public.lists_products lp
            WHERE lp.product_id = NEW.id
        )
    ) g
    WHERE l.id = g.list_id;

    RETURN NEW;
END;
$$;

-- Backfill all existing rows.
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
