-- Show dispensaries the name their customers know them by.
--
-- These rows came from licence records, so eighteen of them carry the holding
-- company, the trading name and the town in one string:
--
--   Beechnut Ridge Enterprises LLC (dba The Grass Hole Cannabis) Plattsburgh
--
-- That is what the store page has been showing, and it is what a thousand
-- owners are about to be invited to go and look at. The name inside the (dba)
-- is the one on the shopfront; the town is already in the address beside it.
--
-- The licence name is not thrown away — legal_name keeps it, because it is
-- what matches these rows back to the state register.
--
-- Only the eighteen with an explicit (dba) are touched. Another twenty-nine
-- carry a bare "LLC" or "Inc" with no trading name to fall back on, and
-- stripping the suffix mechanically does more harm than good: it turns
-- "Amsterdam Cannabis, Inc. Amsterdam" into "Amsterdam Cannabis Amsterdam",
-- cuts the "Co" out of "Black Market Canna Co", and leaves "Bliss + Lex
-- (Weedish)" holding an empty bracket. Those need a person, not a regex.

alter table public.locations
  add column if not exists legal_name text;

comment on column public.locations.legal_name is
  'The licensed entity name as it appears on the state register, kept when '
  'name was shortened to the trading name. Null where the two are the same.';

-- Preserve before overwriting, and only for the rows about to change.
update public.locations
   set legal_name = name
 where name ~* '\(d\.?b\.?a\.?\s+[^)]+\)'
   and legal_name is null;

-- "Holdco LLC (dba The Real Name) Town" -> "The Real Name"
--
-- Skipping any rename that would collide: locations_name_unique means a
-- trading name already in use stops the statement dead, and one does —
-- "Geneva Naturals LLC (dba Dryden Dispensary) Dryden" (2207 Dryden Road)
-- against an existing "Dryden Dispensary" (150 W Main St). Two addresses, so
-- either two shops or a duplicated record; that is a question about the data,
-- not something a rename should answer by picking a winner.
update public.locations l
   set name = btrim((regexp_match(l.name, '\(d\.?b\.?a\.?\s+([^)]+)\)', 'i'))[1])
 where l.name ~* '\(d\.?b\.?a\.?\s+[^)]+\)'
   and btrim(coalesce((regexp_match(l.name, '\(d\.?b\.?a\.?\s+([^)]+)\)', 'i'))[1], '')) <> ''
   and not exists (
     select 1 from public.locations other
      where other.id <> l.id
        and lower(btrim(other.name))
            = lower(btrim((regexp_match(l.name, '\(d\.?b\.?a\.?\s+([^)]+)\)', 'i'))[1]))
   );

-- A row that was skipped kept its licence name as its display name, so
-- legal_name holding the same string says nothing. Null it, so the column
-- means what the comment claims: set only where the two differ.
update public.locations
   set legal_name = null
 where legal_name is not null
   and btrim(lower(legal_name)) = btrim(lower(name));
