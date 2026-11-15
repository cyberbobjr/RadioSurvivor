# ADR — Déplacements des PNJ : chemin du jeu, passages interdits marqués

| | |
|---|---|
| Date | 2026-11-15 |
| Statut | Accepté |
| Décideur | utilisateur |
| Remplace | le guidage « porte d'abord » de LK04-T09 et ses suites (modèle « zombie » prédisant le chemin natif, jalonnement en lignes dégagées, sortie par une porte, dernier recours par points de passage, prudence après une fenêtre refusée de LK05-T23) |
| Plan associé | [LK17 — Chemin du jeu pour les PNJ](../../annexes/plans/LK17-chemin-vanilla.md) |
| Références | sources Java 42.22 : `zombie/pathfind/SearchNode.java:86-90`, `PathFindRequest.java:44-80`, `VGAStar.java:159` et `:243`, `zombie/ai/MapKnowledge.java:55-105`, `IsoGameCharacter.java:11069` ; Lua vanilla `media/lua/client/DebugUIs/DebugContextMenu.lua:759` |

## Contexte

Les PNJ de Living Knox ont un corps de zombie. Le moteur calcule donc leur chemin comme celui d'un zombie :

- une fenêtre coûte 200 (ou 20 si elle est ouverte) aux joueurs et aux animaux qui ne grimpent pas, et rien aux zombies
  (`SearchNode.java:86-90`) ;
- un zombie peut cogner pour passer (`PathFindRequest.java:58`).

Le chemin natif passe donc par une fenêtre, même condamnée. Or Living Knox interdit à ses survivants une fenêtre qu'ils ne
peuvent pas ouvrir : refusé au contact, le PNJ reste bloqué.

Pour l'éviter, `LK_Routing.lua` (957 lignes) recalcule en Lua un itinéraire censé prédire le chemin natif, puis pose des
points de passage par les portes. Chaque blocage vu en campagne y a ajouté un cas. Le 2026-11-15 encore, la recherche
échouait depuis une cuisine et le PNJ reprenait la fenêtre condamnée (campagnes `20261115-101858`, `20261115-131957`).

Le moteur offre l'outil prévu pour cela. Chaque personnage a une mémoire des passages bloqués,
`IsoGameCharacter:getMapKnowledge()`, avec `setKnownBlockedWindow`, `setKnownBlockedDoor`, `setKnownBlockedEdgeN` et
`setKnownBlockedEdgeW` (`MapKnowledge.java`). Chaque demande de chemin de ce personnage copie ces marques
(`PathFindRequest.java:73-80`). La recherche traite un bord marqué comme un mur, pour tous les types de déplaceur
(`VGAStar.java:159`). Le Lua vanilla s'en sert déjà (`DebugContextMenu.lua:759`).

## Décisions

- **D01 — Le jeu calcule le chemin.** Un déplacement de PNJ demande le trajet de A à B au moteur, sans point de passage
  calculé en Lua pour éviter les fenêtres ou les portes. Le détour autour des plantes et des feux de camp (LK04-T06) n'est
  pas concerné et reste.
- **D02 — Les passages interdits sont marqués dans la mémoire du corps.** Une fenêtre, une porte ou une clôture que les
  règles de contact refusent au PNJ (verrouillée, condamnée, barricadée, foyer d'un autre groupe…) est marquée bloquée
  dans le `MapKnowledge` de son corps. On marque à deux moments, confirmés par défaut :
  - au refus au contact, puis le chemin est redemandé aussitôt, sans attendre ;
  - d'avance, pour les ouvertures du bâtiment de départ et du bâtiment d'arrivée.

  Les règles de contact restent la seule source de vérité sur ce qui est permis.
- **D03 — Marques posées là où le chemin est calculé.** En MP, le chemin est calculé par le client propriétaire du corps.
  L'autorité tient la liste des passages interdits de chaque PNJ et la joint à la consigne de déplacement. L'exécutant
  la pose dans le `MapKnowledge` du corps avant de demander le chemin. Il la reprend à chaque changement de propriétaire.
- **D04 — Dernier recours.** Un PNJ enfermé (aucun chemin sans passage interdit) garde la règle de LK04-T20 : le moteur
  ne trouve pas de chemin, l'autorité lève les marques des fenêtres de ce bâtiment et autorise au contact la fenêtre
  verrouillée abordée de l'intérieur.
- **D05 — Le code de guidage remplacé est supprimé**, avec ses tests : modèle « zombie », jalonnement, sortie par une
  porte, prudence après refus. Aucun test ne vérifie son absence.

## Conséquences

- Le chemin suivi est celui du jeu, avec ses évitements natifs (meubles, murs, zones). Le PNJ ne marche plus de point en
  point.
- Les règles de contact (`LK_Obstacles` : ouvrir, fermer, verrouiller, refuser) ne changent pas. Seul l'endroit où un
  refus agit change : il devient une marque, au lieu d'un blocage.
- Les suites en jeu des traversées et des portes (`lk.traversal`, `lk.doors`, `lk.expedition`, `lk.windowsally`) sont la
  preuve, en solo et en MP.
