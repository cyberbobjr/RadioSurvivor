# Entretien du foyer : générateur, lumières, sang, verre brisé, morts

- Tâche : LK05-T10 (idées I3.5, I3.6 de `docs/annexes/recherches/idees-bandits-alife.md`)
- Code : moteur `Contents/mods/batman_LivingKnox/42.21/media/lua/server/LivingKnox/LK_Upkeep.lua`, tâches `.../LivingKnox/Jobs/LK_Job_*.lua`, potager `.../LivingKnox/LK_Garden.lua` (LK15-T01) ; points d'accroche dans `LK_Routines.lua` (comportement `chore`, `Routines.exec`, `leave`/`forget`) ; matériaux par `LK_Stock.lua` (`findItem`, `findFluid`, `drawFluid`, `takeItem`) ; banc `tests/test_lk_upkeep.py` ; suite en jeu `lk.upkeep` (`dev/batman_LivingKnoxTests/42.21/media/lua/shared/RST/suites/RST_LKUpkeep.lua`)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\` ; Lua vanilla **M/** = `media/lua`) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement

Base de connaissances : [power-and-lights.md](../../../../.claude/pz-knowledge/power-and-lights.md) (générateurs, carburant, interrupteurs), [api-42-21.md](../../../../.claude/pz-knowledge/api-42-21.md) (`FluidContainer:adjustAmount`), [multiplayer.md](../../../../.claude/pz-knowledge/multiplayer.md) (synchronisation d'un objet dans un meuble). Aucune ligne de Bandits! ni de Project A-Life n'a été lue : seules les idées I3.5 et I3.6 sont reprises.

## Problème

Les corvées de LK05-T04 sont visuelles. Un foyer habité doit aussi s'entretenir : générateur rempli et réparé avec les matériaux du stock, pièces éclairées le soir, sang lavé, débris ramassés. Chaque effet modifie le monde partagé : il doit être appliqué une seule fois par l'autorité, consommer exactement ce qu'il faut et rester dans le foyer.

## Choix

### Tâches (liste fermée, ordre = priorité)

| Tâche | Condition (zone du foyer : `LK_Homes.RADIUS` cases, niveau du foyer) | Matériau (conteneurs du foyer) | Effet (comme le vanilla) | Preuve vanilla |
|---|---|---|---|---|
| `refuel` | générateur (`IsoGenerator`) **du groupe** (LK05-T19) à moins de `RADIUS` cases, carburant < 5 l (sur 10) | récipient dont le fluide principal est `Fluid.Petrol` | prise = min(contenu, place libre) ; récipient vidé d'autant ; `setFuel` | `ISAddFuel.lua:52-63`, J/iso/objects/IsoGenerator.java:436-456 |
| `repair` | générateur du groupe **arrêté**, état < 60 | une `Base.ElectronicsScrap` | pièce retirée ; état + 4 (`setCondition`) | `ISFixGenerator.lua:6-11, 62-77` |
| `clean` | case du bâtiment du foyer avec `haveBlood()` | produit `Fluid.Bleach` ou `Fluid.CleaningLiquid` ≥ `ZomboidGlobals.CleanBloodBleachAmount` (0,24999 l) + outil `CleanStains` non cassé | produit diminué de la dose ; `removeBlood(false, false)` ; `removeGrime()` ; l'outil reste | `ISCleanBlood.lua` (`complete`), J/iso/IsoGridSquare.java:4657-4675, 4778-4840 |
| `glass` | case du bâtiment du foyer avec `getBrokenGlass()` | aucun | `triggerEvent("OnObjectAboutToBeRemoved", verre)` puis `transmitRemoveItemFromSquare` | `ISMoveableSpriteProps.lua:1481-1491`, J/iso/IsoGridSquare.java:2657, 5072-5098 |

- Relevé des tâches d'un groupe au plus toutes les `SCAN_MINUTES` (10) minutes de jeu, seulement quand toute la zone du foyer est lisible (`Homes.ready`). Les matériaux sont seulement **vus** au relevé ; ils sont relus et pris au moment de l'effet.
- Le générateur doit être à moins de `RADIUS` cases (une case de marge) : la place du membre à côté reste dans la zone du foyer. **Seulement les générateurs du groupe** (LK05-T19, décision de l'utilisateur du 2026-10-14 : « seulement le leur ») : `refuel` et `repair` ne retiennent qu'un générateur marqué `ModData.LKGenerator = <groupe>` (marque posée à l'aménagement du foyer sur les générateurs déjà dans le bâtiment, voir [foyers.md](foyers.md)), relue au relevé et au moment de l'effet. Un générateur d'origine inconnue (sans marque : celui d'un joueur, ou un générateur ramassé puis reposé) ou marqué par un autre groupe n'est jamais rempli ni réparé.
- Compétence : un PNJ n'a pas de niveau d'Électricité ; la réparation compte le niveau 0 du vanilla (+4 par pièce). Le plein ne demande aucune compétence en vanilla.

### Arrosage (LK05-T11)

Tâche `water` ajoutée après `repair` : plante cultivée assoiffée de la zone, hors pluie, eau croupie du stock d'abord ; voir [nourriture.md](nourriture.md).

### Potager du jardinier : graines reçues, sillon, semis (LK15-T04 à T06)

ADR `adr-registre-routines.md` D07, D08 et Q01 (valeurs confirmées par défaut le 2026-11-13). Trois tâches, chacune dans son fichier de `Jobs/`, prises dans l'ordre du registre par tous les membres, jardinier compris (révision du 2026-11-16, voir « Ordre ») ; aides de domaine et réglages dans `LK_Garden.lua` (`Garden.CFG`). Sources vanilla 42.22 (`M` = `media/lua`, `J` = Java) relevées le 2026-11-13.

| Tâche (`order`) | Condition (zone du foyer) | Effet | Preuve vanilla |
|---|---|---|---|
| `seeds` (42, `LK_Job_SeedSupply.lua`) | groupe avec un jardinier vivant (rôle portant `garden`) ; moins de `SEED_LOW` (2) graines **semables ce mois-ci** dans les conteneurs du foyer ; aucun sachet depuis `SEED_DAYS` (7) jours de jeu ; une variété de saison parmi carotte, pomme de terre, chou, tomate ; un conteneur de dépôt | `SEED_PACKET` (5) graines d'une variété rangées dans le dépôt (`AddItems`, `sendAddItemsToContainer` sur un serveur), jour retenu ; journal du groupe | sachet de 5 graines : `recipes_farming.txt:111-127` ; graines `seedTypes` ou `{ seedName }` : `ISFarmingMenu.lua:1138` |
| `sow` (44, `LK_Job_Sow.lua`) | sillon vide (état `plow`) ; une graine du stock dont la variété a le mois courant dans `sowMonth` | une graine retirée (`Stock.takeItem` : conteneur, clients, référence dans la même écriture) puis `plant:seed(variété, 0)` ; journal du groupe | commande `seed` refusée hors `plow` : `M/server/Farming/farmingCommands.lua:89-97` ; `SPlantGlobalObject:seed` : `SPlantGlobalObject.lua:715-732` ; mois : `getMonth() + 1`, `:162-173` |
| `dig` (46, `LK_Job_Dig.lua`) | aucun sillon vide dans la zone ; moins de `MAX_PLOTS` (6) sillons et plantes vivantes ; première case hors du bâtiment, à l'air libre (`isOutside`), creusable comme le menu vanilla : ni tombe, ni sillon ni plante vivante, rez-de-chaussée, `isFree(false)`, sol `dirt` | herbes hautes (`removeTallGrass`), herbe du sol (`removeGrass`), plante morte retirées, puis `SFarmingSystem.instance:plow(case)` ; l'outil reste au stock | `ISFarmingMenu.canDigHereSquare` : `M/client/Farming/ISUI/ISFarmingMenu.lua:514-534` ; `ISShovelGroundCursor.GetDirtGravelSand` : `M/server/BuildingObjects/ISShovelGroundCursor.lua:97-132` ; `ISPlowAction:complete` : `M/shared/Farming/TimedActions/ISPlowAction.lua:110-124` ; `plow` : `SFarmingSystem.lua:508-536` ; refus d'une case déjà prise : `J/globalObjects/GlobalObjectSystem.java:40-48` |

- **Ordre** : récolte (30) et arrosage (40) d'abord, puis l'entretien du foyer (ménage 50, verre 60), puis graines (70), semis (72), creusage (74) : les plantes vivantes passent avant le potager à venir, l'entretien du foyer passe avant la création du potager, et une graine trouve son sillon avant qu'on en creuse un autre. Raison : campagne MP du 2026-11-13 (`lk.upkeep`), où un sachet de graines puis un sillon creusé à mains nues sont passés avant le verre brisé et le sang, et la scène d'entretien n'a pas fini en 300 s (premier classement : 42, 44, 46). **Révision du 2026-11-16** : le jardinier prenait encore ces trois tâches en premier (`prefer = "garden"`) ; dans la campagne MP du 2026-11-16 (`runs/20261116-174655-mp-728f528426ed`), les deux ouvriers du groupe ont enchaîné sillons et semis, qui se renouvellent sans fin, et le verre n'a jamais été ramassé. Le jardinier ne prend plus d'abord que les plantes en terre (arrosage, récolte) ; graines, semis et creusage suivent l'ordre du registre pour tous.
- **Un sillon à la fois** : on ne creuse pas tant qu'un sillon vide attend sa graine (le vanilla efface un sillon resté vide : marque `plowDay`), d'où au plus un sillon vide même sans graine.
- **Outil** : objet du stock non cassé portant le tag `DigPlow` (`Garden.DIG_PLOW`, prédicat vanilla `predicateDigPlow`, `ISFarmingMenu.lua:20-22` ; pelles, truelles, binettes, pioches : `media/scripts/generated/items`). Sans outil, mains nues et durée doublée comme `ISPlowAction:getDuration` (`:132-144`) : `DIG_MINUTES` (3) avec outil, 6 sans. Le moteur lit cette durée par le champ générique `duration(job, gid)` du registre (ajouté en LK15-T04, lu au début du travail).
- **Semable** : le type de l'objet est une graine de la définition (`seedTypes`, sinon `seedName`) et la variété est de saison. Jamais un objet de nourriture (la pomme de terre et la tomate figurent dans des listes de graines vanilla) : le groupe ne sème pas ses vivres. Hors saison, rien n'est semé (le vanilla sèmerait une plante « maudite » avec l'option `PlantGrowingSeasons`).
- **Tirage de la variété** : parmi les variétés de la liste qui sont de saison, à tour de rôle d'une fenêtre de 7 jours à la suivante (`Garden.seedVariety(jour, mois)`, sans hasard) ; aucune de saison (septembre à janvier) : aucun sachet.
- **Pourquoi une tâche et pas un dépôt silencieux** : le sachet arrive par la main d'un membre, à l'écran, quand le foyer est chargé ; la tâche suit le même registre que les autres (aucun `if` ajouté au moteur).
- **Référence du stock** : les graines (`DisplayCategory = Gardening`) ne sont dans aucune catégorie du stock ; ajoutées comme les produits d'une récolte (référence complétée pour les seuls objets classés), elles ne sont ni comptées, ni vues perdues ou volées à la relecture `Stock.check`. Une graine semée est ôtée de la référence si elle y était suivie (`Stock.takeItem`).
- **Mémoire** : le jour du dernier sachet n'est pas sauvegardé (comme le reste de l'entretien) : un redémarrage du serveur rouvre la fenêtre (voir Limites).

### Exécution

- **Registre (LK15-T01, ADR `adr-registre-routines.md` D01 à D03).** `LK_Upkeep.lua` est le moteur : relevé, réservation, geste, effet une fois, compteurs ; il ne nomme aucune tâche. Une tâche s'inscrit par `LivingKnox.Upkeep.registerJob(spec)` : `kind` (nom unique), `order` (plus petit d'abord, puis `kind`), `prefer` (comportement de rôle facultatif, `"garden"`), `gesture`, `minutes`, `survey(gid, g, area)` (cases ouvertes `{ x, y, bid }`), `apply(job, gid, who, sq)` (effet, matériaux relus), et facultatifs `place(job, home)` (`home` : foyer du groupe, LK15-T07), `standOnSelf`, `groupLog`, `duration(job, gid)` (minutes de cette tâche-ci, lues au début du travail ; LK15-T04).
- **Un fichier par tâche** : `server/LivingKnox/Jobs/LK_Job_<Nom>.lua` (`refuel`, `repair`, `harvest`, `water`, `seeds`, `sow`, `dig`, `clean`, `glass`), qui commence par `require "LivingKnox/LK_Upkeep"` et s'inscrit au premier niveau. Le jeu charge le dossier seul : **ajouter une tâche = ajouter un fichier**, sans modifier le moteur. Les réglages propres à une tâche vont dans `Upkeep.CFG` (valeurs par défaut dans le fichier). Le potager partagé par l'arrosage et la récolte est dans `server/LivingKnox/LK_Garden.lua` (`LivingKnox.Garden`).
- Branchée dans `Routines.apply` pour le comportement `chore` (de jour, au foyer, postes `keeper`, `carer`, `forager`, `builder` et routine) : `Upkeep.run` passe avant la corvée visible. Aucune modification de `LK_Decisions.lua`.
- Un membre prend la première tâche ouverte qu'aucun autre membre ne tient (`claims` par groupe et clé). Jardinier (comportement `garden` de son rôle : travailleur des colons, décision du 2026-11-13) : il prend d'abord une tâche dont `prefer` est `garden` (`water`, `harvest`), puis les autres dans l'ordre. Il va à une case libre voisine de l'objet (`Routines.exec.placeBeside`, règle des corvées ; à défaut la case tachée elle-même pour `clean` et `glass`), se tourne vers l'objet, fait le geste (`kneel` : plein, lavage ; `rummage` : réparation, verre), attend `WORK_MINUTES` minutes de jeu (3, 5, 3, 2), puis l'effet est appliqué.
- **Place dans le rayon du foyer (LK15-T07)** : la place où se tenir doit être « au foyer » pour les décisions (`Upkeep.atHome` : même niveau, la case entière à `HOME_RADIUS` cases au plus du centre de la case du foyer, lu dans `LivingKnox.Decisions.CFG` ; rayon 10 → 9 cases au plus, un corps arrêté n'étant pas au centre de sa case). Par défaut, le moteur écarte les voisines hors du foyer avant `placeBeside` ; une place hors du foyer (rendue par `place` ou par défaut) est **refusée dès la prise** : tâche abandonnée, plus proposée pendant `DONE_MINUTES`, jamais libérée pour être reprise aussitôt. Le potager ne creuse un sillon que sur une case entière « au foyer » (`Garden.digSpot`) et cherche la place d'arrosage, de récolte et de semis parmi les cases libres « au foyer » (`Garden.placeNear(job, home)`, même ordre que `Bodies.findFreeSquare`). Raison : campagne MP du 2026-11-13 (`lk.upkeep`, reproduite au banc en `E19-T04`) : premier sillon au bord de la zone (10 cases), place à côté à 11 cases ; le membre arrivé n'était plus « au foyer », quittait sa routine (`Decisions.apply` → `Routines.leave`), la tâche libérée était reprise par l'autre ouvrier, sans fin ; le verre et le sang n'étaient jamais faits. Même boucle possible avant la correction pour une plante mûre ou assoiffée posée au bord de la zone (case libre la plus proche au-delà du rayon) et, dans un grand bâtiment, pour une tache ou un verre au bord de la zone.
- **Une seule fois** : la phase passe à `done` avant l'effet (même si le Java lève une erreur, `pcall`) ; tâche faite ou abandonnée → plus proposée pendant `DONE_MINUTES` (10) ; interrompue avant l'effet (menace, autre consigne, corps retiré : `Routines.leave`/`forget`) → rien n'est fait, la tâche est libérée.
- **État relu** au moment de l'effet : générateur parti, déjà plein, en marche (réparation), sang déjà lavé, verre déjà ramassé, matériau emporté entre-temps → rien n'est fait (`skipped`).
- Journal du moteur pour chaque effet ; journal du groupe (kind `upkeep`) pour le générateur seulement (le lavage remplirait les 32 entrées).

### Matériaux (`LK_Stock`)

- `Stock.findItem(gid, pred)`, `findFluid(gid, fluides, minimum)` : lecture des conteneurs du foyer (mêmes conteneurs et même ordre que le stock).
- `Stock.drawFluid(gid, fluides, voulu, minimum, qui, usage)` : un seul récipient, `adjustAmount(contenu - prise)` (la quantité est **fixée**, base api-42-21.md), quantité exacte rendue ; sur un serveur `sendItemStats(objet)` : l'objet est dans un meuble, `syncItemFields` ne vise que l'inventaire d'un joueur ou un objet au sol (J/inventory/InventoryItem.java:4154-4170) alors que `sendItemStats` envoie aux clients proches du meuble une copie du fluide (J/network/GameServer.java:2944-2964, J/network/packets/ItemStatsPacket.java:160-168, 520-523).
- `Stock.takeItem(gid, pred, qui, usage)` : retrait comme un repas (`DoRemoveItem`, `sendRemoveItemFromContainer`), ôté de la référence s'il y était suivi (essence, Javel, pièces électroniques ne sont pas dans les catégories du stock : la référence ne change pas, rien n'est vu comme perdu ou volé).
- Rien n'est jamais créé.

### Lumières

- À chaque minute de jeu (`EveryOneMinute`), de `LIGHT_FROM` (19 h) à `LIGHT_TO` (7 h), pour chaque groupe dont le foyer est dans un bâtiment chargé : un membre incarné qui **entre** dans une pièce du bâtiment de son foyer (niveau du foyer, zone du foyer ; pièce différente de la précédente, ou première vue de la soirée) allume les interrupteurs éteints de la pièce que le courant permet d'allumer (`IsoLightSwitch:canSwitchLight` : ampoule et réseau ou générateur, J/iso/objects/IsoLightSwitch.java:392-447). `setActive(true)` allume toute la pièce, envoie `SyncIsoObject` aux clients proches et se sauvegarde (:449-530, 582-630).
- Lampes sur pile (`getCanBeModified() and getUseBattery()`, dont la lampe posée par `LK_Homes`) écartées : elles n'ont pas besoin de courant de la pièce et usent leur pile.
- Une lumière éteinte par un joueur pendant que le membre reste dans la pièce n'est pas rallumée (pas de nouvelle entrée).
- Au jour, la mémoire des pièces est effacée.

### Morts portés à une tombe : non fait

- Aucun chemin vanilla fiable sans LK07-T04 (mort unique et cadavre) : la tombe vanilla est un objet de deux cases creusé à la pelle (`graves`), le corps enterré est le cadavre que le **joueur** a saisi (`ISBuryCorpse:complete` cherche `lastPlayerGrabbed` = identifiant du joueur), puis la tombe est comblée (`ISFillGrave`). Un corps de PNJ n'a pas encore de cadavre unique (LK07-T04) et aucune action vanilla ne porte un cadavre sans personnage joueur. Reste documenté, à reprendre après LK07-T04 (enterrement « hors action » : retrait du cadavre et pose d'une tombe comblée, à concevoir).

## Alternatives écartées

- Éteindre le générateur avant le plein puis le rallumer (idée I3.6) : le vanilla remplit un générateur en marche (`ISAddFuel` n'exige pas l'arrêt) ; démarrer un générateur à l'intérieur rendrait le bâtiment toxique (base power-and-lights.md). Le plein se fait donc sans arrêt ; la réparation, comme le vanilla, seulement à l'arrêt.
- Ramasser des objets au sol comme « déchets » : aucune notion de déchet en vanilla ; un objet au sol peut appartenir à un joueur. Seul le verre brisé est un débris de case.
- Décision de la cascade (nouveau comportement `upkeep`) : demandait de modifier `LK_Decisions.lua`, partagé ; l'entretien est une corvée prioritaire.

## Multijoueur

- Tout sur l'autorité : `LK_Upkeep` s'arrête sur un client (`isClient()`). Effets synchronisés par le Java ou les envois vanilla : `setFuel`/`setCondition` (`sync()` sur un serveur), `sendItemStats` (récipient), `sendRemoveItemFromContainer` (pièce), paquet `RemoveBlood` (`removeBlood` sur un serveur), `transmitUpdatedSpriteToClients` (`removeGrime`), `GameServer.RemoveItemFromMap` (verre), `SyncIsoObject` (lumières).
- Banc MP : le serveur verse une fois, un seul envoi du bidon, mêmes consignes et gestes chez deux clients ; aucun module d'entretien chez un client.

## Tests

- Banc `tests/test_lk_upkeep.py` : plage éclairée ; générateurs retenus seulement s'ils sont marqués pour le groupe (LK05-T19 : générateur d'un joueur dans la maison et au jardin, vide et usé, intact ; générateur remplacé par un générateur sans marque avant l'effet : rien fait) ; adoption à l'aménagement dans `tests/test_lk_homes.py` ; relevé (matériaux requis, ordre, rien hors du bâtiment ni de la zone, autre niveau) ; plein exact (2 + 4 l, bidon vide gardé ; grand bidon : place libre seulement) ; réparation avec une pièce ; lavage d'une dose et verre retiré, une fois ; interruption avant l'effet (rien versé, tâche libérée, puis faite une fois) ; fausse tâche dont la place est hors du rayon « au foyer » : refusée, close avec son délai, reprise par personne pendant une minute de jeu (LK15-T07) ; scène `lk.upkeep` sur le vrai potager vanilla avec une cour de 10 cases (`test_garden_at_the_edge_of_the_home_does_not_hold_the_upkeep`) ; plante mûre au bord de la zone récoltée depuis une place « au foyer », prise une fois (`test_lk_garden.py`) ; matériau emporté avant l'effet (rien fait) ; lumières (entrée, lampe sur pile écartée, sans courant, hors bâtiment, jour, soir suivant, événement minute) ; MP (serveur seul, un envoi, mêmes vues) ; suite listée, sources sûres pour Kahlua.
- Banc `tests/test_lk_garden.py` (LK15-T04 à T06) : ordre des tâches et préférence ; graines semables (mois, `seedTypes`, jamais de nourriture) ; tirage reproductible ; sillon creusé une fois, herbes retirées, outil gardé, un seul sillon vide ; mains nues deux fois plus long, outil cassé ignoré ; cases refusées (tombe, maison, toit, case occupée, gravier, hors zone, plante vivante, étage), plante morte recreusée ; plafond relu à l'effet ; une graine en moins et une plante semée, rien hors saison ni de la nourriture ; sachet une fois par fenêtre, rien sans jardinier, rien au seuil, rien en hiver, référence du stock inchangée ; MP (serveur seul, envois une fois) ; suite `lk.garden` sur les doublures.
- En jeu : `RST.run({ suite = "lk.garden", tags = "world" })` en solo, joueur dans une maison avec un conteneur et de la terre libre dehors dans la zone du foyer, au printemps ou en été ; campagnes `solo-lk` et `mp`.
- En jeu : `RST.run({ suite = "lk.upkeep", tags = "world" })` en solo, dans une maison avec un meuble à conteneur (générateur de la suite marqué pour le groupe ; second générateur sans marque qui doit rester intact) ; MP : campagne automatique.

## Limites et restes

- ⚠ API réelles non vérifiées en jeu : `IsoGenerator.new` d'un objet `Base.Generator` (suite), `sendItemStats` d'un objet dans un meuble, `removeBlood` sur un serveur, `IsoRoom:getLightSwitches` depuis Lua.
- Pas d'extinction des lumières (départ de la pièce, jour, coucher) ; le générateur paie leur consommation.
- Un générateur jamais démarré par les PNJ (ni branchement, ni démarrage).
- Sang : la dose du vanilla nettoie la case et le sol voisin (une case autour) ; les murs tachés des cases voisines restent.
- Relevé limité au niveau du foyer ; mémoire non sauvegardée (recalculée).
- Potager (LK15-T04 à T06) : ⚠ non vérifié en jeu (`ISShovelGroundCursor.GetDirtGravelSand` sur un serveur dédié, `plow` et `seed` sans joueur vus par deux clients, `removeGrass` sur un serveur). Jour du dernier sachet en mémoire : un serveur redémarré peut donner un sachet de plus dans la fenêtre de 7 jours. Le réglage `PlaceDirtAboveground` n'est pas suivi (rez-de-chaussée seulement). Un membre non jardinier peut aussi prendre ces tâches (préférence seulement, comme l'arrosage). Les autres suites en jeu avec des colons (`lk.upkeep`, `lk.forage`...) peuvent désormais laisser un sillon, des graines reçues ou semées dans la maison de test.
- Valeurs (seuils, durées, plage éclairée) à recalibrer en jeu.
- Décisions à confirmer : déchets = verre brisé seulement ; lumières allumées de 19 h à 7 h, jamais éteintes ; générateur d'un joueur dans la zone entretenu ; plein sans arrêt.

## Plafond des tâches (2026-10-14)

`MAX_JOBS` garde toujours la première tâche de chaque sorte (`Upkeep.capJobs`), puis complète dans l'ordre de `JOBS` :
une maison tachée de sang partout (combats) remplissait les huit places de « clean » et le verre brisé n'était jamais
proposé. Confirmé par l'utilisateur le 2026-10-14 (ordre inchangé quand la liste tient dans le plafond).
