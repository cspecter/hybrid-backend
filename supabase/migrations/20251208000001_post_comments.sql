-- ============================================================================
-- POST COMMENTS TABLE
-- Allows users to comment on posts
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.post_comments (
    id integer NOT NULL,
    public_id uuid NOT NULL DEFAULT gen_random_uuid(),
    
    -- Content
    message text NOT NULL,
    
    -- Relations
    post_id integer NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    profile_id integer NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    parent_id integer REFERENCES public.post_comments(id) ON DELETE CASCADE, -- For nested replies
    
    -- Moderation
    is_hidden boolean DEFAULT false,
    is_flagged boolean DEFAULT false,
    
    -- Counts
    like_count integer DEFAULT 0,
    reply_count integer DEFAULT 0,
    
    -- Timestamps
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    
    CONSTRAINT post_comments_pkey PRIMARY KEY (id),
    CONSTRAINT post_comments_public_id_key UNIQUE (public_id)
);

ALTER TABLE public.post_comments OWNER TO postgres;

-- Create sequence for auto-incrementing id
CREATE SEQUENCE IF NOT EXISTS public.post_comments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.post_comments_id_seq OWNER TO postgres;
ALTER SEQUENCE public.post_comments_id_seq OWNED BY public.post_comments.id;
ALTER TABLE ONLY public.post_comments ALTER COLUMN id SET DEFAULT nextval('public.post_comments_id_seq'::regclass);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_post_comments_post_id ON public.post_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_post_comments_profile_id ON public.post_comments(profile_id);
CREATE INDEX IF NOT EXISTS idx_post_comments_parent_id ON public.post_comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_post_comments_public_id ON public.post_comments(public_id);
CREATE INDEX IF NOT EXISTS idx_post_comments_created_at ON public.post_comments(created_at DESC);

-- ============================================================================
-- ADD COMMENT COUNT TO POSTS TABLE
-- ============================================================================

ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS comment_count integer DEFAULT 0;

-- ============================================================================
-- TRIGGER TO UPDATE COMMENT COUNT ON POSTS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_update_post_comment_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Only count top-level comments (parent_id IS NULL)
        IF NEW.parent_id IS NULL THEN
            UPDATE public.posts SET comment_count = comment_count + 1 WHERE id = NEW.post_id;
        ELSE
            -- Update reply count on parent comment
            UPDATE public.post_comments SET reply_count = reply_count + 1 WHERE id = NEW.parent_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.parent_id IS NULL THEN
            UPDATE public.posts SET comment_count = GREATEST(0, comment_count - 1) WHERE id = OLD.post_id;
        ELSE
            UPDATE public.post_comments SET reply_count = GREATEST(0, reply_count - 1) WHERE id = OLD.parent_id;
        END IF;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_post_comment_count ON public.post_comments;
CREATE TRIGGER trg_update_post_comment_count
    AFTER INSERT OR DELETE ON public.post_comments
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_update_post_comment_count();

-- ============================================================================
-- TIMESTAMPS TRIGGER
-- ============================================================================

DROP TRIGGER IF EXISTS set_post_comments_updated_at ON public.post_comments;
CREATE TRIGGER set_post_comments_updated_at
    BEFORE UPDATE ON public.post_comments
    FOR EACH ROW
    EXECUTE FUNCTION public.manage_timestamps();

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

-- Anyone can read comments
CREATE POLICY "post_comments_select_policy" ON public.post_comments
    FOR SELECT USING (true);

-- Authenticated users can insert their own comments
CREATE POLICY "post_comments_insert_policy" ON public.post_comments
    FOR INSERT WITH CHECK (
        profile_id IN (
            SELECT id FROM public.profiles WHERE auth_id = auth.uid()
        )
    );

-- Users can update their own comments
CREATE POLICY "post_comments_update_policy" ON public.post_comments
    FOR UPDATE USING (
        profile_id IN (
            SELECT id FROM public.profiles WHERE auth_id = auth.uid()
        )
    );

-- Users can delete their own comments, or post owners can delete comments on their posts
CREATE POLICY "post_comments_delete_policy" ON public.post_comments
    FOR DELETE USING (
        profile_id IN (
            SELECT id FROM public.profiles WHERE auth_id = auth.uid()
        )
        OR post_id IN (
            SELECT p.id FROM public.posts p
            JOIN public.profiles pr ON p.profile_id = pr.id
            WHERE pr.auth_id = auth.uid()
        )
    );

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT ALL ON TABLE public.post_comments TO anon;
GRANT ALL ON TABLE public.post_comments TO authenticated;
GRANT ALL ON TABLE public.post_comments TO service_role;
GRANT ALL ON SEQUENCE public.post_comments_id_seq TO anon;
GRANT ALL ON SEQUENCE public.post_comments_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.post_comments_id_seq TO service_role;
