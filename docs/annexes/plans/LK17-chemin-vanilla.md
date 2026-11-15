# LK17 — Chemin du jeu pour les PNJ, détour seulement après un refus

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** à faire — 0 / 2 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | LK17-T01 | Détour immédiat par la porte la plus proche après un refus au contact | `à faire` | MP | — |
| ☐ | LK17-T02 | Suppression du guidage maison | `à faire` | MP | LK17-T01 |

<!-- fin du tableau de bord -->

**Mod.** Living Knox (`batman_LivingKnox`).

**Objectif.** Un PNJ va de A à B par le chemin que calcule le jeu. Quand les règles de contact lui refusent une fenêtre,
une porte ou une clôture, il reçoit un seul détour court par la porte utilisable la plus proche, puis le jeu recalcule le
chemin. Le guidage maison de `LK_Routing.lua` disparaît.

**ADR.** [Déplacements des PNJ : chemin du jeu, détour seulement après un refus](../../architecture/decisions/adr-chemin-vanilla.md)
(accepté le 2026-11-15, révisé le même jour : le moteur natif ignore `MapKnowledge`) ; ce plan en est l'ordre de livraison.

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
