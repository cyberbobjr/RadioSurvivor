# ADR — Bords des cases : un seul lecteur du jeu, des règles pures

| | |
|---|---|
| Date | 2026-11-16 |
| Statut | Accepté |
| Décideur | utilisateur (« fait le tout de suite », 2026-11-16) |
| Plan associé | [LK17 — Chemin du jeu pour les PNJ](../../annexes/plans-termines/LK17-chemin-vanilla.md), tâche LK17-T03 |
| Références | [Déplacements des PNJ : chemin du jeu](adr-chemin-vanilla.md) ; [Les PNJ se cèdent le passage](adr-ceder-le-passage.md) ; [Remise en ordre SOLID](adr-remise-en-ordre-solid.md). Java 42.22 : `zombie/iso/IsoGridSquare.java` (`isWallTo` 718, `isWindowTo` 726, `isBlockedTo` 935, `isHoppableTo` 1043, `getDoorTo` 3077, `getWindowTo` 3131, `getBuildingDef` 7813) |

## Contexte

Le chemin d'un PNJ vient du jeu (ADR « chemin du jeu »). Autour de lui, quatre règles de Living Knox demandent ce qui
sépare deux cases voisines :

- l'arrivée d'un déplacement (`LK_Executor`, client) ;
- le point de déblocage en ligne dégagée (`LK_Movement`, partagé) ;
- les places d'arrêt (`LK_StopPlace`, autorité) ;
- le couloir d'un détour (`LK_Detour`, autorité).

Chacune interrogeait la carte elle-même, avec sa propre liste d'objets (porte, fenêtre, mur, clôture). Le 2026-11-16,
la règle d'arrivée ne regardait que les portes : un PNJ resté dehors sous une fenêtre se croyait arrivé dedans
(`lk.windowsally`, campagnes `20261116-071539` et `20261116-073736-mp`), alors que la règle de déblocage connaissait déjà
les fenêtres. Chaque cas limite demandait aussi de simuler une carte entière au banc.

## Décisions

- **D01 — Un seul lecteur du jeu.** `LivingKnox.Edges` (`shared/LivingKnox/Edges/LK_Edges.lua`) est le seul module qui
  demande au jeu ce qui sépare deux cases voisines. Il rend des faits en valeurs simples : porte (ouverte, portail bas,
  barricadée, objet), fenêtre (sorte, objet), clôture basse vue par le moteur, objet enjambable, mur, bord bloqué, et
  pour une case : dedans ou dehors, praticable.
- **D02 — Des règles pures.** `LivingKnox.EdgeRules` (`shared/LivingKnox/Edges/LK_EdgeRules.lua`) ne reçoit que ces
  faits et n'appelle aucune fonction du jeu : bord fermé à la marche, arrivée empêchée (bord voisin, diagonale),
  refus d'une place d'arrêt, pas de couloir. Chaque cas limite se teste sur des tables.
- **D03 — Les appelants composent.** Les quatre modules lisent les faits par `Edges`, puis appliquent la règle de
  `EdgeRules`. Les règles de contact (`LK_Obstacles` : ouvrir, fermer, verrouiller, refuser) ne changent pas.
- **D04 — Même comportement.** Ce changement ne modifie aucun comportement en jeu. Les anciennes fonctions
  (`Movement.edgeBlocked`, `Detour.isFenceTo`, `Obstacles.windowOf`) disparaissent ; leurs appelants et leurs tests
  passent par `Edges`.

## Conséquences

- Un nouvel objet de bord (une sorte de porte d'un mod, par exemple) se lit à un seul endroit.
- Les règles se testent sans carte (`tests/test_lk_edges.py`) ; les bancs existants restent la preuve que le
  comportement n'a pas changé.
- La preuve en jeu est celle des campagnes `solo-lk` et MP suivantes.
