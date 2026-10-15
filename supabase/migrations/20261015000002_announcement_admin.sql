-- Let a super admin manage the featured carousel.
--
-- public.announcements drives the carousel on the home screen, and it has
-- only ever had one policy: public read of published rows. Nothing could
-- write to it — not even a super admin — and nothing could read a draft. The
-- two rows in it were authored by hand against a privileged connection, which
-- is also the only way they could be edited or retired. There is no admin
-- screen because there was no way to build one.
--
-- Scoped to super admins deliberately. The carousel is platform-wide: an
-- announcement is the app speaking in its own voice on everyone's home
-- screen, not a brand promoting itself, so it does not belong to the
-- profile_admins chain that products, deals and locations use.

-- Reading drafts. The existing public policy stays exactly as it is — this is
-- additive, and policies for the same command are OR-ed, so published rows
-- remain world-readable and super admins additionally see everything else.
drop policy if exists "Super admins can read every announcement" on public.announcements;
create policy "Super admins can read every announcement"
  on public.announcements for select to authenticated
  using (exists (select 1 from public.profiles
                  where profiles.auth_id = auth.uid() and profiles.role_id = 9));

-- Writing. One policy for every command, matching the shape products and
-- product_brands already use.
drop policy if exists "Super admins can manage announcements" on public.announcements;
create policy "Super admins can manage announcements"
  on public.announcements for all to authenticated
  using (exists (select 1 from public.profiles
                  where profiles.auth_id = auth.uid() and profiles.role_id = 9))
  with check (exists (select 1 from public.profiles
                       where profiles.auth_id = auth.uid() and profiles.role_id = 9));

-- The carousel orders by sort_order and the admin list will read the whole
-- table newest-first; neither has an index today.
create index if not exists announcements_status_sort_idx
  on public.announcements (status, sort_order, id desc);
