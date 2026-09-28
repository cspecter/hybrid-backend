-- Two additions: other names a brand's SKU goes by, and matching that respects state.
--
-- Lobo's Sauce Cannon reaches menus as "Jack'd Sour D", "Jack'd Sour D x Jelly Donut",
-- "Sour D x Jelly Donutz" and "Jack'd Sour D | Donut Hole" -- one SKU, eight identities.
-- No rule over names gets there: Jelly Donut is a strain name in its own right, and three
-- separate attempts to infer this class of thing were deleted for destroying products. What
-- settles it is the brand saying so, which is what an alias is.
create table if not exists public.brand_catalogue_alias (
  id           serial primary key,
  catalogue_id integer not null references public.brand_catalogue(id) on delete cascade,
  alias_text   text not null,
  strain_key   text,
  note         text,
  unique (catalogue_id, alias_text)
);

comment on table public.brand_catalogue_alias is
  'Other names a brand''s SKU is listed under. Read with the same vocabulary as the strain column, and matched the same way.';

create index if not exists brand_catalogue_alias_cat_idx on public.brand_catalogue_alias (catalogue_id);

-- Aliases are normalised alongside the catalogue they belong to.
create or replace function public.refresh_brand_catalogue_alias_norm(p_brand_key text default null)
returns integer
language plpgsql set search_path = public as $$
declare
  v_format text; v_material text; v_grow text; v_noise text; n integer;
begin
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_format
    from product_terms where kind = 'format';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_material
    from product_terms where kind = 'material';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_grow
    from product_terms where kind = 'grow';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_noise
    from product_terms where kind = 'noise';

  update brand_catalogue_alias a
     set strain_key = norm_strain_key(
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(
             norm_strip_brand(norm_strip_sizes(norm_clean(a.alias_text)), c.brand_key),
             v_format, ' ', 'g'), v_material, ' ', 'g'), v_grow, ' ', 'g'), v_noise, ' ', 'g'))
    from brand_catalogue c
   where c.id = a.catalogue_id
     and (p_brand_key is null or c.brand_key = p_brand_key);
  get diagnostics n = row_count;
  return n;
end $$;

-- Every name a SKU answers to, its own and its aliases.
create or replace view public.v_catalogue_strain as
  select c.id as catalogue_id, c.brand_key, c.format, c.material, c.grams, c.pack,
         c.markets, c.strain_key, true as is_primary
  from brand_catalogue c where c.strain_key is not null
  union all
  select a.catalogue_id, c.brand_key, c.format, c.material, c.grams, c.pack,
         c.markets, a.strain_key, false
  from brand_catalogue_alias a
  join brand_catalogue c on c.id = a.catalogue_id
  where a.strain_key is not null;

comment on view public.v_catalogue_strain is
  'Each catalogue SKU once per name it answers to: its own strain plus its aliases.';

-- Matching now also has to agree about the market. A New Jersey shop's listing is matched
-- against the New Jersey menu, which is what stops a NJ-only SKU claiming a New York
-- listing. A product with no known market is matched against everything, as before.
create or replace function public.match_brand_catalogue(p_brand_key text)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  delete from product_catalogue_match m
   using brand_catalogue c
   where m.catalogue_id = c.id and c.brand_key = p_brand_key;

  insert into product_catalogue_match (product_id, catalogue_id, score)
  select distinct on (x.product_id) x.product_id, x.catalogue_id, x.score
  from (
    select pn.product_id, c.catalogue_id, c.is_primary,
           (case when pn.format = c.format then 4
                 when pn.format in ('flower','preroll','blunt','moonrocks','popcorn','shake')
                  and c.format  in ('flower','preroll','blunt','moonrocks','popcorn','shake') then 2
                 when pn.format in ('concentrate','cartridge','aio','disposable')
                  and c.format  in ('concentrate','cartridge','aio','disposable') then 2
                 else 0 end) as fmt_score,
           (case when pn.grams is not null and c.grams = pn.grams then 4
                 when c.pack is not null and pn.pack = c.pack then 4
                 when c.pack is not null and pn.grams is not null
                  and pn.grams / c.pack between 0.4 and 1.2 then 3
                 else 1 end) as size_score,
           (case when pn.material = c.material then 1 else 0 end) as mat_score,
           (case when ps.toks = cs.toks then 2 else 1 end) as strain_score,
           cardinality(cs.toks) as cat_tokens,
           (case when pn.format = c.format then 4
                 when pn.format in ('flower','preroll','blunt','moonrocks','popcorn','shake')
                  and c.format  in ('flower','preroll','blunt','moonrocks','popcorn','shake') then 2
                 when pn.format in ('concentrate','cartridge','aio','disposable')
                  and c.format  in ('concentrate','cartridge','aio','disposable') then 2
                 else 0 end)
         + (case when pn.grams is not null and c.grams = pn.grams then 4
                 when c.pack is not null and pn.pack = c.pack then 4
                 when c.pack is not null and pn.grams is not null
                  and pn.grams / c.pack between 0.4 and 1.2 then 3
                 else 1 end)
         + (case when pn.material = c.material then 1 else 0 end) as score
    from product_norm pn
    left join product_market pm on pm.product_id = pn.product_id
    cross join lateral (select norm_strain_less_lines(pn.strain_key, pn.brand_key) as toks) ps
    join v_catalogue_strain c on c.brand_key = pn.brand_key
    cross join lateral (select norm_strain_less_lines(c.strain_key, c.brand_key) as toks) cs
    where pn.brand_key = p_brand_key
      and pn.strain_key is not null
      and cardinality(ps.toks) > 0 and cardinality(cs.toks) > 0
      -- The shops that list it have to be in a state whose menu carries it.
      and (pm.states is null or c.markets = '{}' or c.markets && pm.states)
      and (
           cs.toks <@ ps.toks or ps.toks <@ cs.toks
        or (cardinality(cs.toks) = cardinality(ps.toks)
            and exists (
              select 1
              from (select array(select t from unnest(ps.toks) as a(t) where not (t = any(cs.toks))) as p_only,
                           array(select t from unnest(cs.toks) as b(t) where not (t = any(ps.toks))) as c_only) d
              where cardinality(d.p_only) = 1 and cardinality(d.c_only) = 1
                and length(d.p_only[1]) >= 4 and length(d.c_only[1]) >= 4
                and d.p_only[1] !~ '[0-9]' and d.c_only[1] !~ '[0-9]'
                and extensions.levenshtein(d.p_only[1], d.c_only[1]) = 1))
      )
      and (
           (pn.grams is not null and c.grams is not null and pn.grams = c.grams)
        or (pn.pack  is not null and c.pack  is not null and pn.pack  = c.pack)
        or (c.pack is not null and pn.grams is not null and pn.grams / c.pack between 0.4 and 1.2)
        or (c.grams is null and c.pack is null)
        or (pn.grams is null and pn.pack is null)
        or (c.grams is null and pn.pack = c.pack)
        or (pn.grams is null and c.pack is null)
      )
  ) x
  order by x.product_id, x.strain_score desc, x.is_primary desc, x.fmt_score desc,
           x.size_score desc, x.mat_score desc, x.cat_tokens desc, x.catalogue_id;

  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.match_brand_catalogue(text) is
  'Recognise each of a brand''s listings as one of the SKUs the brand says it sells, in a market that carries it. Strain and size decide; format ranks. Aliases count as names the SKU answers to.';

-- Markets and aliases both feed matching, so the maintenance chain refreshes them first.
create or replace function public.refresh_product_identities() returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_pending integer; v_tokens integer; v_lines integer; v_cat integer;
  v_alias integer; v_market integer; v_matched integer := 0;
  v_merges integer; v_retire jsonb; b record;
begin
  select count(*) into v_pending
  from products p
  left join product_categories c on c.id = p.category_id
  where coalesce(c.name, '') not in ('Accessories', 'Experiences')
    and not exists (select 1 from product_norm pn where pn.product_id = p.id);

  if v_pending > 0 then
    return jsonb_build_object(
      'error', 'products still unnormalised', 'pending', v_pending,
      'hint', 'call refresh_product_norm(15000) until it returns 0, then call this again');
  end if;

  v_tokens  := refresh_product_token_stats();
  perform locations_apply_postal_state();
  v_market  := refresh_product_market();
  v_cat     := refresh_brand_catalogue_norm();
  v_alias   := refresh_brand_catalogue_alias_norm();
  v_lines   := refresh_brand_line_terms();

  for b in select distinct brand_key from brand_catalogue loop
    v_matched := v_matched + match_brand_catalogue(b.brand_key);
  end loop;

  v_merges := build_identity_merges();
  v_retire := retire_duplicate_products();

  return jsonb_build_object(
    'tokens', v_tokens, 'catalogue_skus', v_cat, 'aliases', v_alias,
    'line_terms', v_lines, 'products_with_a_market', v_market,
    'catalogue_matches', v_matched, 'merges', v_merges,
    'merges_by_reason', (select jsonb_object_agg(reason, n) from
       (select reason, count(*) as n from product_identity_merge group by reason) z),
    'retirement', v_retire,
    'identities', (select count(distinct canonical_key) from v_identity_resolved));
end $$;

revoke all on table public.brand_catalogue_alias from anon, authenticated;
alter table public.brand_catalogue_alias enable row level security;
grant select on public.brand_catalogue_alias to authenticated;
revoke all on function public.refresh_brand_catalogue_alias_norm(text) from anon, authenticated;
revoke all on function public.match_brand_catalogue(text)   from anon, authenticated;
revoke all on function public.refresh_product_identities()  from anon, authenticated;
