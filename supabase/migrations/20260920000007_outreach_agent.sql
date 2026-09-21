-- Outreach agent: onboarding and engagement email.
--
-- Four tables plus a settings row. None of them carry a grant to anon or
-- authenticated: the agent runs as service_role from Edge Functions, and the
-- admin dashboard reads through the SECURITY DEFINER views at the bottom of this
-- file, which check is_super_admin() before answering. Table privileges are
-- checked before row security, so the REVOKEs are the real lock and RLS is the
-- second one — both are here because this database hands anon broad default
-- grants on new tables (see location_employees) and a future GRANT would
-- otherwise open these silently.
--
-- No credential, key or token is stored in any of these tables. The Anthropic key,
-- the Gmail OAuth client and the refresh token live in Supabase function secrets
-- and are read from the environment inside the functions.

-- ─── Contacts ────────────────────────────────────────────────────────────────
-- consent_basis is NOT NULL and non-blank by constraint, not by convention: this
-- is cannabis marketing in NY and NJ, and a row that cannot say why it may be
-- emailed must not exist. The importer rejects such rows; the constraint means a
-- direct insert cannot create one either.
create table if not exists public.outreach_contacts (
  id                      bigint generated always as identity primary key,
  public_id               uuid not null default gen_random_uuid(),
  email                   text not null,
  name                    text,
  segment                 text not null
                            check (segment in ('consumer', 'creator', 'brand', 'dispensary')),
  -- Set where the person already has an account, so digests and nudges can read
  -- their real state. Null means prospect: the emails point at signing up.
  profile_id              integer references public.profiles(id) on delete set null,
  consent_basis           text not null check (btrim(consent_basis) <> ''),
  source                  text,
  status                  text not null default 'active'
                            check (status in ('active', 'paused', 'completed',
                                              'unsubscribed', 'bounced', 'complained',
                                              'no_engagement')),

  -- Sequence state. stage moves welcome -> sequence -> updates and never back.
  stage                   text not null default 'welcome'
                            check (stage in ('welcome', 'sequence', 'updates')),
  sequence_step           integer not null default 0,
  sends_count             integer not null default 0,
  -- Reset to 0 by any inbound reply. Drives the no-engagement stop condition.
  sends_since_engagement  integer not null default 0,
  replies_count           integer not null default 0,
  last_sent_at            timestamptz,
  -- The scheduler only ever picks up rows whose next_eligible_at has passed, so
  -- every interval in config.ts becomes a single value written on this row.
  next_eligible_at        timestamptz not null default now(),
  last_digest_at          timestamptz,
  last_nudge_field        text,
  gmail_thread_id         text,
  notes                   text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint outreach_contacts_email_key unique (email)
);

-- Addresses are compared case-insensitively everywhere (suppression especially),
-- so they are stored one way. Doing it in a trigger rather than in the importer
-- means a direct insert cannot slip a mixed-case duplicate past the unique index.
create or replace function public.outreach_normalize_email()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.email := lower(btrim(new.email));
  new.updated_at := now();
  return new;
end;
$$;

create trigger outreach_contacts_normalize
  before insert or update on public.outreach_contacts
  for each row execute function public.outreach_normalize_email();

create index if not exists outreach_contacts_due_idx
  on public.outreach_contacts (next_eligible_at)
  where status = 'active';
create index if not exists outreach_contacts_profile_idx
  on public.outreach_contacts (profile_id) where profile_id is not null;
create index if not exists outreach_contacts_segment_idx
  on public.outreach_contacts (segment, status);

-- ─── Messages: the audit trail ───────────────────────────────────────────────
-- Every message the agent sends, drafts or receives, including the ones it
-- refused to answer. Nothing is deleted here.
create table if not exists public.outreach_messages (
  id               bigint generated always as identity primary key,
  contact_id       bigint references public.outreach_contacts(id) on delete set null,
  -- Kept alongside contact_id so an inbound reply from an address that is not a
  -- contact (forwarded, aliased) is still logged rather than dropped.
  email            text,
  direction        text not null check (direction in ('outbound', 'inbound')),
  message_type     text not null,
  subject          text,
  body             text,
  gmail_message_id text,
  gmail_thread_id  text,
  -- 'drafted' is a real outcome, not a failure: draft mode is the default.
  status           text not null default 'logged'
                     check (status in ('drafted', 'sent', 'received', 'failed', 'skipped')),
  mode             text check (mode in ('draft', 'send')),
  -- Inbound only: how_to | unsubscribe | escalate | unclear
  classification   text,
  needs_human      boolean not null default false,
  handled_at       timestamptz,
  handled_by       integer references public.profiles(id) on delete set null,
  error            text,
  created_at       timestamptz not null default now()
);

create index if not exists outreach_messages_contact_idx
  on public.outreach_messages (contact_id, created_at desc);
create index if not exists outreach_messages_thread_idx
  on public.outreach_messages (gmail_thread_id) where gmail_thread_id is not null;
create index if not exists outreach_messages_needs_human_idx
  on public.outreach_messages (created_at desc) where needs_human and handled_at is null;
create index if not exists outreach_messages_day_idx
  on public.outreach_messages (created_at desc);
-- The reply poller asks "have I already processed this Gmail message?" on every
-- pass; without this it would re-answer the same reply after a partial failure.
create unique index if not exists outreach_messages_inbound_gmail_idx
  on public.outreach_messages (gmail_message_id)
  where direction = 'inbound' and gmail_message_id is not null;

-- ─── Suppressions: checked before every send, no exceptions ──────────────────
create table if not exists public.outreach_suppressions (
  id         bigint generated always as identity primary key,
  email      text not null unique,
  reason     text not null
               check (reason in ('unsubscribed', 'bounced', 'complained', 'manual')),
  source     text,
  contact_id bigint references public.outreach_contacts(id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function public.outreach_normalize_suppression()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.email := lower(btrim(new.email));
  return new;
end;
$$;

create trigger outreach_suppressions_normalize
  before insert or update on public.outreach_suppressions
  for each row execute function public.outreach_normalize_suppression();

-- Suppressing an address takes the contact out of the rotation in the same
-- statement. Two tables could otherwise disagree about whether someone is still
-- being emailed, and the one the scheduler reads would win.
create or replace function public.outreach_apply_suppression()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update public.outreach_contacts
     set status = case new.reason
                    when 'bounced'    then 'bounced'
                    when 'complained' then 'complained'
                    else 'unsubscribed'
                  end,
         next_eligible_at = 'infinity'::timestamptz
   where lower(email) = new.email;
  return new;
end;
$$;

create trigger outreach_suppressions_stop_contact
  after insert on public.outreach_suppressions
  for each row execute function public.outreach_apply_suppression();

-- ─── Knowledge document ──────────────────────────────────────────────────────
-- The only thing reply answers may draw on. A table rather than a file in the
-- repo so it can be edited in the Supabase table editor without a deploy; the
-- body column is plain markdown.
create table if not exists public.outreach_knowledge (
  id         integer generated always as identity primary key,
  slug       text not null unique,
  title      text not null,
  body       text not null,
  sort_order integer not null default 100,
  is_active  boolean not null default true,
  updated_at timestamptz not null default now()
);

-- ─── Settings: one row, the kill switch ──────────────────────────────────────
create table if not exists public.outreach_settings (
  id             integer primary key default 1 check (id = 1),
  is_paused      boolean not null default false,
  paused_at      timestamptz,
  paused_by      integer references public.profiles(id) on delete set null,
  pause_reason   text,
  updated_at     timestamptz not null default now()
);

insert into public.outreach_settings (id) values (1) on conflict (id) do nothing;

-- ─── Lock the tables ─────────────────────────────────────────────────────────
-- RLS with no policy at all denies every row to every non-bypassing role, which
-- is exactly the intent. service_role bypasses RLS; anon and authenticated do
-- not, and have no privileges to reach it with either.
alter table public.outreach_contacts    enable row level security;
alter table public.outreach_messages    enable row level security;
alter table public.outreach_suppressions enable row level security;
alter table public.outreach_knowledge   enable row level security;
alter table public.outreach_settings    enable row level security;

revoke all on public.outreach_contacts     from anon, authenticated, public;
revoke all on public.outreach_messages     from anon, authenticated, public;
revoke all on public.outreach_suppressions from anon, authenticated, public;
revoke all on public.outreach_knowledge    from anon, authenticated, public;
revoke all on public.outreach_settings     from anon, authenticated, public;

grant all on public.outreach_contacts     to service_role;
grant all on public.outreach_messages     to service_role;
grant all on public.outreach_suppressions to service_role;
grant all on public.outreach_knowledge    to service_role;
grant all on public.outreach_settings     to service_role;

-- ─── Admin dashboard surface ─────────────────────────────────────────────────
-- The dashboard runs as `authenticated` and must never touch the tables. These
-- three functions are the whole interface, and each one refuses anyone who is not
-- a super admin. current_user rebinds inside a DEFINER function, so the guard has
-- to read the request's JWT role rather than ask who it is running as.

create or replace function public.outreach_admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.is_super_admin() then
    raise exception 'Not authorised';
  end if;

  select jsonb_build_object(
    'paused', (select is_paused from public.outreach_settings where id = 1),
    'paused_at', (select paused_at from public.outreach_settings where id = 1),
    'pause_reason', (select pause_reason from public.outreach_settings where id = 1),
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object('segment', segment, 'status', status, 'count', c)
             order by segment, status)
      from (select segment, status, count(*) c
              from public.outreach_contacts group by segment, status) s
    ), '[]'::jsonb),
    'contacts_total', (select count(*) from public.outreach_contacts),
    -- Fourteen days of activity is what fits on the card without scrolling.
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('day', d, 'sent', sent, 'drafted', drafted,
                                          'received', received) order by d desc)
      from (
        select created_at::date d,
               count(*) filter (where status = 'sent')     sent,
               count(*) filter (where status = 'drafted')  drafted,
               count(*) filter (where direction = 'inbound') received
          from public.outreach_messages
         where created_at > now() - interval '14 days'
         group by 1
      ) t
    ), '[]'::jsonb),
    'awaiting_human', (
      select count(*) from public.outreach_messages
       where needs_human and handled_at is null
    ),
    'suppressions', (select count(*) from public.outreach_suppressions),
    'suppressions_recent', coalesce((
      select jsonb_agg(jsonb_build_object('email', email, 'reason', reason,
                                          'created_at', created_at) order by created_at desc)
      from (select email, reason, created_at from public.outreach_suppressions
             order by created_at desc limit 10) r
    ), '[]'::jsonb),
    'last_send_at', (select max(created_at) from public.outreach_messages
                      where direction = 'outbound')
  ) into result;

  return result;
end;
$$;

-- The replies a human still has to look at. Body is truncated here rather than in
-- the client so a long forwarded thread cannot bloat the dashboard payload.
create or replace function public.outreach_pending_replies(p_limit integer default 25)
returns table (
  id bigint,
  email text,
  name text,
  segment text,
  classification text,
  subject text,
  excerpt text,
  gmail_thread_id text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Not authorised';
  end if;

  return query
    select m.id,
           coalesce(c.email, m.email),
           c.name,
           c.segment,
           m.classification,
           m.subject,
           left(coalesce(m.body, ''), 600),
           m.gmail_thread_id,
           m.created_at
      from public.outreach_messages m
      left join public.outreach_contacts c on c.id = m.contact_id
     where m.needs_human and m.handled_at is null
     order by m.created_at desc
     limit greatest(1, least(coalesce(p_limit, 25), 200));
end;
$$;

create or replace function public.outreach_set_paused(p_paused boolean, p_reason text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  me integer;
begin
  if not public.is_super_admin() then
    raise exception 'Not authorised';
  end if;

  select id into me from public.profiles where auth_id = auth.uid() limit 1;

  update public.outreach_settings
     set is_paused    = coalesce(p_paused, false),
         paused_at    = case when coalesce(p_paused, false) then now() else null end,
         paused_by    = case when coalesce(p_paused, false) then me else null end,
         pause_reason = case when coalesce(p_paused, false) then p_reason else null end,
         updated_at   = now()
   where id = 1;

  return coalesce(p_paused, false);
end;
$$;

create or replace function public.outreach_mark_reply_handled(p_message_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  me integer;
begin
  if not public.is_super_admin() then
    raise exception 'Not authorised';
  end if;

  select id into me from public.profiles where auth_id = auth.uid() limit 1;

  update public.outreach_messages
     set handled_at = now(), handled_by = me
   where id = p_message_id and needs_human and handled_at is null;

  return found;
end;
$$;

revoke all on function public.outreach_admin_overview()               from public;
revoke all on function public.outreach_pending_replies(integer)       from public;
revoke all on function public.outreach_set_paused(boolean, text)      from public;
revoke all on function public.outreach_mark_reply_handled(bigint)     from public;

grant execute on function public.outreach_admin_overview()           to authenticated;
grant execute on function public.outreach_pending_replies(integer)   to authenticated;
grant execute on function public.outreach_set_paused(boolean, text)  to authenticated;
grant execute on function public.outreach_mark_reply_handled(bigint) to authenticated;
