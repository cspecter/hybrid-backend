-- The promotion itself.
--
-- products.name is UNIQUE across the whole table, which is the constraint that shapes
-- this. Two growers both sell "Blue Dream 3.5g" and both are real, distinct products,
-- so the plain name cannot be the identity. The name is kept clean where it is free
-- and disambiguated with the brand only where it collides — with the existing 40,147
-- products or with a sibling in the same batch. A second collision after that takes
-- the size too, and anything still colliding is skipped rather than guessed at.
create or replace function public.promote_feed_products(
  p_limit       integer default 5000,
  p_fresh_days  integer default 14)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_created integer; v_linked integer;
begin
  create temp table _promote on commit drop as
  with fresh as (
    select r.*,
           lower(btrim(coalesce(r.brand,'') || '|' || r.name || '|' || coalesce(r.size,''))) as product_key
    from public.menu_items_raw r
    where r.provider = 'litalerts'
      and r.last_seen_at > now() - (p_fresh_days || ' days')::interval
      and coalesce(r.in_stock, true)
      and nullif(btrim(coalesce(r.name,'')), '') is not null
  ),
  grouped as (
    select product_key,
           -- mode() rather than max(): the commonest spelling across shops beats an
           -- arbitrary one, and stores punctuate the same product differently.
           mode() within group (order by name)     as name,
           mode() within group (order by brand)    as brand,
           mode() within group (order by category) as category,
           mode() within group (order by size)     as size,
           mode() within group (order by strain_type) as strain_type,
           mode() within group (order by thc)      as thc,
           mode() within group (order by cbd)      as cbd,
           percentile_cont(0.5) within group (order by price) as median_price,
           min(price) as min_price, max(price) as max_price,
           count(distinct location_id) as store_count,
           count(*) as listing_count,
           max(last_seen_at) as last_seen,
           -- Prefer an image we have already cached; fall back to the source URL.
           mode() within group (order by image_url) as image_url
    from fresh
    where product_key is not null
    group by product_key
  ),
  ranked as (
    select *, row_number() over (order by store_count desc, listing_count desc, name) as rnk
    from grouped
  )
  select * from ranked where rnk <= p_limit;

  -- Resolve a unique name: plain, then with the brand, then with brand and size.
  alter table _promote add column final_name text;
  update _promote p set final_name =
    case
      when not exists (select 1 from public.products x where lower(x.name) = lower(p.name))
       and (select count(*) from _promote q where lower(q.name) = lower(p.name)) = 1
        then p.name
      when p.brand is not null
       and not exists (select 1 from public.products x
                        where lower(x.name) = lower(p.name || ' - ' || p.brand))
        then p.name || ' - ' || p.brand
      when p.brand is not null and p.size is not null
       and not exists (select 1 from public.products x
                        where lower(x.name) = lower(p.name || ' - ' || p.brand || ' ' || p.size))
        then p.name || ' - ' || p.brand || ' ' || p.size
      else null            -- unresolvable: skipped rather than guessed
    end;

  -- Two rows in this batch can still land on the same disambiguated name; keep one.
  delete from _promote a using _promote b
   where a.final_name is not null and a.final_name = b.final_name and a.rnk > b.rnk;

  with inserted as (
    insert into public.products
      (name, slug, status, source, price, base_price, currency, category_id,
       cached_brand_names, gallery_urls, description, attributes, published_at)
    select left(p.final_name, 255),
           left(regexp_replace(lower(p.final_name), '[^a-z0-9]+', '-', 'g'), 200)
             || '-' || substr(md5(p.product_key), 1, 6),
           'published',
           'litalerts',
           p.median_price::real,
           p.median_price,
           'USD',
           (select c.id from public.product_categories c
             where lower(c.name) = lower(p.category) limit 1),
           p.brand,
           case when p.image_url is not null then array[p.image_url] else '{}'::text[] end,
           nullif(concat_ws(' · ',
             nullif(p.strain_type, ''),
             case when p.thc is not null then 'THC ' || p.thc || '%' end,
             case when p.cbd is not null then 'CBD ' || p.cbd || '%' end,
             case when p.size is not null then p.size end), ''),
           jsonb_strip_nulls(jsonb_build_object(
             'size', p.size, 'strain_type', p.strain_type, 'thc', p.thc, 'cbd', p.cbd,
             'store_count', p.store_count, 'price_min', p.min_price, 'price_max', p.max_price,
             'feed_key', p.product_key)),
           now()
    from _promote p
    where p.final_name is not null
    returning id, (attributes->>'feed_key') as product_key
  )
  select count(*) into v_created from inserted;

  -- Point every contributing listing at the product it became.
  update public.menu_items_raw r
     set product_id = pr.id
    from public.products pr
   where pr.source = 'litalerts'
     and pr.attributes->>'feed_key' =
         lower(btrim(coalesce(r.brand,'') || '|' || r.name || '|' || coalesce(r.size,'')))
     and r.provider = 'litalerts'
     and r.product_id is distinct from pr.id;
  get diagnostics v_linked = row_count;

  return jsonb_build_object(
    'products_created', v_created,
    'listings_linked', v_linked,
    'skipped_unresolvable_name', (select count(*) from _promote where final_name is null),
    'published_total', (select count(*) from public.products where status='published'));
end;
$$;

revoke all on function public.promote_feed_products(integer, integer) from public, anon, authenticated;
