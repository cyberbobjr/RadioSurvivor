# E21 — Séparer Living Knox et RadioSurvivor autour de batman_CoreAI

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 2 / 10 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E21-T01 | Renommer le mod commun en batman_CoreAI | `testé solo` | solo | — |
| ☑ | E21-T02 | Living Knox sans nom de RadioSurvivor dans ses journaux et ses dossiers | `testé hors jeu` | hors jeu | E21-T01 |
| ☐ | E21-T03 | Carnet client et interfaces dans batman_CoreAI | `testé hors jeu` | solo | E21-T01 |
| ☐ | E21-T04 | Carnet serveur dans batman_CoreAI | `à faire` | MP | E21-T03 |
| ☐ | E21-T05 | Living Knox fournisseur du carnet commun | `à faire` | solo | E21-T04 |
| ☐ | E21-T06 | RadioSurvivor sans appel à Living Knox | `à faire` | solo | E21-T04 |
| ☐ | E21-T07 | Trois mods de test et campagnes séparées | `à faire` | solo | E21-T05, E21-T06 |
| ☐ | E21-T08 | Bancs de Living Knox sans RadioSurvivor | `à faire` | hors jeu | E21-T07 |
| ☐ | E21-T09 | Les trois montages en jeu, solo et MP | `à faire` | MP | E21-T08 |
| ☐ | E21-T10 | Documentation, README et descriptions Workshop | `à faire` | hors jeu | E21-T09 |

<!-- fin du tableau de bord -->

**Mods.** `batman_RadioSurvivorCore` (renommé `batman_CoreAI`), `batman_LivingKnox`, `batman_RadioSurvivor`, le pont,
les mods de test sous `dev/`.

**Objectif.** Living Knox et RadioSurvivor s'ignorent. Ils ne partagent que le pont et le mod commun `batman_CoreAI`,
qui porte le carnet et les méthodes factorisées. Les tests de Living Knox ne chargent rien de RadioSurvivor.

**ADR.** [Living Knox et RadioSurvivor séparés autour de batman_CoreAI](../../architecture/decisions/adr-coreai-separation.md)
(accepté le 2026-11-15). Ce plan en est l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** E18 (trois mods dans un article), E20 (gabarits de mission dans le commun).

**Sources.** Relevé des liens du 2026-11-15 :

- **Mod commun :** 45 fichiers Lua.
  - 22 servent aux deux mods.
  - 11 ne servent qu'à RadioSurvivor : `RC_Caches` et les gabarits de mission Barricade, Clear, Item, Recover, Relay,
    Retrieve, Route, Scout, Signal et Watch.
  - 1 ne sert qu'à Living Knox : `RC_SlotFile`.
  - Les autres sont chargés seuls, sans `require`.
- **Living Knox vers RadioSurvivor :**
  - l'adaptateur `RS_LivingKnox.lua` ;
  - `radioSurvivorActive()` dans `LK_TalkView`, `LK_TalkAlone` et `LK_Contacts` ;
  - 10 journaux `[RS_…]` ;
  - la lecture de `RS_LivingKnox` par `LK_Admin`.
- **RadioSurvivor vers Living Knox :**
  - `RS_Carnet_Server` appelle `Agreements`, `Relations`, `Hostility` et `Talk` ;
  - `RS_Facts` lit `API` et trois événements `OnLivingKnox…` ;
  - `RS_Relations` appelle `Observations`, `Agreements`, `API` et `PersonalRelation` ;
  - le commun lui-même lit `LivingKnox.Identity` (`RC_MissionClear`).
- **Tests :**
  - 44 bancs `test_lk_*.py` touchent RadioSurvivor : 24 chargent son code, 20 ne prennent qu'une suite du mod de test
    `batman_RadioSurvivorTests` ;
  - ce mod de test contient 75 suites LK, 68 RS et 4 RC.
- **Hors `Contents/` :** 209 fichiers nomment `RadioSurvivorCore` (tests 105, dev 53, docs 40, outils 4, pont 1,
  racine 6).

**Conception.** [Carnet commun dans batman_CoreAI](../conception/carnet-commun-e21.md) : répartition fonction par fonction, chemin unique de Living Knox, registres neutres, tranches de E21-T03 à E21-T06.

**Décisions.** Voir l'ADR (D01 à D08). Ordre retenu par défaut :

1. le renommage, mécanique, d'abord, pour que la suite parte des noms définitifs ;
2. puis le carnet ;
3. puis les liens entre les deux mods ;
4. puis les tests ;
5. enfin les campagnes.

- [x] **E21-T01** — Renommer le mod commun en batman_CoreAI
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `Contents/mods/batman_RadioSurvivorCore` → `Contents/mods/batman_CoreAI` (dossier Lua `CoreAI/`, fichiers `CA_*.lua`, `mod.info`, traductions `IGUI_CA_`) ; `require=` des autres `mod.info` (dont `dev/`) ; tout code, banc, outil, pont et document qui nomme `RadioSurvivorCore`, `RC_` ou `IGUI_RC_`
  - Faire : renommage scripté selon D03 de l'ADR ; clés `RS_` du commun en `CA_` ; dossier d'échange du pont `Zomboid/Lua/batman_CoreAI/` ; journaux `[CoreAI]` ; aucune autre modification.
  - Accepté si : aucune occurrence de `RadioSurvivorCore`, `batman_RadioSurvivorCore`, `RC_` (préfixe de module) ni `IGUI_RC_` hors des plans terminés et de l'historique ; suite hors jeu au niveau d'avant ; démarrage en jeu sans erreur des trois mods.
  - Tests : `tests/run_all.py --keep-going` ; luacheck ; `tools/check_case.py` ; campagne solo des deux mods.
  - Preuve : commit `d8954ee` (renommage scripté, 60 fichiers déplacés, 367 retouchés) ; `python RadioSurvivor/tests/run_all.py --keep-going` le 2026-11-15 : `Summary: 185 passed, 0 failed, 0 skipped` (avant : 185 passed), luacheck Contents 8 avertissements (référence 8), `case` PASS, plan 0 erreur ; 5 bancs qui lisaient l'ancien nom par accident corrigés (ordre des mods de `test_autoclient`, verrou des notes `CoreAI`, textures du carnet, marque `CA_` reconnue par le troc) ; commit `d8954ee` ; `run_all.py --keep-going` : `Summary: 185 passed, 0 failed, 0 skipped` ; campagne solo des deux mods du 2026-11-15 sur `8fc4b16` (copie figée, `--campaign solo --bridge on --llm fake --wait-idle 3600`) : code 1, `RST-RESULT ok=false total=281 pass=268 fail=3 error=0 skip=10` (`tools/autoclient/runs/20261115-101858-a55f4c478725`), suites `ca.notebook` et toutes les suites du carnet vertes, aucune erreur Lua au démarrage des trois mods ; échecs étrangers au renommage : `rs.personas.update` et `rs.voicedarlene` (suites E20, corrigées par la session E20), `lk.expedition` (fenêtre condamnée, LK05-T23, journal ajouté en `a4a51a6` ; seule, la suite passe : code 0, `RST-RESULT ok=true total=1 pass=1`, `tools/autoclient/runs/20261115-105732-507fa93dfc5b`)
  - Reste : aucun

- [x] **E21-T02** — Living Knox sans nom de RadioSurvivor dans ses journaux et ses dossiers
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E21-T01
  - Fichiers : `LK_Conversations.lua`, `LK_Incidents.lua`, `LK_Initiatives.lua`, bancs qui lisent ces journaux
  - Faire : journaux `[LK_Conversations]`, `[LK_Incidents]`, `[LK_Initiatives]` ; commentaires qui décrivent un lien vers RadioSurvivor réécrits ou retirés à mesure des tâches suivantes.
  - Accepté si : aucun `[RS_` dans `batman_LivingKnox`.
  - Tests : bancs LK concernés.
  - Preuve : commit `e3b2914` : journaux `[LK_Conversations]`, `[LK_Incidents]`, `[LK_Initiatives]` ; aucun `[RS_` dans le code de `batman_LivingKnox` hors l'adaptateur que retire E21-T05 ; `run_all.py --only conversations --only initiatives --only incidents --only lk_speech --only luacheck-contents` : `Summary: 5 passed, 0 failed`
  - Reste : commentaires qui décrivent RadioSurvivor : réécrits par E21-T05

- [ ] **E21-T03** — Carnet client et interfaces dans batman_CoreAI
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : E21-T01
  - Fichiers : `RS_NPCProvider.lua` → `CA_NPCProvider.lua` ; `RS_Notebook.lua`, `RS_MissionViews.lua`, `MissionViews/`, `RS_MapActions.lua`, `RS_DeadDropLines.lua` et leurs traductions → `batman_CoreAI` ; parties propres aux voix inscrites depuis RadioSurvivor par registre
  - Faire : déplacer le carnet côté client et l'interface des fournisseurs dans le commun (D04) ; ce qui ne concerne que les voix (pages radio, troc) s'inscrit au carnet depuis RadioSurvivor.
  - Accepté si : le carnet s'ouvre et affiche contacts et missions avec RadioSurvivor seul, Living Knox seul, et les deux ; aucun fichier du commun ne nomme RadioSurvivor ni Living Knox.
  - Tests : bancs du carnet ; suites `rc.notebook`, `rs.*` du carnet.
  - Preuve : commits `c4a29e1` (CA_NPCProvider, CA_MissionViews et registre des donneurs, CA_MapZones) et `ca4c530` (module réseau `CoreAI`, registre des commandes, CA_NotebookClient, onglets Contacts, Missions, Réputation dans le commun, onglet Radio dans RS_NotebookRadio) ; bancs nouveaux `test_core_npc_provider`, `test_core_mission_views`, `test_core_map_zones`, `test_core_notebook` (CoreClientRoundTripTests), `test_protocol` (scenario_notebook_module), rouges avant, verts après ; `run_all.py --keep-going` : `Summary: 188 passed, 0 failed, 0 skipped` ; luacheck Contents 5 avertissements (référence 8), dev 0 ; `check_case` PASS
  - Reste : campagne solo ; `CA_NotebookJournal` provisoire jusqu'à la tranche 11 (E21-T04) ; libellé de la touche CoreAISelect à reformuler quand Living Knox s'en sert (E21-T05)

- [ ] **E21-T04** — Carnet serveur dans batman_CoreAI
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E21-T03
  - Fichiers : `RS_Carnet_Server.lua` (partie commune → `CA_NotebookServer.lua`), `RS_Config.lua` (module réseau du carnet), `RS_Client.lua`
  - Faire : le serveur du carnet devient commun (identité, contacts, missions, journal, historique, parole par les fournisseurs) ; ce qui ne sert qu'aux voix (gabarits enregistrés, personas, troc, réputation des voix) reste dans RadioSurvivor et s'inscrit au carnet.
  - Accepté si : le carnet fonctionne avec chaque mod seul et avec les deux, en solo et en MP ; aucun module commun ne charge `RadioSurvivor/` ni `LivingKnox/`.
  - Tests : bancs du carnet et du protocole ; campagnes solo et MP.
  - Preuve : —
  - Reste : —

- [ ] **E21-T05** — Living Knox fournisseur du carnet commun
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E21-T04
  - Fichiers : `shared/RadioSurvivor/RS_LivingKnox.lua` → `LK_NotebookProvider.lua` ; `LK_Core.lua` (`radioSurvivorActive` retiré) ; `LK_TalkView.lua`, `LK_TalkAlone.lua`, `LK_Contacts.lua`, `LK_Admin.lua`
  - Faire : l'adaptateur s'inscrit toujours à `CA_NPCProvider`, que RadioSurvivor soit là ou non ; la parole de proximité passe par un seul chemin ; `LK_Admin` lit les noms par le registre commun.
  - Accepté si : aucun `RadioSurvivor` ni `RS_` dans le code de `batman_LivingKnox`.
  - Tests : bancs LK de la parole, du carnet et des contacts ; suites `lk.*` concernées.
  - Preuve : —
  - Reste : —

- [ ] **E21-T06** — RadioSurvivor sans appel à Living Knox
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E21-T04
  - Fichiers : `RS_Facts.lua`, `RS_Relations.lua`, partie RadioSurvivor du carnet ; `CA_MissionClear.lua` ; registres ou événements neutres du commun
  - Faire : faits de groupe, accords, relations, hostilité et attribution des morts lus par des registres ou événements neutres de `batman_CoreAI` que Living Knox alimente (D05) ; tout comportement impossible à neutraliser est nommé ici et signalé.
  - Accepté si : aucun `LivingKnox` ni `LK_` dans le code de `batman_RadioSurvivor` et de `batman_CoreAI`.
  - Tests : bancs des faits, des relations et des accords ; suites `rs.*` concernées.
  - Preuve : —
  - Reste : —

- [ ] **E21-T07** — Trois mods de test et campagnes séparées
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E21-T05, E21-T06
  - Fichiers : `dev/batman_CoreAITests` (outil `RST`, aides communes, suites `rc.*`), `dev/batman_LivingKnoxTests` (suites `lk.*`), `dev/batman_RadioSurvivorTests` (suites `rs.*`) ; `autotest.json` ; `tools/autoclient/autoclient.py` ; `RST_Campaign.lua`
  - Faire : répartir les suites et aides selon D06 ; `solo-lk` sans RadioSurvivor ni Belt Walkie-Talkie ; `solo-rs` sans Living Knox ; `solo` avec tout.
  - Accepté si : les trois montages démarrent et jouent leurs suites.
  - Tests : `test_autoclient.py`, `test_rst.py` ; campagnes `solo-lk`, `solo-rs`, `solo`.
  - Preuve : —
  - Reste : —

- [ ] **E21-T08** — Bancs de Living Knox sans RadioSurvivor
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E21-T07
  - Fichiers : les 44 bancs `tests/test_lk_*.py` du relevé
  - Faire : chaque banc LK ne charge que CoreAI et Living Knox ; un banc qui vérifiait les deux mods ensemble passe dans les bancs du commun avec des doublures neutres, ou il est supprimé avec le code qu'il vérifiait.
  - Accepté si : aucun banc `test_lk_*.py` ne nomme `batman_RadioSurvivor` ni un fichier `RS_`.
  - Tests : `tests/run_all.py --keep-going`.
  - Preuve : —
  - Reste : —

- [ ] **E21-T09** — Les trois montages en jeu, solo et MP
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E21-T08
  - Fichiers : —
  - Faire : campagnes `solo-lk`, `solo-rs`, `solo` (pont avec faux modèle) et MP (serveur dédié et deux clients), une à la fois.
  - Accepté si : aucune suite en échec liée à la séparation.
  - Tests : `autoclient.py`, `--wait-idle 3600`.
  - Preuve : —
  - Reste : —

- [ ] **E21-T10** — Documentation, README et descriptions Workshop
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E21-T09
  - Fichiers : `README*`, `README.steam*`, `workshop.txt`, `docs/` (architecture, spécifications, wiki), page des fonctionnalités
  - Faire : décrire les trois mods (`batman_CoreAI` : ce qu'il apporte, activé seul), mettre à jour l'architecture et les specs ; aucune publication.
  - Accepté si : contrôles des descriptions verts ; aucune mention de l'ancien nom hors historique.
  - Tests : contrôles des descriptions du dépôt ; `features_status.py --check`.
  - Preuve : —
  - Reste : —
