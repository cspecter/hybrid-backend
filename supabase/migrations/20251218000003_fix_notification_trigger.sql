-- Fix Notification URLs Trigger
-- Updates the set_notification_urls function to resolve related_id from data JSONB
-- if it is missing (which happens when notifications are created with public_ids).

CREATE OR REPLACE FUNCTION public.set_notification_urls()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_related_image text;
    v_related_public_id uuid;
    v_actor_public_id uuid;
BEGIN
    -- 1. Resolve related_id if missing (using public_id from data)
    IF NEW.related_id IS NULL AND NEW.data IS NOT NULL THEN
        BEGIN
            IF NEW.related_type = 'post' AND NEW.data->>'post_id' IS NOT NULL THEN
                SELECT id INTO NEW.related_id FROM public.posts WHERE public_id = (NEW.data->>'post_id')::uuid;
            ELSIF NEW.related_type = 'product' AND NEW.data->>'product_id' IS NOT NULL THEN
                SELECT id INTO NEW.related_id FROM public.products WHERE public_id = (NEW.data->>'product_id')::uuid;
            ELSIF NEW.related_type = 'giveaway' AND NEW.data->>'giveaway_id' IS NOT NULL THEN
                SELECT id INTO NEW.related_id FROM public.giveaways WHERE public_id = (NEW.data->>'giveaway_id')::uuid;
            ELSIF NEW.related_type = 'list' AND NEW.data->>'list_id' IS NOT NULL THEN
                SELECT id INTO NEW.related_id FROM public.lists WHERE public_id = (NEW.data->>'list_id')::uuid;
            ELSIF NEW.related_type = 'location' AND NEW.data->>'location_id' IS NOT NULL THEN
                SELECT id INTO NEW.related_id FROM public.locations WHERE public_id = (NEW.data->>'location_id')::uuid;
            ELSIF NEW.related_type = 'deal' AND NEW.data->>'deal_id' IS NOT NULL THEN
                SELECT id INTO NEW.related_id FROM public.deals WHERE public_id = (NEW.data->>'deal_id')::uuid;
            ELSIF NEW.related_type = 'profile' AND NEW.data->>'profile_id' IS NOT NULL THEN
                SELECT id INTO NEW.related_id FROM public.profiles WHERE public_id = (NEW.data->>'profile_id')::uuid;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Ignore invalid UUID errors or other issues during resolution
            NULL;
        END;
    END IF;

    -- 2. Get related entity image and public_id (using the now potentially populated related_id)
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

    -- 3. Set image_url if not present
    -- Prioritize related content image
    IF NEW.image_url IS NULL AND v_related_image IS NOT NULL THEN
        NEW.image_url := v_related_image;
    END IF;

    -- 4. Set action_url if not present or invalid
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

-- Force update on all notifications to fix missing URLs and related_ids
UPDATE public.notifications
SET id = id
WHERE related_id IS NULL OR image_url IS NULL OR action_url IS NULL;
