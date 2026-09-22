-- Let a budtender claim the reward they have earned.
--
-- referral_check_target already creates a payout row the moment someone crosses the
-- target, with status 'pending', and notifies them. What it does not capture is the
-- budtender saying "yes, send it" — so the reward screen had nothing real to do, and
-- a Claim button would have been decoration.
--
-- Additive on purpose: claimed_at sits beside the existing status machine rather
-- than inside it. pending/approved/paid/rejected is moderation's lane and is
-- untouched; claimed_at is the budtender's, and the two answer different questions
-- ("has Hybrid actioned this" vs "has the person asked for it"). Folding the claim
-- into status would have meant a fifth value that every admin query already written
-- would have had to learn.
alter table public.referral_payouts
  add column if not exists claimed_at timestamptz;

-- Claim a cycle the caller has actually earned. Cycle rather than an id because the
-- client already has cycle numbers from referral_my_stats, and because it scopes
-- naturally: there is exactly one row per (profile, cycle).
create or replace function public.referral_claim_reward(p_cycle integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me     integer;
  v_row  public.referral_payouts%rowtype;
begin
  select id into me from public.profiles where auth_id = auth.uid() limit 1;
  if me is null then
    raise exception 'You must be signed in' using errcode = '42501';
  end if;

  select * into v_row from public.referral_payouts
   where profile_id = me and cycle = p_cycle
   for update;
  if not found then
    raise exception 'You have not earned that reward yet' using errcode = 'P0002';
  end if;
  if v_row.status = 'rejected' then
    raise exception 'That reward was not approved' using errcode = '22023';
  end if;
  -- Claiming twice is a double tap, not an error worth showing anyone.
  if v_row.claimed_at is not null then
    return jsonb_build_object('cycle', v_row.cycle, 'claimed_at', v_row.claimed_at, 'already', true);
  end if;

  update public.referral_payouts
     set claimed_at = now()
   where id = v_row.id;

  insert into public.referral_payout_events (payout_id, from_status, to_status, note)
  values (v_row.id, v_row.status, v_row.status, 'Claimed by the budtender');

  return jsonb_build_object('cycle', v_row.cycle, 'claimed_at', now(), 'already', false);
end;
$$;

revoke execute on function public.referral_claim_reward(integer) from public;
grant execute on function public.referral_claim_reward(integer) to authenticated;

-- referral_my_stats already returns the payouts array; it now carries claimed_at so
-- the reward screen can tell "ready to claim" from "claimed, waiting on Hybrid"
-- without a second round trip.
create or replace function public.referral_my_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  me integer;
  tgt integer; label text; win integer; paused boolean;
  qualified integer; pending integer; expired integer;
  since timestamptz;
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

  select min(le.created_at) into since
    from public.location_employees le
   where le.profile_id = me and le.is_approved is true and le.role = 'budtender';

  return jsonb_build_object(
    'eligible', public.referral_is_eligible(me),
    'code', (select code from public.referral_codes where profile_id = me),
    'paused', coalesce(paused, false),
    'target', tgt, 'reward_label', label, 'qualify_window_days', win,
    'qualified', qualified, 'pending', pending, 'expired', expired,
    'budtender_since', since,
    'cycles_earned', floor(qualified / greatest(tgt, 1)),
    'toward_next', qualified % greatest(tgt, 1),
    'payouts', coalesce((
      select jsonb_agg(jsonb_build_object('cycle', cycle, 'status', status,
                                          'reward_label', reward_label,
                                          'claimed_at', claimed_at,
                                          'created_at', created_at)
             order by cycle desc)
        from public.referral_payouts where profile_id = me), '[]'::jsonb)
  );
end;
$function$;

revoke execute on function public.referral_my_stats() from public;
grant execute on function public.referral_my_stats() to authenticated;
