-- Posting rights, enforced in the database for the first time.
--
-- Before this migration "can post" was a client-side constant:
--
--   app/hybrid-mvp.jsx:  const canPost = role === "creator" || role === "brand";
--
-- and the posts policies only ever asked WHOSE profile the post is filed under,
-- never whether that profile is allowed to post at all. Anyone with the public
-- anon key and a session could insert a post for their own profile.
--
-- ── Why this is derived, not a new role_id ──────────────────────────────────
-- Budtender and Store Manager are NOT new role_id values. role_id is a single
-- integer, and these statuses are neither single nor exclusive:
--   • someone can be a budtender AND an approved creator — one column cannot say both
--   • someone can work at two stores — a budtender is always a budtender *somewhere*
--   • losing the job must remove the rights, which a derived read does for free;
--     a role_id would need a demotion trigger, and that trigger would have to guess
--     what to demote TO without clobbering creator status
-- location_employees already carries (location_id, profile_id, role, is_approved),
-- is already the source of truth for is_location_manager() and can_manage_location(),
-- and is already what getBudtenderBadge() reads for the badge. Adding a third
-- identity axis would also make an existing inconsistency worse: 33 live profiles
-- already disagree between profile_type and role_id.
--
-- ── Who may post ───────────────────────────────────────────────────────────
-- Deliberately generous on the existing axes and strict only on the new one, so
-- nobody who could post yesterday is locked out today. Checked against production:
-- every profile that has ever posted is a creator, a brand or a super admin, except
-- one account named test-tester-11 with a single post.
create or replace function public.profile_can_post(p_profile_id integer)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.profiles p
     where p.id = p_profile_id
       and (
         -- What the client already allowed. profile_type is the column the client's
         -- `role` string is actually derived from (lib/auth.js), so this is the rule
         -- that was really in force, and it has to stay in force.
         p.profile_type in ('creator', 'brand')
         -- The same statuses expressed as role_id, for the 15 profiles where the two
         -- columns disagree, plus the admin tiers and super admins.
         or coalesce(p.role_id, 1) in (2, 3, 4, 5, 6, 9, 10)
         -- New: approved staff at any store. 'staff' is included because it is the
         -- column default and predates the budtender/manager split.
         or exists (
           select 1 from public.location_employees le
            where le.profile_id = p.id
              and le.is_approved is true
              and le.role in ('budtender', 'manager', 'staff')
         )
       )
  );
$$;

revoke execute on function public.profile_can_post(integer) from public;
grant execute on function public.profile_can_post(integer) to authenticated, service_role;

-- RESTRICTIVE, so it ANDs with the existing permissive policies instead of
-- widening anything. The ownership rule in "Profiles can have all permissions for
-- posts." still decides WHOSE post you may file; this decides whether that profile
-- may post at all. Scoped to INSERT and to authenticated on purpose: editing and
-- deleting an existing post must keep working for someone who has since lost the
-- right to write a new one, and service_role must stay unaffected.
drop policy if exists "Only posting-enabled profiles may create posts" on public.posts;
create policy "Only posting-enabled profiles may create posts"
  on public.posts
  as restrictive
  for insert
  to authenticated
  with check (public.profile_can_post(profile_id));
