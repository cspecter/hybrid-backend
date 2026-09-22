-- Who may ask to work at a store, and who may say yes.
--
-- The store-takeover bug in 8d8a6b9 was an insert that arrived already approved.
-- That is closed at the policy level, but the policy only covers INSERT and only
-- covers the columns it names, so the same class of mistake can still arrive via
-- UPDATE — and one rule the brief asks for (a manager must not be able to mint
-- another manager) cannot be expressed in a WITH CHECK at all, because it depends
-- on OLD as well as NEW. Hence a trigger, with the policy kept as the outer fence.

-- ── Who may grant the manager role ─────────────────────────────────────────
-- can_manage_location() deliberately includes approved managers, because that is
-- the right answer for editing the store. It is the wrong answer for granting
-- manager: a manager controls the whole store page, so promoting someone is a
-- higher-trust act than anything a manager does day to day. This is the same set
-- MINUS is_location_manager().
create or replace function public.can_grant_manager(p_location_id integer)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_location_id is not null
     and (
       public.is_super_admin()
       or exists (
           select 1 from public.locations l
            where l.id = p_location_id and l.brand_id = public.current_actor_id())
       or exists (
           select 1 from public.locations l
             join public.profile_admins pa on pa.managed_profile_id = l.brand_id
            where l.id = p_location_id and pa.admin_profile_id = public.current_actor_id())
     );
$$;

revoke execute on function public.can_grant_manager(integer) from public;
grant execute on function public.can_grant_manager(integer) to authenticated, service_role;

create or replace function public.location_employees_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_jwt_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  v_actor    integer;
begin
  -- Same bypass as update_employee_approval and the profiles guard: only
  -- anon/authenticated PostgREST traffic is policed. Migrations and seeds insert
  -- approved rows on purpose and must keep working.
  if v_jwt_role not in ('anon', 'authenticated') then
    return new;
  end if;

  v_actor := public.current_actor_id();

  if tg_op = 'INSERT' then
    if not public.can_manage_location(new.location_id) then
      -- A self-request. It is for yourself, it is one of the roles a person can ask
      -- for, and it arrives undecided — belt and braces over the INSERT policy,
      -- because this is the exact shape of the takeover bug.
      if new.profile_id is distinct from v_actor then
        raise exception 'You can only ask to work somewhere as yourself' using errcode = '42501';
      end if;
      if coalesce(new.role, 'staff') not in ('budtender', 'manager', 'staff') then
        raise exception 'Unknown employee role: %', new.role using errcode = '22023';
      end if;
      new.is_approved      := false;
      new.has_been_reviewed := false;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    -- Only the moment of approval is policed. Rejections, and edits that leave
    -- is_approved alone, fall through.
    if new.is_approved is true and old.is_approved is not true then
      if new.profile_id = v_actor and not public.is_super_admin() then
        raise exception 'You cannot approve your own request to work somewhere' using errcode = '42501';
      end if;
      if coalesce(new.role, 'staff') = 'manager' and not public.can_grant_manager(new.location_id) then
        raise exception 'Only Hybrid moderation or the brand can approve a store manager' using errcode = '42501';
      end if;
      if coalesce(new.role, 'staff') <> 'manager' and not public.can_manage_location(new.location_id) then
        raise exception 'You do not manage that location' using errcode = '42501';
      end if;
    end if;

    -- Promotion by edit is the same grant wearing a different hat.
    if new.role is distinct from old.role and coalesce(new.role,'staff') = 'manager'
       and new.is_approved is true and not public.can_grant_manager(new.location_id) then
      raise exception 'Only Hybrid moderation or the brand can make someone a store manager' using errcode = '42501';
    end if;

    return new;
  end if;

  return new;
end;
$$;

revoke execute on function public.location_employees_guard() from public;

drop trigger if exists trg_location_employees_guard on public.location_employees;
create trigger trg_location_employees_guard
  before insert or update on public.location_employees
  for each row execute function public.location_employees_guard();

-- The INSERT policy gains 'manager' as a role someone may ASK for — asking is not
-- getting, and the guard above plus can_grant_manager() decide the getting. It
-- also now pins has_been_reviewed, so a self-request cannot arrive pre-decided by
-- either column.
drop policy if exists "Enable insert for authenticated users only" on public.location_employees;
create policy "Enable insert for authenticated users only"
  on public.location_employees
  for insert
  with check (
    public.can_manage_location(location_id)
    or (
      profile_id = public.current_actor_id()
      and is_approved is not true
      and has_been_reviewed is not true
      and role = any (array['budtender'::text, 'manager'::text, 'staff'::text])
    )
  );

-- update_employee_approval is the only path the client uses to decide a request.
-- It gains the same two rules, so a caller gets a clear message instead of a
-- trigger exception, and so the rules hold even if the RPC is called directly.
create or replace function public.update_employee_approval(
  p_location_id uuid, p_profile_id uuid, p_is_approved boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_jwt_role    text;
  v_location_id integer;
  v_profile_id  integer;
  v_role        text;
begin
  v_jwt_role := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');

  select id into v_location_id from public.locations where public_id = p_location_id;
  select id into v_profile_id  from public.profiles  where public_id = p_profile_id;
  if v_location_id is null or v_profile_id is null then
    raise exception 'Location or profile not found' using errcode = 'P0002';
  end if;

  select role into v_role from public.location_employees
   where location_id = v_location_id and profile_id = v_profile_id;
  if v_role is null then
    raise exception 'No employment request from that person at that store' using errcode = 'P0002';
  end if;

  if v_jwt_role in ('anon', 'authenticated') then
    if v_profile_id = public.current_actor_id() and not public.is_super_admin() then
      raise exception 'You cannot approve your own request to work somewhere' using errcode = '42501';
    end if;
    -- A manager request is the brand's or moderation's call, never another
    -- manager's. Everything else is the ordinary store-management rule.
    if p_is_approved and coalesce(v_role, 'staff') = 'manager' then
      if not public.can_grant_manager(v_location_id) then
        raise exception 'Only Hybrid moderation or the brand can approve a store manager' using errcode = '42501';
      end if;
    elsif not public.can_manage_location(v_location_id) then
      raise exception 'You do not manage that location' using errcode = '42501';
    end if;
  end if;

  update public.location_employees
     set has_been_reviewed = true,
         is_approved       = p_is_approved
   where location_id = v_location_id
     and profile_id  = v_profile_id;
end;
$$;

revoke execute on function public.update_employee_approval(uuid, uuid, boolean) from public;
grant execute on function public.update_employee_approval(uuid, uuid, boolean) to authenticated, service_role;
