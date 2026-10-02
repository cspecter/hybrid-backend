# Finding brands' and stores' social handles

    python3 scripts/social/find_social_handles.py --limit 600

Reads each brand's and store's own website and takes the Instagram handle it links. There were
four handles in the whole database before this; a handle is the thing any Instagram feature
needs first, because no amount of scraping tells you that "Lobo" is `@loboextracts`, and
guessing wrong puts a stranger's photographs on a brand's page.

## Running it

    select social_discovery_enqueue();                  -- queue sites that have no handle yet
    python3 scripts/social/find_social_handles.py       -- read them (about 0.8 sites a second)
    select * from v_social_discovery_progress;          -- how it went
    select * from v_social_discovery_found;             -- what it found
    select jsonb_pretty(social_discovery_apply());      -- write the confident ones
    select * from v_social_discovery_review;            -- what a person needs to decide

Resumable: work is claimed in batches, a site that answers is marked done whether or not it
mentioned Instagram, and only a failed fetch is retried, up to three times.

## What it will not do

**Apply a handle it cannot vouch for.** A handle is applied when it shares an opening with the
business's name or its own domain, or one contains the other. Anything else waits for a person,
because a wrong handle is worse than an empty field. That holds back the parent-company links
a brand's own site carries — `@curaleaf.usa` on trykecompanies.com, `@terrascend` on
valhallaconfections.com — and it also holds back some that are probably right, like
`@madebykiva` for Kiva Confections.

**Trust a site builder's footer.** `hackettstowndispensarynj.com` links `@squarespace`. Site
builders, menu platforms and directories are rejected outright.

**Overwrite anything.** Only an empty handle is filled, and the 311 locations carrying
`{"instagram": ""}` count as empty — the key was created and never filled.

## What it cannot reach

Of 600 sites: 283 gave a handle, 63 were read and linked no Instagram, 84 failed to answer and
18 refused by robots.txt. The failures break down as sites that render their footer in
JavaScript (caliva.com), bot protection (403), link shorteners stored in the website field
(`bit.ly/...`, `app.link/...`), and dead deep paths (`golddropco.com/our-story`, where the
root would probably have worked). A headless browser would recover the JavaScript ones; the
shorteners are bad stored data rather than a crawl problem.

robots.txt is fetched with this crawler's own user agent and read the way RFC 9309 says: 4xx
means no restrictions exist, 5xx means stay away. An earlier crawler here used urllib's
RobotFileParser directly, which fetches with Python's default user agent, gets a 403 from a
WAF, and records that as `disallow_all` — politely doing nothing while reporting good manners.
