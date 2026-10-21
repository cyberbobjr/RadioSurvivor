# Expéditions physiques des fourrageurs et retour au foyer

- Tâches : LK05-T05 (création, 2026-10-12) ; s'appuie sur LK05-T02 (objectif `supply`, poste `forager`), LK08-T06/T07 (stock réel, manques), LK09-T02 (expédition abstraite), LK09-T03 (matérialisation) ; servira LK05-T11 (production de nourriture), LK09-T06 (stock hors écran)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\` ; **M/** = `media/lua` vanilla) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement

Code : `Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/LivingKnox/LK_Expeditions.lua` (`LivingKnox.Expeditions`, autorité seulement). Branchements (modifications minimales) : `LK_Decisions.lua` (comportement `expedition`, règle `duty`, faim/soif/fatigue au retour, `ctx.trip`, `Decisions.apply`), `LK_Materialize.lua` (`onReleased` → `Expeditions.onReleased`), `LK_Simulation.lua` (retour d'une expédition abstraite d'origine physique → `Expeditions.resolveAbstract`), `LK_Needs.lua` (activité `travel`). Banc `tests/test_lk_expeditions.py` ; suite en jeu `lk.expedition` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKExpedition.lua`).

## Problème

Quand le stock du foyer manque de quelque chose, une petite équipe doit vraiment partir : marcher jusqu'à un bâtiment proche choisi par le serveur, fouiller ses meubles, prendre de vrais objets utiles, les rapporter et les ranger au foyer. Deux joueurs doivent voir le même départ et le même retour. Si plus personne ne regarde (corps retirés loin des joueurs), l'expédition continue hors écran sans tuer personne, et le retour reprend l'état. Idées reprises : I4.1 (bâtiment choisi par le chef, conteneurs réservés, charge bornée, retour au dépôt), I4.2 (objets cherchés selon les manques, par catégories du jeu), voir [idees-bandits-alife.md](../recherches/idees-bandits-alife.md). Aucune ligne de Bandits! ni de Project A-Life n'a été lue pour cette tâche.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Les bâtiments et leurs pièces se lisent dans la métagrille sans rien charger : `IsoMetaCell:getBuildingsIntersecting` (cellules couvertes seulement), `BuildingDef:getX/getY/getX2/getY2` (fin exclue), `getRooms`, `getIDString` ; pièce : `getName`, `getZ`, bornes à fin exclue, `getRects`. | base `world-placement.md` (« Tirer un bâtiment de la carte… ») ; `J/iso/RoomDef.java:210-252` | confirmé statiquement |
| Le centre du premier rectangle d'une pièce (`RoomDef.RoomRect`, `getX2 = x + w`) est dans la pièce ; le centre de l'emprise d'une pièce en L ne l'est pas toujours. | `J/iso/RoomDef.java:252-274, 482-496` ; base `world-placement.md` | confirmé statiquement |
| Un conteneur jamais ouvert n'a pas forcément son butin : rempli au chargement du chunk, sinon à la première ouverture (`ISInventoryPage:checkExplored` : `ItemPicker.fillContainer(container, joueur)` puis `setExplored(true)`) ; `ItemPicker = ItemPickerJava`, rien sur un client MP ; un conteneur marqué exploré n'est plus envoyé à la demande d'un client : `sendItemsInContainer(objet, conteneur)` sur un serveur. | `M/client/ISUI/ISInventoryPage.lua:1511-1523`, `M/server/Items/ItemPicker.lua:1`, `J/inventory/ItemPickerJava.java:570-579` ; base `world-placement.md` (« Butin vanilla et objets du mod ») | confirmé statiquement |
| Retrait d'un objet d'un meuble : `DoRemoveItem` (une seule surcharge), `sendRemoveItemFromContainer` sur un serveur ; ajout : `AddItem`, `sendAddItemToContainer`. L'objet garde son identifiant (`getID`). | [stock.md](stock.md) (repas, kit) ; `J/inventory/ItemContainer.java:444, 1979` | confirmé statiquement |
| Un corps de PNJ sans joueur à `BODIES.RELEASE_RADIUS` (120) cases pendant 60 s est retiré ; `Materialize.onReleased` le rend « présent au foyer » pour la simulation et il est rematérialisé au foyer si un joueur en est proche. | [corps-registre.md](corps-registre.md) ; `LK_Bodies.lua` (`Bodies.release`, `releasePass`) | confirmé statiquement (banc) |
| Une consigne `move` est refusée au-delà de 60 cases (`Directives.MAX_TRIP`) et vers une case non chargée ou impraticable. | [consignes.md](consignes.md) ; `LK_Directives.lua` | confirmé statiquement (banc) |

## Choix

Retenu le 2026-10-12, dans le cadre du contrat de la tâche (aucune décision `à décider` dans LK05 pour LK05-T05). Valeurs de départ propres au mod (`Expeditions.CFG`), à recalibrer en jeu.

### Départ (`Expeditions.minutePass`, chaque minute de jeu, chaque groupe au plus toutes les 10 minutes)

| Règle | Valeur | Raison |
|---|---|---|
| Groupe matérialisé, objectif `supply` (LK05-T02) | — | L'objectif du groupe décide ; un groupe hors écran a ses expéditions abstraites (LK09-T02). |
| Aucune expédition abstraite ni physique en cours ; 240 minutes de jeu depuis la fin de la précédente | `COOLDOWN_MINUTES` | Une à la fois ; repos entre deux. |
| De 7 h à 16 h | `DEPART_FROM`, `DEPART_TO` | Retour avant la nuit. |
| Stock de référence avec des manques (`Stock.needs`, catégories sous leur visée, dans l'ordre du manque) | — | I4.2 : ce qui manque le plus d'abord. |
| Équipe : postes `forager` vivants, incarnés, au foyer, hors chef, santé ≥ 0,6, sans besoin élevé que l'expédition ne comble pas (LK05-T15 : faim admise si la nourriture est cherchée, soif si l'eau l'est ; fatigue et peur écartent toujours ; seuils `NEED_HIGH` de la cascade), par numéro ; 2 au plus, 1 au moins ; 1 membre reste au foyer | `TEAM_MAX`, `TEAM_MIN`, `MIN_HOME`, `TEAM_HEALTH` | Même règle de chef que la simulation (pas de succession pendant une absence). |
| Charge : 4 objets par membre, 8 au plus, sans dépasser la somme des manques | `CARRY_PER_MEMBER`, `CARRY_MAX` | I4.1 : charge bornée. |

### Lieu (`Expeditions.pickTarget`, I4.1 : choisi par le serveur, sans charger)

- Bâtiments de la métagrille à `MIN_DIST` (6) à `MAX_DIST` (45) cases du foyer (écart au rectangle), 64 au plus, triés par identifiant ; écartés : le bâtiment du foyer, tout bâtiment qui contient le foyer d'un groupe (rectangle, et identifiant si la case est chargée), les `SEEN_MAX` (8) derniers fouillés.
- Note : pour chaque pièce au niveau du foyer, somme de (rang inverse du manque) × `ROOM_SCORE` (10) des catégories que son nom promet (`Expeditions.ROOMS` : noms de pièce des distributions vanilla, par exemple `kitchen` → nourriture et eau, `bathroom` → soins, `gunstore` → munitions, `garagestorage` → matériaux), moins `DIST_WEIGHT` (0,5) par case ; meilleure pièce du bâtiment ; à note égale, le plus proche, puis l'identifiant. Reproductible : même carte, même foyer, mêmes manques → même lieu.
- Point visé : centre du premier rectangle de la meilleure pièce, puis la case libre la plus proche du même bâtiment (4 cases au plus) ; sinon bâtiment suivant (6 essais).
- Écrit au registre et au journal du groupe : kind `expedition`, `trip 1 to kitchen 135,107 (20 squares): m-3 m-4 for ammo 2, materials 4, water 10, …`.

### Exécution (comportement `expedition`, `Expeditions.apply`)

- Cascade ([decisions.md](decisions.md)) : un membre de l'équipe d'une expédition en cours (`ctx.trip`) prend `expedition` par la règle `duty`, quel que soit son poste du moment (une relève horaire ne casse pas l'expédition) ; clé `trip<n>`. Menace, peur et blessure passent avant (fuite, regard, retour au foyer) ; faim, soif et fatigue attendent le retour (pas de repas en route). Vigilance `guard` ; activité des besoins `travel`.
- Une consigne LK03 au plus par passage, au nom du cadre (`Routines.exec` : marche, regard, geste) ; une consigne étrangère passée entre-temps fait reprendre l'étape.
- `out` : chaque membre marche jusqu'à une place libre près du point visé (une par rang) ; la première arrivée ouvre `search`. Délai `OUT_MINUTES` (120) : sinon retour.
- `search` : conteneurs des cases du bâtiment visé, au niveau visé, à `SEARCH_RADIUS` (10) cases du point, 12 au plus, du plus proche au plus loin (relevé en mémoire). Chacun est **réservé** par un membre (I4.1 ; réservation rendue après `CLAIM_MINUTES` sans nouvelle) ; place libre devant (règle des corvées : `placeBeside`), regard, geste `rummage` pendant `RUMMAGE_MINUTES` (2). Puis, dans l'ordre des objets : catégorie du stock (`Stock.categoryOf`), nourriture et eau consommables (`Stock.consumable`), au plus le manque de chaque catégorie et la charge restante ; chaque objet est retiré (`DoRemoveItem`, `sendRemoveItemFromContainer`) et porté par l'expédition (objet gardé en mémoire, type, catégorie et identifiant écrits au registre). Conteneur jamais ouvert : butin vanilla tiré d'abord, comme à l'ouverture par un joueur (`ItemPickerJava.fillContainer(c, nil)`, `setExplored(true)`, `sendItemsInContainer` sur un serveur). Conteneur sans place devant ou hors d'atteinte : marqué fouillé, rien pris. Fin : manques couverts, charge pleine, plus rien à fouiller, ou délai `SEARCH_MINUTES` (60).
- `back` : retour à une case libre près du foyer ; le premier membre au foyer (10 cases, même niveau) ouvre le dépôt. Délai `BACK_MINUTES` (120).

### Dépôt (`Expeditions.deliver`, phase `deliver`)

- Dès que la zone du foyer est lisible (`Homes.ready`, `Stock.containers`) : conteneur posé par LK_Homes (caisse, tente), sinon le premier conteneur du foyer ; `AddItem`, `sendAddItemToContainer` sur un serveur ; entrées `{ i, t, c, k }` ajoutées à la référence du stock **dans la même écriture** que la clôture (la relecture suivante ne voit ni ajout inexpliqué, ni perte, ni vol) ; journal `return` : `trip 1 back from kitchen 135,107: 2 back, food +3 water +2` ; rationnement relu (`Stock.updateRation`).
- **Aucun objet créé** pour une fouille à l'écran : les objets rangés sont ceux pris dans les conteneurs (mêmes identifiants). Un objet porté perdu de la mémoire (redémarrage du serveur pendant l'expédition) est compté perdu (`, 1 lost`), jamais recréé : pas de doublon possible.

### Hors écran (LK09)

- `Materialize.onReleased` → `Expeditions.onReleased(gid, mid)` dans le même passage que le retrait du corps (avant toute rematérialisation) :
  - si un autre corps de l'équipe a encore un joueur à 120 cases : le membre retiré **quitte seulement l'équipe** (il est « au foyer » pour la simulation, comme tout corps retiré, et rematérialisé au foyer si un joueur en est proche) ;
  - sinon : **toute l'équipe passe hors écran** : champ `expedition` du groupe (LK09-T02) `{ place = "trip", team, departed, returns, trip = n }`, retour dans `ABSTRACT_HOURS` heures selon la phase quittée (3 en route, 2 en fouille, 1 au retour) ; journal `trip` : `trip 1 offscreen (out): m-3 m-4, back in 3 h`. Les absents ne sont jamais matérialisés (LK09-T03) ; les objets déjà portés restent en mémoire.
- Retour abstrait (`LK_Simulation.simulateHour`, heure `returns` → `Expeditions.resolveAbstract`, dans l'écriture du pas, sans accès au monde) : **aucun membre perdu ni blessé** ; pour chaque manque, un tirage par membre (chance `ABSTRACT_FIND` = 0,5, flux reproductible des expéditions de la simulation) rapporte un objet vanilla de `ABSTRACT_ITEMS`, dans la limite de la charge ; phase `deliver` ; journal `trip` : `trip 1 back offscreen: 2 back, 5 item(s) found`. Même registre et mêmes heures → même butin.
- Dépôt ensuite comme à l'écran, dès que le foyer est lisible ; seuls les objets **abstraits** sont créés à ce moment (`instanceItem`, bouteille remplie d'eau). Les membres, de nouveau présents, sont rematérialisés au foyer si un joueur est proche : l'état reprend.

### Registre (schéma 1 inchangé)

Champ facultatif `trips` du groupe, contrôlé par `Expeditions.validTrips` (malformé : oublié avec un avertissement), ignoré par `LK_Groups` :

```
trips = { v = 1, n = <expéditions parties>, last = <minute de jeu de la dernière fin>, seen = { <bâtiment> } (8 au plus),
          cur = { n, phase = out | search | back | away | deliver, team = { mid }, want = { { c, m } },
                  target = { x, y, z, b, room, label }, start, due (minute limite de la phase), cap,
                  carry = { { t, c, i (objet réel) | a = true (abstrait) } }, searched = { <clé de conteneur> },
                  from (phase quittée hors écran) } }
```

Champ `expedition` (LK09-T02) avec en plus `trip = n` : `validExpedition` de LK_Groups l'accepte tel quel (champ supplémentaire), une version antérieure du mod l'ignore et résout l'expédition comme un lieu inconnu (aucun résultat, aucune perte).

### MP

Tout sur l'autorité (`if isClient() then return end`) : choix, réservations, prises, dépôt. Les clients ne reçoivent que les consignes et gestes relayés (LK03) et les envois d'objets du moteur (`sendRemoveItemFromContainer`, `sendAddItemToContainer`) : deux observateurs voient le même départ, la même fouille et le même retour (banc : mêmes consignes chez A et B à chaque passage, une suppression et un ajout envoyés par objet).

### Coût

Départ examiné au plus toutes les 10 minutes de jeu par groupe (lecture du registre ; lieu : une requête de métagrille par cellule couverte, 64 bâtiments au plus). En route : une consigne au plus par membre et par passage. Relevé des conteneurs du lieu : 21 × 21 cases une fois par expédition.

### Cueillette (LK05-T11)

Quand la nourriture est le premier manque et qu'une zone de cueillette proche en rapporte assez à cette saison, l'expédition est de genre `forage` (champs `kind`, `k`, `r`, `target.zone`) : lieu dans la zone, tirages des tables de cueillette vanilla au lieu de la fouille, objets créés au dépôt, tirages restants faits au retour abstrait avec le même flux. Voir [nourriture.md](nourriture.md).

## Alternatives écartées

- **Objets portés dans l'inventaire du corps** (zombie) : un inventaire de zombie n'est pas un sac de personnage (perdu ou dédoublé au retrait et à la mort, sauvegarde incertaine) ; la mémoire de l'autorité plus la liste au registre suffit, avec perte possible au redémarrage plutôt que doublon.
- **Recréer au dépôt les objets portés perdus au redémarrage** : créerait un doublon si le monde n'a pas été sauvegardé après la prise.
- **Bâtiment tiré au hasard** (`ZombRand`) : non reproductible ; classement fixe par manques et distance.
- **Lieux abstraits de LK09-T02 au retour hors écran** (`houses`, `stores`…) : leur tirage de risque tue et blesse ; la tâche exige une bascule sans perte de membre.
- **Attendre toute l'équipe au lieu avant de fouiller** : la première arrivée commence ; l'autre rejoint (réservations).
- **Équipe hors écran dès le premier corps retiré** : un membre retiré alors que l'autre est encore vu quitte seulement l'équipe ; sinon un joueur qui suit l'équipe verrait son compagnon disparaître de l'expédition.

## Idées reprises

- I4.1 : bâtiment choisi par l'autorité (classement par manques et distance), conteneurs réservés (un membre par conteneur), charge bornée, retour au dépôt du foyer ; repos = délai entre deux expéditions.
- I4.2 : objets cherchés selon les manques du stock, par les catégories du jeu (`DisplayCategory`, fluide) de LK_Stock ; pièces de la carte promettant une catégorie (noms de pièce des distributions vanilla) ; aucun mot-clé de texte de joueur.

## Tests

- Banc lupa `tests/test_lk_expeditions.py` (13 tests) : classement (manques puis distance, foyer et bâtiments récents écartés, pièce hors niveau ignorée) ; cascade (expédition par la règle duty quel que soit le poste, faim/soif/fatigue au retour, peur, menace et blessure d'abord) ; retour abstrait reproductible, sans mort ni blessure, borné par la charge ; source sûre pour Kahlua ; pile solo : départ des deux éclaireurs vers la cuisine du bâtiment voisin (ni chef ni ouvrier), une expédition à la fois ; fouille d'un comptoir garni : 5 objets retirés une fois, outil laissé, rangés dans la caisse du foyer avec les mêmes identifiants, référence à jour, `Stock.check` sans perte ni vol, aucun objet créé, journal `return`, délai de repos ; menace en route qui interrompt puis reprise ; conteneur jamais ouvert rempli d'abord ; corps retirés loin des joueurs : bascule hors écran de toute l'équipe, absents non matérialisés, retour abstrait sans perte, butin abstrait rangé, membres rematérialisés ; membre retiré pendant que l'autre est vu : il quitte seulement l'équipe ; pile MP (serveur + deux clients) : mêmes consignes chez A et B à chaque passage, une suppression et un ajout envoyés par objet, rien créé, aucune expédition chez un client ; suite `lk.expedition` déroulée sur les doublures.
- VM Kahlua : sans objet (motifs interdits contrôlés dans la source par le banc).
- En jeu : suite `lk.expedition` (solo, tags `world`, maison avec un bâtiment meublé à 6-45 cases) ; MP à la séance finale.

## Points ouverts

- ⚠ À voir en jeu : chemin réel jusqu'au bâtiment (portes fermées, clôtures), place devant les meubles d'un vrai bâtiment, rendu de la fouille, `ItemPickerJava.fillContainer` appelé depuis le serveur sur un conteneur jamais ouvert, envoi aux clients des objets retirés et rangés.
- ⚠ Une seule pièce visée par niveau : seuls les conteneurs du niveau du foyer, à 10 cases du point visé, sont fouillés (pas d'étage).
- ⚠ Hors écran, l'équipe n'est pas matérialisée au bâtiment visé si un joueur s'en approche : elle « réapparaît » au foyer à son retour (simplification).
- ⚠ Dépôt en attente tant que le foyer n'est pas lisible : pas de nouvelle expédition entre-temps.
- ⚠ Objets portés perdus si le serveur redémarre pendant l'expédition (comptés perdus au journal).
- Décisions à confirmer : valeurs de `Expeditions.CFG` (équipe de 2, charge 4 par membre, 6-45 cases, 7 h-16 h, 4 h de repos), noms de pièce de `ROOMS` (chambre pour les munitions), butin abstrait (chance 0,5, objets de `ABSTRACT_ITEMS`), membre retiré seul qui quitte l'équipe.
