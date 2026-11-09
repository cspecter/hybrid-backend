-- Make `lists.is_private` mean something.
--
-- The client gained the private-stashlist feature across five commits in
-- hybrid-raskin (e37388c..a32f807): a list can be marked private at creation,
-- flipped back on its detail page, and is badged on all six surfaces it can
-- appear on. Every one of those is presentation. The predicate that actually
-- withholds the row was never written:
--
--   20241204000014_policies.sql:280
--     CREATE POLICY "Enable read access for all users on lists"
--       ON public.lists FOR SELECT USING (true);
--
-- `anon` holds SELECT on the table (20260920000003) and the anon key ships in
-- the published bundle, so until now anyone could read every private list with
-- one request. fetchers.js filters them out in the browser, which hides them
-- from the app and from nobody else -- the comment at fetchers.js:1049 says so.
--
-- INSERT, UPDATE and DELETE on `lists` are already owner-scoped and are left
-- alone: "Enable insert for owners on lists" (20260920000003), "Enable update
-- for profiles based on email" and "Enable delete for profiles based on
-- profile_id on lists" (both 20241204000014). SELECT was the only hole.
--
-- Checked before writing, because a SELECT policy is worth nothing if something
-- serves the same rows around it:
--
--   * No views exist on `public` at all, so there is no view running as its
--     owner to bypass this.
--   * The RPCs that return list rows -- get_profile_lists, get_product_lists,
--     get_location_lists, get_list_products, typeahead_lists, search_universal,
--     resolve_list_id -- are SECURITY INVOKER, so RLS binds them, and
--     20260918000016 additionally revoked EXECUTE on them from PUBLIC, anon and
--     authenticated. get_feed_items is SECURITY DEFINER but reads only posts,
--     analytics_posts and profile_blocks; it never touches lists.
--   * update_list_product_count (20251218000001), the trigger that maintains
--     lists.product_count, is SECURITY DEFINER, so counts are unaffected by
--     anything below.
--
-- Super admins are deliberately NOT given a disjunct. Unlike products and
-- giveaways, `lists` has no "Super admins can do everything" sibling policy to
-- fall back on, so a disjunct here would be the thing that grants it -- a new
-- decision about who may read someone's private list, not a continuation of an
-- existing one. Nothing in the client needs it: admin-dashboard.jsx contains no
-- read of `lists` on any branch. Fail closed; add it deliberately if it is ever
-- wanted.


-- =====================================
-- lists: SELECT
-- =====================================
-- Public lists stay readable by everyone including anon, which is what keeps a
-- logged-out visitor's app working. A private list resolves only for its owner
-- and for an admin of the profile that owns it.
--
-- TO public, not TO authenticated: anon must evaluate this policy rather than be
-- refused by it. For the same reason the ownership test is inline SQL and not
-- is_super_admin() or any other function -- a policy expression runs as the
-- CALLING role, and anon holds EXECUTE on nothing here. That is the regression
-- 20260918000003 caused and 20260918000005 undid.
--
-- COALESCE because is_private is nullable: null and undefined read as public,
-- matching the client's `!l.is_private`. All 1,189 rows hold false today, so
-- this is belt and braces against a row inserted without the column.
--
-- The profile_admins disjunct mirrors the three sibling write policies on this
-- table. It is not a widening: an admin who can already UPDATE the row can set
-- is_private = false, read it, and set it back. Withholding SELECT from someone
-- who holds UPDATE would buy nothing and would make this policy disagree with
-- its three siblings.
DROP POLICY IF EXISTS "Enable read access for all users on lists" ON public.lists;
CREATE POLICY "Public lists, and your own private ones" ON public.lists
    AS PERMISSIVE FOR SELECT
    TO public
    USING (
        COALESCE(is_private, false) = false
        OR auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = lists.profile_id)
        OR auth.uid() IN (
            SELECT p.auth_id
              FROM public.profile_admins pa
              JOIN public.profiles p ON p.id = pa.admin_profile_id
             WHERE pa.managed_profile_id = lists.profile_id)
    );


-- =====================================
-- lists_products: SELECT
-- =====================================
-- Hiding the list row alone does not hide what is in it. list ids are sequential
-- integers and this policy was:
--
--   20241204000014_policies.sql:126
--     CREATE POLICY "lists_products are viewable by everyone."
--       ON public.lists_products FOR SELECT USING (true);
--
-- so `GET /rest/v1/lists_products?list_id=eq.N&select=product_id` returned the
-- contents of any private list with the published anon key. Closing `lists`
-- without closing this would leave the feature half-done: the name hidden, the
-- products not.
--
-- The predicate is deliberately not a copy of the one above. RLS applies to
-- every table reference in a query for the calling role, policy expressions
-- included, so the inner SELECT is itself filtered by the `lists` policy: a list
-- you cannot see yields no row and its contents disappear with it. One rule,
-- expressed once, and the two tables cannot drift apart. No recursion risk --
-- the `lists` policy reads profiles and profile_admins, never lists_products.
--
-- INSERT and DELETE here are already owner-scoped -- "Add products to a list you
-- own" (20260920000006) and "Enable delete for profiles based on profile_id from
-- lists" (20241204000014) -- so the only writer is the owner, and the FTS and
-- count triggers that fire on those writes are unaffected.
--
-- One thing a reader has to check here and does not have to check on `lists`:
-- this table also carries "Profiles can add and remove lists_products." as a
-- FOR ALL policy, and FOR ALL covers SELECT. Permissive policies OR together, so
-- it is a second read path that replacing the SELECT policy does not close. It
-- is harmless -- its USING is the same owner-or-profile_admins test, which is a
-- strict subset of "the parent list is visible to me": anyone who owns or
-- administers the list can see it, so that disjunct can never admit a row the
-- policy below would withhold. It is left in place because it is also what
-- authorises the writes. `lists` has no FOR ALL policy of any kind, which is why
-- the note about super admins above applies there and not here.
DROP POLICY IF EXISTS "lists_products are viewable by everyone." ON public.lists_products;
CREATE POLICY "Contents of a list you can see" ON public.lists_products
    AS PERMISSIVE FOR SELECT
    TO public
    USING (EXISTS (SELECT 1 FROM public.lists l WHERE l.id = lists_products.list_id));


-- =====================================
-- Deliberately left open
-- =====================================
-- subscriptions_lists, posts_lists, explore_lists and location_stashlists all
-- still carry FOR SELECT USING (true), and each can hold a row naming a private
-- list's id. They are left as they are: with the two policies above in place, a
-- leaked id yields nothing -- the list row is invisible and so are its products
-- -- so what remains is the existence of an integer. Narrowing four more join
-- tables to withhold that is a bigger change than it is worth, and each would
-- need its own argument about what the join is for.
--
-- To roll this back:
--   DROP POLICY "Public lists, and your own private ones" ON public.lists;
--   CREATE POLICY "Enable read access for all users on lists"
--     ON public.lists FOR SELECT USING (true);
--   DROP POLICY "Contents of a list you can see" ON public.lists_products;
--   CREATE POLICY "lists_products are viewable by everyone."
--     ON public.lists_products FOR SELECT USING (true);
