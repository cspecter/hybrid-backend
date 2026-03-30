ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS restash_count integer DEFAULT 0 NOT NULL;
