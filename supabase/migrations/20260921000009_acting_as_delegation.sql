-- Acting as a managed profile.
--
-- THE PROBLEM. is_location_manager, can_manage_location and everything downstream
-- resolve identity from auth.uid(), and can_manage_location short-circuits on
-- is_super_admin() before it looks at anything else. So a super admin who switches
-- the client into "Test Budtender" is still a super admin server-side: the persona
-- changes what the app draws and nothing about what the database permits. It tests
-- the UI and nothing else.
--
-- THE FIX. A session-scoped delegation: while a row exists here, every identity
-- check resolves to the acted-as profile instead of the caller's own, INCLUDING
-- is_super_admin(), which is the whole point — a super admin acting as a budtender
-- must lose super-admin powers or the persona is theatre.
--
-- SCOPE. act_as() refuses unless the caller is a profile_admin of the target, and
-- refuses any target that is itself a super admin, so this can only ever reduce
-- privilege. A row older than the expiry is ignored, so a forgotten switch cannot
-- lock a real admin out of their own account; stop_acting_as() never depends on
-- is_super_admin() and so always works.

create table if not exists public.acting_as (
  auth_id    uuid primary key,
  profile_id integer not null references public.profiles(id) on delete cascade,
  set_at     timestamptz not null default now()
);

alter table public.acting_as enable row level security;
revoke all on public.acting_as from anon, authenticated, public;
grant all on public.acting_as to service_role;

-- Twelve hours. Long enough for a working day of testing, short enough that a
-- forgotten row resolves itself overnight.
create or replace function public.acting_profile_id()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select a.profile_id
    from public.acting_as a
   where a.auth_id = auth.uid()
     and a.set_at > now() - interval '12 hours'
     -- Re-checked on every call, not just at act_as time: losing admin rights over
     -- a profile must end the delegation immediately, not at the next switch.
     and exists (
       select 1 from public.profile_admins pa
        join public.profiles me on me.id = pa.admin_profile_id
       where me.auth_id = auth.uid() and pa.managed_profile_id = a.profile_id)
   limit 1;
$$;

/** The profile every permission check should resolve to: the persona, or yourself. */
create or replace function public.current_actor_id()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.acting_profile_id(),
    (select id from public.profiles where auth_id = auth.uid() limit 1)
  );
$$;

-- ─── The identity checks, rewritten to go through current_actor_id() ─────────

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- While acting as someone, you are that someone. act_as refuses a target that is
  -- itself a super admin, so this branch always denies — deliberately.
  select case
    when public.acting_profile_id() is not null then exists (
      select 1 from public.super_admins sa
       join public.profiles p on p.auth_id = sa.auth_id
      where p.id = public.acting_profile_id())
    else exists (select 1 from public.super_admins where auth_id = auth.uid())
  end;
$$;

create or replace function public.is_location_manager(p_location_id integer)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.location_employees le
     where le.profile_id = public.current_actor_id()
       and le.location_id = p_location_id
       and le.role = 'manager'
       and le.is_approved is true
  );
$$;

create or replace function public.can_manage_location(p_location_id integer)
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
       or public.is_location_manager(p_location_id)
     );
$$;

-- ─── Switching ───────────────────────────────────────────────────────────────

create or replace function public.act_as(p_profile_id integer)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  me integer;
  target_is_super boolean;
begin
  if p_profile_id is null then
    delete from public.acting_as where auth_id = auth.uid();
    return jsonb_build_object('acting_as', null);
  end if;

  select id into me from public.profiles where auth_id = auth.uid() limit 1;
  if me is null then raise exception 'No profile for this session'; end if;

  -- Only a profile_admin of the target may act as it. Checked against the real
  -- caller, not current_actor_id(), so acting as one persona cannot be used to hop
  -- into another.
  if not exists (
    select 1 from public.profile_admins
     where admin_profile_id = me and managed_profile_id = p_profile_id
  ) then
    raise exception 'You do not manage that profile';
  end if;

  -- This may only ever reduce privilege.
  select exists (
    select 1 from public.super_admins sa
      join public.profiles p on p.auth_id = sa.auth_id
     where p.id = p_profile_id) into target_is_super;
  if target_is_super then raise exception 'Cannot act as a super admin'; end if;

  insert into public.acting_as (auth_id, profile_id, set_at)
  values (auth.uid(), p_profile_id, now())
  on conflict (auth_id) do update set profile_id = excluded.profile_id, set_at = now();

  return jsonb_build_object('acting_as', p_profile_id);
end;
$$;

create or replace function public.stop_acting_as()
returns jsonb
language sql
volatile
security definer
set search_path = public
as $$
  delete from public.acting_as where auth_id = auth.uid()
  returning jsonb_build_object('acting_as', null);
$$;

/** What the client shows in the TEST badge, and how it recovers after a reload. */
create or replace function public.acting_as_status()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'acting_as', public.acting_profile_id(),
    'name', (select coalesce(display_name, username) from public.profiles
              where id = public.acting_profile_id()),
    'is_super_admin', public.is_super_admin());
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'public.acting_profile_id()', 'public.current_actor_id()',
    'public.act_as(integer)', 'public.stop_acting_as()', 'public.acting_as_status()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
end $$;

grant execute on function public.act_as(integer)      to authenticated;
grant execute on function public.stop_acting_as()     to authenticated;
grant execute on function public.acting_as_status()   to authenticated;
grant execute on function public.current_actor_id()   to authenticated;
