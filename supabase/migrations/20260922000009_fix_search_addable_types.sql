-- search_addable_employees declared username and display_name as text, but both
-- columns are character varying, so every call failed with "structure of query does
-- not match function result type". plpgsql only discovers that when the query runs,
-- which is why it survived the migration and showed up on the first behavioural call.
create or replace function public.search_addable_employees(p_location_id uuid, p_query text)
returns table (username text, display_name text, profile_id integer, avatar_id integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_location_id integer;
  v_q text := lower(regexp_replace(coalesce(p_query, ''), '^@', ''));
begin
  select id into v_location_id from public.locations where public_id = p_location_id;
  if v_location_id is null or not public.can_manage_location(v_location_id) then
    return;
  end if;
  if length(v_q) < 2 then
    return;
  end if;
  return query
    select p.username::text,
           coalesce(p.display_name, p.username)::text,
           p.id,
           p.avatar_id
      from public.profiles p
     where p.profile_type <> 'brand'
       and p.auth_id is not null
       and (lower(p.username) like v_q || '%' or lower(coalesce(p.display_name,'')) like '%' || v_q || '%')
       and not exists (
         select 1 from public.location_employees le
          where le.location_id = v_location_id and le.profile_id = p.id and le.is_approved is true)
     order by (lower(p.username) = v_q) desc, lower(p.username)
     limit 10;
end;
$$;

revoke execute on function public.search_addable_employees(uuid, text) from public;
grant execute on function public.search_addable_employees(uuid, text) to authenticated;
