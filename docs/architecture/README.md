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
[decisions/](decisions/README.md) et [AGENTS.md](../../AGENTS.md)) :

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
├── common/                     requis en B42 ; media/AnimSets (nœuds d'animation des corps de PNJ, générés par tools/gen_animsets.py)
└── 42.21/                      seule variante
    ├── mod.info                id=batman_RadioSurvivor, versionMin=42.21, modversion=0.3.0
    ├── personas/               fiches des six voix livrées (walt, darlene, cody, whitaker, nightowl, gus)
    └── media/
        ├── sandbox-options.txt pages RadioSurvivor et LivingKnox
        ├── scripts/            objets du module RadioSurvivor (notes de fréquence, journal du dehors)
        ├── textures/RadioSurvivor/
        └── lua/{client,server,shared}/{RadioSurvivor,LivingKnox}/ + Translate/{EN,FR}
```

`mod.info` : `require=\batman_BeltRadio,\batman_SignalSmoke` (prérequis), `loadModAfter=\batman_CharacterReputation`
(intégration facultative), `incompatible=\Bandits2,\ProjectALifeNPCs`. Le mod de tests `dev/batman_RadioSurvivorTests`
n'est jamais publié.

## 3. Modules Lua

| Côté | Dossier | Responsabilités |
|---|---|---|
| shared | `RadioSurvivor/` | constantes et noms de commandes (`RadioSurvivor_Const.lua`), codec RSV2 (`RS_Codec`), interface `RS_NPCProvider` et son implémentation Living Knox (`RS_LivingKnox`), notes, valeurs de troc, coupe des textes |
| shared | `LivingKnox/` | cœur (`LK_Core`, `LK_Config`), identité et apparence, équipement, sens, mouvement, garde des corps (`LK_ZombieGuard`), types de groupes et textes (`Data/`) |
| server | `RadioSurvivor_Server.lua`, `RS_Carnet_Server.lua` | points d'entrée : commandes client, carnet, livraisons |
| server | `RadioSurvivor/` (47 fichiers) | état privé (`RS_State`), transport vers le pont (`RS_Transport`), voix (`RS_Persona*`), actions et missions (`RS_Actions`, `RS_Mission*`), secours (`RS_Rescue*`), troc (`RS_Trade*`), chronique et faits, dernières pages, réputation, équipes (`RS_Factions`) |
| server | `LivingKnox/` (43 fichiers) | groupes et foyers, population, décisions, routines, alerte, défense, combat, santé, mort et butin, stock, fortification, simulation hors écran, récits, relations, raids, API publique (`LK_API`), registre (`LK_Store`) |
| client | `RadioSurvivor_Client.lua`, `RS_Carnet_Client.lua`, `RadioSurvivor/` | module « Émettre » de la fenêtre radio, carnet, historique radio, lecture des notes, actions de carte, vue de debug des fréquences |
| client | `LivingKnox/` | exécuteur des consignes sur le client propriétaire (`LK_Executor`), relais combat, santé, zombies, mort ; vues : fiche PNJ, administration, relations, troc, bulles |

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
