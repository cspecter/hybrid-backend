-- Give every location its state.
--
-- locations.state was empty for all 1,012 rows: the address enrichment filled the street
-- and linked a postal code, but never wrote the state, so a listing could not be tied to a
-- market and catalogue matching had to run against every menu at once.
--
-- The postal code already knows. Every location has one, and postal_codes carries the state,
-- so this is a join rather than new data: 634 New York, 377 New Jersey, and one Cambridge MA
-- test row.
create or replace function public.locations_apply_postal_state() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  update locations l
     set state = pc.state_code
    from postal_codes pc
   where pc.id = l.postal_code_id
     and pc.state_code is not null
     and coalesce(l.state, '') <> pc.state_code;
  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.locations_apply_postal_state() is
  'Fill locations.state from the linked postal code. Re-runnable, and the only writer of that column, so a new location picks up its state on the next run.';

select public.locations_apply_postal_state();

create index if not exists locations_state_idx on public.locations (state);

-- Which markets a product is actually sold in, from the shops that list it. A product with
-- listings in both states belongs to both.
create table if not exists public.product_market (
  product_id bigint primary key references public.products(id) on delete cascade,
  states     text[] not null
);

comment on table public.product_market is
  'The states a product is listed in, taken from the locations of its listings. Used so a New Jersey listing is matched against the New Jersey menu.';

create or replace function public.refresh_product_market() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  truncate product_market;
  insert into product_market (product_id, states)
  select mi.product_id, array_agg(distinct l.state order by l.state)
  from menu_items_raw mi
  join locations l on l.id = mi.location_id
  where mi.product_id is not null and l.state is not null
  group by mi.product_id;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on table public.product_market from anon, authenticated;
alter table public.product_market enable row level security;
revoke all on function public.locations_apply_postal_state() from anon, authenticated;
revoke all on function public.refresh_product_market()       from anon, authenticated;
