-- Refinements found by reading all 133 Lobo identities against the 22 SKUs the brand
-- actually sells. Every one of these is general; Lobo is only where they showed up.
--
--   "Lobos - Moonrocks: Blueberry Diesel"   brand written plural, so not stripped
--   "Oreoz x Gelato-Presidente"             hyphen fused two words into one token
--   "WEDDING CAKE SNOW CAPS"                "caps" read as capsules
--   "1g Hashish Jar" / "Hashish"            jar is packaging, not a format
--   "Minis 5pk" / "Infused Pre-Roll 5pk"    same SKU, two formats
--   "Hemp Wrapped Infused Blunt"            "wrapped" left in the strain
--   "Pre Roll Pack Infused"                 bare "pack" left in the strain
--   "STARDUST THC ISO POWDER"               "iso" left in the strain
--   "Permanent Marker Solventless Hash"     "solventless" left in the strain
--   "Purple Punch x ZOAP" / "x SOAP"        z for s at the start of a word

-- A hyphen always separates. Keeping it inside words was meant to protect "pre-roll" and
-- "5-pack", but those patterns already tolerate a space, and the cost was words fusing:
-- "gelato-presidente" became one token no vocabulary could match.
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
  -- Everything that only ever separates, hyphens included. "." and "/" survive inside
  -- numbers so 0.5 and 1/8 still read.
  s := regexp_replace(s, '[|\[\]()<>{}“”"*#!?:;,_~®™©@&+\-]', ' ', 'g');
  s := regexp_replace(s, '\.(?!\d)|(?<!\d)\.', ' ', 'g');
  s := regexp_replace(s, '/(?![\d])|(?<![\d])/', ' ', 'g');
  return trim(regexp_replace(s, '\s+', ' ', 'g'));
end $$;

-- Compare brand words in their folded form, so a shop writing "Lobos" still loses the
-- brand. Without this, "Lobos - Moonrocks: Blueberry Diesel" kept "lobo" in its strain
-- and sat apart from every other Blueberry Diesel moonrock.
create or replace function public.norm_fold(p_token text) returns text
language sql immutable as $$
  select case when length(p_token) >= 5 and right(p_token, 1) in ('s', 'z')
              then left(p_token, length(p_token) - 1) else p_token end;
$$;

comment on function public.norm_fold(text) is
  'Fold a trailing s or z off a token from five characters up, so plurals and z-spellings compare equal.';

create or replace function public.norm_strip_brand(p_clean text, p_brand text) returns text
language sql immutable
set search_path = public
as $$
  with brand as (
    select array_agg(norm_fold(w)) filter (where length(w) >= 3) as words,
           string_agg(left(w, 1), '' order by ord)               as initials
    from unnest(regexp_split_to_array(norm_clean(p_brand), ' ')) with ordinality as u(w, ord)
    where w <> ''
  )
  select coalesce((
    select string_agg(tok, ' ' order by ord)
    from unnest(regexp_split_to_array(p_clean, ' ')) with ordinality as n(tok, ord)
    cross join brand b
    where tok <> ''
      and tok ~ '[a-z0-9]'
      and not (norm_fold(tok) = any(coalesce(b.words, '{}')))
      and not (length(coalesce(b.initials, '')) between 2 and 4 and tok = b.initials)
  ), '');
$$;

-- "caps" is Snow Caps, Cherry Caps, a dozen product lines. Only the full word names a form.
update public.product_terms
   set pattern = 'capsules?|softgels?|\mgelcaps?\M'
 where kind = 'format' and label = 'capsule';

-- A jar is what the product arrives in. "1g Hashish Jar" is a concentrate, and treating
-- jar as a format put it somewhere different from the shop that wrote just "Hashish".
delete from public.product_terms where kind = 'format' and label = 'jar';

-- Minis are pre-rolls, several to a box. As its own format it sat apart from the shop that
-- wrote "Infused Pre-Roll | 5pk" for the identical thing; the pack count already carries
-- what makes it different from a single pre-roll.
delete from public.product_terms where kind = 'format' and label = 'minis';

insert into public.product_terms (kind, label, pattern, priority, note) values
  ('noise', null, '\mjars?\M|\mtins?\M|\mbags?\M|\mpouch\M|\mbottles?\M|\mboxe?s?\M', 50, 'containers'),
  ('noise', null, 'minis?\M|\mmini\M',                                        50, 'size of a pre-roll, not a format'),
  ('noise', null, '\mwrapped?\M|\mwraps?\M|\mtipped?\M|\mcones?\M',            50, 'how it is rolled'),
  ('noise', null, '\mpacks?\M|\mpks?\M|\mcts?\M',                             50, 'bare pack words; a counted pack is read as a size'),
  ('noise', null, '\miso\M|\misolate\M|\msolventless\M|\msolvent\M',           50, 'extraction descriptors'),
  ('noise', null, '\mxl\M|\mxxl\M|\msml\M|\mlg\M|\mreg\M',                     50, 'garment-style sizes')
on conflict do nothing;

-- Fold a leading z to s as well as a trailing one. The z spelling is a branding habit:
-- Zoap and Soap, Zkittlez and Skittles are the same strain written two ways.
create or replace function public.norm_strain_key(p_resid text) returns text
language sql immutable
set search_path = public
as $$
  select nullif((
    select string_agg(t, ' ' order by t)
    from (
      select distinct
        case when length(f) >= 4 and left(f, 1) = 'z' then 's' || right(f, length(f) - 1)
             else f end as t
      from (
        select norm_fold(trim(both '-' from tok)) as f
        from unnest(regexp_split_to_array(coalesce(p_resid, ''), ' ')) as u(tok)
      ) w
      where length(f) > 1 and f ~ '[a-z]'
    ) z
  ), '');
$$;

comment on function public.norm_strain_key(text) is
  'Turn a strain residue into a matching key: tokens deduplicated, a leading or trailing z folded to s, bare numbers dropped, sorted so word order stops mattering.';
