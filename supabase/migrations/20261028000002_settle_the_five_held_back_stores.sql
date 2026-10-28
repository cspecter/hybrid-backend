-- Settle the five groups the 2026-10-28 sweep deliberately left alone.
--
-- Each of them matched on one signal and contradicted itself on another, so
-- the sweep stopped and asked. The answers came back, and three of them are
-- facts about the world rather than about this database, so they were checked
-- against the shops' own sites and the state registers before being written
-- here. The sources are named beside each one.
--
--   Herbal IQ Depew -- one shop, two addresses. herbaliq.org and the OCM
--     licensee list both say 6300 Transit Rd, Depew NY 14043, which is the
--     address the crawler found and not the one on the 2024 row. The 2024 row
--     survives, carrying its banner and hours, and takes the right address and
--     a pin to match; 6055 Transit Rd was about three quarters of a mile south.
--
--   CONBUD -- there are three shops, not two: conbud.com lists 85 Delancey St
--     (LES), 2412 Third Ave (Mott Haven) and 898 Gerard Ave (Yankee Stadium).
--     "CONBUD Bronx (Summit Canna)" is Mott Haven, and it was sitting on
--     Delancey Street with a Lower East Side pin and the LES shop's licence,
--     because the feed matched it to the register by name. It gets its own
--     address and pin, and the licence goes back to being held by one row.
--
--   ESH -- one shop at 90-67 Sutphin Blvd, which is in Jamaica. The Rosedale
--     row's menu moves onto the Jamaica row.
--
--   Treehouse -- not a rebrand. Treehouse is in Nyack NY; The Next Chapter
--     Market is a New Jersey shop at 1808 Brielle Ave, Ocean Township NJ
--     07712 (NJ CRC licence record, and njdispo.com, which runs it). It was
--     matched to the New York register and inherited Treehouse's licence,
--     address and state. All three are wrong and all three are corrected.
--
--   Misha's Flower Shop -- stays Misha's, at 299 Knickerbocker Ave Brooklyn.
--     The THC Shop - Brooklyn is the same licence at the same address; its
--     menu moves across.
--
-- Everything else is the sweep's pattern: menu_items_raw.location_id is
-- ON DELETE SET NULL, so the menu moves before the row goes, never after.

begin;

create temporary table _pairs (keep_name text, keep_addr text,
                               drop_name text, drop_addr text) on commit drop;
insert into _pairs values
  ('Herbal IQ Depew',            '6055 Transit Rd, Depew Ny',
   'Herbal I.Q. - Depew',        '6300 Transit Rd'),
  ('CONBUD LLC New York',        '85 Delancey St, New York, NY',
   'CONBUD - LES',               '85 Delancey St'),
  ('ESH - Jamaica ',             '90-67 Sutphin Blvd.',
   'ESH - Rosedale ',            '90-67 Sutphin Blvd.'),
  ('Treehouse Cannabis Nyack',   '28 NY-59, Nyack, NY',
   'Treehouse - Nyack',          '28 Route 59'),
  ('Misha''s Flower Shop Brooklyn', '299 Knickerbocker Avenue, New York',
   'The THC Shop - Brooklyn',       '299 Knickerbocker Ave');

-- Resolved here rather than written as ids, for the same reason as the sweep:
-- ids are assigned at seed time and mean something different anywhere else.
-- Address is part of the key because "28 Route 59" holds two different shops
-- until the last statement in this file, and name alone would pick either.
create temporary table _merge on commit drop as
select p.keep_name, p.drop_name,
       (select l.id from public.locations l
         where l.name = p.keep_name and l.address_line1 = p.keep_addr) as keep_id,
       (select l.id from public.locations l
         where l.name = p.drop_name and l.address_line1 = p.drop_addr) as drop_id
  from _pairs p;

-- The two rows that are corrected in place rather than merged away. Resolved
-- now, before the updates below move the addresses they are found by.
create temporary table _fix on commit drop as
select 'CONBUD Mott Haven'::text as what,
       (select l.id from public.locations l
         where l.name = 'CONBUD Bronx (Summit Canna) Bronx'
           and l.address_line1 = '85 Delancey Street New York, NY') as id,
       '2412 Third Ave, Bronx, NY 10454'::text as addr,
       'NY'::text as st,
       40.808296::double precision as lat,
       -73.930500::double precision as lng
union all
select 'The Next Chapter Market',
       (select l.id from public.locations l
         where l.name = 'The Next Chapter Market'
           and l.address_line1 = '28 Route 59'),
       '1808 Brielle Ave, Ocean Township, NJ 07712',
       'NJ', 40.236167, -74.046952;

-- Stop rather than guess. A row that no longer resolves, or resolves to the
-- row it is being merged into, means the table has moved on since this was
-- written and the statements below would act on a situation nobody has seen.
do $$
declare bad text;
begin
  select string_agg(format('%s -> %s (keep=%s drop=%s)',
                           drop_name, keep_name, keep_id, drop_id), '; ')
    into bad
    from _merge
   where keep_id is null or drop_id is null or keep_id = drop_id;
  if bad is not null then
    raise exception 'settle-held-back-stores: unresolved or self-referential '
                    'pairs: %. Already merged, or the data changed -- look '
                    'before re-running.', bad;
  end if;

  select string_agg(what, '; ') into bad from _fix where id is null;
  if bad is not null then
    raise exception 'settle-held-back-stores: could not find %. Name or '
                    'address changed -- look before re-running.', bad;
  end if;
end $$;

update public.menu_items_raw mi
   set location_id = m.keep_id
  from _merge m
 where mi.location_id = m.drop_id;

update public.feed_retailer_map f
   set location_id = m.keep_id
  from _merge m
 where f.location_id = m.drop_id;

-- Release the licence before the delete, so nothing downstream can briefly
-- see two locations claiming one licence number.
update public.locations l
   set ocm_license_number = null
  from _merge m
 where l.id = m.drop_id;

delete from public.locations l
 using _merge m
 where l.id = m.drop_id;

-- Herbal IQ: the surviving row was holding the wrong one of the two addresses,
-- so its pin was wrong too. Moving the address without moving the pin would
-- leave the page saying one thing and the map showing another.
update public.locations l
   set address_line1 = '6300 Transit Rd, Depew, NY 14043',
       coordinates   = extensions.st_setsrid(
                         extensions.st_makepoint(-78.697526, 42.927183),
                         4326)::extensions.geography
  from _merge m
 where m.keep_name = 'Herbal IQ Depew'
   and l.id = m.keep_id;

-- "ESH - Jamaica " came out of the feed with a trailing space, and it is about
-- to be the name a shop sees on its own claim page. The surviving row is a
-- feed row, so it has never had a pin; it gets one here rather than being the
-- one shop settled today that is still invisible on the map. 90-67 Sutphin
-- Blvd is an exact house match in Jamaica, 11435.
update public.locations l
   set name        = btrim(l.name),
       coordinates = extensions.st_setsrid(
                       extensions.st_makepoint(-73.807560, 40.701220),
                       4326)::extensions.geography
  from _merge m
 where m.keep_name = 'ESH - Jamaica '
   and l.id = m.keep_id;

-- Mott Haven and Ocean Township: a real address, a pin that agrees with it,
-- and no licence, because in both cases the licence on the row belongs to a
-- different shop that is still holding it.
update public.locations l
   set address_line1       = f.addr,
       state               = f.st,
       coordinates         = extensions.st_setsrid(
                               extensions.st_makepoint(f.lng, f.lat),
                               4326)::extensions.geography,
       ocm_license_number  = null
  from _fix f
 where l.id = f.id;

-- Both of those licences were applied by the feed resolver matching a name
-- against the New York register, so clearing them on the location alone would
-- last until the next import. confirmed_by_human is the table's own word for
-- "do not re-decide this one"; the mapping to the location stays, only the
-- borrowed licence goes.
update public.feed_retailer_map
   set ocm_license_number = null,
       confirmed_by_human = true
 where retailer_name in ('CONBUD - Bronx', 'The Next Chapter Market');

commit;
