-- Two brands in one batch can want the same clean handle.
--
-- link_product_brands checked a candidate handle against existing profiles but not
-- against its siblings in the same insert, so "Bliss Co" and "Bliss Co." both reduced
-- to "blissco" and the insert aborted on the unique index. The same mistake as the
-- first brand creation, in a different place: uniqueness has to be checked against
-- what is already there AND what is arriving alongside.
--
-- Now the clean handle goes to the first claimant by name order and everyone else
-- takes the hashed form, which is unique by construction.
create or replace function public.link_product_brands()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_profiles integer; v_links integer;
begin
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
