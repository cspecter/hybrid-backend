-- Sponsored posts: boost a real post into the feed, to a chosen audience.
--
-- A campaign points at an existing post rather than carrying its own creative. That
-- keeps the post card, its likes, its comments and its product tags — a sponsored
-- item behaves like everything around it, which is the point of boosting rather
-- than building an ad unit. posts.promoted already existed and was unused on all
-- 449 rows; it is now what the card reads to draw the Sponsored label.
--
-- Targeting is three independent filters, each of which means "everyone" when empty:
--   account_types   member / creator / brand / budtender / manager
--   states          two-letter codes, from the viewer's home postal code
--   followed_brands profile ids of brands the viewer follows
-- A campaign with all three empty is the global rotation.
--
-- Cannabis advertising is regulated state by state, which is why states are a
-- targeting dimension rather than an afterthought — and why the label is not
-- optional. Disclosure is the advertiser's legal obligation, not a UI preference.

create table if not exists public.sponsored_campaigns (
  id              bigint generated always as identity primary key,
  public_id       uuid not null default gen_random_uuid() unique,
  post_id         integer not null references public.posts(id) on delete cascade,
  name            text not null,
  status          text not null default 'draft' check (status in ('draft','active','paused','ended')),
  starts_at       timestamptz,
  ends_at         timestamptz,
  target_account_types text[] not null default '{}',
  target_states        text[] not null default '{}',
  target_followed_brand_ids integer[] not null default '{}',
  created_by      integer references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists sponsored_campaigns_live
  on public.sponsored_campaigns (status, starts_at, ends_at) where status = 'active';

alter table public.sponsored_campaigns enable row level security;

-- Moderation only, for everything. Ordinary readers never touch this table: the
-- feed asks sponsored_posts_for_me(), which returns post ids and nothing about who
-- else is being targeted or what a campaign is worth.
drop policy if exists "Moderation manages campaigns" on public.sponsored_campaigns;
create policy "Moderation manages campaigns"
  on public.sponsored_campaigns for all
  using (public.is_super_admin()) with check (public.is_super_admin());

-- posts.promoted mirrors "is any campaign live on this post", so the feed card can
-- label a post without a join and without the client deciding what counts as live.
create or replace function public.sync_post_promoted()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_post integer := coalesce(new.post_id, old.post_id);
begin
  update public.posts p
     set promoted = exists (
       select 1 from public.sponsored_campaigns c
        where c.post_id = v_post
          and c.status = 'active'
          and (c.starts_at is null or c.starts_at <= now())
          and (c.ends_at is null or c.ends_at > now()))
   where p.id = v_post;
  return null;
end;
$$;

revoke execute on function public.sync_post_promoted() from public;

drop trigger if exists trg_sync_post_promoted on public.sponsored_campaigns;
create trigger trg_sync_post_promoted
  after insert or update or delete on public.sponsored_campaigns
  for each row execute function public.sync_post_promoted();

-- ── What this viewer should see ────────────────────────────────────────────
-- Returns post ids only. The feed already has the machinery to render a post; this
-- decides which sponsored ones are eligible for this person, in a stable order so a
-- refresh does not reshuffle the whole feed.
create or replace function public.sponsored_posts_for_me(p_limit integer default 5)
returns table (post_id integer, campaign_id uuid, campaign_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me     integer := public.current_actor_id();
  v_state  text;
  v_types  text[] := '{}';
begin
  if v_me is null then
    -- Signed out: only untargeted campaigns, since nothing is known about them.
    return query
      select c.post_id, c.public_id, c.name
        from public.sponsored_campaigns c
       where c.status = 'active'
         and (c.starts_at is null or c.starts_at <= now())
         and (c.ends_at is null or c.ends_at > now())
         and cardinality(c.target_account_types) = 0
         and cardinality(c.target_states) = 0
         and cardinality(c.target_followed_brand_ids) = 0
       order by c.id
       limit greatest(coalesce(p_limit, 5), 0);
    return;
  end if;

  -- The viewer's account types. Plural on purpose: a budtender can also be a
  -- creator, and a campaign aimed at either should reach them.
  select array_remove(array[
    case when p.profile_type = 'brand' or p.role_id = 10 then 'brand' end,
    case when p.profile_type = 'creator' or p.role_id = 2 then 'creator' end,
    case when p.profile_type = 'individual' and coalesce(p.role_id,1) = 1 then 'member' end
  ], null) into v_types
    from public.profiles p where p.id = v_me;

  if exists (select 1 from public.location_employees le
              where le.profile_id = v_me and le.is_approved is true and le.role in ('budtender','staff')) then
    v_types := v_types || 'budtender';
  end if;
  if exists (select 1 from public.location_employees le
              where le.profile_id = v_me and le.is_approved is true and le.role = 'manager') then
    v_types := v_types || 'manager';
  end if;

  select pc.state_code into v_state
    from public.profiles p
    join public.postal_codes pc on pc.id = coalesce(p.home_location_id, p.last_location_id)
   where p.id = v_me;

  return query
    select c.post_id, c.public_id, c.name
      from public.sponsored_campaigns c
     where c.status = 'active'
       and (c.starts_at is null or c.starts_at <= now())
       and (c.ends_at is null or c.ends_at > now())
       -- Each filter is "everyone" when empty.
       and (cardinality(c.target_account_types) = 0 or c.target_account_types && v_types)
       and (cardinality(c.target_states) = 0 or (v_state is not null and v_state = any (c.target_states)))
       and (cardinality(c.target_followed_brand_ids) = 0 or exists (
             select 1 from public.relationships r
              where r.follower_id = v_me
                and r.followee_id = any (c.target_followed_brand_ids)))
     order by c.id
     limit greatest(coalesce(p_limit, 5), 0);
end;
$$;

revoke execute on function public.sponsored_posts_for_me(integer) from public;
grant execute on function public.sponsored_posts_for_me(integer) to anon, authenticated;

-- ── The admin list ─────────────────────────────────────────────────────────
create or replace function public.list_sponsored_campaigns()
returns table (
  public_id uuid, name text, status text, post_id integer,
  starts_at timestamptz, ends_at timestamptz,
  target_account_types text[], target_states text[], target_followed_brand_ids integer[],
  created_at timestamptz, post_message text, author_name text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.public_id, c.name, c.status, c.post_id, c.starts_at, c.ends_at,
         c.target_account_types, c.target_states, c.target_followed_brand_ids,
         c.created_at,
         left(coalesce(p.message, ''), 120),
         coalesce(a.display_name, a.username, 'Unknown')::text
    from public.sponsored_campaigns c
    join public.posts p on p.id = c.post_id
    left join public.profiles a on a.id = p.profile_id
   where public.is_super_admin()
   order by c.created_at desc
   limit 200;
$$;

revoke execute on function public.list_sponsored_campaigns() from public;
grant execute on function public.list_sponsored_campaigns() to authenticated;

create or replace function public.upsert_sponsored_campaign(
  p_public_id uuid,
  p_post_id integer,
  p_name text,
  p_status text,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null,
  p_account_types text[] default '{}',
  p_states text[] default '{}',
  p_followed_brand_ids integer[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.is_super_admin() then
    raise exception 'Only Hybrid moderation can manage sponsored campaigns' using errcode = '42501';
  end if;
  if p_status not in ('draft','active','paused','ended') then
    raise exception 'Unknown status: %', p_status using errcode = '22023';
  end if;
  if not exists (select 1 from public.posts where id = p_post_id) then
    raise exception 'That post does not exist' using errcode = 'P0002';
  end if;

  if p_public_id is null then
    insert into public.sponsored_campaigns
      (post_id, name, status, starts_at, ends_at, target_account_types, target_states, target_followed_brand_ids, created_by)
    values
      (p_post_id, p_name, p_status, p_starts_at, p_ends_at,
       coalesce(p_account_types,'{}'), coalesce(p_states,'{}'), coalesce(p_followed_brand_ids,'{}'),
       public.current_actor_id())
    returning public_id into v_id;
  else
    update public.sponsored_campaigns
       set post_id = p_post_id, name = p_name, status = p_status,
           starts_at = p_starts_at, ends_at = p_ends_at,
           target_account_types = coalesce(p_account_types,'{}'),
           target_states = coalesce(p_states,'{}'),
           target_followed_brand_ids = coalesce(p_followed_brand_ids,'{}'),
           updated_at = now()
     where public_id = p_public_id
     returning public_id into v_id;
    if v_id is null then
      raise exception 'Campaign not found' using errcode = 'P0002';
    end if;
  end if;
  return v_id;
end;
$$;

revoke execute on function public.upsert_sponsored_campaign(uuid, integer, text, text, timestamptz, timestamptz, text[], text[], integer[]) from public;
grant execute on function public.upsert_sponsored_campaign(uuid, integer, text, text, timestamptz, timestamptz, text[], text[], integer[]) to authenticated;
