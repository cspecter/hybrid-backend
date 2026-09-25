#!/usr/bin/env python3
"""Load a Lit Alerts export into staging.

    scripts/litalerts/import_csv.py export.csv
    scripts/litalerts/import_csv.py export.csv --chunk 300 --dry-run

Reads any CSV (or JSON array) the Lit Alerts subscription produces, sends it to
public.litalerts_import in chunks, and prints what landed. Column names are matched
server-side by feed_pick, which flattens case, spaces and underscores and tries several
spellings per field — so "Product Name", "product_name" and "PRODUCT NAME" all work and
an unexpected header is a re-parse rather than a re-export.

WHAT IT DOES NOT DO: it does not log into Lit Alerts, drive their dashboard, or page
past the 10,000-row cap in their UI. It takes a file you exported, or one their API
gave you. API access is included in the subscription; that is the route for full
coverage, not automation against the web app.

Nothing here writes to `products`. Rows land in menu_items_raw for review.
"""
import argparse, csv, json, os, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def run_sql(sql: str) -> dict:
    """supabase db query --file, because a large JSON literal does not belong in argv."""
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(sql)
        path = f.name
    try:
        out = subprocess.run(
            ["supabase", "db", "query", "--linked", "--file", path],
            cwd=REPO, capture_output=True, text=True, timeout=600)
        body = out.stdout or out.stderr
        start = body.find("{")
        if start < 0:
            raise RuntimeError(f"no JSON in response: {body[:400]}")
        parsed, _ = json.JSONDecoder().raw_decode(body[start:])
        if parsed.get("_tag") == "Error":
            raise RuntimeError(parsed["error"]["message"][:600])
        return parsed
    finally:
        os.unlink(path)


def sql_literal(payload) -> str:
    """Dollar-quoted, with a tag no product name can contain."""
    blob = json.dumps(payload, ensure_ascii=False)
    tag = "$LITROWS$"
    if tag in blob:                     # never seen, but silent corruption if it happened
        raise RuntimeError("payload contains the dollar-quote tag; refusing to send")
    return tag + blob + tag


def sql_text(value: str) -> str:
    """A plain single-quoted SQL literal, doubling any quote inside it."""
    return "'" + str(value).replace("'", "''") + "'"


def read_rows(path: str):
    if path.lower().endswith(".json"):
        data = json.load(open(path, encoding="utf-8-sig"))
        if not isinstance(data, list):
            # Some APIs wrap the array; take the first list-valued key.
            data = next((v for v in data.values() if isinstance(v, list)), None)
            if data is None:
                raise SystemExit("JSON file has no array of rows in it")
        return data
    # utf-8-sig: exports from web apps routinely carry a BOM, which otherwise becomes
    # part of the first column name and makes that column silently unmatchable.
    with open(path, newline="", encoding="utf-8-sig") as f:
        return [{k: v for k, v in row.items() if k} for row in csv.DictReader(f)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file", help="CSV or JSON export from Lit Alerts")
    ap.add_argument("--chunk", type=int, default=400, help="rows per statement (default 400)")
    ap.add_argument("--label", default=None, help="what to record as the source of this batch")
    ap.add_argument("--dry-run", action="store_true", help="parse and report, send nothing")
    args = ap.parse_args()

    rows = read_rows(args.file)
    if not rows:
        raise SystemExit("no rows found in that file")

    headers = list(rows[0].keys())
    print(f"{len(rows)} rows, {len(headers)} columns")
    print("columns:", ", ".join(headers))

    if args.dry_run:
        print("\n--dry-run: nothing sent. First row as it would be posted:")
        print(json.dumps(rows[0], indent=1, ensure_ascii=False)[:900])
        return

    label = args.label or os.path.basename(args.file)
    opened = run_sql(f"select public.feed_batch_open({sql_text(label)}) as id;")
    batch = opened["rows"][0]["id"]
    print(f"batch {batch} opened ({label})")

    sent = 0
    for i in range(0, len(rows), args.chunk):
        chunk = rows[i:i + args.chunk]
        res = run_sql(
            "select public.litalerts_import("
            f"{sql_literal(chunk)}::jsonb, null, {batch}) as r;")
        got = res["rows"][0]["r"]
        sent += got["rows_imported"]
        print(f"  chunk {i // args.chunk + 1}: +{got['rows_imported']} (total {sent})")

    closed = run_sql(f"select public.feed_batch_close({batch}) as r;")["rows"][0]["r"]
    print("\n", json.dumps(closed, indent=1))
    print(f"\nreview:   select * from v_feed_coverage;")
    print(f"unmatched: select * from v_feed_unmatched_retailers;")
    print(f"undo:      select feed_batch_discard({batch});")


if __name__ == "__main__":
    main()
