-- Legacy Hybrid category cleanup archived in ../legacy_hybrid/20260216000003_remove_vapes_category.sql.
-- This migration intentionally does not modify data during shared backend bootstrap.
DO $$
BEGIN
    RAISE NOTICE 'Skipping legacy Hybrid vape category cleanup during shared bootstrap.';
END $$;
