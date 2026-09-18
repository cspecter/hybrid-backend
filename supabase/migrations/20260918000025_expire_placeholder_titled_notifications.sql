-- Expire the 48 notifications whose title never said anything.
--
-- These surfaced as the residue of 20260918000024, which typed them
-- general_message for want of anywhere better. A type does not help them: the
-- title is the notification, and theirs carries no information.
--
--   42  title '1',  related_type 'post'        40 unread
--    3  title '1',  no related_type
--    1  title '2',  related_type 'post'
--    1  title '3',  no related_type
--    1  title 'Notification', related_type 'post'   1 unread
--
-- All 48 were written between 2023-05-09 and 2023-10-17, one per recipient, and
-- none has been expired before now. They look like a sender that fell back to
-- writing a bare counter or a literal placeholder into the title column.
--
-- Correcting a count from the previous migration's comment: that described these
-- as "43 titled literally '1'". It is 45 titled '1' -- 42 with related_type
-- 'post' and 3 without -- plus one '2', one '3' and one 'Notification'. The
-- regex that produced the original figure matched any all-digit title, and the
-- prose then reported the whole group as if it were a single value.
--
-- Expired rather than deleted, for the same reason as 20260918000023: setting
-- expires_at back to NULL restores them exactly, and deleting them does not.
-- The client already filters expired rows when paging, and since 53df296 the
-- unread badge does too, so the 41 unread ones stop inflating a count their
-- owners cannot clear by reading.
--
-- Rehearsed against production: 48 rows expire, nothing outside the set is
-- touched, and title, type_id, is_read, image_url and action_url are unchanged
-- on all of them.

UPDATE public.notifications
   SET expires_at = now()
 WHERE expires_at IS NULL
   AND (title ~ '^[0-9]+$' OR title = 'Notification');
