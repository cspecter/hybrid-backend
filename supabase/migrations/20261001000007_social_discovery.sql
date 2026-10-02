-- Find brands' and stores' Instagram handles on their own websites.
--
-- There are four Instagram handles in the whole database, one of them on a brand, and all
-- 311 locations carrying a social_links blob have an "instagram" key set to the empty string.
-- So the blocker is not fetching posts, it is not knowing whose account to fetch: no scraper
-- tells you that "Lobo" is @loboextracts, and guessing it wrong puts a stranger's
-- photographs on a brand's page.
--
-- A brand's own site almost always links its Instagram, and reading a site that invites the
-- public to read it raises none of the questions scraping Instagram would. The handle alone
-- is also useful before any post ever appears: it is a way to reach a brand, and a way for
-- one to prove an account is theirs when claiming a page.

create table if not exists public.social_discovery (
  id           bigserial primary key,
  subject_type text not null check (subject_type in ('brand', 'location')),
  subject_id   integer not null,
  website      text not null,
  status       text not null default 'pending'
                 check (status in ('pending', 'claimed', 'done', 'failed', 'skipped')),
  instagram    text,
  socials      jsonb,        -- anything else found, so a second pass need not refetch
  http_status  integer,
  note         text,
  attempts     integer not null default 0,
  claimed_at   timestamptz,
  fetched_at   timestamptz,
  unique (subject_type, subject_id)
);

create index if not exists social_discovery_pending_idx
  on public.social_discovery (status, id) where status = 'pending';

comment on table public.social_discovery is
  'One row per brand or store website to read for social handles. A queue so the crawl is resumable and a second run does not refetch what it already has.';

-- Turn whatever is on a page into a handle, or nothing.
--
-- instagram.com/p/<id> is a post, /reel/<id> a video, /explore a directory: none of them is
-- an account, and storing one as a brand's handle would be worse than storing nothing. The
-- reserved list is what keeps a link to a specific post from becoming "the brand is @p".
create or replace function public.norm_instagram_handle(p_raw text) returns text
language plpgsql immutable as $$
declare
  s text := lower(trim(coalesce(p_raw, '')));
  h text;
begin
  if s = '' then return null; end if;

  -- A full URL, or a bare @handle, or a bare handle.
  if s ~ 'instagram\.com' then
    h := (regexp_match(s, 'instagram\.com/+([^/?#\s"'']+)'))[1];
  else
    h := ltrim(s, '@');
  end if;
  if h is null then return null; end if;

  h := rtrim(split_part(split_part(h, '?', 1), '#', 1), '/');

  -- Instagram's own paths, not accounts.
  if h in ('p','reel','reels','tv','explore','accounts','about','developer','legal',
           'directory','stories','s','web','graphql','api','oauth','challenge','emails',
           'sessions','invites','direct','archive','your_activity','help','press','privacy',
           'terms','security','igtv','ar','guides','lite','locations','topics') then
    return null;
  end if;

  -- Instagram allows letters, digits, periods and underscores, up to 30 characters.
  if h !~ '^[a-z0-9._]{1,30}$' then return null; end if;
  -- A handle that is only punctuation is not a handle.
  if h !~ '[a-z0-9]' then return null; end if;

  return h;
end $$;

comment on function public.norm_instagram_handle(text) is
  'Reduce a URL or @mention to an Instagram handle, or null. Rejects Instagram''s own paths (/p/, /reel/, /explore) so a link to one post does not become a brand''s handle.';

create or replace function public.social_discovery_enqueue()
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  insert into social_discovery (subject_type, subject_id, website)
  select 'brand', p.id, norm_url(p.website)
    from profiles p
   where p.profile_type = 'brand'
     and norm_url(p.website) is not null
     -- Nothing to look for if we already know the handle.
     and norm_instagram_handle(p.social_links->>'instagram') is null
  on conflict (subject_type, subject_id) do nothing;

  insert into social_discovery (subject_type, subject_id, website)
  select 'location', l.id, norm_url(l.website)
    from locations l
   where norm_url(l.website) is not null
     and norm_instagram_handle(l.social_links->>'instagram') is null
  on conflict (subject_type, subject_id) do nothing;

  select count(*) into n from social_discovery where status = 'pending';
  return n;
end $$;

create or replace function public.social_discovery_claim(p_limit integer default 25)
returns table (id bigint, subject_type text, subject_id integer, website text)
language plpgsql set search_path = public as $$
begin
  return query
  with picked as (
    select d.id from social_discovery d
     where d.status = 'pending' and d.attempts < 3
     order by d.id
     limit p_limit
     for update skip locked
  )
  update social_discovery d
     set status = 'claimed', claimed_at = now(), attempts = d.attempts + 1
    from picked
   where d.id = picked.id
  returning d.id, d.subject_type, d.subject_id, d.website;
end $$;

create or replace function public.social_discovery_record(
  p_id bigint, p_instagram text, p_socials jsonb, p_http_status integer, p_note text
) returns void
language plpgsql set search_path = public as $$
declare h text := norm_instagram_handle(p_instagram);
begin
  update social_discovery
     set instagram   = h,
         socials     = p_socials,
         http_status = p_http_status,
         note        = p_note,
         -- "done" means the site was read, whether or not it mentioned Instagram. Only a
         -- fetch that failed goes back to pending for another attempt.
         status      = case when p_http_status between 200 and 299 then 'done'
                           when attempts >= 3 then 'failed'
                           else 'pending' end,
         fetched_at  = now()
   where id = p_id;
end $$;

create or replace function public.social_discovery_release_stale(p_minutes integer default 30)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  update social_discovery set status = 'pending', claimed_at = null
   where status = 'claimed' and claimed_at < now() - make_interval(mins => p_minutes);
  get diagnostics n = row_count;
  return n;
end $$;

-- Found handles, for reading before anything is written to a profile.
create or replace view public.v_social_discovery_found as
  select d.subject_type, d.subject_id, d.instagram, d.website,
         case d.subject_type when 'brand' then (select p.username from profiles p where p.id = d.subject_id)
                             else (select l.name from locations l where l.id = d.subject_id) end as subject,
         d.socials, d.fetched_at
  from social_discovery d
  where d.instagram is not null
  order by d.subject_type, d.instagram;

comment on view public.v_social_discovery_found is
  'Handles found, with whose site they came from, so they can be read before being applied.';

revoke all on table public.social_discovery from anon, authenticated;
alter table public.social_discovery enable row level security;
revoke all on function public.social_discovery_enqueue()              from anon, authenticated;
revoke all on function public.social_discovery_claim(integer)         from anon, authenticated;
revoke all on function public.social_discovery_record(bigint, text, jsonb, integer, text) from anon, authenticated;
revoke all on function public.social_discovery_release_stale(integer) from anon, authenticated;
