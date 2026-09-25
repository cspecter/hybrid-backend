-- Take menu data from Lit Alerts instead of crawling 250 sites for it.
--
-- WHY THIS IS THE BETTER SOURCE. Lit Alerts is a paid subscription Hybrid already
-- holds ($500/market/month, API access included in the plan), covering both New York
-- and New Jersey with the menus already normalised, deduplicated and refreshed during
-- business hours. The per-site crawl built yesterday reaches 187 New York sites and no
-- New Jersey sites at all, because New Jersey has no public list of dispensary
-- websites to crawl. One feed replaces both problems.
--
-- THE LICENCE QUESTION IS NOT SETTLED AND THIS SCHEMA DOES NOT SETTLE IT. A market
-- intelligence subscription is normally licensed for internal analysis, and Hybrid
-- would be republishing to 2,485 users, which is a different use. Nothing here
-- promotes a single row into products; landing the data and publishing it are separate
-- steps on purpose, and the second one is blocked on an answer from Lit Alerts.
--
-- WHAT IS DELIBERATELY ABSENT: anything that drives the Lit Alerts dashboard to page
-- past its 10,000-row UI cap. The subscription includes API access, so the cap is
-- something to ask about, not something to engineer around. This importer takes rows
-- from wherever they legitimately arrive — a CSV export, a bulk drop, or the API.

-- ─── The feed carries more than a crawl does ─────────────────────────────────
-- Fields visible in the Lit Alerts listing view that the crawl schema had nowhere to
-- put. days_on_menu and change_24h are the interesting ones: they are derived history,
-- which is exactly what a subscription buys and a single-shot crawl can never produce.
alter table public.menu_items_raw add column if not exists sale_price      numeric(10,2);
alter table public.menu_items_raw add column if not exists quantity        integer;
alter table public.menu_items_raw add column if not exists weight_text     text;
alter table public.menu_items_raw add column if not exists days_on_menu    integer;
alter table public.menu_items_raw add column if not exists change_24h      text;
alter table public.menu_items_raw add column if not exists availability    text;

-- Provenance. Rows now arrive two ways and a reader must be able to tell which without
-- inferring it from which columns happen to be null.
alter table public.menu_items_raw add column if not exists provider        text not null default 'crawl';
alter table public.menu_items_raw add column if not exists retailer_name   text;
alter table public.menu_items_raw add column if not exists retailer_ref    text;
alter table public.menu_items_raw add column if not exists location_id     integer references public.locations(id) on delete set null;
alter table public.menu_items_raw add column if not exists ocm_license_number text;

-- A feed row belongs to a retailer, not to a website we crawled, so the crawl parent
-- can no longer be mandatory.
alter table public.menu_items_raw alter column source_id drop not null;

create index if not exists menu_items_raw_provider_idx  on public.menu_items_raw (provider);
create index if not exists menu_items_raw_location_idx  on public.menu_items_raw (location_id);
create index if not exists menu_items_raw_retailer_idx  on public.menu_items_raw (lower(retailer_name));
create index if not exists menu_items_raw_licence_idx   on public.menu_items_raw (ocm_license_number);

comment on column public.menu_items_raw.provider is
  '''crawl'' = read from a dispensary website by us. ''litalerts'' = supplied by the Lit Alerts subscription.';
comment on column public.menu_items_raw.days_on_menu is
  'Derived history from the feed — how long the listing has been up. A crawl cannot produce this from one visit.';

-- menu_crawls already models "one batch, attributable and discardable as a unit", which
-- is exactly what a feed import needs. Reusing it beats a parallel table that would
-- drift; it just has to say which kind of batch it was.
alter table public.menu_crawls add column if not exists kind      text not null default 'crawl';
alter table public.menu_crawls add column if not exists provider  text;
alter table public.menu_crawls add column if not exists source_label text;

comment on column public.menu_crawls.kind is '''crawl'' or ''feed''.';
comment on column public.menu_crawls.source_label is
  'Where the batch came from in human terms — the export filename, or the API endpoint and window.';

-- ─── Reading a header we have not seen yet ───────────────────────────────────
-- The exact field names are unknown: the listing view shows "Product Name", "Sale
-- Price", "24HR CHANGE", "DAYS ON MENU", but a CSV export and a JSON API rarely agree
-- on casing, spaces or underscores, and this was built from a screenshot rather than
-- from a file. So every field is looked up by trying a list of plausible spellings
-- with case, spaces, underscores and hyphens all flattened.
--
-- The alternative — guessing one spelling and failing on import day — costs a
-- round trip for every column that guessed wrong.
create or replace function public.feed_pick(p_row jsonb, variadic p_keys text[])
returns text
language sql
immutable
set search_path = public
as $$
  select v
  from (
    select k.ord, e.value #>> '{}' as v
    from jsonb_each(p_row) e
    join unnest(p_keys) with ordinality k(want, ord)
      on regexp_replace(lower(e.key), '[^a-z0-9]', '', 'g')
       = regexp_replace(lower(k.want), '[^a-z0-9]', '', 'g')
  ) s
  where nullif(btrim(coalesce(v, '')), '') is not null
    and lower(btrim(v)) not in ('-', '—', 'n/a', 'null', 'none')
  order by ord
  limit 1
$$;

-- "$36.99" / "1,234.50" / "-" → numeric or null. A dash is the feed's way of writing
-- "no sale price", and must not become 0.
create or replace function public.feed_money(p_text text)
returns numeric
language sql
immutable
set search_path = public
as $$
  select nullif(regexp_replace(coalesce(p_text, ''), '[^0-9.]', '', 'g'), '')::numeric
$$;

revoke all on function public.feed_pick(jsonb, text[]) from public, anon, authenticated;
revoke all on function public.feed_money(text)         from public, anon, authenticated;

-- ─── Which of our stores is this ─────────────────────────────────────────────
-- The feed names a retailer; Hybrid needs a location id and, where we have it, the OCM
-- licence. Same standard the OCM reconciliation settled on — two shared name words, or
-- one that is the whole of one side's name — and the same reason: a single shared word
-- matches 'Buffalo Dreams' to 'Buffalo Cannabis Outlet'.
--
-- Both sides have their own city and county words stripped first, because Hybrid's
-- location names carry the city on the end and the feed's retailer names very likely
-- do too.
create or replace function public.feed_match_retailer(p_retailer text)
returns table(location_id integer, ocm_license_number text)
language sql
stable
security definer
set search_path = public
as $$
  with want as (
    select public.ocm_tokens(p_retailer) as toks
  ),
  candidates as (
    select l.id,
           l.ocm_license_number,
           (select coalesce(array_agg(t), '{}'::text[])
              from unnest(public.ocm_tokens(l.name)) t
             where t <> all (public.ocm_tokens(coalesce(pc.place_name,'') || ' ' || coalesce(pc.county,'')))
           ) as name_toks
    from public.locations l
    left join public.postal_codes pc on pc.id = l.postal_code_id
  )
  select c.id, c.ocm_license_number
  from candidates c, want w
  where array_length(public.ocm_overlap(w.toks, c.name_toks), 1) >= 2
     or (array_length(public.ocm_overlap(w.toks, c.name_toks), 1) = 1
         and (array_length(w.toks, 1) = 1 or array_length(c.name_toks, 1) = 1))
  order by array_length(public.ocm_overlap(w.toks, c.name_toks), 1) desc nulls last, c.id
  limit 1
$$;

revoke all on function public.feed_match_retailer(text) from public, anon, authenticated;

-- ─── The importer ────────────────────────────────────────────────────────────
-- Takes an array of rows exactly as the feed gives them and lands them in staging. One
-- batch per call, recorded in menu_crawls, so a bad import is one delete to undo.
--
-- Rows are kept verbatim in `raw` alongside the parsed columns. When a header turns out
-- to be spelled differently from every guess in feed_pick, the value is still in the
-- row and the fix is a re-parse rather than a re-export.
--
-- NOTHING IS PROMOTED INTO products. Landing and publishing are separate steps, and
-- publishing is blocked on the licence question, not on code.
create or replace function public.litalerts_import(
  p_rows         jsonb,
  p_source_label text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_batch   bigint;
  v_count   integer;
  v_matched integer;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'litalerts_import: expected a JSON array of rows';
  end if;
  if jsonb_array_length(p_rows) = 0 then
    raise exception 'litalerts_import: refusing an empty batch';
  end if;

  insert into public.menu_crawls (kind, provider, source_label, sources_tried, sources_ok, note)
  values ('feed', 'litalerts', p_source_label, 1, 1, 'Lit Alerts feed import')
  returning id into v_batch;

  insert into public.menu_items_raw (
    provider, crawl_id, external_id, name, brand, category, subcategory, strain_type,
    thc, cbd, size, weight_text, price, sale_price, quantity, days_on_menu, change_24h,
    availability, in_stock, image_url, retailer_name, retailer_ref, location_id,
    ocm_license_number, raw)
  select
    'litalerts',
    v_batch,
    public.feed_pick(e, 'id', 'listing_id', 'menu_listing_id', 'external_id', 'product_id'),
    coalesce(public.feed_pick(e, 'product_name', 'name', 'product', 'title'), '(unnamed)'),
    public.feed_pick(e, 'brand', 'brand_name'),
    public.feed_pick(e, 'category', 'product_category'),
    public.feed_pick(e, 'subcategory', 'sub_category', 'product_subcategory'),
    public.feed_pick(e, 'strain_type', 'strain', 'type'),
    public.feed_pick(e, 'thc', 'thc_percent', 'thc_content'),
    public.feed_pick(e, 'cbd', 'cbd_percent', 'cbd_content'),
    public.feed_pick(e, 'size', 'dosage', 'dosage_size'),
    public.feed_pick(e, 'weight', 'weight_text', 'unit_weight'),
    public.feed_money(public.feed_pick(e, 'price', 'list_price', 'regular_price')),
    public.feed_money(public.feed_pick(e, 'sale_price', 'saleprice', 'discount_price')),
    nullif(regexp_replace(coalesce(public.feed_pick(e, 'quantity', 'qty', 'stock', 'inventory'), ''), '[^0-9-]', '', 'g'), '')::integer,
    nullif(regexp_replace(coalesce(public.feed_pick(e, 'days_on_menu', 'daysonmenu', 'days'), ''), '[^0-9-]', '', 'g'), '')::integer,
    public.feed_pick(e, '24hr_change', '24hrchange', 'change_24h', 'twentyfourhourchange'),
    public.feed_pick(e, 'status', 'availability', 'stock_status'),
    -- in_stock is derived, not trusted: the feed's own words win where present, and a
    -- zero quantity settles it otherwise. Unknown stays null rather than becoming false.
    case
      when lower(coalesce(public.feed_pick(e, 'status', 'availability', 'stock_status'), '')) like '%not available%' then false
      when lower(coalesce(public.feed_pick(e, 'status', 'availability', 'stock_status'), '')) like '%out of stock%'  then false
      when lower(coalesce(public.feed_pick(e, 'status', 'availability', 'stock_status'), '')) like '%available%'     then true
      when lower(coalesce(public.feed_pick(e, 'status', 'availability', 'stock_status'), '')) like '%low stock%'     then true
      when nullif(regexp_replace(coalesce(public.feed_pick(e, 'quantity', 'qty', 'stock'), ''), '[^0-9-]', '', 'g'), '')::integer = 0 then false
      else null
    end,
    public.feed_pick(e, 'image', 'image_url', 'imageurl', 'thumbnail', 'photo'),
    public.feed_pick(e, 'retailer', 'retailer_name', 'store', 'store_name', 'dispensary', 'location'),
    public.feed_pick(e, 'retailer_id', 'store_id', 'dispensary_id', 'location_id'),
    m.location_id,
    m.ocm_license_number,
    e
  from jsonb_array_elements(p_rows) e
  left join lateral public.feed_match_retailer(
    public.feed_pick(e, 'retailer', 'retailer_name', 'store', 'store_name', 'dispensary', 'location')
  ) m on true;

  get diagnostics v_count = row_count;

  select count(*) into v_matched
    from public.menu_items_raw where crawl_id = v_batch and location_id is not null;

  update public.menu_crawls
     set finished_at = now(), items_found = v_count,
         note = format('Lit Alerts import: %s rows, %s matched to a Hybrid location', v_count, v_matched)
   where id = v_batch;

  return jsonb_build_object(
    'batch_id', v_batch,
    'rows_imported', v_count,
    'matched_to_location', v_matched,
    'unmatched_retailers', (
      select coalesce(jsonb_agg(distinct retailer_name), '[]'::jsonb)
        from public.menu_items_raw
       where crawl_id = v_batch and location_id is null and retailer_name is not null));
end;
$$;

revoke all on function public.litalerts_import(jsonb, text) from public, anon, authenticated;

-- Undo one import without touching anything else.
create or replace function public.feed_batch_discard(p_batch_id bigint)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  delete from public.menu_items_raw where crawl_id = p_batch_id;
  get diagnostics v_n = row_count;
  delete from public.menu_crawls where id = p_batch_id;
  return v_n;
end;
$$;

revoke all on function public.feed_batch_discard(bigint) from public, anon, authenticated;

-- ─── What landed ─────────────────────────────────────────────────────────────
create or replace view public.v_feed_coverage as
select
  (select count(*) from public.menu_items_raw where provider = 'litalerts')                        as feed_items,
  (select count(*) from public.menu_items_raw where provider = 'crawl')                            as crawled_items,
  (select count(distinct retailer_name) from public.menu_items_raw where provider = 'litalerts')   as feed_retailers,
  (select count(distinct location_id) from public.menu_items_raw
     where provider = 'litalerts' and location_id is not null)                                     as retailers_matched,
  (select count(distinct retailer_name) from public.menu_items_raw
     where provider = 'litalerts' and location_id is null)                                         as retailers_unmatched,
  (select count(distinct brand) from public.menu_items_raw where provider = 'litalerts')           as distinct_brands,
  (select count(*) from public.menu_items_raw where provider = 'litalerts' and image_url is not null) as items_with_image,
  (select max(finished_at) from public.menu_crawls where kind = 'feed')                            as last_import;

-- The retailers the feed names that we could not place. This is the worklist that makes
-- the import useful on day one: each one is either a store missing from Hybrid or a name
-- spelled differently on the two sides.
create or replace view public.v_feed_unmatched_retailers as
select retailer_name, count(*) as listings, min(seen_at) as first_seen
from public.menu_items_raw
where provider = 'litalerts' and location_id is null and retailer_name is not null
group by retailer_name
order by listings desc;

revoke all on table public.v_feed_coverage             from anon, authenticated;
revoke all on table public.v_feed_unmatched_retailers  from anon, authenticated;
