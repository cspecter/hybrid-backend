-- The marker filter was half-broken, and ten closed or duplicate stores got in.
--
-- feed_create_missing_locations excluded Lit Alerts' housekeeping names with two
-- patterns. The first, anchored with an optional escaped bracket:
--
--   name ~* '^\s*\(?\s*(closed|old|dupe|...|readd|removed|...)\b'
--
-- never matched anything. Tested directly against '(Readd) Curaleaf - Carle Place'
-- it returns false. Postgres's advanced regex does not treat '\(?' the way the
-- pattern assumed, so the whole first rule was dead and every exclusion that appeared
-- to work came from the second pattern alone.
--
-- The second only matched a marker word immediately followed by a closing bracket, so
-- these all got through and became locations:
--
--   (Outdated) The Botanist - Collingswood     'outdated' was not in the list
--   (Readd) Curaleaf - Carle Place             first rule was dead
--   (Remove) Good Daze Dispensary              'remove', not 'removed'
--   (Removed )Munchies Dispensary              space before the bracket
--   (Removed, Moved) Curaleaf - Bellmawr       comma before the bracket
--
-- One pattern now does the job, using a character class instead of an escaped group,
-- dropping the requirement for a closing bracket, and covering the variants seen.
-- Verified against all ten offenders and against 'Treehouse - Nyack' and 'Zen Leaf -
-- Neptune Township', which must not match.
create or replace function public.feed_name_is_housekeeping(p_name text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_name, '') ~*
    '^\s*[\(\[]?\s*(closed|old|out ?dated|dupe|duplicate|re-?add|removed?|test|inactive|delete|do not use|archive)'
$$;

revoke all on function public.feed_name_is_housekeeping(text) from public, anon, authenticated;

-- Remove the ten that should never have been created. Narrow on purpose: draft only,
-- feed-created only, marker only. menu_items_raw.location_id and
-- feed_retailer_map.location_id are both ON DELETE SET NULL, so their listings simply
-- go back to being unattached, which is the correct state for a store that is shut.
delete from public.locations l
where l.status = 'draft'
  and l.description like 'Created from the Lit Alerts feed%'
  and public.feed_name_is_housekeeping(l.name);

-- And use the fixed test from here on.
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
      and not public.feed_name_is_housekeeping(m.retailer_name)
      and not exists (select 1 from public.locations l
                       where lower(btrim(l.name)) = lower(btrim(m.retailer_name)))
  ),
  detail as (
    select distinct on (c.retailer_name)
           c.retailer_name, c.ocm_license_number,
           o.address_line_1, o.zip_code, o.business_website
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
           'draft', 'dispensary',
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

  return jsonb_build_object('locations_created', v_created, 'retailers_linked', v_linked,
    'listing_rows_stamped', v_stamped,
    'still_unlinked_retailers', (select count(*) from public.feed_retailer_map where location_id is null));
end;
$$;

revoke all on function public.feed_create_missing_locations() from public, anon, authenticated;
