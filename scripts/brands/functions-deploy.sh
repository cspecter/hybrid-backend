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

mapfile -t FUNCTIONS < <(find "${SUPABASE_DIR}/functions" -mindepth 1 -maxdepth 1 -type d | sort)

for function_dir in "${FUNCTIONS[@]}"; do
  function_name="$(basename "${function_dir}")"
  if [[ "${function_name}" == _* ]] || [[ "${function_name}" == .* ]]; then
    continue
  fi

  echo "note: deploying function '${function_name}' to '${BRAND}'"
  supabase functions deploy "${function_name}" --project-ref "${SUPABASE_PROJECT_REF}"
done

echo "✅ Deployed shared functions to brand '${BRAND}'"
