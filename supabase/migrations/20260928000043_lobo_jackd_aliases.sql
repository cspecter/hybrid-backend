-- Jack'd Sour D is one SKU: Lobo's 3.5g Sauce Cannon, whose strain the New York sheet
-- records as Sour Diesel. Shops write it eight ways, and several of those names carry a
-- second strain -- Jelly Donut, Donut Hole -- which is exactly why no rule over names could
-- merge them without also merging things that are genuinely different.
insert into public.brand_catalogue_alias (catalogue_id, alias_text, note)
select c.id, v.alias, 'confirmed by the brand: all one SKU'
from public.brand_catalogue c
cross join (values
  ('Jack''d Sour D'),
  ('Jack''d Sour D Cannon'),
  ('Jack''d Sour D x Jelly Donut'),
  ('Sour D x Jelly Donutz'),
  ('Jack''d Sour D Donut Hole')
) as v(alias)
where c.brand_key = 'lobo' and c.sku_label = '3.5g Sauce Cannon' and c.strain = 'Sour Diesel'
on conflict (catalogue_id, alias_text) do nothing;
