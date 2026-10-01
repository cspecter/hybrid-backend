-- Make the scheduled draw's email outcome visible.
--
-- The chain already works: giveaway_draw_due calls giveaway_finalize(id, true), which calls
-- giveaway_winner_email_dispatch, which posts to the Edge Function with the Vault token. A
-- call on 24 Sep came back 200 with reason "no_email", which proves the whole path including
-- authorization.
--
-- What it does not do is tell anyone the outcome. pg_net cannot answer the caller, so the
-- dispatch fires and forgets, and on 24 Sep at 12:30 a send came back
-- "Mailgun API error: 401 - Forbidden" and sat in net._http_response for a week with nobody
-- looking. The giveaway was marked drawn, the winner got their in-app notification, and the
-- email silently did not happen. That is the part worth fixing: a scheduled job whose
-- failures are invisible is a scheduled job nobody can trust.
--
-- pg_net hands back a request id. Keeping it means the response can be found later, which
-- turns an invisible failure into a row someone can query.

create table if not exists public.giveaway_email_log (
  id          bigserial primary key,
  giveaway_id integer not null,
  profile_id  integer,
  request_id  bigint,          -- net.http_post's handle; null when no request was made
  note        text,            -- why, when no request was made
  queued_at   timestamptz not null default now()
);

create index if not exists giveaway_email_log_giveaway_idx on public.giveaway_email_log (giveaway_id);
create index if not exists giveaway_email_log_request_idx  on public.giveaway_email_log (request_id);
create index if not exists giveaway_email_log_queued_idx   on public.giveaway_email_log (queued_at desc);

comment on table public.giveaway_email_log is
  'One row per winner-email attempt from the scheduled draw, carrying the pg_net request id so the outcome can be looked up afterwards. A row with no request_id is an attempt that never left, and note says why.';

create or replace function public.giveaway_winner_email_dispatch(p_giveaway_id integer)
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  base  text;
  token text;
  w     record;
  req   bigint;
  n     integer := 0;
begin
  select decrypted_secret into base
    from vault.decrypted_secrets where name = 'functions_base_url';
  select decrypted_secret into token
    from vault.decrypted_secrets where name = 'giveaway_invoke_token';

  if base is null or token is null then
    -- Names only, never any part of a value. Recorded as well as raised, because a notice
    -- in a cron log is a notice nobody reads.
    insert into giveaway_email_log (giveaway_id, note)
    values (p_giveaway_id, 'vault secrets not set (functions_base_url / giveaway_invoke_token)');
    raise notice 'giveaway_winner_email_dispatch(%): vault secrets not set — no email sent', p_giveaway_id;
    return;
  end if;

  for w in
    select profile_id from public.giveaway_entries
     where giveaway_id = p_giveaway_id and won = true and profile_id is not null
  loop
    select net.http_post(
      url     := rtrim(base, '/') || '/giveaway-winner-email',
      headers := jsonb_build_object(
                   'Content-Type', 'application/json',
                   'Authorization', 'Bearer ' || token
                 ),
      body    := jsonb_build_object('giveaway_id', p_giveaway_id,
                                    'winner_profile_id', w.profile_id),
      timeout_milliseconds := 20000
    ) into req;

    insert into giveaway_email_log (giveaway_id, profile_id, request_id)
    values (p_giveaway_id, w.profile_id, req);
    n := n + 1;
  end loop;

  if n = 0 then
    insert into giveaway_email_log (giveaway_id, note)
    values (p_giveaway_id, 'no winner rows to email');
  end if;
end;
$function$;

comment on function public.giveaway_winner_email_dispatch(integer) is
  'Post a winner-email request per winner and record each pg_net request id in giveaway_email_log, so the outcome can be read afterwards rather than being lost.';

-- What actually happened to each attempt. net._http_response keeps responses for a limited
-- window, so an attempt older than that shows as 'expired' rather than pretending to know.
create or replace view public.v_giveaway_email_outcome as
  select l.id,
         l.giveaway_id,
         g.name as giveaway_name,
         l.profile_id,
         l.queued_at,
         l.note,
         r.status_code,
         case
           when l.note is not null                     then 'never sent'
           when r.id is null and l.queued_at > now() - interval '6 hours' then 'in flight'
           when r.id is null                           then 'expired from the response log'
           when r.status_code between 200 and 299
            and coalesce(r.content::text, '') like '%"ok":true%'  then 'sent'
           when r.status_code between 200 and 299      then 'refused by the function'
           else 'failed'
         end as outcome,
         left(coalesce(r.error_msg, r.content::text), 200) as detail
  from giveaway_email_log l
  left join giveaways g on g.id = l.giveaway_id
  left join net._http_response r on r.id = l.request_id;

comment on view public.v_giveaway_email_outcome is
  'Every winner-email attempt with what came back: sent, refused by the function (no email on file, for instance), failed, never sent, or still in flight.';

revoke all on table public.giveaway_email_log from anon, authenticated;
alter table public.giveaway_email_log enable row level security;
revoke all on function public.giveaway_winner_email_dispatch(integer) from anon, authenticated;
