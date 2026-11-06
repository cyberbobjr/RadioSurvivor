# E18 — Séparer RadioSurvivor et Living Knox autour d'un mod commun

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 4 / 22 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E18-T01 | Mod commun `batman_RadioSurvivorCore` : dossier et métadonnées | `testé solo` | solo | — |
| ☑ | E18-T02 | Outils partagés déplacés dans le commun | `testé hors jeu` | hors jeu | E18-T01 |
| ☐ | E18-T03 | Identité des personnages dans le commun | `testé hors jeu` | MP | E18-T02 |
| ☐ | E18-T04 | Lien avec le pont dans le commun | `testé hors jeu` | MP | E18-T02 |
| ☐ | E18-T05 | Moteur de missions dans le commun, donneurs voix et PNJ | `testé hors jeu` | MP | E18-T03, E18-T04 |
| ☐ | E18-T06 | Journal commun des missions | `testé hors jeu` | MP | E18-T05 |
| ☐ | E18-T07 | Mod `batman_LivingKnox` : code déplacé | `testé hors jeu` | solo | E18-T02 |
| ☐ | E18-T08 | Bases connues et sites sans RadioSurvivor | `testé hors jeu` | solo | E18-T07 |
| ☐ | E18-T09 | Adaptateur fournisseur porté par Living Knox | `testé hors jeu` | MP | E18-T07 |
| ☐ | E18-T10 | Dossier de données de Living Knox et reprise des parties existantes | `testé hors jeu` | MP | E18-T07 |
| ☐ | E18-T11 | Historique des échanges avec les PNJ dans le commun | `testé hors jeu` | MP | E18-T04, E18-T09 |
| ☐ | E18-T12 | Pont : un dossier d'échange pour les deux mods | `à faire` | MP | E18-T04, E18-T17 |
| ☑ | E18-T13 | Traductions et options sandbox des trois mods | `testé hors jeu` | hors jeu | E18-T06, E18-T07 |
| ☑ | E18-T14 | Outillage des tests pour trois montages | `testé hors jeu` | hors jeu | E18-T07 |
| ☐ | E18-T15 | Validation des trois montages | `à faire` | MP | E18-T05, E18-T06, E18-T08, E18-T10, E18-T12, E18-T13, E18-T14, E18-T18, E18-T19 |
| ☐ | E18-T16 | Documentation et page Workshop des trois mods | `à faire` | hors jeu | E18-T15 |
| ☐ | E18-T17 | File des demandes de parole des PNJ portée par Living Knox | `à faire` | MP | E18-T11, E18-T20, E18-T21, E18-T22 |
| ☐ | E18-T18 | Parole de proximité avec Living Knox seul | `à faire` | MP | E18-T17 |
| ☐ | E18-T19 | Historique des voix radio dans le commun | `à faire` | MP | E18-T11 |
| ☐ | E18-T20 | Accords dans Living Knox, identifiants d'équipe dans le commun | `à faire` | MP | E18-T09 |
| ☐ | E18-T21 | Relation personnelle des PNJ dans Living Knox | `à faire` | MP | E18-T09 |
| ☐ | E18-T22 | Réputation dans le commun | `à faire` | MP | E18-T05 |

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
- 2026-11-05 — **Quotas du pont** (utilisateur, `E18-T04`) : **une seule file d'échange, plafonds séparés** : le mod commun porte la file des demandes et des réponses (un fichier de demandes, un fichier de réponses, signal de vie), chaque mod compte ses demandes à part comme aujourd'hui (plafond horaire de la radio par l'option sandbox, `MAX_PER_HOUR` et budget d'enrichissement des PNJ, `MAX_PENDING` de chacun) ; aucun changement de jeu.
- 2026-11-05 — **Gabarits des missions** (utilisateur, `E18-T05`) : **tous les gabarits passent dans le mod commun**
  (livrer, repérer, nettoyer, récupérer, rapporter, signaler), avec ce dont ils ont besoin dans le monde (choix des
  lieux loin des bases, caches) ; le mod commun **exige Signal Smoke** (`require=\batman_SignalSmoke`) pour le gabarit
  « signaler », donc Living Knox seul l'exige aussi. Remplace, pour ce point, « le mod commun n'exige aucun autre mod ».
- 2026-11-05 — **API des donneurs** (utilisateur, `E18-T05`) : **inscription et crochets** : chaque mod inscrit sa
  sorte de donneur (`RC_Missions.registerDonor(kind, { find, … })`) ; le moteur garde ses champs (mission en cours,
  compteur, attente avant la prochaine offre) sur la fiche du donneur, tenue par le mod ; fin de mission, réputation,
  tri des offres, oubli d'une mission par les personnages : crochets facultatifs (RadioSurvivor y branche réputation et
  carnet).
- 2026-11-06 — **Origine des échanges** (utilisateur, `E18-T17`) : une voix entendue au talkie-walkie (missions,
  dialogues) a pour origine RadioSurvivor ; un PNJ du monde (voix, comportement, dialogues, missions) a pour origine
  Living Knox. Le mod commun, prérequis obligatoire, ne fait que recevoir, transmettre et renvoyer : chaque réponse
  revient au mod qui a émis la demande, à lui de l'écouter et de la traiter.
- 2026-11-06 — **Règle d'or** (utilisateur) : RadioSurvivor et Living Knox vivent absolument l'un sans l'autre ; le
  contexte d'un échange (relation, réputation, accords) est toujours fourni, par le mod à qui il appartient.
- 2026-11-06 — **Accords** (utilisateur, `E18-T20`) : trêves et alliances entre un groupe de PNJ et une équipe de
  joueurs (`RS_Factions`, incidents `RS_Incidents`, E09) passent dans **Living Knox** ; Living Knox seul les garde.
- 2026-11-06 — **Réputation** (utilisateur, `E18-T22`) : une seule réputation par personnage, tenue par le **mod
  commun** (`RS_Reputation`), nourrie par les missions communes ; chaque mod y signale ses faits (troc triché par
  RadioSurvivor, meurtre d'un PNJ ou d'un donneur par Living Knox) ; voix et PNJ lisent la même.
- 2026-11-06 — Confirmé par défaut : la **relation personnelle d'un PNJ** (`RS_Relations`, écart d'un niveau autour de
  l'attitude de son groupe, E09-T04) passe dans **Living Knox** (`E18-T21`), comme les accords ; les **identifiants
  d'équipe** (`fac-<n>`, mandats de négociation) lus par les accords (Living Knox) et par les équipes de la radio
  (E12) passent dans le **mod commun** (`E18-T20`).
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
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E18-T02
  - Fichiers : identité du personnage aujourd'hui dans le carnet (`RS_Carnet_Server`, `RS_Client`, ModData `RS_CarnetCharacter`) → commun ; `LK_Hostility`, `LK_Alert`, `LK_Decisions`
  - Faire : un personnage a une identité unique, écrite par le serveur, retirée à la mort (règles de `E00-T01`/`E00-T02`), lue par les deux mods ; Living Knox y clé ses attitudes et ses faits ; identités et attitudes déjà enregistrées reprises.
  - Accepté si : Living Knox seul garde ses relations avec chaque joueur après reconnexion et redémarrage ; RadioSurvivor seul garde ses identités ; ensemble, mêmes identités qu'avant.
  - Tests : bancs de l'identité et `test_lk_hostility*` ; suites rs.identity, rs.death dans les trois montages, phases reconnexion et redémarrage.
  - Preuve : module commun `shared/RadioSurvivorCore/RC_Identity.lua` (identité décidée par l'autorité, écrite dans sa copie de la ModData sous la clé gardée `RS_CarnetCharacter`, revendication du client acceptée seulement pour le même compte et le même emplacement et jamais retirée, retrait par `OnCharacterDeath` des seuls `IsoPlayer`, registre privé `Zomboid/Lua/batman_RadioSurvivorCore/identity-*.txt` à deux emplacements par `RC_SlotFile`, commande `hello`/`identity` du module `RadioSurvivorCore`) ; reprise des parties d'avant la séparation : fiches du carnet reprises au démarrage avec leurs retraits (`Identity.adopt`), identité trouvée dans la ModData serveur reprise ; carnet (`RS_Carnet_Server` : `Identity.bind`, fiche du carnet sous le même identifiant) et `LK_Hostility.keyOf` (`Identity.of`, plus de lecture de `RS_CarnetServer`) branchés dessus ; banc `python tests/test_core_identity.py` (rouge d'abord : 11 erreurs, module absent ; puis « Ran 11 tests … OK » : nouveau personnage, reconnexion sans ModData client, revendication d'un autre compte refusée, mort, mort d'un zombie sans effet, redémarrage, monde neuf, reprise d'une partie d'avant la séparation, reprise des fiches du carnet, clé d'attitude de Living Knox sans RadioSurvivor, solo) ; bancs Living Knox passés de `RS_CarnetServer.bound` à `RC_Identity.bound` ; `python tests/run_all.py --keep-going` : « 149 passed, 0 failed », luacheck `Contents` 15 (référence 15), `dev` 0 ; suite en jeu `rs.identity` complétée (« core identity registry agrees with the notebook ») ; passages MP automatiques du 2026-11-05 (serveur dédié + 2 clients, RadioSurvivor et le commun ensemble), code 0 chacun : `--server-suite rs.identity,rs.death --server-tags server,world` « RST-RESULT ok=true total=10 pass=10 fail=0 » (vraie mort du client 2, journal « [RadioSurvivorCore] identity: retired … (death) ») (`tools/autoclient/runs/20261105-185924-mp-74c7f20b9167`) ; `--server-suite rs.identity --phases reconnect,restart` : après reconnexion « total=6 pass=6 », après redémarrage « total=4 pass=4 » (même identité, notes et engagements gardés ; journal « registry read, 2 character(s) ») (`tools/autoclient/runs/20261105-190152-mp-18973cc91492`) ; premier passage `rs.identity` « total=8 pass=8 » (`tools/autoclient/runs/20261105-185516-mp-62cdbf47d0f8`)
  - Reste : cible MP pour les trois montages : Living Knox seul et RadioSurvivor seul n'existent pas encore comme mods séparés (E18-T07, outillage E18-T14) ; Living Knox seul n'est prouvé que par le banc ; à valider en jeu avec E18-T15

- [ ] **E18-T04** — Lien avec le pont dans le commun
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E18-T02
  - Fichiers : `RS_Transport`, `RS_BridgeAlive`, constantes du pont (`RadioSurvivor_Const`), quotas (`MAX_PENDING`, `MAX_PER_HOUR`, budget d'enrichissement) → commun ; `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : file unique des demandes LLM et des réponses, quotas communs, signal de vie, dossier d'échange unique ; chaque mod enregistre ses sortes de demandes et le traitement de leurs réponses ; secours sans pont conservé.
  - Accepté si : une demande de voix et une demande de PNJ passent par la même file, avec les mêmes quotas ; pont arrêté : secours de chaque mod comme aujourd'hui.
  - Tests : `test_protocol.py`, bancs du transport ; suites du pont (`BRIDGE_SUITES`).
  - Preuve : décision du 2026-11-05 (une file, plafonds séparés) ; mod commun : `RC_Transport` (file unique : voies inscrites par chaque mod, `register(nom, { order, format })`, écriture du fichier de demandes, lecture des réponses de toutes les voies `readResponses`) et `RC_Bridge` (fichiers d'échange, battement du pont, `alive`, `waitMs`) ; RadioSurvivor : `RS_Transport.lua` retiré, voies `radio`, `npc`, `acks`, `lastPages` inscrites par `server/RadioSurvivor/RS_BridgeLanes.lua` (même ordre, lignes `clé=valeur` de la radio), `RadioSurvivor_Const` lit fichiers, délais et battement dans le commun ; plafonds inchangés dans chaque mod ; `protocole-carnet-v2.md` (section « File commune ») ; banc `python tests/test_core_bridge.py` (rouge d'abord : 2 FAIL, 6 ERROR ; puis « Ran 8 tests … OK ») : une seule copie, plus aucun `require` de l'ancien transport, fichier de demandes identique octet pour octet à celui de l'ancien code (`tests/fixtures/e18-t04`), voie d'un autre mod dans le même fichier relue par `radio_bridge.parse_requests`, lecteur unique des réponses, battement lu par le commun ; `python tests/run_all.py --keep-going` : « 150 passed, 0 failed », luacheck `Contents` 15 (référence 15), `dev` 0 ; campagne MP automatique du 2026-11-05 (`--mp --clients 2 --server-campaign mp --bridge on --llm fake`, code 1) : « RST-RESULT ok=false total=375 pass=358 fail=1 skip=16 » ; suites du pont vertes (rs.npctalk 4, rs.conversations 4, rs.initiatives 4 dont le pont arrêté, rs.groupradio 5, rs.relation 3, rs.lastpages 5) ; seul échec `lk.barricade` « builder nails planks from the stock » (instabilité antérieure, déjà vue dans les campagnes du 2026-10-14, `tools/autoclient/runs/20261014-140622-mp-770bdff9653f`) (`tools/autoclient/runs/20261105-193132-mp-0c76bf3df7a3`)
  - Reste : dossier d'échange encore `batman_RadioSurvivor/` (passage au commun et transition du pont : E18-T12) ; voies de Living Knox (parole des PNJ) : E18-T11 ; instabilité `lk.barricade` (chantier non fini dans le délai) sans tâche de suivi : à ouvrir ; validation des trois montages : E18-T15

- [ ] **E18-T05** — Moteur de missions dans le commun, donneurs voix et PNJ
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E18-T03, E18-T04
  - Fichiers : `RS_Missions`, gabarits `RS_Mission*`, `RS_NPCRewards`, récompenses des voix, délais en temps de jeu → commun ; donneurs `RS_MissionVoice` (RadioSurvivor) et offres des PNJ (Living Knox, `LK12-T03`)
  - Faire : un moteur de missions, des gabarits et des récompenses communs ; un donneur s'enregistre (voix radio, PNJ) avec ce qu'il peut offrir ; état des missions dans un état privé du commun, missions en cours d'une partie existante reprises ; dépendance éventuelle d'un gabarit à un autre mod (Signal Smoke pour « signaler ») tranchée ici.
  - Accepté si : Living Knox seul : un PNJ propose une mission, acceptée par la parole, rendue et récompensée ; RadioSurvivor seul : missions des voix comme aujourd'hui ; ensemble : mêmes missions qu'avant la séparation.
  - Tests : bancs des missions (`test_mission_*`, `test_e11*`) ; suites rs.mission*, rs.missions.solo dans les trois montages.
  - Preuve : décisions du 2026-11-05 (tous les gabarits au commun, Signal Smoke exigé ; inscription et crochets) ; mod commun : `server/RadioSurvivorCore/RC_Missions` (moteur et gabarit livrer, déplacés par `git mv` ; donneurs `registerDonor(kind, { find, claim, observeDeliver })`, crochets de résultat, d'oubli, de changement, filtre des offres, nom du personnage, liaison des joueurs, fournisseur de PNJ et magasin injectés), gabarits `RC_MissionScout`, `RC_MissionClear`, `RC_MissionRecover`, `RC_MissionRetrieve`, `RC_MissionSignal`, tirage des lieux `RC_Sites` (partie géométrie de `RS_Rescue`, qui la reprend sous ses noms), placement des caches `RC_Caches`, catalogue et délais `shared/RC_MissionConfig` (même table vue par `RS_Config`), état privé `RC_MissionStore` (`Zomboid/Lua/batman_RadioSurvivorCore/missions-*.txt`, en-tête `RCMISSIONS1`, `RC_SlotFile`) ; `mod.info` du commun : `require=atman_SignalSmoke` ; RadioSurvivor : `RS_MissionHooks` (donneurs `npc` et `voice`, réputation et confiance du carnet, oubli des missions, filtre de réputation, liaison du carnet, publication), attaché par `RS_State`, qui écrit le fichier des missions puis le sien (sans les missions, `missionsInCore`) ; action radio `place_cache` dans `RS_CacheAction` ; banc `python tests/test_core_missions.py` (rouge d'abord : 5 FAIL, 2 ERROR ; puis « Ran 11 tests … OK ») : une seule copie, anciens noms absents de `Contents`, `dev`, `tests`, `tools`, `bridge`, aucun `require` de missions de RadioSurvivor dans Living Knox, ASCII du commun, Signal Smoke exigé, état écrit par l'ancien code (`tests/fixtures/e18-t05`) repris octet pour octet puis plus écrit dans le carnet, redémarrage sans nouvelle reprise, monde neuf vide, donneur inscrit sans aucun module de RadioSurvivor (offre, acceptation, compte rendu, attente avant la prochaine offre, crochet de résultat) ; `python tests/run_all.py --keep-going` : « 151 passed, 0 failed » (`carnet` 94, `kahlua` 39 dans la VM réelle, `mission_*`, `lk_*`, `check_case` avec le commun dépendant de Signal Smoke), luacheck `Contents` 15 (référence 15), `dev` 0, `plan.py check` 0 erreur ; campagne MP automatique du 2026-11-06 (commit `1573eda`, serveur dédié + 2 clients, faux modèle, code 1) : RST-RESULT client 1 ok=false total=376 pass=357 fail=3 skip=16, client 2 total=153 pass=152 fail=1 ; toutes les suites des missions et le journal verts (29 PASS : rs.missions*, rs.mission.*, rc.journal), 3 FAIL sans lien avec les missions : lk.barricade (E01-T21) et lk.traversal ×2 (E01-T22) (`tools/autoclient/runs/20261106-002923-mp-2889c9f2103f/server/20261105-233208-server.txt`)
  - Reste : Living Knox seul (un PNJ propose une mission acceptée par la parole) : donneur et tic des missions de Living Knox avec E18-T07 et E18-T11 (initialisation du magasin commun sans RadioSurvivor comprise) ; titres des missions (`IGUI_RS_*`) et page sandbox dans RadioSurvivor jusqu'à E18-T13 ; Living Knox lit encore la géométrie des lieux par `RS_Rescue` (désormais `RC_Sites`) : E18-T08

- [ ] **E18-T06** — Journal commun des missions
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E18-T05
  - Fichiers : fenêtre du journal dans le commun (client) ; onglet missions du carnet (`RS_Notebook`) ; traductions `IGUI_RC_`
  - Faire : bouton et fenêtre qui listent offres, missions en cours et à rendre (même ordre et mêmes états que le carnet) ; avec RadioSurvivor, le carnet affiche la même liste dans son onglet missions et le bouton du journal s'efface ; manette et toutes les langues livrées.
  - Accepté si : Living Knox seul : la mission d'un PNJ apparaît dans le journal, puis disparaît une fois rendue ; ensemble : missions des voix et des PNJ dans une seule liste du carnet.
  - Tests : banc de l'interface (doublures ISUI) ; suite en jeu du journal dans les trois montages.
  - Preuve : mod commun : `shared/RadioSurvivorCore/RC_MissionList` (qui voit une mission, ordre, état affiché, missions ouvertes), `server/RadioSurvivorCore/RC_MissionJournal` (commande `missions` du module `RadioSurvivorCore`, limitée par `RC_RateLimit`, lignes = projections du moteur plus le demandeur `RC_Missions.requester`, personnage par `RC_Missions.binding`, missions connues par le crochet `setKnownMissions`), `client/RadioSurvivorCore/RC_MissionJournalView` (bouton de la barre latérale, tranche de la roue droite de la manette `ISDPadWheels.onDisplayRight`, fenêtre liste et détail, rafraîchie toutes les 3 s tant qu'elle est ouverte, haut, bas et B à la manette ; hôte `setHost` : bouton retiré, le carnet s'ouvre à la place) ; textes `IGUI_RC_` en EN et FR (`shared/Translate/<LANGUE>/IG_UI.json` du commun) ; RadioSurvivor : le carnet est l'hôte du journal (onglet Missions), sa liste passe par `RC_MissionList` et `RC_Missions.requester` (même ordre, mêmes états) ; suite en jeu `rc.journal` (campagne `mp`) ; banc `python tests/test_core_journal.py` (rouge d'abord : 7 ERROR, modules absents ; puis « Ran 8 tests … OK ») : commun seul sur un serveur dédié et deux clients (doublures ISUI du banc du carnet), offres et missions à rapporter du seul personnage du joueur dans l'ordre et les états du carnet, mission rendue retirée au rafraîchissement suivant, bouton puis hôte, roue, haut, bas et B, demandes limitées, aucun module de RadioSurvivor chargé ; avec RadioSurvivor, mêmes lignes dans le carnet et le journal, bouton absent, le journal ouvre le carnet sur Missions ; clés de toutes les langues livrées ; `test_kahlua.py` (40, suite `rc.journal` chargée dans la VM réelle) ; `python tests/run_all.py --keep-going` : 151 passés, 1 échec (`rs_suites` : renvois `fichier:ligne` de `RS_Env.lua` décalés, corrigés, banc relancé : OK), luacheck `Contents` 15 (référence 15), `dev` 0 ; campagne MP automatique du 2026-11-06 (commit `1573eda`, serveur dédié + 2 clients, faux modèle, code 1) : RST-RESULT client 1 ok=false total=376 pass=357 fail=3 skip=16, client 2 total=153 pass=152 fail=1 ; toutes les suites des missions et le journal verts (29 PASS : rs.missions*, rs.mission.*, rc.journal), 3 FAIL sans lien avec les missions : lk.barricade (E01-T21) et lk.traversal ×2 (E01-T22) (`tools/autoclient/runs/20261106-002923-mp-2889c9f2103f/server/20261105-233208-server.txt`)
  - Reste : passage visuel du journal ; rendu réel de la fenêtre, du bouton et de la roue de la manette non vus en jeu ; Living Knox seul (mission d'un PNJ dans le journal puis retirée) : E18-T07 et E18-T11 ; titres des missions encore en `IGUI_RS_*` dans RadioSurvivor : E18-T13

- [ ] **E18-T07** — Mod `batman_LivingKnox` : code déplacé
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : E18-T02
  - Fichiers : `Contents/mods/batman_LivingKnox/` (`common/`, `42.21/mod.info`, `require=` du commun) ; code `media/lua/*/LivingKnox/`, AnimSets `lkactor_*`, page `LivingKnox` des options, clés `IGUI_LK_` et `Sandbox_LivingKnox_` déplacés ; `tools/gen_animsets.py`
  - Faire : déplacer le moteur dans son mod ; `incompatible=` Bandits! et Project A-Life repris par Living Knox ; plus aucun fichier du moteur dans `batman_RadioSurvivor`.
  - Accepté si : Living Knox seul coché démarre (commun actif) sans erreur Lua ; les trois mods ensemble se chargent comme aujourd'hui.
  - Tests : `run_all.py` (bancs adaptés aux trois dossiers) ; démarrage solo de chaque montage.
  - Preuve : mod `batman_LivingKnox` (`common/` avec les 45 AnimSets `lkactor_*`, `42.21/mod.info` `require=\batman_RadioSurvivorCore`, `incompatible=\Bandits2,\ProjectALifeNPCs` repris de RadioSurvivor) ; code `media/lua/{client,server,shared}/LivingKnox/` déplacé par `git mv` (78 fichiers) ; page `LivingKnox` des options (32 options) et clés `IGUI_LK_` (339) et `Sandbox_LivingKnox_` (65) déplacées en EN et FR ; RadioSurvivor exige Living Knox jusqu'à `E18-T09` (son adaptateur `RS_LivingKnox` requiert `LK_Core`) ; lanceurs (autoclient, `autotest.json`, `run_dedicated_smoke.ps1`) : commun, Living Knox puis RadioSurvivor ; `tools/gen_animsets.py --check` OK ; `tools/check_case.py` PASS (quatre mods) ; banc `tests/test_lk_mod.py` (7 tests, rouge avant le déplacement puis vert) ; bancs adaptés aux trois dossiers (`harness.lua_src`, `LK_LUA`) ; `run_all.py` 152 PASS ; luacheck Contents 15, dev 0 ; `plan.py check` 0 erreur ; passage solo automatique du 2026-11-06 (trois mods chargés dans l'ordre commun, Living Knox, RadioSurvivor ; rs.env et rst, faux modèle, code 0) : 13/13 (`tools/autoclient/runs/20261106-093910-85b09873beb7`) ; campagne MP automatique du 2026-11-06 (copie figée du commit `df05e83`, trois mods, serveur dédié + 2 clients, faux modèle, code 1) : client 1 total=376 pass=359 fail=1 skip=16, client 2 153/153 ; seul échec lk.zombies (instable, sans lien) ; lk.traversal et lk.barricade verts (`tools/autoclient/runs/20261106-102744-mp-922acdb1a395/server/20261106-092949-server.txt`)
  - Reste : Living Knox seul coché : `LK_Sites` et `LK_Simulation` requièrent encore `RadioSurvivor/RS_Rescue` (`E18-T08`) ; démarrage en jeu de Living Knox seul avec le montage de `E18-T14` ; données encore sous `Zomboid/Lua/batman_RadioSurvivor/livingknox/` (`E18-T10`)

- [ ] **E18-T08** — Bases connues et sites sans RadioSurvivor
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : E18-T07
  - Fichiers : `LK_Sites`, `LK_Simulation` (`knownBases`), `RS_Rescue`
  - Faire : Living Knox ne requiert plus `RS_Rescue` ; la géométrie des bases des joueurs passe dans le commun (servie aux missions et aux PNJ) ou arrive par un crochet optionnel ; seul, Living Knox repère les bases par ses propres moyens ou s'en passe.
  - Accepté si : sites et raids tournent sans RadioSurvivor ; avec lui, mêmes bases qu'aujourd'hui.
  - Tests : bancs `test_lk_sites*`, `test_lk_raids` ; suites lk.sites et lk.raids dans les trois montages.
  - Preuve : `LK_Sites` (tirage, classement, bases) et `LK_Simulation.knownBases` lisent `RadioSurvivorCore/RC_Sites` du mod commun (mêmes fonctions et mêmes bases que `RS_Rescue`, qui les recopie) ; plus aucun module de RadioSurvivor requis par Living Knox (`tests/test_lk_mod.py`) ; suite en jeu `lk.sites` sur `RC_Sites` ; `tools/check_case.py` : Living Knox vérifié avec le mod commun et Signal Smoke seuls, PASS ; bancs `test_lk_sites.py` (classe `WithoutRadioSurvivorTests` : sites et bases sans aucun module de RadioSurvivor sur le chemin, rouge avant le changement puis vert), `test_lk_simulation.py`, `test_lk_raids.py` OK ; `run_all.py` 153 PASS ; luacheck Contents 15, dev 0 ; passage solo automatique du 2026-11-06 (trois mods, lk.sites et lk.raid, faux modèle, code 0) : 8/8 (`tools/autoclient/runs/20261106-095205-72e9139224c8`) ; campagne MP automatique du 2026-11-06 (copie figée du commit `df05e83`, trois mods, serveur dédié + 2 clients, faux modèle, code 1) : client 1 total=376 pass=359 fail=1 skip=16, client 2 153/153 ; seul échec lk.zombies (instable, sans lien) ; lk.traversal et lk.barricade verts (`tools/autoclient/runs/20261106-102744-mp-922acdb1a395/server/20261106-092949-server.txt`)
  - Reste : suites lk.sites et lk.raid dans le montage Living Knox seul (outillage `E18-T14`, validation `E18-T15`)

- [ ] **E18-T09** — Adaptateur fournisseur porté par Living Knox
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E18-T07
  - Fichiers : `RS_LivingKnox.lua` (déplacé dans `batman_LivingKnox`, chargé seulement si RadioSurvivor est actif) ; `RS_NPCProvider.lua` (reste dans RadioSurvivor)
  - Faire : le fournisseur s'enregistre auprès de `RS_NPCProvider` quand les deux mods sont actifs ; sans Living Knox, RadioSurvivor tourne avec « aucun moteur de PNJ » (cas déjà prévu par E17).
  - Accepté si : RadioSurvivor seul démarre sans erreur et sans fiche de PNJ ; ensemble, comportement d'aujourd'hui.
  - Tests : bancs `test_carnet.py`, `test_lk_api*` ; campagnes des trois montages.
  - Preuve : adaptateur `shared/RadioSurvivor/RS_LivingKnox.lua` déplacé par `git mv` dans `batman_LivingKnox` (même chemin relatif, même nom global), inactif si `batman_RadioSurvivor` n'est pas dans `getActivatedMods()` (aucun module de RadioSurvivor requis, `RS_LivingKnox` reste nil) ; `require=` de RadioSurvivor sans Living Knox (description du mod mise à jour) ; tableau des outils de debug déplacé dans le commun (`client/RadioSurvivorCore/RC_Table`, anglais, ASCII ; `LK_Table` en garde le nom `LivingKnox.Table`) pour la vue de debug des fréquences de RadioSurvivor ; bancs `test_carnet.py` (`test_radiosurvivor_alone_without_living_knox` : tous les fichiers shared de RadioSurvivor, carnet et vue de debug sans Living Knox sur le chemin, fournisseur « none », rouge avant le déplacement puis vert), `test_lk_mod.py` (adaptateur muet sans RadioSurvivor, actif avec), `test_check_case.py` et `tools/check_case.py` (RadioSurvivor vérifié sans Living Knox) ; `run_all.py` 153 PASS ; luacheck Contents 15, dev 0 ; passage solo automatique du 2026-11-06 (trois mods, rs.env, rs.carnet.lk, rs.carnet.lk.supply, lk.debugview, faux modèle, code 0) : 17 PASS + 1 SKIP (MP), « [RS_NPCProvider] provider livingknox registered » dans la console (`tools/autoclient/runs/20261106-100705-bd2132575b40`) ; campagne MP automatique du 2026-11-06 (copie figée du commit `df05e83`, trois mods, serveur dédié + 2 clients, faux modèle, code 1) : client 1 total=376 pass=359 fail=1 skip=16, client 2 153/153 ; seul échec lk.zombies (instable, sans lien) ; lk.traversal et lk.barricade verts (`tools/autoclient/runs/20261106-102744-mp-922acdb1a395/server/20261106-092949-server.txt`)
  - Reste : RadioSurvivor seul démarré en jeu (montage de `E18-T14`, validation `E18-T15`) ; campagne MP des deux mods ensemble

- [ ] **E18-T10** — Dossier de données de Living Knox et reprise des parties existantes
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E18-T07
  - Fichiers : `LK_Store` (`DIR`), `LK_Groups`, `LK_Hostility`
  - Faire : registres sous `Zomboid\Lua\batman_LivingKnox\` ; au premier lancement, reprise une seule fois de `batman_RadioSurvivor\livingknox\` (copie, ancien dossier laissé en place, ligne de journal en anglais).
  - Accepté si : une partie créée avant la séparation garde ses groupes, foyers et attitudes ; la reprise ne se refait pas.
  - Tests : banc de reprise ; phase `after-restart` sur une partie d'avant la séparation.
  - Preuve : registres de Living Knox (PNJ `registry`, groupes `groups`, attitudes `attitudes`) sous `Zomboid/Lua/batman_LivingKnox/` (`LK_Store.DIR`) ; `Store.takeOver` appelé par `Store.init`, `Groups.init` et `Hostility.init` hors monde neuf : les deux emplacements de l'ancien dossier `batman_RadioSurvivor/livingknox/` copiés tels quels si aucun n'existe dans le nouveau, ancien dossier laissé, ligne « taken over » en anglais ; banc `tests/test_lk_takeover.py` (3 tests : partie de l'ancien format écrite par le même code avec l'ancien dossier, reprise octet pour octet des trois registres, PNJ relu, aucune seconde reprise après une écriture dans le nouveau dossier, rien pour un monde neuf ; rouge avant le changement puis vert) ; `run_all.py` 154 PASS ; luacheck Contents 15 ; campagne MP automatique du 2026-11-06 (copie figée du commit `df05e83`, trois mods, serveur dédié + 2 clients, faux modèle, code 1) : client 1 total=376 pass=359 fail=1 skip=16, client 2 153/153 ; seul échec lk.zombies (instable, sans lien) ; lk.traversal et lk.barricade verts (`tools/autoclient/runs/20261106-102744-mp-922acdb1a395/server/20261106-092949-server.txt`)
  - Reste : phase `after-restart` en jeu sur une partie créée par l'ancienne version (campagne MP de `E18-T15`) ; groupes et attitudes relus après redémarrage dans le nouveau dossier (suites `lk.*persist` de la campagne MP)

- [ ] **E18-T11** — Historique des échanges avec les PNJ dans le commun
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E18-T04, E18-T09
  - Fichiers : `RC_History` (commun, état privé `Zomboid/Lua/batman_RadioSurvivorCore/history-*.txt`) ; `RS_Carnet_Server.lua` (`contacts[...].history`), `RS_Conversations`, `RS_Initiatives`, `RS_GroupRadio`, `RS_State` (reprise), `RS_StatePurge`
  - Faire : historique des échanges avec les PNJ dans le mod commun, par personnage et par interlocuteur, borné comme aujourd'hui (`MAX_HISTORY`) ; historiques d'une partie existante repris une seule fois depuis l'état du carnet ; le carnet le lit pour l'affichage (décision du 2026-11-05). Découpage du 2026-11-06 : la file des demandes de parole passe à `E18-T17`, la parole avec Living Knox seul à `E18-T18`, l'historique des voix radio à `E18-T19`.
  - Accepté si : une partie existante garde l'historique affiché par le carnet ; mêmes lignes et mêmes bornes qu'avant ; un personnage mort oublié comme aujourd'hui.
  - Tests : banc de reprise (fixture écrite par l'ancien code) ; `test_carnet.py`, `test_conversations.py`, `test_initiatives.py`, `test_group_radio.py` ; suites rs.npctalk, rs.conversations, rs.initiatives.
  - Preuve : `server/RadioSurvivorCore/RC_History` (mod commun, ASCII, anglais : lignes par personnage et par interlocuteur, `MAX` 40, fichier privé `batman_RadioSurvivorCore/history-*` en-tête RCHISTORY1 par `RC_SlotFile`) ; `RS_State` : historiques d'une partie d'avant la séparation repris une fois, chaque `contacts[...].history` devient la table du commun (écrivains du carnet, des conversations, des initiatives et de la radio de groupe inchangés), fichier du carnet écrit sans les historiques, contacts et personnages disparus oubliés à l'écriture (`History.retain`) ; banc `tests/test_core_history.py` (5 tests, fixture `tests/fixtures/e18-t11` écrite par l'ancien `RS_State`, rouge avant puis vert) ; `run_all.py` 156 PASS ; luacheck Contents 15, dev 0
  - Reste : suites rs.npctalk, rs.conversations, rs.initiatives en campagne MP avec l'historique dans le commun ; redémarrage d'une partie existante en jeu (`E18-T15`)
- [ ] **E18-T12** — Pont : un dossier d'échange pour les deux mods
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T04, E18-T17
  - Fichiers : `bridge/radio_bridge.py`, `bridge/npc_protocol.py`, `bridge/README*`
  - Faire : dossier d'échange par défaut du commun, ancien dossier lu en transition ; personnages des voix lus seulement quand RadioSurvivor les installe ; limites de texte de la parole lues dans un seul endroit ; aucune demande ni dossier créé pour un mod absent.
  - Accepté si : le même pont, sans option, sert RadioSurvivor seul, Living Knox seul et les deux.
  - Tests : bancs du pont (`tests/test_bridge*`, `test_protocol.py`) dans les trois montages ; campagnes avec `--bridge on`.
  - Preuve : —
  - Reste : —

- [x] **E18-T13** — Traductions et options sandbox des trois mods
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E18-T06, E18-T07
  - Fichiers : `media/lua/shared/Translate/*/` et `media/sandbox-options.txt` des trois mods
  - Faire : chaque mod porte ses clés et sa page d'options (missions et pont dans le commun) ; aucune clé ni option perdue, dans toutes les langues livrées ; réglages d'une partie existante relus.
  - Accepté si : union des clés égale aux clés d'avant plus celles du journal ; aucune clé d'un mod dans un autre.
  - Tests : banc de comparaison des clés ; `check_case`.
  - Preuve : confirmé par défaut le 2026-11-06 : aucune option sandbox ne porte sur les missions ou le pont (les 15 options de la page `RadioSurvivor` règlent la radio, ses plafonds, les secours et le confort, plafonds séparés décidés le 2026-11-05) : le mod commun n'a pas de page d'options ; titres des missions passés au commun sous `IGUI_RC_Mission_<nom>` (10 clés EN et FR : FirstAid, Scout, Supply, Supply_food, Supply_medical, Supply_ammo, Retrieve, Clear, Recover, Signal, retirées de RadioSurvivor ; `RC_MissionConfig`, `RC_Missions`, repli du carnet `IGUI_RC_Mission`) ; mission enregistrée avant la séparation (`IGUI_RS_<nom>`) projetée avec la nouvelle clé par `RC_MissionConfig.titleKey`, état sur disque inchangé ; `protocole-carnet-v2.md` mis à jour ; banc `tests/test_translations_split.py` (7 tests, rouge d'abord : 3 FAIL, 1 ERROR ; puis OK) : clés d'avant la séparation figées depuis le commit `4ab5c75` (`tests/fixtures/e18-t13/keys-before.json`, 6 fichiers par langue, 47 options), union des trois mods = clés d'avant + 19 clés du journal + titres renommés, dans chaque langue et chaque fichier ; aucune clé livrée par deux mods ; préfixes séparés (`IGUI_RC_` commun, `IGUI_LK_` et `Sandbox_LivingKnox` Living Knox) ; mêmes clés EN et FR dans chaque mod ; toute clé littérale du Lua d'un mod livrée par lui, un mod qu'il exige ou le jeu ; 47 options gardées sous leur nom (réglages d'une partie existante relus), chacune sur la page de son mod avec son libellé dans ce mod ; banc visuel du carnet (`test_notebook_visual.py`, suite `rs.notebook.visual`) : tables du commun et de RadioSurvivor fusionnées comme le jeu ; `run_all.py` 157 PASS (dont `case` PASS), luacheck `Contents` 15 (référence 15), `dev` 0, `plan.py check` 0 erreur
  - Reste : —

- [x] **E18-T14** — Outillage des tests pour trois montages
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E18-T07
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/mod.info` (exige le commun seul, détecte les autres) ; `tests/harness.py`, `tests/run_all.py` ; `tools/autoclient/autoclient.py` (`--mods rs|lk|both`, dossiers de résultats et d'échange) ; `tests/run_dedicated_smoke.ps1` ; listes des campagnes
  - Faire : chaque suite déclare les mods qu'elle exige (SKIP sinon) ; suites mixtes (carnet et PNJ) seulement avec les deux ; campagnes `solo` et `mp` lançables dans chaque montage.
  - Accepté si : `run_all.py` vert ; un passage de chaque montage démarre et rend un rapport.
  - Tests : bancs `test_autoclient.py`, `test_rst.py`.
  - Preuve : moteur RST : chaque suite exige ses mods (`opts.mods`, sinon `lk.*` Living Knox, `rs.*` RadioSurvivor, autres : le commun seul), suite d'un mod absent SKIP « needs mod(s) … (not active) » (`RST.suiteMods`, `RST.modsRefusal`, `getActivatedMods`) ; 23 suites mixtes déclarées (`mods = { "rs", "lk" }`), `rst.rights` `{ "rs" }` ; banc `tests/test_suite_mods.py` (ce que chaque suite utilise est couvert par ses mods déclarés) ; mod de test : `require=\batman_RadioSurvivorCore` seul ; `autoclient.py --mods rs|lk|both` (lk : Signal Smoke, commun, Living Knox, mod de test) ; bancs `test_rst.py` (`ModsGuardTests`, rouge puis vert), `test_autoclient.py` (trois montages), `run_all.py` 156 PASS, luacheck dev 0 ; passages solo automatiques du 2026-11-06 : RadioSurvivor seul (`--mods rs`, rs.env et rst, code 0) 13/13, aucune erreur Lua au chargement (`tools/autoclient/runs/20261106-111224-6371ee6c5612`) ; Living Knox seul (`--mods lk`, lk.sites, lk.raid, rst, rs.env, code 1) 21 PASS, 1 FAIL rst.guard (auto-test qui ne connaissait pas le refus par mod, corrigé) (`tools/autoclient/runs/20261106-111314-7fc92fd30d78`), relancé code 0 : 22 PASS + 11 SKIP (rs.env, rst.rights, rst.fixtures.npc : RadioSurvivor absent), aucune erreur Lua au chargement (`tools/autoclient/runs/20261106-111504-a322ac1c347b`)
  - Reste : campagnes `solo` et `mp` complètes dans chaque montage (`E18-T15`) ; `run_dedicated_smoke.ps1` reste sur les deux mods ensemble

- [ ] **E18-T15** — Validation des trois montages
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T05, E18-T06, E18-T08, E18-T10, E18-T12, E18-T13, E18-T14, E18-T18, E18-T19
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


- [ ] **E18-T17** — File des demandes de parole des PNJ portée par Living Knox
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T11, E18-T20, E18-T21, E18-T22
  - Fichiers : `LK_Talk` (Living Knox : file, voie `npc` de `RC_Transport`, numéros d'ordre et révisions par PNJ, délais, refus) ; `RS_Carnet_Server.lua` (`enqueue`, `syncTransport`, `poll`, `reply`), `RS_Conversations`, `RS_Initiatives`, `RS_BridgeLanes` ; `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : Living Knox émet `npc_talk`, `npc_converse`, `npc_initiative` et `npc_enrich` par le lien commun ; RadioSurvivor ajoute au contexte ses éléments (relation, réputation, accords, missions du carnet) et traite ses actions de la réponse par des crochets de l'API ; demandes en attente d'une partie existante reprises.
  - Accepté si : ensemble : mêmes demandes, mêmes offres, acceptations et relations qu'aujourd'hui (suites rs.npctalk, rs.conversations, rs.initiatives).
  - Tests : `test_protocol.py`, `test_carnet.py`, `test_conversations.py`, `test_initiatives.py`, `test_npc_reply.py` ; campagne MP.
  - Preuve : —
  - Reste : —

- [ ] **E18-T18** — Parole de proximité avec Living Knox seul
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T17
  - Fichiers : `LK_Talk` (commande de parole près d'un PNJ, contexte du PNJ seul), donneur de missions des PNJ (`RC_Missions.registerDonor`), magasin des missions du commun sans RadioSurvivor ; `bridge/npc_protocol.py`
  - Faire : sans RadioSurvivor, une phrase dite près d'un PNJ part au pont avec le contexte du PNJ (groupe, rôle, besoins, historique du commun) et revient en bulle ; offres et acceptations de missions des PNJ par le moteur commun (journal des missions du commun).
  - Accepté si : Living Knox seul : une phrase dite près d'un PNJ reçoit une réponse du LLM en bulle, le PNJ se souvient des échanges précédents, et un PNJ propose une mission.
  - Tests : banc de la parole sans RadioSurvivor ; suites de parole dans le montage Living Knox seul.
  - Preuve : —
  - Reste : —

- [ ] **E18-T19** — Historique des voix radio dans le commun
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T11
  - Fichiers : `RS_RadioLog` (aujourd'hui `characters[...].radio` de l'état du carnet), `RC_History`
  - Faire : les échanges avec les voix radio gardés par le mod commun comme ceux des PNJ (confirmé par défaut le 2026-11-05), mêmes règles (lignes typées, fréquences entendues vérifiées, bornes) ; historiques d'une partie existante repris une fois.
  - Accepté si : une partie existante garde l'historique radio du carnet ; mêmes lignes qu'avant.
  - Tests : `test_radio_log*` ; suites rs.radiolog.
  - Preuve : —
  - Reste : —

- [ ] **E18-T20** — Accords dans Living Knox, identifiants d'équipe dans le commun
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T09
  - Fichiers : `RS_Factions` (identifiants d'équipe et mandats → commun ; accords → Living Knox), `RS_Incidents`, `RS_Carnet_Server` (offre, conclusion, `collectiveCheck`, annonce), crochet `LivingKnox.Hooks.covered` ; `bridge/npc_protocol.py` (termes de la négociation) ; `docs/annexes/conception/accords.md`
  - Faire : décision du 2026-11-06 : trêves, alliances et incidents tenus par Living Knox (état privé de Living Knox), négociés par la parole des PNJ ; identifiants `fac-<n>` et mandats dans le commun ; accords d'une partie existante repris une seule fois ; RadioSurvivor n'a plus aucun code d'accord (le carnet affiche ceux que Living Knox publie, s'il est présent).
  - Accepté si : Living Knox seul : une trêve conclue avec un chef de groupe rend le groupe non agressif, gardée après redémarrage ; RadioSurvivor seul démarre sans code d'accord ; ensemble : mêmes accords qu'avant.
  - Tests : bancs des accords et des incidents (fixture écrite par l'ancien code) ; suites des accords dans les montages Living Knox seul et les deux.
  - Preuve : —
  - Reste : —

- [ ] **E18-T21** — Relation personnelle des PNJ dans Living Knox
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T09
  - Fichiers : `RS_Relations` → Living Knox ; `RS_Carnet_Server` (intention `change_relation`, affichage) ; `docs/annexes/conception/relations.md`
  - Faire : confirmé par défaut le 2026-11-06 : la relation d'un PNJ envers un personnage (écart d'un niveau autour de l'attitude du groupe, faits citables) tenue par Living Knox ; relations d'une partie existante reprises une seule fois ; le carnet la lit par l'API de Living Knox s'il est présent.
  - Accepté si : Living Knox seul : la relation change par un fait réel cité dans la réponse et reste après redémarrage ; ensemble : mêmes niveaux et mêmes tendances qu'avant.
  - Tests : bancs des relations (fixture écrite par l'ancien code) ; suite rs.relation dans les deux montages concernés.
  - Preuve : —
  - Reste : —

- [ ] **E18-T22** — Réputation dans le commun
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T05
  - Fichiers : `RS_Reputation` → `RC_Reputation` (commun, état privé du commun) ; sources des faits (`RC_Missions.finish`, troc `RS_TradeExchange`, morts de PNJ et de donneurs côté Living Knox) ; filtre des offres (`RS_MissionHooks`) ; `docs/annexes/conception/reputation-interne.md`
  - Faire : décision du 2026-11-06 : une réputation par personnage dans le commun, mêmes règles et mêmes bornes ; chaque mod signale ses faits par l'API du commun (liste fermée des sortes de faits, aucun fait venu d'un client ni d'une phrase) ; réputations d'une partie existante reprises une seule fois ; voix et PNJ lisent le même niveau.
  - Accepté si : chaque mod seul : missions réussies ou ratées changent la réputation ; Living Knox seul : le meurtre d'un membre d'un groupe la baisse ; ensemble : mêmes scores qu'avant.
  - Tests : bancs de la réputation (fixture écrite par l'ancien code) ; suites rs.reputation dans les trois montages.
  - Preuve : —
  - Reste : —
