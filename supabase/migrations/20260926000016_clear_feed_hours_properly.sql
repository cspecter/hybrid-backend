-- Clear the opening hours on feed-created locations. Third attempt; the first two
-- matched nothing and both failures are worth recording.
--
-- ATTEMPT ONE compared operating_hours against information_schema.column_default.
-- That view returns the default as SQL source text — quotes and ::jsonb cast included
-- — so nothing ever matched, the UPDATE reported success having changed no rows, and
-- the locations were published still carrying the default.
--
-- ATTEMPT TWO tested every day for 09:00-21:00. It matched nothing either, and this
-- time the SQL was fine and the assumption was wrong: the default is not uniform.
-- Weekdays are 09:00-21:00, Saturday is 10:00-20:00, Sunday 10:00-18:00. I had read
-- the first 120 characters of the value, seen two weekdays, and generalised from that.
--
-- The right test is simpler than either. The Lit Alerts feed carries no opening hours
-- whatsoever — not in any of the thirteen columns across three exports — so no
-- location created from it can have real hours. Every one is the column default,
-- inherited because the insert never named the field. All 700 share exactly one
-- pattern, which confirms none has been edited since.
--
-- Left as-is, the app tells users that seven hundred dispensaries are open at 8pm on a
-- Sunday. Absent data has to look absent.
--
-- Safe because null is handled: lib/fetchers.js only builds hoursDetail when
-- operating_hours is an object, the detail panel renders behind hoursDetail.length > 0,
-- and the "Open now" filter excludes any location whose hours it cannot read — so
-- these drop out of "open now" instead of being wrongly included.
update public.locations
   set operating_hours = null, updated_at = now()
 where description like 'Created from the Lit Alerts feed%'
   and operating_hours is not null;
