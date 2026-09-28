-- The one-mistyped-word rule is removed. It merged 180 identities and most of that was
-- damage.
--
-- An edit distance of one does catch typos -- "cresendo" for Crescendo, "surple" for
-- Purple, "sereal" for Cereal -- but it catches far more that is not a typo:
--
--   710labs "Hot Lixz #16 Persy" into "#14 Persy", Dabwoods "Runtz #32" into "#30".
--   A phenotype number is one edit from another phenotype number, and those are the
--   separate releases that preserving "#N" existed to protect in the first place.
--
--   Wana "1:1 Quick" into "10:1 Quick". A ratio is one edit from another ratio, and
--   that is the whole identity of a tincture.
--
--   Cannabiotix and Rythm "L'Orange" into "Orange". Raw Garden "Lemon Cream Cake" into
--   "Lemon Dream Cake".
--
-- Excluding numeric tokens would fix the first two and leave the third, and the third is
-- the same failure as the two merge rules already deleted: no measure over names alone
-- decides whether two spellings are one strain. Names are not the place to settle it.
-- A brand's own product list is, and that is a different mechanism.
create or replace function public.build_identity_merges(p_price_tolerance numeric default 0.15)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  delete from product_identity_merge;

  -- 1. A name that omits its size joins the sized product it can only be. Ambiguous cases
  --    are left alone: Lobo's pre-ground Sativa Blend comes in 7g, 14g and 28g.
  insert into product_identity_merge (from_identity, to_identity, reason)
  select u.identity_key, min(s.identity_key), 'size omitted'
  from v_identity_group u
  join v_identity_group s
    on  s.brand_key = u.brand_key
    and coalesce(s.format, '')   = coalesce(u.format, '')
    and coalesce(s.material, '') = coalesce(u.material, '')
    and coalesce(s.grow, '')     = coalesce(u.grow, '')
    and s.strain_key = u.strain_key
    and s.size_key <> '' and u.size_key = ''
  group by u.identity_key
  having count(*) = 1
  on conflict (from_identity) do nothing;

  -- 2. A name that does not say what the product is made of joins the one that does, when
  --    the material is intrinsic. Hashish, badder and diamonds describe what the thing IS,
  --    so "Permanent Marker 1g" and "1g Hashish Permanent Marker" are one jar. "infused"
  --    and "preground" are excluded here: those describe something done to flower, and a
  --    brand can sell the plain version alongside. Rule 3 handles them, on evidence.
  insert into product_identity_merge (from_identity, to_identity, reason)
  select u.identity_key, min(s.identity_key), 'material unstated'
  from v_identity_group u
  join v_identity_group s
    on  s.brand_key = u.brand_key
    and coalesce(s.format, '') = coalesce(u.format, '')
    and coalesce(s.grow, '')   = coalesce(u.grow, '')
    and s.strain_key = u.strain_key
    and s.size_key   = u.size_key
    and u.material is null
    and s.material is not null
    and s.material not in ('infused', 'preground')
  group by u.identity_key
  having count(*) = 1
  on conflict (from_identity) do nothing;

  -- 3. Whether the name mentions the infusion, when the price says it is the same product.
  --    A brand often sells both: STIIIZY's "40s Preroll" is $10 and its "40's Infused
  --    Pre-Roll" is $20, and those are two products. Lobo's "Blue Dream 1g Bold Blunt" is
  --    $17 and its "Blue Dream Sauce & Hash Infused Blunt" is $15.26, which is one product
  --    described twice. Price is what tells them apart, so price is what decides.
  insert into product_identity_merge (from_identity, to_identity, reason)
  select distinct on (u.identity_key) u.identity_key, s.identity_key, 'infusion unstated, price agrees'
  from v_identity_group u
  join v_identity_group s
    on  s.brand_key = u.brand_key
    and coalesce(s.format, '') = coalesce(u.format, '')
    and coalesce(s.grow, '')   = coalesce(u.grow, '')
    and s.strain_key = u.strain_key
    and s.size_key   = u.size_key
    and u.material is null
    and s.material in ('infused', 'preground')
  where u.price is not null and s.price is not null
    and greatest(u.price, s.price) > 0
    and abs(u.price - s.price) / greatest(u.price, s.price) <= p_price_tolerance
  order by u.identity_key, abs(u.price - s.price), s.products desc, s.identity_key
  on conflict (from_identity) do nothing;

  select count(*) into n from product_identity_merge;
  return n;
end $$;

revoke all on function public.build_identity_merges(numeric) from anon, authenticated;
