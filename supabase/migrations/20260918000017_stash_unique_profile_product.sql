-- Add the unique constraint public.stash has always been missing.
--
-- stash has only stash_pkey on id. public.stash_product() carries
--     INSERT INTO public.stash (profile_id, product_id) VALUES (...)
--     ON CONFLICT DO NOTHING;
-- which can therefore never fire, so every repeat call inserts another row for the same
-- (profile_id, product_id). The function's own comment suspects this and then draws the
-- wrong conclusion from it.
--
-- Latent rather than live: the client writes stash directly and lets
-- fn_change_profiles_stash_count / update_product_stash_count do the counting, so
-- stash_product is not called and 0 duplicate pairs exist. Measured immediately before
-- writing this: 1124 rows, 0 duplicate (profile_id, product_id) pairs, 0 rows with a null
-- on either column.
--
-- The DO block re-checks at apply time rather than trusting that measurement, because the
-- gap between writing and applying is exactly where a duplicate could appear. If any
-- exists the migration aborts with the count instead of failing on an opaque constraint
-- violation.
--
-- NOT changed here: stash_product still carries its redundant IF NOT EXISTS block. With
-- the constraint in place the ON CONFLICT now works and that block is dead code, but
-- removing it is a function rewrite and this migration is a table-level constraint that
-- takes a lock. Kept separate deliberately. Tracked in docs/SUPABASE-TODO.md item 8.
DO $$
DECLARE
    dupes integer;
BEGIN
    SELECT count(*) INTO dupes
    FROM (
        SELECT profile_id, product_id
        FROM public.stash
        GROUP BY profile_id, product_id
        HAVING count(*) > 1
    ) d;

    IF dupes > 0 THEN
        RAISE EXCEPTION
            'stash has % duplicate (profile_id, product_id) pair(s); de-duplicate before adding the constraint', dupes;
    END IF;
END
$$;

ALTER TABLE public.stash
    ADD CONSTRAINT stash_unique UNIQUE (profile_id, product_id);
