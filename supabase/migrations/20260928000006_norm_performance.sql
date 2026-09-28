-- Make the whole-catalogue pass finish.
--
-- The first version cost 41ms per product, which is 31 minutes for the catalogue and
-- well past the query API's statement timeout at any useful batch size. The cost was
-- not the volume of regex, it was Postgres recompiling it. Postgres caches 32 compiled
-- patterns; this ran ~55 distinct ones per row, so nearly every match was a cache miss.
--
-- Two changes, both about compiling each pattern once instead of once per row:
--
--   1. norm_strip_brand built a pattern out of each brand word. Across 7,528 brands
--      those patterns are all distinct, so every row evicted the cache no matter how
--      few other patterns were in play. Removing a known word from a list of words
--      does not need a regex at all -- it is set arithmetic on tokens.
--
--   2. Format and material were chosen with a correlated subquery, so a row was tested
--      against all 40 patterns before the next row began, interleaving 40 patterns
--      forever. Now one pattern sweeps the whole batch before the next is used, which
--      is the same number of tests and 40 compiles per batch instead of 40 per row.

-- ---------------------------------------------------------------- brand, without regex

create or replace function public.norm_strip_brand(p_clean text, p_brand text) returns text
language sql immutable
set search_path = public
as $$
  with brand as (
    select array_agg(w) filter (where length(w) >= 3) as words,
           string_agg(left(w, 1), '' order by ord)    as initials
    from unnest(regexp_split_to_array(norm_clean(p_brand), ' ')) with ordinality as u(w, ord)
    where w <> ''
  )
  select coalesce((
    select string_agg(tok, ' ' order by ord)
    from unnest(regexp_split_to_array(p_clean, ' ')) with ordinality as n(tok, ord)
    cross join brand b
    where tok <> ''
      and tok ~ '[a-z0-9]'                                        -- drop stray separators
      and not (tok = any(coalesce(b.words, '{}')))
      and not (length(coalesce(b.initials, '')) between 2 and 4 and tok = b.initials)
  ), '');
$$;

comment on function public.norm_strip_brand(text, text) is
  'Remove the brand from an item name by token comparison. A brand recurs spelled out ("Florist Farms | Gorilla Glue") or initialised ("FF - Triangle Cake"); neither is the strain.';

-- ---------------------------------------------------------------- staging

-- Permanent and unlogged rather than temporary: plpgsql caches plans by table name, and
-- a temp table recreated on each call invalidates them mid-loop.
create unlogged table if not exists public.product_norm_stage (
  product_id bigint primary key,
  brand_key  text,
  brand      text,
  clean      text,
  category   text,
  grams      numeric(10,2),
  mg         numeric(10,2),
  oz         numeric(10,2),
  pack       integer
);

create unlogged table if not exists public.product_norm_hit (
  product_id bigint not null,
  kind       text   not null,
  label      text   not null,
  priority   integer not null
);

create index if not exists product_norm_hit_pick_idx
  on public.product_norm_hit (product_id, kind, priority);

revoke all on table public.product_norm_stage from anon, authenticated;
revoke all on table public.product_norm_hit   from anon, authenticated;
alter table public.product_norm_stage enable row level security;
alter table public.product_norm_hit   enable row level security;

-- ---------------------------------------------------------------- the pass

create or replace function public.refresh_product_norm(
  p_limit     integer default 5000,
  p_brand_key text default null
) returns integer
language plpgsql
set search_path = public
as $$
declare
  v_format   text;
  v_material text;
  v_noise    text;
  t          record;
  n          integer;
begin
  truncate product_norm_stage;
  truncate product_norm_hit;

  insert into product_norm_stage (product_id, brand_key, brand, clean, category)
  select p.id,
         norm_brand_key(p.cached_brand_names),
         p.cached_brand_names,
         norm_clean(p.name),
         c.name
  from products p
  left join product_categories c on c.id = p.category_id
  where coalesce(c.name, '') not in ('Accessories', 'Experiences')
    and not exists (select 1 from product_norm pn where pn.product_id = p.id)
    and (p_brand_key is null or norm_brand_key(p.cached_brand_names) = p_brand_key)
  order by p.id
  limit p_limit;

  update product_norm_stage s
     set grams = (sz).grams, mg = (sz).mg, oz = (sz).oz, pack = (sz).pack
    from (select product_id, norm_size(clean) as sz from product_norm_stage) c
   where c.product_id = s.product_id;

  -- One pattern at a time, each sweeping the whole batch.
  for t in select kind, label, pattern, priority from product_terms
            where kind in ('format', 'material') order by kind, priority, id
  loop
    insert into product_norm_hit (product_id, kind, label, priority)
    select product_id, t.kind, t.label, t.priority
      from product_norm_stage where clean ~ t.pattern;
  end loop;

  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_format
    from product_terms where kind = 'format';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_material
    from product_terms where kind = 'material';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_noise
    from product_terms where kind = 'noise';

  with picked as (
    select s.*,
      coalesce(
        (select h.label from product_norm_hit h
          where h.product_id = s.product_id and h.kind = 'format'
          order by h.priority limit 1),
        -- No format word in the name. The shop's own shelf still says something:
        -- "Pop Rocks" under Concentrates is a concentrate even though the name is bare.
        case s.category
          when 'Flower'       then 'flower'
          when 'Pre-Rolls'    then 'preroll'
          when 'Vaporizers'   then 'cartridge'
          when 'Edibles'      then 'edible'
          when 'Beverages'    then 'beverage'
          when 'Tinctures'    then 'tincture'
          when 'Topicals'     then 'topical'
          when 'Concentrates' then 'concentrate'
        end
      ) as format,
      (select h.label from product_norm_hit h
        where h.product_id = s.product_id and h.kind = 'material'
        order by h.priority limit 1) as material
    from product_norm_stage s
  ),
  residue as (
    select picked.*,
      trim(regexp_replace(
        regexp_replace(regexp_replace(regexp_replace(
          norm_strip_brand(norm_strip_sizes(clean), brand),
          v_format,   ' ', 'g'),
          v_material, ' ', 'g'),
          v_noise,    ' ', 'g'),
        ' +', ' ', 'g')) as resid
    from picked
  ),
  keyed as (
    select residue.*,
      -- Shops disagree about word order ("Sour Jack" / "Jack Sour"), so the matching
      -- key is the token bag, sorted. The display value keeps the order as written.
      (select string_agg(tok, ' ' order by tok)
         from unnest(regexp_split_to_array(resid, ' ')) as u(tok)
        where length(tok) > 1) as strain_key
    from residue
  )
  insert into product_norm as pn
    (product_id, brand_key, format, material, strain, strain_key, grams, mg, oz, pack, identity_key, computed_at)
  select
    product_id, brand_key, format, material,
    nullif(resid, ''), strain_key,
    grams, mg, oz, pack,
    concat_ws('|',
      coalesce(brand_key, '?'),
      coalesce(format, '?'),
      coalesce(material, ''),
      coalesce(strain_key, '?'),
      -- Whichever measure this kind of product is actually sold by.
      coalesce(grams::text, mg::text || 'mg', oz::text || 'oz', '')
    ),
    now()
  from keyed
  on conflict (product_id) do update set
    brand_key    = excluded.brand_key,
    format       = excluded.format,
    material     = excluded.material,
    strain       = excluded.strain,
    strain_key   = excluded.strain_key,
    grams        = excluded.grams,
    mg           = excluded.mg,
    oz           = excluded.oz,
    pack         = excluded.pack,
    identity_key = excluded.identity_key,
    computed_at  = excluded.computed_at;

  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.refresh_product_norm(integer, text) is
  'Read up to p_limit not-yet-normalised products into (brand, format, material, strain, size). Returns rows written; call in a loop until it returns 0.';

revoke all on function public.refresh_product_norm(integer, text) from anon, authenticated;
