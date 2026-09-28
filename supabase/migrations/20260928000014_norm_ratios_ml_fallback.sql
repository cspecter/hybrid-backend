-- 182 products were merging into each other because their names contain no strain.
--
-- Care By Design's tinctures are the clearest case: "40:1 TINCTURE, 15ML" and
-- "2:1 TINCTURE, 15ML" are different products, but cleaning struck the colon and then
-- dropped the bare numbers, leaving an empty residue -- so every tincture in the range
-- collapsed into one. Three things were missing.

-- A cannabinoid ratio is part of the product's identity, so it has to survive cleaning.
-- Rewritten to "40to1" it stays a single token through every later pass.
create or replace function public.norm_clean(p_text text) returns text
language plpgsql immutable as $$
declare s text := lower(coalesce(p_text, ''));
begin
  -- Apostrophes join rather than separate: Jack'd -> jackd, Smoker's -> smokers.
  s := regexp_replace(s, '[''’`´]', '', 'g');
  -- A letter o standing in for a zero. Shops type "o.5g" often enough to matter.
  s := regexp_replace(s, '\mo(\.\d)', '0\1', 'g');
  -- CBD:THC ratios, before the colon is treated as punctuation.
  s := regexp_replace(s, '(\d+)\s*:\s*(\d+)', '\1to\2', 'g');
  -- Fractions and words for weight, resolved to grams before "/" is stripped.
  s := regexp_replace(s, '\m1\s*/\s*8\M|\meighth\M',                ' 3.5g ', 'g');
  s := regexp_replace(s, '\m1\s*/\s*4\M|\mquarter\M|\mquad\M',      ' 7g ',   'g');
  s := regexp_replace(s, '\m1\s*/\s*2\M|\mhalf\s*(oz|ounce)s?\M',   ' 14g ',  'g');
  s := regexp_replace(s, '\m(1\s*)?(oz|ounce)s?\M(?!\s*\d)',        ' 28g ',  'g');
  s := regexp_replace(s, 'full\s*gram',                             ' 1g ',   'g');
  -- Everything that only ever separates. "." and "/" survive inside numbers.
  s := regexp_replace(s, '[|\[\]()<>{}“”"*#!?:;,_~®™©@&+]', ' ', 'g');
  s := regexp_replace(s, '\.(?!\d)|(?<!\d)\.', ' ', 'g');
  s := regexp_replace(s, '/(?![\d])|(?<![\d])/', ' ', 'g');
  -- A hyphen joining two characters belongs to the word; one against a space does not.
  s := regexp_replace(s, '(?<![a-z0-9])-|-(?![a-z0-9])', ' ', 'g');
  return trim(regexp_replace(s, '\s+', ' ', 'g'));
end $$;

-- Tinctures and drinks are sold by volume, so millilitres are a size like grams.
alter type public.norm_size_t add attribute ml numeric cascade;

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

  select max((x[1])::numeric) into r.ml
  from regexp_matches(p_clean, '(\d*\.?\d+)\s*ml\M', 'g') x;

  select max((x[1])::numeric) into r.oz
  from regexp_matches(p_clean, '(\d*\.?\d+)\s*(?:fl\s*)?oz\M', 'g') x;

  return r;
end $$;

create or replace function public.norm_strip_sizes(p_clean text) returns text
language sql immutable as $$
  select trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
    p_clean,
    '\d*\.?\d+\s*(?:g|gr|gm|grams?|mg|mgs?|ml|mls?|oz|fl\s*oz|lbs?)\M', ' ', 'g'),
    '\d+\s*(?:-\s*)?(?:pk\M|packs?\M|ct\M|counts?\M|-\s*p\M)',          ' ', 'g'),
    '\m\d+\s*[-x]\s*\d+\M|\m\d{2,}\M',                                  ' ', 'g'),
    '\s+', ' ', 'g'));
$$;

alter table public.product_norm add column if not exists ml numeric(10,2);
alter table public.product_norm add column if not exists strain_from_name boolean not null default false;

comment on column public.product_norm.strain_from_name is
  'True when the name left no strain residue and the whole cleaned name stands in for it. Such identities are weak: they merge only with a name written the same way.';

alter table public.product_norm_stage add column if not exists ml numeric(10,2);
