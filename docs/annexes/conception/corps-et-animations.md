# Corps et animations

- Tâches : LK02-T01 (création), LK02-T02 à LK02-T07, complétée par LK02-T05
- Build : 42.21.0 (sources décompilées `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\` ; données vanilla `<PZ>\media`, noté **media/**) — Date : 2026-10-09 — Statut : brouillon

Lecture statique uniquement : aucune mesure en jeu. Les faits génériques sont aussi rangés dans la base (`.claude/pz-knowledge/zombies-as-npc-bodies.md`, `multiplayer.md`, `character-textures.md`).

## Problème

Un PNJ de Living Knox est un `IsoZombie` qui doit être créé par le serveur à une case choisie, retrouvé comme « le même » après déchargement et redémarrage, avoir l'air humain chez tous les clients, ne pas se comporter en zombie, jouer des gestes humains (clips `Bob_…`), tenir une arme visible et marcher vers une case. Ce document établit ce que le moteur 42.21 permet, pour les tâches LK02-T02 (création, identité), T03 (apparence), T04 (neutralisation), T05 (animations), T06 (arme), T07 (déplacement et relais de pose).

## Contraintes du moteur

### 1. Création côté serveur et persistance (LK02-T02)

| Fait | Preuve | Statut |
|---|---|---|
| `addZombiesInOutfit` (6, 13 à 17 arguments) crée sur **une case précise**, renvoie la liste, rien si la case n'est pas chargée. Avec un nom de tenue : `dressInPersistentOutfit(outfit)` tire un `persistentOutfitID` (sexe + index de tenue + variante 1-500). Force `lunger = true` et `setHealth(health)` (1,0 dans la forme à 6 arguments). | `J/Lua/LuaManager.java:8355-8445` (corps 8380-8445, tenue 8409-8414) ; `J/characters/IsoGameCharacter.java:1741-1747` | confirmé statiquement |
| `createZombie(x, y, z, desc, palette, dir)` **ignore** `desc` et `palette` : tenue tirée par la zone en MP. `spawnHorde` ne renvoie rien. | `J/Lua/LuaManager.java:4395-4415` | confirmé statiquement |
| `OnZombieCreate` part **avant** l'attribution de `onlineId` sur le serveur, et avant l'habillage et les drapeaux posés par `addZombiesInOutfit`. Sur un client MP, il part avant que le paquet ne pose `onlineId`, la position exacte, l'index de peau et les drapeaux. | `J/VirtualZombieManager.java:207-219` ; `J/Lua/LuaManager.java:8400-8414` ; `J/popman/NetworkZombieSimulator.java:182-188, 219` | confirmé statiquement |
| `onlineId` n'est valable que tant que le zombie reste réel ; il est réattribué à chaque réalisation (`getUniqueZombieId`). Pas de recherche Lua par identifiant : parcourir `getCell():getZombieList()`. | `J/VirtualZombieManager.java:213-219` ; `J/network/GameClient.java:1440` (non exposé) | confirmé statiquement |
| Virtualisation (zombie ordinaire) : seuls position, direction, `persistentOutfitID`, drapeaux `ZombieStateFlags` (rampant, marche, faux mort, sous véhicule, réanimé pour être traîné) et `persistentId` survivent. ModData vidées au recyclage ; santé, vitesse, `useless`, `noTeeth` perdus. | base : `staging-effects.md` « Reconnaître un zombie après virtualisation », `clothing-and-character-state.md` « ModData d'un zombie » ; `J/popman/ZombieStateFlags.java:31-40` ; `J/popman/ZombiePopulationManager.java:373-395` | confirmé statiquement |
| **Joueur réanimé** : un `IsoDeadBody` non faux mort, réanimé par `reanimate()` (public) côté serveur, devient un zombie `isReanimatedPlayer()` qui reprend l'inventaire, les vêtements portés, les objets accrochés, `HumanVisual` et les ModData du corps. | `J/iso/objects/IsoDeadBody.java:1832-1900` (ModData : 1865 ; drapeau et descripteur : 1897-1900) | confirmé statiquement |
| Un joueur réanimé n'est **jamais virtualisé** ni supprimé par l'optimiseur de population ; au déchargement du chunk, le même objet Java est mis de côté puis remis en monde au rechargement ; il est sauvegardé **en entier** (`IsoZombie.save` : ModData, visuel, inventaire, vêtements) dans `reanimated.bin`. | `J/popman/ZombiePopulationManager.java:382` ; `J/popman/ZombieCountOptimiser.java:37` ; `J/VirtualZombieManager.java:677-684` ; `J/ReanimatedPlayers.java:40-110, 112-196` ; `J/iso/IsoMovingObject.java:699-713` ; `J/characters/IsoGameCharacter.java:5021-5033` | confirmé statiquement |
| Création d'un cadavre sur une case : `sq:createCorpse(false)` (zombie hors monde, puis `IsoDeadBody`, `fakeDead = false`) ; `createRandomDeadBody(sq, sang)` (global). | `J/iso/IsoGridSquare.java:10100-10124` ; `J/Lua/LuaManager.java:8279-8301` | confirmé statiquement |
| Retrouver « le même » corps : zombie ordinaire → seule clé lisible `getPersistentOutfitID()` (non unique : 500 variantes par tenue) + zone ; joueur réanimé → ModData conservées (objet non recyclé, sauvegardé). | base `staging-effects.md` ; lignes ci-dessus | confirmé statiquement ; ⚠ joueur réanimé à mesurer |

### 2. Apparence humaine et transmission aux clients (LK02-T03)

| Fait | Preuve | Statut |
|---|---|---|
| Le paquet zombie ne porte, pour l'apparence, que `outfitId` (= `persistentOutfitID`) et `skinTextureIndex`. Le client crée le zombie avec `createRealZombieAlways(outfitId)` et pose l'index de peau **une seule fois**, à la création. | `J/network/packets/character/ZombiePacket.java:23-49, 213-247` ; `J/popman/NetworkZombieSimulator.java:176-188` | confirmé statiquement |
| Le client habille le zombie à la création de son modèle par `dressInPersistentOutfitID`, qui **efface** `HumanVisual` et `ItemVisuals` puis rejoue la tenue avec la graine de la variante (graines `z_outfits.bin` envoyées par le serveur à la connexion). Une modification Lua faite à `OnZombieCreate` est donc écrasée ; toute modification serveur de `HumanVisual`/vêtements d'un zombie ordinaire n'atteint pas les clients. | `J/core/skinnedmodel/ModelManager.java:506-524` ; `J/characters/IsoZombie.java:3904-3915` ; `J/PersistentOutfits.java:61-81, 321-334` ; `J/network/packets/RequestDataPacket.java:178, 267` | confirmé statiquement |
| Tenue déterministe : une tenue de mod (`clothing.xml`) entre dans `PersistentOutfits` (index trié par nom) ; cheveux, barbe et couleur par tenue via `HairOutfitDefinitions.haircutOutfitDefinition` (`haircut`, `maleHaircut`, `femaleHaircut`, `beard`, `haircutColor`). Sang, saleté, trous, plaies (`ZedDmg_*`) et bandages sanglants sont ajoutés à l'habillage d'un zombie (`addRandomBloodDirtHolesEtc`), avec la même graine. | `J/PersistentOutfits.java:83-108, 265-283` ; `J/characters/HairOutfitDefinitions.java:28-70, 97-180` ; `media/lua/shared/Definitions/HairOutfitDefinitions.lua:39-90` ; `J/characters/IsoZombie.java:3749-3767, 4204-4227` | confirmé statiquement |
| Peau : pour un propriétaire zombie, `getSkinTexture()` choisit **toujours** dans les listes `M_ZedBody0n_levelX` (stade de décomposition tiré au hasard, non transmis) sauf si `skinTextureName` est posé ; `setSkinTextureName("MaleBody01")` (listes humaines `MaleBody01..05`, `FemaleBody01..05`) donne une peau humaine. Ce nom est sauvegardé et copié par `copyFrom`. | `J/core/skinnedmodel/visual/HumanVisual.java:110-195, 349-386, 387-430` ; `J/core/skinnedmodel/population/PopTemplateManager.java:47-70` | confirmé statiquement ; rendu à mesurer |
| Nettoyage : `HumanVisual:removeBlood()`, `removeDirt()`, `getBodyVisuals():clear()` (plaies, bandages) ; `ItemVisual:removeBlood()`, `removeDirt()`, `removeHole(i)` ; puis `resetModel()` (exposé) pour reconstruire le modèle. | `J/core/skinnedmodel/visual/HumanVisual.java:298-304, 673` ; `J/core/skinnedmodel/visual/ItemVisual.java:617, 635-645` ; `J/characters/IsoGameCharacter.java:1581-1583` | confirmé statiquement ; effet visuel à mesurer |
| **Descripteur partagé** d'un joueur réanimé : à sa création, le serveur copie `HumanVisual` + `ItemVisuals` et les envoie à toutes les connexions (paquet `ZombieDescriptors`) ; un client qui se connecte plus tard les reçoit par `RequestDataPacket`. Le client applique ce descripteur à l'habillage (`useDescriptor`). Copie figée : un changement ultérieur n'est pas renvoyé ; les objets accrochés n'y sont pas. | `J/SharedDescriptors.java:44-96, 133-157, 159-241` ; `J/network/packets/RequestDataPacket.java:185-205, 352-354` ; `J/PersistentOutfits.java:115-119` ; `J/characters/IsoZombie.java:3792-3805` | confirmé statiquement |
| Un zombie distant sans paquet depuis 5 s est retiré du monde par le client, puis recréé au paquet suivant (nouvel objet, apparence rejouée depuis `outfitId`). | `J/characters/IsoZombie.java:2716-2722` ; `J/popman/NetworkZombieSimulator.java:172-188` | confirmé statiquement |

### 3. Neutraliser le zombie (LK02-T04)

Suite et choix retenus : [neutralisation.md](neutralisation.md).

| Fait | Preuve | Statut |
|---|---|---|
| `setUseless(true)` : `spottedNew`/`spottedOld` effacent la cible, `RespondToSound` sort, l'errance de `ZombieIdleState` et le groupe (`ZombieGroupManager`) sont coupés. **Mais** `WalkTowardState.enter` renvoie aussitôt un zombie `useless` à l'état idle : un `pathToLocation` en ligne droite (`bPathfind = false`) ne le fait pas marcher. `PathFindState` ne teste pas `useless`. | `J/characters/IsoZombie.java:1303-1316` (`RespondToSound`), `1662-1704` (`spottedNew`), `1967-2009` (`spottedOld`) ; `J/ai/states/ZombieIdleState.java:78-80` ; `J/ai/ZombieGroupManager.java:70` ; `J/ai/states/WalkTowardState.java:45-58` ; `J/characters/IsoGameCharacter.java:5927-5957` | confirmé statiquement |
| Sans cible, ni `blunge` ni `bAttack` : pas de bond ni d'attaque, y compris pour les états `-network` des clients distants (cible reçue du propriétaire). | `J/characters/IsoZombie.java:604, 666-700` ; `media/actiongroups/zombie/idle/to_attack.xml`, `to_attack-network.xml`, `to_lunge-network.xml` | confirmé statiquement |
| `setNoTeeth(true)` : le contrôle de collision d'attaque (morsure, dégâts) n'a pas lieu. Non transmis, non sauvegardé. | `J/ai/states/AttackState.java:137` ; `J/characters/IsoZombie.java:4498-4545` | confirmé statiquement |
| Voix : jouées **localement par chaque client** (`ZombieVocalsManager`) pour tout zombie vivant, non faux mort, non « réanimé pour être traîné », dans un rayon de 70 ; nom = préfixe de voix du descripteur + `Voice` + A/B/C. Aucun drapeau simple ne les coupe. | `J/characters/IsoZombie.java:2888-2929, 3730-3745` ; `J/characters/ZombieVocalsManager.java:46-200` ; `J/iso/IsoCell.java:1937` | confirmé statiquement ; ⚠ coupure à mesurer |
| Restent actifs même `useless` et sans cible : recherche de cadavre à manger dans 10 cases (puis `pathToLocationF` depuis l'état idle), destruction aléatoire d'une plante cultivée sur sa case, extinction d'un feu de camp en marchant, séparation (poussée). | `J/characters/IsoZombie.java:2837-2847, 2859, 2940-2985` | confirmé statiquement |
| Drapeaux transmis (14) : faux mort, `lunger`, `running`, rampant, assis, joueur réanimé, en feu, `useless`, au sol, réanimé pour être traîné, `canWalk`, squelette, chute sur le ventre, enregistrement d'animation. Les valeurs **du propriétaire** écrasent celles du serveur et des autres clients ; au changement de propriétaire, le nouveau garde celles qu'il a reçues. `noTeeth`, santé, voix : non transmis. | `J/characters/NetworkZombieVariables.java:10-64` ; `J/popman/NetworkZombiePacker.java:216-251` ; `J/characters/NetworkZombieAI.java:235-268` | confirmé statiquement |
| Phase d'inactivité (`ZombieLore.ActiveOnly`) : `makeInactive` impose une marche `slow1-3`, puis `DoZombieStats` retire la marche imposée. | `J/characters/IsoZombie.java:2651-2653, 4352-4368` | confirmé statiquement |

### 4. Animations (LK02-T05)

| Fait | Preuve | Statut |
|---|---|---|
| Un état d'animation = un dossier `media/AnimSets/zombie/<état>/` ; chaque `.xml` est un nœud (dédoublonné par chemin relatif : même chemin = remplacement, autre nom = ajout). | `J/core/skinnedmodel/advancedanimation/AnimState.java:59-75` ; base `api-42-21.md` « Remplacer un nœud d'animation » | confirmé statiquement |
| Choix du nœud : nœuds triés par `m_ConditionPriority` puis **nombre de conditions** ; le premier dont toutes les conditions passent est retenu, avec les suivants de même rang. Un nœud portant une condition de plus que le nœud vanilla (ou une `m_ConditionPriority` plus haute) l'emporte quand sa condition est vraie. Types : `STRING`, `STRNEQ`, `BOOL`, `EQU`, `NEQ`, `LESS`, `GTR`, `ABSLESS`, `ABSGTR`, `OR`. | `J/core/skinnedmodel/advancedanimation/AnimState.java:28-57, 78-91` ; `AnimNode.java:43-46, 287-307` ; `AnimCondition.java:202-214` | confirmé statiquement |
| Les nœuds vanilla des zombies jouent déjà des clips `Bob_…` (traîné, ramassé, chutes) : le corps de zombie partage le squelette du joueur. | `media/AnimSets/zombie/corpseDragged-onback/*.xml`, `bumped/sprinterTripping.xml` ; `J/core/skinnedmodel/ModelManager.java:527-541` | confirmé statiquement ; chaque clip à vérifier visuellement |
| L'état (dossier) vient de l'actiongroup `media/actiongroups/zombie` et de ses transitions sur variables ; chaque nom d'état est lié à un état Java (`registerAIState`). Zombie local : `walktoward`/`pathfind` ; zombie distant (`bClient` = client et `isRemoteZombie()`) : `walktoward-network`, `lunge-network`, `attack-network`… `bMovingNetwork` = cible réseau à plus de 0,5 case. | `media/actiongroups/zombie/idle/to_walktoward.xml`, `to_walktoward-network.xml`, `to_pathfind.xml` ; `J/characters/IsoZombie.java:540-600` | confirmé statiquement |
| Synchronisé : état réel (`realState`, 39 valeurs), marche (`walkType` limité à 13 valeurs `1-5`, `sprint1-5`, `slow1-3`, toute autre chaîne devient `1`), 14 drapeaux, cible, direction. **Non synchronisé** : toute variable posée par `setVariable`, `BumpType`. Les variables personnalisées sont effacées au recyclage (`clearVariables`). | `J/network/NetworkVariables.java:8-50, 103-135` ; `J/characters/NetworkZombieAI.java:192` ; `J/VirtualZombieManager.java:318` ; base `multiplayer.md` | confirmé statiquement |
| Noms de variables insensibles à la casse (`zombiewalktype` enregistré, `zombieWalkType` lu). | `J/characters/IsoZombie.java:796` ; `J/characters/NetworkZombieAI.java:192` | confirmé statiquement |

### 5. Objet en main (LK02-T06)

Mise en œuvre (arme accrochée au repos, en main pour les gestes, garde `OnEquipPrimary`) : [equipement.md](equipement.md).

| Fait | Preuve | Statut |
|---|---|---|
| Le rendu des objets en main (`Bip01_Prop1/2`) et accrochés vaut pour **tout** `IsoGameCharacter`, zombie compris ; `setPrimaryHandItem` pose aussi la variable `Weapon`. | `J/core/skinnedmodel/ModelManager.java:558-670` ; `J/characters/IsoGameCharacter.java:2987-3025, 3361-3375` | confirmé statiquement ; rendu à mesurer |
| `setPrimaryHandItem` sur un zombie **côté serveur** lève le drapeau `handItemShouldSendToClients`, puis `preupdate` exécute `INetworkPacket.send((IsoPlayer)this, …)` : conversion impossible pour un `IsoZombie`, exception probable à chaque mise à jour. Ne poser l'objet en main que chez les clients. | `J/characters/IsoGameCharacter.java:3015, 7998-8001` ; `J/characters/IsoZombie.java:2451-2476` ; `J/network/packets/EquipPacket.java:37-46` | confirmé statiquement ; ⚠ exception à mesurer |
| `sendAttachedItem(personnage, emplacement, objet)` (global, serveur) envoie `GameCharacterAttachedItem` aux clients proches, qui appliquent `setAttachedItem` au zombie désigné par son `onlineId`. Seuls les clients présents à l'envoi le reçoivent ; emplacements du groupe `Human` (`Rifle On Back`, `Holster Right`, `Belt Left`…). | `J/Lua/LuaManager.java:9719-9724` ; `J/network/packets/GameCharacterAttachedItemPacket.java:37-120` ; `J/network/fields/MovingObject.java:52-60, 117-122` ; `media/lua/shared/NPCs/AttachedLocations.lua:2-43` | confirmé statiquement |

### 6. Déplacement (préparation LK02-T05/T07)

| Fait | Preuve | Statut |
|---|---|---|
| `pathToLocation(x, y, z)`/`pathToLocationF` : ligne dégagée → `bMoving` (état `walktoward`), sinon `bPathfind` (état `pathfind`). Ignorés pendant `allowRepathDelay > 0` si le zombie marche déjà. | `J/characters/IsoGameCharacter.java:5927-5978` ; `J/characters/IsoZombie.java:944-958` | confirmé statiquement |
| Seul le propriétaire cherche un chemin ; un zombie distant suit la position réseau (`walktoward-network`) et est téléporté au-delà de 3 cases d'écart. | base `multiplayer.md` « Zombies en MP » ; `J/characters/NetworkZombieAI.java:235-276` | confirmé statiquement |
| La vitesse de marche dépend de `walkType`/`speedType` et des nœuds d'animation ; avec un clip humain, la vitesse réelle dépend du déplacement porté par le clip. | `media/AnimSets/zombie/walktoward/walktoward1.xml` | ⚠ hypothèse à mesurer |

## Choix

Aucun choix arrêté : les options ci-dessous sont présentées pour les tâches suivantes ; celles marquées « décision » relèvent de l'utilisateur.

- **Base du corps (décision, LK02-T02/T03)** :
  - A. **Zombie ordinaire** (`addZombiesInOutfit` avec une tenue de mod par profil) : identité par registre serveur + `persistentOutfitID` + zone ; apparence rejouée par chaque client (peau `setSkinTextureName`, nettoyage, cheveux) à chaque création locale du modèle et après chaque retrait « périmé » ; rien de persistant sur le corps.
  - B. **Joueur réanimé** (`sq:createCorpse(false)` ou cadavre préparé, `HumanVisual`/vêtements réglés côté serveur, puis `body:reanimate()`) : apparence exacte diffusée par le descripteur partagé, ModData et vêtements réels conservés, jamais virtualisé. Risques : chemin peu exercé par le vanilla (prévu pour les joueurs morts), propriétaire attribué comme pour un zombie, descripteur figé, corps qui ne disparaît jamais seul (retrait des orphelins à notre charge).
  - Essai court recommandé avant de trancher (voir Tests).
- **Neutralisation pendant la marche (décision, LK02-T04/T07)** : `useless` empêche `walktoward`. Options : basculer `useless` à faux pendant un trajet (avec cible effacée à chaque tick par le propriétaire) ; ou garder `useless` et forcer `bPathfind` ; ou ne pas utiliser `useless` et effacer cible/son chez le propriétaire.
- **Voix (LK02-T04)** : pistes à mesurer, chez chaque client : préfixe de voix inexistant via `getDescriptor():setVoicePrefix(…)`, ou coupure de l'émetteur.
- **Animations (LK02-T05)** : nœuds ajoutés dans les états existants (`idle`, `walktoward`, `walktoward-network`, `pathfind`) avec une condition sur une variable d'acteur propre au mod (plus une sous-condition de geste) ; aucun fichier vanilla remplacé. Variables posées chez **chaque** client (non synchronisées).
- **Arme (LK02-T06)** : objet en main posé localement par chaque client (`instanceItem` + `setPrimaryHandItem`), sur consigne serveur ; ou `sendAttachedItem` pour une arme portée au dos/à la ceinture, à renvoyer aux clients qui arrivent.

## Alternatives écartées

- `createZombie(x, y, z, desc, …)` pour fixer l'apparence : le descripteur est ignoré (`LuaManager.java:4408-4415`).
- Modifier `HumanVisual` d'un zombie ordinaire côté serveur seulement : jamais transmis (§2).
- `setPrimaryHandItem` côté serveur : piège du `(IsoPlayer)this` (§5).
- `walkType` personnalisé comme canal de geste : réduit à 13 valeurs, toute autre chaîne devient `1` (§4).
- ModData d'un zombie ordinaire comme identité : vidées au recyclage (§1).

## Idées reprises

- Aucune.

## Tests

- Banc lupa (`tests/harness.py`) : sans objet pour cette fiche (aucun code).
- VM Kahlua (`tests/test_kahlua.py`) : sans objet.
- En jeu, à prévoir (protocole court, nominal d'abord) :
  1. **Essai de base** (solo puis serveur dédié + 2 clients) : créer A et B côte à côte ; comparer l'apparence chez les deux clients, puis après sortie de zone, retour et redémarrage du serveur ; relever ModData, `getPersistentOutfitID()`, `isReanimatedPlayer()`.
  2. Peau humaine : `setSkinTextureName("MaleBody01")` + nettoyage + `resetModel()` sur un zombie ordinaire, capture des deux clients.
  3. Neutralisation : `useless`, `noTeeth`, cible effacée ; un joueur au contact une minute ; trajet en ligne droite avec et sans `useless`.
  4. Voix : préfixe de voix inexistant ; écoute à 2 m.
  5. Arme : `setPrimaryHandItem` côté client (rendu) ; vérifier dans `console.txt` du serveur l'exception si posé côté serveur ; `sendAttachedItem` vers un client présent puis un client arrivé ensuite.
  6. Animations : nœud ajouté dans `idle` avec une condition, clip `Bob_IdleAimPistol` (ou autre) basculé par `setVariable` ; zombie ordinaire voisin inchangé.

## Essai comparatif — protocole

Tâche LK02-T10. Code d'essai dans le **mod de dev seulement** (`dev/batman_RadioSurvivorTests/42.21/media/lua/`, jamais publié) : `shared/RST/RST_LKEssai.lua` (noyau), `server/RST/RST_LKEssaiServer.lua` (autorité), `client/RST/RST_LKEssaiClient.lua` (console), `shared/RST/suites/RST_LKEssaiSuite.lua` (suite `lk.essai`). Mode d'emploi détaillé en tête de chaque fichier ; moteur RST : `docs/annexes/tests/tests-en-jeu.md`.

### Chemins réels utilisés (Java 42.21.0)

- **A** : `addZombiesInOutfit(x, y, z, 1, "Generic01", 50)` (`J/Lua/LuaManager.java:8355-8445`) ; tenue civile vanilla `Generic01` (`media/clothing/clothing.xml:7719` femme, `:27617` homme).
- **B** : `addZombiesInOutfit` (zombie habillé) → `zombie:DoZombieInventory()` (vêtements de la tenue devenus objets portés, comme le vanilla `addZombiesEating`, `LuaManager.java:8317-8341` ; `IsoZombie.java:3129-3160`) → `sq:createCorpse(zombie)` (`IsoGridSquare.java:10109-10124` ; le constructeur `IsoDeadBody.java:252-440` copie visuel, objets portés, ModData et retire le zombie du monde) → `body:reanimate()` (`IsoDeadBody.java:1832-1946`). **Pas** `sq:createCorpse(false)` : il tire son zombie dans `VirtualZombieManager.choices` **avant** d'y placer la case (`IsoGridSquare.java:10100-10102`), liste vide hors génération → `nil` (`VirtualZombieManager.java:247-254`). Le serveur ne transmet pas aux clients un cadavre créé par Lua (`IsoDeadBody` sans paquet ; `sendCorpse` existe, `LuaManager.java:3280-3285`) : sans importance ici, le cadavre est réanimé dans la même commande. Option `clean` : peau humaine et nettoyage **avant** le cadavre (le descripteur partagé est une copie figée, `SharedDescriptors.java:44-96`).
- **Retrait** : `removeFromWorld()` + `removeFromSquare()` (vanilla `ISSpawnHordeUI.lua:325-326`) ; un joueur réanimé vivant serait mis de côté puis remis en monde avec son chunk (`VirtualZombieManager.java:677-684`, `ReanimatedPlayers.java:69-110`) : `setHealth(0)` d'abord. Le serveur ne peut pas appeler `NetworkZombiePacker.deleteZombie` (utilisé par `/removezombies`, `RemoveZombiesCommand`) : les clients retirent leur copie sur la commande `removed`, sinon au bout de 5 s sans paquet. Cadavre restant : `sq:removeCorpse(body, false)` (transmis, `IsoGridSquare.java:2600-2620`).
- **Qui simule** : `isRemoteZombie()` = « aucune connexion propriétaire » (`NetworkZombieComponent.java:23`). Client : faux pour le zombie qu'il possède (`NetworkZombieSimulator.java:124-129`). **Serveur : vrai pour un zombie qu'il simule lui-même, faux pour un zombie possédé par un client** (`NetworkZombieManager.java:140-177`) ; solo : toujours vrai. L'essai utilise donc `getOwner() == nil` côté serveur.
- **Marche** : sur le serveur, `pathToAux` ne pose jamais `bPathfind` (`CanUsePathfindState()` = `!GameServer.server`, `IsoGameCharacter.java:5923-5958`) : la marche est confiée au propriétaire ; le mode `pathfind` reproduit la branche « ligne non dégagée » (`setVariable("bPathfind", true)`, `setMoving(false)`).

### Préparation

1. `python RadioSurvivor/tools/install_tests.py` (copie le mod de dev), jeu lancé avec `-debug`, mods `batman_RadioSurvivor` et `batman_RadioSurvivorTests` actifs.
2. Journaux à relever après chaque séance : `console.txt` de chaque machine ; `Zomboid/Lua/batman_RadioSurvivor/tests/lke-essai.log` (lignes `[LKE]`, une copie par machine ; sur le serveur de test, dans le cache affiché par `RS_SMOKE_CACHE=`) ; rapports RST `<horodatage>-solo.txt` / `-server.txt` dans le même dossier. Ranger captures et copies des journaux dans `RadioSurvivor/docs/essais/lk02-t10/` (à créer), un sous-dossier par séance.

### Solo (`rstest-solo`) d'abord

1. Partie neuve nommée `rstest-solo`, lieu dégagé (rue), jour ; ne pas mettre en pause pendant une mesure.
2. Suite automatique : `RST.run({ suite = "lk.essai", tags = "world" })` (≈ 6 min) ; noter le bilan et les lignes `[LKE] measure ...`.
3. Console : `LKE.spawn("A")`, `LKE.spawn("B")`, `LKE.spawn("B", "clean")`, `LKE.spawn("A", "clean")`, puis `LKE.list()`. Regarder : peau (zombie/humaine), sang, plaies, cheveux, vêtements ; capture.
4. Neutralisation : `LKE.set(1, "useless", true)`, `LKE.set(1, "noTeeth", true)`, `LKE.set(1, "clearTarget", true)` (idem pour 2) ; rester au contact une minute ; noter santé, attaques, cible (`LKE.list()`).
5. Marche : `LKE.walk(1, 8, 0, "plain")`, puis `"pathfind"`, `"notarget"`, `"uselessline"` ; `LKE.list()` après 8 s (champ `moved=`) ; idem pour B.
6. Voix : à 2 m, `LKE.set(1, "voice", "prefix")`, écouter 30 s ; `LKE.set(1, "voice", "normal")` ; puis `"grapple"` (noter tout changement d'animation ou d'état) ; comparer avec un zombie ordinaire voisin.
7. Objets : `LKE.set(1, "hand", "Base.Hammer")`, `LKE.set(1, "attached", "Base.Shotgun")`, `LKE.set(2, "attached", "Base.Pistol@Holster Right")` ; capture.
8. Persistance : s'éloigner à plus de 300 cases (ou `RST.run` du test « identity after a round trip »), revenir, `LKE.list()` (`found=object|moddata|outfit|lost`, `candidates=`) ; puis quitter vers le menu, recharger, `LKE.list()` (le registre d'essai est en mémoire : relever surtout si un corps tagué réapparaît, A ou B, et en combien d'exemplaires).
9. `LKE.clear()` ; vérifier qu'aucun corps ni cadavre ne reste.

### Serveur dédié de test, deux clients

1. `powershell -ExecutionPolicy Bypass -File RadioSurvivor/tests/run_dedicated_smoke.ps1 -Manual` : serveur `rstest_smoke` (nom de sauvegarde accepté par la garde `rstest*`), `127.0.0.1`, ports 17381/17382, cache temporaire conservé (noter `RS_SMOKE_CACHE=`), compte admin `rs_smoke_admin` / `local-smoke-only`. Le mod de dev doit aussi être actif chez chaque client.
2. Client 1 : `rs_smoke_admin` ; client 2 (seconde instance ou second PC, `-debug`) : compte créé à la connexion, puis `grantadmin <compte>` dans la console du serveur si ce client doit lancer des commandes.
3. Suite : depuis le client 1, `RST.server({ suite = "lk.essai", tags = "world" })` ; rapport complet dans `<cache>/Lua/batman_RadioSurvivor/tests/`.
4. Console (client 1) : mêmes commandes qu'en solo ; la réponse du serveur s'affiche en `[LKE] server: ...`. **Chez chaque client**, `LKE.here()` donne ce que ce client voit (peau, voix, propriétaire, drapeaux) ; captures simultanées des deux clients.
5. Propriétaire : `LKE.list()` donne `owner=<compte>|server` ; la marche est exécutée par le client propriétaire, qui le signale (`client X reports: walk #n ...` dans le journal du serveur). Rapprocher le client 2 du corps pour forcer un changement de propriétaire pendant une marche.
6. Arme : `hand` (posé par chaque client) ; `serverHand` **une seule fois, sur un corps à retirer aussitôt** : relever dans `server-console.txt` l'exception attendue de `IsoGameCharacter.preupdate` ; `attached` avec les deux clients présents, puis client 2 déconnecté, `attached` changé, client 2 reconnecté.
7. Reconnexion : client 2 se déconnecte et revient ; comparer l'apparence de A (rejouée depuis la tenue + réglages réappliqués par le client) et de B (descripteur partagé reçu à la connexion).
8. Redémarrage : `quit` dans la console du serveur, relancer la commande `java` du script avec le même `-cachedir=` (le script crée un nouveau cache à chaque lancement), puis `LKE.list()` (registre vide) et compter les corps tagués revenus (`B` attendu dans `reanimated.bin`) ; taille de `<cache>/Saves/Multiplayer/rstest_smoke/reanimated.bin` avant et après.
9. `LKE.clear()`, puis vérifier chez les deux clients qu'aucune copie ne reste (`LKE.here()`).

### Résultats A/B (solo du 2026-10-09 rempli ; MP à faire)

| Mesure | A — zombie ordinaire | B — joueur réanimé | Preuve (fichier, capture) |
|---|---|---|---|
| Création côté serveur (`lk.essai`) | solo : debout, peau zombie `M_ZedBody01_level1` | solo : `reanimatedPlayer=true`, couché puis relevé, aucun cadavre restant | `20261009-090207-solo.txt` |
| Peau humaine, client 1 / client 2 | solo : peau zombie « level1 », peu visible de loin | solo : `clean` = `FemaleBody01`, **le plus humain** (avis de l'utilisateur) ; client 2 à faire | capture solo du 2026-10-09 |
| Sang, plaies, cheveux, vêtements, client 1 / client 2 | solo : vêtements de zombie | solo : `clean` : casquette gardée, **vêtements déchirés** (tenue de zombie) | capture solo du 2026-10-09 |
| Apparence après reconnexion d'un client | | | |
| Identité après sortie de zone (`found=`, doublons) | solo : **perdu** (`found=lost`, 0 candidat, étiquette effacée) | solo : **retrouvé** (`found=object`, 1 candidat, étiquette conservée) | `20261009-090207-solo.txt` |
| Identité après redémarrage du serveur | | | |
| Contact 60 s : attaque, cible, santé du joueur | solo : santé 100 → 100, 0 cible, 0 attaque | idem | `20261009-090207-solo.txt` |
| Marche `plain` (cases en 8 s) | 5,31 | 3,23 (se relève d'abord) | `20261009-090207-solo.txt` |
| Marche `pathfind` | 6,51 | 6,52 | `20261009-090207-solo.txt` |
| Marche `notarget` | 3,66 | 6,11 | `20261009-090207-solo.txt` |
| `useless` + ligne droite (`uselessline`) | 0,01 : **bloqué** (confirme `WalkTowardState.java:56`) | — | `20261009-090207-solo.txt` |
| Marche pendant un changement de propriétaire | | | |
| Voix `prefix` (silence ? effets de bord) | solo : **plus de gémissement**, aucune erreur | idem | retour de l'utilisateur, `console.txt` 2026-10-09 |
| Voix `grapple` (silence ? effets de bord) | | | |
| Objet en main posé par chaque client | solo : marteau visible ; 1er essai : erreur `handleFishing` (abonné vanilla `OnEquipPrimary` qui suppose un joueur) | — | `console.txt` 2026-10-09, base `zombies-as-npc-bodies.md` |
| `serverHand` : exception serveur | | | |
| `sendAttachedItem` : client présent / arrivé après | — | solo : pistolet à la hanche (`clean`) visible ; MP à faire | retour de l'utilisateur |
| Retrait (`clear`) : corps, cadavres, copies clientes | solo : tout retiré | solo : tout retiré | `20261009-090207-solo.txt` et retour de l'utilisateur |
| Taille de `reanimated.bin` | sans objet | | |

## Animations (LK02-T05)

État : code et tests hors jeu le 2026-10-09 ; aucun essai visuel en jeu. Écriture indépendante : Java 42.21.0 décompilé et `media/` vanilla seulement.

### Mécanisme

- **Table source** : `tools/anim_table.json` (geste → nœud, état, clip, conditions, preuve vanilla). **Générateur** : `tools/gen_animsets.py` écrit un fichier complet par nœud et par état dans `Contents/mods/batman_RadioSurvivor/common/media/AnimSets/zombie/<état>/lkactor_*.xml` ; `--check` signale un fichier absent, modifié ou en trop (le générateur possède tous les `lkactor_*.xml` de cet arbre) et, si le jeu est installé, contrôle clips, dossiers d'état et collisions. Depuis LK04-T11, la table porte aussi les événements d'un nœud (`events` : `SetVariable`, `PlaySound`) et les états d'escalade `climbwindow`/`climbfence` (nœuds humains de l'enjambée, sans `OnFloor` ; voir `deplacement.md`, « Animation humaine pour l'enjambée »).
- **Conditions exclusives** : chaque nœud exige `LKActor` = vrai (`BOOL`). Une variable absente ne satisfait une condition `BOOL` que si la valeur attendue est `false` (`AnimCondition.check`, `J/core/skinnedmodel/advancedanimation/AnimCondition.java`) : un zombie ordinaire ne peut jamais choisir nos nœuds. Aucune condition `OR`. Le geste passe par `LKGesture` (`STRING`) ; deux variantes lisent la variable vanilla `Weapon`, posée par `setPrimaryHandItem` (`J/characters/IsoGameCharacter.java:3018`, valeurs de `J/inventory/types/WeaponType.java:15-24` : `firearm`, `handgun`, `1handed`, `2handed`…).
- **Priorité** : `m_ConditionPriority` = 5. Les nœuds d'un état sont triés par priorité puis nombre de conditions ; le premier qui passe est retenu avec les suivants de **même rang** (`AnimState.java:44-52, 78-91`, `AnimNode.java:287-310`). Tous les nœuds vanilla des quatre états visés ont la priorité 0, sauf `pathfind/ragdollVehicleCollision.xml` (10) : le choc d'un véhicule garde la main. Entre nos nœuds, une condition de plus départage (`aim` + `Weapon=firearm` passe avant `aim`) ; deux nœuds de même rang sont exclusifs par `LKGesture`, `Weapon` ou `bMoving` (vérifié pour toutes les combinaisons par `tests/test_gen_animsets.py`, qui reproduit cet algorithme).
- **Emplacement `common/`** : `AnimationSet.Load` liste `media/AnimSets/zombie/*` du jeu puis, pour chaque mod, de `getCommonDir()` **et** `getVersionDir()` (`J/ZomboidFileSystem.java:1157-1167`, `AnimationSet.java:50-60`) : les deux conviennent ; `common/` suit le plan et vaut pour toute variante. Fichiers d'un état ajoutés à ceux du jeu, dédoublonnés par chemin relatif (`resolveAllFiles`, `:1196-1205`) : un nom différent ajoute un nœud, un même nom remplacerait le nœud vanilla (refusé par le générateur).
- **Casse (Linux)** : le dossier est lu par `new File(racine, "media/AnimSets/zombie/<état>")` (`J/ZomboidFileSystem.java:1169-1172`), sensible à la casse sous Linux : `AnimSets` et les noms d'état sont écrits exactement comme les dossiers vanilla. Un dossier d'état d'une autre casse (ex. `Idle`) créerait un second état de même clé et **remplacerait** l'état vanilla entier (`states.put(nom.toLowerCase())`, `AnimationSet.java:58`). Noms de fichiers en minuscules ; fichiers complets, sans `x_extends` (héritage relatif perdu sur un serveur dédié Linux, base `file-path-case.md`).
- **Clips `Bob_`** : l'AnimSet `zombie` admet les préfixes `Bob_` et `Zombie_` (`media/AnimSets/zombie.xml`, `animNodeFilter`) ; chaque clip est joué par un nœud vanilla du joueur (colonne Preuve) et existe dans `media/anims_X/Bob/`.
- **Variables locales** : `setVariable` est sans effet sur un zombie côté serveur (`J/characters/IsoGameCharacter.java:11374-11396`) et n'est pas synchronisé. `LK_Anim.lua` (shared) pose `LKActor` et `LKGesture` sur chaque machine qui affiche le corps : solo par `LivingKnox.Bodies.bound`, client MP par les copies que la garde retrouve (`LivingKnox.ZombieGuard.cache`, liste `guardRoster`). Passage toutes les 3 images, idempotent (lecture avant écriture) ; une copie recréée est reprise au passage suivant ; un objet qui n'est plus le corps courant perd les deux variables.
- **API** : `LivingKnox.Anim.setGesture(npcId, geste)` sur l'autorité (« idle » efface l'entrée). Serveur : changement confié au relais des gestes (LK03-T05, section « Relais des gestes » ci-dessous : clients proches seulement, regroupé, borné) ; entrée plus ancienne ignorée. **Volet MP écrit, non validé.**
- **Contrôle MP du moteur** : les fichiers `AnimSets`/`actiongroups` des mods entrent dans la somme de contrôle comparée à la connexion (`AdvancedAnimator.load`, `ChecksumPacket.java:226`) : serveur et clients doivent avoir la même version des XML générés.

### Table des gestes

| Geste | État(s) | Nœud (fichier) | Clip | Conditions (en plus de `LKActor` = vrai) | Preuve vanilla |
|---|---|---|---|---|---|
| repos (`idle`, aussi `walk`/`run` à l'arrêt, geste inconnu) | `idle` | `LKActorIdle` (`lkactor_idle.xml`) | `Bob_Idle` | — | `AnimSets/player/idle/Idle.xml` |
| accroupi | `idle` | `LKActorCrouchIdle` (`lkactor_crouch.xml`) | `Bob_IdleSneak` | `LKGesture=crouch` | `player/idle/sneakidle.xml` |
| visée (pistolet ou sans arme) | `idle` | `LKActorAimHandgun` (`lkactor_aim.xml`) | `Bob_IdleAimHandgun` | `LKGesture=aim` | `player/aim/aim_handgun.xml` |
| visée (arme longue) | `idle` | `LKActorAimRifle` (`lkactor_aimrifle.xml`) | `Bob_IdleAimRifle` | `LKGesture=aim`, `Weapon=firearm` | `player/aim/aim_rifle.xml` |
| garde de mêlée (deux mains ou sans arme) | `idle` | `LKActorGuard2H` (`lkactor_guard.xml`) | `Bob_IdleAimBat` | `LKGesture=guard` | `player/aim/aim_2handed.xml` |
| garde (une main) | `idle` | `LKActorGuard1H` (`lkactor_guard1h.xml`) | `Bob_IdleAim1Hand` | `LKGesture=guard`, `Weapon=1handed` | `player/aim/aim.xml` |
| frappe (deux mains ou sans arme), en boucle | `idle` | `LKActorStrike2H` (`lkactor_strike.xml`) | `Bob_AttackBat01_Hit` | `LKGesture=strike` | `player/melee/2handed/2HDefault.xml` |
| frappe (une main), en boucle | `idle` | `LKActorStrike1H` (`lkactor_strike1h.xml`) | `Bob_Attack1Hand01_Hit` | `LKGesture=strike`, `Weapon=1handed` | `player/melee/1handed/1HDefault.xml` |
| tir (pistolet ou sans arme), en boucle : un coup par boucle de 1,0 s (vitesse 0,667), LK06-T03 | `idle` | `LKActorShootHandgun` (`lkactor_shoot.xml`) | `Bob_AttackHandgun` | `LKGesture=shoot` | `player/ranged/handgun/HandgunDefault.xml` |
| tir (arme longue), en boucle : 1,0 s (vitesse 0,5) | `idle` | `LKActorShootRifle` (`lkactor_shootrifle.xml`) | `Bob_AttackRifle` | `LKGesture=shoot`, `Weapon=firearm` | `player/ranged/firearm/FirearmDefault.xml` |
| rechargement (pistolet ou sans arme), en boucle : 1,875 s (vitesse 0,80) | `idle` | `LKActorReloadHandgun` (`lkactor_reload.xml`) | `Bob_Reload_Handgun_Load` | `LKGesture=reload` | `player/actions/LoadHandgun.xml` |
| rechargement (arme longue), en boucle : 2,167 s (vitesse 0,80) | `idle` | `LKActorReloadRifle` (`lkactor_reloadrifle.xml`) | `Bob_Reload_Rifle_Load` | `LKGesture=reload`, `Weapon=firearm` | `player/actions/LoadRifle.xml` |
| accroupi, mains en avant (corvées : feu, soins, LK05-T04) | `idle` | `LKActorKneel` (`lkactor_kneel.xml`) | `Bob_IdleLooting_Low` | `LKGesture=kneel` | `player/actions/LootLow.xml` |
| reddition, debout les deux mains levées, en boucle : 0,67 s de clip (vitesse 0,48, celle de l'emote ; corps entier ici, haut du corps seulement chez le joueur) (LK06-T12) | `idle` | `LKActorSurrender` (`lkactor_surrender.xml`) | `Bob_EmoteSurrender` | `LKGesture=surrender` | `player/emote/looped.xml` (+ `surrender.xml`) |
| fouille à hauteur de taille (corvée : ranger un meuble) | `idle` | `LKActorRummage` (`lkactor_rummage.xml`) | `Bob_IdleLooting_Mid` | `LKGesture=rummage` | `player/actions/Loot.xml` |
| marteau debout, sans outil ni bruit (corvée : bricoler) | `idle` | `LKActorHammer` (`lkactor_hammer.xml`) | `Bob_IdleHammering` | `LKGesture=hammer` | `player/actions/Build.xml` |
| cigarette, sans objet ni bruit (corvée, trait `smoker`) | `idle` | `LKActorSmoke` (`lkactor_smoke.xml`) | `Bob_IdleSmoke` | `LKGesture=smoke` | `player/actions/Smoke.xml` |
| assis, mains vers le feu (corvée : se chauffer) | `idle` | `LKActorWarmHands` (`lkactor_warmhands.xml`) | `Bob_SitGround_WarmHands` | `LKGesture=warmhands` | `player/sitonground-sitting-warmhands/sit_warmhands.xml` |
| marche (tout geste sauf `run`, `crouch`) | `walktoward`, `walktoward-network`, `pathfind` | `LKActorWalk` (`lkactor_walk.xml`) | `Bob_Walk` | `pathfind` : `bMoving=true` | `player/movement/defaultWalk.xml` |
| course | idem | `LKActorRun` (`lkactor_run.xml`) | `Bob_Run` | `LKGesture=run` ; `pathfind` : `bMoving=true` | `player/run/defaultRun.xml` |
| marche accroupie | idem | `LKActorCrouchWalk` (`lkactor_crouchwalk.xml`) | `Bob_WalkSneak` | `LKGesture=crouch` ; `pathfind` : `bMoving=true` | `player/movement/sneakWalk.xml` |
| attente d'un chemin | `pathfind` | `LKActorPathWaitIdle` (`lkactor_wait.xml`) | `Bob_Idle` | `bMoving=false` | `player/idle/Idle.xml` |
| attente accroupie | `pathfind` | `LKActorPathWaitCrouch` (`lkactor_waitcrouch.xml`) | `Bob_IdleSneak` | `LKGesture=crouch`, `bMoving=false` | `player/idle/sneakidle.xml` |
| ouvrir une fenêtre, 1er clip (geste ponctuel `openwindow`, LK04-T13) | `idle`, `pathfind` | `LKActorOpenWindowStart` (`lkactor_openwindowstart.xml`) | `Bob_WindowStruggle_Start` | `LKGesture=openwindow`, `LKActPhase=false` ; `pathfind` : `bMoving=false` ; événement `SetVariable` fin `LKActPhase=true` | `player/openwindow/start.xml` |
| ouvrir une fenêtre, 2e clip | idem | `LKActorOpenWindow` (`lkactor_openwindow.xml`) | `Bob_WindowStruggleSuccess` | `LKGesture=openwindow`, `LKActPhase=true` ; `pathfind` : `bMoving=false` ; `PlaySound` début `OpenWindow` | `player/openwindow/success.xml` |
| refermer une fenêtre, 1er clip (geste ponctuel `closewindow`) | idem | `LKActorCloseWindowStart` (`lkactor_closewindowstart.xml`) | `Bob_WindowCloseStart` | `LKGesture=closewindow`, `LKActPhase=false` ; `pathfind` : `bMoving=false` ; `SetVariable` fin `LKActPhase=true` | `player/closewindow/start.xml` |
| refermer une fenêtre, 2e clip | idem | `LKActorCloseWindow` (`lkactor_closewindow.xml`) | `Bob_WindowCloseSuccess` | `LKGesture=closewindow`, `LKActPhase=true` ; `pathfind` : `bMoving=false` ; `PlaySound` début `CloseWindow` | `player/closewindow/success.xml` |

Vitesses (`m_SpeedScale`) reprises des nœuds du joueur, en nombre (les variables `IdleSpeed`, `CombatSpeed`, `sneakLimpSpeedScale` du joueur n'existent pas sur un zombie). Toutes les boucles sont `m_Looped=true`.

### Gestes d'ouverture (LK04-T13)

Gestes **ponctuels** (`Anim.ACTS` : `openwindow`, `closewindow`) posés par l'autorité avec `Anim.startAct(npcId, geste, durée, angle)` **par-dessus** le geste voulu : `Anim.gestureOf` rend toujours le geste voulu (consignes, routines, équipement), `Anim.shownOf` le geste affiché (geste ponctuel en cours, sinon le geste voulu). Le geste s'éteint seul à son échéance (`Anim.expireActs`, passage de l'autorité) ou par `Anim.endAct`. Relais : l'entrée porte le geste affiché `g` et, pendant un geste ponctuel, l'angle `fa` vers lequel tourner le corps ; ces gestes sont gardés par le regroupement (`KEEP_GESTURES`). Deux clips à la suite, comme le nœud du joueur : le premier nœud pose `LKActPhase` à sa fin (événement `SetVariable`, traité pour tout personnage, `AnimNode.java:155`, `IsoGameCharacter.java:948, 3793`), le second est choisi sur `LKActPhase=true` ; `Anim.applyTo` efface `LKActPhase` à chaque changement de geste affiché (un nouveau geste repart de son premier clip). Nœuds dans `idle` et dans `pathfind` à l'arrêt seulement (`bMoving=false`) : un corps encore en marche garde la marche, le geste commence quand l'exécutant l'a arrêté. Sons `OpenWindow` / `CloseWindow` au début du second clip, comme le joueur (`ToggleWindow` n'en joue aucun). Aucun geste de porte : le joueur vanilla ouvre une porte sans animation (`ISOpenCloseDoor:getDuration()` = 0, `ToggleDoor`). Synchronisation avec la bascule : `deplacement.md`, section « Gestes d'ouverture et de fermeture ». LK04-T04 : deux gestes ponctuels sans nœuds propres, `force` (frapper une barricade ou une porte, joué par le clip `strike`) et `wait` (attendre devant un passage bloqué, clip de repos), choisis par `Anim.ACT_CLIP` (`Anim.clipOf` donne la valeur de `LKGesture`) ; renouvelés par l'autorité avant `ACT_MAX_MS` ; mêmes effets sur l'exécutant (corps arrêté, tourné vers `fa`) : `deplacement.md`, section « Passage bloqué : attendre ou forcer ».

### Choix et alternatives

- Retenu : nœuds ajoutés aux états existants, priorité de condition 5, variables propres `LKActor`/`LKGesture`. Écartés : remplacer un nœud vanilla par le même chemin (toucherait tous les zombies) ; un nouvel état ou des transitions d'`actiongroups` (il faudrait un état Java correspondant, `registerAIState`) ; `walkType` comme canal (réduit à 13 valeurs synchronisées, §4) ; `x_extends` vers un nœud vanilla (perdu sous Linux).
- Les 2D blends du joueur (visée vers le haut ou le bas) ne sont pas repris : posture fixe. Visée ou garde **en marchant** : clip de marche simple. Frappe : boucle tant que le geste reste `strike` (un coup unique demande une durée de clip, à décider avec le combat).
- Côté Lua, rien sur le serveur (il n'anime pas) ; la consigne de geste est un état complet versionné plutôt qu'un événement, pour qu'un client arrivé ou une copie recréée la retrouve.

### Tests

- Hors jeu : `tests/test_gen_animsets.py` (XML complets, chemins, collisions, exclusivité sur toutes les combinaisons, `--check`, fins de ligne CRLF), `tests/test_lk_anim.py` (variables posées sur les seules copies de PNJ, serveur sans écriture, idempotence, copie recréée, client arrivé après, table plus ancienne, commande `LKB.gesture`, lecture de `getAnimationDebug`).
- En jeu (mod de dev) : `LKB.gesture(id, geste)`, `LKB.anim(id)` (lecture locale : variables, état d'action, état d'animation, nœuds vivants et clips d'après `getAnimationDebug`, `J/characters/IsoGameCharacter.java:1545`) ; suite `lk.anims` (tag `world`, solo) : chaque geste au repos sélectionne son nœud, zombie ordinaire voisin sans variable ni nœud `LKActor*`, marche et course dans un état de déplacement avec nos nœuds.
- Protocole solo (`rstest-solo`, mod de dev installé) : `LKB.spawn(2, 0)` ; attendre qu'il soit debout ; `LKB.gesture(1, "aim")`, `"guard"`, `"strike"`, `"crouch"`, `"idle"` en regardant la posture ; `LKB.anim(1)` après chaque geste (nœud `LKActor…` attendu) ; un zombie ordinaire voisin garde sa démarche de zombie ; puis `RST.run({ suite = "lk.anims", tags = "world" })` ; `LKB.clear()`.

### Points ouverts (animations)

- ⚠ Rendu réel de chaque clip sur un corps de zombie (squelette commun, mais poses d'arme sans arme en main).
- ⚠ Vitesse de déplacement avec `Bob_Walk`/`Bob_Run` (mouvement porté par le clip) et dérive éventuelle de la frappe en boucle (mouvement différé du clip).
- ⚠ MP : variables posées chez chaque client (copies distantes en `walktoward-network`), table `animState` après reconnexion ; somme de contrôle des AnimSets identique serveur/clients ; serveur Linux (casse des dossiers, à confirmer par le journal du serveur de l'utilisateur).

## Relais des gestes (LK03-T05)

État : code et banc hors jeu le 2026-10-10 ; aucune mesure réseau réelle. Fichiers : `server/LivingKnox/LK_Relay.lua` (serveur), `LK_Anim.lua` et `LK_Presentation.lua` (clients), valeurs dans `LivingKnox.Config.RELAY`.

Avant : `animState` (table complète des gestes de tous les PNJ) à **tous** les clients à chaque changement, et `poseState` (une pose) à **tous** à chaque rapport accepté ; coût proportionnel au nombre total de joueurs (faiblesse relevée dans `docs/annexes/recherches/alife-analyse.md` §1). Après :

- **Contenu** : par PNJ, le geste voulu (`Anim.gestureOf`) et la dernière pose acceptée (`Directives.poses`) dans une même entrée. Message unique `animState` (module `LivingKnox`) : `{ d = { [npcId] = { r, g, p = { pr, v, s, a, x, y, z, t, ts } } | { r, gone = true } } }`. `r` : numéro d'envoi croissant (client : entrée de `r` inférieur ou égal au dernier reçu pour ce PNJ ignorée, livraison RELIABLE non ordonnée) ; `pr` : numéro de pose, inchangé ; `poseState` n'existe plus.
- **Destinataires** : ceux des consignes, sans code dupliqué (`Directives.targets` : joueurs à `NEAR_RADIUS` = 100 cases du corps en x et en y, et le propriétaire). Recalculés à chaque publication et toutes les `SCAN_EVERY` = 10 images (1 s sur un serveur dédié). Entré dans le rayon : état courant ; sorti : `{ gone }` (geste oublié, repos ; pose oubliée) ; PNJ disparu (`unknown`, `dead`, `virtual`) : `{ gone }` à ses détenteurs. Entrée en partie (`guardHello`) : tout ce qui est à sa portée, à l'image suivante.
- **Cadence et regroupement** : au plus un état publié par PNJ par `WINDOW_MS` = 150 ms ; l'état publié est l'état courant (dernier état gagnant : plusieurs changements de la fenêtre n'en font qu'un). Sur un serveur dédié à 10 images/s (`J/network/GameServer.java:261, 835-836`), une publication au plus toutes les 2 images, soit 5 par seconde et par PNJ.
- **Gestes ponctuels gardés** : `strike` (`KEEP_GESTURES`) et les poses finales (`arrived`, `stopped`, `faced`, `failed`) remplacés avant publication sont gardés (4 au plus par PNJ, au-delà : `WARN`) et publiés d'abord, chacun dans sa fenêtre ; un état important déjà publié n'est remplacé qu'une fois remis à **tous** ses destinataires (un client différé par le budget ne le saute pas). Les autres gestes (`idle`, `walk`, `run`, `crouch`, `aim`, `guard`) sont des états : seul le dernier compte.
- **Regroupement par client** : un message par client et par image, tous ses PNJ dedans.
- **Budget** : `MAX_PER_TICK` = 16 messages de gestes par image au total ; les clients au-delà gardent leur rang et passent en tête à l'image suivante ; chaque envoi porte l'état courant au moment de l'envoi (rien de figé, rien de perdu ; un client différé peut sauter un état intermédiaire non important).
- **Délai d'émission** (changement → envoi) : au plus `WINDOW_MS` + une image = 250 ms sur un serveur dédié ; un état gardé attend une fenêtre de plus (compté à part, `keptMaxDelay`).
- **Mesure** : `LivingKnox.Relay.stats` : `messages`, `entries`, `bytes` (estimés comme la sonde du mod de dev : chaînes et clés par longueur, nombres 8, booléens 1, tables 2), `byClient` (messages et octets par client), `second` (dernière seconde complète), `maxMsgsPerSec`, `maxBytesPerSec`, `maxPerTick`, `deferred`, `published`, `coalesced`, `kept`, délai `lastDelay`/`maxDelay`/`meanDelay()` (clients déjà servis seulement) ; ligne DEBUG par seconde de trafic : `gesture relay: N msg, N B in N ms (A n/nB, B n/nB), N deferred so far`. Suite en jeu `lk.executor` (test « move 9 squares », sur un serveur : ligne `[LKX] measure gesture relay during the move: …`).
- **Solo** : inchangé, aucun message (Anim et Directives lus directement).

Banc (`tests/test_lk_relay.py`, images de 100 ms) : même scénario (marche de 9 cases, puis `aim`, `strike`, `guard`, `idle` à une image d'intervalle) avec 2 joueurs puis 20 dont 2 proches : **18 messages, 1 804 octets estimés** dans les deux cas, reçus par A et B seulement ; délai d'émission maximal 200 ms ; `strike` remis malgré le regroupement ; geste final `idle` et pose finale `arrived` chez les deux. Aussi : 30 changements en 3 s → au plus un envoi par 2 images, dernier état remis ; budget à 2 pour 6 clients → 2, 2, 2 envois, chacun une fois, état courant remis au client différé ; `strike` reçu par chaque client différé avant `idle` ; deux PNJ dans un seul message par client ; entrée dans le rayon (état courant), sortie (`gone`), PNJ oublié (`gone`) ; compteurs par seconde et ligne DEBUG ; solo sans message.

Protocole MP (séance finale, serveur dédié + 2 clients, option Debug) : (1) un client près d'un PNJ, l'autre à plus de 100 cases ; `LKB.gesture(1, "aim")` puis `"idle"` : seul le proche voit le geste ; le journal du serveur porte `gesture relay: … (A n/nB)` sans le client lointain ; (2) le lointain s'approche : geste courant visible en 1 s environ ; (3) `RST.server({ suite = "lk.executor", tags = "world" })` : ligne `gesture relay during the move` à relever ; (4) délai visible : `LKB.pose(1)` chez le client non propriétaire (délai de relais de la pose, horloges synchronisées) pendant une marche, attendu < 300 ms sur réseau local.

Limites : `equipState` (arme) et `guardRoster` restent diffusés à tous ; le délai réseau réel n'est pas mesuré ; écran partagé non traité (un compte = un client).

## Apparition debout (LK02-T14)

État : code et banc hors jeu le 2026-10-11 (`tests/test_lk_stand.py` 12/12) ; rendu en jeu à vérifier. Fichiers : `shared/LivingKnox/LK_Stand.lua`, appel dans `LK_Bodies.createBody` (autorité) et dans `LK_ZombieGuard.adopt` (clients MP). Java 42.21.0.

**Cause (constat en jeu du 2026-10-11 : chaque PNJ apparaît allongé puis se relève).** `IsoDeadBody.reanimate` pose `setOnFloor(true)` et reprend `fallOnFront` du cadavre (`zombie/iso/objects/IsoDeadBody.java:1875-1880`), puis fait tourner l'`ActionContext` et l'animateur du zombie (`:1930-1937`). La transition vanilla `idle → onground` ne demande que `bOnFloor` (`media/actiongroups/zombie/idle/to_onground.xml`, variable liée à `isOnFloor`, `IsoGameCharacter.java:850`). `ZombieOnGroundState.enter` rend le corps non collidable et arme `reanimateTimer` à 30-90 (`ZombieOnGroundState.java:37-67, 157-159`) ; `onground` ne sort que vers `getup-fromOnBack`/`getup-fromOnFront` (clip `Zombie_GetUp`) quand le minuteur tombe à 0 (`media/actiongroups/zombie/onground/to_getup-*.xml`). D'où 1 à 3 s au sol puis le relevé, plus longtemps si un personnage debout est voisin (LK02-T11).

**Leviers écartés.**
- Ajouter une transition `onground → idle` réservée à `LKActor` : impossible, les actiongroups ne sont lus que dans le `media` du jeu (`ActionGroup.java:32-47`, `getMediaFile`), pas dans les mods.
- Nœud de relevé quasi instantané (AnimSets `onground`/`getup-*` sous `LKActor`) : purement visuel ; il garde le corps non collidable 1 à 3 s, dépend de `LKActor` posé avant la première image, et masquerait aussi le relevé d'un PNJ réellement renversé plus tard (exigence 3).
- `setOnFloor(false)` seul : l'état `onground` n'a aucune sortie sur `bOnFloor` faux ; le relevé se joue quand même.

**Voie retenue : remise debout par l'état Java, dans l'appel même de la réanimation.** L'`ActionContext` n'est pas exposé à Lua, mais `IsoGameCharacter.playbackRecordCurrentStateSnapshot` / `playbackSetCurrentStateSnapshot` le sont (`IsoGameCharacter.java:11516-11528`) : ils relèvent et imposent l'état d'action courant (`ActionStateContainer.java:199-243` ; `ActionStateSnapshot` = nom d'état + sous-états, objet opaque jamais indexé en Lua). Le patron « idle » est relevé une fois sur un zombie qui vient de naître (zombie temporaire de `createBody`, ou `OnZombieCreate`) : son `ActionContext` est sur l'état initial du groupe `zombie`, sans sous-état (`IsoZombie.java:412-413`, `VirtualZombieManager.java:324-325`, `ActionContext.java:210-213`). `LivingKnox.Stand.now(z)` : `setOnFloor(false)`, `setFallOnFront(false)`, `setKnockedDown(false)`, `setCollidable(true)` (ce que fait `ZombieGetUpState.exit`, `ZombieGetUpState.java:47-53`), état d'action imposé à `idle`, état Java changé tout de suite (`changeState(ZombieIdleState.instance())` ; sinon il ne suit qu'à la mise à jour suivante, `StateMachineComponent.java:67-87`), et, sur une machine qui affiche, `setAlpha(0)` : le moteur ramène l'alpha vers sa cible en quelques images (`IsoObject.java:3845-3870`), ce qui masque la seule image encore couchée et le fondu d'animation (0,3 s) du couché vers le debout. Échec (patron absent, erreur du moteur) : un `WARN` unique, la création réussit et le corps se relève comme avant.

**MP.** Le serveur remet sa copie debout dans le même appel Lua. Mais chaque client crée sa copie d'un corps réanimé dans `ZombieOnGroundState` : le serveur garde l'identifiant du cadavre réanimé dans chaque paquet (`NetworkZombieAI.java:198`, `ZombiePacket.java:242-244`) et le client force alors l'état au sol (`NetworkZombieSimulator.java:226-233`) — à la création du PNJ, à chaque entrée dans la zone et à chaque copie recréée. `LK_ZombieGuard.adopt` confie donc la copie à `Stand.watch` : remise debout si elle est couchée par ce seul effet, c'est-à-dire si ce client la simule, ou si l'état réseau de l'autorité (`getRealState`) est un état debout (`idle`, `walktoward`, `walktoward-network`, `pathfind`, `turnalerted`, `face-target`) ; sinon surveillance d'au plus `WATCH_MS` = 5 s (le premier paquet peut encore porter `onground` si le corps a été créé dans `OnTick`, après la mise à jour des zombies du serveur, `IngameState.java:1543, 1681`). Aucune position n'est touchée : rien ne glisse.

**Corps renversé plus tard.** Jamais touché : l'autorité ne remet debout qu'à la création ; un client ne surveille une copie que pendant `WATCH_MS` après son apparition et l'abandonne dès qu'il l'a vue debout. Le relevé vanilla reste donc pour un coup ou une chute.

**Tests.** Banc `tests/test_lk_stand.py` : corps debout au retour de `spawn` (serveur et solo, fondu en solo seulement), patron absent et erreur du moteur (création réussie, un seul `WARN`), corps renversé ensuite laissé au relevé vanilla, copies client (adoptée debout si l'autorité est debout, attente puis remise debout quand l'état réseau change, copie simulée ici, autorité restée au sol au-delà de `WATCH_MS`, copie vue debout puis renversée, vrai joueur réanimé jamais touché). Suite en jeu `lk.anims` : « a new npc is standing from its creation and never plays the get-up » (aucune image au sol ni `Zombie_GetUp` pendant 4 s) et « an npc put on the floor later gets up through the vanilla get-up ».

Protocole solo court (`rstest-solo`, mod de dev) : `LKB.spawn(2, 0)` en regardant le point d'apparition (le PNJ apparaît debout en fondu, sans se relever) ; `RST.run({ suite = "lk.anims", tags = "world" })` ; `LKB.clear()`.

Limites : rendu non vu en jeu ; client MP : la copie peut rester couchée le temps d'un paquet (non mesuré) puis se redresser en fondu ; une copie qui apparaît pendant le relevé réel de l'autorité est redressée sans le relevé ; une copie simulée par ce client à son apparition est redressée même si l'autorité était au sol (cas rare : coup reçu dans la seconde de la création).

## Points ouverts

- ⚠ Joueur réanimé créé par mod : propriété réseau, comportement de l'IA, mort et cadavre, coût de `reanimated.bin` — tout à mesurer.
- ⚠ Exception `ClassCastException` de `preupdate` après `setPrimaryHandItem` serveur : à confirmer dans le journal.
- ⚠ Coupure des voix sans effet de bord.
- ⚠ Zombie `useless` attiré par un cadavre voisin (recherche de nourriture non coupée) : fréquence et parade à mesurer.
- ⚠ Vitesse réelle d'une marche jouée avec un clip `Bob_Walk` sur un corps de zombie.

Observations solo hors tableau (2026-10-09) : sans `useless`, les corps B errent seuls (une dizaine de cases, `PathFindState`) sans cible ni attaque : poser `useless` hors des trajets et marcher en mode `pathfind`. Les identifiants d'essai continuent la numérotation de la suite (`LKE-16`…).

