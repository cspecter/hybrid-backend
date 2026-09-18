-- Retire the 1,801 notifications whose subject no longer exists.
--
-- 20260918000020 backfilled the typed reference columns from related_type /
-- related_id, but only where the referenced row still existed. What it could not
-- backfill is this set: notifications that name content since deleted.
--
--   related_type = 'post'       1,719
--   related_type = 'giveaway'      73
--   related_type = 'product'        9
--   created_at          2023-03-28 .. 2025-12-05  (none in the last 90 days)
--   unread                      1,654
--   distinct recipients           233
--
-- None of them dead-ends on tap -- all 1,801 carry an action_url, and the client
-- falls through to the actor's profile or the deals page when the real target
-- cannot be fetched. The problem is that 233 people carry unread counts for
-- alerts about things that are gone, and following one lands somewhere other
-- than what the alert promised.
--
-- These are expired rather than deleted. notifications already has expires_at
-- for exactly this -- "no longer relevant" -- and the client already honours it
-- when paging. Expiring is reversible: setting expires_at back to NULL restores
-- every row untouched. Deleting 1,801 rows of 233 people's history to achieve
-- the same visible result is not reversible, so it is not what this does. If the
-- rows should actually be gone, that is a separate and deliberate decision.
--
-- Note that expires_at is currently NULL on every row in the table, even though
-- 60 of the 69 notification_types define auto_expire_after -- almost nothing has
-- been written through send_notification, which is what applies it. So this
-- migration is the first thing to put the column to use, which is also why the
-- matching client gap is worth closing: fetchNotifPage filters on expires_at but
-- fetchUnreadNotifCount does not, so without a client change the bell badge
-- would keep counting these. That fix ships alongside this in hybrid-raskin.
--
-- Rehearsed against production: 1,801 rows expire, none of image_url, action_url,
-- is_read, title or type_id changes on any of them (trg_set_notification_urls
-- fires on this UPDATE and finds nothing to fill, the referenced content being
-- deleted), no row outside the set is touched, and none of the 1,801 remains
-- visible to a client afterwards.

UPDATE public.notifications
   SET expires_at = now()
 WHERE expires_at IS NULL
   AND related_id IS NOT NULL
   AND related_type IS NOT NULL
   AND post_id     IS NULL
   AND product_id  IS NULL
   AND list_id     IS NULL
   AND giveaway_id IS NULL
   AND deal_id     IS NULL
   AND location_id IS NULL;
