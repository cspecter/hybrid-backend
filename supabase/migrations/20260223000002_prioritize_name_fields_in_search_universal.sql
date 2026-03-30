-- Prioritize entity name fields (username/display_name/product name/brand) over description-only matches
-- in search_universal ranking.

CREATE OR REPLACE FUNCTION public.search_universal(
  table_name TEXT,
  fts_vector_column TEXT,
  search_query TEXT,
  result_limit INTEGER DEFAULT 50,
  result_offset INTEGER DEFAULT 0,
  exclude_ids UUID[] DEFAULT '{}',
  filter_clause TEXT DEFAULT '',
  headline_column TEXT DEFAULT 'description'
)
RETURNS TABLE(id UUID, rank REAL, snippet TEXT, total_count INTEGER) AS $$
DECLARE
    query tsquery;
    full_query TEXT;
    featured_condition TEXT;
    rank_boost_expr TEXT;
    normalized_search TEXT;
BEGIN
    normalized_search := lower(trim(coalesce(search_query, '')));

    -- 1. Handle Empty Search Query
    IF search_query IS NULL OR trim(search_query) = '' THEN

        -- Special handling for Giveaways (just latest)
        IF table_name = 'giveaways' THEN
            full_query := format(
                'WITH search_results AS (
                    SELECT
                        t.public_id as id,
                        0::REAL as rank,
                        LEFT(t.%I, 100) as snippet,
                        count(*) OVER()::INTEGER as total_count
                    FROM %I t
                    WHERE ($1 IS NULL OR t.public_id <> ALL($1))
                    %s
                    ORDER BY t.created_at DESC
                    LIMIT $2 OFFSET $3
                )
                SELECT id, rank, snippet, total_count FROM search_results',
                headline_column,
                table_name,
                filter_clause
            );
            RETURN QUERY EXECUTE full_query USING exclude_ids, result_limit, result_offset;
            RETURN;
        END IF;

        -- Determine the condition for featured profiles based on table name
        IF table_name = 'profiles' THEN
            featured_condition := 't.id IN (SELECT item_id FROM public.featured_items WHERE item_type = ''profiles'')';
        ELSIF table_name = 'products' THEN
            featured_condition := 't.id IN (SELECT product_id FROM public.product_brands WHERE brand_id IN (SELECT item_id FROM public.featured_items WHERE item_type = ''profiles''))';
        ELSIF table_name = 'locations' THEN
            featured_condition := 't.brand_id IN (SELECT item_id FROM public.featured_items WHERE item_type = ''profiles'')';
        ELSIF table_name = 'lists' OR table_name = 'posts' THEN
            featured_condition := 't.profile_id IN (SELECT item_id FROM public.featured_items WHERE item_type = ''profiles'')';
        ELSE
            featured_condition := 'FALSE';
        END IF;

        full_query := format(
            'WITH search_results AS (
                SELECT
                    t.public_id as id,
                    CASE
                        WHEN %s THEN 1.0::REAL
                        ELSE 0.0::REAL
                    END as rank,
                    LEFT(t.%I, 100) as snippet,
                    count(*) OVER()::INTEGER as total_count
                FROM %I t
                WHERE ($1 IS NULL OR t.public_id <> ALL($1))
                %s
                ORDER BY rank DESC, t.created_at DESC
                LIMIT $2 OFFSET $3
            )
            SELECT id, rank, snippet, total_count FROM search_results',
            featured_condition,
            headline_column,
            table_name,
            filter_clause
        );

        RETURN QUERY EXECUTE full_query USING exclude_ids, result_limit, result_offset;
        RETURN;
    END IF;

    -- 2. Normal Search Logic
    BEGIN
        query := to_tsquery('english',
            array_to_string(
                ARRAY(
                    SELECT trim(token) || ':*'
                    FROM unnest(string_to_array(trim(search_query), ' ')) AS token
                    WHERE trim(token) != ''
                ),
                ' & '
            )
        );
    EXCEPTION WHEN OTHERS THEN
        query := websearch_to_tsquery('english', search_query);
    END;

    -- Per-table rank boosts so canonical name fields outrank description/bio mentions.
    IF table_name = 'profiles' THEN
        rank_boost_expr := '
            CASE
                WHEN lower(coalesce(t.username, '''')) = $5 THEN 8.0
                WHEN lower(coalesce(t.username, '''')) LIKE $5 || ''%'' THEN 4.0
                WHEN lower(coalesce(t.username, '''')) LIKE ''%'' || $5 || ''%'' THEN 2.0
                ELSE 0
            END
            +
            CASE
                WHEN lower(coalesce(t.display_name, '''')) = $5 THEN 6.0
                WHEN lower(coalesce(t.display_name, '''')) LIKE $5 || ''%'' THEN 3.0
                WHEN lower(coalesce(t.display_name, '''')) LIKE ''%'' || $5 || ''%'' THEN 1.5
                ELSE 0
            END';
    ELSIF table_name = 'products' THEN
        rank_boost_expr := '
            CASE
                WHEN lower(coalesce(t.name, '''')) = $5 THEN 8.0
                WHEN lower(coalesce(t.name, '''')) LIKE $5 || ''%'' THEN 4.0
                WHEN lower(coalesce(t.name, '''')) LIKE ''%'' || $5 || ''%'' THEN 2.0
                ELSE 0
            END
            +
            CASE
                WHEN lower(coalesce(t.cached_brand_names, '''')) = $5 THEN 6.0
                WHEN lower(coalesce(t.cached_brand_names, '''')) LIKE $5 || ''%'' THEN 3.0
                WHEN lower(coalesce(t.cached_brand_names, '''')) LIKE ''%'' || $5 || ''%'' THEN 1.5
                ELSE 0
            END';
    ELSE
        rank_boost_expr := '0.0';
    END IF;

    full_query := format(
        'WITH search_results AS (
            SELECT
                t.public_id as id,
                (ts_rank(t.%I, $1)::REAL + (%s)::REAL) as rank,
                ts_headline(t.%I, $1) as snippet,
                count(*) OVER()::INTEGER as total_count
            FROM %I t
            WHERE t.%I @@ $1
            AND ($2 IS NULL OR t.public_id <> ALL($2))
            %s
            ORDER BY rank DESC
            LIMIT $3 OFFSET $4
        )
        SELECT id, rank, snippet, total_count FROM search_results',
        fts_vector_column,
        rank_boost_expr,
        headline_column,
        table_name,
        fts_vector_column,
        filter_clause
    );

    RETURN QUERY EXECUTE full_query
    USING query, exclude_ids, result_limit, result_offset, normalized_search;
END;
$$ LANGUAGE plpgsql;
