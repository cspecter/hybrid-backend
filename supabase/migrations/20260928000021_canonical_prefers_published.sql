-- Order published ahead of having a picture.
--
-- The previous order preferred a row with a photograph, so a draft with an image beat a
-- published row without one and became the survivor. That hid live products behind rows
-- the app does not show: 9,468 published products collapsed to 7,045, which is more
-- products than there are duplicates. A published row must never disappear behind a draft.
create or replace view public.v_product_canonical as
  select distinct on (r.canonical_key)
         r.canonical_key,
         p.id   as canonical_product_id,
         p.name as canonical_name
  from v_identity_resolved r
  join products p on p.id = r.product_id
  order by r.canonical_key,
           (p.status = 'published') desc,
           (p.thumbnail_id is not null or p.gallery_urls is not null) desc,
           length(coalesce(p.name, '')) desc,
           p.id;

comment on view public.v_product_canonical is
  'The one product row that represents each identity: published first so nothing live is hidden behind a draft, then a picture, then the fullest name, then the oldest id so the choice does not move between runs.';
