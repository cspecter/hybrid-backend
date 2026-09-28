-- Match menu listings onto the brand's own SKUs.
--
-- Strain and size decide; format only ranks. That split is deliberate. Strain and size are
-- what a shop reliably records, while the format word is the thing shops disagree about --
-- Presidente arrives as a blunt from one and a pre-roll from the next, and a moonrock gets
-- filed under Flower, Moon Rocks or Concentrates depending on who is typing.
--
-- Size is why this works where arithmetic did not. Gruntz Minis arrive at 1g, 2.5g, 5g and
-- "5pk" because shops disagree about what one mini weighs, but every one of them says 5 per
-- box, and the catalogue says Minis come 5 to a box. The pack count matches where no weight
-- ever will.
--
-- The strain test is subset in one direction or the other, not overlap. Overlap would let
-- "Jelly Donut" match "Sour Diesel" on the shared word "sour". Under subset it matches
-- nothing and keeps its own identity, which is correct: Jelly Donut is not on Lobo's list.

-- A catalogue strain that reduces to nothing takes its name from its label. Lobo's
-- "Pure THC diamond powder" is all vocabulary -- pure, THC, diamond, powder -- so the SKU
-- would have no strain to match on at all; "1g Stardust Jar" gives it Stardust.
update public.brand_catalogue c
   set strain_key = norm_strain_key(
         norm_strip_brand(norm_strip_sizes(norm_clean(c.sku_label)), c.brand_key))
 where c.strain_key is null;

create table if not exists public.product_catalogue_match (
  product_id   bigint primary key references public.products(id) on delete cascade,
  catalogue_id integer not null references public.brand_catalogue(id) on delete cascade,
  score        integer not null,
  matched_at   timestamptz not null default now()
);

create index if not exists product_catalogue_match_cat_idx
  on public.product_catalogue_match (catalogue_id);

comment on table public.product_catalogue_match is
  'The brand SKU each listing was recognised as. Listings matching nothing on the brand''s list are absent and keep the identity read from their name.';

create or replace function public.match_brand_catalogue(p_brand_key text)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  delete from product_catalogue_match m
   using brand_catalogue c
   where m.catalogue_id = c.id and c.brand_key = p_brand_key;

  insert into product_catalogue_match (product_id, catalogue_id, score)
  select distinct on (pn.product_id)
         pn.product_id, c.id,
         -- Format agreement only ranks; it never admits or rejects.
         (case when pn.format = c.format then 4
               when pn.format in ('flower','preroll','blunt','moonrocks','popcorn','shake')
                and c.format  in ('flower','preroll','blunt','moonrocks','popcorn','shake') then 2
               when pn.format in ('concentrate','cartridge','aio','disposable')
                and c.format  in ('concentrate','cartridge','aio','disposable') then 2
               else 0 end)
       + (case when pn.grams is not null and c.grams = pn.grams then 4
               when c.pack is not null and pn.pack = c.pack then 4
               else 1 end)
       + (case when pn.material = c.material then 1 else 0 end) as score
  from product_norm pn
  join brand_catalogue c
    on  c.brand_key = pn.brand_key
    and c.strain_key is not null
    and pn.strain_key is not null
    -- One strain name contains the other. A shop adds words ("Cannon Sour Diesel Jackd"),
    -- it does not usually drop the strain.
    and (string_to_array(c.strain_key,' ') <@ string_to_array(pn.strain_key,' ')
      or string_to_array(pn.strain_key,' ') <@ string_to_array(c.strain_key,' '))
    -- Size has to be reconcilable: the same weight, the same pack count, or one side
    -- silent about it. A stated weight that disagrees with a stated weight is a different
    -- product, which is what keeps 7g, 14g and 28g pre-ground apart.
    and (
         (pn.grams is not null and c.grams is not null and pn.grams = c.grams)
      or (pn.pack  is not null and c.pack  is not null and pn.pack  = c.pack)
      or (c.grams is null and c.pack is null)
      or (pn.grams is null and pn.pack is null)
      or (c.grams is null and pn.pack = c.pack)
      or (pn.grams is null and c.pack is null)
    )
  where pn.brand_key = p_brand_key
  order by pn.product_id,
           -- exact format, then exact size, then material, then the brand's own ordering
           (case when pn.format = c.format then 4
                 when pn.format in ('flower','preroll','blunt','moonrocks','popcorn','shake')
                  and c.format  in ('flower','preroll','blunt','moonrocks','popcorn','shake') then 2
                 when pn.format in ('concentrate','cartridge','aio','disposable')
                  and c.format  in ('concentrate','cartridge','aio','disposable') then 2
                 else 0 end) desc,
           (case when pn.grams is not null and c.grams = pn.grams then 4
                 when c.pack is not null and pn.pack = c.pack then 4
                 else 1 end) desc,
           (case when pn.material = c.material then 1 else 0 end) desc,
           cardinality(string_to_array(c.strain_key,' ')) desc,
           c.id;

  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.match_brand_catalogue(text) is
  'Recognise each of a brand''s listings as one of the SKUs the brand says it sells. Strain and size decide the match; format only ranks it.';

-- A matched listing takes its identity from the catalogue SKU. Everything else keeps the
-- identity read from its name, resolved through the merge chain as before.
create or replace view public.v_identity_resolved as
  with recursive walk as (
    select from_identity as identity_key, to_identity, 1 as depth
      from product_identity_merge
    union all
    select w.identity_key, m.to_identity, w.depth + 1
      from walk w join product_identity_merge m on m.from_identity = w.to_identity
     where w.depth < 10
  ),
  root as (
    select distinct on (identity_key) identity_key, to_identity as canonical_key
      from walk order by identity_key, depth desc
  )
  select pn.product_id,
         pn.identity_key,
         coalesce('cat:' || cm.catalogue_id, r.canonical_key, pn.identity_key) as canonical_key
  from product_norm pn
  left join root r on r.identity_key = pn.identity_key
  left join product_catalogue_match cm on cm.product_id = pn.product_id;

comment on view public.v_identity_resolved is
  'Every product with the identity it ends up at: the brand''s own SKU where the listing was recognised as one, otherwise the identity read from its name with merge chains followed to their root.';

revoke all on table public.product_catalogue_match from anon, authenticated;
alter table public.product_catalogue_match enable row level security;
grant select on public.product_catalogue_match to authenticated;
revoke all on function public.match_brand_catalogue(text) from anon, authenticated;
