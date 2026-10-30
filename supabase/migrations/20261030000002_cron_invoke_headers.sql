-- Let the cron-invoked Instagram functions past the gateway, without turning the gateway off.
--
-- Both of them were unreachable. pg_net was sending the shared invoke token as the bearer,
-- and the platform gateway rejects anything that is not a valid project JWT before the
-- function runs: UNAUTHORIZED_INVALID_JWT_FORMAT, 401, every time. instagram-sync has had
-- this since 20261002000007 and nobody noticed, because no brand has ever been connected for
-- it to do anything about.
--
-- The obvious fix is to deploy these with verify_jwt off and let the shared secret be the
-- only gate. This does not do that. It keeps the gateway checking, and sends two things:
--
--   Authorization   the anon key, which is a real project JWT and satisfies the gateway.
--                   It is public -- it ships in the frontend bundle -- so it proves only
--                   that the caller knows which project this is, and decides nothing.
--
--   X-Invoke-Token  the shared secret, compared in constant time inside each function.
--                   This is the check that actually decides, exactly as the outreach
--                   functions' auth helper describes for the same reason.
--
-- Two gates where one would have done, because the cost is one Vault entry holding a value
-- that is already public, and the alternative is an endpoint on the open internet whose only
-- protection is a single secret.

create or replace function public.instagram_sync_dispatch()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare base text; token text; anon_key text; n integer;
begin
  select count(*) into n from brand_instagram where status = 'active';
  if n = 0 then
    return;
  end if;

  select decrypted_secret into base     from vault.decrypted_secrets where name = 'functions_base_url';
  select decrypted_secret into token    from vault.decrypted_secrets where name = 'giveaway_invoke_token';
  select decrypted_secret into anon_key from vault.decrypted_secrets where name = 'functions_anon_key';
  if base is null or token is null or anon_key is null then
    raise notice 'instagram_sync_dispatch: vault secrets not set — no sync';
    return;
  end if;

  perform net.http_post(
    url     := rtrim(base, '/') || '/instagram-sync',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'Authorization', 'Bearer ' || anon_key,
                                  'X-Invoke-Token', token),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end $$;

create or replace function public.instagram_scrape_dispatch()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare base text; token text; anon_key text; n integer;
begin
  select count(*) into n
    from instagram_consent
   where source = 'scrape' and consent_status = 'granted' and status = 'active';
  if n = 0 and not exists (select 1 from instagram_media_purge where purged_at is null) then
    return;
  end if;

  select decrypted_secret into base     from vault.decrypted_secrets where name = 'functions_base_url';
  select decrypted_secret into token    from vault.decrypted_secrets where name = 'giveaway_invoke_token';
  select decrypted_secret into anon_key from vault.decrypted_secrets where name = 'functions_anon_key';
  if base is null or token is null or anon_key is null then
    raise notice 'instagram_scrape_dispatch: vault secrets not set — no scrape';
    return;
  end if;

  perform net.http_post(
    url     := rtrim(base, '/') || '/instagram-scrape',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'Authorization', 'Bearer ' || anon_key,
                                  'X-Invoke-Token', token),
    body    := '{}'::jsonb,
    timeout_milliseconds := 300000
  );
end $$;

revoke all on function public.instagram_sync_dispatch()   from anon, authenticated;
revoke all on function public.instagram_scrape_dispatch() from anon, authenticated;
