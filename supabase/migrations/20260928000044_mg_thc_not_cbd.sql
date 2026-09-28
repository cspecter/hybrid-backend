-- A dose is the THC figure, not whichever number is largest.
--
-- norm_size took the maximum milligram figure in the name, so "Chill Drops [2pk Pouch]
-- (10mg THC/50mg CBD)" recorded 50mg and sat apart from "*CHILL - 10 MG - 2 PACK", which
-- is the same box. Same for "100mg THC/500mg CBD" against "100 MG". Removing the figures
-- that are explicitly labelled as another cannabinoid leaves the dose.
create or replace function public.norm_size(p_clean text) returns public.norm_size_t
language plpgsql immutable as $$
declare
  r public.norm_size_t;
  m text[];
  lo numeric; hi numeric;
  dose_text text;
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

  -- Drop anything named as a different cannabinoid before reading the dose.
  dose_text := regexp_replace(p_clean, '\d*\.?\d+\s*mg\s*(?:cbd|cbn|cbg|cbc|cbdv|thcv)\M', ' ', 'g');
  select max((x[1])::numeric) into r.mg
  from regexp_matches(dose_text, '(\d*\.?\d+)\s*mg\M', 'g') x;

  select max((x[1])::numeric) into r.ml
  from regexp_matches(p_clean, '(\d*\.?\d+)\s*ml\M', 'g') x;

  select max((x[1])::numeric) into r.oz
  from regexp_matches(p_clean, '(\d*\.?\d+)\s*(?:fl\s*)?oz\M', 'g') x;

  return r;
end $$;
