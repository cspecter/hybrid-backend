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

-- Recalculate counts to correct any bad existing values
UPDATE public.lists l
SET product_count = (
    SELECT COUNT(*)
    FROM public.lists_products lp
    WHERE lp.list_id = l.id
);

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
