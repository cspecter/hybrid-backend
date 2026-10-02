-- profiles.username and locations.name are varchar, and the function declares text, so the
-- subject needs an explicit cast. Postgres refuses the whole RETURN QUERY over the
-- difference rather than coercing it.
drop function if exists public.social_discovery_claim(integer);

create or replace function public.social_discovery_claim(p_limit integer default 25)
returns table (id bigint, subject_type text, subject_id integer, website text, subject text)
language plpgsql set search_path = public as $$
begin
  return query
  with picked as (
    select d.id from social_discovery d
     where d.status = 'pending' and d.attempts < 3
     order by d.id
     limit p_limit
     for update skip locked
  ),
  claimed as (
    update social_discovery d
       set status = 'claimed', claimed_at = now(), attempts = d.attempts + 1
      from picked
     where d.id = picked.id
    returning d.id, d.subject_type, d.subject_id, d.website
  )
  select c.id, c.subject_type::text, c.subject_id, c.website::text,
         (case c.subject_type
            when 'brand' then (select coalesce(nullif(trim(p.display_name), ''), p.username)
                                 from profiles p where p.id = c.subject_id)
            else (select l.name from locations l where l.id = c.subject_id)
          end)::text
  from claimed c;
end $$;

comment on function public.social_discovery_claim(integer) is
  'Claim up to p_limit sites to read, including the name of the brand or store, which the crawler needs to break a tie between two handles on one page.';

revoke all on function public.social_discovery_claim(integer) from anon, authenticated;
