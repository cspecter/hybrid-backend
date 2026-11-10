-- Hold six posts per subject, not six per fetch.
--
-- store_instagram_post_limit() is 6 and instagram-scrape asks for 6, so the limit
-- looked enforced. It was not. The scraper prunes a post that has gone missing
-- only inside the window the provider looked at -- deliberately, and for a good
-- reason given in its own comment: pruning on absence alone would have made the
-- fetch limit silently authoritative and deleted older posts the provider was
-- never asked about.
--
-- The consequence was not noticed. Each sync adds up to six new most-recent posts
-- and the window prune removes almost nothing, so the count climbs with every
-- run, without limit. Measured 2026-11-10: Housing Works 13, Jaunty 11, Cheech &
-- Chong 11, all from scraping, spanning 2026-09-08 to 2026-11-09. Jaunty held 6
-- that morning and 11 by the afternoon.
--
-- That matters beyond tidiness. Every one of these subjects consented to six
-- posts -- it is written in instagram_consent.consent_note -- and three of them
-- were over it, by growing amounts, with copies of the photographs held in a
-- public bucket. The number in the consent record has to be the number held.
--
-- Enforced here rather than in the Edge Function so it binds whatever writes the
-- table: the scraper, a manual insert, or a later provider. Statement-level with a
-- transition table, so it runs once per upsert rather than mid-way through one and
-- cannot delete a row the same statement is about to update.
--
-- Deleting is safe and complete, which was checked before writing this:
--   * instagram_media_unpublish (20261030000003) already deletes the published
--     Hybrid post on the way out, so no post is orphaned.
--   * instagram_media_queue_purge (20261030000001) already queues the stored
--     image and video for removal, so no bytes are left behind.
--   * The 17 rows this first removes carry one like between them, and no
--     comments or views.
--
-- Two deliberate choices worth knowing. Rows with no posted_at sort last and are
-- therefore dropped first, because an undated row cannot be shown to be among the
-- six most recent. And a 'manual' row is treated no differently from a scraped
-- one: none exists today, and if hand-picked posts ever need to outrank fetched
-- ones that is a different rule, not a tweak to this one.
create or replace function public.instagram_media_enforce_limit()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  delete from instagram_consent_media m
   using (
     select im.id,
            row_number() over (partition by im.subject_type, im.subject_id
                               order by im.posted_at desc nulls last, im.id desc) as rn
       from instagram_consent_media im
      where (im.subject_type, im.subject_id) in (
              select distinct c.subject_type, c.subject_id from changed c)
   ) ranked
   where m.id = ranked.id
     and ranked.rn > store_instagram_post_limit();
  return null;
end $$;

comment on function public.instagram_media_enforce_limit() is
  'Keeps only the store_instagram_post_limit() most recent posts per subject. The fetch limit bounded one request; this bounds what is held, which is what the consent record promises.';

-- Two triggers, one per event, because Postgres rejects a transition table on a
-- trigger with more than one event: "transition tables cannot be specified for
-- triggers with more than one event" (0A000). `after insert or update` with
-- `referencing new table` parses but will not create. Both name the transition
-- table `changed`, so one function body serves both.
drop trigger if exists instagram_media_enforce_limit        on public.instagram_consent_media;
drop trigger if exists instagram_media_enforce_limit_insert on public.instagram_consent_media;
drop trigger if exists instagram_media_enforce_limit_update on public.instagram_consent_media;

create trigger instagram_media_enforce_limit_insert
  after insert on public.instagram_consent_media
  referencing new table as changed
  for each statement
  execute function public.instagram_media_enforce_limit();

create trigger instagram_media_enforce_limit_update
  after update on public.instagram_consent_media
  referencing new table as changed
  for each statement
  execute function public.instagram_media_enforce_limit();

-- The rows already over the limit. A no-op update is enough to fire the trigger
-- above, and going through it means the backfill and the steady state cannot
-- disagree about which six are kept.
update public.instagram_consent_media m
   set synced_at = m.synced_at
 where (m.subject_type, m.subject_id) in (
         select subject_type, subject_id
           from public.instagram_consent_media
          group by subject_type, subject_id
         having count(*) > public.store_instagram_post_limit());
