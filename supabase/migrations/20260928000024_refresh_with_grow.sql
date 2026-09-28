-- Read the grow method as a fourth axis, and collapse infusion wording on flower formats.
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
  v_grow     text;
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
     set grams = (sz).grams, mg = (sz).mg, oz = (sz).oz, ml = (sz).ml, pack = (sz).pack
    from (select product_id, norm_size(clean) as sz from product_norm_stage) c
   where c.product_id = s.product_id;

  -- One pattern at a time, each sweeping the whole batch, so Postgres compiles each
  -- regex once per batch instead of once per row.
  for t in select kind, label, pattern, priority from product_terms
            where kind in ('format', 'material', 'grow') order by kind, priority, id
  loop
    insert into product_norm_hit (product_id, kind, label, priority)
    select product_id, t.kind, t.label, t.priority
      from product_norm_stage where clean ~ t.pattern;
  end loop;

  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_format
    from product_terms where kind = 'format';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_material
    from product_terms where kind = 'material';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_grow
    from product_terms where kind = 'grow';
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
        order by h.priority limit 1) as material_raw,
      (select h.label from product_norm_hit h
        where h.product_id = s.product_id and h.kind = 'grow'
        order by h.priority limit 1) as grow
    from product_norm_stage s
  ),
  residue as (
    select picked.*,
      norm_material_for_format(format, material_raw) as material,
      trim(regexp_replace(
        regexp_replace(regexp_replace(regexp_replace(regexp_replace(
          norm_strip_brand(norm_strip_sizes(clean), brand),
          v_format,   ' ', 'g'),
          v_material, ' ', 'g'),
          v_grow,     ' ', 'g'),
          v_noise,    ' ', 'g'),
        ' +', ' ', 'g')) as resid
    from picked
  ),
  keyed as (
    select residue.*,
           norm_strain_key(resid) as resid_key,
           norm_strain_key(clean) as name_key
    from residue
  )
  insert into product_norm as pn
    (product_id, brand_key, format, material, grow, strain, strain_key, strain_from_name,
     grams, mg, oz, ml, pack, identity_key, computed_at)
  select
    product_id, brand_key, format, material, grow,
    coalesce(nullif(resid, ''), clean),
    coalesce(resid_key, name_key),
    resid_key is null,
    grams, mg, oz, ml, pack,
    concat_ws('|',
      coalesce(brand_key, '?'),
      coalesce(format, '?'),
      coalesce(material, ''),
      coalesce(grow, ''),
      coalesce(resid_key, name_key, 'p' || product_id),
      norm_size_key(grams, mg, ml, oz, pack)
    ),
    now()
  from keyed
  on conflict (product_id) do update set
    brand_key        = excluded.brand_key,
    format           = excluded.format,
    material         = excluded.material,
    grow             = excluded.grow,
    strain           = excluded.strain,
    strain_key       = excluded.strain_key,
    strain_from_name = excluded.strain_from_name,
    grams            = excluded.grams,
    mg               = excluded.mg,
    oz               = excluded.oz,
    ml               = excluded.ml,
    pack             = excluded.pack,
    identity_key     = excluded.identity_key,
    computed_at      = excluded.computed_at;

  get diagnostics n = row_count;
  return n;
end $$;

-- The sizeless merge has to agree on the grow method too, or an unsized indoor listing
-- could adopt a sungrown product's weight.
create or replace function public.build_identity_merges() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  delete from product_identity_merge;

  insert into product_identity_merge (from_identity, to_identity, dropped_tokens, min_brands)
  with ident as (
    select identity_key, brand_key, format, material, grow, strain_key,
           norm_size_key(min(grams), min(mg), min(ml), min(oz), min(pack)) as size_key
    from product_norm
    where strain_key is not null and brand_key is not null and not strain_from_name
    group by identity_key, brand_key, format, material, grow, strain_key
  ),
  unsized as (select * from ident where size_key = ''),
  sized   as (select * from ident where size_key <> ''),
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
      and coalesce(s.grow, '')     = coalesce(u.grow, '')
      and s.strain_key = u.strain_key
    group by u.identity_key
  )
  select from_identity, to_identity, null, null
  from candidate where options = 1;

  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.refresh_product_norm(integer, text) from anon, authenticated;
revoke all on function public.build_identity_merges() from anon, authenticated;
