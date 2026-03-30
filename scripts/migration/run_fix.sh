#!/bin/bash
# ============================================================================
# FIX RELATIONSHIPS SCRIPT
# Run this to fix missing relationships in the new database
# ============================================================================

set -e

# Disable GSSAPI negotiation (required for Supabase pooler)
export PGGSSENCMODE=disable

# Configuration
NEW_DB_HOST="aws-0-us-west-2.pooler.supabase.com"
NEW_DB_USER="postgres.ujmisqstpmowanvivtcr"
NEW_DB_PASSWORD="HYBRIDisCANNABIS"
NEW_DB_PORT="5432"
DB_NAME="postgres"

echo "============================================"
echo "Running Relationship Fix Migration..."
echo "============================================"

PGPASSWORD=$NEW_DB_PASSWORD psql \
    -h $NEW_DB_HOST \
    -p $NEW_DB_PORT \
    -U $NEW_DB_USER \
    -d $DB_NAME \
    -f scripts/migration/05_fix_relationships.sql

echo ""
echo "Done!"
