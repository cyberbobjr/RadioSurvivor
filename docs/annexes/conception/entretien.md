# Entretien du foyer : générateur, lumières, sang, verre brisé, morts

- Tâche : LK05-T10 (idées I3.5, I3.6 de `docs/annexes/recherches/idees-bandits-alife.md`)
- Code : `Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/LivingKnox/LK_Upkeep.lua` ; points d'accroche dans `LK_Routines.lua` (comportement `chore`, `Routines.exec`, `leave`/`forget`) ; matériaux par `LK_Stock.lua` (`findItem`, `findFluid`, `drawFluid`, `takeItem`) ; banc `tests/test_lk_upkeep.py` ; suite en jeu `lk.upkeep` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKUpkeep.lua`)
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

### Exécution

- Branchée dans `Routines.apply` pour le comportement `chore` (de jour, au foyer, postes `keeper`, `carer`, `forager`, `builder` et routine) : `Upkeep.run` passe avant la corvée visible. Aucune modification de `LK_Decisions.lua`.
- Un membre prend la première tâche ouverte qu'aucun autre membre ne tient (`claims` par groupe et clé). Il va à une case libre voisine de l'objet (`Routines.exec.placeBeside`, règle des corvées ; à défaut la case tachée elle-même pour `clean` et `glass`), se tourne vers l'objet, fait le geste (`kneel` : plein, lavage ; `rummage` : réparation, verre), attend `WORK_MINUTES` minutes de jeu (3, 5, 3, 2), puis l'effet est appliqué.
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

- Banc `tests/test_lk_upkeep.py` : plage éclairée ; générateurs retenus seulement s'ils sont marqués pour le groupe (LK05-T19 : générateur d'un joueur dans la maison et au jardin, vide et usé, intact ; générateur remplacé par un générateur sans marque avant l'effet : rien fait) ; adoption à l'aménagement dans `tests/test_lk_homes.py` ; relevé (matériaux requis, ordre, rien hors du bâtiment ni de la zone, autre niveau) ; plein exact (2 + 4 l, bidon vide gardé ; grand bidon : place libre seulement) ; réparation avec une pièce ; lavage d'une dose et verre retiré, une fois ; interruption avant l'effet (rien versé, tâche libérée, puis faite une fois) ; matériau emporté avant l'effet (rien fait) ; lumières (entrée, lampe sur pile écartée, sans courant, hors bâtiment, jour, soir suivant, événement minute) ; MP (serveur seul, un envoi, mêmes vues) ; suite listée, sources sûres pour Kahlua.
- En jeu : `RST.run({ suite = "lk.upkeep", tags = "world" })` en solo, dans une maison avec un meuble à conteneur (générateur de la suite marqué pour le groupe ; second générateur sans marque qui doit rester intact) ; MP : campagne automatique.

## Limites et restes

- ⚠ API réelles non vérifiées en jeu : `IsoGenerator.new` d'un objet `Base.Generator` (suite), `sendItemStats` d'un objet dans un meuble, `removeBlood` sur un serveur, `IsoRoom:getLightSwitches` depuis Lua.
- Pas d'extinction des lumières (départ de la pièce, jour, coucher) ; le générateur paie leur consommation.
- Un générateur jamais démarré par les PNJ (ni branchement, ni démarrage).
- Sang : la dose du vanilla nettoie la case et le sol voisin (une case autour) ; les murs tachés des cases voisines restent.
- Relevé limité au niveau du foyer ; mémoire non sauvegardée (recalculée).
- Valeurs (seuils, durées, plage éclairée) à recalibrer en jeu.
- Décisions à confirmer : déchets = verre brisé seulement ; lumières allumées de 19 h à 7 h, jamais éteintes ; générateur d'un joueur dans la zone entretenu ; plein sans arrêt.

## Plafond des tâches (2026-10-14)

`MAX_JOBS` garde toujours la première tâche de chaque sorte (`Upkeep.capJobs`), puis complète dans l'ordre de `JOBS` :
une maison tachée de sang partout (combats) remplissait les huit places de « clean » et le verre brisé n'était jamais
proposé. Confirmé par l'utilisateur le 2026-10-14 (ordre inchangé quand la liste tient dans le plafond).
