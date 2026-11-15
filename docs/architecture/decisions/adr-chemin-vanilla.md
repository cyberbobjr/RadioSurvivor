# ADR — Déplacements des PNJ : chemin du jeu, détour seulement après un refus

| | |
|---|---|
| Date | 2026-11-15 (révisée le même jour, voir « Révision ») |
| Statut | Accepté |
| Décideur | utilisateur |
| Remplace | le guidage « porte d'abord » de LK04-T09 et ses suites : le modèle « zombie » qui prédit le chemin natif, le jalonnement en lignes dégagées, la sortie forcée par une porte, le dernier recours par points de passage et la prudence après une fenêtre refusée (LK05-T23) |
| Plan associé | [LK17 — Chemin du jeu pour les PNJ](../../annexes/plans/LK17-chemin-vanilla.md) |
| Références | Sources Java 42.22 : `zombie/pathfind/SearchNode.java:86-90`, `PathFindRequest.java:44-80`, `nativeCode/PathFindRequest.java:51-96`, `nativeCode/PathfindNative.java:54`, `:120-135` et `:276-312`, `iso/IsoWorld.java:2066`, `debug/DebugOptions.java:76`, `zombie/ai/MapKnowledge.java`. Base de connaissances : `.claude/pz-knowledge/pathfinding-and-obstacles.md` |

## Contexte

Les PNJ de Living Knox ont un corps de zombie, et le moteur calcule leur chemin comme celui d'un zombie. Dans le moteur
Java, une fenêtre ne coûte rien à un zombie (`SearchNode.java:86-90`) et un zombie peut cogner pour passer
(`PathFindRequest.java:58`). Le chemin natif traverse donc des fenêtres que Living Knox interdit à ses survivants. Le PNJ
est refusé au contact et reste bloqué.

Pour l'éviter, `LK_Routing.lua` (957 lignes) recalcule en Lua un itinéraire qui doit prédire le chemin natif, puis pose
des points de passage par les portes. Chaque blocage vu en campagne y a ajouté un cas. Le 2026-11-15 encore, la recherche
échouait depuis une cuisine et le PNJ reprenait la fenêtre condamnée (campagnes `20261115-101858` et `20261115-131957`).
L'utilisateur juge, à raison, que ce guidage est devenu une usine à gaz.

## Révision du 2026-11-15

**Première version.** Elle laissait le moteur calculer tout le chemin et marquait les passages interdits dans la mémoire du
corps (`getMapKnowledge():setKnownBlockedWindow` et les fonctions voisines).

**Pourquoi elle est abandonnée.** Seul le moteur Java de repli lit ces marques (`PathFindRequest.java:73-80`). Le jeu tourne
par défaut avec son moteur natif :
- `Pathfind.UseNativeCode` vaut `true` (`DebugOptions.java:76`, appliqué par `IsoWorld.java:2066`) ;
- la demande native ne copie jamais la mémoire du personnage (`nativeCode/PathFindRequest.java:51-96`) ;
- `PathfindNative.findPath` (`:276-312`) ne transmet aucun bord bloqué à la bibliothèque `PZPathFind64.dll`.

Les marques ne changeraient donc rien. Basculer tout le jeu sur le moteur Java (option de débogage globale, coût inconnu
pour tous les zombies, joueurs et animaux) a été écarté par l'utilisateur.

## Décisions

- **D01 — Le jeu calcule le chemin.** Un déplacement de PNJ demande le trajet de A à B au moteur, sans prédiction ni point
  de passage calculé d'avance pour éviter une fenêtre ou une porte. Le détour autour des plantes et des feux de camp
  (LK04-T06) n'est pas concerné et reste.
- **D02 — Détour seulement après un refus (décision de l'utilisateur, révision du 2026-11-15).**
  - Quand les règles de contact refusent au PNJ une fenêtre, une porte ou une clôture, l'autorité choisit la porte ou le
    portail utilisable le plus proche (règles de contact `decide` et `decideWindow` réutilisées).
  - Elle donne un détour de quelques points par cette porte, puis redemande aussitôt le chemin au jeu, sans attendre.
  - L'ouverture refusée est retenue pour ce PNJ le temps de ce déplacement, pour ne pas la reprendre.
  - Les règles de contact restent la seule source de vérité sur ce qui est permis.
- **D03 — Dernier recours.** Un PNJ enfermé (aucune porte utilisable pour sortir) garde la règle de LK04-T20 : la fenêtre
  verrouillée abordée de l'intérieur lui est permise au contact.
- **D04 — Le code de guidage remplacé est supprimé**, avec ses tests : modèle « zombie », jalonnement, sortie par une
  porte, prudence après refus. Aucun test ne vérifie son absence.

## Conséquences

- Le PNJ suit le chemin du jeu, avec ses évitements natifs. Il ne marche plus de point en point, sauf pendant le court
  détour qui suit un refus.
- Les règles de contact (`LK_Obstacles` : ouvrir, fermer, verrouiller, refuser) ne changent pas. Seule la réaction au
  refus change : un détour immédiat, au lieu d'un blocage.
- La preuve est en jeu, en solo et en MP : suites des traversées et des portes (`lk.traversal`, `lk.doors`), de
  l'expédition (`lk.expedition`) et de la sortie contre un zombie à la fenêtre (`lk.windowsally`).
