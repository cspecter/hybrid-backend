-- Hold our own copy of a consenting account's photographs, because embedding them is not
-- available to us.
--
-- 20261029000002 proved the embed route dead for this industry: Instagram age-restricts
-- cannabis accounts, and a logged-out visitor in New York gets "You must be 21 years old or
-- over to see this profile" instead of a post. The embed is fetched by the visitor's browser,
-- so their session and their IP decide it and we cannot influence either.
--
-- A fetch we make ourselves is a different matter. We choose the address and the session, so
-- the content is reachable -- and that is the whole reason this path exists where the other
-- one failed. The cost is that we are now holding copies of someone else's photographs
-- rather than pointing at them, and everything below is shaped by that:
--
--   Nothing is fetched for a subject that has not consented. The scraper reads the same
--   instagram_consent table the embed route reads, and a row that is not 'granted' is not
--   visited at all.
--
--   WITHDRAWING CONSENT DELETES THE FILES, not just the rows. Hiding a copy is not the same
--   as not having one, and a store that changes its mind is entitled to the second. The
--   rows go immediately; the bytes are queued and removed by the next drain, which revoke
--   triggers rather than waits for.
--
-- The credentials this needs are somebody's Instagram session. That account is bound by
-- Meta's terms and can be suspended, so it should be a dedicated one and never a principal's.
-- Nothing here stores or logs a credential: the Edge Function reads them from Vault by name.

-- ─── Where the copies live ───────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('instagram-posts', 'instagram-posts', true, 10485760,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Public read, matching product-images. These are photographs a shop asked us to show; the
-- restriction that matters is upstream, in whether a consent row exists at all.
drop policy if exists "instagram posts are publicly readable" on storage.objects;
create policy "instagram posts are publicly readable" on storage.objects
  for select using (bucket_id = 'instagram-posts');

-- ─── What a post is, when we hold the picture ────────────────────────────────

alter table public.instagram_consent_media
  add column if not exists image_path   text,
  add column if not exists image_width  integer,
  add column if not exists image_height integer,
  add column if not exists is_video     boolean not null default false;

comment on column public.instagram_consent_media.image_path is
  'Path in the instagram-posts bucket, for a post we fetched and copied. Null for a post that is only ever embedded, where Meta serves the image and we hold nothing.';
comment on column public.instagram_consent_media.image_width is
  'Natural size of the copy, so a page can reserve the right space before it loads rather than reflowing around it.';

-- A third way for posts to arrive, alongside a person pasting links and the Graph API.
alter table public.instagram_consent drop constraint if exists instagram_consent_source_check;
alter table public.instagram_consent add constraint instagram_consent_source_check
  check (source in ('manual', 'graph', 'scrape'));

alter table public.instagram_consent_media drop constraint if exists instagram_consent_media_source_check;
alter table public.instagram_consent_media add constraint instagram_consent_media_source_check
  check (source in ('manual', 'graph', 'scrape'));

-- ─── Deleting the bytes, not just the rows ───────────────────────────────────

create table if not exists public.instagram_media_purge (
  id         bigserial primary key,
  bucket     text not null,
  path       text not null,
  queued_at  timestamptz not null default now(),
  purged_at  timestamptz,
  last_error text
);

create index if not exists instagram_media_purge_pending_idx
  on public.instagram_media_purge (queued_at) where purged_at is null;

comment on table public.instagram_media_purge is
  'Copies that are to be deleted from storage. Postgres cannot reach the storage API, so a withdrawal records what must go and the next drain removes it. Rows are already unreachable by then; this is about the files.';

-- Every route out of instagram_consent_media ends here: a revoked consent, a post the shop
-- deleted, a re-scrape that replaced the set. If there was a copy, it is queued for removal.
create or replace function public.instagram_media_queue_purge()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.image_path is not null then
    insert into instagram_media_purge (bucket, path)
    values ('instagram-posts', old.image_path);
  end if;
  return old;
end $$;

drop trigger if exists instagram_media_queue_purge on public.instagram_consent_media;
create trigger instagram_media_queue_purge
  after delete on public.instagram_consent_media
  for each row execute function public.instagram_media_queue_purge();

-- ─── The posts a page may show ───────────────────────────────────────────────

create or replace view public.v_instagram_posts as
  select m.subject_type, m.subject_id, m.shortcode, m.permalink, m.caption, m.posted_at,
         m.rank, m.image_path, m.image_width, m.image_height, m.is_video
    from public.instagram_consent_media m
    join public.instagram_consent c
      on c.subject_type = m.subject_type and c.subject_id = m.subject_id
   where c.consent_status = 'granted';

-- ─── Asking for a scrape ─────────────────────────────────────────────────────

create or replace function public.instagram_scrape_dispatch()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare base text; token text; n integer;
begin
  select count(*) into n
    from instagram_consent
   where source = 'scrape' and consent_status = 'granted' and status = 'active';
  -- Still worth a run when nothing is connected but copies are owed a deletion.
  if n = 0 and not exists (select 1 from instagram_media_purge where purged_at is null) then
    return;
  end if;

  select decrypted_secret into base  from vault.decrypted_secrets where name = 'functions_base_url';
  select decrypted_secret into token from vault.decrypted_secrets where name = 'giveaway_invoke_token';
  if base is null or token is null then
    raise notice 'instagram_scrape_dispatch: vault secrets not set — no scrape';
    return;
  end if;

  perform net.http_post(
    url     := rtrim(base, '/') || '/instagram-scrape',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'Authorization', 'Bearer ' || token),
    body    := '{}'::jsonb,
    timeout_milliseconds := 300000
  );
end $$;

comment on function public.instagram_scrape_dispatch() is
  'Ask instagram-scrape to refresh consenting accounts and drain the purge queue. Runs for the queue alone when nothing is connected, so a withdrawal is not left waiting on unrelated work.';

revoke all on function public.instagram_scrape_dispatch() from anon, authenticated;

-- Daily rather than six-hourly. A copy we hold does not expire the way a CDN link does, so
-- the only reason to return is new posts -- and every visit is a request to somebody else's
-- service made on a shop's behalf, which is a reason to go less often, not more.
select cron.unschedule('instagram-scrape') where exists (select 1 from cron.job where jobname = 'instagram-scrape');
select cron.schedule('instagram-scrape', '41 5 * * *', $$select public.instagram_scrape_dispatch()$$);

-- ─── Withdrawal takes effect now, not tonight ────────────────────────────────

create or replace function public.instagram_consent_revoke(
  p_subject_type text, p_subject_id integer
) returns jsonb
language plpgsql security definer set search_path = public, extensions
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

  -- The trigger has deleted the rows and queued the files. Waiting until the next nightly
  -- run to delete somebody's photographs after they asked us to stop is not good enough.
  perform instagram_scrape_dispatch();

  return jsonb_build_object('ok', true);
end $$;

-- ─── Choosing where a subject's posts come from ──────────────────────────────

create or replace function public.instagram_consent_set_source(
  p_subject_type text, p_subject_id integer, p_source text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if not can_manage_instagram_subject(p_subject_type, p_subject_id) then
    return jsonb_build_object('ok', false, 'error', 'You do not manage this page.');
  end if;
  if p_source not in ('manual', 'graph', 'scrape') then
    return jsonb_build_object('ok', false, 'error', 'Unrecognised source.');
  end if;
  if not exists (select 1 from instagram_consent
                  where subject_type = p_subject_type and subject_id = p_subject_id
                    and consent_status = 'granted') then
    return jsonb_build_object('ok', false, 'error', 'This page has no Instagram consent on record.');
  end if;

  update instagram_consent set source = p_source, last_sync_error = null
   where subject_type = p_subject_type and subject_id = p_subject_id;

  if p_source = 'scrape' then perform instagram_scrape_dispatch(); end if;
  return jsonb_build_object('ok', true, 'source', p_source);
end $$;

comment on function public.instagram_consent_set_source(text, integer, text) is
  'Switch where a consenting subject''s posts come from. Turning on scrape fetches immediately rather than waiting for the nightly run.';

grant execute on function public.instagram_consent_set_source(text, integer, text) to authenticated;

-- The manager view should say which route a page is on, since they behave differently.
create or replace view public.v_instagram_consent as
  select c.subject_type, c.subject_id, c.username, c.consent_status, c.consent_source,
         c.consent_note, c.consent_at, c.revoked_at, c.source, c.status, c.last_sync_at,
         c.last_sync_error,
         (select count(*) from public.instagram_consent_media m
           where m.subject_type = c.subject_type and m.subject_id = c.subject_id) as post_count
    from public.instagram_consent c
   where public.can_manage_instagram_subject(c.subject_type, c.subject_id);

create or replace view public.v_store_instagram as
  select subject_id as location_id, username, consent_status, consent_source, consent_note,
         consent_at, revoked_at, source, status, last_sync_at
    from public.v_instagram_consent
   where subject_type = 'location';

alter table public.instagram_media_purge enable row level security;
revoke all on table public.instagram_media_purge from anon, authenticated;

grant select on public.v_instagram_posts   to anon, authenticated;
grant select on public.v_instagram_consent to authenticated;
grant select on public.v_store_instagram   to authenticated;
