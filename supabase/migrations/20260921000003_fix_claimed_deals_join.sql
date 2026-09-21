-- analytics_refresh joined claimed_deals to deals on public_id, but
-- claimed_deals.deal_id is an integer FK to deals.id — the uuid column belongs to
-- deal_products, which is a different table with the same-looking column name. The
-- backfill rehearsal failed with `operator does not exist: uuid = integer`, which
-- is the same mismatch that bit the deals work earlier this week.
--
-- Recreated with the correct join. Nothing else in the function changes.
create or replace function public.analytics_refresh(p_from date, p_to date)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $BODY$
declare
  counts jsonb;
begin
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'analytics_refresh: bad range';
  end if;

  -- ── Profile ────────────────────────────────────────────────────────────────
  delete from public.analytics_daily_profile where day between p_from and p_to;

  insert into public.analytics_daily_profile (
    profile_id, day, impressions, reach_accounts, reach_sessions, profile_visits,
    followers_gained, followers_lost, likes_received, comments_received,
    restashes_driven, restashes_from_posts, restashes_from_lists, restashes_from_profile,
    list_subscribers_gained, shares, taps, posts_published)
  select profile_id, day,
         sum(impressions), sum(reach_accounts), sum(reach_sessions), sum(profile_visits),
         sum(followers_gained), sum(followers_lost), sum(likes_received), sum(comments_received),
         sum(restashes_driven), sum(rs_posts), sum(rs_lists), sum(rs_profile),
         sum(list_subs), sum(shares), sum(taps), sum(posts_published)
  from (
    -- Events against the profile itself, and against its posts.
    select coalesce(po.profile_id, e.target_id) profile_id, e.created_at::date as day,
           count(*) filter (where e.event_type = 'post_impression') impressions,
           count(distinct e.actor_profile_id) filter (where e.event_type in ('post_view','profile_visit')) reach_accounts,
           count(distinct e.session_id) filter (where e.event_type in ('post_view','profile_visit')) reach_sessions,
           count(*) filter (where e.event_type = 'profile_visit') profile_visits,
           0 followers_gained, 0 followers_lost, 0 likes_received, 0 comments_received,
           0 restashes_driven, 0 rs_posts, 0 rs_lists, 0 rs_profile, 0 list_subs,
           count(*) filter (where e.event_type = 'share') shares,
           count(*) filter (where e.event_type in ('link_tap','phone_tap','directions_tap','website_tap')) taps,
           0 posts_published
      from public.analytics_events e
      left join public.posts po on e.target_type = 'post' and po.id = e.target_id
     where e.created_at::date between p_from and p_to
       and e.target_type in ('post','profile')
     group by 1, 2

    union all
    select r.followee_id, r.created_at::date, 0,0,0,0, count(*),0,0,0, 0,0,0,0,0, 0,0,0
      from public.relationships r
     where r.created_at::date between p_from and p_to group by 1,2

    union all
    select e.target_id, e.created_at::date, 0,0,0,0, 0,count(*),0,0, 0,0,0,0,0, 0,0,0
      from public.analytics_events e
     where e.event_type = 'unfollow' and e.target_type = 'profile'
       and e.created_at::date between p_from and p_to group by 1,2

    union all
    select po.profile_id, l.created_at::date, 0,0,0,0, 0,0,count(*),0, 0,0,0,0,0, 0,0,0
      from public.likes l join public.posts po on po.id = l.post_id
     where l.created_at::date between p_from and p_to group by 1,2

    union all
    select po.profile_id, c.created_at::date, 0,0,0,0, 0,0,0,count(*), 0,0,0,0,0, 0,0,0
      from public.post_comments c join public.posts po on po.id = c.post_id
     where c.created_at::date between p_from and p_to group by 1,2

    -- Restashes, attributed to whoever owns the surface the stash came from.
    union all
    select po.profile_id, s.created_at::date, 0,0,0,0, 0,0,0,0, count(*),count(*),0,0,0, 0,0,0
      from public.stash s join public.posts po on po.id = s.restash_post_id
     where s.created_at::date between p_from and p_to group by 1,2
    union all
    select li.profile_id, s.created_at::date, 0,0,0,0, 0,0,0,0, count(*),0,count(*),0,0, 0,0,0
      from public.stash s join public.lists li on li.id = s.restash_list_id
     where s.created_at::date between p_from and p_to group by 1,2
    union all
    select s.restash_profile_id, s.created_at::date, 0,0,0,0, 0,0,0,0, count(*),0,0,count(*),0, 0,0,0
      from public.stash s
     where s.restash_profile_id is not null
       and s.restash_post_id is null and s.restash_list_id is null
       and s.created_at::date between p_from and p_to group by 1,2

    union all
    select li.profile_id, sl.created_at::date, 0,0,0,0, 0,0,0,0, 0,0,0,0,count(*), 0,0,0
      from public.subscriptions_lists sl join public.lists li on li.id = sl.list_id
     where sl.created_at::date between p_from and p_to group by 1,2

    union all
    select po.profile_id, po.created_at::date, 0,0,0,0, 0,0,0,0, 0,0,0,0,0, 0,0,count(*)
      from public.posts po
     where po.created_at::date between p_from and p_to group by 1,2
  ) u
  where profile_id is not null
  group by profile_id, day;

  -- ── Post ───────────────────────────────────────────────────────────────────
  delete from public.analytics_daily_post where day between p_from and p_to;

  insert into public.analytics_daily_post (
    post_id, day, impressions, views, reach_accounts, reach_sessions,
    likes, comments, shares, stashes_driven, watch_events, watch_ms_total, completions)
  select post_id, day, sum(impressions), sum(views), max(reach_accounts), max(reach_sessions),
         sum(likes), sum(comments), sum(shares), sum(stashes_driven),
         sum(watch_events), sum(watch_ms), sum(completions)
  from (
    select e.target_id post_id, e.created_at::date as day,
           count(*) filter (where e.event_type = 'post_impression') impressions,
           count(*) filter (where e.event_type = 'post_view') views,
           count(distinct e.actor_profile_id) filter (where e.event_type = 'post_view') reach_accounts,
           count(distinct e.session_id) filter (where e.event_type = 'post_view') reach_sessions,
           0 likes, 0 comments,
           count(*) filter (where e.event_type = 'share') shares,
           0 stashes_driven,
           count(*) filter (where e.event_type = 'video_watch') watch_events,
           coalesce(sum((e.context->>'watch_ms')::bigint) filter (where e.event_type = 'video_watch'), 0) watch_ms,
           count(*) filter (where e.event_type = 'video_watch' and (e.context->>'completed')::boolean) completions
      from public.analytics_events e
     where e.target_type = 'post' and e.created_at::date between p_from and p_to
     group by 1,2

    -- analytics_posts is the legacy view/watch record. The client stopped writing it,
    -- but 2,870 rows of real history are in there and they are the only watch-time
    -- data that predates tracking.
    union all
    select ap.post_id, ap.created_at::date,
           0, count(*), 0, 0, 0, 0,
           count(*) filter (where ap.share_date is not null),
           0,
           count(*) filter (where ap.watch_duration is not null),
           coalesce(sum(ap.watch_duration) filter (where ap.watch_duration is not null), 0) * 1000,
           count(*) filter (where ap.watch_in_full)
      from public.analytics_posts ap
     where ap.post_id is not null and ap.created_at::date between p_from and p_to
     group by 1,2

    union all
    select l.post_id, l.created_at::date, 0,0,0,0, count(*),0,0,0, 0,0,0
      from public.likes l where l.created_at::date between p_from and p_to group by 1,2
    union all
    select c.post_id, c.created_at::date, 0,0,0,0, 0,count(*),0,0, 0,0,0
      from public.post_comments c where c.created_at::date between p_from and p_to group by 1,2
    union all
    select s.restash_post_id, s.created_at::date, 0,0,0,0, 0,0,0,count(*), 0,0,0
      from public.stash s where s.restash_post_id is not null
       and s.created_at::date between p_from and p_to group by 1,2
  ) u
  where post_id is not null
  group by post_id, day;

  -- ── Product ────────────────────────────────────────────────────────────────
  delete from public.analytics_daily_product where day between p_from and p_to;

  insert into public.analytics_daily_product (
    product_id, day, views, reach_accounts, stashes, unstashes, list_adds, posts_tagging)
  select product_id, day, sum(views), max(reach), sum(stashes), sum(unstashes),
         sum(list_adds), sum(posts_tagging)
  from (
    select e.target_id product_id, e.created_at::date as day,
           count(*) filter (where e.event_type = 'product_view') views,
           count(distinct e.actor_profile_id) filter (where e.event_type = 'product_view') reach,
           0 stashes,
           count(*) filter (where e.event_type = 'unstash') unstashes,
           0 list_adds, 0 posts_tagging
      from public.analytics_events e
     where e.target_type = 'product' and e.created_at::date between p_from and p_to
     group by 1,2
    union all
    select s.product_id, s.created_at::date, 0,0, count(*),0, 0,0
      from public.stash s where s.created_at::date between p_from and p_to group by 1,2
    union all
    select lp.product_id, lp.created_at::date, 0,0, 0,0, count(*),0
      from public.lists_products lp where lp.created_at::date between p_from and p_to group by 1,2
    union all
    select pp.product_id, pp.created_at::date, 0,0, 0,0, 0,count(*)
      from public.posts_products pp where pp.created_at::date between p_from and p_to group by 1,2
  ) u
  where product_id is not null
  group by product_id, day;

  -- ── Location ───────────────────────────────────────────────────────────────
  delete from public.analytics_daily_location where day between p_from and p_to;

  insert into public.analytics_daily_location (
    location_id, day, views, reach_accounts, favourites,
    directions_taps, phone_taps, website_taps, deal_claims, deal_redemptions)
  select location_id, day, sum(views), max(reach), sum(favs),
         sum(dir), sum(phone), sum(web), sum(claims), sum(redemptions)
  from (
    select e.target_id location_id, e.created_at::date as day,
           count(*) filter (where e.event_type = 'location_view') views,
           count(distinct e.actor_profile_id) filter (where e.event_type = 'location_view') reach,
           0 favs,
           count(*) filter (where e.event_type = 'directions_tap') dir,
           count(*) filter (where e.event_type = 'phone_tap') phone,
           count(*) filter (where e.event_type = 'website_tap') web,
           0 claims, 0 redemptions
      from public.analytics_events e
     where e.target_type = 'location' and e.created_at::date between p_from and p_to
     group by 1,2
    union all
    select fl.location_id, fl.created_at::date, 0,0, count(*), 0,0,0, 0,0
      from public.favorite_locations fl
     where fl.created_at::date between p_from and p_to group by 1,2
    union all
    select d.location_id, cd.claimed_at::date, 0,0, 0, 0,0,0, count(*),
           count(*) filter (where cd.redeemed_at is not null)
      from public.claimed_deals cd join public.deals d on d.id = cd.deal_id
     where cd.claimed_at::date between p_from and p_to group by 1,2
  ) u
  where location_id is not null
  group by location_id, day;

  -- ── Giveaway ───────────────────────────────────────────────────────────────
  delete from public.analytics_daily_giveaway where day between p_from and p_to;

  insert into public.analytics_daily_giveaway (giveaway_id, day, views, reach_accounts, entries)
  select giveaway_id, day, sum(views), max(reach), sum(entries)
  from (
    select e.target_id giveaway_id, e.created_at::date as day,
           count(*) filter (where e.event_type = 'giveaway_view') views,
           count(distinct e.actor_profile_id) filter (where e.event_type = 'giveaway_view') reach,
           0 entries
      from public.analytics_events e
     where e.target_type = 'giveaway' and e.created_at::date between p_from and p_to group by 1,2
    -- giveaway_views predates the events table and is still written by the client.
    union all
    select gv.giveaway_id, gv.created_at::date, count(*), count(distinct gv.profile_id), 0
      from public.giveaway_views gv
     where gv.created_at::date between p_from and p_to group by 1,2
    union all
    select ge.giveaway_id, ge.created_at::date, 0,0, count(*)
      from public.giveaway_entries ge
     where ge.created_at::date between p_from and p_to group by 1,2
  ) u
  where giveaway_id is not null
  group by giveaway_id, day;

  select jsonb_build_object(
    'from', p_from, 'to', p_to,
    'profile_rows', (select count(*) from public.analytics_daily_profile where day between p_from and p_to),
    'post_rows', (select count(*) from public.analytics_daily_post where day between p_from and p_to),
    'product_rows', (select count(*) from public.analytics_daily_product where day between p_from and p_to),
    'location_rows', (select count(*) from public.analytics_daily_location where day between p_from and p_to),
    'giveaway_rows', (select count(*) from public.analytics_daily_giveaway where day between p_from and p_to)
  ) into counts;

  return counts;
end;
$BODY$;

revoke all on function public.analytics_refresh(date, date) from public, anon, authenticated;
