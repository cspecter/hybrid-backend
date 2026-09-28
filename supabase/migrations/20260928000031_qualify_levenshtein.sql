-- levenshtein lives in the extensions schema and build_identity_merges pins its
-- search_path to public, so the call has to name the schema.
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

  -- 4. One mistyped word. "Permanent Marker" arrives as "Maker", "Jack'd" as "Jockd",
  --    "Zkittlez" as "Zklittlez". The test is deliberately narrow: the same number of
  --    words, exactly one word different on each side, and those two words one edit apart.
  --    Trigram similarity was tried and cannot do this -- "blue diesel" against "blueberry
  --    diesel" scores 0.61 while "jackd sour" against "jockd sour" scores 0.57, so no
  --    threshold separates a typo from a different strain. An edit distance of one does:
  --    blue to blueberry is five edits.
  --
  --    The better-attested spelling wins, and the comparison is strictly ordered so the
  --    edges cannot form a cycle.
  insert into product_identity_merge (from_identity, to_identity, reason)
  select distinct on (a.identity_key) a.identity_key, b.identity_key, 'one mistyped word'
  from v_identity_group a
  join v_identity_group b
    on  b.brand_key = a.brand_key
    and coalesce(b.format, '')   = coalesce(a.format, '')
    and coalesce(b.material, '') = coalesce(a.material, '')
    and coalesce(b.grow, '')     = coalesce(a.grow, '')
    and b.size_key = a.size_key
    and array_length(b.toks, 1) = array_length(a.toks, 1)
    and (b.products, b.identity_key) > (a.products, a.identity_key)
  cross join lateral (
    select array(select t from unnest(a.toks) as x(t) where not (t = any(b.toks))) as a_only,
           array(select t from unnest(b.toks) as y(t) where not (t = any(a.toks))) as b_only
  ) d
  where array_length(d.a_only, 1) = 1
    and array_length(d.b_only, 1) = 1
    and length(d.a_only[1]) >= 4
    and length(d.b_only[1]) >= 4
    and extensions.levenshtein(d.a_only[1], d.b_only[1]) = 1
  order by a.identity_key, b.products desc, b.identity_key
  on conflict (from_identity) do nothing;

  select count(*) into n from product_identity_merge;
  return n;
end $$;

revoke all on function public.build_identity_merges(numeric) from anon, authenticated;
