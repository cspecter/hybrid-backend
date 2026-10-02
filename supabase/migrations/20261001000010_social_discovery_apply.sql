-- Write discovered handles onto the brand and store records.
--
-- Separate from the crawl on purpose. The crawl reads sites; this decides what to believe,
-- and v_social_discovery_found sits between them so a run can be looked at before anything
-- lands on a profile. A wrong handle is worse than a missing one -- it puts a stranger's
-- account on a brand's page -- so this is a deliberate second step rather than the tail of
-- the first.
--
-- Only ever fills a gap. An existing handle is left alone, and so is one someone typed by
-- hand. The 311 locations carrying {"instagram": ""} count as gaps: the key was created and
-- never filled, and an empty string is not an answer.
--
-- Provenance stays in social_discovery, which keeps the site the handle came from and when it
-- was read. It is deliberately not written into social_links, because that column is read by
-- the app and is not the place for crawler bookkeeping.
create or replace function public.social_discovery_apply(p_subject_type text default null)
returns jsonb
language plpgsql
set search_path = public
as $$
declare n_brand integer := 0; n_loc integer := 0;
begin
  if p_subject_type is null or p_subject_type = 'brand' then
    update profiles p
       set social_links = coalesce(p.social_links, '{}'::jsonb)
                        || jsonb_build_object('instagram', d.instagram)
      from social_discovery d
     where d.subject_type = 'brand'
       and d.subject_id = p.id
       and d.instagram is not null
       and coalesce(nullif(trim(p.social_links->>'instagram'), ''), '') = '';
    get diagnostics n_brand = row_count;
  end if;

  if p_subject_type is null or p_subject_type = 'location' then
    update locations l
       set social_links = coalesce(l.social_links, '{}'::jsonb)
                        || jsonb_build_object('instagram', d.instagram)
      from social_discovery d
     where d.subject_type = 'location'
       and d.subject_id = l.id
       and d.instagram is not null
       and coalesce(nullif(trim(l.social_links->>'instagram'), ''), '') = '';
    get diagnostics n_loc = row_count;
  end if;

  return jsonb_build_object(
    'brands_updated',    n_brand,
    'locations_updated', n_loc,
    'brands_with_a_handle', (select count(*) from profiles
                              where profile_type = 'brand'
                                and nullif(trim(social_links->>'instagram'), '') is not null),
    'locations_with_a_handle', (select count(*) from locations
                                 where nullif(trim(social_links->>'instagram'), '') is not null));
end $$;

comment on function public.social_discovery_apply(text) is
  'Copy discovered Instagram handles onto brands and stores, filling gaps only. Never overwrites a handle already present, and treats the empty string as a gap.';

-- How a run went, for deciding whether to apply it.
create or replace view public.v_social_discovery_progress as
  select subject_type,
         count(*)                                              as sites,
         count(*) filter (where status = 'pending')             as pending,
         count(*) filter (where status = 'done')                as read_ok,
         count(*) filter (where status = 'failed')              as failed,
         count(*) filter (where instagram is not null)          as handles_found,
         count(*) filter (where status = 'done' and instagram is null) as read_but_no_handle,
         count(*) filter (where http_status = 999)              as robots_disallowed
  from social_discovery
  group by subject_type;

comment on view public.v_social_discovery_progress is
  'Per subject type: how many sites were read, how many gave a handle, and how many refused.';

revoke all on function public.social_discovery_apply(text) from anon, authenticated;
