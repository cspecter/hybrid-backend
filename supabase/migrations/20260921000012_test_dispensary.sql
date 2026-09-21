-- Test dispensary and role-switching personas.
--
-- Everything created here is tagged so it can be found and removed as a set:
-- profiles carry slug 'hybrid-test-*', and the location is matched by its code.
-- The removal script is supabase/scripts/remove-test-dispensary.sql.
--
-- Two rules held to even for test data:
--   * no persona gets role_id 9 — a test account must never be able to do more
--     than the role it is pretending to be;
--   * nothing here creates a login bypass. The personas have no auth_id at all,
--     so there is no credential to sign in with. They are reachable only by a
--     super admin switching into them through profile_admins.
--
-- ASSUMPTION: personas have no auth_id. They are profiles that exist to be acted
-- as, never signed into. act_as() resolves them through profile_admins, which does
-- not need the target to have an auth row.

-- PostGIS lives in the extensions schema on this project, and a DO block cannot
-- carry its own SET. Same trip-up as the analytics migration earlier this week.
set local search_path = public, extensions;

do $$
declare
  brand_id integer;
  loc_id integer;
  mgr_id integer;
  bud_id integer;
  pc_id integer;
  list_a integer;
  list_b integer;
  deal_id integer;
  sa record;
begin
  select id into pc_id from public.postal_codes
   where postal_code = '10111' and country_code = 'US' limit 1;
  if pc_id is null then
    raise exception 'No postal_codes row for 10111 — refusing to invent one';
  end if;

  -- ── Brand that owns the store ──────────────────────────────────────────────
  insert into public.profiles (username, display_name, slug, profile_type, bio, status)
  values ('hybridtestbrand', 'Hybrid Test Brand', 'hybrid-test-brand', 'brand',
          'Test brand. Owns the Hybrid Test Dispensary. Safe to delete.', 'active')
  on conflict (username) do update set display_name = excluded.display_name
  returning id into brand_id;

  -- ── Personas ───────────────────────────────────────────────────────────────
  -- location_employees is unique on (location_id, profile_id), so one profile
  -- cannot be both manager and budtender at the same store. Two profiles.
  insert into public.profiles (username, display_name, slug, profile_type, bio, status)
  values ('hybridtestmanager', 'Test Store Manager', 'hybrid-test-manager', 'individual',
          'Test persona. Store manager at the Hybrid Test Dispensary.', 'active')
  on conflict (username) do update set display_name = excluded.display_name
  returning id into mgr_id;

  insert into public.profiles (username, display_name, slug, profile_type, bio, status)
  values ('hybridtestbudtender', 'Test Budtender', 'hybrid-test-budtender', 'individual',
          'Test persona. Budtender at the Hybrid Test Dispensary.', 'active')
  on conflict (username) do update set display_name = excluded.display_name
  returning id into bud_id;

  -- ── The store ──────────────────────────────────────────────────────────────
  -- Coordinates as PostGIS geography, matching every other row.
  insert into public.locations (
    brand_id, name, slug, description, location_type, status,
    address_line1, postal_code_id, country, coordinates,
    phone, website, email, code,
    operating_hours, features, licenses, logo_id, banner_id,
    is_verified, is_claimed, about_us, min_age)
  values (
    brand_id, 'Hybrid Test Dispensary', 'hybrid-test-dispensary',
    'Test storefront used to exercise every store surface in the app. Not a real dispensary. Safe to delete.',
    'dispensary', 'published',
    '45 Rockefeller Plaza, New York, NY 10111', pc_id, 'US',
    ST_SetSRID(ST_MakePoint(-73.9787, 40.7587), 4326)::geography,
    '+1 555 0100', 'https://example.com/hybrid-test-dispensary', 'test@example.com',
    'HYBRID-TEST',
    -- Every day, so the hours module renders in full rather than part-filled.
    jsonb_build_object(
      'monday_open','09:00:00','monday_close','21:00:00',
      'tuesday_open','09:00:00','tuesday_close','21:00:00',
      'wednesday_open','09:00:00','wednesday_close','21:00:00',
      'thursday_open','09:00:00','thursday_close','22:00:00',
      'friday_open','09:00:00','friday_close','22:00:00',
      'saturday_open','10:00:00','saturday_close','22:00:00',
      'sunday_open','10:00:00','sunday_close','19:00:00'),
    jsonb_build_object(
      'license_types', jsonb_build_array('medical','recreational'),
      'services', jsonb_build_array('storefront','pickup','delivery'),
      'amenities', jsonb_build_array('ada_accessible','parking','restroom'),
      'payment', jsonb_build_array('cash','debit'),
      'certifications', jsonb_build_array()),
    -- Licences deliberately empty, as asked.
    '[]'::jsonb,
    1, 2, true, true,
    'A test storefront at Rockefeller Center. Everything here is fake.', 21)
  on conflict (slug) do update set name = excluded.name
  returning id into loc_id;

  -- ── Employment ─────────────────────────────────────────────────────────────
  insert into public.location_employees (location_id, profile_id, role, is_approved)
  values (loc_id, mgr_id, 'manager', true)
  on conflict (location_id, profile_id) do update set role = 'manager', is_approved = true;

  insert into public.location_employees (location_id, profile_id, role, is_approved)
  values (loc_id, bud_id, 'budtender', true)
  on conflict (location_id, profile_id) do update set role = 'budtender', is_approved = true;

  -- ── Every super admin may act as all three ─────────────────────────────────
  -- Being an admin of the brand IS the "dispensary owner" role; there is no
  -- separate owner profile, because locations.brand_id already names the owner.
  for sa in select p.id from public.super_admins s join public.profiles p on p.auth_id = s.auth_id loop
    insert into public.profile_admins (admin_profile_id, managed_profile_id, role)
    values (sa.id, brand_id, 'admin') on conflict do nothing;
    insert into public.profile_admins (admin_profile_id, managed_profile_id, role)
    values (sa.id, mgr_id, 'admin') on conflict do nothing;
    insert into public.profile_admins (admin_profile_id, managed_profile_id, role)
    values (sa.id, bud_id, 'admin') on conflict do nothing;
  end loop;

  -- ── Featured stashlists ────────────────────────────────────────────────────
  insert into public.lists (name, description, profile_id, is_private)
  values ('Test Staff Picks', 'Seeded for the test dispensary.', brand_id, false)
  returning id into list_a;
  insert into public.lists (name, description, profile_id, is_private)
  values ('Test Daily Drivers', 'Seeded for the test dispensary.', brand_id, false)
  returning id into list_b;

  insert into public.location_stashlists (location_id, list_id, profile_id)
  values (loc_id, list_a, brand_id), (loc_id, list_b, brand_id)
  on conflict do nothing;

  -- ── A deal with a redemption code ──────────────────────────────────────────
  insert into public.deals (
    location_id, title, description, long_description, deal_type, discount_value,
    start_date, end_date, max_claims, is_active, category, redemption_type, code, terms)
  values (
    loc_id, 'Test Deal: 20% Off Flower',
    'Seeded deal for testing redemption at the test store.',
    'Use the code at the register. This deal is not real.',
    'percentage_off', 20,
    now() - interval '1 day', now() + interval '365 days',
    500, true, 'Flower', 'code', 'TESTDEAL', 'Test terms. Not a real offer.')
  returning id into deal_id;

  -- The store's master redemption code, so a budtender without an app account can
  -- still be tested against this store.
  insert into public.location_redemption_codes (location_id, code)
  values (loc_id, 'TESTSTORE')
  on conflict (location_id) do update set code = 'TESTSTORE';

  raise notice 'brand=% location=% manager=% budtender=% listA=% listB=% deal=%',
    brand_id, loc_id, mgr_id, bud_id, list_a, list_b, deal_id;
end $$;
