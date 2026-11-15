# LK17 — Chemin du jeu pour les PNJ, passages interdits marqués

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** à faire — 0 / 2 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | LK17-T01 | Passages interdits marqués dans la mémoire du corps | `à faire` | MP | — |
| ☐ | LK17-T02 | Suppression du guidage maison | `à faire` | MP | LK17-T01 |

<!-- fin du tableau de bord -->

**Mod.** Living Knox (`batman_LivingKnox`).

**Objectif.** Un PNJ va de A à B par le chemin que calcule le jeu. Les passages que les règles de contact lui refusent sont
marqués dans la mémoire de son corps (`getMapKnowledge`), et le jeu les contourne. Le guidage maison de `LK_Routing.lua`
disparaît.

**ADR.** [Déplacements des PNJ : chemin du jeu, passages interdits marqués](../../architecture/decisions/adr-chemin-vanilla.md)
(accepté le 2026-11-15) ; ce plan en est l'ordre de livraison.

**Dépend de.** LK04 (déplacement et obstacles), LK05-T23.

**Sources.** Voir l'ADR (sources Java 42.22, campagnes du 2026-11-15).

- [ ] **LK17-T01** — Passages interdits marqués dans la mémoire du corps
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `LK_Obstacles.lua` (refus au contact → marque), `LK_Directives.lua` (consigne de déplacement : liste des passages interdits ; pose chez l'exécutant), nouveau module de marques si besoin ; bancs `tests/test_lk_obstacles.py`, `tests/test_lk_directives.py`
  - Faire : D02 et D03 de l'ADR : au refus au contact, la fenêtre, la porte ou le bord est marqué bloqué pour ce PNJ et le chemin est redemandé aussitôt ; à l'émission d'un déplacement, les ouvertures refusées par les règles dans le bâtiment de départ et celui d'arrivée sont marquées d'avance ; l'exécutant pose les marques dans `getMapKnowledge()` du corps avant la demande de chemin, et à chaque changement de propriétaire.
  - Accepté si : au banc, une fenêtre refusée est marquée et le déplacement suivant ne la prend plus, sans point de passage Lua ; en jeu, `lk.traversal`, `lk.doors`, `lk.expedition`, `lk.windowsally` verts en solo et en MP.
  - Tests : bancs ci-dessus ; campagnes `solo-lk` et MP.
  - Preuve : —
  - Reste : —

- [ ] **LK17-T02** — Suppression du guidage maison
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK17-T01
  - Fichiers : `LK_Routing.lua` (`planDoorRoute`, modèle « zombie », jalonnement, sortie par une porte, prudence), `LK_Directives.lua` (`planDoors`, champs `w`/`dr` des consignes qui en viennent), `LK_Obstacles.lua` (`windowRefusedAt`, évitement de 60 s s'il ne sert plus), bancs qui ne testaient que ce code
  - Faire : D01, D04 et D05 : chaque déplacement part du chemin du jeu ; le dernier recours d'un PNJ enfermé lève les marques des fenêtres de son bâtiment ; tout le code de guidage remplacé est supprimé avec ses tests ; le détour des plantes et feux de camp reste.
  - Accepté si : plus aucun point de passage calculé pour éviter fenêtres ou portes ; mêmes suites en jeu vertes en solo et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes `solo-lk`, `solo` et MP.
  - Preuve : —
  - Reste : —
