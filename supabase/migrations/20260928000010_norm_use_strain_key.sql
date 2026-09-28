-- Use norm_strain_key for the matching key, so the z-for-s fold, the bare-number drop
-- and token deduplication apply to every product rather than only to new ones.
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

  -- One pattern at a time, each sweeping the whole batch, so Postgres compiles each
  -- regex once per batch instead of once per row.
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
  )
  insert into product_norm as pn
    (product_id, brand_key, format, material, strain, strain_key, grams, mg, oz, pack, identity_key, computed_at)
  select
    product_id, brand_key, format, material,
    nullif(resid, ''), norm_strain_key(resid),
    grams, mg, oz, pack,
    concat_ws('|',
      coalesce(brand_key, '?'),
      coalesce(format, '?'),
      coalesce(material, ''),
      coalesce(norm_strain_key(resid), '?'),
      -- Whichever measure this kind of product is actually sold by.
      coalesce(grams::text, mg::text || 'mg', oz::text || 'oz', '')
    ),
    now()
  from residue
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

revoke all on function public.refresh_product_norm(integer, text) from anon, authenticated;
