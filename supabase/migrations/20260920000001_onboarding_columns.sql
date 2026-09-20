-- Two columns for first-session onboarding: whether it has been done, and what
-- the person said they like.
--
-- Checked before adding. public.profiles has nothing that fits either purpose:
-- the only vaguely related column is last_seen_at, which answers a different
-- question, and there is no preferences, settings, metadata or interests column
-- anywhere on the table. notification_preferences is its own table and is about
-- channels and quiet hours, not product taste.
--
-- onboarding_completed_at rather than a boolean: "when" answers "whether" and
-- also says which cohort a user joined in, which a boolean throws away. NULL
-- means never finished.
--
-- preferred_category_ids as integer[] of product_categories ids rather than
-- names. Names are display text and would break on a rename; ids are stable.
-- Postgres cannot put a foreign key on an array element, so nothing enforces
-- that the ids resolve -- the client writes only ids it read from the table, and
-- a stale id degrades to a category that no longer matches anything rather than
-- to an error.
--
-- Both are written by the user for their own row. The existing profiles UPDATE
-- policy already allows that via auth.uid() = auth_id, so no policy change.

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS onboarding_completed_at timestamptz,
    ADD COLUMN IF NOT EXISTS preferred_category_ids  integer[];

COMMENT ON COLUMN public.profiles.onboarding_completed_at IS
    'When the first-session onboarding was finished or skipped. NULL means it has '
    'not been. Server-side so it follows the user across devices.';

COMMENT ON COLUMN public.profiles.preferred_category_ids IS
    'product_categories ids the user picked during onboarding. No foreign key is '
    'possible on array elements; unresolvable ids are ignored by readers.';

-- Every existing profile predates onboarding and must not be shown it.
UPDATE public.profiles
   SET onboarding_completed_at = now()
 WHERE onboarding_completed_at IS NULL;
