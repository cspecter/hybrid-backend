-- Route employment requests to the people who can actually decide them.
--
-- Before this, notify_brand_of_employee_request() notified exactly one profile:
-- locations.brand_id. That is the store's owning brand account, which in practice
-- nobody signs into — so a budtender's request produced one notification that the
-- store manager who is supposed to approve it never saw, and Hybrid moderation
-- never saw either.
--
-- Who gets told, and why:
--   budtender / staff  → the owning brand, that store's approved managers, and
--                        Hybrid moderation. The manager is the normal path;
--                        moderation can see and override.
--   manager            → the owning brand, the brand's profile_admins, and Hybrid
--                        moderation. Deliberately NOT other managers: they cannot
--                        approve it (can_grant_manager excludes them), so telling
--                        them would be an invitation to a button that will refuse.
--
-- No new notification types. 54 employee_request / 55 employee_approved /
-- 56 employee_rejected already exist and already carry {location_name, role};
-- 55 and 56 already fire from notify_employee_of_approval() and are left alone, so
-- nothing here duplicates them. The client writes no notification on this path —
-- lib/location-modules.js setEmployeeApproval() says so and stays true.
create or replace function public.notify_brand_of_employee_request()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_brand_id      integer;
  v_location_name text;
  v_role          text := coalesce(new.role, 'budtender');
  v_recipient     integer;
begin
  select l.brand_id, l.name into v_brand_id, v_location_name
    from public.locations l where l.id = new.location_id;

  -- A row that arrives already approved is a seed or an admin adding staff
  -- directly, not a request anyone needs to decide.
  if new.is_approved is true then
    return new;
  end if;

  for v_recipient in
    select distinct r.pid
      from (
        -- the owning brand account
        select v_brand_id as pid
        union
        -- Hybrid moderation
        select p.id
          from public.super_admins sa
          join public.profiles p on p.auth_id = sa.auth_id
        union
        -- that store's approved managers — budtender/staff requests only
        select le.profile_id
          from public.location_employees le
         where v_role <> 'manager'
           and le.location_id = new.location_id
           and le.role = 'manager'
           and le.is_approved is true
        union
        -- the brand's profile_admins — manager requests only
        select pa.admin_profile_id
          from public.profile_admins pa
         where v_role = 'manager'
           and pa.managed_profile_id = v_brand_id
      ) r
     where r.pid is not null
       and r.pid <> new.profile_id      -- never tell the requester about their own request
  loop
    perform public.send_notification(
      v_recipient,
      'employee_request',
      new.profile_id,
      'location',
      new.location_id,
      jsonb_build_object('location_name', v_location_name, 'role', v_role)
    );
  end loop;

  return new;
end;
$$;

revoke execute on function public.notify_brand_of_employee_request() from public;
