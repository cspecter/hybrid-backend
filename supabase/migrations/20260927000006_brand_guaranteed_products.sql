-- Guarantee every significant brand a presence in the catalogue.
--
-- The first promotion ranked products purely by how many shops carry them, took the
-- top 5,000, and the cutoff landed at 4 stores. That systematically favours brands
-- with a few widely-stocked hero SKUs and buries brands with deep catalogues, because
-- a wide range spreads its listings thin across many products.
--
-- Lobo is the proof: 728 fresh listings across 96 stores, 96% in stock, and not one
-- product in the app. Its best SKU sits on 3 shops against a cutoff of 4. By any
-- reading Lobo is a significant New York brand; by the ranking it did not exist.
--
-- So brands on 20 or more shops — 642 of them — are guaranteed their ten best
-- products. The store-coverage ranking still fills the rest; this only ensures the
-- catalogue looks like the market rather than like a distribution table.
--
-- ADDITIVE, not a rebuild. I had said this would replace the existing 4,609, but
-- deleting them buys nothing and costs something: products cascade to posts_products,
-- posts and stash on delete, and those 4,609 are already live and correct. The
-- guarantees are simply added where they are missing.
create or replace function public.promote_brand_guarantees(
  p_min_brand_stores integer default 20,
  p_per_brand        integer default 10,
  p_fresh_days       integer default 14)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_created integer; v_linked integer; v_brands integer;
begin
  create temp table _guar on commit drop as
  with fresh as (
    select r.*, lower(btrim(coalesce(r.brand,''))) as brand_key,
           lower(btrim(coalesce(r.brand,'') || '|' || r.name || '|' || coalesce(r.size,''))) as product_key
    from public.menu_items_raw r
    where r.provider = 'litalerts'
      and r.last_seen_at > now() - (p_fresh_days || ' days')::interval
      and coalesce(r.in_stock, true)
      and nullif(btrim(coalesce(r.name,'')), '') is not null
      and nullif(btrim(coalesce(r.brand,'')), '') is not null
  ),
  big_brands as (
    select brand_key from fresh group by brand_key
    having count(distinct location_id) >= p_min_brand_stores
  ),
  grouped as (
    select f.product_key, f.brand_key,
           mode() within group (order by f.name)     as name,
           mode() within group (order by f.brand)    as brand,
           mode() within group (order by f.category) as category,
           mode() within group (order by f.size)     as size,
           mode() within group (order by f.strain_type) as strain_type,
           mode() within group (order by f.thc)      as thc,
           mode() within group (order by f.cbd)      as cbd,
           percentile_cont(0.5) within group (order by f.price) as median_price,
           min(f.price) as min_price, max(f.price) as max_price,
           count(distinct f.location_id) as store_count,
           count(*) as listing_count,
           mode() within group (order by f.image_url) as image_url
    from fresh f join big_brands b on b.brand_key = f.brand_key
    group by f.product_key, f.brand_key
  ),
  ranked as (
    select *, row_number() over (partition by brand_key
                                 order by store_count desc, listing_count desc, name) as rnk_in_brand
    from grouped
  )
  select * from ranked
   where rnk_in_brand <= p_per_brand
     -- Already promoted by the coverage pass; nothing to do.
     and not exists (select 1 from public.products x
                      where x.source='litalerts' and x.attributes->>'feed_key' = ranked.product_key);

  select count(distinct brand_key) into v_brands from _guar;

  -- Same unique-name resolution as the coverage pass: products.name is UNIQUE
  -- table-wide, so plain where free, then brand, then brand and size, then skip.
  alter table _guar add column final_name text;
  update _guar g set final_name =
    case
      when not exists (select 1 from public.products x where lower(x.name) = lower(g.name))
       and (select count(*) from _guar q where lower(q.name) = lower(g.name)) = 1
        then g.name
      when not exists (select 1 from public.products x
                        where lower(x.name) = lower(g.name || ' - ' || g.brand))
        then g.name || ' - ' || g.brand
      when g.size is not null
       and not exists (select 1 from public.products x
                        where lower(x.name) = lower(g.name || ' - ' || g.brand || ' ' || g.size))
        then g.name || ' - ' || g.brand || ' ' || g.size
      else null
    end;
  delete from _guar a using _guar b
   where a.final_name is not null and a.final_name = b.final_name
     and (a.store_count, a.product_key) < (b.store_count, b.product_key);

  with inserted as (
    insert into public.products
      (name, slug, status, source, price, base_price, currency, category_id,
       gallery_urls, description, attributes, published_at)
    select left(g.final_name, 255),
           left(regexp_replace(lower(g.final_name), '[^a-z0-9]+', '-', 'g'), 200)
             || '-' || substr(md5(g.product_key), 1, 6),
           'published', 'litalerts',
           g.median_price::real, g.median_price, 'USD',
           (select c.id from public.product_categories c where lower(c.name) = lower(g.category) limit 1),
           case when g.image_url is not null then array[g.image_url] else '{}'::text[] end,
           nullif(concat_ws(' · ', g.brand, nullif(g.strain_type,''),
             case when g.thc is not null then 'THC ' || g.thc || '%' end,
             case when g.cbd is not null then 'CBD ' || g.cbd || '%' end,
             g.size), ''),
           jsonb_strip_nulls(jsonb_build_object(
             'brand', g.brand, 'size', g.size, 'strain_type', g.strain_type,
             'thc', g.thc, 'cbd', g.cbd, 'store_count', g.store_count,
             'price_min', g.min_price, 'price_max', g.max_price,
             'feed_key', g.product_key, 'promoted_by', 'brand-guarantee')),
           now()
    from _guar g where g.final_name is not null
    returning id
  )
  select count(*) into v_created from inserted;

  -- Delegated: the join runs off the generated feed_key column and its index rather
  -- than recomputing the key on 748,909 rows, which is what timed this out.
  v_linked := public.link_listings_to_products();

  return jsonb_build_object('brands_covered', v_brands, 'products_created', v_created,
    'listings_linked', v_linked,
    'skipped_unresolvable_name', (select count(*) from _guar where final_name is null),
    'published_total', (select count(*) from public.products where status='published'));
end;
$$;

revoke all on function public.promote_brand_guarantees(integer, integer, integer) from public, anon, authenticated;
