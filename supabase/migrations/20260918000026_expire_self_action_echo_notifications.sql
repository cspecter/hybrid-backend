-- Expire the 63 notifications that told people what they had just done.
--
-- The last of the legacy residue. 20260918000024 typed these general_message
-- because the vocabulary has no code for them: every other code describes
-- something another person or the system did, and these describe the recipient's
-- own action, sent to the recipient.
--
--   'You followed <name>'                        38   no related_type   30 unread
--   "You created list <name>'s list"             17   related_type 'list'  17 unread
--   'You added N new products to <list>.'         8   related_type 'list'   4 unread
--
-- Written between 2023-07-27 and 2024-04-09, one row per recipient per action,
-- 51 of them still unread. Nothing has produced one since April 2024 -- the
-- current stack does not write them -- so this is a closed set, not a stream.
--
-- These differ from the placeholders of 20260918000025 in that they are
-- intelligible. They are expired anyway because a notification is a message
-- about something you did not already know, and the person who just pressed
-- Follow knows they pressed Follow. Sitting in Alerts between real notifications
-- they read as noise, and 51 of them hold an unread count their owner gains
-- nothing by clearing.
--
-- Expired, not deleted, as with 20260918000023 and 20260918000025: expires_at
-- back to NULL restores them exactly.
--
-- The predicate names the three title shapes rather than just type_id = 66.
-- Today those are equivalent -- all 63 unexpired general_message rows are echoes
-- -- but general_message is the catch-all, so anything landing there later would
-- be swept up by the looser test. Matching the shapes keeps this migration to
-- the rows it was written for.
--
-- Rehearsed against production: 63 rows expire, nothing outside the set is
-- touched, and title, type_id, is_read, image_url and action_url are unchanged.

UPDATE public.notifications
   SET expires_at = now()
 WHERE expires_at IS NULL
   AND type_id = 66
   AND (   title ~ '^You followed '
        OR title ~ '^You created list '
        OR title ~ 'You added [0-9]+ new products to ');
