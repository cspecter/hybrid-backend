-- Fix search and FTS functions that reference non-existent 'name' column on profiles table
-- Replaces 'name' with 'display_name'

-- 1. Fix typeahead_profiles
CREATE OR REPLACE FUNCTION "public"."typeahead_profiles"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "username" "text", "profile_picture_url" "text", "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    p.id,
    p.display_name::text as name,
    p.username::text,
    coalesce(cf.secure_url, '') as profile_picture_url,
    CASE 
      WHEN p.username ILIKE (query_prefix || '%') THEN 100
      WHEN p.display_name ILIKE (query_prefix || '%') THEN 90
      ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM profiles p
  LEFT JOIN cloud_files cf ON cf.id = p.avatar_id
  WHERE 
    p.display_name ILIKE (query_prefix || '%')
    OR p.username ILIKE (query_prefix || '%')
    OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, p.display_name
  LIMIT limit_results;
END;$$;

-- 2. Fix typeahead_locations
CREATE OR REPLACE FUNCTION "public"."typeahead_locations"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "address1" "text", "address2" "text", "brand_name" "text", "place_name" "text", "state" "text", "postal_code" "text", "rank" real)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    l.id,
    l.name::text,
    l.address1::text,
    l.address2::text,
    coalesce(p.display_name, '')::text as brand_name,
    coalesce(pc.place_name, '')::text as place_name,
    coalesce(pc.state, '')::text as state,
    coalesce(pc.postal_code, '')::text as postal_code,
    CASE 
      WHEN l.name ILIKE (query_prefix || '%') THEN 100
      WHEN l.address1 ILIKE (query_prefix || '%') THEN 95
      WHEN pc.place_name ILIKE (query_prefix || '%') THEN 90
      WHEN pc.state ILIKE (query_prefix || '%') THEN 85
      ELSE ts_rank(l.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM locations l
  LEFT JOIN profiles p ON p.id = l.brand_id
  LEFT JOIN postal_codes pc ON pc.id = l.postal_code_id
  WHERE 
    l.name ILIKE (query_prefix || '%')
    OR l.address1 ILIKE (query_prefix || '%')
    OR pc.place_name ILIKE (query_prefix || '%')
    OR pc.state ILIKE (query_prefix || '%')
    OR l.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, l.name
  LIMIT limit_results;
END;
$$;

-- 3. Fix typeahead_lists
CREATE OR REPLACE FUNCTION "public"."typeahead_lists"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "description" "text", "profile_name" "text", "profile_username" "text", "created_at" timestamp with time zone, "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    l.id,
    l.name::text,
    l.description::text,
    coalesce(p.display_name::text, '') as profile_name,
    coalesce(p.username::text, '') as profile_username,
    l.created_at,
    CASE 
      WHEN l.name ILIKE (query_prefix || '%') THEN 100
      WHEN l.description ILIKE (query_prefix || '%') THEN 90
      ELSE ts_rank(l.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM lists l
  LEFT JOIN profiles p ON p.id = l.profile_id
  WHERE 
    l.name ILIKE (query_prefix || '%')
    OR l.description ILIKE (query_prefix || '%')
    OR l.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, l.created_at DESC
  LIMIT limit_results;
END;$$;

-- 4. Fix typeahead_posts
CREATE OR REPLACE FUNCTION "public"."typeahead_posts"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "message" "text", "profile_name" "text", "profile_username" "text", "created_at" timestamp with time zone, "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 
    p.id,
    p.message::text,
    coalesce(pr.display_name::text, '') as profile_name,
    coalesce(pr.username::text, '') as profile_username,
    p.created_at,
    CASE 
      WHEN p.message ILIKE (query_prefix || '%') THEN 100
      ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM posts p
  LEFT JOIN profiles pr ON pr.id = p.profile_id
  WHERE 
    p.message ILIKE (query_prefix || '%')
    OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, p.created_at DESC
  LIMIT limit_results;
END;$$;

-- 5. Fix typeahead_universal
CREATE OR REPLACE FUNCTION "public"."typeahead_universal"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("table_name" "text", "id" "uuid", "display_name" "text", "secondary_text" "text", "rank" real)
    LANGUAGE "plpgsql"
    AS $$DECLARE
  query_prefix text;
BEGIN
  query_prefix := trim(lower(search_query));
  
  IF length(query_prefix) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  (
    -- Profiles
    SELECT 
      'profiles'::text,
      p.id,
      p.display_name::text as display_name,
      '@' || coalesce(p.username::text, '') as secondary_text,
      CASE 
        WHEN p.username ILIKE (query_prefix || '%') THEN 100
        WHEN p.display_name ILIKE (query_prefix || '%') THEN 90
        ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM profiles p
    WHERE 
      p.display_name ILIKE (query_prefix || '%')
      OR p.username ILIKE (query_prefix || '%')
      OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Products
    SELECT 
      'products'::text,
      pr.id,
      pr.name as display_name,
      coalesce(pc.name, '') as secondary_text,
      CASE 
        WHEN pr.name ILIKE (query_prefix || '%') THEN 100
        ELSE ts_rank(pr.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM products pr
    LEFT JOIN product_categories pc ON pc.id = pr.category_id
    WHERE 
      pr.name ILIKE (query_prefix || '%')
      OR pr.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Posts
    SELECT 
      'posts'::text,
      po.id,
      coalesce(left(po.message, 50), '') as display_name,
      coalesce(p.display_name, '') as secondary_text,
      CASE 
        WHEN po.message ILIKE (query_prefix || '%') THEN 100
        ELSE ts_rank(po.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM posts po
    LEFT JOIN profiles p ON p.id = po.profile_id
    WHERE 
      po.message ILIKE (query_prefix || '%')
      OR po.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Lists
    SELECT 
      'lists'::text,
      l.id,
      l.name as display_name,
      coalesce(p.display_name, '') as secondary_text,
      CASE 
        WHEN l.name ILIKE (query_prefix || '%') THEN 100
        WHEN l.description ILIKE (query_prefix || '%') THEN 90
        ELSE ts_rank(l.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM lists l
    LEFT JOIN profiles p ON p.id = l.profile_id
    WHERE 
      l.name ILIKE (query_prefix || '%')
      OR l.description ILIKE (query_prefix || '%')
      OR l.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Giveaways
    SELECT 
      'giveaways'::text,
      g.id,
      coalesce(g.name, '') as display_name,
      coalesce(pr.name, '') as secondary_text,
      CASE 
        WHEN g.name ILIKE (query_prefix || '%') THEN 100
        WHEN g.description ILIKE (query_prefix || '%') THEN 90
        ELSE ts_rank(g.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM giveaways g
    LEFT JOIN products pr ON pr.id = g.product_id
    WHERE 
      g.name ILIKE (query_prefix || '%')
      OR g.description ILIKE (query_prefix || '%')
      OR g.fts_vector @@ plainto_tsquery('english', query_prefix)
    
    UNION ALL
    
    -- Locations
    SELECT 
      'locations'::text,
      l.id,
      l.name as display_name,
      coalesce(pc.place_name || ', ' || pc.state, l.address1) as secondary_text,
      CASE 
        WHEN l.name ILIKE (query_prefix || '%') THEN 100
        WHEN l.address1 ILIKE (query_prefix || '%') THEN 95
        WHEN pc.place_name ILIKE (query_prefix || '%') THEN 90
        WHEN pc.state ILIKE (query_prefix || '%') THEN 85
        ELSE ts_rank(l.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM locations l
    LEFT JOIN postal_codes pc ON pc.id = l.postal_code_id
    WHERE 
      l.name ILIKE (query_prefix || '%')
      OR l.address1 ILIKE (query_prefix || '%')
      OR pc.place_name ILIKE (query_prefix || '%')
      OR pc.state ILIKE (query_prefix || '%')
      OR l.fts_vector @@ plainto_tsquery('english', query_prefix)
  )
  ORDER BY rank DESC
  LIMIT limit_results;
END;$$;

-- 6. Fix universal_search
CREATE OR REPLACE FUNCTION "public"."universal_search"("search_query" "text", "result_limit" integer DEFAULT 50, "result_offset" integer DEFAULT 0) RETURNS TABLE("table_name" "text", "id" "uuid", "rank" real, "headline" "text", "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    query tsquery;
    total_rows bigint;
BEGIN
    query := to_tsquery('english', search_query);

    -- Calculate total count across all tables
    SELECT sum(count)
    INTO total_rows
    FROM (
        SELECT count(*) FROM posts WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM products WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM profiles WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM lists WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM giveaways WHERE fts_vector @@ query
        UNION ALL
        SELECT count(*) FROM locations WHERE fts_vector @@ query
    ) as counts;

    RETURN QUERY
    WITH all_results AS (
        SELECT 'posts'::text as table_name, p.id, ts_rank(p.fts_vector, query) as rank,
               ts_headline('english', coalesce(p.message, ''), query) as headline
        FROM posts p
        WHERE p.fts_vector @@ query

        UNION ALL

        SELECT 'products'::text, p.id, ts_rank(p.fts_vector, query) as rank,
               ts_headline('english', coalesce(p.name, ''), query) as headline
        FROM products p
        WHERE p.fts_vector @@ query

        UNION ALL

        SELECT 'profiles'::text, pr.id, ts_rank(pr.fts_vector, query) as rank,
               ts_headline('english', coalesce(pr.display_name, ''), query) as headline
        FROM profiles pr
        WHERE pr.fts_vector @@ query

        UNION ALL

        SELECT 'lists'::text, l.id, ts_rank(l.fts_vector, query) as rank,
               ts_headline('english', coalesce(l.name, ''), query) as headline
        FROM lists l
        WHERE l.fts_vector @@ query

        UNION ALL

        SELECT 'giveaways'::text, g.id, ts_rank(g.fts_vector, query) as rank,
               ts_headline('english', coalesce(g.name, ''), query) as headline
        FROM giveaways g
        WHERE g.fts_vector @@ query

        UNION ALL

        SELECT 'locations'::text, l.id, ts_rank(l.fts_vector, query) as rank,
               ts_headline('english', coalesce(l.name, ''), query) as headline
        FROM locations l
        WHERE l.fts_vector @@ query
    )
    SELECT r.table_name, r.id, r.rank, r.headline, total_rows
    FROM all_results r
    ORDER BY r.rank DESC
    LIMIT result_limit
    OFFSET result_offset;
END;
$$;

-- 7. Fix update_locations_fts
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

-- 8. Fix update_lists_fts
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

-- 9. Fix update_posts_fts
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

-- 10. Fix update_products_fts
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

-- 11. Fix update_profiles_fts
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

-- 12. Fix update_product_cached_brands
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

-- 13. Fix update_null_cached_brand_names
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

-- 14. Fix update_products_fts_data
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

-- 15. Fix test_product_brand_names (bigint version)
CREATE OR REPLACE FUNCTION "public"."test_product_brand_names"("product_id" bigint) RETURNS TABLE("product_name" "text", "brand_count" bigint, "brand_names" "text", "query_time_ms" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  start_time timestamp;
  end_time timestamp;
  p_name text;
BEGIN
  SELECT name INTO p_name FROM products WHERE id = product_id;
  
  start_time := clock_timestamp();
  
  SELECT 
    p_name,
    COUNT(pb.brand_id),
    COALESCE(string_agg(p.display_name, ' '), ''),
    EXTRACT(MILLISECONDS FROM (clock_timestamp() - start_time))
  INTO product_name, brand_count, brand_names, query_time_ms
  FROM products pr
  LEFT JOIN product_brands pb ON pb.product_id = product_id
  LEFT JOIN profiles p ON p.id = pb.brand_id
  WHERE pr.id = product_id
  GROUP BY pr.id;
  
  RETURN NEXT;
END;
$$;

-- 16. Fix test_product_brand_names (uuid version)
CREATE OR REPLACE FUNCTION "public"."test_product_brand_names"("product_id" "uuid") RETURNS TABLE("product_name" "text", "brand_count" bigint, "brand_names" "text", "query_time_ms" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  start_time timestamp;
  end_time timestamp;
  p_name text;
BEGIN
  SELECT name INTO p_name FROM products WHERE id = product_id;
  
  start_time := clock_timestamp();
  
  SELECT 
    p_name,
    COUNT(pb.brand_id),
    COALESCE(string_agg(p.display_name, ' '), ''),
    EXTRACT(MILLISECONDS FROM (clock_timestamp() - start_time))
  INTO product_name, brand_count, brand_names, query_time_ms
  FROM products pr
  LEFT JOIN product_brands pb ON pb.product_id = product_id
  LEFT JOIN profiles p ON p.id = pb.brand_id
  WHERE pr.id = product_id
  GROUP BY pr.id;
  
  RETURN NEXT;
END;
$$;

-- 17. Fix update_associated_data
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
