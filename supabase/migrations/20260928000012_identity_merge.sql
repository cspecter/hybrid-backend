-- Merge the identities that are the same product wearing an extra word.
--
-- After the vocabulary has taken out formats, materials, sizes, brands and noise, Lobo
-- still shows "papaya punch" beside "fuerte papaya punch", and "jackd sour" beside
-- "cannon jackd sour". Fuerte and Sauce Cannon are Lobo's names for its own pre-roll
-- lines, so those pairs are one product each.
--
-- The tempting rule -- "a token used by only one brand is that brand's range name" --
-- is wrong. Jack'd is used by one brand too, and it is a strain. What actually separates
-- them is whether dropping the token lands on a residue the brand already has: Lobo
-- sells a bare "papaya punch", so "fuerte" is removable. Lobo sells no bare "sour", so
-- "jackd" is not. The test is the merge itself, which makes it self-limiting.
--
-- One guard. A strain is grown and sold by many brands, so a token that many brands use
-- is a strain word and is never treated as a removable extra. That keeps "purple punch"
-- from swallowing "purple punch x soap", and "blue dream" from swallowing "blue dream haze".

create table if not exists public.product_token_stats (
  token   text primary key,
  brands  integer not null,   -- distinct brands whose residues use it: the strain signal
  uses    integer not null
);

comment on table public.product_token_stats is
  'How widely each strain-residue token is used. A token many brands use is a strain word; a token one brand uses may be that brand''s own range name.';

create or replace function public.refresh_product_token_stats() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  truncate product_token_stats;
  insert into product_token_stats (token, brands, uses)
  select u.t, count(distinct pn.brand_key), count(*)
  from product_norm pn,
       unnest(string_to_array(pn.strain_key, ' ')) as u(t)
  where pn.strain_key is not null and length(u.t) > 1
  group by u.t;
  get diagnostics n = row_count;
  return n;
end $$;

create table if not exists public.product_identity_merge (
  from_identity  text primary key,
  to_identity    text not null,
  dropped_tokens text[],
  min_brands     integer,       -- widest use among the dropped tokens, for auditing
  created_at     timestamptz not null default now()
);

comment on table public.product_identity_merge is
  'Identities that are the same product as another: from_identity carried extra words. Recorded rather than applied, so a merge can be reviewed and reversed.';

create index if not exists product_identity_merge_to_idx on public.product_identity_merge (to_identity);

create or replace function public.build_identity_merges(p_strain_min_brands integer default 8)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  delete from product_identity_merge;

  insert into product_identity_merge (from_identity, to_identity, dropped_tokens, min_brands)
  with ident as (
    select identity_key, brand_key, format, material,
           coalesce(grams::text, mg::text || 'mg', oz::text || 'oz', '') as size_key,
           strain_key,
           string_to_array(strain_key, ' ') as toks,
           count(*) as products
    from product_norm
    where strain_key is not null and brand_key is not null
    group by 1,2,3,4,5,6,7
  ),
  pair as (
    select b.identity_key as from_identity,
           a.identity_key as to_identity,
           array(select t from unnest(b.toks) as u(t) where not (t = any(a.toks))) as dropped,
           array_length(a.toks, 1) as parent_tokens,
           a.products as parent_products
    from ident b
    join ident a
      on  a.brand_key = b.brand_key
      and coalesce(a.format, '')   = coalesce(b.format, '')
      and coalesce(a.material, '') = coalesce(b.material, '')
      and a.size_key = b.size_key
      and a.toks <@ b.toks
      and array_length(a.toks, 1) < array_length(b.toks, 1)
  ),
  allowed as (
    select pair.*,
           (select min(coalesce(s.brands, 0))
              from unnest(pair.dropped) as u(t)
              left join product_token_stats s on s.token = u.t) as min_brands
    from pair
    where not exists (
      -- Every word being dropped must be one that few brands use. A widely used word
      -- is a strain word, and dropping it would merge two different products.
      select 1 from unnest(pair.dropped) as u(t)
      left join product_token_stats s on s.token = u.t
      where coalesce(s.brands, 0) >= p_strain_min_brands
    )
  ),
  best as (
    -- Closest parent: the one that keeps the most words, then the one with more products.
    select distinct on (from_identity)
           from_identity, to_identity, dropped, min_brands
    from allowed
    order by from_identity, parent_tokens desc, parent_products desc, to_identity
  )
  select from_identity, to_identity, dropped, min_brands from best;

  get diagnostics n = row_count;
  return n;
end $$;

-- A merge can point at an identity that merges onward. Following the chain to its root
-- is what makes the result a set of products rather than a set of pairs.
create or replace view public.v_identity_resolved as
  with recursive walk as (
    select from_identity as identity_key, to_identity, 1 as depth
      from product_identity_merge
    union all
    select w.identity_key, m.to_identity, w.depth + 1
      from walk w join product_identity_merge m on m.from_identity = w.to_identity
     where w.depth < 10
  ),
  root as (
    select distinct on (identity_key) identity_key, to_identity as canonical_key
      from walk order by identity_key, depth desc
  )
  select pn.product_id,
         pn.identity_key,
         coalesce(r.canonical_key, pn.identity_key) as canonical_key
  from product_norm pn
  left join root r on r.identity_key = pn.identity_key;

comment on view public.v_identity_resolved is
  'Every product with the identity it ends up at once merge chains are followed to their root.';

revoke all on table public.product_token_stats    from anon, authenticated;
revoke all on table public.product_identity_merge from anon, authenticated;
alter table public.product_token_stats    enable row level security;
alter table public.product_identity_merge enable row level security;
