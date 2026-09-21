-- referral_qualify_on_write picked the profile id with a CASE expression over
-- TG_TABLE_NAME. plpgsql evaluates that as one SQL expression, so every branch's
-- field reference has to resolve against NEW — and on the profiles trigger NEW has
-- no follower_id. Every attempt to finish onboarding failed with
-- `record "new" has no field "follower_id"`.
--
-- That is worse than it sounds: the trigger fires on profiles UPDATE OF
-- onboarding_completed_at, so it would have broken finishing onboarding for every
-- user on the platform, referred or not. Caught by the behavioural qualification
-- test; the catalog had nothing to say about it.
--
-- IF/ELSIF evaluates only the branch it takes.
create or replace function public.referral_qualify_on_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid integer;
begin
  if TG_TABLE_NAME = 'relationships' then
    pid := NEW.follower_id;
  elsif TG_TABLE_NAME = 'profiles' then
    pid := NEW.id;
  else
    -- stash, lists, giveaway_entries and claimed_deals all name it profile_id.
    pid := NEW.profile_id;
  end if;

  if pid is not null then
    -- Cheap guard: almost no account is a pending referral, and this runs on every
    -- follow and stash in the system.
    if exists (select 1 from public.referrals where referred_profile_id = pid and status = 'pending') then
      perform public.referral_try_qualify(pid);
    end if;
  end if;
  return NEW;
end;
$$;

revoke all on function public.referral_qualify_on_write() from public, anon, authenticated;
