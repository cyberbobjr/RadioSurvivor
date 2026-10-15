# Routines des PNJ au foyer : guet aux postes, rondes, relèves et sommeil

- Tâches : LK05-T03 (création, 2026-10-11), LK05-T04 (corvées, 2026-10-11) ; suite : LK05-T06 (besoins : fatigue), LK05-T08 (alerte : réveil, portes), LK05-T09 (défense des postes)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-11 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Routines.lua` (`LivingKnox.Routines`, autorité seulement), appelé par `LK_Decisions.lua` (contexte d'un membre, application d'un état) et chargé par `LK_Server.lua`. Entrées : [decisions.md](decisions.md) (poste `sentry`, comportements `guard`, `patrol`, `sleep`), [groupes.md](groupes.md) (registre, foyer). Sorties : [consignes.md](consignes.md) (`Directives.moveTo`, `face`, `stop`), gestes ([corps-et-animations.md](corps-et-animations.md)), vigilance de la perception ([perception.md](perception.md)).

## Problème

Un groupe au foyer doit avoir une vie lisible : quelqu'un garde la maison, la nuit comme le jour, à tour de rôle ; une ronde fait le tour du bâtiment sans s'éloigner ; les autres dorment à un lit. Tout doit être décidé par le serveur (ou le jeu en solo), reproductible, vu de la même façon par deux joueurs, et céder la place à une menace. Idées reprises : I2.2 (sentinelle à pleine vigilance), I3.1 (horaires décalés, veille de nuit), I3.2 (laisse autour du foyer), I3.3 (maison tenue la nuit, cour à l'aube), voir [idees-bandits-alife.md](../idees-bandits-alife.md).

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Un lit (ou tout couchage proposé par le menu « Dormir ») est un objet dont le sprite porte le drapeau `IsoFlagType.bed` ; sa qualité est la propriété de tuile `BedType` (`goodBed`, `averageBed`, `badBed`…), `averageBed` si absente. | `J/iso/ISWorldObjectContextMenuLogic.java:321-323` (drapeau), `2847-2850` (`BedType`) ; `media/lua/client/ISUI/ISWorldObjectContextMenu.lua:2640-2646` ; `IsoObject.getProperties` = propriétés du sprite (`J/iso/IsoObject.java:3136-3141`), `PropertyContainer.has(IsoFlagType)` et `get(String)` (`J/core/properties/PropertyContainer.java:84, 162`) | confirmé statiquement |
| Bâtiment d'une case : `getBuildingDef` passe par la pièce (nil hors pièce) ; identifiant comparé par `getIDString`. | base `world-placement.md` ; `J/iso/IsoGridSquare.java:7805-7816` | confirmé statiquement |
| Porte, fenêtre et fenêtre construite d'un bord : `getDoorTo`, `getWindowTo`, `getWindowThumpableTo` entre deux cases voisines. | base `pathfinding-and-obstacles.md` ; `J/iso/IsoGridSquare.java:3107-3112, 3131-3172, 3228-3236` | confirmé statiquement |
| Un escalier est `isFree(false)` : à exclure des places. | base `world-placement.md` ; `J/iso/IsoGridSquare.java:2173-2175` | confirmé statiquement |
| Les variables d'animation ne sont posées que par la machine qui affiche le corps ; le serveur publie le geste voulu (relais LK03-T05). | [corps-et-animations.md](corps-et-animations.md) ; `J/characters/IsoGameCharacter.java:11374-11396` | confirmé statiquement |
| Clips joueur sur un corps de zombie : jouables par nos nœuds `lkactor_*` (AnimSets du zombie, condition `LKActor`). Assis au sol : clip `Bob_SitGround_Idle` (`media/AnimSets/player/sitonground-sitting/sit_loop.xml`). Couché : `Bob_Asleep` existe (`AnimSets/player/onbed/OnBedAsleep.xml`) mais suppose le personnage posé **sur** le lit (`IsoGameCharacter.setOnBed`, variable `onbed`, `J/characters/IsoGameCharacter.java:836, 3563-3567`), ce qu'un corps de zombie mené par des consignes ne fait pas. | fichiers cités | confirmé statiquement ; rendu à voir en jeu |
| Foyers à feu : un conteneur de type `fireplace`, `woodstove`, `brazier` ou `campfire` devient un `IsoFireplace` au chargement de la case ; `stove`, `toaster`, `coffeemaker` et `microwave` deviennent un `IsoStove` (type du conteneur : `ItemContainer.getType`). | `J/iso/CellLoader.java:115, 197-231` ; `IsoObject.getContainer` (`J/iso/IsoObject.java:1879`) ; classes exposées (`J/Lua/LuaManager.java:2072, 2085`) | confirmé statiquement |
| Mur, fenêtre ou porte bloqués, escalier entre deux cases : `IsoGridSquare.isBlockedTo`. | `J/iso/IsoGridSquare.java:935-941` ; base `pathfinding-and-obstacles.md` | confirmé statiquement |
| Clips d'action vanilla joués hors de l'état `actions` : `Bob_IdleLooting_Low` (`AnimSets/player/actions/LootLow.xml`), `Bob_IdleLooting_Mid` (`Loot.xml`, aussi `MedicalCheck.xml`), `Bob_IdleHammering` (`Build.xml`), `Bob_IdleSmoke` (`Smoke.xml`), `Bob_SitGround_WarmHands` (`sitonground-sitting-warmhands/sit_warmhands.xml`) ; chez le joueur ils dépendent de `PerformingAction` (ou `SitGroundAnim`) et de masques d'os, nos nœuds `lkactor_*` les jouent en entier dans l'état `idle` d'un corps de zombie. | fichiers cités ; `media/anims_X/Bob/*.x` ; `tools/gen_animsets.py --check` | confirmé statiquement ; rendu à voir en jeu |
| `GameTime.getWorldAgeHours` = nuits × 24 + heure − 7 (ou + 17 avant 7 h) ; les nuits ne s'incrémentent qu'au passage de 7 h. `setTimeOfDay` change donc l'âge du monde directement, en avant entre 7 h et 23 h seulement. | `J/GameTime.java:770-772, 830-834, 522-523` ; base `api-42-21.md` | confirmé statiquement |

## Choix

### Relevé du foyer (`Routines.survey`, `ensurePosts`)

Une fois par foyer, au premier passage d'un membre incarné, si la zone du foyer est chargée (coins à ±10 cases ; sinon nouvel essai au plus toutes les 10 s), au niveau du foyer, dans le bâtiment de la case du foyer :

- **postes de guet** : case intérieure praticable (`isFree(false)`, sans escalier) contre une porte ou une fenêtre qui donne hors du bâtiment ; direction = vers l'extérieur (0 est, 90 sud, 180 ouest, 270 nord, comme `setDirectionAngle`) ; portes d'abord, puis distance au foyer, puis position ; 6 postes au plus ;
- **couchages** : objets `IsoFlagType.bed`, meilleure qualité d'abord (`goodBed` 4, `averageBed` 3, `badBed` 2, `badChair` 1) ; une case de lit voisine d'un lit retenu est le même lit (lit double) ; place = case praticable voisine du lit (nord, est, sud, ouest), regard vers le lit ; 6 au plus ;
- **ronde** (laisse, I3.2) : coins et milieux des côtés du rectangle du bâtiment relevé, sens horaire depuis le nord-ouest, à 2 cases du mur (sinon 3, sinon 1), hors bâtiment, praticables et à 10 cases au plus du foyer (`HOME_RADIUS`) ; 3 à 8 points, sinon pas de ronde.

Foyer hors bâtiment (camp) : ni poste, ni ronde, ni couchage. Le relevé est sauvegardé avec le groupe (champ facultatif `posts` du registre, schéma 1 inchangé : `{ v, hx, hy, hz, day, camp, posts = { { x, y, z, a, k } }, round = { { x, y, z } }, beds = { { x, y, z, bx, by, a, q } } }`), contrôlé à la relecture (`validPosts`) et refait si sa forme est fausse ou si le foyer a changé (journal « home survey redone »). Journal : « group grp-N home x,y,z surveyed: … ».

### Relèves (I3.1, I3.3)

- **Quarts de 4 heures** à 22 h, 2 h, 6 h, 10 h, 14 h, 18 h (`Decisions.watchOf`). La rotation des postes du groupe (`Decisions.rotation`) = décalage propre au groupe + numéro du quart : le guetteur change à chaque quart, à tour de rôle parmi les membres aptes (veille de nuit assurée, horaires décalés). Une relève prévue par l'horloge seule (même objectif) va au journal du moteur (« group grp-N watch … »), pas au journal du groupe.
- **Poste de guet** du guetteur = poste n° (quart + rang du guetteur) : les postes tournent aussi, deux guetteurs ne tiennent pas le même poste.
- **Guet ou ronde** (`Routines.sentryKind`) : nuit (22 h-6 h, `Config.SIMULATION`) : guet aux postes intérieurs (maison tenue) ; aube (6 h-8 h) : ronde (la cour) ; jour : ronde la première heure du quart, guet ensuite. Sans ronde relevée : guet ; sans poste : regard vers l'extérieur du foyer (repli de LK05-T02).
- Dans la cascade de [decisions.md](decisions.md), le poste `sentry` donne `guard` ou `patrol` (nouveau comportement, mêmes rôles que `guard`, vigilance `guard`, durée 10 à 20 min) ; passer de l'un à l'autre interrompt l'état.

### Exécution (`Routines.apply`, à chaque passage du cadre de décision)

- `guard` : aller au poste (marche), puis `face` dans sa direction.
- `patrol` : aller de point en point de la ronde (deux guetteurs partent de points répartis sur la boucle) ; un point manqué deux fois est sauté ; un tour complet est compté (`stats.laps`).
- `sleep` : aller à la place de son couchage (rang du membre parmi les présents **hors guetteurs** = rang du lit : le lit du guetteur n'est pas perdu ; un guetteur qui dort quand même prend les lits restants), se tourner vers le lit, geste `sit` ; sans couchage : retour dans le bâtiment du foyer s'il est dehors (case libre près du foyer, `Materialize.placeFor`), `stop`, geste `sit`.
- **Assis plutôt que couché** : geste `sit` (nouveau nœud `lkactor_sit.xml`, clip `Bob_SitGround_Idle`, généré par `tools/gen_animsets.py`). L'animation couchée vanilla exige un personnage posé sur le lit (voir « Contraintes ») ; ce repos assis au sol, à côté du lit, est le repli documenté.
- Une consigne au plus par membre et par passage, émise au nom du cadre de décision (`Decisions.noteIssued` : jamais « externe »). Une autre consigne passée entre-temps (menace, retour au foyer) : la routine repart de son plan (point de ronde gardé). Plan changé (relève, réveil) : le membre se relève d'abord.
- **Menace** : la cascade la fait passer avant le poste ; tout comportement hors routine (y compris `watch`) relève le membre (`Routines.leave`) et oublie sa mémoire de routine. La menace partie, la routine reprend.
- Mémoire des membres (point de ronde, consignes suivies) non sauvegardée : recalculée.

### Vigilance transmise à l'exécutant (MP)

La vigilance décidée par l'autorité (`sleep` endormi, `rest`, `guard`) est posée pour la perception de l'autorité (`Senses.setVigilance`) **et** portée par la consigne courante : champ `vg` de l'entrée de consigne (`Directives.setVigil`, sans nouveau numéro de consigne, republiée aux détenteurs si elle change ; copiée dans toute nouvelle consigne). Un client MP lit `vg` de la consigne reçue dans `Senses.vigilanceOf` ; sans consigne : vigilance déduite comme avant. Les deux observateurs reçoivent la même consigne, donc la même vigilance.

### Autorité et coût

Fichier arrêté sur un client MP ; aucun module de routine chez un client. Coût : un relevé par foyer (au plus 21 × 21 cases, une fois), puis par membre évalué (4 par seconde au plus) une recherche de plan en table et au plus une consigne. Compteurs `Routines.stats` (`surveys`, `notLoaded`, `moves`, `faces`, `stops`, `sits`, `refused`, `laps`, `gaveUp`).

### Corvées (LK05-T04, I3.4)

Petites activités **visibles** au foyer, de jour, sans aucun effet sur le monde. Comportement `chore` de la cascade ([decisions.md](decisions.md)) : poste `keeper`, `carer`, `forager`, `builder` (règle `duty`) ou sans poste (règle `routine`), hors nuit, quand les routines sont chargées (`ctx.chores`) ; vigilance `rest` ; durée de l'état 20 à 40 min. Loin du foyer, comme `home` : retour d'abord, sans interrompre l'état. La nuit : `home` (poste) ou `rest` (routine) comme avant.

**Liste fermée** `Routines.CHORES` (ordre du tirage) :

| Corvée | Place (relevée au foyer) | Regard | Geste (clip vanilla) |
|---|---|---|---|
| `fire` entretenir le feu ou le poêle | case voisine d'un `IsoFireplace` (cheminée, poêle à bois, brasero) ou d'une cuisinière (conteneur `stove`) | vers l'objet | `kneel` (`Bob_IdleLooting_Low`) |
| `warm` se chauffer les mains | idem | vers le feu | `warmhands` (`Bob_SitGround_WarmHands`, assis) |
| `tidy` ranger un meuble | case voisine d'un objet à conteneur, hors cuisson, feu et lessive (`NOT_FURNITURE`) | vers le meuble | `rummage` (`Bob_IdleLooting_Mid`) ; aucun conteneur ouvert |
| `lookout` guetter à une fenêtre | poste de fenêtre du relevé, hors postes des guetteurs du quart | vers l'extérieur | debout (aucun geste) |
| `repair` bricoler | poste de porte ou de fenêtre du relevé | vers la porte ou la fenêtre | `hammer` (`Bob_IdleHammering`, sans outil ni bruit) |
| `smoke` fumer | poste de fenêtre libre, sinon sur place | vers l'extérieur | `smoke` (`Bob_IdleSmoke`, sans cigarette) |
| `care` soigner un blessé | case voisine du membre présent le plus blessé (santé < 75 %, corps au foyer) | vers le blessé | `kneel` |
| `rest` se reposer | sur place, ou dans le bâtiment s'il est dehors | — | `sit` (`Bob_SitGround_Idle`) |

**Places** (`Routines.surveySpots`, mémoire, une fois par foyer, zone chargée comme le relevé des postes) : dans le bâtiment du foyer, au niveau du foyer, à `HOME_RADIUS` cases ; objet de case lu par `choreObject` (lecture seule) ; place = première case voisine (nord, est, sud, ouest) praticable, du même bâtiment, sans lit, non prise, sans mur ni porte fermée entre elle et l'objet (`isBlockedTo`) ; regard vers l'objet. Cheminées d'abord, puis cuisinières, puis meubles, chacun par distance au foyer puis position ; 4 feux et 12 meubles au plus. Camp : aucune place (restent `rest`, `smoke`, `care`). Places non sauvegardées (recalculées au redémarrage) ; journal « group grp-N home … chore places: N fire(s), N furniture ».

**Choix** (`Routines.chorePlan`, autorité) : poids `CHORE_DUTY` par poste (sans poste à corvées : `routine`), plus `CHORE_ROLE` par comportement du rôle (`heal` → soins, `cook` → feu, `chores` → feu et rangement, `maintain`/`fortify` → bricolage, `guard`/`patrol`/`scout` → guet, `scavenge` → rangement) et `CHORE_TRAIT` par trait du membre (I3.4 : `tidy` → rangement +3, `nervous` → guet +3, `keenHearing` → guet +2, `strong` → bricolage +2, `smoker` → fumer +4, seul moyen de fumer, `drinker` → repos +2 et chaleur +1). Une corvée sans place au foyer a un poids nul ; aucun poids : `rest`. Tirage pondéré par `Decisions.stream("chore/<id>", créneau, 11)` : **graine d'identité + créneau de temps de jeu**. Créneau = `CHORE_MINUTES` (30) minutes de jeu, décalé de 0 à 29 minutes selon l'identité : la corvée change toutes les 30 minutes, pas pour tous à la même minute. Place choisie parmi les candidates par (créneau + rang du membre) : deux membres présents ne prennent pas la même au même créneau quand il y en a assez.

**Exécution** : comme une routine (une consigne au plus par passage, au nom du cadre) : marche jusqu'à la place, `face`, puis geste ; `rest` et `smoke` sans place : `stop` puis geste. Nouveau créneau ou nouvelle corvée : le membre se relève (`Routines.leave`, geste remis au repos) puis part. **Menace** : la cascade passe avant ; `Routines.leave` remet au repos tout geste de routine (`Routines.GESTURES` : `sit`, `kneel`, `warmhands`, `rummage`, `hammer`, `smoke`) et oublie la mémoire ; la menace partie, la corvée du créneau reprend. Compteurs `stats.chores`, `stats.gestures`, `stats.spotSurveys`, `state.byChore`.

**Aucune modification d'objet** : seuls `getObjects`, `getContainer`, `ItemContainer.getType`, `getSprite`/`getProperties` (lits), `isFree`, `HasStairs`, `isBlockedTo`, `getBuildingDef` sont lus ; aucun conteneur ouvert, aucun objet consommé, aucun feu touché. Les corvées qui modifient le foyer viendront avec LK05-T10.

**MP** : décision, places et choix sur l'autorité seule ; consignes et gestes relayés aux proches (LK03-T05) : deux observateurs reçoivent les mêmes. Mêmes entrées (monde, identité, minute) → mêmes corvées.

**Gestes** : nœuds `lkactor_kneel`, `lkactor_rummage`, `lkactor_hammer`, `lkactor_smoke`, `lkactor_warmhands` (état `idle`, condition `LKGesture`, priorité 5, vitesses vanilla) générés par `tools/gen_animsets.py` depuis `tools/anim_table.json` ; aucun événement (ni `OnFloor`, ni son). Voir [corps-et-animations.md](corps-et-animations.md).

### Repas réels (LK05-T07)

Comportement `meal` (faim ou soif, cascade), géré par `Routines.runMeal` : recherche dans le stock du foyer, case libre à côté du meuble (même règle que les corvées), regard, fouille (`rummage`), prise d'**un** objet par `Stock.takeMeal`, consommation assise (`sit`), effet appliqué une seule fois, puis pause de 60 minutes de jeu ; rien à prendre : pénurie au journal du groupe et besoin mis de côté (`Routines.unfed`, lu par la cascade). Détails et preuves : [besoins.md](besoins.md), section « Repas réels » ; stock : [stock.md](stock.md).

### Expéditions (LK05-T05)

Comportement `expedition` mené par `LK_Expeditions.lua` (pas par `Routines.apply`), avec les mêmes outils `Routines.exec` (marche, regard, geste `rummage`) : trajet jusqu'à un bâtiment proche, fouille de ses conteneurs, retour et dépôt au foyer. Détails : [expeditions.md](expeditions.md).

### Entretien du foyer (LK05-T10)

Un membre en corvée (`chore`) prend d'abord une tâche d'entretien ouverte du foyer (`LK_Upkeep.run` appelé par `Routines.apply` : plein et réparation du générateur, sang lavé, verre brisé ramassé), avec les outils partagés `Routines.exec` (déplacement, regard, geste) et une mémoire `kind = "upkeep"` libérée par `Routines.leave`/`forget`. Effet appliqué une fois, matériaux pris par `LK_Stock`. Lumières allumées à l'entrée d'une pièce le soir. Détails : [entretien.md](entretien.md).

## Alternatives écartées

- **Animation couchée sur le lit** : demanderait de poser le corps sur la case du lit (case non praticable) et la variable `onbed` propre aux joueurs ; non prouvé pour un corps de zombie, gardé pour un essai ultérieur.
- **Postes saisis à la main ou par fichier de carte** : le relevé automatique suffit à tout foyer ; une saisie par le joueur pourra venir avec LK14 (fortification).
- **Ronde par pathfinding libre autour du foyer** : le chemin d'un zombie n'est pas lisible en Lua ; des points fixes, vérifiés au relevé, gardent la laisse.
- **Réveil des dormeurs par alerte de groupe** : LK05-T08 (ici, seul le membre menacé se lève).
- **Corvées réelles** (ouvrir le conteneur, ajouter du combustible, poser un bandage) : hors de ce lot (effet purement visuel exigé) ; LK05-T07, LK05-T10.
- **Objet en main pendant le geste** (marteau, cigarette, livre) : demanderait de changer l'objet tenu par le corps et sa synchronisation ; gestes à mains nues, à revoir avec le rendu en jeu.
- **Corvée tirée par le hasard du jeu** (`ZombRand`) : non reproductible entre deux observateurs ni entre deux parties ; flux tiré de l'identité et du créneau.

## Tests

- Banc lupa `tests/test_lk_routines.py` (18 tests) : heures, quarts et choix guet/ronde ; rotation sur une journée (chaque guetteur apte a son quart, même guetteur tout le quart) ; répartition des postes, des rondes et des lits ; contrôle du relevé sauvegardé ; cascade (`patrol`, menace avant routine) ; relevé d'une maison doublée (porte puis fenêtres, lit double compté une fois, ronde de 8 points dans la laisse, case bloquée évitée, camp, zone non chargée) ; pile solo : relevé sauvegardé une fois et refait si malformé, guetteur au poste tourné vers l'extérieur, dormeurs au lit et assis, sans lit : rentrés et assis, menace qui relève et fait fuir ou regarder, reprise ; ronde parcourue dans l'ordre ; relèves aux heures prévues seulement ; pile MP (serveur + deux clients) : aucune routine chez un client, mêmes consignes, gestes et vigilances chez A et B, `vg` « sleep » la nuit ; même monde rejoué deux fois → mêmes observations ; suite `lk.routines` déroulée sur les doublures.
- En jeu : suite `lk.routines` (solo, tags `world`) ; MP à la séance finale.
- Corvées : banc lupa `tests/test_lk_chores.py` (12 tests) : liste fermée et gestes générés ; poids par poste, rôle et traits ; tirage reproductible qui suit les poids, nul hors des corvées possibles ; créneau de 30 min décalé par membre ; cascade (corvée de jour pour keeper, carer, forager, builder et la routine, `home`/`rest` la nuit, menace d'abord, comportement d'avant sans routines) ; relevé des places (cheminée puis cuisinière, micro-ondes écarté, meuble muré : place du côté ouvert, camp, zone non chargée) avec des conteneurs doublés sans autre méthode que `getType`/`getItems` et état des objets inchangé ; pile solo : corvée atteinte avec son geste, vigilance `rest`, menace qui l'interrompt (geste remis, mémoire oubliée), reprise, objets inchangés ; corvées qui changent par créneau et cessent la nuit ; soins à côté du blessé seulement s'il y en a un ; pile MP (serveur + deux clients) : mêmes consignes et gestes chez A et B, même monde rejoué → mêmes corvées ; suite `lk.chores` déroulée sur les doublures. `tests/test_lk_decisions.py` : l'ouvrier de garde au foyer fait désormais une corvée (repos assis sur le banc sans meuble).
- En jeu : suite `lk.chores` (solo, tags `world`) ; l'utilisateur vérifie le rendu des gestes.

## Points ouverts

- ⚠ Rendu du clip assis sur un corps de zombie, choix des postes et des rondes sur de vraies maisons (portes de garage, fenêtres de rez-de-chaussée hautes, cour encombrée) : à voir en jeu.
- ⚠ Foyer à étages : relevé au seul niveau du foyer.
- ⚠ Relevé figé tant que le foyer ne change pas (meubles déplacés, lit détruit : rien n'est revu) ; `Routines.resurvey(gid)` pour forcer.
- ⚠ Postes de guet occupés devant une porte : un guetteur peut gêner le passage d'un autre membre.
- ⚠ Corps sans client propriétaire en MP : consigne suspendue, routine figée (comportement de LK03-T04).
- ⚠ Corvées : rendu des clips d'action joués en entier sur un corps de zombie (jambes des clips de fumée et de marteau, mains vides, passage debout ↔ assis sans transition) à voir en jeu ; places relevées une fois (meuble déplacé : refaites seulement au redémarrage ou si le foyer change) ; une place peut être occupée par un autre membre (guetteur, blessé) ; soins sans effet sur la santé ; aucune corvée à l'étage.
