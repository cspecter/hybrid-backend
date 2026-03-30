-- Reassign all Vapes products to Concentrate(s), then remove Vapes category.
DO $$
DECLARE
    concentrate_id bigint;
    vape_category_id bigint;
BEGIN
    -- Resolve the destination category (supports either naming convention).
    SELECT id
    INTO concentrate_id
    FROM product_categories
    WHERE lower(name) IN ('concentrate', 'concentrates')
       OR lower(slug) IN ('concentrate', 'concentrates')
    ORDER BY id
    LIMIT 1;

    IF concentrate_id IS NULL THEN
        RAISE EXCEPTION 'Concentrate category not found.';
    END IF;

    -- Remap all products from Vapes -> Concentrate(s).
    FOR vape_category_id IN
        SELECT id
        FROM product_categories
        WHERE lower(name) IN ('vape', 'vapes')
           OR lower(slug) IN ('vape', 'vapes')
    LOOP
        UPDATE products
        SET category_id = concentrate_id
        WHERE category_id = vape_category_id;

        DELETE FROM product_categories
        WHERE id = vape_category_id
          AND id <> concentrate_id;
    END LOOP;

    -- Keep product_count aligned with actual product totals.
    UPDATE product_categories pc
    SET product_count = COALESCE(p.cnt, 0)
    FROM (
        SELECT category_id, COUNT(*)::int AS cnt
        FROM products
        WHERE category_id IS NOT NULL
        GROUP BY category_id
    ) p
    WHERE pc.id = p.category_id;

    UPDATE product_categories
    SET product_count = 0
    WHERE id NOT IN (
        SELECT DISTINCT category_id
        FROM products
        WHERE category_id IS NOT NULL
    );
END $$;
