-- Put the size back where the app reads it.
--
-- Correcting myself: I said moving metadata off attributes had also fixed a bug where
-- the strain never displayed because we wrote "strain_type" and the app reads
-- "strain". The rename was harmless and pointless — the Lit Alerts export carries no
-- strain, THC or CBD at all. Zero of 748,909 listings have any of the three. Nothing
-- was being hidden; there was nothing there.
--
-- What the feed does carry is size, on 684,574 listings, and the app reads
-- attributes.weight. Stripping metadata took 'size' out of attributes along with the
-- genuine bookkeeping, so it now reads back from feed_meta. About 150 kB of
-- attributes for a field that actually renders, against the 1.2 MB of bookkeeping
-- that did not.
update public.products p
   set attributes = jsonb_strip_nulls(
         coalesce(p.attributes, '{}'::jsonb) || jsonb_build_object('weight', p.feed_meta->>'size')),
       updated_at = now()
 where p.source = 'litalerts'
   and p.feed_meta->>'size' is not null
   and coalesce(p.attributes->>'weight', '') = '';
