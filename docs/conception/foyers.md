# Aménagement des foyers : objets vanilla posés au premier chargement

- Tâche : LK08-T04 (création) ; sert LK08-T06 (stock réel dans les conteneurs du foyer), LK05-T03 (couchages relevés par les routines), LK14 (fortification progressive)
- Code : `Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/LivingKnox/LK_Homes.lua` ; banc `tests/test_lk_homes.py` ; suite en jeu `lk.homes` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKHomes.lua`)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\` ; Lua vanilla **M/** = `ProjectZomboid\media\lua\`) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement

Base de connaissances : [world-placement.md](../../../.claude/pz-knowledge/world-placement.md) (quand poser, placement différé), [barricades-and-constructions.md](../../../.claude/pz-knowledge/barricades-and-constructions.md) (barricade posée par script), [power-and-lights.md](../../../.claude/pz-knowledge/power-and-lights.md) (lampe sur pile), [custom-tiles-entities.md](../../../.claude/pz-knowledge/custom-tiles-entities.md) (meuble vanilla posé par script, tentes et sacs de couchage). Aucune ligne de Bandits! ni de Project A-Life n'a été lue ; l'idée de jeu vient de I8.3 (foyer lisible de l'extérieur).

## Problème

Un foyer choisi sans charger la zone (LK08-T03) n'est qu'un point. Quand un joueur approche pour la première fois, le lieu doit déjà paraître habité : fenêtres condamnées, lumière, couchages, réserves dans une maison ; tentes et feu dans un camp. L'aménagement doit être fait une seule fois, par l'autorité, avec des objets que chaque client reçoit et qu'un joueur peut démonter ou emporter, sans doublon après un redémarrage.

## Moment

| Règle | Raison |
|---|---|
| Examen à chaque `LoadChunk` (au plus une fois par seconde) et à chaque minute de jeu. | `LoadChunk` arrive à la fin du chargement d'un chunk, après les histoires de bâtiment et le butin (J/iso/IsoChunk.java:3612) ; il ne revient pas pour un chunk déjà chargé, d'où la minute. |
| Rien tant que la case du foyer et les quatre coins du carré de 10 cases ne sont pas lisibles (`getCell():getGridSquare`). | Évite la pose en bordure de zone chargée (base world-placement.md, « Placement différé »). |
| Bâtiment : attendre `BuildingDef:isFullyStreamedIn()` ou une pièce explorée. | L'histoire de bâtiment vanilla passe une fois, sur un bâtiment complet jamais exploré, et peut retirer ou vider des objets (base world-placement.md, « Quand poser »). |
| Option `LivingKnox.Enabled` fausse : rien. | Comme les autres modules du moteur. |

## Contenu (quantités modestes, tout vanilla, tout démontable)

| Foyer | Objets | Détails |
|---|---|---|
| Bâtiment (case du foyer dans une pièce) | 2 fenêtres barricadées | Fenêtres `IsoWindow` du bâtiment au niveau du foyer, fermées et non barricadées, les plus éloignées du foyer d'abord ; 2 planches côté extérieur (au-delà de 2 la vue est bloquée, J/iso/objects/IsoBarricade.java:234-236). |
| | 1 lampe sur pile allumée | `lighting_indoor_03_4` (lampe sur pied, rayon 12), pile pleine : lumière sans courant, visible du dehors ; la pile s'use (2,5e-4 par minute allumée, environ 2,8 jours). |
| | sacs de couchage | Jusqu'à un couchage par membre vivant (4 au plus), lits déjà présents comptés (un lit double = un lit) ; `camping_02_16` + `_17` (2 cases, drapeau `bed`). |
| | 1 caisse vide | `carpentry_01_16` (conteneur `crate`, 60) au fond de la maison ; LK08-T06 y range le stock initial ([stock.md](stock.md)). |
| Camp (case du foyer hors de toute pièce) | 1 feu de camp allumé | Système vanilla `SCampfireSystem` ; 120 minutes de combustible ; sur la case du foyer ou à 2 cases au plus. |
| | tentes | Une pour 2 membres vivants (1 à 3), petite tente `camping_01_1`/`_0` (est) ou `camping_01_2`/`_3` (sud), à 3, 4 ou 5 cases du feu ; leurs conteneurs (`tent`, 30) servent de réserve. |

Cases utilisées : praticables (`isFree(false)`), ni escalier, ni eau, ni buisson, ni meuble déplaçable, ni objet au sol ; dans le bâtiment du foyer ou hors de tout bâtiment ; jamais la case du foyer et son pourtour (bâtiment), ni une case intérieure contre une porte ou une fenêtre (postes de guet des routines), ni le pourtour d'un objet déjà posé (passages). Le camp ne coupe aucun arbre : une case boisée est simplement évitée.

## Pose (comme le vanilla, sans personnage, sur l'autorité)

| Objet | Chemin | Preuve |
|---|---|---|
| Meubles | `ISMoveableSpriteProps.new(sprite)`, objet d'inventaire `instanceItem(case)`, `placeMoveableInternal(nil, case, objet, sprite)` : objet créé, ajouté, conteneurs créés, ModData de l'objet d'inventaire recopiée, `transmitCompleteItemToClients` sur un serveur. | M/shared/Moveables/ISMoveableSpriteProps.lua:215-244, 2075-2560 |
| Meuble de 2 cases | Une pose par case de la grille de sprites (`getSpriteGridInfo`), comme la pose vanilla d'un objet `ForceSingleItem`. | ISMoveableSpriteProps.lua:1088-1176, 2024-2044 |
| Lampe | Objet `Moveable` réglé avant la pose : `setLightUseBattery(true)`, `setLightHasBattery(true)`, `setLightPower(1)` ; relu par `IsoLightSwitch.getCustomSettingsFromItem`. Puis `switchLight(true)` : la source de lumière est créée avant la pile, donc éteinte. | J/iso/objects/IsoLightSwitch.java:104-116, 392-400, 457-476, 531-543 |
| Barricade | Modèle `IsoWindow.addRandomBarricades` : côté sans pièce, `IsoBarricade.AddBarricadeToObject(fenêtre, opposé)`, `addPlank(nil, nil)`, `transmitCompleteItemToClients()` sur un serveur. | J/iso/objects/IsoWindow.java:1324-1343 ; IsoBarricade.java:85-108, 739-764 |
| Feu de camp | `SCampfireSystem.instance:addCampfire(case)`, `addFuel(120)`, `lightFire()` ; synchronisé par le système d'objets globaux. | M/server/Camping/SCampfireSystem.lua:62-77 ; SCampfireGlobalObject.lua:337-353 |

Chaque meuble et chaque barricade porte `ModData.LKHome = <groupe>` et `ModData.LKHomeKind = <sorte>` (recopiés de l'objet d'inventaire avant la transmission). Le feu de camp n'est pas marqué : sa ModData appartient à son système global.

**Générateurs du groupe (LK05-T19)** : juste avant la marque d'aménagement d'un foyer de bâtiment, chaque `IsoGenerator` du bâtiment du foyer (zone du foyer, niveau du foyer) sans marque reçoit `ModData.LKGenerator = <groupe>` (`Homes.adoptGenerators`, `Homes.markGenerator` ; lecture `Homes.groupGenerator`). Ce sont les générateurs déjà là quand le bâtiment devient le foyer. Aucun autre n'est jamais marqué : un générateur posé ensuite par un joueur, ou ramassé puis reposé (la marque ne suit pas l'objet : base power-and-lights.md), n'est pas celui du groupe. Un foyer aménagé avant LK05-T19 n'a aucun générateur marqué. Marquage idempotent (un arrêt entre le marquage et la marque le refait sans effet) ; un générateur marqué par un autre groupe est laissé.

Une erreur Java pendant une pose est attrapée (`pcall` par objet), journalisée, et n'empêche ni les poses suivantes ni la marque finale : la marque est déjà écrite, rien ne sera reposé.

## Une seule fois : marque persistante côté serveur

Champ facultatif `furnish` du groupe dans le registre privé des groupes (schéma 1 inchangé ; contrôlé par `LK_Homes`, ignoré par `LK_Groups`) :

```
furnish = { v = 1, hx, hy, hz, style = "building" | "camp", day, state = "placing" | "done",
            placed = { { k = "barricade" | "lamp" | "bed" | "crate" | "fire" | "tent", x, y, z }, ... } }
```

- Écrite **avant** la pose (`state = "placing"`), complétée après (`"done"`, liste des objets posés). Une marque `placing` relue au redémarrage vaut « fait » (avertissement), jamais une seconde pose.
- Foyer déplacé (`Groups.setHome`) : la marque ne correspond plus, le nouveau foyer est aménagé, l'ancien aménagement reste en place.
- Registre plus ancien que le monde (fichier restauré) : sans marque, si des objets marqués du groupe existent autour du foyer, la marque est rétablie d'après eux et rien n'est posé (`Homes.findTagged`). En plus : une case occupée n'est plus libre, une fenêtre barricadée est écartée, `addCampfire` refuse une case qui a déjà un feu.
- Après la pose, `LivingKnox.Routines.resurvey(gid)` : postes et couchages relevés de nouveau (les sacs de couchage comptent comme couchages, `BedType = badBed`).

## Multijoueur

Tout est posé sur l'autorité. Les meubles et les barricades sont transmis par `transmitCompleteItemToClients` au moment de la pose ; un client qui arrive plus tard les reçoit avec le chunk (objets sauvegardés avec la case). Le feu de camp suit le système d'objets globaux vanilla. Un client MP ne charge pas le module (`if isClient() then return end`). Critère « deux clients voient le même foyer » : à vérifier en jeu (suite `lk.homes` sur serveur dédié, puis contrôle visuel depuis un second client aux positions notées).

## Limites et restes

- ⚠ Rendu et pose réels à vérifier en jeu : lampe allumée sur pile sans courant (et en plein jour), sacs et tentes de deux cases bien orientés, caisse avec conteneur, feu allumé et synchronisé.
- Les groupes créés par les suites en jeu avec un foyer (lk.chores, lk.routines…) sont aussi aménagés ; leur nettoyage (`Groups.remove`) ne retire pas l'aménagement : `LivingKnox.Homes.clear(gid)` le fait.
- Rideaux tirés (I8.3) : non faits (hors du texte de la tâche).
- Aucune clairière dégagée : les arbres ne sont pas coupés ; un camp en pleine forêt peut avoir moins de tentes que prévu.
- Fenêtres des étages et fenêtres construites (`IsoThumpable`) jamais barricadées ici (LK14).
- Choix à confirmer : lampe sur pile plutôt que lampe de pièce (sans courant, une lampe de pièce reste éteinte) ; sacs de couchage plutôt que matelas ; caisse vide unique.

## Groupes des suites de test

`Homes.skip(gid)` écrit une marque « aménagé » vide sans rien poser : les suites en jeu qui créent un groupe avec un foyer (`lk.alert`, `lk.chores`, `lk.routines`, `lk.traversal`) l'appellent pour ne pas barricader ni meubler le site de leurs essais. Seule `lk.homes` aménage réellement.
