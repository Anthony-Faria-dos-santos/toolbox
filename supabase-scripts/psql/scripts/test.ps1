# =====================================================================
# test.ps1  — Lance sql/02_test_forced.sql (test forcé pg_cron).
# Durée : 60 à 120 secondes.
# Usage : .\psql\scripts\test.ps1 [service]
# =====================================================================
param(
  [string]$Service = 'supabase-prod'
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SqlFile   = Join-Path $ScriptDir '..\..\sql\02_test_forced.sql' | Resolve-Path

Write-Host "[test] service=$Service  file=$SqlFile" -ForegroundColor Cyan
Write-Host "[test] Attente 60-120s selon l'instant de lancement..." -ForegroundColor Yellow

psql "service=$Service" -v ON_ERROR_STOP=1 -f $SqlFile

if ($LASTEXITCODE -eq 0) {
  Write-Host "[test] OK — vérifier la sortie ci-dessus pour 'SUCCES'" -ForegroundColor Green
} else {
  Write-Host "[test] FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
  exit $LASTEXITCODE
}
