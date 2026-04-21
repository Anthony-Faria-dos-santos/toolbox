# ADR-001 — Keepalive Supabase via pg_cron interne

**Statut :** Accepté — 2025-04
**Auteur :** Anthony Faria Dos Santos
**Scope :** `toolbox/supabase-scripts/`

---

## Context

Supabase free tier met en pause automatique tout projet après **7 jours sans activité DB**. Une pause :
- Rend le projet inaccessible côté API jusqu'à réactivation manuelle
- Interrompt les connecteurs externes (webhooks, jobs externes, app mobile/web)
- Casse la chaîne de dépendance pour n'importe quel service qui s'appuie dessus

Pour un projet en cours de développement ou en démo permanente, ce comportement est bloquant. Il faut donc une source d'activité récurrente, idéalement :

1. **Sans service externe** (pas de cron externe, pas de Vercel function, pas de GitHub Actions avec secret DB)
2. **Sans secret exposé** (mot de passe DB nulle part en dehors de la DB elle-même)
3. **Sans dépendance à l'infra utilisateur** (pas de laptop allumé, pas de VPS)
4. **À coût nul** (pas de nouveau plan, pas de nouveau service)
5. **Réversible** (désinstallation en un script)

## Decision

Utiliser **l'extension native `pg_cron` de Supabase** pour exécuter un job SQL interne toutes les 48 h, qui insère une ligne dans une table dédiée.

Composants :

```
┌─────────────────────────────────────────────────────────────┐
│  PostgreSQL (Supabase Cloud)                                │
│                                                             │
│  ┌──────────────────┐       schedule '0 3 */2 * *'          │
│  │  pg_cron worker  │ ─────────────────────────────┐        │
│  │  (background)    │                              ▼        │
│  └──────────────────┘       ┌─────────────────────────────┐ │
│                             │ public._keepalive_tick()    │ │
│                             │ SECURITY DEFINER            │ │
│                             │ search_path = public        │ │
│                             └──────────────┬──────────────┘ │
│                                            │                │
│                                            ▼                │
│                             ┌─────────────────────────────┐ │
│                             │ public._keepalive           │ │
│                             │ (ping_at timestamptz)       │ │
│                             │ RLS enabled, 0 policy       │ │
│                             └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

Détail des choix internes :

| Élément | Choix | Justification |
|---|---|---|
| Extension | `pg_cron` | Native Supabase, pas de dépendance ajoutée, exécution intra-PostgreSQL |
| Cadence | `0 3 */2 * *` (03:00 UTC, un jour sur deux) | Marge confortable sous la limite de 7 j, horaire off-peak |
| Table | Append-only, colonne unique `ping_at timestamptz` | Schéma minimal, pas de PK synthétique, pas d'ID à gérer |
| Rétention | Purge > 90 jours à chaque tick | ~45 lignes max en régime permanent, volume négligeable |
| Index | btree sur `ping_at` | Accélère la requête de purge et les rapports de monitoring |
| RLS | Activé **sans aucune policy** | Bloque PostgREST (anon, authenticated) par défaut deny |
| Fonction | `SECURITY DEFINER` + `search_path = public` explicite | Immune au schema injection, exécute avec les droits du propriétaire |
| Autorisations | `REVOKE EXECUTE ... FROM PUBLIC` | Seul `postgres` peut l'invoquer (pg_cron tourne sous ce rôle) |

## Alternatives considérées

### A. Webhook HTTP externe (GitHub Actions, Vercel cron, etc.)

- **+** Indépendant de pg_cron
- **−** Nécessite de stocker un secret (URL + clé) dans le système externe
- **−** Dépend de la disponibilité du service tiers
- **−** Ajoute un point de défaillance réseau
- **−** Surface d'attaque élargie (endpoint HTTP exposé)

**Rejeté :** viole les contraintes 1, 2 et 5 (désinstallation multi-système).

### B. Laptop + cron local

- **+** Zéro nouvel outil
- **−** Nécessite laptop allumé 24/7
- **−** Secret DB sur poste utilisateur
- **−** Casse si changement de machine, VPN, coupure réseau

**Rejeté :** viole les contraintes 2 et 3.

### C. Supabase Edge Function programmée

- **+** Reste dans l'écosystème Supabase
- **−** Les Edge Functions n'ont pas de scheduler natif en free tier à date
- **−** Nécessite tout de même un déclencheur externe (même problème que A)

**Rejeté :** ne résout pas le problème, décale le déclencheur externe.

### D. Requête HTTP fake contre l'API (`select 1` via PostgREST)

- **+** Trivial à mettre en place
- **−** Toujours besoin d'un déclencheur externe
- **−** Nécessite de gérer la clé anon ou JWT

**Rejeté :** équivalent à A avec les mêmes défauts.

### E. `pg_cron` + fonction sans table (juste `SELECT 1`)

- **+** Plus minimaliste
- **−** Un `SELECT` pur peut être considéré comme "pas d'activité DB" par le heuristique de Supabase (non documenté, mais observé en pratique)
- **−** Impossible de monitorer un historique d'exécutions côté applicatif

**Rejeté :** risque de ne pas déclencher le reset du compteur d'inactivité, et impossibilité de vérifier a posteriori.

## Consequences

### Positives

- **Zéro secret à gérer.** Tout vit dans PostgreSQL, aucun token, aucune URL, aucune clé à stocker ailleurs.
- **Zéro dépendance externe.** Aucun service tiers ne peut tomber en panne.
- **Zéro coût.** `pg_cron` est inclus dans le free tier.
- **Surface d'attaque nulle.** Aucun nouvel endpoint réseau.
- **Auditable.** `cron.job_run_details` garde l'historique d'exécution, `public._keepalive` garde l'historique fonctionnel.
- **Réversible en 1 script** (`99_teardown.sql`).
- **Portable** : fonctionne sur toute instance PostgreSQL avec `pg_cron` (pas spécifique Supabase).

### Négatives

- **Nécessite un client SQL sans timeout strict** pour exécuter le test forcé (`02_test_forced.sql` dure 60-120 s). Le SQL Editor de Supabase Studio impose un `statement_timeout='58s'` non-débrayable, donc le test doit passer par DataGrip, DBeaver, psql ou équivalent. Voir [GOTCHAS.md](./GOTCHAS.md#2-supabase-studio-58s-timeout).
- **Dépend de `pg_cron` restant activé.** Si un futur reset du projet désactive l'extension, le keepalive s'arrête silencieusement. Mitigation : le monitoring (`03_monitoring.sql`) détecte cette situation.
- **Dépend du worker pg_cron étant sain.** Si le background worker crash sans être redémarré, les ticks sautent. Mitigation : même monitoring.
- **Gap potentiel de 3 jours fin de mois.** Le cron `*/2` sur day-of-month saute du 31 au 2 du mois suivant. Reste strictement sous la limite de 7 j, mais alternative possible `0 3 * * 1,4` (lundi + jeudi) pour une cadence plus régulière. Voir [GOTCHAS.md](./GOTCHAS.md#6-cron-expression-2-sur-day-of-month).

### Neutres

- **Le `jobid` pg_cron n'est pas configurable côté user** sur Supabase Cloud (la séquence `cron.jobid_seq` appartient à `supabase_admin`). Impact purement cosmétique : on référence toujours par `jobname = 'keepalive'`, pas par jobid.

## Validation

Le comportement est vérifiable à trois niveaux :

1. **Installation** (`01_install.sql`) — vérifie que le job apparaît dans `cron.job` avec `active=true`.
2. **Test forcé** (`02_test_forced.sql`) — reprogramme temporairement à 2 minutes dans le futur, attend, vérifie qu'un run est bien enregistré dans `cron.job_run_details` et qu'une ligne est bien insérée dans `public._keepalive`, puis restaure le schedule de production.
3. **Monitoring périodique** (`03_monitoring.sql`) — 6 requêtes read-only pour santé, régularité, historique, taux de succès, config et taille de table.

## Références

- [pg_cron documentation officielle](https://github.com/citusdata/pg_cron)
- [Supabase — pg_cron Extension](https://supabase.com/docs/guides/database/extensions/pg_cron)
- [PostgreSQL — CREATE FUNCTION SECURITY DEFINER](https://www.postgresql.org/docs/current/sql-createfunction.html)
- [SECURITY.md](./SECURITY.md) — analyse du modèle de menace
- [GOTCHAS.md](./GOTCHAS.md) — pièges rencontrés et contournements
