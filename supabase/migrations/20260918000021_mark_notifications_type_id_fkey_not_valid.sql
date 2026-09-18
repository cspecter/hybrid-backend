-- Make notifications_type_id_fkey tell the truth about itself.
--
-- The constraint is recorded in pg_constraint with convalidated = true, and it
-- is live: an INSERT naming a missing type is rejected right now. But the data
-- behind it has never satisfied it. Of 21,020 rows, 21,001 carry type_id = 1,
-- and notification_types has no id 1 -- its ids run 11..82.
--
--   type_id = 1     21,001 rows   created_at 2023-02-23 .. 2025-12-05
--   type_id 11..40      19 rows   created_at 2026-06-07 .. 2026-09-18
--
-- The split is exactly the legacy import versus everything the current stack has
-- written. A validated constraint cannot acquire violating rows through normal
-- DML, so the import ran with enforcement suppressed -- session_replication_role
-- = replica, or ALTER TABLE ... DISABLE TRIGGER ALL around a bulk load. Neither
-- clears convalidated, so the flag has claimed a guarantee that has never held.
--
-- That claim is not cosmetic. pg_dump emits a constraint as it is recorded, so
-- the dump of this database emits a plain validated FOREIGN KEY, and restoring
-- it fails at that statement -- the backup does not round-trip. The same applies
-- to setting up logical replication or any fresh rebuild from a dump. Marking it
-- NOT VALID makes pg_dump emit NOT VALID, and the restore succeeds.
--
-- NOT VALID changes nothing about enforcement going forward. Postgres checks a
-- NOT VALID foreign key on every INSERT and UPDATE exactly as it does a valid
-- one; the flag governs only whether the existing rows were ever scanned. Live
-- behaviour after this migration is identical to live behaviour before it.
--
-- Deliberately NOT done here: repairing the 21,001 rows. Their real type is
-- recoverable from the title text -- a first pass maps 17,508 of them onto
-- existing codes (new_post_from_following 5,380, post_liked 4,427, new_follower
-- 3,756, new_list_from_following 1,993, restash_from_profile 1,301, and six
-- smaller groups), and most of the 3,493 that miss are restash_from_post /
-- restash_from_list / list_items_added / upgraded_to_creator phrasings a second
-- pass would catch. But type_id is NOT NULL, so whatever cannot be classified --
-- one group's title is the single character '1' -- still needs a type assigned,
-- and type drives the icon, the category and the grouping a user sees in Alerts.
-- Choosing those is a product decision, so the rows are left as they are and the
-- constraint is marked to match. Once the backfill is decided, the closing step
-- is ALTER TABLE public.notifications VALIDATE CONSTRAINT notifications_type_id_fkey,
-- which takes no exclusive lock and will then succeed.

ALTER TABLE public.notifications
    DROP CONSTRAINT IF EXISTS notifications_type_id_fkey;

ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_type_id_fkey
        FOREIGN KEY (type_id) REFERENCES public.notification_types(id)
        NOT VALID;

COMMENT ON CONSTRAINT notifications_type_id_fkey ON public.notifications IS
    'NOT VALID: 21,001 legacy rows carry type_id = 1, which notification_types '
    'does not contain. Enforced on all new writes. Run VALIDATE CONSTRAINT once '
    'those rows are backfilled.';
