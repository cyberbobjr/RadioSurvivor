# Architecture de Radio Survivor

Synthèse de l'architecture logicielle du mod `batman_RadioSurvivor` (Build 42.21, version 0.3.0). Les détails vivent
dans les pages liées ; ce document ne les répète pas.

| Page | Contenu |
|---|---|
| [ia-multijoueur.md](ia-multijoueur.md) | Analyse comparative qui a fondé la décision LK00-T02 (IA des PNJ en multijoueur, contraintes du moteur) |
| [decisions/](decisions/README.md) | Journal des décisions d'architecture et ADR |

## 1. Vue d'ensemble

```text
            joueur (client)                         autorité (serveur dédié, ou jeu en solo)
  ┌─────────────────────────────┐   commandes    ┌────────────────────────────────────────────┐
  │ fenêtre radio (module       │ ─────────────▶ │ RadioSurvivor : voix, missions, troc,      │
  │ « Émettre »), carnet, vues  │ ◀───────────── │ secours, chronique, réputation (RS_State)  │
  │ Living Knox (fiche, admin)  │ sendServer...  │        │ RS_NPCProvider                     │
  └─────────────────────────────┘                │        ▼                                   │
                                                 │ Living Knox : groupes, PNJ, décisions,     │
                                                 │ corps (joueurs réanimés), registre fichier │
                                                 └───────────────┬────────────────────────────┘
                                                                 │ requests.txt / responses.txt
                                                                 ▼ (Zomboid/Lua/batman_RadioSurvivor)
                                                 ┌────────────────────────────────────────────┐
                                                 │ pont Python (bridge/radio_bridge.py) ─▶ LLM │
                                                 └────────────────────────────────────────────┘
```

Principes validés par la décision LK00-T02 du 2026-10-03 et la fusion du 2026-10-08 (voir
[decisions/](decisions/README.md) et [developpement.md](../developpement.md)) :

- **Serveur autoritaire** : seules les fonctions serveur décident des effets persistants (récompenses, stocks,
  objectifs, réputation, fréquences). Le client présente et demande.
- **Le LLM propose, le serveur décide** : le pont ne fait que valider le protocole et choisir dans des listes fermées
  (actions `say`, `mark_map`, `start_mission`…, voir [protocole-carnet-v2.md](../specifications-techniques/protocole-carnet-v2.md)).
- **Adaptateurs moteur** (inventaire, monde, XP, réseau) : ils exécutent les décisions validées, rien d'autre.
- **Interface `RS_NPCProvider`** entre le carnet et le moteur de PNJ : le carnet ne dépend pas des corps.
- **État secret** dans `RS_State` et dans les registres fichiers de Living Knox, jamais en ModData globale (lisible
  par tous les clients).

> Schéma à produire : `docs/images/diagrams/architecture.svg` (le schéma texte ci-dessus en tient lieu).

## 2. Arborescence du mod

```text
Contents/mods/batman_RadioSurvivor/
├── common/                     requis en B42 (vide)
└── 42.21/                      seule variante
    ├── mod.info                id=batman_RadioSurvivor, versionMin=42.21, modversion=0.3.0
    ├── personas/               fiches des six voix livrées (walt, darlene, cody, whitaker, nightowl, gus)
    └── media/
        ├── sandbox-options.txt page RadioSurvivor
        ├── scripts/            objets du module RadioSurvivor (notes de fréquence, journal du dehors)
        ├── textures/RadioSurvivor/
        └── lua/{client,server,shared}/RadioSurvivor/ + Translate/{EN,FR}
Contents/mods/batman_LivingKnox/   moteur des PNJ depuis E18-T07
├── common/                     media/AnimSets (nœuds d'animation des corps de PNJ, générés par tools/gen_animsets.py)
└── 42.21/
    ├── mod.info                id=batman_LivingKnox, require=\batman_RadioSurvivorCore
    └── media/
        ├── sandbox-options.txt page LivingKnox
        └── lua/{client,server,shared}/LivingKnox/ + Translate/{EN,FR} (IGUI_LK_, Sandbox_LivingKnox_)
Contents/mods/batman_RadioSurvivorCore/   mod commun (E18-T01 à T06)
```

`mod.info` de RadioSurvivor : `require=\batman_RadioSurvivorCore,\batman_BeltRadio,\batman_SignalSmoke`
(Living Knox facultatif depuis `E18-T09` : l'adaptateur du carnet `shared/RadioSurvivor/RS_LivingKnox.lua` est livré par Living Knox et ne s'active qu'avec RadioSurvivor), `loadModAfter=\batman_CharacterReputation`
(intégration facultative). Living Knox : `incompatible=\Bandits2,\ProjectALifeNPCs`. Le mod de tests
`dev/batman_RadioSurvivorTests` n'est jamais publié.

## 3. Modules Lua

| Côté | Dossier | Responsabilités |
|---|---|---|
| shared (mod commun `batman_RadioSurvivorCore`) | `RadioSurvivorCore/` | outils partagés depuis `E18-T02` : codec RSV2 (`RC_Codec`), limite de débit des commandes (`RC_RateLimit`), coupe des textes (`RC_TextCut`), valeurs de troc (`RC_TradeValues`), monde neuf ou relancé (`RC_WorldStart`), horloge de jeu des délais (`RC_GameClock`) ; depuis `E18-T03`, identité des personnages (`RC_Identity` : identité décidée par l'autorité, écrite dans sa copie de la ModData du joueur sous la clé `RS_CarnetCharacter`, retirée à la mort, registre privé `Zomboid/Lua/batman_RadioSurvivorCore/identity-*.txt` ; lue par le carnet et par `LK_Hostility.keyOf`) et fichiers privés à deux emplacements (`RC_SlotFile`) |
| shared | `RadioSurvivor/` | constantes et noms de commandes (`RadioSurvivor_Const.lua`), interface `RS_NPCProvider` (implémentation Living Knox `RS_LivingKnox` livrée par `batman_LivingKnox` depuis `E18-T09`), notes |
| shared (mod `batman_LivingKnox`) | `LivingKnox/` | cœur (`LK_Core`, `LK_Config`), identité et apparence, équipement, sens, mouvement, garde des corps (`LK_ZombieGuard`), types de groupes et textes (`Data/`) |
| server (mod commun `batman_RadioSurvivorCore`) | `RadioSurvivorCore/` | depuis `E18-T05`, moteur de missions commun (`RC_Missions` : offres, acceptation, délais, compte rendu, lot de récompense ; donneurs inscrits par `registerDonor` et crochets de résultat, d'oubli, de filtre des offres), gabarits `RC_MissionScout`, `RC_MissionClear`, `RC_MissionRecover`, `RC_MissionRetrieve`, `RC_MissionSignal` (exige Signal Smoke), tirage des lieux (`RC_Sites`), caches (`RC_Caches`), catalogue (`shared/RC_MissionConfig`), état privé des missions (`RC_MissionStore`, `Zomboid/Lua/batman_RadioSurvivorCore/missions-*.txt` ; missions d'une partie d'avant la séparation reprises une fois depuis `RS_State`) ; RadioSurvivor y inscrit ses donneurs (fiches PNJ, voix) et ses crochets dans `RS_MissionHooks` ; depuis `E18-T06`, lignes du journal des missions (`RC_MissionJournal`, commande `missions` du module `RadioSurvivorCore`, même liste que le carnet par `shared/RC_MissionList`) |
| server | `RadioSurvivor_Server.lua`, `RS_Carnet_Server.lua` | points d'entrée : commandes client, carnet, livraisons |
| server | `RadioSurvivor/` (47 fichiers) | état privé (`RS_State`), transport vers le pont (`RS_BridgeLanes` (file `RC_Transport` du mod commun)), voix (`RS_Persona*`), actions et missions des voix (`RS_Actions`, `RS_MissionVoice`, `RS_MissionHooks`, `RS_CacheAction`), secours (`RS_Rescue*`), troc (`RS_Trade*`), chronique et faits, dernières pages, réputation, équipes (`RS_Factions`) |
| server (mod `batman_LivingKnox`) | `LivingKnox/` (43 fichiers) | groupes et foyers, population, décisions, routines, alerte, défense, combat, santé, mort et butin, stock, fortification, simulation hors écran, récits, relations, raids, API publique (`LK_API`), registre (`LK_Store`) |
| client (mod commun `batman_RadioSurvivorCore`) | `RadioSurvivorCore/` | depuis `E18-T06`, journal des missions (`RC_MissionJournalView` : bouton de la barre latérale, tranche de la roue droite de la manette, fenêtre des offres, missions en cours et à rapporter) ; avec RadioSurvivor, le carnet en est l'hôte (onglet Missions) et le bouton s'efface ; textes `IGUI_RC_` (EN, FR) |
| client | `RadioSurvivor_Client.lua`, `RS_Carnet_Client.lua`, `RadioSurvivor/` | module « Émettre » de la fenêtre radio, carnet, historique radio, lecture des notes, actions de carte, vue de debug des fréquences |
| client (mod `batman_LivingKnox`) | `LivingKnox/` | exécuteur des consignes sur le client propriétaire (`LK_Executor`), relais combat, santé, zombies, mort ; vues : fiche PNJ, administration, relations, troc, bulles |

Les dépendances suivent le sens présentation/pont → contrat → décisions serveur → adaptateurs moteur. Les fichiers
serveur se gardent par `isClient()` ; les fiches de conception de chaque sous-système sont dans
[annexes/conception/](../annexes/conception/README.md).

## 4. Flux de données

- **Radio** : le joueur émet depuis la fenêtre radio vanilla → commande `RadioSurvivor`/`talk` → le serveur choisit la
  voix d'après la fréquence (tirée par partie, jamais envoyée aux clients) → demande écrite dans `requests.txt` → le pont
  appelle le LLM et écrit `responses.txt` → le serveur valide les actions de la liste fermée, puis diffuse les lignes
  sur la fréquence (`AddDeviceText`). Détails : [protocole-carnet-v2.md](../specifications-techniques/protocole-carnet-v2.md),
  [persona-format.md](../specifications-techniques/persona-format.md).
- **Carnet** : module `RS_Carnet` (`report`, `accept`, `invite`, `abandon`, `prepare_delivery`…), réponses par
  `sendServerCommand`.
- **PNJ** : décisions sur l'autorité (`EveryHours`, `OnTick`) → consignes (`LK_Directives`) → exécution par le client
  propriétaire du corps (`dirAsk`, `dirClaim`, `dirReport`, `dirState`) ; dégâts, combat et santé remontent par le
  module `LivingKnox` (`combatHit`, `combatMelee`, `combatShot`, `zombieHurt`, `bodyReport`…).
- **Événements moteur principaux** : `OnClientCommand`/`OnServerCommand`, `OnTickEvenPaused`, `OnTick`, `EveryHours`,
  `EveryTenMinutes`, `EveryOneMinute`, `OnInitGlobalModData`, `OnLoadRadioScripts`, `OnCharacterDeath`, `OnZombieDead`,
  `OnWorldSound`, `OnDeviceText`, `OnFillContainer`.
- **Événements publics de Living Knox** pour RadioSurvivor : voir [api-living-knox.md](../specifications-techniques/api-living-knox.md).

## 5. Persistance

| Donnée | Support | Écrit par |
|---|---|---|
| État RadioSurvivor (voix, missions, fréquences, réputation interne, équipes…) | `Zomboid/Lua/batman_RadioSurvivor/state-<partie>-<0\|1>.txt` (en-tête `RSSTATE2`, RSV2 en hex, somme de contrôle, double emplacement) | `RS_State` |
| Registre des PNJ et des groupes | `Zomboid/Lua/batman_RadioSurvivor/livingknox/registry-<partie>-<0\|1>.txt` (`LKREG1`), une écriture par image au plus | `LK_Store` ([corps-registre.md](../annexes/conception/corps-registre.md)) |
| Échange avec le pont | `requests.txt`, `responses.txt`, `bridge-alive.txt`, `bridge.lock`, `personas/` | serveur / pont |
| Données d'objets et de PNJ | ModData d'objet et de corps (marques d'idempotence, identité) | serveur |

Un schéma inconnu ou deux fichiers illisibles bloquent l'écriture (fichiers conservés). Un monde neuf
(`OnInitGlobalModData(true)`) repart d'un registre vide. Les migrations de schéma passent par `Identity.upgrade`.

## 6. Points d'extension et intégrations

- **API publique Living Knox** (`LivingKnox.API`, version 1) : lecture des groupes, événements publics, demandes de
  ressources, journal de récit : [api-living-knox.md](../specifications-techniques/api-living-knox.md).
- **Fiches de voix** éditables par l'admin, relues à chaud : [persona-format.md](../specifications-techniques/persona-format.md)
  et le guide [Créer une voix radio](../wiki/fr/10-creer-une-voix-radio.md).
- **CharacterReputation** (facultatif) : contrat [reputation-contract.md](../specifications-techniques/reputation-contract.md).
- **Belt Walkie-Talkie** et **Signal Smoke** (prérequis) : talkie à la ceinture, fumées et fusées des missions.
- **Incompatibles** : Bandits! et Project A-Life (deux moteurs de PNJ concurrents, voir [ia-multijoueur.md](ia-multijoueur.md)).

## 7. Outillage

| Outil | Rôle |
|---|---|
| `tests/run_all.py` | tous les bancs hors jeu (lupa, VM Kahlua réelle `tests/test_kahlua.py`, luacheck avec base `tests/luacheck_baseline.txt`) |
| `tests/harness.py` | serveur et deux clients simulés sous lupa (ne valide pas l'API Java réelle) |
| `dev/batman_RadioSurvivorTests` + `tools/autoclient/autoclient.py` | tests en jeu RST : solo, serveur dédié avec deux clients pilotés ; méthode dans [tests-en-jeu.md](../annexes/tests/tests-en-jeu.md) |
| `autotest.json` | configuration du lanceur générique `pz-autotest` |
| `tools/plan.py` | plan d'implémentation : `check`, `suivi`, `next`, `show` ([annexes/plans/](../annexes/plans/README.md)) |
| `tools/features_status.py` | colonnes Solo/MP de [fonctionnalites.html](../annexes/maquettes/fonctionnalites.html) depuis le plan |
| `tools/gen_animsets.py`, `tools/gen_notebook_textures.py` | génération des AnimSets et des textures du carnet |
| `tools/make_test_zip.py` | zip de test local sans le Workshop |

Aucune CI GitHub (`.github/` absent) : les contrôles sont locaux.
