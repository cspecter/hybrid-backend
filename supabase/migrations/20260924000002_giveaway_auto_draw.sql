-- Draw a giveaway when it ends, without anyone being awake for it.
--
-- Until now the only way a giveaway got drawn was a super admin opening the admin
-- manager and pressing Pick Winner. Over a month of scheduled drops that is a month
-- of remembering, and a forgotten draw is a prize nobody receives and an entrant
-- list that quietly rots. Every one of the 103 giveaways in this database was drawn
-- by hand.
--
-- THE SHAPE OF THE PROBLEM auto_pick_giveaway_winner could not be reused directly:
-- its first act is to resolve auth.uid() and demand is_super_admin(), and a cron job
-- has no JWT at all, so it would fail on 'Not authenticated' every time. Rather than
-- weaken that check or clone the pick logic — two copies of a random draw is exactly
-- the kind of thing that diverges and gets noticed a year later by the person who
-- didn't win — the body moves down into an internal function that takes no view on
-- who is asking, and both callers go through it:
--
--   auto_pick_giveaway_winner  (client)  authorization → giveaway_finalize
--   giveaway_draw_due          (cron)    due-list      → giveaway_finalize
--
-- giveaway_finalize is granted to nobody. It is SECURITY DEFINER and reachable only
-- through those two, so the authorization story is unchanged for anything that can
-- actually be called.
--
-- WHAT MOVED IN, AND WHY MORE THAN A MOVE: the old function notified the winners and
-- stopped there. Telling the people who lost was done afterwards in JavaScript, by
-- the browser that pressed the button — which meant a cron draw would have closed
-- the loop for nobody, and also meant every manual draw sent its winners TWO "you
-- won" notifications, one from SQL and one from the client. Both notifications now
-- come from here, once, whoever triggered the draw.

-- ─── The draw itself ─────────────────────────────────────────────────────────
create or replace function public.giveaway_finalize(p_giveaway_id integer, p_send_email boolean default true)
returns table(winners_picked integer, total_entries integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_total_prizes  integer;
  v_entries_count integer;
  v_picked        integer := 0;
  v_name          text;
  v_won_type      integer;
  v_finished_type integer;
begin
  -- Optimistic lock, unchanged from the original: SKIP LOCKED means a draw already
  -- in flight elsewhere is a no-op here rather than a wait, and selected_winner in
  -- the predicate makes a second call idempotent.
  select coalesce(total_prizes, 1), name
    into v_total_prizes, v_name
    from public.giveaways
   where id = p_giveaway_id and selected_winner = false
     for update skip locked;

  if not found then
    return query select 0, 0;
    return;
  end if;

  select count(*) into v_entries_count
    from public.giveaway_entries
   where giveaway_id = p_giveaway_id and won = false;

  -- A giveaway nobody entered is still finished. Marking it closes it out so the
  -- due-list does not keep returning it every five minutes forever.
  if v_entries_count = 0 then
    update public.giveaways set selected_winner = true, winner_count = 0
     where id = p_giveaway_id;
    return query select 0, 0;
    return;
  end if;

  v_total_prizes := least(v_total_prizes, v_entries_count);

  with picked as (
    select id from public.giveaway_entries
     where giveaway_id = p_giveaway_id and won = false
     order by random()
     limit v_total_prizes
  )
  update public.giveaway_entries set won = true where id in (select id from picked);

  get diagnostics v_picked = row_count;

  update public.giveaways set selected_winner = true, winner_count = v_picked
   where id = p_giveaway_id;

  select id into v_won_type from public.notification_types where code = 'giveaway_won';
  select id into v_finished_type from public.notification_types where code = 'giveaway_finished';

  -- Winners.
  if v_won_type is not null then
    insert into public.notifications (profile_id, type_id, related_type, related_id, title, body)
    select e.profile_id, v_won_type, 'giveaway', p_giveaway_id,
           'You won! 🎉',
           'You won ' || coalesce(v_name, 'a giveaway') || '. Open the giveaway for how to claim it.'
      from public.giveaway_entries e
     where e.giveaway_id = p_giveaway_id and e.won = true and e.profile_id is not null;
  end if;

  -- Everyone else who entered. A draw they lost still deserves an ending, and an
  -- entrant who hears nothing cannot tell "not picked" from "we forgot".
  if v_finished_type is not null then
    insert into public.notifications (profile_id, type_id, related_type, related_id, title, body)
    select e.profile_id, v_finished_type, 'giveaway', p_giveaway_id,
           'Giveaway drawn',
           coalesce(v_name, 'A giveaway') || ' has been drawn. You were not picked this time — more drops coming.'
      from public.giveaway_entries e
     where e.giveaway_id = p_giveaway_id and e.won = false and e.profile_id is not null;
  end if;

  -- Email, for the caller that cannot do it itself.
  --
  -- A super admin pressing Pick Winner passes false and calls the Edge Function from
  -- the browser instead, because it wants the send's outcome to put in front of them
  -- — "winner picked, but the email didn't send" is a sentence someone needs to read
  -- while they are still looking at the screen. pg_net cannot give an answer back, so
  -- the scheduler takes the fire-and-forget route and nobody is waiting for it.
  --
  -- Either way only one of the two sends: the composing and the template live in one
  -- place regardless of which door the draw came through.
  if p_send_email then
    perform public.giveaway_winner_email_dispatch(p_giveaway_id);
  end if;

  return query select v_picked, v_entries_count;
end;
$$;

revoke all privileges on function public.giveaway_finalize(integer, boolean) from public, anon, authenticated;

-- ─── Reaching the mailer ─────────────────────────────────────────────────────
-- The winner email is composed by an Edge Function, because Mailgun needs an HTTP
-- call and a credential this database has no business holding. pg_net makes the
-- call; Vault holds the token, for the reasons outreach_invoke sets out at length.
--
-- FIRE AND FORGET, ON PURPOSE. net.http_post returns as soon as the request is
-- queued, so a slow or unreachable mailer cannot hold open the transaction that just
-- committed a draw. Nobody loses a prize because Mailgun had a bad minute — the
-- in-app notification above is the channel of record, and this is the courtesy copy.
--
-- STATED PLAINLY: there is no retry. A dropped request is a dropped email. That is
-- an acceptable trade only because of the next paragraph.
--
-- WORTH KNOWING BEFORE RELYING ON THIS AT ALL: exactly one of 2,485 profiles has an
-- email address, because sign-in is phone OTP and nothing ever asks for an email.
-- For everyone else the function will answer no_email and send nothing. This wires
-- up the capability; it does not create the addresses, and collecting them is a
-- product decision nobody has made yet.
--
-- Until the two secrets exist this logs a notice and returns. Nothing fails.
create or replace function public.giveaway_winner_email_dispatch(p_giveaway_id integer)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  base  text;
  token text;
  w     record;
begin
  select decrypted_secret into base
    from vault.decrypted_secrets where name = 'functions_base_url';
  select decrypted_secret into token
    from vault.decrypted_secrets where name = 'giveaway_invoke_token';

  if base is null or token is null then
    -- Names only, never any part of a value.
    raise notice 'giveaway_winner_email_dispatch(%): vault secrets not set (functions_base_url / giveaway_invoke_token) — no email sent', p_giveaway_id;
    return;
  end if;

  for w in
    select profile_id from public.giveaway_entries
     where giveaway_id = p_giveaway_id and won = true and profile_id is not null
  loop
    perform net.http_post(
      url     := rtrim(base, '/') || '/giveaway-winner-email',
      headers := jsonb_build_object(
                   'Content-Type', 'application/json',
                   'Authorization', 'Bearer ' || token
                 ),
      body    := jsonb_build_object('giveaway_id', p_giveaway_id,
                                    'winner_profile_id', w.profile_id),
      timeout_milliseconds := 20000
    );
  end loop;
end;
$$;

revoke all privileges on function public.giveaway_winner_email_dispatch(integer) from public, anon, authenticated;

-- ─── The client's entry point, now a doorman ─────────────────────────────────
-- Same name, same signature, same return type, same authorization. The live
-- definition was diffed against the migration that created it before being replaced
-- here, and the only thing removed is the pick-and-notify body that now lives in
-- giveaway_finalize.
--
-- The is_super_admin() check stays exactly as it was, including the deliberate
-- omission of a created_by_profile_id branch — that decision and its reasoning are
-- in 20260918000003 and nothing here revisits it.
create or replace function public.auto_pick_giveaway_winner(p_giveaway_id integer)
returns table(winners_picked integer, total_entries integer)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_requester_profile_id integer;
begin
  select p.id into v_requester_profile_id
    from public.profiles p where p.auth_id = auth.uid();

  if v_requester_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_super_admin() then
    raise exception 'Access denied';
  end if;

  -- false: the browser that called this sends the email and reports what happened.
  return query select * from public.giveaway_finalize(p_giveaway_id, false);
end;
$$;

revoke all privileges on function public.auto_pick_giveaway_winner(integer) from public, anon;
grant execute on function public.auto_pick_giveaway_winner(integer) to authenticated, postgres, service_role;

-- ─── The scheduler's entry point ─────────────────────────────────────────────
-- Everything whose end_time has passed and which has not been drawn. No JWT, so no
-- authorization check is possible or wanted: the only thing it will act on is a
-- giveaway the clock has already closed.
--
-- BOUNDED AT 25 PER TICK so a backlog drains over several minutes instead of one
-- enormous transaction, and so a pathological row cannot make every later giveaway
-- wait behind it forever. At five-minute ticks that is 300 an hour.
--
-- Each giveaway is finalized in its own exception block. One that throws is logged
-- and skipped rather than rolling back the draws that already succeeded in this
-- tick — losing one draw is bad, losing twenty-four good ones alongside it is worse.
create or replace function public.giveaway_draw_due()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  g       record;
  v_drawn integer := 0;
begin
  for g in
    select id, name from public.giveaways
     where selected_winner = false
       and end_time is not null
       and end_time <= now()
     order by end_time
     limit 25
  loop
    begin
      perform public.giveaway_finalize(g.id, true);
      v_drawn := v_drawn + 1;
    exception when others then
      raise warning 'giveaway_draw_due: giveaway % (%) failed: %', g.id, g.name, sqlerrm;
    end;
  end loop;

  return v_drawn;
end;
$$;

revoke all privileges on function public.giveaway_draw_due() from public, anon, authenticated;

-- Every five minutes, matching process_scheduled_notifications. A giveaway that
-- closes at 8pm is drawn by 8:05 — close enough that an entrant refreshing the page
-- sees a result, and loose enough that the schedule is not pretending to be exact.
select cron.schedule('giveaway_draw_due', '*/5 * * * *', $$select public.giveaway_draw_due()$$);
