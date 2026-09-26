-- Publish the 700 feed-created locations, after removing something they should not
-- have been carrying.
--
-- FABRICATED OPENING HOURS. Every one of the 700 drafts claimed to be open 09:00 to
-- 21:00, seven days a week. Nobody entered that: it is the column default on
-- locations.operating_hours, inherited because the creation never set the field. The
-- 312 real stores have 207 distinct hour patterns between them; the drafts have
-- exactly one.
--
-- Published as-is, the app would have told users that seven hundred dispensaries are
-- open at 8pm on a Sunday. Someone drives across town on that. Absent data has to look
-- absent, so the default is cleared wherever it is still untouched.
--
-- Checked before clearing, because null has to be safe: lib/fetchers.js only builds
-- hoursDetail when operating_hours is an object, the detail panel renders behind
-- `hoursDetail.length > 0`, and the "Open now" filter drops any location it cannot
-- read hours for. So a store with no hours is quietly excluded from "open now" rather
-- than wrongly included — which is the correct answer when we do not know.
update public.locations
   set operating_hours = null, updated_at = now()
 where status = 'draft'
   and description like 'Created from the Lit Alerts feed%'
   and operating_hours::text = (
     select column_default from information_schema.columns
      where table_schema='public' and table_name='locations' and column_name='operating_hours'
   )::text;

-- The one location the CRC map gave a street but no usable postcode: "NJ-66" is a
-- route with no number, so nothing matched. Neptune Township's zip, from the register
-- row itself, makes it mappable like the other 699.
update public.locations l
   set postal_code_id = (select pc.id from public.postal_codes pc
                          where pc.postal_code = '07753' and pc.country_code = 'US'
                          order by pc.id limit 1),
       updated_at = now()
 where l.status = 'draft' and l.postal_code_id is null
   and l.name ilike 'Zen Leaf - Neptune%';

-- ─── Publish ─────────────────────────────────────────────────────────────────
-- Only rows that can actually render: a name, a street address, and a postcode, which
-- is where lib/fetchers.js takes lat/lng from when a location has no coordinates of
-- its own. Anything failing that stays draft rather than appearing on a map at 0,0.
update public.locations
   set status = 'published', updated_at = now()
 where status = 'draft'
   and description like 'Created from the Lit Alerts feed%'
   and nullif(btrim(coalesce(name, '')), '') is not null
   and nullif(btrim(coalesce(address_line1, '')), '') is not null
   and postal_code_id is not null;
