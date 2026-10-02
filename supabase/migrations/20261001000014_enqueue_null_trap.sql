-- Queue the sites that did not respond at all, which the first version silently skipped.
--
-- The predicate was:
--
--     (d.http_status is null or d.http_status >= 400) and d.http_status <> 999
--
-- and a site that never answered has http_status null, so the second clause is null rather
-- than true, the AND is null, and the row is not selected. The branch written specifically to
-- catch those 215 sites excluded every one of them: 22 queued instead of 221, and nothing
-- said so. The 999 exclusion belongs inside the same parenthesis as the comparison it guards.
create or replace function public.website_check_enqueue(p_only_suspect boolean default true)
returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  insert into website_check (subject_type, subject_id, website)
  select 'brand', p.id, p.website
    from profiles p
   where p.profile_type = 'brand' and nullif(trim(p.website), '') is not null
     and (not p_only_suspect
          or p.website ~* '(bit\.ly|tinyurl|app\.link|lnk\.to|rebrand\.ly|ow\.ly)'
          or exists (select 1 from social_discovery d
                      where d.subject_type = 'brand' and d.subject_id = p.id
                        -- 999 is "robots.txt said no", which is not a broken site.
                        and (d.http_status is null or (d.http_status >= 400 and d.http_status <> 999))))
  on conflict (subject_type, subject_id) do nothing;

  insert into website_check (subject_type, subject_id, website)
  select 'location', l.id, l.website
    from locations l
   where nullif(trim(l.website), '') is not null
     and (not p_only_suspect
          or l.website ~* '(bit\.ly|tinyurl|app\.link|lnk\.to|rebrand\.ly|ow\.ly)'
          or exists (select 1 from social_discovery d
                      where d.subject_type = 'location' and d.subject_id = l.id
                        and (d.http_status is null or (d.http_status >= 400 and d.http_status <> 999))))
  on conflict (subject_type, subject_id) do nothing;

  select count(*) into n from website_check where status = 'pending';
  return n;
end $$;
