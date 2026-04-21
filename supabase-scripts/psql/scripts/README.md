# Wrappers psql

Scripts shell prêts à l'emploi pour exécuter les fichiers SQL du dossier [`../../sql/`](../../sql/) via psql, en s'appuyant sur la configuration [`pg_service.conf`](../README.md) mise en place au niveau du dossier parent.

Deux versions équivalentes sont fournies :
- **`.ps1`** pour PowerShell (Windows natif, PowerShell Core cross-platform)
- **`.sh`** pour Bash (WSL, macOS, Linux)

## Pré-requis

1. psql installé et dans le `PATH` (`psql --version` doit répondre)
2. Configuration psql en place : `~/.pg_service.conf` et `~/.pgpass` remplis avec les placeholders remplacés — voir [../README.md](../README.md) pour le setup complet
3. Au moins un service défini (`supabase-prod` par défaut)

## Catalogue

| Wrapper | Script SQL appelé | Durée | Confirmation | Destructif |
|---|---|---|---|---|
| `install.ps1` / `install.sh` | [`01_install.sql`](../../sql/01_install.sql) | < 5 s | non | non |
| `test.ps1` / `test.sh` | [`02_test_forced.sql`](../../sql/02_test_forced.sql) | 60-120 s | non | non |
| `monitor.ps1` / `monitor.sh` | [`03_monitoring.sql`](../../sql/03_monitoring.sql) | < 2 s | non | non (read-only) |
| `teardown.ps1` / `teardown.sh` | [`99_teardown.sql`](../../sql/99_teardown.sql) | < 2 s | **oui** (saisir `teardown`) | **oui** |

## Contrat des wrappers

Tous les wrappers :

- Acceptent un **premier argument positionnel** optionnel : le nom du service psql (par défaut `supabase-prod`). Utile si tu as plusieurs projets Supabase définis dans `pg_service.conf` (ex : `supabase-prod`, `supabase-staging`).
- Résolvent le chemin du `.sql` **relativement à leur propre emplacement**, donc fonctionnent quelle que soit le répertoire de lancement.
- Utilisent `psql -v ON_ERROR_STOP=1` pour stopper net à la première erreur SQL (pas d'exécution partielle silencieuse).
- Propagent le **code retour de psql** : `0` = succès, `!= 0` = échec. Exploitable dans des chaînes CI/CD ou scripts d'automatisation.

## Usage

### PowerShell (Windows natif, depuis la racine du repo)

```powershell
.\psql\scripts\install.ps1
.\psql\scripts\test.ps1
.\psql\scripts\monitor.ps1

# Avec un service autre que supabase-prod
.\psql\scripts\monitor.ps1 supabase-staging

# Teardown avec saut de la confirmation (automation)
.\psql\scripts\teardown.ps1 supabase-prod -Force
```

### Bash (WSL, macOS, Linux, depuis la racine du repo)

```bash
./psql/scripts/install.sh
./psql/scripts/test.sh
./psql/scripts/monitor.sh

# Avec un service alternatif
./psql/scripts/monitor.sh supabase-staging

# Teardown sans confirmation
./psql/scripts/teardown.sh supabase-prod --force
```

Sur Linux/macOS, vérifier que les `.sh` ont le bit exécutable :

```bash
chmod +x ./psql/scripts/*.sh
```

## Détail du wrapper `teardown`

Seul wrapper avec garde-fou interactif. Comportement par défaut (sans flag) :

```
[teardown] service=supabase-prod
           file=.../sql/99_teardown.sql
           DESTRUCTIF : supprime job pg_cron + fonction + table
Taper 'teardown' pour confirmer :
```

Tant que l'utilisateur ne tape pas **exactement** `teardown`, le script sort avec code `1` sans rien faire. Le flag `-Force` (PowerShell) ou `--force` (Bash, en second argument positionnel) skip la confirmation — utile pour les chaînes CI, à manier avec précaution.

## Codes retour

| Code | Signification |
|---|---|
| `0` | Succès complet |
| `1` | Annulation utilisateur (teardown sans confirmation valide) |
| `3` | Erreur SQL (syntax, permission, timeout… — propagé depuis psql) |
| autre | Erreur système (`psql` introuvable, fichier SQL absent, etc.) |

Exemple d'exploitation CI :

```bash
if ./psql/scripts/monitor.sh; then
  echo "Monitoring OK"
else
  echo "Monitoring a détecté un problème ou la connexion a échoué"
  exit 1
fi
```

## Personnalisation

Si tu veux ajouter un wrapper (par exemple `backup.sh` qui exporte la table en CSV), suis le template :

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:-supabase-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/../../backups/keepalive-$(date -u +%Y%m%dT%H%M%SZ).csv"

mkdir -p "$(dirname "${OUTPUT}")"
psql "service=${SERVICE}" -c "\copy (select * from public._keepalive order by ping_at) to '${OUTPUT}' with csv header"
echo "[backup] ${OUTPUT}"
```

## Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `psql: command not found` | psql pas dans le `PATH` | [Installer psql](../README.md#1-installer-psql), puis vérifier `psql --version` |
| `could not find service "supabase-prod"` | `pg_service.conf` absent ou au mauvais emplacement | [Voir setup psql](../README.md#2-copier-les-templates-au-bon-emplacement) |
| `no password supplied` | Entrée manquante dans `.pgpass` | Vérifier le format `host:port:db:user:password` |
| `statement timeout` pendant `test.ps1` | Pas un problème du wrapper — le SQL lui-même est en cause, ou tu as un `statement_timeout` forcé ailleurs | [Voir GOTCHAS §2](../../docs/GOTCHAS.md#2-supabase-studio-58s-timeout) |
| Test OK mais 0 ping inséré | Mode transaction manuel côté psql (très rare : psql est auto-commit par défaut) | Ajouter `--set=AUTOCOMMIT=on` ou vérifier absence de `.psqlrc` qui désactiverait l'autocommit |

## Références

- [../README.md](../README.md) — config psql complète (pg_service.conf + .pgpass)
- [../../sql/README.md](../../sql/README.md) — détail des scripts SQL appelés
- [../../docs/GOTCHAS.md](../../docs/GOTCHAS.md) — pièges techniques
