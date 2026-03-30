-- Trigger to update product_count on lists when items are added or removed from lists_products

CREATE OR REPLACE FUNCTION public.update_list_product_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.lists
        SET product_count = (SELECT count(*) FROM public.lists_products WHERE list_id = NEW.list_id)
        WHERE id = NEW.list_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.lists
        SET product_count = (SELECT count(*) FROM public.lists_products WHERE list_id = OLD.list_id)
        WHERE id = OLD.list_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_list_product_count ON public.lists_products;

CREATE TRIGGER trg_update_list_product_count
AFTER INSERT OR DELETE ON public.lists_products
FOR EACH ROW
EXECUTE FUNCTION public.update_list_product_count();
