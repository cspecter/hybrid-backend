-- Fix negative list.product_count values and prevent future drift.
-- Root cause: legacy trigger update_product_count_on_list increments/decrements product_count
-- while newer trigger trg_update_list_product_count recalculates from lists_products.

-- Ensure only one trigger manages product_count
DROP TRIGGER IF EXISTS update_product_count_on_list ON public.lists_products;

-- Make legacy function safe if invoked elsewhere
CREATE OR REPLACE FUNCTION public.fn_change_lists_product_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE lists
        SET updated_at = NOW(), product_count = GREATEST(0, product_count - 1)
        WHERE id = OLD.list_id;
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE lists
        SET updated_at = NOW(), product_count = product_count + 1
        WHERE id = NEW.list_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- Legacy Hybrid repair backfill archived in ../legacy_hybrid/20260105000001_fix_list_product_count_negative.backfill.sql.
-- New backend bootstraps should not replay historical data repairs from the active migration chain.

-- Prevent negative counts at the DB layer
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'lists_product_count_nonnegative'
    ) THEN
        ALTER TABLE public.lists
        ADD CONSTRAINT lists_product_count_nonnegative
        CHECK (product_count >= 0);
    END IF;
END
$$;
