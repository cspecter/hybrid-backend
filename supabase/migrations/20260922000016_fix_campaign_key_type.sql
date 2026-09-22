create or replace function public.sponsored_posts_for_me(p_limit integer default 5)
returns table (post_id integer, campaign_id uuid, campaign_name text, campaign_key integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- sponsored_campaigns.id is bigint (generated always as identity), but
-- analytics_events.target_id is integer — which is the column this value exists to
-- be written into. Casting here rather than widening target_id keeps the analytics
-- table's shape alone and makes the narrowing explicit at the one place that knows
-- why it is safe: this is a campaign counter, not a row id from a hot table.
declare
  v_me     integer := public.current_actor_id();
  v_state  text;
  v_types  text[] := '{}';
begin
  if v_me is null then
    return query
      select c.post_id, c.public_id, c.name, c.id::integer
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
    select c.post_id, c.public_id, c.name, c.id::integer
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

-- Same narrowing on the join, so a campaign's events are found by the same integer
-- the feed handed out.
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
     and e.target_id = c.id::integer
     and e.created_at > now() - make_interval(days => greatest(coalesce(p_days, 30), 1))
   where public.is_super_admin()
   group by c.public_id;
$$;

revoke execute on function public.sponsored_campaign_stats(integer) from public;
grant execute on function public.sponsored_campaign_stats(integer) to authenticated;
