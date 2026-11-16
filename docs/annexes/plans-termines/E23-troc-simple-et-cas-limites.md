# E23 — Troc simple et cas limites

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** terminée — 9 / 9 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E23-T01 | Sac de récompense gardé jusqu'à sa pose | `testé hors jeu` | hors jeu | — |
| ☑ | E23-T02 | Mission perdue avec le mort | `testé hors jeu` | hors jeu | — |
| ☑ | E23-T03 | Délai suspendu sans pont | `testé hors jeu` | hors jeu | — |
| ☑ | E23-T04 | Livraison comptée après un arrêt brutal | `testé hors jeu` | hors jeu | — |
| ☑ | E23-T05 | Carte de planque remise d'abord | `testé hors jeu` | hors jeu | — |
| ☑ | E23-T06 | Troc par liste d'objets | `testé hors jeu` | hors jeu | — |
| ☑ | E23-T07 | Échange tout ou rien sur ce qui a été déposé | `testé hors jeu` | hors jeu | E23-T06 |
| ☑ | E23-T08 | Annulations rares et annoncées | `testé hors jeu` | hors jeu | E23-T06 |
| ☑ | E23-T09 | Atelier, wiki et exemples du troc | `testé hors jeu` | hors jeu | E23-T06, E23-T07, E23-T08 |

<!-- fin du tableau de bord -->

**Mod.** RadioSurvivor (`batman_RadioSurvivor`) pour le troc, les récompenses et les missions des voix ; CoreAI
(`batman_CoreAI`) pour les missions, les caches et le carnet ; le pont (`bridge/`) pour les consignes du troc et
l'atelier. Living Knox hors périmètre.

**Objectif.** Un troc qu'un adolescent comprend : une liste d'objets convenue à la radio, déposée au lieu du
rendez-vous, échangée tout ou rien. Plus aucun cas où un joueur perd une récompense, une mission ou un dépôt sans
l'avoir mérité.

**ADR.** [Troc par liste d'objets et cas limites](../../architecture/decisions/adr-troc-simple-et-cas-limites.md)
(accepté le 2026-11-16) ; ce plan en est l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** E20 (troc déclaré dans la fiche), E22 (atelier).

**Sources.** Revue des cas limites du 2026-11-16 ; `Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_Trade*.lua`,
`TradeArrivals/`, `Rewards/` ; `Contents/mods/batman_CoreAI/42.21/media/lua/server/CoreAI/CA_Missions.lua`, `CA_Caches.lua`.

## Décisions

- 2026-11-16 — **E23** (utilisateur) : décisions D01 à D10 de l'ADR, posées une à une.
- 2026-11-16 — **E23** (utilisateur) : la fiche déclare d'avance ce que la voix propose et ce qu'elle accepte en paiement, et l'atelier édite les deux ; plus aucun objet saisi à la main (liste filtrable) ; lien vers la carte zomboidmap.com dans l'onglet des lieux.
- 2026-11-16 — **E23** (confirmé par défaut) : dépôt incomplet = sanction actuelle de tricherie, rien déposé = la
  moitié ; si un autre participant est vivant, la mission continue pour lui.

## Hors périmètre

- Living Knox ; monnaie rendue ; lecture des véhicules.

## Tâches

- [x] **E23-T01** — Sac de récompense gardé jusqu'à sa pose
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : ADR D06. Une mission dont le sac de récompense (`m.cache`) n'est pas posé n'est jamais purgée.
  - Accepté si : un sac de récompense non posé après plus de 24 h réelles est posé au passage du joueur.
  - Preuve : `test_mission_recover.test_reward_cache_not_placed_is_kept_beyond_the_retention` du 2026-11-16 : mission de voix réussie, sac non posé, gardée après 36 h réelles, sac posé au passage du joueur, mission purgée ensuite (`Ran 17 tests ... OK`) ; `CA_Missions.lua` `cachePending` dans `M.prune`.

- [x] **E23-T02** — Mission perdue avec le mort
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : ADR D07. La mort d'un participant finit sa participation, message dans le carnet du nouveau personnage ;
    la mission continue pour un autre participant vivant.
  - Accepté si : bancs mort seul (mission finie, message) et mort en équipe (mission continue).
  - Preuve : `test_carnet.IdentitySuiteTests` du 2026-11-16 (`Ran 11 tests ... OK`) : mort seul, mission `cancelled_lost` sans réputation, message `IGUI_CA_LostMission` dans le carnet du nouveau personnage ; mort en équipe, mission active pour l'équipier (`IGUI_CA_LostMissionTeam`) ; `M.participantDied`, `CA_MissionLoss.lua` (7 jours de jeu, 8 messages par compte). Reste : mort réelle en MP avec un équipier.

- [x] **E23-T03** — Délai suspendu sans pont
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : ADR D08. Le délai d'une mission qui attend un rapport à une voix s'arrête tant que le pont ne répond pas ;
    message dans le carnet.
  - Accepté si : banc panne du pont puis retour, délai repris là où il s'était arrêté.
  - Preuve : `test_mission_recover.test_delay_of_a_report_to_a_voice_stops_while_the_bridge_is_silent` du 2026-11-16 : délai figé 3 h sans battement du pont (`CA_Bridge.alive`), ligne `IGUI_RS_VoiceSilentWaiting`, reprise au retour du pont ; crochet `paused(m)` du donneur (`RS_MissionHooks.lua`). Arrêt seulement une fois l'objectif atteint. Reste : coupure réelle du pont en jeu.

- [x] **E23-T04** — Livraison comptée après un arrêt brutal
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : ADR D09. Au redémarrage, les objets en cours de ramassage disparus sont comptés comme livrés.
  - Accepté si : banc arrêt entre le retrait et l'enregistrement.
  - Preuve : `test_voice_delivery` du 2026-11-16 (`Ran 33 tests ... OK`), 4 tests `test_interrupted_pickup_*` : objet disparu de la caisse ou sac disparu comptés, rien disparu rien compté, case non chargée : attente ; `RS_DeadDrops.lua` `stillThere`, `settleJournal`.

- [x] **E23-T05** — Carte de planque remise d'abord
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : ADR D10. La planque n'est réservée qu'après l'entrée de la carte dans l'inventaire.
  - Accepté si : banc inventaire plein, rien consommé, récompense encore à réclamer.
  - Preuve : `test_mission_rewards` du 2026-11-16 (`Ran 12 tests ... OK`) : carte entrée avant la réservation de la planque, inventaire plein sans rien consommer, carte remise par le poll `RS_RewardRetry.lua` dès qu'il y a de la place ; `R.retry`, `resume` facultatif par sorte.

- [x] **E23-T06** — Troc par liste d'objets
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : ADR D01, D04. `propose_trade` porte les deux listes ; le serveur vérifie stock, poids et équité au barème ;
    accord figé à l'arrivée ; liste convenue dans le carnet ; consignes du pont et fiches des marchands.
  - Accepté si : bancs accord équitable accepté, inéquitable refusé, nouvelle offre refusée après l'arrivée.
  - Preuve : `test_rs_trade.py` 30 OK, `test_rs_trade_run.py` 23 OK (`test_deal_frozen_once_the_trader_arrived`), `test_persona_sections` 12, `test_personas` 20, `test_fake_llm` 27 OK, du 2026-11-16 : `propose_trade` à deux listes (`gives`, `wants`), refus `not_taken`, `over_count`, `pay_weight`, `unfair`, `frozen` ; clé `accept=` de `[trade]` obligatoire (objets à prix ou catégories ; 5 catégories partagées de paiement), 11 fiches de marchands avec leur liste ; ligne « Accord de troc » dans le carnet ; consignes du pont réécrites. Reste en jeu : accord avec Gus et ligne du carnet.

- [x] **E23-T07** — Échange tout ou rien sur ce qui a été déposé
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E23-T06
  - Faire : ADR D02, D03. Contenu noté au premier chargement du lieu après la réservation ; seuls les ajouts comptent,
    additionnés sur tous les sacs ou contenants ; tout ou rien ; compensation et réputation ; consigne « jamais dans un
    véhicule ».
  - Accepté si : bancs butin déjà présent ignoré, deux sacs additionnés, dépôt incomplet gardé avec pénalité, rien
  - Preuve : `test_rs_trade_exchange.py` 20 OK, `test_rs_trade_traders` 14, `test_rs_town_traders` 14 OK du 2026-11-16 : `RS_TradeDeposit.lua` (contenu noté au premier chargement après réservation, gardé au redémarrage), ajouts additionnés, tout ou rien, dépôt incomplet gardé (−5), rien déposé (fait `trade.nodrop`, −2,5), sac d'un autre joueur déjà là ignoré, véhicule jamais lu. Reste en jeu : sacs avant/après accord, planque d'Odessa sur deux conteneurs, redémarrage du dédié.
    déposé, sac d'un autre joueur déjà là ignoré.

- [x] **E23-T08** — Annulations rares et annoncées
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E23-T06
  - Faire : ADR D05. Patrouille 1/75, hélicoptère 1/100, orage selon la météo du jeu ; annonce répétée chaque heure
    jusqu'au rendez-vous ; dépôt intact, aucune pénalité.
  - Accepté si : bancs tirages, annonce répétée, dépôt intact.
  - Preuve : `test_rs_trade_run.py` du 2026-11-16 : `test_patrol_and_helicopter_are_rare_reproducible_rolls` (1/75, 1/100 sur 15 000 tirages), `test_storm_cancels_and_is_announced_every_hour_until_the_meeting`, `test_cancelled_run_touches_no_deposit` ; causes vérifiées dès 3 h avant la fenêtre, `Run.remind`. Reste en jeu : annonce répétée.

- [x] **E23-T09** — Atelier, wiki et exemples du troc
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E23-T06, E23-T07, E23-T08
  - Faire : atelier (aides du troc), wiki 10, 13, 14 (fr, en), `passeur-table.md`, `persona-format.md`, CHANGELOG.
  - Accepté si : `test_wiki_voice_examples`, tests de l'atelier, captures refaites.
  - Preuve : Atelier : éditeur « Ce que la voix accepte », plus aucun objet à taper (liste filtrable à cocher, ligne en lecture seule), lien de carte zomboidmap.com zoomé sur la case (`maplink.js`) ; tests atelier OK (ui 17, help 5, catalog 10, server 33), `tools/atelier_smoke.py` `summary: OK (2 locales, 0 failure(s))`, `test_wiki_voice_examples` 5 OK, captures refaites ; wiki 10, 13, 14 (fr, en), `persona-format.md`, `passeur-table.md`, CHANGELOG. Suite complète du 2026-11-16 : `python tests/run_all.py --keep-going` `Summary: 208 passed, 0 failed, 0 skipped (649.5 s)`. Ensuite (demande de l'utilisateur) : « Revenir à la version du mod » recopie aussitôt la version du mod et s'offre aussi pour une copie en ancienne version (`test_atelier_server` 33 OK, `atelier_smoke` OK).
