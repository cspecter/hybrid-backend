-- Narrow what counts as worth waking someone for.
--
-- The first version alerted on outcome in ('failed', 'never sent'), and "never sent" covers
-- the note "no winner rows to email". That is not a failure -- a giveaway whose winners have
-- no profile row has nothing to email and nothing went wrong -- and alerting on it would have
-- put a notification in front of three super admins for an ordinary event.
--
-- Worth alerting on: a send that came back an error, and a dispatch that could not even start
-- because the Vault secrets are missing. The second is rare and serious: it means every
-- winner email is silently doing nothing.
--
-- Deliberately not alerting on "refused by the function", which is almost always a winner
-- with no email address on file. That is the expected case for now -- of 3,054 profiles one
-- has an address -- and alerting on it would make the alert worthless by the second draw.
create or replace function public.giveaway_email_alert_failures()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  t_id     integer;
  t_title  text;
  g        record;
  v_total  integer := 0;
begin
  select id, title_template into t_id, t_title
    from public.notification_types where code = 'giveaway_email_failed';
  if t_id is null then return 0; end if;

  for g in
    select v.giveaway_id,
           coalesce(nullif(trim(v.giveaway_name), ''), 'A giveaway') as giveaway_name,
           count(*) as failures,
           array_agg(v.id) as log_ids,
           min(left(coalesce(v.detail, v.note), 140)) as sample_detail
    from public.v_giveaway_email_outcome v
    join public.giveaway_email_log l on l.id = v.id
    where l.alerted_at is null
      and (
            v.outcome = 'failed'
         or (v.outcome = 'never sent' and v.note like 'vault secrets not set%')
      )
    group by v.giveaway_id, v.giveaway_name
  loop
    insert into public.notifications (profile_id, type_id, related_type, related_id, title, body)
    select p.id, t_id, 'giveaway', g.giveaway_id,
           t_title,
           case when g.failures = 1
                then 'The winner email for "' || g.giveaway_name || '" did not send. ' ||
                     'The winner was notified in the app. Reason: ' || coalesce(g.sample_detail, 'unknown') || '.'
                else g.failures || ' winner emails for "' || g.giveaway_name || '" did not send. ' ||
                     'The winners were notified in the app. First reason: ' || coalesce(g.sample_detail, 'unknown') || '.'
           end
      from public.super_admins sa
      join public.profiles p on p.auth_id = sa.auth_id;

    update public.giveaway_email_log set alerted_at = now() where id = any(g.log_ids);
    v_total := v_total + g.failures;
  end loop;

  return v_total;
end;
$$;

-- Attempts that are not failures are marked reported straight away, so they never sit in the
-- unalerted set and the sweep's work stays proportional to what actually went wrong.
create or replace function public.giveaway_email_mark_benign() returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update giveaway_email_log l set alerted_at = now()
   where l.alerted_at is null
     and exists (
       select 1 from v_giveaway_email_outcome v
        where v.id = l.id
          and (v.outcome in ('sent', 'refused by the function')
            or (v.outcome = 'never sent' and coalesce(v.note,'') not like 'vault secrets not set%'))
     );
  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.giveaway_email_mark_benign() is
  'Mark attempts that need no attention as reported: sent, refused by the function, and notes that are not about missing Vault secrets.';

revoke execute on function public.giveaway_email_mark_benign() from public, anon, authenticated;

select cron.unschedule('giveaway-email-failure-alert');
select cron.schedule(
  'giveaway-email-failure-alert',
  '*/10 * * * *',
  $$select public.giveaway_email_mark_benign(), public.giveaway_email_alert_failures()$$
);
