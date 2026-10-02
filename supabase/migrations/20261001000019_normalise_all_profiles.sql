-- Normalise every profile's website, not only brands'.
--
-- The first pass restricted itself to profile_type='brand' because brands are what the Shop Now
-- work needed, and left 18 creator and dispensary profiles holding schemeless URLs. The column
-- is the same column and a value a browser cannot open is no better on one row type than
-- another.
create or replace function public.normalise_stored_websites() returns jsonb
language plpgsql set search_path = public as $$
declare n_loc integer := 0; n_prof integer := 0; n_bad_loc integer := 0; n_bad_prof integer := 0;
begin
  update locations set website = norm_url(website)
   where nullif(trim(website), '') is not null
     and norm_url(website) is not null and norm_url(website) <> website;
  get diagnostics n_loc = row_count;

  update profiles set website = norm_url(website)
   where nullif(trim(website), '') is not null
     and norm_url(website) is not null and norm_url(website) <> website;
  get diagnostics n_prof = row_count;

  -- Not a URL at all: no dot in it, so not a hostname whatever else it is.
  update locations set website = null, website_source = null
   where nullif(trim(website), '') is not null and norm_url(website) is null;
  get diagnostics n_bad_loc = row_count;

  update profiles set website = null, website_source = null
   where nullif(trim(website), '') is not null and norm_url(website) is null;
  get diagnostics n_bad_prof = row_count;

  return jsonb_build_object(
    'locations_normalised', n_loc, 'profiles_normalised', n_prof,
    'locations_cleared_not_a_url', n_bad_loc, 'profiles_cleared_not_a_url', n_bad_prof,
    'still_without_a_scheme', (select count(*) from (
        select website from locations where website is not null
        union all select website from profiles where website is not null) z
      where website !~* '^https?://'));
end $$;
