-- Dedicated product search RPC with server-side filters and sorting.
-- Keeps search_universal generic while allowing product-specific tuning.

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
BEGIN
  normalized_sort := lower(coalesce(p_sort_order, 'desc'));
  IF normalized_sort NOT IN ('asc', 'desc') THEN
    normalized_sort := 'desc';
  END IF;

  IF coalesce(trim(p_search_query), '') <> '' THEN
    tsq := plainto_tsquery('english', p_search_query);
  END IF;

  RETURN QUERY
  WITH filtered AS (
    SELECT
      p.public_id,
      COALESCE(ts_rank_cd(p.fts_vector, tsq), 0)::real AS rank_val,
      p.description,
      p.release_date
    FROM products p
    WHERE
      (tsq IS NULL OR p.fts_vector @@ tsq)
      AND (p_exclude_ids IS NULL OR p.public_id <> ALL(p_exclude_ids))
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
