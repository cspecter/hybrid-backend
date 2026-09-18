-- Add authorization to the user-facing SECURITY DEFINER functions.
--
-- These eleven accept a caller-supplied target -- a profile, list, product, location
-- or saved search -- and act on it with the owner's rights and no check that the
-- caller has anything to do with it. 20260918000003 revoked EXECUTE from anon and
-- authenticated, so none is reachable today; this closes the bodies so that a future
-- re-grant does not reopen them. They are the likeliest to be re-granted, because
-- unlike the notification and maintenance functions they are product features.
--
-- Guard shape, used identically in all eleven:
--
--     v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')
--                            ::jsonb ->> 'role', '');
--     IF v_jwt_role IN ('anon','authenticated') AND NOT (<ownership> OR <super admin>)
--     THEN RAISE EXCEPTION ... USING ERRCODE = '42501';
--
-- Why the JWT role claim rather than current_user: inside a SECURITY DEFINER function
-- current_user is rebound to the function's OWNER, so it always reads 'postgres' and
-- can never identify the caller. That is the mistake 20260918000012 shipped and
-- 20260918000013 had to correct. current_setting is not affected by the security
-- context, so it still reports who actually made the request.
--
-- What each branch yields:
--     PostgREST, anon or authenticated   -> role claim is 'anon' / 'authenticated', checked
--     PostgREST, service_role key        -> role claim is 'service_role', exempt
--     cron, psql, a migration            -> setting absent, '', exempt
-- Exempting server-side callers is deliberate: these run as postgres or service_role,
-- which already bypass RLS, and gating them would break any Edge Function that acts
-- on a user's behalf. None of the eleven has an internal caller or a cron job, so
-- there is no trigger path to consider.
--
-- The ownership tests are not invented. Each mirrors the RLS policy that already
-- governs the same table: profile self or profile_admins for lists and profiles,
-- profile_admins-via-product_brands or direct brand ownership for products,
-- brand owner / profile_admins / location manager for locations.
--
-- update_employee_approval additionally gets a correctness fix. Its parameters are
-- declared uuid but location_employees.location_id and profile_id are integer, so
-- every call raised "operator does not exist: integer = uuid". The uuid arguments are
-- kept and resolved through locations.public_id and profiles.public_id, which is what
-- uuid parameters on this schema mean everywhere else.


CREATE OR REPLACE FUNCTION public.update_employee_approval(p_location_id uuid, p_profile_id uuid, p_is_approved boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
    v_location_id integer;
    v_profile_id integer;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    SELECT id INTO v_location_id FROM public.locations WHERE public_id = p_location_id;
    SELECT id INTO v_profile_id  FROM public.profiles  WHERE public_id = p_profile_id;
    IF v_location_id IS NULL OR v_profile_id IS NULL THEN
        RAISE EXCEPTION 'Location or profile not found';
    END IF;

    IF v_jwt_role IN ('anon', 'authenticated') AND NOT (
        EXISTS (SELECT 1 FROM public.profile_admins pa
                  JOIN public.profiles p ON p.id = pa.admin_profile_id
                 WHERE p.auth_id = auth.uid()
                   AND pa.managed_profile_id = (SELECT brand_id FROM public.locations WHERE id = v_location_id))
        OR public.is_location_manager(v_location_id)
        OR EXISTS (SELECT 1 FROM public.profiles WHERE auth_id = auth.uid() AND role_id = 9)
    ) THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    UPDATE public.location_employees
    SET has_been_reviewed = TRUE,
        is_approved = p_is_approved
    WHERE location_id = v_location_id
      AND profile_id  = v_profile_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_list(p_profile_id uuid, p_name text, p_description text DEFAULT NULL::text, p_is_private boolean DEFAULT false, p_background_id integer DEFAULT NULL::integer, p_thumbnail_id integer DEFAULT NULL::integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
    v_profile_id integer;
    v_list_id integer;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    SELECT id INTO v_profile_id FROM public.profiles WHERE public_id = p_profile_id;
    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    IF v_jwt_role IN ('anon', 'authenticated') AND NOT (
        v_profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profile_admins pa
                     JOIN public.profiles p ON p.id = pa.admin_profile_id
                    WHERE p.auth_id = auth.uid() AND pa.managed_profile_id = v_profile_id)
        OR EXISTS (SELECT 1 FROM public.profiles WHERE auth_id = auth.uid() AND role_id = 9)
    ) THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.lists (profile_id, name, description, is_private, background_id, thumbnail_id)
    VALUES (v_profile_id, p_name, p_description, p_is_private, p_background_id, p_thumbnail_id)
    RETURNING id INTO v_list_id;

    RETURN v_list_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.update_list_images(list_public_id uuid, thumbnail_public_id uuid DEFAULT NULL::uuid, background_public_id uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
    v_list_id integer;
    v_thumbnail_id integer;
    v_background_id integer;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    SELECT id INTO v_list_id FROM public.lists WHERE public_id = list_public_id;
    IF v_list_id IS NULL THEN
        RAISE EXCEPTION 'List not found';
    END IF;

    IF v_jwt_role IN ('anon', 'authenticated') AND NOT (
        EXISTS (SELECT 1 FROM public.lists l
                 WHERE l.id = v_list_id
                   AND l.profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid()))
        OR EXISTS (SELECT 1 FROM public.lists l
                     JOIN public.profile_admins pa ON pa.managed_profile_id = l.profile_id
                     JOIN public.profiles p ON p.id = pa.admin_profile_id
                    WHERE l.id = v_list_id AND p.auth_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profiles WHERE auth_id = auth.uid() AND role_id = 9)
    ) THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    IF thumbnail_public_id IS NOT NULL THEN
        SELECT id INTO v_thumbnail_id FROM public.cloud_files WHERE public_id = thumbnail_public_id;
        UPDATE public.lists SET thumbnail_id = v_thumbnail_id WHERE id = v_list_id;
    END IF;

    IF background_public_id IS NOT NULL THEN
        SELECT id INTO v_background_id FROM public.cloud_files WHERE public_id = background_public_id;
        UPDATE public.lists SET background_id = v_background_id WHERE id = v_list_id;
    END IF;

    UPDATE public.lists SET updated_at = now() WHERE id = v_list_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.update_location_images(location_public_id uuid, logo_public_id uuid DEFAULT NULL::uuid, banner_public_id uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
    v_location_id integer;
    v_logo_id integer;
    v_banner_id integer;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    SELECT id INTO v_location_id FROM public.locations WHERE public_id = location_public_id;
    IF v_location_id IS NULL THEN
        RAISE EXCEPTION 'Location not found';
    END IF;

    IF v_jwt_role IN ('anon', 'authenticated') AND NOT (
        EXISTS (SELECT 1 FROM public.locations l
                  JOIN public.profiles p ON p.id = l.brand_id
                 WHERE l.id = v_location_id AND p.auth_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.locations l
                     JOIN public.profile_admins pa ON pa.managed_profile_id = l.brand_id
                     JOIN public.profiles p ON p.id = pa.admin_profile_id
                    WHERE l.id = v_location_id AND p.auth_id = auth.uid())
        OR public.is_location_manager(v_location_id)
        OR EXISTS (SELECT 1 FROM public.profiles WHERE auth_id = auth.uid() AND role_id = 9)
    ) THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    IF logo_public_id IS NOT NULL THEN
        SELECT id INTO v_logo_id FROM public.cloud_files WHERE public_id = logo_public_id;
        UPDATE public.locations SET logo_id = v_logo_id WHERE id = v_location_id;
    END IF;

    IF banner_public_id IS NOT NULL THEN
        SELECT id INTO v_banner_id FROM public.cloud_files WHERE public_id = banner_public_id;
        UPDATE public.locations SET banner_id = v_banner_id WHERE id = v_location_id;
    END IF;

    UPDATE public.locations SET updated_at = now() WHERE id = v_location_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.update_product_images(product_public_id uuid, thumbnail_public_id uuid DEFAULT NULL::uuid, cover_public_id uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
    v_product_id integer;
    v_thumbnail_id integer;
    v_cover_id integer;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    SELECT id INTO v_product_id FROM public.products WHERE public_id = product_public_id;
    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'Product not found';
    END IF;

    -- Mirrors the products UPDATE policy: profile_admins via product_brands, or the
    -- brand profile itself. The old comment here claimed "RLS on products handles
    -- auth" -- it does not, SECURITY DEFINER bypasses the caller's RLS entirely.
    IF v_jwt_role IN ('anon', 'authenticated') AND NOT (
        EXISTS (SELECT 1 FROM public.product_brands pb
                  JOIN public.profile_admins pa ON pa.managed_profile_id = pb.brand_id
                  JOIN public.profiles p ON p.id = pa.admin_profile_id
                 WHERE pb.product_id = v_product_id AND p.auth_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.product_brands pb
                     JOIN public.profiles p ON p.id = pb.brand_id
                    WHERE pb.product_id = v_product_id AND p.auth_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profiles WHERE auth_id = auth.uid() AND role_id = 9)
    ) THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    IF thumbnail_public_id IS NOT NULL THEN
        SELECT id INTO v_thumbnail_id FROM public.cloud_files WHERE public_id = thumbnail_public_id;
        UPDATE public.products SET thumbnail_id = v_thumbnail_id WHERE id = v_product_id;
    END IF;

    IF cover_public_id IS NOT NULL THEN
        SELECT id INTO v_cover_id FROM public.cloud_files WHERE public_id = cover_public_id;
        UPDATE public.products SET cover_id = v_cover_id WHERE id = v_product_id;
    END IF;

    UPDATE public.products SET updated_at = now() WHERE id = v_product_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_product_variant(target_product_id uuid, variant_name text, variant_price numeric, variant_sku text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
    v_product_id integer;
    v_variant_id uuid;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;
    IF v_product_id IS NULL THEN RAISE EXCEPTION 'Product not found'; END IF;

    IF v_jwt_role IN ('anon', 'authenticated') AND NOT (
        EXISTS (SELECT 1 FROM public.product_brands pb
                  JOIN public.profile_admins pa ON pa.managed_profile_id = pb.brand_id
                  JOIN public.profiles p ON p.id = pa.admin_profile_id
                 WHERE pb.product_id = v_product_id AND p.auth_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.product_brands pb
                     JOIN public.profiles p ON p.id = pb.brand_id
                    WHERE pb.product_id = v_product_id AND p.auth_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profiles WHERE auth_id = auth.uid() AND role_id = 9)
    ) THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.product_variants (product_id, name, price, sku)
    VALUES (v_product_id, variant_name, variant_price, variant_sku)
    RETURNING public_id INTO v_variant_id;

    RETURN v_variant_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_location(name text, address_line1 text, city text, state text, postal_code text, brand_public_id uuid DEFAULT NULL::uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
    v_brand_id integer;
    v_postal_code_id integer;
    v_location_id uuid;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    -- The brand_public_id branch was the hole: passing it replaced the auth.uid()
    -- lookup entirely, so a caller could create a location owned by any brand.
    IF brand_public_id IS NOT NULL THEN
        SELECT id INTO v_brand_id FROM public.profiles WHERE public_id = brand_public_id;
    ELSE
        SELECT id INTO v_brand_id FROM public.profiles WHERE auth_id = auth.uid();
    END IF;

    IF v_brand_id IS NULL THEN RAISE EXCEPTION 'Brand profile not found'; END IF;

    IF v_jwt_role IN ('anon', 'authenticated') AND NOT (
        v_brand_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.profile_admins pa
                     JOIN public.profiles p ON p.id = pa.admin_profile_id
                    WHERE p.auth_id = auth.uid() AND pa.managed_profile_id = v_brand_id)
        OR EXISTS (SELECT 1 FROM public.profiles WHERE auth_id = auth.uid() AND role_id = 9)
    ) THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_postal_code_id FROM public.postal_codes
     WHERE public.postal_codes.postal_code = create_location.postal_code LIMIT 1;

    INSERT INTO public.locations (brand_id, name, address_line1, city, state, postal_code_id)
    VALUES (v_brand_id, name, address_line1, city, state, v_postal_code_id)
    RETURNING public_id INTO v_location_id;

    RETURN v_location_id;
END;
$$;


-- The four search functions take a profile id and read or write that profile's
-- private search data. Scoped to the caller's own profile.

CREATE OR REPLACE FUNCTION public.save_search_query(query text, p_profile_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    IF v_jwt_role IN ('anon', 'authenticated')
       AND p_profile_id IS DISTINCT FROM (SELECT id FROM public.profiles WHERE auth_id = auth.uid())
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.saved_searches (profile_id, query)
    VALUES (p_profile_id, save_search_query.query);
END;
$$;


CREATE OR REPLACE FUNCTION public.delete_saved_search(search_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    IF v_jwt_role IN ('anon', 'authenticated') THEN
        -- Scope the delete rather than raising: a row that is not yours simply is
        -- not found, which does not leak whether the id exists.
        DELETE FROM public.saved_searches
         WHERE id = search_id
           AND profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid());
    ELSE
        DELETE FROM public.saved_searches WHERE id = search_id;
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION public.get_saved_searches(p_profile_id integer, limit_val integer)
RETURNS TABLE(id integer, public_id uuid, query text, term text, "timestamp" timestamp with time zone, "resultCount" integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    IF v_jwt_role IN ('anon', 'authenticated')
       AND p_profile_id IS DISTINCT FROM (SELECT p.id FROM public.profiles p WHERE p.auth_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.auth_id = auth.uid() AND p.role_id = 9)
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT ss.id, ss.public_id, ss.query, ss.query AS term,
           ss.created_at AS "timestamp", 0 AS "resultCount"
    FROM public.saved_searches ss
    WHERE ss.profile_id = p_profile_id
    ORDER BY ss.created_at DESC
    LIMIT limit_val;
END;
$$;


CREATE OR REPLACE FUNCTION public.get_search_history(p_profile_id integer, limit_val integer)
RETURNS TABLE(id integer, public_id uuid, query text, term text, "timestamp" timestamp with time zone, "resultCount" integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_jwt_role text;
BEGIN
    v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

    IF v_jwt_role IN ('anon', 'authenticated')
       AND p_profile_id IS DISTINCT FROM (SELECT p.id FROM public.profiles p WHERE p.auth_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.auth_id = auth.uid() AND p.role_id = 9)
    THEN
        RAISE EXCEPTION 'Access denied' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT sh.id, sh.public_id, sh.query, sh.query AS term,
           sh.created_at AS "timestamp", sh.result_count AS "resultCount"
    FROM public.search_history sh
    WHERE sh.profile_id = p_profile_id
    ORDER BY sh.created_at DESC
    LIMIT limit_val;
END;
$$;
