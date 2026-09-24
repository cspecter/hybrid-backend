-- Foundations for building a live product list from dispensary websites.
--
-- SCOPE, stated up front because it is narrower than "scrape New York and New Jersey"
-- and the difference is not a matter of effort:
--
--   NEW YORK is workable. The OCM register publishes a website for 275 of the open
--   retail licences — 251 distinct hosts — so there is a target list to crawl.
--
--   NEW JERSEY HAS NO TARGET LIST. locations.website is populated on 1 of 312 rows
--   across the whole app, New Jersey's open-data entry for dispensaries is a bare link
--   with no API, and the CRC publishes permits as individual PDFs with no websites and
--   no addresses in them. Before a single New Jersey menu can be read, somebody has to
--   discover ~240 websites from business names — which means either a search engine
--   (whose terms forbid automated querying, so it trades one exposure for a worse one)
--   or manual work. That is a decision, not a task, so New Jersey is absent here
--   rather than half-built. The tables below are state-agnostic and will take it.
--
-- WHAT THIS CRAWLS AND WHAT IT WILL NOT. Dispensaries' own public websites, which is
-- ordinary practice. Not Weedmaps, Leafly or Dutchie's marketplace: taking an
-- aggregator's compiled database is a different act with a different risk, and nothing
-- here points at one. robots.txt is obeyed, the crawler identifies itself with a
-- contact address, and no bot protection is circumvented — a site that refuses us is
-- recorded as refusing us and skipped.

-- ─── What platform each site runs ────────────────────────────────────────────
-- Fingerprints first, extractors second. Dispensary sites almost never hand-roll a
-- menu; they embed one from a handful of providers, so the work is a small number of
-- adapters plus the knowledge of which site needs which. Guessing that distribution
-- would have been the expensive mistake.
create table if not exists public.menu_sources (
  id                bigserial primary key,
  host              text not null unique,
  license_number    text,
  store_name        text,
  homepage_url      text,
  menu_url          text,
  platform          text,
  cms               text,
  robots_verdict    text,
  crawlable         boolean not null default true,
  last_probed_at    timestamptz,
  last_probe_note   text,
  consecutive_fails integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists menu_sources_platform_idx  on public.menu_sources (platform);
create index if not exists menu_sources_crawlable_idx on public.menu_sources (crawlable);
create index if not exists menu_sources_licence_idx   on public.menu_sources (license_number);

comment on table public.menu_sources is
  'One row per dispensary website: which menu platform it runs and whether we may crawl it. crawlable=false means robots.txt said no.';
comment on column public.menu_sources.robots_verdict is
  'What robots.txt actually said. "bot protection" is distinct from "blocked" — a 403 from a CDN is not the site declining to be crawled.';

-- ─── Raw menu rows, exactly as found ─────────────────────────────────────────
-- Staging, deliberately separate from products. Scraped data is a claim about the
-- world, not a fact: prices go stale within the hour, names are inconsistent between
-- stores, and the same product appears under four spellings. Landing it raw means a
-- bad crawl can be discarded without having corrupted a catalogue that 2,485 people
-- see — and the 40,147 rows already in products, 37,941 of them still drafts from a
-- 2025 import, are argument enough for not writing straight into it.
create table if not exists public.menu_items_raw (
  id              bigserial primary key,
  source_id       bigint not null references public.menu_sources(id) on delete cascade,
  crawl_id        bigint,
  external_id     text,
  name            text not null,
  brand           text,
  category        text,
  subcategory     text,
  strain_type     text,
  thc             text,
  cbd             text,
  size            text,
  unit            text,
  price           numeric(10,2),
  price_currency  text default 'USD',
  in_stock        boolean,
  image_url       text,
  raw             jsonb,
  seen_at         timestamptz not null default now()
);

create index if not exists menu_items_raw_source_idx on public.menu_items_raw (source_id);
create index if not exists menu_items_raw_crawl_idx  on public.menu_items_raw (crawl_id);
create index if not exists menu_items_raw_name_idx   on public.menu_items_raw (lower(name));

comment on table public.menu_items_raw is
  'Menu rows as scraped, one batch per crawl. Never read directly by the app — promotion into products is a separate, reviewed step.';

-- One row per crawl, so a run can be attributed, counted and thrown away as a unit.
create table if not exists public.menu_crawls (
  id            bigserial primary key,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  sources_tried integer not null default 0,
  sources_ok    integer not null default 0,
  items_found   integer not null default 0,
  note          text
);

comment on table public.menu_crawls is
  'One row per crawl run. menu_items_raw.crawl_id points here so a bad batch can be identified and deleted wholesale.';

alter table public.menu_sources   enable row level security;
alter table public.menu_items_raw enable row level security;
alter table public.menu_crawls    enable row level security;

revoke all on table public.menu_sources   from anon, authenticated;
revoke all on table public.menu_items_raw from anon, authenticated;
revoke all on table public.menu_crawls    from anon, authenticated;

-- ─── Seed the target list from the register ──────────────────────────────────
-- Hosts come from the licence register rather than from locations.website, which is
-- populated on 1 of 312 rows. Host, not full URL, is the identity: six licences share
-- evlfarm.com and three share flynnstoned.com, so a chain is one site to crawl and
-- several licences to attribute it to.
create or replace function public.menu_sources_seed_ny()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  insert into public.menu_sources (host, license_number, store_name, homepage_url)
  select distinct on (host) host, license_number, store_name, homepage_url
  from (
    select lower(regexp_replace(
             regexp_replace(o.business_website, '^https?://', '', 'i'),
             '^www\.', '', 'i')) as raw_host,
           o.license_number,
           coalesce(o.dba, o.entity_name) as store_name,
           case when o.business_website ~* '^https?://' then o.business_website
                else 'https://' || o.business_website end as homepage_url
    from public.ny_ocm_licenses o
    where o.license_status = 'Active'
      and o.operational_status = 'Active'
      and (o.license_type ilike '%retail%' or o.license_type ilike '%dispensary%'
           or o.license_type ilike '%microbusiness%')
      and nullif(trim(coalesce(o.business_website, '')), '') is not null
  ) s
  cross join lateral (select split_part(split_part(s.raw_host, '/', 1), '?', 1) as host) h
  where h.host <> ''
  order by host, license_number
  on conflict (host) do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.menu_sources_seed_ny() from public, anon, authenticated;

-- ─── What the crawler needs, and what it reports back ────────────────────────
-- The crawler runs outside the database — fetching 250 sites with age gates and
-- JavaScript menus is not work for plpgsql — so these two are its whole contract:
-- ask what to crawl, hand back what happened.
create or replace view public.v_menu_crawl_queue as
select id as source_id, host, homepage_url, menu_url, platform, license_number, store_name
from public.menu_sources
where crawlable
  and consecutive_fails < 5     -- stop knocking on a door that has not opened five times
order by last_probed_at nulls first, id;

comment on view public.v_menu_crawl_queue is
  'Sites the crawler may fetch, oldest probe first. Excludes robots.txt refusals and anything that has failed five times running.';

create or replace function public.menu_source_record_probe(
  p_source_id bigint,
  p_ok boolean,
  p_platform text default null,
  p_cms text default null,
  p_menu_url text default null,
  p_robots_verdict text default null,
  p_crawlable boolean default null,
  p_note text default null)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  update public.menu_sources set
    platform          = coalesce(p_platform, platform),
    cms               = coalesce(p_cms, cms),
    menu_url          = coalesce(p_menu_url, menu_url),
    robots_verdict    = coalesce(p_robots_verdict, robots_verdict),
    crawlable         = coalesce(p_crawlable, crawlable),
    last_probed_at    = now(),
    last_probe_note   = p_note,
    consecutive_fails = case when p_ok then 0 else consecutive_fails + 1 end,
    updated_at        = now()
  where id = p_source_id;
end;
$$;

revoke all on function public.menu_source_record_probe(bigint, boolean, text, text, text, text, boolean, text)
  from public, anon, authenticated;

-- ─── Where we stand ──────────────────────────────────────────────────────────
create or replace view public.v_menu_coverage as
select
  (select count(*) from public.menu_sources)                          as sites_known,
  (select count(*) from public.menu_sources where not crawlable)      as sites_robots_blocked,
  (select count(*) from public.menu_sources where platform is not null) as sites_with_known_platform,
  (select count(*) from public.menu_sources where last_probed_at is null) as sites_never_probed,
  (select count(*) from public.menu_items_raw)                        as raw_items,
  (select count(distinct source_id) from public.menu_items_raw)       as sites_with_items,
  (select max(finished_at) from public.menu_crawls)                   as last_crawl;

revoke all on table public.v_menu_crawl_queue from anon, authenticated;
revoke all on table public.v_menu_coverage    from anon, authenticated;
