#!/usr/bin/env bash
# =====================================================================
# teardown.sh  — Lance sql/99_teardown.sql (DESTRUCTIF).
# Usage : ./psql/scripts/teardown.sh [service] [--force]
# =====================================================================
set -euo pipefail

SERVICE="${1:-supabase-prod}"
FORCE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/../../sql/99_teardown.sql"

echo "[teardown] service=${SERVICE}"
echo "           file=${SQL_FILE}"
echo "           DESTRUCTIF : supprime job pg_cron + fonction + table"

if [[ "${FORCE}" != "--force" ]]; then
  read -r -p "Taper 'teardown' pour confirmer : " resp
  if [[ "${resp}" != "teardown" ]]; then
    echo "[teardown] Annulé"
    exit 1
  fi
fi

psql "service=${SERVICE}" -v ON_ERROR_STOP=1 -f "${SQL_FILE}"
echo "[teardown] OK"
