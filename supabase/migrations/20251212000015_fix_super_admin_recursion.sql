-- Fix infinite recursion in super admin check by introducing a separate table
-- and ensuring the check function does not query the protected profiles table.

-- 1. Drop the recursive policy on profiles immediately to allow querying profiles
DROP POLICY IF EXISTS "Super admins can do everything" ON public.profiles;

-- 2. Create the super_admins table
CREATE TABLE IF NOT EXISTS public.super_admins (
    auth_id uuid PRIMARY KEY,
    created_at timestamptz DEFAULT now()
);

-- 3. Enable RLS on super_admins
ALTER TABLE public.super_admins ENABLE ROW LEVEL SECURITY;

-- 4. Populate with existing super admins (role_id = 9)
INSERT INTO public.super_admins (auth_id)
SELECT auth_id FROM public.profiles WHERE role_id = 9
ON CONFLICT DO NOTHING;

-- 5. Create/Update the sync trigger to keep super_admins up to date
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

-- 6. Update the check function to use super_admins table
-- This function is SECURITY DEFINER and owned by postgres (superuser), so it bypasses RLS on super_admins
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

-- 7. Re-add the policy to profiles
CREATE POLICY "Super admins can do everything" ON public.profiles
FOR ALL
TO authenticated
USING (public.is_super_admin());

-- 8. Ensure super_admins table is accessible to super admins (optional, but good for debugging)
-- Note: We do NOT use the "Super admins can do everything" policy here to avoid any potential confusion,
-- although is_super_admin bypasses RLS so it would be technically safe.
CREATE POLICY "Super admins can view super_admins" ON public.super_admins
FOR SELECT
TO authenticated
USING (public.is_super_admin());
