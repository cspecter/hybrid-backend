-- outreach_digest_consumer could not run: PostGIS is installed in the `extensions`
-- schema on this project, and the function set search_path to public alone, so
-- `geography` and ST_Distance were not resolvable. Every call failed with
-- `type "geography" does not exist`.
--
-- Recreated with extensions on the search path. This is the only outreach function
-- that touches PostGIS, so the others keep the narrower path.

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
set search_path = public, extensions
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

revoke all on function public.outreach_digest_consumer(integer,integer,integer,integer,integer,integer,integer)
  from public, anon, authenticated;
grant execute on function public.outreach_digest_consumer(integer,integer,integer,integer,integer,integer,integer)
  to service_role;
