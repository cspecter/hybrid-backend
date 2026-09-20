-- Stop anyone making anyone follow anyone.
--
-- relationships already has the right rule. "Profiles can have all permissions
-- for relationships" is an ALL policy whose USING and WITH CHECK both require
-- auth.uid() to be the follower's own auth_id. Alongside it sat a second policy:
--
--   Enable insert for authenticated users only relationships
--   FOR INSERT TO public WITH CHECK (true)
--
-- Permissive policies OR together, so the true defeated the owner check
-- completely. Anyone could insert any row — follower_id of a stranger, followee_id
-- of anyone — and since follower_count and following_count are trigger-maintained
-- off this table, that is a write into other people's public numbers, not just a
-- junk row. It was also granted TO public, so it did not even need a session.
--
-- The blanket policy is dropped rather than rewritten. The ALL policy already
-- covers INSERT correctly and a second permissive policy could only widen it
-- again; the narrowest set of policies that expresses the rule is one.
--
-- Also adds a self-follow check. The client guards followee != follower before
-- calling, but nothing stopped a direct request writing one, and a self-follow
-- would inflate both counters on the same profile. No existing row violates it.
--
-- Grants: both API roles held DELETE, TRUNCATE, REFERENCES, TRIGGER and UPDATE.
-- Nothing updates this table — the client only selects, inserts and deletes, and
-- no function updates it either — and TRUNCATE is not subject to RLS at all, so
-- that grant could have emptied the entire social graph. anon keeps SELECT,
-- which is what makes follower lists public.

DROP POLICY IF EXISTS "Enable insert for authenticated users only relationships" ON public.relationships;

ALTER TABLE public.relationships DROP CONSTRAINT IF EXISTS relationships_no_self_follow;
ALTER TABLE public.relationships
    ADD CONSTRAINT relationships_no_self_follow CHECK (follower_id IS DISTINCT FROM followee_id);

REVOKE ALL ON TABLE public.relationships FROM anon, authenticated;
GRANT SELECT ON TABLE public.relationships TO anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.relationships TO authenticated;
