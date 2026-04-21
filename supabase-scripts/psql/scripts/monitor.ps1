# =====================================================================
# monitor.ps1  — Lance sql/03_monitoring.sql (read-only).
# Usage : .\psql\scripts\monitor.ps1 [service]
# =====================================================================
param(
  [string]$Service = 'supabase-prod'
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SqlFile   = Join-Path $ScriptDir '..\..\sql\03_monitoring.sql' | Resolve-Path

Write-Host "[monitor] service=$Service" -ForegroundColor Cyan
psql "service=$Service" -f $SqlFile
