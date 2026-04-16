#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd supabase
load_brand_env "${1:-}"
require_env SUPABASE_PROJECT_REF
require_env SUPABASE_DB_PASSWORD

sync_backend_env

cd "${BACKEND_DIR}"
supabase link --project-ref "${SUPABASE_PROJECT_REF}" --password "${SUPABASE_DB_PASSWORD}"
supabase db push

echo "✅ Pushed shared migrations to brand '${BRAND}'"
