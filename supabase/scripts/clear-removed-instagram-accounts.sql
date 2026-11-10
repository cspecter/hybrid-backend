-- Three handles that are correct and useless.
--
-- doobielabs.ny, smokiez.handcrafted and lobocannagar were discovered from the
-- brands' own websites, and the websites still link them today -- verified by
-- reading doobielabs.com, smokiez.com and lobocannagar.com on 2026-11-10. The
-- crawler was right and so was the provider: all three accounts answer
-- "Profile isn't available. The link may be broken, or the profile may have been
-- removed", checked directly in a browser, not inferred from the scraper.
--
-- Instagram removes cannabis accounts, and the brands have not updated their own
-- footers. So there is no better handle to find; the fix is to stop showing one.
-- A brand page linking a dead account is worse than a brand page linking nothing,
-- which is the same reasoning social_discovery_apply already applies to a handle
-- it cannot vouch for.
--
-- Four profiles, not three: Smokiez exists twice, as 307 "Smokiez Edibles" and
-- 3487 "Smokiez", and both carry the handle. The duplicate is left alone here --
-- merging brands is a separate decision -- but both are cleared.

-- 1. Stop the app showing them.
UPDATE public.profiles
   SET social_links = social_links - 'instagram'
 WHERE id IN (5423, 3487, 307, 3036);

-- 2. Stop a future social_discovery_apply() putting them back. The handle is kept
--    in socials so the record of what the site said is not lost, and the override
--    is set because confidence alone is recomputed on every apply().
UPDATE public.social_discovery
   SET socials = coalesce(socials, '{}'::jsonb)
               || jsonb_build_object('instagram_removed_by_instagram', instagram),
       instagram = null,
       confidence_override = 'low',
       note = coalesce(note, '') || ' [cleared 2026-11-10: the account this site links has been removed by Instagram. Verified in a browser, not just from the scraper. Kept in socials.instagram_removed_by_instagram.]'
 WHERE subject_type = 'brand'
   AND instagram IN ('doobielabs.ny', 'smokiez.handcrafted', 'lobocannagar');

-- 3. Take them out of the daily scrape. Consent is NOT revoked: the brands'
--    permission has not changed, there is simply no account to read, and revoking
--    would both misstate that and delete media on a withdrawal that did not
--    happen. 'needs_reauth' is what instagram_scrape_dispatch() already excludes,
--    so the 41 5 * * * job stops failing on them every morning.
UPDATE public.instagram_consent
   SET status = 'needs_reauth',
       last_sync_error = 'Instagram has removed this account. The brand''s own website still links it; there is no replacement handle to use.'
 WHERE subject_type = 'brand'
   AND username IN ('doobielabs.ny', 'smokiez.handcrafted', 'lobocannagar');

SELECT (SELECT count(*) FROM public.profiles
         WHERE id IN (5423,3487,307,3036)
           AND public.norm_instagram_handle(social_links->>'instagram') IS NOT NULL) AS profiles_still_showing_a_handle,
       (SELECT count(*) FROM public.social_discovery
         WHERE subject_type='brand'
           AND instagram IN ('doobielabs.ny','smokiez.handcrafted','lobocannagar')) AS discovery_rows_still_set,
       (SELECT count(*) FROM public.instagram_consent
         WHERE status='active' AND consent_status='granted')                          AS subjects_still_scraped;
