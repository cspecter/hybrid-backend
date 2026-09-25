-- Stop matching retailers one row at a time.
--
-- feed_match_retailer was called through a LATERAL join, once per imported row, and
-- each call tokenised the name of every location in the database. At 400 rows nobody
-- noticed. At 5,000 it is 1.5 million tokenisations and the insert dies on the
-- statement timeout — which is what a 5,000-row chunk of the real 570,129-row export
-- did. The same mistake the OCM matching view made a day earlier: a per-row function
-- over a set that should have been prepared once.
--
-- The fix is to separate the two jobs. Importing stores the retailer's name and stops.
-- Resolution happens afterwards, once per DISTINCT name rather than once per row —
-- and a 570,000-row state export contains a few hundred distinct retailers, not
-- 570,000. The answers are then cached, so re-importing tomorrow resolves nothing it
-- already knows.

-- ─── Location names, tokenised once ──────────────────────────────────────────
-- Both states. The OCM matview covers New York only because that is all the register
-- knows; retailer matching has to work for New Jersey's 141 locations too, which have
-- no register behind them and can only ever be matched on name.
drop materialized view if exists public.mv_location_tokens cascade;
create materialized view public.mv_location_tokens as
select l.id,
       l.name,
       l.ocm_license_number,
       pc.state_code,
       (select coalesce(array_agg(t), '{}'::text[])
          from unnest(public.ocm_tokens(l.name)) t
         where t <> all (public.ocm_tokens(coalesce(pc.place_name, '') || ' ' || coalesce(pc.county, '')))
       ) as name_tokens
from public.locations l
left join public.postal_codes pc on pc.id = l.postal_code_id;

create unique index mv_location_tokens_id_idx     on public.mv_location_tokens (id);
create index        mv_location_tokens_tokens_idx on public.mv_location_tokens using gin (name_tokens);

comment on materialized view public.mv_location_tokens is
  'Every location with its name tokens precomputed, own city and county words removed. Refresh after a bulk location change.';

-- ─── One decision per retailer, remembered ───────────────────────────────────
-- confirmed_by_human exists so a correction survives the next resolution pass. The
-- matcher is good but not right every time, and the cost of re-deciding the same
-- wrong answer every import is that nobody bothers correcting it once.
create table if not exists public.feed_retailer_map (
  retailer_name      text primary key,
  location_id        integer references public.locations(id) on delete set null,
  ocm_license_number text,
  matched_on         text,
  confirmed_by_human boolean not null default false,
  listings_seen      integer not null default 0,
  first_seen         timestamptz not null default now(),
  resolved_at        timestamptz
);

create index if not exists feed_retailer_map_location_idx on public.feed_retailer_map (location_id);

comment on table public.feed_retailer_map is
  'Feed retailer name -> Hybrid location. One row per distinct name. confirmed_by_human rows are never re-decided.';

-- ─── Resolve everything unresolved, in one pass ──────────────────────────────
-- Same rule the OCM reconciliation settled on: two shared name words, or one that is
-- the whole of one side's name. A single shared word matched 'Buffalo Dreams' to
-- 'Buffalo Cannabis Outlet', which is why one word is not enough on its own.
--
-- New York gets a second chance the register makes possible: a retailer that matches
-- no Hybrid location may still match an open OCM licence, which both identifies the
-- store and says it is one Hybrid should be carrying and does not.
create or replace function public.feed_resolve_retailers()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_new integer; v_loc integer; v_lic integer;
begin
  -- Names seen in staging that we have never decided on.
  insert into public.feed_retailer_map (retailer_name, listings_seen)
  select r.retailer_name, count(*)
    from public.menu_items_raw r
   where r.retailer_name is not null
     and not exists (select 1 from public.feed_retailer_map m where m.retailer_name = r.retailer_name)
   group by r.retailer_name;
  get diagnostics v_new = row_count;

  -- Against Hybrid's own locations.
  with cand as (
    select m.retailer_name, t.id as location_id, t.ocm_license_number,
           public.ocm_overlap(public.ocm_tokens(m.retailer_name), t.name_tokens) as shared
      from public.feed_retailer_map m
      join public.mv_location_tokens t
        on public.ocm_tokens(m.retailer_name) && t.name_tokens
     where m.location_id is null and not m.confirmed_by_human
  ), ruled as (
    select distinct on (retailer_name) retailer_name, location_id, ocm_license_number,
           case when array_length(shared,1) >= 2 then 'name' else 'name-single' end as basis,
           array_length(shared,1) as n
      from cand
     where array_length(shared,1) >= 2
        or (array_length(shared,1) = 1
            and (array_length(public.ocm_tokens(retailer_name),1) = 1))
     order by retailer_name, array_length(shared,1) desc
  )
  update public.feed_retailer_map m
     set location_id = r.location_id, ocm_license_number = r.ocm_license_number,
         matched_on = r.basis, resolved_at = now()
    from ruled r where r.retailer_name = m.retailer_name;
  get diagnostics v_loc = row_count;

  -- New York only: still unmatched, but the register knows them.
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

  return jsonb_build_object('new_retailers', v_new, 'matched_to_location', v_loc,
                            'matched_to_licence_only', v_lic,
                            'still_unresolved', (select count(*) from public.feed_retailer_map
                                                  where location_id is null and ocm_license_number is null));
end;
$$;

-- Stamp the resolved answers back onto the staged rows. Separate from resolution so a
-- correction to the map can be re-applied without re-importing anything.
create or replace function public.feed_apply_retailer_map(p_batch_id bigint default null)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  update public.menu_items_raw r
     set location_id = m.location_id, ocm_license_number = m.ocm_license_number
    from public.feed_retailer_map m
   where m.retailer_name = r.retailer_name
     and (p_batch_id is null or r.crawl_id = p_batch_id)
     and (r.location_id is distinct from m.location_id
       or r.ocm_license_number is distinct from m.ocm_license_number);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.feed_resolve_retailers()          from public, anon, authenticated;
revoke all on function public.feed_apply_retailer_map(bigint)   from public, anon, authenticated;
revoke all on table public.mv_location_tokens   from anon, authenticated;
revoke all on table public.feed_retailer_map    from anon, authenticated;
alter table public.feed_retailer_map enable row level security;

-- ─── The importer, no longer matching per row ────────────────────────────────
-- Reproduced from the applied definition and diffed. The only change is that the
-- LATERAL call to feed_match_retailer is gone and location_id / ocm_license_number are
-- left for the resolution pass to fill.
create or replace function public.litalerts_import(
  p_rows         jsonb,
  p_source_label text default null,
  p_batch_id     bigint default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_batch   bigint;
  v_own     boolean := p_batch_id is null;
  v_count   integer;
  v_matched integer;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'litalerts_import: expected a JSON array of rows';
  end if;
  if jsonb_array_length(p_rows) = 0 then
    raise exception 'litalerts_import: refusing an empty batch';
  end if;

  if v_own then
    v_batch := public.feed_batch_open(p_source_label);
  else
    v_batch := p_batch_id;
    if not exists (select 1 from public.menu_crawls where id = v_batch) then
      raise exception 'litalerts_import: batch % does not exist', v_batch;
    end if;
  end if;

  insert into public.menu_items_raw (
    provider, crawl_id, external_id, name, brand, category, subcategory, strain_type,
    thc, cbd, size, weight_text, price, sale_price, quantity, days_on_menu, change_24h,
    availability, in_stock, image_url, retailer_name, retailer_ref, location_id,
    ocm_license_number, raw)
  select
    'litalerts', v_batch,
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
    public.feed_money(public.feed_pick(e, 'normal_price', 'price', 'list_price', 'regular_price', 'base_price')),
    public.feed_money(public.feed_pick(e, 'sale_price', 'saleprice', 'discount_price')),
    nullif(regexp_replace(coalesce(public.feed_pick(e, 'quantity', 'qty', 'stock', 'inventory'), ''), '[^0-9-]', '', 'g'), '')::integer,
    nullif(regexp_replace(coalesce(public.feed_pick(e, 'days_on_menu', 'daysonmenu', 'days'), ''), '[^0-9-]', '', 'g'), '')::integer,
    public.feed_pick(e, '24hr_change', '24hrchange', 'change_24h', 'twentyfourhourchange'),
    public.feed_pick(e, 'status', 'availability', 'stock_status'),
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
    -- Left null on purpose. feed_resolve_retailers() decides once per distinct
    -- retailer name, then feed_apply_retailer_map() stamps the answer onto these rows.
    null::integer, null::text, e
  from jsonb_array_elements(p_rows) e;

  get diagnostics v_count = row_count;

  if v_own then
    perform public.feed_batch_close(v_batch);
  end if;

  select count(*) into v_matched
    from public.menu_items_raw where crawl_id = v_batch and location_id is not null;

  return jsonb_build_object(
    'batch_id', v_batch, 'rows_imported', v_count, 'matched_to_location', v_matched,
    'unmatched_retailers', (
      select coalesce(jsonb_agg(distinct retailer_name), '[]'::jsonb)
        from public.menu_items_raw
       where crawl_id = v_batch and location_id is null and retailer_name is not null));
end;
$$;

revoke all on function public.litalerts_import(jsonb, text, bigint) from public, anon, authenticated;

-- feed_match_retailer was only ever called from the importer's lateral join. Dropped so
-- nothing reintroduces the per-row pattern by reaching for the obvious-looking helper.
drop function if exists public.feed_match_retailer(text);
