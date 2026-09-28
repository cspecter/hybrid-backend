-- One rule for an incompletely written name, replacing three that each handled one axis.
--
-- The three previous rules -- size omitted, material unstated, infusion unstated where the
-- price agrees -- each required every other axis to match exactly. A listing that left out
-- two things could therefore never reach its sibling, and that is common:
--
--   1906's "*BLISS - 10 MG - 2 PACK" states a dose and a count and no format at all, while
--   "Bliss Drops [2pk Pouch] (10mg THC/10mg CBD)" states the format too. Three identities
--   for one box of drops.
--
--   Rythm's "Afternoon Delight #4 Live Resin Disposable" states format and material but no
--   size; the disposable that states a size does not state the material.
--
-- The general form: a listing joins another when everything it does say agrees, the other
-- says strictly more, and there is exactly one such candidate at the nearest level of
-- detail. Ambiguity is left alone, which is what protects a brand selling the same strain
-- indoor and sungrown -- an unstated grow method has two candidates and merges into neither.
--
-- One exception keeps its own evidence. "Infused" and "preground" are not omissions, they
-- are descriptions a brand may or may not apply, and STIIIZY sells a "40s Preroll" at $10
-- beside a "40's Infused Pre-Roll" at $20. Where the only thing gained is one of those two
-- words, the prices still have to agree.
create or replace function public.build_identity_merges(p_price_tolerance numeric default 0.15)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  delete from product_identity_merge;

  insert into product_identity_merge (from_identity, to_identity, reason)
  with ig as (
    select pn.identity_key, pn.brand_key, pn.strain_key,
           pn.format, pn.material, pn.grow, pn.grams, pn.mg, pn.ml, pn.oz, pn.pack,
             (pn.format   is not null)::int + (pn.material is not null)::int
           + (pn.grow     is not null)::int + (pn.grams    is not null)::int
           + (pn.mg       is not null)::int + (pn.ml       is not null)::int
           + (pn.oz       is not null)::int + (pn.pack     is not null)::int as stated,
           count(*) as products,
           avg(coalesce(p.price, p.base_price)) as price
    from product_norm pn
    join products p on p.id = pn.product_id
    where pn.brand_key is not null and pn.strain_key is not null and not pn.strain_from_name
    group by pn.identity_key, pn.brand_key, pn.strain_key,
             pn.format, pn.material, pn.grow, pn.grams, pn.mg, pn.ml, pn.oz, pn.pack
  ),
  pair as (
    select a.identity_key as from_identity, b.identity_key as to_identity,
           b.stated, b.products,
           -- The only thing gained is a word a brand may simply not have used.
           (a.material is null and b.material in ('infused','preground')
            and a.format = b.format and coalesce(a.grow,'') = coalesce(b.grow,'')
            and coalesce(a.grams,-1) = coalesce(b.grams,-1)
            and coalesce(a.mg,-1) = coalesce(b.mg,-1)
            and coalesce(a.pack,-1) = coalesce(b.pack,-1)) as descriptor_only,
           a.price as a_price, b.price as b_price
    from ig a
    join ig b
      on  b.brand_key  = a.brand_key
      and b.strain_key = a.strain_key
      and b.stated     > a.stated
      and (a.format   is null or a.format   = b.format)
      and (a.material is null or a.material = b.material)
      and (a.grow     is null or a.grow     = b.grow)
      and (a.grams    is null or a.grams    = b.grams)
      and (a.mg       is null or a.mg       = b.mg)
      and (a.ml       is null or a.ml       = b.ml)
      and (a.oz       is null or a.oz       = b.oz)
      and (a.pack     is null or a.pack     = b.pack)
  ),
  allowed as (
    select * from pair
    where not descriptor_only
       or (a_price is not null and b_price is not null
           and greatest(a_price, b_price) > 0
           and abs(a_price - b_price) / greatest(a_price, b_price) <= p_price_tolerance)
  ),
  -- The nearest level of detail, and only if nothing else sits at that level.
  nearest as (
    select from_identity, min(stated) as stated from allowed group by from_identity
  ),
  unique_parent as (
    select a.from_identity, min(a.to_identity) as to_identity, count(*) as options
    from allowed a
    join nearest nr on nr.from_identity = a.from_identity and nr.stated = a.stated
    group by a.from_identity
  )
  select from_identity, to_identity, 'name says less, one candidate says more'
  from unique_parent where options = 1;

  select count(*) into n from product_identity_merge;
  return n;
end $$;

comment on function public.build_identity_merges(numeric) is
  'Join an incompletely written name to the one listing that says more and contradicts nothing. Ambiguity is left alone. Gaining only "infused" or "preground" additionally requires the prices to agree.';

revoke all on function public.build_identity_merges(numeric) from anon, authenticated;
