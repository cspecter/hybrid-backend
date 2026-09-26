-- Bring the product images onto our own storage instead of hotlinking 29 CDNs.
--
-- The feed carries 730,927 image references across 420,169 distinct URLs, served by
-- 29 hosts belonging to dispensaries and POS vendors. Hotlinking works until any one
-- of them reorganises, and every view spends someone else's bandwidth.
--
-- MEASURED, NOT GUESSED. One HEAD per host: median image 191 KB, mean 930 KB, largest
-- 15 MB. Stored as-is that is roughly 77 GB at the median and far more at the mean.
-- These render at about 400px in a phone app, so originals are not worth keeping —
-- the worker resizes to a 400px WebP on the way in, which lands the whole set nearer
-- 15-20 GB. The original URL is kept on every row so a bigger rendition can always be
-- fetched again.
--
-- WORTH SAYING ONCE, since this is the step that makes copies: hotlinking references
-- someone's file, whereas this reproduces 420,169 photographs owned by brands and
-- dispensaries. That question is not settled by this table; it is only made concrete
-- by it. `source_licence_note` exists so a decision, when there is one, has somewhere
-- to live per image.

create table if not exists public.product_images (
  id             bigserial primary key,
  source_url     text not null unique,
  source_host    text generated always as (split_part(split_part(source_url, '//', 2), '/', 1)) stored,
  content_hash   text,
  storage_path   text,
  bytes_original integer,
  bytes_stored   integer,
  width          integer,
  height         integer,
  mime           text,
  status         text not null default 'pending',
  attempts       integer not null default 0,
  last_error     text,
  claimed_at     timestamptz,
  fetched_at     timestamptz,
  source_licence_note text,
  created_at     timestamptz not null default now()
);

-- Partial index on the work queue: the table is 420k rows and all but the pending
-- ones are irrelevant to the worker, so the index it actually uses stays small.
create index if not exists product_images_queue_idx
  on public.product_images (source_host, id) where status = 'pending';
create index if not exists product_images_status_idx on public.product_images (status);
create index if not exists product_images_hash_idx   on public.product_images (content_hash)
  where content_hash is not null;

comment on table public.product_images is
  'One row per distinct source image URL. status: pending -> claimed -> stored | failed | skipped.';
comment on column public.product_images.content_hash is
  'sha256 of the fetched bytes. The same photograph is served under many URLs across CDNs, so this is what makes deduplication possible.';

-- ─── Fill the queue from whatever the feed has seen ──────────────────────────
create or replace function public.product_images_enqueue()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  insert into public.product_images (source_url)
  select distinct r.image_url
    from public.menu_items_raw r
   where r.image_url is not null
     and r.image_url ~* '^https?://'
     and not exists (select 1 from public.product_images p where p.source_url = r.image_url)
  on conflict (source_url) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ─── Handing work out ────────────────────────────────────────────────────────
-- Claims a batch for one host at a time. Per-host is the important part: two of the
-- 29 CDNs carry 59% of the images (143,381 on one S3 bucket alone), and a worker that
-- ignored the split would hammer a single origin at full speed, which is
-- indistinguishable from an attack and gets the whole run blocked.
--
-- FOR UPDATE SKIP LOCKED so several workers can run without handing the same image to
-- two of them.
create or replace function public.product_images_claim(
  p_host  text,
  p_limit integer default 50)
returns table(id bigint, source_url text)
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  return query
  with picked as (
    select p.id from public.product_images p
     where p.status = 'pending'
       and p.source_host = p_host
       and p.attempts < 4
     order by p.id
     limit p_limit
     for update skip locked
  )
  update public.product_images u
     set status = 'claimed', claimed_at = now(), attempts = u.attempts + 1
    from picked
   where u.id = picked.id
   returning u.id, u.source_url;
end;
$$;

create or replace function public.product_images_record(
  p_id bigint, p_ok boolean, p_storage_path text default null,
  p_hash text default null, p_bytes_original integer default null,
  p_bytes_stored integer default null, p_width integer default null,
  p_height integer default null, p_mime text default null, p_error text default null)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.product_images
     set status = case when p_ok then 'stored'
                       when attempts >= 4 then 'failed'
                       else 'pending' end,   -- back to the queue until attempts run out
         storage_path = coalesce(p_storage_path, storage_path),
         content_hash = coalesce(p_hash, content_hash),
         bytes_original = coalesce(p_bytes_original, bytes_original),
         bytes_stored = coalesce(p_bytes_stored, bytes_stored),
         width = coalesce(p_width, width), height = coalesce(p_height, height),
         mime = coalesce(p_mime, mime),
         last_error = case when p_ok then null else left(p_error, 400) end,
         fetched_at = case when p_ok then now() else fetched_at end,
         claimed_at = null
   where id = p_id;
$$;

-- Anything claimed and abandoned — a worker killed mid-batch — comes back after an
-- hour rather than sitting claimed forever.
create or replace function public.product_images_release_stale()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  update public.product_images
     set status = 'pending', claimed_at = null
   where status = 'claimed' and claimed_at < now() - interval '1 hour';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.product_images_enqueue()        from public, anon, authenticated;
revoke all on function public.product_images_claim(text, integer) from public, anon, authenticated;
revoke all on function public.product_images_record(bigint, boolean, text, text, integer, integer, integer, integer, text, text)
  from public, anon, authenticated;
revoke all on function public.product_images_release_stale()  from public, anon, authenticated;
revoke all on table public.product_images from anon, authenticated;
alter table public.product_images enable row level security;

-- ─── Progress, and what is left per host ─────────────────────────────────────
create or replace view public.v_product_image_progress as
select source_host,
       count(*)                                        as total,
       count(*) filter (where status='stored')         as stored,
       count(*) filter (where status='pending')        as pending,
       count(*) filter (where status='claimed')        as in_flight,
       count(*) filter (where status='failed')         as failed,
       sum(bytes_stored) filter (where status='stored') as bytes_stored,
       sum(bytes_original) filter (where status='stored') as bytes_original
from public.product_images group by source_host order by count(*) desc;

revoke all on table public.v_product_image_progress from anon, authenticated;
