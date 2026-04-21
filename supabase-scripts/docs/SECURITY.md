# Modèle de sécurité

Analyse des menaces et contrôles en place pour le keepalive. Ce document complète [ARCHITECTURE.md](./ARCHITECTURE.md) en détaillant **qui peut faire quoi**, **ce qui est protégé** et **ce qui est hors périmètre**.

## Actifs protégés

| Actif | Sensibilité | Raison |
|---|---|---|
| Fonction `public._keepalive_tick()` | Faible | Exécute un INSERT + DELETE borné. Pas de donnée sensible, mais rôle de test du fonctionnement système. |
| Table `public._keepalive` | Très faible | Ne contient qu'un timestamp. Aucune PII, aucun secret. |
| Job pg_cron `keepalive` | Faible | Si modifié par un attaquant, perte du mécanisme anti-pause. Pas d'impact direct données. |
| Configuration `cron.job` | Moyen | Partagée avec d'autres jobs éventuels (hors scope ici). Un attaquant pourrait y greffer un job malveillant. |

## Acteurs

| Rôle PostgreSQL | Source | Privilèges sur nos objets |
|---|---|---|
| `anon` | PostgREST / API publique | **Aucun** (bloqué par RLS sans policy) |
| `authenticated` | PostgREST / utilisateurs loggés Supabase Auth | **Aucun** (bloqué par RLS sans policy) |
| `service_role` | PostgREST avec JWT service | **Tous** sur `public._keepalive` (bypass RLS par design) |
| `postgres` | Connexion directe (DataGrip, psql, pg_cron) | **Tous** (propriétaire de la table et de la fonction) |
| `supabase_admin` | Interne Supabase | **Tous** (superuser scope projet) |
| Attaquant anonyme | Internet | **Aucun** (pas d'endpoint exposé) |

## Contrôles implémentés

### 1. Isolation PostgREST via RLS sans policy

```sql
alter table public._keepalive enable row level security;
-- Aucune CREATE POLICY volontairement
```

**Effet :** RLS activé + zéro policy = deny par défaut pour tout rôle qui respecte RLS (`anon`, `authenticated`). Même si PostgREST exposait l'endpoint `/rest/v1/_keepalive`, aucune ligne ne serait retournée, aucun INSERT/UPDATE/DELETE ne passerait.

**Limites :** `service_role` bypass RLS — c'est intentionnel côté Supabase. Si tu exposes `service_role` côté client, tu perds cette garantie. Ne jamais mettre `service_role` dans un navigateur.

**Vérification :**
```sql
select rowsecurity, hasrules from pg_tables
where schemaname = 'public' and tablename = '_keepalive';
-- Attendu : rowsecurity = true
```

### 2. SECURITY DEFINER + search_path figé

```sql
create function public._keepalive_tick()
returns void
language sql
security definer
set search_path = public   -- ← critique
as $$ ... $$;
```

**Effet :** la fonction s'exécute avec les privilèges de son **propriétaire** (`postgres`), pas de l'appelant. Le `search_path = public` explicite immunise contre l'attaque **schema injection** : même si un appelant malveillant modifie son propre `search_path` avant l'appel, la fonction ne résoudra pas `_keepalive` ailleurs que dans `public`.

**Pourquoi c'est nécessaire :** une fonction SECURITY DEFINER sans `search_path` fixé est un anti-pattern documenté. Un attaquant peut créer une table `attaquant._keepalive` et forcer `search_path = attaquant, public`, détournant l'INSERT vers sa propre table. Le `set search_path = public` ferme cette porte.

**Référence :** [PostgreSQL docs — Writing SECURITY DEFINER Functions Safely](https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY).

### 3. REVOKE EXECUTE FROM PUBLIC

```sql
revoke execute on function public._keepalive_tick() from public;
```

**Effet :** aucun rôle autre que le propriétaire (`postgres`) ne peut invoquer la fonction. pg_cron tourne sous `postgres`, donc il conserve le droit. Un client PostgREST ne peut pas appeler la fonction via `rpc()`.

**Vérification :**
```sql
select grantee, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name = '_keepalive_tick';
-- Attendu : aucune ligne pour anon/authenticated/PUBLIC
```

### 4. Zéro secret stocké

| Élément | Contient un secret ? |
|---|---|
| Scripts SQL versionnés | Non |
| Table `public._keepalive` | Non (juste timestamps) |
| Fonction `_keepalive_tick` | Non |
| Cron expression | Non |
| Tous les fichiers `.example` | Non (placeholders) |

Les seuls endroits où transite un secret (mot de passe DB, token PAT) : les fichiers locaux `~/.pgpass` et `~/.pg_service.conf` exclus via `.gitignore`, et la mémoire du client SQL utilisateur.

### 5. Aucune exposition réseau ajoutée

Le job pg_cron s'exécute **intra-Postgres**. Pas de nouveau port ouvert, pas de nouvel endpoint HTTP, pas de webhook outbound. La surface d'attaque du projet Supabase est strictement inchangée par rapport à l'état pré-installation.

### 6. Purge automatique (rétention bornée)

```sql
delete from public._keepalive where ping_at < now() - interval '90 days';
```

**Effet :** la table reste à ~45 lignes max. Pas d'accumulation de données indéfinie, pas de risque de saturation disque lié au keepalive.

## Hypothèses de sécurité

Ces contrôles fonctionnent **sous réserve que les hypothèses suivantes restent vraies** :

1. **Le rôle `postgres` n'est pas compromis.** Si un attaquant obtient le mot de passe `postgres`, il peut tout faire. Mitigation : rotation régulière via *Settings → Database → Reset database password*, et utilisation du Session Pooler qui log chaque connexion.
2. **`service_role` n'est jamais exposé côté client.** Le keepalive ne protège pas contre ce scénario — aucun contrôle technique de notre repo ne peut le faire.
3. **Supabase n'introduit pas de régression sur RLS.** Hypothèse raisonnable (RLS est un contrat PostgreSQL natif).
4. **L'extension `pg_cron` n'est pas désactivée.** Si Supabase désactive `pg_cron` en free tier, le keepalive cesse sans alerte. Le monitoring détecte cette situation.
5. **Le worker pg_cron reste sain.** Pas de contrôle direct côté user ; observabilité via `cron.job_run_details`.

## Hors périmètre

Ce modèle **ne protège pas contre** :

- **Compromission du compte Supabase** (phishing, vol de session web, etc.)
- **Compromission du laptop utilisateur** (keylogger, RAT, etc.)
- **Attaques supply-chain côté extensions** (un pg_cron backdooré, hors de portée user)
- **DoS du worker pg_cron** (le worker est partagé Supabase-side, pas tunable user)
- **Exfiltration par un admin Supabase** (trust model Supabase, hors scope)
- **Fuite via logs PostgreSQL** (les INSERT sont journalisés ; ce n'est pas un problème car la donnée est publique et non-sensible)

## Vérification de posture après installation

Checklist à dérouler post-`01_install.sql` :

```sql
-- 1. RLS actif
select rowsecurity from pg_tables
 where schemaname = 'public' and tablename = '_keepalive';
-- true

-- 2. Aucune policy (deny par défaut)
select count(*) from pg_policies
 where schemaname = 'public' and tablename = '_keepalive';
-- 0

-- 3. Fonction SECURITY DEFINER avec search_path fixé
select prosecdef, proconfig
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = '_keepalive_tick';
-- prosecdef=true, proconfig={search_path=public}

-- 4. PUBLIC n'a pas EXECUTE
select has_function_privilege('public', 'public._keepalive_tick()', 'execute');
-- false

-- 5. Propriétaire = postgres
select pg_get_userbyid(proowner)
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = '_keepalive_tick';
-- postgres
```

Les 5 assertions doivent passer. Sinon, réinstaller via `01_install.sql` qui réapplique l'état propre.

## Références

- [PostgreSQL — Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [PostgreSQL — Writing SECURITY DEFINER Functions Safely](https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY)
- [Supabase — Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- [OWASP — SQL Injection via search_path](https://owasp.org/www-community/attacks/SQL_Injection)
- [ARCHITECTURE.md](./ARCHITECTURE.md) — justification du design
- [GOTCHAS.md](./GOTCHAS.md) — pièges pratiques rencontrés
