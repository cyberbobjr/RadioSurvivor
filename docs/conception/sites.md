# Sites des foyers

- Tâches : LK08-T03 (création), LK08-T08 (repli des pillards assoupli), E10-T05 (anneau autour d'un centre) ; servira LK08-T04 (aménagement des foyers), LK08-T05 (population initiale), LK09 (relève, déménagement)
- Build : 42.21.0 — Date : 2026-10-10 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Sites.lua` (autorité seulement), qui réutilise `media/lua/server/RadioSurvivor/RS_Rescue.lua` (tirage d'un bâtiment par la métagrille, E12-T01, [rescue.md](../rescue.md)) : `Rescue.check`, `Rescue.knownBases`, `Rescue.gap` et le tirage Park-Miller `Rescue.drawer` (exposé pour cette tâche, comportement inchangé).

## Problème

Choisir où un groupe s'installe, sans charger la zone : un vrai bâtiment habitable pour les colons et les neutres, une clairière en forêt pour les pillards ; loin des bases des joueurs et des foyers des autres groupes ; sur la terre ferme ; tirage borné et reproductible par graine. Le choix ne pose rien et n'affecte pas le foyer : l'appelant (LK08-T05) fera `LivingKnox.Groups.setHome(id, site.x, site.y, site.z)`, et LK08-T04 aménagera le lieu au premier chargement.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| La métagrille répond sans rien charger : `getBuildings()` (tous les `BuildingDef`), `getCellData`, `isValidSquare`, `IsoMetaCell:getBuildingsIntersecting` des seules cellules utiles. | base `world-placement.md` (« Choisir un point lointain », « Tirer un bâtiment de la carte ») ; [rescue.md](../rescue.md) | confirmé statiquement |
| Les zones de forêt (`DeepForest`, `PHForest`, `BirchForest`…) ne viennent plus d'`objects.lua` en B42 (`metazoneHandler.lua` ignore `Forest`, `DeepForest`, `Vegitation`, `TownZone`…) mais du canal G de la biomemap. | `media/lua/server/metazones/metazoneHandler.lua:93` ; `media/lua/server/metazones/BiomeMapConfig.lua` ; base `map-files.md` | confirmé statiquement |
| Ces zones ne sont inscrites dans la métagrille, pour **toute une cellule** 256 × 256, qu'au premier chargement d'un de ses chunks (`IsoChunk.LoadOrCreate` → `ZoneGenerator.genForaging`), puis sauvegardées (`map_zone.bin`). Une cellule jamais approchée dans la partie n'a aucune zone de forêt, et `BiomeMap` (`getWorld():getBiomeMap()`) n'est pas exposé à Lua. | `J/iso/IsoChunk.java:2219-2221`, `J/iso/worldgen/zones/ZoneGenerator.java:59-138`, `J/iso/worldgen/maps/BiomeMap.java:21-110` ; `LuaManager.java` (aucun `setExposed(BiomeMap.class)`) ; base `world-placement.md` (« Eau d'une case non chargée ») | confirmé statiquement |
| `IsoMetaCell:getZonesIntersecting(x, y, z, w, h, liste)` ne lit que les métachunks existants (`hasChunk`) : aucun n'est créé, rien n'est chargé ; `IsoMetaGrid:getZonesIntersecting` interroge seulement les cellules couvertes. `IsoMetaGrid:getZonesAt` crée en revanche un métachunk vide s'il manque (aucun chargement). | `J/iso/IsoMetaCell.java:88-116, 235-253`, `J/iso/IsoMetaGrid.java:210-235, 1183-1197` | confirmé statiquement |
| Les zones de la biomemap sont des rectangles au grain du chunk (8 cases) : un chunk dont un pixel est de l'eau est couvert par une zone `Water`. La zone `Forest` n'est affectée qu'aux rives argileuses des lacs (pixels 59 et 79). | `ZoneGenerator.java:59-138` ; `BiomeMapConfig.lua` | confirmé statiquement |
| Routes : zones `Nav` tirées de `streets.xml`, connues partout dès le chargement de la carte. | base `world-placement.md` (« Point sur la terre ferme ») | confirmé statiquement |
| `RoomDef:isExplored()` est sauvegardé (drapeau 1 de `map_meta.bin`) et lisible sans charger ; il passe à vrai quand un joueur voit la pièce (y compris côté serveur par `ServerLOS` → `IsoGridSquare.CalcVisibility`), mais aussi pour le bâtiment d'apparition, une alarme, les histoires de bâtiment et les cachettes. Aucune date : « déjà vu », jamais « récemment ». La date de dernière vue n'existe que par case chargée (`IsoGridSquare.getHoursSinceLastSeen`). | `J/iso/RoomDef.java:34, 72, 304` ; `J/iso/IsoMetaGrid.java:880-910, 1010-1032` ; `J/iso/IsoGridSquare.java:7457-7465, 7544-7556, 8861-8880` ; `J/network/ServerLOS.java:277` ; `J/network/GameServer.java:2558` ; `J/AmbientSoundManager.java:196` ; `J/randomizedWorld/randomizedBuilding/RBBurnt.java:33` | confirmé statiquement |
| Un client MP charge aussi `media/lua/server` : garde `isClient()`. Aucune ModData globale pour un état privé. | base `mod-loading.md`, `multiplayer.md` | confirmé statiquement |

## Choix

Retenu le 2026-10-10 (LK08-T03), dans le cadre du contrat de la tâche.

```lua
local site, reason = LivingKnox.Sites.pick("raiders", { seed = 42 })
```

**Style de foyer** : réglage `home` du type de groupe (`building` pour `settlers`, `neutrals` ; `forest` pour `raiders`, [groupes.md](groupes.md)), remplaçable par `opts.home`.

**Bâtiment** (`kind = "building"`, `key = "b<id>"`) : tirage dans `getBuildings()` et contrôle `Rescue.check` (habitable par ses pièces, ni construction de joueur ni sous-sol seul, surface minimale, loin des bases, pas sur l'eau connue, point au centre d'une pièce principale) ; type admis par `Sites.KINDS_BY_TYPE` (colons : ferme, maison avec garage, maison, église, école, motel, caserne, immeuble ; neutres : maison, maison avec garage, ferme, motel, immeuble, clinique, église ; un type absent admet tout bâtiment habitable ; `opts.kinds` remplace la liste) ; loin des autres foyers ; **aucune pièce explorée** (I8.2).

**Clairière** (`kind = "clearing"`, `key = "c<x>_<y>"`, `z = 0`) :
1. relevé des zones de forêt connues : grille des cellules parcourue de `getMinX..getMaxX` × `getMinY..getMaxY` (au plus `MAX_CELLS` = 20 000 emplacements), un appel `IsoMetaCell:getZonesIntersecting` par cellule existante ; types `Sites.FOREST_ZONES` (`DeepForest`, `PHForest`, `PRForest`, `FarmForest`, `FarmMixForest`, `BirchForest`, `BirchMixForest`, `OrganicForest`), rive `Forest` écartée ; une cellule est « connue » si elle porte une zone de la biomemap (`biome_map_config` du jeu relu s'il existe) ;
2. tirage d'une zone au prorata de sa surface utile, puis d'un point à `CLEARING_RADIUS` (8) cases au moins de son bord ;
3. contrôle : carré de 17 × 17 cases entièrement couvert de forêt (sondes au plus tous les 8 cases), aucune zone `Water` qui le croise, aucune route `Nav` à 40 cases (`ROAD_DISTANCE`), aucun bâtiment à 60 cases (`BUILDING_DISTANCE`), loin des bases et des foyers ; un seul `IsoMetaGrid:getZonesIntersecting` par essai.

**Repli** (validé par l'utilisateur le 2026-10-10, assoupli par LK08-T08) : si aucune zone de forêt n'est connue, ou si aucun point ne convient après `MAX_ATTEMPTS` essais, **bâtiment le plus isolé** vu pendant les tirages, rendu avec `kind = "building"`, `fallback = "isolated-building"`, `fallbackReason`, `isolation`, `isolationTier`, `candidates` et `lair` (repaire) ; journal `WARN sites: no forest clearing for … fallback to an isolated building: <type> <clé>, isolation …, best of … candidate(s)`. `opts.noFallback` le désactive.
   - *Constat en jeu* (2026-10-10, `rstest-1010`) : l'ancienne règle « habitable et aucun autre bâtiment à 100 cases » échouait sur la carte vanilla (300 tirages : `not habitable` 135, `not isolated` 135, aucun succès ; 3 groupes de pillards sur 3 sans foyer).
   - *Candidats* : tout bâtiment habitable (`RS_Rescue.KINDS`, types `KINDS_BY_TYPE` ignorés) ou, pour les types de `Sites.LAIR_TYPES` (pillards), un **repaire** de la liste fermée `Sites.LAIR_KINDS` : entrepôt (`warehouse`, `storageunit`, `factory`, `loggingfactory`, `metalshop`), grange (`barn`, `farmstorage`), garage (`garagestorage`, `mechanic`, `carsupply`), station-service (`gasstore`, `gasstorage`, `fossoil`), atelier (`toolstore`, `shed`) — noms de pièces vanilla de `Distributions.lua` — avec une pièce de ces noms au niveau 0 d'au moins `LAIR_MIN_ROOM_AREA` = 25 cases (refus `lair room too small`) ; point du site au centre de cette pièce. Mêmes contrôles qu'un foyer de bâtiment : `Rescue.check` (avec `opts.rules` = habitables puis repaires), distance aux bases et aux autres foyers, aucune pièce explorée.
   - *Isolement* : écart (`Rescue.gap`) au plus proche autre bâtiment de la métagrille, relevé dans le carré de `ISOLATION_RADIUS` = 100 cases (cellules couvertes seulement) et plafonné à 100.
   - *Paliers dégressifs* `ISOLATION_TIERS` = 100, 60, 30, chacun sur une tranche égale des tirages (`Sites.tierAt` : tirages 1-100, 101-200, 201-300) : le meilleur candidat vu (isolement le plus grand, le premier à égalité) est rendu dès qu'il atteint le palier en cours ; sinon, après tous les tirages, le meilleur candidat quel que soit son isolement (`isolationTier = 0`). **Échec** seulement si aucun bâtiment tiré ne passe les contrôles (raison : `no suitable isolated building after 300 draw(s): near a known base …`).

**Bases et foyers** : bases des joueurs = `Rescue.knownBases(opts)` (refuges, joueurs connectés ou locaux, `opts.avoid`) à `BASE_DISTANCE` = 600 cases ; foyers = `LivingKnox.Groups.list()` puis `get(id).home`, sauf `opts.ignoreGroup`, plus `opts.homes`, à `GROUP_DISTANCE` = 400 cases (écart entre l'emprise du site et le point). `baseDistance` et `groupDistance` du site donnent l'écart réel au plus proche.

**Anneau autour d'un centre** (E10-T05, foyer d'un membre parti, [depart.md](depart.md)) : `opts.near = { x, y, min,
max [, widen] }`, foyer de bâtiment seulement (sinon `near option needs a building home` ; option malformée :
`bad near option`). Candidats = bâtiments des cellules qui croisent le carré de rayon `max` autour du centre
(`IsoMetaCell:getBuildingsIntersecting`, comme le relevé d'isolement ; jamais `getBuildings()`), emprise à `max` cases
au plus, mélangés par la graine ; au plus `MAX_ATTEMPTS` examinés par palier. Contrôles habituels (`checkBuilding`)
plus : bâtiment qui contient le centre refusé (`center building`), point du site à moins de `min` (`too close to the
center`) ou à plus de `max` (`beyond the ring`, seul refus réexaminé au palier suivant). Aucun candidat : `max` x
`NEAR_WIDEN` (2, puis 4 ; `widen` le remplace), un `WARN` par palier refusé, puis tirage habituel sur la carte entière
(minimum et bâtiment du centre toujours exclus, `nearTier = 0`, `nearFallback` = raisons des paliers). Champs du site :
`nearDistance`, `nearTier`, `nearMin`, `nearMax`. Sans `near`, rien ne change.

**Bornes** : au plus `MAX_ATTEMPTS` (300) tirages par recherche (bâtiment, clairière, repli) ; le relevé des forêts coûte un appel par cellule existante de la carte, pas par case. Graine : `Rescue.drawer` (Park-Miller) ; même site pour la même carte, les mêmes mods de carte, les mêmes cellules approchées et les mêmes foyers.

**Résultat** : table simple (sérialisable, aucun objet Java), ou `nil` et la raison en anglais : `no suitable building after 300 draw(s): near a known base 212, …`, `no forest zone known in the metagrid (… cell(s), … known)`, `unknown group type …`.

Valeurs chiffrées : points de départ propres au mod (600 cases repris d'E12-T01, bien au-delà de la zone chargée de 79 cases), à recalibrer en jeu.

## Alternatives écartées

- **Lire la biomemap directement** : `BiomeMap` n'est pas exposé et `getFileReader` lit en UTF-8 (octets invalides en U+FFFD, base `logs-and-tools.md`) : un PNG n'est pas lisible depuis Lua.
- **Tirer un point au hasard sur toute la carte** : la plupart des cellules ne sont pas approchées ; le taux d'échec serait très élevé et l'eau inconnue.
- **`getZonesAt` pour chaque sonde** : crée des métachunks vides ; `getZonesIntersecting` des cellules suffit.
- **Zones `Forest` des `objects.lua`** : ignorées par le jeu en B42.
- **Bâtiment visité « récemment »** : aucune date sans charger la case ; le drapeau d'exploration (« déjà vu ») est plus strict et c'est la seule donnée lisible.

## Idées reprises

- I8.2 (pas d'installation dans un bâtiment visité récemment par un joueur) : retenu sous la forme « aucune pièce explorée » (`RoomDef:isExplored`, `CONFIG.EXCLUDE_EXPLORED`, `opts.allowExplored` pour l'ignorer). Plus strict que l'idée (aucune notion de date) et marque aussi les bâtiments vus par le jeu lui-même (apparition, alarme, histoires de bâtiment). Pour une clairière, aucune donnée équivalente.

## Tests

- Banc lupa (`tests/test_lk_sites.py`, 40 tests ; étape `lk_sites` de `tests/run_all.py`) : doublures de la métagrille de `tests/test_rescue.py` complétées (`getMinX..getMaxY`, `getZonesIntersecting` de la grille et des cellules, objets `Zone`, `RoomDef:isExplored`), vrais `LK_GroupTypes`, types livrés et `LK_Groups` (fichiers en mémoire). Colons et neutres : bâtiments admis, loin du joueur, essais bornés ; filtre de types ; bâtiment exploré jamais retenu ; foyer d'un autre groupe évité (vrai registre), `ignoreGroup`, `homes` ; pillards : 40 clairières valides (forêt, sans eau, ni route, ni bâtiment proches) et variées dans trois types de forêt, chaque refus avec sa raison (base, eau, lisière, route, bâtiment, rive `Forest`, cellule jamais approchée, hors carte, exclu, autre foyer), relevé des zones et coupure `MAX_CELLS` ; repli bâtiment isolé sans forêt connue, `noFallback`, double échec ; LK08-T08 : carte réaliste sans forêt (villes en îlots de 48 cases, fermes et chapelets de maisons à 30-90 cases, aucun bâtiment à 100 cases d'isolement) où chaque graine de la suite et 30 autres donnent un foyer reproductible (isolement recalculé, palier, distances), paliers de `tierAt`, arrêt au premier palier atteint (dépôts isolés ajoutés), meilleur candidat conservé (premier des meilleurs vus), villes seules (palier 0 après 300 tirages), repaires admis pour les pillards seulement (grange, abri trop petit, commerce refusé), colons et neutres inchangés, échec seulement quand les distances excluent tout ; suite `lk.sites` aussi sur cette carte (6/6, détection d'un foyer près du joueur et d'un isolement faux) ; aucune lecture de case, aucun parcours lent, aucune écriture ; graine reproductible ; site en données simples ; client MP sans module ; suite `lk.sites` sur le vrai moteur RST (succès, puis détection d'un site près du joueur et d'un chargement).
- VM Kahlua : sans objet pour cette tâche (logique couverte par lupa ; pas de test Kahlua dédié).
- En jeu : suite `lk.sites` (tag `server`, lecture seule) — `RST.server("lk.sites")` en solo ou depuis un client admin : relevé des zones de forêt connues, cinq tirages par type (validité, distances, variété, reproductibilité), sondes de non-chargement (`LoadChunk` pendant les tirages et 3 s après, cases lisibles autour du joueur et sur chaque site, `isFullyStreamedIn`), refus d'une distance impossible, foyer d'un autre groupe évité. Chaque site est noté (`site type=… seed=…`, coordonnées, type, `FALLBACK`) pour aller voir sur place.

## Points ouverts

- Aucune source de forêt fiable sans chargement n'existe pour une cellule jamais approchée (42.21). En début de partie, presque aucune forêt n'est connue loin des joueurs : les pillards s'installent alors dans le **bâtiment le plus isolé** tiré (repli marqué, validé le 2026-10-10). Sur une carte dense, ce bâtiment peut avoir des voisins proches (`isolationTier` 30 ou 0) : à surveiller en jeu (`WARN sites: … isolation …`). Option possible si ce repli ne convient pas : livrer avec le mod une table de points de forêt pré-calculée hors jeu depuis les biomemaps vanilla (valable pour la carte vanilla seulement, à régénérer si la carte change).
- ⚠ La clairière n'est qu'un point de forêt : arbres, buissons et pente ne sont pas connus sans charger (génération procédurale, base `knox-geography.md`) ; LK08-T04 devra dégager ou déplacer le camp quand la zone est chargée.
- ⚠ Eau et forêt connues au grain du chunk ; une rivière d'une cellule approchée est vue, un lac d'une cellule non approchée ne l'est pas (sans effet ici : seules les cellules approchées sont tirées pour les clairières).
- ⚠ I8.2 : « exploré » n'a pas de date et ne couvre pas les pièces jamais vues d'un bâtiment visité ; une base de joueur sans refuge déclaré et les joueurs hors ligne ne sont pas des bases connues (même limite qu'[E12-T01](../rescue.md)).
- ⚠ Même graine pour deux types « bâtiment » = même bâtiment : la création de plusieurs groupes (LK08-T05) doit poser chaque foyer avant le tirage suivant ou passer `homes`.
- ⚠ Coût du relevé des forêts non mesuré sur la carte vanilla complète (noté par la suite en jeu).
