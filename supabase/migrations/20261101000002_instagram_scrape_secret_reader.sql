-- Give instagram-scrape a way to actually read its own secrets.
--
-- The function asked PostgREST for `decrypted_secrets`, which resolves to
-- public.decrypted_secrets. The view is in the vault schema, which PostgREST does not
-- expose, so the lookup returned null however many secrets were in Vault — and the function
-- reported "instagram_scrape_token is not in Vault" while the token sat there. Every other
-- Vault reader in this database is a security-definer SQL function, which is why none of
-- them hit this.
--
-- Exposing the vault schema to PostgREST would fix the symptom and hand out every secret
-- the project owns. This instead returns one secret by name, for the three names this
-- feature uses and nothing else, so it cannot be turned into a general oracle even by
-- something already holding the service key.

create or replace function public.instagram_scrape_secret(p_name text)
returns text
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v text;
begin
  if p_name not in ('instagram_scrape_token', 'instagram_scrape_actor', 'instagram_scrape_input') then
    raise exception 'instagram_scrape_secret: % is not a secret this function may read', p_name;
  end if;
  select decrypted_secret into v from vault.decrypted_secrets where name = p_name;
  return v;
end $$;

-- Only the service key, which is to say only an Edge Function. Never a browser.
revoke all on function public.instagram_scrape_secret(text) from public, anon, authenticated;
grant execute on function public.instagram_scrape_secret(text) to service_role;

comment on function public.instagram_scrape_secret(text) is
  'Reads one of instagram-scrape''s own Vault secrets by name, for the service role only. Exists because PostgREST cannot see the vault schema, and exposing it would surrender every other secret too.';
