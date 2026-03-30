-- Prioritize product name and brand matches over description-only matches in product search.

CREATE OR REPLACE FUNCTION public.search_products(
  p_search_query text DEFAULT '',
  p_result_limit integer DEFAULT 20,
  p_result_offset integer DEFAULT 0,
  p_exclude_ids uuid[] DEFAULT '{}'::uuid[],
  p_category_id integer DEFAULT NULL,
  p_state_id integer DEFAULT NULL,
  p_start_date timestamptz DEFAULT NULL,
  p_end_date timestamptz DEFAULT NULL,
  p_sort_order text DEFAULT 'desc'
)
RETURNS TABLE (
  id uuid,
  rank real,
  snippet text,
  total_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  tsq tsquery;
  normalized_sort text;
  search_term text;
BEGIN
  normalized_sort := lower(coalesce(p_sort_order, 'desc'));
  IF normalized_sort NOT IN ('asc', 'desc') THEN
    normalized_sort := 'desc';
  END IF;

  search_term := lower(trim(coalesce(p_search_query, '')));

  IF search_term <> '' THEN
    BEGIN
      tsq := websearch_to_tsquery('english', p_search_query);
    EXCEPTION WHEN OTHERS THEN
      tsq := plainto_tsquery('english', p_search_query);
    END;
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      p.public_id,
      p.name,
      p.cached_brand_names,
      p.description,
      p.release_date,
      (
        setweight(to_tsvector('english', coalesce(p.name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(p.cached_brand_names, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(p.slug, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(p.description, '')), 'D')
      ) AS search_vector
    FROM products p
    WHERE
      (p_exclude_ids IS NULL OR p.public_id <> ALL(p_exclude_ids))
      AND (p_category_id IS NULL OR p.category_id = p_category_id)
      AND (
        p_state_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM products_states ps
          WHERE ps.product_id = p.id
            AND ps.state_id = p_state_id
        )
      )
      AND (p_start_date IS NULL OR p.release_date >= p_start_date)
      AND (p_end_date IS NULL OR p.release_date <= p_end_date)
  ),
  filtered AS (
    SELECT
      b.public_id,
      (
        COALESCE(ts_rank_cd(b.search_vector, tsq, 32), 0)::real
        + CASE
            WHEN search_term = '' THEN 0
            WHEN lower(coalesce(b.name, '')) = search_term THEN 6
            WHEN lower(coalesce(b.name, '')) LIKE search_term || '%' THEN 3
            WHEN lower(coalesce(b.name, '')) LIKE '%' || search_term || '%' THEN 1.5
            ELSE 0
          END
        + CASE
            WHEN search_term = '' THEN 0
            WHEN lower(coalesce(b.cached_brand_names, '')) = search_term THEN 4
            WHEN lower(coalesce(b.cached_brand_names, '')) LIKE search_term || '%' THEN 2
            WHEN lower(coalesce(b.cached_brand_names, '')) LIKE '%' || search_term || '%' THEN 1
            ELSE 0
          END
      )::real AS rank_val,
      b.description,
      b.release_date
    FROM base b
    WHERE
      (
        tsq IS NULL
        OR b.search_vector @@ tsq
        OR (
          search_term <> ''
          AND (
            lower(coalesce(b.name, '')) LIKE '%' || search_term || '%'
            OR lower(coalesce(b.cached_brand_names, '')) LIKE '%' || search_term || '%'
          )
        )
      )
  ),
  counted AS (
    SELECT
      public_id,
      rank_val,
      description,
      release_date,
      COUNT(*) OVER() AS total_count
    FROM filtered
  )
  SELECT
    c.public_id AS id,
    c.rank_val AS rank,
    LEFT(COALESCE(c.description, ''), 200) AS snippet,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN tsq IS NOT NULL THEN c.rank_val END DESC,
    CASE WHEN normalized_sort = 'asc' THEN c.release_date END ASC NULLS LAST,
    CASE WHEN normalized_sort = 'desc' THEN c.release_date END DESC NULLS LAST,
    c.public_id
  LIMIT GREATEST(1, LEAST(COALESCE(p_result_limit, 20), 100))
  OFFSET GREATEST(COALESCE(p_result_offset, 0), 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_products(text, integer, integer, uuid[], integer, integer, timestamptz, timestamptz, text) TO anon;
GRANT EXECUTE ON FUNCTION public.search_products(text, integer, integer, uuid[], integer, integer, timestamptz, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_products(text, integer, integer, uuid[], integer, integer, timestamptz, timestamptz, text) TO service_role;
