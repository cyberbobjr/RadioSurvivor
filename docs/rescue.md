# Survivants à secourir : bâtiment, indices, réserves et équipe (E12-T01, E12-T02)

Module `Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/RadioSurvivor/RS_Rescue.lua`, autorité seulement
(serveur dédié ou solo ; rien sur un client MP). Il choisit le bâtiment d'un groupe à secourir et rédige les indices
que la voix donnera, puis tient les secours en cours (réserves, délai, équipe : `E12-T02`, section « Secours en
cours »). Rien n'est encore envoyé au pont ; livraison et scènes viennent avec `E12-T03` et suivantes.

```lua
local Rescue = require "RadioSurvivor/RS_Rescue"
local site, reason = Rescue.pick({ seed = "team-alpha" })
-- site = { x, y, z, buildingId, key = "b<id>", kind, label, bounds = { x1, y1, x2, y2 }, baseDistance,
--          attempts, clues = { "The shelter is a two-storey house.", ... } }
```

Options de `pick` : `seed` (nombre ou chaîne : tirage reproductible), `minDistance` (défaut 600 cases),
`maxAttempts` (défaut 300), `minArea` (20), `avoid` (points `{ x, y }` ou rectangles `{ x1, y1, x2, y2 }` à fin
exclusive), `exclude` (ensemble de clés `key` déjà attribuées), `noClues`. Échec : `nil` et une raison, par exemple
`no suitable building after 300 draw(s): near a known base 212, not habitable 88`.
`Rescue.check(b, bases, opts, grid)` accepte aussi `opts.rules` (liste de types au format de `Rescue.KINDS`, qui la
remplace ; défaut inchangé) : `LivingKnox/LK_Sites` y ajoute les repaires des pillards (LK08-T08,
[conception/sites.md](conception/sites.md)).

## Tirage sans charger la zone

- Un index au hasard dans `getWorld():getMetaGrid():getBuildings()`, la liste de tous les `BuildingDef` de la carte
  après fusion des dossiers (Java 42.21 `IsoMetaGrid.consolidateBuildings`). Au plus `MAX_ATTEMPTS` tirages par
  appel : le coût est borné et ne dépend pas de la taille de la carte.
- Chaque essai ne lit que le `BuildingDef` (emprise, niveaux, surface, `isUserDefined`, `isBasement`), ses `RoomDef`
  (noms, niveau, rectangles), la métagrille au point retenu (`isValidSquare`, `getCellData`, `getZonesAt`) et les
  bases connues. Aucun `getGridSquare`, `getCell`, `getChunk`, `LoadChunk`, ni `getBuildingAt(x, y)` à deux
  arguments, qui parcourt toute la liste des bâtiments.
- Graine : Park-Miller (aucun opérateur binaire), même site pour la même graine tant que la carte et les mods de
  carte ne changent pas (l'ordre de la liste suit les fichiers de carte). Sans graine : `ZombRand`.
- Clé stable : `"b" .. BuildingDef:getIDString()` ; l'identifiant vient de la cellule du fichier de carte et du rang
  du bâtiment dans ce fichier (`BuildingID.makeID`). `getIDString` évite la perte de précision d'un `long` en Lua.

## Définitions retenues

**Habitable** : premier type de `Rescue.KINDS` dont les pièces correspondent, par leurs noms de `RoomDef` :
église (`church`), école (`classroom`, `elementaryclassroom`), poste de police (`policestorage`), caserne
(`firestorage`), hôpital (`hospitalroom`), clinique (`medical`, `medicalstorage`), motel (`motelroom…`), ferme
(`bedroom` et `barn` ou `farmstorage`), immeuble (au moins 4 `bedroom` et 2 `kitchen`), maison avec garage
(`bedroom` et `garagestorage`), maison (`bedroom` et `kitchen` ou `livingroom`). Sont exclus : construction de
joueur ou de l'éditeur de pièces (`isUserDefined`), bâtiment sans pièce ou dont la première pièce est sous terre
(sous-sol seul), surface totale sous `MIN_AREA`. La liste est fermée et se règle dans le module.

**Base connue** : refuges vanilla (`SafeHouse.getSafehouseList()`, rectangles à fin exclusive), position des joueurs
connectés (`getOnlinePlayers()` sur un serveur, joueurs locaux en solo, écran partagé compris) et points ou
rectangles passés par l'appelant (`avoid`). La distance est l'écart entre l'emprise du bâtiment et la base ; elle doit
dépasser `MIN_DISTANCE` (600 cases, bien au-delà de la zone chargée autour d'un joueur, 79 cases au plus). Ne couvre
**pas** : les joueurs hors ligne, une base sans refuge déclaré, les véhicules, les cachettes. Une source future
(équipe, refuge de faction) passera par `avoid`.

**Terre ferme** : un bâtiment de carte repose sur des cases de sol ; le point du site est le centre du premier
rectangle d'une pièce de niveau 0 ou plus (pièce principale du type de préférence), donc dans le bâtiment. Une zone
`Water` de la métagrille à ce point écarte aussi le bâtiment ; ces zones ne sont connues que des cellules déjà
approchées dans la partie (base `world-placement.md`), c'est un filtre de plus, pas une garantie.

## Indices

`Rescue.clues(building)` rend des phrases anglaises (pour le prompt du pont) sans aucun chiffre ; une phrase qui en
contiendrait est retirée. `Rescue.clueData(building)` (E11-T09) rend ces phrases et, dans le même ordre, leurs données
traduisibles `{ key, args }` (codes de type, taille, étages, repère, distance, direction ; nom de ville) que le carnet
compose dans la langue du joueur (`docs/protocole-carnet-v2.md`, « Indices dans le carnet »).

- Type, taille et étages : « The shelter is a large two-storey house with a garage. », « It has a basement. ».
- Jusqu'à trois repères voisins dans un rayon de 160 cases, parmi les bâtiments de la métagrille
  (`IsoMetaCell:getBuildingsIntersecting` des seules cellules couvertes), classés par leurs pièces
  (`Rescue.LANDMARKS` : station-service, épicerie, église, école, police, pompiers, pharmacie, motel, bar…), avec la
  direction (nord = y décroissant) et une distance en mots : « There is a gas station a short walk to the north. ».
- Voisinage : maisons voisines à moins de 80 cases (« a few other houses around it », « a built-up street », « on its
  own »).
- Ville la plus proche, seulement si la carte vanilla est chargée (`getLotDirectories()` contient `Muldraugh, KY`) :
  centres des annotations vanilla et rayons approximatifs de `Rescue.TOWNS`. Sur une carte de mod, pas de ville.

## Secours en cours (E12-T02)

Choix de conception : [conception/secours.md](conception/secours.md).

```lua
local id, rec = Rescue.start(player, { days = 3, requester = "Darlene" })  -- équipe du joueur (RS_Factions.idOf)
local id, rec = Rescue.startForTeam("fac-4", { seed = 7 })                 -- refus : nil, "team_busy", id actif
Rescue.activeFor("fac-4"); Rescue.get(id); Rescue.list()                   -- copies, avec daysLeft et hoursLeft
Rescue.addReserves(id, hours)                                               -- E12-T03 : dépôt réel constaté
Rescue.finish(id, "saved" | "missed" | "abandoned", { participants = { "Kate Smith" } })  -- E12-T04 / T05
Rescue.onOutcome = function(rescue, result) end                             -- écouteur unique facultatif
Rescue.pendingScenes(); Rescue.scenePlaced(id)                              -- scènes à poser au chargement
```

- **État privé** : `S.data.rescues = { seq, active = { [équipe] = id }, rescues = { [id] = secours } }` (fichier
  serveur `RS_State`, sauvegardé avec le carnet). Un secours : `id` (`rsc-<n>`), `team`, `state` (`active`,
  `saved`, `missed`, `abandoned`), `days`, `reserves` (heures, flottant), `consumed`, `delivered`, `startedAt` et
  `closedAt` (âge du monde), `requester`, `voice`, `site` (point, clé, type, emprise), `clues`, `clueData`,
  `scene` (`pending` puis `placed` pour les issues `saved` et `missed`).
- **Délai = réserves** : au départ `days × 24` heures, plafond de 10 jours après livraisons. `days` : `opts.days` s'il
  est donné (borné de 1 à 10 : bancs, suites en jeu), sinon l'option sandbox `RadioSurvivor.RescueDays` (E12-T06,
  `Const.rescueDays`, entier de 1 à 10, défaut 3 ; absente, non entière ou hors bornes : 3), lue au lancement de
  chaque secours : un secours en cours garde ses réserves quand l'option change. La voix annonce `daysLeft` (jours entamés).
- **Décompte** : sondage toutes les `RUN.POLL_MS` (1 s réelle, `OnTickEvenPaused`) et à chaque `EveryHours` ; l'écart
  de `getWorldAgeHours()` depuis le sondage précédent est retiré des réserves actives **seulement si au moins un
  joueur est connecté** (`getOnlinePlayers()` sur un serveur, joueurs locaux en solo). Sans joueur, l'écart est
  oublié : un serveur vide sans `PauseEmpty` ne fait mourir personne et rien n'est rattrapé au retour d'un joueur
  (au plus une seconde réelle mal attribuée). Le premier sondage d'une session ne retire rien ; un âge du monde
  qui recule (sauvegarde restaurée) non plus. Les heures sautées en dormant comptent (joueurs connectés).
- **Équipe** : `RS_Factions.idOf` (faction vanilla, ou joueur seul ; E09-T03). Un seul secours `active` par
  équipe ; les bâtiments des secours actifs ou dont la scène reste à poser sont exclus du tirage d'un autre.
- **Issues** : réserves à zéro → `missed` ; `saved` par E12-T04, `abandoned` par un appelant futur. À l'issue
  `saved` ou `missed`, un fait du jour `rescue` (`RS_Facts.record` : `result`, `requester`, `participants`, lieu
  arrondi à la ville) puis `Rescue.onOutcome`. L'équipe peut alors recevoir un nouveau secours. Au plus
  `RUN.MAX_CLOSED` (16) secours clos gardés, ceux dont la scène reste à poser en dernier.
- **Magasin de travail** : `Rescue.useStore(Rescue.newStore())` (suites en jeu) remplace l'état privé sans le
  marquer à sauvegarder ni écrire de fait ; `Rescue.useStore(nil)` y revient.

## Livraison sur place et approche (E12-T03)

`RS_RescueVisit.lua` (sondage d'une seconde réelle, autorité seulement ; choix détaillés :
[conception/secours-livraison.md](conception/secours-livraison.md)) :

- **Dépôt réel** : les vivres et soins d'un membre de l'équipe vus dans son inventaire dehors (à moins de 40 cases du
  bâtiment) comptent quand ils sont retrouvés, par leur identifiant d'objet, dans un conteneur de meuble du
  bâtiment à 8 cases d'un membre entré, à son étage. Objet utilisable seulement ; il est retiré (pris par les
  survivants) et `Rescue.addReserves` ajoute 8 h (aliment), 4 h (eau propre) ou 6 h (soins). Le butin du bâtiment
  ne compte jamais.
- **Approche** : premier sondage où un membre est à moins de 40 cases, au plus une fois par 12 h de jeu
  (`Rescue.noteApproach` : `approach = { at, dir, count, vehicle, smoke, aired }`, `approaches`). Mod requis Signal
  Smoke : fumée verte de 30 minutes à 2 cases du bâtiment côté du membre ; fumée refusée : description traduite (direction, un ou
  plusieurs, véhicule). Ligne diffusée sur la fréquence de la voix (`rec.voice`) par `RS_RadioServer.air`.
- `Rescue.startForTeam(team, { site = site })` impose un site déjà examiné (`Rescue.check`) : suites en jeu.

## Issue « à temps » (E12-T04)

`RS_RescueScene.lua` (choix détaillés : [conception/secours-issue.md](conception/secours-issue.md)) :

- **Déclenchement** (`RS_RescueVisit`) : après un dépôt réel, les membres proches sont notés comme aidants
  (`Rescue.noteHelpers(id, { { name, caller, cid } })`, `rec.helped`, `rec.helpers`) ; au premier sondage où plus
  aucun membre vivant et connecté n'est à moins de 40 cases, `Rescue.finish(id, "saved")` (participants = aidants).
- **À l'issue** (`Rescue.sceneHook` → `Scene.prepare`, sur le secours réel) : cache `RS_Caches` (table tirée par
  l'identifiant) avec une note verrouillée (`Base.SheetPaper2`, `IGUI_RS_RescueNote_*`) ; nouvel endroit tiré par
  `Rescue.pick` (`rec.moved`) devenu le lieu dit de la voix (`RS_PersonaState`, moral +2) ; souvenirs de la voix sur
  chaque aidant (`RS_Memory`) ; relevé de vie `RS_LifeLog.rescue` hors magasin de travail.
- **Scène** (`Scene.poll`, 2 s réelles) : le sac est posé quand la case du site est chargée (`RS_Caches.place`, une
  seule fois même après redémarrage), puis `Rescue.scenePlaced`.

## Issue « trop tard » (E12-T05)

`RS_RescueLost.lua` (choix détaillés : [conception/secours-trop-tard.md](conception/secours-trop-tard.md)) :

- **Survivants** (au départ, `RS_Rescue`) : `rec.survivors` = 2 ou 3 tenues vanilla distinctes de `Rescue.OUTFITS`
  (le premier est le demandeur), `rec.looks` = phrases anglaises sans chiffre que la voix dira.
- **À l'issue `missed`** (enveloppe de `Rescue.sceneHook`) : `rec.lost = { placing, placed, bodies, pages }`,
  dernières pages composées des faits du secours (`IGUI_RS_RescueLast_*`, aucune si `RadioSurvivor.LastPages` est
  coupée) ; relevé de vie `missed` des aidants liés au carnet, hors magasin de travail.
- **Scène** (`Lost.poll`, 2 s réelles) : quand la case du site est chargée, un cadavre par survivant dans sa tenue
  (`createRandomDeadBody`, jamais faux mort, marque `RS_RescueBody`), cahier verrouillé « Last pages of … » dans le
  cadavre du demandeur ; une seule fois, cadavres adoptés après un arrêt, puis `Rescue.scenePlaced`.

## Tests

- Hors jeu : `python RadioSurvivor/tests/test_rescue.py` (aussi l'étape `rescue` de `tests/run_all.py`).
  Doublures de la métagrille, des refuges, des joueurs et des cases ; toute lecture de case pendant un choix est
  comptée et doit rester à zéro ; la suite en jeu y est jouée par le vrai moteur RST.
- Hors jeu : `python RadioSurvivor/tests/test_rescue_visit.py` (étape `rescue_visit`) : dépôt réel, approche,
  fumée et repli sur la description.
- Hors jeu : `python RadioSurvivor/tests/test_rescue_scene.py` (étape `rescue_scene`) : issue « à temps », cache,
  note, nouvel endroit, mémoire, pose unique.
- Hors jeu : `python RadioSurvivor/tests/test_rescue_lost.py` (étape `rescue_lost`) : survivants et tenues, issue
  « trop tard », dernières pages, pose unique et adoption.
- En jeu : suite `rs.rescue.missed` (E12-T05, magasin de travail, debout dans un bâtiment),
  `RST.server("rs.rescue.missed")` : un cadavre par survivant dans la tenue décrite, cahier verrouillé dans le
  cadavre du demandeur, rien de plus au second passage ni après un arrêt simulé ; cadavres retirés à la fin.
- En jeu : suite `rs.rescue.saved` (E12-T04, magasin de travail, debout dans un bâtiment), `RST.server("rs.rescue.saved")`
  : issue `saved`, lieu et souvenir de la voix de test, un seul sac avec une note verrouillée, retiré à la fin.
- En jeu : suite `rs.rescue.visit` (E12-T03, magasin de travail, debout dans un bâtiment près d'un meuble à
  conteneur), `RST.server("rs.rescue.visit")` : une boîte apportée compte (+8 h) et part, une boîte de butin reste ;
  description quand aucune fumée n'est possible (module masqué le temps du test), puis fumée verte.
- En jeu : suite `rs.rescue.run` (E12-T02, tag `server`, magasin de travail : l'état privé n'est pas touché),
  `RST.server("rs.rescue.run")` : deux équipes, deux bâtiments, refus `team_busy`, équipe du joueur, décompte
  pendant 4 s égal à l'avance de l'âge du monde (joueur connecté) ou nul (serveur vide), clôture `missed`.
- En jeu : suite `rs.rescue.pick` (tag `server`, lecture seule, aucune partie `rstest*` exigée),
  `RST.server("rs.rescue.pick")` en solo ou depuis un client admin. Sonde du non-chargement : événements `LoadChunk`
  comptés pendant les tirages (zéro) puis pendant 3 s (aucun chunk dans un bâtiment tiré), cases lisibles au
  centre des chunks autour du joueur (même nombre avant et après) et dans chaque bâtiment tiré (zéro),
  `isFullyStreamedIn()` faux. Chaque site est noté (`site seed=…`, coordonnées, type, indices) dans le rapport pour
  être vérifié sur place.
