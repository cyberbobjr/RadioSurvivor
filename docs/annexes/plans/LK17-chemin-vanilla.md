# LK17 — Chemin du jeu pour les PNJ, détour seulement après un refus

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 1 / 3 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | LK17-T01 | Détour immédiat par la porte la plus proche après un refus au contact | `à faire` | MP | — |
| ☐ | LK17-T02 | Suppression du guidage maison | `à faire` | MP | LK17-T01 |
| ☑ | LK17-T03 | Bords des cases : un seul lecteur du jeu, des règles pures | `testé MP` | MP | LK17-T01 |

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

- [ ] **LK17-T01** — Détour immédiat par la porte la plus proche après un refus au contact
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `LK_Obstacles.lua` (refus au contact), `LK_Directives.lua` (redemande du déplacement), module du détour ; bancs `tests/test_lk_obstacles.py`, `tests/test_lk_directives.py`
  - Faire : D02 de l'ADR. Au refus d'une fenêtre, d'une porte ou d'une clôture au contact, l'autorité choisit la porte ou le portail utilisable le plus proche (règles de contact réutilisées), émet un détour de quelques points par cette porte et redemande aussitôt le chemin, sans l'évitement de 60 s. L'ouverture refusée est retenue pour ce déplacement. Un PNJ enfermé garde le dernier recours (D03).
  - Accepté si : au banc, un refus de fenêtre produit un détour par la porte voisine, puis l'arrivée ; en jeu, `lk.traversal`, `lk.doors`, `lk.expedition` et `lk.windowsally` verts en solo et en MP.
  - Tests : bancs ci-dessus ; campagnes `solo-lk` et MP.
  - Preuve : —
  - Reste : —

- [ ] **LK17-T02** — Suppression du guidage maison
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK17-T01
  - Fichiers : `LK_Routing.lua` (`planDoorRoute`, modèle « zombie », jalonnement, sortie par une porte, prudence), `LK_Directives.lua` (`planDoors` et les points qu'il pose d'avance), `LK_Obstacles.lua` (`windowRefusedAt`), bancs qui ne testaient que ce code
  - Faire : D01 et D04. Chaque déplacement part du chemin du jeu, sans prédiction. Tout le code de guidage remplacé est supprimé avec ses tests. Le détour des plantes et feux de camp reste.
  - Accepté si : plus aucun point de passage calculé d'avance pour éviter une fenêtre ou une porte ; mêmes suites en jeu vertes en solo et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes `solo-lk`, `solo` et MP.
  - Preuve : —
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
