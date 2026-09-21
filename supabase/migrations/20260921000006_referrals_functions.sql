-- Budtender referral program: the whole API.
--
-- Nothing touches a referral table directly; every path is one of these functions.
-- EXECUTE is revoked from PUBLIC explicitly on each, then granted only where needed:
-- 81 of 82 functions on this database once carried a PUBLIC grant, and revoking anon
-- alone would have left every one of them open.

-- ─── Eligibility ─────────────────────────────────────────────────────────────
-- An approved budtender, at any store. Kept separate so the code issuer, the
-- attribution path and the admin views cannot drift apart on what "eligible" means.
create or replace function public.referral_is_eligible(p_profile_id integer)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.location_employees le
     where le.profile_id = p_profile_id
       and le.is_approved is true
       and le.role = 'budtender'
  );
$$;

-- ─── Code generation ─────────────────────────────────────────────────────────
-- Crockford-style alphabet with 0/O/1/l/I removed, so a code read aloud across a
-- counter cannot come back wrong. 31^6 is about 887 million, and the unique index
-- settles any collision by making the insert fail and the loop try again.
create or replace function public.referral_generate_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  out text;
  i integer;
begin
  loop
    out := '';
    for i in 1..6 loop
      out := out || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.referral_codes where code = out);
  end loop;
  return out;
end;
$$;

-- The caller's own code, created on first ask. Returns null for anyone not eligible
-- rather than raising: the profile screen asks for every user and shows the panel
-- only when a code comes back.
create or replace function public.referral_my_code()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  me integer;
  existing text;
begin
  select id into me from public.profiles where auth_id = auth.uid() limit 1;
  if me is null then return null; end if;

  select code into existing from public.referral_codes where profile_id = me;
  if existing is not null then return existing; end if;

  -- Eligibility is checked at issue AND at attribution. A code issued today must
  -- stop attributing if approval is withdrawn tomorrow, so neither check is enough
  -- on its own.
  if not public.referral_is_eligible(me) then return null; end if;

  insert into public.referral_codes (profile_id, code)
  values (me, public.referral_generate_code())
  on conflict (profile_id) do nothing;

  select code into existing from public.referral_codes where profile_id = me;
  return existing;
end;
$$;

-- ─── Landing page ────────────────────────────────────────────────────────────
-- The one thing anon may call. Returns the budtender and the store to put on the
-- landing screen, and nothing else — no counts, no ids beyond what the page draws,
-- and null for a code that is unknown or whose owner is no longer approved.
create or replace function public.referral_resolve(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rc record;
  store record;
  paused boolean;
begin
  if p_code is null or btrim(p_code) = '' then return null; end if;
  select is_paused into paused from public.referral_settings where id = 1;

  select c.profile_id, c.code, coalesce(p.display_name, p.username) as name,
         p.username, p.avatar_id
    into rc
    from public.referral_codes c
    join public.profiles p on p.id = c.profile_id
   where c.code = upper(btrim(p_code));

  if rc.profile_id is null then return null; end if;
  if not public.referral_is_eligible(rc.profile_id) then return null; end if;

  select l.name, l.logo_id, l.banner_id
    into store
    from public.location_employees le
    join public.locations l on l.id = le.location_id
   where le.profile_id = rc.profile_id and le.is_approved is true and le.role = 'budtender'
   order by le.created_at
   limit 1;

  return jsonb_build_object(
    'code', rc.code,
    'paused', coalesce(paused, false),
    'budtender', jsonb_build_object(
      'name', rc.name,
      'handle', case when rc.username is null then null else '@' || rc.username end,
      'avatar', (select coalesce(f.secure_url, f.url) from public.cloud_files f where f.id = rc.avatar_id)),
    'store', case when store.name is null then null else jsonb_build_object(
      'name', store.name,
      'avatar', (select coalesce(f.secure_url, f.url) from public.cloud_files f where f.id = store.logo_id)) end
  );
end;
$$;

-- ─── Attribution ─────────────────────────────────────────────────────────────
-- Called by the newly created account, once, with the code it carried through
-- signup. Silent about every failure: an invalid code, a paused program, a lapsed
-- budtender and a self-referral all return false, because the new user should never
-- see an error about somebody else's eligibility in the middle of signing up.
--
-- "New account" means one with no referred_by yet and created within the qualify
-- window. An existing user who opens a referral link is not attributed: their
-- profile already exists, and this is the only way referred_by is ever written.
create or replace function public.referral_claim(p_code text)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  me integer;
  me_created timestamptz;
  me_referred integer;
  owner_id integer;
  paused boolean;
  win integer;
begin
  select id, created_at, referred_by into me, me_created, me_referred
    from public.profiles where auth_id = auth.uid() limit 1;
  if me is null then return false; end if;
  if me_referred is not null then return false; end if;           -- already attributed
  if p_code is null or btrim(p_code) = '' then return false; end if;

  select is_paused, qualify_window_days into paused, win
    from public.referral_settings where id = 1;
  if coalesce(paused, false) then return false; end if;

  -- Only genuinely new accounts. Without this, anyone could paste a code into the
  -- RPC months later and attribute themselves retroactively.
  if me_created < now() - make_interval(days => coalesce(win, 14)) then return false; end if;

  select profile_id into owner_id from public.referral_codes
   where code = upper(btrim(p_code));
  if owner_id is null then return false; end if;
  if owner_id = me then return false; end if;                     -- self-referral
  if not public.referral_is_eligible(owner_id) then return false; end if;

  insert into public.referrals (code, referrer_profile_id, referred_profile_id, signed_up_at)
  values (upper(btrim(p_code)), owner_id, me, me_created)
  on conflict (referred_profile_id) do nothing;

  -- The immutability trigger refuses every write it is not told to expect. This
  -- flag is set and cleared inside this function; a PostgREST request starts with a
  -- clean session, so a client has no way to turn it on.
  perform set_config('hybrid.referral_attribution', 'on', true);
  update public.profiles set referred_by = owner_id where id = me and referred_by is null;
  perform set_config('hybrid.referral_attribution', 'off', true);

  return true;
end;
$$;

-- ─── Qualification ───────────────────────────────────────────────────────────
-- Computed here, never claimed by the client. A referral qualifies when, inside the
-- window, the account has finished onboarding AND done one real thing.
create or replace function public.referral_first_action(p_profile_id integer, p_by timestamptz)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select action from (
    select 'follow' as action, min(created_at) as at from public.relationships where follower_id = p_profile_id
    union all
    select 'stash', min(created_at) from public.stash where profile_id = p_profile_id
    union all
    select 'stashlist', min(created_at) from public.lists where profile_id = p_profile_id
    union all
    select 'giveaway_entry', min(created_at) from public.giveaway_entries where profile_id = p_profile_id
    union all
    select 'deal_claim', min(claimed_at) from public.claimed_deals where profile_id = p_profile_id
  ) a
  where at is not null and at <= p_by
  order by at
  limit 1;
$$;

-- Evaluates one account's referral. Idempotent, and once qualified it stays
-- qualified — a later run never walks it back.
create or replace function public.referral_try_qualify(p_referred_profile_id integer)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r record;
  win integer;
  deadline timestamptz;
  onboarded timestamptz;
  act text;
begin
  select * into r from public.referrals
   where referred_profile_id = p_referred_profile_id and status = 'pending';
  if r.id is null then return false; end if;

  select qualify_window_days into win from public.referral_settings where id = 1;
  deadline := r.signed_up_at + make_interval(days => coalesce(win, 14));

  select onboarding_completed_at into onboarded from public.profiles where id = p_referred_profile_id;

  if onboarded is not null and onboarded <= deadline then
    act := public.referral_first_action(p_referred_profile_id, deadline);
    if act is not null then
      update public.referrals
         set status = 'qualified', qualified_at = now(), first_action = act
       where id = r.id;
      perform public.referral_notify(r.referrer_profile_id, 'referral_qualified');
      perform public.referral_check_target(r.referrer_profile_id);
      return true;
    end if;
  end if;

  -- Past the window with the conditions unmet: marked, never deleted.
  if now() > deadline then
    update public.referrals set status = 'expired', expired_at = now() where id = r.id;
  end if;

  return false;
end;
$$;

-- The cron sweep, and the catch-up for anything the write-time triggers missed.
create or replace function public.referral_evaluate_due()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  rec record;
  n_qualified integer := 0;
  n_expired integer := 0;
begin
  for rec in select referred_profile_id from public.referrals where status = 'pending' loop
    if public.referral_try_qualify(rec.referred_profile_id) then
      n_qualified := n_qualified + 1;
    end if;
  end loop;
  select count(*) into n_expired from public.referrals
   where status = 'expired' and expired_at > now() - interval '1 day';

  perform public.referral_scan_fraud();

  return jsonb_build_object('qualified', n_qualified, 'expired_last_day', n_expired);
end;
$$;

-- Write-time evaluation, so a budtender's progress moves while the customer is still
-- standing there rather than at the next cron tick. Attached to the five tables the
-- qualifying actions live in, plus profiles for the onboarding flag.
create or replace function public.referral_qualify_on_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid integer;
begin
  pid := case TG_TABLE_NAME
           when 'relationships'   then NEW.follower_id
           when 'stash'           then NEW.profile_id
           when 'lists'           then NEW.profile_id
           when 'giveaway_entries' then NEW.profile_id
           when 'claimed_deals'   then NEW.profile_id
           when 'profiles'        then NEW.id
         end;
  if pid is not null then
    -- Cheap guard: almost no account is a pending referral, and this runs on every
    -- follow and stash in the system.
    if exists (select 1 from public.referrals where referred_profile_id = pid and status = 'pending') then
      perform public.referral_try_qualify(pid);
    end if;
  end if;
  return NEW;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['relationships', 'stash', 'lists', 'giveaway_entries', 'claimed_deals'] loop
    execute format('drop trigger if exists referral_qualify_%I on public.%I', t, t);
    execute format('create trigger referral_qualify_%I after insert on public.%I
                    for each row execute function public.referral_qualify_on_write()', t, t);
  end loop;
end $$;

drop trigger if exists referral_qualify_onboarding on public.profiles;
create trigger referral_qualify_onboarding
  after update of onboarding_completed_at on public.profiles
  for each row
  when (NEW.onboarding_completed_at is not null and OLD.onboarding_completed_at is null)
  execute function public.referral_qualify_on_write();

-- ─── Notifications ───────────────────────────────────────────────────────────
-- Nothing in notification_types covers a referral: the closest are the *_milestone
-- types, which are about a user's own counts, and general_message, which is a
-- catch-all that would give every one of these the same title. Three new types, in
-- the 'activity' category alongside employee_approved and deal_claimed.
--
-- Checked for duplication first: no existing trigger writes anything on referrals,
-- relationships inserts, or payout tables.
insert into public.notification_types (code, name, category, title_template, body_template, priority)
values
  ('referral_qualified', 'Referral qualified', 'activity',
   'A referral qualified', 'Someone you signed up is now counted toward your reward.', 5),
  ('referral_target_reached', 'Reward earned', 'activity',
   'You have earned your reward', 'You hit the target. Your reward is being processed.', 8),
  ('referral_payout_paid', 'Reward sent', 'activity',
   'Your reward is on its way', 'Your reward has been marked as sent.', 8)
on conflict (code) do nothing;

create or replace function public.referral_notify(p_profile_id integer, p_code text, p_body text default null)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  t record;
begin
  if p_profile_id is null then return; end if;
  select id, title_template, body_template into t
    from public.notification_types where code = p_code;
  if t.id is null then return; end if;

  insert into public.notifications (profile_id, type_id, title, body)
  values (p_profile_id, t.id, t.title_template, coalesce(p_body, t.body_template));
end;
$$;

-- ─── Fraud signals ───────────────────────────────────────────────────────────
-- Flags, never blocks. Payouts are approved by hand precisely so someone reads
-- these first, and an automatic rejection would punish a budtender for a busy shift.
--
-- Thresholds live in referral_settings:
--   burst          5 or more signups for one budtender inside 60 minutes
--   minimal_action a referral that qualified on exactly one action and has done
--                  nothing at all in the 7 days since
--   shared_session a referred account whose analytics session id also belongs to
--                  another referred account of the same budtender, or to the
--                  budtender themselves
create or replace function public.referral_scan_fraud()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  s record;
  n integer := 0;
begin
  select burst_count, burst_minutes, minimal_action_days into s
    from public.referral_settings where id = 1;

  -- Reset and recompute, so a flag that no longer holds disappears rather than
  -- following a budtender around forever.
  update public.referrals set fraud_flags = '[]'::jsonb where fraud_flags <> '[]'::jsonb;

  -- Burst.
  with bursts as (
    select r.id
      from public.referrals r
     where (select count(*) from public.referrals r2
             where r2.referrer_profile_id = r.referrer_profile_id
               and r2.signed_up_at between r.signed_up_at - make_interval(mins => coalesce(s.burst_minutes, 60))
                                       and r.signed_up_at + make_interval(mins => coalesce(s.burst_minutes, 60))
           ) >= coalesce(s.burst_count, 5)
  )
  update public.referrals r set fraud_flags = r.fraud_flags || '["burst"]'::jsonb
    from bursts b where b.id = r.id;

  -- Qualified on the bare minimum, and nothing since.
  with minimal as (
    select r.id
      from public.referrals r
     where r.status = 'qualified'
       and r.qualified_at < now() - make_interval(days => coalesce(s.minimal_action_days, 7))
       and (
         (select count(*) from public.relationships where follower_id = r.referred_profile_id) +
         (select count(*) from public.stash where profile_id = r.referred_profile_id) +
         (select count(*) from public.lists where profile_id = r.referred_profile_id) +
         (select count(*) from public.giveaway_entries where profile_id = r.referred_profile_id) +
         (select count(*) from public.claimed_deals where profile_id = r.referred_profile_id)
       ) <= 1
  )
  update public.referrals r set fraud_flags = r.fraud_flags || '["minimal_activity"]'::jsonb
    from minimal m where m.id = r.id;

  -- Shared device session, between two referrals of the same budtender or with the
  -- budtender's own session. analytics_events is the only place a session id lives.
  with sessions as (
    select distinct e.actor_profile_id as pid, e.session_id
      from public.analytics_events e
     where e.actor_profile_id is not null and e.session_id not like 'trigger:%'
  ), shared as (
    select distinct r.id
      from public.referrals r
      join sessions s1 on s1.pid = r.referred_profile_id
      join sessions s2 on s2.session_id = s1.session_id and s2.pid <> s1.pid
      join public.referrals r2 on r2.referred_profile_id = s2.pid
                              and r2.referrer_profile_id = r.referrer_profile_id
     union
    select distinct r.id
      from public.referrals r
      join sessions s1 on s1.pid = r.referred_profile_id
      join sessions s2 on s2.session_id = s1.session_id and s2.pid = r.referrer_profile_id
  )
  update public.referrals r set fraud_flags = r.fraud_flags || '["shared_session"]'::jsonb
    from shared sh where sh.id = r.id;

  select count(*) into n from public.referrals where fraud_flags <> '[]'::jsonb;
  return n;
end;
$$;

-- ─── Reaching the target ─────────────────────────────────────────────────────
-- Cycle N is earned at N x target. The count never resets, so a budtender's own
-- total always agrees with the admin leaderboard.
create or replace function public.referral_check_target(p_profile_id integer)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  tgt integer;
  label text;
  qualified integer;
  earned integer;
  existing integer;
  i integer;
begin
  select target, reward_label into tgt, label from public.referral_settings where id = 1;
  select count(*) into qualified from public.referrals
   where referrer_profile_id = p_profile_id and status = 'qualified';
  earned := floor(qualified / greatest(tgt, 1));
  if earned < 1 then return; end if;

  select coalesce(max(cycle), 0) into existing from public.referral_payouts
   where profile_id = p_profile_id;

  for i in (existing + 1)..earned loop
    insert into public.referral_payouts
      (profile_id, cycle, target, qualified_at_request, reward_label)
    values (p_profile_id, i, tgt, qualified, label)
    on conflict (profile_id, cycle) do nothing;

    insert into public.referral_payout_events (payout_id, from_status, to_status, note)
    select id, null, 'pending', 'Target reached'
      from public.referral_payouts where profile_id = p_profile_id and cycle = i;

    perform public.referral_notify(p_profile_id, 'referral_target_reached');
  end loop;
end;
$$;

-- ─── What the budtender sees ─────────────────────────────────────────────────
-- Counts only. There is deliberately no path from here to the identity of anyone
-- referred: the query never selects a referred profile's name, handle or id.
create or replace function public.referral_my_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me integer;
  tgt integer; label text; win integer; paused boolean;
  qualified integer; pending integer; expired integer;
begin
  select id into me from public.profiles where auth_id = auth.uid() limit 1;
  if me is null then return null; end if;

  select target, reward_label, qualify_window_days, is_paused
    into tgt, label, win, paused from public.referral_settings where id = 1;

  select count(*) filter (where status = 'qualified'),
         count(*) filter (where status = 'pending'),
         count(*) filter (where status = 'expired')
    into qualified, pending, expired
    from public.referrals where referrer_profile_id = me;

  return jsonb_build_object(
    'eligible', public.referral_is_eligible(me),
    'code', (select code from public.referral_codes where profile_id = me),
    'paused', coalesce(paused, false),
    'target', tgt, 'reward_label', label, 'qualify_window_days', win,
    'qualified', qualified, 'pending', pending, 'expired', expired,
    -- Progress toward the NEXT reward, since the total never resets.
    'cycles_earned', floor(qualified / greatest(tgt, 1)),
    'toward_next', qualified % greatest(tgt, 1),
    'payouts', coalesce((
      select jsonb_agg(jsonb_build_object('cycle', cycle, 'status', status,
                                          'reward_label', reward_label, 'created_at', created_at)
             order by cycle desc)
        from public.referral_payouts where profile_id = me), '[]'::jsonb)
  );
end;
$$;

-- ─── Admin ───────────────────────────────────────────────────────────────────
-- Every one of these refuses anyone who is not a super admin. The dashboard hides
-- the section too, but that is the convenience; this is the control.

create or replace function public.referral_admin_leaderboard(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then raise exception 'Not authorised'; end if;

  return jsonb_build_object(
    'settings', (select to_jsonb(s) from public.referral_settings s where id = 1),
    'awaiting_payout', (select count(*) from public.referral_payouts where status = 'pending'),
    'flagged', (select count(*) from public.referrals where fraud_flags <> '[]'::jsonb),
    'leaderboard', coalesce((
      select jsonb_agg(x order by (x->>'qualified')::int desc) from (
        select jsonb_build_object(
          'profile_id', p.id,
          'name', coalesce(p.display_name, p.username),
          'handle', case when p.username is null then null else '@' || p.username end,
          'code', c.code,
          'eligible', public.referral_is_eligible(p.id),
          'store', (select l.name from public.location_employees le
                     join public.locations l on l.id = le.location_id
                    where le.profile_id = p.id and le.is_approved and le.role = 'budtender'
                    order by le.created_at limit 1),
          'qualified', count(*) filter (where r.status = 'qualified'),
          'pending', count(*) filter (where r.status = 'pending'),
          'expired', count(*) filter (where r.status = 'expired'),
          'flagged', count(*) filter (where r.fraud_flags <> '[]'::jsonb)
        ) x
        from public.referral_codes c
        join public.profiles p on p.id = c.profile_id
        left join public.referrals r on r.referrer_profile_id = p.id
        group by p.id, p.display_name, p.username, c.code
        order by count(*) filter (where r.status = 'qualified') desc
        limit greatest(1, least(coalesce(p_limit, 50), 200))
      ) s), '[]'::jsonb),
    'payout_queue', coalesce((
      select jsonb_agg(jsonb_build_object(
        'payout_id', po.id, 'profile_id', po.profile_id,
        'name', coalesce(p.display_name, p.username),
        'cycle', po.cycle, 'target', po.target,
        'qualified_at_request', po.qualified_at_request,
        'status', po.status, 'reward_label', po.reward_label,
        'notes', po.notes, 'reject_reason', po.reject_reason,
        'created_at', po.created_at,
        'flagged', (select count(*) from public.referrals r
                     where r.referrer_profile_id = po.profile_id and r.fraud_flags <> '[]'::jsonb)
      ) order by po.created_at)
        from public.referral_payouts po
        join public.profiles p on p.id = po.profile_id
       where po.status in ('pending', 'approved')), '[]'::jsonb)
  );
end;
$$;

-- The only place a referred account's identity is ever returned, and only to a
-- super admin reviewing a specific budtender.
create or replace function public.referral_admin_detail(p_profile_id integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then raise exception 'Not authorised'; end if;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'name', (select coalesce(display_name, username) from public.profiles where id = p_profile_id),
    'referrals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'referral_id', r.id,
        'referred', coalesce(rp.display_name, rp.username),
        'handle', case when rp.username is null then null else '@' || rp.username end,
        'signed_up_at', r.signed_up_at,
        'status', r.status,
        'qualified_at', r.qualified_at,
        'expired_at', r.expired_at,
        'first_action', r.first_action,
        'fraud_flags', r.fraud_flags
      ) order by r.signed_up_at desc)
        from public.referrals r
        join public.profiles rp on rp.id = r.referred_profile_id
       where r.referrer_profile_id = p_profile_id), '[]'::jsonb),
    'payouts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'payout_id', po.id, 'cycle', po.cycle, 'status', po.status,
        'notes', po.notes, 'reject_reason', po.reject_reason, 'created_at', po.created_at,
        'history', (select jsonb_agg(jsonb_build_object(
                      'to_status', e.to_status, 'note', e.note, 'at', e.created_at)
                    order by e.created_at)
                    from public.referral_payout_events e where e.payout_id = po.id)
      ) order by po.cycle desc)
        from public.referral_payouts po where po.profile_id = p_profile_id), '[]'::jsonb)
  );
end;
$$;

-- approve | paid | reject. Every transition writes an event row, so a payout's
-- history is the audit trail rather than a status column that forgets.
create or replace function public.referral_payout_action(
  p_payout_id bigint, p_action text, p_note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  me integer;
  po record;
  next_status text;
begin
  if not public.is_super_admin() then raise exception 'Not authorised'; end if;
  select id into me from public.profiles where auth_id = auth.uid() limit 1;

  select * into po from public.referral_payouts where id = p_payout_id;
  if po.id is null then raise exception 'No such payout'; end if;

  next_status := case p_action
    when 'approve' then 'approved'
    when 'paid'    then 'paid'
    when 'reject'  then 'rejected'
    else null end;
  if next_status is null then raise exception 'Unknown action'; end if;
  if po.status = 'paid' then raise exception 'Already paid'; end if;

  update public.referral_payouts
     set status = next_status,
         notes = case when p_action = 'paid' then coalesce(p_note, notes) else notes end,
         reject_reason = case when p_action = 'reject' then p_note else reject_reason end
   where id = p_payout_id;

  insert into public.referral_payout_events (payout_id, from_status, to_status, actor_profile_id, note)
  values (p_payout_id, po.status, next_status, me, p_note);

  -- The referrals counted toward this cycle are stamped so a later cycle cannot
  -- re-count them, and the budtender is told when the money actually moves.
  if p_action = 'paid' then
    update public.referrals set payout_id = p_payout_id
     where referrer_profile_id = po.profile_id and status = 'qualified' and payout_id is null;
    perform public.referral_notify(po.profile_id, 'referral_payout_paid');
  end if;

  return jsonb_build_object('payout_id', p_payout_id, 'status', next_status);
end;
$$;

create or replace function public.referral_set_paused(p_paused boolean, p_reason text default null)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare me integer;
begin
  if not public.is_super_admin() then raise exception 'Not authorised'; end if;
  select id into me from public.profiles where auth_id = auth.uid() limit 1;
  update public.referral_settings
     set is_paused = coalesce(p_paused, false),
         paused_at = case when coalesce(p_paused, false) then now() else null end,
         paused_by = case when coalesce(p_paused, false) then me else null end,
         updated_at = now()
   where id = 1;
  return coalesce(p_paused, false);
end;
$$;

-- ─── Grants ──────────────────────────────────────────────────────────────────
-- PUBLIC first and explicitly on every function, then only what each caller needs.
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.referral_is_eligible(integer)',
    'public.referral_generate_code()',
    'public.referral_my_code()',
    'public.referral_resolve(text)',
    'public.referral_claim(text)',
    'public.referral_first_action(integer,timestamptz)',
    'public.referral_try_qualify(integer)',
    'public.referral_evaluate_due()',
    'public.referral_qualify_on_write()',
    'public.referral_notify(integer,text,text)',
    'public.referral_scan_fraud()',
    'public.referral_check_target(integer)',
    'public.referral_my_stats()',
    'public.referral_admin_leaderboard(integer)',
    'public.referral_admin_detail(integer)',
    'public.referral_payout_action(bigint,text,text)',
    'public.referral_set_paused(boolean,text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
end $$;

-- A signed-in user asks for their own code and their own counts, and a new account
-- claims its code.
grant execute on function public.referral_my_code()   to authenticated;
grant execute on function public.referral_my_stats()  to authenticated;
grant execute on function public.referral_claim(text) to authenticated;
-- The landing page is seen by someone who is not signed in yet. This is the only
-- referral function anon may call, and it returns no counts and no identities
-- beyond the two names and avatars the page draws.
grant execute on function public.referral_resolve(text) to anon, authenticated;
-- Admin.
grant execute on function public.referral_admin_leaderboard(integer)      to authenticated;
grant execute on function public.referral_admin_detail(integer)           to authenticated;
grant execute on function public.referral_payout_action(bigint,text,text) to authenticated;
grant execute on function public.referral_set_paused(boolean,text)        to authenticated;

-- ─── Cron ────────────────────────────────────────────────────────────────────
-- Follows the two original jobs: pg_cron calling SQL directly.
select cron.unschedule('referral_evaluate') where exists (select 1 from cron.job where jobname = 'referral_evaluate');
select cron.schedule('referral_evaluate', '17 * * * *', $$select public.referral_evaluate_due()$$);
