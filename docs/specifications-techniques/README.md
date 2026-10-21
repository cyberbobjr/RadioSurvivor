# Spécifications techniques de Radio Survivor

Contrats précis du mod `batman_RadioSurvivor` 0.3.0. Cible : **Project Zomboid 42.21** (`versionMin=42.21`, variante
unique `42.21/`) ; aucune autre Build n'est validée. Vue d'ensemble : [architecture](../architecture/README.md) ;
comportement vu du joueur : [spécifications fonctionnelles](../specifications-fonctionnelles/README.md).

## Contrats détaillés

| Document | Contrat |
|---|---|
| [protocole-carnet-v2.md](protocole-carnet-v2.md) | Échange Lua ↔ pont Python v2 : enveloppe, réponse radio structurée et actions en liste fermée, codec RSV2, demandes PNJ, mémoire et acquittement, dépôt discret des livraisons |
| [api-living-knox.md](api-living-knox.md) | API publique `LivingKnox.API` version 1 : constantes, fonctions, journal de récit, demandes d'aide, faits publiés, événements publics, fonctions de test |
| [persona-format.md](persona-format.md) | Fiches des voix radio (format 1) : champs, chargement serveur, tirage des fréquences, routage, appels spontanés, secrets, erreurs |
| [reputation-contract.md](reputation-contract.md) | Contrat RSREP-1 avec CharacterReputation (facultatif) |
| [passeur-table.md](passeur-table.md) | Barème de troc du passeur et des groupes Living Knox (identifiants vanilla 42.21, poids) |
| [factions.md](factions.md) | Équipes et mandats de négociation (`RS_Factions`) |
| [rescue.md](rescue.md) | Survivants à secourir : tirage du bâtiment, indices, réserves, issues (`RS_Rescue*`) |
| [notes-frequences.md](notes-frequences.md) | Notes de fréquences : transport de la fréquence, butin |

Les fiches de conception des sous-systèmes Living Knox (choix, contraintes du moteur, persistance, tests) sont dans
[annexes/conception/](../annexes/conception/README.md) ; le registre des PNJ est décrit dans
[corps-registre.md](../annexes/conception/corps-registre.md).

## Objets et scripts

Module `RadioSurvivor` (`media/scripts/`) : `RadioSurvivor.NoteWalt`, `RadioSurvivor.NoteDarlene`,
`RadioSurvivor.NoteCody`, `RadioSurvivor.NoteGus`, `RadioSurvivor.NoteNightOwl` (notes de fréquences, `literature` sans
`CanBeWrite`, document `printMedia`) et `RadioSurvivor.OutsideNews` (journal du dehors apporté par le passeur). Les
autres objets créés par le mod (caches, dernières pages, butin des PNJ) sont des objets vanilla.

## Commandes réseau

Noms définis dans le code ; arguments et contrôles serveur dans les documents cités.

| Module | Commandes | Sens | Définition |
|---|---|---|---|
| `RadioSurvivor` | `talk`, `heard`, `history`, `note_read` | client → serveur | `RadioSurvivor_Const.lua` (`Const.CMD`), traitées dans `RadioSurvivor_Server.lua` |
| `RadioSurvivor` | `accepted`, `rejected`, `done`, `history_lines`, `history_add`, `map_mark`, `map_reveal`, `comfort` | serveur → client | idem |
| `RS_Carnet` | `report`, `accept`, `invite`, `abandon`, `prepare_delivery`… | client → serveur | `RS_Carnet_Server.lua` ([protocole-carnet-v2.md](protocole-carnet-v2.md)) |
| `RadioSurvivorDebug` | `freqRequest` / `freqReply` | client admin ↔ serveur | `RS_FreqDebug.lua` ([persona-format.md](persona-format.md), « Panneau de debug ») |
| `LivingKnox` | `dirAsk`, `dirClaim`, `dirReport` / `dirState`, `npcHand` (passage à un nouveau propriétaire) | client propriétaire ↔ serveur | `LK_Directives`, `LK_Executor` |
| `LivingKnox` | `combatState`, `combatHit`, `combatShot`, `combatMelee`, `zombieHurt`, `zombieThumps`, `bodyReport`, `bodyGone`, `corpseCheck`, `corpseMissing` | client ↔ serveur | `LK_CombatClient`, `LK_ZombiesClient`, `LK_DeathClient`, `LK_Senses` |
| `LivingKnox` | `animState`, `equipState`, `guardRoster` (réponse à `guardHello`) | serveur → clients proches | `LK_Anim`, `LK_Equipment`, `LK_ZombieGuard` |
| `LivingKnox` | `adminRequest` / `adminReply`, `tradeRequest` / `tradeReply`, `aidRequest` | client ↔ serveur | vues admin, fiche PNJ, troc, relations ; capacité d'administration vérifiée côté serveur |

Toute commande client est revérifiée par le serveur (distance, propriété, capacité) ; aucune n'attribue directement un
objet ou une récompense.

## Fichiers et persistance

Dossier d'échange : `Zomboid/Lua/batman_RadioSurvivor/` (ou `<cachedir>/Lua/batman_RadioSurvivor` pour un serveur
lancé avec `-cachedir`).

| Fichier | Format |
|---|---|
| `requests.txt`, `responses.txt` | demandes et réponses du pont ([protocole-carnet-v2.md](protocole-carnet-v2.md)) |
| `bridge-alive.txt`, `bridge.lock` | battement de cœur et verrou du pont |
| `personas/<voix>.txt` | fiches des voix installées par le serveur ([persona-format.md](persona-format.md)) |
| `state-<partie>-<0\|1>.txt` | état `RS_State` : `RSSTATE2=<génération>`, octets RSV2 en hex, somme de contrôle, `end` ; `schema = 2` |
| `livingknox/registry-<partie>-<0\|1>.txt` | registre Living Knox : `LKREG1=<n>`, même enveloppe ; migration par `Identity.upgrade` |

`<partie>` = hex du « mode/nom » de la partie. Aucune donnée secrète en ModData globale.

## Options sandbox

Pages `RadioSurvivor` et `LivingKnox` de `media/sandbox-options.txt` (47 options ; effet de chacune :
[wiki](../wiki/fr/09-options-sandbox.md)).

| Option | Type | Défaut | Bornes | Libellé (FR) |
|---|---|---|---|---|
| `RadioSurvivor.Enabled` | boolean | true | — | Activer le survivant à la radio |
| `RadioSurvivor.PlayerCooldown` | integer | 10 | 0–600 | Délai entre deux messages d'un joueur (secondes) |
| `RadioSurvivor.MaxPerHour` | integer | 60 | 0–1000 | Messages par heure, tous joueurs (0 = illimité) |
| `RadioSurvivor.SpontaneousCalls` | boolean | true | — | Appels spontanés |
| `RadioSurvivor.CallLanguage` | enum | 1 | 1–3 | Langue des appels spontanés |
| `RadioSurvivor.NoteRarity` | enum | 3 | 1–4 | Notes de fréquences dans le butin |
| `RadioSurvivor.ChronicleHour` | integer | 20 | 0–23 | Heure du bulletin du soir |
| `RadioSurvivor.LastPages` | boolean | true | — | Dernières pages des morts |
| `RadioSurvivor.InitiativeFrequency` | enum | 3 | 1–4 | Initiatives des PNJ |
| `RadioSurvivor.RescueDays` | integer | 3 | 1–10 | Jours de réserves d'un groupe à secourir |
| `RadioSurvivor.ComfortBoredom` | integer | 3 | 0–20 | Ennui apaisé par une réponse radio |
| `RadioSurvivor.ComfortSadness` | integer | 1 | 0–20 | Tristesse apaisée par une réponse radio |
| `RadioSurvivor.ComfortListen` | integer | 1 | 0–20 | Ennui apaisé en écoutant des survivants |
| `RadioSurvivor.ComfortPerHour` | integer | 5 | 0–20 | Réconforts par la parole par heure |
| `LivingKnox.Enabled` | boolean | true | — | Activer le moteur de PNJ Living Knox |
| `LivingKnox.Debug` | boolean | false | — | Journal de débogage Living Knox |
| `LivingKnox.GroupCount` | integer | 4 | 3–5 | Nombre de groupes de survivants |
| `LivingKnox.WeightSettlers` | integer | 40 | 0–100 | Part des groupes de colons |
| `LivingKnox.WeightRaiders` | integer | 35 | 0–100 | Part des groupes de pillards |
| `LivingKnox.WeightNeutrals` | integer | 25 | 0–100 | Part des groupes neutres |
| `LivingKnox.GroupSizeMin` | integer | 4 | 4–8 | Membres par groupe, au moins |
| `LivingKnox.GroupSizeMax` | integer | 8 | 4–8 | Membres par groupe, au plus |
| `LivingKnox.ReliefDaysMin` | integer | 2 | 2–5 | Jours avant l'arrivée d'un nouveau groupe, au moins |
| `LivingKnox.ReliefDaysMax` | integer | 5 | 2–5 | Jours avant l'arrivée d'un nouveau groupe, au plus |
| `LivingKnox.ZombieAlertDistance` | integer | 10 | 1–30 | Distance d'alerte pour un zombie (cases) |
| `LivingKnox.AlertReach` | integer | 20 | 5–60 | Portée de l'alerte (cases) |
| `LivingKnox.AlertShoutZombie` | integer | 10 | 1–30 | Rayon du cri d'alerte pour un zombie (cases) |
| `LivingKnox.FleeDistance` | integer | 4 | 1–20 | Distance de fuite d'un non-combattant (cases) |
| `LivingKnox.FleeDistanceAfraid` | integer | 8 | 1–30 | Distance de fuite d'un non-combattant apeuré (cases) |
| `LivingKnox.ZombieEngageDeputy` | integer | 10 | 1–15 | Distance d'engagement d'un zombie : second (cases) |
| `LivingKnox.ZombieEngageFighter` | integer | 10 | 1–15 | Distance d'engagement d'un zombie : combattant (cases) |
| `LivingKnox.ZombieEngageScout` | integer | 10 | 1–15 | Distance d'engagement d'un zombie : éclaireur (cases) |
| `LivingKnox.ZombieEngageMedic` | integer | 10 | 1–15 | Distance d'engagement d'un zombie : soignant (cases) |
| `LivingKnox.ZombieEngageWorker` | integer | 10 | 1–15 | Distance d'engagement d'un zombie : ouvrier (cases) |
| `LivingKnox.ZombieEngageBreaker` | integer | 10 | 1–15 | Distance d'engagement d'un zombie : casseur (cases) |
| `LivingKnox.DefenseRadius` | integer | 8 | 3–30 | Rayon de défense du foyer (cases) |
| `LivingKnox.DefenseWithdrawRatio` | integer | 3 | 2–10 | Rapport de repli de la défense |
| `LivingKnox.RetreatDangerDistance` | integer | 8 | 2–30 | Distance de danger pour la retraite (cases) |
| `LivingKnox.ReinforcementRadius` | integer | 15 | 3–50 | Rayon des renforts (cases) |
| `LivingKnox.WarnHomeRadius` | integer | 14 | 4–30 | Rayon des sommations autour du foyer (cases) |
| `LivingKnox.WarnGroupRadius` | integer | 10 | 2–30 | Rayon des sommations autour d'un membre (cases) |
| `LivingKnox.WoundedHealth` | integer | 50 | 10–90 | Seuil blessé (pour cent de la santé) |
| `LivingKnox.AfraidFear` | integer | 70 | 30–100 | Seuil apeuré (peur de 0 à 100) |
| `LivingKnox.RaidsEnabled` | boolean | true | — | Raids des pillards sur les bases des joueurs |
| `LivingKnox.RaidDays` | integer | 14 | 3–90 | Jours entre deux raids |
| `LivingKnox.RevengeDelayHours` | integer | 72 | 12–336 | Heures avant une vengeance |
| `RadioSurvivor.LessonMultiplier` | double | 1 | 0–5 | Multiplicateur XP des leçons de mission |

## Traductions

`media/lua/shared/Translate/EN` et `FR` (JSON seulement en 42.21) : `IG_UI.json` (préfixes `IGUI_RS_`, `IGUI_LK_`,
`IGUI_RadioSurvivor_`), `Sandbox.json` (`Sandbox_RadioSurvivor_`, `Sandbox_LivingKnox_`), `Print_Media.json` et
`Print_Text.json` (documents des notes et des dernières pages), `ItemName.json`, `UI.json` (`UI_optionscreen_`, touche
de sélection d'un PNJ). Les textes destinés au joueur passent par ces clés ; les messages de journal sont en anglais.
La langue des voix suit `CallLanguage` (langue du serveur, anglais, français).

## Dépendances et compatibilité

| Mod | Relation | Déclaration |
|---|---|---|
| Belt Walkie-Talkie (`batman_BeltRadio`) | prérequis | `require=` |
| Signal Smoke (`batman_SignalSmoke`) | prérequis (fumées, fusées des missions) | `require=` |
| CharacterReputation (`batman_CharacterReputation`) | facultatif | `loadModAfter=`, contrat [RSREP-1](reputation-contract.md) |
| Bandits! (`Bandits2`), Project A-Life (`ProjectALifeNPCs`) | incompatibles | `incompatible=` |
