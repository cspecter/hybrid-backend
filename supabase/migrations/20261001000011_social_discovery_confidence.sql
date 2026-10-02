-- Decide which discovered handles are safe to apply without someone reading them.
--
-- Reading the first 283 found two ways of being wrong:
--
--   Somebody else's platform. hackettstowndispensarynj.com links @squarespace, because the
--   template's own footer does. A denylist of site builders, menu providers and directories
--   keeps a vendor's account from becoming a dispensary's.
--
--   The parent company. trykecompanies.com links @curaleaf.usa, valhallaconfections.com links
--   @terrascend, forbiddenflowers.com links @glasshousefarms. All real accounts, all the wrong
--   level, and all genuinely on the brand's own site because the brand belongs to them.
--
-- What separates the good ones is that they resemble the host even when they do not resemble
-- the name: @a21experience on a21dispensary.com, @gasandgrassusa on gasandgrassnj.com,
-- @sky.hopewell on skycannanj.com. The parent accounts and the vendor accounts resemble
-- neither. So a handle that echoes the subject or its domain is applied, and one that echoes
-- nothing waits for a person -- a wrong handle puts a stranger's photographs on a brand's
-- page, which is worse than an empty field.
alter table public.social_discovery add column if not exists confidence text;

comment on column public.social_discovery.confidence is
  'high when the handle echoes the subject name or its own domain; low when it echoes neither, which is how a parent company or a site-builder account shows up. Only high is applied automatically.';

-- Accounts that belong to somebody's vendor, not to the business whose site it is.
create or replace function public.social_handle_is_vendor(p_handle text) returns boolean
language sql immutable as $$
  select lower(coalesce(p_handle, '')) in (
    -- site builders and hosts
    'squarespace','wix','wixcom','shopify','wordpress','wordpressdotcom','godaddy','webflow',
    'duda','weebly','bigcommerce','squareup','square',
    -- cannabis menu and ordering platforms
    'dutchie','iheartjane','janetechnology','treez','tymber','blaze','meadow','leaflogix',
    'springbig','alpineiq','sweed','greenline',
    -- directories and media
    'weedmaps','leafly','hightimes','merryjane','cannabisnow','forbes',
    -- generic social plumbing
    'instagram','facebook','twitter','tiktok','youtube','linkedin','pinterest','snapchat'
  );
$$;

comment on function public.social_handle_is_vendor(text) is
  'True for accounts belonging to a site builder, menu platform or directory rather than to the business whose website linked it.';

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

  -- A handle too short to compare is held for a person rather than guessed at.
  update social_discovery
     set confidence = coalesce(confidence, 'low')
   where instagram is not null and confidence is null;

  return n;
end $$;

comment on function public.social_discovery_score() is
  'Mark each discovered handle high, low or vendor, so only the ones that echo the subject or its domain are applied without review.';

-- Apply only what was judged high.
create or replace function public.social_discovery_apply(p_subject_type text default null)
returns jsonb
language plpgsql
set search_path = public
as $$
declare n_brand integer := 0; n_loc integer := 0;
begin
  perform social_discovery_score();

  if p_subject_type is null or p_subject_type = 'brand' then
    update profiles p
       set social_links = coalesce(p.social_links, '{}'::jsonb)
                        || jsonb_build_object('instagram', d.instagram)
      from social_discovery d
     where d.subject_type = 'brand' and d.subject_id = p.id
       and d.instagram is not null and d.confidence = 'high'
       and coalesce(nullif(trim(p.social_links->>'instagram'), ''), '') = '';
    get diagnostics n_brand = row_count;
  end if;

  if p_subject_type is null or p_subject_type = 'location' then
    update locations l
       set social_links = coalesce(l.social_links, '{}'::jsonb)
                        || jsonb_build_object('instagram', d.instagram)
      from social_discovery d
     where d.subject_type = 'location' and d.subject_id = l.id
       and d.instagram is not null and d.confidence = 'high'
       and coalesce(nullif(trim(l.social_links->>'instagram'), ''), '') = '';
    get diagnostics n_loc = row_count;
  end if;

  return jsonb_build_object(
    'brands_updated', n_brand,
    'locations_updated', n_loc,
    'held_for_review', (select count(*) from social_discovery where confidence = 'low'),
    'vendor_rejected', (select count(*) from social_discovery where confidence = 'vendor'),
    'brands_with_a_handle', (select count(*) from profiles where profile_type='brand'
                              and nullif(trim(social_links->>'instagram'),'') is not null),
    'locations_with_a_handle', (select count(*) from locations
                                 where nullif(trim(social_links->>'instagram'),'') is not null));
end $$;

-- The ones a person has to look at.
create or replace view public.v_social_discovery_review as
  select d.subject_type, d.subject_id, d.instagram, d.website, d.confidence,
         case d.subject_type when 'brand' then (select coalesce(nullif(trim(p.display_name),''), p.username)
                                                  from profiles p where p.id = d.subject_id)
                             else (select l.name from locations l where l.id = d.subject_id) end as subject
  from social_discovery d
  where d.instagram is not null and d.confidence in ('low', 'vendor')
  order by d.confidence, d.subject_type;

comment on view public.v_social_discovery_review is
  'Handles that were not applied: low means it echoes neither the name nor the domain, often a parent company; vendor means it belongs to a site builder or menu platform.';

revoke all on function public.social_discovery_score() from anon, authenticated;
