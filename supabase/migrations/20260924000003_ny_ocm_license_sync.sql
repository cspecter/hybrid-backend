-- A local mirror of New York's cannabis licence register, and a reconciliation
-- against the locations Hybrid already carries.
--
-- WHY THIS EXISTS. Hybrid has 170 New York dispensaries. New York has 879 retail
-- licences that are both Active and operational, 684 of which publish a street
-- address. So the app carries about 23% of the addressable open market, and until now
-- there was no way to know which 23% — locations.state is null on all 312 rows and
-- locations.licenses is empty on all 312, so there was no key to reconcile on and no
-- means of telling a thriving shop from one that closed in 2024.
--
-- The register is free, public, needs no credential, and was last updated the day
-- before this migration was written.
--
--   dataset  data.ny.gov / jskf-tt3q  "Current OCM Licenses"
--
-- NEW JERSEY HAS NO EQUIVALENT. Its open-data entry for dispensaries is a bare link
-- with no API, last touched April 2025; the CRC publishes permits as individual PDFs.
-- The 141 New Jersey locations cannot be reconciled this way and are out of scope
-- here rather than half-handled.

-- ─── The mirror ──────────────────────────────────────────────────────────────
-- Surrogate key and full replacement on every sync, deliberately, because the source
-- has no usable primary key: license_number is null on 355 of 2,995 rows, and
-- coalesce(license_number, application_number) yields only 2,597 distinct values
-- across those rows — amendments and multi-site operators repeat it.
--
-- Full replacement also gets deletions right for free. A revoked licence simply stops
-- appearing in the feed, which an upsert would never notice and which matters more
-- here than the writes saved: a store that lost its licence is precisely the row you
-- must not keep emailing.
create table if not exists public.ny_ocm_licenses (
  id                   bigserial primary key,
  license_number       text,
  application_number   text,
  license_type         text,
  license_status       text,
  operational_status   text,
  entity_name          text,
  dba                  text,
  address_line_1       text,
  address_line_2       text,
  city                 text,
  state                text,
  zip_code             text,
  county               text,
  region               text,
  business_website     text,
  issued_date          text,
  expiration_date      text,
  synced_at            timestamptz not null default now()
);

create index if not exists ny_ocm_licenses_license_number_idx on public.ny_ocm_licenses (license_number);
create index if not exists ny_ocm_licenses_zip_idx            on public.ny_ocm_licenses (left(zip_code, 5));
create index if not exists ny_ocm_licenses_open_retail_idx    on public.ny_ocm_licenses (license_status, operational_status);

comment on table public.ny_ocm_licenses is
  'Mirror of data.ny.gov/jskf-tt3q (Current OCM Licenses). Replaced wholesale by ny_ocm_sync(); never edited by hand.';

-- Every run, successful or not, so a silently stalled sync is visible rather than
-- inferred from a stale synced_at.
create table if not exists public.ny_ocm_sync_log (
  id          bigserial primary key,
  ran_at      timestamptz not null default now(),
  ok          boolean not null,
  rows_fetched integer,
  rows_stored  integer,
  note        text
);

-- ─── Matching helpers ────────────────────────────────────────────────────────
-- Hybrid's address and name fields were imported with the city and state appended
-- and literal tabs left in the middle:
--
--   name           'Gotham Buds<TAB>New York'
--   address_line1  '75 Court St<TAB>Binghamton'
--
-- so neither side can be compared raw. These three do the flattening once, in one
-- place, and are used by both the matching view and anything built on it later.
create or replace function public.ocm_norm(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select regexp_replace(
           regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', ' ', 'g'),
           '\s+', ' ', 'g')
$$;

-- The leading house number, which is the single most discriminating part of a US
-- street address once the zip is known.
create or replace function public.ocm_house_number(p_addr text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif((regexp_match(coalesce(p_addr, ''), '^\s*(\d+)'))[1], '')
$$;

-- Significant words only. The stop list carries street furniture, the state, and the
-- words that appear in so many cannabis business names that matching on them is
-- noise: two shops sharing only the token "cannabis" are not the same shop.
create or replace function public.ocm_tokens(p_text text)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(t order by t), '{}'::text[])
  from (
    select distinct t from regexp_split_to_table(public.ocm_norm(p_text), ' ') t
    where length(t) > 2
      and t !~ '^\d+$'
      and t not in ('st','street','ave','avenue','rd','road','blvd','boulevard','dr','drive',
                    'lane','place','court','hwy','highway','pkwy','parkway','ste','suite','unit',
                    'north','south','east','west','new','york','the','llc','inc','corp',
                    'cannabis','dispensary','company','nyc','dba')
  ) s
$$;

create or replace function public.ocm_overlap(a text[], b text[])
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(x), '{}'::text[])
  from (select unnest(a) intersect select unnest(b)) s(x)
$$;

revoke all on function public.ocm_norm(text)          from public, anon, authenticated;
revoke all on function public.ocm_house_number(text)  from public, anon, authenticated;
revoke all on function public.ocm_tokens(text)        from public, anon, authenticated;
revoke all on function public.ocm_overlap(text[], text[]) from public, anon, authenticated;

-- ─── The sync ────────────────────────────────────────────────────────────────
-- Synchronous on purpose. The register is public and unauthenticated, so there is no
-- credential to hold and no reason to route through an Edge Function; extensions.http
-- fetches 2,995 rows in about 1.2 MB in a single call, which keeps the fetch, the
-- validation and the replacement inside one transaction. If anything throws, the
-- delete rolls back with it and yesterday's mirror survives — the failure mode that
-- matters, because an empty mirror would read as "New York has no dispensaries".
--
-- Nothing is deleted until the new rows have been parsed and counted.
create or replace function public.ny_ocm_sync()
returns integer
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  c_limit    constant integer := 5000;
  v_url      text;
  v_status   integer;
  v_body     text;
  v_rows     jsonb;
  v_fetched  integer;
  v_stored   integer;
begin
  v_url :=
    'https://data.ny.gov/resource/jskf-tt3q.json'
    || '?$select=license_number,application_number,license_type,license_status,'
    || 'operational_status,entity_name,dba,address_line_1,address_line_2,city,state,'
    || 'zip_code,county,region,business_website,issued_date,expiration_date'
    || '&$limit=' || c_limit;

  select status, content into v_status, v_body from extensions.http_get(v_url);

  if v_status is distinct from 200 then
    insert into public.ny_ocm_sync_log (ok, note)
    values (false, format('HTTP %s from data.ny.gov', v_status));
    raise exception 'ny_ocm_sync: data.ny.gov returned HTTP %', v_status;
  end if;

  begin
    v_rows := v_body::jsonb;
  exception when others then
    insert into public.ny_ocm_sync_log (ok, note) values (false, 'response was not JSON');
    raise exception 'ny_ocm_sync: response was not JSON';
  end;

  v_fetched := jsonb_array_length(v_rows);

  -- A register that suddenly returns nothing is far more likely to be an upstream
  -- fault than a state with no licences, and replacing 3,000 good rows with zero is
  -- not a recoverable mistake. Refuse rather than comply.
  if v_fetched is null or v_fetched = 0 then
    insert into public.ny_ocm_sync_log (ok, rows_fetched, note)
    values (false, v_fetched, 'refused: feed returned no rows');
    raise exception 'ny_ocm_sync: feed returned no rows — keeping the existing mirror';
  end if;

  delete from public.ny_ocm_licenses;

  insert into public.ny_ocm_licenses (
    license_number, application_number, license_type, license_status, operational_status,
    entity_name, dba, address_line_1, address_line_2, city, state, zip_code, county,
    region, business_website, issued_date, expiration_date)
  select e->>'license_number', e->>'application_number', e->>'license_type',
         e->>'license_status', e->>'operational_status', e->>'entity_name', e->>'dba',
         e->>'address_line_1', e->>'address_line_2', e->>'city', e->>'state',
         e->>'zip_code', e->>'county', e->>'region', e->>'business_website',
         e->>'issued_date', e->>'expiration_date'
  from jsonb_array_elements(v_rows) e;

  get diagnostics v_stored = row_count;

  insert into public.ny_ocm_sync_log (ok, rows_fetched, rows_stored, note)
  values (true, v_fetched, v_stored,
          case when v_fetched >= c_limit
               then format('WARNING: hit the %s row page limit — raise it, the register has outgrown it', c_limit)
               else null end);

  return v_stored;
end;
$$;

revoke all on function public.ny_ocm_sync() from public, anon, authenticated;

-- ─── The link ────────────────────────────────────────────────────────────────
-- Not unique, and that is not an oversight. One licence can run several storefronts:
-- The Travel Agency trades at Union Square and Downtown Brooklyn under
-- OCM-CAURD-23-000003, and Gotham, CONBUD and Freshly Baked do the same. A unique
-- constraint here would force a choice between rejecting the second shop and
-- pretending it is the first.
alter table public.locations add column if not exists ocm_license_number text;
create index if not exists locations_ocm_license_number_idx on public.locations (ocm_license_number);

comment on column public.locations.ocm_license_number is
  'NY OCM licence this location trades under. Not unique — one licence may cover several storefronts. Set by ny_ocm_apply_matches() or by hand.';

-- ─── Which of ours is which of theirs ────────────────────────────────────────
-- Hybrid's own state column is null on all 312 rows, so New York is identified by
-- joining postal_code_id through to postal_codes.state_code rather than read off the
-- location. Fixing locations.state is a separate job and this does not depend on it.
--
-- SCORING, and why a single signal is not enough. Zip alone is far too coarse in
-- Manhattan. House number alone collides across the state. A shared name token is
-- strong for "Smacked" and worthless for "Green". So:
--
--   zip match                                   1
--   + same house number                        +3   → 4, accepted
--   + a shared street word                     +1
--   a convincing name overlap                  +3   → accepted on its own
--
-- "Convincing" means two shared tokens, or one of six characters or more. That second
-- clause is what catches Happy Munkey and Polanco Brothers, both of which are in the
-- register at a zip Hybrid has wrong — matching on zip alone would have called them
-- absent and sent someone to sign up a store already on the app.
--
-- Threshold 4, not 3: at 3 a lone shared street word plus a zip was enough, which
-- paired Culture House with Terp Bros because both sit in 10001 on Broadway.
create or replace view public.v_ny_ocm_matches as
with hybrid_ny as (
  select l.id, l.name, l.address_line1, l.ocm_license_number,
         left(pc.postal_code, 5) as zip,
         public.ocm_house_number(l.address_line1) as house_no,
         public.ocm_tokens(l.address_line1)       as street_tokens,
         public.ocm_tokens(l.name)                as name_tokens
  from public.locations l
  join public.postal_codes pc on pc.id = l.postal_code_id
  where pc.state_code = 'NY'
),
open_retail as (
  select o.id, o.license_number, o.license_type, o.dba, o.entity_name,
         o.address_line_1, o.city, o.county, o.business_website,
         left(o.zip_code, 5) as zip,
         public.ocm_house_number(o.address_line_1) as house_no,
         public.ocm_tokens(o.address_line_1)       as street_tokens,
         public.ocm_tokens(coalesce(o.dba, '') || ' ' || coalesce(o.entity_name, '')) as name_tokens
  from public.ny_ocm_licenses o
  where o.license_status = 'Active'
    and o.operational_status = 'Active'
    and (o.license_type ilike '%retail%' or o.license_type ilike '%dispensary%'
         or o.license_type ilike '%microbusiness%')
),
scored as (
  select h.id as location_id, h.name as hybrid_name, h.address_line1 as hybrid_address,
         h.zip as hybrid_zip, h.ocm_license_number as linked_license,
         o.license_number, o.license_type, coalesce(o.dba, o.entity_name) as ocm_name,
         o.address_line_1 as ocm_address, o.city as ocm_city, o.county as ocm_county,
         o.business_website,
         (case when h.zip is not null and h.zip = o.zip then 1 else 0 end)
       + (case when h.zip = o.zip and h.house_no is not null
                    and h.house_no = o.house_no then 3 else 0 end)
       + (case when h.zip = o.zip
                    and public.ocm_overlap(h.street_tokens, o.street_tokens) <> '{}' then 1 else 0 end)
       + (case when array_length(public.ocm_overlap(h.name_tokens, o.name_tokens), 1) >= 2
                 or exists (select 1 from unnest(public.ocm_overlap(h.name_tokens, o.name_tokens)) t
                             where length(t) >= 6)
               then 3 else 0 end) as score
  from hybrid_ny h
  cross join open_retail o
)
select distinct on (location_id)
       location_id, hybrid_name, hybrid_address, hybrid_zip, linked_license,
       license_number, license_type, ocm_name, ocm_address, ocm_city, ocm_county,
       business_website, score
from scored
where score >= 4
order by location_id, score desc, license_number;

comment on view public.v_ny_ocm_matches is
  'Best open-OCM-licence candidate for each NY location Hybrid carries. Fuzzy — treat the count as approximate, individual rows as reviewable.';

-- ─── The worklist: open stores Hybrid does not have ──────────────────────────
-- Only rows with a street address. 195 of the 879 open retail licences publish none
-- at all, and a licence with no address cannot be visited, posted to, or added as a
-- location — listing them as "missing" would pad the number with work nobody can do.
--
-- has_website is here because it changes the outreach entirely: only about 30% of the
-- addressable open market publishes one, so for the other 70% the register's street
-- address is the only route to them.
create or replace view public.v_ny_ocm_gap as
select o.license_number, o.license_type, coalesce(o.dba, o.entity_name) as store_name,
       o.entity_name, o.address_line_1, o.city, left(o.zip_code, 5) as zip, o.county,
       o.region, o.business_website,
       nullif(trim(coalesce(o.business_website, '')), '') is not null as has_website,
       o.license_type ilike '%microbusiness%' as is_microbusiness
from public.ny_ocm_licenses o
where o.license_status = 'Active'
  and o.operational_status = 'Active'
  and (o.license_type ilike '%retail%' or o.license_type ilike '%dispensary%'
       or o.license_type ilike '%microbusiness%')
  and nullif(trim(coalesce(o.address_line_1, '')), '') is not null
  and not exists (select 1 from public.v_ny_ocm_matches m
                   where m.license_number = o.license_number)
order by (nullif(trim(coalesce(o.business_website, '')), '') is not null) desc, o.county, o.city;

comment on view public.v_ny_ocm_gap is
  'Open, addressable NY dispensaries with no matching Hybrid location. The store-outreach worklist.';

-- ─── Ours that the register does not vouch for ───────────────────────────────
-- Three different problems wearing one face, which is why the view says which:
--   closed or revoked   — the licence is gone from the open list
--   register artefact   — every Registered Organization row in the register is
--                         flagged Non-Operational, including Curaleaf NY and Etain,
--                         which plainly do trade. Their absence is the register's
--                         fault, not the store's, and emailing them is still fine.
--   bad address         — Hybrid's zip or street is wrong, so nothing lines up
create or replace view public.v_ny_ocm_unvouched as
with hybrid_ny as (
  select l.id, l.name, l.address_line1, left(pc.postal_code, 5) as zip
  from public.locations l
  join public.postal_codes pc on pc.id = l.postal_code_id
  where pc.state_code = 'NY'
)
select h.id as location_id, h.name, h.address_line1, h.zip,
       exists (select 1 from public.ny_ocm_licenses o
                where public.ocm_overlap(public.ocm_tokens(h.name),
                        public.ocm_tokens(coalesce(o.dba,'') || ' ' || coalesce(o.entity_name,''))) <> '{}'
                  and o.license_type ilike '%registered organization%') as looks_like_registered_org,
       exists (select 1 from public.ny_ocm_licenses o
                where public.ocm_overlap(public.ocm_tokens(h.name),
                        public.ocm_tokens(coalesce(o.dba,'') || ' ' || coalesce(o.entity_name,''))) <> '{}') as named_anywhere_in_register
from hybrid_ny h
where not exists (select 1 from public.v_ny_ocm_matches m where m.location_id = h.id)
order by h.id;

comment on view public.v_ny_ocm_unvouched is
  'NY locations Hybrid carries with no open-licence match: closed, a register artefact (see looks_like_registered_org), or a bad address.';

-- ─── One number for "where do we stand" ──────────────────────────────────────
create or replace view public.v_ny_ocm_coverage as
select
  (select count(*) from public.locations l join public.postal_codes pc on pc.id = l.postal_code_id
    where pc.state_code = 'NY')                                   as hybrid_ny_locations,
  (select count(*) from public.ny_ocm_licenses where license_status='Active'
     and operational_status='Active'
     and (license_type ilike '%retail%' or license_type ilike '%dispensary%'
          or license_type ilike '%microbusiness%'))               as ocm_open_retail,
  (select count(*) from public.ny_ocm_licenses where license_status='Active'
     and operational_status='Active'
     and (license_type ilike '%retail%' or license_type ilike '%dispensary%'
          or license_type ilike '%microbusiness%')
     and nullif(trim(coalesce(address_line_1,'')),'') is not null) as ocm_open_addressable,
  (select count(*) from public.v_ny_ocm_matches)                   as matched_locations,
  (select count(distinct license_number) from public.v_ny_ocm_matches) as licences_covered,
  (select count(*) from public.v_ny_ocm_unvouched)                 as unvouched_locations,
  (select count(*) from public.v_ny_ocm_gap)                       as gap_stores,
  (select count(*) from public.v_ny_ocm_gap where has_website)     as gap_with_website,
  (select max(ran_at) from public.ny_ocm_sync_log where ok)        as last_successful_sync;

-- ─── Writing the link back ───────────────────────────────────────────────────
-- Only the confident ones. Score 4 is a zip and a house number agreeing, or a name
-- that is genuinely distinctive; below that a human should look. Never overwrites a
-- value already set by hand.
create or replace function public.ny_ocm_apply_matches(p_min_score integer default 4)
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
    from public.v_ny_ocm_matches m
   where m.location_id = l.id
     and m.score >= p_min_score
     and m.license_number is not null
     and l.ocm_license_number is null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.ny_ocm_apply_matches(integer) from public, anon, authenticated;

-- ─── Locked down ─────────────────────────────────────────────────────────────
-- Public register data, but it is operational intelligence — who Hybrid has not signed
-- yet — and there is no UI for it, so nothing client-facing gets a grant. Open it up
-- deliberately when the admin dashboard grows a screen for it.
revoke all on table public.ny_ocm_licenses  from anon, authenticated;
revoke all on table public.ny_ocm_sync_log   from anon, authenticated;
revoke all on table public.v_ny_ocm_matches   from anon, authenticated;
revoke all on table public.v_ny_ocm_gap       from anon, authenticated;
revoke all on table public.v_ny_ocm_unvouched from anon, authenticated;
revoke all on table public.v_ny_ocm_coverage  from anon, authenticated;

alter table public.ny_ocm_licenses enable row level security;
alter table public.ny_ocm_sync_log  enable row level security;

-- Daily, early, after the register's own overnight refresh and offset from the
-- analytics rollup at 04:25 so two heavy jobs are not competing.
select cron.schedule('ny_ocm_sync', '40 4 * * *', $$select public.ny_ocm_sync()$$);
