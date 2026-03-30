-- Optimize product search performance for filtered product search in SearchView.
-- Key improvements:
-- 1) Use indexed products.fts_vector instead of rebuilding vectors per row.
-- 2) Restrict non-FTS fallback matching to exact/prefix name and brand checks.
-- 3) Add supporting indexes for common filter paths.

CREATE INDEX IF NOT EXISTS idx_products_states_state_id_product_id
ON public.products_states USING btree (state_id, product_id);

CREATE INDEX IF NOT EXISTS idx_products_category_release_public
ON public.products USING btree (category_id, release_date DESC, public_id);

CREATE INDEX IF NOT EXISTS idx_products_release_public
ON public.products USING btree (release_date DESC, public_id);

CREATE INDEX IF NOT EXISTS idx_products_lower_name_pattern
ON public.products (lower(name) text_pattern_ops);

CREATE INDEX IF NOT EXISTS idx_products_lower_cached_brand_names_pattern
ON public.products (lower(cached_brand_names) text_pattern_ops);

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
  WITH filtered AS (
    SELECT
      p.public_id,
      p.description,
      p.release_date,
      (
        COALESCE(ts_rank_cd(p.fts_vector, tsq, 32), 0)::real
        + CASE
            WHEN search_term = '' THEN 0
            WHEN lower(coalesce(p.name, '')) = search_term THEN 6
            WHEN lower(coalesce(p.name, '')) LIKE search_term || '%' THEN 3
            WHEN lower(coalesce(p.name, '')) LIKE '%' || search_term || '%' THEN 1.5
            ELSE 0
          END
        + CASE
            WHEN search_term = '' THEN 0
            WHEN lower(coalesce(p.cached_brand_names, '')) = search_term THEN 4
            WHEN lower(coalesce(p.cached_brand_names, '')) LIKE search_term || '%' THEN 2
            WHEN lower(coalesce(p.cached_brand_names, '')) LIKE '%' || search_term || '%' THEN 1
            ELSE 0
          END
      )::real AS rank_val
    FROM public.products p
    WHERE
      (p_exclude_ids IS NULL OR p.public_id <> ALL(p_exclude_ids))
      AND (p_category_id IS NULL OR p.category_id = p_category_id)
      AND (
        p_state_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM public.products_states ps
          WHERE ps.product_id = p.id
            AND ps.state_id = p_state_id
        )
      )
      AND (p_start_date IS NULL OR p.release_date >= p_start_date)
      AND (p_end_date IS NULL OR p.release_date <= p_end_date)
      AND (
        search_term = ''
        OR p.fts_vector @@ tsq
        OR lower(coalesce(p.name, '')) = search_term
        OR lower(coalesce(p.name, '')) LIKE search_term || '%'
        OR lower(coalesce(p.cached_brand_names, '')) = search_term
        OR lower(coalesce(p.cached_brand_names, '')) LIKE search_term || '%'
      )
  ),
  counted AS (
    SELECT
      f.public_id,
      f.rank_val,
      f.description,
      f.release_date,
      COUNT(*) OVER() AS total_count
    FROM filtered f
  )
  SELECT
    c.public_id AS id,
    c.rank_val AS rank,
    LEFT(COALESCE(c.description, ''), 200) AS snippet,
    c.total_count
  FROM counted c
  ORDER BY
    CASE WHEN search_term <> '' THEN c.rank_val END DESC,
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
