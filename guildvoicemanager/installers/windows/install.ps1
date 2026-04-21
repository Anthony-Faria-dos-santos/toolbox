# ============================================================
# GuildVoiceManager - Installation & Mise a jour (Windows)
# Version : {{VERSION}}
# Par Anthony aka NIXshade
# ============================================================
#
# Ce script :
#   1. Clone le Vencord OFFICIEL (Vendicated/Vencord) — branche main
#   2. Injecte le plugin GuildVoiceManager depuis ce repo
#      (chemin relatif : ..\..\plugin\)
#   3. Installe les deps, build, injecte dans Discord
#
# Deux modes auto-detectes :
#   - INSTALLATION : dossier ~\Vencord absent ou sans .git
#   - MISE A JOUR  : ~\Vencord\.git present -> fetch + reset --hard origin/main,
#                     re-inject du plugin, rebuild, reinject Discord
#
# Prerequis auto-installes si absents : Git, Node.js LTS, pnpm
# (via winget — necessite droits admin pour Defender et winget silencieux)
#
# Plugin source : https://github.com/Anthony-Faria-dos-santos/toolbox
#                 (dossier guildvoicemanager/plugin/)
# Vencord upstream : https://github.com/Vendicated/Vencord
# ============================================================

$ErrorActionPreference = "Continue"
# "Continue" et non "Stop" car git/node/pnpm ecrivent des warnings sur stderr
# (DeprecationWarning, progression git, etc.) que PowerShell traiterait
# comme des erreurs fatales. Verification manuelle via $LASTEXITCODE.

Set-ExecutionPolicy RemoteSigned -Scope Process -Force
$env:NODE_NO_WARNINGS = "1"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
$VENCORD_REPO   = "https://github.com/Vendicated/Vencord.git"
$VENCORD_BRANCH = "main"
$INSTALL_DIR    = "$env:USERPROFILE\Vencord"
$PLUGIN_NAME    = "guildVoiceManager"

# Resolution du chemin source du plugin (deux modes supportes) :
#   1) depuis le repo clone : installers\windows\install.ps1 -> ..\..\plugin\
#   2) depuis le ZIP distribue : install.ps1 cote a cote avec .\plugin\
# Le build script (build.ps1) copie le plugin DANS le ZIP au moment du packaging.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginSrc = $null
foreach ($candidate in @('..\..\plugin', '.\plugin', '..\plugin')) {
    $full = Join-Path $ScriptDir $candidate
    if (Test-Path (Join-Path $full 'index.ts')) {
        $PluginSrc = (Resolve-Path $full).Path
        break
    }
}

if (-not $PluginSrc) {
    Write-Host "[install] Plugin source introuvable." -ForegroundColor Red
    Write-Host "         Cherche : ..\..\plugin\, .\plugin\, ..\plugin\ (relatifs a ce script)." -ForegroundColor Red
    Write-Host "         Lance ce script depuis le repo toolbox clone ou depuis le ZIP non-altere." -ForegroundColor Red
    Read-Host "  Appuie sur Entree pour quitter"
    exit 1
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Write-Step  { param($num, $total, $msg) Write-Host "`n  [$num/$total] $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "       OK: $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "       ATTENTION: $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "       ERREUR: $msg" -ForegroundColor Red }
function Test-Command { param($cmd) return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Install-WithWinget {
    param($Name, $WingetId)
    Write-Host "       Installation de $Name via winget..." -ForegroundColor Yellow
    winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "$Name n'a pas pu etre installe automatiquement."
        Write-Err "Installe-le manuellement et relance ce script."
        Read-Host "  Appuie sur Entree pour quitter"
        exit 1
    }
    Refresh-Path
}

function Copy-Plugin {
    param($src, $dest)
    # Cree le dossier cible (vide) puis copie le plugin
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path "$src\*" -Destination $dest -Recurse -Force
}

# ------------------------------------------------------------
# Detection du mode
# ------------------------------------------------------------
$isUpdate = Test-Path (Join-Path $INSTALL_DIR ".git")
$totalSteps = 8

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Magenta
Write-Host "    GuildVoiceManager {{VERSION}}" -ForegroundColor Magenta
if ($isUpdate) {
    Write-Host "    Mode : MISE A JOUR" -ForegroundColor Yellow
} else {
    Write-Host "    Mode : INSTALLATION" -ForegroundColor Green
}
Write-Host "    Par Anthony aka NIXshade" -ForegroundColor Magenta
Write-Host "  ================================================" -ForegroundColor Magenta
Write-Host ""

if ($isUpdate) {
    Write-Host "  Installation existante detectee dans :" -ForegroundColor White
    Write-Host "  $INSTALL_DIR" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  La mise a jour va :" -ForegroundColor White
    Write-Host "    - Synchroniser Vencord avec l'upstream officiel (reset --hard)" -ForegroundColor Gray
    Write-Host "    - Reinjecter le plugin GuildVoiceManager depuis ce repo" -ForegroundColor Gray
    Write-Host "    - Recompiler et reinjecter dans Discord" -ForegroundColor Gray
    Write-Host ""
    $confirm = Read-Host "  Continuer ? (O/n)"
    if ($confirm -eq "n" -or $confirm -eq "N") {
        Write-Host "  Annule." -ForegroundColor Yellow
        exit 0
    }
}

$currentStep = 1

# ============================================================
# 1. Fermer Discord
# ============================================================
Write-Step $currentStep $totalSteps "Fermeture de Discord..."
$discordProcs = Get-Process -Name "Discord*" -ErrorAction SilentlyContinue
if ($discordProcs) {
    $discordProcs | Stop-Process -Force
    Start-Sleep -Seconds 3
    Write-Ok "Discord ferme."
} else {
    Write-Ok "Discord deja ferme."
}
$currentStep++

# ============================================================
# 2. Exclusion Defender
# ============================================================
Write-Step $currentStep $totalSteps "Configuration de Windows Defender..."
$defenderExcluded = $false
try {
    Add-MpPreference -ExclusionPath $INSTALL_DIR -ErrorAction Stop
    $defenderExcluded = $true
    Write-Ok "Exclusion temporaire ajoutee pour $INSTALL_DIR"
    Write-Host "       (retiree en fin d'installation)" -ForegroundColor Gray
} catch {
    Write-Warn "Impossible de configurer Defender (droits admin requis)."
    Write-Warn "Si l'installation echoue, relance via clic droit > Executer en tant qu'admin."
}
$currentStep++

# ============================================================
# 3. Verifier Git
# ============================================================
Write-Step $currentStep $totalSteps "Verification de Git..."
if (Test-Command "git") {
    $gitVer = (git --version 2>$null) -replace "git version ", ""
    Write-Ok "Git $gitVer"
} else {
    Write-Warn "Git non trouve, installation..."
    if (Test-Command "winget") {
        Install-WithWinget "Git" "Git.Git"
        if (-not (Test-Command "git")) {
            $gitDefault = "C:\Program Files\Git\cmd"
            if (Test-Path "$gitDefault\git.exe") {
                $env:Path += ";$gitDefault"
                Write-Ok "Git installe (PATH mis a jour)."
            } else {
                Write-Err "Git installe mais introuvable. Ferme et relance ce script."
                Read-Host; exit 1
            }
        } else {
            Write-Ok "Git installe."
        }
    } else {
        Write-Err "winget non disponible. Installe Git manuellement : https://git-scm.com"
        Read-Host; exit 1
    }
}
$currentStep++

# ============================================================
# 4. Verifier Node.js + pnpm
# ============================================================
Write-Step $currentStep $totalSteps "Verification de Node.js et pnpm..."
if (Test-Command "node") {
    $nodeVer = node --version 2>$null
    Write-Ok "Node.js $nodeVer"
} else {
    Write-Warn "Node.js non trouve, installation..."
    if (Test-Command "winget") {
        Install-WithWinget "Node.js" "OpenJS.NodeJS.LTS"
        if (-not (Test-Command "node")) {
            $nodeDefault = "C:\Program Files\nodejs"
            if (Test-Path "$nodeDefault\node.exe") {
                $env:Path += ";$nodeDefault"
                Write-Ok "Node.js installe (PATH mis a jour)."
            } else {
                Write-Err "Node.js installe mais introuvable. Ferme et relance ce script."
                Read-Host; exit 1
            }
        } else {
            Write-Ok "Node.js installe."
        }
    } else {
        Write-Err "winget non disponible. Installe Node.js manuellement : https://nodejs.org"
        Read-Host; exit 1
    }
}

if (-not (Test-Command "pnpm")) {
    Write-Host "       Installation de pnpm..." -ForegroundColor Gray
    npm install -g pnpm 2>$null
    Refresh-Path
}
if (-not (Test-Command "pnpm")) {
    try { corepack enable 2>$null; corepack prepare pnpm@latest --activate 2>$null; Refresh-Path } catch {}
}
if (Test-Command "pnpm") { Write-Ok "pnpm disponible." }
else { Write-Err "Impossible d'installer pnpm. Lance manuellement : npm install -g pnpm"; Read-Host; exit 1 }
$currentStep++

# ============================================================
# 5. Clone / sync Vencord upstream
# ============================================================
if ($isUpdate) {
    Write-Step $currentStep $totalSteps "Synchronisation avec Vencord upstream..."
    Set-Location $INSTALL_DIR

    # S'assurer que le remote origin pointe bien sur l'upstream officiel.
    # Si l'install initiale venait d'un ancien fork, on re-pointe.
    $currentRemote = git remote get-url origin 2>$null
    if ($currentRemote -ne $VENCORD_REPO) {
        Write-Warn "Remote origin = $currentRemote"
        Write-Warn "Re-pointage vers $VENCORD_REPO"
        git remote set-url origin $VENCORD_REPO 2>&1 | Out-Null
    }

    git fetch origin 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Impossible de contacter le serveur. Verifie ta connexion internet."
        Read-Host; exit 1
    }

    git reset --hard "origin/$VENCORD_BRANCH" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Reset echoue, re-clone complet..."
        Set-Location $env:USERPROFILE
        Remove-Item -Recurse -Force $INSTALL_DIR 2>$null
        git clone --branch $VENCORD_BRANCH $VENCORD_REPO $INSTALL_DIR 2>&1 | Out-Null
        Set-Location $INSTALL_DIR
    }

    git clean -fd 2>&1 | Out-Null
    Write-Ok "Vencord synchronise sur origin/$VENCORD_BRANCH."
} else {
    Write-Step $currentStep $totalSteps "Clone du Vencord officiel..."
    if (Test-Path $INSTALL_DIR) {
        Write-Warn "Dossier existant sans depot git, suppression..."
        Remove-Item -Recurse -Force $INSTALL_DIR 2>$null
    }
    git clone --branch $VENCORD_BRANCH $VENCORD_REPO $INSTALL_DIR 2>&1 | Out-Null
    if (-not (Test-Path $INSTALL_DIR)) {
        Write-Err "Le clone a echoue. Verifie ta connexion internet."
        Read-Host; exit 1
    }
    Set-Location $INSTALL_DIR
    Write-Ok "Vencord clone depuis Vendicated/Vencord."
}
$currentStep++

# Purge userplugins pour eviter les erreurs de build
# (Vencord scanne ce dossier et plante si des fichiers invalides s'y trouvent)
$userplugins = Join-Path $INSTALL_DIR "src\userplugins"
if (Test-Path $userplugins) {
    $items = Get-ChildItem $userplugins -Force -ErrorAction SilentlyContinue
    if ($items.Count -gt 0) {
        Write-Warn "Nettoyage de src/userplugins/ ($($items.Count) element(s))..."
        Remove-Item -Recurse -Force "$userplugins\*" 2>$null
        Write-Ok "userplugins/ purge."
    }
}

# ============================================================
# 6. Injection du plugin depuis ce repo
# ============================================================
Write-Step $currentStep $totalSteps "Injection du plugin GuildVoiceManager..."
$pluginDest = Join-Path $INSTALL_DIR "src\plugins\$PLUGIN_NAME"
Copy-Plugin -src $PluginSrc -dest $pluginDest

if (Test-Path (Join-Path $pluginDest "index.ts")) {
    Write-Ok "Plugin copie dans src\plugins\$PLUGIN_NAME\"
    $pluginSize = (Get-Item (Join-Path $pluginDest "index.ts")).Length
    Write-Host "       index.ts = $pluginSize octets" -ForegroundColor Gray
} else {
    Write-Err "Echec copie plugin (index.ts absent de la destination)."
    Read-Host; exit 1
}
$currentStep++

# ============================================================
# 7. Deps + build
# ============================================================
Write-Step $currentStep $totalSteps "Installation des dependances et compilation (~1-2 min)..."
Set-Location $INSTALL_DIR
pnpm install --frozen-lockfile 2>$null
if ($LASTEXITCODE -ne 0) { pnpm install 2>$null }
pnpm build
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Err "La compilation a echoue."
    Write-Err "Fais une capture d'ecran et envoie-la a NIXshade."
    if ($defenderExcluded) {
        try { Remove-MpPreference -ExclusionPath $INSTALL_DIR -ErrorAction Stop } catch {}
    }
    Read-Host "  Appuie sur Entree pour quitter"
    exit 1
}
Write-Ok "Compilation reussie."
$currentStep++

# ============================================================
# 8. Injection dans Discord
# ============================================================
Write-Step $currentStep $totalSteps "Injection dans Discord..."
$discordProcs = Get-Process -Name "Discord*" -ErrorAction SilentlyContinue
if ($discordProcs) { $discordProcs | Stop-Process -Force; Start-Sleep -Seconds 3 }

pnpm inject
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Injection auto echouee, lancement interactif..."
    pnpm inject
}
Write-Ok "Vencord injecte dans Discord."

# ============================================================
# Termine
# ============================================================
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
if ($isUpdate) {
    Write-Host "    Mise a jour terminee !" -ForegroundColor Green
} else {
    Write-Host "    Installation terminee !" -ForegroundColor Green
}
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Prochaines etapes :" -ForegroundColor White
Write-Host "     1. Discord va se lancer automatiquement" -ForegroundColor Gray
Write-Host "     2. Parametres > Vencord > Plugins" -ForegroundColor Gray
Write-Host "     3. Active 'GuildVoiceManager'" -ForegroundColor Gray
Write-Host "     4. Redemarre Discord (Ctrl+R)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Commandes du plugin :" -ForegroundColor White
Write-Host "     /gvg      - Mutes + message dynamique" -ForegroundColor Gray
Write-Host "     /gvgcheck - Appel des troupes par role" -ForegroundColor Gray
Write-Host "     /unmute   - Unmute tout le monde" -ForegroundColor Gray
Write-Host "     /muted    - Liste des joueurs mutes" -ForegroundColor Gray
Write-Host "     /vdebug   - Diagnostic du plugin" -ForegroundColor Gray
Write-Host "     /gvghelp  - Aide des commandes" -ForegroundColor Gray
Write-Host ""

# Retrait de l'exclusion Windows Defender
if ($defenderExcluded) {
    try {
        Remove-MpPreference -ExclusionPath $INSTALL_DIR -ErrorAction Stop
        Write-Ok "Exclusion Defender retiree."
    } catch {
        Write-Warn "Impossible de retirer l'exclusion Defender."
        Write-Warn "Retire-la manuellement : Securite Windows > Protection contre les virus > Exclusions"
    }
}

# Lancer Discord
$discordPath = "$env:LOCALAPPDATA\Discord\Update.exe"
if (Test-Path $discordPath) {
    Start-Process $discordPath -ArgumentList "--processStart", "Discord.exe"
    Write-Ok "Discord lance !"
} else {
    Write-Warn "Lance Discord manuellement."
}
