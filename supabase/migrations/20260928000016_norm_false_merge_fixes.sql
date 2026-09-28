-- Four false merges found by reading the groups the pass produced.

-- 1. "cream" was a topical format word, so "Orange Cream #26 10-Pack Noodle Doinks"
--    became a topical and "Banana Cream x Jealousy" lost Cream out of its strain.
--    Cream is a strain word far more often than it is a moisturiser.
update public.product_terms
   set pattern = 'topical|\mbalm\M|\mlotion\M|\msalve\M|\mpatch\M|\mbath\M|\mroll[\s-]?on\M'
 where kind = 'format' and label = 'topical';

-- 2. "cookies" was a baked format word, so "Cookies N Cream - 1g" became a baked good.
--    Cookies is one of the largest strain families there is.
update public.product_terms
   set pattern = 'brownies?\M|\mbar\M|caramels?|\mtaffy\M|\mkrispy\M|\mrice\s*krispie'
 where kind = 'format' and label = 'baked';

-- 3. "mint" singular is a strain word (Mint Chocolate Chip, Peppermint Cookies).
--    Only the plural reliably names a format.
update public.product_terms
   set pattern = '\mmints\M|lozenges?|\mtabs?\M|\mtablets?\M'
 where kind = 'format' and label = 'mints';

-- 4. A phenotype number is part of the product. 710 Labs sells Grease Bucket #5 and
--    Grease Bucket #9 as separate releases, and dropping the number merged them.
--    Only an explicitly marked number is kept: "#9" becomes the word "no9" and survives,
--    while a bare trailing number stays droppable, because those are usually a size or
--    a count a shop half-wrote ("Sativa Blend | 1").
create or replace function public.norm_clean(p_text text) returns text
language plpgsql immutable as $$
declare s text := lower(coalesce(p_text, ''));
begin
  -- Apostrophes join rather than separate: Jack'd -> jackd, Smoker's -> smokers.
  s := regexp_replace(s, '[''’`´]', '', 'g');
  -- A letter o standing in for a zero. Shops type "o.5g" often enough to matter.
  s := regexp_replace(s, '\mo(\.\d)', '0\1', 'g');
  -- A marked phenotype number, kept as a word so later passes cannot mistake it
  -- for a weight or a count.
  s := regexp_replace(s, '#\s*(\d+)', ' no\1 ', 'g');
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

-- 5. Pack count belongs in the size. A grams figure already absorbs the pack, but
--    "Gelcaps 25mg 40ct" and "Gelcaps 25mg 10ct" are the same dose in different boxes,
--    and without the count they were one product.
create or replace function public.norm_size_key(
  p_grams numeric, p_mg numeric, p_ml numeric, p_oz numeric, p_pack integer
) returns text
language sql immutable as $$
  select case
    -- Grams are already the package total, so the count is spent.
    when p_grams is not null then p_grams::text
    when p_mg    is not null then p_mg::text || 'mg' || coalesce('x' || p_pack, '')
    when p_ml    is not null then p_ml::text || 'ml' || coalesce('x' || p_pack, '')
    when p_oz    is not null then p_oz::text || 'oz' || coalesce('x' || p_pack, '')
    else coalesce('x' || p_pack, '')
  end;
$$;

comment on function public.norm_size_key(numeric, numeric, numeric, numeric, integer) is
  'The size component of an identity: whichever measure this kind of product is sold by, with the pack count where the measure is per-piece.';
