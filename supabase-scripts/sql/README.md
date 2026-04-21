# Scripts SQL

Les 4 scripts SQL qui composent le keepalive, de l'installation à la désinstallation. Conçus pour s'exécuter individuellement, dans l'ordre, sans dépendance extérieure.

## Vue d'ensemble

| # | Script | Rôle | Durée | Idempotent | Réversible | Client |
|---|---|---|---|---|---|---|
| 1 | `01_install.sql` | Installation complète (table + fonction + job cron) | < 5 s | ✅ | via `99_teardown.sql` | Studio OK, DataGrip/psql OK |
| 2 | `02_test_forced.sql` | Test forcé : déclenche un tick en 60-120 s | 60-120 s | ✅ | sans effet final (restaure le schedule prod) | ❌ Studio, ✅ DataGrip/psql |
| 3 | `03_monitoring.sql` | Checkup santé, 6 rapports read-only | < 2 s | ✅ (lecture seule) | n/a | Studio OK, DataGrip/psql OK |
| 4 | `99_teardown.sql` | Désinstallation complète (job + fonction + table) | < 2 s | ✅ | **non** (historique perdu) | Studio OK, DataGrip/psql OK |

## Ordre d'exécution

```
 01_install.sql                      (une fois, à la mise en place)
        │
        ▼
 02_test_forced.sql                  (optionnel, validation sans attendre 48 h)
        │
        ▼
 03_monitoring.sql                   (périodiquement : hebdo, ou ad hoc)
        │
        ▼
 99_teardown.sql                     (si désinstallation totale souhaitée)
```

Le script 2 est **optionnel** — on peut attendre 48 h que le cron se déclenche naturellement, et lancer le script 3 après pour vérifier. Le script 2 est là pour ceux qui veulent la confirmation immédiate.

## Détail des scripts

### `01_install.sql` — Installation

**Prérequis :**
- Projet Supabase actif (non en pause)
- Extension `pg_cron` disponible (native Supabase, activée par défaut ou à la première exécution du script)

**Effet :**
1. Active `pg_cron` dans le schéma `extensions` (`create extension if not exists`)
2. Nettoie tout état antérieur (`unschedule`, `drop function`, `drop table cascade`)
3. Crée `public._keepalive (ping_at timestamptz)` + index btree
4. Active RLS sans policy (bloque PostgREST)
5. Crée `public._keepalive_tick()` en `SECURITY DEFINER` avec `search_path = public`
6. Révoque `EXECUTE` à `PUBLIC`
7. Appelle la fonction une fois (validation applicative)
8. Programme le job `keepalive` avec `cron.schedule('keepalive', '0 3 */2 * *', ...)`

**Sortie attendue :**
- 1 ligne dans `public._keepalive`
- 1 ligne dans `cron.job` avec `active=true`

**Ré-exécution :** sûre. Le script commence par un nettoyage complet → état propre à chaque run, mais **l'historique des pings est perdu**. Acceptable car la table est purement technique.

### `02_test_forced.sql` — Test forcé

**Prérequis :**
- `01_install.sql` déjà exécuté
- Client SQL **sans timeout strict** (DataGrip ou psql, pas Studio — [voir GOTCHAS §2](../docs/GOTCHAS.md#2-supabase-studio-58s-timeout))
- Mode transaction **Auto-commit** côté client (DataGrip : Data Source → Options → Tx = Auto)

**Effet :**
1. Crée une `PROCEDURE public._keepalive_test_forced()` temporaire
2. Appelée via `CALL`, elle :
   - Capture les compteurs `before` (runs pg_cron, lignes `_keepalive`)
   - Calcule la minute UTC cible = `date_trunc('minute', now()) + 2 min`
   - Reprogramme temporairement le job sur cette minute (`cron.alter_job`)
   - **COMMIT** (rend le nouveau schedule visible au worker pg_cron — [voir GOTCHAS §1](../docs/GOTCHAS.md#1-do-block-invisible-au-worker-pg_cron))
   - `pg_sleep(target - now + 20s)` laisse le worker déclencher le job
   - Restaure le schedule de production (`0 3 */2 * *`)
   - **COMMIT**
   - Lit les compteurs `after` et rapporte via `RAISE NOTICE`
3. Drop de la procédure en fin de script (nettoyage)
4. Émet 3 rapports post-test (derniers runs, état table, schedule restauré)

**Sortie attendue :**

```
--- REPROGRAMMATION TEMPORAIRE ---
Heure cible UTC : 2026-04-21 14:29:00+00
Schedule cron   : 29 14 * * *
Attente : 78 s
--- RESULTAT ---
Runs pg_cron      avant/après : 0 / 1
Lignes _keepalive avant/après : 1 / 2
SUCCES : pg_cron a déclenché et la fonction a écrit en base
```

Et `select ... from cron.job where jobname = 'keepalive'` doit montrer `schedule = '0 3 */2 * *'` (restauré).

**En cas d'échec :** consulter `cron.job_run_details.return_message` pour l'erreur exacte du worker.

### `03_monitoring.sql` — Checkup

**Prérequis :**
- `01_install.sql` déjà exécuté

**Effet :** 6 requêtes en lecture seule :

| # | Rapport | Ce qu'on vérifie |
|---|---|---|
| 1 | Synthèse santé | Dernier ping, âge, verdict (OK / à surveiller / alerte) |
| 2 | Régularité 20 derniers pings | Écart entre pings (attendu ≈ 2 jours) |
| 3 | Historique pg_cron (20 derniers runs) | Statut, message retour, durée |
| 4 | Taux de succès 30 derniers runs | % succès, à 100 % en régime normal |
| 5 | Configuration du job | `schedule`, `active`, `command` |
| 6 | Taille table + nb lignes | Contrôle de non-croissance (doit rester ~45 lignes) |

**Utilisation type :** une fois par semaine, ou dès qu'un doute existe sur l'état du projet. Exécutable dans Studio (aucun risque de timeout, toutes les requêtes sont rapides).

### `99_teardown.sql` — Désinstallation

**Prérequis :** aucun (sûr même si l'installation est partielle).

**Effet :**
1. `cron.unschedule('keepalive')` avec catch d'exception si le job n'existe pas
2. `drop function if exists public._keepalive_tick()`
3. `drop table if exists public._keepalive cascade`
4. Vérification finale : 3 `exists(...)` qui doivent tous retourner `false`

**Ce qui reste en place :**
- L'extension `pg_cron` (inoffensive, peut être utilisée pour d'autres jobs)
- Aucune trace côté `public.*` ou `cron.job`

**⚠️ Destructif** : historique des pings **définitivement perdu**. Si tu veux conserver l'historique, exporte-le avant :

```sql
\copy (select * from public._keepalive) to 'keepalive_backup.csv' with csv header;
```

## Workflow complet type

```bash
# 1. Installation (via n'importe quel client)
psql service=supabase-prod -f sql/01_install.sql

# 2. Test de validation (DataGrip ou psql uniquement — pas Studio)
psql service=supabase-prod -f sql/02_test_forced.sql

# 3. Surveillance périodique
psql service=supabase-prod -f sql/03_monitoring.sql

# 4. (éventuel) Désinstallation
psql service=supabase-prod -f sql/99_teardown.sql
```

Les wrappers PowerShell / Bash équivalents sont dans [../psql/scripts/](../psql/scripts/).

## Références

- [../README.md](../README.md) — overview et quick start
- [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) — justification du design
- [../docs/SECURITY.md](../docs/SECURITY.md) — modèle de menace
- [../docs/GOTCHAS.md](../docs/GOTCHAS.md) — pièges rencontrés
- [../psql/README.md](../psql/README.md) — config psql
