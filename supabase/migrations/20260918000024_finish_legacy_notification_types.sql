-- Give the last 149 legacy notifications a type, and validate the constraint.
--
-- 20260918000022 recovered 20,852 of the 21,001 rows stuck on type_id = 1 and
-- deliberately stopped there, because the remaining 149 looked unclassifiable
-- against the existing vocabulary. Two of those three groups turned out to be
-- classifiable after all, once the right evidence was consulted.
--
-- The giveaway teasers -- 38 rows, previously called ambiguous between
-- giveaway_drawing_3days, _1day, _1hour and new_giveaway_from_following. The
-- titles do not settle it, but the clock does. Every one of them was written
-- between 2 days 23:54:56 and 2 days 23:56:55 before its giveaway's end_time:
--
--   'Are you a potential winner? X ends on ...'   29 rows   end_time - created_at ~ 2d 23:55
--   'X is coming soon on <date>'                   8 rows   end_time - created_at ~ 2d 23:57
--
-- That is a single scheduler firing a three-day reminder a few minutes late,
-- under two different wordings. Not a judgement call -- a measurement. Both go
-- to giveaway_drawing_3days. The wording of the second is misleading, since
-- start_time had already passed by 28 hours when it was sent; it announces the
-- draw, not the giveaway.
--
--   'Did you win? Check on the ... draw'           1 row
--
-- is the post-draw counterpart and goes to giveaway_finished. Its giveaway has
-- been deleted, so this is the one row of the 149 that 20260918000023 already
-- expired.
--
-- The remaining 111 go to general_message (66), which is the vocabulary's own
-- catch-all for a notification that does not belong to a specific event:
--
--   ~63  self-action echoes -- 'You followed Raskin', "You created list Lobo
--        Hashish's list", 'You added 3 new products to My first stashlist'.
--        Every other code describes what someone else or the system did. The
--        legacy sender also told people what they had just done themselves, and
--        that concept has no code. Rather than invent one -- a new code means a
--        new icon, category and grouping in Alerts, which is a product decision
--        -- these take the catch-all that already exists.
--    48  placeholder titles -- 43 titled literally '1', four more titled '1'
--        with no related_type, one titled 'Notification'. Nothing to recover.
--
-- This migration changes type_id and nothing else. It does not change what is
-- visible: the 148 unexpired rows stay visible, with the same titles they have
-- now. Two things that follow from that are left alone on purpose, both being
-- questions about what a user should see rather than what the data should say:
--
--   * whether a notification titled '1' should be shown at all. 48 of these are
--     in 96 people's Alerts right now, and a type_id does not make them mean
--     anything. Expiring them is one line if that is wanted.
--   * whether the self-action echoes are worth showing. They were presumably
--     useful once; they read oddly next to notifications about other people.
--
-- With the last row typed, notifications_type_id_fkey can finally be validated,
-- which 20260918000021 marked NOT VALID and explicitly deferred to this point.
-- VALIDATE CONSTRAINT takes only a SHARE UPDATE EXCLUSIVE lock -- it does not
-- block reads or writes -- and scans the table once.

UPDATE public.notifications
   SET type_id = CASE
        WHEN title ~* 'are you a potential winner|is coming soon on'  THEN 37
        WHEN title ~* 'did you win'                                    THEN 41
        ELSE 66
       END
 WHERE type_id = 1;

ALTER TABLE public.notifications
    VALIDATE CONSTRAINT notifications_type_id_fkey;

COMMENT ON CONSTRAINT notifications_type_id_fkey ON public.notifications IS
    'Validated. Every row references a real notification_types id.';
