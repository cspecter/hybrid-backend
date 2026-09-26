-- Refuse prices that are not prices.
--
-- The NY export contains a $100,000,000.00 pre-roll at Weedly NYC. numeric(10,2) tops
-- out just below 10^8, so the import died on row 52,757 with a numeric field overflow
-- after 50,000 good rows — one bad cell in half a million taking the whole load down.
--
-- WHERE THE LINE GOES, and why it is not arbitrary. Across both states, 748,909 prices:
--
--   median        $40.00
--   99th          $184.99
--   99.99th       $479.92
--   highest real  $1,000.00   (a handful, plausible for bulk or glass)
--   then a gap, then: $99,999 · $999,999 · $10,000,000 · $100,000,000
--
-- Four values, all obvious upstream typos, separated from everything credible by two
-- orders of magnitude. A $10,000 ceiling sits in that gap with enormous room above
-- anything real.
--
-- The rejected value is not lost: menu_items_raw.raw keeps the row verbatim, and
-- v_feed_rejected_prices lists every rejection so a ceiling that turns out to be wrong
-- is visible rather than silently eating good data.
create or replace function public.feed_money(p_text text, p_max numeric default 10000)
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare v text; n numeric;
begin
  v := nullif(regexp_replace(coalesce(p_text, ''), '[^0-9.]', '', 'g'), '');
  if v is null then return null; end if;
  begin
    n := v::numeric;
  exception when others then
    return null;                       -- '1.2.3' and similar: missing, not fatal
  end;
  if n > p_max then return null; end if;
  return n;
end;
$$;

revoke all on function public.feed_money(text, numeric) from public, anon, authenticated;

-- Every row whose source carried a number we declined to store. Empty is the expected
-- state; anything in here is either upstream junk or a ceiling set too low.
create or replace view public.v_feed_rejected_prices as
select id, crawl_id, left(name, 60) as name, retailer_name,
       raw->>'normal_price' as raw_price, raw->>'sale_price' as raw_sale_price
from public.menu_items_raw
where provider = 'litalerts'
  and ((price is null and nullif(regexp_replace(coalesce(raw->>'normal_price',''), '[^0-9.]','','g'),'') is not null)
    or (sale_price is null and nullif(regexp_replace(coalesce(raw->>'sale_price',''), '[^0-9.]','','g'),'') is not null));

revoke all on table public.v_feed_rejected_prices from anon, authenticated;

-- The importer, reproduced from the applied definition and diffed. No change to its
-- own text: feed_money keeps its single-argument call signature and picks up the
-- default ceiling. Re-issued so the dependency is recorded with this migration.
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
