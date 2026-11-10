-- Plug something into the age-restriction socket 20261102000001 left open.
--
-- Actor: intropix~instagram-posts-reels-scraper. Chosen because it reads 18+
-- accounts with no credential from us -- it manages authenticated sessions on its
-- own side -- which is the whole difficulty. apify~instagram-scraper,
-- apify~instagram-post-scraper and apidojo~instagram-scraper-api were all measured
-- refusing these accounts, and none of them accepts a cookie or a session, so no
-- amount of extra input would have fixed them.
--
-- Neither value here is a credential. The actor id is public, and the input is a
-- template with no session in it: this route works precisely because the provider
-- holds the session, so no Instagram login of ours is involved.
--
-- The input is a __template, not extra fields. The actor takes `usernames` rather
-- than directUrls, and the username differs per brand, so it cannot be a static
-- addition -- instagram-scrape substitutes {{username}} wherever it appears.
-- maxPosts is 6, matching POST_LIMIT and the six posts the consent records.
--
-- Pricing at the time of writing: $0.005 per run start, $0.002 per account
-- scanned, $0.0019 per post delivered, and failed lookups are not charged. The
-- store header quotes $1.55/1,000 against $1.90/1,000 in the pricing section, so
-- check it before relying on the figure. 15 accounts at 6 posts is pennies.
select vault.create_secret(
  'intropix~instagram-posts-reels-scraper',
  'instagram_scrape_fallback_actor',
  'Apify actor used only when the normal one is refused for age restriction. Manages its own Instagram sessions, so no credential of ours is stored.'
);

select vault.create_secret(
  '{"__template":{"usernames":["{{username}}"],"maxPosts":6,"maxPostsPerAccount":6}}',
  'instagram_scrape_fallback_input',
  'Input template for the fallback actor. {{username}} is substituted per account. Contains no credential.'
);
