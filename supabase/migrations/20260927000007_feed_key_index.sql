-- Make the listing-to-product join indexable.
--
-- Both promotions finish by pointing each listing at the product it became, matching
-- on a key computed on the fly on both sides:
--
--   pr.attributes->>'feed_key' = lower(btrim(coalesce(r.brand,'')||'|'||r.name||'|'||coalesce(r.size,'')))
--
-- Nothing can index that, so it is a nested loop over 748,909 listings and thousands
-- of products. It squeaked through the first time and hit the statement timeout on
-- the second, which is the usual trajectory for a query that only works while the
-- table is small.
--
-- The key becomes a stored generated column on the listings and an expression index
-- on the products, so the join has something to use from both sides. Generated
-- because it is derived data that must never drift from the columns it comes from —
-- a trigger or a backfill could.
alter table public.menu_items_raw
  add column if not exists feed_key text
  generated always as (
    lower(btrim(coalesce(brand, '') || '|' || name || '|' || coalesce(size, '')))
  ) stored;

create index if not exists menu_items_raw_feed_key_idx on public.menu_items_raw (feed_key);
create index if not exists products_feed_key_idx on public.products ((attributes->>'feed_key'))
  where source = 'litalerts';

-- Linking is now its own function: it is the slow part, it is worth being able to run
-- on its own after any promotion, and it is idempotent.
create or replace function public.link_listings_to_products()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  update public.menu_items_raw r
     set product_id = pr.id
    from public.products pr
   where pr.source = 'litalerts'
     and pr.attributes->>'feed_key' = r.feed_key
     and r.provider = 'litalerts'
     and r.product_id is null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.link_listings_to_products() from public, anon, authenticated;
