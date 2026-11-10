-- Two brands were each in the catalogue twice, so their products were split
-- across two pages and neither page looked complete.
--
--   Smokiez Edibles (307, 438 products, 2022) kept; Smokiez (3487, 13) merged in.
--   1937 Cannabis   (408,  55 products, 2022) kept; 1937    (5371,  5) merged in.
--
-- Both pairs were confirmed the same brand from their products: 3487's are all
-- SMOKIEZ chews and gummies, 5371's are 1937 flower strains matching 408's
-- "1937 Premium Flower" line. The keeper in each pair is older, has more
-- products and has the followers.
--
-- 1937 Group (41) is left alone. It shares the "1937" string and nothing else:
-- its one product is a KVL International flower ball, and it is a different
-- company.
--
-- Products move by DELETE + INSERT rather than UPDATE on purpose. Both counter
-- triggers on product_brands fire AFTER INSERT OR DELETE and not on UPDATE, so
-- repointing brand_id in place would move the products and leave product_count
-- stale on both profiles. Nothing holds a foreign key to product_brands, so
-- re-creating the rows is safe.

begin;

-- Fail rather than merge the wrong rows if the catalogue has shifted.
do $$
begin
  if (select count(*) from public.product_brands where brand_id = 3487) <> 13
     or (select count(*) from public.product_brands where brand_id = 5371) <> 5 then
    raise exception 'product counts have changed since this merge was written; re-check before running';
  end if;
  if exists (select 1 from public.product_brands a
              where a.brand_id in (3487, 5371)
                and exists (select 1 from public.product_brands b
                             where b.brand_id = case a.brand_id when 3487 then 307 else 408 end
                               and b.product_id = a.product_id)) then
    raise exception 'a product is now on both the keeper and the loser; merging would collide';
  end if;
end $$;

create temp table merged_products on commit drop as
select product_id,
       case brand_id when 3487 then 307 else 408 end as keeper_id,
       is_primary
  from public.product_brands
 where brand_id in (3487, 5371);

delete from public.product_brands where brand_id in (3487, 5371);

insert into public.product_brands (product_id, brand_id, is_primary)
select product_id, keeper_id, is_primary from merged_products;

-- The handle "1937cannabis" was discovered from 5371's website but held back,
-- because the cross-brand rule saw a handle naming "1937 Cannabis" on a brand
-- called "1937". Merged into 408 the names agree, so the row moves to the
-- keeper and the hold is no longer warranted.
update public.social_discovery
   set subject_id = 408
 where subject_type = 'brand' and subject_id = 5371
   and not exists (select 1 from public.social_discovery d2
                    where d2.subject_type = 'brand' and d2.subject_id = 408);

-- 307 already has its own discovery row, so 3487's is redundant once the brand
-- is merged. Its pin was only ever there to hold back a handle on a page that
-- is going away.
delete from public.social_discovery
 where subject_type = 'brand' and subject_id = 3487;

-- The consent record for smokiez.handcrafted was taken against 3487. It follows
-- the surviving brand so the record is not left pointing at a merged-away page.
-- It stays needs_reauth: Instagram removed that account.
update public.instagram_consent
   set subject_id = 307
 where subject_type = 'brand' and subject_id = 3487
   and not exists (select 1 from public.instagram_consent c2
                    where c2.subject_type = 'brand' and c2.subject_id = 307);

commit;
