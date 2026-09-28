-- The label fallback has to live in the function, not in a one-off statement.
--
-- refresh_brand_catalogue_norm recomputes strain_key from the strain column, so putting the
-- fallback in a migration UPDATE meant the next maintenance run undid it: Lobo's
-- "1g Stardust Jar / Pure THC diamond powder" reduces to nothing -- pure, THC, diamond and
-- powder are all vocabulary -- and lost its 14 listings the first time the chain ran.
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
                               when 'flower'           then 'flower'
                               when 'infused pre-roll' then 'preroll'
                               when 'infused blunt'    then 'blunt'
                               when 'moon rocks'       then 'moonrocks'
                               when 'concentrate'      then 'concentrate'
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
