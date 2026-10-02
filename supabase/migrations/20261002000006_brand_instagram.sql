-- A brand connects its own Instagram, and its posts appear on its page.
--
-- This is the version of the Instagram feature that is defensible. The brand authorises it,
-- so there is explicit permission to show its photographs -- which the scraping route never
-- has, and which matters most for the 231 brand pages nobody has claimed. It is also the
-- better onboarding ask: "connect your Instagram and your posts show up here" gives a brand
-- a reason to claim a page, where "please claim this page" gives it none.
--
-- BLOCKED ON META, NOT ON THIS CODE. Nobody outside a developer test list can authorise
-- anything until the app passes App Review, which needs a Facebook app, a privacy policy, a
-- screencast and business verification. Everything here is inert until instagram_app_id and
-- instagram_app_secret exist in Vault, and refuses clearly rather than half-working.

-- Who may act for a brand. Same rule the profiles update policy already uses: the account
-- itself, or an admin delegated through profile_admins.
create or replace function public.can_admin_profile(p_profile_id integer) returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles p
     where p.id = p_profile_id
       and (p.auth_id = auth.uid()
         or auth.uid() in (select a.auth_id from profile_admins pa
                             join profiles a on a.id = pa.admin_profile_id
                            where pa.managed_profile_id = p.id))
  ) or public.is_super_admin();
$$;

comment on function public.can_admin_profile(integer) is
  'True when the signed-in user is this profile or an admin delegated to it, or a super admin. Mirrors the profiles update policy.';

-- The connection, including the token. Nothing reads this table from the client: RLS denies
-- every role and the Edge Functions reach it with the service key. A long-lived Instagram
-- token is a credential for somebody else's account and has no business leaving the server.
create table if not exists public.brand_instagram (
  profile_id       integer primary key references public.profiles(id) on delete cascade,
  ig_user_id       text not null,
  username         text,
  account_type     text,
  access_token     text not null,
  token_expires_at timestamptz,
  connected_by     integer references public.profiles(id),
  connected_at     timestamptz not null default now(),
  last_sync_at     timestamptz,
  last_sync_error  text,
  status           text not null default 'active'
                     check (status in ('active', 'needs_reauth', 'revoked'))
);

comment on table public.brand_instagram is
  'A brand''s authorised Instagram connection and its access token. RLS denies every client role; only Edge Functions read it. v_brand_instagram is what the app may see.';

-- What the app is allowed to know: that a brand is connected, and as whom.
create or replace view public.v_brand_instagram as
  select profile_id, username, status, last_sync_at, connected_at
  from brand_instagram;

comment on view public.v_brand_instagram is
  'The connection without the token: enough to show "connected as @handle" and nothing more.';

create table if not exists public.brand_instagram_media (
  id            bigserial primary key,
  profile_id    integer not null references public.profiles(id) on delete cascade,
  ig_media_id   text not null,
  media_type    text,
  permalink     text,
  caption       text,
  -- Instagram's CDN links expire within hours, so this is refreshed on every sync and is
  -- not something to cache a page against. The permalink does not expire.
  media_url     text,
  thumbnail_url text,
  posted_at     timestamptz,
  rank          smallint,
  synced_at     timestamptz not null default now(),
  unique (profile_id, ig_media_id)
);

create index if not exists brand_instagram_media_rank_idx
  on public.brand_instagram_media (profile_id, rank);

comment on table public.brand_instagram_media is
  'Recent posts for a connected brand, newest first by rank. media_url expires within hours and is refreshed by each sync; permalink is stable.';

-- Single-use CSRF state for the authorise round trip.
create table if not exists public.instagram_oauth_state (
  state       text primary key,
  profile_id  integer not null references public.profiles(id) on delete cascade,
  created_by  integer references public.profiles(id),
  created_at  timestamptz not null default now(),
  used_at     timestamptz
);

comment on table public.instagram_oauth_state is
  'One row per authorise attempt. Single use and short lived, so a callback cannot be replayed or pointed at a brand the user does not administer.';

-- Begin the authorise flow. Returns where to send the browser, or why not.
create or replace function public.instagram_connect_begin(p_profile_id integer)
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
  if not can_admin_profile(p_profile_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this brand.');
  end if;

  select decrypted_secret into v_app_id   from vault.decrypted_secrets where name = 'instagram_app_id';
  select decrypted_secret into v_redirect from vault.decrypted_secrets where name = 'instagram_redirect_uri';

  if v_app_id is null or v_redirect is null then
    -- Names only, never a value.
    return jsonb_build_object('ok', false, 'pending_setup', true,
      'error', 'Instagram connection is not configured yet.');
  end if;

  v_state := encode(extensions.gen_random_bytes(24), 'hex');
  insert into instagram_oauth_state (state, profile_id, created_by)
  select v_state, p_profile_id, p.id from profiles p where p.auth_id = auth.uid() limit 1;

  -- instagram_business_basic is read-only: the account's own profile and media. Nothing
  -- here can post, message, or read anyone else's account.
  return jsonb_build_object('ok', true, 'state', v_state,
    'authorize_url',
      'https://www.instagram.com/oauth/authorize'
      || '?client_id=' || url_encode(v_app_id)
      || '&redirect_uri=' || url_encode(v_redirect)
      || '&response_type=code'
      || '&scope=' || url_encode('instagram_business_basic')
      || '&state=' || v_state);
end $$;

comment on function public.instagram_connect_begin(integer) is
  'Where to send a brand admin to authorise Instagram, with a single-use state. Returns pending_setup when the Vault credentials do not exist yet.';

create or replace function public.instagram_disconnect(p_profile_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not can_admin_profile(p_profile_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this brand.');
  end if;
  -- The posts go with the permission. A brand that disconnects has withdrawn consent to
  -- show them, and keeping the cache would be ignoring that.
  delete from brand_instagram_media where profile_id = p_profile_id;
  delete from brand_instagram       where profile_id = p_profile_id;
  return jsonb_build_object('ok', true);
end $$;

comment on function public.instagram_disconnect(integer) is
  'Forget a brand''s Instagram connection and the posts cached under it. Disconnecting withdraws the permission the posts were shown under, so they go too.';

alter table public.brand_instagram        enable row level security;
alter table public.brand_instagram_media  enable row level security;
alter table public.instagram_oauth_state  enable row level security;

-- The token table and the state table are server-only. No policy means no client access.
revoke all on table public.brand_instagram       from anon, authenticated;
revoke all on table public.instagram_oauth_state from anon, authenticated;

-- Posts are public: they are what the brand connected Instagram in order to show.
grant select on table public.brand_instagram_media to anon, authenticated;
create policy brand_instagram_media_public_read on public.brand_instagram_media
  for select using (true);

grant select on public.v_brand_instagram to anon, authenticated;
grant execute on function public.instagram_connect_begin(integer) to authenticated;
grant execute on function public.instagram_disconnect(integer)    to authenticated;
grant execute on function public.can_admin_profile(integer)       to authenticated;
