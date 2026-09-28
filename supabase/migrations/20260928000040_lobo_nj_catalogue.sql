-- Lobo's New Jersey list: 12 SKUs. Three are also on the New York list, and those rows
-- gain NJ rather than being duplicated, because one product sold in two states is one
-- product. Status in this sheet is typed with zeros for the letter O.
insert into public.brand_catalogue
  (brand_key, sku_label, strain, category, price, in_stock, markets, source_note) values
  ('lobo', 'Bold 1g infused', 'Blue Dream', 'Infused Pre-Roll', 8.00, true, array['NJ'], 'NJ sheet 2026-09-28: In Stock'),
  ('lobo', 'Bold 1g infused', 'Skunk Diesel', 'Infused Pre-Roll', 8.00, true, array['NJ'], 'NJ sheet 2026-09-28: In Stock'),
  ('lobo', '3.5g Snowcaps', 'Wedding Cake', 'Infused Flower', 25.00, true, array['NJ'], 'NJ sheet 2026-09-28: In Stock'),
  ('lobo', '3.5g Moonrocks', 'Zkittlez', 'Infused Flower', 25.00, true, array['NJ'], 'NJ sheet 2026-09-28: In Stock'),
  ('lobo', '3.5g Moonrocks', 'Rainbow Belts', 'Infused Flower', 25.00, true, array['NJ'], 'NJ sheet 2026-09-28: In Stock'),
  ('lobo', '1g Hashish Jar', 'Blue Dream', 'Concentrate', 25.00, true, array['NJ'], 'NJ sheet 2026-09-28: In Stock'),
  ('lobo', '3.5g Moonrocks', 'Tangie Cream', 'Infused Flower', 25.00, false, array['NJ'], 'NJ sheet 2026-09-28: 0UT 0F ST0CK'),
  ('lobo', '4g Preground Infused', 'Sativa Blend', 'Infused Flower', 25.00, false, array['NJ'], 'NJ sheet 2026-09-28: 0UT 0F ST0CK'),
  ('lobo', 'Bold 1g infused', 'Pineapple Express', 'Infused Pre-Roll', 8.00, false, array['NJ'], 'NJ sheet 2026-09-28: 0UT 0F ST0CK'),
  ('lobo', 'Minis 5-pack', 'Pineapple Express', 'Infused Pre-Roll', 16.00, false, array['NJ'], 'NJ sheet 2026-09-28: 0UT 0F ST0CK'),
  ('lobo', 'Minis 5-pack', 'Skunk Diesel', 'Infused Pre-Roll', 16.00, false, array['NJ'], 'NJ sheet 2026-09-28: 0UT 0F ST0CK'),
  ('lobo', 'Minis 5-pack', 'Blue Dream', 'Infused Pre-Roll', 16.00, false, array['NJ'], 'NJ sheet 2026-09-28: 0UT 0F ST0CK')
on conflict (brand_key, sku_label, strain) do update set
  markets     = (select array_agg(distinct m order by m)
                   from unnest(brand_catalogue.markets || excluded.markets) as u(m)),
  in_stock    = brand_catalogue.in_stock or excluded.in_stock,
  source_note = brand_catalogue.source_note || ' | ' || excluded.source_note;
