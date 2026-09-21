-- referral_resolve did not return the budtender's profile id, so the client had
-- nothing to attribute the referral_visit and referral_signup_start events to and
-- the funnel had no subject. Added; it is the id of a public profile, and the
-- function still returns no counts and no referred identities.
create or replace function public.referral_resolve(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rc record;
  store record;
  paused boolean;
begin
  if p_code is null or btrim(p_code) = '' then return null; end if;
  select is_paused into paused from public.referral_settings where id = 1;

  select c.profile_id, c.code, coalesce(p.display_name, p.username) as name,
         p.username, p.avatar_id
    into rc
    from public.referral_codes c
    join public.profiles p on p.id = c.profile_id
   where c.code = upper(btrim(p_code));

  if rc.profile_id is null then return null; end if;
  if not public.referral_is_eligible(rc.profile_id) then return null; end if;

  select l.name, l.logo_id
    into store
    from public.location_employees le
    join public.locations l on l.id = le.location_id
   where le.profile_id = rc.profile_id and le.is_approved is true and le.role = 'budtender'
   order by le.created_at
   limit 1;

  return jsonb_build_object(
    'code', rc.code,
    'paused', coalesce(paused, false),
    'budtender_profile_id', rc.profile_id,
    'budtender', jsonb_build_object(
      'name', rc.name,
      'handle', case when rc.username is null then null else '@' || rc.username end,
      'avatar', (select coalesce(f.secure_url, f.url) from public.cloud_files f where f.id = rc.avatar_id)),
    'store', case when store.name is null then null else jsonb_build_object(
      'name', store.name,
      'avatar', (select coalesce(f.secure_url, f.url) from public.cloud_files f where f.id = store.logo_id)) end
  );
end;
$$;

revoke all on function public.referral_resolve(text) from public, anon, authenticated;
grant execute on function public.referral_resolve(text) to anon, authenticated;
