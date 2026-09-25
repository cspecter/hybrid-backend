-- Teach feed_pick the spellings the real export actually uses.
--
-- The first Lit Alerts export arrived on 25 Sep with eight columns:
--   name, category, subcategory, normal_price, sale_price, quantity, size, Days On Menu
--
-- Seven mapped on the first try. `normal_price` did not — the guesses were price,
-- list_price and regular_price — so every row would have imported with a null price
-- while looking otherwise healthy. Exactly the failure the raw-row-preserved design
-- was for: the fix is this one line plus a re-parse, not another export.
--
-- Also confirmed against the real file: the export writes an absent sale price as the
-- literal string NULL rather than the UI's dash. feed_pick already discards both.
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
    and lower(btrim(v)) not in ('-', '—', 'n/a', 'null', 'none', 'nil')
  order by ord
  limit 1
$$;

revoke all on function public.feed_pick(jsonb, text[]) from public, anon, authenticated;

-- The importer carries its own alias list per field, so it needs the same addition.
-- Reproduced from the applied definition and diffed; the only change is the price line.
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
    m.location_id, m.ocm_license_number, e
  from jsonb_array_elements(p_rows) e
  left join lateral public.feed_match_retailer(
    public.feed_pick(e, 'retailer', 'retailer_name', 'store', 'store_name', 'dispensary', 'location')
  ) m on true;

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
