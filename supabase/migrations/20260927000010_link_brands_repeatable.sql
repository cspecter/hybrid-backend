-- Attaching brand pages has to be repeatable, not a one-off.
--
-- 20260927000004 created brand profiles and linked them as a migration, which worked
-- once. Every promotion since has produced products with no product_brands row and
-- therefore no cached_brand_names — the 397 Lobo products landed brandless for
-- exactly this reason. Anything that runs after each import needs to be a function.
create or replace function public.link_product_brands()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_profiles integer; v_links integer;
begin
  -- Brand pages for anything promoted since the last run. Unclaimed placeholders:
  -- auth_id null so nobody can sign in, default role, not verified.
  with wanted as (
    select mode() within group (order by p.attributes->>'brand') as brand
    from public.products p
    where p.source = 'litalerts' and p.attributes->>'brand' is not null
    group by lower(btrim(p.attributes->>'brand'))
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
  resolved as (
    -- Clean handle when it is free, hashed only when taken. The hash as default gave
    -- @ayrloome77dfe beside @rythm, and a handle is the brand's public address.
    select m.brand,
           case when length(m.clean_handle) >= 3
                 and not exists (select 1 from public.profiles x where x.username = m.clean_handle)
                then m.clean_handle else m.fallback_handle end as handle
    from missing m
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
   and lower(btrim(pr.display_name)) = lower(btrim(p.attributes->>'brand'))
  where p.source = 'litalerts'
    and p.attributes->>'brand' is not null
    and not exists (select 1 from public.product_brands pb
                     where pb.product_id = p.id and pb.brand_id = pr.id);
  get diagnostics v_links = row_count;

  return jsonb_build_object('brand_profiles_created', v_profiles, 'product_links_created', v_links,
    'feed_products_without_brand',
      (select count(*) from public.products where source='litalerts' and cached_brand_names is null));
end;
$$;

revoke all on function public.link_product_brands() from public, anon, authenticated;
