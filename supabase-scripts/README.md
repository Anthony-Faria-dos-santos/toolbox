# supabase-scripts

Anti-sleep auto-hébergé pour Supabase free tier. Empêche la mise en pause automatique d'un projet après 7 jours d'inactivité, via un job `pg_cron` interne — zéro service externe, zéro secret exposé, zéro coût.

## En 3 commandes

Pré-requis : psql installé + `pg_service.conf` configuré (voir [`psql/README.md`](psql/README.md)).

```bash
# 1. Installation
./psql/scripts/install.sh

# 2. Validation immédiate (60-120 s) — optionnel mais recommandé
./psql/scripts/test.sh

# 3. Checkup (à relancer périodiquement)
./psql/scripts/monitor.sh
```


## Arborescence

```
supabase-scripts/
├── README.md                  ← ce fichier (entry point)
├── .gitignore
├── docs/                      ← documentation technique cross-cutting
│   ├── ARCHITECTURE.md        ← ADR : pourquoi ce design (pg_cron + RLS + SECURITY DEFINER)
│   ├── SECURITY.md            ← modèle de menace et contrôles
│   └── GOTCHAS.md             ← pièges rencontrés + workarounds
├── sql/                       ← les 4 scripts SQL (le cœur du système)
│   ├── README.md              ← catalog + ordre d'exécution
│   ├── 01_install.sql         ← installation idempotente
│   ├── 02_test_forced.sql     ← test forcé pg_cron (60-120 s)
│   ├── 03_monitoring.sql      ← checkup read-only
│   └── 99_teardown.sql        ← désinstallation complète
└── psql/                      ← config psql + wrappers
    ├── README.md              ← setup pg_service.conf + .pgpass
    ├── pg_service.conf.example
    ├── pgpass.example
    └── scripts/               ← wrappers install/test/monitor/teardown
        ├── README.md
        ├── install.{ps1,sh}
        ├── test.{ps1,sh}
        ├── monitor.{ps1,sh}
        └── teardown.{ps1,sh}
```

## Documentation par section

| Cible | Fichier |
|---|---|
| **Pourquoi ce design, alternatives écartées** | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| **Modèle de sécurité, RLS, SECURITY DEFINER** | [`docs/SECURITY.md`](docs/SECURITY.md) |
| **Pièges rencontrés (timeout 58s, DO block, IPv6…)** | [`docs/GOTCHAS.md`](docs/GOTCHAS.md) |
| **Détail des 4 scripts SQL** | [`sql/README.md`](sql/README.md) |
| **Setup psql (pg_service.conf + .pgpass)** | [`psql/README.md`](psql/README.md) |
| **Utilisation des wrappers PowerShell/Bash** | [`psql/scripts/README.md`](psql/scripts/README.md) |

## Principe en une phrase

Un job `pg_cron` exécute toutes les 48 h (03:00 UTC) une fonction `SECURITY DEFINER` qui insère une ligne dans une table RLS-protégée sans policy, avec purge automatique > 90 jours. Aucune exposition réseau, aucun secret, aucun tiers.

Détail complet dans [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Clients SQL — compatibilité

| Client | Install | Test forcé | Monitoring | Teardown |
|---|---|---|---|---|
| **psql** CLI | ✅ | ✅ | ✅ | ✅ |
| **DataGrip** (JetBrains Student Pack gratuit) | ✅ | ✅ | ✅ | ✅ |
| **DBeaver Community** (open source) | ✅ | ✅ | ✅ | ✅ |
| **Supabase Studio** (SQL Editor web) | ✅ | ❌ (timeout 58 s) | ✅ | ✅ |

Connexion recommandée : **Session Pooler** (port 5432, IPv4). La Direct Connection Supabase est IPv6-only depuis fin 2024 — voir [`docs/GOTCHAS.md §4`](docs/GOTCHAS.md#4-direct-connection-ipv6-only).

## Dépannage express

Les pannes fréquentes sont décrites avec symptôme, cause et fix dans [`docs/GOTCHAS.md`](docs/GOTCHAS.md). Réflexes rapides :

| Symptôme | Pointer |
|---|---|
| Test forcé ne produit rien | [GOTCHAS §1](docs/GOTCHAS.md#1-do-block-invisible-au-worker-pg_cron) |
| `statement timeout` | [GOTCHAS §2](docs/GOTCHAS.md#2-supabase-studio-58s-timeout) |
| `column "ping_at" does not exist` | [GOTCHAS §7](docs/GOTCHAS.md#7-schéma-obsolète-lors-dune-ré-installation) |
| Rien dans `cron.job_run_details` après 48 h | Projet probablement en pause avant installation → reprendre depuis le Dashboard et relancer `01_install.sql` |

## Statut

✅ Installé et testé sur Supabase Cloud free tier (PostgreSQL 15, pg_cron natif).
✅ Test forcé validé (run pg_cron + insert confirmés).

## Licence

Usage personnel / interne.
