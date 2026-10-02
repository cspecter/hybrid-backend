-- An empty string is not a website.
--
-- 224 locations and 21 profiles held website = '', which is not null and not a URL. Every
-- count in this project already used nullif(trim(website),'') and so read them correctly, but
-- anything checking "website is not null" sees a value and finds nothing in it -- and the
-- normalisation pass walked straight past them, because norm_url('') is null so the rewrite
-- branch skipped them while the clear branch required a non-empty value to act on. A column
-- that means "absent" two different ways will be read wrongly eventually.
--
-- Same for social_links: {"instagram": ""} was the shape of all 311 location blobs before the
-- handle crawl, and an empty handle there is the same trap.
create or replace function public.blank_to_null_contacts() returns jsonb
language plpgsql set search_path = public as $$
declare n_loc_web integer := 0; n_prof_web integer := 0;
        n_loc_other integer := 0;
begin
  update locations set website = null, website_source = null
   where website is not null and trim(website) = '';
  get diagnostics n_loc_web = row_count;

  update profiles set website = null, website_source = null
   where website is not null and trim(website) = '';
  get diagnostics n_prof_web = row_count;

  -- phone and email carry the same emptiness on this table.
  update locations
     set phone = nullif(trim(phone), ''),
         email = nullif(trim(email), '')
   where (phone is not null and trim(phone) = '') or (email is not null and trim(email) = '');
  get diagnostics n_loc_other = row_count;

  return jsonb_build_object(
    'location_websites_nulled', n_loc_web,
    'profile_websites_nulled',  n_prof_web,
    'location_phone_email_nulled', n_loc_other,
    'locations_with_a_website', (select count(*) from locations where website is not null),
    'brands_with_a_website', (select count(*) from profiles
                               where profile_type='brand' and website is not null),
    'empty_strings_left', (select count(*) from (
        select website from locations union all select website from profiles) z
      where website is not null and trim(website) = ''));
end $$;

comment on function public.blank_to_null_contacts() is
  'Turn empty-string websites, phones and emails into nulls, so "absent" has one representation rather than two.';

-- An empty handle inside social_links is the same trap: the key exists and says nothing.
create or replace function public.prune_blank_social_links() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  with blanks as (
    select 'location' as kind, id, social_links from locations where social_links is not null
    union all
    select 'profile', id, social_links from profiles where social_links is not null
  ),
  cleaned as (
    select kind, id,
           coalesce((select jsonb_object_agg(k, v)
                       from jsonb_each(social_links) as e(k, v)
                      where nullif(trim(v #>> '{}'), '') is not null), '{}'::jsonb) as fixed,
           social_links as was
    from blanks
  )
  select count(*) into n from cleaned where fixed <> was;

  update locations l set social_links = coalesce((
      select jsonb_object_agg(k, v) from jsonb_each(l.social_links) as e(k, v)
       where nullif(trim(v #>> '{}'), '') is not null), '{}'::jsonb)
   where l.social_links is not null;

  update profiles p set social_links = coalesce((
      select jsonb_object_agg(k, v) from jsonb_each(p.social_links) as e(k, v)
       where nullif(trim(v #>> '{}'), '') is not null), '{}'::jsonb)
   where p.social_links is not null;

  return n;
end $$;

comment on function public.prune_blank_social_links() is
  'Drop keys whose value is an empty string from social_links, so a present key always means a present handle.';

revoke all on function public.blank_to_null_contacts()   from anon, authenticated;
revoke all on function public.prune_blank_social_links() from anon, authenticated;
