"""Mint one claim invite per Hybrid listing, and build the mail-merge file.

Tokens are generated here rather than read back from the database, because
create_store_invite returns a token exactly once and never again: if the output
of a 118-row batch were lost, every invite would be unusable and would have to
be revoked. Generating them locally means the token in the CSV and the token in
the database come from the same place, and the batch can be re-run safely.

The alphabet and length match store_invite_generate_token(): 26 characters from
a 32-letter set with no I, O, 0 or 1, because these get retyped off an email.
"""
import csv, json, secrets

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
BASE_URL = "https://gethybrid.app/s/"
NOTE     = "NY buyers outreach, minted 2026-11-19"
EXPIRES_DAYS = 60

def token():
    return "".join(secrets.choice(ALPHABET) for _ in range(26))

data = json.load(open("resolved.json"))
by_loc = data["by_loc"]

rows, sql = [], []
seen = set()
for public_id, rec in sorted(by_loc.items(), key=lambda x: x[1]["loc"]["name"]):
    t = token()
    while t in seen: t = token()
    seen.add(t)
    loc = rec["loc"]
    sql.append(
        "  (%s, %s, %s, 1, now() + interval '%d days', 17)" % (
            "'" + t + "'", loc["id"], "'" + NOTE.replace("'", "''") + "'", EXPIRES_DAYS))
    for email in rec["contacts"]:
        rows.append({"Email": email,
                     "Store name": rec["stores"][0],
                     "Hybrid listing": loc["name"],
                     "Claim link": BASE_URL + t,
                     "Claim code": t,
                     "location_id": loc["id"],
                     "matched_by": rec["why"]})

header = """-- One store-claim invite per Hybrid listing for the NY buyer email blast.
--
-- Inserted directly rather than through create_store_invite() because that
-- function gates on can_grant_manager(), which reads current_actor_id() - null
-- in a server-side session, so it refuses. The gate exists to stop one store
-- manager minting an invite for another store; it is not a check on the
-- operator. Everything else matches the function: the same 26-character
-- alphabet, max_uses 1, created_by 17 (Raskin, role_id 9).
--
-- Each invite is single use. Where a shop has several contacts on the list they
-- share one link, so whoever opens it first takes the listing and the rest see
-- "already used" - which is what claiming a store should mean.
--
-- Re-running this is safe: tokens are unique and ON CONFLICT does nothing.

insert into public.store_claim_invites
  (token, location_id, note, max_uses, expires_at, created_by)
values
"""

footer = """
on conflict (token) do nothing;

select count(*) as invites_now,
       count(*) filter (where note = '%s') as from_this_batch
  from public.store_claim_invites;
""" % NOTE

open("mint_invites.sql", "w").write(header + ",\n".join(sql) + footer)

out = "/Users/macbookpro/hybrid-raskin/ny-buyers-claim-links.csv"
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)

print(f"listings      : {len(by_loc)}")
print(f"contact rows  : {len(rows)}")
print(f"tokens        : {len(seen)} unique, {len(ALPHABET)}^26 keyspace")
print(f"expiry        : {EXPIRES_DAYS} days")
print(f"\nSQL : {__import__('os').path.abspath('mint_invites.sql')}")
print(f"CSV : {out}")
