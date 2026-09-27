-- Brands that get their whole range in the app, not just their best few.
--
-- The catalogue is built by ranking, which is right for 5,000 brands and wrong for
-- the handful you have a commercial relationship with. Lobo is the first: 402 fresh
-- products across 93 shops, of which the guarantee rule admitted five. If you are
-- running a Lobo deal, five products is not a catalogue.
--
-- A table rather than a hardcoded brand, because there will be a second one. Adding a
-- row and re-running is the whole workflow.
create table if not exists public.featured_brands (
  brand_key  text primary key,          -- lowercased, trimmed; matches the feed's brand
  label      text,                      -- how to write it when a human reads it
  note       text,
  added_at   timestamptz not null default now()
);

comment on table public.featured_brands is
  'Brands whose entire fresh range is promoted, bypassing the store-coverage ranking. Commercial relationships, not data quality.';

revoke all on table public.featured_brands from anon, authenticated;
alter table public.featured_brands enable row level security;

insert into public.featured_brands (brand_key, label, note)
values ('lobo', 'Lobo', 'Commercial partner — full range in the app.')
on conflict (brand_key) do nothing;

-- Promote every fresh product for every featured brand. Same freshness test as the
-- other promotions, same unique-name resolution, and it skips anything already there,
-- so re-running after a new import only adds what is new.
create or replace function public.promote_featured_brands(p_fresh_days integer default 14)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_created integer; v_brands integer;
begin
  create temp table _feat on commit drop as
  with fresh as (
    select r.*, lower(btrim(coalesce(r.brand,''))) as brand_key
    from public.menu_items_raw r
    where r.provider = 'litalerts'
      and r.last_seen_at > now() - (p_fresh_days || ' days')::interval
      and coalesce(r.in_stock, true)
      and nullif(btrim(coalesce(r.name,'')), '') is not null
      and nullif(btrim(coalesce(r.brand,'')), '') is not null
  ),
  grouped as (
    select f.feed_key as product_key, f.brand_key,
           mode() within group (order by f.name) as name,
           mode() within group (order by f.brand) as brand,
           mode() within group (order by f.category) as category,
           mode() within group (order by f.size) as size,
           mode() within group (order by f.strain_type) as strain_type,
           mode() within group (order by f.thc) as thc,
           mode() within group (order by f.cbd) as cbd,
           percentile_cont(0.5) within group (order by f.price) as median_price,
           min(f.price) as min_price, max(f.price) as max_price,
           count(distinct f.location_id) as store_count, count(*) as listing_count,
           mode() within group (order by f.image_url) as image_url
    from fresh f
    join public.featured_brands fb on fb.brand_key = f.brand_key
    group by f.feed_key, f.brand_key
  )
  select * from grouped g
   where not exists (select 1 from public.products x
                      where x.source = 'litalerts' and x.attributes->>'feed_key' = g.product_key);

  select count(distinct brand_key) into v_brands from _feat;

  alter table _feat add column final_name text;
  update _feat g set final_name = case
      when not exists (select 1 from public.products x where lower(x.name) = lower(g.name))
       and (select count(*) from _feat q where lower(q.name) = lower(g.name)) = 1 then g.name
      when not exists (select 1 from public.products x where lower(x.name) = lower(g.name||' - '||g.brand))
        then g.name || ' - ' || g.brand
      when g.size is not null and not exists (select 1 from public.products x
             where lower(x.name) = lower(g.name||' - '||g.brand||' '||g.size))
        then g.name || ' - ' || g.brand || ' ' || g.size
      else null end;
  delete from _feat a using _feat b
   where a.final_name is not null and a.final_name = b.final_name
     and (a.store_count, a.product_key) < (b.store_count, b.product_key);

  with inserted as (
    insert into public.products (name, slug, status, source, price, base_price, currency,
      category_id, gallery_urls, description, attributes, published_at)
    select left(g.final_name, 255),
           left(regexp_replace(lower(g.final_name),'[^a-z0-9]+','-','g'),200)||'-'||substr(md5(g.product_key),1,6),
           'published', 'litalerts', g.median_price::real, g.median_price, 'USD',
           (select c.id from public.product_categories c where lower(c.name)=lower(g.category) limit 1),
           case when g.image_url is not null then array[g.image_url] else '{}'::text[] end,
           nullif(concat_ws(' · ', g.brand, nullif(g.strain_type,''),
             case when g.thc is not null then 'THC '||g.thc||'%' end,
             case when g.cbd is not null then 'CBD '||g.cbd||'%' end, g.size), ''),
           jsonb_strip_nulls(jsonb_build_object('brand',g.brand,'size',g.size,
             'strain_type',g.strain_type,'thc',g.thc,'cbd',g.cbd,'store_count',g.store_count,
             'price_min',g.min_price,'price_max',g.max_price,'feed_key',g.product_key,
             'promoted_by','featured-brand')),
           now()
    from _feat g where g.final_name is not null returning id)
  select count(*) into v_created from inserted;

  return jsonb_build_object('brands', v_brands, 'products_created', v_created,
    'skipped_unresolvable_name', (select count(*) from _feat where final_name is null),
    'published_total', (select count(*) from public.products where status='published'));
end;
$$;

revoke all on function public.promote_featured_brands(integer) from public, anon, authenticated;
