-- A second attempt for accounts the normal actor cannot see.
--
-- Instagram age-restricts most cannabis accounts, and whether a given one is readable
-- varies by who is asking. Measured: @hw.cco, @cheechandchong and @cannarealmny all return
-- their posts to apify~instagram-scraper with no session, while @get_jaunty answers
-- "You must be 21 years old or over to see this profile" to that actor, to
-- apify~instagram-post-scraper, and silently to apidojo~instagram-scraper-api.
--
-- So the restriction is not something extra input fixes: none of those actors accept a
-- cookie, a session or a login — they manage access themselves. Getting past it means a
-- different actor, one that authenticates.
--
-- These two secrets are that socket. Nothing is plugged into it yet, and until something
-- is, a restricted account stays restricted and says so.
create or replace function public.instagram_scrape_secret(p_name text)
returns text
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v text;
begin
  if p_name not in ('instagram_scrape_token', 'instagram_scrape_actor', 'instagram_scrape_input',
                    'instagram_scrape_fallback_actor', 'instagram_scrape_fallback_input') then
    raise exception 'instagram_scrape_secret: % is not a secret this function may read', p_name;
  end if;
  select decrypted_secret into v from vault.decrypted_secrets where name = p_name;
  return v;
end $$;

revoke all on function public.instagram_scrape_secret(text) from public, anon, authenticated;
grant execute on function public.instagram_scrape_secret(text) to service_role;

comment on function public.instagram_scrape_secret(text) is
  'Reads one of instagram-scrape''s own Vault secrets by name, for the service role only, including the fallback actor used for age-restricted accounts. Exists because PostgREST cannot see the vault schema, and exposing it would surrender every other secret too.';
