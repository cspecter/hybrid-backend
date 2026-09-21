-- Every INSERT into profile_admins has been failing.
--
-- Both AFTER INSERT triggers on the table still use the column names it had before
-- it was renamed: NEW.brand_id and NEW.admin_id, against a table whose columns are
-- managed_profile_id and admin_profile_id. Postgres raises
-- `record "new" has no field "brand_id"` and the insert is rolled back, so nobody
-- has been able to add an admin to a brand. The newest row in profile_admins is
-- from 2025-12-08, which is consistent with that.
--
-- _fn_profile_set_claimed also sets profiles.claimed, a column that does not exist
-- on this database at all — so even with the names corrected it would still fail.
-- That write is dropped rather than guessed at: there is no column to write to, and
-- inventing one to satisfy a trigger would be the wrong way round.
--
-- FOUND WHILE seeding the test dispensary, which needs profile_admins rows. Outside
-- the brief, but a hard blocker for it.

create or replace function public._fn_profile_set_claimed()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    -- Touch the brand's products and locations so anything keyed on updated_at
    -- re-reads them now that the brand has an administrator.
    update public.products p set updated_at = now()
     where p.id in (select pb.product_id from public.product_brands pb
                     where pb.brand_id = NEW.managed_profile_id);
    update public.locations l set updated_at = now()
     where l.brand_id = NEW.managed_profile_id;
  end if;
  return NEW;
end;
$$;

create or replace function public.fn_profile_admins_triggers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  brand_name text;
begin
  if TG_OP = 'INSERT' then
    select display_name into brand_name from public.profiles where id = NEW.managed_profile_id;

    -- Notifying is a courtesy; it must never be the reason an admin cannot be
    -- added. That is exactly how this table ended up unwritable for nine months.
    begin
      perform public.send_notification(
        NEW.admin_profile_id,
        'admin_added',
        NEW.managed_profile_id,
        'profile',
        NEW.managed_profile_id,
        jsonb_build_object('brand_name', brand_name, 'role', coalesce(NEW.role, 'admin')));
    exception when others then
      raise warning 'profile_admins: admin_added notification failed: %', SQLERRM;
    end;
  end if;
  return NEW;
end;
$$;

revoke all on function public._fn_profile_set_claimed() from public, anon, authenticated;
revoke all on function public.fn_profile_admins_triggers() from public, anon, authenticated;
