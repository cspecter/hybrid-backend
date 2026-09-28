-- The shapes a cannabis product comes in.
--
-- A menu name is a brand's product written however the shop felt like writing it.
-- Lobo's own catalogue says what the identity underneath actually is: a SKU form
-- crossed with a strain — "Minis 5-pack" in Gruntz, Blue Dream, Papaya Punch. So
-- collapsing 402 spellings back to 22 products means recognising the form and the
-- strain and ignoring everything else.
--
-- Forms are a closed vocabulary and go in a table; strains are open and get mined
-- from the data separately.
--
-- ORDER MATTERS, which is why there is a priority column. A brand's own SKU name beats
-- the material it is made of: "Bold" is Lobo's 1g blunt and it happens to be sauce-and-
-- hash infused, so matching "hash" first labels it hashish and splits it from its
-- siblings. Named SKUs first, then materials, then generic shapes.
create table if not exists public.product_forms (
  id        serial primary key,
  label     text not null unique,     -- canonical name used in the identity key
  pattern   text not null,            -- case-insensitive regex matched against the name
  priority  integer not null,         -- lower wins
  brand_key text,                     -- set when the form is one brand's SKU name
  note      text
);

create index if not exists product_forms_priority_idx on public.product_forms (priority);

comment on table public.product_forms is
  'Vocabulary of product forms, matched against menu names to recover product identity. Lower priority wins when several match.';
comment on column public.product_forms.brand_key is
  'Set when this is a specific brand''s SKU name rather than a general form, so it is only applied to that brand.';

insert into public.product_forms (label, pattern, priority, brand_key, note) values
  -- Lobo's own SKU names, from the catalogue they supplied. Scoped to Lobo so
  -- "bold" in another brand's name does not become a Lobo blunt.
  ('bold blunt',    '\mbold\M',                              10, 'lobo', 'Lobo SKU: Bold 1g infused blunt'),
  ('presidente',    'presidente?',                           10, 'lobo', 'Lobo SKU: Presidente 2g infused'),
  ('fuerte',        'fuerte',                                10, 'lobo', 'Lobo SKU: Fuerte 1g'),
  ('sauce cannon',  'sauce\s*cann?on|\mcann?on\M',           10, 'lobo', 'Lobo SKU: 3.5g Sauce Cannon'),
  ('stardust',      'stardust',                              10, 'lobo', 'Lobo SKU: 1g Stardust Jar'),
  -- Forms that are specific enough to be unambiguous for anyone.
  ('minis 5pk',     'minis?\M|mini.?s\M',                    20, null, null),
  ('moonrocks',     'moon\s*rocks?',                         20, null, null),
  ('badder',        'badder|budder',                         20, null, null),
  ('hashish',       'hashish|\mhash\M',                      25, null, null),
  ('live rosin',    'live\s*rosin',                          25, null, null),
  ('live resin',    'live\s*resin',                          25, null, null),
  ('diamonds',      '\mdiamonds\M',                          25, null, 'the concentrate, not "diamond infused"'),
  ('shatter',       'shatter',                               25, null, null),
  ('kief',          '\mkief\M',                              25, null, null),
  ('preground',     'pre[\s-]*ground|preground',             30, null, null),
  ('infused preroll','infused\s+pre[\s-]*rolls?',            35, null, null),
  ('blunt',         'blunts?\M',                             40, null, null),
  ('preroll',       'pre[\s-]*rolls?|prerolls?|\mjoints?\M', 40, null, null),
  ('vape',          '\maio\M|all[\s-]in[\s-]one|cart(ridge)?s?\M|\mvape', 40, null, null),
  ('disposable',    'disposable',                            40, null, null),
  ('gummies',       'gummies|gummy',                         40, null, null),
  ('chocolate',     'chocolate',                             40, null, null),
  ('beverage',      'beverage|drink|seltzer|soda|lemonade',   40, null, null),
  ('tincture',      'tincture|\mdrops\M',                    40, null, null),
  ('capsule',       'capsules?|\mcaps\M|softgel',            40, null, null),
  ('topical',       'topical|\mbalm\M|\mlotion\M|\msalve\M', 40, null, null),
  ('jar',           '\mjars?\M',                             50, null, null),
  ('flower',        '\mflower\M|\mbud\M|\msmalls\M|\mshake\M', 55, null, null)
on conflict (label) do nothing;

revoke all on table public.product_forms from anon, authenticated;
alter table public.product_forms enable row level security;
