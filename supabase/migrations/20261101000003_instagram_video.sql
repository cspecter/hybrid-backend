-- Store the reel, not just its cover frame.
--
-- The provider returns videoUrl alongside displayUrl — measured against @cheechandchong,
-- whose six most recent posts all come back as type "Video" with the MP4 populated. Until
-- now the pipeline kept the cover and threw the video away, so a reel appeared as a still.
--
-- The cover is still stored, and deliberately at the same base path with a .jpg extension,
-- because the client derives a video's poster by swapping the extension:
--   thumbUrl = rawUrl.replace(/\.(mp4|mov|webm)$/, ".jpg")
-- So brand/5680/ABC.mp4 and brand/5680/ABC.jpg are one post's two files, and the feed
-- resolves both with no frontend change at all.

update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'video/mp4'],
       -- Reels run 3–30MB against a photo's 300KB. 50MB leaves headroom for a long one
       -- without inviting something that has no business in a feed.
       file_size_limit = 52428800
 where id = 'instagram-posts';

alter table public.instagram_consent_media
  add column if not exists video_path text;

comment on column public.instagram_consent_media.video_path is
  'Path of the stored MP4 for a reel, beside the cover frame in image_path. Null for a photo.';

-- A post with a video points at the video. The client already detects .mp4 and renders a
-- player, and finds the poster by swapping the extension, so nothing downstream changes.
create or replace function public.instagram_media_publish()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_author integer; v_url text; v_post integer;
begin
  if new.image_path is null and new.video_path is null then return new; end if;

  v_author := instagram_author_profile(new.subject_type, new.subject_id);
  if v_author is null then return new; end if;

  v_url := instagram_public_image_url(coalesce(new.video_path, new.image_path));
  if v_url is null then return new; end if;

  if tg_op = 'UPDATE' and old.post_id is not null then
    update posts
       set message = new.caption, url = v_url,
           live_time = coalesce(new.posted_at, live_time)
     where id = old.post_id;
    new.post_id := old.post_id;
    return new;
  end if;

  insert into posts (profile_id, message, url, has_file, status, live_time, created_at)
  values (v_author, new.caption, v_url, false, 'published',
          coalesce(new.posted_at, now()), coalesce(new.posted_at, now()))
  returning id into v_post;
  new.post_id := v_post;
  return new;
end $$;

-- Withdrawing consent has to take both files, or the video outlives the permission for it.
create or replace function public.instagram_media_queue_purge()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.image_path is not null then
    insert into instagram_media_purge (bucket, path) values ('instagram-posts', old.image_path);
  end if;
  if old.video_path is not null then
    insert into instagram_media_purge (bucket, path) values ('instagram-posts', old.video_path);
  end if;
  if old.post_id is not null then
    delete from posts where id = old.post_id;
  end if;
  return old;
end $$;

comment on function public.instagram_media_queue_purge() is
  'On removal, queue every stored file for deletion — cover and video both — and delete the Hybrid post it became. Withdrawal removes the copies, not just the rows pointing at them.';
