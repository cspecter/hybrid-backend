This folder contains archived one-time data backfills and repair SQL that were originally embedded in the active migration chain for the legacy Hybrid backend.

Rules:
- `backend/supabase/migrations` is the active shared migration chain for all backends.
- Files in this folder are not part of automatic bootstrap or `supabase db push`.
- Use these only for manual remediation of the legacy Hybrid database when a historical repair needs to be replayed intentionally.

Why this exists:
- Fresh backend bootstrap must be schema-safe and idempotent.
- Historical Hybrid-only data fixes should not run automatically against new brand databases.
- The archived SQL remains available for auditability and manual execution.
