#!/bin/bash
# ============================================================================
# Set secrets for sync Edge Function
# Run on OLD Supabase project
# ============================================================================

# Replace these with your actual values
NEW_SUPABASE_URL="https://your-new-project.supabase.co"
NEW_SUPABASE_SERVICE_ROLE_KEY="your-new-service-role-key"

echo "Setting secrets for sync-to-new-db Edge Function..."

supabase secrets set \
    NEW_SUPABASE_URL="$NEW_SUPABASE_URL" \
    NEW_SUPABASE_SERVICE_ROLE_KEY="$NEW_SUPABASE_SERVICE_ROLE_KEY"

echo "Secrets set successfully!"
echo ""
echo "Deploy the function with:"
echo "  supabase functions deploy sync-to-new-db"
