# Lit Alerts feed import

Loads menu listings from the Lit Alerts subscription into staging.

```bash
scripts/litalerts/import_csv.py export.csv --dry-run   # parse and report, send nothing
scripts/litalerts/import_csv.py export.csv             # load it
```

Takes CSV or JSON. Column names are matched server-side by `feed_pick`, which flattens
case, spaces and underscores and tries several spellings per field, so `Product Name`,
`product_name` and `PRODUCT NAME` all land in the same column. The whole original row is
kept in `menu_items_raw.raw`, so a header nobody guessed is a re-parse, not a re-export.

## After an import

```sql
select * from v_feed_coverage;              -- rows, retailers, how many we could place
select * from v_feed_unmatched_retailers;   -- stores the feed names that we could not
select feed_batch_discard(<batch_id>);      -- undo one import, entirely
```

`v_feed_unmatched_retailers` is the useful one on day one: each row is either a
dispensary missing from `locations`, or the same shop spelled differently on the two
sides. Retailers that do match carry their OCM licence number through from the register
sync, so a listing can be traced to a licensed store.

## Two things this deliberately does not do

**It does not touch `products`.** Rows land in `menu_items_raw` and stop there.
Publishing is a separate, reviewed step — and it is blocked on a licence question, not
on code: a market-intelligence subscription is normally licensed for internal analysis,
while Hybrid would be republishing to users. Ask Lit Alerts before promoting anything.

**It does not automate the Lit Alerts web app.** Their listing view caps at 10,000 rows;
the full NY + NJ feed is much larger. API access is included in the subscription, so the
cap is something to ask them about rather than engineer around. This script takes a file
you exported or one their API returned.

## Full coverage

The UI export will not give it — ask for API credentials, or a one-off bulk drop for
backfill. Point this script at the resulting JSON and it works unchanged.
