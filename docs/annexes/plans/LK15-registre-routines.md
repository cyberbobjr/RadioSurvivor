# LK15 — Registres des routines et potager du jardinier

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** à faire — 0 / 6 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | LK15-T01 | Moteur des tâches du foyer et registre `registerJob` | `à faire` | hors jeu | — |
| ☐ | LK15-T02 | Registre des activités et une routine par fichier | `à faire` | hors jeu | LK15-T01 |
| ☐ | LK15-T03 | Découpage vérifié en jeu | `à faire` | MP | LK15-T02 |
| ☐ | LK15-T04 | Creuser un sillon (`LK_Job_Dig`) | `à faire` | MP | LK15-T03 |
| ☐ | LK15-T05 | Semer (`LK_Job_Sow`) | `à faire` | MP | LK15-T04 |
| ☐ | LK15-T06 | Graines reçues par le jardinier | `à faire` | MP | LK15-T05 |

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

- [ ] **LK15-T01** — Moteur des tâches du foyer et registre `registerJob`
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `LK_Upkeep.lua` ; `server/LivingKnox/Jobs/LK_Job_Refuel.lua`, `LK_Job_Repair.lua`, `LK_Job_Harvest.lua`, `LK_Job_Water.lua`, `LK_Job_Clean.lua`, `LK_Job_Glass.lua` ; `LK_Garden.lua` ; `tests/test_lk_upkeep.py`, `tests/test_lk_forage.py`, `tests/test_lk_homes.py` (chargement du dossier) ; `docs/annexes/conception/entretien.md`
  - Faire : ADR D01, D02, D03, D06 : moteur sans nom de tâche, chaque tâche actuelle dans son fichier, ordre et `prefer` déclarés par la tâche (`prefer = "garden"` pour l'arrosage et la récolte, à la place de `Upkeep.GARDEN_JOBS`). Aucun changement de comportement.
  - Accepté si : `grep` de `job.kind ==` vide dans le moteur ; banc du moteur avec une fausse tâche inscrite par le test (relevé, réservation, effet une fois, préférence) ; bancs actuels de l'entretien, du potager et des foyers verts sans changement d'attendu ; luacheck sans hausse.
  - Tests : bancs hors jeu complets.
  - Preuve : —
  - Reste : —
- [ ] **LK15-T02** — Registre des activités et une routine par fichier
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK15-T01
  - Fichiers : `LK_Routines.lua` ; `LK_RoutineExec.lua` ; `server/LivingKnox/Routines/` (guet et rondes, sommeil, repas, corvées visibles) ; `LK_Fortify.lua`, `LK_Upkeep.lua` (inscription comme activités) ; bancs `tests/test_lk_routines.py`, `test_lk_meals.py`, `test_lk_fortify*.py`, `test_lk_upkeep.py` ; `docs/annexes/conception/routines.md`
  - Faire : ADR D04, D05, D06 : `Routines.registerActivity`, `Routines.apply` sans module nommé, ordre actuel gardé (barricades, entretien, corvée visible) ; découpage de `LK_Routines.lua`. Aucun changement de comportement.
  - Accepté si : `Routines.apply` ne cite ni `Fortify`, ni `Upkeep`, ni un comportement par son nom ; banc de l'aiguillage avec une fausse activité ; bancs actuels verts sans changement d'attendu.
  - Tests : bancs hors jeu complets.
  - Preuve : —
  - Reste : —
- [ ] **LK15-T03** — Découpage vérifié en jeu
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK15-T02
  - Fichiers : —
  - Faire : ADR D06 : campagnes solo (deux mods, Living Knox seul) et MP (`mp`, `mp-ambient`) sur le commit du découpage.
  - Accepté si : mêmes résultats que les campagnes vertes du 2026-11-13 (`20261113-071238-run-13d311e27a22`, `20261113-092625-parallel-3-13d311e27a22`, `20261113-095437-run-85680d65085c`).
  - Tests : campagnes en jeu.
  - Preuve : —
  - Reste : —
- [ ] **LK15-T04** — Creuser un sillon (`LK_Job_Dig`)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK15-T03
  - Fichiers : `server/LivingKnox/Jobs/LK_Job_Dig.lua` ; `LK_Garden.lua` ; banc nouveau ; suite en jeu `lk.garden`
  - Faire : ADR D07, Q01 : case de terre libre, dehors, au rez-de-chaussée, dans la zone du foyer, au plus `MAX_PLOTS` sillons par foyer ; outil `DIG_PLOW` du stock sinon mains nues (durée doublée) ; effet `SFarmingSystem.instance:plow`, herbes hautes retirées d'abord.
  - Accepté si : au banc, sillon créé une fois, plafond respecté, case refusée hors conditions ; en jeu, le sillon apparaît chez les deux clients.
  - Tests : banc ; suite `lk.garden` (campagnes solo et MP).
  - Preuve : —
  - Reste : —
- [ ] **LK15-T05** — Semer (`LK_Job_Sow`)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK15-T04
  - Fichiers : `server/LivingKnox/Jobs/LK_Job_Sow.lua` ; `LK_Garden.lua` ; banc ; suite `lk.garden`
  - Faire : ADR D07 : sillon vide, graine du stock dont le mois est dans `sowMonth`, effet `plant:seed(type, 0)`, graine retirée du conteneur et de la référence du stock dans la même écriture.
  - Accepté si : au banc, une graine en moins, une plante semée, rien hors saison ; en jeu, la plante semée est vue par les deux clients, puis arrosée par la tâche existante.
  - Tests : banc ; suite `lk.garden`.
  - Preuve : —
  - Reste : —
- [ ] **LK15-T06** — Graines reçues par le jardinier
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK15-T05
  - Fichiers : `server/LivingKnox/Jobs/LK_Job_SeedSupply.lua` (ou activité du jardinier) ; banc ; suite `lk.garden`
  - Faire : ADR D08, Q01 : dépôt de graines de saison au foyer quand le stock en a moins de `SEED_LOW`, au plus une fois tous les `SEED_DAYS` jours par groupe qui a un jardinier ; graines ajoutées à la référence du stock (ni perte ni vol à la relecture).
  - Accepté si : au banc, dépôt une fois par fenêtre, rien sans jardinier, rien au-dessus du seuil ; en jeu, le potager se remplit sans action du joueur.
  - Tests : banc ; suite `lk.garden`.
  - Preuve : —
  - Reste : —
