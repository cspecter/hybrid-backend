-- Archived from active migration 20260216000003_remove_vapes_category.sql
-- Legacy Hybrid category cleanup script.

DO $$
DECLARE
    concentrate_id bigint;
    vape_category_id bigint;
BEGIN
    SELECT id
    INTO concentrate_id
    FROM product_categories
    WHERE lower(name) IN ('concentrate', 'concentrates')
       OR lower(slug) IN ('concentrate', 'concentrates')
    ORDER BY id
    LIMIT 1;

    IF concentrate_id IS NULL THEN
        RAISE NOTICE 'Concentrate category not found. Skipping vape category consolidation.';
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM product_categories
        WHERE lower(name) IN ('vape', 'vapes')
           OR lower(slug) IN ('vape', 'vapes')
    ) THEN
        RAISE NOTICE 'Vape category not found. Skipping vape category consolidation.';
        RETURN;
    END IF;

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
