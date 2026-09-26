-- Match on an exact name before trying to be clever, and never fight the unique index.
--
-- A dry run of feed_create_missing_locations died on locations_name_unique: "Chronic
-- Brooklyn" already exists. The feed names it identically and the matcher still missed
-- it, because the two sides are tokenised asymmetrically — a location's own city word
-- is stripped from its tokens, the feed's retailer name keeps it. So "Chronic
-- Brooklyn" tokenises to {chronic} on one side and {chronic, brooklyn} on the other:
-- one word in common, and the single-word rule requires the FEED side to be one word,
-- which it is not.
--
-- Two retailers were affected. The number is small; the failure was not, because it
-- would have tried to insert a duplicate name and taken the whole creation down.
--
-- An exact, case-insensitive name comparison now runs first. Reaching for fuzzy
-- matching before checking whether the strings are simply equal was the actual mistake.

create or replace function public.feed_resolve_retailers()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_new integer; v_exact integer; v_loc integer; v_lic integer;
begin
  insert into public.feed_retailer_map (retailer_name, listings_seen)
  select r.retailer_name, count(*)
    from public.menu_items_raw r
   where r.retailer_name is not null
     and not exists (select 1 from public.feed_retailer_map m where m.retailer_name = r.retailer_name)
   group by r.retailer_name;
  get diagnostics v_new = row_count;

  -- Identical names. No tokenising, no scoring, no argument.
  update public.feed_retailer_map m
     set location_id = l.id, ocm_license_number = coalesce(m.ocm_license_number, l.ocm_license_number),
         matched_on = 'exact-name', resolved_at = now()
    from public.locations l
   where m.location_id is null and not m.confirmed_by_human
     and lower(btrim(l.name)) = lower(btrim(m.retailer_name));
  get diagnostics v_exact = row_count;

  with cand as (
    select m.retailer_name, t.id as location_id, t.ocm_license_number,
           public.ocm_overlap(public.ocm_tokens(m.retailer_name), t.name_tokens) as shared
      from public.feed_retailer_map m
      join public.mv_location_tokens t
        on public.ocm_tokens(m.retailer_name) && t.name_tokens
     where m.location_id is null and not m.confirmed_by_human
  ), ruled as (
    select distinct on (retailer_name) retailer_name, location_id, ocm_license_number,
           case when array_length(shared,1) >= 2 then 'name' else 'name-single' end as basis
      from cand
     where array_length(shared,1) >= 2
        or (array_length(shared,1) = 1 and array_length(public.ocm_tokens(retailer_name),1) = 1)
     order by retailer_name, array_length(shared,1) desc
  )
  update public.feed_retailer_map m
     set location_id = r.location_id, ocm_license_number = r.ocm_license_number,
         matched_on = r.basis, resolved_at = now()
    from ruled r where r.retailer_name = m.retailer_name;
  get diagnostics v_loc = row_count;

  with cand as (
    select m.retailer_name, o.license_number,
           public.ocm_overlap(public.ocm_tokens(m.retailer_name), o.clean_name_tokens) as shared
      from public.feed_retailer_map m
      join public.ny_ocm_licenses o
        on public.ocm_tokens(m.retailer_name) && o.clean_name_tokens
     where m.location_id is null and m.ocm_license_number is null and not m.confirmed_by_human
       and o.license_status = 'Active' and o.operational_status = 'Active'
  ), ruled as (
    select distinct on (retailer_name) retailer_name, license_number
      from cand where array_length(shared,1) >= 2
     order by retailer_name, array_length(shared,1) desc
  )
  update public.feed_retailer_map m
     set ocm_license_number = r.license_number, matched_on = 'ocm-register', resolved_at = now()
    from ruled r where r.retailer_name = m.retailer_name;
  get diagnostics v_lic = row_count;

  return jsonb_build_object('new_retailers', v_new, 'matched_exact_name', v_exact,
                            'matched_to_location', v_loc, 'matched_to_licence_only', v_lic,
                            'still_unresolved', (select count(*) from public.feed_retailer_map
                                                  where location_id is null and ocm_license_number is null));
end;
$$;

revoke all on function public.feed_resolve_retailers() from public, anon, authenticated;

-- The creator, reproduced from the applied definition, with the uniqueness guard added.
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
      -- locations.name is UNIQUE. Even with the exact-name pass in front of this, a
      -- name already taken must never reach the insert: one collision aborts the whole
      -- creation. Belt as well as braces, because the cost of being wrong is total.
      and not exists (select 1 from public.locations l
                       where lower(btrim(l.name)) = lower(btrim(m.retailer_name)))
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
