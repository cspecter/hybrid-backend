-- One application route for the two account types a member can ask to become.
--
-- Both "Apply to Be a Creator" and "Register Your Brand" were dead ends: the sheet
-- opens, both of its buttons close it, and nothing is written anywhere. Creator was
-- the only account type with no path in at all, and after 20260922000006 a user can
-- no longer quietly self-register as a brand either — so this is now the only way in
-- for both, which is why they are one table with a `kind` rather than two features.
--
-- Deliberately NOT a second queue. Budtender and manager requests are decided from
-- location_employees; these are decided from here; the admin dashboard shows both in
-- one place. Adding a third moderation surface was the thing to avoid.

create table if not exists public.account_applications (
  id             bigint generated always as identity primary key,
  public_id      uuid not null default gen_random_uuid() unique,
  profile_id     integer not null references public.profiles(id) on delete cascade,
  kind           text not null check (kind in ('creator', 'brand')),
  status         text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  -- Short by design. Three questions, none of them required to be long.
  reason         text,                 -- why they want to post
  links          jsonb not null default '[]'::jsonb,   -- existing social accounts
  samples        jsonb not null default '[]'::jsonb,   -- optional sample posts
  -- brand applications only
  brand_name     text,
  brand_url      text,
  reviewer_profile_id integer references public.profiles(id) on delete set null,
  review_reason  text,
  created_at     timestamptz not null default now(),
  reviewed_at    timestamptz
);

-- One open application per person per kind. A partial index rather than a plain
-- unique: a rejected application has to be able to sit beside a new one, or
-- reapplying after the cooldown would be impossible.
create unique index if not exists account_applications_one_pending
  on public.account_applications (profile_id, kind) where status = 'pending';
create index if not exists account_applications_status_created
  on public.account_applications (status, created_at desc);

alter table public.account_applications enable row level security;

-- Readable by the applicant and by moderation, and by nobody else: these contain
-- someone's pitch for themselves, which is not public.
drop policy if exists "Applicants read their own applications" on public.account_applications;
create policy "Applicants read their own applications"
  on public.account_applications for select
  using (
    public.is_super_admin()
    or profile_id = public.current_actor_id()
  );

-- No INSERT/UPDATE/DELETE policies at all. Every write goes through the two
-- SECURITY DEFINER functions below, which is what lets the cooldown, the
-- already-can-post check and the self-approval ban be enforced in one place
-- instead of being spread across a policy that cannot express them.

-- ── Config ─────────────────────────────────────────────────────────────────
-- How long a rejected applicant waits before trying again. A constant in one place
-- rather than a literal buried in the function, because it is a product setting.
create table if not exists public.account_application_settings (
  id                    integer primary key default 1 check (id = 1),
  reapply_cooldown_days integer not null default 30
);
insert into public.account_application_settings (id, reapply_cooldown_days)
values (1, 30) on conflict (id) do nothing;

alter table public.account_application_settings enable row level security;
drop policy if exists "Anyone signed in may read the cooldown" on public.account_application_settings;
create policy "Anyone signed in may read the cooldown"
  on public.account_application_settings for select using (true);

-- ── One new notification type ──────────────────────────────────────────────
-- Approval reuses what already exists: 60 upgraded_to_creator for a creator, 58
-- admin_added for a brand ("You've been added as an {role} for {brand_name}", which
-- is exactly what brand approval does). Rejection had nothing that fits — 56
-- employee_rejected is worded for a store — so this is the only type added.
insert into public.notification_types
  (id, code, name, category, title_template, body_template, default_channels,
   is_optional, priority, is_groupable, action_url_template, auto_expire_after, badge_increment)
values
  (86, 'application_rejected', 'Application Update', 'system',
   'Application update',
   'Your {kind} application wasn''t approved this time. {review_reason}',
   '{in_app,push}', true, 4, false, '/profile', '30 days', 1)
on conflict (id) do nothing;

-- ── Submitting ─────────────────────────────────────────────────────────────
create or replace function public.submit_account_application(
  p_kind text,
  p_reason text default null,
  p_links jsonb default '[]'::jsonb,
  p_samples jsonb default '[]'::jsonb,
  p_brand_name text default null,
  p_brand_url text default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me       integer := public.current_actor_id();
  v_cooldown integer;
  v_last     timestamptz;
  v_public   uuid;
begin
  if v_me is null then
    raise exception 'You must be signed in to apply' using errcode = '42501';
  end if;
  if p_kind not in ('creator', 'brand') then
    raise exception 'Unknown application type: %', p_kind using errcode = '22023';
  end if;

  -- Applying for posting rights you already hold is a dead end for the applicant and
  -- noise for moderation. The client hides the button; this is the rule behind it.
  if p_kind = 'creator' and public.profile_can_post(v_me) then
    raise exception 'You can already post on Hybrid' using errcode = '22023';
  end if;

  if exists (select 1 from public.account_applications
              where profile_id = v_me and kind = p_kind and status = 'pending') then
    raise exception 'You already have a % application waiting to be reviewed', p_kind using errcode = '23505';
  end if;

  select reapply_cooldown_days into v_cooldown from public.account_application_settings where id = 1;
  select max(reviewed_at) into v_last
    from public.account_applications
   where profile_id = v_me and kind = p_kind and status = 'rejected';
  if v_last is not null and v_last > now() - make_interval(days => coalesce(v_cooldown, 30)) then
    raise exception 'You can apply again after %', (v_last + make_interval(days => coalesce(v_cooldown, 30)))::date
      using errcode = '22023';
  end if;

  insert into public.account_applications
    (profile_id, kind, reason, links, samples, brand_name, brand_url)
  values
    (v_me, p_kind, nullif(trim(coalesce(p_reason, '')), ''),
     coalesce(p_links, '[]'::jsonb), coalesce(p_samples, '[]'::jsonb),
     nullif(trim(coalesce(p_brand_name, '')), ''), nullif(trim(coalesce(p_brand_url, '')), ''))
  returning public_id into v_public;

  -- No notification on submit. The brief asks for the applicant to hear about the
  -- decision, not for moderation to be paged on every application: the dashboard
  -- shows a pending count, and there is no existing type worded for this. Adding one
  -- would mean every super admin gets a push for every application.
  return v_public;
end;
$$;

revoke execute on function public.submit_account_application(text, text, jsonb, jsonb, text, text) from public;
grant execute on function public.submit_account_application(text, text, jsonb, jsonb, text, text) to authenticated;

-- ── Reviewing ──────────────────────────────────────────────────────────────
-- The only path to role_id = 2. After 20260922000006 nobody can set their own
-- role_id, and this runs as the table owner, so approval here is the single place a
-- member becomes a creator.
create or replace function public.review_account_application(
  p_public_id uuid,
  p_approve boolean,
  p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_app      public.account_applications%rowtype;
  v_me       integer := public.current_actor_id();
  v_brand_id integer;
begin
  if not public.is_super_admin() then
    raise exception 'Only Hybrid moderation can review applications' using errcode = '42501';
  end if;

  select * into v_app from public.account_applications where public_id = p_public_id for update;
  if not found then
    raise exception 'Application not found' using errcode = 'P0002';
  end if;
  if v_app.status <> 'pending' then
    raise exception 'That application has already been %', v_app.status using errcode = '22023';
  end if;
  -- Belt and braces. is_super_admin() is false while acting as someone else, so a
  -- super admin cannot reach this by switching into the applicant either — but the
  -- rule is stated rather than inferred from that.
  if v_app.profile_id = v_me then
    raise exception 'You cannot review your own application' using errcode = '42501';
  end if;

  update public.account_applications
     set status = case when p_approve then 'approved' else 'rejected' end,
         reviewer_profile_id = v_me,
         review_reason = nullif(trim(coalesce(p_reason, '')), ''),
         reviewed_at = now()
   where id = v_app.id;

  if not p_approve then
    perform public.send_notification(
      v_app.profile_id, 'application_rejected', null, 'profile', v_app.profile_id,
      jsonb_build_object('kind', v_app.kind,
                         'review_reason', coalesce(nullif(trim(coalesce(p_reason,'')),''), '')));
    return;
  end if;

  if v_app.kind = 'creator' then
    -- profile_type is left alone on purpose. The client's `role` string comes from
    -- profile_type (lib/auth.js), and trg_set_profile_type_from_role_id will move it
    -- to 'creator' from role_id anyway; writing both here would race that trigger.
    update public.profiles set role_id = 2 where id = v_app.profile_id;
    perform public.send_notification(
      v_app.profile_id, 'upgraded_to_creator', null, 'profile', v_app.profile_id, '{}'::jsonb);
  else
    -- A brand application creates a NEW brand profile and makes the applicant its
    -- admin. It does not convert the person's own profile: they keep their identity
    -- and gain a second account, which is what profile_admins and the account
    -- switcher already model, and what the form promises ("you'll receive admin
    -- access"). The brand profile has no auth_id — nobody signs into it directly.
    insert into public.profiles (username, display_name, profile_type, role_id, website)
    values (
      lower(regexp_replace(coalesce(v_app.brand_name, 'brand'), '[^a-zA-Z0-9]+', '', 'g'))
        || '_' || substr(v_app.public_id::text, 1, 6),
      coalesce(v_app.brand_name, 'Brand'),
      'brand', 10, v_app.brand_url)
    returning id into v_brand_id;

    insert into public.profile_admins (admin_profile_id, managed_profile_id)
    values (v_app.profile_id, v_brand_id)
    on conflict do nothing;

    perform public.send_notification(
      v_app.profile_id, 'admin_added', null, 'profile', v_brand_id,
      jsonb_build_object('role', 'admin', 'brand_name', coalesce(v_app.brand_name, 'your brand')));
  end if;
end;
$$;

revoke execute on function public.review_account_application(uuid, boolean, text) from public;
grant execute on function public.review_account_application(uuid, boolean, text) to authenticated;

-- ── Reading the queue ──────────────────────────────────────────────────────
-- One row per pending application with the applicant attached, so the dashboard does
-- not need a second round trip per row.
create or replace function public.pending_account_applications()
returns table (
  public_id uuid, kind text, reason text, links jsonb, samples jsonb,
  brand_name text, brand_url text, created_at timestamptz,
  applicant_name text, applicant_handle text, applicant_profile_id integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select a.public_id, a.kind, a.reason, a.links, a.samples,
         a.brand_name, a.brand_url, a.created_at,
         coalesce(p.display_name, p.username, 'Someone'),
         case when p.username is null then '' else '@' || p.username end,
         p.id
    from public.account_applications a
    join public.profiles p on p.id = a.profile_id
   where a.status = 'pending'
     and public.is_super_admin()
   order by a.created_at desc
   limit 200;
$$;

revoke execute on function public.pending_account_applications() from public;
grant execute on function public.pending_account_applications() to authenticated;

-- ── The applicant's own view ───────────────────────────────────────────────
-- Drives the button: none, pending, or rejected-with-a-date.
create or replace function public.my_account_application(p_kind text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select jsonb_build_object(
        'status', a.status,
        'kind', a.kind,
        'reason', a.review_reason,
        'reviewed_at', a.reviewed_at,
        'can_reapply_at', case when a.status = 'rejected'
            then a.reviewed_at + make_interval(days => (select reapply_cooldown_days from public.account_application_settings where id = 1))
            else null end)
       from public.account_applications a
      where a.profile_id = public.current_actor_id()
        and a.kind = p_kind
      order by a.created_at desc
      limit 1),
    'null'::jsonb);
$$;

revoke execute on function public.my_account_application(text) from public;
grant execute on function public.my_account_application(text) to authenticated;
