-- The grouping list reached position 6, which is the size_key expression, and that
-- expression is built from aggregates. identity_key already determines the size, so
-- the group is the first five columns and the size comes out of the aggregate.
create or replace function public.build_identity_merges() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  delete from product_identity_merge;

  insert into product_identity_merge (from_identity, to_identity, dropped_tokens, min_brands)
  with ident as (
    select identity_key, brand_key, format, material, strain_key,
           norm_size_key(min(grams), min(mg), min(ml), min(oz), min(pack)) as size_key,
           count(*) as products
    from product_norm
    where strain_key is not null and brand_key is not null and not strain_from_name
    group by identity_key, brand_key, format, material, strain_key
  ),
  unsized as (select * from ident where size_key = ''),
  sized   as (select * from ident where size_key <> ''),
  -- Only when the sized match is unambiguous. Lobo's pre-ground Sativa Blend comes in
  -- 7g, 14g and 28g, so a listing that omits the weight cannot be assigned to one of
  -- them and is left alone.
  candidate as (
    select u.identity_key as from_identity,
           min(s.identity_key) as to_identity,
           count(*) as options
    from unsized u
    join sized s
      on  s.brand_key  = u.brand_key
      and coalesce(s.format, '')   = coalesce(u.format, '')
      and coalesce(s.material, '') = coalesce(u.material, '')
      and s.strain_key = u.strain_key
    group by u.identity_key
  )
  select from_identity, to_identity, null, null
  from candidate where options = 1;

  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.build_identity_merges() from anon, authenticated;
