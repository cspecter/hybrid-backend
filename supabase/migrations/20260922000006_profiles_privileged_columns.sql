-- Lock every privileged column on profiles, at INSERT as well as UPDATE.
--
-- RLS is row-level. Postgres has no way to say "this policy may change these
-- columns and not those", so the moment a policy lets someone write their own
-- profiles row it lets them write every column on it. The policies here are:
--
--   UPDATE  auth.uid() = auth_id  OR  caller is a profile_admin of the row
--   INSERT  auth.uid() = auth_id  AND coalesce(role_id, 1) = 1
--
-- The INSERT policy pins role_id and nothing else. Everything else was open.
--
-- ── What was actually reachable, measured before writing this ───────────────
-- Each column tested on its own as an ordinary authenticated user, inside a
-- rolled-back transaction. Testing them in one statement is worthless: the first
-- guard to fire rejects the whole statement and every other column in it reads as
-- a pass it never earned.
--
--   role_id -> 9         BLOCKED   (20260922000001, last run; was live before that)
--   is_verified          BLOCKED   (same)
--   referred_by          BLOCKED   (profiles_protect_referred_by, pre-existing)
--   status -> suspended  ACCEPTED  a user could lift or set their own moderation state
--   is_employee          ACCEPTED
--   follower_count       ACCEPTED  and the other seven counters with it
--   INSERT is_verified   ACCEPTED  a brand-new signup could mark itself verified
--
-- profile_type at INSERT turned out to be blocked only incidentally:
-- trg_set_profile_type_from_role_id overwrites it from role_id, which the INSERT
-- policy pins to 1. That is a side effect of a different trigger, not a rule, and
-- it would evaporate the moment that trigger changed. It is a rule here now.
--
-- Also worth knowing: profiles.role_id DEFAULTS TO 10 (brand). Any insert path that
-- omits role_id creates a brand. Forcing it to 1 on INSERT closes that too.
--
-- ── Caller identity ────────────────────────────────────────────────────────
-- Read from the request's JWT role, never current_user: current_user rebinds inside
-- a SECURITY DEFINER body, so a guard that trusts it can be walked straight past by
-- calling through any definer function. Same test the other guards in this schema use.
--
-- ── Trigger depth ──────────────────────────────────────────────────────────
-- The counter triggers maintain follower_count and friends by updating profiles from
-- other tables' triggers, and trg_set_profile_type_from_role_id rewrites profile_type
-- in place. Those must keep working, so trigger-invoked writes are exempt.
--
-- The threshold is > 1, not > 0. Inside a trigger fired by a direct statement
-- pg_trigger_depth() is already 1 — measured, not assumed, with a probe trigger:
-- a direct UPDATE reported 1, an UPDATE caused by the relationships trigger reported
-- 2. `> 0` would have exempted every call this guard exists to catch, and it would
-- have passed a catalog check and every test written against it.
create or replace function public.profiles_guard_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_jwt_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
begin
  if pg_trigger_depth() > 1 then return new; end if;
  -- service_role, migrations, cron and Edge Functions arrive with no anon/authenticated
  -- claim and are the supported way to set these columns.
  if v_jwt_role not in ('anon', 'authenticated') then return new; end if;
  if public.is_super_admin() then return new; end if;

  if tg_op = 'INSERT' then
    -- Forced, not rejected. A signup that sends the wrong thing should still get an
    -- account; it just gets an ordinary one. Brand and creator profiles are made by
    -- moderation, or through account_applications.
    new.role_id         := 1;
    new.profile_type    := 'individual';
    new.is_verified     := false;
    new.status          := 'active';
    new.is_employee     := false;
    new.follower_count  := 0;
    new.following_count := 0;
    new.post_count      := 0;
    new.like_count      := 0;
    new.stash_count     := 0;
    new.restash_count   := 0;
    new.product_count   := 0;
    new.location_count  := 0;
    -- referred_by is deliberately NOT forced: signup is exactly when it is legitimately
    -- set. profiles_protect_referred_by keeps it write-once from then on.
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.role_id      is distinct from old.role_id      then raise exception 'role_id can only be changed by Hybrid moderation' using errcode='42501'; end if;
    if new.profile_type is distinct from old.profile_type then raise exception 'profile_type can only be changed by Hybrid moderation' using errcode='42501'; end if;
    if new.is_verified  is distinct from old.is_verified  then raise exception 'is_verified can only be changed by Hybrid moderation' using errcode='42501'; end if;
    if new.status       is distinct from old.status       then raise exception 'status can only be changed by Hybrid moderation' using errcode='42501'; end if;
    if new.is_employee  is distinct from old.is_employee  then raise exception 'is_employee can only be changed by Hybrid moderation' using errcode='42501'; end if;
    if new.auth_id      is distinct from old.auth_id      then raise exception 'auth_id cannot be changed' using errcode='42501'; end if;

    -- The counters are derived state. A profile that can edit its own follower_count
    -- can fake an audience, and every leaderboard and ranking in the app reads them.
    if new.follower_count  is distinct from old.follower_count
    or new.following_count is distinct from old.following_count
    or new.post_count      is distinct from old.post_count
    or new.like_count      is distinct from old.like_count
    or new.stash_count     is distinct from old.stash_count
    or new.restash_count   is distinct from old.restash_count
    or new.product_count   is distinct from old.product_count
    or new.location_count  is distinct from old.location_count then
      raise exception 'counts are maintained by Hybrid and cannot be set directly' using errcode='42501';
    end if;

    return new;
  end if;

  return new;
end;
$$;

revoke execute on function public.profiles_guard_privileged_columns() from public;

-- Replaces the UPDATE-only guard from 20260922000001, which this supersedes
-- completely: same rules, plus INSERT, status, is_employee and the counters.
drop trigger if exists trg_profiles_guard_privilege_columns on public.profiles;
drop function if exists public.profiles_guard_privilege_columns();

drop trigger if exists trg_profiles_guard_privileged_columns on public.profiles;
create trigger trg_profiles_guard_privileged_columns
  before insert or update on public.profiles
  for each row execute function public.profiles_guard_privileged_columns();
