-- Force update of all FTS triggers to ensure correct column names are used
-- This fixes "column does not exist" errors caused by legacy code persisting in the database

-- 1. Fix update_posts_fts (Critical: fixes products_id -> product_id, posts_id -> post_id)
CREATE OR REPLACE FUNCTION "public"."update_posts_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.url, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.display_name FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.username FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM posts_products pp 
       JOIN products p ON p.id = pp.product_id 
       WHERE pp.post_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pc.name, ' ') 
       FROM posts_products pp 
       JOIN products p ON p.id = pp.product_id 
       JOIN product_categories pc ON pc.id = p.category_id 
       WHERE pp.post_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pt.tag, ' ') 
       FROM posts_hashtags ph 
       JOIN post_tags pt ON pt.id = ph.post_tag_id 
       WHERE ph.post_id = NEW.id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;

-- 2. Fix update_lists_fts
CREATE OR REPLACE FUNCTION "public"."update_lists_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.display_name FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.username FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM lists_products lp 
       JOIN products p ON p.id = lp.product_id 
       WHERE lp.list_id = NEW.id), ''
    )), 'C');
  
  RETURN NEW;
END;
$$;

-- 3. Fix update_products_fts
CREATE OR REPLACE FUNCTION "public"."update_products_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.cached_brand_names := (
    SELECT string_agg(p.display_name, ' ') 
    FROM product_brands pb 
    JOIN profiles p ON p.id = pb.brand_id 
    WHERE pb.product_id = NEW.id
  );
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.name FROM product_categories pc WHERE pc.id = NEW.category_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.display_name, ' ') 
       FROM product_brands pb 
       JOIN profiles p ON p.id = pb.brand_id 
       WHERE pb.product_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.slug, '')), 'D') ||
    setweight(to_tsvector('english', coalesce(NEW.url, '')), 'D');
  
  RETURN NEW;
END;
$$;

-- 4. Fix update_locations_fts
CREATE OR REPLACE FUNCTION "public"."update_locations_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.about_us, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.display_name FROM profiles p WHERE p.id = NEW.brand_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.address_line1, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.address_line2, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.delivery_details, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.place_name FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.state FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'D') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.postal_code FROM postal_codes pc WHERE pc.id = NEW.postal_code_id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;

-- 5. Fix update_profiles_fts
CREATE OR REPLACE FUNCTION "public"."update_profiles_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.display_name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.username, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.slug, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.bio, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.website, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.email, '')), 'D');
  
  RETURN NEW;
END;
$$;

-- 6. Fix update_giveaways_fts
CREATE OR REPLACE FUNCTION "public"."update_giveaways_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.terms_url, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.name FROM products p WHERE p.id = NEW.product_id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.name 
       FROM products p 
       JOIN product_categories pc ON pc.id = p.category_id 
       WHERE p.id = NEW.product_id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pc.postal_code, ' ')
       FROM giveaways_regions gr
       JOIN region_postal_codes rpc ON rpc.region_id = gr.region_id
       JOIN postal_codes pc ON pc.id = rpc.postal_code_id
       WHERE gr.giveaway_id = NEW.id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;

-- 7. Fix update_product_cached_brands
CREATE OR REPLACE FUNCTION "public"."update_product_cached_brands"("product_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  brand_names text;
BEGIN
  SELECT COALESCE(string_agg(p.display_name, ' '), '') INTO brand_names
  FROM product_brands pb 
  JOIN profiles p ON p.id = pb.brand_id 
  WHERE pb.product_id = product_id;
  
  UPDATE products 
  SET cached_brand_names = brand_names
  WHERE id = product_id;
END;
$$;

-- 8. Fix update_null_cached_brand_names
CREATE OR REPLACE FUNCTION "public"."update_null_cached_brand_names"() RETURNS TABLE("product_id" bigint, "product_name" "text", "old_cached_brand_names" "text", "new_cached_brand_names" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    product_record RECORD;
    new_brand_names text;
BEGIN
    FOR product_record IN SELECT * FROM products WHERE cached_brand_names IS NULL
    LOOP
        SELECT string_agg(p.display_name, ' ') INTO new_brand_names
        FROM product_brands pb 
        JOIN profiles p ON p.id = pb.brand_id 
        WHERE pb.product_id = product_record.id;
        
        UPDATE products
        SET cached_brand_names = new_brand_names,
        fts_vector = 
            setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
            setweight(to_tsvector('english', coalesce(
                (SELECT pc.name FROM product_categories pc WHERE pc.id = product_record.category_id), ''
            )), 'B') ||
            setweight(to_tsvector('english', coalesce(new_brand_names, '')), 'C') ||
            setweight(to_tsvector('english', coalesce(product_record.slug, '')), 'D') ||
            setweight(to_tsvector('english', coalesce(product_record.url, '')), 'D')
        WHERE id = product_record.id;
        
        product_id := product_record.id;
        product_name := product_record.name;
        old_cached_brand_names := product_record.cached_brand_names;
        new_cached_brand_names := new_brand_names;
        RETURN NEXT;
    END LOOP;
    
    RETURN;
END;
$$;

-- 9. Fix update_products_fts_data
CREATE OR REPLACE FUNCTION "public"."update_products_fts_data"() RETURNS TABLE("product_id" bigint, "product_name" "text", "was_null" boolean, "old_value" "text", "new_value" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    product_record RECORD;
    new_brand_names text;
BEGIN
    FOR product_record IN SELECT * FROM products WHERE cached_brand_names IS NULL
    LOOP
        SELECT string_agg(p.display_name, ' ') INTO new_brand_names
        FROM product_brands pb 
        JOIN profiles p ON p.id = pb.brand_id 
        WHERE pb.product_id = product_record.id;
        
        IF new_brand_names IS NOT NULL OR product_record.cached_brand_names IS NULL THEN
            UPDATE products
            SET cached_brand_names = new_brand_names,
            fts_vector = 
                setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
                setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
                setweight(to_tsvector('english', coalesce(
                    (SELECT pc.name FROM product_categories pc WHERE pc.id = product_record.category_id), ''
                )), 'B') ||
                setweight(to_tsvector('english', coalesce(new_brand_names, '')), 'C') ||
                setweight(to_tsvector('english', coalesce(product_record.slug, '')), 'D') ||
                setweight(to_tsvector('english', coalesce(product_record.url, '')), 'D')
            WHERE id = product_record.id;
            
            product_id := product_record.id;
            product_name := product_record.name;
            was_null := product_record.cached_brand_names IS NULL;
            old_value := product_record.cached_brand_names;
            new_value := new_brand_names;
            RETURN NEXT;
        END IF;
    END LOOP;
    
    IF NOT FOUND THEN
        product_id := NULL;
        product_name := 'No products with NULL cached_brand_names were found';
        was_null := NULL;
        old_value := NULL;
        new_value := NULL;
        RETURN NEXT;
    END IF;
    
    RETURN;
END;
$$;

-- 10. Fix update_associated_data
CREATE OR REPLACE FUNCTION "public"."update_associated_data"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    UPDATE products SET updated_at = NOW() WHERE products.id = ANY(select product_id from product_brands where brand_id = NEW.id);
    UPDATE posts SET updated_at = NOW() WHERE profile_id = NEW.id;
    UPDATE locations SET updated_at = NOW() WHERE brand_id = NEW.id;
    UPDATE lists SET updated_at = NOW() WHERE profile_id = NEW.id;
    RETURN NEW;
END;
$$;
