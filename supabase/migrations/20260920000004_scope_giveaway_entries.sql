-- Enter a giveaway as yourself, and let the draw decide who won.
--
-- giveaway_entries had three policies: a super-admin ALL, SELECT true, and
--
--   Enable insert for authenticated users only   WITH CHECK (true)
--
-- and no ownership rule anywhere. Measured as an ordinary signed-in user:
--
--   insert with someone else's profile_id     blocked, 42501
--   insert your own row with won = true       ALLOWED
--   UPDATE existing entries to won            0 rows
--   DELETE rival entries                      0 rows
--
-- Two of those need explaining, because neither is what it looks like.
--
-- The UPDATE and DELETE zeroes are not this table defending itself either way --
-- there is simply no policy for those commands, so RLS denies them. That is the
-- right outcome reached by omission; the grants still said both were allowed,
-- which is the sort of gap that closes the moment someone adds a convenience
-- policy. They are revoked below so the grant matches the intent.
--
-- The blocked cross-profile insert is genuinely accidental. WITH CHECK (true)
-- permits it; what refused was fn_giveaway_entry_triggers, which fires on INSERT
-- and writes a notification addressed to NEW.profile_id, and the notifications
-- policy will not let you write a notification addressed to someone else. So the
-- protection is a side effect of a trigger, one refactor away from vanishing, and
-- it is not a rule anybody wrote down. This writes it down.
--
-- The real hole is the second line. won and sent are columns on the entry, and
-- nothing stopped an entrant setting them. auto_pick_giveaway_winner picks from
-- entries and fn_giveaway_entry_triggers recounts redeemed off won, so a
-- self-declared winner is not a cosmetic lie -- it lands in the same column the
-- draw writes and the counters read. 89 of the 341 rows here are winners.
--
-- So: you may insert only your own entry, and only as a non-winner. Flipping won
-- or sent afterwards stays where it already was -- super admins and the definer
-- functions that run the draw.

DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.giveaway_entries;

CREATE POLICY "Enter a giveaway as yourself" ON public.giveaway_entries
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = giveaway_entries.profile_id)
        -- The draw decides these, not the entrant.
        AND COALESCE(won, false)  = false
        AND COALESCE(sent, false) = false
    );

-- UPDATE and DELETE have no policy and are therefore already denied; the grants
-- should not claim otherwise. anon has no business writing here at all.
REVOKE ALL ON TABLE public.giveaway_entries FROM anon, authenticated;
GRANT SELECT ON TABLE public.giveaway_entries TO anon;
GRANT SELECT, INSERT ON TABLE public.giveaway_entries TO authenticated;
