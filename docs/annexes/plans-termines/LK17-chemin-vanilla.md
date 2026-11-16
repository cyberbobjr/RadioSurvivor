# LK17 — Chemin du jeu pour les PNJ, détour seulement après un refus

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** terminée — 3 / 3 tâche(s) terminée(s), 1 abandonnée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | LK17-T01 | Détour immédiat par la porte la plus proche après un refus au contact | `testé MP` | MP | — |
| ☑ | LK17-T02 | Suppression du guidage maison | `testé MP` | MP | LK17-T01 |
| ☑ | LK17-T03 | Bords des cases : un seul lecteur du jeu, des règles pures | `testé MP` | MP | LK17-T01 |
| ✕ | LK17-T04 | Une fenêtre ouverte voisine n'est plus reprise par le PNJ qui passe à côté | `abandonné` | MP | LK17-T01 |

<!-- fin du tableau de bord -->

**Mod.** Living Knox (`batman_LivingKnox`).

**Objectif.** Un PNJ va de A à B par le chemin que calcule le jeu. Quand les règles de contact lui refusent une fenêtre,
une porte ou une clôture, il reçoit un seul détour court par la porte utilisable la plus proche, puis le jeu recalcule le
chemin. Le guidage maison de `LK_Routing.lua` disparaît.

**ADR.** [Déplacements des PNJ : chemin du jeu, détour seulement après un refus](../../architecture/decisions/adr-chemin-vanilla.md)
(accepté le 2026-11-15, révisé le même jour : le moteur natif ignore `MapKnowledge`) ; ce plan en est l'ordre de livraison.
LK17-T03 suit l'ADR [Bords des cases : un seul lecteur du jeu, des règles pures](../../architecture/decisions/adr-bords-des-cases.md)
(accepté le 2026-11-16).

**Dépend de.** LK04 (déplacement et obstacles), LK05-T23.

**Sources.** Voir l'ADR (sources Java 42.22, campagnes du 2026-11-15).

- [x] **LK17-T01** — Détour immédiat par la porte la plus proche après un refus au contact
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `LK_Obstacles.lua` (refus au contact), `LK_Directives.lua` (redemande du déplacement), module du détour ; bancs `tests/test_lk_obstacles.py`, `tests/test_lk_directives.py`
  - Faire : D02 de l'ADR. Au refus d'une fenêtre, d'une porte ou d'une clôture au contact, l'autorité choisit la porte ou le portail utilisable le plus proche (règles de contact réutilisées), émet un détour de quelques points par cette porte et redemande aussitôt le chemin, sans l'évitement de 60 s. L'ouverture refusée est retenue pour ce déplacement. Un PNJ enfermé garde le dernier recours (D03).
  - Accepté si : au banc, un refus de fenêtre produit un détour par la porte voisine, puis l'arrivée ; en jeu, `lk.traversal`, `lk.doors`, `lk.expedition` et `lk.windowsally` verts en solo et en MP.
  - Tests : bancs ci-dessus ; campagnes `solo-lk` et MP.
  - Preuve : codé le 2026-11-15 (`be9f01d1`, puis `7c653e68` et `a2ef6a7e` : couloir du détour sans la fenêtre refusée) : `LK_Detour.lua` (`Obstacles.onRefusal`), banc `tests/test_lk_detour.py`. Hors jeu : `run_all` de LK17-T03, `Summary: 207 passed, 0 failed`, `RESULT: PASS`. En jeu sur `8a911d13` : `solo-lk` `runs/20261116-143506-2781d392947b` et MP `runs/20261116-145738-mp-2259cb26aba1`, `lk.traversal`, `lk.doors`, `lk.expedition` et `lk.windowsally` verts dans les deux (les trois échecs MP sont côté RadioSurvivor, voir LK17-T03). Le plan n'avait pas été mis à jour au commit (relevé du 2026-11-16).
  - Reste : —

- [x] **LK17-T02** — Suppression du guidage maison
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK17-T01
  - Fichiers : `LK_Routing.lua` (`planDoorRoute`, modèle « zombie », jalonnement, sortie par une porte, prudence), `LK_Directives.lua` (`planDoors` et les points qu'il pose d'avance), `LK_Obstacles.lua` (`windowRefusedAt`), bancs qui ne testaient que ce code
  - Faire : D01 et D04. Chaque déplacement part du chemin du jeu, sans prédiction. Tout le code de guidage remplacé est supprimé avec ses tests. Le détour des plantes et feux de camp reste.
  - Accepté si : plus aucun point de passage calculé d'avance pour éviter une fenêtre ou une porte ; mêmes suites en jeu vertes en solo et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes `solo-lk`, `solo` et MP.
  - Preuve : codé le 2026-11-15 (`be9f01d1`) : `LK_Routing.lua` (957 lignes) et les sept modèles de `Routing/` supprimés, `planDoors` retiré de `LK_Directives.lua`, `windowRefusedAt` de `LK_Obstacles.lua`, `tests/test_lk_routing.py` et les tests du guidage supprimés (3 177 lignes retirées, 890 ajoutées). Mêmes preuves hors jeu et en jeu que LK17-T01.
  - Reste : —

- [x] **LK17-T03** — Bords des cases : un seul lecteur du jeu, des règles pures
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK17-T01
  - Fichiers : nouveaux `shared/LivingKnox/Edges/LK_Edges.lua` (lecture du jeu) et `LK_EdgeRules.lua` (règles pures) ; appelants `LK_Executor.lua` (arrivée), `LK_Movement.lua` (déblocage), `LK_StopPlace.lua` (places d'arrêt), `LK_Detour.lua` (couloir, clôtures), `LK_Obstacles.lua` (fenêtre d'un bord), `LK_PassageAuthority.lua` ; banc `tests/test_lk_edges.py`
  - Faire : D01 à D04 de l'ADR « bords des cases ». Les quatre règles lisent les faits d'un bord par `Edges` et décident par `EdgeRules`, sans changer le comportement.
  - Accepté si : chaque règle de `EdgeRules` testée sur des faits sans carte ; `tests/run_all.py --keep-going` vert ; campagnes `solo-lk` et MP sans nouvel échec.
  - Tests : `tests/test_lk_edges.py`, `tests/run_all.py --keep-going` ; campagnes `solo-lk` et MP.
  - Preuve : 2026-11-16, `python tests/run_all.py --keep-going` : `Summary: 207 passed, 0 failed, 0 skipped (571.8 s)`, `RESULT: PASS` (dont `lk_edges` 9 tests OK, luacheck Contents et dev 0 avertissement, `plan-check` 0 erreur). Rouge d'abord : `tests/test_lk_edges.py` 9 erreurs avant `LK_EdgeRules.lua`. Campagnes sur `8a911d13` : `solo-lk` code 0, `RST-RESULT ok=true total=139 pass=132 fail=0 skip=7`, `runs/20261116-143506-2781d392947b` ; MP code 1, `ok=false total=414 pass=394 fail=3 skip=17`, `runs/20261116-145738-mp-2259cb26aba1`, les trois échecs côté RadioSurvivor (`rs.factions.accord` et `rs.relation` : le PNJ s'éloigne pendant la réponse ; `rs.notes.written` : pont lancé pendant la campagne), toutes les suites `lk.*` vertes. Campagnes précédentes, échecs corrigés : `8c9a7f86` (solo `runs/20261116-112759-66e3f0e32f8a` code 0 ; MP `runs/20261116-115134-mp-de37e3bd28df` code 1, `lk.expedition`, `lk.windowsally`, `lk.npcsheet`) -> `137f97d1` ; `137f97d1` (solo `runs/20261116-125651-2b98666c3baf` code 1, `lk.windowsally` ; MP `runs/20261116-132125-mp-26231bccb711` code 1, `lk.traversal`, `lk.npcsheet`, `lk.windowsally`) -> `8a911d13` (`run_all` : `Summary: 207 passed, 0 failed`, `RESULT: PASS`).
  - Reste : —

- [ ] **LK17-T04** — Une fenêtre ouverte voisine n'est plus reprise par le PNJ qui passe à côté
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : LK17-T01
  - Fichiers : `LK_Obstacles.lua` (`Obstacles.inFrontOf`, `noteWindows`, réglage `ALIGN`) ; banc `tests/test_lk_obstacles.py`
  - Faire : défaut de la campagne `solo-lk` du 2026-11-16 (`runs/20261116-171910-c3a0093c3273`, `lk.traversal` « open window » : 6 bascules au lieu de 5). La fenêtre voisine du même mur (`10910,10037,0,W`), ouverte par un PNJ d'une suite précédente puis retiré, rapprochait aussi le corps de son étape (`onRoute`) : le PNJ qui franchissait sa propre fenêtre (`10910,10038,0,W`) en devenait le dernier passant et la refermait. Un PNJ ne devient le passant d'une fenêtre ouverte que s'il est en face de son ouverture (écart le long du bord ≤ `ALIGN`, 0,75 case).
  - Accepté si : au banc, `test_open_window_beside_the_crossed_one_is_not_taken_over` passe (rouge avant) ; bancs des obstacles verts ; en jeu, `lk.traversal` verte en `solo-lk` et en MP.
  - Tests : banc ; campagnes `solo-lk` et MP.
  - Preuve : 2026-11-16, `python tests/run_all.py --keep-going` : `Summary: 208 passed, 0 failed, 0 skipped (590.8 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement, `plan-check` 0 erreur). Rouge d'abord : `test_open_window_beside_the_crossed_one_is_not_taken_over` en échec (fenêtre voisine refermée), vert après `inFrontOf` ; `test_lk_obstacles` 132 OK.
  - Reste : remplacée par LK19-T01 (ADR [Fenêtres : chacun referme ce qu'il a ouvert ou enjambé](../../architecture/decisions/adr-fenetres-chacun-referme.md), 2026-11-16) : la campagne `solo-lk` sur `f8688584` (`runs/20261116-200750-b90f4778c1ef`, code 1, `RST-RESULT ok=false total=188 pass=179 fail=1`) a montré le même défaut (`lk.traversal` « open window », 6 bascules au lieu de 5) : en marchant, le corps passe un instant en face de la fenêtre voisine. `inFrontOf` est retiré par LK19-T01.
