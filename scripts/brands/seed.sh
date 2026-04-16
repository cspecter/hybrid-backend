#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd psql
load_brand_env "${1:-}"

TARGET="${2:-local}"
SHARED_SEED_FILE="${SUPABASE_DIR}/seed.sql"

if [ ! -f "${SHARED_SEED_FILE}" ]; then
  echo "error: missing shared seed file: ${SHARED_SEED_FILE}" >&2
  exit 1
fi

if [ ! -f "${BRAND_SEED_FILE}" ]; then
  echo "error: missing brand seed file: ${BRAND_SEED_FILE}" >&2
  exit 1
fi

case "${TARGET}" in
  local)
    DATABASE_URL="${LOCAL_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
    ;;
  remote)
    require_env SUPABASE_DB_URL
    DATABASE_URL="${SUPABASE_DB_URL}"
    ;;
  *)
    echo "error: target must be 'local' or 'remote'" >&2
    exit 1
    ;;
esac

psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${SHARED_SEED_FILE}"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${BRAND_SEED_FILE}"

echo "✅ Applied shared and '${BRAND}' seed data to ${TARGET} database"
