#!/bin/zsh
# ================================================
#  GuildVoiceManager {{VERSION}} - Installateur
#  Par Anthony aka NIXshade
# ================================================
#
#  Discord sera ferme automatiquement.
#  Clic droit > Ouvrir si macOS bloque le script.
#
# ================================================

killall Discord 2>/dev/null
sleep 1

cd "$(dirname "$0")"
/bin/bash install.sh
