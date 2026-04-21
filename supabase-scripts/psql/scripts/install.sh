#!/usr/bin/env bash
# =====================================================================
# install.sh  — Lance sql/01_install.sql sur le service pg choisi.
# Usage : ./psql/scripts/install.sh [service]
#   service : nom défini dans pg_service.conf (défaut: supabase-prod)
# =====================================================================
set -euo pipefail

SERVICE="${1:-supabase-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/../../sql/01_install.sql"

echo "[install] service=${SERVICE}  file=${SQL_FILE}"
psql "service=${SERVICE}" -v ON_ERROR_STOP=1 -f "${SQL_FILE}"
echo "[install] OK"
