#!/usr/bin/env python3
"""Read brands' and stores' own websites for their social handles.

    python3 scripts/social/find_social_handles.py --limit 600

There are four Instagram handles in the whole database. That is the blocker on anything that
shows a brand's posts: no scraper tells you that "Lobo" is @loboextracts, and guessing wrong
puts a stranger's photographs on a brand's page. A brand's own site nearly always links its
account, and reading a site that invites the public to read it raises none of the questions
reading Instagram would.

Work comes from social_discovery, claimed in batches, so this is resumable and two copies can
run without doing the same site twice. A site that answers is marked done whether or not it
mentioned Instagram; only a failed fetch returns to the queue, and only three times.

ROBOTS, AND THE MISTAKE NOT TO REPEAT
    An earlier crawler here used urllib's RobotFileParser directly. It fetches robots.txt with
    Python's own user agent, a WAF answers 403, and RobotFileParser records that as
    disallow_all -- indistinguishable from a site that really did forbid everything. The
    crawler politely did nothing and said it was being well behaved.

    So robots.txt is fetched here with our own user agent and the status is read the way
    RFC 9309 says to: 4xx means no restrictions exist (a missing or forbidden robots.txt is
    not a prohibition), 5xx means the site is unwell and we stay away, 2xx means parse it and
    obey it.
"""
import argparse, json, os, re, subprocess, sys, tempfile, time
import urllib.error, urllib.parse, urllib.request
from urllib.robotparser import RobotFileParser

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UA = ("HybridSocialFinder/0.1 (+https://hybrid-raskin.vercel.app; "
      "contact: aaron.raskin@gmail.com)")
FETCH_TIMEOUT = 15
MAX_BYTES = 2 * 1024 * 1024          # a homepage; anything larger is not what we came for
PER_HOST_DELAY = 1.0                 # one request a second to any one site
# Where a site puts its social links when the homepage does not. Tried in order and only
# when the homepage yielded nothing, so a cooperative site costs exactly one request.
FALLBACK_PATHS = ("/contact", "/about")

try:
    sys.stdout.reconfigure(line_buffering=True)
except Exception:
    pass


def run_sql(sql: str):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(sql)
        path = f.name
    try:
        out = subprocess.run(["supabase", "db", "query", "--linked", "--file", path],
                             cwd=REPO, capture_output=True, text=True, timeout=180)
        body = out.stdout or out.stderr
        i = body.find("{")
        if i < 0:
            raise RuntimeError(f"no JSON from supabase: {body[:300]}")
        d = json.JSONDecoder().raw_decode(body[i:])[0]
        if "error" in d:
            raise RuntimeError(str(d["error"])[:400])
        return d.get("rows", [])
    finally:
        os.unlink(path)


def q(s) -> str:
    if s is None:
        return "null"
    return "'" + str(s).replace("'", "''") + "'"


# ── robots ───────────────────────────────────────────────────────────────────
_robots: dict = {}

def allowed(url: str) -> bool:
    parts = urllib.parse.urlsplit(url)
    origin = f"{parts.scheme}://{parts.netloc}"
    if origin not in _robots:
        _robots[origin] = _load_robots(origin)
    rp = _robots[origin]
    if rp is None:          # no restrictions exist
        return True
    if rp is False:         # site unwell; stay away
        return False
    try:
        return rp.can_fetch(UA, url)
    except Exception:
        return True


def _load_robots(origin: str):
    req = urllib.request.Request(origin + "/robots.txt",
                                headers={"User-Agent": UA, "Accept": "text/plain,*/*"})
    try:
        with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as r:
            body = r.read(MAX_BYTES).decode("utf-8", "replace")
        rp = RobotFileParser()
        rp.parse(body.splitlines())
        return rp
    except urllib.error.HTTPError as e:
        # 4xx: no robots.txt that forbids anything. 5xx: the site is struggling, leave it.
        return None if 400 <= e.code < 500 else False
    except Exception:
        # Timeouts, DNS, TLS. Not a prohibition, and the page fetch will fail too if the
        # host is truly unreachable.
        return None


# ── fetching ─────────────────────────────────────────────────────────────────
def fetch(url: str):
    """Return (status, html). status 0 means the request never completed."""
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en-US,en;q=0.9",
    })
    try:
        with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as r:
            ctype = (r.headers.get("Content-Type") or "").lower()
            if "html" not in ctype and "xml" not in ctype:
                return r.status, ""
            return r.status, r.read(MAX_BYTES).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception:
        return 0, ""


# ── extraction ───────────────────────────────────────────────────────────────
IG_RE = re.compile(r'(?:https?:)?//(?:www\.)?instagram\.com/+([A-Za-z0-9._]{1,30})', re.I)
OTHER_RE = {
    "facebook":  re.compile(r'(?:https?:)?//(?:[a-z-]+\.)?facebook\.com/+([A-Za-z0-9._-]{2,60})', re.I),
    "twitter":   re.compile(r'(?:https?:)?//(?:www\.)?(?:twitter|x)\.com/+([A-Za-z0-9_]{2,15})', re.I),
    "tiktok":    re.compile(r'(?:https?:)?//(?:www\.)?tiktok\.com/+@([A-Za-z0-9._]{2,30})', re.I),
    "linkedin":  re.compile(r'(?:https?:)?//(?:[a-z]{2,3}\.)?linkedin\.com/(?:company|in)/+([A-Za-z0-9._-]{2,60})', re.I),
}
# Path segments that are the platform's own plumbing rather than an account. Without these,
# facebook.com/people/Some-Shop/123 stores the handle "people", a share widget at
# facebook.com/sharer stores "sharer", and profile.php?id=2008... stores "2008" — which is
# how the first trial run produced facebook handles of "people", "profi" and "2008".
OTHER_RESERVED = {
    "facebook": {"people", "profile", "profile.php", "pages", "pg", "sharer", "sharer.php",
                 "dialog", "plugins", "tr", "share.php", "login", "help", "policies",
                 "legal", "groups", "events", "watch", "marketplace", "hashtag"},
    "twitter":  {"share", "intent", "home", "search", "hashtag", "i", "privacy", "tos"},
    "tiktok":   set(),
    "linkedin": {"sharearticle", "sharing"},
}
# Instagram's own paths. The SQL validator rejects these too; doing it here as well keeps a
# link to one post from crowding out the real handle in the frequency count below.
RESERVED = {"p", "reel", "reels", "tv", "explore", "accounts", "about", "developer", "legal",
            "directory", "stories", "s", "web", "graphql", "api", "oauth", "challenge",
            "emails", "sessions", "invites", "direct", "archive", "help", "press", "privacy",
            "terms", "security", "igtv", "ar", "guides", "lite", "locations", "topics"}


def pick_handle(html: str, subject: str):
    """The handle a site is most likely claiming as its own."""
    counts = {}
    for m in IG_RE.finditer(html):
        h = m.group(1).lower().strip(".")
        if h and h not in RESERVED:
            counts[h] = counts.get(h, 0) + 1
    if not counts:
        return None
    # A site links its own account in the header and the footer, and a staffer's once. Where
    # the count ties, prefer the handle that looks most like whoever owns the site.
    key = re.sub(r"[^a-z0-9]", "", (subject or "").lower())

    def affinity(h: str) -> int:
        bare = re.sub(r"[^a-z0-9]", "", h)
        if not bare or not key:
            return 0
        if bare == key:
            return 3
        if bare in key or key in bare:
            return 2
        return 1 if bare[:5] == key[:5] else 0

    return sorted(counts, key=lambda h: (counts[h], affinity(h), -len(h)), reverse=True)[0]


def others(html: str):
    """Other handles, best effort. Skipped rather than guessed when a match is plumbing."""
    out = {}
    for name, rx in OTHER_RE.items():
        reserved = OTHER_RESERVED.get(name, set())
        for m in rx.finditer(html):
            h = m.group(1).lower().strip(".")
            # A bare run of digits is an internal id, not a handle anyone would type.
            if not h or h in reserved or h.isdigit():
                continue
            out[name] = h
            break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=600, help="how many sites to read")
    ap.add_argument("--batch", type=int, default=25)
    args = ap.parse_args()

    run_sql("select social_discovery_release_stale(30);")

    done = found = 0
    last_hit: dict = {}
    started = time.time()

    while done < args.limit:
        n = min(args.batch, args.limit - done)
        rows = run_sql(f"select * from social_discovery_claim({n});")
        if not rows:
            break

        results = []
        for r in rows:
            url = r["website"]
            subject = r.get("subject") or ""
            host = urllib.parse.urlsplit(url).netloc

            # One request a second to any one host, however the queue is ordered.
            wait = PER_HOST_DELAY - (time.time() - last_hit.get(host, 0))
            if wait > 0:
                time.sleep(wait)

            if not allowed(url):
                results.append((r["id"], None, None, 999, "robots.txt disallows"))
                continue

            status, html = fetch(url)
            last_hit[host] = time.time()
            handle = pick_handle(html, subject) if html else None
            social = others(html) if html else {}

            # Only ask for more pages when the homepage gave us nothing at all.
            if status and 200 <= status < 300 and not handle:
                for path in FALLBACK_PATHS:
                    alt = url.rstrip("/") + path
                    if not allowed(alt):
                        continue
                    wait = PER_HOST_DELAY - (time.time() - last_hit.get(host, 0))
                    if wait > 0:
                        time.sleep(wait)
                    s2, h2 = fetch(alt)
                    last_hit[host] = time.time()
                    if h2:
                        handle = pick_handle(h2, subject)
                        social = social or others(h2)
                    if handle:
                        break

            results.append((r["id"], handle, social or None, status,
                            None if handle else "no instagram link found"))
            if handle:
                found += 1

        # One statement per batch rather than per site.
        stmts = []
        for rid, handle, social, status, note in results:
            sj = q(json.dumps(social)) + "::jsonb" if social else "null"
            stmts.append(f"select social_discovery_record({rid}, {q(handle)}, {sj}, "
                         f"{status if status else 'null'}, {q(note)});")
        run_sql("\n".join(stmts))

        done += len(rows)
        rate = done / max(1e-9, time.time() - started)
        print(f"  {done} sites read, {found} handles found ({rate:.1f}/s)")

    print(f"\n{done} sites read, {found} handles found in {(time.time()-started)/60:.1f} min")
    print("review:  select * from v_social_discovery_found;")


if __name__ == "__main__":
    main()
