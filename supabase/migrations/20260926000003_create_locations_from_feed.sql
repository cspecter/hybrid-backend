-- Create a Hybrid location for every dispensary the feed knows and we do not.
--
-- The 25 Sep import brought 1,186 distinct retailers across New York and New Jersey
-- against Hybrid's 312 locations. 317 matched. The rest — 869 — are real dispensaries
-- trading in both states that the app has never heard of, and while they are missing,
-- 538,220 of the 748,909 listings (72%) have nowhere to attach.
--
-- TWO THINGS THIS DELIBERATELY DOES NOT DO.
--
-- It does not create everything. The feed's retailer names carry Lit Alerts' own
-- housekeeping in the string — "(CLOSED) - Columbia Care - Manhattan", "(DUPE) -
-- Curaleaf - Newburgh (REC)", "(Old) Bellanova", "(Removed) New Amsterdam NYC". Those
-- are closed shops, duplicates and retired records; importing them would put shut
-- dispensaries in the app and duplicate stores already there. 43 retailers carry such
-- a marker and are skipped.
--
-- It does not publish them. locations is read by the app with
-- .in("status", ["published","active"]) and .limit(1000) — with 312 rows today, adding
-- 826 published rows would cross that limit and silently drop existing stores from the
-- app, which is a far worse outcome than a missing new one. Everything lands as
-- 'draft': linked for data, invisible to users until someone raises the limit and
-- promotes them deliberately.
--
-- ADDRESSES come from the OCM register where the retailer matched a licence. New
-- Jersey has no register, so most New Jersey rows are a name and a state. That is a
-- real quality difference and v_feed_locations_needing_detail reports it rather than
-- letting it pass as complete.

create or replace function public.feed_create_missing_locations()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_created integer := 0;
  v_linked  integer := 0;
  v_stamped integer;
begin
  -- Draft locations for every clean, unlinked retailer.
  with candidate as (
    select m.retailer_name, m.ocm_license_number
    from public.feed_retailer_map m
    where m.location_id is null
      -- Lit Alerts' housekeeping markers, at the start or in brackets anywhere.
      and m.retailer_name !~* '^\s*\(?\s*(closed|old|dupe|duplicate|readd|removed|test|inactive|delete|do not use)\b'
      and m.retailer_name !~* '\((closed|dupe|duplicate|old|test|removed|inactive)\)'
  ),
  -- The register row, when we have a licence for it. distinct on because a licence can
  -- appear more than once in the mirror.
  detail as (
    select distinct on (c.retailer_name)
           c.retailer_name, c.ocm_license_number,
           o.address_line_1, o.city, o.zip_code, o.state, o.business_website
    from candidate c
    left join public.ny_ocm_licenses o
      on o.license_number = c.ocm_license_number
     and nullif(btrim(coalesce(o.address_line_1,'')),'') is not null
    order by c.retailer_name, o.id
  ),
  inserted as (
    insert into public.locations
      (name, status, location_type, address_line1, country, postal_code_id,
       website, ocm_license_number, description)
    select left(d.retailer_name, 255),
           'draft',
           'dispensary',
           nullif(btrim(coalesce(d.address_line_1, '')), ''),
           'US',
           (select pc.id from public.postal_codes pc
             where pc.postal_code = left(d.zip_code, 5) and pc.country_code = 'US'
             order by pc.id limit 1),
           nullif(btrim(coalesce(d.business_website, '')), ''),
           d.ocm_license_number,
           'Created from the Lit Alerts feed on ' || to_char(now(), 'YYYY-MM-DD')
             || '. Draft until reviewed.'
    from detail d
    returning id, name
  )
  select count(*) into v_created from inserted;

  -- Point the retailer map at whichever location now carries that exact name. Matching
  -- on the literal name rather than on the matcher, because we just created these and
  -- know the name is identical — no fuzzy logic where an exact answer exists.
  update public.feed_retailer_map m
     set location_id = l.id,
         matched_on  = coalesce(m.matched_on, 'created-from-feed'),
         resolved_at = now()
    from public.locations l
   where m.location_id is null
     and l.name = left(m.retailer_name, 255)
     and l.status = 'draft';
  get diagnostics v_linked = row_count;

  v_stamped := public.feed_apply_retailer_map(null);

  -- Names changed, so the token matview is stale for anything built on it.
  refresh materialized view public.mv_location_tokens;

  return jsonb_build_object(
    'locations_created', v_created,
    'retailers_linked',  v_linked,
    'listing_rows_stamped', v_stamped,
    'still_unlinked_retailers', (select count(*) from public.feed_retailer_map where location_id is null));
end;
$$;

revoke all on function public.feed_create_missing_locations() from public, anon, authenticated;

-- What was created without enough detail to be publishable. New Jersey dominates this
-- because no licence register exists there to draw an address from.
create or replace view public.v_feed_locations_needing_detail as
select l.id, l.name, l.status, l.ocm_license_number,
       l.address_line1 is null as no_address,
       l.postal_code_id is null as no_postcode,
       l.coordinates is null as no_coordinates,
       (select count(*) from public.menu_items_raw r where r.location_id = l.id) as listings
from public.locations l
where l.status = 'draft'
  and l.description like 'Created from the Lit Alerts feed%'
  and (l.address_line1 is null or l.postal_code_id is null)
order by listings desc;

revoke all on table public.v_feed_locations_needing_detail from anon, authenticated;
