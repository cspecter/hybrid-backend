#!/usr/bin/env python3
"""Decide which stored websites actually work, and where.

    python3 scripts/social/check_websites.py

A Shop Now button uses locations.website, so a dead link is now the store's reputation on the
other end of a tap. The handle crawl found 215 stored sites that did not answer at all, but one
failed fetch does not tell a dead domain from a slow server, an expired certificate, or bot
protection closing the connection. This separates them, and only says "dead" when it is sure.

    alive    the stored URL answers
    moved    something close answers: the root where the path 404s, http where https fails,
             or a shortener's destination. The working URL is recorded.
    dead     the domain does not resolve, or refuses every connection, or serves 404 at its
             own root. These lose their website.
    unknown  blocked, timed out, or erroring. Keeps its website: a site that blocks a crawler
             usually works perfectly for a person.
"""
import argparse, json, os, socket, ssl, subprocess, sys, tempfile, time
import urllib.error, urllib.parse, urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UA = ("HybridLinkChecker/0.1 (+https://hybrid-raskin.vercel.app; "
      "contact: aaron.raskin@gmail.com)")
TIMEOUT = 25
PER_HOST_DELAY = 1.0

try:
    sys.stdout.reconfigure(line_buffering=True)
except Exception:
    pass


def run_sql(sql: str):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(sql); path = f.name
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


def q(s):
    return "null" if s is None else "'" + str(s).replace("'", "''") + "'"


def attempt(url: str):
    """Return (kind, http_status, final_url, detail).

    kind is one of ok, http_error, dns, refused, tls, timeout, other — the distinction that
    decides whether a store keeps its link.
    """
    req = urllib.request.Request(url, headers={
        "User-Agent": UA, "Accept": "text/html,*/*", "Accept-Language": "en-US,en;q=0.9"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return "ok", r.status, r.geturl(), None
    except urllib.error.HTTPError as e:
        # A server answered, just not with a page.
        return "http_error", e.code, url, None
    except urllib.error.URLError as e:
        reason = e.reason
        if isinstance(reason, socket.gaierror):
            return "dns", None, url, "domain does not resolve"
        if isinstance(reason, ssl.SSLError) or "certificate" in str(reason).lower():
            return "tls", None, url, f"tls: {str(reason)[:90]}"
        if isinstance(reason, socket.timeout) or "timed out" in str(reason).lower():
            return "timeout", None, url, "timed out"
        if isinstance(reason, ConnectionRefusedError) or "refused" in str(reason).lower():
            return "refused", None, url, "connection refused"
        return "other", None, url, str(reason)[:90]
    except socket.timeout:
        return "timeout", None, url, "timed out"
    except Exception as e:
        return "other", None, url, str(e)[:90]


def judge(stored: str):
    """Work out what, if anything, serves this store's site."""
    # Some stored values have no scheme at all -- "nashax.com" -- because they were supplied
    # before anything normalised this column. urlsplit gives them an empty scheme, which makes
    # every URL built from them invalid, so they are given one here. If the site then answers,
    # the verdict is "moved" and the stored value gets fixed as a side effect.
    stored = stored.strip()
    if not stored.lower().startswith(("http://", "https://")):
        stored = "https://" + stored.lstrip("/")

    parts = urllib.parse.urlsplit(stored)
    root = f"{parts.scheme}://{parts.netloc}/"
    has_path = (parts.path or "/").rstrip("/") not in ("", "/")

    tried = []
    kind, status, final, detail = attempt(stored)
    tried.append(kind)

    if kind == "ok":
        # A shortener or a redirect lands somewhere else; that somewhere is the real site.
        same = final.rstrip("/") == stored.rstrip("/")
        return ("alive" if same else "moved"), status, (None if same else final), detail

    # The stored URL is a path that is gone, but the site itself may be fine.
    if has_path and (kind == "http_error" and status in (404, 410) or kind in ("dns", "other")):
        k2, s2, f2, d2 = attempt(root)
        tried.append(k2)
        if k2 == "ok":
            return "moved", s2, f2, f"stored path returned {status or kind}; root works"

    # https failed outright: some of these only serve http.
    if parts.scheme == "https" and kind in ("tls", "refused", "other", "dns"):
        alt = urllib.parse.urlunsplit(("http",) + tuple(parts[1:]))
        k3, s3, f3, d3 = attempt(alt)
        tried.append(k3)
        if k3 == "ok":
            return "moved", s3, f3, "https failed; http works"

    # Nothing answered. Only a domain that does not exist, or one that refuses every
    # connection, is called dead — a block or a timeout is not evidence of absence.
    if all(t == "dns" for t in tried):
        return "dead", None, None, "domain does not resolve"
    if kind == "refused" and "ok" not in tried:
        return "dead", None, None, "connection refused on every attempt"
    if kind == "http_error" and status in (404, 410) and not has_path:
        return "dead", status, None, "server answers 404 at its own root"
    if kind == "http_error" and status in (401, 403):
        return "unknown", status, None, "blocked to automated requests; may work for a person"
    return "unknown", status, None, detail or f"no answer ({'/'.join(tried)})"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=400)
    ap.add_argument("--batch", type=int, default=20)
    args = ap.parse_args()

    run_sql("select website_check_release_stale(30);")
    done = 0
    tally = {}
    last_hit = {}
    started = time.time()

    while done < args.limit:
        rows = run_sql(f"select * from website_check_claim({min(args.batch, args.limit - done)});")
        if not rows:
            break
        stmts = []
        for r in rows:
            host = urllib.parse.urlsplit(r["website"]).netloc
            wait = PER_HOST_DELAY - (time.time() - last_hit.get(host, 0))
            if wait > 0:
                time.sleep(wait)
            verdict, status, resolved, detail = judge(r["website"])
            # A stored value with no scheme that works is still worth rewriting, so the
            # column ends up with something a browser can open.
            if verdict == "alive" and not r["website"].strip().lower().startswith(("http://", "https://")):
                verdict, resolved = "moved", "https://" + r["website"].strip().lstrip("/")
            last_hit[host] = time.time()
            tally[verdict] = tally.get(verdict, 0) + 1
            stmts.append(f"select website_check_record({r['id']}, {q(verdict)}, {q(resolved)}, "
                         f"{status if status else 'null'}, {q(detail)});")
        run_sql("\n".join(stmts))
        done += len(rows)
        print(f"  {done} checked  " + "  ".join(f"{k}:{v}" for k, v in sorted(tally.items())))

    print(f"\n{done} checked in {(time.time()-started)/60:.1f} min")
    print("review:  select * from v_website_check_summary;")
    print("apply:   select jsonb_pretty(website_check_apply());")


if __name__ == "__main__":
    main()
