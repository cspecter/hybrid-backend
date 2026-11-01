-- Let a person sync their own Instagram, not just a brand or a store.
--
-- Anyone who can post on Hybrid — a budtender, a store manager, a creator, a brand — should
-- be able to mirror their own Instagram onto their own profile. The consent model already
-- had the right shape for it; it was only missing the third kind of subject.
--
-- 'profile' means the person's own profile. can_admin_profile already returns true for
-- "this is me" (p.auth_id = auth.uid()), so no new notion of who is in charge is introduced
-- here either — it delegates to the same rule as a brand.

alter table public.instagram_consent
  drop constraint if exists instagram_consent_subject_type_check;
alter table public.instagram_consent
  add constraint instagram_consent_subject_type_check
  check (subject_type in ('brand', 'location', 'profile'));

create or replace function public.can_manage_instagram_subject(
  p_subject_type text, p_subject_id integer
) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select case p_subject_type
           when 'brand'    then public.can_admin_profile(p_subject_id)
           when 'profile'  then public.can_admin_profile(p_subject_id)
           when 'location' then public.can_manage_location(p_subject_id)
           else false
         end;
$$;
comment on function public.can_manage_instagram_subject(text, integer) is
  'Delegates to the rule that already governs the subject: can_admin_profile for a brand or a person''s own profile, can_manage_location for a store. No third notion of who is in charge.';

create or replace function public.instagram_author_profile(
  p_subject_type text, p_subject_id integer
) returns integer
language sql stable
set search_path = public
as $$
  select case p_subject_type
           when 'brand'    then p_subject_id
           when 'profile'  then p_subject_id
           -- A location is not a profile and cannot author anything. Its brand can.
           when 'location' then (select brand_id from public.locations where id = p_subject_id)
         end;
$$;

-- The guard that stands in for a foreign key across two parent tables has to know about the
-- third subject, or a 'profile' row could name an id that does not exist.
create or replace function public.instagram_consent_subject_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.subject_type in ('brand', 'profile')
     and not exists (select 1 from profiles where id = new.subject_id) then
    raise exception 'no profile % to consent for', new.subject_id;
  elsif new.subject_type = 'location'
     and not exists (select 1 from locations where id = new.subject_id) then
    raise exception 'no location % to consent for', new.subject_id;
  end if;

  if tg_op = 'UPDATE'
     and new.consent_status = 'revoked' and coalesce(old.consent_status, '') <> 'revoked' then
    -- Withdrawing permission deletes the posts it covered, rather than hiding them.
    delete from instagram_consent_media
     where subject_type = new.subject_type and subject_id = new.subject_id;
  end if;

  new.updated_at := now();
  return new;
end $$;

-- ─── Why automatic syncing is or is not available ───────────────────────────
--
-- Ongoing mirroring needs a fetch provider configured server-side, and for an age-restricted
-- account that provider needs a logged-in session. None of that is visible to the client, so
-- without this the setting would appear to work and quietly do nothing — which is how the
-- nightly run has in fact behaved since it shipped.
--
-- Returns whether each piece is present, never a secret's value.
create or replace function public.instagram_sync_capability()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare has_token boolean; has_anon boolean; has_base boolean; has_session boolean;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'Not signed in.');
  end if;
  select exists (select 1 from vault.decrypted_secrets where name = 'instagram_scrape_token'
                   and coalesce(decrypted_secret, '') <> '') into has_token;
  select exists (select 1 from vault.decrypted_secrets where name = 'functions_anon_key'
                   and coalesce(decrypted_secret, '') <> '') into has_anon;
  select exists (select 1 from vault.decrypted_secrets where name = 'functions_base_url'
                   and coalesce(decrypted_secret, '') <> '') into has_base;
  select exists (select 1 from vault.decrypted_secrets where name = 'instagram_scrape_input'
                   and coalesce(decrypted_secret, '') <> '') into has_session;

  return jsonb_build_object(
    'ok', has_token and has_anon and has_base,
    'has_provider', has_token,
    'has_session',  has_session,
    'reason', case
      when not has_token then 'Automatic syncing is not switched on for this site yet — it needs a fetch provider configured by an administrator. You can still add posts by hand.'
      when not has_base or not has_anon then 'Automatic syncing is configured but cannot be reached. An administrator needs to finish the setup.'
      when not has_session then 'Automatic syncing is on, but age-restricted accounts may not be readable until an administrator adds a signed-in session.'
      else null end
  );
end $$;

revoke all on function public.instagram_sync_capability() from anon;
grant execute on function public.instagram_sync_capability() to authenticated;

comment on function public.instagram_sync_capability() is
  'Whether ongoing Instagram mirroring can actually run, and a plain reason when it cannot. Reports only presence of configuration, never a secret.';
