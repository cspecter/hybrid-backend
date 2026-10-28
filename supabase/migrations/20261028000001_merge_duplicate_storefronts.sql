-- Merge eleven shops that are in the locations table twice.
--
-- Same shape as the White Plains merge of 2026-10-27, and the same cause. The
-- Lit Alerts crawler created a row on 2026-09-26 whenever it could not match a
-- listing to an existing location. Often it could not, and the result is a pair:
-- a 2024 row from the licence register holding the banner, the opening hours,
-- the written description and the coordinates, and a 2026 row holding the menu.
-- A page with no menu, and a menu with no page. Around a thousand owners are
-- being invited to come and look at their page, so the pairs get settled first.
--
-- menu_items_raw.location_id is ON DELETE SET NULL. Deleting the crawler row
-- first does not delete its menu, it orphans it: the items vanish from the app
-- and stop being traceable to the shop they were scraped from. There are already
-- 80,856 rows in that state from earlier deletions. The menu moves first.
--
-- feed_retailer_map is repointed too, so the next crawl updates the surviving
-- row instead of rebuilding the duplicate. Its key is retailer_name, so a
-- surviving row simply ends up with two feed names pointing at it, which is
-- what a merged store is.
--
-- Only pairs confirmed on two independent signals are here: an identical street
-- address, plus either a matching OCM licence or a matching trading name. Five
-- groups that matched on one signal are deliberately left alone, because each
-- asks a question the data cannot answer:
--
--   Herbal IQ Depew (181) / Herbal I.Q. - Depew (1875) -- one licence,
--     OCM-CAURD-23-000018, but 6055 Transit Rd against 6300 Transit Rd. One
--     shop, so a merge is right, but one of the two addresses is wrong and
--     merging would silently pick a map pin. Ask the shop.
--   CONBUD (186, 266, 1729) -- 186 and 266 are both 85 Delancey St on licence
--     OCM-CAURD-23-000021, yet 266 is named "CONBUD Bronx". Either the Bronx
--     branch was given the Manhattan address, or there is no Bronx branch.
--   ESH (1781, 1782) -- "ESH - Jamaica" and "ESH - Rosedale", one licence,
--     both at 90-67 Sutphin Blvd, which is in Jamaica. Two shops with one
--     address copied across, or one shop entered twice.
--   Treehouse (217, 2182, 2208) -- three rows at 28 Route 59 on licence
--     OCM-CAURD-24-000122, one of them named "The Next Chapter Market".
--     A rebrand needs someone to say which name is current.
--   Misha's Flower Shop (262) / The THC Shop - Brooklyn (2192) -- one licence,
--     one address, unrelated names, and 3,495 menu items against 462. A
--     rebrand or a licence transfer; either way not a machine's call.

begin;

create temporary table _pairs (keep_name text, keep_addr text,
                               drop_name text, drop_addr text) on commit drop;
insert into _pairs values
  ('ZenZest Staten Island',               '2343 Forest Ave Staten Island, NY',
   'ZenZest - Staten Island',             '2343 Forest Ave'),
  ('SESH NYC Bronx',                      '4219 Webster Avenue Bronx, NY',
   'Sesh - Bronx',                        '4219 Webster Ave'),
  ('Hibernica',                           '3220 Westchester Avenue Pelham Bay, Bronx, NY',
   'Hibernica - Bronx',                   '3220 Westchester Ave'),
  ('The Cannabist Deptford',              '1692 Clements Bridge Rd, Deptford, NJ',
   'Cannabist - Deptford',                '1692 Clements Bridge Rd'),
  ('Bronx Joint Bronx',                   '925 Hunts Point  Ave Bronx, NY',
   'The Bronx Joint',                     '925 Hunts Point Ave'),
  ('The Apothecarium Dispensary of Phillipsburg', '55 S Main St',
   'Apothecarium - Phillipsburg',         '55 S Main St'),
  ('The Apothecarium Dispensary of Maplewood',    '1865 Springfield Ave',
   'Apothecarium - Maplewood',            '1865 Springfield Ave'),
  ('The Apothecarium Dispensary of Lodi',         '200 NJ-17',
   'Apothecarium - Lodi',                 '200 NJ-17'),
  ('Dagmar Cannabis New York',            '412 W Broadway SoHo, NY',
   'Dagmar Cannabis - SOHO',              '412 W Broadway'),
  ('VERDI',                               '158 W 23RD STREET NEW YORK, NY',
   'Verdi - Chelsea',                     '158 W 23rd St'),
  ('The Cannabis Place Middle Village',   '74-03 Metropolitan Ave Queens, NY',
   'The Cannabis Place',                  '74-03 Metropolitan Ave');

-- Resolve names to ids here rather than writing ids into the file: ids are
-- assigned at seed time, so a literal id means something different in any
-- database where the numbering differs.
create temporary table _merge on commit drop as
select p.keep_name, p.drop_name,
       (select l.id from public.locations l
         where l.name = p.keep_name and l.address_line1 = p.keep_addr) as keep_id,
       (select l.id from public.locations l
         where l.name = p.drop_name and l.address_line1 = p.drop_addr) as drop_id
  from _pairs p;

-- Stop rather than guess. A name that no longer resolves, resolves twice, or
-- resolves to the row it is being merged into means the table has moved on
-- since this was written, and the statements below would act on a situation
-- nobody has looked at. A sub-select returning two rows raises on its own;
-- these checks cover the rest.
do $$
declare bad text;
begin
  select string_agg(format('%s -> %s (keep=%s drop=%s)',
                           drop_name, keep_name, keep_id, drop_id), '; ')
    into bad
    from _merge
   where keep_id is null or drop_id is null or keep_id = drop_id;
  if bad is not null then
    raise exception 'merge-duplicate-storefronts: unresolved or self-referential '
                    'pairs: %. Already merged, or the data changed -- look '
                    'before re-running.', bad;
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

-- Release the licence before the delete, so nothing downstream can briefly see
-- two locations claiming one licence number.
update public.locations l
   set ocm_license_number = null
  from _merge m
 where l.id = m.drop_id;

delete from public.locations l
 using _merge m
 where l.id = m.drop_id;

commit;
