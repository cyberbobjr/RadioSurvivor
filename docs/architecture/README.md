# Architecture de Radio Survivor, Living Knox et du mod commun

Synthèse de l'architecture logicielle des **trois mods** de l'article Workshop (Build 42.21) : `batman_RadioSurvivorCore`
(mod commun, 0.1.0), `batman_RadioSurvivor` (radio, voix, factions, 0.3.0) et `batman_LivingKnox` (moteur de PNJ, 0.1.0).
Les détails vivent dans les pages liées ; ce document ne les répète pas.

| Page | Contenu |
|---|---|
| [ia-multijoueur.md](ia-multijoueur.md) | Analyse comparative qui a fondé la décision LK00-T02 (IA des PNJ en multijoueur, contraintes du moteur) |
| [decisions/](decisions/README.md) | Journal des décisions d'architecture et ADR |

## 1. Vue d'ensemble

```text
            joueur (client)                         autorité (serveur dédié, ou jeu en solo)
  ┌─────────────────────────────┐   commandes    ┌────────────────────────────────────────────┐
  │ carnet (Core), fenêtre      │ ─────────────▶ │ RadioSurvivor : voix, troc, secours,       │
  │ radio (RadioSurvivor),      │ ◀───────────── │ chronique, factions (RS_State)             │
  │ vues Living Knox (fiche,    │ sendServer...  │        │ RS_NPCProvider                     │
  │ admin, parole)              │                │        ▼                                   │
  └─────────────────────────────┘                │ Living Knox : groupes, PNJ, décisions,     │
                                                 │ corps (joueurs réanimés), registre fichier │
                                                 │ Core (commun) : missions, identité,        │
                                                 │ historique, réputation, file du pont       │
                                                 └───────────────┬────────────────────────────┘
                                                                 │ requests.txt / responses.txt
                                                                 ▼ (Zomboid/Lua/batman_RadioSurvivorCore)
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
- **Interface `RS_NPCProvider`** entre le carnet de RadioSurvivor et le moteur de PNJ : le carnet ne dépend pas des
  corps. Living Knox ne dépend d'aucun module de RadioSurvivor : chacun des deux mods vit sans l'autre.
- **État secret** dans `RS_State` et dans les registres fichiers de Living Knox, jamais en ModData globale (lisible
  par tous les clients).

> Schéma à produire : `docs/images/diagrams/architecture.svg` (le schéma texte ci-dessus en tient lieu).

## 2. Arborescence des mods

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
Contents/mods/batman_RadioSurvivorCore/   mod commun, activé par le jeu avec l'un ou l'autre
├── common/
└── 42.21/
    ├── mod.info                id=batman_RadioSurvivorCore, require=\batman_SignalSmoke, modversion=0.1.0
    └── media/lua/{client,server,shared}/RadioSurvivorCore/ + Translate/{EN,FR} (IGUI_RC_)
```

Montages valides : RadioSurvivor seul, Living Knox seul, ou les deux, toujours avec le mod commun, qui seul n'apporte
rien de jouable. Le pont Python est un seul programme, sans option selon le montage.

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
| server (mod commun `batman_RadioSurvivorCore`) | `RadioSurvivorCore/` | depuis `E18-T05`, moteur de missions commun (`RC_Missions` : offres, acceptation, délais, compte rendu, lot de récompense ; donneurs inscrits par `registerDonor` et crochets de résultat, d'oubli, de filtre des offres), gabarits `RC_MissionScout`, `RC_MissionClear`, `RC_MissionRecover`, `RC_MissionRetrieve`, `RC_MissionSignal` (exige Signal Smoke), tirage des lieux (`RC_Sites`), caches (`RC_Caches`), catalogue (`shared/RC_MissionConfig`), état privé des missions (`RC_MissionStore`, `Zomboid/Lua/batman_RadioSurvivorCore/missions-*.txt` ) ; RadioSurvivor y inscrit ses donneurs (fiches PNJ, voix) et ses crochets dans `RS_MissionHooks` ; depuis `E18-T06`, lignes du journal des missions (`RC_MissionJournal`, commande `missions` du module `RadioSurvivorCore`, même liste que le carnet par `shared/RC_MissionList`) |
| server | `RadioSurvivor_Server.lua`, `RS_Carnet_Server.lua` | points d'entrée : commandes client, carnet, livraisons |
| server | `RadioSurvivor/` (47 fichiers) | état privé (`RS_State`), transport vers le pont (`RS_BridgeLanes` (file `RC_Transport` du mod commun)), voix (`RS_Persona*`), actions et missions des voix (`RS_Actions`, `RS_MissionVoice`, `RS_MissionHooks`, `RS_CacheAction`), secours (`RS_Rescue*`), troc (`RS_Trade*`), chronique et faits, dernières pages, réputation ; depuis `E18-T20`, les identifiants d'équipe sont au mod commun (`RC_Teams`) et les accords à Living Knox (`LK_Agreements`, lus par `LivingKnox.Agreements`) |
| server (mod `batman_LivingKnox`) | `LivingKnox/` (43 fichiers) | groupes et foyers, population, décisions, routines, alerte, défense, combat, santé, mort et butin, stock, fortification, simulation hors écran, récits, relations, raids, API publique (`LK_API`), registre (`LK_Store`) |
| client (mod commun `batman_RadioSurvivorCore`) | `RadioSurvivorCore/` | depuis `E18-T24`, le carnet (`RC_Notebook` : cadre papier, marque-pages, bouton de la barre latérale, tranche de la roue droite de la manette, registre d'onglets `registerTab` / `extendTab`) ; chaque onglet appartient à un mod et n'existe que si ce mod est actif : Radio (RadioSurvivor), Équipe (inscrit par RadioSurvivor avec Living Knox actif, passe à Living Knox avec `E18-T20`), Contacts, Missions et Réputation communs ; sans mod pour les remplir, Missions liste les missions ouvertes du personnage (commande `missions`, ancien journal des missions de `E18-T06`) ; textes `IGUI_RC_` (EN, FR) |
| client | `RadioSurvivor_Client.lua`, `RS_Carnet_Client.lua`, `RadioSurvivor/` | module « Émettre » de la fenêtre radio, pages du carnet (`RS_Notebook` : onglet Radio, contenu des onglets communs, onglet Équipe), historique radio, lecture des notes, actions de carte, vue de debug des fréquences |
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
| Registre des PNJ et des groupes | `Zomboid/Lua/batman_LivingKnox/registry-<partie>-<0\|1>.txt` (`LKREG1`), une écriture par image au plus | `LK_Store` ([corps-registre.md](../annexes/conception/corps-registre.md)) |
| État du mod commun (missions, identités, historique des échanges) | `Zomboid/Lua/batman_RadioSurvivorCore/` : `missions-*`, `identity-*`, `history-*` (fichiers privés à deux emplacements, `RC_SlotFile`) | `RC_MissionStore`, `RC_Identity`, `RC_History` |
| Échange avec le pont | `Zomboid/Lua/batman_RadioSurvivorCore/` : `requests.txt`, `responses.txt`, `bridge-alive.txt`, `bridge.lock` | serveur / pont |
| Fiches de voix | `Zomboid/Lua/batman_RadioSurvivor/personas/` (RadioSurvivor actif seulement) | `RS_Personas` |
| Données d'objets et de PNJ | ModData d'objet et de corps (marques d'idempotence, identité) | serveur |

Un schéma inconnu ou deux fichiers illisibles bloquent l'écriture (fichiers conservés). Un monde neuf
(`OnInitGlobalModData(true)`) repart d'un registre vide. Aucune reprise des parties d'avant la séparation : les mods ne
sont pas publiés avec une sauvegarde à reprendre.

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
