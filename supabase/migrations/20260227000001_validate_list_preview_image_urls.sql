-- Ensure list preview image URLs are normalized/validated before storing.

CREATE OR REPLACE FUNCTION public.normalize_list_preview_url(p_url text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_url text;
BEGIN
    v_url := btrim(coalesce(p_url, ''));

    IF v_url = '' THEN
        RETURN NULL;
    END IF;

    -- Accept protocol-relative URLs and normalize to https.
    IF v_url ~* '^//[^[:space:]]+$' THEN
        RETURN 'https:' || v_url;
    END IF;

    -- Normalize valid absolute http/https URLs to https.
    IF v_url ~* '^https?://[^[:space:]]+$' THEN
        IF v_url ~* '^http://' THEN
            RETURN regexp_replace(v_url, '^http://', 'https://', 'i');
        END IF;
        RETURN v_url;
    END IF;

    -- Reject malformed or unsupported values.
    RETURN NULL;
END;
$$;

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
        SELECT u.preview_url
        FROM (
            SELECT public.normalize_list_preview_url(coalesce(cf.secure_url, cf.url)) AS preview_url,
                   lp.created_at,
                   lp.id
            FROM public.lists_products lp
            JOIN public.products p ON lp.product_id = p.id
            JOIN public.cloud_files cf ON p.thumbnail_id = cf.id
            WHERE lp.list_id = target_list_id
              AND p.thumbnail_id IS NOT NULL
        ) u
        WHERE u.preview_url IS NOT NULL
        ORDER BY u.created_at DESC, u.id DESC
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

-- Rebuild preview_images for all existing lists.
UPDATE public.lists l
SET preview_images = ARRAY(
    SELECT u.preview_url
    FROM (
        SELECT public.normalize_list_preview_url(coalesce(cf.secure_url, cf.url)) AS preview_url,
               lp.created_at,
               lp.id
        FROM public.lists_products lp
        JOIN public.products p ON lp.product_id = p.id
        JOIN public.cloud_files cf ON p.thumbnail_id = cf.id
        WHERE lp.list_id = l.id
          AND p.thumbnail_id IS NOT NULL
    ) u
    WHERE u.preview_url IS NOT NULL
    ORDER BY u.created_at DESC, u.id DESC
    LIMIT 4
);
