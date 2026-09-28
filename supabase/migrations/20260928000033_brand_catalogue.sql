-- A brand's own product list, and the matching of menu listings onto it.
--
-- Name normalisation has a ceiling and Lobo shows exactly where it is. After the vocabulary,
-- the sizes, the grow axis and the three evidence-based merges, Lobo still holds 87
-- identities for 22 real products, and the remainder splits on things that would be wrong
-- to merge for anyone else:
--
--   Size. Gruntz appears at 1g, 2.5g, 5g and "5pk" -- every one of them the Minis 5-pack,
--   because shops disagree about whether a mini weighs 0.5g or 1g. No arithmetic reconciles
--   that, and collapsing 1g into 5g would be wrong for every brand that sells both.
--
--   Format. "Presidente 2g" arrives as a blunt from one shop and a pre-roll from the next.
--   Treating those as one format would merge real pairs elsewhere.
--
--   Strain text. Twelve identities for Jack'd Sour Diesel and Jelly Donut. Three different
--   inference rules were built to close gaps like this and all three were deleted for
--   destroying products.
--
-- So stop inferring. A brand knows what it sells. Given that list, a listing does not have
-- to be understood in the abstract, only recognised as the nearest thing on it -- and the
-- list is also what says 22, which no amount of reading shop names can know.

create table if not exists public.brand_catalogue (
  id          serial primary key,
  brand_key   text not null,
  sku_label   text not null,      -- the brand's own name for the form, e.g. "Minis 5-pack"
  strain      text not null,
  category    text,
  price       numeric(10,2),
  in_stock    boolean,
  -- Filled by refresh_brand_catalogue_norm, using the same reading the menu names get.
  format      text,
  material    text,
  grams       numeric(10,2),
  pack        integer,
  strain_key  text,
  source_note text,
  created_at  timestamptz not null default now(),
  unique (brand_key, sku_label, strain)
);

comment on table public.brand_catalogue is
  'What a brand says it sells, one row per SKU, supplied by the brand. Menu listings are matched onto this, so the count of real products comes from the brand rather than from guessing at shop spellings.';

create index if not exists brand_catalogue_brand_idx on public.brand_catalogue (brand_key);

-- The SKU label and the strain go through exactly the vocabulary the menu names go through,
-- so "Minis 5-pack" and a shop's "Minis | 5pk Infused | Pre Rolls" are read the same way.
create or replace function public.refresh_brand_catalogue_norm(p_brand_key text default null)
returns integer
language plpgsql set search_path = public as $$
declare
  v_format text; v_material text; v_grow text; v_noise text;
  r record; n integer := 0;
  c_clean text; c_fmt text; c_mat text; sz norm_size_t;
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
    -- The label carries the form and the size; the strain column carries the strain.
    c_clean := norm_clean(r.sku_label || ' ' || coalesce(r.category, ''));
    sz      := norm_size(c_clean);

    select t.label into c_fmt from product_terms t
     where t.kind = 'format' and c_clean ~ t.pattern
     order by t.priority, t.id limit 1;

    select t.label into c_mat from product_terms t
     where t.kind = 'material' and c_clean ~ t.pattern
     order by t.priority, t.id limit 1;

    update brand_catalogue set
      format     = coalesce(c_fmt, case lower(coalesce(r.category,''))
                                     when 'flower'          then 'flower'
                                     when 'infused pre-roll' then 'preroll'
                                     when 'infused blunt'    then 'blunt'
                                     when 'moon rocks'       then 'moonrocks'
                                     when 'concentrate'      then 'concentrate'
                                   end),
      material   = norm_material_for_format(
                     coalesce(c_fmt, case lower(coalesce(r.category,''))
                                       when 'flower'           then 'flower'
                                       when 'infused pre-roll' then 'preroll'
                                       when 'infused blunt'    then 'blunt'
                                       when 'moon rocks'       then 'moonrocks'
                                       when 'concentrate'      then 'concentrate'
                                     end), c_mat),
      grams      = (sz).grams,
      pack       = (sz).pack,
      strain_key = norm_strain_key(
                     regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                       norm_strip_brand(norm_strip_sizes(norm_clean(r.strain)), r.brand_key),
                       v_format, ' ', 'g'), v_material, ' ', 'g'), v_grow, ' ', 'g'), v_noise, ' ', 'g'))
    where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

comment on function public.refresh_brand_catalogue_norm(text) is
  'Read each catalogue SKU''s label and strain with the same vocabulary the menu names get, so the two sides are comparable.';

revoke all on table public.brand_catalogue from anon, authenticated;
alter table public.brand_catalogue enable row level security;
grant select on public.brand_catalogue to authenticated;
revoke all on function public.refresh_brand_catalogue_norm(text) from anon, authenticated;
