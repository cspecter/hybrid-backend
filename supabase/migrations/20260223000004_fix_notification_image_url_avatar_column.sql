-- Fix notification image trigger to use profiles.avatar_id instead of removed profiles.profile_picture_id.
-- This function is called by trigger `set_notification_image_url` on notifications inserts.

CREATE OR REPLACE FUNCTION public.update_notification_image_url()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.actor_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.profiles p
            LEFT JOIN public.cloud_files f ON p.avatar_id = f.id
            WHERE p.id = NEW.actor_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;

    IF NEW.product_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.products p
            LEFT JOIN public.cloud_files f ON p.thumbnail_id = f.id
            WHERE p.id = NEW.product_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;

    IF NEW.post_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.posts po
            LEFT JOIN public.cloud_files f ON po.file_id = f.id
            WHERE po.id = NEW.post_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;

    IF NEW.giveaway_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.giveaways g
            LEFT JOIN public.cloud_files f ON g.cover_id = f.id
            WHERE g.id = NEW.giveaway_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;

    IF NEW.list_id IS NOT NULL AND NEW.image_url IS NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.lists l
            LEFT JOIN public.cloud_files f ON l.thumbnail_id = f.id
            WHERE l.id = NEW.list_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;

    RETURN NEW;
END;
$$;
