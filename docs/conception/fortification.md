# Fortification d'un foyer : barricades et constructions vanilla posées par script

- Tâches : LK14-T01 (création, investigation) ; LK14-T02 (§6, plan de fortification, `LK_Fortify.lua`) ; LK14-T03 (§7, pose des barricades, `LK_Fortify.lua` + `LK_Routines.lua`) ; LK14-T04 (§8, murs et palissade du pourtour, `LK_Fortify.lua`) ; LK14-T06 (§9, entretien et réparation après une attaque, `LK_Fortify.lua`) ; LK14-T05 (§10, rattrapage hors écran, `LK_Fortify.lua` + accroche `LK_Simulation.lua` + `LK_Stock.lua`) ; LK13-T07 (§10.3, forme compacte du relevé gardé au registre, `LK_Fortify.lua`) ; sert LK14-T03 (barricades), LK14-T04 (murs et palissades en bois, décision du 2026-10-08), LK14-T05 (rattrapage hors écran), LK14-T06 (entretien et réparation)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\` ; Lua, scripts et tuiles vanilla sous `<PZ>\media`, noté **M/**) — Date : 2026-10-10 — Statut : brouillon

Base de connaissances : [barricades-and-constructions.md](../../../.claude/pz-knowledge/barricades-and-constructions.md) (faits génériques établis ici), [pathfinding-and-obstacles.md](../../../.claude/pz-knowledge/pathfinding-and-obstacles.md) (ce que le chemin d'un zombie traverse, portes), [power-and-lights.md](../../../.claude/pz-knowledge/power-and-lights.md) (portail grillagé `IsoThumpable` posé par script), [world-placement.md](../../../.claude/pz-knowledge/world-placement.md) (pose différée dans une zone chargée). Fiche voisine : [deplacement.md](deplacement.md) (portes, fenêtres, barricades vues par la recherche de chemin).

Aucune ligne de Bandits! ni de Project A-Life n'a été lue pour cette fiche.

Statuts : **confirmé statiquement** (lecture du Java ou du Lua 42.21.0), **déduit** (conséquence de plusieurs lignes, non mesurée), **à mesurer** (seul un essai en jeu peut trancher).

## Problème

Les groupes de PNJ renforcent leur foyer avec des matériaux réels : barricades de planches (puis de tôle ou de barres) sur les portes et fenêtres, puis murs et palissades en bois des constructions vanilla. Les PNJ n'étant pas des joueurs (corps = zombies, décisions sur le serveur), le mod ne peut pas passer par les actions chronométrées vanilla : il doit savoir créer lui-même, sur la bonne machine, des objets identiques à ceux d'un joueur, synchronisés, persistants, que les zombies frappent comme les autres et qu'un joueur peut démonter ou réparer.

## 1. Barricades

### 1.1 Chemin vanilla d'un joueur en 42.21

| Fait | Preuve | Statut |
|---|---|---|
| L'option « Barricader » du menu contextuel (portes, fenêtres, cadres, portes de joueur) est construite en Java et appelle `ISWorldObjectContextMenu.onBarricade(sprite)`, qui ouvre un **curseur de construction d'entité** (`ISBuildIsoEntity`) : planches `carpentry_01_8`, tôle `constructedobjects_01_24`, barres `constructedobjects_01_55`. | `J/iso/ISWorldObjectContextMenuLogic.java:1902-1928` ; `M/lua/client/ISUI/ISWorldObjectContextMenu.lua:3046-3052` | confirmé statiquement |
| `ISBarricadeAction` (marteau + planche en main, 2 clous) **n'est plus appelée** par le jeu : seule une suite de tests de débogage la crée. Ses `complete()` restent un bon modèle de code serveur (§1.3). | `M/lua/client/Tests/TimedActionsTests.lua:498, 511` ; aucune autre occurrence de `ISBarricadeAction:new` | confirmé statiquement |
| Entités vanilla : `BarricadePlanks` (marteau gardé, **1 planche, 1 clou**, durée 200, aucune compétence, XP Menuiserie 10), `BarricadeMetalSheet` (chalumeau, 1 tôle, baguettes de soudure, **Soudure 3**), `BarricadeMetalBar` (chalumeau, **3 barres** fer/métal/acier, 3 baguettes, Soudure 3). Le menu demande pourtant au moins 2 clous dans l'inventaire pour proposer les planches. | `M/scripts/generated/entities/barricades/entity_barricade_planks.txt:46-60`, `…_metalsheet.txt`, `…_metalbar.txt` ; `ISWorldObjectContextMenuLogic.java:1908-1915` | confirmé statiquement |
| Construction : l'action `ISBuildAction` du client envoie un paquet `BuildAction` ; le **serveur** recrée l'objet Lua de construction, lance l'événement `OnProcessAction("build")` et appelle `create()`. Les matériaux sont consommés côté serveur par `buildPanelLogic:performCurrentRecipe()`. | `M/lua/client/BuildingObjects/TimedActions/ISBuildAction.lua:127-153, 201-243` ; `J/core/BuildAction.java:114-162` ; `M/lua/shared/ActionManager.lua:26-51` ; `M/lua/server/BuildingObjects/ISBuildIsoEntity.lua:539-554` | confirmé statiquement |
| Pour une barricade, `create()` pose d'abord un `IsoThumpable` provisoire (serveur seulement), puis `BuildRecipeCode.barricade.OnCreate` ajoute une planche à la barricade existante **ou** en crée une (`addBarricadesFromCraftRecipe` → `AddBarricadeToObject(objet, opposite)`), retire l'objet provisoire et transmet : `transmitCompleteItemToClients()` pour une barricade neuve, `sendObjectChange(IsoObjectChange.STATE)` pour une planche ajoutée. | `M/lua/server/BuildRecipeCode/buildRecipeCode.lua:92-161` ; `J/iso/objects/interfaces/BarricadeAble.java:30-46` | confirmé statiquement |

### 1.2 L'objet `IsoBarricade`

| Fait | Preuve | Statut |
|---|---|---|
| Une barricade est un objet spécial de la case, **distinct** de la porte ou de la fenêtre, orienté N, S, E ou W. `AddBarricadeToObject(objet, addOpposite)` la place sur la case de l'objet (`N`/`W`) ou sur la case opposée (`S`/`E`), et rend la barricade déjà présente de ce côté s'il y en a une. Aucun contrôle d'autorisation, de porte ouverte ou de joueur : c'est à l'appelant de le faire. | `J/iso/objects/IsoBarricade.java:739-764` | confirmé statiquement |
| Variante « personnage » : `AddBarricadeToObject(objet, chr)` choisit le côté du personnage (`chr.getY() < objet.y` pour un objet nord). Il y a donc **deux barricades possibles** par ouverture, une de chaque côté. | `IsoBarricade.java:766-776, 719-737` | confirmé statiquement |
| Objets barricadables : `IsoDoor` (sauf portes doubles et de garage), `IsoWindow`, `IsoWindowFrame` sans fenêtre, `IsoThumpable` avec `canBarricade` (portes et fenêtres de joueur). | `J/iso/objects/IsoDoor.java:1699-1701` ; `J/iso/objects/IsoWindow.java:1106-1108` ; `J/iso/objects/IsoWindowFrame.java:104-106` ; `M/lua/server/BuildingObjects/ISBuildIsoEntity.lua:628-629` | confirmé statiquement |
| Planches : 4 au plus, 1000 PV chacune à neuf ; une planche vaut `état/étatMax × 1000 × getBarricadeStrengthMod()` (Menuiserie : 1 jusqu'au niveau 1, puis 1,1 à 1,5 au niveau 10). `addPlank(nil, nil)` donne une planche neuve à 1000 PV. Pas de planche sur une barricade de métal. | `IsoBarricade.java:62-67, 90-108, 147-149` ; `J/characters/IsoGameCharacter.java:4034-4063` | confirmé statiquement |
| Tôle : 5000 PV (`état × 5000 × getMetalBarricadeStrengthMod()`), sprite « abîmé » sous 2500 ; barres : 3000 PV prévus, mais `addMetalBar` avec un objet calcule `état × 5000`. Ni tôle ni barres sur une barricade qui a des planches. | `IsoBarricade.java:64-66, 151-206, 240-266` | confirmé statiquement (l'écart 3000/5000 est un défaut vanilla) |
| Vue et lumière : une barricade bloque la vue au-delà de 2 planches ou en tôle, pas en barres ; elle filtre la lumière (−15 % par planche, tôle opaque). | `IsoBarricade.java:234-236, 326-347, 916-925` | confirmé statiquement |
| **Une porte barricadée d'un côté ou de l'autre ne s'ouvre plus** (`ToggleDoor` refuse, son « bloqué ») ; une fenêtre barricadée ne se franchit plus (`canClimbThrough` faux) et ne s'ouvre pas du côté de la barricade. | `IsoDoor.java:1320-1325, 1690-1696` ; `IsoWindow.java:701-731, 1220-1226` | confirmé statiquement |
| Retrait : `removePlank(nil)` retire la planche extérieure (indice le plus haut) et rend un `Base.Plank` d'état proportionnel ; la dernière planche retirée efface la barricade (`transmitRemoveItemFromSquare` sur le serveur). `removeMetal`/`removeMetalBar` effacent toujours la barricade ; `removeMetalBar` rend une barre d'état ≤ 1 (`Math.min(…, 1.0f)`, défaut vanilla) et l'action vanilla rend 3 barres. **Les clous ne sont jamais rendus.** | `IsoBarricade.java:110-136, 172-188, 212-228` ; `M/lua/shared/TimedActions/ISUnbarricadeAction.lua:97-152` | confirmé statiquement |
| Outils du retrait vanilla : tag `REMOVE_BARRICADE` (pied-de-biche, marteau à arrache-clou…) pour les planches, chalumeau pour le métal ; durée `200 − 5 × Menuiserie` (−20 si « Bricoleur »). | `ISUnbarricadeAction.lua:5-23, 153-162` | confirmé statiquement |

### 1.3 Poser, compléter, retirer ou réparer par script sur le serveur

Modèle vanilla sans joueur : `IsoWindow.addRandomBarricades` (barricades des maisons à la génération) choisit le côté extérieur (case sans pièce), appelle `AddBarricadeToObject(fenêtre, addOpposite)`, `addPlank(null, null)` 1 à 3 fois, puis `transmitCompleteItemToClients()` sur un serveur (`J/iso/objects/IsoWindow.java:1324-1343`). Recette pour le mod (confirmée statiquement, non essayée) :

```lua
-- Serveur (ou solo), case chargée. obj : IsoDoor fermée, IsoWindow, IsoWindowFrame ou IsoThumpable barricadable.
local sq = obj:getSquare()
local outside = (sq:getRoom() == nil) and sq or obj:getOppositeSquare()
local barricade = IsoBarricade.AddBarricadeToObject(obj, outside ~= sq)   -- surcharge booléenne
local isNew = barricade:getNumPlanks() == 0 and not barricade:isMetal() and not barricade:isMetalBar()
barricade:addPlank(nil, plank)              -- plank = objet Base.Plank réel retiré du stock (ou nil : planche neuve)
if isNew then barricade:transmitCompleteItemToClients()          -- objet complet aux clients proches
else barricade:sendObjectChange(IsoObjectChange.STATE) end       -- 4 PV de planches + métal ; sprite et lumière recalculés
buildUtil.setHaveConstruction(sq, true)     -- drapeau de zone posé par toutes les actions vanilla
```

| Fait | Preuve | Statut |
|---|---|---|
| `addPlank`, `addMetal`, `addMetalBar` acceptent `chr = nil` (pas de bonus de compétence) et un objet `nil` (pleine santé). | `IsoBarricade.java:90-206` | confirmé statiquement |
| `AddSpecialObject` (appelé par `AddBarricadeToObject`) recalcule la case et ses voisines et met à jour la recherche de chemin (`PolygonalMap2.squareChanged`) sur la machine qui pose. | `J/iso/IsoGridSquare.java:4955-4991` | confirmé statiquement |
| Une barricade posée sur un **client** n'est jamais envoyée : `transmitCompleteItemToClients` et `sendObjectChange` n'agissent que sur le serveur (`sendObjectChange` ne fait que journaliser sur un client). | `J/iso/IsoObject.java:4265-4272, 4314-4322` | confirmé statiquement |
| **Réparation scriptée** : `barricade:setHealth(h)` met **toutes** les planches présentes à `h` (borné à 1000), ou la tôle/les barres ; aucune synchro : enchaîner `sendObjectChange(IsoObjectChange.STATE)`. Le jeu vanilla n'a **aucune** réparation de barricade : on retire la planche abîmée et on en cloue une neuve. | `IsoBarricade.java:551-563, 634-656` | confirmé statiquement |
| Retirer : `removePlank(nil)` ; si des planches restent, `sendObjectChange(IsoObjectChange.STATE)` (comme `ISUnbarricadeAction:complete`) ; sinon la barricade s'efface et se transmet seule. | `IsoBarricade.java:110-136` ; `ISUnbarricadeAction.lua:133-145` | confirmé statiquement |
| Persistance : la barricade est sauvegardée avec la case (direction, 4 PV de planches, métal, barres) et recharge son sprite. | `IsoBarricade.java:606-632` | confirmé statiquement |

## 2. Constructions B42 : murs, palissades, portails

### 2.1 Chemin vanilla

| Fait | Preuve | Statut |
|---|---|---|
| Les constructions du menu « Construire » sont des **entités** (`entity X { component SpriteConfig … component CraftRecipe … }`) ; l'objet posé est un `IsoThumpable` créé par `ISBuildIsoEntity:setInfo`, sur le serveur en MP (même chaîne `BuildAction` que §1.1). Les anciennes classes `ISWoodenWall`, `ISWoodenDoor`… ne servent plus qu'au tutoriel. | `M/lua/server/BuildingObjects/ISBuildIsoEntity.lua:501-763` ; `M/lua/client/Tutorial/Tutorial1.lua:482` | confirmé statiquement |
| `setInfo` : `IsoThumpable.new(cell, sq, sprite[, spriteOuvert], north, self)`, drapeaux déduits du sprite (`canPassThrough`, `isHoppable`, `isDoor`, `isDoorFrame`, `canBarricade`, `blockAllTheSquare`, `thumpDmg = 5` pour une porte), `buildUtil.setInfo` (nom = nom de l'entité, `dismantable`, `isThumpable`…), santé, son de bris, composants de l'entité (`GameEntityFactory.CreateIsoObjectEntity`), retrait de l'étape précédente (`transmitRemoveItemFromSquare`), `AddSpecialObject`, coin (`buildUtil.checkCorner`), `setExplored(true)`, `OnCreate` éventuel, `RecalcAllWithNeighbours(true)`, puis `transmitCompleteItemToClients()`. | `ISBuildIsoEntity.lua:595-763` ; `M/lua/server/BuildingObjects/ISBuildUtil.lua:57-99, 362-393` | confirmé statiquement |
| Santé : `santé de base du script + bonus × multiplicateur sandbox ConstructionBonusPoints + niveau × skillBaseHealth`, le niveau étant celui de la compétence la plus pertinente de la recette (Menuiserie ici) ; `santé max = santé`. | `ISBuildIsoEntity.lua:643-668` ; `J/SandboxOptions.java:150` | confirmé statiquement ; compétence retenue = **déduit** |
| Le 5ᵉ argument de `IsoThumpable.new` (table Lua) est **sauvegardé avec l'objet** ; la santé max, la santé, le nom, les drapeaux et la ModData aussi. | `J/iso/objects/IsoThumpable.java:395-416, 561-635` | confirmé statiquement |

### 2.2 Défenses en bois vanilla (scripts `M/scripts/generated/entities/`)

| Entité (nom = `getName()` de l'objet) | Sprites W / N | Santé | Matériaux et outils | Compétence | Franchissement par un zombie |
|---|---|---|---|---|---|
| `WoodenWallFrame` (cadre) | `carpentry_02_100` / `_101` | 50 + 20 × niv. | marteau ; 2 planches, 2 clous | Menuiserie 2 | **enjambé** (`HoppableW`) |
| `WoodenWallLvl1` (pose sur un cadre, `previousStage`) | `walls_exterior_wooden_01_44` / `_45`, coin `_27` | 450 + 20 × niv. | marteau ; 2 planches, 4 clous | Menuiserie 2 (menu < 4) | mur : frappé |
| `WoodenWallLvl2` / `Lvl3` | `_01_40`/`_41` ; `_01_24`/`_25` | 550 / 650 + 20 × niv. | idem | Menuiserie 4 / 6 | mur : frappé |
| `LogWall` (palissade de rondins) | `carpentry_02_80` / `_81` | 500 + 50 × niv. | **4 rondins**, 4 liens (draps déchirés, ficelle, corde, corde de draps), aucun outil | aucune | **clôture haute** (`TallHoppableW`) : jamais escaladée par un zombie, frappée |
| `WoodFenceLvl1` / `Lvl2` (clôture en bois) | `carpentry_02_40`/`_41` ; `_44`/`_45` | 250 / 350 + 20 × niv. | marteau ; 2 planches, 2 clous | Menuiserie 3 / 5 | **enjambée** (`HoppableW`) |
| `WoodFenceGate` (portail en bois) | `fixtures_doors_fences_01_4`/`_5`, ouvert `_6`/`_7` | 300 × niv. | marteau ; 4 planches, 4 clous, 2 charnières, 1 poignée | Menuiserie 3 | **enjambé fermé** (sprite fermé `HoppableW`) |
| `WoodenDoorLvl1` (porte, sur un cadre de porte) | `carpentry_01_48`/`_49`, ouvert `_50`/`_51` | 300 × niv. | marteau ; 4 planches, 4 clous, 2 charnières, 1 poignée | Menuiserie 3 | porte : frappée (`thumpDmg` 5) |

Preuves : `walls/entity_woodenwallframe.txt`, `walls/entity_wood_walllvl1.txt` à `lvl3.txt`, `walls/entity_logwall.txt:11-43`, `walls/entity_wood_fencelvl1.txt`, `lvl2.txt`, `walls/entity_wood_fencegate.txt`, `walls/entity_woodendoorlvl1.txt` ; propriétés de tuile `M/newtiledefinitions.tiles.txt:20077-20086` (`carpentry_02_80` : `TallHoppableW`, `WallW`), `:20288-20294` (`carpentry_02_100` : `HoppableW`), `:19376-19387` (`carpentry_02_40` : `HoppableW`), `:54606-54614` (`fixtures_doors_fences_01_4` : `HoppableW`, `doorW`), `:303281-303305` (murs en bois : `WallW`/`WallN`, `Material = Wood`). Franchissement : `J/iso/objects/IsoThumpable.java:975-1005, 1551-1569` ; `J/characters/IsoZombie.java:3051-3069`. Statut : confirmé statiquement.

Un mur complet vanilla coûte donc **cadre + mur = 4 planches et 6 clous** par segment ; le cadre seul ne protège rien. Le champ `LogicClass = WoodenWall` des scripts n'est lu par aucun code Java ou Lua 42.21 (aucune occurrence hors scripts).

### 2.3 Poser un mur ou une palissade par script sur le serveur

`ISBuildIsoEntity:create` exige un personnage (niveau de compétence, consommation par la logique de recette) : le mod reproduit `setInfo` à la main. Recette (confirmée statiquement, non essayée) :

```lua
-- Serveur (ou solo), case chargée. north = false pour la face W (sprite _44), true pour la face N (_45).
local sprite = north and "walls_exterior_wooden_01_45" or "walls_exterior_wooden_01_44"
local info = SpriteConfigManager.getObjectInfoFromSprite(sprite)       -- comme onBarricade
local t = IsoThumpable.new(getCell(), sq, sprite, north, {})           -- table sauvegardée : la garder vide
t:setName(info:getName())             -- "WoodenWallLvl1" : nom lu par previousStage, démontage, menus
t:setIsThumpable(true); t:setIsDismantable(true); t:setCanBarricade(false)
t:setCanPassThrough(false); t:setIsHoppable(false); t:setBlockAllTheSquare(false)
t:setMaxHealth(450 + 20 * niveau); t:setHealth(t:getMaxHealth())       -- avant l'ajout : setHealth synchronise dès que l'objet est posé
t:setBreakSound("ZombieThumpWoodCollapse")
GameEntityFactory.CreateIsoObjectEntity(t, info:getScript():getParent(), true)
sq:AddSpecialObject(t, -1)            -- recalcul de la case et PolygonalMap2.squareChanged
buildUtil.checkCorner(sq:getX(), sq:getY(), sq:getZ(), north, t, { corner = "walls_exterior_wooden_01_27" })
t:setExplored(true)
sq:RecalcAllWithNeighbours(true)
t:transmitCompleteItemToClients()
buildUtil.setHaveConstruction(sq, true)
```

| Fait | Preuve | Statut |
|---|---|---|
| Un portail ou une porte se crée avec le constructeur à deux sprites (`fermé`, `ouvert`) et `setIsDoor(true)` ; verrou par `setKeyId` + `setLockedByKey(true)` puis `sync()` sur le serveur (le verrou seul ne transmet rien). | `IsoThumpable.java:395-405, 2097-2111` ; base `power-and-lights.md` (portail grillagé) | confirmé statiquement |
| `buildUtil.checkCorner` ajoute un poteau d'angle (`IsoThumpable` `setCorner(true)`, traversable) quand deux murs se rejoignent à angle droit, sinon un trou reste à l'angle. | `ISBuildUtil.lua:54-99` ; `IsoThumpable.java:762-800` | confirmé statiquement |
| `IsoThumpable:setHealth` envoie `sync()` sur le serveur si l'objet est déjà sur sa case ; le paquet transporte ouverture, verrous, `keyId` et **santé**, pas la santé max (celle-ci part avec l'objet complet). | `IsoThumpable.java:288-297, 1671-1686` | confirmé statiquement |
| L'utilité de `CreateIsoObjectEntity` pour un mur (composants `UiConfig`/`SpriteConfig` sans interface) n'est pas établie ; vanilla l'appelle toujours. | `ISBuildIsoEntity.lua:678-684` | **à mesurer** (démontage, menu, rechargement sans lui) |
| Clé de `SpriteConfigManager.GetObjectInfo(nom)` (`"WoodenWallLvl1"` ou `"Base.WoodenWallLvl1"`) non vérifiée ; `getObjectInfoFromSprite` est sûr. Le nom de l'objet est le nom de script de l'entité (`ComponentScript.getName` → `getScriptObjectName`). | `J/entity/components/spriteconfig/SpriteConfigManager.java:82-90, 232-267` ; `J/scripting/entity/ComponentScript.java:30-35` | confirmé statiquement ; clé **à mesurer** |

## 3. Synchronisation, persistance et recherche de chemin

| Fait | Preuve | Statut |
|---|---|---|
| **Autorité : le serveur.** En MP vanilla, barricades et constructions sont créées par le serveur (`BuildAction` → `create`), qui consomme les matériaux et envoie l'objet. Un objet ajouté par un client n'est envoyé à personne. | §1.1 ; `IsoObject.java:4265-4272` | confirmé statiquement |
| `transmitCompleteItemToClients` envoie le paquet `AddItemToMap` (objet sérialisé complet) aux **connexions pour lesquelles la case est pertinente** (`sendToRelative`). À la réception, le client l'ajoute au monde, recalcule la case et ses voisines, la vue, la lumière, `MapCollisionData` et `PolygonalMap2.squareChanged`, puis déclenche `OnObjectAdded`. | `IsoObject.java:4265-4272` ; `J/network/packets/AddItemToMapPacket.java:32-99` | confirmé statiquement |
| Un client éloigné au moment de la pose reçoit l'objet quand il charge la zone, par les données de chunk du serveur. | — | déduit ; **à mesurer** |
| Modifications : `sendObjectChange(IsoObjectChange.STATE)` pour une barricade (planches, métal ; sprite et lumière recalculés à la réception) ; `sync()` pour un `IsoThumpable` (santé, porte) ; `transmitRemoveItemFromSquare` pour un retrait. | `IsoBarricade.java:634-656` ; `IsoThumpable.java:1671-1745` ; `IsoGridSquare.java:5072-5098` | confirmé statiquement |
| Persistance : barricades et `IsoThumpable` sont des objets de case sauvegardés avec leur chunk (santé, planches, nom, ModData) ; ils survivent au déchargement et au redémarrage sans code du mod. | `IsoBarricade.java:606-632` ; `IsoThumpable.java:428-470, 561-635` | confirmé statiquement |
| Pose impossible dans une zone non chargée : la case n'existe pas sur le serveur (`getGridSquare` rend `nil`) ; la pose différée se fait au chargement (`LoadGridsquare`, base `world-placement.md`). | base `world-placement.md` | confirmé statiquement (base) |
| Recherche de chemin d'un **zombie** : porte barricadée = porte fermée ; fenêtre barricadée traversée sans surcoût ; mur ou palissade de joueur (`IsoThumpable` frappable) traversé avec un surcoût 20, car il peut frapper. **Joueur** : construction pleine bloquante, fenêtre barricadée à 200. | [deplacement.md](deplacement.md) §2 ; `J/pathfind/nativeCode/SquareUpdateTask.java:139-150, 157-239` | confirmé statiquement |
| Collision : un mur `IsoThumpable` fermé bloque son bord (`TestCollide`), sauf `canPassThrough`, escalier ou coin ; `blockAllTheSquare` bloque toute la case. | `IsoThumpable.java:762-800` | confirmé statiquement |

## 4. Dégâts et réparation

| Fait | Preuve | Statut |
|---|---|---|
| Un zombie ne frappe une barricade, un mur ou une porte que s'il a une cible, suit un bruit, ou si `ZombieLore.ThumpNoChasing` est vrai ; les constructions de joueur exigent aussi `ZombieLore.ThumpOnConstruction` (vrai par défaut). Clôtures basses et portail en bois sont enjambés, jamais frappés (sauf zombie rampant). | `IsoZombie.java:3071-3109` ; `IsoThumpable.java:893-896, 975-1005` ; `J/SandboxOptions.java:1922` | confirmé statiquement |
| La cible d'une porte barricadée est la porte, qui renvoie le coup à sa barricade (côté du zombie d'abord) ; celle d'une fenêtre barricadée est directement la barricade. | `IsoThumpable.java:893-906, 975-985` ; `IsoWindow.java:404-416` ; `IsoZombie.java:3104-3108` | confirmé statiquement |
| **Barricade frappée** : `Damage(force du zombie × nombre de coups)` ; force 5 / 3 / 1 selon `ZombieLore.Strength` (3 par défaut, « normale »). Seule la **planche extérieure** perd des PV ; quand elle tombe à 0, son de bris et `sendObjectChange` ; à la dernière, retrait (`transmitRemoveItemFromSquare`) et réveil du bâtiment. Sur le serveur, chaque coup envoie aussi `sync()`. | `IsoBarricade.java:350-385, 459-497` ; `IsoZombie.java:3174-3185` ; `SandboxOptions.java:1909` | confirmé statiquement |
| **Mur ou porte de joueur frappé** : −1 PV par coup si au moins `thumpDmg` zombies (8 ; 5 pour une porte) sont à moins de 1,5 case, sinon une fraction `zombies proches / thumpDmg` accumulée ; à 0 PV, son de bris, `OnDestroyIsoThumpable`, contenu vidé au sol et retrait. Un zombie seul retire donc 1 PV tous les 8 coups (≈ 3 900 coups pour un `WoodenWallLvl1` à 490 PV). | `IsoThumpable.java:924-972, 1440-1458` ; `J/iso/IsoMovingObject.java:2168-2173` | confirmé statiquement ; cadence réelle des coups **à mesurer** |
| MP : les coups d'un zombie simulé par un client contre une porte ou un `IsoThumpable` partent au serveur (paquet `ZombieHitThumpable`, accepté seulement du propriétaire du zombie), qui applique les dégâts. Aucune branche équivalente pour une **barricade de fenêtre** frappée directement : `IsoBarricade.Thump` abîme la copie locale du client propriétaire. | `IsoThumpable.java:914-921` ; `J/network/packets/hit/ZombieHitThumpablePacket.java:62-80` ; `J/network/fields/hit/Thumpable.java:52-82` ; `IsoBarricade.java:350-385` | confirmé statiquement ; état du serveur après des coups sur une barricade de fenêtre **à mesurer** |
| Arme d'un joueur : barricade `Damage(dégâts de porte × 5)` (100 à mains nues), `IsoThumpable` `Damage(dégâts de porte)`, sur l'autorité seulement (`OnWeaponHitThumpable`). | `IsoBarricade.java:416-457` ; `IsoThumpable.java:1029-1078` ; base `combat-and-xp.md` | confirmé statiquement |
| **Réparation vanilla d'un mur** : mode « Réparer » des objets déplaçables (`ISMoveableSpriteProps:repairObject`) selon le `Material` de la tuile ; définition `Wood` : marteau et scie, 2 planches requises, 4 clous ou vis facultatifs, Menuiserie, **réussite au hasard**, santé remise au maximum et `sync()`. Les murs en bois vanilla portent `Material = Wood` ; la palissade porte `Material = Log`. | `M/lua/shared/Moveables/ISMoveableSpriteProps.lua:3537-3599, 4087-4130` ; `M/lua/shared/Moveables/ISMoveableDefinitions.lua:656-659` ; `newtiledefinitions.tiles.txt:303288, 20079` | confirmé statiquement ; menu proposé pour un mur et définition `Log` **à mesurer** |
| Réparation scriptée d'un mur : `t:setHealth(t:getMaxHealth())` sur le serveur (synchronise seule). | `IsoThumpable.java:288-297` | confirmé statiquement |

## 5. Conséquences pour LK14-T02 à T06

Constats, pas décisions : chaque tâche reste à trancher avec l'utilisateur si elle est `à décider`.

1. **Tout se pose sur le serveur**, par les mêmes appels que le code vanilla (§1.3, §2.3) : `AddBarricadeToObject` + `addPlank`/`addMetal` + transmission ; `IsoThumpable.new` + `setInfo` reproduit + `AddSpecialObject` + `transmitCompleteItemToClients`. Les objets obtenus sont ceux d'un joueur : sauvegardés, frappés, démontables, visibles par tous les clients proches.
2. **Matériaux réels (T03, T04)** : barricade = 1 planche + 1 clou par planche (entité 42.21 ; l'ancienne action prenait 2 clous), marteau requis ; mur = cadre (2 planches, 2 clous) + mur (2 planches, 4 clous), marteau ; palissade = 4 rondins + 4 liens, sans outil ; portail = 4 planches, 4 clous, 2 charnières, 1 poignée. Le mod retire ces objets du stock (`Remove` + synchro du conteneur) avant la pose, une seule fois, et passe la planche réelle à `addPlank` pour reprendre son état.
3. **Côté et passage (T03)** : une barricade, d'un côté ou de l'autre, **bloque l'ouverture pour tout le monde**, membres compris. L'entrée du foyer doit rester sans barricade (ou en recevoir une seulement quand le groupe est dedans) ; poser à l'extérieur comme `addRandomBarricades` (côté sans pièce).
4. **Défenses lourdes (T04)** : seuls les murs en bois (`WoodenWallLvl1-3`) et la palissade de rondins (`LogWall`) arrêtent un zombie ; clôtures en bois, cadres et portail en bois sont **enjambés**. Un portail qui doit arrêter les zombies demande une porte (`WoodenDoorLvl1` sur un cadre de porte), à vérifier en jeu. Poser les poteaux d'angle (`checkCorner`) pour fermer les coins.
5. **Travail visible (T03, T04)** : vanilla joue l'animation `Build` (marteau) ou `Loot` haut (palissade), le son `Hammering` et un bruit monde de rayon `20 × getHammerSoundMod()` qui attire les zombies (`ISBuildAction.lua:73-104`, `M/scripts/generated/timedactions.txt:828-858`). Pour un corps de PNJ, geste et son sont à jouer par le mod pendant une durée tirée de la recette (200), puis la pose a lieu sur le serveur ; rendu du geste sur un corps de zombie **à mesurer** ([corps-et-animations.md](corps-et-animations.md)).
6. **Rattrapage hors écran (T05)** : rien ne se pose dans une zone non chargée ; le serveur garde le chantier simulé et pose le résultat au chargement de la case (`LoadGridsquare`), avant qu'un joueur ne l'atteigne. Les objets posés persistent ensuite sans aide du mod.
7. **Entretien (T06)** : détecter les dégâts par `getNumPlanks()`/`getHealth()` d'une barricade et `getHealth()`/`getMaxHealth()` d'un mur ; seule la planche extérieure s'use. Réparer = retirer la planche abîmée (`removePlank`) et en clouer une neuve, ou `setHealth` + synchro (hors gameplay vanilla). Les dégâts sur une barricade de **fenêtre** frappée par un zombie qu'un client simule peuvent ne pas atteindre le serveur : à mesurer avant de fonder la détection sur l'état du serveur.
8. **Recherche de chemin** : barricades et murs de joueurs ne détournent pas le chemin d'un zombie (il compte frapper) ; un corps de PNJ, sans cible, s'arrête devant ([deplacement.md](deplacement.md) §5). Les trajets des membres doivent donc éviter eux-mêmes les ouvertures barricadées du foyer.

## 6. Plan de fortification du foyer (LK14-T02, `LK_Fortify.lua`)

Module serveur (autorité seulement), **lecture seule** : il dresse la liste des chantiers ; la pose revient à LK14-T03 (barricades), LK14-T04 (murs, palissade) et LK14-T05 (hors écran).

| Tier (priorité) | Chantiers | Visée | Ordre dans le tier |
|---|---|---|---|
| `ground` | ouvertures extérieures du bâtiment du foyer au niveau 0 : `IsoDoor` simple, `IsoWindow`, `IsoWindowFrame` sans fenêtre, `IsoThumpable` barricadable (un côté dans le bâtiment, l'autre dehors) | `PLANKS.ground` = 4 planches | cadre vide (trou), fenêtre, porte ; puis la plus éloignée du foyer, niveau, y, x, face |
| `upper` | mêmes ouvertures aux niveaux 1 .. `getMaxLevel()` | `PLANKS.upper` = 2 | idem |
| `outer` | bâtiment : murs en bois (`WoodenWallFrame` + `WoodenWallLvl1`) sur le pourtour du rectangle du bâtiment élargi de `OUTER_MARGIN` = 2 cases ; camp : palissade `LogWall` sur le pourtour du carré de `CAMP_RING` = 7 cases autour du foyer | cadre + mur (2 étapes) ; palissade (1 étape) | côtés N, E, S, W, position croissante |

- **Entrée libre** : la porte extérieure simple du rez-de-chaussée la plus proche de la case du foyer n'est jamais dans le plan (§1.2 : une barricade bloque la porte pour tous). Portes doubles et de garage (`isBarricadeAllowed` faux) : écartées (`skipped`). Une barricade de métal (d'un côté ou de l'autre) vaut une ouverture faite.
- **Brèche** : 2 × `GAP` + 1 = 3 segments laissés ouverts sur le côté du pourtour le plus proche de la case extérieure de l'entrée (distance du milieu du bord) ; camp ou bâtiment sans entrée : en face du foyer, sud d'abord à égalité. Le portail en bois vanilla est enjambé (§2.2) : aucune porte dans la brèche.
- **Segments écartés** : case non chargée, dans un bâtiment, eau, escalier, case impraticable (`isFree(false)` faux : arbre, meuble plein), bord déjà fermé (`isBlockedTo`). Un ouvrage vanilla déjà posé sur le bord (nom `WoodenWallFrame`, `WoodenWallLvl1-3`, `LogWall`) compte ses étapes faites. Pourtour de plus de `MAX_OUTER` = 96 segments : aucune défense extérieure (`outerSkipped`).
- **Matériaux restants et durée** (scripts vanilla, §2.2) : barricade = 1 `Base.Plank` + 1 `Base.Nails` par planche manquante, outil `HAMMER`, 200 unités par planche ; mur = 4 planches, 6 clous, 400 (cadre déjà posé : 2, 4, 200) ; palissade = 4 `Base.Log` + 4 liens (`RippedSheets`, `RippedSheetsDirty`, `Twine`, `Rope`, `SheetRope`), sans outil, 200. Unités des actions vanilla (≈ 48 par seconde réelle à vitesse 1, base `api-42-21.md`).
- **Reproductible** : même foyer et même monde → même plan (parcours en ordre fixe, tri total, identifiant `kind:x,y,zN|W`, clé `plan.key`), quel que soit l'ordre des objets sur les cases. **Aucun chantier hors du foyer** : ouvertures du seul bâtiment du foyer, segments dans `plan.bounds` (rectangle du pourtour plus une case).
- **Niveau 0..100** (`Fortify.levelOf(gid)`, interface `LivingKnox.Fortification` lue par `Decisions.fortificationOf`) : par tier, étapes faites / étapes visées, pondéré `WEIGHTS` (rez-de-chaussée 3, étages 1, pourtour 2) ; aucun chantier = 100. Plan en mémoire `PLAN_MS` (1 min réelle), journalisé quand il change ; zone non chargée : dernier plan (`stale`), sinon `nil` (valeur neutre 50 du cadre).
- **Faisable** : matériaux de l'inventaire de référence du stock (`Stock.reference` ; boîte de clous = 100 clous, recette `OpenBox100`), outil cherché dans les conteneurs du foyer (`Stock.findItem`, `hasTag(ItemTag.HAMMER)`) ; chantiers pris dans l'ordre du plan, matériaux réservés de l'un au suivant.
- **Cadre de décision** (`LK_Decisions`) : `groupInput.fortWork = Fortification.hasWork(gid)` ; `fortify` n'est noté que si toutes les réserves sont à 50 ou plus **et** qu'un chantier est faisable (faux : aucun score de fortification ; inconnu : comme avant), plus `FORT_THREAT` (5) par menace connue, plafonné à `FORT_THREAT_MAX` (20), quand un chantier est faisable et le niveau sous 100.
- **Point d'appel de LK14-T03** : `Fortify.siteFor(gid, mid)` rend au k-ième membre vivant de poste `builder` (numéro croissant) le k-ième chantier faisable (deux ouvriers n'ont jamais le même chantier ni les mêmes planches).

Choix pris par défaut (à confirmer) : 4 planches au rez-de-chaussée (vue bloquée au-delà de 2 planches, §1.2 : les postes de guet aux fenêtres perdent leur vue), 2 aux étages ; murs en bois autour d'un bâtiment, palissade autour d'un camp ; marge de 2 cases, carré de 7 cases, brèche de 3 segments ; pondération 3/1/2.

Limites : compétences (Menuiserie 2 pour un mur) non vérifiées (les PNJ n'ont pas de niveaux) ; draps déchirés (`DisplayCategory = Household`) absents de l'inventaire de référence, donc jamais comptés ; une ficelle (`Twine`, consommable à utilisations) compte pour un lien ; aux étages la case extérieure d'une ouverture peut ne pas exister (pose de la barricade à vérifier par LK14-T03) ; coins des murs (`checkCorner`) laissés à LK14-T04.

## 7. Pose des barricades par un membre (LK14-T03, `LK_Fortify.lua`)

Autorité seulement (module absent d'un client MP). Code : `Fortify.run`, `Fortify.nailPlank`, `Fortify.openingOf`, `Fortify.release` ; point d'accroche `LK_Routines.apply` (comportement `chore`), `Routines.leave`/`forget` (chantier libéré).

| Étape | Règle | Preuve / source |
|---|---|---|
| Qui | membre de poste `builder` (objectif `fortify`, `Decisions.assignDuties`) dont la cascade choisit `chore` (de jour, au foyer : `RULES.duty`) ; branché comme **corvée prioritaire** dans `Routines.apply`, avant l'entretien (`LK_Upkeep`) et la corvée visible. Aucun changement de `LK_Decisions.lua` : la cascade mène déjà un `builder` à `chore`, et `ctx.duty` porte le poste. | `LK_Decisions.lua` `RULES.duty`, `assignDuties` |
| Quoi | chantier de `Fortify.siteFor(gid, mid)` (k-ième faisable pour le k-ième ouvrier) de sorte `barricade` ; un chantier tenu par un autre membre (`state.claims`) n'est pas pris ; sans chantier : nouvel essai après `IDLE_MINUTES` (10) ; après un chantier : `REST_MINUTES` (2). | §6 |
| Où | case **intérieure** de l'ouverture (`site.inside`), tournée vers l'extérieur ; case encombrée : case libre voisine du même bâtiment (`Routines.exec.placeBeside`). Trajet manqué deux fois : chantier abandonné. | `Routines.exec` |
| Geste | `CFG.GESTURE` = `hammer` (nœud existant `lkactor_hammer`, clip vanilla `Bob_IdleHammering` de l'action `Build`, déjà joué par la corvée « bricoler ») pendant `PLANK_MINUTES` (2) minutes de jeu avant **chaque** planche ; remis debout par `Routines.leave`. Aucun nouveau nœud. | `tools/anim_table.json` ; `AnimSets/player/actions/Build.xml` |
| Effet (une planche) | phase `nail` posée avant l'appel (jamais deux fois). `nailPlank` relit tout **avant** toute prise : ouverture présente (même case, même face, `isBarricadeAllowed`), pas l'entrée du plan, porte fermée (`IsOpen`), pas de métal, planches sous la visée, marteau (`ItemTag.HAMMER`), une planche et un clou (ou une boîte) au foyer. Puis : boîte ouverte au besoin (§7.1), planche puis clou retirés par `Stock.takeItem` (conteneur, clients, référence dans la même écriture : ni perte ni vol), `IsoBarricade.AddBarricadeToObject(obj, addOpposite)`, `addPlank(nil, planche)` (état de la planche repris), transmission sur un serveur comme `BuildRecipeCode.barricade.OnCreate` (neuve : `transmitCompleteItemToClients` ; planche ajoutée : `sendObjectChange(IsoObjectChange.STATE)`), `buildUtil.setHaveConstruction`, plan invalidé. | `M/lua/server/BuildRecipeCode/buildRecipeCode.lua:91-161` ; `J/iso/objects/IsoBarricade.java:90-108, 739-764` ; `J/iso/IsoObject.java:4265-4272, 4314-4322` |
| Côté | celui de la barricade déjà commencée (la plus garnie) ; sinon le côté **extérieur** du plan (`site.opp`, comme `IsoWindow.addRandomBarricades`, §5.3) ; sans case de ce côté (étage), l'autre. | §1.3 |
| Fin | planches posées = `site.steps` : chantier fini (`stats.finished`) ; refus (matériaux partis, porte ouverte, ouverture disparue…) : chantier arrêté, raison au journal (`stats.skipped`). Interrompu (menace, autre consigne, corps retiré) avant une planche : rien de pris pour elle, chantier libéré. | banc |
| Entrée | jamais dans le plan (§6) et refusée par `nailPlank` (`home entry`) : la porte d'entrée reste praticable pour les membres. | `IsoDoor.java:1320-1325` |

### 7.1 Clous en boîte

Le kit de départ ne contient qu'une `Base.NailsBox`. Sans clou libre, la boîte est ouverte comme la recette vanilla `OpenBox100` : boîte retirée par `Stock.takeItem`, `container:AddItems("Base.Nails", BOX_NAILS)` dans le même meuble, `sendAddItemsToContainer` sur un serveur, puis `Stock.check(gid, { force = true })` (objets ajoutés acceptés). Bilan exact en clous : boîte (100) → 100 − n clous libres.

### 7.2 Tests

- Banc `tests/test_lk_barricade.py` (12 tests) : geste existant ; plan de la maison de test (deux fenêtres, entrée libre) ; ouvrier qui barricade les deux fenêtres (8 planches, 8 clous, boîte ouverte une fois, marteau gardé, planche abîmée reprise, entrée sans planche, stock relu sans perte ni vol, plus rien ensuite) ; matériaux qui limitent le travail ; sans marteau ou sans poste `builder` : rien ; interruption avant la planche : rien de pris, chantier libéré, debout ; refus de `nailPlank` (entrée, porte ouverte, métal, ouverture absente) sans rien prendre, barricade commencée complétée de son côté ; MP serveur + 2 clients (envois : barricade neuve puis 3 changements d'état par fenêtre, 100 clous envoyés une fois, mêmes vues chez A et B) ; suite listée ; sources sûres pour Kahlua.
- En jeu : `RST.run({ suite = "lk.barricade", tags = "world" })` (solo, dans une maison avec un meuble à conteneur et une ouverture extérieure autre que l'entrée).

### 7.3 Limites et points ouverts

- ⚠ Rendu réel à vérifier en jeu : barricade visible, identique chez deux clients (MP), persistante, démontable ; rendu du geste `hammer` sur un corps.
- Aucun son de marteau ni bruit monde (vanilla : `Hammering`, rayon `20 × getHammerSoundMod()`) : reste.
- Porte ouverte : chantier refusé (la fermer d'abord n'est pas fait).
- Clous au-delà de la limite de suivi du stock (`Stock.MAX_ITEMS` = 128) : non comptés par `Fortify.available`.
- Décisions à confirmer : geste `hammer` (le contrat citait `strike` ou `kneel`) ; barricade posée côté extérieur alors que l'ouvrier est dedans ; branchement en corvée prioritaire plutôt qu'en comportement de la cascade ; 2 minutes de jeu par planche.

## 8. Murs et palissade du pourtour (LK14-T04, `LK_Fortify.lua`)

Autorité seulement. Code : `Fortify.buildStep`, `Fortify.placeStructure`, `Fortify.entityInfo`, `Fortify.healthOf` ; même ouvrier et même boucle que §7 (`Fortify.run`, chantier de `siteFor`, verrou `state.claims`, `Routines.leave`/`forget`).

| Étape | Règle | Preuve / source |
|---|---|---|
| Qui, quoi | membre `builder` en corvée (§7) ; chantier `wall` (bâtiment) ou `palisade` (camp) du tier `outer` donné par `siteFor`, après les barricades (ordre du plan, §6). | §6, §7 |
| Où | case **intérieure** du bord (`site.inside` : la case porteuse pour les côtés N et W, la voisine pour E et S), tournée vers l'extérieur ; case encombrée : case libre voisine (`placeBeside`, hors bâtiment). | `Fortify.ringSegments` |
| Geste | `CFG.RING_GESTURES` : mur `hammer` (clip `Bob_IdleHammering`, action vanilla `BuildWallHammer` = `Build`), palissade `rummage` (clip `Bob_IdleLooting_Mid` ; vanilla `BuildWallNoTool` = `Loot` haut) ; `CFG.STAGE_MINUTES` (2) minutes de jeu avant **chaque** étape (200 unités vanilla par étape, comme une planche). | `M/scripts/generated/timedactions.txt:828-858` ; `tools/anim_table.json` |
| Étapes | mur : `WoodenWallFrame` (2 planches, 2 clous, marteau) puis `WoodenWallLvl1` **sur le cadre** (2 planches, 4 clous, marteau) ; palissade : `LogWall` (4 rondins, 4 liens parmi `RippedSheets`, `RippedSheetsDirty`, `Twine`, `Rope`, `SheetRope`, aucun outil). Une étape par appel ; l'étape suivante se déduit des ouvrages présents sur le bord (`getName` + face). | `M/scripts/generated/entities/walls/entity_woodenwallframe.txt`, `entity_wood_walllvl1.txt`, `entity_logwall.txt` |
| Contrôles (avant toute prise) | chantier **encore au plan** (même identifiant), hors brèche, dans `plan.bounds` ; bord chargé ; pas d'autre ouvrage ; première étape : sol praticable (`groundOk`), case voisine hors bâtiment et hors eau, bord libre (`isBlockedTo`) ; mur : cadre présent ; fiche d'entité trouvée par le sprite et de **même nom** (sprite repris par un autre mod : refus) ; marteau ; tous les matériaux (objets distincts) ; clous libres insuffisants : boîte ouverte comme §7.1. | `Fortify.buildStep` |
| Prise | chaque objet retiré par `Stock.takeItem` (conteneur, clients, référence) ; une prise qui échoue remet les objets déjà pris dans leur conteneur (rien n'est perdu). | §7 |
| Pose | `IsoThumpable.new(cell, sq, sprite, north, {})` (table vide : non sauvegardée) ; drapeaux tirés des propriétés du sprite (`canPassThrough`, `hoppable`, `blockAllTheSquare`, `isFloor`) ; `buildUtil.setInfo` (nom de l'entité, `dismantable`, `isThumpable` du script, `thumpDmg` 8) ; santé `setMaxHealth`/`setHealth` **avant** la pose ; son de bris du script ; `GameEntityFactory.CreateIsoObjectEntity(t, script:getParent(), true)` ; mur : cadre retiré par `transmitRemoveItemFromSquare` et remplacé au même indice (`AddSpecialObject(t, index)`) ; poteau d'angle ; `setExplored(true)` ; `RecalcAllWithNeighbours(true)` ; `transmitCompleteItemToClients()` sur un serveur ; `buildUtil.setHaveConstruction`. | `M/lua/server/BuildingObjects/ISBuildIsoEntity.lua:595-763` ; `ISBuildUtil.lua:57-99, 362-393` |
| Santé | `max(santé du script, 0) + bonus × multiplicateur ConstructionBonusPoints + niveau × skillBaseHealth`, **niveau = plus haut niveau requis par la recette** (Menuiserie 2 pour le cadre et le mur, 0 pour la palissade) : cadre 90, mur 490, palissade 500 (bonus 0 dans ces scripts). | `ISBuildIsoEntity.lua:637-668` |
| Poteau d'angle | règle de `buildUtil.checkCorner` (mur perpendiculaire sur la case diagonale, aucun mur `WallN`/`WallW` sur la case du coin) puis `buildUtil.addCorner` (poteau `walls_exterior_wooden_01_27`, transmis) ; **un seul poteau** : vanilla relance `checkCorner` à chaque étape et en ajoute un second quand le mur remplace le cadre (le poteau, `WallSE`, n'est pas vu par `getWallFull`) ; ici un poteau déjà présent (`isCorner`) suffit. Sur le rectangle du pourtour, la règle vanilla n'en pose qu'au coin sud-est (seul coin dont la case du coin ne porte aucun des deux murs) ; fermeture réelle des coins à vérifier en jeu. Palissade : aucun poteau (`LogWall` n'a pas de `corner`). | `ISBuildUtil.lua:57-99` ; `J/iso/IsoGridSquare.java:3873-3880` ; `newtiledefinitions.tiles.txt:303050-303063` |
| Fin | étapes faites = `site.steps` (2 pour un mur, 1 pour une palissade) : chantier fini ; refus : chantier arrêté, raison au journal. Plan invalidé après chaque étape (niveau du foyer à jour). | §7 |
| Synchronisation, persistance | objets vanilla posés par le serveur (`AddItemToMap`), cadre retiré pour tous (`RemoveItemFromMap`), poteau transmis par `addCorner` ; sauvegardés avec leur case sans code du mod (§3). | §3 |

Brèche et foyer : la brèche (§6) n'est jamais dans le plan et `buildStep` la refuse ; aucun bord hors du plan (`not in the plan`) ni hors de `plan.bounds` (`outside the home`) n'est construit.

### 8.1 Tests

- Banc `tests/test_lk_walls.py` (10 tests) : plan réduit au pourtour (brèche de 3 segments au sud en face de l'entrée, cases intérieure et extérieure des côtés) ; gestes existants ; ouvrier qui monte deux segments (cadre puis mur, santé 490, entité, 8 planches et 12 clous retirés, boîte ouverte une fois, marteau gardé, stock relu sans perte ni vol, plus rien ensuite) ; cadre existant : étape du mur seule, cadre remplacé ; refus sans rien prendre (brèche, hors du foyer, clous manquants, sans marteau) ; poteau d'angle unique au coin sud-est ; palissade (4 rondins, 4 liens, sans outil, aucun poteau) ; MP serveur + 2 clients (envois : cadre neuf, cadre retiré, mur neuf ; 100 clous envoyés une fois ; rien sur les clients) ; suite listée ; source sûre pour Kahlua.
- En jeu : `RST.run({ suite = "lk.walls", tags = "world" })` (solo, dans une maison avec un meuble à conteneur et un terrain dégagé à 2 cases autour).

### 8.2 Limites et points ouverts

- ⚠ Rendu réel à vérifier en jeu : mur et poteau visibles, identiques chez deux clients (MP), persistants après redémarrage, démontables et réparables par un joueur ; rendu du geste sur un corps ; `CreateIsoObjectEntity` sur un mur posé par script.
- ⚠ `SpriteConfigManager.getObjectInfoFromSprite` doit rendre la fiche de l'entité pour chaque sprite (non vérifié en jeu ; refus journalisé sinon, aucun matériau pris).
- Aucun son ni bruit monde (vanilla : `BuildingGeneric`/`Hammering`, bruit qui attire les zombies) : reste, comme §7.
- Les draps déchirés (`Household`) ne sont pas suivis par le stock : la palissade ne compte que ficelle, corde et corde de draps comme liens ; une ficelle entière vaut un lien.
- Un membre ou un zombie sur la case intérieure n'empêche pas la pose (bord, pas case) ; un ouvrier hors du pourtour (case intérieure inaccessible) peut se retrouver dehors une fois le mur fermé : il passe par la brèche.
- Décisions à confirmer : niveau de compétence = niveau requis par la recette (santé 490 par mur) ; geste `rummage` pour la palissade ; 2 minutes de jeu par étape ; poteau d'angle posé une seule fois (écart volontaire au vanilla).

## 9. Entretien et réparation après une attaque (LK14-T06, `LK_Fortify.lua`)

Autorité seulement. Code : `Fortify.outerCondition`, `Fortify.healthRatio`, `Fortify.repairParts`, `Fortify.urgent`, `Fortify.repairShortage`, `Fortify.needOf`, `Fortify.repair` ; même ouvrier, même boucle et même verrou que §7 (`Fortify.run`, `siteFor`, `state.claims`).

| Étape | Règle | Preuve / source |
|---|---|---|
| Repérage | relevé (`survey`) : état de la **planche extérieure** de la barricade de bois la plus garnie de chaque ouverture (`getThumpCondition`, seule planche usée par les coups) ; santé relative des murs achevés (`WoodenWallLvl1-3`) et des palissades (`LogWall`). Sous `CFG.REPAIR_BELOW` (0,75) : chantier `repair` (cible `barricade`, `wall` ou `palisade`, tier de l'ouvrage, 1 étape). | `J/iso/objects/IsoBarricade.java:459-497, 536-549` |
| Planche retirée | barricade sous sa visée (planche arrachée ou chantier en cours) = chantier de barricade ordinaire (§7), **jamais** un chantier `repair` : la planche ajoutée devient la planche extérieure. Une barricade complète seulement reçoit une réparation (aucun chevauchement de chantiers sur la même ouverture). Cadre de mur seul : l'étape du mur le remplace (pas de réparation). Métal : non réparé (reste). | §1.2, §8 |
| Priorité | `Fortify.urgent(gid)` : marque `LivingKnox.Defense.after(gid)` (fin d'une défense, LK05-T09) de moins de `CFG.REPAIR_URGENT_MINUTES` (1440 = un jour de jeu). Plan urgent : réparations (rez-de-chaussée, étages, pourtour), puis barricades entamées, puis le reste. Sinon : plan de §6, réparations en dernier. Le plan en mémoire est refait dès que l'urgence change (clé `urgent;…`). | `LK_Defense.lua` `finish`, `Defense.after` |
| Niveau | un chantier `repair` compte une étape non faite dans le tier de son ouvrage : les dégâts baissent le niveau (`levelOf`) et poussent l'objectif `fortify` du cadre de décision, sans changer `LK_Decisions`. | §6 |
| Barricade | `repairPlank` : tout relu avant la prise (ouverture, barricade de bois, planche extérieure encore sous le seuil, marteau, **planche saine** d'état au moins `REPAIR_BELOW`, clou ou boîte) ; planche et clou retirés par `Stock.takeItem` ; `removePlank(nil)` (planche abîmée rendue au conteneur de la planche neuve, comme `ISUnbarricadeAction` la rend au joueur) ; `addPlank(nil, planche)` ; un `sendObjectChange(STATE)` sur un serveur ; dernière planche retirée : barricade recréée (`AddBarricadeToObject`) et envoyée complète. Geste `hammer`, `REPAIR_MINUTES.barricade` = 4 min (retrait 200 + pose 200 unités). | `IsoBarricade.java:85-136` ; `M/lua/shared/TimedActions/ISUnbarricadeAction.lua:97-152` |
| Mur, palissade | `repairStructure` : recette vanilla `Wood` / `Log` (`ISMoveableDefinitions.lua:656-668`) sans hasard ni compétence : marteau **et scie** (tag `SAW`), pièce requise (planches ou rondins) et une pièce facultative (première présente : clous, vis ; palissade : clous, vis, draps déchirés, draps, corde), quantités `floor(max(n × dégâts, 1))` ; boîte de clous ouverte si aucune facultative libre ; matériaux retirés une seule fois (remis si une prise échoue) ; `setHealth(getMaxHealth())` (synchronisé par le Java sur un serveur). Geste `hammer`, `REPAIR_MINUTES.wall/palisade` = 10 min (1000 unités vanilla). | `ISMoveableSpriteProps.lua:840-869, 3538-3599` ; `J/iso/objects/IsoThumpable.java:288-297` |
| Besoin | réparation non faisable (matériaux ou outils) : `Fortify.repairShortage` (manques après les chantiers faisables) → `Fortify.needOf(gid)` (`{ materials, tools, sites, text, attack }`, mémoire) et entrée `shortage` au journal du groupe (« materials to repair N defence(s): 1 Base.Plank (after def-3) ») une fois par attaque et au plus toutes les `NEED_HOURS` (6 h) pour un même besoin ; effacé quand plus rien ne bloque. Calculé à chaque `Fortify.feasible` (notation horaire du groupe, `siteFor`). | — |

Choix pris par défaut (à confirmer) : besoin remonté par le **journal du groupe** (kind `shortage`, comme les pénuries de `LK_Stock`) et `Fortify.needOf` ; ni `Stock.needs` (catégorie « materials » = planches et clous comptés en vrac, pas le manque d'une réparation) ni l'objectif `supply` (qui ne lit que nourriture, eau, soins, munitions) ne sont modifiés : un consommateur (expéditions LK05-T05, missions) lit `needOf`. Seuil 0,75 ; urgence d'un jour de jeu ; réparations toujours réussies (vanilla : 17 % au niveau 0 de Menuiserie, pièces perdues en cas d'échec) ; scie exigée comme le vanilla ; planche abîmée rendue au conteneur.

### 9.1 Tests

- Banc `tests/test_lk_repair.py` (13 tests) : chantier `repair` d'une barricade complète abîmée, en dernier sans attaque, en tête après la marque (puis barricade entamée), fin de l'urgence après `REPAIR_URGENT_MINUTES` ; barricade saine ou incomplète non réparée ; ouvrier qui répare d'abord après l'attaque (planche saine à l'extérieur, 4 planches, une planche et un clou retirés, planche abîmée rendue, stock relu sans perte ni vol, aucun besoin) ; refus relus avant toute prise (marteau, déjà réparée, métal) ; dernière planche remplacée (barricade recréée) ; planches absentes : besoin `1 Base.Plank` au journal une fois, de nouveau après une autre attaque, effacé au retour des planches ; mur à 200/490 réparé avec 1 planche et 2 clous (marteau et scie gardés) ; sans scie : besoin d'outil, rien pris ; MP : un seul `sendObjectChange(STATE)` et la planche rendue envoyée, un seul `sync` du mur ; suite listée et sûre pour Kahlua.
- En jeu : `RST.run({ suite = "lk.repair", tags = "world" })` (solo, dans une maison avec un meuble à conteneur et une ouverture extérieure sans barricade autre que l'entrée).

### 9.2 Limites et points ouverts

- ⚠ Rendu réel à vérifier : planche remplacée visible chez deux clients (MP) ; mur réparé (santé) relu après reconnexion.
- ⚠ Barricade de fenêtre frappée par un zombie simulé par un client : l'usure peut ne pas atteindre le serveur (§4) ; le repérage lit l'état du serveur.
- Barricades de métal non réparées ; vis comptées seulement si présentes en quantité ; `Tag.Rope` réduit à `Base.Rope`.
- La planche abîmée rendue peut être reclouée plus tard par une barricade ordinaire (§7 prend la première planche venue) : elle redevient alors une réparation.
- Pas de son de marteau ni de bruit monde (comme §7, §8).

## 10. Rattrapage hors écran (LK14-T05, `LK_Fortify.lua`)

Autorité seulement. Code : `Fortify.snapshot`, `Fortify.offscreenHour`, `Fortify.offscreenLevel`, `Fortify.offscreenFeasible`, `Fortify.applyPending`, `Fortify.scan`, `Fortify.addPlanks` (pose de planches extraite de `nailPlank`) ; `Stock.offscreenCount`, `Stock.offscreenTake` (`LK_Stock.lua`) ; accroche d'une ligne dans `Simulation.advance` (après `Stock.offscreenHour`). Le fichier `LK_Offscreen.lua` cité par la tâche n'existe pas : la simulation hors écran est `LK_Simulation.lua`. Modèle suivi : stock hors écran de LK09-T06 ([stock.md](stock.md), section « Hors écran »).

Rien ne se pose hors de la zone chargée (§3, §5.6) : la simulation avance un **relevé** gardé au registre privé des groupes, et le résultat est posé par les fonctions de pose existantes quand la zone du foyer est chargée.

| Étape | Règle | Preuve / source |
|---|---|---|
| Relevé | Champ facultatif `fort` du groupe (schéma 1 des groupes inchangé, contrôlé par `LK_Fortify`, ignoré par `LK_Groups` comme `stock`), gardé en **forme compacte** depuis LK13-T07 (§10.3) ; vue de travail (`Fortify.fortView`) : `{ v, hx, hy, hz, key, day, tools, tiers = { [tier] = { h, s } }, sites = { { id, k, t, x, y, z, n, o, s, h } }, work, boxes = { { i, u } }, pend = { n, ops } }`. Écrit par `Fortify.feasible` quand le plan vient d'un relevé du monde (pas `stale`) et que rien n'attend d'être posé, seulement s'il a changé (clé = clé du plan + outils + portes ouvertes écartées) : chantiers restants `barricade`, `wall`, `palisade` dans l'ordre du plan ; réparations et portes ouvertes écartées (refusées en jeu : `door open`) ; étapes faites et visées par tier (niveau) ; outils présents au foyer. Tenu à jour chaque minute de jeu (`Fortify.scan`) pour un foyer chargé dont le plan a expiré ou a été invalidé (chaque planche, chaque étape). Relevé invalide : ignoré, remplacé au prochain relevé. | §6 |
| Qui travaille | De jour (`Simulation.isNight` de l'heure du jour de début de l'heure simulée) ; groupe sans membre incarné (`Simulation.materialized` : sinon les vrais ouvriers de §7-§8 travaillent) ; chaque membre vivant de poste `builder`, au foyer (hors équipe d'expédition), non incarné. Le cadre de décision garde ses postes hors écran : `Fortify.hasWork` et `Fortify.levelOf` lisent le relevé quand le plan est absent ou ancien (`offscreenFeasible`, `offscreenLevel`). | `LK_Decisions` `assignDuties`, `RULES.duty` |
| Temps | `CFG.OFF_WORK_MINUTES` (30) minutes utiles par ouvrier et par heure (trajets et pauses du travail visible) ; une étape coûte `PLANK_MINUTES` (planche) ou `STAGE_MINUTES` (cadre, mur, palissade), comme §7-§8 ; le reste de minutes est gardé (`work`) tant qu'un chantier attend, remis à zéro sinon. | §7, §8 |
| Ordre et matériaux | Chantiers dans l'ordre du plan ; un chantier n'avance que si **tout ce qui lui reste** tient dans le stock (comme `feasibleSites`) et que son outil est présent, sinon il est passé. Une étape prend ses matériaux dans la référence du stock, une seule fois, par son journal d'écarts (`Stock.offscreenTake` : ajouts en attente annulés d'abord, puis écarts `take`, appliqués aux conteneurs à l'arrivée comme ceux du repas abstrait). Clous : libres d'abord, puis boîtes suivies (`BOX_NAILS` clous chacune, clous utilisés notés dans `boxes` ; la boîte reste dans la référence jusqu'à son ouverture réelle ; une boîte encore en attente d'ajout ne compte pas). | [stock.md](stock.md) « Hors écran » |
| Écart de pose | Étape faite : `h` du chantier et de son tier avancés ; écart `{ u, id, k, x, y, z, n, o, a, b }` (étapes avant, après) au journal de pose, un par chantier et par heure ; plan en mémoire invalidé. Logique pure, sans hasard ni accès au monde : même registre que les heures passent une par une ou en rattrapage. | `LK_Simulation` |
| Arrivée | `Fortify.scan` (`LoadChunk` au plus une fois par seconde, chaque minute de jeu) et `Fortify.feasible` (avant tout chantier en jeu) appliquent le journal dès que le relevé du foyer réussit (coins du pourtour chargés, donc bien avant qu'un joueur n'atteigne le foyer). Barricade : `Fortify.addPlanks` (planches neuves, une transmission) du côté de §7 ; mur, palissade : `Fortify.placeStructure`, étape par étape, contrôles de `buildStep` sans prise. On pose jusqu'à `b` étapes en partant de l'**état réel**, jamais plus que `b − a`. Boîtes entamées : ouvertes comme `OpenBox100` (`BOX_NAILS − u` clous ajoutés au conteneur de la boîte, `sendAddItemsToContainer`, boîte retirée par `Stock.takeItem`), puis `Stock.check` (clous acceptés). | §1.3, §2.3, §7.1 |
| Idempotence | Une écriture du registre ôte les écarts traités (par numéro) ; marque `ModData.LKFortOp = "<groupe>:<numéro>"` sur l'**ouverture** barricadée (la ModData d'une `IsoBarricade` n'est pas sauvegardée : `J/iso/objects/IsoBarricade.java:621-632` n'appelle pas `IsoObject.save`, `J/iso/IsoObject.java:1514` ; `IsoWindow`, `IsoDoor`, `IsoThumpable` la sauvegardent) ou sur le dernier ouvrage, `"<groupe>:box:<id>"` sur les clous créés, effacée après l'écriture. Écriture perdue : l'objet marqué est repris, l'état réel déjà à `b` n'est pas reposé, la boîte déjà ouverte est reconnue à ses clous marqués : ni double, ni second achat. | base `barricades-and-constructions.md` |
| Refus | Ouverture disparue, entrée, porte ouverte, métal, autre ouvrage sur le bord, étape précédente absente, sol ou bord devenus impropres, fiche d'entité absente : écart abandonné (avertissement), matériaux non rendus. Case non chargée, erreur : écart gardé, réessayé. | — |

**État posé = état simulé** : après l'application, le plan relevé dans le monde a le niveau et les étapes faites du relevé simulé (banc).

**Multijoueur** : tout sur l'autorité ; le relevé reste dans le registre privé ; barricades et ouvrages partent aux clients par les transmissions vanilla de `addPlanks`/`placeStructure` (une barricade neuve envoyée complète une fois, quel que soit le nombre de planches) ; un client qui charge la zone plus tard reçoit les objets avec la case.

Choix pris par défaut (à confirmer) : 30 minutes utiles par ouvrier et par heure de jour ; travail hors écran seulement de jour et pour les membres de poste `builder` ; aucune réparation hors écran (aucun dégât n'y est simulé) ; écart abandonné sans rendre les matériaux ; portes ouvertes écartées du relevé.

### 10.1 Tests

- Banc `tests/test_lk_fortify_offscreen.py` (12 tests) : relevé (chantiers, outils, tiers ; niveau et chantiers faisables tirés du relevé hors zone) ; rien la nuit, sans ouvrier ou avec des corps ; une heure hors écran barricade les deux fenêtres (8 planches en écarts du stock, 8 clous de la boîte notés), rien posé hors zone, puis à l'arrivée 4 planches par fenêtre dehors, entrée libre, boîte ouverte (92 clous), stock appliqué, aucune marque restante, plan relu = niveau simulé, aucun double aux examens suivants ; budget de temps sur cinq heures (reste gardé) puis cadre et mur posés à l'arrivée ; application interrompue (écriture perdue, mémoire perdue) reprise sans double ; état réel déjà à la cible non reposé ; accroche de `Simulation.step` ; MP serveur + 2 clients (une barricade neuve envoyée par fenêtre, 92 clous envoyés une fois, module absent des clients) ; suite listée et jouée sur doublures ; sources sûres pour Kahlua.
- Banc `tests/test_lk_fortify_offscreen.py`, classe `CompactFormTests` (LK13-T07, 5 tests) : forme compacte au registre (chaînes, empreinte, au moins deux fois plus petite que l'ancienne forme, relevé inchangé non réécrit) ; empreinte et aller-retour `packFort`/`fortView`, chaîne mal formée refusée ; ancienne forme avec travail en attente convertie au premier examen puis posée une fois à l'arrivée ; ancienne forme après une application interrompue : objets marqués repris, aucun double ; heure hors écran sur l'ancienne forme qui écrit la forme compacte. VM Kahlua : `KR-FORT` (`tests/test_kahlua.py`, mêmes chaînes que sous lupa).
- En jeu : `RST.run({ suite = "lk.fortify_offscreen", tags = "world" })` (solo, dans une maison avec un meuble à conteneur et une ouverture extérieure fermée autre que l'entrée).

### 10.2 Limites et points ouverts

- ⚠ À vérifier en jeu : barricades et murs posés à l'arrivée visibles, identiques chez deux clients (MP), persistants ; marque `LKFortOp` relue sur une fenêtre après redémarrage.
- Les heures hors écran ne sont simulées que par `LK_Simulation` (EveryHours) : la suite en jeu appelle la règle directement.
- Un relevé pris juste avant le départ du joueur peut retarder d'une minute de jeu sur le monde (planche clouée en jeu entre-temps) : l'état réel en avance n'est pas reposé, mais ses matériaux simulés restent pris.
- Planches posées hors écran neuves (1000 PV) quel que soit l'état des planches prises dans la référence (non examinées hors écran, comme le repas abstrait).
- Les ajouts en attente du stock (butin abstrait) ne fournissent pas de clous en boîte hors écran ; les draps déchirés ne sont pas suivis (§8.2).
- Plantage entre la pose et la sauvegarde du monde : comme pour le stock, le monde revient à sa sauvegarde ; le registre peut alors croire posé ce qui ne l'est plus (le relevé suivant le corrige d'après le monde, matériaux perdus).

### 10.3 Forme compacte au registre (LK13-T07)

Mesure de LK13-T02 : le relevé `fort` faisait 71 % du registre des groupes (83 Ko sur 117 Ko en hex, 16 Ko par groupe : 57 chantiers de palissade, chacun en table de dix champs, plus la clé du plan en texte complet, 1,3 Ko) et chaque écriture du registre le réencodait. Le relevé garde désormais des chaînes courtes (forme 2) :

| Champ | Forme 2 | Ancienne forme 1 |
|---|---|---|
| `sites` | `"<sorte><tier><dx>,<dy>,<z><face><côté><visées><faites>;…"`, sorte `b`/`w`/`p`, tier `g`/`u`/`o`, `dx`, `dy` relatifs au foyer, face `N`/`W`, côté opposé `0`/`1`, 1 chiffre chacun (ex. `bg2,-5,0N140`) | liste de tables `{ id, k, t, x, y, z, n, o, s, h }` |
| `ops` (écarts de pose), `pn` (dernier numéro) | `"<u>:<sorte><dx>,<dy>,<z><face><côté><a><b>;…"` | `pend = { n, ops = { { u, id, k, x, y, z, n, o, a, b } } }` |
| `boxes` | `"<id>:<clous utilisés>,…"` | `{ { i, u } }` |
| `tools`, `tiers` | `"HAMMER,SAW"` (outils présents), `"h/s,h/s,h/s"` (ordre `TIERS`) | tables |
| `key` | empreinte du texte (`Fortify.digest` : longueur, Adler-32, polynôme modulo 2^31 − 1), le texte restant en mémoire | texte complet du plan |

- Les identifiants de chantier se recalculent (`siteId(sorte, x, y, z, face)`) ; tout le code de §10 lit une **vue de travail** de l'ancienne forme (`Fortify.fortView`, vue relue en mémoire tant que le relevé n'a pas changé), puis réécrit la forme compacte (`Fortify.packFort`) quand il change le relevé (`offscreenHour`, `applyPending`, `snapshot`). Rattrapage hors écran et pose à l'arrivée inchangés : mêmes chantiers, mêmes écarts, mêmes numéros.
- **Migration** : l'ancienne forme est lue telle quelle (même contrôle qu'avant) ; `Fortify.migrate` la réécrit en forme compacte au premier examen (`Fortify.scan`) de chaque registre chargé, en une écriture, écarts en attente, numéros et boîtes entamées compris. Les marques d'application (`LKFortOp = "<groupe>:<numéro>"`) restent donc valables : une application interrompue avant LK13-T07 est reprise sans double pose. Une heure hors écran ou un relevé qui passe avant l'examen convertit aussi le relevé. Ancienne forme invalide : laissée, remplacée au prochain relevé, comme avant.
- Recalculer le plan à l'arrivée au lieu de le garder (autre piste de la tâche) a été écarté : le relevé sert justement **hors** de la zone chargée (niveau et chantiers faisables du cadre de décision, travail simulé), quand le monde n'existe pas.

### 10.4 Relevé de la minute étalé (LK13-T11)

Mesure de LK13-T09 : `Fortify.onEveryOneMinute` faisait des pointes de 10 à 23 ms lupa à des minutes isolées. Profil
(fonctions des modules enveloppées, banc de charge) : à ces minutes, les plans des **cinq** groupes expiraient
ensemble (relevés dans la même image, `PLAN_MS` réel) et `Fortify.feasible` les relevait tous dans l'image de la
minute, 3 à 4 ms chacun (`plan` : relevé du monde puis `build`, 60 % ; `snapshot`, 25 % ; faisabilité et stock).

- **File** `Fortify.minuteJobs` : à la minute, les groupes dont le plan a expiré y entrent (sans doublon, ordre trié de
  l'examen) avec l'heure de la minute ; **un relevé par image** (`OnTick`, abonné `Fortify.minuteQueue`) à partir de
  l'image qui suit (marque `fresh` effacée par `OnTickEvenPaused`, comme la relecture du stock, [stock.md](stock.md)).
  Le relevé hors écran écrit pendant la file attend une seule écriture du registre (`Groups.hold("fortify")`), faite
  dans une image à elle ; `OnSave` vide la file. Le travail hors écran à poser (`applyPending`) reste dans l'examen.
- **Même résultat qu'à la minute** : relevé fait avec l'heure de la minute (`Fortify.clockAt` lu par `now()`) : même
  `plan.ms`, même expiration suivante. Tout ce qui lit ou change le plan d'un groupe encore en file fait d'abord son
  relevé (`settle`) : `Fortify.plan` (donc `feasible`, `siteFor`, `levelOf`, `hasWork`, pose d'une planche, d'un
  ouvrage, réparation), `invalidate`, `applyPending`, et `offscreenHour` quand l'heure hors écran peut travailler
  (référence du stock valide, jour, groupe non incarné : mêmes conditions que le début de son corps). L'abonné de la
  file est inscrit avant celui de la relecture du stock (ordre des fichiers ; ordre des clés pendant une mesure) : un
  groupe est relevé au plus tard dans l'image où son stock est relu, avant lui.
- **Vérifié au banc de charge**, sans la mesure : une journée complète, registre des groupes, attitudes, registre des
  PNJ, consignes et état des décisions identiques à l'octet avant et après ; lignes `fortify:` identiques et dans le
  même ordre (les autres lignes du journal console sont les mêmes, entrelacées autrement) ; même nombre de relevés et
  d'écritures du registre. Validation : [etalement-pointes-2026-10-12.md](../validation/etalement-pointes-2026-10-12.md).
- **Trois images par relevé** (suite de LK13-T11, 2026-10-15) : le relevé en file se fait en trois étapes, une par
  image, toutes avec l'heure de sa minute : relevé du monde (`Fortify.survey`), plan pur (`Fortify.build`, journal,
  plan gardé), faisabilité et relevé hors écran (`Fortify.feasible`, qui reçoit le plan des deux premières étapes par
  `Fortify.givenPlan` au lieu de relever de nouveau). L'entrée reste en file jusqu'à la dernière étape : une lecture
  du plan entre deux étapes fait les étapes restantes d'un coup (`settle`). La relecture du stock d'un groupe dont le
  relevé est en file attend sa fin (`Fortify.isQueued`, [stock.md](stock.md)) : stock toujours relu après le relevé
  de son groupe. Retenue de l'écriture : `JOB_FRAMES` (3) images par relevé en file plus la marge. Pointe `Fortify`
  du banc 6,1-6,4 → 2,9-4,2 ms lupa, aucune image lourde ; registre identique à l'octet (journée de banc, et bancs
  3 h relevé à la minute / file) : [charge-ecriture-etapes-2026-10-15.md](../validation/charge-ecriture-etapes-2026-10-15.md).
- `snapshot` relit le relevé gardé par la vue mémorisée `readView` (lecture seule) au lieu de le décoder à chaque
  appel : 0,5 à 1 ms de moins par relevé inchangé, même résultat.
- **Écarté** : relevé à budget en ms (horloge à la milliseconde en jeu) ; découper un relevé (relevé du monde dans une
  image, plan dans la suivante : le monde peut changer entre les deux) ; plan gardé plus longtemps (change les
  résultats et la fraîcheur du plan).
- **Limite** : un relevé coûte encore 3 à 8 ms lupa (camp de 57 chantiers, plan reconstruit) dans son image ; le monde
  lu par un relevé décalé peut avoir changé entre la minute et son image (zombie qui abîme une barricade, objet ajouté
  à un conteneur du foyer) : sans effet au banc, au plus une différence d'un relevé (le suivant la rattrape).

Choix pris par défaut (à confirmer) : empreinte de 3 nombres au lieu de la clé complète (collision possible mais sans effet durable : le relevé n'est pas réécrit jusqu'au prochain changement du plan) ; migration au premier examen plutôt qu'au chargement du registre (aucun crochet de chargement dans `LK_Groups`, hors du périmètre de la tâche ; l'ancienne forme reste lisible entre-temps).

## Alternatives écartées

- Simuler la fortification par un niveau abstrait seul (sans relevé des chantiers) : rien ne permettrait de poser à l'arrivée l'état simulé, ouverture par ouverture.
- Marquer la barricade elle-même : sa ModData n'est pas sauvegardée (§10).
- Ouvrir les boîtes de clous hors écran (écart « take » de la boîte + 100 ajouts en attente) : le journal du stock et la référence sont bornés à 128 objets suivis.
- Lancer `ISBarricadeAction` ou `ISBuildAction` sur un corps : ces actions exigent un `IsoPlayer` (inventaire en main, paquet `BuildAction` d'un joueur, niveau de compétence) ; un zombie n'en a pas.
- Appeler `ISBuildIsoEntity:create` sans personnage : la santé lit `getPerkLevel` du personnage et la consommation passe par la logique de recette d'un joueur (`ISBuildIsoEntity.lua:539-554, 637-658`).
- Poser depuis le client propriétaire du corps : l'objet ne serait ni envoyé au serveur ni sauvegardé par lui (§3).
- Clôtures en bois et portail en bois comme défense : enjambés par les zombies (§2.2).

## Idées reprises

- I8.5 (planches réparties, entrée dégagée) : citée par LK14-T03 ; cette fiche établit que toute barricade bloque la porte des deux côtés et que seule la planche extérieure s'use, ce qui oriente la répartition.

## Tests

- Banc lupa, VM Kahlua : sans objet pour l'investigation ; LK14-T02 : `tests/test_lk_fortify.py` (15 tests : ordre de priorité et entrée libre, matériaux, outils et durées, brèche et segments écartés, aucun chantier hors du foyer, niveau pondéré, plan reproductible dans un autre banc avec un autre ordre d'objets, journal à chaque changement, zone non chargée, grand bâtiment, faisabilité et réservation des matériaux, ouvriers distincts, palissade d'un camp, score de `fortify` selon stock et menaces, entrée du cadre, module absent des clients MP).
- En jeu : aucun essai fait pour cette fiche. Les points « à mesurer » sont à couvrir par les suites de LK14-T03 à T06.

## Points ouverts

- ⚠ Pose scriptée d'une barricade et d'un mur sur un serveur dédié : visibles et identiques chez deux clients, persistants après redémarrage, démontables par un joueur.
- ⚠ Rôle de `GameEntityFactory.CreateIsoObjectEntity` pour un mur posé par script (démontage, menus, rechargement).
- ⚠ Clé exacte de `SpriteConfigManager.GetObjectInfo`.
- ⚠ Barricade de fenêtre frappée par un zombie simulé par un client : PV du serveur et des autres clients.
- ⚠ Client éloigné au moment de la pose : objet reçu au chargement de la zone.
- ⚠ Cadence réelle des coups d'un zombie (durée de vie d'une barricade et d'un mur sous un groupe).
- ⚠ Menu « Réparer » vanilla sur un mur en bois et sur la palissade (`Material = Log`).
- ⚠ Porte en bois sur cadre comme portail infranchissable.
