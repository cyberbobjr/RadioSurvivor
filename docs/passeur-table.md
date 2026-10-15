# Table de troc — passeur de l'Ohio et groupes Living Knox

> **Proposition à valider** (tâche `E13-T01`, barème commun avec `LK11-T08`). Rédigée le 2026-10-10. Rien n'est codé ;
> la table serveur (`E13-T02`) reprendra ces valeurs une fois validées.

Sources des identifiants : scripts vanilla installés **42.21**, dossier
`<PZ>\media\scripts\generated\items\` (abrégé `items/`), et recettes
`...\scripts\generated\recipes\` (abrégé `recipes/`). Chaque objet cité ci-dessous existe dans le fichier et à la ligne
indiqués (`fichier:ligne` de la déclaration `item X`). Noms anglais relevés dans
`media/lua/shared/Translate/EN/ItemName.json`.

## 1. Unité et règle d'un échange

### Valeur

- Chaque objet a une **valeur V en points entiers**. Il n'y a pas de monnaie : les points ne servent qu'à comparer deux
  lots, ils ne se gardent pas d'un passage à l'autre.
- Échelle : **1 point ≈ un petit objet courant** (une pile, un fil électrique). Un antibiotique vaut 8, une boîte de
  munitions de chasse 12 à 14, une cartouche de cigarettes 25.
- La même valeur V sert au passeur et aux groupes Living Knox (section 5). Ce qui change d'un partenaire à l'autre :
  **ce qu'il accepte** (catégories) et **sa marge**.

### Prix d'un lot

- Ce que le joueur donne compte pour **Σ V** (valeur pleine, sans décote).
- Ce que le passeur fournit coûte, **ligne par ligne** (objet × quantité), arrondi à l'entier supérieur :

  `prix = ⌈ V × quantité × (1 + marge) × M ⌉`

- **Marge** du passeur : **0,25** par défaut ; elle suit la réputation de l'équipe (E04), **bornée à 0,10 – 0,50**
  (0,10 pour un client fidèle et honnête, 0,50 après une tricherie).
  E04-T11 (Q13, confirmé par défaut le 2026-10-15) : la marge la plus basse permise part du **niveau de réputation
  interne du personnage appelant** (`RS_Reputation.margin`, `RS_Config.Reputation.margin`) : **bonne 0,10, neutre 0,25,
  mauvaise 0,40** ; s'y ajoute le rabais d'historique (−0,05 par affaire conclue avec ce passeur, jamais sous 0,10) ;
  **0,50** après une tricherie, quel que soit le niveau. Sans personnage du carnet : neutre. Remplace le « faute d'API
  de réputation » de la décision E13-T02.
- **Multiplicateur M** = cordon × rareté, **borné à 1,0 – 1,75** :
  - **cordon militaire** : 1,0 (calme), 1,25 (patrouilles ou hélicoptère signalés dans la semaine), 1,5 (cordon serré :
    état serveur fixé par les événements de la semaine, E13-T03) ;
  - **rareté** d'un objet : 1,25 si son stock du passage est de **1 exemplaire**, sinon 1,0.
- **Accepté si** Σ V donnée ≥ Σ prix demandés. L'écart **n'est pas rendu** (pas de petite monnaie) : le LLM peut proposer
  d'ajouter un petit objet pour l'équilibrer, dans les stocks du passage.
- Le LLM négocie **à l'intérieur** de ces bornes : il choisit la marge dans la fourchette permise par la réputation et
  peut refuser, jamais proposer sous le prix calculé (E13-T02).

### Plafonds d'un passage

- Un passage par semaine de jeu pour tout le serveur (décision acquise).
- Le passeur prend **au plus 120 points** au total par passage, et **au plus 20 kg** (place dans la barque), avec un
  plafond par catégorie (sections 2.1 à 2.4).
- La contrepartie pèse **au plus 10 kg**.
- Le stock d'apport est tiré à chaque passage dans les fourchettes de la section 3 (tirage serveur reproductible).

### Ce qui est toujours refusé

- Tout objet **hors module `Base`** : en particulier les objets de ce mod (module `RadioSurvivor`, par exemple
  `RadioSurvivor.NoteWalt`, `NoteDarlene`, `NoteCody`, `NoteGus`, `NoteNightOwl`, déclarés dans
  `Contents/mods/batman_RadioSurvivor/42.21/media/scripts/RadioSurvivor_notes.txt`), le carnet et les objets de mission.
- Tout objet portant des **ModData du mod** (objet de quête, preuve de mission), même de type `Base`.
- Les objets **portés ou équipés** : seul compte le contenu du sac déposé, au premier niveau ; un portefeuille compte
  avec son contenu (un niveau de plus, section 2.3), les autres contenants ne comptent que leur contenu.
- Un objet hors des listes ci-dessous vaut **0** pour le passeur : il est laissé sur la berge.

## 2. Ce que le passeur prend

### 2.1 Argent et bijoux — plafond 60 points par passage

| Objet (`Base.X`) | Fichier:ligne | V | Condition |
|---|---|---|---|
| `Money` (billet) | `items/normal.txt:8636` | 1 par lot de 10 | lots entiers, au plus 100 billets en vrac |
| `MoneyBundle` (liasse = 100 billets, `recipes/recipes_packing.txt:168` `UnbundleMoney`) | `items/normal.txt:8647` | 10 | — |
| `GoldCoin` | `items/normal.txt:9093` | 3 | — |
| `SilverCoin` | `items/normal.txt:9103` | 2 | — |
| `Diamond` | `items/normal.txt:11737` | 10 | — |
| `GoldBar` (16 kg) | `items/normal.txt:1643` | 40 | 1 au plus |
| `SilverBar` | `items/normal.txt:1665` | 20 | 1 au plus |
| Bagues or : `Ring_Right_MiddleFinger_Gold`, `Ring_Left_MiddleFinger_Gold`, `Ring_Right_RingFinger_Gold`, `Ring_Left_RingFinger_Gold` | `items/clothing.txt:7573-7621` | 4 | — |
| Bagues argent : `Ring_{Right,Left}_{MiddleFinger,RingFinger}_Silver` (4 objets) | `items/clothing.txt:7637-7685` | 2 | — |
| Bagues argent et diamant : `…_SilverDiamond` (4) | `items/clothing.txt:7701-7749` | 6 | — |
| Bagues or et rubis : `…_GoldRuby` (4) | `items/clothing.txt:7765-7813` | 6 | — |
| Bagues or et diamant : `…_GoldDiamond` (4) | `items/clothing.txt:7829-7877` | 8 | — |
| Chevalières : `…_Signet` (4) | `items/clothing.txt:8287-8338` | 3 | — |
| `Necklace_Gold` / `Necklace_Silver` | `items/clothing.txt:6994` / `7033` | 4 / 2 | — |
| `Necklace_GoldRuby` / `Necklace_GoldDiamond` | `items/clothing.txt:7007` / `7020` | 6 / 8 | — |
| `Necklace_SilverSapphire` / `Necklace_SilverDiamond` / `Necklace_SilverCrucifix` | `items/clothing.txt:7046` / `7072` / `7059` | 4 / 6 / 2 | — |
| `Necklace_Pearl` | `items/clothing.txt:7110` | 4 | — |
| `NecklaceLong_Gold` / `NecklaceLong_GoldDiamond` | `items/clothing.txt:7122` / `7135` | 5 / 8 | — |
| `NecklaceLong_Silver` / `NecklaceLong_SilverEmerald` / `NecklaceLong_SilverSapphire` / `NecklaceLong_SilverDiamond` | `items/clothing.txt:7148` / `7161` / `7174` / `7187` | 3 / 5 / 5 / 6 | — |
| `Necklace_Choker_Sapphire` / `Necklace_Choker_Diamond` | `items/clothing.txt:7224` / `7249` | 3 / 5 | — |
| Boucles or : `Earring_LoopLrg_Gold`, `Earring_LoopMed_Gold`, `Earring_LoopSmall_Gold_Both`, `Earring_LoopSmall_Gold_Top`, `Earring_Stud_Gold` | `items/clothing.txt:7314, 7353, 7382, 7398, 7430` | 2 | — |
| Boucles argent : `Earring_LoopLrg_Silver`, `Earring_LoopMed_Silver`, `Earring_LoopSmall_Silver_Both`, `Earring_LoopSmall_Silver_Top`, `Earring_Stud_Silver` | `items/clothing.txt:7327, 7340, 7366, 7414, 7443` | 1 | — |
| Boucles à pierre : `Earring_Stone_Sapphire`, `_Emerald`, `_Ruby`, `Earring_Dangly_Sapphire`, `_Emerald`, `_Ruby` | `items/clothing.txt:7456-7534` | 3 | — |
| `Earring_Dangly_Diamond` / `Earring_Pearl` / `Earring_Dangly_Pearl` | `items/clothing.txt:7547` / `7495` / `7560` | 5 / 2 / 2 | — |
| Bracelets or : `Bracelet_BangleRightGold`, `Bracelet_BangleLeftGold`, `Bracelet_ChainRightGold`, `Bracelet_ChainLeftGold` | `items/clothing.txt:7893-7941` | 4 | — |
| Bracelets argent : `Bracelet_BangleRightSilver`, `…LeftSilver`, `Bracelet_ChainRightSilver`, `…LeftSilver` | `items/clothing.txt:7957-8005` | 2 | — |
| `WristWatch_Right_Expensive` / `WristWatch_Left_Expensive` | `items/alarmclockclothing.txt:269` / `288` | 8 | — |
| `WristWatch_Right_ClassicGold` / `WristWatch_Left_ClassicGold` | `items/alarmclockclothing.txt:117` / `136` | 5 | — |
| `Pocketwatch` | `items/alarmclock.txt:3` | 3 | — |

Refusés (valeur 0) : bijoux sans métal précieux ni pierre (`Necklace_Crucifix`, `Necklace_YingYang`, `Necklace_Choker`,
ambre, dents, crânes, défenses, os : `items/clothing.txt:7085-7237, 8372-8541, 12639`), bracelets d'amitié
(`Bracelet_*FriendshipTINT`), montres ordinaires (`WristWatch_*_ClassicBlack`, `_ClassicBrown`, `_ClassicMilitary`,
`_Digital*`), coffrets (`JewelleryBox`, `JewelleryBox_Fancy`, `items/container.txt:4815, 4831` : seul le contenu
compte), métal de fonte et objets fabriqués (`GoldScrap`, `SilverScrap`, `GoldSheet`, `SilverSheet`), coupes
(`GoldCup`, `SilverCup`).

### 2.2 Images — plafond 40 points par passage

Les télévisions du dehors paient les images de l'intérieur : surtout les vidéos d'amateur et ce qui permet d'en faire.

| Objet (`Base.X`) | Fichier:ligne | V | Condition |
|---|---|---|---|
| `CameraFilm` (pellicule) | `items/normal.txt:9568` | 3 | 6 au plus |
| `CameraDisposable` | `items/normal.txt:9548` | 3 | — |
| `Camera` | `items/normal.txt:9538` | 5 | — |
| `CameraExpensive` | `items/normal.txt:9558` | 10 | — |
| `VHS_Home` (cassette d'amateur) | `items/normal.txt:4996` | 6 | 4 au plus |

Ces objets n'ont pas d'état d'usure dans leur script : ils sont pris tels quels. Refusés : `VHS_Retail` et
`Disc_Retail` (films et disques du commerce, `items/normal.txt:4984`, `4974`), `VideoGame`, les photos
(`Photo`, `Photo_Racy`, `Photo_Secret`, `Photo_VeryOld`, `items/literature.txt:4041-4083`, souvenirs d'avant sans
intérêt pour une télévision), `Photo_Hass` (`items/literature.txt:8248`, objet unique de l'histoire vanilla) et les
albums.

### 2.3 Papiers des morts — plafond 30 points et 10 pièces par passage

Des familles paient pour savoir. Seuls les papiers **nominatifs** comptent : le serveur exige un nom affiché différent du
nom du script (`getDisplayName`), et refuse un papier au nom du personnage d'un joueur du serveur (recherche
`Prénom Nom` du descripteur dans le nom, base `api-42-21.md`, « Pièces d'identité nominatives »). Un papier nommé au
hasard dans le butin et un papier pris sur un mort sont indiscernables : les deux sont acceptés.

| Objet (`Base.X`) | Fichier:ligne | V | Condition |
|---|---|---|---|
| `IDcard`, `IDcard_Male`, `IDcard_Female` (tags `base:idcard;base:applyownername`) | `items/literature.txt:4801, 4847, 4836` | 3 | nominative |
| `Passport` | `items/literature.txt:4858` | 4 | nominatif |
| `PressID` | `items/literature.txt:4869` | 3 | nominative |
| `Badge` | `items/normal.txt:8528` | 3 | nominatif |
| `Necklace_DogTag`, `Necklace_DogTag_Male`, `Necklace_DogTag_Female` (tag `base:dogtag`) | `items/clothing.txt:6952, 6980, 6966` | 4 | nominatives |
| `CreditCard` | `items/normal.txt:8586` | 1 | nominative |
| `Wallet`, `Wallet_Male`, `Wallet_Female` | `items/container.txt:3976, 4010, 3993` | 1 | contenu compté à part |

Les plaques d'identité sont classées ici plutôt qu'en matériel militaire : ce sont des papiers de morts.
Refusés : `IDcard_Stolen` (sans `applyownername`) et `IDcard_Blank` (`items/literature.txt:4812`, `4823`),
`CreditCard_Stolen` (`items/normal.txt:8597`), plaques d'animaux (`DogTag_Pet`, `DogTag_Pet_Blank`), `Wallet_Hide`
(fabriqué), papiers sans tag (`Paperwork`, `Receipt`…), et tout papier au nom d'un joueur.

### 2.4 Matériel militaire abandonné — plafond 60 points par passage

Pour des collectionneurs et des milices. Les vêtements, l'arme et le masque doivent être **en état ≥ 50 %**
(`getCondition` / `getConditionMax`) ; le filtre, à moitié plein au moins.

| Objet (`Base.X`) | Fichier:ligne | V | Condition |
|---|---|---|---|
| `AssaultRifle` (M16) | `items/weapon.txt:10549` | 20 | 1 au plus, état ≥ 50 % |
| `556Clip` (chargeur M16) | `items/normal.txt:13781` | 3 | — |
| `556Box` (20 cartouches, `recipes/recipes_ammunition.txt` `OpenBoxOfBullets20`) | `items/normal.txt:13517` | 8 | 2 au plus |
| `Vest_BulletArmy` | `items/clothing.txt:20448` | 10 | état ≥ 50 % |
| `Hat_Army` (casque) | `items/clothing.txt:4372` | 3 | état ≥ 50 % |
| `Hat_GasMask` / `Hat_NBCmask` | `items/clothing.txt:8724` / `8925` | 5 / 6 | état ≥ 50 % |
| `GasmaskFilter` | `items/drainable.txt:1610` | 2 | ≥ 50 % |
| `Bag_ALICEpack_Army` | `items/container.txt:207` | 5 | vide |
| `WalkieTalkie5` (« US Army Walkie Talkie ») | `items/radio.txt:115` | 6 | — |
| `FlashLight_AngleHead_Army` | `items/drainable.txt:1031` | 2 | — |
| `CanteenMilitary` | `items/normal.txt:13991` | 1 | — |
| `EntrenchingTool` | `items/weapon.txt:5881` | 3 | état ≥ 50 % |
| `Shoes_ArmyBoots` | `items/clothing.txt:18753` | 2 | état ≥ 50 % |
| `MilitaryMedal` | `items/normal.txt:8402` | 4 | — |

Refusés : tenues de camouflage, de chasse et vêtements civils, `Bag_Military` (simple sac de sport, « Duffel Bag »),
masques et filtres improvisés (`Hat_ImprovisedGasMask`, `GasmaskFilterCrafted`), munitions d'autres calibres.

## 3. Ce que le passeur apporte

Prix de vente selon la section 1 (`⌈V × quantité × (1 + marge) × M⌉`). Stock tiré à chaque passage dans la
fourchette ; les objets usables (piles, paquets) sont fournis pleins.

| Objet (`Base.X`) | Fichier:ligne | V | Stock par passage |
|---|---|---|---|
| `Battery` | `items/drainable.txt:673` | 2 | 4 – 12 |
| `Antibiotics` | `items/food.txt:15211` | 8 | 2 – 6 |
| `ShotgunShellsBox` (25 cartouches, `recipes/recipes_ammunition.txt` `OpenBoxOfShotgunShells`) | `items/normal.txt:13722` | 12 | 0 – 2 |
| `308Box` (20, fusil de chasse `HuntingRifle`) | `items/normal.txt:13487` | 14 | 0 – 2 |
| `3030Box` (20, carabine `L94_Rifle`) | `items/normal.txt:13547` | 12 | 0 – 1 |
| Graines, un sachet (refait par 5 graines, recette `PutSeedsInPacket`, `recipes/recipes_farming.txt`) : `CarrotBagSeed2`, `BroccoliBagSeed2`, `RedRadishBagSeed2`, `StrewberrieBagSeed2`, `TomatoBagSeed2`, `PotatoBagSeed2`, `CabbageBagSeed2`, `CornBagSeed`, `KaleBagSeed`, `OnionBagSeed`, `GarlicBagSeed`, `WheatBagSeed`, `LettuceBagSeed` | `items/literature.txt:249, 276, 303, 330, 357, 384, 411, 452, 466, 522, 536, 578, 1005` | 3 | 3 – 8 sachets, 4 sortes au plus |
| `CigarettePack` | `items/drainable.txt:2087` | 3 | 2 – 8 |
| `CigaretteCarton` (10 paquets, `UnpackCigaretteCarton`) | `items/normal.txt:10104` | 25 | 0 – 1 |
| `Whiskey` / `Vodka` | `items/normal.txt:6536` / `6510` | 5 | 1 – 4 bouteilles au total, alcools confondus |
| `Wine` / `Wine2` | `items/normal.txt:6563` / `6591` | 3 | (même total) |
| `BeerPack` | `items/normal.txt:6728` | 4 | (même total) |
| `Coffee2` (« Coffee », boîte de café) | `items/food.txt:4728` | 4 | 1 – 3 |
| `RadioReceiver` | `items/normal.txt:4557` | 4 | 0 – 2 |
| `RadioTransmitter` | `items/normal.txt:4569` | 6 | 0 – 2 |
| `Amplifier` | `items/normal.txt:4503` | 4 | 0 – 2 |
| `ElectricWire` | `items/normal.txt:4525` | 1 | 2 – 5 |
| `ElectronicsScrap` | `items/normal.txt:4536` | 1 | 2 – 5 |
| Journal du dehors (`RadioSurvivor.OutsideNews`, document du mod, E13-T05) | `media/scripts/RadioSurvivor_outsidenews.txt` | 2 | 1 (une édition par passage) |

Valeur moyenne d'un stock complet : environ 140 points (≈ 175 au prix de vente calme). Le plafond de 120 points pris
par passage empêche de tout acheter : il faut choisir, et la rareté reste réelle.

**Journaux récents : pas d'objet vanilla convenable.** Les journaux vanilla `Newspaper_New`, `Newspaper_Recent` et
`Newspaper_*_New` (`items/literature.txt:4174-4239`) reçoivent à leur création un numéro d'**avant l'épidémie** :
`RecipeCodeHelper.nameNewspaper` (`<decompiled>\42.21.0\java\zombie\scripting\logic\RecipeCodeHelper.java:35-43`)
prend un numéro au hasard, ou le **dernier numéro paru** pour le tag `base:newspaper_new`. Aucun ne porte des nouvelles
du dehors. Il faudra un **document du mod** : un objet `literature` sans `CanBeWrite`, avec `modData.printMedia` posé
côté serveur (base `quest-building-blocks.md`, « Document de mod au rendu des journaux », titre distinct par édition,
tag `base:fastread`). Son contenu (nouvelles du dehors écrites par le LLM ou par gabarit) relève d'une tâche à créer ;
cette table ne fixe que sa valeur.

**Réalisé en E13-T05** (fiche `docs/conception/journal-du-dehors.md`) : objet `RadioSurvivor.OutsideNews`, nouvelles
du dehors tirées de gabarits FR/EN (une, trois brèves, prix de la semaine), datées du jour du passage ; une édition par
passage (`RS_OutsideNewsServer.create(passage)`, point d'appel de l'échange E13-T04). Valeur de vente 2
(`RS_TradeValues.SELL_ONLY`) ; hors module `Base`, il vaut 0 quand on le rend au passeur (section 1, « Ce qui est
toujours refusé »).

## 4. Exemples d'échanges complets (passeur)

Les prix sont calculés ligne par ligne, arrondis à l'entier supérieur.

1. **Première affaire, semaine calme** (marge 0,25, M = 1,0). Le joueur dépose une liasse `MoneyBundle` (10), un
   `Necklace_Gold` (4) et deux `IDcard` nominatives (6) : **20 points**. Il demande 2 `Antibiotics` :
   ⌈8 × 2 × 1,25⌉ = **20**. Accepté, rien de perdu.
2. **Cordon serré** (marge 0,25, cordon 1,5). Le joueur dépose une `CameraExpensive` (10), deux `VHS_Home` (12) et deux
   `CameraFilm` (6) : **28 points**. Une `308Box` coûte ⌈14 × 1,25 × 1,5⌉ = **27** ; y ajouter deux piles
   (⌈2 × 2 × 1,875⌉ = 8) dépasserait. Accepté pour la seule boîte ; le point d'écart reste au passeur.
3. **Lot militaire** (marge 0,25, M = 1,0). Le joueur dépose un `AssaultRifle` en bon état (20), un `Vest_BulletArmy`
   (10), une `556Box` (8) et trois `Necklace_DogTag` nominatives (12) : **50 points** (militaire 38 ≤ 60, papiers
   12 ≤ 30). Il obtient une `CigaretteCarton` (⌈25 × 1,25⌉ = 32), une bouteille de `Whiskey` (7), un `Coffee2` (5) et
   deux `Battery` (⌈4 × 1,25⌉ = 5) : **49**. Accepté.
4. **Rareté et réputation.** Ce passage ne compte qu'**un** antibiotique (rareté 1,25), cordon 1,25 :
   - équipe neutre (marge 0,25) : ⌈8 × 1,25 × 1,5625⌉ = **16** (M = 1,25 × 1,25 = 1,5625 ≤ 1,75) ;
   - équipe fidèle (marge 0,10) : ⌈8 × 1,10 × 1,5625⌉ = **14** ;
   - après une tricherie (marge 0,50) : ⌈8 × 1,50 × 1,5625⌉ = **19**.

Ordre de grandeur : un passage moyen échange 20 à 60 points, soit une bonne fouille de quartier (bijoux, papiers,
quelques images) contre 2 à 5 objets rares. Une semaine sans passage rend chaque antibiotique précieux.

## 5. Même barème avec un groupe Living Knox ami (`LK11-T08`)

### Principe

- **Même valeur V** que le passeur. Un groupe de la zone n'a aucun débouché pour l'argent, les bijoux, les images et
  les papiers : ces quatre catégories valent **0** pour lui (il les refuse). Il échange ce qui le fait vivre.
- **Marge du groupe** selon l'attitude envers ce joueur (`LK11-T03`) : ami 0,10, neutre 0,30, hostile = pas de troc.
- **Multiplicateur de besoin** à la place du cordon, par réserve abstraite (`docs/conception/simulation.md` : réserves
  0 – 100, seuils `NEED_LOW` = 25, `NEED_OK` = 40, `NEED_TARGET` = 60) :
  - **ce que le groupe achète** : V × 1,5 si la réserve concernée est sous 25 ; × 1,0 entre 25 et 60 ; × 0,5 au-dessus
    de 60 ; refus à 100 ;
  - **ce que le groupe vend** : ⌈V × quantité × (1 + marge)⌉, sans cordon.
- **Le groupe ne vend pas ce qui lui manque** : une vente qui ferait passer une réserve **sous `NEED_OK` = 40** est
  refusée (motif « on en manque nous-mêmes »). Il vend aussi seulement des objets de son **stock réel** (`LK08-T07`) :
  la réserve donne le droit de vendre, le stock fournit l'objet.

### Objets qui alimentent ou vident les réserves

Conversion proposée : **1 point de réserve = 4 points V**, arrondi au plus proche (une vente de 20 V retire 5 points de
réserve, un achat de 16 V en ajoute 4). Elle reste à recaler avec `LK08-T07` et le calibrage des expéditions (une
expédition `houses` de 4 survivants rapporte en moyenne food +16, soit 64 V, environ trente conserves).

| Réserve | Objets (`Base.X`, fichier:ligne) | V |
|---|---|---|
| `food` | conserves `TinnedBeans` (`items/food.txt:4381`), `TinnedSoup` (`4433`), `CannedChili` (`3727`), `CannedCornedBeef` (`3778`), `CannedCorn` (`3828`), `CannedPeas` (`4077`), `CannedPotato2` (`4176`), `CannedTomato2` (`4278`), `CannedBolognese` (`3624`), `CannedFruitCocktail` (`3884`) | 2 |
| `food` | `Rice` (`items/food.txt:5006`), `Pasta` (`4959`), `DriedBlackBeans` (`4786`), `PeanutButter` (`13359`) | 2 |
| `medical` | `Antibiotics` (`items/food.txt:15211`) / `AntibioticsBox` (12 comprimés, `items/normal.txt:8144`, `recipes/recipes_packing.txt:315`) | 8 / 90 |
| `medical` | `Bandage` (`items/normal.txt:8071`), `AlcoholWipes` (`items/drainable.txt:1506`) | 1 |
| `medical` | `Disinfectant` (`items/normal.txt:8283`), `Pills` (« Painkillers », `items/drainable.txt:1414`), `SutureNeedle` (`items/normal.txt:8156`) | 3 |
| `ammo` | `ShotgunShellsBox` 12, `308Box` 14, `3030Box` 12, `556Box` 8 (lignes de la section 3 et 2.4), `Bullets9mmBox` (50 cartouches, `items/normal.txt:13693`) 10 | — |

Les autres objets du barème (piles, alcool, cigarettes, café, graines, pièces radio, matériel militaire) s'échangent au
même V **depuis et vers le stock réel** du groupe, sans toucher aux réserves abstraites.

### Exemple

Colons amis (marge 0,10), réserves `medical` 20 et `food` 70. Le joueur donne 2 `Antibiotics` : 16 V × 1,5 (besoin,
réserve sous 25) = **24**. Il demande 10 conserves `TinnedBeans` : ⌈2 × 10 × 1,10⌉ = **22**. Accepté : `medical`
+4 (16 V / 4), `food` −5 (20 V / 4), soit 65 ≥ 40. Le même jour, une demande de 3 `Antibiotics` au groupe serait
refusée : `medical` passerait de 24 à 18, sous 40.

## Questions ouvertes

1. **Écart non rendu** : le passeur garde l'excédent (proposé), ou le note comme crédit pour le passage suivant (mémoire
   des affaires passées, E13-T02) ?
2. **Armes et munitions militaires** : garder `AssaultRifle`, `556Clip` et `556Box` dans ce que le passeur prend
   (proposé, plafonnés), ou limiter le matériel militaire aux équipements sans arme ?
3. **Journal du dehors** : créer un document du mod (`printMedia`, une édition par passage, tâche à ajouter au plan), ou
   retirer les journaux du catalogue d'apport faute d'objet vanilla ?

## Décisions du 2026-10-10

Table validée telle quelle par l'utilisateur. Questions ouvertes tranchées : l'écart reste au passeur ; M16 et boîtes de 5.56 acceptés avec plafond ; les journaux récents seront un document propre au mod (tâche `E13-T05`).
