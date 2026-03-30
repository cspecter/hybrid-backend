-- Add Super Admin policies to all application tables
-- This migration ensures that:
-- 1. RLS is enabled on all public tables (excluding Directus system tables)
-- 2. Super Admins (role_id = 9) have full access (ALL operations) to all tables

-- Create super_admins table to break recursion loop
CREATE TABLE IF NOT EXISTS public.super_admins (
    auth_id uuid PRIMARY KEY,
    created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.super_admins ENABLE ROW LEVEL SECURITY;

-- Populate initially
INSERT INTO public.super_admins (auth_id)
SELECT auth_id FROM public.profiles WHERE role_id = 9
ON CONFLICT DO NOTHING;

-- Trigger to sync super admins
CREATE OR REPLACE FUNCTION public.sync_super_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        IF NEW.role_id = 9 THEN
            INSERT INTO public.super_admins (auth_id) VALUES (NEW.auth_id) ON CONFLICT DO NOTHING;
        ELSE
            DELETE FROM public.super_admins WHERE auth_id = NEW.auth_id;
        END IF;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM public.super_admins WHERE auth_id = OLD.auth_id;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_super_admin ON public.profiles;
CREATE TRIGGER trg_sync_super_admin
AFTER INSERT OR UPDATE OR DELETE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.sync_super_admin();

-- Update is_super_admin to use the new table
-- This breaks the recursion because it no longer queries 'profiles'
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.super_admins 
        WHERE auth_id = auth.uid()
    );
$$;

DO $$
DECLARE
    t text;
BEGIN
    FOR t IN 
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
          AND table_type = 'BASE TABLE'
          AND table_name NOT LIKE 'directus_%'
          AND table_name NOT LIKE 'pg_%'
          AND table_name NOT LIKE 'sql_%'
          AND table_name != '_prisma_migrations'
          AND table_name != 'super_admins' -- Exclude the admin table itself to avoid any loops
    LOOP
        -- 1. Enable RLS (idempotent operation)
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);

        -- 2. Add Super Admin Policy if it doesn't exist
        IF NOT EXISTS (
            SELECT 1 
            FROM pg_policies 
            WHERE schemaname = 'public' 
              AND tablename = t 
              AND policyname = 'Super admins can do everything'
        ) THEN
            EXECUTE format('
                CREATE POLICY "Super admins can do everything" ON public.%I
                FOR ALL
                TO authenticated
                USING (public.is_super_admin());
            ', t);
        END IF;
    END LOOP;
END $$;
