-- Class B: replace the role_id tautology on giveaways and products with real
-- ownership predicates. These are the last five policies carrying
--   (role_id <= 9 OR role_id >= 3)   /   (role_id <= 9 OR role_id > 3)
-- which is true for every integer, so each currently evaluates true for any
-- authenticated user with a profile row -- all 2481 of them.
--
-- 20260918000004 deliberately skipped these because, unlike class A, the tautology
-- was the ONLY thing making a legitimate operation work. Removing it without a
-- replacement would have locked brands out of giveaways entirely.
--
-- The predicates below are not invented. They are what the client already
-- implements, read out of hybrid-raskin on main:
--
--   admin-dashboard.jsx:3015  const status = isSuperAdmin ? "active" : "pending";
--   admin-dashboard.jsx:3069  insert sets created_by_profile_id: currentUser?._dbId
--   admin-dashboard.jsx:2429  super admin sets status 'active'  (approve)
--   admin-dashboard.jsx:3563  super admin sets status 'rejected' (reject)
--   giveaways.js:256          if (!isSuperAdmin) q.eq("created_by_profile_id", profileId)
--   hybrid-mvp.jsx:6386       isAdmin = isSuperAdmin || [3,4,5,6].includes(role_id)
--                                       || role_id === 10 || role === "brand"
--
-- So the model is already decided: an admin or brand account creates a giveaway and
-- it lands as 'pending'; a super admin approves or rejects it; a creator sees and
-- edits only their own. The RLS just never expressed any of it.
--
-- Super admins are NOT given a disjunct in any policy below. Each table already has
-- a "Super admins can do everything" policy FOR ALL with role_id = 9, and permissive
-- policies OR together -- a FOR ALL policy with a null WITH CHECK uses its USING
-- expression as the check, so it covers INSERT, UPDATE and DELETE. Duplicating that
-- test here would be redundant.
--
-- These policies use the inline EXISTS (... role_id = 9) idiom that the sibling
-- policies on these same tables already use, rather than is_super_admin(). Two of
-- them are TO public, so anon evaluates them, and a policy expression runs as the
-- CALLING role -- anon does not hold EXECUTE on is_super_admin and would get 42501
-- instead of an empty result. That is the regression 20260918000003 caused and
-- 20260918000005 undid. Inline SQL has no such dependency.


-- =====================================
-- GIVEAWAYS
-- =====================================

-- INSERT: you may only create a giveaway that names you as its creator, and only
-- 'pending' -- publishing straight to 'active' is the super admin's approval step,
-- reached through the sibling FOR ALL policy.
--
-- The role list mirrors isAdmin in hybrid-mvp.jsx:6386 -- admins (3,4,5,6) and brand
-- accounts (10). Role 9 is absent on purpose: super admins pass via the sibling.
-- This is a deliberate coupling to a client-side gate; if that gate changes, this
-- policy has to change with it.
DROP POLICY IF EXISTS "Enable insert for admin users only" ON public.giveaways;
CREATE POLICY "Enable insert for admin users only" ON public.giveaways
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (
        created_by_profile_id = (SELECT p.id FROM public.profiles p WHERE p.auth_id = auth.uid())
        AND status = 'pending'
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.auth_id = auth.uid() AND p.role_id IN (3, 4, 5, 6, 10)
        )
    );

-- UPDATE: the creator, and nobody else. The 99 legacy rows with a null
-- created_by_profile_id fall to super admins only, which matches fetchMyGiveaways --
-- it already shows a non-super-admin nothing for those rows.
DROP POLICY IF EXISTS "Enable update for profiles based on role id" ON public.giveaways;
CREATE POLICY "Enable update for profiles based on role id" ON public.giveaways
    AS PERMISSIVE FOR UPDATE
    TO public
    USING (created_by_profile_id = (SELECT p.id FROM public.profiles p WHERE p.auth_id = auth.uid()))
    WITH CHECK (created_by_profile_id = (SELECT p.id FROM public.profiles p WHERE p.auth_id = auth.uid()));

-- DELETE: same rule as UPDATE.
DROP POLICY IF EXISTS "Enable delete for profiles based on role id" ON public.giveaways;
CREATE POLICY "Enable delete for profiles based on role id" ON public.giveaways
    AS PERMISSIVE FOR DELETE
    TO public
    USING (created_by_profile_id = (SELECT p.id FROM public.profiles p WHERE p.auth_id = auth.uid()));


-- =====================================
-- PRODUCTS
-- =====================================
-- The profile_admins disjunct is carried over verbatim from the live predicate. The
-- tautology disjunct is replaced by direct brand ownership: the caller IS the brand
-- profile linked to the product through product_brands. Both are ownership paths the
-- schema already declares; neither is new policy.
--
-- Coverage is small and that is a data problem, not a policy one: of 40,147 products,
-- 1,276 are reachable via profile_admins and 10 more via a brand profile that can
-- actually sign in. The remaining ~38,800 belong to seeded brand rows with no
-- loginable owner and become super-admin-only. The client writes to products on no
-- branch -- zero insert, update or delete call sites -- so nothing in the app changes.

DROP POLICY IF EXISTS "Enable update for profiles based on email" ON public.products;
CREATE POLICY "Enable update for profiles based on email" ON public.products
    AS PERMISSIVE FOR UPDATE
    TO public
    USING (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id IN ( SELECT product_brands.brand_id
           FROM product_brands
          WHERE (product_brands.product_id = products.id))))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (public.product_brands pb
     JOIN public.profiles p ON ((p.id = pb.brand_id)))
  WHERE (pb.product_id = products.id)))))
    WITH CHECK (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id IN ( SELECT product_brands.brand_id
           FROM product_brands
          WHERE (product_brands.product_id = products.id))))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (public.product_brands pb
     JOIN public.profiles p ON ((p.id = pb.brand_id)))
  WHERE (pb.product_id = products.id)))));

DROP POLICY IF EXISTS "Enable delete for profiles based on profile_id" ON public.products;
CREATE POLICY "Enable delete for profiles based on profile_id" ON public.products
    AS PERMISSIVE FOR DELETE
    TO public
    USING (((auth.uid() IN ( SELECT p.auth_id
   FROM (profile_admins pa
     JOIN profiles p ON ((p.id = pa.admin_profile_id)))
  WHERE (pa.managed_profile_id IN ( SELECT product_brands.brand_id
           FROM product_brands
          WHERE (product_brands.product_id = products.id))))) OR (auth.uid() IN ( SELECT p.auth_id
   FROM (public.product_brands pb
     JOIN public.profiles p ON ((p.id = pb.brand_id)))
  WHERE (pb.product_id = products.id)))));
