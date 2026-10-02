-- Curate the generic-word list rather than infer it.
--
-- The first-word chain rule gave Casa Bliss Cannabis the website of Casa Verde, because two
-- Casa Verde stores agree on casaverdenewyork.com and "casa" is the word they share. Two
-- attempts to separate those automatically both failed on this exact pair:
--
--   Treat the extra words as place names, since a chain's suffix is a town. "Bliss" is a real
--   hamlet in Wyoming County NY, so Casa Bliss passes.
--   Require the host to hold nothing the candidate lacks. casaverdenewyork holds "verde", which
--   rejects Casa Bliss correctly -- and also rejects Beleaf - Calverton against
--   collectivebeleaf.com, which is a genuine chain.
--
-- So the list is curated, the way product_terms is. "Casa" is a word for house and belongs
-- beside "house", "green" and "pure" on the same grounds: a word two unrelated dispensaries
-- can both open with is not a chain name.
create or replace function public.is_generic_store_word(p_word text) returns boolean
language sql immutable as $$
  select lower(coalesce(p_word, '')) in (
    'cannabis','dispensary','dispensaries','weed','marijuana','the','green','greenhouse',
    'high','happy','good','best','premium','leaf','leafs','leaves','bud','buds','smoke',
    'herb','herbs','flower','flowers','garden','gardens','house','shop','store','co',
    'company','farm','farms','new','jersey','york','city','urban','local','natural','nature',
    'pure','elevated','elevate','lifted','blazed','chill','zen','holistic','wellness','apothecary',
    -- Added after Casa Bliss was handed Casa Verde's website.
    'casa','verde','terra','canna','kush','gold','golden','silver','royal','crown','empire',
    'liberty','freedom','garden','valley','river','mountain','summit','harbor','bay','park',
    'main','first','union','central','grand','star','stars','moon','sun','cloud','sky'
  );
$$;

comment on function public.is_generic_store_word(text) is
  'True for an opening word too common among dispensary names to identify a chain. Curated rather than inferred: two attempts to separate "Casa Bliss" from "Casa Verde" by rule both failed, one of them by also rejecting a real chain.';

-- Chain guesses are rebuilt rather than patched, because a word moving onto the generic list
-- has to withdraw the assignments it already made.
create or replace function public.locations_rebuild_chain_websites() returns jsonb
language plpgsql set search_path = public as $$
declare n_cleared integer := 0; r jsonb;
begin
  update locations set website = null, website_source = null where website_source = 'chain';
  get diagnostics n_cleared = row_count;

  -- First two words, then first word: a chain written "Curaleaf Bellmawr" and one written
  -- "Curaleaf Edgewater Park" are the same chain, and only the one-word key sees that.
  perform locations_backfill_websites();
  r := locations_backfill_chain_websites();

  return jsonb_build_object('cleared_first', n_cleared) || r;
end $$;

comment on function public.locations_rebuild_chain_websites() is
  'Withdraw every chain-inferred website and derive them again, so a change to the generic-word list takes effect on what was already assigned.';

revoke all on function public.is_generic_store_word(text)              from anon, authenticated;
revoke all on function public.locations_rebuild_chain_websites()       from anon, authenticated;
