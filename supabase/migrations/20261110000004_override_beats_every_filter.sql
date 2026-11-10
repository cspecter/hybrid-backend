-- Make confidence_override actually override.
--
-- 20261110000001 added the column and honoured it inside social_discovery_score()'s
-- main UPDATE. 20261110000002 restored two filters on that same UPDATE -- the
-- four-character floor on a handle, and `instagram is not null` -- without noticing
-- that a row excluded by either is a row whose override is never read.
--
-- So the override worked only for handles of four characters or more: exactly the
-- rows least likely to need one. Measured 2026-11-10, all five overrides in the
-- table were being ignored, and brand 197's three-character handle 'nug' was
-- written onto its profile by the very apply() that was supposed to be prevented
-- from doing so.
--
-- A decision a person has recorded cannot be conditional on the scorer's own
-- filters. It goes last, after everything, and nothing can skip it.
create or replace function public.social_discovery_score() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  update social_discovery d
     set confidence = coalesce(
       d.confidence_override,
       case
         when social_handle_is_vendor(d.instagram) then 'vendor'
         when d.subject_type = 'brand'
              and social_handle_names_another_brand(d.subject_id, d.instagram) then 'low'
         when echoes then 'high'
         else 'low'
       end)
    from (
      select d2.id,
             (   position(left(subj, 4) in hand) > 0 or position(left(hand, 4) in subj) > 0
              or position(left(host, 4) in hand) > 0 or position(left(hand, 4) in host) > 0
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
      ) d2
      where length(d2.hand) >= 4
    ) scored
   where scored.id = d.id;
  get diagnostics n = row_count;

  -- A handle too short to compare is held for a person rather than guessed at.
  update social_discovery
     set confidence = 'low'
   where instagram is not null and confidence is null;

  -- Last, and subject to nothing above it. A row below the length floor, or with
  -- no handle at all, never reaches the first statement -- and those are exactly
  -- the rows someone is most likely to have ruled on by hand.
  update social_discovery
     set confidence = confidence_override
   where confidence_override is not null
     and confidence is distinct from confidence_override;

  return n;
end $$;

comment on function public.social_discovery_score() is
  'Recomputes confidence for every row with a handle: vendor accounts rejected, a handle naming another brand demoted, otherwise does it echo the subject or its host. A handle under four characters is never scored high. confidence_override is applied last and overrides all of it.';

-- brand 197 was written while the override was being ignored. Take it back off
-- the profile; the override now holds, so apply() will not return it.
UPDATE public.profiles
   SET social_links = social_links - 'instagram'
 WHERE id = 197
   AND social_links->>'instagram' = 'nug';
