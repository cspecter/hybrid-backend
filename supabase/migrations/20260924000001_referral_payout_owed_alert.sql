-- Tell Hybrid when it owes someone money.
--
-- referral_check_target has always created the payout row and notified the
-- budtender that their reward "is being processed". Nobody at Hybrid was told
-- anything. The payout queue sits in the admin referral panel behind two taps, so
-- the only way to discover an obligation was to go looking for one — and with the
-- reward being a $20 gift card sent by hand, "nobody went looking" is the failure
-- mode that costs a budtender their reward and Hybrid its credibility with the
-- store that put them up to it.
--
-- So the same event now also notifies every super admin. In-app, because that is
-- the only channel this project actually delivers on today: there are no push
-- tokens and one email address across 2,485 profiles.
--
-- WHY NOT A DIGEST: a payout is rare — 40 qualified signups each — and arrives at
-- the moment a budtender has just done the work and is watching for the reward.
-- One notification per payout is the right volume, and a nightly roll-up would put
-- up to a day between the earning and the noticing.

-- The id sequence had drifted behind the table: last_value and max(id) were both 86,
-- so the next nextval() handed back an id that already existed and ANY insert here
-- failed on the primary key before the on-conflict-on-code clause could do its job.
-- This migration hit it on the first attempt. Repaired for everyone, not just for the
-- row below, since the next person to add a notification type would have hit it too.
select setval('public.notification_types_id_seq',
               (select max(id) from public.notification_types), true);

insert into public.notification_types (code, name, category, title_template, body_template, priority)
values
  ('referral_payout_owed', 'Reward owed', 'system',
   'A reward is owed',
   'A budtender hit the referral target. Approve and send it from Admin → Referrals.', 9)
on conflict (code) do nothing;

-- Notify every super admin, addressed to their own profile so it lands in the
-- ordinary notification list rather than needing a new surface.
--
-- super_admins holds auth_id only, so the profile id comes back through profiles.
-- A super admin with no profile row is skipped rather than erroring: is_super_admin()
-- reads super_admins, so the two can legitimately disagree.
create or replace function public.referral_notify_staff_payout_owed(p_profile_id integer, p_cycle integer)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  t record;
  v_who text;
begin
  select id, title_template, body_template into t
    from public.notification_types where code = 'referral_payout_owed';
  if t.id is null then return; end if;

  -- The budtender's own handle, so the notification is actionable without a lookup.
  select coalesce(nullif(trim(display_name), ''), username, 'A budtender')
    into v_who from public.profiles where id = p_profile_id;

  insert into public.notifications (profile_id, type_id, related_type, related_id, title, body)
  select p.id, t.id, 'profile', p_profile_id,
         t.title_template,
         v_who || ' hit the referral target (reward #' || p_cycle ||
         '). Approve and send it from Admin → Referrals.'
    from public.super_admins sa
    join public.profiles p on p.auth_id = sa.auth_id;
end;
$$;

revoke execute on function public.referral_notify_staff_payout_owed(integer, integer) from public, anon, authenticated;

-- ─── referral_check_target, patched ──────────────────────────────────────────
-- Reproduced from the live definition (pg_get_functiondef) and diffed, rather than
-- retyped from the migration that created it: that mistake once silently dropped a
-- whole block from send_notification.
--
-- The only change is the one added line marked below.
CREATE OR REPLACE FUNCTION public.referral_check_target(p_profile_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- ...and tell Hybrid, which is the half that was missing.
    perform public.referral_notify_staff_payout_owed(p_profile_id, i);
  end loop;
end;
$function$;
