-- Let one import arrive in pieces.
--
-- litalerts_import created a batch per call, which is right for a few hundred rows and
-- wrong for the real thing: the Lit Alerts listing view alone caps at 10,000 rows and
-- the full New York + New Jersey feed is larger again. Sending that as one statement
-- means a single enormous JSON literal, and a failure anywhere loses all of it.
--
-- So a batch can now be opened once and filled by many calls. The loader sends a few
-- hundred rows at a time; they all land in one batch, so the import is still a single
-- unit to inspect, count, or discard.
create or replace function public.feed_batch_open(
  p_source_label text,
  p_provider     text default 'litalerts')
returns bigint
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_id bigint;
begin
  insert into public.menu_crawls (kind, provider, source_label, sources_tried, sources_ok, note)
  values ('feed', p_provider, p_source_label, 1, 0, 'open')
  returning id into v_id;
  return v_id;
end;
$$;

-- Counts are recomputed from the rows rather than accumulated, so a retried chunk
-- cannot inflate them.
create or replace function public.feed_batch_close(p_batch_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_items integer; v_matched integer; v_retailers integer;
begin
  select count(*), count(*) filter (where location_id is not null), count(distinct retailer_name)
    into v_items, v_matched, v_retailers
    from public.menu_items_raw where crawl_id = p_batch_id;

  update public.menu_crawls
     set finished_at = now(), items_found = v_items, sources_ok = 1,
         note = format('%s rows, %s retailers, %s rows matched to a Hybrid location',
                       v_items, v_retailers, v_matched)
   where id = p_batch_id;

  return jsonb_build_object('batch_id', p_batch_id, 'rows', v_items,
                            'retailers', v_retailers, 'rows_matched', v_matched);
end;
$$;

revoke all on function public.feed_batch_open(text, text) from public, anon, authenticated;
revoke all on function public.feed_batch_close(bigint)    from public, anon, authenticated;

-- p_batch_id appends to an open batch; omitted, it behaves exactly as before and opens
-- and closes one of its own.
drop function if exists public.litalerts_import(jsonb, text);

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
    public.feed_money(public.feed_pick(e, 'price', 'list_price', 'regular_price')),
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
