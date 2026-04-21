# Pièges rencontrés & contournements

Journal de bord technique des obstacles non-triviaux rencontrés lors de la mise en place du keepalive. Chaque entrée : symptôme, cause, solution, statut.

## Sommaire

1. [DO block invisible au worker pg_cron (transaction visibility)](#1-do-block-invisible-au-worker-pg_cron)
2. [Supabase Studio 58s timeout](#2-supabase-studio-58s-timeout)
3. [Permission denied sur `cron.jobid_seq`](#3-permission-denied-sur-cronjobid_seq)
4. [Direct connection IPv6-only (fin 2024)](#4-direct-connection-ipv6-only)
5. [DataGrip n'introspecte pas les schémas `cron` / `extensions`](#5-datagrip-nintrospecte-pas-les-schémas-cron--extensions)
6. [Cron expression `*/2` sur day-of-month](#6-cron-expression-2-sur-day-of-month)
7. [Schéma obsolète lors d'une ré-installation](#7-schéma-obsolète-lors-dune-ré-installation)

---

## 1. DO block invisible au worker pg_cron

### Symptôme

Le script `02_test_forced.sql` tourne jusqu'au bout, affiche `SCHEDULE CRON : MI HH24 * * *`, fait son `pg_sleep`, restaure le schedule, mais aucun run n'apparaît dans `cron.job_run_details` et aucune nouvelle ligne dans `public._keepalive`.

### Cause

Un bloc `DO $$ ... $$` s'exécute dans **une seule transaction**. Tant qu'elle n'a pas committé, les changements qu'elle effectue (dont `cron.alter_job`) sont invisibles pour les autres sessions — y compris le worker pg_cron qui vit dans son propre processus background.

Séquence observée :

```
t=0s    DO block démarre transaction
t=0s    cron.alter_job('keepalive', schedule='XX YY * * *')  ← invisible au worker
t=0s    pg_sleep(90)                                          ← transaction toujours ouverte
t=90s   cron.alter_job(...) restore '0 3 */2 * *'             ← toujours invisible
t=90s   DO block termine → COMMIT                             ← trop tard, le schedule
                                                                final est celui de prod
```

Le worker pg_cron voit en tout et pour tout : **rien**. Du début à la fin de la transaction, `cron.job.schedule = '0 3 */2 * *'`.

### Solution

Remplacer le `DO $$ ... $$` par une `CREATE PROCEDURE` + `CALL`. Les procédures (PG 11+) autorisent `COMMIT` au milieu du corps :

```sql
create or replace procedure public._keepalive_test_forced()
language plpgsql
as $$
begin
  -- ... setup ...
  perform cron.alter_job(v_jobid, schedule := v_target_schedule);
  commit;                                 -- ← visible au worker AVANT le sleep
  perform pg_sleep(v_sleep_seconds);
  perform cron.alter_job(v_jobid, schedule := '0 3 */2 * *');
  commit;
end;
$$;

call public._keepalive_test_forced();
```

Appliqué dans `sql/02_test_forced.sql` v2.

### Piège lié : mode transaction DataGrip

Même avec une `PROCEDURE`, si le client SQL force un mode **manual commit** (tx autour du `CALL`), le `COMMIT` interne à la procédure peut entrer en conflit. Dans DataGrip : **Data Source properties → Options → Tx : Auto**. psql en CLI est en auto-commit par défaut.

### Statut

✅ Résolu dans `sql/02_test_forced.sql` v2.

---

## 2. Supabase Studio 58s timeout

### Symptôme

Lancement de `02_test_forced.sql` dans le SQL Editor du Dashboard Supabase :

```
ERROR: canceling statement due to statement timeout
CONTEXT: SQL function "_keepalive_tick" statement 1
```

Le log Postgres montre : `SET statement_timeout TO '58s'` injecté automatiquement avant chaque requête, écrasant notre `set statement_timeout = '5min'` placé en tête de script.

### Cause

Supabase Studio hardcode un timeout de 58 secondes sur le SQL Editor web pour éviter les runaway queries côté utilisateur. Ce `SET` est appliqué après la connexion mais avant le script, donc notre réglage n'a aucun effet. Comportement non-débrayable (pas d'option utilisateur).

### Solution

Utiliser un client SQL **qui ne joue pas ce jeu** :

| Client | Timeout par défaut | Plan étudiant ? | Recommandation |
|---|---|---|---|
| **psql** CLI | aucun (illimité) | open source | ⭐ plus fiable |
| **DataGrip** (JetBrains) | configurable | oui (Student Pack gratuit) | ⭐ bonne DX |
| **DBeaver Community** | configurable | open source | OK |
| **pgAdmin 4** | configurable | open source | OK mais UI lourde |
| Supabase Studio | 58s forcé | n/a | ❌ à éviter pour ce test |

psql ou DataGrip en Session Pooler sont les deux voies validées dans ce repo.

### Statut

✅ Documenté, workaround clair.

---

## 3. Permission denied sur `cron.jobid_seq`

### Symptôme

Après avoir créé et supprimé plusieurs jobs pg_cron pendant la phase de mise au point, `cron.job.jobid` vaut par exemple 3 alors qu'un seul job existe. Tentative de reset :

```sql
select setval('cron.jobid_seq', 1, false);
-- ERROR: 42501: permission denied for sequence jobid_seq
```

### Cause

Sur Supabase Cloud, la séquence `cron.jobid_seq` appartient au rôle `supabase_admin` (principe de least privilege). L'utilisateur `postgres` exposé à l'user final n'a pas les droits de modification sur cette séquence. Impossible de contourner sans une connexion `supabase_admin` (non exposée par Supabase).

### Solution

Accepter le `jobid` tel quel — il est **purement cosmétique**. Tous les scripts de ce repo référencent le job par **`jobname = 'keepalive'`**, jamais par jobid. Exemples :

```sql
-- Bonne pratique (portable, indépendante de jobid)
select cron.alter_job(
  job_id   := (select jobid from cron.job where jobname = 'keepalive'),
  schedule := '0 3 */2 * *'
);

-- À éviter (hardcode fragile)
select cron.alter_job(3, schedule := '0 3 */2 * *');
```

### Option nucléaire (déconseillée)

Drop + recreate de l'extension `pg_cron` remet le compteur à zéro, mais détruit tous les jobs existants. Faisable uniquement si tu n'as **qu'un seul** job. Réservé aux cas désespérés :

```sql
drop extension pg_cron;
create extension pg_cron with schema extensions;
-- puis réinstaller via 01_install.sql
```

### Statut

✅ Contourné par convention (jobname partout).

---

## 4. Direct connection IPv6-only

### Symptôme

Connexion Direct depuis DataGrip / psql avec le host `db.<PROJECT_REF>.supabase.co` sur port 5432 → timeout silencieux ou `Network is unreachable`. Tout fonctionne depuis certains environnements (GitHub Actions, Vercel) mais pas depuis réseau domestique français typique.

### Cause

Supabase a migré la **Direct Connection** en **IPv6-only** fin 2024. La plupart des FAI résidentiels (Orange, Free, SFR, Bouygues) fournissent de l'IPv4 NAT par défaut, IPv6 optionnel et parfois buggé. Résultat : la résolution DNS renvoie une adresse AAAA que la machine ne sait pas router.

### Solution

Utiliser le **Session Pooler** (pgbouncer en mode session) :

```
Host     : aws-0-<REGION>.pooler.supabase.com    ← IPv4 + IPv6 dual-stack
Port     : 5432
User     : postgres.<PROJECT_REF>                 ← format spécial pooler
Database : postgres
SSL      : require
```

Le Session Pooler est **équivalent fonctionnellement** à une Direct Connection : sessions longues supportées, `pg_sleep` fonctionne, pas de limite "une requête à la fois" (contrairement au Transaction Pooler port 6543).

**Piège additionnel :** ne pas confondre avec le **Transaction Pooler** (port 6543). Celui-ci n'autorise pas `pg_sleep`, prepared statements, ou SET de session.

| Mode | Port | IPv4 | pg_sleep OK ? | Sessions longues ? |
|---|---|---|---|---|
| Direct | 5432 | ❌ (IPv6 only) | ✅ | ✅ |
| **Session Pooler** | **5432** | **✅** | **✅** | **✅** |
| Transaction Pooler | 6543 | ✅ | ❌ | ❌ |

### Statut

✅ Tous les templates de ce repo utilisent Session Pooler.

---

## 5. DataGrip n'introspecte pas les schémas `cron` / `extensions`

### Symptôme

Après connexion réussie, les appels `cron.schedule(...)`, `cron.alter_job(...)`, `public._keepalive_tick()` sont soulignés en rouge dans DataGrip avec *"Unresolved reference"*. L'autocomplete ne fonctionne pas sur `cron.`.

### Cause

DataGrip par défaut n'introspecte que le schéma `public`. Les schémas `cron`, `extensions`, `pg_catalog` ne sont pas analysés → aucune métadonnée locale → les symboles apparaissent comme inconnus.

### Solution

Data Source Properties (`F4`) → onglet **Schemas** → cocher :

- `public` (tes objets)
- `cron` (job, job_run_details, schedule, unschedule, alter_job)
- `extensions` (pg_cron installé ici, convention Supabase)
- `pg_catalog` (métadonnées système — autocomplete)
- `information_schema` (standard SQL — optionnel)

Ajouter `auth`, `storage`, `realtime`, `graphql`, `vault` si tu veux l'autocomplete sur les autres schémas Supabase. Plus tu coches, plus l'introspection est lente au premier lancement.

### Note

Sur Supabase Cloud, selon ton profil utilisateur, certaines fonctions `cron.*` peuvent ne pas être visibles en introspection même quand le schéma est coché. Elles restent **appelables** via SQL normal — seul l'autocomplete est absent. Non bloquant.

### Statut

✅ Configuration DataGrip documentée.

---

## 6. Cron expression `*/2` sur day-of-month

### Symptôme

Le schedule `0 3 */2 * *` (03:00 UTC un jour sur deux) génère les jours 1, 3, 5, ..., 29, 31. Au changement de mois, on passe du 31 au 2 → **écart de 3 jours** entre deux ticks (31 → 2 = skip du 1 du mois suivant).

### Cause

Le pattern `*/2` dans la spec cron signifie "toutes les 2 unités à partir de 0". Sur day-of-month (plage 1-31) : 1, 3, 5, ..., 31. La règle cron redémarre au jour 1 du mois suivant, mais 31 + 2 = 33, donc on saute au prochain match dans la liste base (1, 3, 5, ...) → le prochain match après le 31 est le 3 du mois suivant.

Concrètement :
- Mois à 31 jours : ticks le 29 et le 31 → prochain tick le 2 du mois suivant. Gap = 2 jours. ✅
- Mois à 30 jours : ticks le 29 → prochain tick le 1 du mois suivant. Gap = 2 jours. ✅
- Février (28/29) : ticks le 27 (ou 29 si bissextile) → prochain tick le 1 mars. Gap = 2 ou 1 jour. ✅

**En réalité, le gap max observable est de 2 jours**, pas 3 — j'ai corrigé le README initial qui disait 3 par excès de prudence. Reste strictement sous la limite de 7 j Supabase, donc non bloquant.

### Solution (optionnelle)

Si tu veux une cadence strictement régulière :

```sql
select cron.alter_job(
  job_id   := (select jobid from cron.job where jobname = 'keepalive'),
  schedule := '0 3 * * 1,4'   -- lundi + jeudi, 03:00 UTC
);
```

Garantit un gap de 3 jours max (jeudi → lundi suivant), toujours sous 7 j. Sémantique plus lisible.

### Statut

✅ Documenté, alternative fournie.

---

## 7. Schéma obsolète lors d'une ré-installation

### Symptôme

Relance de `01_install.sql` après une version antérieure (qui avait `id bigserial` + `last_ping` + `ping_count`) :

```
ERROR: 42703: column "ping_at" does not exist
```

### Cause

L'ancienne version du script utilisait `create table if not exists` avec un schéma différent. Le `if not exists` voit la table déjà là et **saute la création** → la nouvelle fonction tente d'insérer dans `ping_at` qui n'existe pas sur l'ancienne table.

### Solution

Appliqué dans `01_install.sql` v2 : force `drop table if exists ... cascade` avant `create`, garantissant un état propre à chaque exécution :

```sql
-- Nettoyage idempotence stricte
do $$ begin perform cron.unschedule('keepalive'); exception when others then null; end $$;
drop function if exists public._keepalive_tick();
drop table    if exists public._keepalive cascade;

-- Création propre
create table public._keepalive (ping_at timestamptz not null default now());
```

Coût : perte de l'historique de pings à chaque ré-installation. Accepté car la table est purement technique (45 lignes max).

### Statut

✅ Résolu dans `sql/01_install.sql` v2.

---

## Checklist de dépannage rapide

| Symptôme | Section | Fix en 1 ligne |
|---|---|---|
| Test forcé ne produit rien | [#1](#1-do-block-invisible-au-worker-pg_cron) | Utiliser la v2 avec PROCEDURE + COMMIT |
| `statement timeout` | [#2](#2-supabase-studio-58s-timeout) | Quitter Studio, utiliser DataGrip ou psql |
| `permission denied for sequence` | [#3](#3-permission-denied-sur-cronjobid_seq) | Ignorer le jobid, référencer par jobname |
| `Network unreachable` | [#4](#4-direct-connection-ipv6-only) | Passer sur Session Pooler port 5432 |
| Rouge dans DataGrip sur `cron.*` | [#5](#5-datagrip-nintrospecte-pas-les-schémas-cron--extensions) | Cocher `cron`, `extensions`, `pg_catalog` dans Schemas |
| Colonne `ping_at` does not exist | [#7](#7-schéma-obsolète-lors-dune-ré-installation) | Relancer `01_install.sql` v2 (drop + create) |

## Références

- [ARCHITECTURE.md](./ARCHITECTURE.md) — contexte et décisions
- [SECURITY.md](./SECURITY.md) — modèle de menace
- [PostgreSQL Docs — Stored Procedures & Transaction Control](https://www.postgresql.org/docs/current/plpgsql-transactions.html)
- [pg_cron FAQ](https://github.com/citusdata/pg_cron#faq)
