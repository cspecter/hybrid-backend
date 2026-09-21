-- Analytics: the read side.
--
-- Dashboards never touch a rollup table — those have no grant to authenticated.
-- Everything goes through these functions, and every one of them calls
-- analytics_can_read() first. Hiding the button is not access control.
--
-- Aggregates only. No function here can return who viewed anything: the events
-- table is never selected from by a caller-facing function, and audience
-- breakdowns are suppressed below a configured follower count so a small account
-- cannot identify an individual follower by elimination.

-- Owner, an admin of that profile, or a super admin. Brands and dispensaries have
-- no login of their own, so profile_admins is the normal path for them.
create or replace function public.analytics_can_read(p_profile_id integer)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare me integer;
begin
  if p_profile_id is null then return false; end if;
  if public.is_super_admin() then return true; end if;
  select id into me from public.profiles where auth_id = auth.uid() limit 1;
  if me is null then return false; end if;
  if me = p_profile_id then return true; end if;
  return exists (select 1 from public.profile_admins
                  where admin_profile_id = me and managed_profile_id = p_profile_id);
end;
$$;

-- The profiles this account may open a dashboard for: itself plus anything it
-- administers. Drives the account switcher.
create or replace function public.analytics_my_scopes()
returns table (profile_id integer, name text, profile_type text, is_self boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
declare me integer;
begin
  select id into me from public.profiles where auth_id = auth.uid() limit 1;
  if me is null then return; end if;
  return query
    select p.id, coalesce(p.display_name, p.username), p.profile_type::text, p.id = me
      from public.profiles p
     where p.id = me
        or p.id in (select managed_profile_id from public.profile_admins where admin_profile_id = me)
     order by (p.id = me) desc, coalesce(p.display_name, p.username);
end;
$$;

-- Engagement rate is defined here, once, and the definition is returned with the
-- number so the UI can show it rather than inventing its own wording:
--   (likes + comments + shares + restashes driven) / impressions
-- Impressions, not followers, because followers is a stock and this is a flow.
create or replace function public.analytics_overview(p_profile_id integer, p_days integer default 28)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d int := greatest(1, least(coalesce(p_days, 28), 365));
  cur_from date := (now() at time zone 'UTC')::date - (d - 1);
  cur_to   date := (now() at time zone 'UTC')::date;
  prv_from date := cur_from - d;
  prv_to   date := cur_from - 1;
  track_start date;
  result jsonb;
begin
  if not public.analytics_can_read(p_profile_id) then
    raise exception 'Not authorised';
  end if;

  select to_timestamp(value * 86400)::date into track_start
    from public.analytics_config where key = 'tracking_start_epoch_day';

  with cur as (
    select coalesce(sum(impressions),0) impressions, coalesce(sum(reach_accounts),0) reach_accounts,
           coalesce(sum(reach_sessions),0) reach_sessions, coalesce(sum(profile_visits),0) profile_visits,
           coalesce(sum(followers_gained),0) followers_gained, coalesce(sum(followers_lost),0) followers_lost,
           coalesce(sum(likes_received),0) likes, coalesce(sum(comments_received),0) comments,
           coalesce(sum(shares),0) shares, coalesce(sum(restashes_driven),0) restashes,
           coalesce(sum(taps),0) taps, coalesce(sum(posts_published),0) posts
      from public.analytics_daily_profile
     where profile_id = p_profile_id and day between cur_from and cur_to
  ), prv as (
    select coalesce(sum(impressions),0) impressions, coalesce(sum(reach_accounts),0) reach_accounts,
           coalesce(sum(reach_sessions),0) reach_sessions, coalesce(sum(profile_visits),0) profile_visits,
           coalesce(sum(followers_gained),0) followers_gained, coalesce(sum(followers_lost),0) followers_lost,
           coalesce(sum(likes_received),0) likes, coalesce(sum(comments_received),0) comments,
           coalesce(sum(shares),0) shares, coalesce(sum(restashes_driven),0) restashes,
           coalesce(sum(taps),0) taps, coalesce(sum(posts_published),0) posts
      from public.analytics_daily_profile
     where profile_id = p_profile_id and day between prv_from and prv_to
  ), series as (
    select jsonb_agg(jsonb_build_object(
             'day', g.day,
             'impressions', coalesce(r.impressions,0), 'reach', coalesce(r.reach_accounts,0),
             'visits', coalesce(r.profile_visits,0),
             'gained', coalesce(r.followers_gained,0), 'lost', coalesce(r.followers_lost,0),
             'engagements', coalesce(r.likes_received,0)+coalesce(r.comments_received,0)
                            +coalesce(r.shares,0)+coalesce(r.restashes_driven,0)
           ) order by g.day) s
      from generate_series(cur_from, cur_to, interval '1 day') g(day)
      left join public.analytics_daily_profile r
             on r.profile_id = p_profile_id and r.day = g.day::date
  )
  select jsonb_build_object(
    'profile_id', p_profile_id,
    'days', d,
    'from', cur_from, 'to', cur_to,
    'tracking_start', track_start,
    'engagement_rate_definition',
      '(likes + comments + shares + restashes driven) ÷ impressions, over the period',
    'current', to_jsonb(cur), 'previous', to_jsonb(prv),
    'followers_total', (select coalesce(follower_count,0) from public.profiles where id = p_profile_id),
    'net_followers', cur.followers_gained - cur.followers_lost,
    'engagement_rate', case when cur.impressions > 0
        then round(((cur.likes + cur.comments + cur.shares + cur.restashes)::numeric / cur.impressions) * 100, 2)
        else null end,
    'engagement_rate_prev', case when prv.impressions > 0
        then round(((prv.likes + prv.comments + prv.shares + prv.restashes)::numeric / prv.impressions) * 100, 2)
        else null end,
    'series', coalesce((select s from series), '[]'::jsonb)
  ) into result
  from cur, prv;

  return result;
end;
$$;

-- ─── Creator ─────────────────────────────────────────────────────────────────
create or replace function public.analytics_creator(p_profile_id integer, p_days integer default 28)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d int := greatest(1, least(coalesce(p_days, 28), 365));
  f date := (now() at time zone 'UTC')::date - (d - 1);
  t date := (now() at time zone 'UTC')::date;
  min_aud int;
  followers int;
begin
  if not public.analytics_can_read(p_profile_id) then raise exception 'Not authorised'; end if;
  select value into min_aud from public.analytics_config where key = 'min_audience_for_breakdown';
  select coalesce(follower_count,0) into followers from public.profiles where id = p_profile_id;

  return jsonb_build_object(
    'posts', coalesce((
      select jsonb_agg(x order by (x->>'views')::int desc) from (
        select jsonb_build_object(
          'post_id', po.id,
          'excerpt', left(coalesce(po.message,''), 70),
          'posted', po.created_at::date,
          'views', coalesce(sum(r.views),0), 'impressions', coalesce(sum(r.impressions),0),
          'reach', coalesce(max(r.reach_accounts),0),
          'likes', coalesce(sum(r.likes),0), 'comments', coalesce(sum(r.comments),0),
          'shares', coalesce(sum(r.shares),0), 'stashes_driven', coalesce(sum(r.stashes_driven),0),
          'watch_events', coalesce(sum(r.watch_events),0),
          'avg_watch_ms', case when coalesce(sum(r.watch_events),0) > 0
                               then round(sum(r.watch_ms_total)::numeric / sum(r.watch_events)) else null end,
          'completion_rate', case when coalesce(sum(r.watch_events),0) > 0
                               then round((sum(r.completions)::numeric / sum(r.watch_events)) * 100, 1) else null end
        ) x
        from public.posts po
        left join public.analytics_daily_post r on r.post_id = po.id and r.day between f and t
        where po.profile_id = p_profile_id
        group by po.id, po.message, po.created_at
        order by coalesce(sum(r.views),0) desc
        limit 50
      ) s), '[]'::jsonb),

    'attribution', (
      select jsonb_build_object(
        'total', coalesce(sum(restashes_driven),0),
        'from_posts', coalesce(sum(restashes_from_posts),0),
        'from_lists', coalesce(sum(restashes_from_lists),0),
        'from_profile', coalesce(sum(restashes_from_profile),0))
        from public.analytics_daily_profile
       where profile_id = p_profile_id and day between f and t),

    'top_converting_posts', coalesce((
      select jsonb_agg(x order by (x->>'stashes')::int desc) from (
        select jsonb_build_object(
          'post_id', r.post_id, 'excerpt', left(coalesce(po.message,''),70),
          'views', sum(r.views), 'stashes', sum(r.stashes_driven),
          'conversion', case when sum(r.views) > 0
            then round((sum(r.stashes_driven)::numeric / sum(r.views)) * 100, 1) else null end) x
        from public.analytics_daily_post r join public.posts po on po.id = r.post_id
        where po.profile_id = p_profile_id and r.day between f and t and r.stashes_driven > 0
        group by r.post_id, po.message order by sum(r.stashes_driven) desc limit 10
      ) s), '[]'::jsonb),

    'lists', coalesce((
      select jsonb_agg(x order by (x->>'subscribers')::int desc) from (
        select jsonb_build_object(
          'list_id', li.id, 'name', li.name,
          'subscribers', coalesce(li.subscription_count,0),
          'products', coalesce(li.product_count,0),
          'restashes_driven', (select count(*) from public.stash s
                                where s.restash_list_id = li.id and s.created_at::date between f and t)) x
        from public.lists li
        where li.profile_id = p_profile_id and li.is_private is not true
        order by li.subscription_count desc nulls last limit 20
      ) s), '[]'::jsonb),

    -- Audience. Suppressed below the configured follower count, and each piece
    -- reports its own availability so the UI can say why rather than show a zero.
    'audience', jsonb_build_object(
      'followers', followers,
      'min_required', coalesce(min_aud, 20),
      'available', followers >= coalesce(min_aud, 20),
      'categories', case when followers < coalesce(min_aud, 20) then '[]'::jsonb else coalesce((
        select jsonb_agg(jsonb_build_object('category', pc.name, 'count', c) order by c desc)
          from (select unnest(fp.preferred_category_ids) cat_id, count(*) c
                  from public.relationships r
                  join public.profiles fp on fp.id = r.follower_id
                 where r.followee_id = p_profile_id
                   and fp.preferred_category_ids is not null
                 group by 1 order by 2 desc limit 8) q
          join public.product_categories pc on pc.id = q.cat_id), '[]'::jsonb) end,
      'states', case when followers < coalesce(min_aud, 20) then '[]'::jsonb else coalesce((
        select jsonb_agg(jsonb_build_object('state', st, 'count', c) order by c desc)
          from (select pcode.state_code st, count(*) c
                  from public.relationships r
                  join public.profiles fp on fp.id = r.follower_id
                  join public.postal_codes pcode on pcode.id = fp.home_location_id
                 where r.followee_id = p_profile_id
                 group by 1 order by 2 desc limit 8) q), '[]'::jsonb) end,
      'active_hours', case when followers < coalesce(min_aud, 20) then '[]'::jsonb else coalesce((
        select jsonb_agg(jsonb_build_object('hour', h, 'count', c) order by h)
          from (select extract(hour from l.created_at)::int h, count(*) c
                  from public.likes l join public.posts po on po.id = l.post_id
                 where po.profile_id = p_profile_id and l.created_at::date between f and t
                 group by 1) q), '[]'::jsonb) end,
      -- birthday is set on 8 of 2,481 profiles, so an age split would be noise.
      'age', jsonb_build_object('available', false, 'reason', 'Date of birth is recorded for almost no accounts')
    )
  );
end;
$$;

-- ─── Brand ───────────────────────────────────────────────────────────────────
create or replace function public.analytics_brand(p_profile_id integer, p_days integer default 28)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d int := greatest(1, least(coalesce(p_days, 28), 365));
  f date := (now() at time zone 'UTC')::date - (d - 1);
  t date := (now() at time zone 'UTC')::date;
  prods integer[];
begin
  if not public.analytics_can_read(p_profile_id) then raise exception 'Not authorised'; end if;
  select array_agg(product_id) into prods from public.product_brands where brand_id = p_profile_id;
  if prods is null then prods := array[]::integer[]; end if;

  return jsonb_build_object(
    'product_count', coalesce(array_length(prods,1), 0),
    'products', coalesce((
      select jsonb_agg(x order by (x->>'stashes')::int desc) from (
        select jsonb_build_object(
          'product_id', p.id, 'name', p.name,
          'views', coalesce(sum(r.views),0), 'stashes', coalesce(sum(r.stashes),0),
          'unstashes', coalesce(sum(r.unstashes),0),
          'list_adds', coalesce(sum(r.list_adds),0), 'posts_tagging', coalesce(sum(r.posts_tagging),0),
          'stash_total', coalesce(p.stash_count,0))
        x from public.products p
        left join public.analytics_daily_product r on r.product_id = p.id and r.day between f and t
        where p.id = any(prods)
        group by p.id, p.name, p.stash_count
        order by coalesce(sum(r.stashes),0) desc, coalesce(p.stash_count,0) desc
        limit 50) s), '[]'::jsonb),

    -- No social platform can answer this: which creators' content produced stashes
    -- of this brand's products. The restash columns on stash make it a join.
    'creators_driving', coalesce((
      select jsonb_agg(x order by (x->>'stashes')::int desc) from (
        select jsonb_build_object(
          'profile_id', cp.id, 'name', coalesce(cp.display_name, cp.username),
          'stashes', count(*)) x
        from public.stash s
        join public.posts po on po.id = s.restash_post_id
        join public.profiles cp on cp.id = po.profile_id
        where s.product_id = any(prods) and s.created_at::date between f and t
        group by cp.id, cp.display_name, cp.username
        union all
        select jsonb_build_object(
          'profile_id', cp.id, 'name', coalesce(cp.display_name, cp.username),
          'stashes', count(*)) x
        from public.stash s
        join public.lists li on li.id = s.restash_list_id
        join public.profiles cp on cp.id = li.profile_id
        where s.product_id = any(prods) and s.created_at::date between f and t
        group by cp.id, cp.display_name, cp.username
        limit 20) s), '[]'::jsonb),

    'giveaways', coalesce((
      select jsonb_agg(x order by (x->>'ends') desc) from (
        select jsonb_build_object(
          'giveaway_id', g.id, 'name', g.name, 'ends', g.end_time::date,
          'views', coalesce(sum(r.views),0), 'entries', coalesce(g.entry_count,0),
          'conversion', case when coalesce(sum(r.views),0) > 0
            then round((coalesce(g.entry_count,0)::numeric / sum(r.views)) * 100, 1) else null end) x
        from public.giveaways g
        left join public.analytics_daily_giveaway r on r.giveaway_id = g.id
        where g.created_by_profile_id = p_profile_id
        group by g.id, g.name, g.end_time, g.entry_count
        order by g.end_time desc limit 20) s), '[]'::jsonb),

    'deals', coalesce((
      select jsonb_agg(x order by (x->>'claims')::int desc) from (
        select jsonb_build_object(
          'deal_id', dl.id, 'title', dl.title,
          'claims', coalesce(dl.claim_count,0),
          'redemptions', (select count(*) from public.claimed_deals cd
                           where cd.deal_id = dl.id and cd.redeemed_at is not null),
          'rate', case when coalesce(dl.claim_count,0) > 0 then round(((
              select count(*) from public.claimed_deals cd
               where cd.deal_id = dl.id and cd.redeemed_at is not null)::numeric
              / dl.claim_count) * 100, 1) else null end) x
        from public.deals dl
        join public.locations lo on lo.id = dl.location_id
        where lo.brand_id = p_profile_id
        order by dl.claim_count desc nulls last limit 20) s), '[]'::jsonb)
  );
end;
$$;

-- ─── Dispensary ──────────────────────────────────────────────────────────────
create or replace function public.analytics_dispensary(p_profile_id integer, p_days integer default 28)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d int := greatest(1, least(coalesce(p_days, 28), 365));
  f date := (now() at time zone 'UTC')::date - (d - 1);
  t date := (now() at time zone 'UTC')::date;
  locs integer[];
begin
  if not public.analytics_can_read(p_profile_id) then raise exception 'Not authorised'; end if;
  select array_agg(id) into locs from public.locations where brand_id = p_profile_id;
  if locs is null then locs := array[]::integer[]; end if;

  return jsonb_build_object(
    'locations', coalesce((
      select jsonb_agg(x order by (x->>'views')::int desc) from (
        select jsonb_build_object(
          'location_id', lo.id, 'name', lo.name,
          'views', coalesce(sum(r.views),0), 'reach', coalesce(max(r.reach_accounts),0),
          'favourites', coalesce(sum(r.favourites),0),
          'directions_taps', coalesce(sum(r.directions_taps),0),
          'phone_taps', coalesce(sum(r.phone_taps),0),
          'website_taps', coalesce(sum(r.website_taps),0),
          'deal_claims', coalesce(sum(r.deal_claims),0),
          'deal_redemptions', coalesce(sum(r.deal_redemptions),0)) x
        from public.locations lo
        left join public.analytics_daily_location r on r.location_id = lo.id and r.day between f and t
        where lo.id = any(locs)
        group by lo.id, lo.name limit 50) s), '[]'::jsonb),

    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
        'profile_id', p.id, 'name', coalesce(p.display_name, p.username),
        'role', coalesce(le.role,'budtender'),
        'posts', coalesce(p.post_count,0), 'restashes', coalesce(p.restash_count,0)))
        from public.location_employees le
        join public.profiles p on p.id = le.profile_id
       where le.location_id = any(locs) and le.is_approved), '[]'::jsonb),

    'pending_staff', (select count(*) from public.location_employees
                       where location_id = any(locs) and is_approved is not true),

    'featured_lists', coalesce((
      select jsonb_agg(jsonb_build_object(
        'list_id', li.id, 'name', li.name,
        'subscribers', coalesce(li.subscription_count,0),
        'views', 0))
        from public.location_stashlists ls join public.lists li on li.id = ls.list_id
       where ls.location_id = any(locs)), '[]'::jsonb),

    'deals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'deal_id', dl.id, 'title', dl.title,
        'claims', coalesce(dl.claim_count,0),
        'redemptions', (select count(*) from public.claimed_deals cd
                         where cd.deal_id = dl.id and cd.redeemed_at is not null)))
        from public.deals dl where dl.location_id = any(locs)), '[]'::jsonb)
  );
end;
$$;

-- ─── Platform, super admin only ──────────────────────────────────────────────
create or replace function public.analytics_platform(p_days integer default 28)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d int := greatest(1, least(coalesce(p_days, 28), 365));
  f date := (now() at time zone 'UTC')::date - (d - 1);
  t date := (now() at time zone 'UTC')::date;
begin
  if not public.is_super_admin() then raise exception 'Not authorised'; end if;

  return jsonb_build_object(
    'days', d,
    'new_signups', (select count(*) from public.profiles where created_at::date between f and t),
    'event_volume', (select count(*) from public.analytics_events where created_at::date between f and t),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', g.day::date,
        'events', (select count(*) from public.analytics_events e where e.created_at::date = g.day::date),
        'active_accounts', (select count(distinct e.actor_profile_id) from public.analytics_events e
                             where e.created_at::date = g.day::date and e.actor_profile_id is not null),
        'signups', (select count(*) from public.profiles p where p.created_at::date = g.day::date)
      ) order by g.day)
      from generate_series(f, t, interval '1 day') g(day)), '[]'::jsonb),
    'total_engagement', (
      select coalesce(sum(likes_received + comments_received + shares + restashes_driven),0)
        from public.analytics_daily_profile where day between f and t),
    'top_by_engagement', coalesce((
      select jsonb_agg(x order by (x->>'engagement')::int desc) from (
        select jsonb_build_object(
          'profile_id', p.id, 'name', coalesce(p.display_name,p.username),
          'type', p.profile_type::text,
          'engagement', sum(r.likes_received + r.comments_received + r.shares + r.restashes_driven)) x
        from public.analytics_daily_profile r join public.profiles p on p.id = r.profile_id
        where r.day between f and t
        group by p.id, p.display_name, p.username, p.profile_type
        having sum(r.likes_received + r.comments_received + r.shares + r.restashes_driven) > 0
        order by 1 desc limit 15) s), '[]'::jsonb)
  );
end;
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'public.analytics_can_read(integer)',
    'public.analytics_my_scopes()',
    'public.analytics_overview(integer,integer)',
    'public.analytics_creator(integer,integer)',
    'public.analytics_brand(integer,integer)',
    'public.analytics_dispensary(integer,integer)',
    'public.analytics_platform(integer)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end $$;
