#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd supabase
load_brand_env "${1:-}"
require_env SUPABASE_PROJECT_REF

sync_backend_env

declare -a SECRET_ARGS=()

add_secret() {
  local name="$1"
  local value="${!name:-}"
  if [ -n "${value}" ]; then
    SECRET_ARGS+=("${name}=${value}")
  fi
}

add_secret ONESIGNAL_APP_ID
add_secret ONESIGNAL_REST_API_KEY
add_secret MAILGUN_DOMAIN
add_secret MAILGUN_API_KEY
add_secret MAILGUN_FROM_EMAIL
add_secret MAILGUN_FROM_NAME

if [ "${#SECRET_ARGS[@]}" -eq 0 ]; then
  echo "error: no secrets configured for brand '${BRAND}'" >&2
  exit 1
fi

cd "${BACKEND_DIR}"
supabase secrets set --project-ref "${SUPABASE_PROJECT_REF}" "${SECRET_ARGS[@]}"

echo "✅ Set ${#SECRET_ARGS[@]} function secret(s) for brand '${BRAND}'"
