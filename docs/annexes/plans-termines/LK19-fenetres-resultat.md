# LK19 — Fenêtres refermées par leur passant, tests de déplacement sur le résultat

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** terminée — 2 / 2 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | LK19-T01 | Le passant d'une fenêtre change seulement à l'enjambée | `testé MP` | MP | — |
| ☑ | LK19-T02 | Tests en jeu des traversées et des portes sur le résultat | `testé MP` | MP | — |

<!-- fin du tableau de bord -->

**Mod.** Living Knox (`batman_LivingKnox`).

**Objectif.** Une fenêtre ouverte par un PNJ est refermée par lui, ou par le dernier PNJ qui l'a réellement enjambée,
jamais par un PNJ qui passe à côté. Les tests en jeu des traversées et des portes vérifient l'état de l'ouverture du
test et l'arrivée du PNJ, plus les compteurs globaux de l'autorité.

**ADR.** [Fenêtres : chacun referme ce qu'il a ouvert ou enjambé ; tests de déplacement sur le résultat](../../architecture/decisions/adr-fenetres-chacun-referme.md)
(accepté le 2026-11-16) ; ce plan en est l'ordre de livraison.

**Dépend de.** LK17 (chemin du jeu, détour après un refus), LK04-T18 (refermeture juste après l'enjambée).

**Sources.** Voir l'ADR (campagnes `solo-lk` du 2026-11-16, lecture de Living World 1.5.2).

- [x] **LK19-T01** — Le passant d'une fenêtre change seulement à l'enjambée
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `LK_Obstacles.lua` (`noteWindows` et `inFrontOf` retirés, `climbedWindows` à leur place) ; banc `tests/test_lk_obstacles.py`
  - Faire : D01 de l'ADR. Une fenêtre suivie (`Obstacles.openWins`) change de passant seulement quand un autre PNJ est vu en train de l'escalader, corps à `ALIGN` case au plus du milieu du bord, même niveau. Côté de départ noté à ce moment. Plus de reprise d'après le trajet.
  - Accepté si : au banc, une fenêtre ouverte voisine de celle franchie n'est pas refermée par le PNJ qui passe ; une fenêtre ouverte par A puis enjambée par B est refermée par B derrière lui ; bancs des obstacles verts ; en jeu, `lk.traversal` et `lk.windowsally` verts en `solo-lk` et en MP.
  - Tests : banc ; campagnes `solo-lk` et MP.
  - Preuve : 2026-11-16, `python tests/run_all.py --keep-going` : `Summary: 208 passed, 1 failed, 0 skipped (637.2 s)`, seul échec `atelier_ui` (atelier des voix de RadioSurvivor, modifié en parallèle par un autre agent, hors de cette tâche ; vert au passage précédent) ; `lk_obstacles` `Ran 133 tests` OK, luacheck Contents et dev 0 avertissement, `plan-check` 0 erreur. Rouge d'abord : `test_npc_who_walks_up_to_an_open_window_and_turns_away_never_closes_it` en échec (`'false false' != 'true false'` : fenêtre refermée par un PNJ qui ne l'avait pas enjambée), vert après `climbedWindows`. Campagnes sur `8c2be02d` : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-001559-10eaa7905a9d` ; MP code 1, `ok=false total=414 pass=393 fail=3 error=1 skip=17`, `runs/20261117-003759-mp-f3f77ba7956f`, `lk.traversal` et `lk.windowsally` vertes en `solo-lk` et en MP. Échecs MP hors de ces suites : `lk.passage` face à face dans une porte (`no passage granted`, premier échec sur les 7 dernieres campagnes MP), `lk.appear.check` client 1 (second zombie, déjà vu le 2026-11-16), `rs.notes.written` (pont lancé) et `rs.trade_exchange` (erreur `itemsOf`, RadioSurvivor).
  - Reste : —

- [x] **LK19-T02** — Tests en jeu des traversées et des portes sur le résultat
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `dev/batman_LivingKnoxTests/.../RST/suites/RST_LKTraversal.lua`, `RST_LKDoors.lua`
  - Faire : D02 de l'ADR. Les assertions sur `windowToggles`, `windowsClosed`, `windowsRefused`, `opened`, `closed` et `refused` de l'autorité sont remplacées par l'état de l'ouverture du test (ouverte, fermée, verrouillée, brisée), son dernier refus ou sa dernière fermeture (`lastRefused`, `lastClose` : bord, PNJ, distance) et l'arrivée du PNJ. Geste et orientation à la fermeture : mesurés, imprimés, sans assertion.
  - Accepté si : aucun compteur global de l'autorité comparé dans ces deux suites ; `lk.traversal` et `lk.doors` verts en `solo-lk` et en MP.
  - Tests : `tests/run_all.py --keep-going` (luacheck dev) ; campagnes `solo-lk` et MP.
  - Preuve : 2026-11-16, même `run_all` que LK19-T01 (luacheck dev 0 avertissement). Plus aucune comparaison de `windowToggles`, `windowsClosed`, `windowsRefused`, `opened`, `closed`, `refused`, `locked`, `shut` ni `detours` dans `RST_LKTraversal.lua` et `RST_LKDoors.lua` : état de l'ouverture du test, `refusedHere` (dernier refus sur ce bord depuis le départ) et `lastClose` ; geste et orientation imprimés seulement. Campagnes sur `8c2be02d` : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-001559-10eaa7905a9d` ; MP code 1, `ok=false total=414 pass=393 fail=3 error=1 skip=17`, `runs/20261117-003759-mp-f3f77ba7956f`, `lk.traversal` et `lk.doors` vertes en `solo-lk` et en MP. Échecs MP hors de ces suites : `lk.passage` face à face dans une porte (`no passage granted`, premier échec sur les 7 dernieres campagnes MP), `lk.appear.check` client 1 (second zombie, déjà vu le 2026-11-16), `rs.notes.written` (pont lancé) et `rs.trade_exchange` (erreur `itemsOf`, RadioSurvivor).
  - Reste : —
