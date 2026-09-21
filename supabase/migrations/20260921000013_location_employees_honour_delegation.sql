-- Make the location_employees policies resolve identity the same way the helper
-- functions now do.
--
-- With the acting-as delegation in place, is_super_admin(), is_location_manager()
-- and can_manage_location() all resolve to the acted-as persona. These policies did
-- not: the super-admin policy inlines `profiles.role_id = 9` and the write branches
-- inline `auth.uid()`, so a super admin acting as the Test Budtender could still
-- approve an employee. Verified behaviourally before this migration — the budtender
-- persona approved a pending request — and that is exactly the case the persona is
-- supposed to prove impossible.
--
-- Each policy is replaced by the equivalent expressed through the helpers, which
-- already encode the same rule (brand owner OR brand admin OR approved manager OR
-- super admin) and now honour delegation.

drop policy if exists "Super admins can do everything" on public.location_employees;
create policy "Super admins can do everything" on public.location_employees
  as permissive for all to public
  using (public.is_super_admin());

drop policy if exists "Enable update for profiles based on email" on public.location_employees;
create policy "Enable update for profiles based on email" on public.location_employees
  as permissive for update to public
  using (public.can_manage_location(location_id))
  with check (public.can_manage_location(location_id));

drop policy if exists "Enable delete for profiles based on profile_id" on public.location_employees;
create policy "Enable delete for profiles based on profile_id" on public.location_employees
  as permissive for delete to public
  using (public.can_manage_location(location_id));

-- INSERT keeps its third branch: a person asking to work somewhere, which is not a
-- management action. It resolves through current_actor_id() so that acting as a
-- persona files the request as that persona, not as the real account behind it.
drop policy if exists "Enable insert for authenticated users only" on public.location_employees;
create policy "Enable insert for authenticated users only" on public.location_employees
  as permissive for insert to public
  with check (
    public.can_manage_location(location_id)
    or (
      profile_id = public.current_actor_id()
      and is_approved is not true
      and role = any (array['budtender'::text, 'staff'::text])
    )
  );
