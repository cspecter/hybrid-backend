-- `v_types := v_types || 'budtender'` made plpgsql parse the string as an array
-- literal — "malformed array literal: budtender". The || operator on text[] wants an
-- array or an explicitly typed element; a bare quoted literal is neither. Caught on
-- the first behavioural call, not by the migration, because plpgsql only resolves it
-- at run time. array_append says what is meant and cannot be read two ways.
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
    select c.post_id, c.public_id, c.name
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
