-- A brand sells a different range in each state, and some SKUs in both.
--
-- Lobo's New Jersey list carries 12 SKUs. Three of them -- Bold 1g Blue Dream, 1g Hashish
-- Jar Blue Dream, Minis 5-pack Blue Dream -- are also on the New York list. Those are one
-- product available in two states, not two products, so the market is a property of the SKU
-- rather than a second copy of it. One row per (brand, label, strain); markets says where.
alter table public.brand_catalogue add column if not exists markets text[] not null default '{}';

comment on column public.brand_catalogue.markets is
  'States whose menu carries this SKU. A product sold in two states is one row, because it is one product.';

update public.brand_catalogue set markets = array['NY'] where markets = '{}';

-- The two sheets file the same shape under different category names: New York writes
-- "Moon Rocks" and "Infused Blunt", New Jersey writes "Infused Flower" and calls the Bold
-- blunt an "Infused Pre-Roll". Both spellings have to reach the same format.
create or replace function public.refresh_brand_catalogue_norm(p_brand_key text default null)
returns integer
language plpgsql set search_path = public as $$
declare
  v_format text; v_material text; v_grow text; v_noise text;
  r record; n integer := 0;
  c_clean text; c_fmt text; c_mat text; c_strain text; sz norm_size_t;
begin
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_format
    from product_terms where kind = 'format';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_material
    from product_terms where kind = 'material';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_grow
    from product_terms where kind = 'grow';
  select string_agg('(?:' || pattern || ')', '|' order by priority, id) into v_noise
    from product_terms where kind = 'noise';

  for r in select * from brand_catalogue
            where p_brand_key is null or brand_key = p_brand_key loop
    c_clean := norm_clean(r.sku_label || ' ' || coalesce(r.category, ''));
    sz      := norm_size(c_clean);

    select t.label into c_fmt from product_terms t
     where t.kind = 'format' and c_clean ~ t.pattern
     order by t.priority, t.id limit 1;
    select t.label into c_mat from product_terms t
     where t.kind = 'material' and c_clean ~ t.pattern
     order by t.priority, t.id limit 1;

    c_fmt := coalesce(c_fmt, case lower(coalesce(r.category, ''))
                               when 'flower'            then 'flower'
                               when 'infused flower'    then 'flower'
                               when 'pre-rolls'         then 'preroll'
                               when 'infused pre-roll'  then 'preroll'
                               when 'infused pre-rolls' then 'preroll'
                               when 'infused blunt'     then 'blunt'
                               when 'moon rocks'        then 'moonrocks'
                               when 'moonrocks'         then 'moonrocks'
                               when 'concentrate'       then 'concentrate'
                               when 'concentrates'      then 'concentrate'
                               when 'edibles'           then 'edible'
                             end);

    c_strain := norm_strain_key(
      regexp_replace(regexp_replace(regexp_replace(regexp_replace(
        norm_strip_brand(norm_strip_sizes(norm_clean(r.strain)), r.brand_key),
        v_format, ' ', 'g'), v_material, ' ', 'g'), v_grow, ' ', 'g'), v_noise, ' ', 'g'));

    -- A strain that is all vocabulary takes its name from the label instead.
    if c_strain is null then
      c_strain := norm_strain_key(
        norm_strip_brand(norm_strip_sizes(norm_clean(r.sku_label)), r.brand_key));
    end if;

    update brand_catalogue set
      format     = c_fmt,
      material   = norm_material_for_format(c_fmt, c_mat),
      grams      = (sz).grams,
      pack       = (sz).pack,
      strain_key = c_strain
    where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

revoke all on function public.refresh_brand_catalogue_norm(text) from anon, authenticated;
