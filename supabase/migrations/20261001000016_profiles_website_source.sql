-- website_source was added to locations and not to profiles, so the apply failed on the brand
-- half. Brand websites have the same provenance question -- supplied, verified, or cleared --
-- and the column belongs on both.
alter table public.profiles add column if not exists website_source text;

comment on column public.profiles.website_source is
  'Where this website came from, or what confirmed it: supplied, verified, manual. Null when unknown or when the website was cleared.';

update public.profiles
   set website_source = 'supplied'
 where profile_type = 'brand' and nullif(trim(website), '') is not null and website_source is null;
