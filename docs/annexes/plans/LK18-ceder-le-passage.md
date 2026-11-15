# LK18 — Céder le passage

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** à faire — 0 / 3 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | LK18-T01 | Registre des priorités de passage et arbitrage | `à faire` | hors jeu | — |
| ☐ | LK18-T02 | Action « s'écarter », signalement du blocage par l'exécutant | `à faire` | MP | LK18-T01 |
| ☐ | LK18-T03 | Places d'arrêt hors des portes et des couloirs | `à faire` | solo | — |

<!-- fin du tableau de bord -->

**Mod.** Living Knox (`batman_LivingKnox`).

**Objectif.** Deux PNJ qui se gênent se cèdent le passage par une règle locale : le moins prioritaire s'écarte, puis
reprend sa tâche. Aucun PNJ ne s'arrête dans une porte ou un couloir.

**ADR.** [Les PNJ se cèdent le passage](../../architecture/decisions/adr-ceder-le-passage.md) (accepté le 2026-11-15).

**Dépend de.** LK17 (chemin du jeu), LK15 (registre des routines), LK16 (remise en ordre SOLID).

**Sources.** Observation de l'utilisateur du 2026-11-15 ; campagne `solo-lk` du 2026-11-15 sur `be9f01d1`.

- [ ] **LK18-T01** — Registre des priorités de passage et arbitrage
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : nouveau module de passage (registre `priority(kind, n)`, arbitrage pur) ; déclaration de priorité dans le fichier de chaque comportement ou directive concerné ; bancs dédiés
  - Faire : D02 et D05 de l'ADR. L'arbitrage prend deux PNJ (priorité, identifiant) et les cases libres autour du bloqueur, et rend « le bloqueur s'écarte vers telle case », « le bloqueur recule » ou « rien ».
  - Accepté si : au banc, chaque cas de l'ADR donne la décision attendue ; un comportement ajouté par un test déclare sa priorité sans modifier le module de passage.
  - Tests : bancs de l'arbitrage et du registre.
  - Preuve : —
  - Reste : —

- [ ] **LK18-T02** — Action « s'écarter », signalement du blocage par l'exécutant
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK18-T01
  - Fichiers : exécutant (signalement d'un PNJ voisin sur le trajet), autorité (vérification, ordre), action « s'écarter » au registre des actions ; suite en jeu dédiée dans `batman_LivingKnoxTests`
  - Faire : D01, D03 et D06. Le blocage par un PNJ est signalé à l'autorité, qui arbitre et donne l'action au bloqueur ; celui-ci s'écarte, attend le passage ou une durée bornée, puis reprend sa tâche.
  - Accepté si : en jeu, deux PNJ face à face dans une porte passent tous les deux ; un PNJ de garde sur le passage s'écarte puis revient, en solo et en MP.
  - Tests : bancs ; suite en jeu dédiée ; campagnes `solo-lk` et MP.
  - Preuve : —
  - Reste : —

- [ ] **LK18-T03** — Places d'arrêt hors des portes et des couloirs
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : le choix des places d'arrêt (un seul endroit, utilisé par les comportements qui s'arrêtent)
  - Faire : D04. Une place d'arrêt n'est jamais une case de porte ou de portail, un seuil ou un passage d'une case de large ; elle se décale à la case libre la plus proche.
  - Accepté si : au banc, une place demandée dans une porte ou un couloir est décalée ; en jeu, aucun PNJ de garde ou en attente sur un seuil.
  - Tests : bancs ; campagne `solo-lk`.
  - Preuve : —
  - Reste : —
