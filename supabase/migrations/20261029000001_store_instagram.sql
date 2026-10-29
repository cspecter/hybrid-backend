-- A store's Instagram posts on its store page, shown only where the store said yes.
--
-- The brand version of this (20261002000006) connects through Instagram's own OAuth and
-- caches the photographs. Stores could not wait for that: Advanced Access needs App Review,
-- and 994 of 995 stores have not claimed their page, so nobody is there to click Connect.
--
-- So this takes the other route, and two measurements decided its shape:
--
--   Instagram's public endpoints are closed to servers. A logged-out fetch of
--   /api/v1/users/web_profile_info returns 401 require_login, and the profile and embed HTML
--   both come back as an empty script shell. Scraping posts server-side does not work today
--   from an ordinary address -- not "breaks eventually", does not work now.
--
--   Instagram's embed does work, in the visitor's browser, from any origin. An iframe at
--   /p/<shortcode>/embed/ renders the photograph, the handle and the caption, served by
--   Meta, and posts its own height back to the parent.
--
-- That is why this table stores a shortcode and nothing else. No media_url, no thumbnail, no
-- copy of anyone's photograph on our side -- Meta serves the image to the visitor directly.
-- It is the cheapest thing to hold, the only thing that does not expire, and it means a
-- store withdrawing consent leaves us holding nothing but a dead string.
--
-- Consent is a row, not a memory. Who said yes, when, by what means, and a note saying where
-- the yes is written down. A store can take it back, and when it does the posts go with it,
-- the same rule the brand version follows.

-- ─── Shortcodes ──────────────────────────────────────────────────────────────

-- Reduce a post or reel URL to the shortcode the embed needs, or null.
--
-- The sibling of norm_instagram_handle, and the opposite job: that one rejects /p/ because a
-- link to a single post is not an account, this one wants exactly that. Anything that is not
-- a post or a reel returns null rather than a guess, because a wrong shortcode puts a
-- stranger's photograph on a store's page -- the same thing the handle crawl is careful about.
create or replace function public.norm_instagram_shortcode(p_raw text) returns text
language plpgsql immutable as $$
declare
  s text := trim(coalesce(p_raw, ''));
  c text;
begin
  if s = '' then return null; end if;

  if s ~* 'instagram\.com' then
    -- /p/<code>, /reel/<code>, /tv/<code>, and the /<handle>/p/<code> form the web app uses.
    c := (regexp_match(s, 'instagram\.com/(?:[^/?#\s]+/)?(?:p|reel|reels|tv)/([^/?#\s]+)', 'i'))[1];
  elsif s ~ '^[A-Za-z0-9_-]+$' then
    c := s;                                   -- already a bare shortcode
  else
    return null;
  end if;

  if c is null then return null; end if;
  -- Instagram shortcodes are base64url. Eleven characters today, but that has changed before,
  -- so the bound is loose enough to survive it and tight enough to reject a path fragment.
  if c !~ '^[A-Za-z0-9_-]{5,40}$' then return null; end if;
  return c;
end $$;

comment on function public.norm_instagram_shortcode(text) is
  'Reduce an Instagram post or reel URL to its shortcode, or null. The inverse of norm_instagram_handle: that one rejects /p/ links, this one wants only those.';

-- ─── The connection and the consent behind it ────────────────────────────────

create table if not exists public.store_instagram (
  location_id      integer primary key references public.locations(id) on delete cascade,
  username         text,

  -- Who said yes, and how we know. consent_note is where the yes actually lives -- the person
  -- who replied, the date of the email -- so that "they approved it" is a record rather than
  -- somebody's recollection a year from now.
  consent_status   text not null default 'granted'
                     check (consent_status in ('granted', 'revoked')),
  consent_source   text not null
                     check (consent_source in ('oauth', 'claim', 'email', 'phone', 'in_person', 'other')),
  consent_note     text,
  consent_by       integer references public.profiles(id),
  consent_at       timestamptz not null default now(),
  revoked_at       timestamptz,
  revoked_by       integer references public.profiles(id),

  -- Where the posts come from. 'manual' is a person pasting links; 'graph' is the store
  -- having authorised Instagram itself, which only becomes possible once App Review passes.
  -- The token columns are null for every manual connection and that is the normal case.
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

  -- A revoked consent must say when, and a live one must not.
  constraint store_instagram_revoked_ck check (
    (consent_status = 'revoked') = (revoked_at is not null)
  )
);

comment on table public.store_instagram is
  'One row per store that has agreed to show its Instagram here, with the record of who agreed and how. A row exists only where consent was given; revoking keeps the row as an audit trail and deletes the posts.';
comment on column public.store_instagram.consent_note is
  'Where the yes is written down -- who replied and when. Operational, not public: this table is readable only through v_store_instagram, which shows a row to its own managers.';
comment on column public.store_instagram.access_token is
  'Null for every manual connection. Only the graph path fills it, and only Edge Functions ever read it.';

-- ─── The posts ───────────────────────────────────────────────────────────────

create table if not exists public.store_instagram_media (
  id          bigserial primary key,
  location_id integer not null references public.store_instagram(location_id) on delete cascade,

  -- The shortcode is the whole payload. Everything the page renders -- the photograph, the
  -- handle, the caption, the like count -- comes from Meta's own embed at request time, so
  -- there is no image URL here to expire and no copy of a photograph to delete.
  shortcode   text not null,
  permalink   text not null,
  caption     text,
  posted_at   timestamptz,
  rank        smallint not null,
  source      text not null default 'manual' check (source in ('manual', 'graph')),
  added_by    integer references public.profiles(id),
  synced_at   timestamptz not null default now(),
  unique (location_id, shortcode)
);

create index if not exists store_instagram_media_rank_idx
  on public.store_instagram_media (location_id, rank);

comment on table public.store_instagram_media is
  'Recent posts for a consenting store, lowest rank first. Holds a shortcode, never an image: the page embeds the post and Meta serves the photograph to the visitor.';

-- The FK to store_instagram already means a post cannot exist without a consent row. This
-- adds the other half: revoking consent takes the posts with it rather than leaving them
-- hidden behind a view, so withdrawing permission actually deletes something.
create or replace function public.store_instagram_consent_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.consent_status = 'revoked' and coalesce(old.consent_status, '') <> 'revoked' then
    delete from store_instagram_media where location_id = new.location_id;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists store_instagram_consent_guard on public.store_instagram;
create trigger store_instagram_consent_guard
  before update on public.store_instagram
  for each row execute function public.store_instagram_consent_guard();

-- ─── What each audience may see ──────────────────────────────────────────────

-- Public. Posts for stores whose consent is current, and nothing about the consent itself.
-- The filter lives in the view rather than in the caller, so "no consent, no posts" is a
-- property of the schema and not of whoever remembers to add a where clause.
create or replace view public.v_store_instagram_posts as
  select m.location_id, m.shortcode, m.permalink, m.caption, m.posted_at, m.rank
    from public.store_instagram_media m
    join public.store_instagram s on s.location_id = m.location_id
   where s.consent_status = 'granted';

comment on view public.v_store_instagram_posts is
  'The posts a store page may show. Joined against live consent, so revoking hides them in the same statement that deletes them.';

-- The store's own managers. Enough to render "connected as @handle, you can turn this off",
-- including the consent record, and never the token.
create or replace view public.v_store_instagram as
  select s.location_id, s.username, s.consent_status, s.consent_source, s.consent_note,
         s.consent_at, s.revoked_at, s.source, s.status, s.last_sync_at
    from public.store_instagram s
   where public.can_manage_location(s.location_id);

comment on view public.v_store_instagram is
  'A store''s Instagram arrangement, visible to the people who run that store (and super admins). Tokenless by construction.';

-- ─── Doing something about it ────────────────────────────────────────────────

-- How many posts a store page shows. Six is the ask, and it is also about as much as a strip
-- of Instagram embeds can carry before the page is mostly somebody else's website.
create or replace function public.store_instagram_post_limit() returns integer
language sql immutable as $$ select 6 $$;

create or replace function public.store_instagram_grant_consent(
  p_location_id integer,
  p_username    text,
  p_source      text default 'email',
  p_note        text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor  integer;
  v_handle text;
begin
  if not can_manage_location(p_location_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this store.');
  end if;
  if p_source not in ('oauth', 'claim', 'email', 'phone', 'in_person', 'other') then
    return jsonb_build_object('ok', false, 'error', 'Unrecognised consent source.');
  end if;

  v_handle := norm_instagram_handle(p_username);
  if v_handle is null then
    return jsonb_build_object('ok', false, 'error', 'That is not an Instagram handle.');
  end if;

  select id into v_actor from profiles where auth_id = auth.uid() limit 1;

  insert into store_instagram as s
    (location_id, username, consent_status, consent_source, consent_note, consent_by, consent_at,
     revoked_at, revoked_by, source)
  values
    (p_location_id, v_handle, 'granted', p_source, nullif(trim(coalesce(p_note, '')), ''), v_actor, now(),
     null, null, case when p_source = 'oauth' then 'graph' else 'manual' end)
  on conflict (location_id) do update
    set username       = excluded.username,
        consent_status = 'granted',
        consent_source = excluded.consent_source,
        consent_note   = coalesce(excluded.consent_note, s.consent_note),
        consent_by     = excluded.consent_by,
        consent_at     = now(),
        revoked_at     = null,
        revoked_by     = null;

  return jsonb_build_object('ok', true, 'username', v_handle);
end $$;

comment on function public.store_instagram_grant_consent(integer, text, text, text) is
  'Record that a store agreed to show its Instagram here, and as which handle. Re-granting after a revoke clears the revocation rather than creating a second record.';

create or replace function public.store_instagram_revoke(p_location_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_actor integer;
begin
  if not can_manage_location(p_location_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this store.');
  end if;
  select id into v_actor from profiles where auth_id = auth.uid() limit 1;

  -- The trigger deletes the posts. The row stays so there is a record that consent existed
  -- and was withdrawn, which is the part worth keeping.
  update store_instagram
     set consent_status = 'revoked',
         revoked_at     = now(),
         revoked_by     = v_actor,
         status         = 'revoked',
         access_token   = null
   where location_id = p_location_id;

  return jsonb_build_object('ok', true);
end $$;

comment on function public.store_instagram_revoke(integer) is
  'Withdraw a store''s consent. The posts are deleted and the token dropped; the consent record stays so the history is legible.';

-- Set the posts from pasted links. This is the path that works today: Instagram's public
-- endpoints refuse servers, so somebody with the store's permission supplies the URLs.
create or replace function public.store_instagram_set_posts(
  p_location_id integer,
  p_urls        text[]
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor    integer;
  v_limit    integer := store_instagram_post_limit();
  v_rejected text[] := '{}';
  v_kept     integer := 0;
  v_url      text;
  v_code     text;
  v_rank     smallint := 0;
begin
  if not can_manage_location(p_location_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this store.');
  end if;
  if not exists (select 1 from store_instagram
                  where location_id = p_location_id and consent_status = 'granted') then
    return jsonb_build_object('ok', false,
      'error', 'This store has not agreed to show its Instagram yet.');
  end if;

  select id into v_actor from profiles where auth_id = auth.uid() limit 1;

  create temporary table _wanted (shortcode text primary key, permalink text, rank smallint)
    on commit drop;

  foreach v_url in array coalesce(p_urls, '{}')
  loop
    v_code := norm_instagram_shortcode(v_url);
    if v_code is null then
      v_rejected := v_rejected || v_url;
      continue;
    end if;
    -- A link pasted twice is one post, and it keeps the position it was first given.
    if exists (select 1 from _wanted w where w.shortcode = v_code) then continue; end if;
    exit when v_rank >= v_limit;
    v_rank := v_rank + 1;
    insert into _wanted values (v_code, 'https://www.instagram.com/p/' || v_code || '/', v_rank);
    v_kept := v_kept + 1;
  end loop;

  -- Posts the store dropped from the list stop showing.
  delete from store_instagram_media m
   where m.location_id = p_location_id
     and not exists (select 1 from _wanted w where w.shortcode = m.shortcode);

  insert into store_instagram_media (location_id, shortcode, permalink, rank, source, added_by)
  select p_location_id, w.shortcode, w.permalink, w.rank, 'manual', v_actor from _wanted w
  on conflict (location_id, shortcode) do update
    set rank = excluded.rank, synced_at = now();

  update store_instagram set last_sync_at = now(), last_sync_error = null
   where location_id = p_location_id;

  return jsonb_build_object('ok', true, 'kept', v_kept,
                            'rejected', to_jsonb(v_rejected), 'limit', v_limit);
end $$;

comment on function public.store_instagram_set_posts(integer, text[]) is
  'Replace a store''s shown posts with these links, in this order. Anything that is not a post or reel URL is reported back rather than stored as a guess.';

-- The durable path, for when Meta approves the app. Mirrors instagram_connect_begin, except
-- the state carries a location instead of a brand.
create or replace function public.store_instagram_connect_begin(p_location_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_app_id   text;
  v_redirect text;
  v_state    text;
begin
  if not can_manage_location(p_location_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this store.');
  end if;

  select decrypted_secret into v_app_id   from vault.decrypted_secrets where name = 'instagram_app_id';
  select decrypted_secret into v_redirect from vault.decrypted_secrets where name = 'instagram_redirect_uri';

  if v_app_id is null or v_redirect is null then
    return jsonb_build_object('ok', false, 'pending_setup', true,
      'error', 'Instagram connection is not configured yet.');
  end if;

  v_state := encode(extensions.gen_random_bytes(24), 'hex');
  insert into instagram_oauth_state (state, location_id, created_by)
  select v_state, p_location_id, p.id from profiles p where p.auth_id = auth.uid() limit 1;

  return jsonb_build_object('ok', true, 'state', v_state,
    'authorize_url',
      'https://www.instagram.com/oauth/authorize'
      || '?client_id=' || url_encode(v_app_id)
      || '&redirect_uri=' || url_encode(v_redirect)
      || '&response_type=code'
      || '&scope=' || url_encode('instagram_business_basic')
      || '&state=' || v_state);
end $$;

comment on function public.store_instagram_connect_begin(integer) is
  'Where to send a store manager to authorise Instagram. Inert until the Vault credentials exist, which waits on App Review.';

-- ─── The authorise state learns about stores ─────────────────────────────────

alter table public.instagram_oauth_state
  add column if not exists location_id integer references public.locations(id) on delete cascade;
alter table public.instagram_oauth_state
  alter column profile_id drop not null;

-- A state is for exactly one subject. Without this a callback could be ambiguous about what
-- it was authorising, which is the whole thing the state parameter exists to pin down.
alter table public.instagram_oauth_state
  drop constraint if exists instagram_oauth_state_subject_ck;
alter table public.instagram_oauth_state
  add constraint instagram_oauth_state_subject_ck
  check (num_nonnulls(profile_id, location_id) = 1);

comment on column public.instagram_oauth_state.location_id is
  'Set instead of profile_id when a store, rather than a brand, is authorising.';

-- ─── Access ──────────────────────────────────────────────────────────────────

alter table public.store_instagram       enable row level security;
alter table public.store_instagram_media enable row level security;

-- Both base tables are server-only. No policy means no client reaches them; the views above
-- are the whole client surface, and the token never appears in either.
revoke all on table public.store_instagram       from anon, authenticated;
revoke all on table public.store_instagram_media from anon, authenticated;

grant select on public.v_store_instagram_posts to anon, authenticated;
grant select on public.v_store_instagram       to authenticated;

grant execute on function public.norm_instagram_shortcode(text)                     to anon, authenticated;
grant execute on function public.store_instagram_post_limit()                       to anon, authenticated;
grant execute on function public.store_instagram_grant_consent(integer, text, text, text) to authenticated;
grant execute on function public.store_instagram_revoke(integer)                    to authenticated;
grant execute on function public.store_instagram_set_posts(integer, text[])         to authenticated;
grant execute on function public.store_instagram_connect_begin(integer)             to authenticated;
-- The store panel asks this before offering any of the above, so the client needs it too.
grant execute on function public.can_manage_location(integer)                       to authenticated;
