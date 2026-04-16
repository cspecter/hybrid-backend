#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BRANDS_DIR="${BACKEND_DIR}/brands"
SUPABASE_DIR="${BACKEND_DIR}/supabase"

usage() {
  echo "Usage: $0 <brand>" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "error: missing required env var: ${name}" >&2
    exit 1
  fi
}

load_brand_env() {
  local brand="${1:-}"
  if [ -z "${brand}" ]; then
    usage
  fi

  BRAND="${brand}"
  BRAND_DIR="${BRANDS_DIR}/${BRAND}"
  BRAND_ENV_FILE="${BRAND_DIR}/.env"
  BRAND_ENV_EXAMPLE="${BRAND_DIR}/.env.example"
  BRAND_SEED_FILE="${BRAND_DIR}/seed.sql"

  if [ ! -d "${BRAND_DIR}" ]; then
    echo "error: unknown brand '${BRAND}'" >&2
    exit 1
  fi

  if [ ! -f "${BRAND_ENV_FILE}" ]; then
    echo "error: missing ${BRAND_ENV_FILE}" >&2
    echo "note: copy ${BRAND_ENV_EXAMPLE} to ${BRAND_ENV_FILE} and fill in real values" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "${BRAND_ENV_FILE}"
  set +a
}

sync_backend_env() {
  local target="${BACKEND_DIR}/.env"
  cp "${BRAND_ENV_FILE}" "${target}"
  echo "note: synced ${BRAND_ENV_FILE} -> ${target}"
}
