-- Three more ways one product wore several identities.
--
--   "blend lobo-" -- the brand strip compares whole tokens, and "lobo-" is not "lobo",
--   so the brand survived as part of the strain. A hyphen between two characters is
--   part of a word ("pre-roll", "5-pack"); a hyphen against a space is punctuation.
--
--   "cannon donut jackd jelly sour" / "cannon donuts jelly sour" -- one is plural.
--
--   "blue dream multi-pack" -- packaging.

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
  -- Everything that only ever separates. "." and "/" survive inside numbers.
  s := regexp_replace(s, '[|\[\]()<>{}“”"*#!?:;,_~®™©@&+]', ' ', 'g');
  s := regexp_replace(s, '\.(?!\d)|(?<!\d)\.', ' ', 'g');
  s := regexp_replace(s, '/(?![\d])|(?<![\d])/', ' ', 'g');
  -- A hyphen joining two characters belongs to the word; one against a space does not.
  s := regexp_replace(s, '(?<![a-z0-9])-|-(?![a-z0-9])', ' ', 'g');
  return trim(regexp_replace(s, '\s+', ' ', 'g'));
end $$;

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
        case when length(tok) >= 5 and right(tok, 1) in ('s', 'z')
             then left(tok, length(tok) - 1) else tok end as t
      from unnest(regexp_split_to_array(coalesce(p_resid, ''), ' ')) as u(tok)
      where length(tok) > 1
        and tok ~ '[a-z]'          -- drop bare numbers and stray punctuation
    ) z
  ), '');
$$;

comment on function public.norm_strain_key(text) is
  'Turn a strain residue into a matching key: tokens deduplicated, trailing s/z folded, bare numbers dropped, sorted so word order stops mattering.';

insert into public.product_terms (kind, label, pattern, priority, note) values
  ('noise', null, 'multi[\s-]?packs?|\mvariety\M|\massorted\M|\mmixed\M|\msampler\M', 50, 'packaging')
on conflict do nothing;
