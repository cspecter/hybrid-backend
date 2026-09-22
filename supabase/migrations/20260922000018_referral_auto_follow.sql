-- A referred user follows the budtender who invited them, automatically.
--
-- Someone who signed up because a budtender handed them a QR code across a counter
-- has an obvious connection to that person, and making them search for the handle
-- afterwards loses it. The follow is created at attribution, which is the moment we
-- know the two are connected.
--
-- ── The trap this had to avoid ─────────────────────────────────────────────
-- referral_first_action() treats ANY relationships row as the qualifying "first
-- action", and qualification is what turns a signup into one of the 40 that earns
-- $20. An auto-follow would therefore have BEEN the first action: every referral
-- would qualify the moment onboarding finished, with no genuine engagement at all,
-- and the 14-day window would have stopped meaning anything.
--
-- So the follow we manufacture is excluded from what counts. A follow of the person
-- who referred you is not independent evidence that you are using Hybrid — it is
-- evidence that we wrote a row. Every other follow still counts, including a
-- deliberate follow of that same budtender made later, which is indistinguishable
-- and rare enough not to chase.
create or replace function public.referral_first_action(p_profile_id integer, p_by timestamp with time zone)
returns text
language sql
stable
security definer
set search_path = public
as $function$
  select action from (
    select 'follow' as action, min(r.created_at) as at
      from public.relationships r
     where r.follower_id = p_profile_id
       -- ...but not the follow of the referrer, which referral_claim creates.
       and r.followee_id is distinct from (
         select ref.referrer_profile_id from public.referrals ref
          where ref.referred_profile_id = p_profile_id)
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
$function$;

revoke execute on function public.referral_first_action(integer, timestamp with time zone) from public;
grant execute on function public.referral_first_action(integer, timestamp with time zone) to authenticated, service_role;

create or replace function public.referral_claim(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $function$
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

  -- Follow the budtender who invited them. After the attribution above, so that the
  -- qualification trigger this fires sees the referral row it needs to exclude the
  -- follow from first_action. ON CONFLICT because they may already follow them —
  -- someone can scan a code from a budtender they already knew about.
  insert into public.relationships (follower_id, followee_id)
  values (me, owner_id)
  on conflict (follower_id, followee_id) do nothing;

  return true;
end;
$function$;

revoke execute on function public.referral_claim(text) from public;
grant execute on function public.referral_claim(text) to authenticated;
