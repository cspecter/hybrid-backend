# Database Migration Guide

## Overview

This guide explains how to migrate data from your old Supabase database to the new database with the updated schema, and keep them in sync during the transition period.

## ⚠️ Major Schema Change: Integer Primary Keys

The new schema uses **INTEGER primary keys** instead of UUIDs for better performance:

- All tables now have `id INTEGER PRIMARY KEY` (auto-incrementing)
- Old UUID IDs are stored in `public_id UUID NOT NULL UNIQUE`
- External APIs should use `public_id` for references
- Internal database operations use `id` (integer) for faster joins

### Primary Key Pattern
```sql
-- Old schema
id UUID PRIMARY KEY DEFAULT gen_random_uuid()

-- New schema
id INTEGER PRIMARY KEY,  -- Auto-incrementing
public_id UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE
```

## Schema Changes Summary

### Table Renames
| Old Table | New Table |
|-----------|-----------|
| `users` | `profiles` |
| `dispensary_locations` | `locations` |
| `dispensary_employees` | `location_employees` |
| `products_products` | `related_products` |
| `products_brands` | `product_brands` |
| `deals_dispensary_locations` | `deals_locations` |
| `user_blocks` | `profile_blocks` |
| `user_brand_admins` | `profile_admins` |
| `posts_users` | `posts_profiles` |

### Column Renames
| Table | Old Column | New Column |
|-------|------------|------------|
| All tables | `date_created` | `created_at` |
| All tables | `date_updated` | `updated_at` |
| All tables | `fts_vector` | `fts` |
| profiles | `name` | `display_name` |
| profiles | `description` | `bio` |
| locations | `address1` | `address_line1` |
| locations | `address2` | `address_line2` |
| notifications | `read` | `is_read` |
| posts | `user_id` | `profile_id` |
| notifications | `user_id` | `profile_id` |

### New Columns
| Table | Column | Description |
|-------|--------|-------------|
| All tables | `public_id` | UUID for external API references (stores old UUID) |
| `profiles` | `auth_id` | Reference to `auth.users(id)` |
| `profiles` | `profile_type` | Enum: 'individual', 'brand' |
| `profiles` | `business_info` | JSONB for brand-specific data |
| `location_employees` | `role` | Enum: 'manager', 'employee' (replaces `is_admin` boolean) |

### Removed Tables
- `typesense_import_log`
- `g_ids`
- `sels`
- `files`

## Migration Steps

### Prerequisites

1. **Supabase CLI** installed: `brew install supabase/tap/supabase`
2. **psql** installed: `brew install postgresql`
3. **Both database passwords** available
4. **New database** with migrations applied: `supabase db reset --linked`

### Step 1: One-Time Data Migration

```bash
# 1. Set your database credentials
export OLD_DB_HOST="db.xxxxxxxxxx.supabase.co"
export OLD_DB_PASSWORD="your_old_password"
export NEW_DB_HOST="db.yyyyyyyyyy.supabase.co"
export NEW_DB_PASSWORD="your_new_password"

# 2. Run the export script on OLD database
# This creates integer IDs and stores UUID mappings
PGPASSWORD=$OLD_DB_PASSWORD psql -h $OLD_DB_HOST -U postgres -d postgres \
    -f scripts/migration/01_export_old_data.sql

# 3. Dump the export schema (includes UUID->INT mapping table)
PGPASSWORD=$OLD_DB_PASSWORD pg_dump -h $OLD_DB_HOST -U postgres -d postgres \
    -n migration_export -F c -f migration_export.dump

# 4. Restore to NEW database
PGPASSWORD=$NEW_DB_PASSWORD pg_restore -h $NEW_DB_HOST -U postgres -d postgres \
    -n migration_export --no-owner migration_export.dump

# 5. Run the import script on NEW database
# This uses the UUID->INT mapping to resolve foreign keys
PGPASSWORD=$NEW_DB_PASSWORD psql -h $NEW_DB_HOST -U postgres -d postgres \
    -f scripts/migration/02_import_to_new.sql
```

### How UUID to INT Mapping Works

1. **Export phase** (`01_export_old_data.sql`):
   - Generates sequential integer IDs using `ROW_NUMBER()`
   - Stores old UUIDs in `public_id` column
   - Creates `uuid_to_int_mapping` table for FK resolution

2. **Import phase** (`02_import_to_new.sql`):
   - Uses `migration_export.resolve_uuid()` function
   - Converts all UUID foreign keys to integers
   - Updates sequences to avoid conflicts

### Step 2: Verify Migration

```sql
-- Run on NEW database to verify counts match
SELECT 'profiles' as table_name, COUNT(*) FROM profiles
UNION ALL SELECT 'locations', COUNT(*) FROM locations
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'posts', COUNT(*) FROM posts;

-- Verify UUID mapping exists
SELECT table_name, COUNT(*) as mappings
FROM migration_export.uuid_to_int_mapping
GROUP BY table_name;

-- Verify public_id preservation
SELECT id, public_id, username FROM profiles LIMIT 5;
```

### Step 3: Set Up Ongoing Sync

Choose ONE of these options:

#### Option A: Trigger-Based Sync (Recommended)

This works on all Supabase tiers and handles UUID→INT conversion.

```bash
# 1. Install sync triggers on OLD database
# Creates sync_queue table and uuid_int_mapping cache
PGPASSWORD=$OLD_DB_PASSWORD psql -h $OLD_DB_HOST -U postgres -d postgres \
    -f scripts/migration/04_old_db_triggers.sql

# 2. Link supabase CLI to OLD project
supabase link --project-ref your-old-project-ref

# 3. Set secrets for sync function
supabase secrets set \
    NEW_SUPABASE_URL="https://your-new-project.supabase.co" \
    NEW_SUPABASE_SERVICE_ROLE_KEY="your-new-service-role-key"

# 4. Deploy sync Edge Function
supabase functions deploy sync-to-new-db
```

The sync Edge Function:
- Receives changes with UUID identifiers
- Looks up corresponding INT IDs via `public_id`
- Inserts/updates records with new INT foreign keys
- Caches UUID→INT mappings for performance

#### Option B: Logical Replication (Supabase Pro)

Requires Supabase Pro on the OLD database.

```sql
-- On OLD database, enable logical replication
CREATE PUBLICATION hybrid_migration FOR ALL TABLES;

-- On NEW database, create subscription
CREATE SUBSCRIPTION hybrid_sub 
    CONNECTION 'host=db.old-project.supabase.co dbname=postgres user=postgres password=xxx'
    PUBLICATION hybrid_migration;
```

#### Option C: Foreign Data Wrapper

Query old data directly from new database.

```sql
-- On NEW database
CREATE EXTENSION postgres_fdw;

CREATE SERVER old_db FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'db.old-project.supabase.co', dbname 'postgres');

CREATE USER MAPPING FOR postgres SERVER old_db
    OPTIONS (user 'postgres', password 'xxx');

IMPORT FOREIGN SCHEMA public FROM SERVER old_db INTO old_db;
```

## Auth Users Migration

The `auth.users` table is handled specially:

1. **Initial import**: Users and their encrypted passwords are copied, preserving auth IDs
2. **Ongoing sync**: New signups on OLD database are synced to NEW database
3. **Password changes**: Synced via the sync queue

> ⚠️ **Important**: Users can log in to EITHER database with the same credentials after migration.

## Monitoring Sync

Monitor the sync queue on the OLD database:

```sql
-- Check pending syncs
SELECT table_name, operation, COUNT(*) 
FROM sync_queue 
WHERE NOT synced 
GROUP BY table_name, operation;

-- Check failed syncs
SELECT * FROM sync_queue 
WHERE sync_attempts >= 5 AND NOT synced
ORDER BY created_at DESC;

-- Retry failed syncs
UPDATE sync_queue SET sync_attempts = 0 
WHERE sync_attempts >= 5 AND NOT synced;

-- Check UUID→INT mapping cache
SELECT table_name, COUNT(*) as cached_mappings
FROM uuid_int_mapping
GROUP BY table_name;
```

## API Considerations

With the new integer PK schema, update your API code:

```typescript
// OLD: Direct UUID usage
const { data } = await supabase
  .from('profiles')
  .select('*')
  .eq('id', userId);  // userId was UUID

// NEW: Use public_id for external references
const { data } = await supabase
  .from('profiles')
  .select('*')
  .eq('public_id', userId);  // userId is still UUID from client

// For internal joins, use integer id (more efficient)
const { data } = await supabase
  .from('posts')
  .select('*, profiles!inner(*)')
  .eq('profiles.id', profileIntId);  // Use integer for joins
```

## Cutover Checklist

When ready to switch to the new database:

1. [ ] Verify all data is synced
2. [ ] Update application environment variables
3. [ ] Test authentication on new database
4. [ ] Test all CRUD operations
5. [ ] Monitor for errors
6. [ ] Disable sync triggers on old database
7. [ ] Keep old database as backup for 30 days
8. [ ] Delete old database

## Rollback Plan

If issues occur:

1. Disable writes to new database
2. Re-enable old database as primary
3. Reverse the sync direction (create triggers on NEW db)
4. Investigate and fix issues
5. Retry migration

## Support

For issues:
- Check sync_queue error_message column
- Review Edge Function logs: `supabase functions logs sync-to-new-db`
- Compare row counts between databases
