-- Two more words that are not chain names, each taught by one wrong assignment.
--
--   "NYC Bud - Queens" was handed budcitynj.com, keyed on "nyc".
--   "East Coasting - Eatontown" was handed eastleafdispensary.com, keyed on "east".
--
-- City abbreviations, boroughs and compass directions open dispensary names constantly and
-- identify nothing. Every word on this list arrived the same way: a wrong link, found by
-- reading the assignments rather than the count of them.
create or replace function public.is_generic_store_word(p_word text) returns boolean
language sql immutable as $$
  select lower(coalesce(p_word, '')) in (
    'cannabis','dispensary','dispensaries','weed','marijuana','the','green','greenhouse',
    'high','happy','good','best','premium','leaf','leafs','leaves','bud','buds','smoke',
    'herb','herbs','flower','flowers','garden','gardens','house','shop','store','co',
    'company','farm','farms','new','jersey','york','city','urban','local','natural','nature',
    'pure','elevated','elevate','lifted','blazed','chill','zen','holistic','wellness','apothecary',
    'casa','verde','terra','canna','kush','gold','golden','silver','royal','crown','empire',
    'liberty','freedom','valley','river','mountain','summit','harbor','bay','park',
    'main','first','union','central','grand','star','stars','moon','sun','cloud','sky',
    -- compass points, boroughs and city abbreviations
    'east','west','north','south','upper','lower','downtown','uptown','nyc','njx',
    'brooklyn','queens','bronx','manhattan','staten','harlem','jersey','newark','hoboken'
  );
$$;

comment on function public.is_generic_store_word(text) is
  'True for an opening word too common among dispensary names to identify a chain. Curated: each entry was added because keying on it linked two unrelated businesses.';
