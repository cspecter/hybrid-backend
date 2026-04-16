# Backend

This directory is the single source of truth for all Supabase backends that share the Hybrid app schema and Edge Functions.

## Structure

- `supabase/`
  Shared schema, migrations, and Edge Functions for every backend.
- `brands/<brand>/`
  Brand-specific environment and seed files.
- `scripts/brands/`
  Operational wrappers for linking, pushing, resetting, seeding, and setting secrets per brand.

## Rule

Do not copy `supabase/migrations` or `supabase/functions` per brand.

Every new backend should:

1. Create a new Supabase project.
2. Add a new `brands/<brand>/` folder.
3. Reuse the same shared migrations and functions.
4. Store only brand-specific differences in brand env files and seed SQL.

## Current brands

- `hybrid`
- `prayertoday`

## Common workflow

```bash
cd backend

# Link the local CLI context to a specific remote backend
./scripts/brands/link.sh hybrid

# Push shared schema changes to that backend
./scripts/brands/db-push.sh hybrid

# Deploy shared functions to that backend
./scripts/brands/functions-deploy.sh hybrid

# Apply brand-specific seed/config data
./scripts/brands/seed.sh hybrid remote

# Set secrets for that backend
./scripts/brands/set-secrets.sh hybrid
```

## Local reset workflow

```bash
cd backend
./scripts/brands/db-reset.sh hybrid
```

This runs the shared local schema reset and then applies the brand seed locally.
