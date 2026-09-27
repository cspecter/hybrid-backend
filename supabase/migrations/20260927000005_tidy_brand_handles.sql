-- Give the new brand pages handles a brand would actually use.
--
-- The creation appended a six-character hash to every username to guarantee
-- uniqueness, which worked and reads badly: @ayrloome77dfe next to @rythm and
-- @stiiizy, the handles that already existed. A handle is public — it is the brand's
-- address in the app and the first thing its owner sees when deciding whether to
-- claim the page.
--
-- The hash should have been the fallback, not the default. This takes the clean slug
-- wherever it is free and leaves the hashed form only where something already holds
-- the name. Ordered by id so the result is deterministic if two brands slug the same:
-- the first keeps the clean handle, the rest keep their hash.
with candidate as (
  select pr.id,
         left(regexp_replace(lower(pr.display_name), '[^a-z0-9]+', '', 'g'), 28) as clean
  from public.profiles pr
  where pr.profile_type = 'brand'
    and pr.bio like 'Brand page created automatically%'
),
claimable as (
  select c.id, c.clean,
         row_number() over (partition by c.clean order by c.id) as rn
  from candidate c
  where nullif(c.clean, '') is not null
    and length(c.clean) >= 3            -- a two-letter handle is not worth the collision risk
    and not exists (select 1 from public.profiles x where x.username = c.clean)
)
update public.profiles p
   set username = c.clean, updated_at = now()
  from claimable c
 where p.id = c.id and c.rn = 1;
