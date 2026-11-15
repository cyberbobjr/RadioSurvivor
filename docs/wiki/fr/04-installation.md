*English: [Installation](../en/04-installation.md)*

# Installation

## Quels mods activer

Un seul objet Workshop contient **trois mods**. Abonnez-vous une fois, puis cochez dans la liste **Mods** ceux que vous
voulez jouer.

| Mod | Mod ID | Ce qu'il apporte | Demande |
|---|---|---|---|
| Radio Survivor | `batman_RadioSurvivor` | La radio : seize voix d'IA (dont un marchand par ville) sur de vraies fréquences, leurs missions, l'onglet Radio du carnet, les factions | Core AI, Belt Walkie-Talkie, Signal Smoke |
| Living Knox | `batman_LivingKnox` | Des groupes de survivants PNJ avec foyers, besoins, routines, combats et fortifications ; leurs relations et accords, l'onglet Équipe du carnet | Core AI. **Incompatible** avec Bandits! et Project A-Life |
| Core AI | `batman_CoreAI` | Ce que les deux autres partagent : lien avec le pont, carnet entier (fenêtre, onglets Contacts, Missions et Réputation, vues des missions, zones sur la carte), missions, identité des personnages, historique des échanges, réputation, contacts, équipes | Signal Smoke |

- **Quoi cocher** : Radio Survivor, Living Knox, ou les deux. Chacun fonctionne sans l'autre.
- **Le Core** est exigé par les deux : le jeu l'active pour vous. Activé seul, il n'apporte rien de jouable.
- **Le pont** est toujours le même programme, sans réglage à changer : il sert les voix de Radio Survivor, les PNJ de
  Living Knox, ou les deux ([Le pont](05-pont-en-solo.md)).

Ce que change votre choix :

| Vous activez | Vous jouez |
|---|---|
| Radio Survivor | Des voix à la radio, leurs missions, le carnet avec son onglet Radio. Pas de groupes de PNJ. |
| Living Knox | Des groupes de PNJ dans le comté, avec le carnet complet (contacts, missions, réputation, équipe). Vous parlez à un PNJ avec **Ctrl+G** et le carnet, dans le chat local (`/say`) près de lui, ou par le menu du clic droit **Parler** ; il répond dans une bulle. Les relations et les accords avec les groupes viennent avec lui. |
| Les deux | Tout ce qui précède, dans le même carnet, avec en plus son onglet Radio. |

## Mods requis

| Mod | Mod ID | ID Workshop | Rôle |
|---|---|---|---|
| Belt Walkie-Talkie | `batman_BeltRadio` | 3817018338 | Talkie à la ceinture, règle d'émission commune (Radio Survivor seulement) |
| TooltipLib | `TooltipLib` | 3694097672 | Requis par Belt Walkie-Talkie |
| Signal Smoke | `batman_SignalSmoke` | 3811010882 | Fumigènes et fusées écoutés par le serveur (mission signal, fusée du passeur, fumée des secours) ; requis par les trois mods |

Sans Signal Smoke, le jeu ne charge aucun des trois mods ; sans Belt Walkie-Talkie, il ne charge pas Radio Survivor.
Living Knox seul n'a besoin ni de Belt Walkie-Talkie ni de TooltipLib.

**Incompatible** avec Bandits! (`Bandits2`) et Project A-Life (`ProjectALifeNPCs`) quand Living Knox est activé : un
seul moteur de PNJ par partie. Le sélecteur de mods de Build 42 signale le conflit.

## Solo

1. Abonnez-vous à l'objet Radio Survivor et aux mods requis (Belt Walkie-Talkie, TooltipLib et Signal Smoke) sur le
   Workshop Steam.
2. Au menu principal, **Mods** : activez les mods choisis. Ordre pour tous : **TooltipLib, Belt Walkie-Talkie, Signal
   Smoke, Core AI, Radio Survivor, Living Knox**.
3. Redémarrez complètement le jeu après une installation ou une mise à jour des mods.
4. Commencez une **nouvelle partie** (conseillé pour cette version de test). Les pages sandbox **Radio Survivor** et
   **Living Knox** regroupent les options des mods activés ([Options sandbox](09-options-sandbox.md)).
5. Lancez le pont avant de charger la partie : [Le pont en solo](05-pont-en-solo.md). Sans lui, le jeu
   fonctionne, mais les voix ne répondent que par des parasites et les PNJ restent muets.

## Multijoueur

- Chaque joueur et le serveur ont besoin de la **même version** et du **même ensemble** de mods.
- Les joueurs n'installent rien d'autre : le pont ne tourne que sur la machine du serveur.
- Serveur dédié : voir [Le pont sur un serveur dédié](06-pont-sur-serveur-dedie.md) (`WorkshopItems=`, `Mods=`).
- Partie hébergée depuis le menu (**Héberger**) : le pont tourne sur le PC de l'hôte, exactement comme en solo.

## Premiers pas en jeu

- **Radio** (Radio Survivor) : trouvez une note de fréquence dans le butin (clic droit → **Inspecter**), prenez un
  talkie ou une radio de radioamateur **en main** (ou une radio portée sur le dos), allumez-la, réglez-la, ouvrez le
  micro et tapez votre phrase dans la section **Émettre** de la fenêtre de la radio. Walt est la première voix à
  chercher.
- **PNJ** (Living Knox) : près d'un survivant, appuyez sur **Ctrl+G** pour le sélectionner, ou parlez dans le chat
  local (`/say`) : une phrase dite sans PNJ sélectionné va au plus proche à 8 cases. **Parler** dans le menu du clic
  droit marche aussi. Le bouton **Carnet** ouvre les contacts, les missions, la réputation et l'équipe.
