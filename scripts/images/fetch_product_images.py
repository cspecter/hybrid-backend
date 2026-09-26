#!/usr/bin/env python3
"""Pull product images onto our own storage, resized.

    export SUPABASE_URL=...            # or set them in the environment however you like
    export SUPABASE_SERVICE_ROLE_KEY=...
    scripts/images/fetch_product_images.py --limit 2000        # a measured slice
    scripts/images/fetch_product_images.py                     # everything pending

Credentials are read from the environment and never written to disk or logged.

WHAT IT DOES per image: fetch, resize the long edge to 400px, convert to WebP, upload
to the product-images bucket, record the outcome. The original URL stays on the row,
so a larger rendition can always be fetched again — nothing here is one-way.

WHY RESIZE. Measured across the 29 source CDNs: median image 191 KB, mean 930 KB,
largest 15 MB. Stored untouched that is ~77 GB at the median and far more at the mean,
to render at roughly 400px on a phone. The renditions land nearer 15-20 GB.

WHY PER-HOST. Two CDNs carry 59% of the 420,169 images — 143,381 sit on one S3 bucket.
Draining the queue by id would point everything at one origin at once, which is
indistinguishable from an attack. Work is claimed per host and each host has its own
rate limit, so the load spreads across all of them instead of landing on one.

Resumable by construction: work is claimed in the database, a killed worker's claims
are released after an hour by product_images_release_stale(), and a failed image
returns to the queue until it has used up four attempts.
"""
import argparse, hashlib, io, json, os, queue, subprocess, sys, tempfile, threading, time
import urllib.error, urllib.request
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
UA = "HybridImageFetcher/0.1 (+https://hybrid-raskin.vercel.app; contact: aaron.raskin@gmail.com)"
BUCKET = "product-images"
MAX_EDGE = 400
WEBP_QUALITY = 82
PER_HOST_DELAY = 0.35          # seconds between requests to the SAME host
FETCH_TIMEOUT = 20
MAX_DOWNLOAD = 25 * 1024 * 1024

try:
    sys.stdout.reconfigure(line_buffering=True)
except Exception:
    pass


def run_sql(sql: str) -> dict:
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(sql)
        path = f.name
    try:
        out = subprocess.run(["supabase", "db", "query", "--linked", "--file", path],
                             cwd=REPO, capture_output=True, text=True, timeout=180)
        body = out.stdout or out.stderr
        i = body.find("{")
        if i < 0:
            raise RuntimeError(f"no JSON in response: {body[:300]}")
        parsed, _ = json.JSONDecoder().raw_decode(body[i:])
        if parsed.get("_tag") == "Error":
            raise RuntimeError(parsed["error"]["message"][:400])
        return parsed
    finally:
        os.unlink(path)


def sql_text(v) -> str:
    return "'" + str(v).replace("'", "''") + "'"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "image/*,*/*"})
    with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as r:
        data = r.read(MAX_DOWNLOAD + 1)
    if len(data) > MAX_DOWNLOAD:
        raise RuntimeError("image exceeds the 25 MB download ceiling")
    return data


def to_webp(raw: bytes):
    """Resize the long edge to MAX_EDGE and encode WebP. Returns (bytes, w, h)."""
    im = Image.open(io.BytesIO(raw))
    im.load()
    # Flatten transparency onto white: these are product shots on menu cards, and a
    # transparent WebP over a dark theme renders as a silhouette.
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im, mask=im.split()[-1])
        im = bg
    elif im.mode != "RGB":
        im = im.convert("RGB")
    w, h = im.size
    if max(w, h) > MAX_EDGE:
        scale = MAX_EDGE / float(max(w, h))
        im = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=WEBP_QUALITY, method=4)
    return buf.getvalue(), im.size[0], im.size[1]


def upload(path: str, blob: bytes, url: str, key: str):
    req = urllib.request.Request(
        f"{url.rstrip('/')}/storage/v1/object/{BUCKET}/{path}",
        data=blob, method="POST",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "image/webp",
                 "x-upsert": "true", "apikey": key})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status


def claim(host: str, n: int):
    res = run_sql(f"select * from public.product_images_claim({sql_text(host)}, {n});")
    return res.get("rows", [])


def record_many(results):
    """One statement for a whole batch.

    Recording each image with its own `supabase db query` meant spawning a CLI
    subprocess per image — about two seconds of overhead against a fetch-and-resize
    that takes a fraction of that. The smoke test ran at 0.5 images/sec, which is ten
    days for 420,169. The work was never the bottleneck; the round trip was.
    """
    if not results:
        return
    def arg(v):
        return "null" if v is None else (sql_text(v) if isinstance(v, str) else str(v))
    calls = []
    for r in results:
        calls.append(
            "select public.product_images_record("
            f"{r['id']}, {str(r['ok']).lower()}, {arg(r.get('path'))}, {arg(r.get('hash'))}, "
            f"{arg(r.get('orig'))}, {arg(r.get('stored'))}, {arg(r.get('w'))}, "
            f"{arg(r.get('h'))}, {arg(r.get('mime'))}, {arg(r.get('error'))});")
    run_sql("\n".join(calls))


def worker(host: str, budget: int, sb_url: str, sb_key: str, stats: dict, lock):
    done = 0
    while done < budget:
        batch = claim(host, min(25, budget - done))
        if not batch:
            return
        results = []
        for row in batch:
            rid, src = row["id"], row["source_url"]
            t0 = time.time()
            try:
                raw = fetch(src)
                blob, w, h = to_webp(raw)
                digest = hashlib.sha256(raw).hexdigest()
                path = f"{digest[:2]}/{digest[2:4]}/{digest}.webp"
                upload(path, blob, sb_url, sb_key)
                results.append({"id": rid, "ok": True, "path": path, "hash": digest,
                                "orig": len(raw), "stored": len(blob), "w": w, "h": h,
                                "mime": "image/webp"})
                with lock:
                    stats["stored"] += 1
                    stats["bytes_in"] += len(raw)
                    stats["bytes_out"] += len(blob)
            except Exception as e:
                results.append({"id": rid, "ok": False, "error": f"{type(e).__name__}: {e}"})
                with lock:
                    stats["failed"] += 1
            done += 1
            # Politeness is per host: this sleep is what keeps 143,381 requests off one
            # S3 bucket in a burst.
            elapsed = time.time() - t0
            if elapsed < PER_HOST_DELAY:
                time.sleep(PER_HOST_DELAY - elapsed)
        # One write for the batch. A crash before this point loses at most 25 images'
        # bookkeeping, and they return to the queue as stale claims within the hour.
        record_many(results)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="stop after roughly this many images (0 = all pending)")
    ap.add_argument("--hosts", type=int, default=8, help="how many CDNs to work in parallel (default 8)")
    args = ap.parse_args()

    sb_url = os.environ.get("SUPABASE_URL")
    sb_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not sb_url or not sb_key:
        raise SystemExit("set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment")

    released = run_sql("select public.product_images_release_stale() as n;")["rows"][0]["n"]
    if released:
        print(f"released {released} stale claims from an earlier run")

    rows = run_sql(
        "select source_host, count(*) as pending from public.product_images "
        "where status='pending' group by 1 order by 2 desc;")["rows"]
    if not rows:
        print("nothing pending")
        return
    total_pending = sum(int(r["pending"]) for r in rows)
    print(f"{total_pending:,} pending across {len(rows)} hosts")

    # Spread the budget over hosts in proportion to what each one owes, so a slice is
    # representative rather than 2,000 images from the biggest CDN.
    budget = args.limit or total_pending
    plan = []
    for r in rows[: args.hosts] if args.limit else rows:
        share = int(budget * (int(r["pending"]) / total_pending)) if args.limit else int(r["pending"])
        if share > 0:
            plan.append((r["source_host"], share))
    if not plan:
        plan = [(rows[0]["source_host"], budget)]

    stats = {"stored": 0, "failed": 0, "bytes_in": 0, "bytes_out": 0}
    lock = threading.Lock()
    threads = [threading.Thread(target=worker, args=(h, n, sb_url, sb_key, stats, lock), daemon=True)
               for h, n in plan]
    t0 = time.time()
    for t in threads:
        t.start()
    try:
        while any(t.is_alive() for t in threads):
            time.sleep(10)
            with lock:
                done = stats["stored"] + stats["failed"]
                rate = done / max(1e-9, time.time() - t0)
                print(f"  {done:,} done ({stats['stored']:,} stored, {stats['failed']:,} failed) "
                      f"{rate:.1f}/s")
    except KeyboardInterrupt:
        print("\ninterrupted — claims release themselves within the hour, rerun to continue")
        return

    dt = time.time() - t0
    done = stats["stored"] + stats["failed"]
    print(f"\n{done:,} images in {dt/60:.1f} min ({done/max(dt,1):.1f}/s)")
    if stats["stored"]:
        print(f"  downloaded {stats['bytes_in']/1024**3:.2f} GB, stored "
              f"{stats['bytes_out']/1024**3:.2f} GB "
              f"({stats['bytes_out']/max(stats['bytes_in'],1)*100:.0f}% of source)")
        print(f"  mean stored size {stats['bytes_out']/stats['stored']/1024:.0f} KB")
    print("\nprogress:  select * from v_product_image_progress;")


if __name__ == "__main__":
    main()
