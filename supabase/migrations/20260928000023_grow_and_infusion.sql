-- Two corrections to what counts as the same product.
--
-- 1. Grow method is part of the identity. "El Jefe - Indoor" and "El Jefe - Sungrown"
--    are different products at different prices, and treating the grow words as noise
--    merged them. They become a fourth axis rather than rejoining noise, because the
--    words still have to leave the strain residue.
--
-- 2. How a shop describes an infusion is not part of the identity. Lobo's Bold blunt
--    arrives as "Sauce & Hash Infused Blunt", "Infused Blunt" and "Blunt", and those are
--    one SKU. On a format that is flower, the extract is a topping the shop mentions or
--    does not; on a concentrate or a cartridge the extract IS the product and still
--    separates a live resin cart from a cured resin one.

delete from public.product_terms
 where kind = 'noise' and note = 'grow method';

alter table public.product_terms drop constraint if exists product_terms_kind_check;
alter table public.product_terms add  constraint product_terms_kind_check
  check (kind in ('format', 'material', 'grow', 'noise'));

insert into public.product_terms (kind, label, pattern, priority, note) values
  ('grow','indoor',     '\mindoors?\M',                         10, null),
  ('grow','light deps', 'light\s*deps?\M|\mdeps?\M|mixed\s*light', 10, 'greenhouse under supplemental light'),
  ('grow','greenhouse', 'greenhouse|green\s*house',             20, null),
  ('grow','sungrown',   'sun\s*grown|sungrown',                 20, 'kept apart from outdoor: a brand using both means something by it'),
  ('grow','outdoor',    '\moutdoors?\M|\mouts\M|\mfull\s*sun\M', 25, null),
  ('grow','hydroponic', 'hydro(ponic)?\M|\maero(ponic)?\M',     25, null)
on conflict do nothing;

-- "outs" was noise, as an abbreviation of outdoors. It is a grow word now.
update public.product_terms
   set pattern = '\minf\M|\mgreen\s*hse\M'
 where kind = 'noise' and note = 'abbreviations';

alter table public.product_norm       add column if not exists grow text;
alter table public.product_norm_stage add column if not exists grow text;

create index if not exists product_norm_grow_idx on public.product_norm (grow);

comment on column public.product_norm.grow is
  'How it was grown, where the name says. Part of the identity: indoor and sungrown of the same strain are different products at different prices.';

-- On a flower format the extract is a topping the shop may or may not name, so every
-- extract collapses to the single fact that it is infused. On a concentrate or a
-- cartridge the extract is the product and is kept.
create or replace function public.norm_material_for_format(p_format text, p_material text)
returns text
language sql immutable as $$
  select case
    when p_material is null then null
    when p_format in ('flower','preroll','blunt','minis','moonrocks','popcorn','shake','cannagar')
     and p_material in ('live rosin','live resin','cured resin','rosin','resin','badder',
                        'sugar','sauce','diamonds','crumble','shatter','wax','kief',
                        'hashish','distillate','rso')
    then 'infused'
    else p_material
  end;
$$;

comment on function public.norm_material_for_format(text, text) is
  'Collapse an extract to "infused" on formats that are flower, where naming the extract is a shop''s choice of words. Leaves concentrates and cartridges alone, where the extract is the product.';
