-- One product row to represent each identity.
--
-- Deliberately a view and not a deletion. Twenty-one tables reference products, among
-- them stash, posts_products, bag_items, lists_products and giveaways, so collapsing
-- rows would rewrite records that belong to users. And choosing which row survives
-- chooses the name and the photograph everyone then sees. Both of those want a decision
-- rather than an inference, so the identity is published and nothing is destroyed.
--
-- The survivor is the most complete row: one with a picture first, then published over
-- draft, then the longest name, then the oldest id so the choice is stable between runs.
create or replace view public.v_product_canonical as
  select distinct on (r.canonical_key)
         r.canonical_key,
         p.id   as canonical_product_id,
         p.name as canonical_name
  from v_identity_resolved r
  join products p on p.id = r.product_id
  order by r.canonical_key,
           (p.thumbnail_id is not null or p.gallery_urls is not null) desc,
           (p.status = 'published') desc,
           length(coalesce(p.name, '')) desc,
           p.id;

comment on view public.v_product_canonical is
  'The one product row that represents each identity: picture first, then published, then the fullest name, then the oldest id so the choice does not move between runs.';

-- Every product with the row that stands in for it. duplicate_of is null for the
-- survivor and for anything with no duplicate at all.
create or replace view public.v_product_identity as
  select r.product_id,
         r.identity_key,
         r.canonical_key,
         c.canonical_product_id,
         case when c.canonical_product_id = r.product_id then null
              else c.canonical_product_id end as duplicate_of
  from v_identity_resolved r
  join v_product_canonical c on c.canonical_key = r.canonical_key;

comment on view public.v_product_identity is
  'Every product with the identity it belongs to and the row representing it. duplicate_of names the survivor when this row is a duplicate.';

grant select on public.v_product_canonical, public.v_product_identity to authenticated;
