# LK15 — Registres des routines et potager du jardinier

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 2 / 7 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | LK15-T01 | Moteur des tâches du foyer et registre `registerJob` | `testé hors jeu` | hors jeu | — |
| ☑ | LK15-T02 | Registre des activités et une routine par fichier | `testé hors jeu` | hors jeu | LK15-T01 |
| ☐ | LK15-T03 | Découpage vérifié en jeu | `à faire` | MP | LK15-T02 |
| ☐ | LK15-T04 | Creuser un sillon (`LK_Job_Dig`) | `testé hors jeu` | MP | LK15-T03 |
| ☐ | LK15-T05 | Semer (`LK_Job_Sow`) | `testé hors jeu` | MP | LK15-T04 |
| ☐ | LK15-T06 | Graines reçues par le jardinier | `testé hors jeu` | MP | LK15-T05 |
| ☐ | LK15-T07 | Potager en bord de zone : l'entretien du foyer n'est plus bloqué | `testé hors jeu` | MP | LK15-T04 |

<!-- fin du tableau de bord -->

**Mod (après la séparation).** Living Knox (`batman_LivingKnox`).

**Objectif.** Des routines et des tâches du foyer isolées, une par fichier, ajoutées sans toucher au moteur (principe
ouvert/fermé), puis un potager tenu par le jardinier : sillons creusés, graines semées, graines reçues
automatiquement.

**ADR.** [Registres des routines et des tâches du foyer](../../architecture/decisions/adr-registre-routines.md)
(accepté le 2026-11-13) ; ce plan en est l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** LK05-T07 (repas), LK05-T10 (entretien), LK05-T11 (arrosage et récolte), LK14-T03 (barricades),
LK05-T21 (préférence du jardinier, remplacée par `prefer`).

**Sources.** Relevé du code du 2026-11-13 (ADR, section Contexte) ; sources vanilla 42.22 du potager (ADR) ;
`pz-knowledge/mod-loading.md`.

## Décisions

- 2026-11-13 — **LK15** (utilisateur) : routines isolées, une par fichier, ajoutées sans toucher au code partout ;
  potager du jardinier « option 2 » (creuser et semer) avec des graines reçues automatiquement. ADR accepté le même jour ; Q01 confirmé par défaut (6 sillons, seuil 2 graines, 7 jours, un sachet de 5 graines de saison).

## Tâches

- [x] **LK15-T01** — Moteur des tâches du foyer et registre `registerJob`
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `LK_Upkeep.lua` ; `server/LivingKnox/Jobs/LK_Job_Refuel.lua`, `LK_Job_Repair.lua`, `LK_Job_Harvest.lua`, `LK_Job_Water.lua`, `LK_Job_Clean.lua`, `LK_Job_Glass.lua` ; `LK_Garden.lua` ; `tests/test_lk_upkeep.py`, `tests/test_lk_forage.py`, `tests/test_lk_homes.py` (chargement du dossier) ; `docs/annexes/conception/entretien.md`
  - Faire : ADR D01, D02, D03, D06 : moteur sans nom de tâche, chaque tâche actuelle dans son fichier, ordre et `prefer` déclarés par la tâche (`prefer = "garden"` pour l'arrosage et la récolte, à la place de `Upkeep.GARDEN_JOBS`). Aucun changement de comportement.
  - Accepté si : `grep` de `job.kind ==` vide dans le moteur ; banc du moteur avec une fausse tâche inscrite par le test (relevé, réservation, effet une fois, préférence) ; bancs actuels de l'entretien, du potager et des foyers verts sans changement d'attendu ; luacheck sans hausse.
  - Tests : bancs hors jeu complets.
  - Preuve : 2026-11-13 : `LK_Upkeep.lua` (476 lignes au lieu de 779) sans nom de tâche, registre `Upkeep.registerJob` (`kind`, `order`, `prefer`, `gesture`, `minutes`, `survey`, `apply`, facultatifs `place`, `standOnSelf`, `groupLog`) ; six tâches dans `server/LivingKnox/Jobs/` ; domaine du potager dans `LK_Garden.lua` (appelants mis à jour : suite `lk.forage`, `test_lk_food.py`) ; `Upkeep.GARDEN_JOBS` remplacé par `prefer = "garden"`. Bancs du moteur avec une fausse tâche (`EngineTests` : relevée, réservée, appliquée une fois ; ordre et préférence) rouges avant, verts après. `python tests/test_lk_upkeep.py` : `Ran 24 tests … OK` ; `test_lk_food.py` 32 OK ; `test_lk_homes.py` 22 OK ; `test_lk_peaks.py` 13 OK ; les 162 fichiers `tests/test_*.py` verts ; luacheck `Contents` 8 avertissements (inchangé), `dev` 0.
  - Reste : vérification en jeu par `LK15-T03`.
- [x] **LK15-T02** — Registre des activités et une routine par fichier
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK15-T01
  - Fichiers : `LK_Routines.lua` ; `LK_RoutineExec.lua` ; `server/LivingKnox/Routines/` (guet et rondes, sommeil, repas, corvées visibles) ; `LK_Fortify.lua`, `LK_Upkeep.lua` (inscription comme activités) ; bancs `tests/test_lk_routines.py`, `test_lk_meals.py`, `test_lk_fortify*.py`, `test_lk_upkeep.py` ; `docs/annexes/conception/routines.md`
  - Faire : ADR D04, D05, D06 : `Routines.registerActivity`, `Routines.apply` sans module nommé, ordre actuel gardé (barricades, entretien, corvée visible) ; découpage de `LK_Routines.lua`. Aucun changement de comportement.
  - Accepté si : `Routines.apply` ne cite ni `Fortify`, ni `Upkeep`, ni un comportement par son nom ; banc de l'aiguillage avec une fausse activité ; bancs actuels verts sans changement d'attendu.
  - Tests : bancs hors jeu complets.
  - Preuve : 2026-11-13 : `Routines.registerActivity({ id, behaviour, order, run })` ; `Routines.apply` réduit à la boucle du registre (ne cite ni module ni comportement) ; `LK_Routines.lua` 542 lignes au lieu de 1 170 (constantes, relevé, plans, registre) ; outils partagés dans `LK_RoutineExec.lua` ; activités `Routines/LK_Routine_Watch.lua` (guet, ronde), `LK_Routine_Sleep.lua`, `LK_Routine_Meal.lua`, `LK_Routine_Chores.lua` ; `LK_Fortify` (`chore.fortify`, ordre 10) et `LK_Upkeep` (`chore.upkeep`, ordre 20) inscrits ; chargement des piles de test par `harness.routine_files()`. Banc `RegistryTests` (4 tests : ordre, première activité qui prend le membre, repli) rouge avant, vert après ; `test_lk_routines.py` 22 OK, `test_lk_chores.py` 12, `test_lk_meals.py` 15, `test_lk_upkeep.py` 24, `test_lk_decisions.py` 27, `test_kahlua.py` 40 ; les 162 fichiers `tests/test_*.py` verts ; luacheck `Contents` 8 (inchangé), `dev` 0.
  - Reste : vérification en jeu par `LK15-T03`.
- [ ] **LK15-T03** — Découpage vérifié en jeu
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK15-T02
  - Fichiers : —
  - Faire : ADR D06 : campagnes solo (deux mods, Living Knox seul) et MP (`mp`, `mp-ambient`) sur le commit du découpage.
  - Accepté si : mêmes résultats que les campagnes vertes du 2026-11-13 (`20261113-071238-run-13d311e27a22`, `20261113-092625-parallel-3-13d311e27a22`, `20261113-095437-run-85680d65085c`).
  - Tests : campagnes en jeu.
  - Preuve : `lk.meals` et `lk.routines` verts en MP ; `lk.meals` vert en solo deux mods et Living Knox seul ; campagnes du 2026-11-13 au soir et du 2026-11-14 (dossier de travail, commits `8b439ee` à `a7ddc94`) : MP 3 tranches `tools/autoclient/runs/20261113-233636-parallel-3` 510/534, 3 FAIL (`lk.alert` garde, `lk.forage` arrosage, `rs.npctalk` délai : corrigés par `19ac890`, `44b200a`, `f9c8d8f`) ; solo deux mods `20261113-235754-parallel-2` 245/257, 3 FAIL (`lk.forage` : lancé avant `44b200a` ; `lk.upkeep` : corrigé par `a7ddc94` ; `lk.debugview` : ouvert, registre des écarts) ; Living Knox seul `20261114-001702-parallel-2` 105/114, 0 FAIL ; `mp-ambient` `20261114-003116-mp-cf36126965e3` 23/24, 0 FAIL ; campagne MP de contrôle sur `a7ddc94` arrêtée par Claude Code (mémoire de la machine basse), non relancée
  - Reste : campagnes partielles du 2026-11-13 après-midi, lancées depuis le dossier de travail (la copie figée d'un commit échoue tant que l'abandon de CharacterReputation de l'autre session n'est pas commité : `batman_CharacterReputation` encore dans la liste des mods du lanceur commité ; c'est aussi la cause du « code 2, total=0 » de la campagne solo deux mods du matin) : MP sur `157c4a0` (`runs/20261113-150840-parallel-3`) code 1, `total=533 pass=509 fail=3` : `lk.upkeep` (tâches du potager avant le verre et le sang, corrigé par `73247c8`), `lk.alert` (cri sans auditeur chez le second client, intermittent connu : 2 échecs sur 9 avant) et `lk.traversal` « destination behind a locked door elsewhere » (intermittent connu : 4 sur 34) ; `mp-ambient` code 0, `total=24 pass=23 fail=0` (`runs/20261113-153040-mp-a41ca303d196`) ; solo deux mods interrompue (jeu rendu à l'utilisateur) ; à refaire sur le dernier commit : solo deux mods, solo Living Knox seul, MP
- [ ] **LK15-T04** — Creuser un sillon (`LK_Job_Dig`)
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK15-T03
  - Fichiers : `server/LivingKnox/Jobs/LK_Job_Dig.lua` ; `LK_Garden.lua` ; banc nouveau ; suite en jeu `lk.garden`
  - Faire : ADR D07, Q01 : case de terre libre, dehors, au rez-de-chaussée, dans la zone du foyer, au plus `MAX_PLOTS` sillons par foyer ; outil `DIG_PLOW` du stock sinon mains nues (durée doublée) ; effet `SFarmingSystem.instance:plow`, herbes hautes retirées d'abord.
  - Accepté si : au banc, sillon créé une fois, plafond respecté, case refusée hors conditions ; en jeu, le sillon apparaît chez les deux clients.
  - Tests : banc ; suite `lk.garden` (campagnes solo et MP).
  - Preuve : 2026-11-13 : `Jobs/LK_Job_Dig.lua` (`dig`, ordre 46, `prefer = "garden"`) ; domaine dans `LK_Garden.lua` (`canDig`, `plots`, `digSpot`, `digTool`, `dig`, `MAX_PLOTS` 6) : conditions du menu vanilla, hors du bâtiment et à l'air libre, un seul sillon vide à la fois, outil `DIG_PLOW` du stock gardé, mains nues deux fois plus long ; champ générique facultatif `duration(job, gid)` ajouté au registre `Upkeep.registerJob` (aucun nom de tâche dans le moteur) ; banc `DigTests` rouge puis vert ; `python tests/test_lk_garden.py` : `Ran 20 tests … OK` ; `test_lk_upkeep.py` 24 OK, `test_lk_food.py` 32 OK, `test_autoclient.py` 93 OK ; `python tests/run_all.py` : `162 passed, 0 failed` ; luacheck `Contents` 8 (inchangé), `dev` 0
  - Reste : campagnes solo et MP (suite `lk.garden` écrite, inscrite dans `solo-lk` et `mp`, jouée sur les doublures) ; à vérifier en jeu : `ISShovelGroundCursor.GetDirtGravelSand` chargé sur un serveur dédié (sinon aucun sillon, sans erreur), sillon vu par les deux clients ; `PlaceDirtAboveground` non suivi ; la première case de terre de la zone est prise (emplacement à juger en jeu)
- [ ] **LK15-T05** — Semer (`LK_Job_Sow`)
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK15-T04
  - Fichiers : `server/LivingKnox/Jobs/LK_Job_Sow.lua` ; `LK_Garden.lua` ; banc ; suite `lk.garden`
  - Faire : ADR D07 : sillon vide, graine du stock dont le mois est dans `sowMonth`, effet `plant:seed(type, 0)`, graine retirée du conteneur et de la référence du stock dans la même écriture.
  - Accepté si : au banc, une graine en moins, une plante semée, rien hors saison ; en jeu, la plante semée est vue par les deux clients, puis arrosée par la tâche existante.
  - Tests : banc ; suite `lk.garden`.
  - Preuve : 2026-11-13 : `Jobs/LK_Job_Sow.lua` (`sow`, ordre 44, `prefer = "garden"`) ; `LK_Garden.lua` (`month`, `inSeason`, `sowable`, `seedCount`, `findSeed`, `takeSeed`) : sillon vide, graine de saison (`sowMonth`), jamais un objet de nourriture, une graine retirée par `Stock.takeItem` puis `plant:seed(type, 0)`, saison relue à l'effet ; banc `SowTests` rouge puis vert ; `python tests/test_lk_garden.py` : `Ran 20 tests … OK` ; `test_lk_upkeep.py` 24 OK, `test_lk_food.py` 32 OK, `test_autoclient.py` 93 OK ; `python tests/run_all.py` : `162 passed, 0 failed` ; luacheck `Contents` 8 (inchangé), `dev` 0
  - Reste : campagnes solo et MP (`lk.garden`) : plante semée vue par les deux clients, puis arrosée ; le groupe sème aussi dans un sillon vide d'un joueur situé dans sa zone
- [ ] **LK15-T06** — Graines reçues par le jardinier
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK15-T05
  - Fichiers : `server/LivingKnox/Jobs/LK_Job_SeedSupply.lua` (ou activité du jardinier) ; banc ; suite `lk.garden`
  - Faire : ADR D08, Q01 : dépôt de graines de saison au foyer quand le stock en a moins de `SEED_LOW`, au plus une fois tous les `SEED_DAYS` jours par groupe qui a un jardinier ; graines ajoutées à la référence du stock (ni perte ni vol à la relecture).
  - Accepté si : au banc, dépôt une fois par fenêtre, rien sans jardinier, rien au-dessus du seuil ; en jeu, le potager se remplit sans action du joueur.
  - Tests : banc ; suite `lk.garden`.
  - Preuve : 2026-11-13 : `Jobs/LK_Job_SeedSupply.lua` (`seeds`, ordre 42, `prefer = "garden"`, journal du groupe) : un membre range au dépôt un sachet de 5 graines d'une variété de saison (carotte, pomme de terre, chou, tomate, à tour de rôle, sans hasard) quand le foyer a moins de 2 graines semables, au plus une fois tous les 7 jours de jeu, seulement avec un jardinier vivant ; rien en hiver ; bancs `SeedSupplyTests` et `PureGardenTests` rouges puis verts ; `python tests/test_lk_garden.py` : `Ran 20 tests … OK` ; `test_lk_upkeep.py` 24 OK, `test_lk_food.py` 32 OK, `test_autoclient.py` 93 OK ; `python tests/run_all.py` : `162 passed, 0 failed` ; luacheck `Contents` 8 (inchangé), `dev` 0
  - Reste : campagnes solo et MP (`lk.garden`) ; les graines n'ont pas de catégorie de stock : elles ne sont pas dans la référence (ni perte ni vol à la relecture, comme les graines d'une récolte) ; le jour du dernier sachet n'est pas sauvegardé (un redémarrage du serveur peut donner un sachet de plus dans la fenêtre)
- [ ] **LK15-T07** — Potager en bord de zone : l'entretien du foyer n'est plus bloqué
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK15-T04
  - Fichiers : `LK_Upkeep.lua` (`placeFor`) ; `LK_Garden.lua` (cases du potager) ; `tests/test_lk_upkeep.py`
  - Faire : défaut de la campagne MP du 2026-11-13 (`lk.upkeep`, `runs/20261113-150840-parallel-3/shard3`), reproduit au banc sur le vrai Lua du potager (`E19-T04`) : le premier sillon tombe au bord de la zone (10 cases), sa place est à 11 cases, le membre n'est plus « au foyer » (`HOME_RADIUS` 10), quitte sa routine, la tâche est libérée sans délai et l'autre ouvrier la reprend en boucle ; le verre et le sang ne sont jamais faits. Correction confirmée par défaut (option recommandée) : une place hors du rayon « au foyer » est refusée par le moteur des tâches (`placeFor`), qui clôt la tâche avec son délai d'attente au lieu de la libérer ; et le potager ne propose que des cases dont la place reste dans ce rayon. L'ordre des tâches du commit `73247c8` (potager après l'entretien) est gardé, mais n'était pas la cause.
  - Accepté si : `test_garden_at_the_edge_of_the_home_does_not_hold_the_upkeep` passe (marque `expectedFailure` retirée) ; bancs de l'entretien, du potager et des décisions verts ; en jeu, `lk.upkeep` verte en campagne MP.
  - Tests : bancs ; campagne MP.
  - Preuve : 2026-11-13 : `Upkeep.atHome` (case entière dans le rayon « au foyer » des décisions, `écart + 0,5 ≤ HOME_RADIUS` : un corps arrêté n'est pas au centre de sa case) ; `placeFor` écarte les places hors du foyer, `spec.place(job, home)` reçoit le foyer ; une place hors du foyer clôt la tâche avec son délai (`DONE_MINUTES`) au lieu de la libérer ; `Garden.digSpot` et `Garden.placeNear` ne proposent que des cases au foyer ; aussi corrigé : récolte et arrosage d'une plante au bord nord (tâche prise 3 fois avant, 1 après) ; `test_garden_at_the_edge_of_the_home_does_not_hold_the_upkeep` rouge avant (« upkeep jobs not all done: condition not met within 300000 ms »), vert après (marque `expectedFailure` retirée) ; `EngineTests.test_place_out_of_the_home_is_refused_and_closed_with_its_delay` rouge avant (`1 != 0` reprise), vert après ; `test_ripe_plant_at_the_edge_of_the_home_is_harvested_from_inside` ; `test_lk_upkeep.py` 28 OK, `test_lk_garden.py` 29 OK, `test_lk_food.py` 33, `test_lk_routines.py` 23, `test_lk_chores.py` 13, `test_lk_decisions.py` 27, `test_lk_homes.py` 22, `test_lk_repair.py` 14, `test_lk_meals.py` 16 verts sans attendu changé ; `python tests/run_all.py` : `168 passed, 0 failed` (515 s) ; luacheck `Contents` 8, `dev` 0
  - Reste : campagne MP (`lk.upkeep`) ; un objet posé sur l'anneau 10 du foyer n'a souvent aucune place : tâche refusée puis reproposée toutes les 10 minutes, sans boucle (laissé ainsi, confirmé par défaut) ; ménage et verre pouvaient boucler dans un grand bâtiment (déduit du code, aucun banc) ; `freeSquareAtHome` reprend l'ordre de `Bodies.findFreeSquare` (un filtre facultatif dans `LK_Bodies.lua` serait mieux : LK16)
