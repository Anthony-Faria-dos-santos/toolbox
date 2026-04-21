#!/usr/bin/env bash
# =====================================================================
# monitor.sh  — Lance sql/03_monitoring.sql (read-only).
# Usage : ./psql/scripts/monitor.sh [service]
# =====================================================================
set -euo pipefail

SERVICE="${1:-supabase-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/../../sql/03_monitoring.sql"

echo "[monitor] service=${SERVICE}"
psql "service=${SERVICE}" -f "${SQL_FILE}"
