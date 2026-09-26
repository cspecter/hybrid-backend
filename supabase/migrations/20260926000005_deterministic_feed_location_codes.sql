-- Stop relying on a random code generator for a bulk insert.
--
-- locations.code is UNIQUE and defaults to generate_randome_code(), which picks a
-- random six-digit number and does not retry. That is survivable for the occasional
-- hand-added store; inserting 826 at once against 312 existing rows made a collision
-- near-certain, and the dry run duly died on code 387078.
--
-- Feed-created rows now get a deterministic code instead: 'LA-' plus the first ten
-- hex characters of the retailer name's md5. Three properties that matter — it cannot
-- collide with the existing codes (all numeric, plus one 'HYBRID-TEST'), it cannot
-- collide with its siblings because retailer names are unique by construction, and
-- re-running the creation computes the same code for the same store rather than
-- minting a second identity for it.
--
-- The typo in generate_randome_code is upstream and left alone; nothing here needs it.

create or replace function public.feed_create_missing_locations()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_created integer := 0;
  v_linked  integer := 0;
  v_stamped integer;
begin
  with candidate as (
    select m.retailer_name, m.ocm_license_number
    from public.feed_retailer_map m
    where m.location_id is null
      and m.retailer_name !~* '^\s*\(?\s*(closed|old|dupe|duplicate|readd|removed|test|inactive|delete|do not use)\b'
      and m.retailer_name !~* '\((closed|dupe|duplicate|old|test|removed|inactive)\)'
      and not exists (select 1 from public.locations l
                       where lower(btrim(l.name)) = lower(btrim(m.retailer_name)))
  ),
  detail as (
    select distinct on (c.retailer_name)
           c.retailer_name, c.ocm_license_number,
           o.address_line_1, o.city, o.zip_code, o.business_website
    from candidate c
    left join public.ny_ocm_licenses o
      on o.license_number = c.ocm_license_number
     and nullif(btrim(coalesce(o.address_line_1,'')),'') is not null
    order by c.retailer_name, o.id
  ),
  inserted as (
    insert into public.locations
      (name, code, status, location_type, address_line1, country, postal_code_id,
       website, ocm_license_number, description)
    select left(d.retailer_name, 255),
           'LA-' || substr(md5(d.retailer_name), 1, 10),
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
    returning id
  )
  select count(*) into v_created from inserted;

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
  refresh materialized view public.mv_location_tokens;

  return jsonb_build_object(
    'locations_created', v_created,
    'retailers_linked',  v_linked,
    'listing_rows_stamped', v_stamped,
    'still_unlinked_retailers', (select count(*) from public.feed_retailer_map where location_id is null));
end;
$$;

revoke all on function public.feed_create_missing_locations() from public, anon, authenticated;
