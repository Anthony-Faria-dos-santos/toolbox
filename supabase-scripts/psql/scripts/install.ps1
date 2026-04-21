# =====================================================================
# install.ps1  — Lance sql/01_install.sql sur le service pg choisi.
# Usage : .\psql\scripts\install.ps1 [service]
#   service : nom défini dans pg_service.conf (défaut: supabase-prod)
# =====================================================================
param(
  [string]$Service = 'supabase-prod'
)

$ErrorActionPreference = 'Stop'

# Résoudre le chemin du script SQL relativement à ce fichier
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SqlFile   = Join-Path $ScriptDir '..\..\sql\01_install.sql' | Resolve-Path

Write-Host "[install] service=$Service  file=$SqlFile" -ForegroundColor Cyan
psql "service=$Service" -v ON_ERROR_STOP=1 -f $SqlFile

if ($LASTEXITCODE -eq 0) {
  Write-Host "[install] OK" -ForegroundColor Green
} else {
  Write-Host "[install] FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
  exit $LASTEXITCODE
}
