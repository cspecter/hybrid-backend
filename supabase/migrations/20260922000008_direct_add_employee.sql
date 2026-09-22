-- Adding a budtender on the spot, without a request and without a manager.
--
-- The permission already existed: location_employees_guard only forces a row to
-- 'pending' when the caller CANNOT manage the location, so a super admin inserting
-- an approved row was always allowed. What was missing was a way to do it — the only
-- entry point was the budtender tapping "I work here" and someone finding that
-- request later. On site, converting twenty budtenders meant twenty round trips.
--
-- Two gaps this closes:
--
--  1. No RPC to add someone by handle. The client had no way to say "this person,
--     this store, approved" without knowing internal ids.
--  2. notify_employee_of_approval fires AFTER UPDATE only, so a row inserted already
--     approved told the new budtender nothing. They would get the badge and the
--     posting rights with no idea why. That is fixed here rather than in the RPC, so
--     it holds for any path that inserts an approved row.

-- ── Tell someone they were added, however it happened ──────────────────────
create or replace function public.notify_employee_added_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_location_name text;
begin
  if new.is_approved is not true then
    return new;
  end if;
  select name into v_location_name from public.locations where id = new.location_id;
  perform public.send_notification(
    new.profile_id,
    'employee_approved',
    null,
    'location',
    new.location_id,
    jsonb_build_object('location_name', v_location_name, 'role', coalesce(new.role, 'budtender')));
  return new;
end;
$$;

revoke execute on function public.notify_employee_added_on_insert() from public;

drop trigger if exists on_employee_added on public.location_employees;
create trigger on_employee_added
  after insert on public.location_employees
  for each row execute function public.notify_employee_added_on_insert();

-- ── Add by handle ──────────────────────────────────────────────────────────
-- Takes the username the person can read off their own profile, so whoever is doing
-- the onboarding needs nothing but their screen.
create or replace function public.add_location_employee(
  p_location_id uuid,
  p_username text,
  p_role text default 'budtender')
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_location_id integer;
  v_profile     public.profiles%rowtype;
  v_role        text := lower(trim(coalesce(p_role, 'budtender')));
  v_handle      text := lower(regexp_replace(coalesce(p_username, ''), '^@', ''));
begin
  if v_role not in ('budtender', 'manager', 'staff') then
    raise exception 'Unknown employee role: %', p_role using errcode = '22023';
  end if;

  select id into v_location_id from public.locations where public_id = p_location_id;
  if v_location_id is null then
    raise exception 'Store not found' using errcode = 'P0002';
  end if;

  -- The same two rules as approving a request, so there is no way in through the
  -- side door: managing the store for budtender/staff, and the stricter
  -- can_grant_manager for manager — a store manager still cannot mint another.
  if v_role = 'manager' then
    if not public.can_grant_manager(v_location_id) then
      raise exception 'Only Hybrid moderation or the brand can add a store manager' using errcode = '42501';
    end if;
  elsif not public.can_manage_location(v_location_id) then
    raise exception 'You do not manage that location' using errcode = '42501';
  end if;

  select * into v_profile from public.profiles where lower(username) = v_handle limit 1;
  if v_profile.id is null then
    raise exception 'No account with the handle @%', v_handle using errcode = 'P0002';
  end if;

  -- Adding yourself is the self-approval ban wearing a different hat.
  if v_profile.id = public.current_actor_id() and not public.is_super_admin() then
    raise exception 'You cannot add yourself' using errcode = '42501';
  end if;

  insert into public.location_employees (location_id, profile_id, role, is_approved, has_been_reviewed)
  values (v_location_id, v_profile.id, v_role, true, true)
  on conflict (location_id, profile_id) do update
     set role = excluded.role,
         is_approved = true,
         has_been_reviewed = true;

  return jsonb_build_object(
    'profile_id', v_profile.id,
    'name', coalesce(v_profile.display_name, v_profile.username),
    'handle', '@' || v_profile.username,
    'role', v_role);
end;
$$;

revoke execute on function public.add_location_employee(uuid, text, text) from public;
grant execute on function public.add_location_employee(uuid, text, text) to authenticated;

-- ── Finding the person ─────────────────────────────────────────────────────
-- Handle search limited to people who could actually be added: no brands, and
-- nobody already approved at that store. Gated to callers who manage the store so
-- it cannot be used as a general user-directory scraper.
create or replace function public.search_addable_employees(p_location_id uuid, p_query text)
returns table (username text, display_name text, profile_id integer, avatar_id integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_location_id integer;
  v_q text := lower(regexp_replace(coalesce(p_query, ''), '^@', ''));
begin
  select id into v_location_id from public.locations where public_id = p_location_id;
  if v_location_id is null or not public.can_manage_location(v_location_id) then
    return;
  end if;
  if length(v_q) < 2 then
    return;
  end if;
  return query
    select p.username, coalesce(p.display_name, p.username), p.id, p.avatar_id
      from public.profiles p
     where p.profile_type <> 'brand'
       and p.auth_id is not null
       and (lower(p.username) like v_q || '%' or lower(coalesce(p.display_name,'')) like '%' || v_q || '%')
       and not exists (
         select 1 from public.location_employees le
          where le.location_id = v_location_id and le.profile_id = p.id and le.is_approved is true)
     order by (lower(p.username) = v_q) desc, lower(p.username)
     limit 10;
end;
$$;

revoke execute on function public.search_addable_employees(uuid, text) from public;
grant execute on function public.search_addable_employees(uuid, text) to authenticated;
