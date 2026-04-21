# =====================================================================
# teardown.ps1  — Lance sql/99_teardown.sql (DESTRUCTIF).
# Demande une confirmation avant exécution.
# Usage : .\psql\scripts\teardown.ps1 [service] [-Force]
# =====================================================================
param(
  [string]$Service = 'supabase-prod',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SqlFile   = Join-Path $ScriptDir '..\..\sql\99_teardown.sql' | Resolve-Path

Write-Host "[teardown] service=$Service" -ForegroundColor Yellow
Write-Host "           file=$SqlFile" -ForegroundColor Yellow
Write-Host "           DESTRUCTIF : supprime job pg_cron + fonction + table" -ForegroundColor Red

if (-not $Force) {
  $resp = Read-Host "Taper 'teardown' pour confirmer"
  if ($resp -ne 'teardown') {
    Write-Host "[teardown] Annulé" -ForegroundColor Cyan
    exit 1
  }
}

psql "service=$Service" -v ON_ERROR_STOP=1 -f $SqlFile

if ($LASTEXITCODE -eq 0) {
  Write-Host "[teardown] OK" -ForegroundColor Green
} else {
  Write-Host "[teardown] FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
  exit $LASTEXITCODE
}
