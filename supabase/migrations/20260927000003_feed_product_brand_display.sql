-- Make the brand visible on promoted products without inventing 3,889 brand accounts.
--
-- products.cached_brand_names is exactly what its name says: a cache, maintained by a
-- trigger from product_brands, and set to null on insert no matter what is passed in.
-- Verified directly — inserting a product with cached_brand_names = 'ACME BRAND' reads
-- back null immediately afterwards. So all 4,609 promoted products landed brandless
-- even though the feed knows the brand for 98% of listings.
--
-- The proper fix is a product_brands row, but brand_id references profiles: a brand in
-- this app is an account, something that can be claimed, followed and posted from.
-- Creating 3,889 of those from a CSV is a product decision with consequences well
-- beyond a catalogue import, and nobody has asked for it.
--
-- So the brand goes where it can be read without pretending to be an account: into
-- attributes.brand as structured data, and at the front of the description where the
-- app already renders it. Re-derived from the listings each product came from rather
-- than parsed back out of the name, so it keeps the feed's own capitalisation.
with brand_of as (
  select r.product_id,
         mode() within group (order by r.brand) as brand
  from public.menu_items_raw r
  where r.product_id is not null and nullif(btrim(coalesce(r.brand,'')), '') is not null
  group by r.product_id
)
update public.products p
   set attributes  = coalesce(p.attributes, '{}'::jsonb) || jsonb_build_object('brand', b.brand),
       description = nullif(concat_ws(' · ', b.brand, nullif(p.description, '')), ''),
       updated_at  = now()
  from brand_of b
 where p.id = b.product_id
   and p.source = 'litalerts'
   and b.brand is not null
   and coalesce(p.attributes->>'brand', '') = '';
