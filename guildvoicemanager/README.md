# guildvoicemanager

Plugin Vencord — gestion vocale GvG (Guerre de Guilde) pour Discord. Mute/unmute local par rôle, avec mémorisation des volumes originaux. Distribué avec des installeurs Windows + macOS qui clonent le Vencord officiel et injectent le plugin sans toucher à l'upstream.

## En 3 étapes

### Utilisateur final (distribution ZIP)

```
1. Télécharger le ZIP depuis GitHub Releases :
     WIN_GuildVoiceManager-v<X.Y.Z>.zip   (Windows)
     MAC_GuildVoiceManager-v<X.Y.Z>.zip   (macOS)
2. Extraire le dossier
3. Double-clic sur INSTALLER.bat (Windows) ou clic droit > Ouvrir
   sur INSTALLER.command (macOS)
```

### Contributeur / dev (depuis le repo cloné)

```bash
# Windows natif
.\guildvoicemanager\installers\windows\INSTALLER.bat

# macOS / Linux
./guildvoicemanager/installers/macos/INSTALLER.command
```

### Générer une nouvelle release

```bash
echo "3.2.0" > VERSION
./installers/build.sh --release     # ou .\installers\build.ps1 -Release
# Copier-coller la commande gh release create affichée
```

## Arborescence

```
guildvoicemanager/
├── README.md                         ← ce fichier (entry point)
├── VERSION                           ← version courante (single source of truth)
├── .gitignore
├── docs/                             ← documentation technique cross-cutting
│   ├── ARCHITECTURE.md               ← ADR : upstream + injection (vs fork)
│   ├── SECURITY.md                   ← modèle de menace et contrôles
│   └── GOTCHAS.md                    ← pièges rencontrés + workarounds
├── plugin/                           ← source du plugin (seule source de vérité)
│   ├── README.md                     ← doc utilisateur du plugin
│   └── index.ts                      ← ~800 lignes, GPL-3.0-or-later
└── installers/                       ← scripts d'installation + build ZIPs
    ├── README.md                     ← usage + flux utilisateur
    ├── build.ps1                     ← génère les ZIPs versionnés (PowerShell)
    ├── build.sh                      ← génère les ZIPs versionnés (Bash)
    ├── dist/                         ← artefacts de build (gitignored)
    ├── windows/
    │   ├── INSTALLER.bat             ← wrapper élévation UAC
    │   ├── MISE-A-JOUR.bat
    │   ├── install.ps1               ← clone Vencord upstream + injection
    │   └── LISEZMOI.txt
    └── macos/
        ├── INSTALLER.command         ← wrapper zsh
        ├── MISE-A-JOUR.command
        ├── install.sh                ← clone Vencord upstream + injection
        └── LISEZMOI.txt
```

## Documentation par section

| Cible | Fichier |
|---|---|
| **Pourquoi ce design (upstream + injection vs fork)** | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| **Modèle de sécurité, exfiltration, droits admin, Defender** | [`docs/SECURITY.md`](docs/SECURITY.md) |
| **Pièges (SmartScreen, Gatekeeper, Corepack, userplugins…)** | [`docs/GOTCHAS.md`](docs/GOTCHAS.md) |
| **Détail des installeurs + build versionné** | [`installers/README.md`](installers/README.md) |
| **Documentation utilisateur du plugin** | [`plugin/README.md`](plugin/README.md) |

## Principe en une phrase

Les installeurs clonent le Vencord officiel (`Vendicated/Vencord`), injectent le plugin depuis ce repo dans `src/plugins/guildVoiceManager/`, puis compilent et patchent Discord — zéro fork à maintenir, zéro divergence upstream, zéro binaire tiers à faire confiance.

Détail complet dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Commandes du plugin

| Commande | Effet |
|---|---|
| `/gvg` | Mute par rôle + message dynamique + auto-transfert dans le salon GvG |
| `/gvgcheck` | Appel des troupes par rôle (objectif 30) |
| `/unmute` | Restaure tous les volumes originaux |
| `/muted` | Liste des joueurs mutés |
| `/vdebug` | Diagnostic complet |
| `/gvghelp` | Aide |

Détail dans [`plugin/README.md`](plugin/README.md).

## Plateformes supportées

| OS | Install | MAJ | Désinstall |
|---|---|---|---|
| **Windows 10/11** (x64) | ✅ via `INSTALLER.bat` | ✅ auto-détecté | `pnpm uninject` + rm `~\Vencord` |
| **macOS 12+** (Intel + Apple Silicon) | ✅ via `INSTALLER.command` | ✅ auto-détecté | `pnpm uninject` + rm `~/Vencord` |
| **Linux** | ⚠️ manuel (pas d'installeur fourni, utiliser install.sh + Discord Flatpak/Snap à vos risques) | — | — |

## Dépannage express

Pannes fréquentes avec symptôme, cause et fix dans [`docs/GOTCHAS.md`](docs/GOTCHAS.md). Réflexes rapides :

| Symptôme | Pointer |
|---|---|
| SmartScreen bloque Windows | [GOTCHAS §1](docs/GOTCHAS.md#1-smartscreen-windows-defender) |
| macOS "ne peut pas être ouvert" | [GOTCHAS §2](docs/GOTCHAS.md#2-gatekeeper-macos) |
| `pnpm: command not found` | [GOTCHAS §3](docs/GOTCHAS.md#3-pnpm-via-corepack) |
| Build qui échoue sur `src/userplugins/` | [GOTCHAS §4](docs/GOTCHAS.md#4-srcuserplugins-obsolète-casse-le-build) |
| Plugin absent de Vencord après install | [GOTCHAS §5](docs/GOTCHAS.md#5-plugin-non-chargé-dans-vencord) |
| `pnpm inject`: Discord introuvable | [GOTCHAS §6](docs/GOTCHAS.md#6-pnpm-inject-échoue-sur-discord-portable-windows) |

## Statut

✅ Installeurs Windows + macOS testés sur install from scratch et mise à jour.
✅ Plugin v3.1 actif sur le serveur Discord GvG "WhereWindsMeet".
✅ Build ZIP reproductible via `installers/build.sh` / `installers/build.ps1`.

## Licence

**GPL-3.0-or-later** (hérité de Vencord). Copyright © 2025 Anthony aka NIXshade.

## Auteur

Anthony Faria Dos Santos aka NIXshade — [@Anthony-Faria-dos-santos](https://github.com/Anthony-Faria-dos-santos)
