-- The rest of the open-write policies found by the sweep.
--
-- Every one of these is the same template: a table with an "Enable insert for
-- authenticated users only <name>" policy whose WITH CHECK is true, sitting
-- either beside a scoped policy it cancels or beside nothing at all.
--
-- The deciding fact for how to treat each was what the client actually does with
-- it. Of the 29 tables left, the app touches nine and writes only six. The other
-- twenty are written by nothing reachable through the API — no read, no write,
-- anywhere in app/ or lib/ — so their open policy is removed and not replaced.
-- With no permissive policy for INSERT, RLS denies it; super admins keep their
-- ALL policy and the SECURITY DEFINER functions that maintain these tables are
-- unaffected, because a definer function runs as its owner and owners bypass RLS.
--
-- The six the client writes get a real rule instead.
--
-- ── profiles, which is the serious one ──────────────────────────────────────
--
-- profiles had INSERT WITH CHECK (true) to anon and authenticated. Measured: an
-- ordinary signed-in user could insert a profile row carrying role_id = 9.
-- is_super_admin() is "a profiles row with my auth_id and role_id 9", and the
-- one moment a person holds a session but has no profile row is the middle of
-- signup — which is exactly when the client inserts one. So a new account could
-- create itself as a super admin. In the probe the attempt bound to an existing
-- auth_id came back 23505, a duplicate-key refusal and not a policy one, which
-- is the whole point: nothing was checking.
--
-- Signup itself only ever writes auth_id = the caller and role_id = 1, so the
-- rule below keeps it working and removes the escalation. A later upgrade to
-- creator, brand or admin is an UPDATE, which is governed separately and already
-- scoped.

-- ── 1. Never written through the API: remove, do not replace ────────────────

DROP POLICY IF EXISTS "Enable addresses insert for authenticated users only" ON public.addresses;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.giveaways_regions;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.location_stashlists;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.locations_cloud_files;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.notification_preferences;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.post_flags;
DROP POLICY IF EXISTS "Enable insert for authenticated users only post_logs" ON public.post_log;
DROP POLICY IF EXISTS "Enable delete for profiles" ON public.post_tags;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.post_tags;
DROP POLICY IF EXISTS "Enable update for profiles based on email" ON public.post_tags;
DROP POLICY IF EXISTS "Enable insert for authenticated users only posts_hashtags" ON public.posts_hashtags;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.posts_lists;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.posts_profiles;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.product_brands;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.product_categories;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.product_feature_types;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.product_features;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.product_variants;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.products;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.products_cloud_files;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.products_product_features;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.profile_blocks;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.profile_delete_requests;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.push_tokens;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.related_products;

-- ── 2. The six the client writes ────────────────────────────────────────────

DROP POLICY IF EXISTS "Anyone can record a view" ON public.giveaway_views;
CREATE POLICY "Record your own giveaway view" ON public.giveaway_views
    AS PERMISSIVE FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = giveaway_views.profile_id));

DROP POLICY IF EXISTS "Enable insert for authenticated users only subscriptions_lists" ON public.subscriptions_lists;
CREATE POLICY "Subscribe yourself to a list" ON public.subscriptions_lists
    AS PERMISSIVE FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = subscriptions_lists.profile_id));

-- These three have no owner of their own; they belong to the parent row, so the
-- rule is "you may attach to something you own".
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.lists_products;
CREATE POLICY "Add products to a list you own" ON public.lists_products
    AS PERMISSIVE FOR INSERT TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.lists l JOIN public.profiles p ON p.id = l.profile_id
         WHERE l.id = lists_products.list_id AND p.auth_id = auth.uid()));

DROP POLICY IF EXISTS "Enable insert for authenticated users only posts_files" ON public.posts_files;
CREATE POLICY "Attach files to a post you own" ON public.posts_files
    AS PERMISSIVE FOR INSERT TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.posts po JOIN public.profiles p ON p.id = po.profile_id
         WHERE po.id = posts_files.post_id AND p.auth_id = auth.uid()));

DROP POLICY IF EXISTS "Enable insert for authenticated users only posts_products" ON public.posts_products;
CREATE POLICY "Tag products on a post you own" ON public.posts_products
    AS PERMISSIVE FOR INSERT TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.posts po JOIN public.profiles p ON p.id = po.profile_id
         WHERE po.id = posts_products.post_id AND p.auth_id = auth.uid()));

-- ── 3. profiles ─────────────────────────────────────────────────────────────
-- You may create your own profile row, as an ordinary user. Nothing else.

DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.profiles;
CREATE POLICY "Create your own profile at signup" ON public.profiles
    AS PERMISSIVE FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = auth_id AND COALESCE(role_id, 1) = 1);
