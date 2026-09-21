-- Budtender referral program: schema.
--
-- Eligibility is an approved location_employees row with role 'budtender'.
-- is_location_manager was checked first: it does test is_approved IS TRUE, so the
-- escalation fixed earlier this week has not come back and the approval flow can be
-- relied on. Note that the two rows on this database today carry role 'staff', which
-- is legacy import data — requestToWorkHere writes 'budtender', so anything created
-- through the app qualifies.
--
-- Every table below has RLS on and no grant to anon or authenticated. Everything the
-- app does goes through the functions in the next migration, and EXECUTE is revoked
-- from PUBLIC explicitly on each one.

-- ─── Settings: the server's own copy of the numbers ──────────────────────────
-- Authoritative here rather than in the client, because qualification and payout
-- eligibility are computed server-side and must not be arguable from the browser.
-- lib/referrals.js mirrors these for mock mode and says so.
create table if not exists public.referral_settings (
  id                   integer primary key default 1 check (id = 1),
  is_paused            boolean not null default false,
  target               integer not null default 40,
  reward_label         text    not null default '$20 Amazon gift card',
  qualify_window_days  integer not null default 14,
  -- Fraud thresholds. Flags only; nothing here rejects anything automatically.
  burst_count          integer not null default 5,
  burst_minutes        integer not null default 60,
  minimal_action_days  integer not null default 7,
  paused_at            timestamptz,
  paused_by            integer references public.profiles(id) on delete set null,
  updated_at           timestamptz not null default now()
);
insert into public.referral_settings (id) values (1) on conflict (id) do nothing;

-- ─── Who was referred by whom ────────────────────────────────────────────────
-- On profiles, because it is a property of the account and every read of a profile
-- may want it. Write-once: see the trigger below.
alter table public.profiles
  add column if not exists referred_by integer references public.profiles(id) on delete set null;

create index if not exists profiles_referred_by_idx
  on public.profiles (referred_by) where referred_by is not null;

-- The profiles UPDATE policy lets the owner (and a brand admin) update any column,
-- and a WITH CHECK cannot express "this column did not change" because it only sees
-- the NEW row. So immutability is a trigger, which sees OLD.
--
-- SECURITY DEFINER functions still run this trigger, so the attribution RPC sets the
-- column by way of a session flag it sets and clears itself. A client cannot set that
-- flag: set_config with is_local true inside a DEFINER function is not reachable from
-- PostgREST, which starts each request with a clean session.
create or replace function public.profiles_protect_referred_by()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if NEW.referred_by is distinct from OLD.referred_by then
    if coalesce(current_setting('hybrid.referral_attribution', true), '') <> 'on' then
      raise exception 'referred_by is set once at signup and cannot be changed';
    end if;
    if OLD.referred_by is not null then
      raise exception 'referred_by has already been set';
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists profiles_referred_by_immutable on public.profiles;
create trigger profiles_referred_by_immutable
  before update on public.profiles
  for each row execute function public.profiles_protect_referred_by();

-- ─── Codes ───────────────────────────────────────────────────────────────────
-- One row per budtender, not one per store: a budtender at three shops still says
-- one code out loud. Codes are never reused — the row is kept even if eligibility
-- lapses, so a code that was on a printed card never comes to mean someone else.
create table if not exists public.referral_codes (
  profile_id  integer primary key references public.profiles(id) on delete cascade,
  code        text not null unique check (code ~ '^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$'),
  created_at  timestamptz not null default now()
);

-- ─── Referrals ───────────────────────────────────────────────────────────────
create table if not exists public.referrals (
  id                   bigint generated always as identity primary key,
  code                 text not null,
  referrer_profile_id  integer not null references public.profiles(id) on delete cascade,
  -- One row per referred account, ever. The unique constraint is the real guard
  -- against double attribution, not the RPC's check.
  referred_profile_id  integer not null unique references public.profiles(id) on delete cascade,
  signed_up_at         timestamptz not null default now(),
  qualified_at         timestamptz,
  expired_at           timestamptz,
  -- Which action qualified it, for the admin detail view.
  first_action         text,
  status               text not null default 'pending'
                         check (status in ('pending', 'qualified', 'expired')),
  -- Flags only. Nothing here blocks a payout; a human reads them.
  fraud_flags          jsonb not null default '[]'::jsonb,
  -- Counted toward a payout cycle once approved, so a later cycle cannot re-count it.
  payout_id            bigint,
  created_at           timestamptz not null default now(),
  check (referrer_profile_id <> referred_profile_id)
);

create index if not exists referrals_referrer_idx on public.referrals (referrer_profile_id, status);
create index if not exists referrals_pending_idx on public.referrals (signed_up_at)
  where status = 'pending';
create index if not exists referrals_referred_idx on public.referrals (referred_profile_id);

-- ─── Payouts, with their own history ─────────────────────────────────────────
-- A budtender can earn more than once. DECISION: the qualified count does NOT reset.
-- Cycle N is earned at N x target, so the lifetime number stays true and the progress
-- bar reads "progress toward the next reward" rather than being wound back to zero —
-- which would make a budtender's own total disagree with the admin leaderboard.
create table if not exists public.referral_payouts (
  id               bigint generated always as identity primary key,
  profile_id       integer not null references public.profiles(id) on delete cascade,
  cycle            integer not null check (cycle >= 1),
  target           integer not null,
  qualified_at_request integer not null,
  status           text not null default 'pending'
                     check (status in ('pending', 'approved', 'paid', 'rejected')),
  reward_label     text not null,
  notes            text,
  reject_reason    text,
  created_at       timestamptz not null default now(),
  unique (profile_id, cycle)
);

create table if not exists public.referral_payout_events (
  id          bigint generated always as identity primary key,
  payout_id   bigint not null references public.referral_payouts(id) on delete cascade,
  from_status text,
  to_status   text not null,
  actor_profile_id integer references public.profiles(id) on delete set null,
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists referral_payout_events_idx
  on public.referral_payout_events (payout_id, created_at);

-- ─── Lock everything ─────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['referral_settings', 'referral_codes', 'referrals',
                           'referral_payouts', 'referral_payout_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated, public', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

revoke all on function public.profiles_protect_referred_by() from public, anon, authenticated;

-- ─── Referral events on the analytics layer ──────────────────────────────────
-- The analytics event layer exists, so link visits and QR landings go through it
-- rather than into a table of their own: conversion from visit to signup to
-- qualification is then one join away from every other funnel already recorded.
alter table public.analytics_events drop constraint if exists analytics_events_event_type_check;
alter table public.analytics_events add constraint analytics_events_event_type_check
  check (event_type in (
    'post_impression', 'post_view', 'video_watch',
    'profile_visit', 'product_view', 'list_view',
    'location_view', 'giveaway_view',
    'share', 'link_tap', 'phone_tap', 'directions_tap', 'website_tap',
    'unfollow', 'unlike', 'unstash',
    -- The referral funnel. target is the referring budtender's profile.
    'referral_visit', 'referral_signup_start'));
