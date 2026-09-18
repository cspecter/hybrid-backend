-- Reconcile the typed reference columns on public.notifications.
--
-- Background. notifications carries two parallel ways of naming its subject:
--
--   (a) related_type text + related_id integer  -- a loose tagged pointer
--   (b) post_id / product_id / giveaway_id / deal_id / list_id / location_id
--
-- (b) is what the schema, the partial indexes, and the image_url trigger are
-- written against. It is also almost entirely empty. Measured on production
-- before this migration, out of 21,020 rows:
--
--   post_id       2      related_type='post'       11,483
--   product_id    4      related_type='product'     1,473
--   list_id       5      related_type='list'        2,117
--   giveaway_id   0      related_type='giveaway'      741
--   deal_id       0      related_type='deal'            0
--   location_id   0      related_type='location'        0
--                        related_type IS NULL       5,206
--
-- The cause is that every writer picks one form and never the other, and they
-- do not agree on which:
--
--   send_notification()                      sets both (CASE WHEN on related_type),
--                                            except location_id, which it omits
--   auto_pick_giveaway_winner()              related_type/related_id only
--   fn_giveaway_entry_triggers()             related_type/related_id only
--   _products_added_to_list_notification()   related_type/related_id only
--   the client, via PostgREST                inconsistent -- some call sites send
--                                            extra:{post_id}, others send
--                                            extra:{related_type, related_id}
--
-- Those handful of populated rows are the recent client inserts that happened to
-- use form (b). Everything else went in as form (a).
--
-- Despite the name these columns have never been foreign keys -- pg_constraint
-- has no entry for any of them. Nothing enforces that a value points anywhere.
-- 1,801 rows currently name content that has since been deleted (1,719 posts,
-- 73 giveaways, 9 products).
--
-- This migration does four things:
--   1. a BEFORE INSERT OR UPDATE trigger that keeps (a) and (b) in agreement,
--      whichever one the writer supplied. One place, so it covers all five
--      write paths including PostgREST, rather than patching each in turn.
--   2. a backfill of (b) from (a) for existing rows.
--   3. the actual foreign keys, ON DELETE SET NULL.
--   4. the two missing partial indexes.
--
-- Deliberately NOT done here, both being product calls rather than technical ones:
--   * the 1,801 notifications naming deleted content are left in place. They keep
--     their related_type/related_id and get a NULL typed column. Removing them,
--     or hiding them in the client, is a decision about what a user sees in Alerts.
--   * the foreign keys are ON DELETE SET NULL, not CASCADE, because CASCADE would
--     silently delete a user's notification history when content is removed.
--
-- send_notification() is not rewritten to add its missing location_id. The
-- trigger below derives location_id from related_type='location' on the way in,
-- so the gap is closed without reproducing that function's large body.

-- ── 1. Keep the two forms in agreement ───────────────────────────────────────

-- SECURITY INVOKER on purpose. This trigger needs no privilege its caller lacks,
-- and a DEFINER trigger here would run its EXISTS probes as the owner, letting a
-- caller confirm the existence of rows RLS hides from them.
CREATE OR REPLACE FUNCTION public.sync_notification_typed_refs()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_type text := lower(NULLIF(btrim(COALESCE(NEW.related_type, '')), ''));
BEGIN
    -- (a) -> (b). Only when the target actually exists: deriving a dangling value
    -- would trip the new foreign key and turn an insert that works today into an
    -- error, which is not this trigger's business.
    IF v_type IS NOT NULL AND NEW.related_id IS NOT NULL THEN
        IF v_type = 'post' AND NEW.post_id IS NULL
           AND EXISTS (SELECT 1 FROM public.posts WHERE id = NEW.related_id) THEN
            NEW.post_id := NEW.related_id;
        ELSIF v_type = 'product' AND NEW.product_id IS NULL
           AND EXISTS (SELECT 1 FROM public.products WHERE id = NEW.related_id) THEN
            NEW.product_id := NEW.related_id;
        ELSIF v_type IN ('list', 'stashlist') AND NEW.list_id IS NULL
           AND EXISTS (SELECT 1 FROM public.lists WHERE id = NEW.related_id) THEN
            NEW.list_id := NEW.related_id;
        ELSIF v_type = 'giveaway' AND NEW.giveaway_id IS NULL
           AND EXISTS (SELECT 1 FROM public.giveaways WHERE id = NEW.related_id) THEN
            NEW.giveaway_id := NEW.related_id;
        ELSIF v_type = 'deal' AND NEW.deal_id IS NULL
           AND EXISTS (SELECT 1 FROM public.deals WHERE id = NEW.related_id) THEN
            NEW.deal_id := NEW.related_id;
        ELSIF v_type = 'location' AND NEW.location_id IS NULL
           AND EXISTS (SELECT 1 FROM public.locations WHERE id = NEW.related_id) THEN
            NEW.location_id := NEW.related_id;
        END IF;
    END IF;

    -- (b) -> (a), for the client call sites that send only a typed column. First
    -- match wins; a row naming two different things is already malformed and this
    -- is not the place to adjudicate it.
    IF NEW.related_type IS NULL AND NEW.related_id IS NULL THEN
        IF    NEW.post_id     IS NOT NULL THEN NEW.related_type := 'post';     NEW.related_id := NEW.post_id;
        ELSIF NEW.product_id  IS NOT NULL THEN NEW.related_type := 'product';  NEW.related_id := NEW.product_id;
        ELSIF NEW.list_id     IS NOT NULL THEN NEW.related_type := 'list';     NEW.related_id := NEW.list_id;
        ELSIF NEW.giveaway_id IS NOT NULL THEN NEW.related_type := 'giveaway'; NEW.related_id := NEW.giveaway_id;
        ELSIF NEW.deal_id     IS NOT NULL THEN NEW.related_type := 'deal';     NEW.related_id := NEW.deal_id;
        ELSIF NEW.location_id IS NOT NULL THEN NEW.related_type := 'location'; NEW.related_id := NEW.location_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.sync_notification_typed_refs() IS
    'BEFORE INSERT/UPDATE on notifications: keeps related_type/related_id and the '
    'typed *_id columns in agreement, in whichever direction the writer left a gap. '
    'Only derives a typed id when the referenced row exists.';

DROP TRIGGER IF EXISTS trg_sync_notification_typed_refs ON public.notifications;
CREATE TRIGGER trg_sync_notification_typed_refs
    BEFORE INSERT OR UPDATE OF related_type, related_id,
                               post_id, product_id, giveaway_id,
                               deal_id, list_id, location_id
    ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_notification_typed_refs();

-- ── 2. Backfill the existing rows ────────────────────────────────────────────
-- Guarded by EXISTS for the same reason as above: 1,801 rows name content that
-- is gone, and those must stay NULL so the foreign keys below can be validated.

UPDATE public.notifications n SET post_id = n.related_id
 WHERE n.post_id IS NULL AND lower(n.related_type) = 'post' AND n.related_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.posts t WHERE t.id = n.related_id);

UPDATE public.notifications n SET product_id = n.related_id
 WHERE n.product_id IS NULL AND lower(n.related_type) = 'product' AND n.related_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.products t WHERE t.id = n.related_id);

UPDATE public.notifications n SET list_id = n.related_id
 WHERE n.list_id IS NULL AND lower(n.related_type) IN ('list', 'stashlist') AND n.related_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.lists t WHERE t.id = n.related_id);

UPDATE public.notifications n SET giveaway_id = n.related_id
 WHERE n.giveaway_id IS NULL AND lower(n.related_type) = 'giveaway' AND n.related_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.giveaways t WHERE t.id = n.related_id);

UPDATE public.notifications n SET deal_id = n.related_id
 WHERE n.deal_id IS NULL AND lower(n.related_type) = 'deal' AND n.related_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.deals t WHERE t.id = n.related_id);

UPDATE public.notifications n SET location_id = n.related_id
 WHERE n.location_id IS NULL AND lower(n.related_type) = 'location' AND n.related_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.locations t WHERE t.id = n.related_id);

-- The reverse direction, for the client rows that carry only a typed column.
UPDATE public.notifications
   SET related_type = 'post', related_id = post_id
 WHERE related_type IS NULL AND related_id IS NULL AND post_id IS NOT NULL;
UPDATE public.notifications
   SET related_type = 'product', related_id = product_id
 WHERE related_type IS NULL AND related_id IS NULL AND product_id IS NOT NULL;
UPDATE public.notifications
   SET related_type = 'list', related_id = list_id
 WHERE related_type IS NULL AND related_id IS NULL AND list_id IS NOT NULL;
UPDATE public.notifications
   SET related_type = 'giveaway', related_id = giveaway_id
 WHERE related_type IS NULL AND related_id IS NULL AND giveaway_id IS NOT NULL;
UPDATE public.notifications
   SET related_type = 'deal', related_id = deal_id
 WHERE related_type IS NULL AND related_id IS NULL AND deal_id IS NOT NULL;
UPDATE public.notifications
   SET related_type = 'location', related_id = location_id
 WHERE related_type IS NULL AND related_id IS NULL AND location_id IS NOT NULL;

-- ── 3. Make them actual foreign keys ─────────────────────────────────────────
-- After the guarded backfill every non-NULL value points at a live row, so these
-- validate without NOT VALID. SET NULL rather than CASCADE: deleting a post must
-- not delete the notification telling someone their post was liked.

ALTER TABLE public.notifications
    DROP CONSTRAINT IF EXISTS notifications_post_id_fkey,
    DROP CONSTRAINT IF EXISTS notifications_product_id_fkey,
    DROP CONSTRAINT IF EXISTS notifications_giveaway_id_fkey,
    DROP CONSTRAINT IF EXISTS notifications_deal_id_fkey,
    DROP CONSTRAINT IF EXISTS notifications_list_id_fkey,
    DROP CONSTRAINT IF EXISTS notifications_location_id_fkey;

ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_post_id_fkey
        FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE SET NULL,
    ADD CONSTRAINT notifications_product_id_fkey
        FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL,
    ADD CONSTRAINT notifications_giveaway_id_fkey
        FOREIGN KEY (giveaway_id) REFERENCES public.giveaways(id) ON DELETE SET NULL,
    ADD CONSTRAINT notifications_deal_id_fkey
        FOREIGN KEY (deal_id) REFERENCES public.deals(id) ON DELETE SET NULL,
    ADD CONSTRAINT notifications_list_id_fkey
        FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE SET NULL,
    ADD CONSTRAINT notifications_location_id_fkey
        FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL;

-- ── 4. The two indexes that were never created ───────────────────────────────
-- post/product/giveaway/deal already have one; list and location do not. A
-- foreign key's referencing side is not indexed automatically, and ON DELETE
-- SET NULL has to scan it on every delete of the parent.

CREATE INDEX IF NOT EXISTS idx_notifications_list
    ON public.notifications (list_id) WHERE list_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_location
    ON public.notifications (location_id) WHERE location_id IS NOT NULL;
