-- Replace the scoring total with an explicit rule, and stop matching stores on the
-- name of the town they are in.
--
-- WHAT WAS WRONG. Hybrid's location names carry the city on the end — 'Buffalo Dreams
-- Buffalo', 'Central Budz Yonkers', 'Herb-Z North Syracuse' — and the matcher treated
-- every word in the name as evidence of identity. Because a city name is comfortably
-- longer than six characters, it satisfied the "one long shared word is convincing"
-- rule on its own. Audited output, all wrong, all the same mistake:
--
--   Buffalo Dreams Buffalo   -> Buffalo Cannabis Outlet   shared: buffalo
--   Central Budz Yonkers     -> YONKERS DREAM LLC         shared: yonkers
--   Herb-Z North Syracuse    -> Thrive Syracuse           shared: syracuse
--   Fiorello Pharmaceuticals -> Mango Cannabis            shared: rochester
--
-- A first attempt to rescue those by adding "+1 when the city agrees" made it worse
-- rather than better: the same city word then supplied both the name evidence and the
-- geographic evidence, so one weak coincidence was counted twice and cleared the bar.
--
-- THE FIX is at the root. Each row's own city and county words are removed from its
-- name tokens before anything is compared, so a town can no longer be mistaken for a
-- brand. Nothing is hardcoded: the words come from postal_codes for Hybrid's side and
-- from the register's own city/county columns for theirs.
--
-- AND THE RULE IS NOW A RULE, not a total. Points were the wrong shape — they let
-- unrelated weak signals accumulate into a confident-looking match. Each basis below
-- stands on its own and says what it is, so a match can be argued with:
--
--   address      same zip and same house number
--   name         two or more shared name words
--   street+name  same zip, a shared street word, and a shared name word
--   name+county  one shared name word of six characters or more, same county, AND
--                that word is the whole of one side's name
--
-- That last clause is doing real work. Without it 'Culture House New York' matched
-- 'Buzzwick Uptown' on the single coincidental word 'culture' — while Culture House's
-- own licence is Inactive, so it has in fact closed. With it, 'Stoops NYC' still
-- matches 'Stoops NYC' and Culture House correctly falls through to unvouched.
--
-- WHERE THE BIAS POINTS, deliberately. A missed match costs one unnecessary outreach
-- email. A wrong match hides an open store from outreach for good AND leaves a closed
-- one sitting in the app. So where the evidence is thin this under-matches on purpose.

-- ─── Clean name tokens, city and county removed ──────────────────────────────
drop materialized view if exists public.mv_ny_ocm_matches cascade;
drop materialized view if exists public.mv_ny_ocm_hybrid_ny cascade;

create materialized view public.mv_ny_ocm_hybrid_ny as
select l.id, l.name, l.address_line1, l.ocm_license_number,
       left(pc.postal_code, 5)                  as zip5,
       pc.place_name                            as city,
       pc.county                                as county,
       public.ocm_house_number(l.address_line1) as house_no,
       public.ocm_tokens(l.address_line1)       as street_tokens,
       (select coalesce(array_agg(t), '{}'::text[])
          from unnest(public.ocm_tokens(l.name)) t
         where t <> all (public.ocm_tokens(coalesce(pc.place_name, '') || ' ' || coalesce(pc.county, '')))
       ) as name_tokens
from public.locations l
join public.postal_codes pc on pc.id = l.postal_code_id
where pc.state_code = 'NY';

create unique index mv_ny_ocm_hybrid_ny_id_idx     on public.mv_ny_ocm_hybrid_ny (id);
create index        mv_ny_ocm_hybrid_ny_tokens_idx on public.mv_ny_ocm_hybrid_ny using gin (name_tokens);
create index        mv_ny_ocm_hybrid_ny_zip_idx    on public.mv_ny_ocm_hybrid_ny (zip5);

comment on materialized view public.mv_ny_ocm_hybrid_ny is
  'Hybrid NY locations with matching keys precomputed. name_tokens excludes the location own city and county words.';

-- The register side loses its own city and county words too: several rows put the town
-- in the trade name, which would reintroduce the same class of false match from the
-- other direction.
alter table public.ny_ocm_licenses add column if not exists clean_name_tokens text[];

update public.ny_ocm_licenses o set clean_name_tokens = (
  select coalesce(array_agg(t), '{}'::text[]) from unnest(o.name_tokens) t
   where t <> all (public.ocm_tokens(coalesce(o.city, '') || ' ' || coalesce(o.county, '')))
);

create index if not exists ny_ocm_licenses_clean_tokens_idx
  on public.ny_ocm_licenses using gin (clean_name_tokens);

-- ─── The matches ─────────────────────────────────────────────────────────────
create materialized view public.mv_ny_ocm_matches as
with open_retail as (
  select o.license_number, o.license_type, o.dba, o.entity_name, o.address_line_1,
         o.city, o.county, o.business_website, o.zip5, o.house_no,
         o.street_tokens, o.clean_name_tokens
  from public.ny_ocm_licenses o
  where o.license_status = 'Active'
    and o.operational_status = 'Active'
    and (o.license_type ilike '%retail%' or o.license_type ilike '%dispensary%'
         or o.license_type ilike '%microbusiness%')
),
candidates as (
  -- Only pairs that could satisfy some basis. Everything else is not generated, which
  -- is what keeps this off the statement timeout it used to hit.
  select h.id as location_id, h.name as hybrid_name, h.address_line1 as hybrid_address,
         h.zip5 as hybrid_zip, h.ocm_license_number as linked_license,
         o.license_number, o.license_type,
         coalesce(o.dba, o.entity_name) as ocm_name,
         o.address_line_1 as ocm_address, o.city as ocm_city, o.county as ocm_county,
         o.business_website,
         public.ocm_overlap(h.name_tokens, o.clean_name_tokens) as shared_name_tokens,
         array_length(h.name_tokens, 1)       as hybrid_name_token_count,
         array_length(o.clean_name_tokens, 1) as ocm_name_token_count,
         (h.zip5 is not null and h.zip5 = o.zip5
            and h.house_no is not null and h.house_no = o.house_no) as addr_strong,
         (h.zip5 is not null and h.zip5 = o.zip5
            and h.street_tokens && o.street_tokens)                 as addr_street,
         (public.ocm_norm(h.county) = public.ocm_norm(o.county)
            and nullif(trim(coalesce(o.county, '')), '') is not null) as county_match
  from public.mv_ny_ocm_hybrid_ny h
  join open_retail o
    on (h.zip5 is not null and h.zip5 = o.zip5)
    or h.name_tokens && o.clean_name_tokens
),
ruled as (
  select c.*,
         coalesce(array_length(c.shared_name_tokens, 1), 0) as n_shared,
         case
           when c.addr_strong then 'address'
           when coalesce(array_length(c.shared_name_tokens, 1), 0) >= 2 then 'name'
           when c.addr_street
                and coalesce(array_length(c.shared_name_tokens, 1), 0) >= 1 then 'street+name'
           -- One word only: it must be long, the county must agree, and it must be the
           -- whole of one side's name. 'Stoops NYC' passes; 'Culture House' does not.
           when coalesce(array_length(c.shared_name_tokens, 1), 0) = 1
                and c.county_match
                and exists (select 1 from unnest(c.shared_name_tokens) t where length(t) >= 6)
                and (c.hybrid_name_token_count = 1 or c.ocm_name_token_count = 1)
             then 'name+county'
           else null
         end as basis
  from candidates c
)
select distinct on (location_id)
       location_id, hybrid_name, hybrid_address, hybrid_zip, linked_license,
       license_number, license_type, ocm_name, ocm_address, ocm_city, ocm_county,
       business_website, shared_name_tokens, basis
from ruled
where basis is not null
order by location_id,
         case basis when 'address' then 1 when 'name' then 2
                    when 'street+name' then 3 else 4 end,
         license_number;

create unique index mv_ny_ocm_matches_location_idx on public.mv_ny_ocm_matches (location_id);
create index        mv_ny_ocm_matches_licence_idx  on public.mv_ny_ocm_matches (license_number);

comment on materialized view public.mv_ny_ocm_matches is
  'One best open-licence match per NY location, with the basis it was matched on. Audit weak bases (name+county, street+name) before trusting them in bulk.';

-- ─── Views rebuilt on the new matview ────────────────────────────────────────
create or replace view public.v_ny_ocm_matches as
  select location_id, hybrid_name, hybrid_address, hybrid_zip, linked_license,
         license_number, license_type, ocm_name, ocm_address, ocm_city, ocm_county,
         business_website, shared_name_tokens, basis
  from public.mv_ny_ocm_matches;

create or replace view public.v_ny_ocm_gap as
select o.license_number, o.license_type, coalesce(o.dba, o.entity_name) as store_name,
       o.entity_name, o.address_line_1, o.city, o.zip5 as zip, o.county,
       o.region, o.business_website,
       nullif(trim(coalesce(o.business_website, '')), '') is not null as has_website,
       o.license_type ilike '%microbusiness%' as is_microbusiness
from public.ny_ocm_licenses o
left join public.mv_ny_ocm_matches m on m.license_number = o.license_number
where o.license_status = 'Active'
  and o.operational_status = 'Active'
  and (o.license_type ilike '%retail%' or o.license_type ilike '%dispensary%'
       or o.license_type ilike '%microbusiness%')
  and nullif(trim(coalesce(o.address_line_1, '')), '') is not null
  and m.license_number is null
order by (nullif(trim(coalesce(o.business_website, '')), '') is not null) desc, o.county, o.city;

-- named_anywhere_in_register used the same any-single-token test that caused the city
-- false matches, so it was true for almost every row and told you nothing. It now uses
-- the same standard as a real match: two shared words, or one that is the whole name.
create or replace view public.v_ny_ocm_unvouched as
select h.id as location_id, h.name, h.address_line1, h.zip5 as zip, h.city, h.county,
       exists (select 1 from public.ny_ocm_licenses o
                where o.license_type ilike '%registered organization%'
                  and (array_length(public.ocm_overlap(h.name_tokens, o.clean_name_tokens), 1) >= 2
                    or (array_length(public.ocm_overlap(h.name_tokens, o.clean_name_tokens), 1) = 1
                        and (array_length(h.name_tokens,1) = 1 or array_length(o.clean_name_tokens,1) = 1)))
              ) as looks_like_registered_org,
       (select string_agg(distinct o.license_status || '/' || o.operational_status, ', ')
          from public.ny_ocm_licenses o
         where array_length(public.ocm_overlap(h.name_tokens, o.clean_name_tokens), 1) >= 2
            or (array_length(public.ocm_overlap(h.name_tokens, o.clean_name_tokens), 1) = 1
                and (array_length(h.name_tokens,1) = 1 or array_length(o.clean_name_tokens,1) = 1))
       ) as register_status_if_named
from public.mv_ny_ocm_hybrid_ny h
left join public.mv_ny_ocm_matches m on m.location_id = h.id
where m.location_id is null
order by h.id;

comment on view public.v_ny_ocm_unvouched is
  'NY locations with no open-licence match. register_status_if_named tells closed (Inactive/...) from register artefact (Active/Non-Operational, e.g. every Registered Organization) from simply absent (null).';

create or replace view public.v_ny_ocm_coverage as
select
  (select count(*) from public.mv_ny_ocm_hybrid_ny)                as hybrid_ny_locations,
  (select count(*) from public.ny_ocm_licenses where license_status='Active'
     and operational_status='Active'
     and (license_type ilike '%retail%' or license_type ilike '%dispensary%'
          or license_type ilike '%microbusiness%'))                as ocm_open_retail,
  (select count(*) from public.ny_ocm_licenses where license_status='Active'
     and operational_status='Active'
     and (license_type ilike '%retail%' or license_type ilike '%dispensary%'
          or license_type ilike '%microbusiness%')
     and nullif(trim(coalesce(address_line_1,'')),'') is not null)  as ocm_open_addressable,
  (select count(*) from public.mv_ny_ocm_matches)                   as matched_locations,
  (select count(*) from public.mv_ny_ocm_matches where basis='address') as matched_on_address,
  (select count(*) from public.mv_ny_ocm_matches where basis<>'address') as matched_on_name,
  (select count(distinct license_number) from public.mv_ny_ocm_matches) as licences_covered,
  (select count(*) from public.v_ny_ocm_unvouched)                  as unvouched_locations,
  (select count(*) from public.v_ny_ocm_gap)                        as gap_stores,
  (select count(*) from public.v_ny_ocm_gap where has_website)      as gap_with_website,
  (select max(ran_at) from public.ny_ocm_sync_log where ok)         as last_successful_sync;

-- ─── Sync keeps the new column in step ───────────────────────────────────────
create or replace function public.ny_ocm_sync()
returns integer
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  c_limit   constant integer := 5000;
  v_url     text; v_status integer; v_body text; v_rows jsonb;
  v_fetched integer; v_stored integer;
begin
  v_url := 'https://data.ny.gov/resource/jskf-tt3q.json'
    || '?$select=license_number,application_number,license_type,license_status,'
    || 'operational_status,entity_name,dba,address_line_1,address_line_2,city,state,'
    || 'zip_code,county,region,business_website,issued_date,expiration_date'
    || '&$limit=' || c_limit;

  select status, content into v_status, v_body from extensions.http_get(v_url);

  if v_status is distinct from 200 then
    insert into public.ny_ocm_sync_log (ok, note) values (false, format('HTTP %s from data.ny.gov', v_status));
    raise exception 'ny_ocm_sync: data.ny.gov returned HTTP %', v_status;
  end if;

  begin
    v_rows := v_body::jsonb;
  exception when others then
    insert into public.ny_ocm_sync_log (ok, note) values (false, 'response was not JSON');
    raise exception 'ny_ocm_sync: response was not JSON';
  end;

  v_fetched := jsonb_array_length(v_rows);
  if v_fetched is null or v_fetched = 0 then
    insert into public.ny_ocm_sync_log (ok, rows_fetched, note)
    values (false, v_fetched, 'refused: feed returned no rows');
    raise exception 'ny_ocm_sync: feed returned no rows — keeping the existing mirror';
  end if;

  delete from public.ny_ocm_licenses;

  insert into public.ny_ocm_licenses (
    license_number, application_number, license_type, license_status, operational_status,
    entity_name, dba, address_line_1, address_line_2, city, state, zip_code, county,
    region, business_website, issued_date, expiration_date,
    zip5, house_no, street_tokens, name_tokens, clean_name_tokens)
  select e->>'license_number', e->>'application_number', e->>'license_type',
         e->>'license_status', e->>'operational_status', e->>'entity_name', e->>'dba',
         e->>'address_line_1', e->>'address_line_2', e->>'city', e->>'state',
         e->>'zip_code', e->>'county', e->>'region', e->>'business_website',
         e->>'issued_date', e->>'expiration_date',
         left(e->>'zip_code', 5),
         public.ocm_house_number(e->>'address_line_1'),
         public.ocm_tokens(e->>'address_line_1'),
         public.ocm_tokens(coalesce(e->>'dba','') || ' ' || coalesce(e->>'entity_name','')),
         (select coalesce(array_agg(t), '{}'::text[])
            from unnest(public.ocm_tokens(coalesce(e->>'dba','') || ' ' || coalesce(e->>'entity_name',''))) t
           where t <> all (public.ocm_tokens(coalesce(e->>'city','') || ' ' || coalesce(e->>'county',''))))
  from jsonb_array_elements(v_rows) e;

  get diagnostics v_stored = row_count;

  refresh materialized view public.mv_ny_ocm_hybrid_ny;
  refresh materialized view public.mv_ny_ocm_matches;

  insert into public.ny_ocm_sync_log (ok, rows_fetched, rows_stored, note)
  values (true, v_fetched, v_stored,
          case when v_fetched >= c_limit
               then format('WARNING: hit the %s row page limit — raise it', c_limit) end);
  return v_stored;
end;
$$;

-- ny_ocm_apply_matches took a score; the rule replaced scores with a basis. Dropped
-- first because the signature changes.
drop function if exists public.ny_ocm_apply_matches(integer);

-- Only the bases that survived an audit of every row. 'name+county' is deliberately
-- excluded from bulk application: it is sound on the rows it now returns, but it is
-- the rule most likely to be wrong on data nobody has looked at yet, and writing a
-- wrong licence number onto a location is the one mistake here that is hard to spot
-- later. Apply those by hand.
create or replace function public.ny_ocm_apply_matches(
  p_bases text[] default array['address','name','street+name'])
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  update public.locations l
     set ocm_license_number = m.license_number
    from public.mv_ny_ocm_matches m
   where m.location_id = l.id
     and m.basis = any (p_bases)
     and m.license_number is not null
     and l.ocm_license_number is null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.ny_ocm_sync()                     from public, anon, authenticated;
revoke all on function public.ny_ocm_apply_matches(text[])      from public, anon, authenticated;
revoke all on table public.mv_ny_ocm_hybrid_ny from anon, authenticated;
revoke all on table public.mv_ny_ocm_matches   from anon, authenticated;
revoke all on table public.v_ny_ocm_matches    from anon, authenticated;
revoke all on table public.v_ny_ocm_gap        from anon, authenticated;
revoke all on table public.v_ny_ocm_unvouched  from anon, authenticated;
revoke all on table public.v_ny_ocm_coverage   from anon, authenticated;
