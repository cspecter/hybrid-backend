-- Decide which stored websites actually work, and fix or clear the ones that do not.
--
-- Reading 600 of them found 215 that did not respond at all, 6 gone, and a handful stored as
-- link shorteners. Those matter now that a Shop Now button uses this column: a button to a
-- dead host is worse than no button, and it is the store's reputation on the other end.
--
-- One failed fetch is not proof. A crawler sees the same silence for a domain that no longer
-- exists, a site whose certificate expired, a server that is merely slow, and bot protection
-- closing the connection. Only the first of those should cost a store its link, so the check
-- distinguishes them and says so, and anything uncertain keeps its website.

create table if not exists public.website_check (
  id           bigserial primary key,
  subject_type text not null check (subject_type in ('brand', 'location')),
  subject_id   integer not null,
  website      text not null,         -- as stored when the check was queued
  status       text not null default 'pending'
                 check (status in ('pending', 'claimed', 'checked', 'failed')),
  verdict      text,                  -- alive | moved | dead | unknown
  resolved_url text,                  -- where it actually works, when that differs
  http_status  integer,
  detail       text,
  attempts     integer not null default 0,
  claimed_at   timestamptz,
  checked_at   timestamptz,
  unique (subject_type, subject_id)
);

create index if not exists website_check_pending_idx
  on public.website_check (status, id) where status = 'pending';

comment on table public.website_check is
  'One row per stored website, with whether it answers and where it answers from. verdict alive keeps it, moved rewrites it, dead clears it, unknown leaves it alone.';

create or replace function public.website_check_enqueue(p_only_suspect boolean default true)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  -- By default only the ones the handle crawl could not reach, plus anything stored as a
  -- shortener. Pass false to re-verify every website.
  insert into website_check (subject_type, subject_id, website)
  select 'brand', p.id, p.website
    from profiles p
   where p.profile_type = 'brand' and nullif(trim(p.website), '') is not null
     and (not p_only_suspect
          or p.website ~* '(bit\.ly|tinyurl|app\.link|lnk\.to|rebrand\.ly|ow\.ly)'
          or exists (select 1 from social_discovery d
                      where d.subject_type = 'brand' and d.subject_id = p.id
                        and (d.http_status is null or d.http_status >= 400) and d.http_status <> 999))
  on conflict (subject_type, subject_id) do nothing;

  insert into website_check (subject_type, subject_id, website)
  select 'location', l.id, l.website
    from locations l
   where nullif(trim(l.website), '') is not null
     and (not p_only_suspect
          or l.website ~* '(bit\.ly|tinyurl|app\.link|lnk\.to|rebrand\.ly|ow\.ly)'
          or exists (select 1 from social_discovery d
                      where d.subject_type = 'location' and d.subject_id = l.id
                        and (d.http_status is null or d.http_status >= 400) and d.http_status <> 999))
  on conflict (subject_type, subject_id) do nothing;

  select count(*) into n from website_check where status = 'pending';
  return n;
end $$;

create or replace function public.website_check_claim(p_limit integer default 25)
returns table (id bigint, subject_type text, subject_id integer, website text)
language plpgsql set search_path = public as $$
begin
  return query
  with picked as (
    select c.id from website_check c
     where c.status = 'pending' and c.attempts < 2
     order by c.id limit p_limit
     for update skip locked
  )
  update website_check c
     set status = 'claimed', claimed_at = now(), attempts = c.attempts + 1
    from picked
   where c.id = picked.id
  returning c.id, c.subject_type::text, c.subject_id, c.website::text;
end $$;

create or replace function public.website_check_record(
  p_id bigint, p_verdict text, p_resolved_url text, p_http_status integer, p_detail text
) returns void
language plpgsql set search_path = public as $$
begin
  update website_check
     set verdict      = p_verdict,
         resolved_url = norm_url(p_resolved_url),
         http_status  = p_http_status,
         detail       = p_detail,
         status       = 'checked',
         checked_at   = now()
   where id = p_id;
end $$;

create or replace function public.website_check_release_stale(p_minutes integer default 30)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  update website_check set status = 'pending', claimed_at = null
   where status = 'claimed' and claimed_at < now() - make_interval(mins => p_minutes);
  get diagnostics n = row_count;
  return n;
end $$;

-- Apply the verdicts. Only two of the four change anything.
create or replace function public.website_check_apply() returns jsonb
language plpgsql set search_path = public as $$
declare n_moved_b integer := 0; n_moved_l integer := 0;
        n_dead_b integer := 0;  n_dead_l integer := 0;
begin
  -- moved: it works, somewhere slightly different. A path that 404s where the root answers,
  -- or http where https fails, or a shortener's destination.
  update profiles p set website = c.resolved_url, website_source = 'verified'
    from website_check c
   where c.subject_type = 'brand' and c.subject_id = p.id
     and c.verdict = 'moved' and c.resolved_url is not null
     and c.resolved_url <> p.website;
  get diagnostics n_moved_b = row_count;

  update locations l set website = c.resolved_url, website_source = 'verified'
    from website_check c
   where c.subject_type = 'location' and c.subject_id = l.id
     and c.verdict = 'moved' and c.resolved_url is not null
     and c.resolved_url <> l.website;
  get diagnostics n_moved_l = row_count;

  -- dead: the domain does not resolve, or nothing is served at it. Cleared, because a Shop
  -- Now button that goes nowhere is worse than an absent one, and the column is now load
  -- bearing. website_check keeps what it was, so this is reversible.
  update profiles p set website = null, website_source = null
    from website_check c
   where c.subject_type = 'brand' and c.subject_id = p.id and c.verdict = 'dead';
  get diagnostics n_dead_b = row_count;

  update locations l set website = null, website_source = null
    from website_check c
   where c.subject_type = 'location' and c.subject_id = l.id and c.verdict = 'dead';
  get diagnostics n_dead_l = row_count;

  return jsonb_build_object(
    'brands_rewritten', n_moved_b, 'locations_rewritten', n_moved_l,
    'brands_cleared',   n_dead_b,  'locations_cleared',   n_dead_l,
    'left_alone_unknown', (select count(*) from website_check where verdict = 'unknown'),
    'locations_with_a_website', (select count(*) from locations where nullif(trim(website),'') is not null),
    'brands_with_a_website', (select count(*) from profiles
                               where profile_type='brand' and nullif(trim(website),'') is not null));
end $$;

comment on function public.website_check_apply() is
  'Rewrite the websites that moved and clear the ones that are dead. Leaves unknown alone, and website_check keeps the original either way so it can be undone.';

create or replace view public.v_website_check_summary as
  select coalesce(verdict, '(unchecked)') as verdict, subject_type, count(*) as sites,
         count(*) filter (where resolved_url is not null and resolved_url <> website) as would_rewrite
  from website_check group by 1, 2 order by 1, 2;

revoke all on table public.website_check from anon, authenticated;
alter table public.website_check enable row level security;
revoke all on function public.website_check_enqueue(boolean)       from anon, authenticated;
revoke all on function public.website_check_claim(integer)         from anon, authenticated;
revoke all on function public.website_check_record(bigint, text, text, integer, text) from anon, authenticated;
revoke all on function public.website_check_release_stale(integer) from anon, authenticated;
revoke all on function public.website_check_apply()                from anon, authenticated;
