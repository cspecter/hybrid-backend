-- Stop a signed-in user from granting themselves any account type.
--
-- FOUND WHILE AUDITING, NOT IN THE BRIEF, FIXED ANYWAY because everything below
-- depends on it. The profiles UPDATE policy only ever checked *who* owns the row:
--
--   using/with check: auth.uid() = auth_id  or  caller is a profile_admin of it
--
-- Nothing constrained WHICH COLUMNS change. So any signed-in user could run
--
--   update profiles set role_id = 9 where auth_id = auth.uid()
--
-- from the browser with the public anon key, and trg_sync_super_admin would then
-- insert them into super_admins — which is what is_super_admin() reads, which is
-- what the "Super admins can do everything" policy on ~60 tables reads. Verified
-- behaviourally against production inside a rolled-back transaction: the update
-- was accepted, role_id became 9, and the row landed in super_admins.
--
-- A WITH CHECK clause cannot fix this: it only sees NEW, so it cannot tell a
-- change from a no-op. This has to be a BEFORE UPDATE trigger comparing OLD.
--
-- Scope of the lock: role_id, profile_type, is_verified and auth_id. The first two
-- decide what the account IS and, after 20260922000002, whether it may post;
-- is_verified drives the verified badge; auth_id is the identity the whole RLS
-- layer keys on, so letting it move would let someone re-point a profile at
-- themselves.
create or replace function public.profiles_guard_privilege_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_jwt_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
begin
  -- Only PostgREST traffic is under suspicion. Migrations, seeds, cron and Edge
  -- Functions on service_role arrive with no anon/authenticated claim and are the
  -- supported way to change these columns — the same test update_employee_approval
  -- already uses, kept identical so there is one rule to reason about.
  if v_jwt_role not in ('anon', 'authenticated') then
    return new;
  end if;

  if public.is_super_admin() then
    return new;
  end if;

  if new.role_id is distinct from old.role_id then
    raise exception 'role_id can only be changed by Hybrid moderation' using errcode = '42501';
  end if;
  if new.profile_type is distinct from old.profile_type then
    raise exception 'profile_type can only be changed by Hybrid moderation' using errcode = '42501';
  end if;
  if new.is_verified is distinct from old.is_verified then
    raise exception 'is_verified can only be changed by Hybrid moderation' using errcode = '42501';
  end if;
  if new.auth_id is distinct from old.auth_id then
    raise exception 'auth_id cannot be changed' using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke execute on function public.profiles_guard_privilege_columns() from public;

-- BEFORE, and ordered ahead of nothing in particular: it only raises or passes
-- NEW through untouched, so it composes with the existing BEFORE triggers.
drop trigger if exists trg_profiles_guard_privilege_columns on public.profiles;
create trigger trg_profiles_guard_privilege_columns
  before update on public.profiles
  for each row execute function public.profiles_guard_privilege_columns();
