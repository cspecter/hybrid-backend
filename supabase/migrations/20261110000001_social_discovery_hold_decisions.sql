-- Let a person overrule the handle scorer, and stop one brand's handle landing
-- on another's profile.
--
-- Both of these were found the hard way on 2026-11-10, applying 28 freshly
-- crawled brand sites.
--
-- ─── 1. A human decision has nowhere to live ─────────────────────────────────
--
-- social_discovery_apply() begins with `perform social_discovery_score()`, and
-- score() recomputes `confidence` for every row from the handle, the subject
-- name and the host. So setting confidence = 'low' by hand to hold a handle back
-- does nothing: the next apply() recomputes it to 'high' and applies it in the
-- same statement. Three handles were held back that way and all three were live
-- on profiles seconds later -- silently, because apply() reports only a count.
--
-- confidence is derived, so it cannot also be the override. This adds a column
-- that is not derived, and teaches score() to respect it.
alter table public.social_discovery
  add column if not exists confidence_override text
    check (confidence_override in ('high', 'low', 'vendor'));

comment on column public.social_discovery.confidence_override is
  'Set by a person to overrule the scorer. social_discovery_score() leaves it alone and confidence follows it. Null means the score decides. This exists because confidence is recomputed on every apply(), so it cannot carry a decision.';


-- ─── 2. The scorer is blind to a child brand on a parent''s site ─────────────
--
-- 20261001000011 catches the parent-on-child case: @curaleaf.usa on
-- trykecompanies.com, @terrascend on valhallaconfections.com, both correctly
-- held at 'low' because the handle echoes neither the subject nor the host.
--
-- It cannot catch the reverse. superfog.mfused on mfused.com scores 'high',
-- because the handle contains the host -- and it is the Instagram account of
-- Super Fog, which is its own brand profile (5574) on the same consented list,
-- with no handle of its own. Applying it put one brand's account on another
-- brand's page and left the real owner empty.
--
-- "Contains the host" cannot simply be tightened: thehouseofsacci, honeykingden
-- and macpharms.official all carry extra words around the host and are all
-- correct. What distinguishes the bad one is not its shape but that the extra
-- word is the name of another brand we already know about.
--
-- So that is the test, and it only ever demotes -- it can make a handle wait for
-- a person, never apply one that would not have applied before.
create or replace function public.social_handle_names_another_brand(
  p_subject_id integer, p_handle text
) returns boolean
language sql stable
set search_path = public, pg_temp
as $$
  with me as (
    select regexp_replace(lower(coalesce(
             nullif(trim(p.display_name), ''), p.username, '')), '[^a-z0-9]', '', 'g') as mine
      from profiles p where p.id = p_subject_id
  ),
  hand as (select regexp_replace(lower(coalesce(p_handle, '')), '[^a-z0-9]', '', 'g') as h)
  select exists (
    select 1
      from profiles o, me, hand
     where o.profile_type = 'brand'
       and o.id <> p_subject_id
       -- Six characters, so that a brand called Herb or Bloom does not match half
       -- the handles in the table. Short brand names are exactly the ones whose
       -- name appearing inside a handle means nothing.
       and length(regexp_replace(lower(coalesce(nullif(trim(o.display_name), ''), o.username, '')),
                                 '[^a-z0-9]', '', 'g')) >= 6
       and position(regexp_replace(lower(coalesce(nullif(trim(o.display_name), ''), o.username, '')),
                                   '[^a-z0-9]', '', 'g') in hand.h) > 0
       -- Not a demotion when the other brand's name is part of this one's own
       -- name: "Cookies" inside "Cookies Small Batch" is the same business.
       and position(regexp_replace(lower(coalesce(nullif(trim(o.display_name), ''), o.username, '')),
                                   '[^a-z0-9]', '', 'g') in me.mine) = 0
  );
$$;

comment on function public.social_handle_names_another_brand(integer, text) is
  'True when a handle contains the name of a different brand in this database, which is how a sub-brand account found on a parent''s website shows up. Demotes only.';


-- ─── score(), respecting both ────────────────────────────────────────────────
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
         when s.echoes then 'high'
         else 'low'
       end)
    from (
      select d2.id,
             (   position(left(subj, 4) in hand) > 0 or position(left(hand, 4) in subj) > 0
              or position(left(host, 4) in hand) > 0 or position(left(hand, 4) in host) > 0
             ) as echoes
        from (
          select d3.id,
                 regexp_replace(lower(coalesce(
                   case d3.subject_type
                     when 'brand' then (select coalesce(nullif(trim(p.display_name), ''), p.username)
                                          from profiles p where p.id = d3.subject_id)
                     else (select l.name from locations l where l.id = d3.subject_id)
                   end, '')), '[^a-z0-9]', '', 'g')                                  as subj,
                 regexp_replace(lower(coalesce(d3.instagram, '')), '[^a-z0-9]', '', 'g') as hand,
                 regexp_replace(lower(coalesce(
                   regexp_replace(d3.website, '^https?://(www\.)?', ''), '')),
                   '[^a-z0-9].*$', '', 'g')                                          as host
            from social_discovery d3
        ) d2
    ) s
   where s.id = d.id and d.instagram is not null;
  get diagnostics n = row_count;
  return n;
end $$;

comment on function public.social_discovery_score() is
  'Recomputes confidence for every row that has a handle. Honours confidence_override, rejects vendor accounts, demotes a handle naming another brand, and otherwise asks whether the handle echoes the subject or its host.';
