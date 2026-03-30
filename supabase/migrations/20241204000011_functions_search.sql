-- Search and Query Functions
-- Functions for full-text search, typeahead, and data retrieval

-- =====================================
-- TYPEAHEAD SEARCH FUNCTIONS
-- =====================================

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
    coalesce(p.name, '')::text as brand_name,
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

CREATE OR REPLACE FUNCTION "public"."typeahead_giveaways"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "description" "text", "product_name" "text", "end_time" timestamp with time zone, "rank" real)
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
    g.id,
    g.name::text,
    g.description::text,
    coalesce(p.name::text, '') as product_name,
    g.end_time,
    CASE 
      WHEN g.name ILIKE (query_prefix || '%') THEN 100
      WHEN g.description ILIKE (query_prefix || '%') THEN 90
      ELSE ts_rank(g.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM giveaways g
  LEFT JOIN products p ON p.id = g.product_id
  WHERE 
    g.name ILIKE (query_prefix || '%')
    OR g.description ILIKE (query_prefix || '%')
    OR g.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, g.end_time DESC
  LIMIT limit_results;
END;$$;

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
    coalesce(p.name::text, '') as profile_name,
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
    coalesce(pr.name::text, '') as profile_name,
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

CREATE OR REPLACE FUNCTION "public"."typeahead_products"("search_query" "text", "limit_results" integer DEFAULT 8) RETURNS TABLE("id" "uuid", "name" "text", "category_name" "text", "thumbnail_url" "text", "rank" real)
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
    p.name::text,
    coalesce(pc.name::text, '') as category_name,
    coalesce(cf.secure_url::text, '') as thumbnail_url,
    CASE 
      WHEN p.name ILIKE (query_prefix || '%') THEN 100
      ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM products p
  LEFT JOIN product_categories pc ON pc.id = p.category_id
  LEFT JOIN cloud_files cf ON cf.id = p.thumbnail_id
  WHERE 
    p.name ILIKE (query_prefix || '%')
    OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, p.name
  LIMIT limit_results;
END;$$;

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
    p.name::text,
    p.username::text,
    coalesce(cf.secure_url, '') as profile_picture_url,
    CASE 
      WHEN p.username ILIKE (query_prefix || '%') THEN 100
      WHEN p.name ILIKE (query_prefix || '%') THEN 90
      ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM profiles p
  LEFT JOIN cloud_files cf ON cf.id = p.profile_picture_id
  WHERE 
    p.name ILIKE (query_prefix || '%')
    OR p.username ILIKE (query_prefix || '%')
    OR p.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, p.name
  LIMIT limit_results;
END;$$;

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
      p.name::text as display_name,
      '@' || coalesce(p.username::text, '') as secondary_text,
      CASE 
        WHEN p.username ILIKE (query_prefix || '%') THEN 100
        WHEN p.name ILIKE (query_prefix || '%') THEN 90
        ELSE ts_rank(p.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM profiles p
    WHERE 
      p.name ILIKE (query_prefix || '%')
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
      coalesce(p.name, '') as secondary_text,
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
      coalesce(p.name, '') as secondary_text,
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

-- =====================================
-- UNIVERSAL SEARCH FUNCTIONS
-- =====================================

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
               ts_headline('english', coalesce(pr.name, ''), query) as headline
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

-- =====================================
-- EMAIL / MESSAGING FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."send_email_message"("message" "jsonb") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $_$
DECLARE
  email_provider text := 'mailgun';
  retval json;
  messageid text;
BEGIN
  IF message->'text_body' IS NULL AND message->'html_body' IS NULL AND message->'template' IS NULL THEN RAISE 'message.text_body or message.html_body is required'; END IF;
  
  IF message->'text_body' IS NULL AND message->'html_body' IS NULL AND message->'template' IS NULL THEN RAISE 'message.template is required'; END IF;

  IF message->'text_body' IS NULL AND message->'template' IS NULL THEN     
     select message || jsonb_build_object('text_body',message->>'html_body') into message;
  END IF;
  
  IF message->'html_body' IS NULL AND message->'template' IS NULL THEN 
     select message || jsonb_build_object('html_body',message->>'text_body') into message;
  END IF;  

  IF message->'recipient' IS NULL THEN RAISE 'message.recipient is required'; END IF;
  IF message->'sender' IS NULL THEN RAISE 'message.sender is required'; END IF;
  IF message->'subject' IS NULL THEN RAISE 'message.subject is required'; END IF;

  RAISE WARNING 'Message %', message;

  EXECUTE 'SELECT send_email_' || email_provider || '($1)' INTO retval USING message;

  RETURN retval;
END;
$_$;

CREATE OR REPLACE FUNCTION "public"."send_push_noti"("message" "text", "devices" "json", "data_type" "text", "campaign" "text", "app_url" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
   BEGIN
        return (SELECT status from http((
                     'POST',
                     'https://onesignal.com/api/v1/notifications',
                     ARRAY[
                        http_header('Authorization','Bearer NzRlNzg5OTctOWIzYy00NjgyLThiZTYtYWJkOWJlYmE0YjE3')
                     ],
                     'application/json',
                     jsonb_build_object(
                        'app_id','1aa58377-7be7-4a0d-a6bc-41437a2f4c08',
                        'include_external_user_ids', devices,
                        'external_id', gen_random_uuid(),
                        'contents', jsonb_build_object('en', message),
                        'content_available', 1,
                        'data', jsonb_build_object('type', data_type),
                        'name', campaign,
                        'app_url', app_url
                        )::jsonb
                  )::http_request));
    END;
$$;

-- =====================================
-- SLUG FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."slugify"("value" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $_$
  WITH "unaccented" AS (
    SELECT unaccent("value") AS "value"
  ),
  "lowercase" AS (
    SELECT lower("value") AS "value"
    FROM "unaccented"
  ),
  "hyphenated" AS (
    SELECT regexp_replace("value", '[^a-z0-9\\-_]+', '-', 'gi') AS "value"
    FROM "lowercase"
  ),
  "trimmed" AS (
    SELECT regexp_replace(regexp_replace("value", '\\-+$', ''), '^\\-', '') AS "value"
    FROM "hyphenated"
  )
  SELECT "value" FROM "trimmed";
$_$;

CREATE OR REPLACE FUNCTION "public"."slugify_varchar"("v" character varying) RETURNS character varying
    LANGUAGE "plpgsql" IMMUTABLE STRICT
    AS $$
BEGIN
  RETURN trim(BOTH '-' FROM regexp_replace(lower(unaccent(trim(v))), '[^a-z0-9\\-_]+', '-', 'gi'));
END;
$$;

CREATE OR REPLACE FUNCTION "public"."set_slug_from_name"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$declare
  newslug text;
BEGIN
  IF (NEW.name IS DISTINCT FROM OLD.name) THEN
  raise info 'Name %', NEW.name;
  newslug := slugify(NEW.name);
  
  NEW.slug := newslug;
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION "public"."set_slug_from_username"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.slug := slugify(NEW.username);
  RETURN NEW;
END
$$;

-- =====================================
-- FTS UPDATE FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."update_locations_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.about_us, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.name FROM profiles p WHERE p.id = NEW.brand_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.address1, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.address2, '')), 'C') ||
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

CREATE OR REPLACE FUNCTION "public"."update_lists_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.name FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.username FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM lists_products lp 
       JOIN products p ON p.id = lp.products_id 
       WHERE lp.lists_id = NEW.id), ''
    )), 'C');
  
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_posts_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.message, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.url, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.name FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT p.username FROM profiles p WHERE p.id = NEW.profile_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM posts_products pp 
       JOIN products p ON p.id = pp.products_id 
       WHERE pp.posts_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pc.name, ' ') 
       FROM posts_products pp 
       JOIN products p ON p.id = pp.products_id 
       JOIN product_categories pc ON pc.id = p.category_id 
       WHERE pp.posts_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(pt.tag, ' ') 
       FROM posts_hashtags ph 
       JOIN post_tags pt ON pt.id = ph.post_tags_id 
       WHERE ph.posts_id = NEW.id), ''
    )), 'D');
  
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_products_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.cached_brand_names := (
    SELECT string_agg(p.name, ' ') 
    FROM product_brands pb 
    JOIN profiles p ON p.id = pb.profile_id 
    WHERE pb.products_id = NEW.id
  );
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.name FROM product_categories pc WHERE pc.id = NEW.category_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(p.name, ' ') 
       FROM product_brands pb 
       JOIN profiles p ON p.id = pb.profile_id 
       WHERE pb.products_id = NEW.id), ''
    )), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.slug, '')), 'D') ||
    setweight(to_tsvector('english', coalesce(NEW.url, '')), 'D');
  
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_profiles_fts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.fts_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.username, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.slug, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.instagram, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.twitter, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.website, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.email, '')), 'D');
  
  RETURN NEW;
END;
$$;

-- =====================================
-- HELPER UPDATE FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."update_product_cached_brands"("product_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  brand_names text;
BEGIN
  SELECT COALESCE(string_agg(p.name, ' '), '') INTO brand_names
  FROM product_brands pb 
  JOIN profiles p ON p.id = pb.profile_id 
  WHERE pb.products_id = product_id;
  
  UPDATE products 
  SET cached_brand_names = brand_names
  WHERE id = product_id;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_products_fts_manual"("product_row" "public"."products") RETURNS "tsvector"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN
    setweight(to_tsvector('english', coalesce(product_row.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(product_row.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (SELECT pc.name FROM product_categories pc WHERE pc.id = product_row.category_id), ''
    )), 'B') ||
    setweight(to_tsvector('english', coalesce(product_row.cached_brand_names, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(product_row.slug, '')), 'D') ||
    setweight(to_tsvector('english', coalesce(product_row.url, '')), 'D');
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_null_cached_brand_names"() RETURNS TABLE("product_id" bigint, "product_name" "text", "old_cached_brand_names" "text", "new_cached_brand_names" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    product_record RECORD;
    new_brand_names text;
BEGIN
    FOR product_record IN SELECT * FROM products WHERE cached_brand_names IS NULL
    LOOP
        SELECT string_agg(p.name, ' ') INTO new_brand_names
        FROM product_brands pb 
        JOIN profiles p ON p.id = pb.profile_id 
        WHERE pb.products_id = product_record.id;
        
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

CREATE OR REPLACE FUNCTION "public"."update_products_fts_data"() RETURNS TABLE("product_id" bigint, "product_name" "text", "was_null" boolean, "old_value" "text", "new_value" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    product_record RECORD;
    new_brand_names text;
BEGIN
    FOR product_record IN SELECT * FROM products WHERE cached_brand_names IS NULL
    LOOP
        SELECT string_agg(p.name, ' ') INTO new_brand_names
        FROM product_brands pb 
        JOIN profiles p ON p.id = pb.profile_id 
        WHERE pb.products_id = product_record.id;
        
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

-- =====================================
-- ASSOCIATED DATA UPDATE FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."update_associated_data"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    UPDATE products SET updated_at = NOW() WHERE products.id = ANY(select products_id from product_brands where profile_id = NEW.id);
    UPDATE posts SET updated_at = NOW() WHERE profile_id = NEW.id;
    UPDATE locations SET updated_at = NOW() WHERE brand_id = NEW.id;
    UPDATE lists SET updated_at = NOW() WHERE profile_id = NEW.id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_subscription_count"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE lists
        SET subscription_count = subscription_count + 1
        WHERE id = NEW.list_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE lists
        SET subscription_count = subscription_count - 1
        WHERE id = OLD.list_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_employee_approval"("p_location_id" "uuid", "p_profile_id" "uuid", "p_is_approved" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE location_employees
  SET 
    has_been_reviewed = TRUE,
    is_approved = p_is_approved
  WHERE 
    location_id = p_location_id
    AND profile_id = p_profile_id;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."update_notification_image_url"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    SET search_path = '';
    
    IF NEW.actor_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.profiles p
            ON p.profile_picture_id = f.id
            WHERE p.id = NEW.actor_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    IF NEW.product_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.products p
            ON p.thumbnail_id = f.id
            WHERE p.id = NEW.product_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    IF NEW.post_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.posts po
            ON po.file_id = f.id
            WHERE po.id = NEW.post_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    IF NEW.giveaway_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.giveaways g
            ON g.cover_id = f.id
            WHERE g.id = NEW.giveaway_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    IF NEW.list_id IS NOT NULL THEN
        UPDATE public.notifications
        SET image_url = (
            SELECT f.secure_url
            FROM public.cloud_files f
            LEFT JOIN public.lists l
            ON l.thumbnail_id = f.id
            WHERE l.id = NEW.list_id
            LIMIT 1
        )
        WHERE id = NEW.id AND image_url IS NULL;
    END IF;
    
    RETURN NEW;
END;
$$;

-- =====================================
-- FEATURED ITEMS FUNCTION
-- =====================================

CREATE OR REPLACE FUNCTION "public"."set_initial_featured_item_sort_order"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.sort_order IS NULL THEN
        NEW.sort_order := (
            SELECT COALESCE(MAX(sort_order), -1) + 1
            FROM public.featured_items
            WHERE item_type = NEW.item_type
        );
    END IF;
    RETURN NEW;
END;
$$;

-- =====================================
-- TEST FUNCTIONS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."test_credentials"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF (NEW.phone = ANY(array['+12125551212', '+15185551212'])) THEN
        NEW.confirmation_token := '123456';
    END IF;
    RETURN NEW;
END;
$$;

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
    COUNT(pb.profile_id),
    COALESCE(string_agg(p.name, ' '), ''),
    EXTRACT(MILLISECONDS FROM (clock_timestamp() - start_time))
  INTO product_name, brand_count, brand_names, query_time_ms
  FROM products pr
  LEFT JOIN product_brands pb ON pb.products_id = product_id
  LEFT JOIN profiles p ON p.id = pb.profile_id
  WHERE pr.id = product_id
  GROUP BY pr.id;
  
  RETURN NEXT;
END;
$$;

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
    COUNT(pb.profile_id),
    COALESCE(string_agg(p.name, ' '), ''),
    EXTRACT(MILLISECONDS FROM (clock_timestamp() - start_time))
  INTO product_name, brand_count, brand_names, query_time_ms
  FROM products pr
  LEFT JOIN product_brands pb ON pb.products_id = product_id
  LEFT JOIN profiles p ON p.id = pb.profile_id
  WHERE pr.id = product_id
  GROUP BY pr.id;
  
  RETURN NEXT;
END;
$$;
