-- Put real products in the app: the 5,000 most widely carried, live immediately.
--
-- 748,909 listings have been staged since the Lit Alerts import and none has ever
-- reached `products`, which is what the app reads — so the catalogue still ends at
-- 2025-07-07 while 1,012 stores sit published with nothing on their shelves.
--
-- WHY 5,000 AND NOT ALL 370,861. The app fetches every published product on load:
--
--   .eq("status","published").order("stash_count", desc).limit(3000)
--
-- Publishing the full set would mean roughly 185 MB downloaded on every app open, and
-- PostgREST answers an over-limit query with a short list rather than an error, so the
-- symptom would be a product tab that looks fine and is missing 99% of its contents.
-- A capped, ranked subset fits the architecture the app actually has. Store-scoped
-- menus are the real answer and a separate job.
--
-- RANKED BY HOW MANY SHOPS CARRY IT. Store coverage is the best available proxy for
-- "someone might look for this" — a product on 200 menus matters more than a
-- one-off, and 79% of SKUs appear on exactly one menu in the state.
--
-- FRESH ONLY: seen on a menu within 14 days and not flagged out of stock. Half the
-- feed was last seen more than a week ago, and is_available alone cannot be trusted —
-- 18% of rows claim available while unseen for over a month.

-- Kept separate from the 2,206 products already published, so the two populations can
-- always be told apart, counted apart, and unpublished apart.
alter table public.products add column if not exists source text;
create index if not exists products_source_idx on public.products (source) where source is not null;
comment on column public.products.source is
  '''litalerts'' for products promoted from the menu feed. Null for everything that predates it.';

-- Which listing became which product, so a store's shelf can be assembled later.
alter table public.menu_items_raw add column if not exists product_id integer references public.products(id) on delete set null;
create index if not exists menu_items_raw_product_idx on public.menu_items_raw (product_id);

-- Vaporizers is the second largest category in the feed at 123,884 listings and had
-- nowhere to go; Beverages likewise. Without these they would import uncategorised.
insert into public.product_categories (name, slug)
select v.name, v.slug from (values ('Vaporizers','vaporizers'), ('Beverages','beverages')) v(name, slug)
where not exists (select 1 from public.product_categories c where lower(c.name) = lower(v.name));
