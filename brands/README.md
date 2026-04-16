# Brands

Each brand folder represents one deployed Supabase backend instance that reuses the shared backend codebase in `../supabase`.

## Files

- `.env.example`
  Template for brand-specific deployment configuration.
- `.env`
  Real brand secrets and project identifiers. Not committed.
- `seed.sql`
  Brand-specific data applied after the shared schema is loaded.

## Add a new backend

1. Copy `hybrid/` to a new folder, for example `brandx/`.
2. Fill in `brandx/.env` from `brandx/.env.example`.
3. Update `brandx/seed.sql` with any brand-specific rows or config values.
4. Use the scripts in `../scripts/brands/` with the new brand name.

## Design constraint

Brand seeds should contain configuration and data only.

Do not put schema changes here. All schema changes belong in `../supabase/migrations`.
