#!/usr/bin/env bash
# ============================================================
# build.sh — Genere les ZIPs d'installation versionnes (Windows + macOS)
#
# Usage :
#   ./installers/build.sh                    # lit la version dans ../VERSION
#   ./installers/build.sh 3.2.0              # override ponctuel
#   ./installers/build.sh 3.2.0 --release    # + affiche gh release create
#
# Sorties :
#   installers/dist/WIN_GuildVoiceManager-v<VERSION>.zip
#   installers/dist/MAC_GuildVoiceManager-v<VERSION>.zip
#
# Chaque ZIP contient :
#   - install.ps1 / install.sh  (avec {{VERSION}} substitue)
#   - INSTALLER + MISE-A-JOUR wrappers
#   - LISEZMOI.txt
#   - plugin/  (copie de ../plugin/ : index.ts + README.md)
# ============================================================

set -euo pipefail

# Parse args (1 positionnel + flag)
VERSION="${1:-}"
RELEASE_FLAG=false
for arg in "$@"; do
    if [ "$arg" = "--release" ]; then RELEASE_FLAG=true; fi
done

# Chemins
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_DIR="${REPO_DIR}/plugin"
VERSION_FILE="${REPO_DIR}/VERSION"
DIST_DIR="${SCRIPT_DIR}/dist"
WIN_SRC="${SCRIPT_DIR}/windows"
MAC_SRC="${SCRIPT_DIR}/macos"

# Charge la version
if [ -z "${VERSION}" ] || [ "${VERSION}" = "--release" ]; then
    VERSION=""
    if [ -f "${VERSION_FILE}" ]; then
        VERSION="$(cat "${VERSION_FILE}" | tr -d '[:space:]')"
    fi
fi
if [ -z "${VERSION}" ]; then
    echo "[build] Aucune version passee et VERSION absent a la racine." >&2
    exit 1
fi
if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "[build] Version invalide : '${VERSION}' (attendu : X.Y.Z)" >&2
    exit 1
fi

TAG="v${VERSION}"
echo ""
echo "[build] Version cible : ${TAG}"
echo "[build] Plugin source : ${PLUGIN_DIR}"

if [ ! -f "${PLUGIN_DIR}/index.ts" ]; then
    echo "[build] Plugin introuvable (index.ts manquant dans ${PLUGIN_DIR})" >&2
    exit 1
fi

# Pre-requis : zip dispo
if ! command -v zip >/dev/null 2>&1; then
    echo "[build] 'zip' introuvable. Installe-le (apt install zip / brew install zip)." >&2
    exit 1
fi

mkdir -p "${DIST_DIR}"

# Substitution {{VERSION}} dans un dossier
# Usage : replace_version "/path/to/dir" "3.1.0"
replace_version() {
    local dir="$1"
    local ver="$2"
    # On cible les extensions texte susceptibles de contenir le placeholder.
    # -type f protege contre les dossiers ; xargs sed -i evite de lancer sed par fichier.
    find "${dir}" -type f \( \
        -name '*.ps1' -o -name '*.sh' -o -name '*.bat' -o \
        -name '*.command' -o -name '*.txt' -o -name '*.md' \
        \) -print0 | xargs -0 -I{} sh -c "grep -l '{{VERSION}}' '{}' >/dev/null 2>&1 && sed -i.bak 's|{{VERSION}}|${ver}|g' '{}' && rm -f '{}.bak' || true"
}

# Package une plateforme
# Usage : build_package "WIN" "${WIN_SRC}" "WIN_GuildVoiceManager"
build_package() {
    local platform="$1"
    local src_dir="$2"
    local stage_name="$3"

    local zip_name="${platform}_GuildVoiceManager-${TAG}.zip"
    local zip_path="${DIST_DIR}/${zip_name}"
    local stage_dir
    stage_dir="$(mktemp -d -t gvm-build-XXXXXX)"
    local stage_sub="${stage_dir}/${stage_name}"

    echo ""
    echo "[build] === ${platform} ==="
    echo "[build] Staging : ${stage_sub}"

    mkdir -p "${stage_sub}"
    cp -R "${src_dir}/." "${stage_sub}/"
    cp -R "${PLUGIN_DIR}" "${stage_sub}/plugin"

    replace_version "${stage_sub}" "${VERSION}"

    # Le zip est cree dans /tmp puis copie vers dist/.
    # Raison : certains filesystems (FUSE mounts, SMB, etc.) ne supportent
    # ni les renames atomiques que 'zip' fait pendant la compression,
    # ni les deletions. On passe par cat > pour ecraser sans unlink.
    local tmp_zip="${stage_dir}/${zip_name}"
    ( cd "${stage_dir}" && zip -qr "${tmp_zip}" "${stage_name}" )

    # Ecriture non-destructive (truncate + rewrite) pour compat mounts restreints
    cat "${tmp_zip}" > "${zip_path}"
    rm -rf "${stage_dir}"

    local size_kb
    size_kb="$(du -k "${zip_path}" | cut -f1)"
    echo "[build] OK ${zip_name} (${size_kb} KB)"
    echo "${zip_path}"
}

WIN_ZIP="$(build_package 'WIN' "${WIN_SRC}" 'WIN_GuildVoiceManager' | tail -n 1)"
MAC_ZIP="$(build_package 'MAC' "${MAC_SRC}" 'MAC_GuildVoiceManager' | tail -n 1)"

echo ""
echo "[build] ============================================"
echo "[build] Build ${TAG} termine."
echo "[build] Sorties :"
echo "          ${WIN_ZIP}"
echo "          ${MAC_ZIP}"
echo "[build] ============================================"

if $RELEASE_FLAG; then
    echo ""
    echo "[build] Commande pour creer la release GitHub :"
    echo ""
    echo "    gh release create ${TAG} \\"
    echo "      \"${WIN_ZIP}\" \\"
    echo "      \"${MAC_ZIP}\" \\"
    echo "      --title 'GuildVoiceManager ${TAG}' \\"
    echo "      --notes 'Release automatisee depuis build.sh'"
    echo ""
fi
