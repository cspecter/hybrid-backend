-- A scraped post is a Hybrid post.
--
-- The feed was going to get these as synthetic cards: a foreign object spliced in at every
-- Nth slot behind an __instagram flag, with its own badge and its own special cases, the way
-- sponsored posts work. Sponsored has to do that, because a campaign boosts a post that
-- already exists and the label is a legal obligation. Neither is true here.
--
-- Once a consenting brand's photograph is in our bucket and its caption is in our database,
-- there is nothing foreign left to special-case. So it becomes a row in posts, authored by
-- that brand, and every part of the app that already knows what a post is -- the feed, the
-- detail view, likes, comments, search, a brand's own post list -- works without being told
-- about Instagram at all. The alternative was carrying a parallel notion of "post" through
-- all of them.
--
-- WHAT THIS MEANS WHEN CONSENT IS WITHDRAWN. The post goes, and so does anything Hybrid
-- users attached to it -- their likes, their comments. That is the correct answer and it is
-- also a real loss, so it is written here rather than discovered later: a brand that takes
-- its photographs back takes the conversation about them too.

-- ─── Where a subject's posts come from ───────────────────────────────────────

create or replace function public.instagram_author_profile(
  p_subject_type text, p_subject_id integer
) returns integer
language sql stable
set search_path = public
as $$
  select case p_subject_type
           when 'brand'    then p_subject_id
           -- A location is not a profile and cannot author anything. Its brand can.
           when 'location' then (select brand_id from public.locations where id = p_subject_id)
         end;
$$;

comment on function public.instagram_author_profile(text, integer) is
  'The profile that authors a subject''s Instagram posts. A brand authors its own; a store''s go to the brand that runs it, since a location has no profile to post as.';

-- The public URL of a copy in our bucket, assembled the way the client assembles it. Derived
-- from the one origin already in Vault rather than hardcoding a project reference.
create or replace function public.instagram_public_image_url(p_path text)
returns text
language plpgsql stable
set search_path = public
as $$
declare base text;
begin
  if p_path is null then return null; end if;
  select decrypted_secret into base from vault.decrypted_secrets where name = 'functions_base_url';
  if base is null then return null; end if;
  return regexp_replace(rtrim(base, '/'), '/functions/v1$', '')
         || '/storage/v1/object/public/instagram-posts/' || p_path;
end $$;

-- ─── The link between a scraped post and the post it became ──────────────────

alter table public.instagram_consent_media
  add column if not exists post_id integer references public.posts(id) on delete set null;

comment on column public.instagram_consent_media.post_id is
  'The posts row this became. Null while the picture has not been fetched yet -- a post we cannot show an image for is not worth putting in the feed.';

-- ─── Becoming a post ─────────────────────────────────────────────────────────

-- Runs BEFORE the row lands so it can fill in its own post_id without a second write and
-- without a trigger that fires itself.
create or replace function public.instagram_media_publish()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_author integer;
  v_url    text;
  v_post   integer;
begin
  -- Only a post we hold the picture for. A pasted link has nothing to show in a feed.
  if new.image_path is null then return new; end if;

  v_author := instagram_author_profile(new.subject_type, new.subject_id);
  if v_author is null then return new; end if;

  v_url := instagram_public_image_url(new.image_path);
  if v_url is null then return new; end if;

  -- Already published: keep the text and the date in step and leave the rest alone.
  if new.post_id is not null then
    update posts
       set message    = coalesce(new.caption, message),
           created_at = coalesce(new.posted_at, created_at),
           updated_at = now()
     where id = new.post_id;
    return new;
  end if;

  -- The picture goes on posts.url rather than through cloud_files, for two reasons. The
  -- picture is not in Cloudinary, which is what that table describes; and deleting a
  -- cloud_files row fires fn_delete_remote_file_on_delete, which calls http_delete -- a
  -- function that does not exist in this database. No cloud_files row can be deleted here
  -- at all today, so a row created now would be one we could never take back, for a
  -- feature whose whole promise is that withdrawing consent removes things.
  --
  -- created_at is when the brand posted it, not when we fetched it, so it sorts among real
  -- posts by when it actually happened.
  insert into posts (profile_id, message, url, has_file, status, live_time, created_at)
  values (v_author, new.caption, v_url, false, 'published',
          coalesce(new.posted_at, now()), coalesce(new.posted_at, now()))
  returning id into v_post;

  new.post_id := v_post;
  return new;
end $$;

drop trigger if exists instagram_media_publish on public.instagram_consent_media;
create trigger instagram_media_publish
  before insert or update on public.instagram_consent_media
  for each row execute function public.instagram_media_publish();

-- ─── Ceasing to be one ───────────────────────────────────────────────────────

-- The existing trigger queued the image file for deletion. It now also takes down the post
-- the row became, because a withdrawn photograph cannot keep appearing in the feed.
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
  -- Deleting the post takes its likes and comments with it. See the header: that is the
  -- point, not an oversight.
  if old.post_id is not null then delete from posts where id = old.post_id; end if;
  return old;
end $$;

-- ─── Publishing what is already stored ───────────────────────────────────────

-- The trigger covers everything written from now on. This is for the rows that were already
-- there when it was added.
create or replace function public.instagram_publish_existing()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  with pending as (
    select m.id from instagram_consent_media m
      join instagram_consent c
        on c.subject_type = m.subject_type and c.subject_id = m.subject_id
     where m.image_path is not null and m.post_id is null
       and c.consent_status = 'granted'
  )
  -- A no-op update is enough: the BEFORE trigger does the work.
  update instagram_consent_media m set synced_at = m.synced_at
    from pending p where p.id = m.id;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'published', n);
end $$;

revoke all on function public.instagram_publish_existing() from anon, authenticated;
