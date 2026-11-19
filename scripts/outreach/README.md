# Store claim invites for an outreach blast

`mint_store_claim_invites.py` turns a list of resolved Hybrid listings into one
single-use claim invite each, and writes two things: a SQL file to insert the
invites, and a CSV to mail-merge.

## Why the tokens are generated here and not by the database

`create_store_invite()` is the normal path and should be used for one-off
invites from the app. It is wrong for a batch of a hundred for two reasons.
It gates on `can_grant_manager()`, which reads `current_actor_id()` — null in a
server-side session, so it refuses. And it returns each token exactly once and
never again, by design: if the output of a large batch were lost, every invite
would be unusable and would have to be revoked one by one.

Generating the tokens in the script means the CSV and the database come from
the same place, and a re-run is safe. The alphabet and length match
`store_invite_generate_token()` exactly: 26 characters from a 32-letter set
with no I, O, 0 or 1, because these get retyped off a printed email.

## The output is credentials

Both output files contain live tokens. A token is control of a shop's page:
whoever opens the link and signs in becomes its manager. So:

- **Neither output file belongs in this repository.** It is public. The script
  writes them outside the repo for that reason, and `.gitignore` here is a
  second line of defence rather than the first.
- Treat the CSV like a password list while the campaign runs.
- If a batch leaks, revoke by note rather than hunting individual tokens:

      update public.store_claim_invites
         set revoked_at = now()
       where note = '<the batch note>' and uses = 0;

  That leaves already-claimed stores alone and kills everything unused.

## Matching is the dangerous step

A code sent to the wrong shop hands one business another's listing. Resolve
each contact to exactly one listing and mint nothing for the rest. An earlier
version of the matcher scored `The Flowery New York` against
`Stoops NYC New York` at 0.5 similarity because they share "New York"; strip
geographic words before comparing, and require a distinctive word in common.

Verify the whole batch after inserting, not a sample — every token in the CSV
should be found in the database, point at the listing the CSV names, and come
back `valid` from `resolve_store_invite()`.
