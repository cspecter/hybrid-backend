-- Restore two safeguards that 20261110000001 dropped.
--
-- That migration rewrote social_discovery_score() from scratch to add
-- confidence_override and the another-brand demotion, instead of editing the
-- body from 20261001000011. Two things in the original did not survive the
-- retyping, and the re-score promoted four location handles that had been
-- correctly held:
--
--   1. `where length(d2.hand) >= 4`, and the follow-up update that sets a null
--      confidence to 'low'. Together they mean a handle too short to compare is
--      held for a person rather than guessed at. Without them a two-character
--      handle goes through the echo test, where left(hand, 4) is the whole
--      handle and matches almost any subject name -- so the shortest, least
--      identifiable handles were the ones most likely to be applied.
--
--   2. lower() before the protocol strip. The original lowercases the website
--      and then removes ^https?://(www\.)?; the rewrite removed the protocol
--      from the raw column first, so an uppercase scheme survived and the host
--      came out as 'https' -- a real case here, there is a stored website of
--      https://HELLSKITCHENCANNABIS.COM.
--
-- The body below is 20261001000011's, unchanged, with only the two deliberate
-- additions folded in. Written out in full rather than patched, because that is
-- what a reader needs in order to check this claim.
create or replace function public.social_discovery_score() returns integer
language plpgsql set search_path = public as $$
declare n integer;
begin
  update social_discovery d
     set confidence = coalesce(
       d.confidence_override,                      -- a person's decision wins
       case
         when social_handle_is_vendor(d.instagram) then 'vendor'
         -- A handle naming a different brand we already have: a sub-brand
         -- account found on its parent's website. Demotes only.
         when d.subject_type = 'brand'
              and social_handle_names_another_brand(d.subject_id, d.instagram) then 'low'
         when echoes then 'high'
         else 'low'
       end)
    from (
      select d2.id,
             -- Does the handle share its opening with the subject's name or its own domain,
             -- in either direction? Four characters is enough to tell "gasandgrassusa" from
             -- "squarespace" and short enough not to demand an exact spelling.
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

  -- A handle too short to compare is held for a person rather than guessed at --
  -- unless a person has already said otherwise.
  update social_discovery
     set confidence = coalesce(confidence_override, confidence, 'low')
   where instagram is not null and confidence is null;

  return n;
end $$;

comment on function public.social_discovery_score() is
  'Mark each discovered handle high, low or vendor, so only the ones that echo the subject or its domain are applied without review. Honours confidence_override, and demotes a handle that names another brand. A handle shorter than four characters is never scored high.';
