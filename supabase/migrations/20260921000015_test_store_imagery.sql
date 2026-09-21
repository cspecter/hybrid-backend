-- Give the test store imagery that reads as a shop.
--
-- The seed reused cloud_files 1 and 2, which are `placeholders/list_bg_...` and
-- `placeholders/Stashlist_Photo_...` — stashlist artwork, not store imagery. The
-- store page and the budtender badge both drew that, so the badge showed a list
-- background where the dispensary's picture belongs.
--
-- WHAT WAS AVAILABLE. Only 5 assets live under placeholders/, none of them
-- shop-like, and exactly one location in 312 has a logo at all (this one). The 351
-- images under dispensary_locations/banner/ are the only real storefront pictures
-- on the system — and every one of them is a photograph of a real business.
--
-- 259554 was chosen after looking at several: a shopfront with no dominant
-- third-party mark in frame. Candidates carrying a chain's signage (Ascend, Reef,
-- 1634 Funk) were rejected because the test store would then look like that
-- business, and one showing identifiable people was rejected outright — real
-- people should not front a fictitious shop.
--
-- It is still someone's real storefront. If that matters for a demo, replace
-- logo_id and banner_id with an asset of Hybrid's own; there is not one in
-- cloud_files today.

update public.locations
   set logo_id   = 259554,
       banner_id = 259554
 where name = 'Hybrid Test Dispensary';

do $$
declare u text;
begin
  select coalesce(cf.secure_url, cf.url) into u
    from public.locations l join public.cloud_files cf on cf.id = l.logo_id
   where l.name = 'Hybrid Test Dispensary';
  if u is null or u like '%/placeholders/%' then
    raise exception 'test store imagery did not take: %', coalesce(u, 'null');
  end if;
  raise notice 'test store imagery: %', u;
end $$;
