#!/usr/bin/env bash
# ============================================================
# GuildVoiceManager - Installation & Mise a jour (macOS)
# Version : {{VERSION}}
# Par Anthony aka NIXshade
# ============================================================
#
# Ce script :
#   1. Clone le Vencord OFFICIEL (Vendicated/Vencord) — branche main
#   2. Injecte le plugin GuildVoiceManager depuis ce repo
#      (chemin relatif : ../../plugin/)
#   3. Installe les deps, build, injecte dans Discord
#
# Deux modes auto-detectes :
#   - INSTALLATION : ~/Vencord absent ou sans .git
#   - MISE A JOUR  : ~/Vencord/.git present -> fetch + reset --hard origin/main,
#                     re-inject du plugin, rebuild, reinject Discord
#
# Compatible Apple Silicon (arm64) et Intel (x86_64).
# Prerequis auto-installes si absents : Homebrew, Git, Node.js LTS, pnpm
#
# Plugin source : https://github.com/Anthony-Faria-dos-santos/toolbox
#                 (dossier guildvoicemanager/plugin/)
# Vencord upstream : https://github.com/Vendicated/Vencord
# ============================================================

set -uo pipefail
# Pas de set -e : gestion manuelle via $? et checks

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
VENCORD_REPO="https://github.com/Vendicated/Vencord.git"
VENCORD_BRANCH="main"
INSTALL_DIR="$HOME/Vencord"
PLUGIN_NAME="guildVoiceManager"

# Resolution du chemin source du plugin (deux modes supportes) :
#   1) depuis le repo clone : installers/macos/install.sh -> ../../plugin/
#   2) depuis le ZIP distribue : install.sh cote a cote avec ./plugin/
# Le build script (build.sh) copie le plugin DANS le ZIP au moment du packaging.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC=""
for candidate in "../../plugin" "./plugin" "../plugin"; do
    full="${SCRIPT_DIR}/${candidate}"
    if [ -f "${full}/index.ts" ]; then
        PLUGIN_SRC="$(cd "${full}" && pwd)"
        break
    fi
done

if [ -z "${PLUGIN_SRC}" ]; then
    echo "[install] Plugin source introuvable." >&2
    echo "         Cherche : ../../plugin/, ./plugin/, ../plugin/ (relatifs a ce script)." >&2
    echo "         Lance ce script depuis le repo toolbox clone ou depuis le ZIP non-altere." >&2
    read -rp "  Appuie sur Entree pour quitter..." _
    exit 1
fi

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; GRAY='\033[0;37m'; NC='\033[0m'

total_steps=8
step_num=1

write_step()  { echo -e "\n  ${CYAN}[$1/$2]${NC} $3"; }
write_ok()    { echo -e "       ${GREEN}OK:${NC} $1"; }
write_warn()  { echo -e "       ${YELLOW}ATTENTION:${NC} $1"; }
write_err()   { echo -e "       ${RED}ERREUR:${NC} $1"; }

pause_exit() {
    echo ""
    read -rp "  Appuie sur Entree pour quitter..." _
    exit 1
}

load_brew() {
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}
load_brew

copy_plugin() {
    # $1 = source dir, $2 = destination dir
    local src="$1"
    local dest="$2"
    rm -rf "${dest}"
    mkdir -p "${dest}"
    cp -R "${src}/." "${dest}/"
}

# ------------------------------------------------------------
# Detection du mode
# ------------------------------------------------------------
is_update=false
if [ -d "${INSTALL_DIR}/.git" ]; then
    is_update=true
fi

echo ""
echo -e "  ${MAGENTA}================================================${NC}"
echo -e "  ${MAGENTA}  GuildVoiceManager {{VERSION}}${NC}"
if $is_update; then
    echo -e "  ${YELLOW}  Mode : MISE A JOUR${NC}"
else
    echo -e "  ${GREEN}  Mode : INSTALLATION${NC}"
fi
echo -e "  ${MAGENTA}  Par Anthony aka NIXshade${NC}"
echo -e "  ${MAGENTA}================================================${NC}"
echo ""

if $is_update; then
    echo -e "  Installation existante detectee dans :"
    echo -e "  ${GRAY}${INSTALL_DIR}${NC}"
    echo ""
    echo "  La mise a jour va :"
    echo -e "  ${GRAY}  - Synchroniser Vencord avec l'upstream officiel (reset --hard)${NC}"
    echo -e "  ${GRAY}  - Reinjecter le plugin GuildVoiceManager depuis ce repo${NC}"
    echo -e "  ${GRAY}  - Recompiler et reinjecter dans Discord${NC}"
    echo ""
    read -rp "  Continuer ? (O/n) " confirm
    if [[ "${confirm}" == "n" || "${confirm}" == "N" ]]; then
        echo "  Annule."
        exit 0
    fi
fi

# ============================================================
# 1. Fermer Discord
# ============================================================
write_step ${step_num} ${total_steps} "Fermeture de Discord..."
if pgrep -x "Discord" > /dev/null 2>&1; then
    pkill -x "Discord" 2>/dev/null || true
    sleep 3
    write_ok "Discord ferme."
else
    write_ok "Discord deja ferme."
fi
((step_num++))

# ============================================================
# 2. Homebrew
# ============================================================
write_step ${step_num} ${total_steps} "Verification de Homebrew..."
if command -v brew &>/dev/null; then
    write_ok "Homebrew detecte."
else
    write_warn "Homebrew non trouve, installation..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew
    if command -v brew &>/dev/null; then
        write_ok "Homebrew installe."
    else
        write_err "Homebrew n'a pas pu etre installe."
        write_err "Installe-le manuellement : https://brew.sh"
        pause_exit
    fi
fi
((step_num++))

# ============================================================
# 3. Git + Node + pnpm
# ============================================================
write_step ${step_num} ${total_steps} "Verification de Git, Node.js et pnpm..."

if command -v git &>/dev/null; then
    write_ok "Git $(git --version | sed 's/git version //')"
else
    write_warn "Git non trouve, installation via Homebrew..."
    brew install git
    command -v git &>/dev/null && write_ok "Git installe." || { write_err "Git installe mais introuvable."; pause_exit; }
fi

if command -v node &>/dev/null; then
    write_ok "Node.js $(node --version)"
else
    write_warn "Node.js non trouve, installation via Homebrew..."
    brew install node@22
    brew link --overwrite node@22 2>/dev/null || true
    command -v node &>/dev/null && write_ok "Node.js installe." || { write_err "Node.js installe mais introuvable."; pause_exit; }
fi

if ! command -v pnpm &>/dev/null; then
    echo -e "       ${GRAY}Installation de pnpm...${NC}"
    npm install -g pnpm 2>/dev/null || true
fi
if ! command -v pnpm &>/dev/null; then
    corepack enable 2>/dev/null || true
    corepack prepare pnpm@latest --activate 2>/dev/null || true
fi
if command -v pnpm &>/dev/null; then
    write_ok "pnpm disponible."
else
    write_err "Impossible d'installer pnpm. Lance manuellement : npm install -g pnpm"
    pause_exit
fi
((step_num++))

# ============================================================
# 4. Clone / sync Vencord upstream
# ============================================================
if $is_update; then
    write_step ${step_num} ${total_steps} "Synchronisation avec Vencord upstream..."
    cd "${INSTALL_DIR}"

    # S'assurer que origin pointe bien sur l'upstream officiel
    current_remote="$(git remote get-url origin 2>/dev/null || echo '')"
    if [ "${current_remote}" != "${VENCORD_REPO}" ]; then
        write_warn "Remote origin = ${current_remote}"
        write_warn "Re-pointage vers ${VENCORD_REPO}"
        git remote set-url origin "${VENCORD_REPO}" 2>/dev/null
    fi

    git fetch origin 2>/dev/null
    if [ $? -ne 0 ]; then
        write_err "Impossible de contacter le serveur. Verifie ta connexion internet."
        pause_exit
    fi

    git reset --hard "origin/${VENCORD_BRANCH}" 2>/dev/null || {
        write_warn "Reset echoue, re-clone complet..."
        cd "${HOME}"
        rm -rf "${INSTALL_DIR}"
        git clone --branch "${VENCORD_BRANCH}" "${VENCORD_REPO}" "${INSTALL_DIR}"
        cd "${INSTALL_DIR}"
    }

    git clean -fd 2>/dev/null
    write_ok "Vencord synchronise sur origin/${VENCORD_BRANCH}."
else
    write_step ${step_num} ${total_steps} "Clone du Vencord officiel..."
    if [ -d "${INSTALL_DIR}" ]; then
        write_warn "Dossier existant sans depot git, suppression..."
        rm -rf "${INSTALL_DIR}"
    fi
    git clone --branch "${VENCORD_BRANCH}" "${VENCORD_REPO}" "${INSTALL_DIR}"
    if [ ! -d "${INSTALL_DIR}" ]; then
        write_err "Le clone a echoue. Verifie ta connexion internet."
        pause_exit
    fi
    cd "${INSTALL_DIR}"
    write_ok "Vencord clone depuis Vendicated/Vencord."
fi
((step_num++))

# Purge userplugins (cf. note Windows)
if [ -d "${INSTALL_DIR}/src/userplugins" ] && [ "$(ls -A "${INSTALL_DIR}/src/userplugins" 2>/dev/null)" ]; then
    write_warn "Nettoyage de src/userplugins/..."
    rm -rf "${INSTALL_DIR}/src/userplugins/"*
    write_ok "userplugins/ purge."
fi

# ============================================================
# 5. Injection du plugin depuis ce repo
# ============================================================
write_step ${step_num} ${total_steps} "Injection du plugin GuildVoiceManager..."
plugin_dest="${INSTALL_DIR}/src/plugins/${PLUGIN_NAME}"
copy_plugin "${PLUGIN_SRC}" "${plugin_dest}"

if [ -f "${plugin_dest}/index.ts" ]; then
    size=$(wc -c < "${plugin_dest}/index.ts")
    write_ok "Plugin copie dans src/plugins/${PLUGIN_NAME}/ (index.ts = ${size} octets)"
else
    write_err "Echec copie plugin (index.ts absent de la destination)."
    pause_exit
fi
((step_num++))

# ============================================================
# 6. Deps
# ============================================================
write_step ${step_num} ${total_steps} "Installation des dependances (~1-2 min)..."
cd "${INSTALL_DIR}"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install 2>/dev/null
write_ok "Dependances installees."
((step_num++))

# ============================================================
# 7. Build
# ============================================================
write_step ${step_num} ${total_steps} "Compilation de Vencord + GuildVoiceManager..."
if ! pnpm build; then
    echo ""
    write_err "La compilation a echoue."
    write_err "Fais une capture d'ecran et envoie-la a NIXshade."
    pause_exit
fi
write_ok "Compilation reussie."
((step_num++))

# ============================================================
# 8. Injection dans Discord
# ============================================================
write_step ${step_num} ${total_steps} "Injection dans Discord..."
pkill -x "Discord" 2>/dev/null || true
sleep 2

if ! pnpm inject; then
    write_warn "Injection auto echouee, lancement interactif..."
    pnpm inject
fi
write_ok "Vencord injecte dans Discord."

# ============================================================
# Termine
# ============================================================
echo ""
echo -e "  ${GREEN}================================================${NC}"
if $is_update; then
    echo -e "  ${GREEN}  Mise a jour terminee !${NC}"
else
    echo -e "  ${GREEN}  Installation terminee !${NC}"
fi
echo -e "  ${GREEN}================================================${NC}"
echo ""
echo -e "  Prochaines etapes :"
echo -e "  ${GRAY}  1. Discord va se lancer automatiquement${NC}"
echo -e "  ${GRAY}  2. Parametres > Vencord > Plugins${NC}"
echo -e "  ${GRAY}  3. Active 'GuildVoiceManager'${NC}"
echo -e "  ${GRAY}  4. Redemarre Discord (Cmd+R)${NC}"
echo ""
echo -e "  Commandes du plugin :"
echo -e "  ${GRAY}  /gvg      - Mutes + message dynamique${NC}"
echo -e "  ${GRAY}  /gvgcheck - Appel des troupes par role${NC}"
echo -e "  ${GRAY}  /unmute   - Unmute tout le monde${NC}"
echo -e "  ${GRAY}  /muted    - Liste des joueurs mutes${NC}"
echo -e "  ${GRAY}  /vdebug   - Diagnostic du plugin${NC}"
echo -e "  ${GRAY}  /gvghelp  - Aide des commandes${NC}"
echo ""

if [ -d "/Applications/Discord.app" ]; then
    open -a Discord
    write_ok "Discord lance !"
else
    write_warn "Lance Discord manuellement."
fi

echo ""
read -rp "  Appuie sur Entree pour fermer..." _
