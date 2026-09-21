-- Analytics: the event capture layer.
--
-- One append-only table, one write path. No grant to anon or authenticated on the
-- table itself — the only way in is track_event(), which derives the actor from
-- auth.uid() and never from a parameter.
--
-- EXECUTE is revoked from PUBLIC explicitly on every function below. Revoking anon
-- alone would leave them open: 81 of 82 functions on this database carried a PUBLIC
-- grant when the surface was first audited, and PUBLIC includes every role.

-- ─── Config, in one place ────────────────────────────────────────────────────
-- Read by the RPC at call time so the thresholds can be changed without touching
-- logic. Service-role only; nothing else can see or set them.
create table if not exists public.analytics_config (
  key   text primary key,
  value integer not null,
  note  text
);

insert into public.analytics_config (key, value, note) values
  ('impression_dedupe_minutes', 30,  'One impression per actor-or-session per target per this many minutes'),
  ('view_dedupe_minutes',       30,  'Same, for views and page visits'),
  ('action_dedupe_minutes',      1,  'Taps and shares: only collapses double-fires'),
  ('session_events_per_minute',120,  'Hard cap per session; events past it are dropped silently'),
  ('min_audience_for_breakdown',20,  'Below this follower count, audience breakdowns are suppressed')
on conflict (key) do nothing;

-- ─── The events table ────────────────────────────────────────────────────────
create table if not exists public.analytics_events (
  id                bigint generated always as identity primary key,
  event_type        text not null check (event_type in (
                      'post_impression', 'post_view', 'video_watch',
                      'profile_visit', 'product_view', 'list_view',
                      'location_view', 'giveaway_view',
                      'share', 'link_tap', 'phone_tap', 'directions_tap', 'website_tap',
                      'unfollow', 'unlike', 'unstash')),
  -- Null for a logged-out viewer. Never taken from a parameter.
  actor_profile_id  integer references public.profiles(id) on delete set null,
  -- Required even when signed in: it is what makes logged-out reach dedupable, and
  -- it keeps one person on two devices from counting as one.
  session_id        text not null check (length(session_id) between 8 and 64),
  target_type       text not null check (target_type in
                      ('post', 'profile', 'product', 'list', 'location', 'giveaway')),
  target_id         integer not null,
  -- Which surface the event happened on, plus a few numeric extras
  -- (watch_ms, duration_ms). Kept small on purpose; this is not a log sink.
  context           jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now()
);

-- The dashboard asks "everything about this target, in this window" far more often
-- than anything else; the dedupe check asks the same question narrowed to one actor.
create index if not exists analytics_events_target_idx
  on public.analytics_events (target_type, target_id, created_at desc);
create index if not exists analytics_events_dedupe_idx
  on public.analytics_events (target_type, target_id, event_type, session_id, created_at desc);
create index if not exists analytics_events_actor_idx
  on public.analytics_events (actor_profile_id, created_at desc)
  where actor_profile_id is not null;
create index if not exists analytics_events_type_day_idx
  on public.analytics_events (event_type, created_at desc);
-- The rollup job sweeps one day at a time.
create index if not exists analytics_events_created_idx
  on public.analytics_events (created_at);

alter table public.analytics_events enable row level security;
alter table public.analytics_config enable row level security;

revoke all on public.analytics_events from anon, authenticated, public;
revoke all on public.analytics_config from anon, authenticated, public;
grant all on public.analytics_events to service_role;
grant all on public.analytics_config to service_role;

-- ─── Who owns a target ───────────────────────────────────────────────────────
-- Self-actions never count: your own view of your own post is not reach. For a
-- brand or a location the owner is the brand profile, so an admin viewing the
-- brand they run is also excluded — they are not an audience either.
create or replace function public.analytics_target_owner(p_target_type text, p_target_id integer)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case p_target_type
    when 'post'     then (select profile_id from public.posts where id = p_target_id)
    when 'profile'  then p_target_id
    when 'list'     then (select profile_id from public.lists where id = p_target_id)
    when 'location' then (select brand_id from public.locations where id = p_target_id)
    when 'giveaway' then (select created_by_profile_id from public.giveaways where id = p_target_id)
    when 'product'  then (select brand_id from public.product_brands
                           where product_id = p_target_id and coalesce(is_primary, false)
                           limit 1)
    else null
  end;
$$;

-- ─── The one write path ──────────────────────────────────────────────────────
-- Returns true when an event was stored, false when it was deliberately dropped.
-- The caller is not told which rule dropped it: a client that could tell dedupe
-- from rate-limit could tune around both.
create or replace function public.track_event(
  p_event_type  text,
  p_target_type text,
  p_target_id   integer,
  p_session_id  text,
  p_context     jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  me           integer;
  owner_id     integer;
  window_min   integer;
  rate_cap     integer;
  recent_count integer;
begin
  -- A session id is required from everyone, signed in or not. Without one there is
  -- no way to dedupe, and an undedupable event is an inflatable one.
  if p_session_id is null or length(btrim(p_session_id)) < 8 then
    return false;
  end if;

  -- Derived, never accepted. There is no actor parameter on this function at all,
  -- which is the point: a caller has nothing to forge.
  select id into me from public.profiles where auth_id = auth.uid() limit 1;

  -- Removals are written by triggers, not by clients.
  if p_event_type in ('unfollow', 'unlike', 'unstash') then
    return false;
  end if;

  if p_target_id is null or p_target_id <= 0 then
    return false;
  end if;

  -- Rate limit, per session per minute.
  select value into rate_cap from public.analytics_config where key = 'session_events_per_minute';
  select count(*) into recent_count
    from public.analytics_events
   where session_id = p_session_id
     and created_at > now() - interval '1 minute';
  if recent_count >= coalesce(rate_cap, 120) then
    return false;
  end if;

  -- Self-action exclusion.
  owner_id := public.analytics_target_owner(p_target_type, p_target_id);
  if me is not null and owner_id is not null and owner_id = me then
    return false;
  end if;
  -- An admin of the brand counts as the brand for this purpose.
  if me is not null and owner_id is not null and exists (
    select 1 from public.profile_admins
     where admin_profile_id = me and managed_profile_id = owner_id
  ) then
    return false;
  end if;

  -- Dedupe window by event class.
  window_min := case
    when p_event_type = 'post_impression' then
      (select value from public.analytics_config where key = 'impression_dedupe_minutes')
    when p_event_type in ('post_view', 'profile_visit', 'product_view', 'list_view',
                          'location_view', 'giveaway_view', 'video_watch') then
      (select value from public.analytics_config where key = 'view_dedupe_minutes')
    else
      (select value from public.analytics_config where key = 'action_dedupe_minutes')
  end;

  -- Deduped on the session, and additionally on the actor when there is one, so
  -- clearing a session id does not buy a second impression.
  if exists (
    select 1 from public.analytics_events e
     where e.event_type = p_event_type
       and e.target_type = p_target_type
       and e.target_id = p_target_id
       and e.created_at > now() - make_interval(mins => coalesce(window_min, 30))
       and (e.session_id = p_session_id
            or (me is not null and e.actor_profile_id = me))
  ) then
    return false;
  end if;

  insert into public.analytics_events
    (event_type, actor_profile_id, session_id, target_type, target_id, context)
  values
    (p_event_type, me, btrim(p_session_id), p_target_type, p_target_id,
     coalesce(p_context, '{}'::jsonb));

  return true;
end;
$$;

-- Batch form, so scrolling a feed is one request rather than one per card. Returns
-- how many of the batch were actually stored.
create or replace function public.track_events(p_events jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  e      jsonb;
  stored integer := 0;
begin
  if p_events is null or jsonb_typeof(p_events) <> 'array' then
    return 0;
  end if;
  -- A client that sends a thousand events in one call is not scrolling a feed.
  if jsonb_array_length(p_events) > 50 then
    return 0;
  end if;

  for e in select * from jsonb_array_elements(p_events) loop
    if public.track_event(
         e->>'event_type', e->>'target_type', (e->>'target_id')::integer,
         e->>'session_id', coalesce(e->'context', '{}'::jsonb)
       ) then
      stored := stored + 1;
    end if;
  end loop;

  return stored;
end;
$$;

-- ─── Removals ────────────────────────────────────────────────────────────────
-- "Followers lost" cannot come from a counter, and deletion_log does not archive
-- relationships, likes or stash — it covers giveaways, lists, posts, products and
-- profiles only. So removals are captured here, at the source.
--
-- A trigger rather than an extension of deletion_log: deletion_log stores the whole
-- deleted row as jsonb for recovery, which is a different job from counting, and
-- its consumers would have to learn three new table_name values. Writing to
-- analytics_events instead means the rollups read one table for both directions.
--
-- session_id is a synthetic marker, not a real session: these events have no
-- browser behind them.
create or replace function public.analytics_log_removal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ev text;
  actor integer;
  t_type text;
  t_id integer;
begin
  if TG_TABLE_NAME = 'relationships' then
    ev := 'unfollow'; actor := OLD.follower_id; t_type := 'profile'; t_id := OLD.followee_id;
  elsif TG_TABLE_NAME = 'likes' then
    ev := 'unlike'; actor := OLD.profile_id; t_type := 'post'; t_id := OLD.post_id;
  elsif TG_TABLE_NAME = 'stash' then
    ev := 'unstash'; actor := OLD.profile_id; t_type := 'product'; t_id := OLD.product_id;
  else
    return OLD;
  end if;

  if t_id is null then return OLD; end if;

  insert into public.analytics_events
    (event_type, actor_profile_id, session_id, target_type, target_id, context)
  values
    (ev, actor, 'trigger:' || TG_TABLE_NAME, t_type, t_id,
     jsonb_build_object('surface', 'trigger'));

  return OLD;
end;
$$;

drop trigger if exists analytics_log_unfollow on public.relationships;
create trigger analytics_log_unfollow
  after delete on public.relationships
  for each row execute function public.analytics_log_removal();

drop trigger if exists analytics_log_unlike on public.likes;
create trigger analytics_log_unlike
  after delete on public.likes
  for each row execute function public.analytics_log_removal();

drop trigger if exists analytics_log_unstash on public.stash;
create trigger analytics_log_unstash
  after delete on public.stash
  for each row execute function public.analytics_log_removal();

-- ─── Grants ──────────────────────────────────────────────────────────────────
-- PUBLIC first, explicitly, then the roles that may actually call it.
revoke all on function public.track_event(text, text, integer, text, jsonb) from public, anon, authenticated;
revoke all on function public.track_events(jsonb) from public, anon, authenticated;
revoke all on function public.analytics_target_owner(text, integer) from public, anon, authenticated;
revoke all on function public.analytics_log_removal() from public, anon, authenticated;

-- Logged-out reach is a real number, so anon may write events — through this
-- function and nothing else.
grant execute on function public.track_event(text, text, integer, text, jsonb) to anon, authenticated;
grant execute on function public.track_events(jsonb) to anon, authenticated;
