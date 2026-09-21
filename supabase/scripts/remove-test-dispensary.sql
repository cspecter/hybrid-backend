-- Remove the test dispensary and its personas.
--
-- NOT RUN as part of any migration. Run it by hand when the test fixtures are no
-- longer wanted:
--
--   supabase db query --linked "$(cat supabase/scripts/remove-test-dispensary.sql)"
--
-- Everything created by 20260921000012_test_dispensary.sql is identified by three
-- stable keys, not by hard-coded ids, so this stays correct if the seed is re-run:
--
--   profiles.username in (hybridtestbrand, hybridtestmanager, hybridtestbudtender)
--   locations.name    = 'Hybrid Test Dispensary'
--   lists.name        in ('Test Staff Picks', 'Test Daily Drivers') owned by the brand
--
-- NOTE: the seed sets profiles.slug, but a trigger rewrites slug from username, so
-- username is the key that actually holds. Matching on slug finds nothing.
--
-- Deletion order follows the foreign keys inward-out: the rows that point at the
-- location and the personas go first, then the location, then the profiles.
--
-- Wrap it in BEGIN/ROLLBACK first if you want to see the counts without committing.

do $$
declare
  brand_id integer;
  mgr_id integer;
  bud_id integer;
  loc_id integer;
  n integer;
  removed jsonb := '{}'::jsonb;
begin
  select id into brand_id from public.profiles where username = 'hybridtestbrand';
  select id into mgr_id   from public.profiles where username = 'hybridtestmanager';
  select id into bud_id   from public.profiles where username = 'hybridtestbudtender';
  select id into loc_id   from public.locations where name = 'Hybrid Test Dispensary';

  if brand_id is null and loc_id is null then
    raise notice 'Nothing to remove — the test fixtures are not present.';
    return;
  end if;

  -- ── Things hanging off the location ────────────────────────────────────────
  if loc_id is not null then
    delete from public.claimed_deals
     where deal_id in (select id from public.deals where location_id = loc_id);
    get diagnostics n = row_count; removed := removed || jsonb_build_object('claimed_deals', n);

    delete from public.deal_products
     where deal_id in (select public_id from public.deals where location_id = loc_id);
    get diagnostics n = row_count; removed := removed || jsonb_build_object('deal_products', n);

    delete from public.deals where location_id = loc_id;
    get diagnostics n = row_count; removed := removed || jsonb_build_object('deals', n);

    delete from public.location_redemption_codes where location_id = loc_id;
    get diagnostics n = row_count; removed := removed || jsonb_build_object('location_redemption_codes', n);

    delete from public.location_stashlists where location_id = loc_id;
    get diagnostics n = row_count; removed := removed || jsonb_build_object('location_stashlists', n);

    delete from public.location_employees where location_id = loc_id;
    get diagnostics n = row_count; removed := removed || jsonb_build_object('location_employees', n);

    delete from public.favorite_locations where location_id = loc_id;
    get diagnostics n = row_count; removed := removed || jsonb_build_object('favorite_locations', n);

    -- Analytics rollups and events that name this location.
    delete from public.analytics_daily_location where location_id = loc_id;
    get diagnostics n = row_count; removed := removed || jsonb_build_object('analytics_daily_location', n);
    delete from public.analytics_events where target_type = 'location' and target_id = loc_id;
    get diagnostics n = row_count; removed := removed || jsonb_build_object('analytics_events_location', n);

    delete from public.locations where id = loc_id;
    get diagnostics n = row_count; removed := removed || jsonb_build_object('locations', n);
  end if;

  -- ── Things hanging off the three profiles ──────────────────────────────────
  -- The seeded stashlists are owned by the brand; deleting by name alone could
  -- catch someone else's list with the same title.
  if brand_id is not null then
    delete from public.lists
     where profile_id = brand_id and name in ('Test Staff Picks', 'Test Daily Drivers');
    get diagnostics n = row_count; removed := removed || jsonb_build_object('lists', n);
  end if;

  delete from public.profile_admins
   where managed_profile_id in (brand_id, mgr_id, bud_id)
      or admin_profile_id   in (brand_id, mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('profile_admins', n);

  -- Any employment these personas hold anywhere else.
  delete from public.location_employees where profile_id in (mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('location_employees_elsewhere', n);

  -- Referral rows, if any were created while testing.
  delete from public.referrals where referrer_profile_id in (brand_id, mgr_id, bud_id)
                                  or referred_profile_id in (brand_id, mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('referrals', n);
  delete from public.referral_payout_events
   where payout_id in (select id from public.referral_payouts where profile_id in (brand_id, mgr_id, bud_id));
  delete from public.referral_payouts where profile_id in (brand_id, mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('referral_payouts', n);
  delete from public.referral_codes where profile_id in (brand_id, mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('referral_codes', n);

  -- Anyone left acting as one of the personas.
  delete from public.acting_as where profile_id in (brand_id, mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('acting_as', n);

  delete from public.notifications where profile_id in (brand_id, mgr_id, bud_id)
                                      or actor_id   in (brand_id, mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('notifications', n);

  delete from public.analytics_daily_profile where profile_id in (brand_id, mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('analytics_daily_profile', n);
  delete from public.analytics_events
   where actor_profile_id in (brand_id, mgr_id, bud_id)
      or (target_type = 'profile' and target_id in (brand_id, mgr_id, bud_id));
  get diagnostics n = row_count; removed := removed || jsonb_build_object('analytics_events_profile', n);

  delete from public.profiles where id in (brand_id, mgr_id, bud_id);
  get diagnostics n = row_count; removed := removed || jsonb_build_object('profiles', n);

  raise notice 'Removed: %', removed::text;
end $$;

-- What should be left: nothing.
select 'profiles'   as what, count(*) from public.profiles  where username like 'hybridtest%'
union all
select 'locations',  count(*) from public.locations where name = 'Hybrid Test Dispensary'
union all
select 'employees',  count(*) from public.location_employees
  where profile_id in (select id from public.profiles where username like 'hybridtest%')
union all
select 'admin links', count(*) from public.profile_admins
  where managed_profile_id in (select id from public.profiles where username like 'hybridtest%');
