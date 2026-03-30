-- Migration to consolidate product categories
DO $$
DECLARE
    tincture_id bigint;
BEGIN
    -- 1. Create Tinctures if not exists
    INSERT INTO product_categories (public_id, name, slug, description, hidden, created_at, updated_at)
    SELECT gen_random_uuid(), 'Tinctures', 'tinctures', 'Cannabis tinctures.', false, now(), now()
    WHERE NOT EXISTS (SELECT 1 FROM product_categories WHERE name = 'Tinctures')
    RETURNING id INTO tincture_id;

    -- If it existed, get the id
    IF tincture_id IS NULL THEN
        SELECT id INTO tincture_id FROM product_categories WHERE name = 'Tinctures';
    END IF;

    -- 2. Update Category Names
    UPDATE product_categories SET name = 'Pre-Rolls' WHERE id = 15;
    UPDATE product_categories SET name = 'Experiences' WHERE id = 12;

    -- 3. Remap Products
    
    -- Flower (9)
    UPDATE products SET category_id = 9 WHERE category_id IN (14, 16, 17, 52, 54, 34, 35, 36);
    
    -- Vapes (4)
    UPDATE products SET category_id = 4 WHERE category_id IN (18, 22, 38);
    
    -- Concentrates (2)
    UPDATE products SET category_id = 2 WHERE category_id IN (3, 10, 21, 24, 25, 26, 27, 32, 33, 37, 39, 40, 45, 53);
    
    -- Edibles (6)
    UPDATE products SET category_id = 6 WHERE category_id IN (8, 11, 23, 28, 29, 42);
    
    -- Topicals (19)
    UPDATE products SET category_id = 19 WHERE category_id IN (20, 41, 43, 46, 47, 55);
    
    -- Accessories (1)
    -- Map Gear(30) and hardware to Accessories(1)
    UPDATE products SET category_id = 1 WHERE category_id IN (30, 5, 7, 31, 44, 48, 49, 50, 51);
    
    -- Experiences (12)
    UPDATE products SET category_id = 12 WHERE category_id IN (13);

    -- 4. Delete old categories
    -- Keep: 1, 2, 4, 6, 9, 12, 15, 19, tincture_id
    DELETE FROM product_categories 
    WHERE id NOT IN (1, 2, 4, 6, 9, 12, 15, 19, tincture_id);

END $$;
