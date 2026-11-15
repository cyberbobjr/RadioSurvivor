# Carnet commun dans batman_CoreAI : conception des tâches E21-T03 à E21-T06

Conception du 2026-11-15 pour le plan [E21](../plans/E21-separation-coreai.md), qui applique l'ADR
[Living Knox et RadioSurvivor séparés autour de batman_CoreAI](../../architecture/decisions/adr-coreai-separation.md).
Les numéros de ligne datent du commit `a7d0453`.

## Constats

1. **Le commun a déjà un second chemin de carnet.**
   - `CA_Notebook.lua` interroge `missions`, `contacts` et `reputation` par `CA_MissionJournal`. Il a sa propre page
     Missions (`CA_Notebook.lua:785-990`, avec `CA_UI_Delivery`).
   - `RS_Notebook` remplace ces onglets par l'instantané du serveur RS (`extendTab`, `RS_Notebook.lua:443-566`).
   - Il y a donc deux doubles chemins : `LK_TalkAlone` face à `RS_Carnet_Server`, et le journal commun face à
     l'instantané RS.
2. **`RS_State` mêle deux stocks.**
   - Données du carnet : `characters`, `npcs`, `bindings`, `world`.
   - Données des voix : `trade`, `personaState`, `memory`, `facts`, `rescues`, `lifelogs`, `voiceDonors`,
     `voiceTeamChains`, `voiceStory`, `actionCounters`.
3. **`RS_GroupRadio` consomme aussi la parole.** Il passe par `RS_CarnetServer.talk/contact/acquaintance/ensure/bound/publish`
   (`RS_GroupRadio.lua:118-210`).
4. **Le donneur de missions `npc` est inscrit deux fois.** Il l'est dans `RS_MissionHooks.lua:118-130` et dans
   `LK_TalkAlone.lua:350-367`.

## Répartition

### `RS_Carnet_Server.lua` → `server/CoreAI/CA_NotebookServer.lua` et `CA_NotebookStore.lua`

**Tout le fichier passe dans le commun** : identité, fiches, contacts (source `npc`), instantané, sélection, parole,
missions, transactions, commandes, morts, administration de la réputation, purge, `tick`, `init`, contexte et actions
de parole, `HOST`, mort d'un personnage.

**Ce qui est retiré :**
- `Agreements()` (l. 22) ;
- le tic des accords (l. 589-591) : `LK_Agreements` tourne déjà seul ;
- `incidentDecided` (l. 764-769) ;
- `announce` (l. 786-795) : devient `LK_AgreementNotices` dans Living Knox.

**Ce qui est rendu neutre :**
- `killerCharacter` (l. 430-444) : `CA_Identity` et la liste des joueurs en ligne, sans `LK.Relations` ni `LK.Hostility` ;
- `missionFor` (l. 309-312) : drapeau `remote` du donneur, à la place de `donor == 'voice'` ;
- la règle d'accès de `reputationAdmin` : factorisée dans `shared/CoreAI/CA_AdminAccess.lua` (copiée aujourd'hui
  dans 7 fichiers).

**Ce que RadioSurvivor inscrit par registre** (`RS_NotebookHooks.lua`) :
- `RS_CacheAction` et `Caches.poll`, par `Server.addPoll` ;
- `overheard` (`RS_Comfort`), `callLanguage` et la revendication de la radio de groupe, par `Server.hooks` ;
- l'oubli de `RS_Memory` et de l'historique radio, par `CA_Identity.onRetire`.

**Ce que fournit Living Knox, par `CA_NPCProvider`** :
- `Relations.offer` et `Relations.panel` (l. 207, 633, 748) : `relationOffer`, `relationApply`, `relationPanel` ;
- `Server.talk` (l. 773-782) : `P.speech()`.

Les commandes passent par un registre (`Server.registerCommand(name, fn, limit)`) ; une commande inconnue est
ignorée.

### `RS_MissionHooks.lua`

- **Dans le commun :** `engineReward`, `npcGiver` (plus `near`), `onResult`, `onPruned`, `characterName`,
  `knownMissions`, `binding`, `publish`.
- **Reste dans RadioSurvivor :** `voiceGiver` (plus `remote = true`), `onVoiceResult`, et la partie voix de `attach`.
- `voiceGiver.find`, `RS_MissionVoice.donor` et `RS_MissionChain.record` lisent `RS_State.data` explicitement.

### Configuration et stocks

- **`RS_Config` :**
  - `MODULE`, `VERSION`, `DELIVERY_RANGE`, `SAVE_INTERVAL_MS`, `SNAPSHOT_*`, `NPC_UNSEEN_MS` et `PRUNE_INTERVAL_MS`
    vont dans `shared/CoreAI/CA_NotebookConfig.lua` (module `CoreAI`) ;
  - `DeadDrops`, `Rewards` et `TradeMargin` restent dans RadioSurvivor.
- **`RS_State` :**
  - `CA_NotebookStore` (sur `CA_SlotFile`) garde `{schema, world, uidCounter, characters, npcs, bindings}` ;
  - les missions et l'historique sont enregistrés d'abord, comme aujourd'hui ;
  - le purgeur des personnages morts appelle `CA_NotebookStore.onPurge(fn)` ;
  - `RS_State` ne garde que les données des voix ;
  - consommateurs à basculer : `RS_LifeLog`, `RS_RadioLog`, `RS_Memory`, `RS_GroupRadio`, `RS_MissionVoice`,
    `RS_VoiceBonds` et `RS_Facts`.

### Interface des fournisseurs

`RS_NPCProvider.lua` devient `shared/CoreAI/CA_NPCProvider.lua`, avec le journal `[CA_NPCProvider]` et la bulle
`CA_Speech`. Il gagne des opérations facultatives, vides par défaut :

| Opération | Rôle |
|---|---|
| `isBody(object, modData)` | reconnaît le corps d'un PNJ |
| `speech()` | moteur de parole |
| `relationOffer`, `relationApply`, `relationPanel`, `debugPair` | relations avec les PNJ |
| `contacts(character)` | PNJ connus par une relation seulement (décision 2) |
| `name` | clé de la page de contact |

### Relations

`RS_Relations.lua` devient `server/LivingKnox/LK_NotebookRelations.lua`. `R.extra` lit `CA_MissionStore`.

### Client

- **`RS_Client.lua` devient `client/CoreAI/CA_NotebookClient.lua`**, avec le global `CoreAI.notebookClient` et un
  registre des commandes client.
  - Les halos des accords et des incidents vont dans `client/LivingKnox/LK_AgreementNotices.lua`.
  - `RS_Carnet_Client.lua` est supprimé.
- **`RS_Notebook.lua` est réparti.**
  - L'onglet Radio devient `RS_NotebookRadio.lua`.
  - Le commun reçoit un fichier par onglet : `CA_NotebookContacts`, `CA_NotebookMissions` (remise et devis compris,
    remplace `CA_Notebook.lua:785-990`) et `CA_NotebookReputation`.
  - Les lignes de confiance personnelle passent par le crochet `Notebook.reputationExtras`, rempli par Living Knox.
  - Le raccourci Ctrl+G devient `CoreAISelect`.
  - Les clés génériques `IGUI_RS_*` deviennent `IGUI_CA_*`.
- **Vues de missions.**
  - `RS_MissionViews` et `MissionViews/RS_View_*` deviennent `CA_MissionViews` et `CoreAI/MissionViews/CA_View_*`.
  - Un registre `registerGiver(kind, {remote, sections, reportLine})` remplace les `if ctx.voice`.
  - Les lignes propres aux voix (`RS_DeadDropLines`) sont inscrites par `RS_VoiceMissionViews.lua`.
- **Carte.** Les zones de `RS_MapActions` (l. 173-282) deviennent `CA_MapZones.lua` ; `mark` et `reveal` restent
  dans RadioSurvivor.

## Un seul chemin pour Living Knox

- **`CA_NotebookServer` héberge seul la parole des PNJ.**
- **L'adaptateur devient `shared/LivingKnox/LK_NotebookProvider.lua`.**
  - Il s'inscrit toujours, que RadioSurvivor soit actif ou non.
  - `speech()` rend `LivingKnox.Talk`.
  - `LK_Admin` lit `LivingKnox.NpcProvider`.
- **Ce qui disparaît :**
  - `LK_TalkAlone.lua` et `LK_Contacts.lua` ;
  - le protocole `npcSay`, `talkRefused`, `talkSpeech` et `talkOffer` de `LK_TalkView`, qui ne garde que le menu
    « Parler » (`CoreAI.notebookClient.talkTo`) ;
  - `LivingKnox.radioSurvivorActive` ;
  - le module `RS_Carnet` ;
  - les commandes client de `CA_MissionJournal`, qui ne garde que les constructeurs de lignes.

**Décisions confirmées par défaut (2026-11-15) :**

1. Une phrase dite sans cible sélectionnée va au PNJ le plus proche. Personne à portée : rien ne part, sans message.
   C'est le comportement de Living Knox seul aujourd'hui.
2. Les PNJ connus seulement par une relation personnelle restent dans les contacts : opération `contacts` du
   fournisseur.

## Ce que RadioSurvivor lit de Living Knox, par le commun

| Aujourd'hui | Demain |
|---|---|
| `RS_Facts` : événements `OnLivingKnox…` et `LK.API.getGroup` | `server/CoreAI/CA_GroupFacts.lua` (`on`, `emit` ; `member_died`, `group_gone`, `group_created`, avec le nom lisible du groupe), alimenté par `LK_GroupFactsFeed.lua` |
| relations | opérations `relation*` de `CA_NPCProvider` |
| accords et incidents annoncés | Living Knox seul, sur le module `LivingKnox` |
| tueur d'un PNJ | `CA_Identity` |
| `CA_MissionClear` : `LivingKnox.Identity.readTag` | `CA_NPCProvider.isBody` |
| `RS_GroupRadio` : `Server.talk` | `CoreAI.notebookServer.talk` |

Aucune fonction de jeu n'est retirée.

## Modules réseau et fichiers

**Modules réseau :**
- `CoreAI` : seul module du carnet, avec ses commandes, ses réponses et ses limites de débit.
- `LivingKnox` : gagne `agreement` et `incident`.
- `RS_Carnet` : supprimé.

**Fichiers :**

| Fichier | Contenu |
|---|---|
| `Zomboid/Lua/batman_CoreAI/notebook-<monde>-<0\|1>.txt` | nouveau, en-tête `CANOTEBOOK1` |
| `Zomboid/Lua/batman_CoreAI/missions-…` et `history-…` | inchangés |
| `Zomboid/Lua/batman_RadioSurvivor/state-…` | données des voix seulement |

Aucune reprise de sauvegarde : les mods ne sont pas publiés.

## Tranches (une par sous-agent, test rouge d'abord)

| # | Tâche | Tranche |
|---|---|---|
| 0 | — | Aucun test d'isolement (règle de l'utilisateur : aucun test qui vérifie qu'un nom retiré ne revient pas) ; l'isolement se constate par `rg` dans la preuve de chaque tâche. Les assertions existantes de ce type qui cassent sont supprimées, pas réécrites |
| 1 | E21-T03 | `CA_NPCProvider` |
| 2 | E21-T03 | `CA_MissionViews` et registre des donneurs |
| 3 | E21-T03 | `CA_MapZones` |
| 4 | E21-T03 | registre des commandes et module `CoreAI` (`CA_NotebookConfig`) |
| 5 | E21-T03 | `CA_NotebookClient` |
| 6 | E21-T03 | onglets du carnet dans le commun, `RS_NotebookRadio` |
| 7 | E21-T04 | opérations du fournisseur côté Living Knox (`LK_NotebookRelations`, `isBody`, `speech`), tueur neutre |
| 8 | E21-T04 | `LK_AgreementNotices` |
| 9 | E21-T04 | `RS_NotebookHooks` |
| 10 | E21-T04 | `CA_NotebookStore`, à couper en deux si besoin |
| 11 | E21-T04 | déplacement du serveur dans `CA_NotebookServer`, `CA_AdminAccess` |
| 12 | E21-T05 | `LK_NotebookProvider` toujours inscrit |
| 13 | E21-T05 | un seul chemin de parole (suppression de `LK_TalkAlone` et de `LK_Contacts`) |
| 14 | E21-T06 | `CA_GroupFacts` et `LK_GroupFactsFeed` |
| 15 | E21-T06 | balayage : plus aucun nom de l'autre mod (`rg`), journaux `[CoreAI] notebook` |

**Risques :**
- en solo, le récepteur client `CoreAI.notebookClient` doit exister avant le premier `hello` ;
- l'inscription du fournisseur, à `OnInitGlobalModData`, précède l'initialisation du serveur commun ;
- les identifiants de mission d'une partie Living Knox seul changent (pas de reprise) ;
- Kahlua : déplacements à l'identique, sans nouveau motif.
