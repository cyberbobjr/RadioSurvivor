# Bandits! : analyse pour un « monde vivant » de groupes persistants

Copie inspectée **en lecture seule** le 2026-10-03 : Workshop `3268487204`, `id=Bandits2`, auteur Slayer, variante `42.20` (seule variante, chargée par 42.21) et `common/`. Chemins relatifs à `mods/Bandits/42.20/media/lua/` sauf mention. Les numéros de ligne valent pour cette copie et se revérifient après une mise à jour de Bandits!.

## Résumé

| Besoin du monde vivant | Ce que Bandits! fournit | Conséquence |
|---|---|---|
| Couper les apparitions aléatoires | 3 générateurs serveur, fonctions `local` non désinscriptibles | Neutralisables sans toucher aux fichiers (§1) |
| Faire apparaître un groupe choisi | `BanditServer.Spawner.Clan` (programme, points, `key` libre) | Utilisable, contraintes §2 |
| Un foyer, une routine | Rien n'exploite `bornCoords` ; routines horaires seulement dans `Camper` et `Defend` | Programme propre à écrire (§3) |
| Des besoins (nourriture, soins, munitions) | Absents ; seulement `BanditBrain.IsOutOfAmmo` | Modèle propre côté serveur (§5) |
| Une organisation (chef, membres) | Clan = un `cid` ; aucun registre de groupe | Registre propre, `brain.key` = identifiant de groupe (§4) |
| Vie hors de portée des joueurs | Aucune simulation (sauf errants abstraits) | Simulation abstraite propre si voulue (§5) |
| Groupe décimé → nouveau groupe | Aucun événement de mort ; commande `BanditRemove` enveloppable | Détection propre (§4) |
| Relations par joueur | `hostile` / `hostileP` valent pour tous les joueurs | Limite connue (E09) |

## 1. Apparitions automatiques et neutralisation

- **A. `checkEvent`** toutes les 10 minutes de jeu (`server/BanditServerSpawner.lua:1067-1137`, inscrit `:1227`) : pour chaque clan de `BanditCustom.ClanGetAll()` (`:1089`), fenêtre `dayStart..dayEnd`, chance `spawnChance × General_SpawnMultiplier / 6` (`:1111`), puis `spawnType` à 60-74 cases d'un joueur (`:979-1065`, points `:161-257`). Programme choisi par les drapeaux du clan : `assault`, `roadblock`, `campers`, `defenders`, `companion` (`:1016-1044`).
- **B. Orchestrateur des errants** toutes les 10 minutes (`server/BanditServerWanderers.lua:727-794`, `:797`) : clans `wanderer`, appelle `BanditServer.Wanderers.AddGroup` (champ de table, `:365-384`, plafond 100 groupes).
- **C. `updateGroups`** chaque minute (`BanditServerWanderers.lua:513-725`, `:796`) : déplace les groupes abstraits, les fait combattre, et les matérialise près d'un joueur en **tuant tous les zombies à 30 cases, bandits compris** (`:651-662`).
- Code mort : `BanditPermanent` (`client/BanditPermanent.lua:8`), `BanditSquareLoader` (`client/BanditSquareLoader.lua:65`), `BanditScenes` (cassées, programme `BaseGuard` et commande `SpawnGroup` inexistants).
- **Neutralisation sans modifier Bandits!** (appliquer à un événement, pas au chargement du fichier : `BanditServerSpawner.lua:1156` fait `BanditServer.Spawner = {}`) :
  - A et B : remplacer côté serveur `BanditCustom.ClanGetAll` par une fonction qui renvoie `{}` ; ses seuls appelants sont les deux générateurs (`BanditServerSpawner.lua:1089`, `BanditServerWanderers.lua:747`). `Spawner.Clan` et `Spawner.Type` utilisent `ClanGet` et continuent de fonctionner.
  - B, par sûreté : `BanditServer.Wanderers.AddGroup` sans effet.
  - C : vider en place `GetBanditModData().Wanderers` après `OnInitGlobalModData` (`shared/BanditGMD.lua:115`).
  - Alternative par données : `General_OriginalBandits = false` et clans du sous-mod à `spawnChance = 0`. `General_SpawnMultiplier` ne descend pas sous 0,25 (`sandbox-options.txt:10-13`).

## 2. Faire apparaître un groupe

- `BanditServer.Spawner.Clan(player, args)` (`BanditServerSpawner.lua:1167-1185`) : `cid`, `program` (défaut `Bandit`), `spawnPoints = {{x, y, z}, …}` ou `size` + position, `hostile`, `hostileP`, `permanent`, `occupation`, `loyal`, **`key` (jamais lu par Bandits!, libre pour un identifiant de groupe)**. Pas de multiplicateur, pas de tirage.
- Contraintes : un `IsoPlayer` réel est exigé (`args.pid` → `brain.master`, `:409`) ; la case doit être **chargée** (sinon rien n'apparaît) ; la taille du groupe est plafonnée au nombre de **définitions de bandits distinctes** du clan (`:462-478`) ; `voice` et `fullname` passés en arguments sont communs à tout le groupe (ne pas les passer).
- `brain` construit par `makeBrain` (`:295-420`), stocké dans `BanditC<id % 32>[id]` puis transmis (`banditize`, `:423-441`). `Spawner.Clan` ne renvoie pas le nombre créé.
- Défauts : `Spawner.Individual` cassé (`:622`, `bandit.cid` au lieu de `bandit.general.cid`) ; `Spawner.Virtual` crée un cerveau sans corps que **rien** ne matérialise ; `Spawner.Restore` régénère nom et personnalité.
- **Sécurité** : les commandes client `Spawner.*`, `Commands.*` (dont `BanditUpdatePart`, `BanditFlush`) et `Custom.ReceiveFromClient` n'ont **aucun contrôle d'administrateur** côté serveur (`BanditServerSpawner.lua:1139-1151`, `server/BanditServerCommands.lua:59-90`, `server/BanditServerCustom.lua:9-15`).

## 3. Comportement (IA)

- **L'IA tourne sur chaque client** qui a le bandit chargé (`client/BanditUpdate.lua:2067-2071`, retour immédiat sur le serveur) ; les effets sur le monde sont réservés au client « contrôleur », le joueur en ligne le plus proche (`shared/BanditUtils.lua:670-696`).
- Répartition : `ZombiePrograms[nom][étape](bandit)` renvoie `{status, next, tasks}` (`BanditUpdate.lua:2035-2053`), sans garde `nil` : **un programme inconnu d'un client produit une erreur à chaque tick**. Un sous-mod ajoute un programme par `ZombiePrograms.MonProgramme = {Prepare = …, Main = …}` dans `shared/`, et une action par `ZombieActions.MonAction = {onStart, onWorking, onComplete}`.
- Programmes existants : `Bandit` (attaque, fuite, vol), `Camper` (sommeil 0-7 h, repas assis, garde, bascule en `Bandit` si un joueur est vu), `Defend` (bâtiment, sommeil 0-7 h et 13-14 h, matelas, bascule en `Looter` dehors, en `Bandit` si un joueur entre), `Companion` (suit son maître ; **les lignes 82-403 sont commentées** : pêche, cueillette, cultures… inactives), `Roadblock`, `Thief`, `Looter` (n'attaque que), `Dead`.
- Actions : déplacement (`Move`, `GoTo`), combat, soins (`Bandage` sans objet), bris (portes, fenêtres, barricades), objets (`LootItems`, `TakeFromContainer`, `PickUp`, `PutInContainer`, `Drop`), monde (lumières, générateurs, cuisinière), cultures, tombes, nettoyage, `Sleep`, `Time`. **Pas de manger ni boire.**
- Briques réutilisables : `BanditPrograms.Weapon.*`, `Idle`, `Generator.*`, `Farm.Water`, `Housekeeping.*`, `Misc.ReturnFood`, `Self.Wash` (`shared/BanditPrograms.lua`) — elles dépendent de `BanditPlayerBase`, **inerte** dans cette version (`client/BanditPlayerBase.lua:702` commenté).
- **Multijoueur** : une modification du cerveau côté serveur (cluster + `TransmitBanditCluster`) n'atteint pas les corps déjà chargés chez les clients, qui gardent leur copie (`BanditGMD.lua:52-67`, `BanditUpdate.lua:2137-2147`) ; seule la suppression les atteint. Il n'existe aucune commande serveur → client qui modifie un cerveau vivant. Piloter un groupe exige donc une commande propre relayée aux clients (cache `BanditZombie.Cache[id]`).

## 4. Persistance, morts, groupes

- Cerveaux dans 32 ModData globales `BanditC0..31`, sauvegardées avec le monde (`shared/BanditGMD.lua:3-48`). Les bandits sont des zombies ordinaires gardés par le gestionnaire de population ; au rechargement, le client les « rebanditise » s'il trouve leur identifiant (`BanditUpdate.lua:2137-2146`).
- Mort : le client envoie `Commands.BanditRemove {id}` (`BanditUpdate.lua:2489-2494`), le serveur efface le cerveau (`BanditServerCommands.lua:47-57`). Le gestionnaire est appelé par la table : **`BanditServer.Commands.BanditRemove` est enveloppable** ; lire `brain.key` avant d'appeler l'original ; plusieurs clients peuvent signaler la même mort.
- **Aucun identifiant de groupe** chez Bandits! (sauf les errants abstraits) : registre propre, `brain.key` posé à l'apparition, recoupé par sondage des clusters quand la zone est chargée.
- Aucune simulation hors chargement : un groupe éloigné est figé.

## 5. Besoins, bases, lieux

- Besoins : absents. Seuls `General_BleedOut`, `General_Infection`, `General_LimitedEndurance`, `General_RunAway` touchent la santé et l'endurance (`BanditUpdate.lua:467-525`). `brain.inventory` est créé mais jamais utilisé ; l'inventaire Java du zombie n'est pas synchronisé en MP (hypothèse).
- Bases : bibliothèques de préfabriqués sans groupe ni coordonnées fixes : `BanditProc.Cabin`, `CampTentSmall`, `MedicalTent`, `MilitaryTent`, `HouseSmall`… (`shared/BanditBases/Procedures/*`), placements unitaires `BanditBasePlacements.*` (`IsoObject` et `IsoThumpable` non transmis aux clients en MP ; `Container` ignore ses objets ; `Journal` cassé). Zone chargée obligatoire.
- `gmd.Posts` (postes de garde partagés, `client/BanditPost.lua`) utilisables comme postes d'une base. `brain.keys["x-y"]` permettrait d'ouvrir les portes verrouillées de sa base (`shared/Bandit.lua:1364-1371`), jamais renseigné par Bandits!.

## 6. Clans et définitions

- Fichiers `common/bandits/clans.txt` et `bandits.txt` lus **dans chaque mod activé** (`getModFileReader`), puis `Zomboid\Lua\bandits\` en dernier (`shared/BanditCustom.lua:215-300`). Un sous-mod peut livrer ses propres clans et bandits (GUID neufs, `general: modid = <id>`, valeurs sans espace). Les fichiers de Bandits! eux-mêmes sont ignorés en jeu si `General_OriginalBandits` est faux (`:232-234`).
- En Lua : `BanditCustom.clanData`, `banditData`, `ClanCreate` (défaut `spawnChance = 1`, `assault = true` : à remettre à 0), `Create` ; `Load()` réinitialise tout : envelopper `Load` pour réinjecter.
- Chargement : client à `OnGameStart`, serveur dédié à `OnServerStarted`, et à chaque ouverture du menu admin. Les clients n'en ont pas besoin pour l'IA (le cerveau est autonome).

## 7. Droits et forme du sous-mod

- Aucun fichier de licence dans le mod. La description Workshop (API `GetPublishedFileDetails`, 2026-10-03) précise : « all my work is copyrighted by default and I do not wish it to be reuploaded without my written permission. Copyright by Piotr Pawłowski ». Le moteur se désactive aussi si l'identifiant `Bandits2` n'est pas actif (`shared/BanditCompatibility.lua:340-345`, chaîne masquée). L'objet Workshop `3764925260` « Bandits [B42] » vient d'un autre compte : ce n'est pas la source officielle. Règle retenue : **étendre par les globales, les événements et les fichiers de données ; ne pas copier ni remplacer des fichiers entiers** de Bandits!.
- `mod.info` du sous-mod : `require=\Bandits2`, `loadModAfter=\Bandits2`, Lua des programmes dans `shared/` (présents chez tous les clients). Normaliser les identifiants de mod avec et sans `\`.
- Exemple d'addon existant : Extraction Mode (`3785397275`) attend les globales au lieu de `require`, appelle `Spawner.Clan` sous `pcall`, édite les clusters, enveloppe des programmes à `OnGameStart` avec un drapeau d'idempotence, ajoute une `ZombieAction` (`shared/ExtractionMode/BanditsIntegration.lua`, `BanditRaidBehaviour.lua`, `BanditMetaEvents.lua`).

## Points incertains

- `isIngameState()` sur un serveur dédié au moment de `OnServerStarted` (`BanditCustom.lua:232`).
- Sort des bandits virtualisés par le gestionnaire de population (cerveaux orphelins possibles).
- Bit « chapeau » de l'identifiant (`BanditUtils.lua:616-632`) pour les tenues `Naked<n>`.
- Synchronisation de l'inventaire Java d'un bandit en MP.
