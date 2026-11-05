# E18 — Séparer RadioSurvivor et Living Knox autour d'un mod commun

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 2 / 16 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E18-T01 | Mod commun `batman_RadioSurvivorCore` : dossier et métadonnées | `testé solo` | solo | — |
| ☑ | E18-T02 | Outils partagés déplacés dans le commun | `testé hors jeu` | hors jeu | E18-T01 |
| ☐ | E18-T03 | Identité des personnages dans le commun | `à faire` | MP | E18-T02 |
| ☐ | E18-T04 | Lien avec le pont dans le commun | `à faire` | MP | E18-T02 |
| ☐ | E18-T05 | Moteur de missions dans le commun, donneurs voix et PNJ | `à faire` | MP | E18-T03, E18-T04 |
| ☐ | E18-T06 | Journal commun des missions | `à faire` | MP | E18-T05 |
| ☐ | E18-T07 | Mod `batman_LivingKnox` : code déplacé | `à faire` | solo | E18-T02 |
| ☐ | E18-T08 | Bases connues et sites sans RadioSurvivor | `à faire` | solo | E18-T07 |
| ☐ | E18-T09 | Adaptateur fournisseur porté par Living Knox | `à faire` | MP | E18-T07 |
| ☐ | E18-T10 | Dossier de données de Living Knox et reprise des parties existantes | `à faire` | MP | E18-T07 |
| ☐ | E18-T11 | Parole des PNJ émise par Living Knox, enrichie par RadioSurvivor | `à faire` | MP | E18-T04, E18-T09 |
| ☐ | E18-T12 | Pont : un dossier d'échange pour les deux mods | `à faire` | MP | E18-T04, E18-T11 |
| ☐ | E18-T13 | Traductions et options sandbox des trois mods | `à faire` | hors jeu | E18-T06, E18-T07 |
| ☐ | E18-T14 | Outillage des tests pour trois montages | `à faire` | hors jeu | E18-T07 |
| ☐ | E18-T15 | Validation des trois montages | `à faire` | MP | E18-T05, E18-T06, E18-T08, E18-T10, E18-T12, E18-T13, E18-T14 |
| ☐ | E18-T16 | Documentation et page Workshop des trois mods | `à faire` | hors jeu | E18-T15 |

<!-- fin du tableau de bord -->

**Mod (après la séparation).** les trois mods de l'article.

**Objectif.** Livrer, dans un seul article Workshop, deux mods qui fonctionnent chacun sans l'autre et mieux
ensemble — `batman_RadioSurvivor` (radio, voix, carnet, factions, troc des voix) et `batman_LivingKnox` (moteur de
PNJ : corps, gestes, groupes, routines, combat, parole de proximité) — bâtis sur un **mod commun** qui porte le code
partagé : moteur de missions, lien avec le pont LLM, identité des personnages, outils. Les voix radio comme les PNJ
donnent des missions ; le pont Python LLM est la base de leur intelligence, avec l'un, l'autre ou les deux mods.

**ADR.** [Trois mods dans un article](../../architecture/decisions/adr-separation-mods.md) (accepté le 2026-11-05) ; ce plan en est l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** `E17` (interface `RS_NPCProvider`, neutre vis-à-vis du moteur) ; `LK12` (API publique de Living Knox) ;
`E11` (missions générées).

**Sources.** Relevé des liens entre les deux moteurs du 2026-11-05 (résumé ci-dessous) ; `docs/architecture/README.md` ;
`docs/specifications-techniques/protocole-carnet-v2.md` ; `docs/specifications-techniques/api-living-knox.md` ;
`shared/RadioSurvivor/RS_NPCProvider.lua` (contrat).

## Décisions

- 2026-11-05 — **Séparation** (utilisateur) : RadioSurvivor et Living Knox deviennent deux mods qui fonctionnent chacun
  sans l'autre ; revient sur la fusion du 2026-10-08 (`E17`, `docs/architecture/decisions/README.md`).
- 2026-11-05 — **Forme** (utilisateur) : **un seul article Workshop** ; même projet `Workshop\RadioSurvivor` et même
  dépôt, dossiers frères sous `Contents/mods`.
- 2026-11-05 — **Pont** (utilisateur) : le pont Python LLM sert les deux mods ensemble ou l'un des deux seul ; c'est la
  base de l'intelligence des voix et des PNJ. Avec Living Knox seul, un joueur parle aux PNJ et reçoit une réponse du
  LLM : la parole des PNJ (`npc_talk`, `npc_converse`, `npc_initiative`, `npc_enrich`) est émise par Living Knox ;
  RadioSurvivor, s'il est présent, y ajoute son contexte (relations, réputation, accords) et applique ses actions.
- 2026-11-05 — **Mutualisation** (utilisateur) : le code commun aux deux mods n'existe qu'une fois, dans un **mod
  commun** que RadioSurvivor et Living Knox exigent (`require=`) ; le joueur coche seulement RadioSurvivor et/ou
  Living Knox, le jeu active le mod commun (`require` active en silence un mod absent de `Mods=`, base de
  connaissances `mod-loading.md`). **Les deux donnent des missions** : voix radio (RadioSurvivor) et PNJ (Living
  Knox) sont des donneurs du même moteur de missions.
- 2026-11-05 — **Journal des missions** (utilisateur) : le mod commun apporte un petit journal des missions (offres,
  missions en cours, compte rendu) ouvert par un bouton ; avec RadioSurvivor, le carnet l'intègre dans son onglet
  missions : une seule liste pour les missions des voix et des PNJ.
- 2026-11-05 — **Historique des échanges** (utilisateur, `E18-T11`) : gardé par le **mod commun**, toujours présent :
  Living Knox y écrit les échanges avec ses PNJ, le carnet de RadioSurvivor le lit pour l'afficher ; il sert de mémoire
  au LLM pour chaque nouvelle phrase. Confirmé par défaut : les échanges avec les voix radio y sont gardés aussi.
- 2026-11-05 — Confirmé par défaut (valeurs techniques, modifiables) :
  - identifiants `batman_RadioSurvivorCore` (mod commun, nom affiché « Radio Survivor Core », code sous
    `media/lua/*/RadioSurvivorCore/`, fichiers `RC_`) et `batman_LivingKnox` (nom affiché « Living Knox ») ;
    `batman_RadioSurvivor` garde son identifiant et ses dossiers de données ;
  - le mod commun n'a aucune fonction de jeu propre hors du journal des missions ; il n'exige aucun autre mod ;
    `batman_BeltRadio` et `batman_SignalSmoke` restent exigés par RadioSurvivor seul (Signal Smoke aussi par le
    gabarit « signaler » s'il passe dans le commun : à vérifier dans `E18-T05`) ;
  - dossier d'échange du pont unique, sous `Zomboid\Lua\batman_RadioSurvivorCore\`, partagé par les deux mods ; le pont
    lit encore l'ancien dossier `batman_RadioSurvivor\` s'il ne trouve pas le nouveau (transition) ;
  - données de Living Knox sous `Zomboid\Lua\batman_LivingKnox\`, missions sous le dossier du mod commun ; reprise
    une seule fois des données d'une partie d'avant la séparation (aucune partie existante perdue) ;
  - un seul mod de test de développement, trois montages (RadioSurvivor seul, Living Knox seul, les deux), campagnes
    solo et MP dans chacun.

## Relevé des liens (2026-11-05, lecture du code, confirmé statiquement)

- RadioSurvivor → Living Knox : un seul lien dur, l'adaptateur `shared/RadioSurvivor/RS_LivingKnox.lua` (requiert
  `LK_Core` et `LK_Config`) ; tout le reste passe par `RS_NPCProvider` ou par des gardes `nil`.
- Living Knox → RadioSurvivor : `LK_ZombieGuard` (`RS_RateLimit`), `LK_Store` (`RS_Codec`, format des registres),
  `LK_Server` (`RS_WorldStart`), `LK_Sites` et `LK_Simulation` (`RS_Rescue`, qui tire `RS_State` et `RS_Factions`),
  `LK_Trade` et `LK_TradeView` (`RS_TradeValues`), `LK_SpeechView` (`RS_TextCut`) ; clé de joueur des attitudes lue
  dans le carnet (`LK_Hostility`, `RS_CarnetServer`).
- Ressources communes : `sandbox-options.txt` (pages `RadioSurvivor` et `LivingKnox`), `IG_UI.json` et `Sandbox.json`
  (préfixes déjà disjoints : `IGUI_LK_`, `Sandbox_LivingKnox_` contre `IGUI_RS_`, `IGUI_RadioSurvivor_`,
  `Sandbox_RadioSurvivor_`) ; AnimSets `lkactor_*` (Living Knox seul).
- Pont : toutes les demandes LLM sont émises aujourd'hui par RadioSurvivor ; dossier d'échange, signal de vie et
  personnages fixés sur `batman_RadioSurvivor`.
- Missions : moteur, gabarits et récompenses dans RadioSurvivor (`RS_Missions`, `RS_Mission*`, `RS_NPCRewards`,
  `RS_GameClock`), état dans l'état privé du carnet (`RS_State`).

## Hors périmètre

Deuxième article Workshop, dépôt séparé, nouvelles règles de jeu des missions ou des PNJ.

## Tâches

- [x] **E18-T01** — Mod commun `batman_RadioSurvivorCore` : dossier et métadonnées
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `Contents/mods/batman_RadioSurvivorCore/` (`common/`, `42.21/mod.info`) ; `mod.info` de `batman_RadioSurvivor` (`require=` du commun)
  - Faire : créer le mod commun vide de jeu ; RadioSurvivor l'exige ; le jeu l'active quand seul RadioSurvivor est coché.
  - Accepté si : RadioSurvivor seul coché démarre avec le commun actif, sans erreur Lua.
  - Tests : `run_all.py` ; démarrage solo.
  - Preuve : `Contents/mods/batman_RadioSurvivorCore` (`common/.keep`, `42.21/mod.info` id `batman_RadioSurvivorCore` sans `require=`, module `RadioSurvivorCore/RC_Core.lua`) ; `batman_RadioSurvivor` : `require=\batman_RadioSurvivorCore,\batman_BeltRadio,\batman_SignalSmoke` ; mod commun ajouté avant RadioSurvivor dans `tools/autoclient/autoclient.py`, `autotest.json`, `tests/run_dedicated_smoke.ps1` ; banc `python tests/test_core_mod.py` : « Ran 4 tests … OK » (rouge d'abord : 2 FAIL, 2 ERROR) ; `python tests/test_autoclient.py` : « Ran 91 tests … OK » ; `python tests/run_all.py --keep-going` : 146 PASS, 1 FAIL (autoclient, ligne `require=` attendue, corrigée puis banc vert) ; passage solo du 2026-11-05 (`autoclient.py --suite rs.env,rst`, code 0) : « RST-RESULT ok=true total=13 pass=13 fail=0 », journal « loading batman_RadioSurvivorCore », mods actifs `…;batman_RadioSurvivorCore;batman_RadioSurvivor;…`, aucune erreur Lua de nos mods hors des échecs volontaires des auto-tests `rst` (`tools/autoclient/runs/20261105-161109-435c6ef1b6c0`)
  - Reste : RadioSurvivor coché seul : activation automatique du commun par `require=` non rejouée hors lanceur (le lanceur liste les mods) ; à voir avec E18-T15

- [x] **E18-T02** — Outils partagés déplacés dans le commun
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E18-T01
  - Fichiers : `RS_Codec`, `RS_RateLimit`, `RS_TextCut`, `RS_TradeValues`, `RS_WorldStart`, `RS_GameClock` → `RC_*` du commun ; leurs appelants dans RadioSurvivor et Living Knox
  - Faire : une seule copie de chaque outil, dans le commun ; plus aucun `require "RadioSurvivor/..."` dans Living Knox pour ces outils ; format des registres (RSV2) inchangé.
  - Accepté si : recherche des anciens noms vide ; anciens registres et anciens états relus octet pour octet.
  - Tests : bancs `test_carnet.py`, `test_kahlua.py`, `test_lk_*` ; banc de relecture d'un registre écrit par l'ancien code.
  - Preuve : six modules `RC_Codec`, `RC_RateLimit`, `RC_TextCut`, `RC_TradeValues`, `RC_WorldStart` (passé de `server/` à `shared/`), `RC_GameClock` sous `batman_RadioSurvivorCore/42.21/media/lua/shared/RadioSurvivorCore/` (déplacés par `git mv`, code identique hors noms, commentaires en anglais ASCII) ; appelants de RadioSurvivor, de Living Knox (`LK_Store`, `LK_Server`, `LK_ZombieGuard`, `LK_Trade`, `LK_TradeView`, `LK_SpeechView`), des suites en jeu (suite `RC_Codec`) et des bancs mis à jour ; banc `python tests/test_core_tools.py` (rouge d'abord : 3 FAIL, 4 ERROR ; puis « Ran 7 tests … OK ») : une seule copie de chaque outil, recherche des anciens noms vide dans `Contents`, `dev`, `tests`, `tools`, `bridge`, aucun `require "RadioSurvivor/..."` de ces outils dans Living Knox, fichiers `tests/fixtures/e18-t02` (état RS `RSSTATE2` et registre `LKREG1` écrits par l'ancien codec) relus par `RC_Codec`, `RS_State._read` et `LK_Store.readSlotFile` puis réécrits octet pour octet ; `python tests/run_all.py --keep-going` : « 148 passed, 0 failed » (`carnet` 94 tests OK, `kahlua` 39 OK dans la VM réelle, 79 bancs `lk_*` verts, `check_case` avec le mod commun en dépendance), luacheck `Contents` 15 avertissements (référence 15), `dev` 0
  - Reste : —

- [ ] **E18-T03** — Identité des personnages dans le commun
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T02
  - Fichiers : identité du personnage aujourd'hui dans le carnet (`RS_Carnet_Server`, `RS_Client`, ModData `RS_CarnetCharacter`) → commun ; `LK_Hostility`, `LK_Alert`, `LK_Decisions`
  - Faire : un personnage a une identité unique, écrite par le serveur, retirée à la mort (règles de `E00-T01`/`E00-T02`), lue par les deux mods ; Living Knox y clé ses attitudes et ses faits ; identités et attitudes déjà enregistrées reprises.
  - Accepté si : Living Knox seul garde ses relations avec chaque joueur après reconnexion et redémarrage ; RadioSurvivor seul garde ses identités ; ensemble, mêmes identités qu'avant.
  - Tests : bancs de l'identité et `test_lk_hostility*` ; suites rs.identity, rs.death dans les trois montages, phases reconnexion et redémarrage.
  - Preuve : —
  - Reste : —

- [ ] **E18-T04** — Lien avec le pont dans le commun
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T02
  - Fichiers : `RS_Transport`, `RS_BridgeAlive`, constantes du pont (`RadioSurvivor_Const`), quotas (`MAX_PENDING`, `MAX_PER_HOUR`, budget d'enrichissement) → commun ; `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : file unique des demandes LLM et des réponses, quotas communs, signal de vie, dossier d'échange unique ; chaque mod enregistre ses sortes de demandes et le traitement de leurs réponses ; secours sans pont conservé.
  - Accepté si : une demande de voix et une demande de PNJ passent par la même file, avec les mêmes quotas ; pont arrêté : secours de chaque mod comme aujourd'hui.
  - Tests : `test_protocol.py`, bancs du transport ; suites du pont (`BRIDGE_SUITES`).
  - Preuve : —
  - Reste : —

- [ ] **E18-T05** — Moteur de missions dans le commun, donneurs voix et PNJ
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T03, E18-T04
  - Fichiers : `RS_Missions`, gabarits `RS_Mission*`, `RS_NPCRewards`, récompenses des voix, délais en temps de jeu → commun ; donneurs `RS_MissionVoice` (RadioSurvivor) et offres des PNJ (Living Knox, `LK12-T03`)
  - Faire : un moteur de missions, des gabarits et des récompenses communs ; un donneur s'enregistre (voix radio, PNJ) avec ce qu'il peut offrir ; état des missions dans un état privé du commun, missions en cours d'une partie existante reprises ; dépendance éventuelle d'un gabarit à un autre mod (Signal Smoke pour « signaler ») tranchée ici.
  - Accepté si : Living Knox seul : un PNJ propose une mission, acceptée par la parole, rendue et récompensée ; RadioSurvivor seul : missions des voix comme aujourd'hui ; ensemble : mêmes missions qu'avant la séparation.
  - Tests : bancs des missions (`test_mission_*`, `test_e11*`) ; suites rs.mission*, rs.missions.solo dans les trois montages.
  - Preuve : —
  - Reste : —

- [ ] **E18-T06** — Journal commun des missions
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T05
  - Fichiers : fenêtre du journal dans le commun (client) ; onglet missions du carnet (`RS_Notebook`) ; traductions `IGUI_RC_`
  - Faire : bouton et fenêtre qui listent offres, missions en cours et à rendre (même ordre et mêmes états que le carnet) ; avec RadioSurvivor, le carnet affiche la même liste dans son onglet missions et le bouton du journal s'efface ; manette et toutes les langues livrées.
  - Accepté si : Living Knox seul : la mission d'un PNJ apparaît dans le journal, puis disparaît une fois rendue ; ensemble : missions des voix et des PNJ dans une seule liste du carnet.
  - Tests : banc de l'interface (doublures ISUI) ; suite en jeu du journal dans les trois montages.
  - Preuve : —
  - Reste : —

- [ ] **E18-T07** — Mod `batman_LivingKnox` : code déplacé
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E18-T02
  - Fichiers : `Contents/mods/batman_LivingKnox/` (`common/`, `42.21/mod.info`, `require=` du commun) ; code `media/lua/*/LivingKnox/`, AnimSets `lkactor_*`, page `LivingKnox` des options, clés `IGUI_LK_` et `Sandbox_LivingKnox_` déplacés ; `tools/gen_animsets.py`
  - Faire : déplacer le moteur dans son mod ; `incompatible=` Bandits! et Project A-Life repris par Living Knox ; plus aucun fichier du moteur dans `batman_RadioSurvivor`.
  - Accepté si : Living Knox seul coché démarre (commun actif) sans erreur Lua ; les trois mods ensemble se chargent comme aujourd'hui.
  - Tests : `run_all.py` (bancs adaptés aux trois dossiers) ; démarrage solo de chaque montage.
  - Preuve : —
  - Reste : —

- [ ] **E18-T08** — Bases connues et sites sans RadioSurvivor
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E18-T07
  - Fichiers : `LK_Sites`, `LK_Simulation` (`knownBases`), `RS_Rescue`
  - Faire : Living Knox ne requiert plus `RS_Rescue` ; la géométrie des bases des joueurs passe dans le commun (servie aux missions et aux PNJ) ou arrive par un crochet optionnel ; seul, Living Knox repère les bases par ses propres moyens ou s'en passe.
  - Accepté si : sites et raids tournent sans RadioSurvivor ; avec lui, mêmes bases qu'aujourd'hui.
  - Tests : bancs `test_lk_sites*`, `test_lk_raids` ; suites lk.sites et lk.raids dans les trois montages.
  - Preuve : —
  - Reste : —

- [ ] **E18-T09** — Adaptateur fournisseur porté par Living Knox
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T07
  - Fichiers : `RS_LivingKnox.lua` (déplacé dans `batman_LivingKnox`, chargé seulement si RadioSurvivor est actif) ; `RS_NPCProvider.lua` (reste dans RadioSurvivor)
  - Faire : le fournisseur s'enregistre auprès de `RS_NPCProvider` quand les deux mods sont actifs ; sans Living Knox, RadioSurvivor tourne avec « aucun moteur de PNJ » (cas déjà prévu par E17).
  - Accepté si : RadioSurvivor seul démarre sans erreur et sans fiche de PNJ ; ensemble, comportement d'aujourd'hui.
  - Tests : bancs `test_carnet.py`, `test_lk_api*` ; campagnes des trois montages.
  - Preuve : —
  - Reste : —

- [ ] **E18-T10** — Dossier de données de Living Knox et reprise des parties existantes
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T07
  - Fichiers : `LK_Store` (`DIR`), `LK_Groups`, `LK_Hostility`
  - Faire : registres sous `Zomboid\Lua\batman_LivingKnox\` ; au premier lancement, reprise une seule fois de `batman_RadioSurvivor\livingknox\` (copie, ancien dossier laissé en place, ligne de journal en anglais).
  - Accepté si : une partie créée avant la séparation garde ses groupes, foyers et attitudes ; la reprise ne se refait pas.
  - Tests : banc de reprise ; phase `after-restart` sur une partie d'avant la séparation.
  - Preuve : —
  - Reste : —

- [ ] **E18-T11** — Parole des PNJ émise par Living Knox, enrichie par RadioSurvivor
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T04, E18-T09
  - Fichiers : historique des échanges (aujourd'hui `contacts[...].history` de l'état du carnet) → commun ; parole de proximité (`RS_Carnet_Server.lua` talk, `RS_Conversations`, `RS_Initiatives`, `RS_Incidents`) → Living Knox (`LK_Talk`) sur le lien commun ; `bridge/npc_protocol.py` ; `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : Living Knox émet `npc_talk`, `npc_converse`, `npc_initiative` et `npc_enrich` par le lien commun ; offres et acceptations de missions des PNJ par le moteur commun ; RadioSurvivor ajoute au contexte ses éléments (relation, réputation, accords) et traite ses actions de la réponse par des crochets de l'API ; le carnet reste un affichage de RadioSurvivor.
  - Faire aussi : historique des échanges (PNJ et voix radio) dans le mod commun, par personnage et par interlocuteur, borné comme aujourd'hui (`MAX_HISTORY`) ; historiques d'une partie existante repris depuis l'état du carnet ; le carnet le lit pour l'affichage (décision du 2026-11-05).
  - Accepté si : Living Knox seul : une phrase dite près d'un PNJ reçoit une réponse du LLM en bulle, le PNJ se souvient des échanges précédents, et un PNJ propose une mission ; ensemble : mêmes offres, acceptations et relations qu'aujourd'hui (suites rs.npctalk, rs.conversations, rs.initiatives).
  - Tests : `test_protocol.py`, bancs de la parole ; suites de parole dans les trois montages.
  - Preuve : —
  - Reste : —

- [ ] **E18-T12** — Pont : un dossier d'échange pour les deux mods
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T04, E18-T11
  - Fichiers : `bridge/radio_bridge.py`, `bridge/npc_protocol.py`, `bridge/README*`
  - Faire : dossier d'échange par défaut du commun, ancien dossier lu en transition ; personnages des voix lus seulement quand RadioSurvivor les installe ; limites de texte de la parole lues dans un seul endroit ; aucune demande ni dossier créé pour un mod absent.
  - Accepté si : le même pont, sans option, sert RadioSurvivor seul, Living Knox seul et les deux.
  - Tests : bancs du pont (`tests/test_bridge*`, `test_protocol.py`) dans les trois montages ; campagnes avec `--bridge on`.
  - Preuve : —
  - Reste : —

- [ ] **E18-T13** — Traductions et options sandbox des trois mods
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E18-T06, E18-T07
  - Fichiers : `media/lua/shared/Translate/*/` et `media/sandbox-options.txt` des trois mods
  - Faire : chaque mod porte ses clés et sa page d'options (missions et pont dans le commun) ; aucune clé ni option perdue, dans toutes les langues livrées ; réglages d'une partie existante relus.
  - Accepté si : union des clés égale aux clés d'avant plus celles du journal ; aucune clé d'un mod dans un autre.
  - Tests : banc de comparaison des clés ; `check_case`.
  - Preuve : —
  - Reste : —

- [ ] **E18-T14** — Outillage des tests pour trois montages
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E18-T07
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/mod.info` (exige le commun seul, détecte les autres) ; `tests/harness.py`, `tests/run_all.py` ; `tools/autoclient/autoclient.py` (`--mods rs|lk|both`, dossiers de résultats et d'échange) ; `tests/run_dedicated_smoke.ps1` ; listes des campagnes
  - Faire : chaque suite déclare les mods qu'elle exige (SKIP sinon) ; suites mixtes (carnet et PNJ) seulement avec les deux ; campagnes `solo` et `mp` lançables dans chaque montage.
  - Accepté si : `run_all.py` vert ; un passage de chaque montage démarre et rend un rapport.
  - Tests : bancs `test_autoclient.py`, `test_rst.py`.
  - Preuve : —
  - Reste : —

- [ ] **E18-T15** — Validation des trois montages
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T05, E18-T06, E18-T08, E18-T10, E18-T12, E18-T13, E18-T14
  - Fichiers : ce fichier
  - Faire : campagnes solo et MP automatiques avec RadioSurvivor seul, Living Knox seul et les deux, pont avec faux modèle ; reconnexion et redémarrage pour les deux ensemble ; une partie d'avant la séparation rechargée.
  - Accepté si : six campagnes vertes (hors instabilités suivies par leur propre tâche, citées dans la preuve).
  - Tests : campagnes automatiques.
  - Preuve : —
  - Reste : —

- [ ] **E18-T16** — Documentation et page Workshop des trois mods
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E18-T15
  - Fichiers : `README.md`, `README_fr.md`, `README.steam*`, `docs/developpement.md`, `docs/architecture/README.md`, `docs/architecture/decisions/README.md`, wiki (`docs/wiki/*`), `docs/annexes/plans/README.md`
  - Faire : expliquer au joueur quoi cocher et ce que chaque mod apporte, le mod commun activé seul, le pont ; architecture et décisions à jour ; page Steam qui présente les mods de l'article.
  - Accepté si : aucune page ne décrit encore un mod unique ; descriptions Steam dans toutes les langues sous la limite de 8 000 octets.
  - Tests : `plan.py check` ; contrôle de taille des descriptions.
  - Preuve : —
  - Reste : —
