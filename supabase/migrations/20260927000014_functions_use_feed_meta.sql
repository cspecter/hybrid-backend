-- Point the promotion functions at feed_meta.
--
-- Moving the import bookkeeping off products.attributes saved 1.2 MB on every app
-- load and broke five functions silently, which is the dangerous half. Each of them
-- decides "have I promoted this already?" by reading attributes->>'feed_key'; with
-- the key gone that test answers no for everything, and the next promotion would
-- have inserted 7,221 duplicate products rather than erroring.
--
-- Reproduced from the live definitions and patched, not retyped. Two changes each:
-- reads come from feed_meta, and the insert splits what used to be one blob into a
-- slim attributes for the client and feed_meta for us.
--
-- Fixed while here: attributes stored "strain_type" while the app reads
-- attributes.strain, so the strain never displayed on a single promoted product. It
-- is written as "strain" now.

CREATE OR REPLACE FUNCTION public.link_listings_to_products(p_batch integer DEFAULT 50000)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n integer;
begin
  with todo as (
    select r.id, pr.id as product_id
    from public.menu_items_raw r
    join public.products pr
      on pr.source = 'litalerts'
     and pr.feed_meta ->> 'feed_key' = r.feed_key
    where r.provider = 'litalerts' and r.product_id is null
    limit p_batch
  )
  update public.menu_items_raw m
     set product_id = t.product_id
    from todo t where m.id = t.id;
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION public.link_product_brands()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_profiles integer; v_links integer;
begin
  with wanted as (
    select mode() within group (order by p.feed_meta ->> 'brand') as brand
    from public.products p
    where p.source = 'litalerts' and p.feed_meta ->> 'brand' is not null
    group by lower(btrim(p.feed_meta ->> 'brand'))
  ),
  missing as (
    select w.brand,
           left(regexp_replace(lower(w.brand), '[^a-z0-9]+', '', 'g'), 22)
             || substr(md5(lower(btrim(w.brand))), 1, 6) as fallback_handle,
           left(regexp_replace(lower(w.brand), '[^a-z0-9]+', '', 'g'), 28) as clean_handle
    from wanted w
    where not exists (select 1 from public.profiles pr
                       where pr.profile_type = 'brand'
                         and lower(btrim(pr.display_name)) = lower(btrim(w.brand)))
  ),
  ranked as (
    select m.*,
           row_number() over (partition by m.clean_handle order by m.brand) as rn
    from missing m
  ),
  resolved as (
    select r.brand,
           case when r.rn = 1
                 and length(r.clean_handle) >= 3
                 and not exists (select 1 from public.profiles x where x.username = r.clean_handle)
                then r.clean_handle
                else r.fallback_handle end as handle
    from ranked r
  )
  insert into public.profiles (display_name, username, profile_type, status, is_verified, bio)
  select r.brand, r.handle, 'brand', 'active', false,
         'Brand page created automatically from dispensary menu data. Unclaimed.'
  from resolved r
  where nullif(btrim(r.handle), '') is not null
    and not exists (select 1 from public.profiles x where x.username = r.handle);
  get diagnostics v_profiles = row_count;

  insert into public.product_brands (product_id, brand_id, is_primary)
  select p.id, pr.id, true
  from public.products p
  join public.profiles pr
    on pr.profile_type = 'brand'
   and lower(btrim(pr.display_name)) = lower(btrim(p.feed_meta ->> 'brand'))
  where p.source = 'litalerts'
    and p.feed_meta ->> 'brand' is not null
    and not exists (select 1 from public.product_brands pb
                     where pb.product_id = p.id and pb.brand_id = pr.id);
  get diagnostics v_links = row_count;

  return jsonb_build_object('brand_profiles_created', v_profiles, 'product_links_created', v_links,
    'feed_products_without_brand',
      (select count(*) from public.products where source='litalerts' and cached_brand_names is null));
end;
$function$;

CREATE OR REPLACE FUNCTION public.promote_brand_guarantees(p_min_brand_stores integer DEFAULT 20, p_per_brand integer DEFAULT 10, p_fresh_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
                     where x.source='litalerts' and x.feed_meta ->> 'feed_key'=ranked.product_key);

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
      category_id, gallery_urls, description, attributes, feed_meta, published_at)
    select left(g.final_name,255),
           left(regexp_replace(lower(g.final_name),'[^a-z0-9]+','-','g'),200)||'-'||substr(md5(g.product_key),1,6),
           'published','litalerts', g.median_price::real, g.median_price,'USD',
           (select c.id from public.product_categories c where lower(c.name)=lower(g.category) limit 1),
           case when g.image_url is not null then array[g.image_url] else '{}'::text[] end,
           nullif(concat_ws(' · ', g.brand, nullif(g.strain_type,''),
             case when g.thc is not null then 'THC '||g.thc||'%' end,
             case when g.cbd is not null then 'CBD '||g.cbd||'%' end, g.size),''),
           jsonb_strip_nulls(jsonb_build_object('thc', g.thc, 'strain', g.strain_type, 'weight', g.size)),
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
end $function$;

CREATE OR REPLACE FUNCTION public.promote_featured_brands(p_fresh_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
                      where x.source = 'litalerts' and x.feed_meta ->> 'feed_key' = g.product_key);

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
      category_id, gallery_urls, description, attributes, feed_meta, published_at)
    select left(g.final_name, 255),
           left(regexp_replace(lower(g.final_name),'[^a-z0-9]+','-','g'),200)||'-'||substr(md5(g.product_key),1,6),
           'published', 'litalerts', g.median_price::real, g.median_price, 'USD',
           (select c.id from public.product_categories c where lower(c.name)=lower(g.category) limit 1),
           case when g.image_url is not null then array[g.image_url] else '{}'::text[] end,
           nullif(concat_ws(' · ', g.brand, nullif(g.strain_type,''),
             case when g.thc is not null then 'THC '||g.thc||'%' end,
             case when g.cbd is not null then 'CBD '||g.cbd||'%' end, g.size), ''),
           jsonb_strip_nulls(jsonb_build_object('thc', g.thc, 'strain', g.strain_type, 'weight', g.size)),
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
$function$;

CREATE OR REPLACE FUNCTION public.promote_feed_products(p_limit integer DEFAULT 5000, p_fresh_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
       cached_brand_names, gallery_urls, description, attributes, feed_meta, published_at)
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
           jsonb_strip_nulls(jsonb_build_object('thc', p.thc, 'strain', p.strain_type, 'weight', p.size)),
           jsonb_strip_nulls(jsonb_build_object(
             'size', p.size, 'strain_type', p.strain_type, 'thc', p.thc, 'cbd', p.cbd,
             'store_count', p.store_count, 'price_min', p.min_price, 'price_max', p.max_price,
             'feed_key', p.product_key)),
           now()
    from _promote p
    where p.final_name is not null
    returning id, (feed_meta ->> 'feed_key') as product_key
  )
  select count(*) into v_created from inserted;

  -- Point every contributing listing at the product it became.
  update public.menu_items_raw r
     set product_id = pr.id
    from public.products pr
   where pr.source = 'litalerts'
     and pr.feed_meta ->> 'feed_key' =
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
$function$;
