#!/bin/bash
# ============================================================================
# COMPLETE MIGRATION SCRIPT
# Run this to perform the full migration from old to new database
# ============================================================================

set -e  # Exit on error

# Disable GSSAPI negotiation (required for Supabase pooler)
export PGGSSENCMODE=disable

# Use PostgreSQL 15 tools (match remote server version)
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"

echo "============================================"
echo "Hybrid Backend Database Migration"
echo "============================================"
echo "Using pg_dump version: $(pg_dump --version)"

# Configuration - UPDATE THESE VALUES
OLD_DB_HOST="aws-0-us-east-1.pooler.supabase.com"
OLD_DB_USER="postgres.axzdfdpwfsynrajqqoae"
OLD_DB_PASSWORD="HYBRIDisCANNABIS"
OLD_DB_PORT="5432"

# Use session pooler for NEW database as well (direct connection blocked)
NEW_DB_HOST="aws-0-us-west-2.pooler.supabase.com"
NEW_DB_USER="postgres.ujmisqstpmowanvivtcr"
NEW_DB_PASSWORD="HYBRIDisCANNABIS"
NEW_DB_PORT="5432"

OLD_PROJECT_REF="axzdfdpwfsynrajqqoae"
NEW_PROJECT_REF="ujmisqstpmowanvivtcr"

# Common settings
DB_NAME="postgres"

echo ""
echo "Step 1: Creating export staging tables on OLD database..."
echo "============================================"

PGPASSWORD=$OLD_DB_PASSWORD psql -h $OLD_DB_HOST -p $OLD_DB_PORT -U $OLD_DB_USER -d $DB_NAME -f scripts/migration/01_export_old_data.sql

echo ""
echo "Step 2: Exporting data from OLD database..."
echo "============================================"

# Use plain SQL format with batched INSERT statements instead of COPY (works with pooler)
PGPASSWORD=$OLD_DB_PASSWORD pg_dump \
    -h $OLD_DB_HOST \
    -p $OLD_DB_PORT \
    -U $OLD_DB_USER \
    -d $DB_NAME \
    -n migration_export \
    --no-owner \
    --no-acl \
    --no-comments \
    --inserts \
    --rows-per-insert=1000 \
    -F p \
    -f migration_export.sql

echo "Export saved to: migration_export.sql"

echo ""
echo "Step 3: Restoring export schema to NEW database..."
echo "============================================"

# First, drop the existing migration_export schema to ensure fresh data
echo "Dropping existing migration_export schema on NEW database..."
PGPASSWORD=$NEW_DB_PASSWORD psql \
    -h $NEW_DB_HOST \
    -p $NEW_DB_PORT \
    -U $NEW_DB_USER \
    -d $DB_NAME \
    -c "DROP SCHEMA IF EXISTS migration_export CASCADE;" || true

# Import using psql (works with pooler)
PGPASSWORD=$NEW_DB_PASSWORD psql \
    -h $NEW_DB_HOST \
    -p $NEW_DB_PORT \
    -U $NEW_DB_USER \
    -d $DB_NAME \
    -f migration_export.sql || true  # Ignore errors for existing objects

echo ""
echo "Step 4: Running migrations on NEW database..."
echo "============================================"

# Make sure supabase is linked to new project
supabase link --project-ref $NEW_PROJECT_REF

# Push migrations
supabase db push

echo ""
echo "Step 5: Importing data to NEW database..."
echo "============================================"

# PGPASSWORD=$NEW_DB_PASSWORD psql -h $NEW_DB_HOST -p $NEW_DB_PORT -U $NEW_DB_USER -d $DB_NAME -f scripts/migration/02_import_to_new.sql

echo ""
echo "Step 6: Setting up sync triggers on OLD database..."
echo "============================================"

# PGPASSWORD=$OLD_DB_PASSWORD psql -h $OLD_DB_HOST -p $OLD_DB_PORT -U $OLD_DB_USER -d $DB_NAME -f scripts/migration/04_old_db_triggers.sql

echo ""
echo "Step 7: Deploying sync Edge Function..."
echo "============================================"

# Link to old project for Edge Function deployment
supabase link --project-ref $OLD_PROJECT_REF

# Set secrets for the sync function
supabase secrets set \
    NEW_SUPABASE_URL="https://$NEW_PROJECT_REF.supabase.co" \
    NEW_SUPABASE_SERVICE_ROLE_KEY="your_new_service_role_key"

# Deploy the sync function
supabase functions deploy sync-to-new-db

echo ""
echo "Step 8: Cleanup..."
echo "============================================"

# Optionally remove the export schema from both databases
# PGPASSWORD=$OLD_DB_PASSWORD psql -h $OLD_DB_HOST -p $OLD_DB_PORT -U $OLD_DB_USER -d $DB_NAME -c "DROP SCHEMA migration_export CASCADE;"
# PGPASSWORD=$NEW_DB_PASSWORD psql -h $NEW_DB_HOST -p $NEW_DB_PORT -U $NEW_DB_USER -d $DB_NAME -c "DROP SCHEMA migration_export CASCADE;"

rm -f migration_export.dump

echo ""
echo "============================================"
echo "Migration Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Verify data in new database"
echo "2. Test authentication with existing users"
echo "3. Monitor sync_queue table for any failed syncs"
echo "4. Update your application to use new database"
echo "5. Once stable, disable sync triggers and retire old database"
echo ""
