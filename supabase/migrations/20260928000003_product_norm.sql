-- Read a menu name into the product underneath it.
--
-- Four questions, asked of every product: whose is it, what format, what material,
-- what strain, what size. Two products with the same five answers are the same product,
-- however differently the two shops wrote it down.
--
-- The work is set-based and lands in a table. Calling a per-row function across an
-- unindexed set has timed out on this database three times; precomputing once and
-- indexing the result is the shape that holds.

-- ---------------------------------------------------------------- cleaning

create or replace function public.norm_clean(p_text text) returns text
language plpgsql immutable as $$
declare s text := lower(coalesce(p_text, ''));
begin
  -- Apostrophes join rather than separate: Jack'd -> jackd, Smoker's -> smokers.
  s := regexp_replace(s, '[''’`´]', '', 'g');
  -- A letter o standing in for a zero. Shops type "o.5g" often enough to matter.
  s := regexp_replace(s, '\mo(\.\d)', '0\1', 'g');
  -- Fractions and words for weight, resolved to grams before "/" is stripped.
  s := regexp_replace(s, '\m1\s*/\s*8\M|\meighth\M',                ' 3.5g ', 'g');
  s := regexp_replace(s, '\m1\s*/\s*4\M|\mquarter\M|\mquad\M',      ' 7g ',   'g');
  s := regexp_replace(s, '\m1\s*/\s*2\M|\mhalf\s*(oz|ounce)s?\M',   ' 14g ',  'g');
  s := regexp_replace(s, '\m(1\s*)?(oz|ounce)s?\M(?!\s*\d)',        ' 28g ',  'g');
  s := regexp_replace(s, 'full\s*gram',                             ' 1g ',   'g');
  -- Everything that only ever separates. "." and "/" survive inside numbers,
  -- "-" survives so that "5-pack" and "pre-roll" still read.
  s := regexp_replace(s, '[|\[\]()<>{}“”"*#!?:;,_~®™©@&+]', ' ', 'g');
  s := regexp_replace(s, '\.(?!\d)|(?<!\d)\.', ' ', 'g');
  s := regexp_replace(s, '/(?![\d])|(?<![\d])/', ' ', 'g');
  return trim(regexp_replace(s, '\s+', ' ', 'g'));
end $$;

comment on function public.norm_clean(text) is
  'Lowercase a menu name and resolve the spellings that vary shop to shop: apostrophes, o-for-zero, weight fractions, separator punctuation.';

-- ---------------------------------------------------------------- size

create type public.norm_size_t as (grams numeric, mg numeric, oz numeric, pack integer);

create or replace function public.norm_size(p_clean text) returns public.norm_size_t
language plpgsql immutable as $$
declare
  r public.norm_size_t;
  m text[];
  lo numeric; hi numeric;
begin
  m := regexp_match(p_clean, '(\d+)\s*(?:-\s*)?(?:pk\M|packs?\M|ct\M|counts?\M|-\s*p\M)');
  if m is not null and (m[1])::numeric between 2 and 100 then
    r.pack := (m[1])::int;
  end if;

  select min(v), max(v) into lo, hi
  from (select (x[1])::numeric as v
        from regexp_matches(p_clean, '(\d*\.?\d+)\s*(?:g|gr|gm|grams?)\M', 'g') x) z
  where v > 0 and v <= 500;

  -- One shop lists the weight of a single pre-roll, the next lists the weight of the
  -- box. Both are describing the same product, so the identity uses the box: the
  -- per-unit figure times the pack count, or the largest figure stated, whichever
  -- is bigger. A figure over 1.5g is already a package weight, not one pre-roll.
  if hi is not null then
    r.grams := hi;
    if r.pack is not null and lo <= 1.5 then
      r.grams := greatest(hi, lo * r.pack);
    end if;
  end if;

  select max((x[1])::numeric) into r.mg
  from regexp_matches(p_clean, '(\d*\.?\d+)\s*mg\M', 'g') x;

  select max((x[1])::numeric) into r.oz
  from regexp_matches(p_clean, '(\d*\.?\d+)\s*(?:fl\s*)?oz\M', 'g') x;

  return r;
end $$;

comment on function public.norm_size(text) is
  'Pull grams, milligrams, fluid ounces and pack count out of a cleaned name. Grams are normalised to the package, so 0.5g x 5pk and 2.5g agree.';

-- ---------------------------------------------------------------- residue

create or replace function public.norm_strip_sizes(p_clean text) returns text
language sql immutable as $$
  select trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
    p_clean,
    '\d*\.?\d+\s*(?:g|gr|gm|grams?|mg|mgs?|oz|fl\s*oz|ml|lbs?)\M', ' ', 'g'),
    '\d+\s*(?:-\s*)?(?:pk\M|packs?\M|ct\M|counts?\M|-\s*p\M)',     ' ', 'g'),
    '\m\d+\s*[-x]\s*\d+\M|\m\d{2,}\M',                             ' ', 'g'),
    '\s+', ' ', 'g'));
$$;

create or replace function public.norm_brand_key(p_brand text) returns text
language sql immutable as $$
  select nullif(regexp_replace(norm_clean(p_brand), '[^a-z0-9]+', '', 'g'), '');
$$;

-- Brand names recur inside the item name, spelled out ("Florist Farms | Gorilla Glue")
-- or initialised ("FF - Triangle Cake"). Either way the brand is not the strain.
create or replace function public.norm_strip_brand(p_clean text, p_brand text) returns text
language plpgsql immutable as $$
declare
  s text := p_clean;
  w text;
  initials text := '';
begin
  foreach w in array regexp_split_to_array(norm_clean(p_brand), '\s+') loop
    if length(w) >= 1 then initials := initials || left(w, 1); end if;
    if length(w) >= 3 then
      s := regexp_replace(s, '\m' || regexp_replace(w, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\M', ' ', 'g');
    end if;
  end loop;
  if length(initials) between 2 and 4 then
    s := regexp_replace(s, '\m' || initials || '\M', ' ', 'g');
  end if;
  return trim(regexp_replace(s, '\s+', ' ', 'g'));
end $$;

-- ---------------------------------------------------------------- the table

create table if not exists public.product_norm (
  product_id     bigint primary key references public.products(id) on delete cascade,
  brand_key      text,
  format         text,
  material       text,
  strain         text,        -- as written, for display
  strain_key     text,        -- tokens sorted, for matching
  grams          numeric(10,2),
  mg             numeric(10,2),
  oz             numeric(10,2),
  pack           integer,
  identity_key   text,
  computed_at    timestamptz not null default now()
);

create index if not exists product_norm_identity_idx on public.product_norm (identity_key);
create index if not exists product_norm_brand_idx    on public.product_norm (brand_key);
create index if not exists product_norm_strain_idx   on public.product_norm (strain_key);

comment on table public.product_norm is
  'One row per product: the brand, format, material, strain and size read out of its name, plus the identity key that products sharing a real-world identity agree on.';

revoke all on table public.product_norm from anon, authenticated;
alter table public.product_norm enable row level security;
