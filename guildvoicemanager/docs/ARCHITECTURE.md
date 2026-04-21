# ADR-001 — Injection du plugin dans Vencord upstream (vs fork)

**Statut :** Accepté — 2026-04
**Auteur :** Anthony Faria Dos Santos
**Scope :** `toolbox/guildvoicemanager/`

---

## Context

GuildVoiceManager est un plugin Vencord (client mod Discord) développé pour la guilde "WhereWindsMeet". Le plugin consiste en un fichier `index.ts` (~800 lignes, TypeScript) qui définit 6 slash commands et consomme les stores internes de Discord via les webpack helpers Vencord.

Vencord n'a **pas** de système de plugins pluggable côté utilisateur final. La compilation se fait en **bundling statique** : tous les plugins sous `src/plugins/` sont inclus dans un bundle unique au moment du `pnpm build`. Il n'existe pas d'API pour charger un plugin externe à runtime.

Deux stratégies étaient donc possibles :

1. **Fork de Vencord** qui embarque le plugin dans `src/plugins/guildVoiceManager/` et suit (ou non) l'upstream
2. **Repo dédié contenant uniquement le plugin**, avec installeurs qui clonent Vencord upstream et injectent le plugin avant build

La stratégie initiale était (1) — fork au niveau de `Anthony-Faria-dos-santos/Vencord`, installeurs qui clonaient le fork. Cette décision est documentée ici en remplaçant par (2).

## Decision

Adopter la stratégie **(2) : repo dédié + injection**. Concrètement :

- `toolbox/guildvoicemanager/plugin/` contient la seule source de vérité du plugin (`index.ts` + `README.md`)
- Les installeurs (`install.ps1`, `install.sh`) clonent **Vencord officiel** (`https://github.com/Vendicated/Vencord.git`, branche `main`) dans `~/Vencord/`
- Immédiatement après le clone, ils copient `plugin/` → `~/Vencord/src/plugins/guildVoiceManager/`
- Puis `pnpm install && pnpm build && pnpm inject`

Schéma de flux :

```
┌───────────────────────────────────────────────────────────┐
│  Repo toolbox (cote utilisateur : ZIP ou clone)           │
│                                                           │
│   guildvoicemanager/                                      │
│   ├── plugin/              ← source de verite             │
│   │   ├── index.ts                                        │
│   │   └── README.md                                       │
│   └── installers/                                         │
│       ├── windows/install.ps1                             │
│       └── macos/install.sh                                │
└──────────────────────────┬────────────────────────────────┘
                           │ 1. execute par l'utilisateur
                           ▼
┌───────────────────────────────────────────────────────────┐
│  git clone Vendicated/Vencord   (upstream officiel)       │
│  ~/Vencord/                                               │
│  ├── .git/                                                │
│  ├── src/                                                 │
│  │   └── plugins/           ← plugins upstream             │
│  └── ...                                                  │
└──────────────────────────┬────────────────────────────────┘
                           │ 2. copy plugin/ → src/plugins/
                           ▼
┌───────────────────────────────────────────────────────────┐
│  ~/Vencord/src/plugins/guildVoiceManager/                 │
│  ├── index.ts    ← injecte depuis le repo toolbox         │
│  └── README.md                                            │
└──────────────────────────┬────────────────────────────────┘
                           │ 3. pnpm install/build/inject
                           ▼
              [Discord patche avec Vencord + plugin]
```

## Alternatives considérées

### A. Fork complet de Vencord (statégie initiale)

- **+** Un seul clone pour l'utilisateur final, `git pull` suffit à mettre à jour
- **+** Le plugin est "live" dans le repo, visible dans l'arbo GitHub du fork
- **−** Divergence inévitable avec upstream : chaque release Vencord nécessite un merge manuel
- **−** Risque sécurité : un correctif upstream (Discord API break, XSS, auth) peut mettre des jours/semaines à arriver dans le fork
- **−** Poids historique : 20+ Mo cloné côté utilisateur pour un plugin de 32 Ko
- **−** Maintenance du fork (rebase, conflits) pour une seule personne = dette technique garantie
- **−** Charge mentale : dev qui veut améliorer le plugin doit naviguer dans 3000+ fichiers Vencord

**Rejeté :** dette de maintenance non soutenable + fenêtre de vulnérabilité dépendante de la vitesse de rebase.

### B. Git submodule de Vencord upstream dans le repo toolbox

- **+** Pinnage de version Vencord explicite (commit SHA)
- **+** Le plugin reste indépendant
- **−** UX terrible côté utilisateur : il faut `git clone --recurse-submodules` et la plupart des installeurs ne le font pas par défaut
- **−** Le pin fige Vencord sur une version — donc même problème de retard sur les correctifs que (A)
- **−** Les submodules sont historiquement source de confusion pour les contributeurs occasionnels

**Rejeté :** perd l'avantage clé d'avoir toujours un Vencord à jour, ajoute de la friction UX.

### C. Publier le plugin sur le registry Vencord officiel (pull request upstream)

- **+** Distribution native : les utilisateurs activent le plugin depuis Vencord, aucune install séparée
- **+** Validation par les mainteneurs Vencord
- **−** Plugin **très spécifique** (rôles hardcodés comme `ATK`, `DEF`, `ROM`, `Chief.L` ; salon GvG spécifique) — refus de merge quasi-garanti
- **−** Cycle de review lent, peu prévisible
- **−** Si accepté, contrainte de maintenir la compat avec la politique Vencord (code style, tests, i18n, etc.)

**Rejeté :** le scope métier du plugin est trop restreint pour être un plugin "officiel" Vencord.

### D. Plugin "userplugin" via `src/userplugins/` (mécanisme interne Vencord)

- **+** C'est le mécanisme Vencord prévu pour les plugins tiers
- **+** Pas besoin de toucher `src/plugins/`
- **−** `src/userplugins/` n'est qu'un dossier scanné à la compilation — il faut **toujours** rebuild Vencord à chaque changement
- **−** Le dossier est marqué "non-supporté" dans la doc Vencord, avec warnings au build
- **−** Les installeurs Vencord modernes purgent `src/userplugins/` (cf. script `install.ps1` qui le vide) pour éviter les builds cassés
- **−** Aucun avantage fonctionnel vs injection dans `src/plugins/` puisqu'on contrôle déjà le build

**Rejeté :** aucun gain, et positionnement "deprecated" côté Vencord.

## Consequences

### Positives

- **Vencord toujours à jour.** Chaque installation/MAJ utilise le dernier commit `main` de l'upstream officiel. Les correctifs sécurité et Discord API sont propagés immédiatement, sans action humaine.
- **Plugin versionnable indépendamment.** Un bump de version du plugin (`VERSION` file) ne force pas un rebase Vencord. On peut shipper le plugin v3.2 sur n'importe quelle version Vencord.
- **Pas de dette de fork.** Zéro conflit de merge, zéro rebase à jour à faire.
- **Repo léger.** Le repo `toolbox/guildvoicemanager/` pèse ~40 Ko (plugin + scripts + docs) au lieu de 20 Mo pour un fork Vencord complet.
- **Audit plus simple.** Un contributeur ou reviewer n'a qu'à regarder `plugin/index.ts` et les installeurs — pas besoin de diff avec upstream.
- **Distribution ZIP = autoportante.** Le ZIP contient le plugin + les scripts, pas de dépendance sur un fork GitHub.
- **Réversibilité.** Désinstallation = `pnpm uninject` dans `~/Vencord` + suppression du dossier. Rien à nettoyer dans le fork (qui n'existe plus).

### Négatives

- **Dépendance forte sur la stabilité de l'API interne Vencord.** Si Vencord upstream change significativement `definePluginSettings`, `findStoreLazy`, ou `ApplicationCommandInputType`, le plugin casse à la prochaine MAJ sans warning. Mitigation : ces helpers sont stables depuis des années, changements annoncés sur le Discord dev Vencord.
- **L'utilisateur doit lancer l'installeur pour mettre à jour** — pas de "update auto" comme une extension de navigateur. Mitigation acceptable pour un plugin non-mainstream distribué à ~30 personnes.
- **Le temps d'installation est plus long qu'un simple `git pull` sur fork** (clone from scratch + build full). ~3-5 min sur connexion normale. Mitigation : le mode MAJ fait `git reset --hard` au lieu d'un re-clone complet.

### Neutres

- **Le plugin a du dupliquer la logique d'installation** (PowerShell + Bash). Pas d'évitement possible vu les différences OS.
- **L'utilisateur voit le dossier `~/Vencord` comme appartenant à Vencord upstream, pas au plugin.** Moins de confusion : le plugin est une "couche" par-dessus Vencord.

## Validation

Le nouveau flux est vérifiable à trois niveaux :

1. **Build des ZIPs** — `./installers/build.sh` doit produire deux ZIPs valides contenant scripts + plugin, avec `{{VERSION}}` substitué partout.
2. **Install from scratch** — Sur une machine sans `~/Vencord`, lancer `INSTALLER.bat`/`.command` depuis un ZIP extrait doit clone Vendicated/Vencord, injecter le plugin, builder, et patcher Discord.
3. **Mise à jour idempotente** — Relancer l'installeur sur un `~/Vencord` existant doit faire `git reset --hard origin/main` + re-inject + rebuild, sans perdre les settings Vencord utilisateur.

## Références

- [Vencord — Making Plugins](https://docs.vencord.dev/installing/) (doc officielle)
- [Vendicated/Vencord](https://github.com/Vendicated/Vencord) — repo upstream
- [SECURITY.md](./SECURITY.md) — modèle de menace
- [GOTCHAS.md](./GOTCHAS.md) — pièges rencontrés
