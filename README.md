# toolbox

Monorepo personnel d'outils dev/cybersécurité maintenus par [Anthony Faria Dos Santos (NIXshade)](https://github.com/Anthony-Faria-dos-santos). Chaque sous-dossier est un projet autonome, auto-documenté, avec son propre README, ses propres scripts, sa propre licence.

## Projets

| Dossier | Rôle | Stack | Statut |
|---|---|---|---|
| [`supabase-scripts/`](supabase-scripts/README.md) | Anti-sleep auto-hébergé pour Supabase free tier (pg_cron + RLS + SECURITY DEFINER) | PostgreSQL, psql, Bash/PowerShell | ✅ Prod |
| [`guildvoicemanager/`](guildvoicemanager/README.md) | Plugin Vencord de gestion vocale GvG Discord (mute/unmute par rôle) + installeurs Windows/macOS | TypeScript, Vencord, PowerShell, zsh | ✅ Prod |

## Convention commune

Chaque projet suit la même structure documentaire :

```
<projet>/
├── README.md          ← entry point (En X étapes + arborescence + doc table + statut)
├── .gitignore         ← exclusions spécifiques au projet
├── docs/              ← documentation technique cross-cutting
│   ├── ARCHITECTURE.md  ← ADR : design, alternatives écartées, conséquences
│   ├── SECURITY.md      ← modèle de menace + contrôles
│   └── GOTCHAS.md       ← pièges rencontrés + workarounds numérotés
└── <sous-dossiers>/   ← code + sous-READMEs par section
```

Cette convention permet à un lecteur de naviguer n'importe quel projet sans contexte préalable : `README.md` donne le mode d'emploi en 3 commandes, `docs/` explique le pourquoi, le reste est le comment.

## Pré-requis généraux

- **Git** pour cloner et maintenir à jour
- **Node.js LTS** (≥ 20) si le projet le requiert (cf. README projet)
- **PostgreSQL client tools** (psql) pour `supabase-scripts/`
- **Discord desktop** pour `guildvoicemanager/`

Chaque projet liste ses pré-requis spécifiques dans son propre README.

## Licences

| Projet | Licence |
|---|---|
| `supabase-scripts/` | Usage personnel / interne |
| `guildvoicemanager/` | GPL-3.0-or-later (hérité de Vencord) |

## Auteur

Anthony Faria Dos Santos aka NIXshade — [@Anthony-Faria-dos-santos](https://github.com/Anthony-Faria-dos-santos)
