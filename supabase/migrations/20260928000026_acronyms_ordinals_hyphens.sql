-- Four flaws that combined to give two unrelated Old Pal strains the same identity.
-- "1/8th - Indica - U.F.O.G." and "1/8th - Sativa - Honeycomb" both came out keyed on
-- the string "1/8th", having lost their actual strains along the way.
--
--   An acronym strain was shredded. U.F.O.G. became "u f o g", and single letters are
--   dropped, so nothing of the strain survived. GG4, MAC and GMO are written this way too.
--
--   "1/8th" is not "1/8". The fraction rule demanded a word boundary straight after the
--   8, which "th" is not, so the weight was never resolved and the text itself became
--   the strain -- the same text for every product written that way.
--
--   Hyphen-delimited names leave hyphen debris. "Pre-Roll-Indica-U.F.O.G." reduces to
--   "-u" once the format and strain-type words are struck out of the middle of it.
--
--   "honeycomb" was a word for crumble, and it is also Old Pal's strain. A texture that
--   niche does not get to eat a strain name.

create or replace function public.norm_clean(p_text text) returns text
language plpgsql immutable as $$
declare s text := lower(coalesce(p_text, ''));
begin
  -- Apostrophes join rather than separate: Jack'd -> jackd, Smoker's -> smokers.
  s := regexp_replace(s, '[''’`´]', '', 'g');
  -- An initialism keeps its letters together: u.f.o.g. -> ufog, g.m.o. -> gmo. Only a
  -- dot between two letters closes up, so 0.5 and "St. Ides" are untouched.
  s := regexp_replace(s, '([a-z])\.(?=[a-z])', '\1', 'g');
  -- A letter o standing in for a zero. Shops type "o.5g" often enough to matter.
  s := regexp_replace(s, '\mo(\.\d)', '0\1', 'g');
  -- A marked phenotype number, kept as a word so later passes cannot mistake it
  -- for a weight or a count.
  s := regexp_replace(s, '#\s*(\d+)', ' no\1 ', 'g');
  -- CBD:THC ratios, before the colon is treated as punctuation.
  s := regexp_replace(s, '(\d+)\s*:\s*(\d+)', '\1to\2', 'g');
  -- Fractions and words for weight, resolved to grams before "/" is stripped. The
  -- ordinal suffix is optional because shops write both "1/8" and "1/8th".
  s := regexp_replace(s, '\m1\s*/\s*8(\s*th)?\M|\meighths?\M',          ' 3.5g ', 'g');
  s := regexp_replace(s, '\m1\s*/\s*4(\s*th)?\M|\mquarters?\M|\mquad\M',' 7g ',   'g');
  s := regexp_replace(s, '\m1\s*/\s*2(\s*nd)?\M|\mhalf\s*(oz|ounce)s?\M',' 14g ', 'g');
  s := regexp_replace(s, '\m(1\s*)?(oz|ounce)s?\M(?!\s*\d)',            ' 28g ',  'g');
  s := regexp_replace(s, 'full\s*gram',                                 ' 1g ',   'g');
  -- Everything that only ever separates. "." and "/" survive inside numbers.
  s := regexp_replace(s, '[|\[\]()<>{}“”"*#!?:;,_~®™©@&+]', ' ', 'g');
  s := regexp_replace(s, '\.(?!\d)|(?<!\d)\.', ' ', 'g');
  s := regexp_replace(s, '/(?![\d])|(?<![\d])/', ' ', 'g');
  -- A hyphen joining two characters belongs to the word; one against a space does not.
  s := regexp_replace(s, '(?<![a-z0-9])-|-(?![a-z0-9])', ' ', 'g');
  return trim(regexp_replace(s, '\s+', ' ', 'g'));
end $$;

update public.product_terms
   set pattern = 'crumble'
 where kind = 'material' and label = 'crumble';

-- Strip hyphens off the ends of tokens. A name delimited entirely by hyphens leaves them
-- stranded once the words between them are struck out.
create or replace function public.norm_strain_key(p_resid text) returns text
language sql immutable
set search_path = public
as $$
  select nullif((
    select string_agg(t, ' ' order by t)
    from (
      select distinct
        -- Fold a trailing s or z, so "Pop Rockz"/"Pop Rocks" and "donut"/"donuts" agree.
        -- Applied only from five characters up, to leave short strain words (gas, kush,
        -- haze, soap) alone.
        case when length(bare) >= 5 and right(bare, 1) in ('s', 'z')
             then left(bare, length(bare) - 1) else bare end as t
      from (
        select trim(both '-' from tok) as bare
        from unnest(regexp_split_to_array(coalesce(p_resid, ''), ' ')) as u(tok)
      ) w
      where length(bare) > 1
        and bare ~ '[a-z]'          -- drop bare numbers and stray punctuation
    ) z
  ), '');
$$;

comment on function public.norm_strain_key(text) is
  'Turn a strain residue into a matching key: hyphens trimmed off token ends, tokens deduplicated, trailing s/z folded, bare numbers dropped, sorted so word order stops mattering.';
