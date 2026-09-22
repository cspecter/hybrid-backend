-- Tell the client WHEN someone became a budtender, so the referral nudge can leave
-- existing ones alone.
--
-- The nudge treats "no stored schedule" as the approval moment, which is right for
-- someone onboarded in a store and wrong for everyone who was already a budtender
-- before it shipped — they would all be interrupted on their next app open, having
-- asked for nothing. The client cannot tell the two apart without knowing when the
-- job started, so referral_my_stats now says.
--
-- created_at of the earliest approved budtender row, not updated_at: for the direct
-- add path (add_location_employee) that is exactly the moment they were made a
-- budtender, and for the request path it is when they asked, which is at most a few
-- days before approval. updated_at would look right and then drift, because
-- manage_timestamps bumps it on any later edit to the row.
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
$function$;

revoke execute on function public.referral_my_stats() from public;
grant execute on function public.referral_my_stats() to authenticated;
