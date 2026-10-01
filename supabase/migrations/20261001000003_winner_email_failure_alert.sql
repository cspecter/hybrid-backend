-- Tell the staff when a winner email fails.
--
-- The outcome of every attempt is recorded now, but a view nobody opens has the same
-- problem as the log nobody read: the 401 on 24 Sep sat in net._http_response for a week,
-- the giveaway was marked drawn, and the winner never heard by email. This closes that by
-- putting the failure in front of someone.
--
-- Grouped per giveaway per sweep rather than per attempt. A giveaway with five winners
-- failing during a Mailgun outage would otherwise be five notifications times three super
-- admins, and fifteen rows saying one thing is a way of saying nothing.

-- The sequence has drifted behind max(id) before, and an insert here would then fail on the
-- primary key before on-conflict could help. Idempotent, so it costs nothing to repeat.
select setval('public.notification_types_id_seq',
              (select max(id) from public.notification_types), true);

insert into public.notification_types (code, name, category, title_template, body_template, priority)
values
  ('giveaway_email_failed', 'Winner email failed', 'system',
   'A winner email didn''t send',
   'A giveaway was drawn but the winner''s email did not go out. They were notified in the app.', 9)
on conflict (code) do nothing;

-- Which attempts have already been reported, so a sweep every ten minutes does not say the
-- same thing six times an hour.
alter table public.giveaway_email_log add column if not exists alerted_at timestamptz;

create index if not exists giveaway_email_log_unalerted_idx
  on public.giveaway_email_log (queued_at) where alerted_at is null;

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
           min(left(v.detail, 140)) as sample_detail
    from public.v_giveaway_email_outcome v
    join public.giveaway_email_log l on l.id = v.id
    where v.outcome in ('failed', 'never sent')
      and l.alerted_at is null
    group by v.giveaway_id, v.giveaway_name
  loop
    -- Addressed to each super admin's own profile, so it lands in the ordinary
    -- notification list rather than needing a new surface. super_admins holds auth_id
    -- only; one with no profile row is skipped rather than erroring, because
    -- is_super_admin() reads super_admins and the two can legitimately disagree.
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

    update public.giveaway_email_log
       set alerted_at = now()
     where id = any(g.log_ids);

    v_total := v_total + g.failures;
  end loop;

  return v_total;
end;
$$;

comment on function public.giveaway_email_alert_failures() is
  'Notify every super admin about winner emails that failed or never left, one notification per giveaway per sweep, and mark those attempts reported so they are not raised again.';

revoke execute on function public.giveaway_email_alert_failures() from public, anon, authenticated;

-- Ten minutes after the hour's draws, which run every five. pg_net answers asynchronously,
-- so a sweep on the same cadence as the draw would keep finding attempts still in flight
-- and classify nothing.
select cron.schedule(
  'giveaway-email-failure-alert',
  '*/10 * * * *',
  $$select public.giveaway_email_alert_failures()$$
);
