-- Queue the 28 verified brand websites for handle discovery.
--
-- Written to social_discovery only, deliberately NOT to profiles.website. These
-- URLs were guessed as <brandname>.com and then verified (answers over verified
-- TLS, carries the brand name, shows a cannabis signal, no off-domain redirect),
-- which is good enough to point a crawler at and not good enough to publish on
-- the brand's profile. If a handle comes back and checks out, the website has
-- earned its place on the profile then.
--
-- on conflict does nothing, matching social_discovery_enqueue(), so this is safe
-- to re-run.
INSERT INTO public.social_discovery (subject_type, subject_id, website)
VALUES
  ('brand', 5382, public.norm_url('https://ayrloom.com')),
  ('brand', 4331, public.norm_url('https://floristfarms.com')),
  ('brand', 5556, public.norm_url('https://rubyfarms.com')),
  ('brand', 5419, public.norm_url('https://dankbydefinition.com')),
  ('brand', 5435, public.norm_url('https://fernway.com')),
  ('brand', 5491, public.norm_url('https://jetpacks.com')),
  ('brand', 5468, public.norm_url('https://headytree.com')),
  ('brand', 5633, public.norm_url('https://akronbloom.com')),
  ('brand', 5482, public.norm_url('https://houseofsacci.com')),
  ('brand', 523, public.norm_url('https://bodegaboyz.com')),
  ('brand', 5427, public.norm_url('https://eatonbotanicals.com')),
  ('brand', 5423, public.norm_url('https://doobielabs.com')),
  ('brand', 3487, public.norm_url('https://smokiez.com')),
  ('brand', 5512, public.norm_url('https://mfused.com')),
  ('brand', 5649, public.norm_url('https://bisonbotanics.com')),
  ('brand', 5567, public.norm_url('https://smoakland.com')),
  ('brand', 5634, public.norm_url('https://alchemypure.com')),
  ('brand', 5479, public.norm_url('https://honeyking.com')),
  ('brand', 3563, public.norm_url('https://kushypunch.com')),
  ('brand', 5659, public.norm_url('https://boutiq.com')),
  ('brand', 5766, public.norm_url('https://honestpharmco.com')),
  ('brand', 3399, public.norm_url('https://missgrass.com')),
  ('brand', 5810, public.norm_url('https://macpharms.com')),
  ('brand', 5593, public.norm_url('https://weedwater.com')),
  ('brand', 5395, public.norm_url('https://brassknuckles.com')),
  ('brand', 5520, public.norm_url('https://muhameds.com')),
  ('brand', 5514, public.norm_url('https://minnygrown.com')),
  ('brand', 3257, public.norm_url('https://sluggers.com'))
ON CONFLICT (subject_type, subject_id) DO NOTHING;

SELECT count(*) FILTER (WHERE status='pending' AND subject_type='brand')  AS brand_pending,
       count(*) FILTER (WHERE status='pending' AND subject_type='location') AS location_pending,
       count(*)                                                            AS total
  FROM public.social_discovery;
