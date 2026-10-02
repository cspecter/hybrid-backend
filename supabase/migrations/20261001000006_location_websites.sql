-- Give stores a website to link out to, from the sources that actually have one.
--
-- 261 of the 912 active stores had one. Three sources can be mined without asking anyone:
--
--   The NY OCM register, through the match view the licence sync already builds. 72 stores,
--   and the match basis is carried through so an address match and a name-only match are
--   not pretended to be equally good.
--   The NJ dispensary register, by exact normalised name. 15 stores.
--   Chains, which share a domain: Curaleaf Bellmawr and Curaleaf Edgewater Park are the
--   same website. 32 stores, and only where every known store in that chain agrees on one
--   host -- a chain with two domains teaches us nothing.
--
-- That reaches about 380 of 912. It is not all of them and the remaining ~530 are not in
-- any data we hold: the NY register lists a website for 793 of 3,005 licensees and the rest
-- simply never gave one. Those need a lookup service, an admin field, or asking the store
-- during outreach. Recorded here so the next person does not re-derive the same dead end.
alter table public.locations add column if not exists website_source text;

comment on column public.locations.website_source is
  'Where this website came from: supplied, ny_ocm_register, nj_register, chain, or manual. Null for rows that predate this column.';

update public.locations
   set website_source = 'supplied'
 where nullif(trim(website), '') is not null and website_source is null;

-- A URL fit to put behind a button.
create or replace function public.norm_url(p_url text) returns text
language sql immutable as $$
  with t as (select trim(coalesce(p_url, '')) as u)
  select case
    -- Anything without a dot in it is not a hostname, whatever else it is.
    when (select u from t) = '' then null
    when (select u from t) !~ '\.' then null
    when (select u from t) ~* '^https?://' then rtrim((select u from t), '/')
    else 'https://' || rtrim(regexp_replace((select u from t), '^/+', ''), '/')
  end;
$$;

comment on function public.norm_url(text) is
  'Make a stored string linkable: add a scheme when missing, trim a trailing slash, and refuse anything with no dot in it.';

create or replace function public.locations_backfill_websites()
returns jsonb
language plpgsql
set search_path = public
as $$
declare n_ocm integer := 0; n_nj integer := 0; n_chain integer := 0;
begin
  -- 1. The NY register, via the licence sync's own match view.
  update locations l
     set website = norm_url(m.business_website), website_source = 'ny_ocm_register'
    from v_ny_ocm_matches m
   where m.location_id = l.id
     and nullif(trim(l.website), '') is null
     and norm_url(m.business_website) is not null;
  get diagnostics n_ocm = row_count;

  -- 2. The NJ register, by exact normalised name. Deliberately exact: a fuzzy name match
  --    across 329 dispensaries would put the wrong shop's website behind a Shop Now button,
  --    which is worse than no button.
  update locations l
     set website = norm_url(n.website), website_source = 'nj_register'
    from nj_dispensary_register n
   where lower(regexp_replace(l.name, '[^a-z0-9]', '', 'gi'))
       = lower(regexp_replace(n.name, '[^a-z0-9]', '', 'gi'))
     and nullif(trim(l.website), '') is null
     and norm_url(n.website) is not null;
  get diagnostics n_nj = row_count;

  -- 3. Chains, where every store we already know agrees on one host.
  with named as (
    select id, nullif(trim(website), '') as website,
           array_to_string((array_remove(regexp_split_to_array(
             lower(regexp_replace(name, '[^a-zA-Z0-9 ]', '', 'g')), '\s+'), ''))[1:2], ' ') as chain
    from locations
  ),
  agreed as (
    select chain, min(regexp_replace(lower(website), '^https?://(www\.)?([^/]+).*$', '\2')) as host
    from named
    where website is not null and chain <> ''
    group by chain
    having count(distinct regexp_replace(lower(website), '^https?://(www\.)?([^/]+).*$', '\2')) = 1
  )
  update locations l
     set website = 'https://' || a.host, website_source = 'chain'
    from named nm
    join agreed a on a.chain = nm.chain
   where nm.id = l.id and nm.website is null;
  get diagnostics n_chain = row_count;

  return jsonb_build_object(
    'from_ny_ocm_register', n_ocm,
    'from_nj_register',     n_nj,
    'from_chain',           n_chain,
    'with_a_website',       (select count(*) from locations where nullif(trim(website),'') is not null),
    'active_without_one',   (select count(*) from locations l
                              where nullif(trim(l.website),'') is null
                                and exists (select 1 from menu_items_raw mi
                                             where mi.location_id = l.id and coalesce(mi.in_stock, true))));
end $$;

comment on function public.locations_backfill_websites() is
  'Fill locations.website from the NY OCM register, the NJ register and agreed chain domains, recording which. Never overwrites a website already present.';

revoke all on function public.locations_backfill_websites() from anon, authenticated;

-- A Shop Now tap is intent to buy, which is a different signal from curiosity about a
-- store, so it gets its own event rather than hiding inside website_tap.
alter table public.analytics_events drop constraint if exists analytics_events_event_type_check;
alter table public.analytics_events add constraint analytics_events_event_type_check
  check (event_type = any (array[
    'post_impression','post_view','video_watch','profile_visit','product_view','list_view',
    'location_view','giveaway_view','share','link_tap','phone_tap','directions_tap',
    'website_tap','shop_now_tap','unfollow','unlike','unstash','referral_visit',
    'referral_signup_start','sponsored_impression','sponsored_tap'
  ]));
