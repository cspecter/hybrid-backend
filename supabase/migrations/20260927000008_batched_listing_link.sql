-- Link listings to products in batches, and stop doing it inside the promotion.
--
-- Even with feed_key stored and indexed on both sides, the link is a single UPDATE
-- touching every unlinked listing — roughly 693,000 rows — and no amount of indexing
-- makes that fit inside a statement timeout. Indexing was still worth doing; it was
-- just never the whole problem.
--
-- Two changes. The update takes a batch size and returns how many it touched, so the
-- caller loops until it returns zero and each pass gets a fresh timeout window. And
-- promotion no longer links at all: creating products is fast and linking is slow, so
-- tying them together meant a timeout in the slow half rolled back the fast half.
create index if not exists menu_items_raw_unlinked_idx
  on public.menu_items_raw (feed_key) where product_id is null and provider = 'litalerts';

create or replace function public.link_listings_to_products(p_batch integer default 50000)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  with todo as (
    select r.id, pr.id as product_id
    from public.menu_items_raw r
    join public.products pr
      on pr.source = 'litalerts'
     and pr.attributes->>'feed_key' = r.feed_key
    where r.provider = 'litalerts' and r.product_id is null
    limit p_batch
  )
  update public.menu_items_raw m
     set product_id = t.product_id
    from todo t where m.id = t.id;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Promotion creates products and stops. Linking is the caller's job now.
create or replace function public.promote_brand_guarantees(
  p_min_brand_stores integer default 20, p_per_brand integer default 10, p_fresh_days integer default 14)
returns jsonb language plpgsql volatile security definer set search_path = public as $fn$
declare v_created integer; v_brands integer;
begin
  create temp table _guar on commit drop as
  with fresh as (
    select r.*, lower(btrim(coalesce(r.brand,''))) as brand_key
    from public.menu_items_raw r
    where r.provider='litalerts' and r.last_seen_at > now() - (p_fresh_days||' days')::interval
      and coalesce(r.in_stock,true) and nullif(btrim(coalesce(r.name,'')),'') is not null
      and nullif(btrim(coalesce(r.brand,'')),'') is not null
  ),
  big_brands as (select brand_key from fresh group by brand_key
                  having count(distinct location_id) >= p_min_brand_stores),
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
    from fresh f join big_brands b on b.brand_key=f.brand_key
    group by f.feed_key, f.brand_key
  ),
  ranked as (select *, row_number() over (partition by brand_key
               order by store_count desc, listing_count desc, name) as rnk_in_brand from grouped)
  select * from ranked where rnk_in_brand <= p_per_brand
    and not exists (select 1 from public.products x
                     where x.source='litalerts' and x.attributes->>'feed_key'=ranked.product_key);

  select count(distinct brand_key) into v_brands from _guar;
  alter table _guar add column final_name text;
  update _guar g set final_name = case
      when not exists (select 1 from public.products x where lower(x.name)=lower(g.name))
       and (select count(*) from _guar q where lower(q.name)=lower(g.name))=1 then g.name
      when not exists (select 1 from public.products x where lower(x.name)=lower(g.name||' - '||g.brand))
        then g.name||' - '||g.brand
      when g.size is not null and not exists (select 1 from public.products x
             where lower(x.name)=lower(g.name||' - '||g.brand||' '||g.size))
        then g.name||' - '||g.brand||' '||g.size
      else null end;
  delete from _guar a using _guar b where a.final_name is not null and a.final_name=b.final_name
    and (a.store_count,a.product_key) < (b.store_count,b.product_key);

  with inserted as (
    insert into public.products (name, slug, status, source, price, base_price, currency,
      category_id, gallery_urls, description, attributes, published_at)
    select left(g.final_name,255),
           left(regexp_replace(lower(g.final_name),'[^a-z0-9]+','-','g'),200)||'-'||substr(md5(g.product_key),1,6),
           'published','litalerts', g.median_price::real, g.median_price,'USD',
           (select c.id from public.product_categories c where lower(c.name)=lower(g.category) limit 1),
           case when g.image_url is not null then array[g.image_url] else '{}'::text[] end,
           nullif(concat_ws(' · ', g.brand, nullif(g.strain_type,''),
             case when g.thc is not null then 'THC '||g.thc||'%' end,
             case when g.cbd is not null then 'CBD '||g.cbd||'%' end, g.size),''),
           jsonb_strip_nulls(jsonb_build_object('brand',g.brand,'size',g.size,
             'strain_type',g.strain_type,'thc',g.thc,'cbd',g.cbd,'store_count',g.store_count,
             'price_min',g.min_price,'price_max',g.max_price,'feed_key',g.product_key,
             'promoted_by','brand-guarantee')),
           now()
    from _guar g where g.final_name is not null returning id)
  select count(*) into v_created from inserted;

  return jsonb_build_object('brands_covered',v_brands,'products_created',v_created,
    'skipped_unresolvable_name',(select count(*) from _guar where final_name is null),
    'published_total',(select count(*) from public.products where status='published'));
end $fn$;

revoke all on function public.link_listings_to_products(integer) from public, anon, authenticated;
revoke all on function public.promote_brand_guarantees(integer, integer, integer) from public, anon, authenticated;
drop function if exists public.link_listings_to_products();
