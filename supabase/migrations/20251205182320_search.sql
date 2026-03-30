-- UNIVERSAL SEARCH RPC FUNCTION
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
RETURNS TABLE(id UUID, rank REAL, headline TEXT, total_count INTEGER) AS $$
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
    full_query := format(
        'WITH search_results AS (
            SELECT
                t.id,
                ts_rank(t.%I, $1) as rank,
                ts_headline(t.%I, $1) as headline,
                count(*) OVER()::INTEGER as total_count
            FROM %I t
            WHERE t.%I @@ $1
            AND ($2 IS NULL OR t.id <> ALL($2))
            %s
            ORDER BY rank DESC
            LIMIT $3 OFFSET $4
        )
        SELECT id, rank, headline, total_count FROM search_results',
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

-- Create search_history table
CREATE TABLE IF NOT EXISTS public.search_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id INTEGER REFERENCES public.profiles(id) ON DELETE CASCADE,
    query TEXT NOT NULL,
    search_type TEXT NOT NULL,
    result_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create saved_searches table
CREATE TABLE IF NOT EXISTS public.saved_searches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id INTEGER REFERENCES public.profiles(id) ON DELETE CASCADE,
    query TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create search_interactions table
CREATE TABLE IF NOT EXISTS public.search_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id INTEGER REFERENCES public.profiles(id) ON DELETE CASCADE,
    query TEXT NOT NULL,
    result_id TEXT NOT NULL,
    position INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.search_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_searches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_interactions ENABLE ROW LEVEL SECURITY;

-- Policies for search_history
CREATE POLICY "Users can view their own search history" ON public.search_history
    FOR SELECT USING (auth.uid() = (SELECT auth_id FROM public.profiles WHERE id = profile_id));

CREATE POLICY "Users can insert their own search history" ON public.search_history
    FOR INSERT WITH CHECK (auth.uid() = (SELECT auth_id FROM public.profiles WHERE id = profile_id));

-- Policies for saved_searches
CREATE POLICY "Users can view their own saved searches" ON public.saved_searches
    FOR SELECT USING (auth.uid() = (SELECT auth_id FROM public.profiles WHERE id = profile_id));

CREATE POLICY "Users can manage their own saved searches" ON public.saved_searches
    FOR ALL USING (auth.uid() = (SELECT auth_id FROM public.profiles WHERE id = profile_id));

-- Policies for search_interactions
CREATE POLICY "Users can insert their own interactions" ON public.search_interactions
    FOR INSERT WITH CHECK (auth.uid() = (SELECT auth_id FROM public.profiles WHERE id = profile_id));

-- Function: record_search_history
CREATE OR REPLACE FUNCTION public.record_search_history(
    query TEXT,
    search_type TEXT,
    result_count INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_profile_id INTEGER;
BEGIN
    -- Get the profile_id for the current user
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    
    -- Insert search history (allow null profile_id for anonymous searches)
    INSERT INTO public.search_history (profile_id, query, search_type, result_count)
    VALUES (v_profile_id, query, search_type, result_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: get_search_history
CREATE OR REPLACE FUNCTION public.get_search_history(
    p_profile_id UUID,
    limit_val INTEGER
)
RETURNS TABLE (
    id UUID,
    query TEXT,
    term TEXT,
    "timestamp" TIMESTAMP WITH TIME ZONE,
    "resultCount" INTEGER
) AS $$
DECLARE
    v_profile_id INTEGER;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE public_id = p_profile_id;

    RETURN QUERY
    SELECT 
        sh.id, 
        sh.query, 
        sh.query as term, 
        sh.created_at as "timestamp", 
        sh.result_count as "resultCount"
    FROM public.search_history sh
    WHERE sh.profile_id = v_profile_id
    ORDER BY sh.created_at DESC
    LIMIT limit_val;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: save_search_query
CREATE OR REPLACE FUNCTION public.save_search_query(
    query TEXT,
    p_profile_id UUID
)
RETURNS VOID AS $$
DECLARE
    v_profile_id INTEGER;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE public_id = p_profile_id;

    INSERT INTO public.saved_searches (profile_id, query)
    VALUES (v_profile_id, save_search_query.query);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: get_saved_searches
CREATE OR REPLACE FUNCTION public.get_saved_searches(
    p_profile_id UUID,
    limit_val INTEGER
)
RETURNS TABLE (
    id UUID,
    query TEXT,
    term TEXT,
    "timestamp" TIMESTAMP WITH TIME ZONE,
    "resultCount" INTEGER
) AS $$
DECLARE
    v_profile_id INTEGER;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE public_id = p_profile_id;

    RETURN QUERY
    SELECT 
        ss.id, 
        ss.query, 
        ss.query as term, 
        ss.created_at as "timestamp", 
        0 as "resultCount"
    FROM public.saved_searches ss
    WHERE ss.profile_id = v_profile_id
    ORDER BY ss.created_at DESC
    LIMIT limit_val;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: delete_saved_search
CREATE OR REPLACE FUNCTION public.delete_saved_search(
    search_id UUID
)
RETURNS VOID AS $$
BEGIN
    DELETE FROM public.saved_searches 
    WHERE id = search_id 
    AND profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: record_search_interaction
CREATE OR REPLACE FUNCTION public.record_search_interaction(
    query TEXT,
    result_id TEXT,
    position_val INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_profile_id INTEGER;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    
    INSERT INTO public.search_interactions (profile_id, query, result_id, position)
    VALUES (v_profile_id, query, result_id, position_val);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: get_search_suggestions
CREATE OR REPLACE FUNCTION public.get_search_suggestions(
    partial_query TEXT,
    limit_val INTEGER
)
RETURNS TABLE (
    id UUID,
    suggestion TEXT,
    type TEXT,
    count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        gen_random_uuid() as id,
        sh.query as suggestion,
        'historyType' as type,
        count(*)::INTEGER as count
    FROM public.search_history sh
    WHERE sh.query ILIKE partial_query || '%'
    GROUP BY sh.query
    ORDER BY count DESC
    LIMIT limit_val;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: get_search_analytics
CREATE OR REPLACE FUNCTION public.get_search_analytics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    -- Mock implementation returning empty analytics structure
    result := '[{
        "totalSearches": 0,
        "successfulSearches": 0,
        "averageSearchDuration": 0,
        "mostCommonTerms": {},
        "lastSearchedTerms": [],
        "searchFunnel": {
            "searchesInitiated": 0,
            "resultsDisplayed": 0,
            "conversions": 0
        }
    }]'::JSONB;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_search_history_profile ON public.search_history(profile_id);
CREATE INDEX idx_search_history_query ON public.search_history USING gin(query extensions.gin_trgm_ops);
CREATE INDEX idx_search_history_created ON public.search_history(created_at DESC);

CREATE INDEX idx_saved_searches_profile ON public.saved_searches(profile_id);

CREATE INDEX idx_search_interactions_profile ON public.search_interactions(profile_id);
CREATE INDEX idx_search_interactions_query ON public.search_interactions(query);

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT ALL ON TABLE public.search_history TO authenticated;
GRANT ALL ON TABLE public.search_history TO service_role;

GRANT ALL ON TABLE public.saved_searches TO authenticated;
GRANT ALL ON TABLE public.saved_searches TO service_role;

GRANT ALL ON TABLE public.search_interactions TO authenticated;
GRANT ALL ON TABLE public.search_interactions TO service_role;

GRANT EXECUTE ON FUNCTION public.search_universal TO anon;
GRANT EXECUTE ON FUNCTION public.search_universal TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_universal TO service_role;

GRANT EXECUTE ON FUNCTION public.record_search_history TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_search_history TO service_role;

GRANT EXECUTE ON FUNCTION public.get_search_history TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_search_history TO service_role;

GRANT EXECUTE ON FUNCTION public.save_search_query TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_search_query TO service_role;

GRANT EXECUTE ON FUNCTION public.get_saved_searches TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_saved_searches TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_saved_search TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_saved_search TO service_role;

GRANT EXECUTE ON FUNCTION public.record_search_interaction TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_search_interaction TO service_role;

GRANT EXECUTE ON FUNCTION public.get_search_suggestions TO anon;
GRANT EXECUTE ON FUNCTION public.get_search_suggestions TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_search_suggestions TO service_role;

GRANT EXECUTE ON FUNCTION public.get_search_analytics TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_search_analytics TO service_role;