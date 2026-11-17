# Architecture de Radio Survivor, Living Knox et du mod commun

Synthèse de l'architecture logicielle des **trois mods** de l'article Workshop (Build 42.21) : `batman_CoreAI`
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
  │ carnet (CoreAI) : onglets   │ ─────────────▶ │ CoreAI (commun) : serveur et stock du      │
  │ Contacts, Missions,         │ ◀───────────── │ carnet, missions, identité, historique,    │
  │ Réputation ; Radio (RS),    │ sendServer...  │ réputation, équipes, file du pont          │
  │ Équipe (LK) ; fenêtre radio │                │   ▲ registres          ▲ CA_NPCProvider    │
  │ (RS) ; vues Living Knox     │                │   │ (commandes, polls, │ CA_GroupFacts     │
  │ (fiche, admin, Parler)      │                │   │ crochets, vues)    │                   │
  └─────────────────────────────┘                │ RadioSurvivor :        Living Knox :       │
                                                 │ voix, troc, secours,   groupes, PNJ, corps,│
                                                 │ chronique (RS_State)   parole, accords     │
                                                 └───────────────┬────────────────────────────┘
                                                                 │ requests.txt / responses.txt
                                                                 ▼ (Zomboid/Lua/batman_CoreAI)
                                                 ┌────────────────────────────────────────────┐
                                                 │ pont Python (bridge/radio_bridge.py) ─▶ LLM │
                                                 └────────────────────────────────────────────┘
```

Principes validés par la décision LK00-T02 du 2026-10-03, la séparation du 2026-11-05 et l'ADR
[Living Knox et RadioSurvivor séparés autour de batman_CoreAI](decisions/adr-coreai-separation.md) du 2026-11-15 (voir
[decisions/](decisions/README.md) et [developpement.md](../developpement.md)) :

- **Serveur autoritaire** : seules les fonctions serveur décident des effets persistants (récompenses, stocks,
  objectifs, réputation, fréquences). Le client présente et demande.
- **Le LLM propose, le serveur décide** : le pont ne fait que valider le protocole et choisir dans des listes fermées
  (actions `say`, `mark_map`, `start_mission`…, voir [protocole-carnet-v2.md](../specifications-techniques/protocole-carnet-v2.md)).
- **Adaptateurs moteur** (inventaire, monde, XP, réseau) : ils exécutent les décisions validées, rien d'autre.
- **Deux mods qui s'ignorent** : ni `batman_RadioSurvivor` ni `batman_LivingKnox` ne nomment l'autre (aucun `require`,
  global, événement, test d'identifiant de mod ni préfixe de journal de l'autre). Ce qu'ils partagent passe par les
  registres de `batman_CoreAI` (section 6).
- **Carnet commun, sans moteur de PNJ** : le carnet entier vit dans `batman_CoreAI` et ne parle aux PNJ que par
  l'interface `CA_NPCProvider` ; Living Knox s'y inscrit comme fournisseur (`LK_NotebookProvider`), RadioSurvivor y
  inscrit ses voix, son onglet Radio et ses crochets.
- **État secret** dans les fichiers privés du mod commun (carnet, missions, historique, identités, réputation), dans
  `RS_State` (voix) et dans les registres fichiers de Living Knox, jamais en ModData globale (lisible par tous les
  clients).

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
    ├── mod.info                id=batman_LivingKnox, require=\batman_CoreAI
    └── media/
        ├── sandbox-options.txt page LivingKnox
        └── lua/{client,server,shared}/LivingKnox/ + Translate/{EN,FR} (IGUI_LK_, Sandbox_LivingKnox_)
Contents/mods/batman_CoreAI/   mod commun, activé par le jeu avec l'un ou l'autre
├── common/
└── 42.21/
    ├── mod.info                id=batman_CoreAI, require=\batman_SignalSmoke, modversion=0.1.0
    └── media/lua/{client,server,shared}/CoreAI/ + Translate/{EN,FR} (IGUI_CA_)
```

Montages valides : RadioSurvivor seul, Living Knox seul, ou les deux, toujours avec le mod commun, qui seul n'apporte
rien de jouable. Le pont Python est un seul programme, sans option selon le montage.

`mod.info` de RadioSurvivor : `require=\batman_CoreAI,\batman_BeltRadio,\batman_SignalSmoke`. Living Knox :
`require=\batman_CoreAI`, `incompatible=\Bandits2,\ProjectALifeNPCs`. Le joueur coche RadioSurvivor et/ou Living Knox ;
le jeu active `batman_CoreAI` par leur `require=`. Les mods de tests `dev/batman_CoreAITests`,
`dev/batman_LivingKnoxTests` et `dev/batman_RadioSurvivorTests` ne sont jamais publiés (section 7).

## 3. Modules Lua

| Côté | Dossier | Responsabilités |
|---|---|---|
| shared (mod commun `batman_CoreAI`) | `CoreAI/` | outils partagés : codec RSV2 (`CA_Codec`), limite de débit des commandes (`CA_RateLimit`), coupe des textes (`CA_TextCut`), valeurs de troc (`CA_TradeValues`, objets vendables seulement inscrits par `registerSellOnly`), monde neuf ou relancé (`CA_WorldStart`), horloge de jeu des délais (`CA_GameClock`), fichiers privés à deux emplacements (`CA_SlotFile`), lien avec le pont (`CA_Bridge`, file `CA_Transport`), règle d'accès administrateur (`CA_AdminAccess`), audition (`CA_Hearing`) ; identité des personnages (`CA_Identity` : identité décidée par l'autorité, écrite dans sa copie de la ModData du joueur sous la clé `CA_Character`, retirée à la mort, registre privé `Zomboid/Lua/batman_CoreAI/identity-*.txt`) ; interface des fournisseurs de PNJ du carnet (`CA_NPCProvider`, opérations décrites dans [api-living-knox.md](../specifications-techniques/api-living-knox.md#fournisseur-du-carnet-lk_notebookprovider)) ; configuration du carnet (`CA_NotebookConfig` : module réseau `CoreAI`), catalogue et liste des missions (`CA_MissionConfig`, `CA_MissionList`), réputation (`CA_ReputationConfig`), parole (`CA_SpeechConfig`) |
| shared (mod `batman_RadioSurvivor`) | `RadioSurvivor/` | constantes et noms de commandes du module `RadioSurvivor` (`RadioSurvivor_Const.lua`), configuration des voix (`RS_Config` : planques, récompenses, marge du troc), notes de fréquence, journal du dehors, son du troc |
| shared (mod `batman_LivingKnox`) | `LivingKnox/` | cœur (`LK_Core`, `LK_Config`), identité et apparence, équipement, sens, mouvement, garde des corps (`LK_ZombieGuard`), types de groupes et textes (`Data/`) ; fournisseur du carnet (`LK_NotebookProvider`, global `LivingKnox.NpcProvider`, toujours inscrit quand Living Knox est actif) |
| server (mod commun `batman_CoreAI`) | `CoreAI/` | serveur du carnet (`CA_NotebookServer`, global `CoreAI.notebookServer` : fiches, contacts, sélection, parole des PNJ par le moteur du fournisseur, missions, transactions, morts, administration de la réputation ; registres `registerCommand`, `addPoll`, `hooks`) et son stock (`CA_NotebookStore`, `Zomboid/Lua/batman_CoreAI/notebook-*.txt`, purge `CA_NotebookPurge`) ; donneur `npc` des fiches de PNJ (`CA_NotebookGiver`) ; moteur de missions commun (`CA_Missions` : offres, acceptation, délais, compte rendu, lot de récompense ; donneurs inscrits par `registerDonor`, source de récompense du moteur de PNJ par `registerNpcReward`), gabarits `CA_MissionScout`, `CA_MissionClear`, `CA_MissionRecover`, `CA_MissionRetrieve`, `CA_MissionSignal` (exige Signal Smoke), `CA_MissionBarricade`, `CA_MissionRelay`, `CA_MissionWatch`, `CA_MissionRoute`, `CA_MissionItem`, missions dites en parlant (`CA_MissionTalk`), lignes du journal (`CA_MissionJournal`), état privé des missions (`CA_MissionStore`, `missions-*.txt`) ; lieux (`CA_Sites`), caches (`CA_Caches`), historique (`CA_History`), réputation (`CA_Reputation`), contacts (`CA_Contacts`, sources inscrites par `registerSource`), équipes et mandats (`CA_Teams`), faits du monde (`CA_WorldFacts`, `CA_WatchFacts`), faits publics des groupes (`CA_GroupFacts`) |
| server (mod `batman_RadioSurvivor`) | `RadioSurvivor_Server.lua`, `RadioSurvivor/` (45 fichiers) | point d'entrée du module `RadioSurvivor` ; état privé des voix (`RS_State`), transport vers le pont (`RS_BridgeLanes`, file `CA_Transport` du mod commun), voix (`RS_Persona*`), actions et missions des voix (`RS_Actions`, `RS_MissionVoice`, `RS_MissionHooks` : donneur `voice`, `RS_CacheAction`), crochets du carnet (`RS_NotebookHooks` : caches par `addPoll`, `overheard`, `callLanguage`, radio de groupe, oubli d'un personnage), secours (`RS_Rescue*`), troc (`RS_Trade*`), chronique et faits (`RS_Facts`, abonné à `CA_GroupFacts`), radio de groupe (`RS_GroupRadio`), dernières pages |
| server (mod `batman_LivingKnox`) | `LivingKnox/` | groupes et foyers, population, décisions, routines, alerte, défense, combat, santé, mort et butin, stock, fortification, simulation hors écran, récits, raids, API publique (`LK_API`), registre (`LK_Store`) ; parole des PNJ (`LK_Talk`, crochets `LK_TalkHost`), initiatives et conversations ; relations personnelles servies au carnet (`LK_NotebookRelations`), accords et incidents (`LK_Agreements`, annonces `LK_AgreementNotices` sur le module `LivingKnox`), faits publics des groupes (`LK_GroupFactsFeed` → `CA_GroupFacts`), administration (`LK_Admin`) |
| client (mod commun `batman_CoreAI`) | `CoreAI/` | le carnet (`CA_Notebook` : cadre papier, marque-pages, bouton de la barre latérale, tranche de la roue droite de la manette, registre d'onglets `registerTab` / `extendTab`, crochet `reputationExtras`) ; récepteur du module `CoreAI` (`CA_NotebookClient`, global `CoreAI.notebookClient`, registre `registerCommand` des réponses du serveur, `talk`, `talkTo`) ; un fichier par onglet commun : `CA_NotebookContacts` (raccourci `CoreAISelect`, Ctrl+G), `CA_NotebookMissions` (remise et devis), `CA_NotebookReputation` ; vues par type de mission (`CA_MissionViews`, `MissionViews/CA_View_*`, registre des donneurs `registerGiver`) ; zones des missions sur la carte (`CA_MapZones`) ; textes `IGUI_CA_` (EN, FR) |
| client (mod `batman_RadioSurvivor`) | `RadioSurvivor_Client.lua`, `RadioSurvivor/` | module « Émettre » de la fenêtre radio (`RS_RadioModule`, `RS_RadioTalk`), onglet Radio du carnet (`RS_NotebookRadio`), lignes de réputation des voix (`RS_NotebookReputation`), vues des missions des voix (`RS_VoiceMissionViews`, `RS_DeadDropLines`), historique radio, lecture des notes, repères et quartiers révélés (`RS_MapActions`), vue de debug des fréquences |
| client (mod `batman_LivingKnox`) | `LivingKnox/` | exécuteur des consignes sur le client propriétaire (`LK_Executor`), relais combat, santé, zombies, mort ; vues : fiche PNJ, administration, relations, troc, bulles ; pages du carnet (`LK_NotebookPages` : onglet Équipe, panneau de relation d'un contact) ; halos des accords et incidents (`LK_AgreementNoticesView`) ; menu « Parler » du monde (`LK_TalkView`, par `CoreAI.notebookClient.talkTo`) |

Les dépendances suivent le sens présentation/pont → contrat → décisions serveur → adaptateurs moteur. Les fichiers
serveur se gardent par `isClient()` ; les fiches de conception de chaque sous-système sont dans
[annexes/conception/](../annexes/conception/README.md).

## 4. Flux de données

- **Radio** : le joueur émet depuis la fenêtre radio vanilla → commande `RadioSurvivor`/`talk` → le serveur choisit la
  voix d'après la fréquence (tirée par partie, jamais envoyée aux clients) → demande écrite dans `requests.txt` → le pont
  appelle le LLM et écrit `responses.txt` → le serveur valide les actions de la liste fermée, puis diffuse les lignes
  sur la fréquence (`AddDeviceText`). Détails : [protocole-carnet-v2.md](../specifications-techniques/protocole-carnet-v2.md),
  [persona-format.md](../specifications-techniques/persona-format.md).
- **Carnet** : module `CoreAI` ; chaque commande est inscrite par `CA_NotebookServer.registerCommand` (`hello`,
  `snapshot`, `select`, `deselect`, `talk`, `note`, `report`, `accept`, `invite`, `abandon`, `prepare_delivery`,
  `confirm_delivery`, `claim`, `rep_admin` ; `team` et `mandate` par `CA_Teams`), une commande inconnue est ignorée ;
  réponses par `sendServerCommand`, distribuées côté client par le registre de `CA_NotebookClient`. Une phrase dite
  dans le chat « dire » sans cible sélectionnée va au PNJ le plus proche (8 cases), sinon nulle part.
- **PNJ** : décisions sur l'autorité (`EveryHours`, `OnTick`) → consignes (`LK_Directives`) → exécution par le client
  propriétaire du corps (`dirAsk`, `dirClaim`, `dirReport`, `dirState`) ; dégâts, combat et santé remontent par le
  module `LivingKnox` (`combatHit`, `combatMelee`, `combatShot`, `zombieHurt`, `bodyReport`…).
- **Événements moteur principaux** : `OnClientCommand`/`OnServerCommand`, `OnTickEvenPaused`, `OnTick`, `EveryHours`,
  `EveryTenMinutes`, `EveryOneMinute`, `OnInitGlobalModData`, `OnLoadRadioScripts`, `OnCharacterDeath`, `OnZombieDead`,
  `OnWorldSound`, `OnDeviceText`, `OnFillContainer`.
- **Faits publics des groupes** : Living Knox les émet dans `CA_GroupFacts` (`LK_GroupFactsFeed`), RadioSurvivor les
  lit sans savoir qui les écrit (`RS_Facts`) ; accords et incidents sont annoncés par Living Knox lui-même (module
  `LivingKnox`, commandes `agreement` et `incident`). Voir [api-living-knox.md](../specifications-techniques/api-living-knox.md).

## 5. Persistance

| Donnée | Support | Écrit par |
|---|---|---|
| État des voix (troc, état et mémoire des voix, faits, secours, relevés de vie, donneurs et chaînes de missions des voix, compteurs d'actions) | `Zomboid/Lua/batman_RadioSurvivor/state-<partie>-<0\|1>.txt` (en-tête `RSSTATE2`, RSV2 en hex, somme de contrôle, double emplacement), écrit après le carnet | `RS_State` |
| Carnet (personnages, fiches des PNJ, liaisons) | `Zomboid/Lua/batman_CoreAI/notebook-<partie>-<0\|1>.txt` (en-tête `CANOTEBOOK1`) | `CA_NotebookStore` |
| Registre des PNJ et des groupes | `Zomboid/Lua/batman_LivingKnox/registry-<partie>-<0\|1>.txt` (`LKREG1`), une écriture par image au plus | `LK_Store` ([corps-registre.md](../annexes/conception/corps-registre.md)) |
| État du mod commun (missions, identités, historique des échanges, réputation) | `Zomboid/Lua/batman_CoreAI/` : `missions-*`, `identity-*`, `history-*`, `reputation-*` (fichiers privés à deux emplacements, `CA_SlotFile`) | `CA_MissionStore`, `CA_Identity`, `CA_History`, `CA_Reputation` |
| Échange avec le pont | `Zomboid/Lua/batman_CoreAI/` : `requests.txt`, `responses.txt`, `bridge-alive.txt`, `bridge.lock` | serveur / pont |
| Fiches de voix | `Zomboid/Lua/batman_RadioSurvivor/personas/` (RadioSurvivor actif seulement) | `RS_Personas` |
| Données d'objets et de PNJ | ModData d'objet et de corps (marques d'idempotence, identité) | serveur |

Un schéma inconnu ou deux fichiers illisibles bloquent l'écriture (fichiers conservés). Un monde neuf
(`OnInitGlobalModData(true)`) repart d'un registre vide. Aucune reprise des parties d'avant la séparation : les mods ne
sont pas publiés avec une sauvegarde à reprendre.

## 6. Points d'extension et intégrations

- **Registres de `batman_CoreAI`**, seuls points de contact entre RadioSurvivor et Living Knox :

  | Registre | Rôle | Inscrit par |
  |---|---|---|
  | `CA_NPCProvider.register` et ses opérations | PNJ du carnet : corps, fiches, contexte, parole (`speech`), relations (`relationOffer`, `relationApply`, `relationPanel`), contacts, `isBody` | Living Knox (`LK_NotebookProvider`) |
  | `CA_NotebookServer.registerCommand`, `addPoll`, `hooks` (`overheard`, `claim`, `callLanguage`) | commandes du module `CoreAI`, passes d'une seconde, crochets du serveur du carnet | commun ; RadioSurvivor (`RS_NotebookHooks`) |
  | `CA_NotebookClient.registerCommand` | réponses du serveur du carnet côté client | commun |
  | `CA_Notebook.registerTab` / `extendTab`, `reputationExtras`, `contactPages` | onglets et lignes du carnet | RadioSurvivor (Radio), Living Knox (Équipe, relations) |
  | `CA_MissionViews.register`, `registerGiver(kind, {remote, sections, reportLine})` | vues des missions par gabarit et par donneur | commun ; RadioSurvivor (`RS_VoiceMissionViews`) |
  | `CA_Missions.registerDonor`, `registerNpcReward`, `register` | donneurs, source de récompense des PNJ, gabarits | commun ; RadioSurvivor (voix) ; Living Knox (`LK_MissionRewards`) |
  | `CA_GroupFacts.on` / `emit` | faits publics des groupes (`member_died`, `group_gone`, `group_created`) | Living Knox émet, RadioSurvivor lit |
  | `CA_TradeValues.registerSellOnly` | objets vendables seulement | RadioSurvivor |
  | `CA_Contacts.registerSource`, `CA_Transport.register` | sources de contacts, voies de la file du pont | chaque mod |

- **API publique Living Knox** (`LivingKnox.API`, version 1) : lecture des groupes, événements publics, demandes de
  ressources, journal de récit : [api-living-knox.md](../specifications-techniques/api-living-knox.md).
- **Fiches de voix** éditables par l'admin, relues à chaud : [persona-format.md](../specifications-techniques/persona-format.md)
  et le guide [Créer une voix radio](../wiki/fr/10-creer-une-voix-radio.md).
- **Belt Walkie-Talkie** et **Signal Smoke** (prérequis) : talkie à la ceinture, fumées et fusées des missions.
- **Incompatibles** : Bandits! et Project A-Life (deux moteurs de PNJ concurrents, voir [ia-multijoueur.md](ia-multijoueur.md)).

## 7. Outillage

| Outil | Rôle |
|---|---|
| `tests/run_all.py` | tous les bancs hors jeu (lupa, VM Kahlua réelle `tests/coreai/test_kahlua.py`, luacheck avec base `tests/luacheck_baseline.txt`) |
| `tests/commun/harness.py` | serveur et deux clients simulés sous lupa (ne valide pas l'API Java réelle) |
| `dev/batman_CoreAITests` (moteur RST, suites `ca.*`), `dev/batman_LivingKnoxTests` (`lk.*`), `dev/batman_RadioSurvivorTests` (`rs.*`) + `tools/autoclient/autoclient.py` | tests en jeu RST : campagnes `solo-lk` (Living Knox seul), `solo-rs`, `solo` (les deux), `mp` (serveur dédié avec deux clients pilotés) ; résultats dans `Zomboid/Lua/batman_CoreAITests/tests/` ; méthode dans [tests-en-jeu.md](../annexes/tests/tests-en-jeu.md) |
| `autotest.json` | configuration du lanceur générique `pz-autotest` |
| `tools/plan.py` | plan d'implémentation : `check`, `suivi`, `next`, `show` ([annexes/plans/](../annexes/plans/README.md)) |
| `tools/features_status.py` | colonnes Solo/MP de [fonctionnalites.html](../annexes/maquettes/fonctionnalites.html) depuis le plan |
| `tools/gen_animsets.py`, `tools/gen_notebook_textures.py` | génération des AnimSets et des textures du carnet |
| `tools/make_test_zip.py` | zip de test local sans le Workshop |

Aucune CI GitHub (`.github/` absent) : les contrôles sont locaux.
