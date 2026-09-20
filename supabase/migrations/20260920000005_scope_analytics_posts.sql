-- Your viewing history should be yours to write.
--
-- analytics_posts is one row per person per post: share_date, like_date,
-- start_watching, end_watching, watch_duration, watch_in_full, view_section.
-- Its SELECT policy is already owner-scoped — you only ever read your own — but
-- INSERT was
--
--   Enable insert for authenticated users only analytics   WITH CHECK (true)
--
-- granted TO public, so any signed-in user could write rows attributed to any
-- profile. Measured: an ordinary user inserting against someone else's
-- profile_id was ALLOWED.
--
-- anon came back refused, and not because of anything here: the error is
-- "permission denied for table posts", a downstream grant that 74ae114 narrowed
-- an hour before this was written. Before that migration anon could almost
-- certainly do this too, and a future change to posts could hand it back. That
-- is the third time in this sweep a table has looked defended when what was
-- really happening was an unrelated object refusing on its behalf — which is
-- exactly why the rule gets written here instead of being left to luck.
--
-- The reason this is worth fixing rather than shrugging at is where the table is
-- read. get_feed and get_feed_items both join it as
--
--   LEFT JOIN public.analytics_posts ap ON p.id = ap.post_id AND ap.profile_id = v_profile_id
--
-- so a row is not inert telemetry: it is an input to what that person's feed
-- shows them. Writing rows against someone else's profile_id is reaching into
-- their feed. And because SELECT is owner-scoped, the victim is the only one who
-- could notice, and only by reading rows they never wrote.
--
-- Nothing legitimate is lost. The client does not touch this table at all — no
-- read, no write, anywhere in app/ or lib/ — and fn_analytics_post, the only
-- function named for it, is a trigger on the table itself rather than a writer.
-- Whatever populates the 2,870 existing rows across 45 profiles does so through
-- a path that is not the anon key.
--
-- UPDATE and DELETE have no policy and are already denied for everyone but a
-- super admin; the grants said otherwise, so they are revoked to match. anon
-- loses the table entirely: the SELECT policy resolves through auth.uid(), so a
-- session-less caller could never read a row anyway, and it has no business
-- writing one — this time by rule rather than by a borrowed refusal.

DROP POLICY IF EXISTS "Enable insert for authenticated users only analytics" ON public.analytics_posts;

CREATE POLICY "Write your own analytics only" ON public.analytics_posts
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = analytics_posts.profile_id)
    );

REVOKE ALL ON TABLE public.analytics_posts FROM anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.analytics_posts TO authenticated;
