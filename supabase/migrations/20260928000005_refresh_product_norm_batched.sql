-- The whole-catalogue pass does not fit in the query API's statement timeout: 45,833
-- products, each matched against 52 regexes, runs past two minutes. So the function
-- takes a batch and the caller loops, exactly as the listing-link job does.
--
-- Replaces refresh_product_norm(text). Dropped explicitly rather than replaced, because
-- CREATE OR REPLACE with a different argument list creates an overload and every later
-- call is ambiguous.
drop function if exists public.refresh_product_norm(text);

create or replace function public.reset_product_norm() returns void
language sql set search_path = public as $$
  delete from product_norm;
$$;

comment on function public.reset_product_norm() is
  'Clear product_norm so the next refresh_product_norm loop recomputes every product. Use after changing product_terms.';

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
  n integer;
begin
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_format
    from product_terms where kind = 'format';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_material
    from product_terms where kind = 'material';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_noise
    from product_terms where kind = 'noise';

  with src as (
    select p.id,
           norm_brand_key(p.cached_brand_names) as brand_key,
           p.cached_brand_names                 as brand,
           norm_clean(p.name)                   as clean,
           c.name                               as category
    from products p
    left join product_categories c on c.id = p.category_id
    where coalesce(c.name, '') not in ('Accessories', 'Experiences')
      and not exists (select 1 from product_norm pn where pn.product_id = p.id)
      and (p_brand_key is null or norm_brand_key(p.cached_brand_names) = p_brand_key)
    order by p.id
    limit p_limit
  ),
  sized as (
    select src.*, norm_size(clean) as sz from src
  ),
  tagged as (
    select sized.*,
      coalesce(
        (select t.label from product_terms t
          where t.kind = 'format' and sized.clean ~ t.pattern
          order by t.priority, t.id limit 1),
        -- No format word in the name. The shop's own shelf still says something:
        -- "Pop Rocks" under Concentrates is a concentrate even though the name is bare.
        case sized.category
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
      (select t.label from product_terms t
        where t.kind = 'material' and sized.clean ~ t.pattern
        order by t.priority, t.id limit 1) as material
    from sized
  ),
  residue as (
    select tagged.*,
      trim(regexp_replace(regexp_replace(
        regexp_replace(regexp_replace(regexp_replace(
          norm_strip_brand(norm_strip_sizes(clean), brand),
          v_format,   ' ', 'g'),
          v_material, ' ', 'g'),
          v_noise,    ' ', 'g'),
        '(^|\s)[-]+(\s|$)', ' ', 'g'),
        '\s+', ' ', 'g')) as resid
    from tagged
  ),
  keyed as (
    select residue.*,
      -- Shops disagree about word order ("Sour Jack" / "Jack Sour"), so the matching
      -- key is the token bag, sorted. The display value keeps the order as written.
      (select string_agg(tok, ' ' order by tok)
         from unnest(regexp_split_to_array(resid, '\s+')) as u(tok)
        where tok <> '' and length(tok) > 1) as strain_key
    from residue
  )
  insert into product_norm as pn
    (product_id, brand_key, format, material, strain, strain_key, grams, mg, oz, pack, identity_key, computed_at)
  select
    id, brand_key, format, material,
    nullif(resid, ''), strain_key,
    (sz).grams, (sz).mg, (sz).oz, (sz).pack,
    concat_ws('|',
      coalesce(brand_key, '?'),
      coalesce(format, '?'),
      coalesce(material, ''),
      coalesce(strain_key, '?'),
      -- Whichever measure this kind of product is actually sold by.
      coalesce((sz).grams::text, (sz).mg::text || 'mg', (sz).oz::text || 'oz', '')
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
revoke all on function public.reset_product_norm() from anon, authenticated;
