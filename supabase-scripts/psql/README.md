# Templates psql pour Supabase

Configuration réutilisable basée sur les mécanismes standards PostgreSQL : `pg_service.conf` (connexions nommées) et `.pgpass` (mots de passe hors-commande). Pas d'export de variables d'env, pas de secrets en ligne de commande, pas d'alias qui sautent en changeant de machine.

## Pourquoi ce duo et pas un alias shell ?

| Approche | Portable | Sécurisé | Plusieurs envs | Standard |
|---|---|---|---|---|
| `alias psupa='psql "host=... password=..."'` | Non | Non (secret visible dans `ps`, `history`) | Non | Non |
| `export PGHOST=...` + `export PGPASSWORD=...` | Non (global au shell) | Moyen (variables d'env fuient via `/proc/*/environ`) | Non | Non |
| `~/.pg_service.conf` + `~/.pgpass` | **Oui** (fichiers reconnus par psql, libpq, psycopg, etc.) | **Oui** (permissions fichier, jamais dans la CLI) | **Oui** (un bloc par service) | **Oui** (doc officielle PostgreSQL) |

Bonus : ces fichiers sont lus aussi par **pgAdmin, DBeaver, Python (psycopg2/3), Node (pg), Go (pgx)**, etc. Tu configures une fois, tu utilises partout.

## Installation

### 1. Installer psql

**Windows (recommandé)** : télécharger les PostgreSQL command-line tools depuis https://www.postgresql.org/download/windows/ (section "Interactive installer by EDB" → tu peux décocher tout sauf **Command Line Tools** pendant l'install). Le binaire `psql.exe` se retrouve dans `C:\Program Files\PostgreSQL\<version>\bin\`.

**WSL / Linux Debian-based** :
```bash
sudo apt update && sudo apt install -y postgresql-client
```

**macOS** :
```bash
brew install libpq && brew link --force libpq
```

### 2. Copier les templates au bon emplacement

| OS | `pg_service.conf` | `.pgpass` |
|---|---|---|
| Linux / macOS / WSL | `~/.pg_service.conf` | `~/.pgpass` |
| Windows (natif) | `%APPDATA%\postgresql\.pg_service.conf` | `%APPDATA%\postgresql\pgpass.conf` |

**Windows PowerShell** :
```powershell
# Création du dossier si absent
New-Item -ItemType Directory -Force -Path "$env:APPDATA\postgresql" | Out-Null

# Copie des templates
Copy-Item psql\pg_service.conf.example "$env:APPDATA\postgresql\.pg_service.conf"
Copy-Item psql\pgpass.example          "$env:APPDATA\postgresql\pgpass.conf"
```

**Linux / macOS / WSL** :
```bash
cp psql/pg_service.conf.example ~/.pg_service.conf
cp psql/pgpass.example          ~/.pgpass
chmod 600 ~/.pgpass ~/.pg_service.conf   # CRITIQUE pour .pgpass
```

### 3. Remplir les placeholders

Édite les deux fichiers et remplace :

| Placeholder | Où le trouver |
|---|---|
| `PROJECT_REF` | Dashboard Supabase → URL de ton projet → `https://supabase.com/dashboard/project/<PROJECT_REF>` |
| `REGION` | Dashboard → Settings → Database → Connection string (host du pooler) |
| `MY_PASSWORD` | Ton mot de passe DB (ou **Settings → Database → Reset database password**) |

### 4. Tester la connexion

```bash
psql service=supabase-prod -c "select version();"
```

Tu dois voir `PostgreSQL 15.x on x86_64-pc-linux-gnu ...`. Si oui, c'est opérationnel.

## Usage quotidien

### Connexion interactive
```bash
psql service=supabase-prod
```

### Exécuter un script
```bash
psql service=supabase-prod -f sql/01_install.sql
psql service=supabase-prod -f sql/02_test_forced.sql
psql service=supabase-prod -f sql/03_monitoring.sql
```

### One-liner
```bash
psql service=supabase-prod -c "select count(*) from public._keepalive;"
```

### Avec sortie formatée
```bash
# Format tableau aligné (défaut)
psql service=supabase-prod -c "\x" -c "select * from cron.job;"

# Format CSV (utile pour pipe ou export)
psql service=supabase-prod --csv -c "select * from public._keepalive;" > pings.csv

# Mode expanded (une colonne par ligne, utile pour les lignes larges)
psql service=supabase-prod -x -c "select * from cron.job;"
```

### Alias shell (optionnel, pour gain de frappe)

**PowerShell** (`$PROFILE`) :
```powershell
function psupa        { psql service=supabase-prod @args }
function psupa-install { psql service=supabase-prod -f (Join-Path $PSScriptRoot 'sql\01_install.sql') }
function psupa-test    { psql service=supabase-prod -f (Join-Path $PSScriptRoot 'sql\02_test_forced.sql') }
function psupa-mon     { psql service=supabase-prod -f (Join-Path $PSScriptRoot 'sql\03_monitoring.sql') }
```

**Bash/Zsh** (`~/.bashrc` ou `~/.zshrc`) :
```bash
alias psupa='psql service=supabase-prod'
alias psupa-install='psql service=supabase-prod -f sql/01_install.sql'
alias psupa-test='psql service=supabase-prod -f sql/02_test_forced.sql'
alias psupa-mon='psql service=supabase-prod -f sql/03_monitoring.sql'
```

## Scripts wrappers fournis

Le dossier `psql/scripts/` contient des wrappers prêts à l'emploi :

| Script | Equivalent |
|---|---|
| `install.ps1` / `install.sh` | `psql service=supabase-prod -f sql/01_install.sql` |
| `test.ps1` / `test.sh` | `psql service=supabase-prod -f sql/02_test_forced.sql` |
| `monitor.ps1` / `monitor.sh` | `psql service=supabase-prod -f sql/03_monitoring.sql` |
| `teardown.ps1` / `teardown.sh` | `psql service=supabase-prod -f sql/99_teardown.sql` (avec confirmation) |

Usage depuis la racine du projet :
```powershell
# PowerShell
.\psql\scripts\install.ps1
.\psql\scripts\test.ps1
```
```bash
# Bash
./psql/scripts/install.sh
./psql/scripts/test.sh
```

Les scripts acceptent un argument optionnel pour choisir le service (par défaut `supabase-prod`) :
```bash
./psql/scripts/monitor.sh supabase-staging
```

## Sécurité

### Permissions fichier

`.pgpass` doit être en **600** sur Linux/macOS, sinon psql refusera de le lire (avec un warning `password contains plaintext`). Sur Windows, les permissions NTFS sont gérées automatiquement par l'OS.

Vérif :
```bash
ls -l ~/.pgpass ~/.pg_service.conf
# Attendu : -rw------- (600)
```

Correction si besoin :
```bash
chmod 600 ~/.pgpass ~/.pg_service.conf
```

### Rotation des mots de passe

Quand tu fais **Settings → Database → Reset database password** sur Supabase :
1. Mets à jour `.pgpass` avec le nouveau mot de passe
2. Aucune autre action : `pg_service.conf` ne contient pas de secret

### Audit via `application_name`

Chaque service déclare un `application_name` unique. Tu peux retrouver tes sessions dans Postgres :

```sql
select pid, usename, application_name, state, query_start, query
from pg_stat_activity
where application_name like 'psql-supabase%'
order by query_start desc;
```

Utile pour le debug (savoir d'où vient une requête longue) et pour l'audit sécurité.

### Ne jamais commit

Les fichiers `pg_service.conf` et `pgpass` **sans** le suffixe `.example` sont exclus du Git via le `.gitignore` du projet. Les `.example` sont versionnés et ne contiennent aucun secret (juste les placeholders).

## Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `could not find service "supabase-prod"` | Fichier pas au bon emplacement | Vérifier avec `psql service=supabase-prod -c "select 1"` en ayant bien copié aux chemins du tableau ci-dessus |
| `WARNING: password file "..." has group or world access; permissions should be u=rw (0600)` | Permissions trop ouvertes | `chmod 600 ~/.pgpass` |
| `no password supplied` | Entrée manquante dans `.pgpass` | Vérifier que `hostname:port:database:username` matche exactement `pg_service.conf` |
| `connection refused` | Région ou pooler incorrect | Recopier host depuis Dashboard Supabase → Settings → Database → Session pooler |
| `SSL error: certificate verify failed` | `sslmode=verify-full` sans CA configuré | Utiliser `sslmode=require` (déjà le défaut dans nos templates) |
| `FATAL: Tenant or user not found` | Username mal construit | Format obligatoire : `postgres.PROJECT_REF` (avec point) |
