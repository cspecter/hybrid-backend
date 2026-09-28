-- Three gaps in catalogue matching, all closable because the catalogue is ground truth.
--
-- 1. Product-line names. Lobo's listings say "Fuerte Papaya", "Gelato Presidente",
--    "El Presidente", and none of those match a strain because Fuerte and Presidente are
--    Lobo's names for its own pre-roll and blunt lines. Two earlier attempts to work this
--    out from the names alone were deleted for destroying products -- no statistic over
--    names separates a line name from a strain word.
--
--    The catalogue settles it. Its SKU labels are exactly where a brand writes its line
--    names: "Bold 1g infused", "Fuerte 1g", "Presidente 2g infused", "3.5g Sauce Cannon",
--    "1g Stardust Jar". Whatever is left of a label once the format, material, size and
--    noise words are gone is a line name -- unless it also appears in the brand's strain
--    column, which is what stops "blend" being taken out of Sativa Blend.
--
-- 2. A pack whose weight the shop stated instead of its count. Minis are 5 to a box; a
--    shop writing "2.5g" or "5g" and no count still describes a box of 5 at 0.5g or 1g
--    each. Dividing by the catalogue's count and asking whether the result is a plausible
--    pre-roll settles it.
--
-- 3. One mistyped word, against the brand's list only. "Maker Permanent" for Permanent
--    Marker. The free-form version of this rule was deleted for merging phenotype numbers
--    and ratios into each other; against a curated list of 22 SKUs it has somewhere to
--    land and nowhere to wander, and numeric tokens are excluded outright.

create table if not exists public.brand_line_term (
  brand_key text not null,
  token     text not null,
  primary key (brand_key, token)
);

comment on table public.brand_line_term is
  'Words that name a brand''s own product line rather than a strain, taken from the brand''s SKU labels. Excluded from strain comparison.';

create or replace function public.refresh_brand_line_terms(p_brand_key text default null)
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

  delete from brand_line_term where p_brand_key is null or brand_key = p_brand_key;

  insert into brand_line_term (brand_key, token)
  with label_residue as (
    select c.brand_key,
           norm_strain_key(
             regexp_replace(regexp_replace(regexp_replace(regexp_replace(
               norm_strip_brand(norm_strip_sizes(norm_clean(c.sku_label)), c.brand_key),
               v_format, ' ', 'g'), v_material, ' ', 'g'), v_grow, ' ', 'g'), v_noise, ' ', 'g')
           ) as resid
    from brand_catalogue c
    where p_brand_key is null or c.brand_key = p_brand_key
  ),
  candidate as (
    select brand_key, u.t as token
    from label_residue, unnest(string_to_array(resid, ' ')) as u(t)
    where resid is not null and length(u.t) > 1
  )
  select distinct cd.brand_key, cd.token
  from candidate cd
  -- A word the brand also uses as a strain is a strain, whatever else it does.
  where not exists (
    select 1 from brand_catalogue c2, unnest(string_to_array(c2.strain_key, ' ')) as s(t)
    where c2.brand_key = cd.brand_key and s.t = cd.token
  )
  on conflict do nothing;

  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.refresh_brand_line_terms(text) is
  'Learn a brand''s product-line names from its own SKU labels: whatever survives the vocabulary and is not also one of its strains.';

-- Strain comparison with line names removed from the listing side.
create or replace function public.norm_strain_less_lines(p_strain_key text, p_brand_key text)
returns text[]
language sql immutable
set search_path = public
as $$
  select coalesce(array_agg(t order by t), '{}')
  from unnest(string_to_array(coalesce(p_strain_key, ''), ' ')) as u(t)
  where t <> ''
    and not exists (select 1 from brand_line_term b
                     where b.brand_key = p_brand_key and b.token = u.t);
$$;

create or replace function public.match_brand_catalogue(p_brand_key text)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  delete from product_catalogue_match m
   using brand_catalogue c
   where m.catalogue_id = c.id and c.brand_key = p_brand_key;

  insert into product_catalogue_match (product_id, catalogue_id, score)
  select distinct on (x.product_id) x.product_id, x.id, x.score
  from (
    select pn.product_id, c.id,
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
    cross join lateral (select norm_strain_less_lines(pn.strain_key, pn.brand_key) as toks) ps
    join brand_catalogue c on c.brand_key = pn.brand_key and c.strain_key is not null
    cross join lateral (select norm_strain_less_lines(c.strain_key, c.brand_key) as toks) cs
    where pn.brand_key = p_brand_key
      and pn.strain_key is not null
      and cardinality(ps.toks) > 0 and cardinality(cs.toks) > 0
      and (
           -- one strain name contains the other, once line names are set aside
           cs.toks <@ ps.toks or ps.toks <@ cs.toks
           -- or the same number of words with one of them mistyped by a single character
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
  order by x.product_id, x.strain_score desc, x.fmt_score desc, x.size_score desc,
           x.mat_score desc, x.cat_tokens desc, x.id;

  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.match_brand_catalogue(text) is
  'Recognise each of a brand''s listings as one of the SKUs the brand says it sells. Strain and size decide; format ranks. Line names come out of the comparison, a stated pack weight is reconciled against the catalogue''s count, and a single mistyped character is tolerated because the target list is curated.';

revoke all on table public.brand_line_term from anon, authenticated;
alter table public.brand_line_term enable row level security;
revoke all on function public.refresh_brand_line_terms(text) from anon, authenticated;
revoke all on function public.norm_strain_less_lines(text, text) from anon, authenticated;
