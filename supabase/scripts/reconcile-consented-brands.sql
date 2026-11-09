-- Reconcile the 167 brands marked "Consented to scrape? = Yes" in
-- OverallBrandsAnalytics_11_02_2026_to_11_08_2026 (sheet id
-- 1PNWYlh81xjKzNXy0xaG53W5wYE84w9VLXTTi3P6a3I4, column H, rows 2..168) against
-- the brand profiles that already exist.
--
-- READ ONLY. It inserts nothing, creates no profile and records no consent. It
-- exists because the sheet has brand names and the app has profile ids, and
-- nothing should be written until those are matched by a human.
--
-- Why this comes first: ~38,800 products already hang off seeded brand profile
-- rows, so most of these brands are very likely already in the app. Creating
-- accounts for them would duplicate, not fill a gap.
--
-- Read the output in three buckets:
--   exact      -- one brand profile, name matches after normalisation. Safe.
--   ambiguous  -- more than one candidate. MUST be resolved by hand. This is
--                 where the generic names land: Bloom, Herb, Major, Grocery,
--                 Untitled, Holiday, Turn, FX, Kiva, Drops, Tune, Preferred.
--   missing    -- no candidate. Decide per brand whether it belongs in the app
--                 at all; several entries are national or accessory companies
--                 (BIC, RAW, Puffco, Blazy Susan, Cycling Frog, Pax, Stiiizy,
--                 Jeeter, Alien Labs, Cheech & Chong) rather than NY brands.

WITH consented(brand) AS (VALUES
  ($q$ayrloom$q$),
  ($q$MFNY$q$),
  ($q$Florist Farms$q$),
  ($q$Off Hours$q$),
  ($q$Ruby Farms$q$),
  ($q$Jaunty$q$),
  ($q$Rythm (GTI)$q$),
  ($q$Leal$q$),
  ($q$Grön$q$),
  ($q$Revert Cannabis$q$),
  ($q$Camino (Kiva)$q$),
  ($q$Hashtag Honey$q$),
  ($q$Stiiizy$q$),
  ($q$Dank. by definition.$q$),
  ($q$Jeeter$q$),
  ($q$Wyld$q$),
  ($q$Nanticoke$q$),
  ($q$Bouket$q$),
  ($q$Fernway$q$),
  ($q$Find (Curaleaf)$q$),
  ($q$Select (Curaleaf)$q$),
  ($q$Untitled$q$),
  ($q$Picc$q$),
  ($q$Jetpacks$q$),
  ($q$Heady Tree$q$),
  ($q$Anthem (Curaleaf)$q$),
  ($q$Cannabals$q$),
  ($q$Herb$q$),
  ($q$Mini Mart$q$),
  ($q$Rolling Green$q$),
  ($q$Grassroots (Curaleaf)$q$),
  ($q$Layup$q$),
  ($q$Back Home Cannabis Co.$q$),
  ($q$Left Coast$q$),
  ($q$Heavy Hitters$q$),
  ($q$Golden Garden$q$),
  ($q$Akron Bloom$q$),
  ($q$Harney Brothers$q$),
  ($q$Rove$q$),
  ($q$Dragonfly$q$),
  ($q$Goodlyfe Farms$q$),
  ($q$House of Sacci$q$),
  ($q$Dogwalkers (GTI)$q$),
  ($q$Zips!$q$),
  ($q$Runtz$q$),
  ($q$Bodega Boyz$q$),
  ($q$High Peaks$q$),
  ($q$Botanist (Canopy USA)$q$),
  ($q$1906$q$),
  ($q$Hepworth$q$),
  ($q$RAW$q$),
  ($q$Claybourne Co$q$),
  ($q$PUFF$q$),
  ($q$Jetty$q$),
  ($q$Good Green (GTI)$q$),
  ($q$ElectraLeaf$q$),
  ($q$Pax$q$),
  ($q$Eaton Botanicals$q$),
  ($q$1937$q$),
  ($q$To The Moon$q$),
  ($q$Kings & Queens$q$),
  ($q$Wizard Trees$q$),
  ($q$NY Honey$q$),
  ($q$High Falls$q$),
  ($q$Flav$q$),
  ($q$Wana Brands$q$),
  ($q$Bloom$q$),
  ($q$Canna Cure Farms$q$),
  ($q$Good Tide$q$),
  ($q$Doobie Labs$q$),
  ($q$Papa's Herb$q$),
  ($q$The Plug Pack$q$),
  ($q$Lost Farm (Kiva)$q$),
  ($q$Smokiez$q$),
  ($q$Protab (LEVEL)$q$),
  ($q$Jive$q$),
  ($q$Drops$q$),
  ($q$Mfused$q$),
  ($q$Sapphire$q$),
  ($q$incredibles (GTI)$q$),
  ($q$Birdies$q$),
  ($q$Umamii$q$),
  ($q$5 Boro$q$),
  ($q$Presidential$q$),
  ($q$&Shine (GTI)$q$),
  ($q$Tune$q$),
  ($q$Ithaca Organics Cannabis...$q$),
  ($q$foy$q$),
  ($q$NYCE$q$),
  ($q$Littles (iAnthus)$q$),
  ($q$Spacebuds$q$),
  ($q$RIPPED$q$),
  ($q$Florette$q$),
  ($q$urbanXtracts$q$),
  ($q$Bison Botanics$q$),
  ($q$Holiday$q$),
  ($q$Smoakland$q$),
  ($q$Alchemy Pure$q$),
  ($q$Grocery$q$),
  ($q$DIME Industries$q$),
  ($q$Honey King$q$),
  ($q$Lowell Farms$q$),
  ($q$Major$q$),
  ($q$Eureka$q$),
  ($q$HiColor (Vireo Health)$q$),
  ($q$Kushy Punch$q$),
  ($q$Moon Dust$q$),
  ($q$Lion Order$q$),
  ($q$Supernaturals$q$),
  ($q$HI*AF (Vireo)$q$),
  ($q$Boutiq$q$),
  ($q$Dark Heart$q$),
  ($q$Grams$q$),
  ($q$Honest Pharm Co.$q$),
  ($q$Alien Labs$q$),
  ($q$Generic AF$q$),
  ($q$Stone Road$q$),
  ($q$Cheevo$q$),
  ($q$Miss Grass$q$),
  ($q$Munchkins$q$),
  ($q$Knack$q$),
  ($q$Uncle Arnie's$q$),
  ($q$Animal House$q$),
  ($q$Old Pal$q$),
  ($q$BUDD$q$),
  ($q$Soft Power Sweets$q$),
  ($q$7 SEAZ$q$),
  ($q$Mac Pharms$q$),
  ($q$Breakfast Connections$q$),
  ($q$Weed Water$q$),
  ($q$Hudson Cannabis$q$),
  ($q$Turn$q$),
  ($q$Preferred$q$),
  ($q$Rec Roots$q$),
  ($q$Connected Cannabis$q$),
  ($q$Kiva$q$),
  ($q$Flower by Edie Parker$q$),
  ($q$KOA$q$),
  ($q$JAMS (Curaleaf)$q$),
  ($q$Cheech & Chong's Cannabis$q$),
  ($q$Nerd Bar$q$),
  ($q$Super Fog (Mfused)$q$),
  ($q$Brass Knuckles$q$),
  ($q$Blazy Susan$q$),
  ($q$Cycling Frog$q$),
  ($q$Nama$q$),
  ($q$No Bad Days$q$),
  ($q$Dark Star$q$),
  ($q$Muha Meds$q$),
  ($q$Voice of the Plant (VOP)$q$),
  ($q$BIC$q$),
  ($q$Minny Grown$q$),
  ($q$Star Batch$q$),
  ($q$High Garden$q$),
  ($q$Jenny's$q$),
  ($q$FLAMER$q$),
  ($q$Pines$q$),
  ($q$High 5$q$),
  ($q$CRU Cannabis$q$),
  ($q$Slack Hollow$q$),
  ($q$Puffco$q$),
  ($q$Sluggers$q$),
  ($q$Zizzle$q$),
  ($q$FX$q$),
  ($q$Bonanza$q$),
  ($q$Lobo$q$),
  ($q$Pot & Head$q$)
),
norm AS (
  SELECT brand,
         lower(regexp_replace(brand, '\s*\([^)]*\)\s*', '', 'g')) AS base
    FROM consented
),
cand AS (
  SELECT n.brand, n.base, p.id, p.display_name, p.username, p.profile_type,
         similarity(lower(p.display_name), n.base) AS sim
    FROM norm n
    JOIN public.profiles p
      ON p.profile_type = 'brand'
     AND (lower(p.display_name) = n.base
          OR lower(p.username) = regexp_replace(n.base, '[^a-z0-9]', '', 'g')
          OR similarity(lower(p.display_name), n.base) > 0.6)
),
tally AS (
  SELECT brand, count(*) AS hits FROM cand GROUP BY brand
)
SELECT CASE WHEN t.hits IS NULL THEN 'missing'
            WHEN t.hits = 1    THEN 'exact'
            ELSE 'ambiguous' END                      AS bucket,
       n.brand,
       c.id                                           AS profile_id,
       c.display_name,
       c.username,
       round(c.sim::numeric, 2)                       AS similarity,
       sd.instagram                                   AS handle_from_own_site,
       sd.status                                      AS discovery_status,
       ic.consent_status                              AS existing_consent
  FROM norm n
  LEFT JOIN tally t  ON t.brand = n.brand
  LEFT JOIN cand  c  ON c.brand = n.brand
  LEFT JOIN public.social_discovery  sd ON sd.subject_type = 'brand' AND sd.subject_id = c.id
  LEFT JOIN public.instagram_consent ic ON ic.subject_type = 'brand' AND ic.subject_id = c.id
 ORDER BY 1, n.brand, c.sim DESC NULLS LAST;
