# Installers

Scripts d'installation et de mise à jour du plugin GuildVoiceManager sur Discord, versionnés et packageables en ZIPs distribuables.

## Arborescence

```
installers/
├── README.md                 ← ce fichier
├── build.ps1                 ← génère les ZIPs versionnés (Windows)
├── build.sh                  ← idem (Linux/macOS)
├── dist/                     ← artefacts de build (gitignored, sauf .gitkeep)
│   ├── WIN_GuildVoiceManager-v<VERSION>.zip
│   └── MAC_GuildVoiceManager-v<VERSION>.zip
├── windows/
│   ├── INSTALLER.bat         ← wrapper admin (relance en élévation)
│   ├── MISE-A-JOUR.bat       ← alias de INSTALLER.bat (mode MAJ auto-détecté)
│   ├── install.ps1           ← logique d'installation + MAJ
│   └── LISEZMOI.txt          ← instructions utilisateur
└── macos/
    ├── INSTALLER.command     ← wrapper zsh (Gatekeeper-friendly)
    ├── MISE-A-JOUR.command   ← alias
    ├── install.sh            ← logique d'installation + MAJ
    └── LISEZMOI.txt          ← instructions utilisateur
```

## Gestion de version

La version est stockée en un seul endroit : le fichier [`../VERSION`](../VERSION) à la racine du dossier parent. Au build, les scripts remplacent le placeholder `{{VERSION}}` dans tous les fichiers `.ps1`, `.sh`, `.bat`, `.command`, `.txt`, `.md` par la valeur du `VERSION` (ou celle passée en CLI).

## Générer une nouvelle version

### Cas typique : bump de version

```bash
# 1. Éditer la version
echo "3.2.0" > VERSION

# 2. Build (lit VERSION automatiquement)
./installers/build.sh             # Linux/macOS/WSL
# ou, Windows natif :
.\installers\build.ps1
```

Les ZIPs sont générés dans `installers/dist/`.

### Override ponctuel sans modifier `VERSION`

```bash
./installers/build.sh 3.2.0-rc1          # premier arg positionnel
.\installers\build.ps1 -Version 3.2.0-rc1
```

### Publier sur GitHub Releases

Ajouter le flag `--release` (Bash) ou `-Release` (PS) pour afficher la commande `gh release create` prête à copier :

```bash
./installers/build.sh --release
.\installers\build.ps1 -Release
```

Exemple de sortie :

```
gh release create v3.1.0 \
  "installers/dist/WIN_GuildVoiceManager-v3.1.0.zip" \
  "installers/dist/MAC_GuildVoiceManager-v3.1.0.zip" \
  --title 'GuildVoiceManager v3.1.0' \
  --notes 'Release automatisée depuis build.sh'
```

## Flux d'installation côté utilisateur

### Depuis un ZIP distribué (GitHub Releases, partage direct)

1. Télécharger le ZIP adapté à l'OS
2. Extraire le dossier
3. Double-clic sur `INSTALLER.bat` (Windows) ou `INSTALLER.command` (macOS, via clic droit > Ouvrir)
4. Le script clone **Vencord officiel** (`Vendicated/Vencord`), injecte le plugin depuis le ZIP, compile, injecte dans Discord

### Depuis le repo toolbox cloné (contributeur)

```bash
# Windows natif
.\toolbox\guildvoicemanager\installers\windows\INSTALLER.bat

# macOS / Linux
./toolbox/guildvoicemanager/installers/macos/INSTALLER.command
```

Les installeurs détectent le plugin via chemin relatif `../../plugin/` sans besoin de ZIP intermédiaire.

## Modes install vs mise à jour

Les deux wrappers (`INSTALLER` et `MISE-A-JOUR`) appellent le même `install.ps1` / `install.sh`. Le mode est auto-détecté :

- Si `~/Vencord/.git` **n'existe pas** → mode INSTALLATION (clone from scratch)
- Si `~/Vencord/.git` **existe** → mode MISE A JOUR (`git fetch` + `git reset --hard origin/main`, re-injection du plugin, rebuild, ré-inject Discord)

Un `MISE-A-JOUR.bat` / `.command` séparé existe uniquement pour la clarté UX côté utilisateur. Techniquement ils lancent le même script.

## Vencord upstream

Les installeurs clonent **le dépôt officiel** :

```
https://github.com/Vendicated/Vencord.git  (branche main)
```

Raisonnement détaillé dans [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md). Résumé : cloner l'upstream garantit que chaque installation reçoit les derniers correctifs (sécurité, Discord API breaks, ajouts plugins). Le plugin GuildVoiceManager est injecté **par-dessus** ce clone, sans toucher au code Vencord.

## Dépannage

| Symptôme | Pointer |
|---|---|
| SmartScreen bloque l'installeur Windows | [GOTCHAS §1](../docs/GOTCHAS.md#1-smartscreen-windows-defender) |
| macOS refuse d'ouvrir `.command` | [GOTCHAS §2](../docs/GOTCHAS.md#2-gatekeeper-macos) |
| `pnpm: command not found` | [GOTCHAS §3](../docs/GOTCHAS.md#3-pnpm-via-corepack) |
| Build pnpm échoue avec erreur sur `src/userplugins/` | [GOTCHAS §4](../docs/GOTCHAS.md#4-userplugins-obsolete) |
| Plugin introuvable après installation | [GOTCHAS §5](../docs/GOTCHAS.md#5-plugin-non-charge-dans-vencord) |

## Références

- [`../README.md`](../README.md) — entry point du projet
- [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) — ADR : upstream + injection vs fork
- [`../docs/SECURITY.md`](../docs/SECURITY.md) — modèle de menace
- [`../docs/GOTCHAS.md`](../docs/GOTCHAS.md) — pièges rencontrés
- [`../plugin/README.md`](../plugin/README.md) — documentation du plugin
