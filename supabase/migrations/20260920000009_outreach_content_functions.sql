-- What the outreach agent is allowed to say, expressed as SQL.
--
-- Every fact in every email comes out of one of these functions, read at send
-- time. Keeping them here rather than in the Edge Function means the joins happen
-- once in the database instead of a dozen PostgREST round trips per contact, and
-- it means the content is reviewable as data rather than as string building.
--
-- All of them return jsonb and all of them are allowed to return an empty section.
-- The sender treats a digest whose sections are all empty as "nothing to say" and
-- does not send it — that is the intended behaviour, not a failure.
--
-- Execute is granted to service_role only. anon and authenticated cannot call
-- these at all, which matters because several of them aggregate across profiles.

-- ─── Which brand profiles a contact speaks for ───────────────────────────────
-- Brands are administered through profile_admins: a brand profile has no login of
-- its own, people are granted admin access to it. So a brand or dispensary contact
-- is a person, and the thing to report on is whatever brand profile they
-- administer. A contact whose profile IS the brand resolves to itself, which is
-- the case when the import knows the brand but not yet who runs it.
create or replace function public.outreach_brand_scope(p_profile_id integer)
returns integer[]
language sql
stable
set search_path = public
as $$
  select coalesce(
    array(
      select p.id from public.profiles p
       where p.id = p_profile_id and p.profile_type = 'brand'
      union
      select pa.managed_profile_id
        from public.profile_admins pa
        join public.profiles mp on mp.id = pa.managed_profile_id
       where pa.admin_profile_id = p_profile_id
         and mp.profile_type = 'brand'
    ),
    array[]::integer[]
  );
$$;

-- The people who administer a brand, so the sender can check it is writing to one
-- of them rather than to an address on the brand record. Email is whatever the
-- profile carries, which on this database is almost never set — the import is the
-- real source of addresses, and this exists to validate, not to harvest.
create or replace function public.outreach_brand_admins(p_brand_profile_id integer)
returns table (profile_id integer, name text, username text, email text)
language sql
stable
set search_path = public
as $$
  select p.id,
         coalesce(p.display_name, p.username),
         p.username,
         nullif(btrim(coalesce(p.contact_email, p.email, '')), '')
    from public.profile_admins pa
    join public.profiles p on p.id = pa.admin_profile_id
   where pa.managed_profile_id = p_brand_profile_id
   order by p.id;
$$;

-- ─── Consumer ────────────────────────────────────────────────────────────────
-- Giveaways, new dispensaries, drops and trending stashlists.
--
-- "Near them" uses the postal code on their profile (profiles.home_location_id
-- points at postal_codes, not at a location) and the PostGIS geography on each
-- location. locations.city and locations.state are empty on every row, so state
-- comes from the joined postal code — going through locations.state would silently
-- match nothing.
create or replace function public.outreach_digest_consumer(
  p_profile_id      integer,
  p_giveaway_ahead  integer default 30,
  p_giveaway_back   integer default 14,
  p_drop_ahead      integer default 30,
  p_drop_back       integer default 14,
  p_new_loc_days    integer default 90,
  p_max             integer default 5
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  home_lat  double precision;
  home_lon  double precision;
  home_state text;
  home_place text;
  result jsonb;
begin
  select pc.latitude, pc.longitude, pc.state_code, pc.place_name
    into home_lat, home_lon, home_state, home_place
    from public.profiles pr
    join public.postal_codes pc on pc.id = pr.home_location_id
   where pr.id = p_profile_id;

  select jsonb_build_object(
    'home', case when home_state is null then null
                 else jsonb_build_object('state', home_state, 'place', home_place) end,

    'giveaways', coalesce((
      select jsonb_agg(x order by (x->>'ends'))
      from (
        select jsonb_build_object(
                 'name', g.name,
                 'ends', g.end_time::date,
                 'ended', (g.end_time < now()),
                 'entries', coalesce(g.entry_count, 0),
                 'prizes', coalesce(g.total_prizes, 0),
                 'drawn', coalesce(g.selected_winner, false),
                 'product', pr.name
               ) x
          from public.giveaways g
          left join public.products pr on pr.id = g.product_id
         where g.status = 'active'
           and g.end_time between now() - make_interval(days => p_giveaway_back)
                              and now() + make_interval(days => p_giveaway_ahead)
         order by g.end_time
         limit p_max
      ) s
    ), '[]'::jsonb),

    -- Dispensaries added in the window. Ordered by distance when we know where
    -- they are, otherwise filtered to their state, otherwise newest first.
    'new_dispensaries', coalesce((
      select jsonb_agg(x order by ord)
      from (
        select jsonb_build_object(
                 'name', l.name,
                 'address', l.address_line1,
                 'state', pc.state_code,
                 'place', pc.place_name,
                 'miles', case when home_lat is null or l.coordinates is null then null
                               else round((ST_Distance(
                                 l.coordinates,
                                 ST_SetSRID(ST_MakePoint(home_lon, home_lat), 4326)::geography
                               ) / 1609.344)::numeric, 1) end,
                 'added', l.created_at::date
               ) x,
               case when home_lat is null or l.coordinates is null
                    then extract(epoch from (now() - l.created_at))
                    else ST_Distance(l.coordinates,
                           ST_SetSRID(ST_MakePoint(home_lon, home_lat), 4326)::geography)
               end ord
          from public.locations l
          left join public.postal_codes pc on pc.id = l.postal_code_id
         where l.status in ('published', 'active')
           and l.created_at > now() - make_interval(days => p_new_loc_days)
           and (home_lat is not null or home_state is null or pc.state_code = home_state)
         order by ord
         limit p_max
      ) s
    ), '[]'::jsonb),

    'drops', coalesce((
      select jsonb_agg(x order by (x->>'release'))
      from (
        select jsonb_build_object(
                 'name', p.name,
                 'brand', nullif(p.cached_brand_names, ''),
                 'release', p.release_date::date,
                 'released', (p.release_date <= now())
               ) x
          from public.products p
         where p.status = 'published'
           and p.release_date between now() - make_interval(days => p_drop_back)
                                  and now() + make_interval(days => p_drop_ahead)
         order by p.release_date
         limit p_max
      ) s
    ), '[]'::jsonb),

    -- Ranked by total subscribers. There is no subscription history table, so this
    -- is "most subscribed", not "rising fastest" — the email must not call it that.
    'trending_lists', coalesce((
      select jsonb_agg(x order by (x->>'subscribers')::int desc)
      from (
        select jsonb_build_object(
                 'name', li.name,
                 'subscribers', coalesce(li.subscription_count, 0),
                 'products', coalesce(li.product_count, 0),
                 'by', coalesce(au.display_name, au.username)
               ) x
          from public.lists li
          left join public.profiles au on au.id = li.profile_id
         where li.is_private is not true
           and coalesce(li.subscription_count, 0) > 0
         order by li.subscription_count desc nulls last
         limit p_max
      ) s
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

-- ─── Creator ─────────────────────────────────────────────────────────────────
-- Their own numbers. A restash is a stash that happened because of them — from one
-- of their posts, one of their lists, or their profile — which is what stash's
-- restash_post_id / restash_list_id / restash_profile_id record.
create or replace function public.outreach_digest_creator(
  p_profile_id integer,
  p_window_days integer default 30,
  p_max integer default 5
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  since timestamptz := now() - make_interval(days => p_window_days);
  result jsonb;
begin
  select jsonb_build_object(
    'window_days', p_window_days,
    'followers_total', coalesce(pr.follower_count, 0),
    'followers_gained', (
      select count(*) from public.relationships r
       where r.followee_id = p_profile_id and r.created_at > since
    ),
    'restash_total', coalesce(pr.restash_count, 0),
    'restashes_window', (
      select count(*) from public.stash s
       where s.created_at > since
         and (s.restash_profile_id = p_profile_id
              or s.restash_post_id in (select id from public.posts where profile_id = p_profile_id)
              or s.restash_list_id in (select id from public.lists where profile_id = p_profile_id))
    ),
    'restash_sources', jsonb_build_object(
      'from_posts', (select count(*) from public.stash s
                      where s.created_at > since
                        and s.restash_post_id in (select id from public.posts where profile_id = p_profile_id)),
      'from_lists', (select count(*) from public.stash s
                      where s.created_at > since
                        and s.restash_list_id in (select id from public.lists where profile_id = p_profile_id)),
      'from_profile', (select count(*) from public.stash s
                        where s.created_at > since and s.restash_profile_id = p_profile_id)
    ),
    'posts_window', (
      select count(*) from public.posts p
       where p.profile_id = p_profile_id and p.created_at > since
    ),
    'top_posts', coalesce((
      select jsonb_agg(x order by (x->>'likes')::int desc)
      from (
        select jsonb_build_object(
                 'excerpt', left(coalesce(p.message, ''), 80),
                 'likes', coalesce(p.like_count, 0),
                 'comments', coalesce(p.comment_count, 0),
                 'tagged_products', coalesce(p.tag_count, 0),
                 'posted', p.created_at::date
               ) x
          from public.posts p
         where p.profile_id = p_profile_id and p.created_at > since
         order by p.like_count desc nulls last
         limit p_max
      ) s
    ), '[]'::jsonb),
    'lists', coalesce((
      select jsonb_agg(x order by (x->>'subscribers')::int desc)
      from (
        select jsonb_build_object(
                 'name', li.name,
                 'subscribers', coalesce(li.subscription_count, 0),
                 'products', coalesce(li.product_count, 0)
               ) x
          from public.lists li
         where li.profile_id = p_profile_id and li.is_private is not true
         order by li.subscription_count desc nulls last
         limit p_max
      ) s
    ), '[]'::jsonb),
    'activity', public.outreach_recent_activity(p_profile_id, p_window_days, p_max)
  ) into result
  from public.profiles pr
  where pr.id = p_profile_id;

  return coalesce(result, '{}'::jsonb);
end;
$$;

-- ─── Notifications, reused rather than recomputed ────────────────────────────
-- The app already writes an event row for a new follower, a restash, a milestone,
-- a giveaway result and so on. Counting those by type is both cheaper and closer
-- to what the person saw in the app than recomputing each one from source.
create or replace function public.outreach_recent_activity(
  p_profile_id integer,
  p_window_days integer default 30,
  p_max integer default 8
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(jsonb_agg(x order by (x->>'count')::int desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
             'type', nt.code,
             'label', nt.name,
             'category', nt.category::text,
             'count', count(*)
           ) x
      from public.notifications n
      join public.notification_types nt on nt.id = n.type_id
     where n.profile_id = p_profile_id
       and n.created_at > now() - make_interval(days => p_window_days)
       and (n.expires_at is null or n.expires_at > now())
     group by nt.code, nt.name, nt.category
     order by count(*) desc
     limit p_max
  ) s;
$$;

-- ─── Brand ───────────────────────────────────────────────────────────────────
-- How the brand's products are doing. Scoped through outreach_brand_scope, so a
-- contact who administers two brands gets both.
create or replace function public.outreach_digest_brand(
  p_profile_id integer,
  p_window_days integer default 30,
  p_max integer default 5
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  brands integer[] := public.outreach_brand_scope(p_profile_id);
  since timestamptz := now() - make_interval(days => p_window_days);
  result jsonb;
begin
  if brands is null or array_length(brands, 1) is null then
    return jsonb_build_object('brands', '[]'::jsonb, 'unresolved', true);
  end if;

  select jsonb_build_object(
    'window_days', p_window_days,
    'brands', coalesce((
      select jsonb_agg(jsonb_build_object('id', b.id, 'name', coalesce(b.display_name, b.username)))
        from public.profiles b where b.id = any(brands)
    ), '[]'::jsonb),
    'products_total', (
      select count(distinct pb.product_id) from public.product_brands pb
       where pb.brand_id = any(brands)
    ),
    'stash_total', (
      select coalesce(sum(p.stash_count), 0) from public.products p
       where p.id in (select product_id from public.product_brands where brand_id = any(brands))
    ),
    'stashes_window', (
      select count(*) from public.stash s
       where s.created_at > since
         and s.product_id in (select product_id from public.product_brands where brand_id = any(brands))
    ),
    'list_appearances', (
      select count(*) from public.lists_products lp
       where lp.product_id in (select product_id from public.product_brands where brand_id = any(brands))
    ),
    'posts_tagging_total', (
      select count(distinct pp.post_id) from public.posts_products pp
       where pp.product_id in (select product_id from public.product_brands where brand_id = any(brands))
    ),
    'posts_tagging_window', (
      select count(distinct pp.post_id)
        from public.posts_products pp
        join public.posts po on po.id = pp.post_id
       where po.created_at > since
         and pp.product_id in (select product_id from public.product_brands where brand_id = any(brands))
    ),
    'top_products', coalesce((
      select jsonb_agg(x order by (x->>'stashes')::int desc)
      from (
        select jsonb_build_object(
                 'name', p.name,
                 'stashes', coalesce(p.stash_count, 0),
                 'lists', coalesce(p.list_count, 0),
                 'posts', coalesce(p.post_count, 0)
               ) x
          from public.products p
         where p.id in (select product_id from public.product_brands where brand_id = any(brands))
           and coalesce(p.stash_count, 0) > 0
         order by p.stash_count desc nulls last
         limit p_max
      ) s
    ), '[]'::jsonb),
    -- Giveaway results, where the brand ran one. Reported exactly as recorded:
    -- entry counts and whether a winner has been drawn, nothing inferred.
    'giveaways', coalesce((
      select jsonb_agg(x order by (x->>'ends') desc)
      from (
        select jsonb_build_object(
                 'name', g.name,
                 'ends', g.end_time::date,
                 'ended', (g.end_time < now()),
                 'entries', coalesce(g.entry_count, 0),
                 'prizes', coalesce(g.total_prizes, 0),
                 'winners_drawn', coalesce(g.winner_count, 0),
                 'drawn', coalesce(g.selected_winner, false)
               ) x
          from public.giveaways g
         where g.created_by_profile_id = any(brands)
         order by g.end_time desc
         limit p_max
      ) s
    ), '[]'::jsonb),
    'activity', public.outreach_recent_activity(p_profile_id, p_window_days, p_max)
  ) into result;

  return result;
end;
$$;

-- ─── Dispensary ──────────────────────────────────────────────────────────────
-- A dispensary is a locations row owned by a brand profile, so the scope is the
-- same as a brand's and the locations hang off it.
create or replace function public.outreach_digest_dispensary(
  p_profile_id integer,
  p_max integer default 5
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  brands integer[] := public.outreach_brand_scope(p_profile_id);
  locs integer[];
  result jsonb;
begin
  if brands is null or array_length(brands, 1) is null then
    return jsonb_build_object('locations', '[]'::jsonb, 'unresolved', true);
  end if;

  select array_agg(id) into locs from public.locations where brand_id = any(brands);
  if locs is null then
    return jsonb_build_object('locations', '[]'::jsonb, 'unresolved', true);
  end if;

  select jsonb_build_object(
    'locations', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', l.name,
               'address', l.address_line1,
               'state', pc.state_code,
               'place', pc.place_name,
               'claimed', coalesce(l.is_claimed, false),
               'verified', coalesce(l.is_verified, false),
               'has_hours', (l.operating_hours is not null and l.operating_hours::text not in ('null', '{}', '[]')),
               'has_phone', (nullif(btrim(coalesce(l.phone, '')), '') is not null),
               'has_website', (nullif(btrim(coalesce(l.website, '')), '') is not null),
               'has_description', (nullif(btrim(coalesce(l.description, '')), '') is not null)
             ))
        from public.locations l
        left join public.postal_codes pc on pc.id = l.postal_code_id
       where l.id = any(locs)
    ), '[]'::jsonb),
    'staff_count', (
      select count(*) from public.location_employees
       where location_id = any(locs) and is_approved
    ),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', coalesce(p.display_name, p.username),
               'role', coalesce(le.role, 'budtender')
             ))
        from public.location_employees le
        join public.profiles p on p.id = le.profile_id
       where le.location_id = any(locs) and le.is_approved
       limit p_max
    ), '[]'::jsonb),
    -- Actionable: somebody has asked to be added and is waiting on them.
    'pending_staff_requests', (
      select count(*) from public.location_employees
       where location_id = any(locs) and is_approved is not true
    ),
    'featured_stashlists', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', li.name,
               'products', coalesce(li.product_count, 0),
               'subscribers', coalesce(li.subscription_count, 0)
             ))
        from public.location_stashlists ls
        join public.lists li on li.id = ls.list_id
       where ls.location_id = any(locs)
       limit p_max
    ), '[]'::jsonb),
    'active_deals', coalesce((
      select jsonb_agg(jsonb_build_object(
               'title', d.title,
               'claims', coalesce(d.claim_count, 0),
               'max_claims', d.max_claims,
               'ends', d.end_date::date
             ))
        from public.deals d
       where d.location_id = any(locs)
         and d.is_active
         and (d.end_date is null or d.end_date > now())
       limit p_max
    ), '[]'::jsonb),
    'activity', public.outreach_recent_activity(p_profile_id, 30, p_max)
  ) into result;

  return result;
end;
$$;

-- ─── Profile completeness ────────────────────────────────────────────────────
-- One nudge per email, so this returns the missing items in priority order and the
-- caller takes the first. Weight is "how much does filling this in change what the
-- rest of the app can do for you", not how easy it is.
create or replace function public.outreach_profile_completeness(
  p_profile_id integer,
  p_segment text default 'consumer'
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  pr record;
  missing jsonb := '[]'::jsonb;
  brands integer[];
  locs integer[];
  add_item text;
begin
  select * into pr from public.profiles where id = p_profile_id;
  if not found then
    return jsonb_build_object('found', false, 'complete', false, 'missing', '[]'::jsonb);
  end if;

  -- Universal, highest value first: a nameless, faceless profile is the one nobody
  -- follows back.
  if pr.avatar_id is null then
    missing := missing || jsonb_build_object('field', 'avatar', 'label', 'a profile photo', 'weight', 100);
  end if;
  if nullif(btrim(coalesce(pr.display_name, '')), '') is null then
    missing := missing || jsonb_build_object('field', 'display_name', 'label', 'a display name', 'weight', 95);
  end if;
  if nullif(btrim(coalesce(pr.bio, '')), '') is null then
    missing := missing || jsonb_build_object('field', 'bio', 'label', 'a short bio', 'weight', 80);
  end if;
  if pr.social_links is null or pr.social_links::text in ('null', '{}', '[]') then
    missing := missing || jsonb_build_object('field', 'social_links', 'label', 'your social links', 'weight', 40);
  end if;

  if p_segment = 'consumer' then
    if pr.onboarding_completed_at is null then
      missing := missing || jsonb_build_object('field', 'onboarding', 'label', 'the short setup in the app', 'weight', 90);
    end if;
    if pr.preferred_category_ids is null or array_length(pr.preferred_category_ids, 1) is null then
      missing := missing || jsonb_build_object('field', 'preferred_categories', 'label', 'what you like to consume, so the feed leans that way', 'weight', 60);
    end if;
    if coalesce(pr.following_count, 0) = 0 then
      missing := missing || jsonb_build_object('field', 'following', 'label', 'following a brand or a shop, so the feed has something in it', 'weight', 85);
    end if;
    if coalesce(pr.stash_count, 0) = 0 then
      missing := missing || jsonb_build_object('field', 'stash', 'label', 'stashing your first product', 'weight', 70);
    end if;

  elsif p_segment = 'creator' then
    if not exists (select 1 from public.lists where profile_id = p_profile_id and is_private is not true) then
      missing := missing || jsonb_build_object('field', 'stashlist', 'label', 'your first public stashlist', 'weight', 92);
    end if;
    if coalesce(pr.post_count, 0) = 0 then
      missing := missing || jsonb_build_object('field', 'posts', 'label', 'your first post', 'weight', 88);
    end if;

  elsif p_segment = 'brand' then
    brands := public.outreach_brand_scope(p_profile_id);
    if brands is null or array_length(brands, 1) is null then
      missing := missing || jsonb_build_object('field', 'brand_access', 'label', 'admin access to your brand profile', 'weight', 99);
    elsif not exists (select 1 from public.product_brands where brand_id = any(brands)) then
      missing := missing || jsonb_build_object('field', 'products', 'label', 'your products on your brand page', 'weight', 98);
    end if;

  elsif p_segment = 'dispensary' then
    brands := public.outreach_brand_scope(p_profile_id);
    select array_agg(id) into locs from public.locations where brand_id = any(coalesce(brands, array[]::integer[]));
    if locs is null then
      missing := missing || jsonb_build_object('field', 'location', 'label', 'claiming your shop''s location page', 'weight', 99);
    else
      if exists (select 1 from public.locations
                  where id = any(locs)
                    and (operating_hours is null or operating_hours::text in ('null', '{}', '[]'))) then
        missing := missing || jsonb_build_object('field', 'hours', 'label', 'your opening hours', 'weight', 94);
      end if;
      if not exists (select 1 from public.location_employees
                      where location_id = any(locs) and is_approved) then
        missing := missing || jsonb_build_object('field', 'staff', 'label', 'your budtenders on your shop page', 'weight', 86);
      end if;
      if exists (select 1 from public.locations
                  where id = any(locs) and nullif(btrim(coalesce(description, '')), '') is null) then
        missing := missing || jsonb_build_object('field', 'shop_description', 'label', 'a description of your shop', 'weight', 62);
      end if;
    end if;
  end if;

  -- Ordered so the caller can take the first and be right.
  select coalesce(jsonb_agg(m order by (m->>'weight')::int desc), '[]'::jsonb)
    into missing
    from jsonb_array_elements(missing) m;

  select missing->0->>'field' into add_item;

  return jsonb_build_object(
    'found', true,
    'complete', jsonb_array_length(missing) = 0,
    'missing', missing,
    'top', case when add_item is null then null else missing->0 end
  );
end;
$$;

-- ─── Lock them to service_role ───────────────────────────────────────────────
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.outreach_brand_scope(integer)',
    'public.outreach_brand_admins(integer)',
    'public.outreach_digest_consumer(integer,integer,integer,integer,integer,integer,integer)',
    'public.outreach_digest_creator(integer,integer,integer)',
    'public.outreach_recent_activity(integer,integer,integer)',
    'public.outreach_digest_brand(integer,integer,integer)',
    'public.outreach_digest_dispensary(integer,integer)',
    'public.outreach_profile_completeness(integer,text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
