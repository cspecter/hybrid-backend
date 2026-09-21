-- The two test personas were showing a yellow "Brand" chip on their profile pages.
--
-- The seed set profile_type = 'individual' explicitly, but profiles.role_id
-- defaults to 10 and fn_set_profile_type_from_role_id forces profile_type to
-- 'brand' whenever role_id = 10, overwriting whatever the insert asked for. So
-- both personas came out as brands: the role chip read "Brand" in gold, and the
-- blue Budtender badge — which carries the dispensary's logo — never rendered,
-- because that badge is only drawn for a profile the app treats as a person.
--
-- role_id is the field that actually decides; profile_type is derived from it.
-- Setting role_id = 1 ('user', which 828 individual profiles use) lets the trigger
-- put profile_type back to 'individual'.
--
-- The brand profile keeps role_id 10: it really is a brand.

update public.profiles
   set role_id = 1
 where username in ('hybridtestmanager', 'hybridtestbudtender');

do $$
declare bad text;
begin
  select string_agg(username || '=' || profile_type::text, ', ')
    into bad
    from public.profiles
   where username in ('hybridtestmanager', 'hybridtestbudtender')
     and profile_type <> 'individual';
  if bad is not null then
    raise exception 'personas still not individual: %', bad;
  end if;
end $$;
