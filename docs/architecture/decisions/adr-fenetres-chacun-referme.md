# ADR — Fenêtres : chacun referme ce qu'il a ouvert ou enjambé ; tests de déplacement sur le résultat

| | |
|---|---|
| Date | 2026-11-16 |
| Statut | Accepté |
| Décideur | utilisateur (« oui go », 2026-11-16, après l'étude des mods PZNS et Living World) |
| Remplace | la règle du « dernier passant » des fenêtres de LK04-T07 et LK04-T18 (tout PNJ dont une fenêtre ouverte rapproche l'étape en devient le passant), et sa retouche LK17-T04 (`Obstacles.inFrontOf`) |
| Plan associé | [LK19 — Fenêtres refermées par leur passant, tests sur le résultat](../../annexes/plans/LK19-fenetres-resultat.md) |
| Références | Campagnes `solo-lk` du 2026-11-16 : `runs/20261116-171910-c3a0093c3273` et `runs/20261116-200750-b90f4778c1ef` (`lk.traversal`, « open window » : 6 bascules au lieu de 5). Mod Living World 1.5.2 (Workshop 3837614147, `Doors.lua`, `closeBehind`), lu le 2026-11-16 pour les idées seulement : aucune licence, aucun code repris. |

## Contexte

Un PNJ referme une fenêtre qu'un PNJ de Living Knox a ouverte. Jusqu'ici, la fenêtre revenait au « dernier passant » :
tout PNJ dont elle rapprochait l'étape, à deux cases au plus. Cette règle devine le trajet, et elle se trompe quand deux
fenêtres se suivent sur le même mur.

Constat du 2026-11-16, deux campagnes de suite :
- un PNJ d'une suite précédente ouvre la fenêtre `10910,10037,0,W` puis disparaît ;
- le PNJ de « open window » franchit la fenêtre voisine `10910,10038,0,W`, frôle la première et la referme
  (`closed behind npc lk-145 (body 1.02 square(s) away)`).

La retouche LK17-T04 exigeait d'être « en face » de l'ouverture : en marchant, le corps l'est un instant, et le défaut est
revenu.

Le test lui-même comptait toutes les bascules de fenêtre de la partie (`Obstacles.stats.windowToggles`). Une fenêtre
voisine suffisait à le faire échouer, alors que le PNJ du test était bien passé par la sienne. L'utilisateur constate
qu'on tourne en rond sur les déplacements.

Living World, mod solo à corps de zombie lui aussi, tient une règle simple : chaque PNJ garde la liste de ce qu'il a ouvert
et le referme ; il ne passe la main qu'à un PNJ qui franchit réellement l'ouverture.

## Décisions

- **D01 — Une fenêtre ouverte par un PNJ est refermée par ce PNJ, ou par le dernier PNJ qui l'a réellement enjambée.**
  - Le passant d'une fenêtre suivie change seulement quand un autre PNJ est vu en train de l'escalader (état
    `climbwindow`, corps à `Obstacles.ALIGN` case au plus du milieu de son bord, même niveau).
  - Plus aucune reprise d'après le trajet ou la distance (`noteWindows`, `onRoute` pour les fenêtres, `inFrontOf`).
  - Le reste ne change pas : refermée juste après l'enjambée, jamais de loin (`ACT_REACH`), cases libres, geste du joueur,
    abandon après `GIVE_UP_MS`.
  - Une fenêtre dont le passant a disparu reste ouverte, sauf si un autre PNJ l'enjambe ensuite.
- **D02 — Les tests en jeu des traversées et des portes vérifient le résultat, pas le nombre de gestes.**
  - Ils regardent l'état de l'ouverture du test : ouverte, fermée, verrouillée, brisée ; qui l'a refermée et à quelle
    distance ; le PNJ arrivé, passé ou non par elle.
  - Ils ne comparent plus les compteurs globaux de l'autorité (`windowToggles`, `windowsClosed`, `opened`, `closed`,
    `refused`), qu'une ouverture voisine ou un autre PNJ fait bouger.
  - Le geste et l'orientation du corps à la fermeture restent mesurés et imprimés, sans faire échouer le test.
- **D03 — Portée.** Les portes gardent leur règle de refermeture (à `CLOSE_DIST` case, sur le trajet) : aucun défaut
  ouvert. Le déblocage d'un corps coincé (`LK_Movement.lua`) garde ses trois temps : il sert au PNJ coincé derrière un
  meuble (`lk.stuck`) et n'a fait échouer aucune campagne. Sa simplification relève de l'audit de complexité en attente.

## Conséquences

- Code retiré de `LK_Obstacles.lua` : `noteWindows`, `inFrontOf` ; le relais par la vue du trajet disparaît pour les
  fenêtres. Les tests hors jeu de ces règles sont remplacés par ceux de D01.
- Une fenêtre ouverte par un PNJ qui s'en va sans l'enjamber (consigne changée, corps retiré) reste ouverte : c'était déjà
  le cas d'un corps retiré, c'est maintenant la seule règle.
- Les tests en jeu n'échouent plus pour une ouverture voisine ou un PNJ d'une autre suite.
- Preuve en jeu : `lk.traversal`, `lk.doors` et `lk.windowsally` verts en `solo-lk` et en MP.
