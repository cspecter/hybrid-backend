-- Let a chain be recognised by its first word, not its first two.
--
-- The original chain rule keyed on the first two words of a store's name, so "Curaleaf
-- Bellmawr" and "Curaleaf Edgewater Park" were different chains and only one of them got
-- curaleaf.com. Curaleaf Edgewater Park is the eighth busiest store in the whole feed with
-- 2,768 in-stock listings and no Shop Now link, which is what the mistake actually cost.
--
-- A first word alone is too loose on its own, though: "Cannabis World" and "Cannabis Huts" are
-- unrelated businesses, and keying on "cannabis" hands both of them cannabisrealmny.com. So a
-- first word only counts as a chain when it is not a word every third dispensary opens with.
create or replace function public.is_generic_store_word(p_word text) returns boolean
language sql immutable as $$
  select lower(coalesce(p_word, '')) in (
    'cannabis','dispensary','dispensaries','weed','marijuana','the','green','greenhouse',
    'high','happy','good','best','premium','leaf','leafs','leaves','bud','buds','smoke',
    'herb','herbs','flower','flowers','garden','gardens','house','shop','store','co',
    'company','farm','farms','new','jersey','york','city','urban','local','natural','nature',
    'pure','elevated','elevate','lifted','blazed','chill','zen','holistic','wellness','apothecary'
  );
$$;

comment on function public.is_generic_store_word(text) is
  'True for an opening word too common among dispensary names to identify a chain. Keeps "Cannabis World" and "Cannabis Huts" from being treated as one business.';

create or replace function public.locations_backfill_chain_websites()
returns jsonb
language plpgsql set search_path = public as $$
declare n integer;
begin
  with named as (
    select id, nullif(trim(website), '') as website,
           (array_remove(regexp_split_to_array(
              lower(regexp_replace(name, '[^a-zA-Z0-9 ]', '', 'g')), '\s+'), ''))[1] as w1
    from locations
  ),
  agreed as (
    select w1,
           min(regexp_replace(lower(website), '^https?://(www\.)?([^/]+).*$', '\2')) as host
    from named
    where website is not null and w1 is not null
      and length(w1) >= 4 and not is_generic_store_word(w1)
    group by w1
    -- Two stores already agreeing is the evidence. One store is not a chain.
    having count(distinct regexp_replace(lower(website), '^https?://(www\.)?([^/]+).*$', '\2')) = 1
       and count(*) >= 2
  )
  update locations l
     set website = 'https://' || a.host, website_source = 'chain'
    from named n join agreed a on a.w1 = n.w1
   where n.id = l.id and n.website is null;
  get diagnostics n = row_count;

  return jsonb_build_object(
    'assigned_from_chain', n,
    'active_stores_with_a_website', (select count(*) from locations l
       where l.website is not null and exists (select 1 from menu_items_raw mi
         where mi.location_id = l.id and coalesce(mi.in_stock, true))),
    'active_stores_still_without', (select count(*) from locations l
       where l.website is null and exists (select 1 from menu_items_raw mi
         where mi.location_id = l.id and coalesce(mi.in_stock, true))));
end $$;

comment on function public.locations_backfill_chain_websites() is
  'Give a store its chain''s website when its first name word identifies a chain whose other stores all agree on one domain. Never overwrites an existing website.';

revoke all on function public.is_generic_store_word(text)             from anon, authenticated;
revoke all on function public.locations_backfill_chain_websites()     from anon, authenticated;
