-- Require you to own the row you are inserting, on the four content tables.
--
-- Each of these had a correctly scoped policy already -- "you, or a
-- profile_admin acting for you" -- sitting beside a second one:
--
--   Enable insert for authenticated users only <table>   WITH CHECK (true)
--
-- Permissive policies OR together, so the true won. Measured as an ordinary
-- signed-in user against production, all of these were allowed:
--
--   insert a post   attributed to someone else's profile_id
--   insert a like   attributed to someone else
--   insert a list   owned by someone else
--
-- and as anon, with no session at all, inserting a post as any profile.
--
-- posts.like_count and profiles.post_count are trigger-maintained off these
-- tables, so a forged row also moves numbers on a profile that has nothing to do
-- with the person writing it.
--
-- posts, likes and cloud_files only need the blanket policy dropped: their ALL
-- policy already carries the ownership test in both USING and WITH CHECK, so it
-- governs INSERT once nothing wider is in the way.
--
-- lists is different and would break if treated the same. Its ownership policies
-- are UPDATE and DELETE only -- there is no scoped ALL -- so dropping the blanket
-- INSERT would leave nobody but a super admin able to create a stashlist. It gets
-- an INSERT policy that mirrors its own UPDATE check.
--
-- The profile_admins branch is kept deliberately: a brand admin posting as the
-- brand they manage is a real flow here, not a loophole.
--
-- Grants: all four handed anon and authenticated TRUNCATE, REFERENCES and
-- TRIGGER, and gave anon full write. TRUNCATE ignores RLS, and cloud_files alone
-- is 263,965 rows. anon is reduced to SELECT, which is what keeps posts, likes
-- and public lists readable to a logged-out visitor.

DROP POLICY IF EXISTS "Enable insert for authenticated users only posts"       ON public.posts;
DROP POLICY IF EXISTS "Enable insert for authenticated users only likes"       ON public.likes;
DROP POLICY IF EXISTS "Enable insert for authenticated users only cloud_files" ON public.cloud_files;
DROP POLICY IF EXISTS "Enable insert for authenticated users only lists"       ON public.lists;

-- lists has no scoped ALL to fall back on, so give it one for INSERT.
CREATE POLICY "Enable insert for owners on lists" ON public.lists
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = lists.profile_id)
        OR auth.uid() IN (
            SELECT p.auth_id
              FROM public.profile_admins pa
              JOIN public.profiles p ON p.id = pa.admin_profile_id
             WHERE pa.managed_profile_id = lists.profile_id)
    );

REVOKE ALL ON TABLE public.posts, public.likes, public.lists, public.cloud_files FROM anon, authenticated;
GRANT SELECT ON TABLE public.posts, public.likes, public.lists, public.cloud_files TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.posts, public.likes, public.lists, public.cloud_files TO authenticated;
