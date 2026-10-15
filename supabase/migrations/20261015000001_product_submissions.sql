-- Let a brand submit a product, and let a super admin publish it.
--
-- The admin dashboard has always had a product form that said "Product
-- submitted for approval!". Nothing was submitted: the handler appended to a
-- React array and there is no products insert anywhere in the app. The
-- approvals queue it was supposedly joining is a hardcoded list of seven demo
-- rows that is never read from the database, and approving one of those
-- mutates local state too. So a brand filled in the form, got a success
-- toast, and lost the product on reload.
--
-- Three things were missing underneath, which is why this is a migration and
-- not only a UI fix:
--
--   1. No INSERT policy on products for anyone but a super admin. Brand
--      admins could already UPDATE and DELETE their own products — an odd
--      asymmetry — but never create one.
--   2. No record of who submitted a product, so a queue could not say whose
--      it was and a policy could not scope anything to its submitter.
--   3. No server-side answer to "which brands does this user manage?".
--      Locations have my_manageable_locations(); brands had nothing, so the
--      client would have had to guess at the rule its own insert is judged by.
--
-- Visibility needs no new status. products_status_check already allows
-- draft/published/archived, fetchProducts filters on status = 'published',
-- and the remaining reads are by-id hydration for things a draft can never be
-- referenced from. A submission is therefore a draft, and approval is the
-- flip to published.

-- ── who manages which brand ──────────────────────────────────────────────
-- Mirrors my_manageable_locations: the server answers with the same rule the
-- policies below enforce, so the form can offer exactly what an insert will
-- accept rather than reimplementing the rule and drifting from it.
create or replace function public.my_manageable_brands()
returns setof integer
language sql
stable
security definer
set search_path = public
as $$
  select pa.managed_profile_id
    from profile_admins pa
    join profiles p on p.id = pa.admin_profile_id
   where p.auth_id = auth.uid()
  union
  -- A super admin manages every brand, so the queue and the form see the lot.
  select pr.id from profiles pr
   where exists (select 1 from profiles me
                  where me.auth_id = auth.uid() and me.role_id = 9)
     and pr.profile_type = 'brand';
$$;

revoke all on function public.my_manageable_brands() from public;
grant execute on function public.my_manageable_brands() to authenticated;

-- ── who submitted it ─────────────────────────────────────────────────────
alter table public.products
  add column if not exists submitted_by_profile_id integer references public.profiles(id);

comment on column public.products.submitted_by_profile_id is
  'Profile that submitted this product through the admin dashboard. Null for '
  'the seeded catalogue, which predates submissions.';

-- Only submitted drafts need looking up by this; the published catalogue is
-- read by other paths entirely. Narrowed to a non-null submitter because
-- "draft" alone is not a review queue: the Hybrid project holds 36,289 draft
-- products that predate submissions and were never sent to anyone. They have
-- no submitter, so they stay out of both the index and the queue.
create index if not exists products_pending_review_idx
  on public.products (status, id desc)
  where status = 'draft' and submitted_by_profile_id is not null;

-- ── submitting ───────────────────────────────────────────────────────────
-- A brand admin may create a product only as a draft, and only stamped with
-- their own profile. Draft is invisible to the app, so the worst an account
-- can do here is fill a review queue nobody else sees. Publishing stays with
-- the super-admin policy that already covers every command.
drop policy if exists "Brand admins can submit draft products" on public.products;
create policy "Brand admins can submit draft products"
  on public.products for insert to authenticated
  with check (
    status = 'draft'
    and submitted_by_profile_id in (
      select id from public.profiles where auth_id = auth.uid()
    )
  );

-- The product is useless without its brand link, and that link is what makes
-- the submission reviewable, so the same people may create it for a brand
-- they manage.
drop policy if exists "Brand admins can link their own products" on public.product_brands;
create policy "Brand admins can link their own products"
  on public.product_brands for insert to authenticated
  with check (brand_id in (select public.my_manageable_brands()));

-- A submitter keeps sight of their own draft. Without this the queue is
-- visible to everyone (products are world-readable) but the brand cannot see
-- what it just sent, which reads as the submission having vanished again.
-- Products are already selectable by all, so this adds nothing to exposure;
-- it is here so the intent survives any future tightening of that policy.
drop policy if exists "Submitters can see their own drafts" on public.products;
create policy "Submitters can see their own drafts"
  on public.products for select to authenticated
  using (
    status <> 'draft'
    or submitted_by_profile_id in (
      select id from public.profiles where auth_id = auth.uid()
    )
    or exists (select 1 from public.profiles me
                where me.auth_id = auth.uid() and me.role_id = 9)
  );
