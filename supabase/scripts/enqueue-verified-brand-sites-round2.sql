-- A second round of verified brand websites, for handle discovery.
--
-- The first round guessed <brandname>.com alone and found 28 of 75. This one
-- tries four shapes per brand -- <brand>.com, <brand>ny.com,
-- <brand>cannabis.com, <brand>.co -- which is what finds most of these: 1937 is
-- at 1937cannabis.com, Animal House at animalhouseny.com, Cannabals at
-- cannabalsny.com.
--
-- Nanticoke shows why it was worth the extra requests. nanticoke.com was
-- rejected in the first round as a real site with no cannabis signal -- it
-- belongs to something else entirely -- while nanticoke.co is the brand.
--
-- Generic one-word names were given only the qualified shapes, never the bare
-- .com: bloom.com and jetty.com belong to other businesses, but bloomcannabis
-- .com could only be the brand. Sub-brands were tried on their own core name,
-- unlike the first round which skipped them -- if a sub-brand has its own site
-- that is the right answer, and if it does not, the name check rejects the
-- parent's page anyway.
--
-- Same acceptance test as the first round: answers over verified TLS, carries
-- the brand's name, shows a cannabis signal, and does not redirect off-domain.
-- Still written to social_discovery only, not to profiles.website -- a verified
-- guess is good enough to point a crawler at and not good enough to publish.
--
-- 22 of 90 brands. The other 68 have no findable site under these shapes and
-- need a licence record or a person.
INSERT INTO public.social_discovery (subject_type, subject_id, website)
VALUES
  ('brand', 5371, public.norm_url('https://1937cannabis.com')),
  ('brand', 5377, public.norm_url('https://animalhouseny.com')),
  ('brand', 5656, public.norm_url('https://bonanzacannabis.com')),
  ('brand', 5660, public.norm_url('https://breakfastconnections.co')),
  ('brand', 5401, public.norm_url('https://cannabalsny.com')),
  ('brand', 3380, public.norm_url('https://florettecannabis.com')),
  ('brand', 5448, public.norm_url('https://goldengardenny.com')),
  ('brand', 5450, public.norm_url('https://goodtidecannabis.com')),
  ('brand', 5471, public.norm_url('https://high5ny.com')),
  ('brand', 5483, public.norm_url('https://hudsoncannabis.co')),
  ('brand', 5794, public.norm_url('https://koacannabis.com')),
  ('brand', 5503, public.norm_url('https://leftcoastcannabis.com')),
  ('brand', 5812, public.norm_url('https://majorcannabis.com')),
  ('brand', 5522, public.norm_url('https://nanticoke.co')),
  ('brand', 5870, public.norm_url('https://recrootsny.com')),
  ('brand', 5552, public.norm_url('https://rollinggreenny.com')),
  ('brand', 5558, public.norm_url('https://sapphirecannabis.com')),
  ('brand', 5915, public.norm_url('https://supernaturalsny.com')),
  ('brand', 5586, public.norm_url('https://untitledcannabis.com')),
  ('brand', 5944, public.norm_url('https://urbanxtracts.com')),
  ('brand', 4213, public.norm_url('https://wanabrands.com')),
  ('brand', 5960, public.norm_url('https://zizzleny.com'))
ON CONFLICT (subject_type, subject_id) DO NOTHING;

SELECT count(*) FILTER (WHERE status='pending' AND subject_type='brand')    AS brand_pending,
       count(*) FILTER (WHERE status='pending' AND subject_type='location') AS location_pending,
       count(*)                                                              AS total
  FROM public.social_discovery;
