-- Fix search_universal to return 'snippet' instead of 'headline' to match Swift Codable struct
-- Also ensures compatibility with FeedManager

-- Drop the function first to avoid ambiguity and ensure clean replacement
DROP FUNCTION IF EXISTS public.search_universal(text, text, text, integer, integer, uuid[], text, text);

CREATE OR REPLACE FUNCTION search_universal(
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
BEGIN
    -- 1. Construct the tsquery (with partial matching support)
    IF search_query IS NULL OR trim(search_query) = '' THEN
        query := ''::tsquery;
    ELSE
        BEGIN
            -- Attempt to create a prefix-matching query
            -- e.g. "Harry Pot" -> "Harry:* & Pot:*"
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
            -- Fallback
            query := websearch_to_tsquery('english', search_query);
        END;
    END IF;

    -- 2. Build dynamic SQL
    -- We use $1, $2, etc. for parameters to avoid formatting issues and SQL injection
    -- Changed 'headline' to 'snippet' in the SELECT list
    -- Changed t.id to t.public_id to return UUIDs and match exclude_ids type
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
        fts_vector_column, -- %I for ts_rank vector column
        headline_column,   -- %I for ts_headline text column
        table_name,        -- %I for table name
        fts_vector_column, -- %I for WHERE clause vector column
        filter_clause      -- %s for filter clause (raw SQL)
    );

    -- 3. Execute with parameters
    RETURN QUERY EXECUTE full_query 
    USING query, exclude_ids, result_limit, result_offset;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions using the specific signature to avoid ambiguity
GRANT EXECUTE ON FUNCTION public.search_universal(text, text, text, integer, integer, uuid[], text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.search_universal(text, text, text, integer, integer, uuid[], text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_universal(text, text, text, integer, integer, uuid[], text, text) TO service_role;

