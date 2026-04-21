# GuildVoiceManager

Plugin Vencord — gestion vocale GvG (Guerre de Guilde) : mute/unmute local par rôle Discord, avec mémorisation et restauration du volume original.

> **Local uniquement** : chaque joueur mute côté client ce qu'**il** entend. Aucune action serveur, aucune permission modération requise.

## Commandes

| Commande | Effet |
|---|---|
| `/gvg` | Commande principale : auto-transfert dans le salon GvG + mute par rôle + message dynamique |
| `/gvgcheck` | Appel des troupes : comptage par rôle (objectif 30) |
| `/unmute` | Unmute tout le monde, restaure les volumes originaux |
| `/muted` | Liste des joueurs actuellement mutés avec leur volume d'origine |
| `/vdebug` | Diagnostic complet (stores Discord, rôles, état interne) |
| `/gvghelp` | Aide des commandes |

## Rôles (configurables)

7 rôles Discord utilisés pour le routage des mutes :

- **Groupes** : `ATK`, `DEF`, `ROM`
- **Leaders** : `L.ATK`, `L.DEF`, `L.ROM`
- **Chef** : `Chief.L`

Tous modifiables depuis **Paramètres > Vencord > Plugins > GuildVoiceManager**.

## Flux type

```
/gvgcheck       → vérifier qui est présent par rôle
  ↓
/gvg            → rejoint le salon, mute les autres groupes, envoie le message
  ↓
(GvG en cours)
  ↓
/unmute         → restaure tous les volumes
```

## Règles

- Toutes les commandes (sauf `/unmute`) ne fonctionnent que **dans le salon vocal GvG configuré**.
- Les volumes originaux sont sauvegardés avant chaque mute (`MediaEngineStore.getLocalVolume`) et restaurés à `/unmute`. Aucun volume écrasé à 100.
- La mémoire interne (`mutedUsers` Map) est volatile : remise à zéro à chaque `/unmute` ou redémarrage Discord.

## Installation

Ce plugin n'est **pas** destiné à être copié-collé manuellement. Utiliser les installeurs fournis dans [`../installers/`](../installers/) qui clonent le Vencord officiel, injectent le plugin, installent les dépendances et compilent.

## Licence

GPL-3.0-or-later (comme Vencord). Copyright © 2025 Anthony aka NIXshade.

## Auteur

Anthony aka NIXshade — [@Anthony-Faria-dos-santos](https://github.com/Anthony-Faria-dos-santos)
