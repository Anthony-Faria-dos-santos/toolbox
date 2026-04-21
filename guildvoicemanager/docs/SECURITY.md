# Sécurité — GuildVoiceManager

Analyse du modèle de menace et des contrôles associés à l'installation et à l'exécution du plugin.

## Surface d'attaque globale

Le plugin consiste en :

1. **Code TypeScript** (`plugin/index.ts`) bundé dans Vencord au moment du `pnpm build`. Exécuté dans le renderer process de Discord desktop.
2. **Scripts d'installation** (`install.ps1`, `install.sh`, wrappers `.bat`/`.command`) qui téléchargent Vencord upstream, installent Node/Git/pnpm, et patchent le binaire Discord.

Ces deux composants ont des profils de menace distincts.

## Actifs protégés

| Actif | Exposition | Impact si compromis |
|---|---|---|
| Token Discord utilisateur | Accessible depuis le renderer Discord | Pire cas : prise de contrôle du compte Discord |
| Mots de passe stockés Discord (SSO, etc.) | Pas d'accès direct, mais accès mémoire renderer | Idem |
| Contrôle du salon vocal GvG | Action locale uniquement | Aucun (mute local, pas serveur) |
| Credentials système (Windows Defender, sudo) | Exposés par les scripts d'install | Exécution arbitraire en tant qu'admin/user |
| Binaires Discord installés | Patchés par `pnpm inject` | Persistance du patch entre redémarrages Discord |

## Acteurs

| Acteur | Accès | Intention supposée |
|---|---|---|
| Utilisateur final (joueur GvG) | Exécute `INSTALLER.bat` avec droits admin | Coopératif |
| Auteur du plugin (NIXshade) | Écrit `plugin/index.ts` et les installeurs | Coopératif (modèle `trust the author`) |
| Mainteneurs Vencord (Vendicated et al.) | Contrôlent le code upstream | Coopératifs (modèle `trust upstream`) |
| Attaquant réseau (MITM lors du clone git) | Passive : observe, active : peut injecter | Non-coopératif |
| Attaquant fournisseur CDN (Homebrew, npm, winget) | Peut altérer les binaires téléchargés | Non-coopératif |

## Contrôles implémentés

### 1. Transparence du code

Le plugin (`plugin/index.ts`) est un seul fichier de ~800 lignes, sans binaires, sans modules compilés, sans `eval()` ni chargement dynamique. **Auditable par n'importe qui lisant du TypeScript** en 20 minutes. Aucune obfuscation.

```typescript
// Extrait : la fonction centrale muteUser est directe et lisible
function muteUser(uid: string, name: string): boolean {
    if (mutedUsers.has(uid)) return false;
    const volume = MediaEngineStore.getLocalVolume(uid, "default") ?? 100;
    mutedUsers.set(uid, { name, volume });
    AudioActions.toggleLocalMute(uid);
    return true;
}
```

### 2. Pas d'exfiltration

Le plugin ne fait **aucune requête réseau sortante**. Il ne consomme que des stores Discord déjà peuplés côté client (`VoiceStateStore`, `GuildMemberStore`, `MediaEngineStore`). Pas de `fetch`, pas de `XMLHttpRequest`, pas de WebSocket externe, pas de `postMessage` vers une origine tierce.

Vérifiable par `grep` :

```bash
grep -iE 'fetch|XMLHttpRequest|WebSocket|postMessage|XHR' plugin/index.ts
# Doit retourner 0 occurrence
```

### 3. Mutes strictement locaux

Les mutes sont effectués via `AudioActions.toggleLocalMute(uid)`, qui est une action **client-only** : elle ne modifie pas l'état du serveur Discord et n'est pas visible par les autres utilisateurs. Aucune permission modérateur requise. Un utilisateur malveillant qui installe un fork compromis ne peut pas affecter les autres membres du salon.

### 4. Clone upstream officiel

Les installeurs clonent **uniquement** `https://github.com/Vendicated/Vencord.git` (HTTPS). Pas de miroir, pas de fork, pas d'URL configurable par l'utilisateur sans modif du script. Cette URL est dure-codée à la ligne `VENCORD_REPO` dans `install.ps1` et `install.sh`.

Si un futur contributeur veut ajouter un miroir, il doit modifier le script — ce qui est visible en diff et reviewable.

### 5. Droits admin uniquement pour Windows Defender

Sur Windows, les wrappers `INSTALLER.bat` / `MISE-A-JOUR.bat` demandent une élévation UAC **uniquement** pour configurer une exclusion temporaire Windows Defender sur `~/Vencord`. Cette exclusion est :

- **Strictement limitée à `$env:USERPROFILE\Vencord`** (pas le disque entier, pas le profil utilisateur)
- **Retirée en fin de script** via `Remove-MpPreference -ExclusionPath $INSTALL_DIR`
- **Optionnelle** : si l'élévation échoue ou que Defender n'est pas configurable, le script continue avec un warning

Sur macOS, **aucun droit root** n'est requis. Les installeurs tournent en user et invoquent Homebrew qui gère lui-même les élévations ponctuelles (permissions `/opt/homebrew/`).

### 6. Pas de désactivation globale de Defender

Certains scripts d'install tiers de mods Discord ajoutent des exclusions Defender permanentes sur `$env:USERPROFILE` entier, ou désactivent totalement la protection temps réel. **Notre script ne fait rien de tel.** L'exclusion est localisée et temporaire.

### 7. Pas de `pnpm install` arbitraire sur package.json compromis

Les installeurs exécutent `pnpm install` sur un `package.json` **qui vient d'être cloné depuis l'upstream Vendicated/Vencord**. Si l'upstream était compromis, `pnpm install` exécuterait des scripts de post-install arbitraires. C'est une menace **partagée avec tout utilisateur Vencord standard** — pas une introduction de notre part.

Mitigation partielle : `pnpm install --frozen-lockfile` est tenté en premier, ce qui interdit l'installation de versions non présentes dans `pnpm-lock.yaml`. Fallback sur `pnpm install` si le lockfile est désynchronisé.

### 8. Licence GPL-3.0

Le plugin hérite de la licence GPL-3.0-or-later de Vencord. Copyright © 2025 Anthony aka NIXshade. Toute modification distribuée doit rester open-source — barrière naturelle contre la distribution de forks malveillants non-auditables.

## Hypothèses de sécurité

Le modèle repose sur les hypothèses suivantes, **non vérifiées par ce projet** :

1. **L'upstream `Vendicated/Vencord` est de confiance.** Un compromis en amont compromet toute la chaîne. Les installeurs utilisent HTTPS mais ne vérifient pas la signature des commits.
2. **Les CDN de Homebrew, winget, et npm sont de confiance.** L'installation automatique de Git/Node/pnpm via ces gestionnaires repose sur leur intégrité.
3. **Le binaire Discord téléchargé par l'utilisateur est légitime.** Le `pnpm inject` patche un binaire existant — si ce binaire est déjà compromis, le plugin n'y peut rien.
4. **L'utilisateur a déjà accepté le risque Vencord.** Vencord est un client mod non-supporté par Discord — son usage viole les TOS Discord (risque de ban de compte, jamais observé en pratique mais théoriquement possible). Ce risque est **préexistant** et non introduit par le plugin.

## Hors périmètre

Les aspects suivants ne sont **pas** adressés par ce projet :

- Vérification cryptographique des scripts d'installation (pas de signature PowerShell, pas de notarization macOS — les wrappers gèrent les warnings SmartScreen/Gatekeeper manuellement)
- Vérification d'intégrité du clone Vencord (pas de `git verify-commit`, pas de pin sur un commit SHA)
- Sandboxing du renderer Discord (hors de notre contrôle)
- Protection contre un utilisateur root malveillant sur la machine cible (hors scope de tout programme user-mode)
- Protection contre un attaquant ayant déjà un accès physique à la machine

## Checklist de vérification post-installation

Pour un utilisateur paranoïaque qui veut valider l'install :

```bash
# 1. Vérifier que ~/Vencord pointe bien sur l'upstream officiel
cd ~/Vencord
git remote -v
# Attendu : origin  https://github.com/Vendicated/Vencord.git (fetch+push)

# 2. Vérifier que le plugin injecté = celui du repo toolbox
diff -r \
  ~/Vencord/src/plugins/guildVoiceManager \
  ~/toolbox/guildvoicemanager/plugin
# Attendu : aucune sortie (fichiers identiques)

# 3. Vérifier l'absence de requêtes réseau sortantes dans le plugin
grep -iE 'fetch|XMLHttpRequest|WebSocket|postMessage' \
  ~/Vencord/src/plugins/guildVoiceManager/index.ts
# Attendu : 0 occurrence

# 4. Vérifier qu'aucune exclusion Defender permanente n'a été ajoutée (Windows)
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
# Attendu : pas de chemin contenant "Vencord" si l'install s'est terminée normalement
```

## Références

- [Vencord — Are there any risks to using Vencord?](https://vencord.dev/#faq)
- [Discord TOS — Third-Party Clients](https://discord.com/terms) (section "Automated use")
- [ARCHITECTURE.md](./ARCHITECTURE.md) — décision de design
- [GOTCHAS.md](./GOTCHAS.md) — pièges techniques et mitigations
