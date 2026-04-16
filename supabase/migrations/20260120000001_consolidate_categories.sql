-- Legacy Hybrid data consolidation archived in ../legacy_hybrid/20260120000001_consolidate_categories.sql.
-- This migration intentionally does not modify data during shared backend bootstrap.
DO $$
BEGIN
    RAISE NOTICE 'Skipping legacy Hybrid category consolidation during shared bootstrap.';
END $$;
