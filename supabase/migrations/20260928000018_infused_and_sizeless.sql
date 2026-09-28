-- Two causes of one product holding several identities.

-- 1. "infused preroll" was a format while "infused" was also a material, so the same
--    word was counted on both axes and a shop writing "Infused Pre-Roll" landed somewhere
--    different from a shop writing "Pre-Roll" for the identical SKU. The format is
--    preroll; that it is infused is the material's job to say.
delete from public.product_terms where kind = 'format' and label = 'infused preroll';

-- 2. Sizeless products. One shop writes "Hashish Jar 1g", the next just "Hashish Jar".
--    The second has no weight to key on, so it became its own product. Where the brand,
--    format, material and strain match exactly one sized identity, the unsized listing
--    is that product with the weight left off.
--
--    Recorded as a merge rather than written back into product_norm, which stays a record
--    of what the name actually said.
--
--    This replaces the subset-merge rule, which is deleted rather than kept. That rule
--    dropped a word from a strain when the remainder was a strain the brand already sold,
--    and it was wrong: strain names are compositional, so a brand selling Lemon Cherry
--    Gelato, Cherry Gelato and Gelato makes "lemon" look exactly like a product line. It
--    merged "apple fuji" into "apple" and "haze moonshine" into "haze". No statistic over
--    names alone separates a line name from a strain word, so nothing here guesses at one.
drop function if exists public.build_identity_merges(integer);
drop table if exists public.product_brand_range_terms;

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
    group by 1,2,3,4,5,6
  ),
  unsized as (
    select * from ident where size_key = ''
  ),
  sized as (
    select * from ident where size_key <> ''
  ),
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

comment on function public.build_identity_merges() is
  'Merge a product whose name omitted its size into the one sized product it can only be. Ambiguous cases are left as they are.';

revoke all on function public.build_identity_merges() from anon, authenticated;
