-- Two columns the second export brought, and a warning about one of them.
--
-- The 25 Sep re-export added brand, dispensary, is_available and last_seen. brand,
-- dispensary and the rest already mapped. These two did not:
--
--   is_available  the alias list had status / availability / stock_status, and the
--                 values are the strings 'True' and 'False' rather than words
--   last_seen     no column existed for it at all
--
-- WHY last_seen MATTERS MORE THAN is_available. 91,800 New York rows (18.4%) and
-- 38,407 New Jersey rows (15.5%) are flagged available while not having been seen on
-- any menu for over thirty days. Believing is_available on its own would put tens of
-- thousands of listings in front of users as in-stock when the crawler behind the feed
-- has not laid eyes on them since spring. last_seen is the honest freshness signal and
-- anything user-facing should filter on it.
alter table public.menu_items_raw add column if not exists last_seen_at timestamptz;
create index if not exists menu_items_raw_last_seen_idx on public.menu_items_raw (last_seen_at desc nulls last);

comment on column public.menu_items_raw.last_seen_at is
  'When the feed last saw this listing on a menu. The real freshness signal — is_available stays true on listings unseen for months.';

-- Tolerant of what the export actually writes: '2026-09-23 18:34:34.250669+00' has a
-- two-digit offset, which to_timestamp handles but ISO parsers frequently do not.
create or replace function public.feed_timestamp(p_text text)
returns timestamptz
language plpgsql
immutable
set search_path = public
as $$
declare v text := nullif(btrim(coalesce(p_text, '')), '');
begin
  if v is null or lower(v) in ('null', 'none', '-') then return null; end if;
  begin
    return v::timestamptz;
  exception when others then
    return null;      -- an unreadable date is missing data, never a failed import
  end;
end;
$$;

revoke all on function public.feed_timestamp(text) from public, anon, authenticated;

-- ─── The importer, reproduced from the applied definition and diffed ─────────
-- Changes: is_available joins the availability aliases, True/False strings are decoded
-- ahead of the word tests so 'false' cannot be swallowed by the '%available%' branch,
-- and last_seen lands in last_seen_at.
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
    ocm_license_number, last_seen_at, raw)
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
    public.feed_pick(e, 'is_available', 'status', 'availability', 'stock_status'),
    case
      -- The export writes the literal strings 'True' and 'False'; earlier shapes wrote
      -- words. Both are handled, exact matches first so 'false' cannot be swallowed by
      -- the '%available%' test below it.
      when lower(coalesce(public.feed_pick(e, 'is_available', 'status', 'availability', 'stock_status'), '')) in ('true','t','yes','1')  then true
      when lower(coalesce(public.feed_pick(e, 'is_available', 'status', 'availability', 'stock_status'), '')) in ('false','f','no','0') then false
      when lower(coalesce(public.feed_pick(e, 'is_available', 'status', 'availability', 'stock_status'), '')) like '%not available%' then false
      when lower(coalesce(public.feed_pick(e, 'is_available', 'status', 'availability', 'stock_status'), '')) like '%out of stock%'  then false
      when lower(coalesce(public.feed_pick(e, 'is_available', 'status', 'availability', 'stock_status'), '')) like '%available%'     then true
      when lower(coalesce(public.feed_pick(e, 'is_available', 'status', 'availability', 'stock_status'), '')) like '%low stock%'     then true
      when nullif(regexp_replace(coalesce(public.feed_pick(e, 'quantity', 'qty', 'stock'), ''), '[^0-9-]', '', 'g'), '')::integer = 0 then false
      else null
    end,
    public.feed_pick(e, 'image', 'image_url', 'imageurl', 'thumbnail', 'photo'),
    public.feed_pick(e, 'retailer', 'retailer_name', 'store', 'store_name', 'dispensary', 'location'),
    public.feed_pick(e, 'retailer_id', 'store_id', 'dispensary_id', 'location_id'),
    -- Left null on purpose. feed_resolve_retailers() decides once per distinct
    -- retailer name, then feed_apply_retailer_map() stamps the answer onto these rows.
    null::integer, null::text,
    public.feed_timestamp(public.feed_pick(e, 'last_seen', 'lastseen', 'last_seen_at', 'seen_at')),
    e
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
