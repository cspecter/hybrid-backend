-- Score on a shared opening, not a four-character window.
--
-- The first scoring held three handles it should have applied:
--
--   NUG -> @nug on nug.com, an exact match, skipped because the code ignored handles shorter
--   than four characters -- a rule meant to avoid noise that instead excluded the clearest
--   case there is.
--   A21 Dispensary -> @a21experience on a21dispensary.com, which share "a21" but not "a21d".
--   Sky Cannabis -> @sky.hopewell on skycannanj.com, which share "sky" but not "skyc".
--
-- Three characters in common at the start separates all of those from the parent-company
-- handles, which share nothing at all with the site they sit on: @curaleaf.usa on
-- trykecompanies.com, @terrascend on valhallaconfections.com, @glasshousefarms on
-- forbiddenflowers.com. Those stay held, which is the point.
create or replace function public.shared_prefix_len(a text, b text) returns integer
language plpgsql immutable as $$
declare i integer := 0; n integer := least(length(coalesce(a,'')), length(coalesce(b,'')));
begin
  while i < n and substr(a, i + 1, 1) = substr(b, i + 1, 1) loop
    i := i + 1;
  end loop;
  return i;
end $$;

comment on function public.shared_prefix_len(text, text) is
  'How many characters two strings share from the start. Used to tell a handle that belongs to a site from one that belongs to its parent company.';

create or replace function public.social_discovery_score() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  update social_discovery d
     set confidence = case
       when social_handle_is_vendor(d.instagram) then 'vendor'
       when echoes then 'high'
       else 'low'
     end
    from (
      select x.id,
             (   hand = subj or hand = host
              or shared_prefix_len(hand, subj) >= 3
              or shared_prefix_len(hand, host) >= 3
              -- One name fully inside the other, long enough not to be a coincidence:
              -- "seedandsmith" against "seedandsmithcom".
              or (length(hand) >= 5 and subj <> '' and (position(hand in subj) > 0 or position(subj in hand) > 0))
              or (length(hand) >= 5 and host <> '' and (position(hand in host) > 0 or position(host in hand) > 0))
             ) as echoes
      from (
        select d3.id,
               regexp_replace(lower(coalesce(d3.instagram, '')), '[^a-z0-9]', '', 'g') as hand,
               regexp_replace(lower(coalesce(
                 case d3.subject_type
                   when 'brand' then (select coalesce(nullif(trim(p.display_name),''), p.username)
                                        from profiles p where p.id = d3.subject_id)
                   else (select l.name from locations l where l.id = d3.subject_id)
                 end, '')), '[^a-z0-9]', '', 'g') as subj,
               regexp_replace(regexp_replace(lower(coalesce(d3.website,'')),
                 '^https?://(www\.)?', ''), '[^a-z0-9].*$', '') as host
        from social_discovery d3
        where d3.instagram is not null
      ) x
    ) scored
   where scored.id = d.id;
  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.social_discovery_score() is
  'Mark each discovered handle high, low or vendor. High means it shares an opening with the subject name or its domain, or one contains the other; low waits for a person.';
