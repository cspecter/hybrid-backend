-- Scheduling the outreach agent.
--
-- The two cron jobs that already exist call SQL functions directly; these two have
-- to reach an Edge Function, because the work needs the Anthropic and Gmail APIs.
-- pg_net makes the call and Vault holds what it needs to authenticate with.
--
-- WHY VAULT AND NOT A CONSTANT: the token is a credential, so it is not in this
-- migration, not in the function body below, and not in any table this project
-- owns. vault.decrypted_secrets is encrypted at rest and readable only by roles
-- that bypass RLS — anon and authenticated have no privilege on it.
--
-- KNOWN CAVEAT, stated rather than hidden: pg_net puts each pending request,
-- Authorization header included, into net.http_request_queue for the moment
-- between the call and the dispatch, then deletes the row. anon and authenticated
-- hold no grant on that table (checked: they have schema USAGE and nothing else),
-- so the exposure is to roles that could read the secret anyway. This is inherent
-- to pg_net, not to how it is used here.
--
-- Until both secrets are set, outreach_invoke logs a notice and returns. Nothing
-- fails, nothing sends. See docs/OUTREACH-AGENT.md for the two commands.

create or replace function public.outreach_invoke(p_function text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  base  text;
  token text;
begin
  -- The pause switch stops the agent at the scheduler, so a paused agent makes no
  -- outbound HTTP call at all rather than making one that returns early.
  if coalesce((select is_paused from public.outreach_settings where id = 1), false) then
    return;
  end if;

  select decrypted_secret into base
    from vault.decrypted_secrets where name = 'outreach_functions_base_url';
  select decrypted_secret into token
    from vault.decrypted_secrets where name = 'outreach_invoke_token';

  if base is null or token is null then
    -- Deliberately says which secret, never any part of a value.
    raise notice 'outreach_invoke(%): vault secrets not set (outreach_functions_base_url / outreach_invoke_token) — skipping', p_function;
    return;
  end if;

  perform net.http_post(
    url     := rtrim(base, '/') || '/' || p_function,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || token
               ),
    body    := jsonb_build_object('source', 'pg_cron'),
    timeout_milliseconds := 55000
  );
end;
$$;

revoke all on function public.outreach_invoke(text) from public, anon, authenticated;

-- Sending: every 15 minutes across a UTC range wide enough to cover the 09:00–18:00
-- Eastern window in both halves of the year. The function re-checks the real local
-- hour, so the schedule being loose costs a no-op call, never an out-of-hours email.
select cron.schedule(
  'outreach_send',
  '*/15 12-23 * * 1-5',
  $$select public.outreach_invoke('outreach-send')$$
);

-- Replies: all day, every day. An unsubscribe that arrives at 3am on a Sunday has
-- to be honoured at 3am on a Sunday, and the reply function only defers the
-- answering of how-to questions to the sending window, never the suppressions.
select cron.schedule(
  'outreach_replies',
  '*/15 * * * *',
  $$select public.outreach_invoke('outreach-replies')$$
);
