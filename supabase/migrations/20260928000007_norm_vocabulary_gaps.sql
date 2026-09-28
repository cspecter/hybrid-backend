-- Gaps found by reading the strain residues the first full pass produced.
--
-- Each of these showed up as one real product split across several identities:
--   "blend" / "blend ground" / "blend outs" / "blend inf"   -- one Sativa Blend
--   "marker permanent" / "concentrate marker permanent"     -- one Permanent Marker hash
--   "pop rockz" / "pop rocks", "belts rainbow" / "beltz rainbow"
--   "blue dream" / "blue dream of" / "and blue dream"

-- "concentrate" and "edible" existed only as category fallbacks, with no pattern, so
-- where a shop wrote the word into the name it survived into the strain. Weak priority:
-- any more specific format already won.
insert into public.product_terms (kind, label, pattern, priority, note) values
  ('format','concentrate','\mconcentrates?\M|\mextracts?\M', 70, 'generic; also the category fallback'),
  ('format','edible',     '\medibles?\M',                    70, 'generic; also the category fallback')
on conflict do nothing;

-- Shops write "Infused Ground Flower" as often as "Pre-Ground".
update public.product_terms
   set pattern = 'pre[\s-]*ground|preground|\mground\M'
 where kind = 'material' and label = 'preground';

insert into public.product_terms (kind, label, pattern, priority, note) values
  ('noise', null, '\mhemp\M|\mpowder\M|\mpure\M|\mstyle\M|\mmoroccan\M', 50, 'descriptors'),
  ('noise', null, '\minf\M|\mouts\M|\moutdoors?\M|\mgreen\s*house\M',    50, 'abbreviations'),
  ('noise', null, '\ms-h\M|\mi-h\M|\ms/h\M|\mi/h\M',                     50, 'sativa- and indica-hybrid markers'),
  ('noise', null, '\m(and|or|of|the|with|for|in|on|at|by|to|an|a|x)\M',  50, 'stopwords')
on conflict do nothing;
