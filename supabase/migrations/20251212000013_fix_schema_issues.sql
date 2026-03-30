-- Fix typeahead_profiles to use avatar_id instead of profile_picture_id
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

-- Fix update_locations_fts to use correct column names (address_line1 instead of address1)
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
