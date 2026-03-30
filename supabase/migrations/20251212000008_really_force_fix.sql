-- Force fix for all FTS and Search functions
-- This migration explicitly drops and recreates functions that have been problematic
-- to ensure the correct schema column names are used.

-- 1. Fix update_profiles_fts (Fixes "record new has no field description")
DROP TRIGGER IF EXISTS profiles_fts_update ON public.profiles;
DROP FUNCTION IF EXISTS public.update_profiles_fts();

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

CREATE TRIGGER profiles_fts_update
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_profiles_fts();

-- 2. Fix typeahead_locations (Fixes "column address1 does not exist")
DROP FUNCTION IF EXISTS public.typeahead_locations(text, integer);

CREATE OR REPLACE FUNCTION "public"."typeahead_locations"("search_query" "text", "limit_results" integer DEFAULT 8) 
RETURNS TABLE("id" "uuid", "name" "text", "address1" "text", "address2" "text", "brand_name" "text", "place_name" "text", "state" "text", "postal_code" "text", "rank" real)
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
    l.address_line1::text as address1,
    l.address_line2::text as address2,
    coalesce(p.display_name, '')::text as brand_name,
    coalesce(pc.place_name, '')::text as place_name,
    coalesce(pc.state, '')::text as state,
    coalesce(pc.postal_code, '')::text as postal_code,
    CASE 
      WHEN l.name ILIKE (query_prefix || '%') THEN 100
      WHEN l.address_line1 ILIKE (query_prefix || '%') THEN 95
      WHEN pc.place_name ILIKE (query_prefix || '%') THEN 90
      WHEN pc.state ILIKE (query_prefix || '%') THEN 85
      ELSE ts_rank(l.fts_vector, plainto_tsquery('english', query_prefix))
    END as rank
  FROM locations l
  LEFT JOIN profiles p ON p.id = l.brand_id
  LEFT JOIN postal_codes pc ON pc.id = l.postal_code_id
  WHERE 
    l.name ILIKE (query_prefix || '%')
    OR l.address_line1 ILIKE (query_prefix || '%')
    OR pc.place_name ILIKE (query_prefix || '%')
    OR pc.state ILIKE (query_prefix || '%')
    OR l.fts_vector @@ plainto_tsquery('english', query_prefix)
  ORDER BY rank DESC, l.name
  LIMIT limit_results;
END;
$$;

-- 3. Fix typeahead_universal (Fixes "column address1 does not exist")
DROP FUNCTION IF EXISTS public.typeahead_universal(text, integer);

CREATE OR REPLACE FUNCTION "public"."typeahead_universal"("search_query" "text", "limit_results" integer DEFAULT 8) 
RETURNS TABLE("table_name" "text", "id" "uuid", "display_name" "text", "secondary_text" "text", "rank" real)
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
      coalesce(pc.place_name || ', ' || pc.state, l.address_line1) as secondary_text,
      CASE 
        WHEN l.name ILIKE (query_prefix || '%') THEN 100
        WHEN l.address_line1 ILIKE (query_prefix || '%') THEN 95
        WHEN pc.place_name ILIKE (query_prefix || '%') THEN 90
        WHEN pc.state ILIKE (query_prefix || '%') THEN 85
        ELSE ts_rank(l.fts_vector, plainto_tsquery('english', query_prefix))
      END as rank
    FROM locations l
    LEFT JOIN postal_codes pc ON pc.id = l.postal_code_id
    WHERE 
      l.name ILIKE (query_prefix || '%')
      OR l.address_line1 ILIKE (query_prefix || '%')
      OR pc.place_name ILIKE (query_prefix || '%')
      OR pc.state ILIKE (query_prefix || '%')
      OR l.fts_vector @@ plainto_tsquery('english', query_prefix)
  )
  ORDER BY rank DESC
  LIMIT limit_results;
END;$$;
