-- One Instagram post, one Hybrid post, however many times it syncs.
--
-- The sync upserts media rows, which is INSERT ... ON CONFLICT DO UPDATE. A BEFORE INSERT
-- trigger runs before the conflict is detected, so instagram_media_publish took its insert
-- branch every single time, created a brand new post, and set new.post_id to it. The
-- conflict then resolved as an update, post_id was overwritten with the new value, and the
-- post from the previous run was left behind with nothing pointing at it.
--
-- Six runs produced six posts for every photograph. Housing Works had 11 media rows and 33
-- posts; Cheech & Chong 6 and 36. Seventy posts across four brands existed that no media
-- row could ever clean up, because withdrawal only deletes the post currently linked.
--
-- The fix is to look for the row this insert is about to collide with. At BEFORE INSERT
-- time during an upsert it is still there, so its post_id can be reused.

create or replace function public.instagram_media_publish()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_author integer; v_url text; v_post integer; v_existing integer;
begin
  if new.image_path is null and new.video_path is null then return new; end if;

  v_author := instagram_author_profile(new.subject_type, new.subject_id);
  if v_author is null then return new; end if;

  v_url := instagram_public_image_url(coalesce(new.video_path, new.image_path));
  if v_url is null then return new; end if;

  -- The post this media already has, whether we arrived by UPDATE or by an INSERT that is
  -- about to become one.
  if tg_op = 'UPDATE' then
    v_existing := old.post_id;
  else
    select post_id into v_existing
      from instagram_consent_media
     where subject_type = new.subject_type
       and subject_id   = new.subject_id
       and shortcode    = new.shortcode;
  end if;

  if v_existing is not null then
    update posts
       set message   = new.caption,
           url       = v_url,
           live_time = coalesce(new.posted_at, live_time)
     where id = v_existing;
    new.post_id := v_existing;
    return new;
  end if;

  insert into posts (profile_id, message, url, has_file, status, live_time, created_at)
  values (v_author, new.caption, v_url, false, 'published',
          coalesce(new.posted_at, now()), coalesce(new.posted_at, now()))
  returning id into v_post;
  new.post_id := v_post;
  return new;
end $$;

comment on function public.instagram_media_publish() is
  'Publishes a scraped post as a Hybrid post, reusing the one this media already has. Looks the existing row up on INSERT as well as UPDATE, because the sync upserts and a BEFORE INSERT trigger fires before the conflict is known.';

-- Clear the duplicates already made. These are posts carrying a stored-media URL, authored
-- by a brand that has consented, with no media row pointing at them — abandoned by exactly
-- the bug above and reachable no other way.
delete from public.posts p
 where p.url like '%/storage/v1/object/public/instagram-posts/%'
   and not exists (select 1 from public.instagram_consent_media m where m.post_id = p.id);
