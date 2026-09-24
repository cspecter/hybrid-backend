-- Make the reconciliation actually runnable.
--
-- The first cut of v_ny_ocm_matches cross-joined 170 Hybrid locations against 684 open
-- licences and called ocm_tokens() on both sides of all 116,000 pairs. Reading
-- v_ny_ocm_coverage hit the statement timeout in ocm_norm and never returned — and
-- v_ny_ocm_gap made it worse, re-evaluating the entire match view once per candidate
-- row because it referenced it inside a NOT EXISTS.
--
-- Two changes fix it, and neither alters a single match:
--
--   1. Tokenise once, at write time, not once per comparison. The register's rows get
--      their zip, house number and token arrays stored alongside them.
--   2. Only compare pairs that could possibly score. A pair sharing neither a zip nor
--      one name token scores zero on the existing rules, so restricting the join to
--      "same zip OR overlapping name tokens" — with a GIN index behind it — throws
--      away only pairs that were already going to be discarded.
--
-- The scoring, the threshold and therefore the results are unchanged; this is purely
-- about not computing the same regex 116,000 times.

-- ─── Stored tokens on the mirror ─────────────────────────────────────────────
alter table public.ny_ocm_licenses add column if not exists zip5          text;
alter table public.ny_ocm_licenses add column if not exists house_no      text;
alter table public.ny_ocm_licenses add column if not exists street_tokens text[];
alter table public.ny_ocm_licenses add column if not exists name_tokens   text[];

create index if not exists ny_ocm_licenses_name_tokens_idx on public.ny_ocm_licenses using gin (name_tokens);
create index if not exists ny_ocm_licenses_zip5_idx        on public.ny_ocm_licenses (zip5);

-- Backfill what the first sync already stored.
update public.ny_ocm_licenses set
  zip5          = left(zip_code, 5),
  house_no      = public.ocm_house_number(address_line_1),
  street_tokens = public.ocm_tokens(address_line_1),
  name_tokens   = public.ocm_tokens(coalesce(dba, '') || ' ' || coalesce(entity_name, ''))
where name_tokens is null;

-- ─── Hybrid's side, precomputed too ──────────────────────────────────────────
-- A materialized view because locations change far less often than this gets read,
-- and because the alternative is paying for 170 tokenisations on every query.
-- Refreshed by ny_ocm_sync(); refresh it by hand after a bulk location import.
drop materialized view if exists public.mv_ny_ocm_hybrid_ny cascade;
create materialized view public.mv_ny_ocm_hybrid_ny as
select l.id, l.name, l.address_line1, l.ocm_license_number,
       left(pc.postal_code, 5)                  as zip5,
       public.ocm_house_number(l.address_line1) as house_no,
       public.ocm_tokens(l.address_line1)       as street_tokens,
       public.ocm_tokens(l.name)                as name_tokens
from public.locations l
join public.postal_codes pc on pc.id = l.postal_code_id
where pc.state_code = 'NY';

create unique index mv_ny_ocm_hybrid_ny_id_idx  on public.mv_ny_ocm_hybrid_ny (id);
create index mv_ny_ocm_hybrid_ny_tokens_idx on public.mv_ny_ocm_hybrid_ny using gin (name_tokens);
create index mv_ny_ocm_hybrid_ny_zip_idx    on public.mv_ny_ocm_hybrid_ny (zip5);

-- ─── The matches, computed once ──────────────────────────────────────────────
-- Same scoring as before, spelled out in 20260924000003:
--   zip 1, + same house number 3, + shared street word 1, convincing name overlap 3.
--   Threshold 4. "Convincing" = two shared tokens, or one of six characters or more.
drop materialized view if exists public.mv_ny_ocm_matches cascade;
create materialized view public.mv_ny_ocm_matches as
with open_retail as (
  select o.license_number, o.license_type, o.dba, o.entity_name, o.address_line_1,
         o.city, o.county, o.business_website, o.zip5, o.house_no,
         o.street_tokens, o.name_tokens
  from public.ny_ocm_licenses o
  where o.license_status = 'Active'
    and o.operational_status = 'Active'
    and (o.license_type ilike '%retail%' or o.license_type ilike '%dispensary%'
         or o.license_type ilike '%microbusiness%')
),
candidates as (
  -- The restriction that makes this tractable. A pair with neither a shared zip nor a
  -- shared name token cannot reach the threshold, so it is not generated.
  select h.id as location_id, h.name as hybrid_name, h.address_line1 as hybrid_address,
         h.zip5 as hybrid_zip, h.ocm_license_number as linked_license,
         o.license_number, o.license_type,
         coalesce(o.dba, o.entity_name) as ocm_name,
         o.address_line_1 as ocm_address, o.city as ocm_city, o.county as ocm_county,
         o.business_website,
         public.ocm_overlap(h.name_tokens, o.name_tokens) as shared_name_tokens,
         (case when h.zip5 is not null and h.zip5 = o.zip5 then 1 else 0 end)
       + (case when h.zip5 = o.zip5 and h.house_no is not null and h.house_no = o.house_no
               then 3 else 0 end)
       + (case when h.zip5 = o.zip5 and h.street_tokens && o.street_tokens then 1 else 0 end)
         as address_score
  from public.mv_ny_ocm_hybrid_ny h
  join open_retail o
    on (h.zip5 is not null and h.zip5 = o.zip5)
    or h.name_tokens && o.name_tokens
),
scored as (
  select c.*,
         c.address_score
       + (case when array_length(c.shared_name_tokens, 1) >= 2
                 or exists (select 1 from unnest(c.shared_name_tokens) t where length(t) >= 6)
               then 3 else 0 end) as score
  from candidates c
)
select distinct on (location_id)
       location_id, hybrid_name, hybrid_address, hybrid_zip, linked_license,
       license_number, license_type, ocm_name, ocm_address, ocm_city, ocm_county,
       business_website, shared_name_tokens, score
from scored
where score >= 4
order by location_id, score desc, license_number;

create unique index mv_ny_ocm_matches_location_idx on public.mv_ny_ocm_matches (location_id);
create index mv_ny_ocm_matches_licence_idx  on public.mv_ny_ocm_matches (license_number);

-- ─── Rebuilt on top of the matview ───────────────────────────────────────────
-- v_ny_ocm_matches stays as the public name so nothing downstream has to know the
-- computation moved.
create or replace view public.v_ny_ocm_matches as
  select location_id, hybrid_name, hybrid_address, hybrid_zip, linked_license,
         license_number, license_type, ocm_name, ocm_address, ocm_city, ocm_county,
         business_website, score
  from public.mv_ny_ocm_matches;

-- The gap, as an anti-join rather than a correlated NOT EXISTS over the match view.
-- That single change is the difference between one pass and 684 of them.
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

create or replace view public.v_ny_ocm_unvouched as
select h.id as location_id, h.name, h.address_line1, h.zip5 as zip,
       exists (select 1 from public.ny_ocm_licenses o
                where o.name_tokens && h.name_tokens
                  and o.license_type ilike '%registered organization%') as looks_like_registered_org,
       exists (select 1 from public.ny_ocm_licenses o
                where o.name_tokens && h.name_tokens)                   as named_anywhere_in_register
from public.mv_ny_ocm_hybrid_ny h
left join public.mv_ny_ocm_matches m on m.location_id = h.id
where m.location_id is null
order by h.id;

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
  (select count(distinct license_number) from public.mv_ny_ocm_matches) as licences_covered,
  (select count(*) from public.v_ny_ocm_unvouched)                  as unvouched_locations,
  (select count(*) from public.v_ny_ocm_gap)                        as gap_stores,
  (select count(*) from public.v_ny_ocm_gap where has_website)      as gap_with_website,
  (select max(ran_at) from public.ny_ocm_sync_log where ok)         as last_successful_sync;

-- ─── Sync, now also responsible for the derived tables ───────────────────────
-- Tokenising at write time and refreshing both matviews in the same transaction as
-- the replacement, so the mirror and everything derived from it are never out of step
-- with each other — a reader either sees yesterday's whole picture or today's.
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
    zip5, house_no, street_tokens, name_tokens)
  select e->>'license_number', e->>'application_number', e->>'license_type',
         e->>'license_status', e->>'operational_status', e->>'entity_name', e->>'dba',
         e->>'address_line_1', e->>'address_line_2', e->>'city', e->>'state',
         e->>'zip_code', e->>'county', e->>'region', e->>'business_website',
         e->>'issued_date', e->>'expiration_date',
         left(e->>'zip_code', 5),
         public.ocm_house_number(e->>'address_line_1'),
         public.ocm_tokens(e->>'address_line_1'),
         public.ocm_tokens(coalesce(e->>'dba', '') || ' ' || coalesce(e->>'entity_name', ''))
  from jsonb_array_elements(v_rows) e;

  get diagnostics v_stored = row_count;

  -- Not CONCURRENTLY: that is disallowed inside a transaction block, and holding a
  -- brief lock on two derived views nothing user-facing reads is the cheaper trade
  -- than letting them disagree with the mirror.
  refresh materialized view public.mv_ny_ocm_hybrid_ny;
  refresh materialized view public.mv_ny_ocm_matches;

  insert into public.ny_ocm_sync_log (ok, rows_fetched, rows_stored, note)
  values (true, v_fetched, v_stored,
          case when v_fetched >= c_limit
               then format('WARNING: hit the %s row page limit — raise it, the register has outgrown it', c_limit)
               else null end);

  return v_stored;
end;
$$;

revoke all on function public.ny_ocm_sync() from public, anon, authenticated;
revoke all on table public.mv_ny_ocm_hybrid_ny from anon, authenticated;
revoke all on table public.mv_ny_ocm_matches   from anon, authenticated;
revoke all on table public.v_ny_ocm_matches    from anon, authenticated;
revoke all on table public.v_ny_ocm_gap        from anon, authenticated;
revoke all on table public.v_ny_ocm_unvouched  from anon, authenticated;
revoke all on table public.v_ny_ocm_coverage   from anon, authenticated;
