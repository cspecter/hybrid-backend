-- Create function to set notification URLs
CREATE OR REPLACE FUNCTION public.set_notification_urls()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_related_image text;
    v_related_public_id uuid;
    v_actor_public_id uuid;
BEGIN
    -- Get related entity image and public_id
    IF NEW.related_type = 'post' AND NEW.related_id IS NOT NULL THEN
        SELECT cf.secure_url, p.public_id INTO v_related_image, v_related_public_id
        FROM public.posts p
        LEFT JOIN public.cloud_files cf ON p.file_id = cf.id
        WHERE p.id = NEW.related_id;
    ELSIF NEW.related_type = 'product' AND NEW.related_id IS NOT NULL THEN
        SELECT cf.secure_url, p.public_id INTO v_related_image, v_related_public_id
        FROM public.products p
        LEFT JOIN public.cloud_files cf ON COALESCE(p.thumbnail_id, p.cover_id) = cf.id
        WHERE p.id = NEW.related_id;
    ELSIF NEW.related_type = 'giveaway' AND NEW.related_id IS NOT NULL THEN
        SELECT cf.secure_url, g.public_id INTO v_related_image, v_related_public_id
        FROM public.giveaways g
        LEFT JOIN public.cloud_files cf ON g.cover_id = cf.id
        WHERE g.id = NEW.related_id;
    ELSIF NEW.related_type = 'list' AND NEW.related_id IS NOT NULL THEN
        SELECT cf.secure_url, l.public_id INTO v_related_image, v_related_public_id
        FROM public.lists l
        LEFT JOIN public.cloud_files cf ON COALESCE(l.thumbnail_id, l.background_id) = cf.id
        WHERE l.id = NEW.related_id;
    ELSIF NEW.related_type = 'location' AND NEW.related_id IS NOT NULL THEN
        SELECT cf.secure_url, l.public_id INTO v_related_image, v_related_public_id
        FROM public.locations l
        LEFT JOIN public.cloud_files cf ON COALESCE(l.logo_id, l.banner_id) = cf.id
        WHERE l.id = NEW.related_id;
    ELSIF NEW.related_type = 'deal' AND NEW.related_id IS NOT NULL THEN
        SELECT cf.secure_url, d.public_id INTO v_related_image, v_related_public_id
        FROM public.deals d
        LEFT JOIN public.products p ON d.product_id = p.id
        LEFT JOIN public.cloud_files cf ON COALESCE(p.thumbnail_id, p.cover_id) = cf.id
        WHERE d.id = NEW.related_id;
    ELSIF NEW.related_type = 'profile' AND NEW.related_id IS NOT NULL THEN
        SELECT cf.secure_url, p.public_id INTO v_related_image, v_related_public_id
        FROM public.profiles p
        LEFT JOIN public.cloud_files cf ON COALESCE(p.avatar_id, p.banner_id) = cf.id
        WHERE p.id = NEW.related_id;
    END IF;

    -- Set image_url if not present
    -- Prioritize related content image
    IF NEW.image_url IS NULL AND v_related_image IS NOT NULL THEN
        NEW.image_url := v_related_image;
    END IF;

    -- Set action_url if not present or invalid
    IF NEW.action_url IS NULL OR NEW.action_url LIKE '%{_%' THEN
        IF v_related_public_id IS NOT NULL THEN
            IF NEW.related_type = 'post' THEN
                NEW.action_url := '/post/' || v_related_public_id;
            ELSIF NEW.related_type = 'product' THEN
                NEW.action_url := '/product/' || v_related_public_id;
            ELSIF NEW.related_type = 'giveaway' THEN
                NEW.action_url := '/giveaway/' || v_related_public_id;
            ELSIF NEW.related_type = 'list' THEN
                NEW.action_url := '/list/' || v_related_public_id;
            ELSIF NEW.related_type = 'location' THEN
                NEW.action_url := '/location/' || v_related_public_id;
            ELSIF NEW.related_type = 'deal' THEN
                NEW.action_url := '/deal/' || v_related_public_id;
            ELSIF NEW.related_type = 'profile' THEN
                NEW.action_url := '/profile/' || v_related_public_id;
            END IF;
        ELSIF NEW.actor_id IS NOT NULL THEN
            -- Fallback to actor profile
            SELECT public_id INTO v_actor_public_id FROM public.profiles WHERE id = NEW.actor_id;
            IF v_actor_public_id IS NOT NULL THEN
                NEW.action_url := '/profile/' || v_actor_public_id;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS trg_set_notification_urls ON public.notifications;
CREATE TRIGGER trg_set_notification_urls
    BEFORE INSERT OR UPDATE ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION public.set_notification_urls();

-- Backfill existing notifications
UPDATE public.notifications
SET id = id -- This will trigger the update
WHERE image_url IS NULL OR action_url IS NULL OR action_url LIKE '%{_%';
