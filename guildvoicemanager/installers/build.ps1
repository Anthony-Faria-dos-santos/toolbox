# ============================================================
# build.ps1 — Genere les ZIPs d'installation versionnes (Windows + macOS)
#
# Usage :
#   .\installers\build.ps1                  # lit la version dans ..\VERSION
#   .\installers\build.ps1 -Version 3.2.0   # override ponctuel
#   .\installers\build.ps1 -Version 3.2.0 -Release   # + affiche gh release create
#
# Sorties :
#   installers\dist\WIN_GuildVoiceManager-v<VERSION>.zip
#   installers\dist\MAC_GuildVoiceManager-v<VERSION>.zip
#
# Chaque ZIP contient :
#   - install.ps1 / install.sh  (avec {{VERSION}} substitue)
#   - INSTALLER + MISE-A-JOUR wrappers
#   - LISEZMOI.txt
#   - plugin/  (copie de ..\plugin\ : index.ts + README.md)
# ============================================================

param(
  [string]$Version,
  [switch]$Release
)

$ErrorActionPreference = 'Stop'

# Resolution des chemins
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir     = Split-Path -Parent $ScriptDir   # guildvoicemanager\
$PluginDir   = Join-Path $RepoDir 'plugin'
$VersionFile = Join-Path $RepoDir 'VERSION'
$DistDir     = Join-Path $ScriptDir 'dist'
$WinSrc      = Join-Path $ScriptDir 'windows'
$MacSrc      = Join-Path $ScriptDir 'macos'

# Charge la version
if (-not $Version) {
    if (-not (Test-Path $VersionFile)) {
        Write-Host "[build] Aucun -Version passe et VERSION absent a la racine." -ForegroundColor Red
        exit 1
    }
    $Version = (Get-Content $VersionFile -Raw).Trim()
}
if ($Version -notmatch '^\d+\.\d+\.\d+') {
    Write-Host "[build] Version invalide : '$Version' (attendu : X.Y.Z)" -ForegroundColor Red
    exit 1
}

$Tag = "v$Version"
Write-Host ""
Write-Host "[build] Version cible : $Tag" -ForegroundColor Cyan
Write-Host "[build] Plugin source : $PluginDir" -ForegroundColor Gray

if (-not (Test-Path (Join-Path $PluginDir 'index.ts'))) {
    Write-Host "[build] Plugin introuvable (index.ts manquant dans $PluginDir)" -ForegroundColor Red
    exit 1
}

# Cree dist\ si absent
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

# Helper : substitue {{VERSION}} dans les fichiers texte d'un dossier
function Replace-Version {
    param($dir, $ver)
    Get-ChildItem $dir -File -Recurse | Where-Object {
        $_.Extension -in '.ps1', '.sh', '.bat', '.command', '.txt', '.md'
    } | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match '\{\{VERSION\}\}') {
            ($content -replace '\{\{VERSION\}\}', $ver) | Set-Content -NoNewline -Path $_.FullName
        }
    }
}

# Helper : package une plateforme
function Build-Package {
    param(
        [string]$Platform,   # 'WIN' ou 'MAC'
        [string]$SrcDir,     # installers\windows ou installers\macos
        [string]$StageName   # nom du dossier racine dans le ZIP
    )
    $zipName  = "${Platform}_GuildVoiceManager-${Tag}.zip"
    $zipPath  = Join-Path $DistDir $zipName
    $stageDir = Join-Path $env:TEMP "gvm-build-$([guid]::NewGuid().ToString('N'))"
    $stageSub = Join-Path $stageDir $StageName

    Write-Host ""
    Write-Host "[build] === $Platform ===" -ForegroundColor Magenta
    Write-Host "[build] Staging : $stageSub" -ForegroundColor Gray

    # Copie scripts + plugin dans le staging
    New-Item -ItemType Directory -Path $stageSub -Force | Out-Null
    Copy-Item -Path (Join-Path $SrcDir '*') -Destination $stageSub -Recurse -Force
    Copy-Item -Path $PluginDir -Destination (Join-Path $stageSub 'plugin') -Recurse -Force

    # Substitue la version
    Replace-Version -dir $stageSub -ver $Version

    # Supprime le ZIP existant puis compresse
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -Force

    # Clean staging
    Remove-Item $stageDir -Recurse -Force

    $size = (Get-Item $zipPath).Length
    Write-Host "[build] OK $zipName ($([math]::Round($size/1024,1)) KB)" -ForegroundColor Green
    return $zipPath
}

# Build Windows
$winZip = Build-Package -Platform 'WIN' -SrcDir $WinSrc -StageName "WIN_GuildVoiceManager"

# Build macOS
$macZip = Build-Package -Platform 'MAC' -SrcDir $MacSrc -StageName "MAC_GuildVoiceManager"

Write-Host ""
Write-Host "[build] ============================================" -ForegroundColor Cyan
Write-Host "[build] Build $Tag termine." -ForegroundColor Cyan
Write-Host "[build] Sorties :" -ForegroundColor Cyan
Write-Host "          $winZip" -ForegroundColor Gray
Write-Host "          $macZip" -ForegroundColor Gray
Write-Host "[build] ============================================" -ForegroundColor Cyan

if ($Release) {
    Write-Host ""
    Write-Host "[build] Commande pour creer la release GitHub :" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    gh release create $Tag ``" -ForegroundColor White
    Write-Host "      `"$winZip`" ``" -ForegroundColor White
    Write-Host "      `"$macZip`" ``" -ForegroundColor White
    Write-Host "      --title 'GuildVoiceManager $Tag' ``" -ForegroundColor White
    Write-Host "      --notes 'Release automatisee depuis build.ps1'" -ForegroundColor White
    Write-Host ""
}
