#!/usr/bin/env bash
# =====================================================================
# test.sh  — Lance sql/02_test_forced.sql (test forcé pg_cron, 60-120s).
# Usage : ./psql/scripts/test.sh [service]
# =====================================================================
set -euo pipefail

SERVICE="${1:-supabase-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/../../sql/02_test_forced.sql"

echo "[test] service=${SERVICE}  file=${SQL_FILE}"
echo "[test] Attente 60-120s selon l'instant de lancement..."
psql "service=${SERVICE}" -v ON_ERROR_STOP=1 -f "${SQL_FILE}"
echo "[test] OK — vérifier la sortie ci-dessus pour 'SUCCES'"
