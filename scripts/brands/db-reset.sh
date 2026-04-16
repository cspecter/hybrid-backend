#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd supabase
load_brand_env "${1:-}"

sync_backend_env

cd "${BACKEND_DIR}"
supabase db reset
"${SCRIPT_DIR}/seed.sh" "${BRAND}" local

echo "✅ Reset local shared schema and applied '${BRAND}' seed"
