# Recherche : soins, sang et plaies d'un PNJ Living Knox (corps IsoZombie), Build 42.22

Périmètre : lecture seule. Sources : `E:\pz-source-42.22` (Java décompilé `java\`, `media\lua`, `media\scripts`), `D:\SteamLibrary\steamapps\common\ProjectZomboid\media` (AnimSets, anims_X), mod `RadioSurvivor\Contents\mods\batman_LivingKnox\42.21\media\lua`, outils `RadioSurvivor\tools`.
Étiquettes : **[S]** = confirmé statiquement (lu dans la source) ; **[H]** = hypothèse (non vérifiée en jeu ni dans le code).
Chemins Java abrégés : `J/` = `E:\pz-source-42.22\java\`, `L/` = `E:\pz-source-42.22\media\lua\`.

---

## 1. Sang, trous, saleté et bandages visibles sur un IsoZombie

### 1.1 Appels disponibles sur IsoZombie
- `IsoGameCharacter` (exposé Lua : `IsoZombie` est exposée, `index-lua-exposed-classes.txt:144`, et les méthodes publiques héritées le sont aussi). **[S]**
  - `addBasicPatch(part)` : `J/characters/IsoGameCharacter.java:12112-12127`.
  - `addHole(part [, allLayers])` : `:12130-12149`. Si `part == nil`, tirage `OutfitRNG.Next(...)` (`:12139`).
  - `addDirt(part, nbr, allLayers)` : `:12151-12174`.
  - `addBlood(part, scratched, bitten, allLayers)` : `:12202-12245`. Nombre de tirages : 1 par défaut, 5 si `scratched`, 20 si `bitten`, +8 si `isZombie()` (`:12207-12226`). Si `part == nil`, partie tirée au hasard (`:12229-12232`).
  - Chaque appel passe par `getItemVisuals(tempItemVisuals)` puis `BloodClothingType` (`J/characterTextures/BloodClothingType.java`) : les vêtements portés reçoivent le sang et les trous ; le `HumanVisual` reçoit sa part. Puis `updateModelTextures = true` (`:12241`), ce qui force la reconstruction de la texture du modèle.
- Rien ne bloque un IsoZombie dans ces méthodes (seuls `IsoAnimal` sont exclus, `:12203`, `:12152`). **[S]**

### 1.2 Stockage et lecture (HumanVisual / ItemVisual)
- `HumanVisual` : `setBlood(part, amount)` `J/core/skinnedmodel/visual/HumanVisual.java:270-273` (valeur 0..1 stockée en octet 0..255) ; `getBlood` `:275` ; `setDirt` `:279` ; `setHole(part)` `:288` (`holes = -1`) ; `removeBlood()` `:296` ; `removeDirt()` `:300`. **[S]**
- `HumanVisual.save/load` sérialisent le sang (`:385`, écriture `:436` ; lecture `:473`, `:518`). **[S]**
- `ItemVisual.setBlood(part, amount)` `J/core/skinnedmodel/visual/ItemVisual.java:524` ; `removeBlood()` `:632`. **[S]**
- Lecture au rendu : `ModelInstanceTextureCreator.java:186` (`humanVisual.getBlood(bpt)`) et `:338` (`itemVisual.getBlood(bpt)`). **[S]**
- Chaîne complète « donnée modifiée -> pixels à l'écran » : **[H]** (le flag `updateModelTextures` est confirmé ; le rendu réel n'a pas été vérifié en jeu).
- Les trous du `HumanVisual` ne sont lus par aucun rendu ; seuls les trous des `ItemVisual` le sont (déjà noté : `.claude/pz-knowledge/zombies-as-npc-bodies.md`, section « Vêtements déchirés »). **[S]** (base de connaissances)

### 1.3 Plaies et bandages « d'habillage » d'un zombie
- Un zombie habillé reçoit des `ItemVisual` de corps (`addBodyVisualFromItemType`) : `J/characters/IsoZombie.java:4197-4210`. Tirage d'une `ZedDmg_*` dans `ScriptManager.getZedDmgMap()` (`J/scripting/ScriptManager.java:1737-1746`).
- Les bandages visibles sur corps existent comme items « Clothing » : `Base.Bandage_<Partie>` et `Base.Bandage_<Partie>_Blood` (ex. `Bandage_Chest` / `Bandage_Chest_Blood`, `media/scripts/generated/items/clothing.txt:21796-22159`). **[S]**
- Les `ZedDmg_*` (plaies, balles, morsures) sont des clés `ItemKey` (`J/scripting/objects/ItemKey.java:5132-5181`). **[S]**
- Le bandage joueur (`BodyDamage` -> `addBandageModel`, `J/characters/IsoGameCharacter.java:16358-16403`) n'est pas employé pour un zombie : `BodyDamage.Update()` s'arrête pour `IsoZombie` (`J/characters/BodyDamage/BodyDamage.java:1812-1814`). **[S]**

### 1.4 Synchronisation multijoueur
- **Paquet zombie : rien de visuel au-delà de `outfitId` et `skinTextureIndex`.** `ZombiePacket.write` (`J/network/packets/character/ZombiePacket.java:105-146`) écrit id, update, position, `outfitId` (`:110`), santé, type de marche, variables, cible, état, `reanimatedBodyId`, `pfb`, `grappledBy`, `skinTextureIndex` (`:145`). Aucun sang, trou, saleté ni bandage. `set(chr)` ne lit que `getSkinTextureIndex()` (`:245`). **[S]**
- **Paquet `SyncVisuals` : joueurs seulement.** `SyncVisualsPacket` porte un `ConnectionPlayer` (`J/network/packets/SyncVisualsPacket.java:31`) ; `setData` n'accepte qu'un `IsoPlayer` (`:37-41`) ; `GameServer.syncVisuals(IsoPlayer)` (`J/network/GameServer.java:2319-2324`). **[S]**
- `ItemVisual` du sang en `SyncVisualsPacket` : bloc `parse` (`:71-95`) mais seulement pour le joueur. **[S]**
- **Corps mort** : `IsoDeadBody.writeInventory` (`J/iso/objects/IsoDeadBody.java:2347-2378`) écrit le conteneur, les emplacements portés et les objets accrochés ; **pas** le `HumanVisual` ni le sang. **[S]**
- **Réanimation** : le zombie réanimé copie le `HumanVisual` du corps côté serveur (`J/characters/IsoZombie.java:1856`, `zombie.getHumanVisual().copyFrom(this.getHumanVisual())`). Ce copie ne traverse pas le réseau. **[S]**
- **Conclusion (1.4)** : le sang, les trous, la saleté et les bandages de corps d'un zombie **ne sont pas synchronisés** par le moteur en MP. Chaque client a sa copie et son propre état visuel. **[S]**

### 1.5 Application locale depuis Lua
- Méthodes utilisables côté client : `setBlood`, `addBlood`, `addHole`, `addBasicPatch`, `getHumanVisual():setBlood/setHole`, `ItemVisual:setBlood`, puis `zombie:resetModel()` ou `resetModelNextFrame()` (`J/characters/IsoGameCharacter.java`, `:1607`, `:1612`). **[S]**
- Le mod relaie déjà des données serveur vers les clients (LK). Une commande qui transmet des **valeurs explicites** (partie, intensité, trou oui/non) et chaque client les applique localement est la voie compatible avec le moteur. **[H]** (design, non testé)
- Attention 1 : `addBlood`/`addHole`/`addDirt` avec un argument `nil` tirent au hasard via `OutfitRNG` (`:12139`, `:12166`, `:12232`). Pour que les clients voient la même chose, passer la partie et l'intensité explicitement, ou appliquer `setBlood` et `setHole` directement. **[H]** (conséquence du code lu)
- Attention 2 : la copie cliente d'un zombie est réhabillée à sa création (`dressInPersistentOutfit`, qui efface l'état). Le sang appliqué localement doit donc être réappliqué à chaque recréation de la copie. Détail déjà documenté : `.claude/pz-knowledge/zombies-as-npc-bodies.md` (sections « Copie cliente d'un zombie », « Apparence d'un zombie chez les clients MP »). **[S]** (base de connaissances, non relue ligne à ligne ici)

---

## 2. Modèle de blessure vanilla (BodyDamage / BodyPart)

### 2.1 Types de blessure, déclencheurs et durées (`J/characters/BodyDamage/BodyPart.java`)
| Type | Déclenchement | Durée / valeur | Réf. |
|---|---|---|---|
| Égratignure (scratch) | `setScratched(true, forceNoInfection)` | 7–15 ; rapide 4–10 ; lent 15–25 ; ×0,5/×1,5 selon gravité sandbox | `:719-746`, `:727-732`, `:733-741` |
| Coupure (cut) | `setCut(true)` | 10–20 ; rapide 5–10 ; lent 20–30 | `:675-703`, `:683-687` |
| Plaie profonde (deep) | `generateDeepWound()` | 15–20 ; rapide 11–15 | `:775-776` |
| Morsure (bite) | `SetBitten(true)` | 50–80 ; rapide 30–50 ; lent 80–150 ; infection certaine | `:601-625`, `:608-614` |
| Balle (haveBullet) | `setHaveBullet` | dégâts 3,125 ×scaler par tick (×0,5 si bandé) | `:169-175` |
| Éclat de verre (haveGlass) | `setHaveGlass` | saignement limité à ≥ 3 ; infection +1e-4/tick | `:213-215`, `:284-285` |
| Fracture | `setFractureTime` | dégâts 3,125 ×scaler si non attelé | `:179-181`, `:392-407` |
| Brûlure (burn) | `setBurnTime` | dégâts 3,75 ×scaler si non bandé | `:176-201` |

### 2.2 Dégâts et saignement par partie (DamageUpdate, `:138-220`)
- Plaie profonde : 3,125 × scaler × multiplicateur de temps par tick ; 1,5625 si bandé (`:145-151`).
- Égratignure non bandée : 0,9375 ; coupure non bandée : 1,875 ; morsure non bandée : 2,1875 (`:152-160`). **[S]**
- Saignement : perte de santé générale `0,2857143 × scaler × (bleedingTime/10)` par tick, et `addBlood(...)` aléatoire 1/1000 par tick (`:161-168`). **[S]**
- Décroissance du temps de saignement : `2e-4` par tick si bandé (`:204`), `2e-5` sinon (`:211`). Bandage plaie profonde : `0,005` / `3e-4` de vie de bandage (`:205-209`). **[S]**

### 2.3 Bandage
- État : `setBandaged(bandaged, bandageLife, isAlcoholic, bandageType)` `:558-595`. Poser un bandage efface `bitten`, `scratched`, `cut`, `stitched`, `deepWounded` (`:563-569`) : les flags sont « couverts » par le bandage. **[S]**
- Vie du bandage : `ISApplyBandage.lua:112` : `bandageLife = ZombRandFloat((doctorLevel+1)*0.5, (doctorLevel+1)*1.0) + item:getBandagePower()` ; sale (`Dirty` dans le type) -> 0 (`:113-115`) ; appel `SetBandaged(index, true, bandageLife, isAlcoholic, type)` (`:119`). **[S]**
- Usure de la vie du bandage : 8e-5 par tick (égratignure, `:309`), 1e-5 (coupure, `:330`), 1e-4 (plaie profonde, `:350`), 1e-4 (point, `:374`), 2e-4 si infecté (`:304`). Vie < 0 -> 0 (`:420-423`). **[S]**
- Bandage alcoolisé : réduit l'infection de 6e-4/tick (`:300-303`) ; pas d'infection par point (`:375`). **[S]**
- Retirer le bandage : `setBandaged(false, 0)` (`:571-592`) rétablit les flags depuis les temps restants. **[S]**
- Infection de la plaie (`:221-257`) : chance de base 40000 (1/40000 par tick), -10000 si non bandé, -35000 si bandage épuisé (vie = 0), -20000 égratignure, -25000 coupure, -30000 plaie profonde, -24000 verre, -23000 brûlure, -20000 vêtement sale sur la partie, -24000 vêtement sanglant ; plancher 5000 (`:222-254`). Une fois infecté, `setInfectedWound(true)`. **[S]**
- Infection de plaie qui progresse : +2e-4/tick si `isInfected` (virus), +1e-4 avec verre, +1e-5 sinon ; réduite par alcool (2e-4), `reduceInfectionPower` (2e-4), ail (2e-4). Plafond 10 (`:258-292`). **[S]**
- Infection par plaie : `generateZombieInfection(baseChance)` : cut 25 %, scratch 7 % (`:701`, `:744`, `:705-717`). **[S]**

### 2.4 Points de suture (stitch)
- `stitchTime` : `ISStitch.lua:119` `setStitchTime(((1+doctorLevel)/2) * ZombRandFloat(2,5))`. **[S]**
- Pendant : bandé, +4e-4 +1e-4 par tick et 1/80000 de chance d'infection ; non bandé, +2e-4 et 1/20000 (`BodyPart.java:371-391`). Plafond 50 (`:388-390`). **[S]**
- Durée de l'action : `ISStitch.lua:141-152` : base 200 ; 150 si `SutureNeedleHolder` dans l'inventaire ; `- doctorLevel*4`. **[S]**

### 2.5 Attelle (splint) et fracture
- `ISSplint.lua:94` `bodyPart:setSplint(true, splintFactor)`. **[S]**
- Fracture : décroissance 5e-5 × splintFactor si attelée, 5e-6 sinon (`BodyPart.java:392-397`). **[S]**

### 2.6 Balles et éclats
- Retrait d'éclat `ISRemoveGlass.lua:82-90` : 300 - doctor*4 (ou 150 - doctor*4 selon le cas) ; retrait de balle `ISRemoveBullet.lua:78-83` : 250 - doctor*6. Outils : tags `base:removebullet` / `base:removeglass` (`normal.txt:8181-8207`, pince et porte-aiguille) ; `Tweezers` a aussi `base:tweezers`. **[S]**

### 2.7 Infection du virus (zombification) et mortalité
- Morsure : `SetBitten` pose `isInfected = true` sauf si la transmission sandbox vaut 4 (`BodyPart.java:616-619`) ; mortalité sandbox 7 = infection « fausse » (`:620-623`). **[S]**
- Passage au niveau du corps : `BodyDamage.Update` pose `setInfected(true)` quand une partie est infectée (`BodyDamage.java:1857-1871`) et fixe `infectionTime` et `infectionMortalityDuration = pickMortalityDuration()` (`:1868-1871`). **[S]**
- Durée tirée (`pickMortalityDuration`, `BodyDamage.java:1789-1807`, heures) : sandbox 1 = 0 ; 2 = 0–30 s ; 3 = 0,5–1 min ; 4 = 3–12 h ; 5 = 2–3 jours ; 6 = 1–2 semaines ; 7 = pas de mort (`-1`). ×1,25 Résilient, ×0,75 Prédisposé à la maladie. **[S]**
- Progression (`BodyDamage.java:2013-2034`) : `percentMortality = (heureMonde - infectionTime) / duration` ; à 1 : `ReduceGeneralHealth(110)` (mort) ; sinon santé max réduite par `(1-p^4)*100`. **[S]**
- Seuil de zombification `InfectionLevelToZombify = 0.001` : défini (`BodyDamage.java:128`) mais **son usage n'a pas été tracé**. **[H]** pour le lien avec la mort.
- Mécanisme de réanimation après la mort : non tracé ici (voir `zombies-as-npc-bodies.md`, section « Cadavre réanimé »). **[H]**

### 2.8 Peut-on utiliser BodyDamage sur un IsoZombie ?
- **Non, pas tel quel.** `BodyDamage.Update()` retourne immédiatement pour `IsoZombie` (`BodyDamage.java:1812-1814`). Les soins (`ISApplyBandage`, `ISStitch`) appellent `getBodyDamage()` sur le soignant ou le blessé (`ISApplyBandage.lua:119`, `:126` `self.bodyPart:SetInfected(true)`), donc un zombie n'a pas de progression vanilla. **[S]** pour Update ; **[H]** pour le reste des appels (non tracé pour chaque méthode).
- Le modèle Lua de PNJ doit donc reproduire ces règles (constantes ci-dessus) sans appeler `BodyDamage`. Les constantes sont exposées côté Java (`BodyPart.java`), donc citables.

---

## 3. Objets de soin, recettes et déchirage

### 3.1 Objets (`media/scripts/generated/items/normal.txt`, sauf mention)
| Item | Ligne | Points clés |
|---|---|---|
| `Base.Bandage` | 8071-8087 | `BandagePower = 4.0`, `CanBandage`, `ReplaceOnUse = Base.BandageDirty` |
| `Base.BandageDirty` | 8102-8117 | `BandagePower = 0.5`, `ItemAfterCleaning = Base.Bandage`, tag `base:canbewashed` |
| `Base.AlcoholBandage` | 8037-8053 | `Alcoholic = true`, `BandagePower = 4.0`, `ReplaceOnUse = Base.BandageDirty` |
| `Base.AlcoholRippedSheets` | 8055-8069 | `Alcoholic`, `BandagePower = 2.0`, `ReplaceOnUse = Base.RippedSheetsDirty` |
| `Base.RippedSheets` | 10656-10681 | `FabricType = Cotton`, `BandagePower = 2.0`, `ReplaceOnUse = RippedSheetsDirty` |
| `Base.RippedSheetsDirty` | 10683-... | `BandagePower = 0.5`, `ItemAfterCleaning = Base.RippedSheets` |
| `Base.SutureNeedle` | 8156-8167 | outil médical |
| `Base.SutureNeedleHolder` | 8181-8193 | tags `base:removebullet;base:removeglass` |
| `Base.Tweezers` | 8209-8221 | tags `base:removebullet;base:removeglass;base:tweezers` |
| `Base.Disinfectant` | 8283-8306 | bouteille 0,5 ; fluide `RubbingAlcohol:1.0` |
| `Base.Splint` | 8308-8318 | `Medical = true` |
| `Base.Needle` | 10764 | `Tool`, `SurvivalGear` |
| `Base.Thread` | `drainable.txt:2277` | `base:drainable`, `UseDelta = 0.05`, `base:thread` |
| `Base.AlcoholWipes` | `drainable.txt:1518` | non détaillé ici |
| `Base.CottonBalls` | 8258-8268 | `FireFuelRatio` ; combiné à l'alcool (`DouseCottonInAlcohol`) |

Le bandage lui-même est le vrai médicament du modèle : `BandagePower` alimente `bandageLife` (`ISApplyBandage.lua:112`). **[S]**

### 3.2 Recettes (`media/scripts/generated/recipes/recipes_medical.txt`)
- `DisinfectRag` (ligne 60-81) : `timedAction = ApplyAlcohol`, 40 ; entrée `[Base.RippedSheets ; Base.Bandage]` détruite, `-fluid 0,1 [RubbingAlcohol;Vodka;Whiskey]` ; sortie `AlcoholRippedSheets` / `AlcoholBandage`. **[S]**
- `DisinfectBandage` (83-106) : `timedAction = ScrubClothWithSoap`, 100 ; `OnTest = RecipeCodeOnTest.hotFluidContainer` (eau chaude = bouillir) ; `-fluid 0,5 [Water]` ; mêmes sorties alcoolisées. **[S]**
- `CleanBandage` (108-131) : `ScrubClothWithSoap`, 40 ; `[BandageDirty ; DenimStripsDirty ; LeatherStripsDirty ; RippedSheetsDirty]` -> propres ; `-fluid 0,5 categories[Water]`. **[S]**
- `MakeSplint` (133-148) : `Making`, 70 ; `[RippedSheets ; RippedSheetsDirty ; DenimStrips ; DenimStripsDirty ; LeatherStrips ; LeatherStripsDirty]` détruit + `[Plank ; TreeBranch2 ; WoodenStick2]` -> `Base.Splint`. **[S]**
- `DouseCottonInAlcohol` (150-166) : `CottonBalls` + alcool -> `AlcoholedCottonBalls`. **[S]**
- Plantes : `MakePlantainPoultice`, `MakeComfreyPoultice`, `MakeWildGarlicPoultice` (lignes 3-58, `MixingMortarPestle`, 60). **[S]**
- Recettes de déchirage (`media/scripts/generated/recipes/recipes.txt`) :
  - `RipClothing` (235-250) : `timedAction = RipClothing`, 40 ; entrée `tags[base:ripclothingcotton]` non portée ; `OnCreate = RecipeCodeOnCreate.ripClothing`. **[S]**
  - `RipDenimClothing` (252-282) : `timedAction = CutClothing`, 80 ; outil `base:scissors`/`base:sharpknife` ; entrée `base:ripclothingdenim`/`base:ripclothingleather` ; sortie `LeatherStrips` pour les cuirs, `DenimStrips` par défaut. **[S]**
  - `RipSheets` (300-313) : `tags[base:sheet]` -> 10 `RippedSheets`. **[S]**
  - Les tags `base:ripclothingcotton|denim|leather` sont posés sur des vêtements dans `clothing.txt` et `recipes.txt` (recherche par motif : 2 fichiers). **[S]**

### 3.3 Calcul du déchirage (Java)
- `RecipeCodeOnCreate.ripClothing` (`J/scripting/logic/RecipeCodeOnCreate.java:562-590`) :
  - matière : `ClothingRecipesDefinitions.FabricType[fabricType].material` (ou `materialDirty`), lue dans le Lua ;
  - `maxMaterial = max(nbrOfCoveredParts - (holes + patches), 1)` ; `minMaterial = 1` si max = 1, sinon 2 ;
  - `nbr = Rand(min, max)`, puis `clamp(nbr + tailoringLevel/2, 1, max)` ;
  - par morceau : sale si `Rand(1..99) <= dirtiness + bloodLevel` ;
  - `filterLife` mis dans le ModData des `RippedSheets` propres ;
  - ajout de `addItemToCharacterInventory` pour chaque morceau ; si le vêtement porte le tag `BUCKLE`, ajout d'une boucle `ItemKey.Normal.BUCKLE` (`:585-586`). **[S]**
- `ClothingRecipesDefinitions.lua:7-17` (`media/lua/shared/Definitions/ClothingRecipesDefinitions.lua`) :
  - `Cotton` -> `Base.RippedSheets` / `Base.RippedSheetsDirty` ;
  - `Denim` -> `Base.DenimStrips` / `DenimStripsDirty`, `noSheetRope = true` ;
  - `Leather` -> `Base.LeatherStrips` / `LeatherStripsDirty`, `noSheetRope = true`. **[S]**
- Aucun fichier `ISRipClothing` dans le Lua vanilla 42.22 : `timedAction = RipClothing` est une action **Java** (non vérifiée). **[H]**

### 3.4 Eau, lavage et stérilisation
- Lavage : `CleanBandage` (eau 0,5 mixture) ; le sale devient propre. **[S]**
- Stérilisation par eau chaude : `DisinfectBandage` (contrôle `hotFluidContainer`). **[S]**
- Alcool : `DisinfectRag` (0,1 alcool), `DouseCottonInAlcohol`. **[S]**
- Pour un PNJ : pas de `hotFluidContainer` côté Lua ; la chaleur doit être testée par le modèle (feu, bouilloire). **[H]**

---

## 4. Retirer des vêtements d'un cadavre (IsoDeadBody) côté serveur

- Retirer un objet du conteneur : `ItemContainer.DoRemoveItem(item)` `J/inventory/ItemContainer.java:2004-2019`. Si le conteneur est celui d'un `IsoDeadBody`, il appelle `isoDeadBody.checkClothing(item)` (`:2015`). **[S]**
- `IsoDeadBody.checkClothing(removed)` (`J/iso/objects/IsoDeadBody.java`, vers `:1362-1378`) : retire de la liste des vêtements portés (`wornItems`) tout objet qui n'est plus dans le conteneur ; retire l'objet tenu si besoin. **[S]**
  - Conséquence : retirer le vêtement du conteneur du cadavre suffit pour l'enlever des vêtements portés.
- Sync serveur : `GameServer.sendRemoveItemFromContainer(container, item)` `J/network/GameServer.java:2286-2292`. La branche (joueur / parent / monde) dépend de `container.getParent()` ou de `inventoryContainer.getWorldItem()`. **Pour un conteneur de cadavre, la branche exacte n'a pas été tracée.** **[H]**
- Clients : un cadavre est transmis par `DeadZombiePacket` avec son inventaire (`writeInventory`), la copie cliente remplace son inventaire (`.claude/pz-knowledge/zombies-as-npc-bodies.md`, section « Cadavre chez un client MP »). **[S]** (base de connaissances)
- Le mod applique déjà ce schéma : `LK_Expeditions_Phases.lua:212-213` (`ct:DoRemoveItem(p.it)` puis `if isServer() then sendRemoveItemFromContainer(ct, p.it) end`) et `LivingKnox.Stock.takeItem` (`server/LivingKnox/Stock/LK_Stock_Materials.lua:87-91`, même couple). **[S]**
- Retrait du vêtement corporel vanilla (tenue d'un joueur) : `ISUnequipAction` côté joueur (`media/lua/client/ISUI/ISInventoryPaneContextMenu.lua:637`). Non applicable à un cadavre sans joueur. **[S]**

---

## 5. Animations pour un soin sur un corps de zombie

### 5.1 Gestes déjà générés par le mod (`RadioSurvivor\tools\anim_table.json`, `tools\gen_animsets.py`)
- Gestes (`gestures`) : idle, walk, run, crouch, aim, guard, strike, sit, **kneel**, **rummage**, hammer, smoke, warmhands, openwindow, closewindow, shoot, reload, strikefloor, stomp, surrender. **[S]**
- Pour un soin : `kneel` -> `lkactor_kneel.xml`, clip `Bob_IdleLooting_Low`, preuve `AnimSets/player/actions/LootLow.xml` (« tending a fire or a stove, caring for a wound ») ; `rummage` -> `Bob_IdleLooting_Mid` ; `hammer` -> `Bob_IdleHammering` ; `warmhands` -> `Bob_SitGround_WarmHands`. **[S]**
- Les fichiers générés sont dans `Contents\mods\batman_LivingKnox\common\media\AnimSets\zombie\idle\` (`lkactor_*.xml`). **[S]**
- Chaque nœud exige `actorVariable = true` (`anim_table.json` `_doc`). **[S]**

### 5.2 Animations vanilla de pansement (joueur)
- Sets vanilla : `media/AnimSets/player/actions/` : `BandageHead.xml`, `BandageUpperBody.xml`, `BandageLowerBody.xml`, `BandageLeftArm.xml`, `BandageRightArm.xml`, `BandageLeftLeg.xml`, `BandageRightLeg.xml` ; clips `Bob_BandageHead`, `Bob_BandageUpperBody`, `Bob_BandageLowerBody`, `Bob_BandageLeftArm`, `Bob_BandageRightArm`, `Bob_BandageLeftLeg` (`m_AnimName`). **[S]** (D:\...\media\AnimSets, grep)
- Fichiers des clips présents : `D:\SteamLibrary\steamapps\common\ProjectZomboid\media\anims_X\Bob\Bob_Bandage*.x`. **[S]** (existence)
- Le joueur choisit le nœud par la variable `BandageType` (`ISApplyBandage.lua:57-58`, `CharacterActionAnims.Bandage` : `J/characters/CharacterActionAnims.java:27`). **[S]**
- Un nœud `lkactor_bandage*.xml` utilisant `Bob_BandageHead` etc. est **possible** : même squelette `Bob`, comme les autres clips repris. **[H]** (non testé sur un zombie)
- Déchirer un tissu : **aucun clip « rip » trouvé** dans la recherche faite (`ripping` / `ripclothing` / `RipClothing` n'apparaissent pas dans les AnimSets ; recherche limitée aux motifs cités). **[S]** pour l'absence dans les motifs cherchés ; **[H]** pour l'absence totale.
- Le déchirage vanilla passe par `timedAction = RipClothing` (action Java, `recipes.txt:237`) : l'animation vient de cette action, non tracée. **[H]**

---

## 6. Le mod : rôles, registres, expéditions, soins

### 6.1 Rôles
- `Config.GROUP_ROLES = { "deputy", "fighter", "scout", "medic", "worker", "breaker" }` (`shared/LivingKnox/LK_Config.lua:191`). **[S]**
- Comportements par rôle : `medic` = `{ "heal", "chores", "cook" }` (`shared/LivingKnox/Data/LK_Type_neutrals.lua:19`) ; `medic` = `{ "heal", "cook", "chores", "talk" }` (`shared/LivingKnox/Data/LK_Type_settlers.lua:22`). **[S]**
- Comportements de groupe : `heal = true` (`shared/LivingKnox/LK_GroupTypes.lua:58`). **[S]**
- Objectifs : `Decisions.OBJECTIVES = { "settle", "rest", "guard", "heal", "supply", "fortify" }` (`server/LivingKnox/Decisions/LK_Decisions_Common.lua:27`). **[S]**
- Postes (duties) : `Decisions.DUTIES = { "sentry", "rest", "keeper", "carer", "forager", "builder" }` (`LK_Decisions_Common.lua:29`), et `carer = { "heal" }` (`:33`). **[S]**
- Le rôle `medic` n'est pas une entrée d'une table propre à la décision : c'est le **comportement** `heal` qui est testé (`LK_Care.lua:12`, `:102` : `m.duty == "carer"`). **[S]**

### 6.2 Registres (LivingKnox.Registry)
- Socle : `LivingKnox.Registry.new(name, opts)` (`shared/LivingKnox/LK_Registry.lua:78`). Inscription : `register(spec)` lève une erreur si refusé, `try(spec)` renvoie `nil, raison`. Même clé = remplacement (rechargement). Tri par `order` puis clé (`:1-20`, `:27-60`). **[S]**
- Instances (une par point d'extension) :
  - `Decisions.registerExtension` (`server/LivingKnox/Decisions/LK_Decisions_Registries.lua:70-76`) ; exemples : `LK_Decide_Post.lua:36-37`, `LK_Decide_Defence.lua:148-156`.
  - `Decisions.registerContext` (`LK_Decisions_Registries.lua:103-109`) ; exemples : `LK_Decisions.lua:127-135`.
  - `Expeditions.registerKind` (`server/LivingKnox/Expeditions/LK_Expeditions_Kinds.lua:49`) ; fichiers `LK_Exp_Forage.lua`, `LK_Exp_Fish.lua`, `LK_Exp_Building.lua`.
  - `Fortify.registerKind` (`server/LivingKnox/Fortify/LK_Fortify_Kinds.lua:76`).
  - `Homes.registerFurnishing` (`server/LivingKnox/LK_Homes.lua:122`).
  - `Loot.registerContent` (`server/LivingKnox/LK_Loot.lua:193`).
  - `Routines.registerActivity` (`server/LivingKnox/LK_Routines.lua:441-445`) ; `Routines.registerChore` (`server/LivingKnox/Routines/LK_Routine_Chores.lua:51`).
  - `Simulation.registerHourly` (`server/LivingKnox/LK_Simulation.lua:85`) ; `Simulation.registerEvent` (`:722`).
  - `Upkeep.registerJob` (`server/LivingKnox/LK_Upkeep.lua:80-84`).
  - `GroupTypes.register` (`shared/LivingKnox/LK_GroupTypes.lua:332`) ; `Passage.priority` (`shared/LivingKnox/LK_Passage.lua:36`).
  **[S]** pour chaque ligne citée.

### 6.3 Corvées, jobs, activités
- Corvées : un fichier par corvée dans `server/LivingKnox/Chores/` appelle `Routines.registerChore({ id, order, gesture, duty, role, ... })`. Exemple soin : `LK_Chore_Care.lua:32-34` : `order = 70`, `gesture = "kneel"`, `duty = { keeper = 1, carer = 6 }`, `role = { heal = 3 }`. **[S]**
- Entretien : `Upkeep.registerJob({ kind, order, gesture, minutes, ... })` dans `server/LivingKnox/Jobs/LK_Job_*.lua` (clean, dig, glass, harvest, refuel, repair, seeds, sow, water). **[S]**
- Activité : `LK_Fortify.lua:132`, `LK_Upkeep.lua:508` (`LivingKnox.Routines.registerActivity({ id = "chore.upkeep", behaviour = "chore", ... })`). **[S]**

### 6.4 Expéditions
- Façade : `server/LivingKnox/LK_Expeditions.lua` (en-tête : départ `Expeditions.minutePass`, exécution `Expeditions.apply` appelée par `LK_Decisions` pour le comportement `expedition`). Fichiers d'implémentation : `server/LivingKnox/Expeditions/LK_Expeditions_*.lua` (Depart, Run, Phases, Deliver, Minute, Target, Record, Offscreen, Kinds, Common) et les types `LK_Exp_*.lua`. **[S]**
- Fouille : `DoRemoveItem` + `sendRemoveItemFromContainer` sur serveur (`LK_Expeditions_Phases.lua:212-213`, en-tête `LK_Expeditions.lua:34`). **[S]**

### 6.5 Soins : où `Care.apply` est appelé
- `Care.apply(id, st, ctx, fresh)` : `server/LivingKnox/LK_Care.lua:355`. **[S]**
- Appel : `server/LivingKnox/Decisions/LK_Decisions_Apply.lua:177-178` :
  ```
  local Ca = LivingKnox.Care   -- LK07-T03 ...
  if Ca ~= nil and Ca.apply ~= nil and Ca.apply(id, st, ctx, fresh) then return end
  ```
  Placé après le test du comportement « lead » (`:170-176`) et avant `R.apply` (routine). **[S]**
- **Point de fermeture** : `Care` n'est pas inscrit dans un registre ; il est câblé par nom dans `LK_Decisions_Apply.lua:177`. Un nouveau soin (ex. bandage, suture) ne peut donc pas s'ajouter par inscription sans toucher ce fichier. **[S]** Recommandation de conception (ouvert/fermé) : un registre `Decisions.registerExtension` avec `overlay = true` existe déjà et sert ce rôle (`LK_Decide_Post.lua:36`). **[H]** qu'il convient à un soin (non étudié en détail).
- Santé de référence : `server/LivingKnox/LK_Health.lua` est le seul écrivain de `npc.hp` et `npc.bleed` (en-tête `:9-17`) ; `Care` ne modifie la santé que par `Health.stopBleeding` et `Health.noteHeal` (en-tête de `LK_Care.lua:20-21`). **[S]**
- Stock : `Stock.takeItem(gid, pred, who, use, apply)` (`server/LivingKnox/Stock/LK_Stock_Materials.lua:87`) ; pénurie : `Stock.reportShortage(gid, cat, who)` (`server/LivingKnox/Stock/LK_Stock_Meals.lua:116`). **[S]**

---

## 7. Limites et points à confirmer en jeu

1. Affichage effectif du sang appliqué à un IsoZombie (chaîne `setBlood` -> texture) : **non vérifié en jeu**. **[H]**
2. Synchronisation par commande Lua relayée : design, **non testé en MP**. Les clients doivent réappliquer l'état après une recréation de copie. **[H]**
3. Animation de soin d'un zombie avec les clips `Bob_Bandage*` : **non testée**. **[H]**
4. Branche de `sendRemoveItemFromContainer` pour un conteneur de cadavre : **non tracée**. **[H]**
5. Seuil de zombification `InfectionLevelToZombify` (0,001) : défini, usage **non tracé**. **[H]**
6. Animation de déchirage (`RipClothing`, action Java) : **non tracée**. **[H]**
7. Caractéristiques d'`AlcoholWipes` (`drainable.txt:1518`) : **non lues en détail**.
8. Tous les chiffres de `BodyPart.java` sont des constantes du tick de jeu (multiplicateur `GameTime`) : une conversion en minutes de jeu n'a pas été faite. **[S]** pour les valeurs ; conversion **[H]**.
9. Les sandbox options (mortalité, transmission, gravité d'injure) changent plusieurs durées ; les valeurs citées sont celles du code à réglage par défaut lu. **[S]**
