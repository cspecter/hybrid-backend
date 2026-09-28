-- Replace the guard on the subset merge, because the first one was wrong.
--
-- The first version dropped a word when few brands used it, on the theory that a strain
-- is grown by many brands and a range name by one. Reading the merges it produced showed
-- the theory is false: plenty of strains are one brand's own genetics. It merged
-- "apple fuji" into "apple", "haze moonshine" into "haze", "j1 ready use" into
-- "ready use" and "bags midz rs11" into "bags midz". Fuji, Moonshine, J1 and RS11 are
-- strains, and those were four different products destroyed.
--
-- What actually separates a range name from a strain word is how many of the brand's OWN
-- strains it crosses. Drop "fuerte" from Lobo's names and you land on "papaya punch" and
-- on "blue dream" -- two strains Lobo already sells, so Fuerte is a line and not a strain.
-- Drop "fuji" and you land on "apple" and nothing else, so Fuji belongs to the strain.
-- Requiring two distinct landings is what makes the difference.
drop function if exists public.build_identity_merges(integer);

create table if not exists public.product_brand_range_terms (
  brand_key  text not null,
  token      text not null,
  lands_on   integer not null,   -- how many of the brand's own strains it crosses
  examples   text[],
  primary key (brand_key, token)
);

comment on table public.product_brand_range_terms is
  'Words that are a brand''s own product-line name rather than part of a strain, learned from the brand''s catalogue: removing the word lands on two or more strains the brand already sells.';

create or replace function public.refresh_brand_range_terms(p_min_lands integer default 2)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  truncate product_brand_range_terms;

  insert into product_brand_range_terms (brand_key, token, lands_on, examples)
  with res as (
    select distinct brand_key, strain_key, string_to_array(strain_key, ' ') as toks
    from product_norm
    where strain_key is not null and brand_key is not null
  ),
  -- Every residue with one of its own words taken out. strain_key is already sorted,
  -- so removing a token leaves the remainder in the same order and comparable as text.
  candidate as (
    select r.brand_key, u.t as token,
           array_to_string(array(select x from unnest(r.toks) as v(x) where x <> u.t), ' ') as rest
    from res r, unnest(r.toks) as u(t)
    where array_length(r.toks, 1) >= 2
  ),
  landed as (
    select c.brand_key, c.token, c.rest
    from candidate c
    join res r2 on r2.brand_key = c.brand_key and r2.strain_key = c.rest
    where c.rest <> ''
  )
  select brand_key, token, count(distinct rest),
         (array_agg(distinct rest))[1:4]
  from landed
  group by 1, 2
  having count(distinct rest) >= p_min_lands;

  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.build_identity_merges(p_max_token_brands integer default 40)
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
  -- Exactly one word apart. Names that differ by two words reach each other through a
  -- chain of single steps, and each step has to justify itself on its own.
  pair as (
    select b.identity_key as from_identity,
           a.identity_key as to_identity,
           (select array_agg(t) from unnest(b.toks) as u(t) where not (t = any(a.toks))) as dropped,
           a.products as parent_products
    from ident b
    join ident a
      on  a.brand_key = b.brand_key
      and coalesce(a.format, '')   = coalesce(b.format, '')
      and coalesce(a.material, '') = coalesce(b.material, '')
      and a.size_key = b.size_key
      and a.toks <@ b.toks
      and array_length(a.toks, 1) = array_length(b.toks, 1) - 1
  ),
  allowed as (
    select p.from_identity, p.to_identity, p.dropped, p.parent_products,
           coalesce(s.brands, 0) as token_brands
    from pair p
    join product_brand_range_terms rt
      on  rt.brand_key = split_part(p.to_identity, '|', 1)
      and rt.token     = p.dropped[1]
    left join product_token_stats s on s.token = p.dropped[1]
    -- Backstop: a word in very wide circulation is a strain word whatever else it looks
    -- like, so it is never dropped.
    where coalesce(s.brands, 0) < p_max_token_brands
  ),
  best as (
    select distinct on (from_identity)
           from_identity, to_identity, dropped, token_brands
    from allowed
    order by from_identity, parent_products desc, to_identity
  )
  select from_identity, to_identity, dropped, token_brands from best;

  get diagnostics n = row_count;
  return n;
end $$;

revoke all on table public.product_brand_range_terms from anon, authenticated;
alter table public.product_brand_range_terms enable row level security;
revoke all on function public.refresh_brand_range_terms(integer) from anon, authenticated;
revoke all on function public.build_identity_merges(integer)     from anon, authenticated;
