# Outreach email agent

Onboarding and engagement email for Hybrid. Runs on Supabase Edge Functions on a
pg_cron schedule, writes with the Anthropic API, and sends through one Gmail
mailbox.

**It ships in draft mode with a placeholder allowlist and a placeholder mailing
address, so out of the box it sends nothing to anybody.** Three things have to
change before it can — see [Before you switch to send mode](#before-you-switch-to-send-mode).

---

## What's here

| Piece | Where |
| --- | --- |
| Tables, RLS, admin RPCs | `supabase/migrations/20260920000007_outreach_agent.sql` |
| Knowledge document seed | `supabase/migrations/20260920000008_outreach_knowledge_seed.sql` |
| Live-data content functions | `supabase/migrations/20260920000009_outreach_content_functions.sql` |
| Cron jobs | `supabase/migrations/20260920000011_outreach_cron.sql` |
| Config — every constant | `supabase/functions/_shared/outreach/config.ts` |
| Hard rules for every generation | `supabase/functions/_shared/outreach/guardrails.ts` |
| Scheduler | `supabase/functions/outreach-send/` |
| Reply handling | `supabase/functions/outreach-replies/` |
| CSV import | `supabase/functions/outreach-import/` |
| Public unsubscribe | `supabase/functions/outreach-unsubscribe/` |
| Admin dashboard | `hybrid-raskin` → `lib/outreach.js`, `app/admin-dashboard.jsx` |

---

## Secrets

Five. None of them appear in a function body, a migration, a table or a log line;
all five are read from `Deno.env` at the point of use.

| Name | What it is |
| --- | --- |
| `ANTHROPIC_API_KEY` | Anthropic API key, for writing and for reply triage |
| `GMAIL_CLIENT_ID` | OAuth client id for the mailbox |
| `GMAIL_CLIENT_SECRET` | OAuth client secret |
| `GMAIL_REFRESH_TOKEN` | Refresh token for that one mailbox |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are already set by the platform.

### Setting them

Put them in a file rather than on the command line, so they do not land in your
shell history:

```bash
cat > /tmp/outreach.env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-...
GMAIL_CLIENT_ID=...apps.googleusercontent.com
GMAIL_CLIENT_SECRET=GOCSPX-...
GMAIL_REFRESH_TOKEN=1//0...
EOF
```

```bash
supabase secrets set --env-file /tmp/outreach.env --project-ref ujmisqstpmowanvivtcr && rm /tmp/outreach.env
```

Check the names landed (values come back hashed, never in the clear):

```bash
supabase secrets list --project-ref ujmisqstpmowanvivtcr
```

---

## Gmail OAuth: creating the credentials and the refresh token

Do this once, signed in as the account that owns the mailbox the agent will send
from. A dedicated mailbox is better than a person's — the From address is what
recipients reply to.

### 1. A Google Cloud project with the Gmail API on

1. <https://console.cloud.google.com/> → create a project (or pick one).
2. **APIs & Services → Library** → search **Gmail API** → **Enable**.

### 2. OAuth consent screen

1. **APIs & Services → OAuth consent screen**.
2. **Internal** if the mailbox is on a Google Workspace domain you control —
   nothing further is needed. **External** otherwise, and then under **Test
   users** add the mailbox address itself.
3. App name, support email, developer email. Nothing else matters here.
4. **Scopes** → add exactly one:

   ```
   https://www.googleapis.com/auth/gmail.modify
   ```

   That single scope covers everything the agent does: read replies, create
   drafts, send, and add labels. It cannot permanently delete anything.

> **External + Testing publishing status expires refresh tokens after 7 days.**
> If the mailbox is not on a Workspace domain, either publish the app
> (**Publish app** on the consent screen) or expect to re-mint the token weekly.
> This is a Google policy, not a limit of this agent.

### 3. OAuth client

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. Application type **Web application**.
3. Under **Authorised redirect URIs** add:

   ```
   https://developers.google.com/oauthplayground
   ```

4. Create. Copy the **client ID** and **client secret** — these are
   `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET`.

### 4. The refresh token

1. Open <https://developers.google.com/oauthplayground>.
2. Gear icon, top right → tick **Use your own OAuth credentials** → paste the
   client ID and secret.
3. Left panel, **Step 1**: paste `https://www.googleapis.com/auth/gmail.modify`
   into the "Input your own scopes" box → **Authorize APIs**.
4. Sign in **as the mailbox account** and accept. (An "unverified app" warning is
   expected while the consent screen is in Testing — **Advanced → Go to …**.)
5. **Step 2** → **Exchange authorization code for tokens**.
6. Copy the **Refresh token** — that is `GMAIL_REFRESH_TOKEN`.

If the refresh token comes back empty, the account has consented before: revoke
at <https://myaccount.google.com/permissions> and repeat step 4.

#### Without the playground

```bash
open "https://accounts.google.com/o/oauth2/v2/auth?client_id=YOUR_CLIENT_ID&redirect_uri=https%3A//developers.google.com/oauthplayground&response_type=code&scope=https%3A//www.googleapis.com/auth/gmail.modify&access_type=offline&prompt=consent"
```

Then exchange the `code` from the redirect URL:

```bash
curl -s -X POST https://oauth2.googleapis.com/token -d client_id=YOUR_CLIENT_ID -d client_secret=YOUR_CLIENT_SECRET -d code=THE_CODE -d grant_type=authorization_code -d redirect_uri=https://developers.google.com/oauthplayground
```

`access_type=offline` and `prompt=consent` are what make a refresh token come
back. Without both you get an access token that dies in an hour.

---

## Letting cron reach the functions

The two scheduled jobs call the Edge Functions over HTTP, which needs a URL and a
bearer token. Both live in Supabase Vault, not in a migration and not in a table
this project owns. Until they are set, `outreach_invoke()` logs a notice and
returns — nothing fails and nothing sends.

Run once, in the SQL editor:

```sql
select vault.create_secret('https://ujmisqstpmowanvivtcr.supabase.co/functions/v1', 'outreach_functions_base_url');
```

and, with your project's service-role key in place of the placeholder:

```sql
select vault.create_secret('PASTE_SERVICE_ROLE_KEY_HERE', 'outreach_invoke_token');
```

> pg_net briefly stores each pending request — Authorization header included — in
> `net.http_request_queue`, then deletes the row once dispatched. `anon` and
> `authenticated` hold no privilege on that table. This is inherent to pg_net.

### The schedule

| Job | Schedule | What it does |
| --- | --- | --- |
| `outreach_send` | `*/15 12-23 * * 1-5` | One sending tick. The function re-checks the real local hour, so the loose UTC range costs a no-op, never an out-of-hours email. |
| `outreach_replies` | `*/15 * * * *` | Polls for replies. Runs around the clock: an unsubscribe at 3am is honoured at 3am. |

---

## Loading contacts

CSV, through the import function. Header row required; column order does not
matter; names are case-insensitive.

| Column | Required | Notes |
| --- | --- | --- |
| `email` | yes | |
| `segment` | yes | `consumer`, `creator`, `brand` or `dispensary` |
| `consent_basis` | **yes** | Why we may email them, in words. A row without one is rejected. |
| `name` | no | |
| `profile_id` | no | Numeric `profiles.id` if they already have an account |
| `source` | no | Where the list came from |
| `notes` | no | |

```bash
curl -X POST "https://ujmisqstpmowanvivtcr.supabase.co/functions/v1/outreach-import?dry_run=1" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "Content-Type: text/csv" --data-binary @contacts.csv
```

Drop `?dry_run=1` to write. The response reports every rejection with its line
number and reason. Rows are rejected for: no consent basis, a malformed address, an
unknown segment, a `profile_id` that does not exist, a duplicate inside the file,
an address already loaded, and an address on the suppression list.

### About `profile_id`

Setting it links the contact to a live account, and the digests and nudges then
read that account's real state. Leave it blank and they are treated as a prospect:
they get the welcome and the getting-started sequence, and no updates, because
there is nothing to report on.

**Brands and dispensaries.** A brand profile has no login — people are given admin
access to it through `profile_admins`. So a brand or dispensary contact is a
person, and `profile_id` may be either that person's profile (the agent resolves
every brand they administer) or the brand profile itself. Either works.

---

## Modes

Both switches are in `config.ts` and take effect on redeploy.

```ts
export const MODE: "draft" | "send" = "draft";
export const TEST_RECIPIENTS: string[] = ["REPLACE-ME@example.com"];
```

- **draft** (default) — everything is written to the Gmail **Drafts** folder and
  logged. Replies are drafted too and the thread is labelled; nothing is sent.
- **send** — sends for real.
- **`TEST_RECIPIENTS`** — when non-empty, every send *and* every draft is
  restricted to those addresses, whatever `MODE` says. Empty the array to let the
  agent reach real contacts.

### Reading the copy before anyone else does

`?dry=1` composes for whoever is due and returns the text without creating a draft
and without moving anybody's cadence. It needs `ANTHROPIC_API_KEY` and no Gmail
credentials at all.

```bash
curl -s -X POST "https://ujmisqstpmowanvivtcr.supabase.co/functions/v1/outreach-send?dry=1" -H "Authorization: Bearer $SERVICE_ROLE_KEY" | python3 -m json.tool
```

---

## The knowledge document

Reply answers may draw on nothing else. It lives in the `outreach_knowledge`
table, one row per section, body in markdown — edit it in the Supabase table
editor, no deploy needed. Adding a section: insert a row with a new `slug`.

If a question is not covered, the agent replies with `ESCALATE` internally and the
thread is labelled for a person instead. Widening what it will answer means adding
to this table, and nothing else.

---

## Pausing

Admin dashboard → **Email Agent** → **Pause**. It stops the cron scheduler before
any outbound call, so a paused agent sends nothing and answers nothing. Or:

```sql
update public.outreach_settings set is_paused = true where id = 1;
```

---

## Before you switch to send mode

1. **Replace `PHYSICAL_MAILING_ADDRESS`** in `config.ts`. It is a placeholder, and
   the agent refuses to compose anything at all while it still says PLACEHOLDER —
   CAN-SPAM requires a real postal address in every commercial email.
2. **Replace or empty `TEST_RECIPIENTS`.** While it holds
   `REPLACE-ME@example.com`, every contact is skipped.
3. **Set the four secrets** and the two Vault values.
4. Run `?dry=1` and read what each segment's email actually says.
5. Run a real tick in draft mode against your own address and look at the drafts.
6. Then set `MODE = "send"`, empty `TEST_RECIPIENTS`, and redeploy.

```bash
supabase functions deploy outreach-send outreach-replies outreach-import --project-ref ujmisqstpmowanvivtcr
```

```bash
supabase functions deploy outreach-unsubscribe --no-verify-jwt --project-ref ujmisqstpmowanvivtcr
```

`outreach-unsubscribe` **must** keep `--no-verify-jwt`: the person clicking the
link is reading email, not signed in.
