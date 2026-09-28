-- Stop shipping import bookkeeping to every phone that opens the app.
--
-- fetchProducts pulls every published product once per session — 9,427 rows, about
-- 6.9 MB. Measured, 1,216 kB of that is products.attributes, and trimmed to the three
-- keys the app actually reads (thc, strain, weight) the same column is 18 kB.
--
-- The rest is mine: feed_key, store_count, price_min, price_max, promoted_by, brand,
-- size, cbd — things the promotion functions need and the client never looks at. I
-- put them in attributes because it was convenient at write time, which is the wrong
-- place to optimise for when the column is downloaded whole by every user.
--
-- They move to feed_meta, which nothing client-facing selects. Roughly 1.2 MB off
-- every app load, about 17%, for no change in what anyone sees.
alter table public.products add column if not exists feed_meta jsonb;

update public.products
   set feed_meta = attributes,
       attributes = attributes - 'feed_key' - 'store_count' - 'price_min' - 'price_max'
                               - 'promoted_by' - 'brand' - 'size' - 'cbd'
 where source = 'litalerts' and feed_meta is null;

-- brand and size were in attributes only to be read back by link_product_brands and
-- the name resolver; cached_brand_names carries the brand for display and the size is
-- already in the description.
create index if not exists products_feed_meta_key_idx
  on public.products ((feed_meta->>'feed_key')) where source = 'litalerts';
drop index if exists products_feed_key_idx;
