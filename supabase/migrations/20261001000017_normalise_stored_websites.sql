-- Give every stored website a scheme and no trailing slash.
--
-- 307 of them had no scheme: "nashax.com", "Www.kushmart.com". They were never broken, because
-- shopNowUrl assumes https when one is missing, but the column is read in more than one place
-- and a value a browser cannot open directly is a trap for the next reader. One of them also
-- crashed the link checker outright -- urlsplit returns an empty scheme, and every URL built
-- from that is invalid.
--
-- Pure text, no network. Anything norm_url refuses -- a value with no dot in it, which is not
-- a hostname whatever else it is -- is cleared rather than left as a link that cannot work.
create or replace function public.normalise_stored_websites() returns jsonb
language plpgsql set search_path = public as $$
declare n_loc integer := 0; n_brand integer := 0; n_bad_loc integer := 0; n_bad_brand integer := 0;
begin
  update locations set website = norm_url(website)
   where nullif(trim(website), '') is not null
     and norm_url(website) is not null
     and norm_url(website) <> website;
  get diagnostics n_loc = row_count;

  update profiles set website = norm_url(website)
   where profile_type = 'brand' and nullif(trim(website), '') is not null
     and norm_url(website) is not null
     and norm_url(website) <> website;
  get diagnostics n_brand = row_count;

  -- Not a URL at all.
  update locations set website = null, website_source = null
   where nullif(trim(website), '') is not null and norm_url(website) is null;
  get diagnostics n_bad_loc = row_count;

  update profiles set website = null, website_source = null
   where profile_type = 'brand' and nullif(trim(website), '') is not null and norm_url(website) is null;
  get diagnostics n_bad_brand = row_count;

  return jsonb_build_object(
    'locations_normalised', n_loc, 'brands_normalised', n_brand,
    'locations_cleared_not_a_url', n_bad_loc, 'brands_cleared_not_a_url', n_bad_brand,
    'still_without_a_scheme', (select count(*) from (
        select website from locations where website is not null
        union all select website from profiles where profile_type='brand' and website is not null) z
      where website !~* '^https?://'));
end $$;

comment on function public.normalise_stored_websites() is
  'Give every stored website a scheme and no trailing slash, and clear anything norm_url refuses. Pure text; safe to re-run.';

revoke all on function public.normalise_stored_websites() from anon, authenticated;
