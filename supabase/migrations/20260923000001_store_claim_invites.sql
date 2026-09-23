-- A link that hands someone their store.
--
-- These go out in a mail written to one named store, and the point is that the
-- recipient signs up and lands on their own store page already able to manage it —
-- no request, no approval, no waiting on us.
--
-- ── What this is, honestly ─────────────────────────────────────────────────
-- A bearer token. Whoever holds the link gets store-manager rights on that store,
-- and a forwarded email holds the link. That is the trade being made deliberately,
-- so the defaults are the conservative end of it:
--
--   single use      the mail goes to one person; the second person to click is
--                   refused rather than silently made a second manager
--   expires         30 days by default, because an invite that works forever is a
--                   credential nobody remembers issuing
--   revocable       one call kills it
--   logged          every claim records who and when, because "who made this person
--                   a manager" must have an answer that is not "a link, somehow"
--
-- Minting one is the same permission as approving a manager request —
-- can_grant_manager() — so a store manager cannot mint a link that creates another
-- store manager. That was the rule in 20260922000003 and this does not weaken it.

create table if not exists public.store_claim_invites (
  id          bigint generated always as identity primary key,
  public_id   uuid not null default gen_random_uuid() unique,
  token       text not null unique,
  location_id integer not null references public.locations(id) on delete cascade,
  note        text,                       -- e.g. which address it was mailed to
  max_uses    integer not null default 1 check (max_uses >= 1),
  uses        integer not null default 0,
  expires_at  timestamptz not null,
  revoked_at  timestamptz,
  created_by  integer references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists store_claim_invites_location on public.store_claim_invites (location_id);

-- Every claim, kept whatever happens to the invite afterwards.
create table if not exists public.store_claim_invite_claims (
  id         bigint generated always as identity primary key,
  invite_id  bigint not null references public.store_claim_invites(id) on delete cascade,
  profile_id integer not null references public.profiles(id) on delete cascade,
  claimed_at timestamptz not null default now()
);

alter table public.store_claim_invites enable row level security;
alter table public.store_claim_invite_claims enable row level security;

-- No policies at all on either: a token that anyone can SELECT is not a token.
-- Everything goes through the definer functions below, which return the store's
-- public details and never the token itself.

-- ── Token ──────────────────────────────────────────────────────────────────
-- 26 characters from gen_random_bytes, not a short code. A referral code is meant
-- to be read aloud at a till and is guessable by design — six characters, rate
-- limited, and worth nothing but an attribution. This is worth a store, so it is
-- long enough that guessing is not a strategy. Ambiguous characters are dropped
-- because these get retyped off a printed email.
-- pgcrypto lives in the extensions schema on this project, so gen_random_bytes has
-- to be qualified: a bare call resolves against the function's own search_path and
-- fails at creation time. (gen_random_uuid elsewhere in this file is core Postgres
-- and needs no qualifying, which is why only this one bites.)
create or replace function public.store_invite_generate_token()
returns text
language sql
volatile
set search_path = public, extensions, pg_temp
as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                           1 + (get_byte(extensions.gen_random_bytes(1), 0) % 32), 1), '')
    from generate_series(1, 26);
$$;

revoke execute on function public.store_invite_generate_token() from public;

-- ── Minting ────────────────────────────────────────────────────────────────
create or replace function public.create_store_invite(
  p_location_id uuid,
  p_expires_days integer default 30,
  p_max_uses integer default 1,
  p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_loc   integer;
  v_token text;
  v_id    uuid;
begin
  select id into v_loc from public.locations where public_id = p_location_id;
  if v_loc is null then
    raise exception 'Store not found' using errcode = 'P0002';
  end if;
  -- Same gate as approving a manager request: a store manager cannot mint a link
  -- that makes another store manager.
  if not public.can_grant_manager(v_loc) then
    raise exception 'Only Hybrid moderation or the brand can invite a store manager' using errcode = '42501';
  end if;

  v_token := public.store_invite_generate_token();
  insert into public.store_claim_invites
    (token, location_id, note, max_uses, expires_at, created_by)
  values
    (v_token, v_loc, nullif(btrim(coalesce(p_note, '')), ''),
     greatest(coalesce(p_max_uses, 1), 1),
     now() + make_interval(days => greatest(coalesce(p_expires_days, 30), 1)),
     public.current_actor_id())
  returning public_id into v_id;

  -- The token is returned exactly once, here, to the person who minted it. It is
  -- never readable again: the listing shows everything about an invite except the
  -- token, so a leaked dashboard screenshot is not a leaked store.
  return jsonb_build_object('public_id', v_id, 'token', v_token);
end;
$$;

revoke execute on function public.create_store_invite(uuid, integer, integer, text) from public;
grant execute on function public.create_store_invite(uuid, integer, integer, text) to authenticated;

create or replace function public.revoke_store_invite(p_public_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_loc integer;
begin
  select location_id into v_loc from public.store_claim_invites where public_id = p_public_id;
  if v_loc is null then
    raise exception 'Invite not found' using errcode = 'P0002';
  end if;
  if not public.can_grant_manager(v_loc) then
    raise exception 'You cannot revoke that invite' using errcode = '42501';
  end if;
  update public.store_claim_invites set revoked_at = now()
   where public_id = p_public_id and revoked_at is null;
end;
$$;

revoke execute on function public.revoke_store_invite(uuid) from public;
grant execute on function public.revoke_store_invite(uuid) to authenticated;

-- ── The landing screen ─────────────────────────────────────────────────────
-- Callable signed out, because the whole point is that the recipient has no account
-- yet. Returns what the store looks like and whether the link still works, and
-- nothing else — no ids to probe with, no hint about other invites.
create or replace function public.resolve_store_invite(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_inv public.store_claim_invites%rowtype;
  v_loc public.locations%rowtype;
  v_logo text;
  v_state text;
begin
  select * into v_inv from public.store_claim_invites
   where token = upper(btrim(coalesce(p_token, '')));
  if v_inv.id is null then return null; end if;

  select * into v_loc from public.locations where id = v_inv.location_id;
  if v_loc.id is null then return null; end if;
  if v_loc.logo_id is not null then
    select coalesce(secure_url, url) into v_logo from public.cloud_files where id = v_loc.logo_id;
  end if;
  v_state := nullif(concat_ws(', ', v_loc.city, v_loc.state), '');

  return jsonb_build_object(
    'store', jsonb_build_object('name', v_loc.name, 'where', v_state, 'avatar', v_logo),
    'valid', (v_inv.revoked_at is null and v_inv.expires_at > now() and v_inv.uses < v_inv.max_uses),
    'reason', case
      when v_inv.revoked_at is not null then 'revoked'
      when v_inv.expires_at <= now()    then 'expired'
      when v_inv.uses >= v_inv.max_uses then 'used'
      else null end);
end;
$$;

revoke execute on function public.resolve_store_invite(text) from public;
grant execute on function public.resolve_store_invite(text) to anon, authenticated;

-- ── Claiming ───────────────────────────────────────────────────────────────
-- location_employees_guard forces a row to 'pending' whenever the caller cannot
-- already manage the location — which is exactly the case here, and exactly the
-- rule that closed the store-takeover bug in 8d8a6b9. Rather than weaken it, this
-- sets a flag the guard recognises, the same shape referral_claim uses for
-- referred_by: set and cleared inside this function, and a PostgREST request starts
-- with a clean session, so no client can turn it on.
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
  if v_jwt_role not in ('anon', 'authenticated') then
    return new;
  end if;
  -- Set only inside claim_store_invite, which has already checked the token.
  if coalesce(current_setting('hybrid.store_invite_claim', true), '') = 'on' then
    return new;
  end if;

  v_actor := public.current_actor_id();

  if tg_op = 'INSERT' then
    if not public.can_manage_location(new.location_id) then
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

create or replace function public.claim_store_invite(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me     integer := public.current_actor_id();
  v_inv  public.store_claim_invites%rowtype;
  v_loc  public.locations%rowtype;
begin
  if me is null then
    raise exception 'You must be signed in to claim a store' using errcode = '42501';
  end if;

  select * into v_inv from public.store_claim_invites
   where token = upper(btrim(coalesce(p_token, ''))) for update;
  if v_inv.id is null then
    raise exception 'That link is not valid' using errcode = 'P0002';
  end if;
  if v_inv.revoked_at is not null then
    raise exception 'That link has been revoked' using errcode = '22023';
  end if;
  if v_inv.expires_at <= now() then
    raise exception 'That link has expired' using errcode = '22023';
  end if;
  if v_inv.uses >= v_inv.max_uses then
    raise exception 'That link has already been used' using errcode = '22023';
  end if;

  select * into v_loc from public.locations where id = v_inv.location_id;

  -- Already managing it: not an error, and not a second use of the invite either.
  if public.is_location_manager(v_inv.location_id) then
    return jsonb_build_object('location_public_id', v_loc.public_id, 'name', v_loc.name, 'already', true);
  end if;

  perform set_config('hybrid.store_invite_claim', 'on', true);
  insert into public.location_employees (location_id, profile_id, role, is_approved, has_been_reviewed)
  values (v_inv.location_id, me, 'manager', true, true)
  on conflict (location_id, profile_id) do update
     set role = 'manager', is_approved = true, has_been_reviewed = true;
  perform set_config('hybrid.store_invite_claim', 'off', true);

  -- The store is theirs now, which is what "claimed" has always meant here.
  update public.locations set is_claimed = true where id = v_inv.location_id;

  update public.store_claim_invites set uses = uses + 1 where id = v_inv.id;
  insert into public.store_claim_invite_claims (invite_id, profile_id) values (v_inv.id, me);

  return jsonb_build_object('location_public_id', v_loc.public_id, 'name', v_loc.name, 'already', false);
end;
$$;

revoke execute on function public.claim_store_invite(text) from public;
grant execute on function public.claim_store_invite(text) to authenticated;

-- ── The admin listing ──────────────────────────────────────────────────────
-- Everything about an invite except the token.
create or replace function public.list_store_invites(p_location_id uuid default null)
returns table (
  public_id uuid, store_name text, location_public_id uuid, note text,
  max_uses integer, uses integer, expires_at timestamptz, revoked_at timestamptz,
  created_at timestamptz, claimed_by text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select i.public_id, l.name::text, l.public_id, i.note,
         i.max_uses, i.uses, i.expires_at, i.revoked_at, i.created_at,
         (select string_agg(coalesce(p.display_name, p.username), ', ')
            from public.store_claim_invite_claims c
            join public.profiles p on p.id = c.profile_id
           where c.invite_id = i.id)::text
    from public.store_claim_invites i
    join public.locations l on l.id = i.location_id
   where public.can_grant_manager(i.location_id)
     and (p_location_id is null or l.public_id = p_location_id)
   order by i.created_at desc
   limit 200;
$$;

revoke execute on function public.list_store_invites(uuid) from public;
grant execute on function public.list_store_invites(uuid) to authenticated;
