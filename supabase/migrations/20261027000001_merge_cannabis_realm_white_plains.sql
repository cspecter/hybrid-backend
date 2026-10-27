-- Give 475 Central Ave one page instead of two.
--
-- White Plains is in the locations table twice. One row came from the state
-- licence register in 2024 and is the page a customer sees: a banner, opening
-- hours, a description the shop wrote, and coordinates that put it on the map.
-- The other was created by the Lit Alerts crawler on 2026-09-26, still carries
-- the placeholder description "Draft until reviewed", has no coordinates at
-- all -- and holds every one of the 1,957 menu items.
--
-- So the shop has a page with no menu and a menu with no page, and its owner
-- is about to be emailed and invited to come and claim one of them.
--
-- The crawler had what it needed to match the two: both rows carry the same
-- licence, OCM-CAURD-24-000046. It recorded created-from-feed regardless. That
-- matcher is not fixed here, and it has left at least six more pairs in the
-- same state; this settles the one store being onboarded this week.
--
-- Note what the obvious fix would have done. menu_items_raw.location_id is
-- ON DELETE SET NULL, so deleting the crawler row on its own does not remove
-- 1,957 rows -- it leaves them pointing at nothing. The menu would vanish from
-- the app while the rows sat in the table, no longer traceable to the shop
-- they were scraped from. The menu moves first, and the delete happens last.

begin;

-- Identify the pair by licence and by how each row got here, never by id:
-- ids are not stable across environments, and a plain id would happily point
-- at some unrelated row in a database where the numbering differs.
create temporary table _merge on commit drop as
select
  (select l.id
     from public.locations l
     left join public.feed_retailer_map m on m.location_id = l.id
    where l.ocm_license_number = 'OCM-CAURD-24-000046'
      and m.location_id is null) as keep_id,
  (select l.id
     from public.locations l
     join public.feed_retailer_map m
       on m.location_id = l.id and m.matched_on = 'created-from-feed'
    where l.ocm_license_number = 'OCM-CAURD-24-000046') as drop_id;

-- Stop rather than guess. If the rows have already been merged, or a third
-- row has appeared under this licence, the statements below would act on a
-- situation nobody looked at.
do $$
declare k integer; d integer;
begin
  select keep_id, drop_id into k, d from _merge;
  if k is null or d is null then
    raise exception
      'merge-cannabis-realm: expected one register row and one feed row for '
      'OCM-CAURD-24-000046, found keep=% drop=%. Already merged, or the data '
      'has changed since this was written -- look before re-running.', k, d;
  end if;
end $$;

-- The menu. 1,957 rows, and nothing on the surviving row to collide with:
-- menu_items_raw is keyed only on its own id and the register row has no
-- menu items of its own.
update public.menu_items_raw mi
   set location_id = m.keep_id
  from _merge m
 where mi.location_id = m.drop_id;

-- The feed mapping, so the next crawl lands on the surviving row instead of
-- creating the duplicate again. Keyed on retailer_name, which the survivor
-- has no row for, so repointing cannot collide either.
update public.feed_retailer_map f
   set location_id = m.keep_id
  from _merge m
 where f.location_id = m.drop_id;

-- The crawler row carried the licence number too. Release it before the
-- delete so nothing downstream can match two locations to one licence in the
-- window between the statements.
update public.locations l
   set ocm_license_number = null
  from _merge m
 where l.id = m.drop_id;

delete from public.locations l
 using _merge m
 where l.id = m.drop_id;

commit;
