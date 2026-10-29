-- Instagram consent belongs to a subject, not to a store.
--
-- 20261029000001 keyed all of this on location_id, which was wrong the moment anyone looked
-- at a brand page. Housing Works is two pages in this app -- location 163 and brand profile
-- 3175 -- and a shop that agrees to show its Instagram means both of them, not whichever one
-- the schema happened to support.
--
-- social_discovery already settled the shape of this question with (subject_type, subject_id)
-- over brands and locations. This follows it rather than inventing a third convention.
--
-- The embed argument is unchanged and is in 20261029000001: a post is a shortcode, Meta
-- serves the photograph to the visitor, and we hold no copy of anyone's work.
--
-- brand_instagram is untouched. That is the OAuth path, it caches images, and it stays the
-- better answer for a brand that authorises properly -- this is what a brand page can show
-- in the years before Meta approves the app.

-- ─── Who may speak for a subject ─────────────────────────────────────────────

create or replace function public.can_manage_instagram_subject(
  p_subject_type text, p_subject_id integer
) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select case p_subject_type
           when 'brand'    then public.can_admin_profile(p_subject_id)
           when 'location' then public.can_manage_location(p_subject_id)
           else false
         end;
$$;

comment on function public.can_manage_instagram_subject(text, integer) is
  'Delegates to the rule that already governs the subject: can_admin_profile for a brand, can_manage_location for a store. No third notion of who is in charge.';

-- ─── The tables, re-keyed ────────────────────────────────────────────────────

create table if not exists public.instagram_consent (
  subject_type     text not null check (subject_type in ('brand', 'location')),
  subject_id       integer not null,
  username         text,

  consent_status   text not null default 'granted'
                     check (consent_status in ('granted', 'revoked')),
  consent_source   text not null
                     check (consent_source in ('oauth', 'claim', 'email', 'phone', 'in_person', 'other')),
  consent_note     text,
  consent_by       integer references public.profiles(id),
  consent_at       timestamptz not null default now(),
  revoked_at       timestamptz,
  revoked_by       integer references public.profiles(id),

  source           text not null default 'manual' check (source in ('manual', 'graph')),
  ig_user_id       text,
  access_token     text,
  token_expires_at timestamptz,
  status           text not null default 'active'
                     check (status in ('active', 'needs_reauth', 'revoked')),
  last_sync_at     timestamptz,
  last_sync_error  text,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  primary key (subject_type, subject_id),
  constraint instagram_consent_revoked_ck check (
    (consent_status = 'revoked') = (revoked_at is not null)
  )
);

comment on table public.instagram_consent is
  'One row per brand or store that agreed to show its Instagram here, with the record of who agreed and how. Keyed the way social_discovery is keyed.';

create table if not exists public.instagram_consent_media (
  id           bigserial primary key,
  subject_type text not null,
  subject_id   integer not null,
  shortcode    text not null,
  permalink    text not null,
  caption      text,
  posted_at    timestamptz,
  rank         smallint not null,
  source       text not null default 'manual' check (source in ('manual', 'graph')),
  added_by     integer references public.profiles(id),
  synced_at    timestamptz not null default now(),
  unique (subject_type, subject_id, shortcode),
  foreign key (subject_type, subject_id)
    references public.instagram_consent (subject_type, subject_id) on delete cascade
);

create index if not exists instagram_consent_media_rank_idx
  on public.instagram_consent_media (subject_type, subject_id, rank);

comment on table public.instagram_consent_media is
  'Recent posts for a consenting subject, lowest rank first. A shortcode, never an image: the page embeds the post and Meta serves the photograph to the visitor.';

-- A subject that does not exist cannot consent. There is no foreign key to be had across two
-- parent tables, so this is the substitute, and it runs on the way in rather than being a
-- comment nobody reads.
create or replace function public.instagram_consent_subject_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.subject_type = 'brand'
     and not exists (select 1 from profiles where id = new.subject_id) then
    raise exception 'no profile % to consent for', new.subject_id;
  elsif new.subject_type = 'location'
     and not exists (select 1 from locations where id = new.subject_id) then
    raise exception 'no location % to consent for', new.subject_id;
  end if;

  if tg_op = 'UPDATE'
     and new.consent_status = 'revoked' and coalesce(old.consent_status, '') <> 'revoked' then
    -- Withdrawing permission deletes the posts it covered, rather than hiding them.
    delete from instagram_consent_media
     where subject_type = new.subject_type and subject_id = new.subject_id;
  end if;

  new.updated_at := now();
  return new;
end $$;

drop trigger if exists instagram_consent_subject_guard on public.instagram_consent;
create trigger instagram_consent_subject_guard
  before insert or update on public.instagram_consent
  for each row execute function public.instagram_consent_subject_guard();

-- ─── Carry over what 20261029000001 already recorded ─────────────────────────

insert into public.instagram_consent
  (subject_type, subject_id, username, consent_status, consent_source, consent_note,
   consent_by, consent_at, revoked_at, revoked_by, source, ig_user_id, access_token,
   token_expires_at, status, last_sync_at, last_sync_error, created_at)
select 'location', s.location_id, s.username, s.consent_status, s.consent_source, s.consent_note,
       s.consent_by, s.consent_at, s.revoked_at, s.revoked_by, s.source, s.ig_user_id,
       s.access_token, s.token_expires_at, s.status, s.last_sync_at, s.last_sync_error, s.created_at
  from public.store_instagram s
on conflict (subject_type, subject_id) do nothing;

insert into public.instagram_consent_media
  (subject_type, subject_id, shortcode, permalink, caption, posted_at, rank, source, added_by, synced_at)
select 'location', m.location_id, m.shortcode, m.permalink, m.caption, m.posted_at,
       m.rank, m.source, m.added_by, m.synced_at
  from public.store_instagram_media m
on conflict (subject_type, subject_id, shortcode) do nothing;

-- ─── Views ───────────────────────────────────────────────────────────────────

drop view if exists public.v_store_instagram_posts;
drop view if exists public.v_store_instagram;

create or replace view public.v_instagram_posts as
  select m.subject_type, m.subject_id, m.shortcode, m.permalink, m.caption, m.posted_at, m.rank
    from public.instagram_consent_media m
    join public.instagram_consent c
      on c.subject_type = m.subject_type and c.subject_id = m.subject_id
   where c.consent_status = 'granted';

comment on view public.v_instagram_posts is
  'The posts a brand or store page may show. Joined against live consent, so revoking hides them in the same statement that deletes them.';

-- The deployed frontend asks for this by name and will keep asking until it is redeployed.
-- It costs one view to not break the running app.
create or replace view public.v_store_instagram_posts as
  select subject_id as location_id, shortcode, permalink, caption, posted_at, rank
    from public.v_instagram_posts
   where subject_type = 'location';

comment on view public.v_store_instagram_posts is
  'Compatibility shim for the frontend deployed before 20261029000002. New code reads v_instagram_posts.';

create or replace view public.v_instagram_consent as
  select c.subject_type, c.subject_id, c.username, c.consent_status, c.consent_source,
         c.consent_note, c.consent_at, c.revoked_at, c.source, c.status, c.last_sync_at
    from public.instagram_consent c
   where public.can_manage_instagram_subject(c.subject_type, c.subject_id);

create or replace view public.v_store_instagram as
  select subject_id as location_id, username, consent_status, consent_source, consent_note,
         consent_at, revoked_at, source, status, last_sync_at
    from public.v_instagram_consent
   where subject_type = 'location';

-- ─── Doing something about it ────────────────────────────────────────────────

create or replace function public.instagram_consent_grant(
  p_subject_type text,
  p_subject_id   integer,
  p_username     text,
  p_source       text default 'email',
  p_note         text default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_actor integer; v_handle text;
begin
  if not can_manage_instagram_subject(p_subject_type, p_subject_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this page.');
  end if;
  if p_source not in ('oauth','claim','email','phone','in_person','other') then
    return jsonb_build_object('ok', false, 'error', 'Unrecognised consent source.');
  end if;

  v_handle := norm_instagram_handle(p_username);
  if v_handle is null then
    return jsonb_build_object('ok', false, 'error', 'That is not an Instagram handle.');
  end if;

  select id into v_actor from profiles where auth_id = auth.uid() limit 1;

  insert into instagram_consent as c
    (subject_type, subject_id, username, consent_status, consent_source, consent_note,
     consent_by, consent_at, revoked_at, revoked_by, source)
  values
    (p_subject_type, p_subject_id, v_handle, 'granted', p_source,
     nullif(trim(coalesce(p_note, '')), ''), v_actor, now(), null, null,
     case when p_source = 'oauth' then 'graph' else 'manual' end)
  on conflict (subject_type, subject_id) do update
    set username = excluded.username, consent_status = 'granted',
        consent_source = excluded.consent_source,
        consent_note = coalesce(excluded.consent_note, c.consent_note),
        consent_by = excluded.consent_by, consent_at = now(),
        revoked_at = null, revoked_by = null;

  return jsonb_build_object('ok', true, 'username', v_handle);
end $$;

create or replace function public.instagram_consent_revoke(
  p_subject_type text, p_subject_id integer
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_actor integer;
begin
  if not can_manage_instagram_subject(p_subject_type, p_subject_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this page.');
  end if;
  select id into v_actor from profiles where auth_id = auth.uid() limit 1;
  update instagram_consent
     set consent_status = 'revoked', revoked_at = now(), revoked_by = v_actor,
         status = 'revoked', access_token = null
   where subject_type = p_subject_type and subject_id = p_subject_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.instagram_consent_set_posts(
  p_subject_type text, p_subject_id integer, p_urls text[]
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_actor integer; v_limit integer := store_instagram_post_limit();
  v_rejected text[] := '{}'; v_kept integer := 0;
  v_url text; v_code text; v_rank smallint := 0;
begin
  if not can_manage_instagram_subject(p_subject_type, p_subject_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this page.');
  end if;
  if not exists (select 1 from instagram_consent
                  where subject_type = p_subject_type and subject_id = p_subject_id
                    and consent_status = 'granted') then
    return jsonb_build_object('ok', false, 'error', 'This page has no Instagram consent on record.');
  end if;

  select id into v_actor from profiles where auth_id = auth.uid() limit 1;
  create temporary table _wanted (shortcode text primary key, permalink text, rank smallint)
    on commit drop;

  foreach v_url in array coalesce(p_urls, '{}')
  loop
    v_code := norm_instagram_shortcode(v_url);
    if v_code is null then v_rejected := v_rejected || v_url; continue; end if;
    if exists (select 1 from _wanted w where w.shortcode = v_code) then continue; end if;
    exit when v_rank >= v_limit;
    v_rank := v_rank + 1;
    insert into _wanted values (v_code, 'https://www.instagram.com/p/' || v_code || '/', v_rank);
    v_kept := v_kept + 1;
  end loop;

  delete from instagram_consent_media m
   where m.subject_type = p_subject_type and m.subject_id = p_subject_id
     and not exists (select 1 from _wanted w where w.shortcode = m.shortcode);

  insert into instagram_consent_media
    (subject_type, subject_id, shortcode, permalink, rank, source, added_by)
  select p_subject_type, p_subject_id, w.shortcode, w.permalink, w.rank, 'manual', v_actor
    from _wanted w
  on conflict (subject_type, subject_id, shortcode) do update
    set rank = excluded.rank, synced_at = now();

  update instagram_consent set last_sync_at = now(), last_sync_error = null
   where subject_type = p_subject_type and subject_id = p_subject_id;

  return jsonb_build_object('ok', true, 'kept', v_kept,
                            'rejected', to_jsonb(v_rejected), 'limit', v_limit);
end $$;

-- The store-shaped names the deployed frontend still calls. Thin, so there is one
-- implementation and not two that drift.
create or replace function public.store_instagram_grant_consent(
  p_location_id integer, p_username text, p_source text default 'email', p_note text default null
) returns jsonb language sql security definer set search_path = public as $$
  select public.instagram_consent_grant('location', p_location_id, p_username, p_source, p_note);
$$;

create or replace function public.store_instagram_revoke(p_location_id integer)
returns jsonb language sql security definer set search_path = public as $$
  select public.instagram_consent_revoke('location', p_location_id);
$$;

create or replace function public.store_instagram_set_posts(p_location_id integer, p_urls text[])
returns jsonb language sql security definer set search_path = public as $$
  select public.instagram_consent_set_posts('location', p_location_id, p_urls);
$$;

-- ─── Retire the location-only tables ─────────────────────────────────────────

drop trigger if exists store_instagram_consent_guard on public.store_instagram;
drop function if exists public.store_instagram_consent_guard();
drop table if exists public.store_instagram_media;
drop table if exists public.store_instagram;

-- ─── Access ──────────────────────────────────────────────────────────────────

alter table public.instagram_consent       enable row level security;
alter table public.instagram_consent_media enable row level security;
revoke all on table public.instagram_consent       from anon, authenticated;
revoke all on table public.instagram_consent_media from anon, authenticated;

grant select on public.v_instagram_posts       to anon, authenticated;
grant select on public.v_store_instagram_posts to anon, authenticated;
grant select on public.v_instagram_consent     to authenticated;
grant select on public.v_store_instagram       to authenticated;

grant execute on function public.can_manage_instagram_subject(text, integer)             to authenticated;
grant execute on function public.instagram_consent_grant(text, integer, text, text, text) to authenticated;
grant execute on function public.instagram_consent_revoke(text, integer)                 to authenticated;
grant execute on function public.instagram_consent_set_posts(text, integer, text[])      to authenticated;
grant execute on function public.store_instagram_grant_consent(integer, text, text, text) to authenticated;
grant execute on function public.store_instagram_revoke(integer)                         to authenticated;
grant execute on function public.store_instagram_set_posts(integer, text[])              to authenticated;
