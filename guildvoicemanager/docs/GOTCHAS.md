# Pièges rencontrés — GuildVoiceManager

Inventaire des pièges OS et pièges Vencord rencontrés lors du développement du plugin et de l'industrialisation des installeurs. Chaque entrée : symptôme, cause, fix.

---

## 1. SmartScreen Windows Defender

### Symptôme

Lors du double-clic sur `INSTALLER.bat`, Windows affiche une fenêtre bleue :

> **Windows a protégé votre ordinateur**
> Microsoft Defender SmartScreen a empêché le démarrage d'une application non reconnue. L'exécution de cette application peut mettre votre ordinateur en danger.

Le bouton "Exécuter quand même" n'est pas visible immédiatement — il faut cliquer d'abord sur "Informations complémentaires".

### Cause

Le script n'est pas **signé numériquement** par un certificat Authenticode EV reconnu. SmartScreen bloque par défaut tout exécutable téléchargé (marqueur `Zone.Identifier:3`) sans réputation établie.

### Fix

Côté utilisateur : cliquer "Informations complémentaires" → "Exécuter quand même". Le `LISEZMOI.txt` Windows contient ces instructions.

Côté signature : signer les scripts nécessiterait un cert Authenticode EV (~400€/an, open-source : plans éducation possibles via SSL.com ou Certum). Non adopté pour ce projet (scope trop étroit, distribution < 50 utilisateurs).

Alternative gratuite évaluée : Windows SDK `signtool` avec un self-signed cert — mais SmartScreen ne fait pas confiance aux cert sans chaîne à une CA publique, donc équivalent au non-signé.

---

## 2. Gatekeeper macOS

### Symptôme

Double-clic sur `INSTALLER.command` échoue avec :

> **"INSTALLER.command" ne peut pas être ouvert car Apple ne peut pas vérifier qu'il est exempt de logiciels malveillants.**

### Cause

macOS Gatekeeper bloque par défaut tout fichier exécutable non notarisé provenant du Web (marqueur extended attribute `com.apple.quarantine`). La notarisation Apple nécessite un Apple Developer Program (99 $/an + Xcode + processus async).

### Fix

Côté utilisateur : **clic droit sur `INSTALLER.command` → "Ouvrir"**, puis confirmer dans la popup Gatekeeper. Cette action ajoute une exception permanente pour ce fichier. Le `LISEZMOI.txt` macOS mentionne cette étape.

Alternative ligne de commande :

```bash
xattr -d com.apple.quarantine INSTALLER.command
# Puis double-clic fonctionne normalement
```

Alternative plus radicale (utilisateur averti) :

```bash
# Désactive Gatekeeper pour tous les .command (à éviter)
sudo spctl --master-disable
```

---

## 3. `pnpm` via Corepack

### Symptôme

Après installation de Node.js, la commande `pnpm install` échoue avec :

```
pnpm : le terme « pnpm » n'est pas reconnu comme nom d'applet de commande...
```

Ou sur macOS/Linux :

```
bash: pnpm: command not found
```

### Cause

Node.js LTS ≥ 16.10 inclut **Corepack**, un gestionnaire de package managers qui sert pnpm/yarn à la demande. Mais Corepack n'active pas pnpm par défaut — il faut soit :

1. `corepack enable && corepack prepare pnpm@latest --activate`
2. `npm install -g pnpm` (plus simple mais dépend du `npm` bundlé)

Sur Windows, même après `npm install -g pnpm`, le PATH n'est pas immédiatement mis à jour dans la session PowerShell courante.

### Fix

Les installeurs appliquent une cascade de fallbacks :

```powershell
if (-not (Test-Command "pnpm")) {
    npm install -g pnpm 2>$null
    Refresh-Path   # Recharge le PATH depuis le registre
}
if (-not (Test-Command "pnpm")) {
    corepack enable
    corepack prepare pnpm@latest --activate
    Refresh-Path
}
```

Si tout échoue : message explicite demandant à l'utilisateur de lancer `npm install -g pnpm` manuellement dans un nouveau terminal (pour rafraîchir le PATH).

---

## 4. `src/userplugins/` obsolète casse le build

### Symptôme

Un `pnpm build` sur un Vencord propre peut échouer avec :

```
error TS2307: Cannot find module '@plugins/userplugins/some-plugin' or its corresponding type declarations.
```

Ou plus insidieusement : le build passe mais Vencord crash au runtime avec des plugins utilisateurs résiduels (d'anciennes installations), car le bundle inclut des références cassées.

### Cause

Le dossier `src/userplugins/` est conservé par Vencord entre les `git reset --hard` si des plugins y ont été mis manuellement auparavant (il n'est pas tracké dans git mais n'est pas nettoyé par défaut). Quand le bundler scanne ce dossier et qu'il contient des fichiers obsolètes pointant vers des APIs disparues, tout casse.

### Fix

Les installeurs purgent explicitement `src/userplugins/` après le `git clone` ou `git reset --hard` :

```powershell
$userplugins = Join-Path $INSTALL_DIR "src\userplugins"
if (Test-Path $userplugins) {
    $items = Get-ChildItem $userplugins -Force
    if ($items.Count -gt 0) {
        Remove-Item -Recurse -Force "$userplugins\*"
    }
}
```

Ceci garantit que **seul** notre plugin injecté dans `src/plugins/guildVoiceManager/` sera bundé.

---

## 5. Plugin non chargé dans Vencord

### Symptôme

Après un `pnpm inject` réussi et un redémarrage Discord, GuildVoiceManager n'apparaît pas dans **Paramètres > Vencord > Plugins**.

### Cause fréquente #1 : build pas exécuté

L'installeur a copié le plugin dans `src/plugins/guildVoiceManager/` mais le bundle JS livré dans Discord contient la version précédente. Vencord ne charge pas dynamiquement — tout est compilé.

**Fix** : relancer `pnpm build` dans `~/Vencord/`.

### Cause fréquente #2 : export par défaut manquant

Vencord scanne `src/plugins/*/index.ts` et attend un `export default definePlugin(...)`. Si le fichier exporte via `export const plugin = ...` ou `export { plugin }`, il n'est pas chargé.

**Fix** : vérifier dans `plugin/index.ts` :

```typescript
export default definePlugin({
    name: "GuildVoiceManager",
    // ...
});
```

### Cause fréquente #3 : erreur TS silencieuse

Un `pnpm build` avec `--watch` affiche les erreurs TS en console, mais `pnpm build` one-shot dans certains cas continue avec des fichiers émis partiels. Si la compilation du plugin rencontre une erreur TS qui n'arrête pas le build global, Vencord charge un bundle où notre plugin est absent.

**Fix** : relancer `pnpm build` et surveiller attentivement la sortie. Chercher "GuildVoiceManager" dans les logs.

---

## 6. `pnpm inject` échoue sur Discord portable (Windows)

### Symptôme

```
Could not find Discord installation.
```

Alors que Discord est installé et fonctionne.

### Cause

`pnpm inject` (équivalent à `vencord-installer`) cherche Discord dans les emplacements standards : `%LOCALAPPDATA%\Discord\` pour une install user-level, ou `Program Files` pour une install system-wide. Les installations **portables** (extract direct d'un .zip dans un dossier custom) ne sont pas détectées.

### Fix

Deux options :

1. Réinstaller Discord via l'installeur officiel (user-level par défaut)
2. Utiliser le flag interactif : `pnpm inject` sans argument ouvre une UI qui accepte un chemin custom

Les installeurs tentent automatiquement le mode interactif en fallback :

```powershell
pnpm inject
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Injection auto echouee, lancement interactif..."
    pnpm inject   # Relance, cette fois en mode UI
}
```

---

## 7. Remote Git incorrect après changement de stratégie (fork → upstream)

### Symptôme

Un utilisateur ayant installé GuildVoiceManager via l'**ancien** installeur (qui clonait le fork `Anthony-Faria-dos-santos/Vencord`) relance un `MISE-A-JOUR.bat` du nouveau système. La MAJ semble fonctionner mais continue à pull depuis le fork — pas depuis l'upstream.

### Cause

`git remote get-url origin` renvoie toujours l'URL du fork car aucun re-pointage automatique n'a été fait. Le fork ne reçoit plus de commits (voir [ARCHITECTURE.md](./ARCHITECTURE.md)), donc l'utilisateur reste figé sur une version obsolète.

### Fix

Les nouveaux installeurs **détectent et corrigent** ce cas :

```powershell
$currentRemote = git remote get-url origin 2>$null
if ($currentRemote -ne $VENCORD_REPO) {
    Write-Warn "Remote origin = $currentRemote"
    Write-Warn "Re-pointage vers $VENCORD_REPO"
    git remote set-url origin $VENCORD_REPO
}
```

Cette bascule est transparente pour l'utilisateur. Elle s'exécute une seule fois — une fois le remote corrigé, les MAJ futures restent sur l'upstream.

---

## 8. DeprecationWarning Node.js pollue stdout

### Symptôme

Lors d'un `pnpm install`, des lignes comme :

```
(node:12345) [DEP0169] DeprecationWarning: `url.parse()` behavior is not standardized...
```

apparaissent sur stderr. Sur PowerShell, avec `$ErrorActionPreference = "Stop"`, ces lignes **déclenchent un arrêt** du script alors qu'elles sont purement informatives.

### Cause

PowerShell traite toute sortie sur stderr comme une erreur fatale si `$ErrorActionPreference = "Stop"`. Node, pnpm et certaines deps émettent des warnings sur stderr par convention Unix.

### Fix

Dans `install.ps1` :

```powershell
$ErrorActionPreference = "Continue"   # Au lieu de "Stop"
$env:NODE_NO_WARNINGS = "1"            # Supprime les DeprecationWarning
```

La gestion d'erreur est faite manuellement via `$LASTEXITCODE` après chaque commande critique. Cette approche est documentée en tête du script.

---

## 9. Build ZIP échoue sur filesystem FUSE / mount restreint

### Symptôme

Lors du `bash build.sh` sur certains environnements (WSL vers un mount SMB, Cowork FUSE, NFS), le ZIP résultat fait **0 octets** et des fichiers parasites `ziXXXXXX` apparaissent dans `dist/`.

### Cause

L'outil `zip` crée un fichier temporaire `ziXXXXXX` dans le dossier cible, puis fait un `rename(2)` atomique vers le nom final. Certains filesystems (FUSE mounts restreints, SMB sans POSIX locking, etc.) refusent le rename ou ne supportent pas le `unlink(2)` de l'ancien fichier.

### Fix

`build.sh` compresse dans `/tmp` (tmpfs local, support POSIX complet) puis copie vers `dist/` avec `cat > dest` — opération qui ne requiert que l'écriture, pas la suppression ni le rename :

```bash
local tmp_zip="${stage_dir}/${zip_name}"
( cd "${stage_dir}" && zip -qr "${tmp_zip}" "${stage_name}" )
# Ecriture non-destructive (truncate + rewrite) pour compat mounts restreints
cat "${tmp_zip}" > "${zip_path}"
```

Les ZIPs parasites `ziXXXXXX` laissés par l'ancienne logique peuvent être ignorés (gitignorés via le wildcard `dist/*`).

---

## Références

- [Vencord — Troubleshooting](https://docs.vencord.dev/installing/)
- [Node.js — Corepack](https://nodejs.org/api/corepack.html)
- [Microsoft — SmartScreen overview](https://learn.microsoft.com/en-us/windows/security/threat-protection/windows-defender-smartscreen/windows-defender-smartscreen-overview)
- [Apple — Gatekeeper](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)
- [ARCHITECTURE.md](./ARCHITECTURE.md) — décision de design upstream vs fork
- [SECURITY.md](./SECURITY.md) — modèle de menace
