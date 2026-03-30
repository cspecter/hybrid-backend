-- Migration to import release_date from migration_export.products if available
-- This script assumes that migration_export.products has been refreshed with the release_date column
-- (by re-running the updated 01_export_old_data.sql and importing the result)

DO $$
BEGIN
    -- Check if migration_export.products exists and has release_date column
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'migration_export' 
        AND table_name = 'products' 
        AND column_name = 'release_date'
    ) THEN
        -- Update public.products from migration_export.products
        UPDATE public.products p
        SET release_date = mp.release_date
        FROM migration_export.products mp
        WHERE p.id = mp.new_id
        AND p.release_date IS NULL;
        
        RAISE NOTICE 'Updated release_date for products from migration_export';
    ELSE
        RAISE NOTICE 'Skipping release_date update: migration_export.products.release_date not found';
    END IF;
END $$;
