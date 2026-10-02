-- Surface stores whose name says one chain and whose websites say two.
--
-- Chasing the chain rule's doubtful assignments showed the rule was right every time and the
-- data under it was wrong. "NYC Bud - Manhattan" carries budcitynj.com as supplied data, which
-- the chain rule faithfully copied to "NYC Bud - Queens" -- while "NYCBUD Long Island City"
-- carries NYCBUD.com from the state licence register. The register is the authority and the
-- supplied value is simply wrong, and the same shape covers Treez Dispensary on gwleaf.com and
-- Unity Rd on jerseydispensary.com.
--
-- A view rather than a correction. Deciding that two similarly named stores are one business is
-- exactly the judgement this session has got wrong twice by rule -- Casa Bliss against Casa
-- Verde, Cannabis World against Cannabis Realm -- and a register disagreeing with a supplied
-- value is worth a person's eye, not another heuristic.
create or replace view public.v_website_conflicts as
  with keyed as (
    select l.id, l.name, l.website, l.website_source,
           regexp_replace(lower(l.website), '^https?://(www\.)?([^/]+).*$', '\2') as host,
           -- The name with punctuation and spaces removed, so "NYCBUD" and "NYC Bud" meet.
           regexp_replace(lower(l.name), '[^a-z0-9]', '', 'g') as namekey
    from locations l
    where l.website is not null and l.name is not null
  ),
  pairs as (
    select a.id as a_id, a.name as a_name, a.host as a_host, a.website_source as a_src,
           b.id as b_id, b.name as b_name, b.host as b_host, b.website_source as b_src
    from keyed a
    join keyed b
      -- One name opening the other: NYCBUD* against NYCBUDLONGISLANDCITY.
      on a.id < b.id
     and a.host <> b.host
     and (position(left(a.namekey, 6) in b.namekey) = 1 or position(left(b.namekey, 6) in a.namekey) = 1)
  )
  select a_name, a_host, a_src, b_name, b_host, b_src,
         -- A register beats a supplied value; anything else is a toss-up for a person.
         case when a_src like '%register%' and b_src not like '%register%' then a_host
              when b_src like '%register%' and a_src not like '%register%' then b_host
              else null end as register_says
  from pairs
  order by a_name;

comment on view public.v_website_conflicts is
  'Stores whose names share an opening but whose websites disagree. register_says names the authoritative host where one side came from a licence register and the other did not.';

grant select on public.v_website_conflicts to authenticated;
