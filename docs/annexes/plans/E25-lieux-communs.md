# E25 — Lieux communs, zones et distances

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 3 / 4 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E25-T01 | Fichier commun des lieux et voix qui les nomment | `testé hors jeu` | hors jeu | — |
| ☐ | E25-T02 | Objectif tiré dans une zone ou à une distance du joueur, pour tous les genres | `testé hors jeu` | solo | E25-T01 |
| ☑ | E25-T03 | Onglet « Lieux » de l'atelier et choix dans des listes | `testé hors jeu` | hors jeu | E25-T01 |
| ☑ | E25-T04 | Wiki, exemples et CHANGELOG des lieux communs | `testé hors jeu` | hors jeu | E25-T02, E25-T03 |

<!-- fin du tableau de bord -->

**Mod.** RadioSurvivor (`batman_RadioSurvivor`) pour le format des fiches ; le mod commun (`batman_CoreAI`) pour le
tirage des bâtiments ; le pont (`bridge/`) et son atelier.

**Objectif.** Une mission ne vise plus toujours la même case : son objectif est un point, une zone où le jeu tire un
bâtiment, ou un bâtiment tiré près, plus loin ou très loin du joueur. Les lieux se déclarent une seule fois, dans un
onglet « Lieux » de l'atelier, et chaque voix choisit les siens dans une liste.

**ADR.** [Lieux communs](../../architecture/decisions/adr-lieux-communs.md), décisions D01 à D08 (2026-11-17).

**Dépend de.** E24.

## Décisions

- 2026-11-17 — **E25** (utilisateur) : objectif d'une mission = point, zone (bâtiment tiré dedans), Près du joueur
  (100-200 cases), Plus loin (200-500), Très loin (500-1 500) ; un seul fichier de lieux commun, onglet « Lieux », voix
  qui choisissent dans une liste, 16 voix reprises.
- 2026-11-17 — **E25** (confirmé par défaut) : genre de bâtiment au choix (`CA_Sites.KINDS`) ; un lieu sert là où la
  voix le nomme (plus de `use=`) ; planque, rendez-vous, trajet et cache = points seulement ; fichier commun installé et
  relu comme une voix, lieu utilisé non supprimable ; zone = rectangle de deux coins ; relevés en jeu vers l'onglet ;
  « Nouveau lieu… » dans les listes.

## Hors périmètre

- Living Knox.

## Tâches

- [x] **E25-T01** — Fichier commun des lieux et voix qui les nomment
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : D02, D04 à D07 ; `_places.txt` (points `at=`, zones `area=`), lecteur du serveur et du pont aux mêmes
    règles et messages, installation et mise à jour comme une voix ; `[place]` et `use=` retirés des fiches, repères,
    planques, objectif, trajet, rendez-vous et cache nommés par la voix ; 16 voix livrées reprises ;
    `persona-format.md`.
  - Accepté si : bancs des lecteurs (lieu absent, zone refusée là où il faut un point, mêmes messages des deux côtés),
    fiches livrées acceptées, prompt sans coordonnée.
  - Preuve : 2026-11-17, `_places.txt` livré (15 points) installé et relu comme une voix (empreintes) ; `RS_Persona.parsePlaces` et `persona_store.parse_places_lines` (points `at=`, zones `area=`, 500 lieux, mêmes messages) ; `[place]` et `use=` retirés des fiches ; `marks=`, `target=` (lieu, `near`, `far`, `very_far`, défaut `near`), `building=`, `drops=` points obligatoires, `landing=` points, `cache_place=` ; 16 voix reprises, `KNOWN_DELIVERED` ; `persona-format.md`. Bancs : `test_personas` 21, `test_personas_server` 111, `test_carnet` 100, `test_persona_sections` 12, `test_kahlua` 42 (libellés de lieux lus dans la VM Kahlua), bancs de missions, troc, récompenses OK ; suite complète `python tests/run_all.py --keep-going` `Summary: 211 passed, 1 failed` (613,8 s), seul échec `luacheck-contents` (ligne de commentaire trop longue dans `RS_Trade.lua`, corrigée ; `--only luacheck-contents` `Summary: 1 passed, 0 failed`).


- [ ] **E25-T02** — Objectif tiré dans une zone ou à une distance du joueur, pour tous les genres
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : E25-T01
  - Faire : D01, D03, D05 ; tirage commun (`CA_Sites`) avec distance mini et maxi, zone et genre ; `target=` lieu,
    `near`, `far`, `very_far` et `building=` reçus par tous les gabarits qui ont un objectif ; repère et quartier
    révélé d'une zone ; coût du tirage « Très loin » mesuré.
  - Accepté si : bancs du tirage (distance, zone, genre, bases évitées, rien trouvé), un banc par gabarit ; en jeu :
    une mission de chaque distance proposée deux fois vise deux bâtiments différents.
  - Preuve : 2026-11-17, tirage commun `CA_Sites.draw` (autour de l'appelant entre deux distances, ou dans une zone ; genre `CA_Sites.KINDS` ; bases connues évitées ; cellules lues tirées au hasard, 9 cellules à bâtiments au plus), bandes `CA_MissionConfig.Targets` (100-200, 200-500, 500-1 500), résolveurs `RS_MissionAim.lua` pour scout, clear, retrieve, signal, barricade, relay, watch, item ; `no_target` retiré ; `reveal_area` d'une zone ; coût « Très loin » : environ 127 cellules traversées, 1,2 lue en moyenne quand elles sont peuplées. Bancs : `test_site_draw` 16, `test_mission_aim` 9, `test_protocol` OK (`scenario_reveal_zone`), bancs de missions et LK `test_lk_sites*` OK ; luacheck 0 ; suite complète `python tests/run_all.py --keep-going` `Summary: 211 passed, 1 failed` (613,8 s), seul échec `luacheck-contents` (ligne de commentaire trop longue dans `RS_Trade.lua`, corrigée ; `--only luacheck-contents` `Summary: 1 passed, 0 failed`). Reste en jeu : deux missions de même distance visent deux bâtiments différents, `reveal_area` d'une zone, pas d'à-coup « Très loin ».


- [x] **E25-T03** — Onglet « Lieux » de l'atelier et choix dans des listes
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E25-T01
  - Faire : D02, D05, D07, D08 ; onglet « Lieux » (point ou zone, collage depuis la carte, lien de carte, voix qui
    l'utilisent, suppression refusée si utilisé), listes de lieux dans les voix avec « Nouveau lieu… », objectif de
    mission (lieu, Près du joueur, Plus loin, Très loin, genre de bâtiment), relevés en jeu vers l'onglet, « Proposer »
    du nom d'un lieu.
  - Accepté si : `test_atelier_*`, `atelier_smoke` (créer un lieu, le choisir dans une voix, refus de suppression, fr et
    en), captures regardées.
  - Preuve : 2026-11-17, onglet « Lieux » (`placestab.js`, `placeform.js`, `placestore.js`, `places.js`) : endroit précis ou quartier, collage depuis la carte, voix qui l'utilisent, suppression refusée si utilisé ; routes `GET/PUT /api/places` ; listes de lieux avec « Nouveau lieu… », objectif (Près du joueur, Plus loin, Très loin, un lieu) et genre de bâtiment, repères, cache, rendez-vous ; relevés en jeu dans l'onglet ; « Proposer » du nom d'un lieu. Bancs : `test_atelier_ui` 27, `test_atelier_server` 34, `test_atelier_places` 4, `test_atelier_ai` 20, autres `test_atelier_*` OK ; `atelier_smoke` `summary: OK (2 locales, 0 failure(s))` ; captures `atelier-*-places.png` regardées ; suite complète `python tests/run_all.py --keep-going` `Summary: 211 passed, 1 failed` (613,8 s), seul échec `luacheck-contents` (ligne de commentaire trop longue dans `RS_Trade.lua`, corrigée ; `--only luacheck-contents` `Summary: 1 passed, 0 failed`).


- [x] **E25-T04** — Wiki, exemples et CHANGELOG des lieux communs
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E25-T02, E25-T03
  - Faire : wiki 10, 13, 14 (fr, en), CHANGELOG, captures refaites, suite complète.
  - Accepté si : `test_wiki_voice_examples`, captures regardées, suite complète verte.
  - Preuve : 2026-11-17, wiki 10, 13, 14 (fr, en) : fichier commun des lieux, où une voix nomme un lieu, objectif et genre de bâtiment, onglet « Lieux », exemples au nouveau format ; `protocole-carnet-v2.md`, wiki 03 ; CHANGELOG ; captures refaites (`atelier_doc_shots` `summary: OK`) et regardées. Bancs : `test_persona_sections` 12, `test_wiki_voice_examples` 6 ; suite complète `python tests/run_all.py --keep-going` `Summary: 211 passed, 1 failed` (613,8 s), seul échec `luacheck-contents` (ligne de commentaire trop longue dans `RS_Trade.lua`, corrigée ; `--only luacheck-contents` `Summary: 1 passed, 0 failed`).
