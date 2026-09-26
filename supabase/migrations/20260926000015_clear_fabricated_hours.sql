-- Actually clear the fabricated opening hours this time.
--
-- The previous migration tried to identify them by comparing against
-- information_schema.column_default. That column returns the default as SQL source —
-- quotes, cast and all — so the comparison never matched a single row, the update
-- reported success having changed nothing, and 700 locations were published still
-- claiming to be open 09:00-21:00 seven days a week.
--
-- Caught immediately afterwards by counting: 1,012 published rows, 1,012 with hours,
-- when 700 of them should have had none.
--
-- Matched on the value itself this time. The test is narrow on purpose — feed-created,
-- and every one of the seven days set to exactly 09:00-21:00 and not closed. A store
-- that genuinely keeps those hours and was edited by hand would be indistinguishable,
-- but none of these have been touched since creation, so there is nothing real to lose.
update public.locations
   set operating_hours = null, updated_at = now()
 where description like 'Created from the Lit Alerts feed%'
   and operating_hours is not null
   and (select bool_and(
          (operating_hours -> d ->> 'open')  = '09:00' and
          (operating_hours -> d ->> 'close') = '21:00' and
          coalesce((operating_hours -> d ->> 'closed')::boolean, false) = false)
        from unnest(array['monday','tuesday','wednesday','thursday','friday',
                          'saturday','sunday']) d);
