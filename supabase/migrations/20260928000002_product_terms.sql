-- Vocabulary for reading a menu name.
--
-- A shop types a brand's product however it likes. "Florist Farms | Gorilla Glue | AIO | 1g",
-- "FF - Triangle Cake - 0.5g Cured Resin Cartridge", "*MANGO HAZE - 1.5 G". Underneath,
-- a product is a brand's particular thing: a format, made of a material, in a strain, at a size.
-- Recovering those four lets 500,000 spellings collapse onto the products that actually exist.
--
-- Supersedes product_forms, which folded format and material into one priority-ordered list.
-- That could not tell a Cured Resin Cartridge from a Live Resin Cartridge -- two real, distinct
-- SKUs -- and needed per-brand rows to stop a material word outranking a format word. Two axes
-- need two vocabularies.
drop table if exists public.product_forms;

create table if not exists public.product_terms (
  id       serial primary key,
  kind     text not null check (kind in ('format','material','noise')),
  label    text,                      -- canonical value; null for noise, which is only ever deleted
  pattern  text not null,             -- case-insensitive regex, matched against the cleaned name
  priority integer not null default 50,
  note     text,
  unique (kind, label, pattern)
);

create index if not exists product_terms_kind_priority_idx on public.product_terms (kind, priority);

comment on table public.product_terms is
  'Regex vocabulary for parsing menu names into (format, material, strain, size). kind=format is the shape you buy, kind=material is what it is made of, kind=noise is deleted before the strain residue is read.';

-- FORMATS -- the shape you buy. Lower priority wins when several match, so that the
-- more specific format takes the name: a "Live Resin Cartridge" is a cartridge, and
-- an "infused pre-roll" is not merely a pre-roll.
insert into public.product_terms (kind, label, pattern, priority, note) values
  ('format','disposable',  'disposable|\mdispo\M',                                  10, null),
  ('format','aio',         '\maio\M|all[\s-]?in[\s-]?one',                          10, 'one-piece battery + oil'),
  ('format','cartridge',   'cart(ridge)?s?\M|\m510\M|\mpod\M|\mvape\M|\mpen\M',     20, null),
  ('format','cannagar',    'cannagar|\mgar\M',                                      20, null),
  ('format','infused preroll','infused[\s-]*(pre[\s-]*roll|joint|cone)s?',          20, null),
  ('format','minis',       'minis?\M|\mmini[\s-]',                                  25, 'small multi-pack pre-rolls'),
  ('format','preroll',     'pre[\s-]*roll?s?\M|\mjoints?\M|\mcones?\M|dogwalker',   30, null),
  ('format','blunt',       'blunts?\M',                                             30, null),
  ('format','moonrocks',   'moon[\s-]*rocks?',                                      30, null),
  ('format','popcorn',     'popcorn|\msmalls?\M',                                   35, null),
  ('format','shake',       '\mshake\M|\mtrim\M',                                    35, null),
  ('format','gummies',     'gumm(y|ies)|\mchews?\M|fruit\s*chews',                  40, null),
  ('format','chocolate',   'chocolates?|\mtruffles?\M',                             40, null),
  ('format','beverage',    'beverage|\mdrink|seltzer|\msoda\M|lemonade|\mjuice\M|\mshot\M', 40, null),
  ('format','syrup',       '\msyrup\M',                                             40, null),
  ('format','mints',       '\mmints?\M|lozenges?|\mtabs?\M|\mtablets?\M',           40, null),
  ('format','baked',       'cookies?\M|brownies?\M|\mbar\M|caramels?|\mtaffy\M|\mkrispy\M', 40, null),
  ('format','capsule',     'capsules?|\mcaps\M|softgels?',                          40, null),
  ('format','tincture',    'tincture|\mdrops\M|sublingual',                         40, null),
  ('format','topical',     'topical|\mbalm\M|\mlotion\M|\msalve\M|\mpatch\M|\mbath\M|\mcream\M|\mroll[\s-]?on\M', 40, null),
  ('format','jar',         '\mjars?\M',                                             60, 'weak: a jar of what matters more'),
  ('format','flower',      '\mflower\M|\mbuds?\M|\mnugs?\M',                        65, null)
on conflict do nothing;

-- MATERIALS -- what it is made of. Independent of format, and part of the identity:
-- a cured resin cart and a live resin cart are different products.
insert into public.product_terms (kind, label, pattern, priority, note) values
  ('material','live rosin',   'live\s*rosin',                          10, null),
  ('material','live resin',   'live\s*resin|\mlr\M',                   10, null),
  ('material','cured resin',  'cured\s*resin',                         10, null),
  ('material','rosin',        '\mrosin\M',                             20, null),
  ('material','resin',        '\mresin\M',                             25, null),
  ('material','badder',       'ba[dt]der|budder|\mbatter\M',           20, null),
  ('material','sugar',        '\msugar\M',                             20, null),
  ('material','sauce',        '\msauce\M',                             20, null),
  ('material','diamonds',     '\mdiamonds?\M|\mthca?\s*diamonds?',     20, null),
  ('material','crumble',      'crumble|\mhoneycomb\M',                 20, null),
  ('material','shatter',      'shatter|\mglass\M(?!\s*tip)',           20, null),
  ('material','wax',          '\mwax\M',                               25, null),
  ('material','kief',         '\mkief\M|\mdry\s*sift',                 20, null),
  ('material','hashish',      'hashish|\mhash\M|temple\s*ball',        20, null),
  ('material','distillate',   'distillate|\mdisti\M',                  25, null),
  ('material','rso',          '\mrso\M|full\s*extract',                20, null),
  ('material','preground',    'pre[\s-]*ground|preground',             30, null),
  ('material','infused',      'infused|\minfusion\M',                  45, 'weakest: flower plus something')
on conflict do nothing;

-- NOISE -- deleted before the strain residue is read. Marketing, hardware, packaging,
-- potency and grow-method words that vary shop to shop and are not part of the identity.
insert into public.product_terms (kind, label, pattern, priority, note) values
  ('noise', null, 'premium|exotic|boutique|craft|artisan|small\s*batch|top\s*shelf|reserve', 50, 'marketing'),
  ('noise', null, '\mbold\M|\mglass\s*tip\M|glasstip|\mtip\M|\mceramic\M|\mrechargeable\M', 50, 'hardware'),
  ('noise', null, 'indoor|outdoor|greenhouse|light\s*deps?\M|\mdeps?\M|sun\s*grown|sungrown|hydro(ponic)?\M', 50, 'grow method'),
  ('noise', null, 'sativa|indica|hybrid|ruderalis|dominant|\mdom\M|\mstrain\M|\mstrains\M', 50, 'strain type'),
  ('noise', null, '\mthca?\M|\mcbda?\M|\mcbn\M|\mcbg\M|\mcbc\M|\mthcv\M|delta[\s-]?\d+|\d+\s*%', 50, 'cannabinoids'),
  ('noise', null, '\mnet\s*wt\M|\mwt\M|\meach\M|\mea\M|\msingle?s?\M|\mtotal\M|\mper\M', 50, 'packaging'),
  ('noise', null, '\mnew\M|\msale\M|\mspecial\M|\mdeal\M|\bclearance\M|\mlimited\M|\mseasonal\M', 50, 'promo'),
  ('noise', null, '\mcdt\M|\mbdt\M|botanical|cannabis[\s-]?derived|terpenes?\M|\mterps?\M', 50, 'terpene source'),
  ('noise', null, '\mcannabis\M|\mmarijuana\M|\mweed\M|\mflwr\M|\mproduct\M|\mitem\M', 50, 'generic'),
  ('noise', null, '\mny\M|\mnj\M|\bnew\s*york\M|new\s*jersey', 50, 'state markers'),
  ('noise', null, 'flavor\s*series|\mseries\M|\medition\M|\mcollection\M|\mline\M',  50, 'range naming'),
  ('noise', null, '\mfull\M(?=\s*gram)|\mapprox\M|\mnla\M|\mtest\M|\msample\M',      50, null)
on conflict do nothing;

revoke all on table public.product_terms from anon, authenticated;
alter table public.product_terms enable row level security;
