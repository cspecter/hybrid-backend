-- Update search_universal to handle empty search queries with default/featured items

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
BEGIN
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
            -- Products need a join to check brand
            featured_condition := 't.id IN (SELECT product_id FROM public.product_brands WHERE brand_id IN (SELECT item_id FROM public.featured_items WHERE item_type = ''profiles''))';
        ELSIF table_name = 'locations' THEN
            featured_condition := 't.brand_id IN (SELECT item_id FROM public.featured_items WHERE item_type = ''profiles'')';
        ELSIF table_name = 'lists' OR table_name = 'posts' THEN
            featured_condition := 't.profile_id IN (SELECT item_id FROM public.featured_items WHERE item_type = ''profiles'')';
        ELSE
            -- Fallback for other tables (no featured logic)
            featured_condition := 'FALSE';
        END IF;

        -- Construct query with boosting for featured items
        -- We use rank 1.0 for featured items, 0.0 for others
        -- This ensures featured items come first, then backfilled with others
        full_query := format(
            'WITH search_results AS (
                SELECT
                    t.public_id as id,
                    CASE 
                        WHEN %s THEN 1.0 
                        ELSE 0.0 
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

    -- 2. Normal Search Logic (Existing)
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

    full_query := format(
        'WITH search_results AS (
            SELECT
                t.public_id as id,
                ts_rank(t.%I, $1) as rank,
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
        headline_column,
        table_name,
        fts_vector_column,
        filter_clause
    );

    RETURN QUERY EXECUTE full_query 
    USING query, exclude_ids, result_limit, result_offset;
END;
$$ LANGUAGE plpgsql;
