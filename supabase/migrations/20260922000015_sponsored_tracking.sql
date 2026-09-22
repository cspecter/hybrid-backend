-- Per-campaign impression and tap tracking, reusing the analytics layer rather than
-- building a second one beside it.
--
-- Three things had to be true first:
--
--  1. The dedupe key is (event_type, target_type, target_id) and does NOT include
--     context. Recording sponsored events against the POST id would make two
--     campaigns boosting the same post dedupe against each other, so they are
--     recorded against the CAMPAIGN id instead — which is also the grain the
--     reporting wants.
--
--  2. analytics_target_owner() drives the self-action exclusion that stops someone
--     inflating their own numbers. It knew nothing about 'campaign', so a brand
--     scrolling past its own boosted post would have counted. It now resolves a
--     campaign to the boosted post's author, which is the same person the exclusion
--     already covers for the organic post.
--
--  3. The dedupe window is chosen by event class, and an unknown class falls to
--     action_dedupe_minutes — one minute. An impression on a one-minute window is an
--     impression counter that can be run up by scrolling back and forth, so
--     sponsored_impression joins post_impression on 30 minutes and sponsored_tap
--     joins the view class.
--
-- The rate limit, the session requirement and the actor derivation are untouched:
-- this is the live function text with exactly the two dedupe edits, diffed to prove
-- it. Everything an advertiser would want to inflate is already defended.

create or replace function public.analytics_target_owner(p_target_type text, p_target_id integer)
returns integer
language sql
stable
security definer
set search_path = public
as $function$
  select case p_target_type
    when 'post'     then (select profile_id from public.posts where id = p_target_id)
    when 'profile'  then p_target_id
    when 'list'     then (select profile_id from public.lists where id = p_target_id)
    when 'location' then (select brand_id from public.locations where id = p_target_id)
    when 'giveaway' then (select created_by_profile_id from public.giveaways where id = p_target_id)
    when 'product'  then (select brand_id from public.product_brands
                           where product_id = p_target_id and coalesce(is_primary, false)
                           limit 1)
    -- A campaign belongs to whoever wrote the post it boosts.
    when 'campaign' then (select p.profile_id
                            from public.sponsored_campaigns c
                            join public.posts p on p.id = c.post_id
                           where c.id = p_target_id)
    else null
  end;
$function$;

CREATE OR REPLACE FUNCTION public.track_event(p_event_type text, p_target_type text, p_target_id integer, p_session_id text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    when p_event_type in ('post_impression', 'sponsored_impression') then
      (select value from public.analytics_config where key = 'impression_dedupe_minutes')
    when p_event_type in ('post_view', 'profile_visit', 'product_view', 'list_view',
                          'location_view', 'giveaway_view', 'video_watch',
                          'sponsored_tap') then
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
$function$
;

-- The feed needs the internal campaign id to record against. public_id stays in the
-- payload for the admin surfaces; analytics_events.target_id is an integer, and the
-- whole point of the change above is that events are keyed on the campaign.
-- Dropped rather than replaced: CREATE OR REPLACE cannot change a function's OUT
-- parameter row type, and this adds a fourth column.
drop function if exists public.sponsored_posts_for_me(integer);

create function public.sponsored_posts_for_me(p_limit integer default 5)
returns table (post_id integer, campaign_id uuid, campaign_name text, campaign_key integer)
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
    return query
      select c.post_id, c.public_id, c.name, c.id
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

  select array_remove(array[
    case when p.profile_type = 'brand' or p.role_id = 10 then 'brand' end,
    case when p.profile_type = 'creator' or p.role_id = 2 then 'creator' end,
    case when p.profile_type = 'individual' and coalesce(p.role_id,1) = 1 then 'member' end
  ], null) into v_types
    from public.profiles p where p.id = v_me;

  if exists (select 1 from public.location_employees le
              where le.profile_id = v_me and le.is_approved is true and le.role in ('budtender','staff')) then
    v_types := array_append(v_types, 'budtender');
  end if;
  if exists (select 1 from public.location_employees le
              where le.profile_id = v_me and le.is_approved is true and le.role = 'manager') then
    v_types := array_append(v_types, 'manager');
  end if;

  select pc.state_code into v_state
    from public.profiles p
    join public.postal_codes pc on pc.id = coalesce(p.home_location_id, p.last_location_id)
   where p.id = v_me;

  return query
    select c.post_id, c.public_id, c.name, c.id
      from public.sponsored_campaigns c
     where c.status = 'active'
       and (c.starts_at is null or c.starts_at <= now())
       and (c.ends_at is null or c.ends_at > now())
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

-- ── Reporting ──────────────────────────────────────────────────────────────
-- Impressions, taps and reach per campaign. Reach is distinct sessions rather than
-- distinct profiles because a signed-out viewer has no profile and would otherwise
-- vanish from the number entirely.
create or replace function public.sponsored_campaign_stats(p_days integer default 30)
returns table (
  campaign_id uuid, impressions bigint, taps bigint, reach bigint, tap_rate numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.public_id,
         count(*) filter (where e.event_type = 'sponsored_impression'),
         count(*) filter (where e.event_type = 'sponsored_tap'),
         count(distinct e.session_id) filter (where e.event_type = 'sponsored_impression'),
         case when count(*) filter (where e.event_type = 'sponsored_impression') = 0 then 0
              else round(
                100.0 * count(*) filter (where e.event_type = 'sponsored_tap')
                      / count(*) filter (where e.event_type = 'sponsored_impression'), 1)
         end
    from public.sponsored_campaigns c
    left join public.analytics_events e
      on e.target_type = 'campaign'
     and e.target_id = c.id
     and e.created_at > now() - make_interval(days => greatest(coalesce(p_days, 30), 1))
   where public.is_super_admin()
   group by c.public_id;
$$;

revoke execute on function public.sponsored_campaign_stats(integer) from public;
grant execute on function public.sponsored_campaign_stats(integer) to authenticated;
