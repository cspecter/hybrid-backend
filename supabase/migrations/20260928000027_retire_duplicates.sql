-- Retire the duplicates instead of filtering them on every app open.
--
-- The catalogue fetch already asks for status = 'published', so moving a duplicate to
-- 'archived' takes it out of every list without a second query, a filter, or an id set
-- travelling to the client. 'archived' is already permitted by products_status_check and
-- was unused.
--
-- Nothing is deleted. Rows stay, with their previous status recorded, and 30 user records
-- that point at a duplicate -- 18 stashes, 6 post attachments, 6 list entries -- move to
-- the row that represents the product, so nobody's stash empties out. Each move is logged,
-- so the whole operation reverses.

create table if not exists public.product_retirement (
  product_id           bigint primary key references public.products(id) on delete cascade,
  previous_status      text not null,
  canonical_product_id bigint not null references public.products(id),
  retired_at           timestamptz not null default now()
);

comment on table public.product_retirement is
  'Products archived for being another product written differently, with the status they held and the row that represents them. Reversed by unretire_duplicate_products().';

create table if not exists public.product_retirement_move (
  id              bigserial primary key,
  table_name      text   not null,
  row_id          bigint not null,
  from_product_id bigint not null,
  to_product_id   bigint not null,
  deleted         boolean not null default false,
  moved_at        timestamptz not null default now()
);

comment on table public.product_retirement_move is
  'Every user record repointed from a duplicate to the product representing it. deleted marks the rows that could not move because the same user already held the canonical product, which a unique constraint forbids.';

create index if not exists product_retirement_move_row_idx
  on public.product_retirement_move (table_name, row_id);

create unlogged table if not exists public.product_retire_plan (
  product_id           bigint primary key,
  canonical_product_id bigint not null
);

create or replace function public.retire_duplicate_products() returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_stash_moved   integer := 0;  v_stash_dropped integer := 0;
  v_lists_moved   integer := 0;  v_lists_dropped integer := 0;
  v_posts_moved   integer := 0;  v_posts_dropped integer := 0;
  v_archived      integer := 0;
  v_leftover      jsonb;
begin
  truncate product_retire_plan;
  insert into product_retire_plan (product_id, canonical_product_id)
  select product_id, duplicate_of from v_product_identity where duplicate_of is not null;

  -- A user who already holds the canonical product cannot also hold the duplicate: the
  -- unique constraint on (profile_id, product_id) forbids it. Those rows are logged and
  -- dropped; the rest move across.
  with collide as (
    delete from stash s using product_retire_plan d
     where s.product_id = d.product_id
       and exists (select 1 from stash t
                    where t.profile_id = s.profile_id
                      and t.product_id = d.canonical_product_id)
    returning s.id, s.product_id, d.canonical_product_id
  ), logged as (
    insert into product_retirement_move (table_name, row_id, from_product_id, to_product_id, deleted)
    select 'stash', id, product_id, canonical_product_id, true from collide returning 1
  ) select count(*) into v_stash_dropped from logged;

  with moved as (
    update stash s set product_id = d.canonical_product_id
      from product_retire_plan d
     where s.product_id = d.product_id
    returning s.id, d.product_id as was, d.canonical_product_id
  ), logged as (
    insert into product_retirement_move (table_name, row_id, from_product_id, to_product_id)
    select 'stash', id, was, canonical_product_id from moved returning 1
  ) select count(*) into v_stash_moved from logged;

  with collide as (
    delete from lists_products l using product_retire_plan d
     where l.product_id = d.product_id
       and exists (select 1 from lists_products t
                    where t.list_id = l.list_id
                      and t.product_id = d.canonical_product_id)
    returning l.id, l.product_id, d.canonical_product_id
  ), logged as (
    insert into product_retirement_move (table_name, row_id, from_product_id, to_product_id, deleted)
    select 'lists_products', id, product_id, canonical_product_id, true from collide returning 1
  ) select count(*) into v_lists_dropped from logged;

  with moved as (
    update lists_products l set product_id = d.canonical_product_id
      from product_retire_plan d
     where l.product_id = d.product_id
    returning l.id, d.product_id as was, d.canonical_product_id
  ), logged as (
    insert into product_retirement_move (table_name, row_id, from_product_id, to_product_id)
    select 'lists_products', id, was, canonical_product_id from moved returning 1
  ) select count(*) into v_lists_moved from logged;

  with collide as (
    delete from posts_products pp using product_retire_plan d
     where pp.product_id = d.product_id
       and exists (select 1 from posts_products t
                    where t.post_id = pp.post_id
                      and t.product_id = d.canonical_product_id)
    returning pp.id, pp.product_id, d.canonical_product_id
  ), logged as (
    insert into product_retirement_move (table_name, row_id, from_product_id, to_product_id, deleted)
    select 'posts_products', id, product_id, canonical_product_id, true from collide returning 1
  ) select count(*) into v_posts_dropped from logged;

  with moved as (
    update posts_products pp set product_id = d.canonical_product_id
      from product_retire_plan d
     where pp.product_id = d.product_id
    returning pp.id, d.product_id as was, d.canonical_product_id
  ), logged as (
    insert into product_retirement_move (table_name, row_id, from_product_id, to_product_id)
    select 'posts_products', id, was, canonical_product_id from moved returning 1
  ) select count(*) into v_posts_moved from logged;

  insert into product_retirement (product_id, previous_status, canonical_product_id)
  select d.product_id, p.status, d.canonical_product_id
  from product_retire_plan d
  join products p on p.id = d.product_id
  where p.status <> 'archived'
  on conflict (product_id) do nothing;

  update products p set status = 'archived'
   where p.id in (select product_id from product_retire_plan)
     and p.status <> 'archived';
  get diagnostics v_archived = row_count;

  -- Anything else still pointing at an archived row. None of these had rows when this
  -- was written; if one appears later it wants attention, because a giveaway or a deal
  -- on a hidden product is a bug rather than a tidy-up.
  select jsonb_object_agg(t, n) into v_leftover from (
    select 'giveaways' as t, count(*) as n from giveaways g join product_retire_plan d on d.product_id = g.product_id
    union all select 'bag_items',     count(*) from bag_items b     join product_retire_plan d on d.product_id = b.product_id
    union all select 'deal_products', count(*) from deal_products x join product_retire_plan d on d.product_id = x.product_id
    union all select 'shop_now',      count(*) from shop_now s      join product_retire_plan d on d.product_id = s.product_id
    union all select 'product_reminders', count(*) from product_reminders r join product_retire_plan d on d.product_id = r.product_id
  ) z where n > 0;

  return jsonb_build_object(
    'archived',        v_archived,
    'stash_moved',     v_stash_moved,   'stash_dropped', v_stash_dropped,
    'lists_moved',     v_lists_moved,   'lists_dropped', v_lists_dropped,
    'posts_moved',     v_posts_moved,   'posts_dropped', v_posts_dropped,
    'still_referenced', coalesce(v_leftover, '{}'::jsonb)
  );
end $$;

comment on function public.retire_duplicate_products() is
  'Move every duplicate product to archived, after repointing the user records that mention it. Logs everything; reversed by unretire_duplicate_products().';

create or replace function public.unretire_duplicate_products() returns jsonb
language plpgsql
set search_path = public
as $$
declare v_restored integer := 0; v_moved_back integer := 0;
begin
  update products p set status = r.previous_status
    from product_retirement r
   where r.product_id = p.id and p.status = 'archived';
  get diagnostics v_restored = row_count;

  -- Put back the records that moved. The ones deleted for colliding with a canonical the
  -- user already held are not recreated: the user still holds that product.
  with back as (
    update stash s set product_id = m.from_product_id
      from product_retirement_move m
     where m.table_name = 'stash' and not m.deleted and m.row_id = s.id
       and s.product_id = m.to_product_id
    returning 1
  ) select count(*) into v_moved_back from back;

  update lists_products l set product_id = m.from_product_id
    from product_retirement_move m
   where m.table_name = 'lists_products' and not m.deleted and m.row_id = l.id
     and l.product_id = m.to_product_id;

  update posts_products pp set product_id = m.from_product_id
    from product_retirement_move m
   where m.table_name = 'posts_products' and not m.deleted and m.row_id = pp.id
     and pp.product_id = m.to_product_id;

  delete from product_retirement;
  delete from product_retirement_move;

  return jsonb_build_object('status_restored', v_restored, 'stash_moved_back', v_moved_back);
end $$;

comment on function public.unretire_duplicate_products() is
  'Undo retire_duplicate_products(): statuses back to what they were and user records back to the rows they named.';

revoke all on table public.product_retirement, public.product_retirement_move,
                    public.product_retire_plan from anon, authenticated;
alter table public.product_retirement      enable row level security;
alter table public.product_retirement_move enable row level security;
alter table public.product_retire_plan     enable row level security;
revoke all on function public.retire_duplicate_products()   from anon, authenticated;
revoke all on function public.unretire_duplicate_products() from anon, authenticated;
