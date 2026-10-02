-- Keep connected brands' posts fresh on a schedule.
--
-- Instagram's media_url expires within hours, so a post cached once stops rendering while
-- still existing. Six-hourly is frequent enough that a brand page is never showing dead image
-- links, and infrequent enough to be unremarkable traffic.
--
-- Same dispatch shape as the giveaway winner email: pg_net cannot answer its caller, so the
-- outcome is read from the response log rather than returned here.
create or replace function public.instagram_sync_dispatch()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare base text; token text; n integer;
begin
  select count(*) into n from brand_instagram where status = 'active';
  if n = 0 then
    -- Nothing connected yet, which is the expected state until App Review passes.
    return;
  end if;

  select decrypted_secret into base  from vault.decrypted_secrets where name = 'functions_base_url';
  select decrypted_secret into token from vault.decrypted_secrets where name = 'giveaway_invoke_token';
  if base is null or token is null then
    raise notice 'instagram_sync_dispatch: vault secrets not set — no sync';
    return;
  end if;

  perform net.http_post(
    url     := rtrim(base, '/') || '/instagram-sync',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'Authorization', 'Bearer ' || token),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end $$;

comment on function public.instagram_sync_dispatch() is
  'Ask instagram-sync to refresh connected brandsّ posts and tokens. Does nothing when no brand is connected.';

select cron.schedule('instagram-sync', '13 */6 * * *', $$select public.instagram_sync_dispatch()$$);

revoke all on function public.instagram_sync_dispatch() from anon, authenticated;
