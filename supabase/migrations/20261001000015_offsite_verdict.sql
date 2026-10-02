-- A redirect that leaves the domain is not a correction.
--
-- The first check pass called these "moved" and would have written them in:
--
--   jukeboxhitz.com   -> wordpress.com/typo/?subdomain=...   a domain-typo parking page
--   gagecannabis.com  -> terrascend.com                      the parent company
--   honorableplant.com-> njdispo.com                         a different business entirely
--
-- Each is genuinely where the URL leads, and none is the site that belongs in that row. It is
-- the same shape as the handle problem: a jump to another entity needs a person, not a rule.
-- So a redirect within the same registrable domain -- a path fixed, a scheme fixed, www added
-- or dropped -- is applied, and one that lands on a different domain is held as "offsite".
alter table public.website_check drop constraint if exists website_check_verdict_check;

-- The last two labels of a hostname, which is close enough to a registrable domain for
-- telling "the same site" from "somebody else's site". It is wrong for co.uk and similar,
-- and every host in this data is a .com, .co, .shop or .store.
create or replace function public.registrable_domain(p_url text) returns text
language sql immutable as $$
  select nullif(
    (regexp_match(
       regexp_replace(regexp_replace(lower(coalesce(p_url, '')), '^https?://', ''), '[/?#].*$', ''),
       '([a-z0-9-]+\.[a-z]{2,})$'))[1], '');
$$;

comment on function public.registrable_domain(text) is
  'The last two labels of a URL''s host, for telling a redirect that stays on the same site from one that lands on somebody else''s.';

-- Hosts that exist to hold a domain rather than serve a business.
create or replace function public.is_parking_host(p_url text) returns boolean
language sql immutable as $$
  select registrable_domain(p_url) in (
    'wordpress.com','godaddysites.com','sedoparking.com','afternic.com','hugedomains.com',
    'dan.com','bodis.com','parkingcrew.net','sedo.com','squadhelp.com','namecheap.com',
    'domain.com','networksolutions.com','wix.com','weebly.com','blogspot.com'
  );
$$;

comment on function public.is_parking_host(text) is
  'True for a host that parks or sells domains, or a builder''s default subdomain, rather than serving the business itself.';

-- Reclassify what has already been checked, and keep offsite out of what gets applied.
update public.website_check
   set verdict = 'offsite',
       detail  = coalesce(detail, '') || ' [lands on ' || coalesce(registrable_domain(resolved_url), '?') || ']'
 where verdict = 'moved'
   and resolved_url is not null
   and (is_parking_host(resolved_url)
     or registrable_domain(resolved_url) is distinct from registrable_domain(website));

create or replace function public.website_check_apply() returns jsonb
language plpgsql set search_path = public as $$
declare n_moved_b integer := 0; n_moved_l integer := 0;
        n_dead_b integer := 0;  n_dead_l integer := 0;
begin
  -- moved: it works, at the same site. A path fixed, a scheme added, www settled.
  update profiles p set website = c.resolved_url, website_source = 'verified'
    from website_check c
   where c.subject_type = 'brand' and c.subject_id = p.id
     and c.verdict = 'moved' and c.resolved_url is not null and c.resolved_url <> p.website
     and not is_parking_host(c.resolved_url)
     and registrable_domain(c.resolved_url) is not distinct from registrable_domain(c.website);
  get diagnostics n_moved_b = row_count;

  update locations l set website = c.resolved_url, website_source = 'verified'
    from website_check c
   where c.subject_type = 'location' and c.subject_id = l.id
     and c.verdict = 'moved' and c.resolved_url is not null and c.resolved_url <> l.website
     and not is_parking_host(c.resolved_url)
     and registrable_domain(c.resolved_url) is not distinct from registrable_domain(c.website);
  get diagnostics n_moved_l = row_count;

  -- dead: the domain does not resolve, refuses every connection, or serves 404 at its own
  -- root. Cleared, because a Shop Now button that goes nowhere is worse than none, and
  -- website_check keeps the original so this is reversible.
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
    'brands_cleared', n_dead_b, 'locations_cleared', n_dead_l,
    'held_offsite', (select count(*) from website_check where verdict = 'offsite'),
    'held_unknown', (select count(*) from website_check where verdict = 'unknown'),
    'locations_with_a_website', (select count(*) from locations where nullif(trim(website),'') is not null),
    'brands_with_a_website', (select count(*) from profiles
                               where profile_type='brand' and nullif(trim(website),'') is not null));
end $$;

create or replace view public.v_website_check_review as
  select c.verdict, c.subject_type,
         case c.subject_type when 'brand' then (select coalesce(nullif(trim(p.display_name),''), p.username)
                                                  from profiles p where p.id = c.subject_id)
                             else (select l.name from locations l where l.id = c.subject_id) end as subject,
         c.website, c.resolved_url, c.detail
  from website_check c
  where c.verdict in ('offsite', 'unknown')
  order by c.verdict, c.subject_type;

comment on view public.v_website_check_review is
  'Checks that were not applied: offsite means the URL leads to another domain (a parent company, a different business, a parking page); unknown means blocked, slow or erroring, and keeps its website.';

revoke all on function public.registrable_domain(text) from anon, authenticated;
revoke all on function public.is_parking_host(text)    from anon, authenticated;
