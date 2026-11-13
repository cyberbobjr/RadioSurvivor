# Besoins individuels des PNJ : faim, soif, fatigue, peur

- Tâches : LK05-T06 (création, 2026-10-11), LK05-T07 (repas réels pris dans le stock, 2026-10-12, section « Repas réels ») ; lus par LK05-T02 ([decisions.md](decisions.md)) ; suite : LK05-T08 (alerte), LK09 (vie hors écran, [simulation.md](simulation.md))
- Build : 42.21.0 — Date : 2026-10-12 — Statut : brouillon (repas réels : testé hors jeu seulement)

Code : `media/lua/server/LivingKnox/LK_Needs.lua` (`LivingKnox.Needs`, autorité seulement), accroché par `server/LivingKnox/LK_Server.lua` (`EveryHours` après la simulation, démarrage) et par `LK_Simulation.step` (pas des besoins après chaque heure simulée de chaque groupe). Lu par `LK_Decisions` (`Needs.get`, `Needs.perceive`, `Needs.fearSource`, `Needs.observe`).

## Problème

Chaque membre d'un groupe a quatre jauges de 0 à 100 (faim, soif, fatigue, peur) qui évoluent avec l'heure de jeu et ce qu'il fait, et qui créent des **envies** (manger, boire, dormir, fuir) lues par la cascade de priorités du membre. Décision de l'utilisateur du 2026-10-08 ([LK05](../plans/LK05-perception-decisions-routines.md), section « Décisions ») : jauges tenues par le serveur, **même modèle à l'écran et hors écran**. Les jauges doivent être reproductibles (mêmes entrées, mêmes valeurs), ne jamais être tenues par un client, coûter peu par heure de jeu et se rattraper après une absence par le même calcul.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `EveryHours` ne part qu'une fois par mise à jour de `GameTime`, même si plusieurs heures passent ; aucun sur un serveur vide en pause (`PauseEmpty`). Les pas se comptent donc d'après `math.floor(getWorldAgeHours())` et l'heure du dernier pas de chaque membre. | base `api-42-21.md` (« `EveryHours` : déclenchement, heures sautées ») ; `J/GameTime.java:553-554` | confirmé statiquement |
| Heure du jour = (âge + 7) % 24 ; le pas k couvre l'âge [k-1, k[, donc commence à l'heure du jour (k + 6) % 24, comme la simulation hors écran. | base `api-42-21.md` ; [simulation.md](simulation.md) | confirmé statiquement |
| Un client MP charge aussi `media/lua/server` : `if isClient() then return end` en tête, aucune jauge côté client. | base `mod-loading.md` | confirmé statiquement ; banc MP (`LivingKnox.Needs` absent chez les deux clients) |
| Aucune ModData globale pour un état privé : les jauges vont dans le registre privé des groupes (fichiers du serveur). | base `multiplayer.md` ; [groupes.md](groupes.md) | confirmé statiquement |
| Kahlua : aucun opérateur binaire ; `%` faux au-delà d'un quotient de 2^31. Le modèle n'emploie que des additions d'entiers bornés à 0..100, sans hasard. | base `kahlua-lua.md` | confirmé statiquement |

## Choix

### Jauges et persistance

`member.vitals = { hunger, thirst, fatigue, fear, hour }` : quatre entiers 0..100 et l'heure de jeu du dernier pas. Champ facultatif du registre des groupes (schéma 1 inchangé), **non contrôlé par `LK_Groups`** : `LK_Needs` le contrôle et le remet aux valeurs de départ (journal `WARN needs: member … had malformed gauges, reset`) s'il est malformé ; un groupe n'est jamais écarté pour lui. Valeurs de départ d'un membre sans jauges : faim 20, soif 20, fatigue 20, peur 0, à l'heure courante (aucun rattrapage).

### Pas horaire (`Needs.step`, pur)

Une heure avec une activité de la liste fermée `ACTIVITIES` :

| Activité | Faim | Soif | Fatigue | Peur sans menace pendant l'heure |
|---|---|---|---|---|
| `sleep` (dormir) | +2 | +3 | −12 | −18 |
| `rest` (repos au foyer) | +3 | +4 | −4 | −18 |
| `idle` (au foyer, trajet du retour) | +4 | +5 | +3 | −12 |
| `watch` (guet, regard) | +4 | +5 | +4 | −12 |
| `work` (corvée, fouille) | +5 | +7 | +5 | −12 |
| `patrol` (ronde) | +5 | +7 | +6 | −12 |
| `travel` (expédition) | +5 | +7 | +6 | −8 |
| `flee` (fuite) | +6 | +9 | +12 | −4 |

Une menace perçue pendant l'heure empêche la peur de retomber cette heure-là. Toutes les valeurs sont bornées à 0..100. Valeurs de départ propres au mod, à recalibrer en jeu ; ordre de grandeur : une journée ordinaire (16 h au foyer, 8 h de sommeil) ajoute environ 80 de faim et 100 de soif, la nuit efface la fatigue du jour ; une journée de ronde atteint l'envie de dormir en 13 h environ.

**Repas en attendant LK05-T07** : en début de pas, un membre **au point de repas** (vu au foyer pendant l'heure, ou hors écran au foyer, ou en expédition avec ses rations) dont la faim atteint 70 mange (−60) si la réserve de nourriture du groupe n'est pas vide ; sa soif atteinte à 70, il boit (−60, eau supposée disponible au foyer). C'est un **geste abstrait** : aucun objet n'est pris ni créé, aucune réserve ne change ici (la consommation du groupe est déjà comptée par la simulation, `FOOD_PER_MEMBER`). L'envie vit donc au plus une heure : le membre affamé rentre au foyer (règle `hunger` ou `thirst` de la cascade), puis mange au pas suivant. Réserve vide : la faim reste haute, le membre attend au foyer. LK05-T07 remplacera ce geste par un repas réel pris dans les conteneurs du stock.

### Activité d'une heure, à l'écran et hors écran

- **À l'écran** (membre incarné évalué par la cascade pendant l'heure) : chaque évaluation note le comportement choisi (`Needs.observe`) ; l'activité de l'heure est la plus souvent observée (`BEHAVIOUR_ACTIVITY` : `sleep`→`sleep`, `rest`→`rest`, `home`→`idle`, `chore`→`work`, `guard` et `watch`→`watch`, `patrol`→`patrol`, `flee`→`flee` ; égalité : ordre de `ACTIVITIES`), au point de repas s'il a été vu au foyer.
- **Hors écran** (ou membre incarné jamais évalué pendant l'heure : consigne d'un autre module) : horaire abstrait `Needs.scheduleActivity` : en expédition → `travel` ; fatigue ≥ 80 → `sleep` ; nuit (22 h-6 h, `Config.SIMULATION`) → `sleep`, ou `watch` pour le poste `sentry` ; de jour, tâche du groupe (`scavenge` → `work`, `rest`/`heal` → `rest`, sinon `idle`).
- Le **même pas** s'applique dans les deux cas : à activités égales, à l'écran et hors écran donnent les mêmes jauges (banc).

### Peur et menaces

Chaque menace distincte perçue par un membre incarné (liste `threatsOf` de la cascade, appel `Needs.perceive` avant la décision) fait monter la peur **aussitôt**, une fois par menace et par heure : zombie vu à 6 cases ou moins +20, vu plus loin +10, entendu +5 ; joueur hostile vu +25, entendu +10 ; joueur méfiant vu +8, entendu +4 ; ×1,5 pour le trait `nervous`, ×0,5 pour un combattant (rôle qui permet `fight` ou `defend`) ; au plus 16 menaces par membre et par heure. La menace la plus proche reste 10 minutes de jeu la **source de la peur** (`Needs.fearSource`). La montée est écrite dans le registre vivant et sauvegardée au pas suivant (changement en place sans écriture, déclaré au contrôle des vues par `Groups.touched`, LK13-T08, [groupes.md](groupes.md) « Lecture en place »). Hors écran, aucune menace n'est perçue : la peur retombe seulement (les combats abstraits de la simulation ne la touchent pas).

### Envies dans la cascade (`LK_Decisions`)

`Decisions.needsOf` lit `Needs.get(gid, mid)` (copie des quatre jauges ; valeurs de départ pour un membre sans jauges ; module absent : 0). Seuils `NEED_HIGH` : faim 70, soif 70, fatigue 80, peur 70.

| Envie | Comportement |
|---|---|
| dormir (fatigue ≥ 80) | `sleep` au foyer (routine de sommeil près d'un lit, [routines.md](routines.md)) ; loin : retour d'abord |
| manger, boire (faim, soif ≥ 70) | `home` : retour au point de repas (le foyer), repas abstrait au pas suivant |
| fuir (peur ≥ 70) | tout rôle depuis LK06-T07 (avant : non-combattant) : menace perçue jusqu'à 12 cases (`FLEE_DIST_AFRAID`, au lieu de 6) → fuite ; aucune menace perçue mais source de la peur à 12 cases ou moins → fuite à l'opposé ; sinon, comme tout combattant, `rest` à l'abri au foyer |

### Rattrapage et coût

- `LK_Simulation.step` avance les jauges des membres de chaque groupe **juste après chaque heure simulée** (`Simulation.advance(…, afterHour)`) : le pas voit la tâche et l'expédition de cette heure-là, que les heures passent une par une (`EveryHours`) ou en rattrapage après un arrêt. Au-delà du rattrapage de la simulation (72 h), les heures sont ignorées comme elle.
- Passage horaire propre (`Needs.pass`, `EveryHours` après la simulation et au démarrage) : avance les membres restés en retard (simulation désactivée, membre nouveau), au plus `CATCHUP_HOURS` = 24 heures par membre (les plus récentes, reste journalisé `WARN needs: N hour(s) missed, 24 applied`). Puis les observations et menaces des heures passées sont oubliées.
- Coût par heure de jeu : un pas (une dizaine d'additions) par membre vivant, au plus 64 groupes × 32 membres ; aucune lecture du monde. En jeu : `Needs.perceive` et `Needs.observe` à chaque évaluation de la cascade (au plus 4 par seconde réelle), bornés par les 16 menaces par heure. Sauvegarde : avec celle de la simulation ; une écriture de plus seulement quand un membre reçoit ses premières jauges.
- Mémoire seulement : activités observées, menaces de l'heure, source de la peur (perdues au redémarrage, sans effet sur les jauges sauvegardées).

### Repas réels pris dans le stock (LK05-T07)

Code : `LK_Routines.lua` (section « repas réels », `Routines.runMeal`), `LK_Stock.lua` (`Stock.consumable`, `findMeal`, `takeMeal`, `reportShortage`), `LK_Needs.lua` (`Needs.relieve`, `Needs.realMeals`), `LK_Decisions.lua` (comportement `meal`, `ctx.meals`, `ctx.unfed`).

| Fait du moteur | Preuve | Statut |
|---|---|---|
| Retirer un objet d'un meuble : `ItemContainer.DoRemoveItem` (une seule surcharge), puis `sendRemoveItemFromContainer` sur un serveur, envoyé aux clients proches du meuble | `J/inventory/ItemContainer.java:1944-2027`, `J/Lua/LuaManager.java:9734-9741`, `J/network/GameServer.java:2269-2277` ; base `multiplayer.md` | confirmé statiquement |
| Un aliment pourri, gelé ou cru dangereux garde la catégorie `Food` : tester `isRotten`, `isFrozen`, `isbDangerousUncooked` et `isCooked` | `J/inventory/types/Food.java:1653, 1671, 1974`, `InventoryItem.java:2413` ; base `api-42-21.md` | confirmé statiquement |

- **Cascade** : faim ou soif ≥ 70 → comportement `meal` au foyer (loin : retour d'abord), quand la routine des repas est chargée (`ctx.meals`) ; sinon `home` comme avant. Un besoin **mis de côté** (`Routines.unfed` : rien à prendre, ou repas récent) ne déclenche pas sa règle : la cascade passe à la suivante (soif, fatigue, poste), le membre ne reste pas planté au foyer.
- **Déroulé** (`Routines.runMeal`, autorité, à chaque passage) : `Stock.findMeal(gid, "food" | "water")` donne le premier objet consommable dans l'ordre des clés de conteneur du foyer (reproductible) ; le membre va à une case libre à côté du meuble (même règle que les corvées : voisine praticable, du bâtiment, sans lit, sans mur entre les deux), se tourne vers lui, **fouille** (geste `rummage`, 1 minute de jeu), puis `Stock.takeMeal` relit le conteneur, retire **un** objet consommable, l'envoie aux clients et l'ôte de la référence du stock dans la même écriture du registre (la relecture suivante n'y voit ni perte ni vol) ; il le consomme **assis** (geste `sit`, 5 minutes de jeu).
- **Effet** : `Needs.relieve` retire `MEAL` (60) à la faim ou `DRINK` (60) à la soif × part de ration (`Stock.portion` : 1, 0,75, 0,5 ; au moins 0,5 quand l'autre catégorie est épuisée, un objet ayant été trouvé), une seule fois : à la fin du repas, ou dès l'interruption (menace, corps retiré) si l'objet a déjà été pris. Puis aucun nouveau repas du même besoin pendant 60 minutes de jeu (`MEAL_GAP_MINUTES`).
- **Consommable** : nourriture ni pourrie, ni gelée, ni crue dangereuse non cuite ; eau = récipient non vide dont le fluide principal est `Fluid.Water` (eau croupie écartée). L'objet entier est consommé (une boîte, une bouteille) : un objet = une portion, comme le compte du stock (LK08-T07).
- **À défaut** (aucun objet consommable) : `Stock.reportShortage` écrit au journal du groupe une entrée `shortage` (« no food to eat left for m-2 (ration strict) »), au plus une fois par 6 h de jeu et par catégorie, relit le rationnement ; le besoin est mis de côté 60 minutes de jeu (`UNFED_MINUTES`), puis le membre réessaie. Les besoins du groupe (`Stock.needs`, objectif `supply` du cadre de décision) suivent la référence : l'expédition (LK05-T05) s'appuiera sur eux. Même mise de côté si le conteneur est hors d'atteinte ou s'il n'y a pas de case libre à côté.
- **Repas abstrait** : un membre vu pendant l'heure dont le groupe a un stock réel (`Needs.realMeals` : routine des repas chargée et référence valide) n'a plus de repas abstrait au pas horaire ; hors écran (membre non vu) ou sans référence de stock, le repas abstrait de LK05-T06 reste en vigueur (stock hors écran : LK09-T06).
- **Rien n'est créé** : aucun `instanceItem` dans ce chemin ; seul `DoRemoveItem` touche le monde.
- Mémoire des repas (phase, objet pris, mise de côté) non sauvegardée : un redémarrage pendant le repas perd l'effet d'un objet déjà pris (jamais deux effets).

### Provisions sur soi et gourde inépuisable (LK05-T20)

Décision de l'utilisateur du 2026-11-04 ([LK05](../plans/LK05-perception-decisions-routines.md), section « Décisions ») : chaque PNJ porte deux vrais aliments non périssables et une gourde d'eau qui ne se vide jamais ; il mange une provision loin du foyer, et décroche du combat pour manger quand la faim devient trop forte.

Code : `LK_Provisions.lua` (`LivingKnox.Provisions` : objets portés, don, remplacement, repas, boisson), `LK_ProvisionMeal.lua` (`LivingKnox.ProvisionMeal` : extension « provision » de la cascade). Points d'extension ajoutés pour cette tâche, sans cas nommé dans les moteurs : registre des extensions de la cascade `Decisions.registerExtension` ([decisions.md](decisions.md), « Extensions de la cascade ») et registre du contenu du butin `Loot.registerContent` ([sante.md](sante.md), « Butin réel du cadavre »). Banc `tests/test_lk_provisions.py` ; suite en jeu `lk.provisions` (`RST_LKProvisions.lua`, campagnes `solo-lk` et `mp` après `lk.meals`).

| Fait du moteur | Preuve | Statut |
|---|---|---|
| Un aliment sans `DaysTotallyRotten` ne pourrit jamais : `offAgeMax` reste à 1 000 000 000 | `J/inventory/InventoryItem.java:165, 2453` ; `J/scripting/objects/Item.java:111, 1563` | confirmé statiquement |
| `Base.GranolaBar`, `Base.BeefJerky`, `Base.DriedApricots` : `DisplayCategory = Food`, ni `DaysFresh` ni `DaysTotallyRotten` | `media/scripts/generated/items/food.txt:12842, 12691, 8721` | confirmé statiquement |
| `Base.CanteenMilitaryFull` : gourde de 0,9 l remplie d'eau à la création (pas d'`InitialPercent` : pleine) ; `Base.WaterBottle` tire au hasard eau ou eau gazeuse, donc écartée | `normal.txt:14015-14040, 13346-13374` ; `J/scripting/entity/components/fluids/FluidContainerScript.java:330-333` | confirmé statiquement |
| L'inventaire du corps passe tel quel au cadavre ; il n'existe que sur la copie de l'autorité (aucun envoi aux clients avant la mort) | voir [sante.md](sante.md), « Butin réel du cadavre » | confirmé statiquement |
| `ItemContainer.AddItem` retire l'objet de son ancien conteneur ; `DoRemoveItem` le retire sans autre effet | `J/inventory/ItemContainer.java:472-497, 2004-2028` | confirmé statiquement |

- **Provision** : aliment (`Food`) mangeable tel quel (`Stock.consumable`) dont `offAgeMax` atteint 1 000 000 000. Les poches du rôle en comptent déjà (chocolat du combattant, barre de céréales de l'éclaireur).
- **Don** (contenu `provisions` du butin, ordre 30, une seule fois par corps) : complète jusqu'à **2** (`Provisions.CFG.COUNT`) avec la liste `FOODS` = barre de céréales, viande séchée, abricots secs (choix reproductible tiré de l'identité du PNJ), plus la **gourde** `Base.CanteenMilitaryFull` s'il n'en porte pas. Journal : `loot built: …; 2 provision(s) and a canteen`.
- **Remplacement au foyer** (`Provisions.refill`, suite de la décision `observe`) : membre au foyer, sans menace ni cible, moins de 2 provisions, butin déjà construit : `Stock.takeItem` prend une provision dans les conteneurs du foyer (retirée du meuble et des clients, ôtée de la référence dans la même écriture), et la met dans l'inventaire du corps ; un objet du stock en moins par provision remplacée ; **rien n'est créé** quand le stock n'en a pas. Au plus un essai toutes les 10 minutes de jeu par membre (`REFILL_MINUTES`). Les conserves du stock (haricots, maïs, soupe) sont des provisions : le PNJ les mange comme le repas réel au foyer.
- **Loin du foyer** (ou sans foyer), hors combat : règles `provision.hunger` et `provision.thirst`, placées juste avant `hunger` et `thirst` (même rang) : faim ≥ 70 et au moins une provision → il s'arrête, s'assoit et mange (5 minutes de jeu), puis une provision en moins et faim − `MEAL` (60), une fois ; soif ≥ 70 et gourde → il s'arrête, s'assoit, boit (2 minutes de jeu), soif − `DRINK` (60), **gourde intacte**. Sans provision : retour au foyer comme avant. Au foyer : repas réel dans le stock (LK05-T07), inchangé. Pendant une expédition ou une traque, la provision est mangée sur place (les règles `hunger` et `thirst` attendent le retour, pas celles-ci).
- **En combat** (cible d'attaque, ou menace hostile perçue) : règle `provision.fight`, avant `threat` (même rang) : faim ≥ **90**, au moins une provision, **aucun ennemi à 3 cases ou moins** (cible et menaces hostiles), ni reddition, ni retraite, ni constantes mauvaises → il **décroche** : course vers une case à **8 cases** de lui à l'opposé des ennemis (`Decisions.fleeAngle`, puis ±45°, ±90°), de préférence **hors de la vue** de l'ennemi le plus proche (`Senses.lineOfSight` bloquée) ; arrivé (ou trajet clos), il s'arrête, mange assis, puis la faim retombe sous 90 et la règle `threat` le **rend au combat**. Ennemi au contact : la menace d'abord ; un ennemi qui arrive au contact pendant le repas l'interrompt (rien n'est mangé ni perdu).
- **Repas atomique** : l'objet n'est retiré et la jauge baissée qu'à la fin ; interrompu avant, rien n'est consommé (contrairement au repas du stock, déjà pris au meuble). Geste assis remis au repos à la sortie du comportement.
- **Mort** : le cadavre garde les provisions restantes et la gourde (inventaire du corps).
- État `provision` : vigilance `guard`, durée 20 minutes de jeu (décrochage et repas y tiennent) ; activité de l'heure `idle`. Mémoire non sauvegardée.

## Alternatives écartées

- **Jauges calculées par le client propriétaire** (il voit son PNJ) : refusé, autorité serveur ; le client ne fait que rapporter la perception.
- **Deux modèles (à l'écran détaillé, hors écran simplifié)** : contraire à la décision du 2026-10-08 ; un seul pas, seule l'activité change de source.
- **Pas par image ou par minute** : coût proportionnel au temps réel et rattrapage impossible à rendre identique ; le pas horaire entier se rattrape exactement. Seule la peur réagit aussitôt (une fois par menace et par heure), car une envie de fuir qui attendrait l'heure suivante serait inutile.
- **Rattrapage indépendant de la simulation** (après coup, avec la tâche courante du groupe) : un rattrapage de plusieurs heures ne voyait ni les tâches successives ni une expédition déjà rentrée, d'où des jauges différentes des pas horaires ; le pas des besoins suit donc chaque heure simulée.
- **Faim et soif qui montent sans jamais redescendre avant LK05-T07** : tout membre finirait bloqué au foyer par ses envies, routines et postes inutilisables ; un repas abstrait au point de repas, sans objet ni réserve touchés, garde la cascade vivante en attendant les repas réels.
- **Repas réel appliqué à la prise** (LK05-T07) : la faim retombait aussitôt sous le seuil et la cascade interrompait le geste de consommation ; l'effet est donc appliqué à la fin du repas, ou à l'interruption si l'objet est déjà pris (une seule fois dans tous les cas).
- **Attendre au foyer quand le stock est vide** (comportement de LK05-T06 pour une réserve vide) : membres affamés immobiles, postes abandonnés ; le besoin est mis de côté une heure de jeu et remonte au groupe.
- **Boire une partie d'une bouteille** (fluide retiré, bouteille rendue) : synchronisation du fluide d'un objet resté dans un meuble à prouver ; un objet entier = une portion, comme le compte du stock.
- **Décroissance exponentielle ou hasard** : additions d'entiers seulement, plus simples à vérifier dans Kahlua et à reproduire.
- **Provisions abstraites** (compteur dans le registre au lieu d'objets) : contraire à la décision du 2026-11-04 (vrais objets, pillables sur le cadavre).
- **Bouteille d'eau `Base.WaterBottle`** pour la gourde : son script tire au hasard eau ou eau gazeuse ; la gourde militaire pleine est toujours de l'eau.
- **Provision prise à la place d'une boisson** ou **gourde vidée puis remplie au foyer** : la gourde inépuisable est le choix assumé de l'utilisateur.
- **Décrocher à la seule faim de 70** : un combattant quitterait la mêlée pour une envie ordinaire ; 90 seulement, comme décidé.
- **Nouveau cas `if` dans la cascade et dans `Decisions.apply`** : interdit par la règle SOLID du projet ; un registre d'extensions (règles placées avant une règle, comportement, entrée, suite) le remplace.
- **Remplacement des provisions par une tâche d'entretien** (`Upkeep.registerJob`) : la tâche n'est prise que par un membre en corvée, de jour ; un guetteur ou un combattant ne remplacerait jamais ses provisions. Le remplacement se fait au passage au foyer, sans geste.

## Idées reprises

- Aucune chez Bandits! ni A-Life (faim et soif seulement animées, voir [idees-bandits-alife.md](../recherches/idees-bandits-alife.md)) : modèle propre.

## Tests

- Banc lupa (`tests/test_lk_needs.py`, 15 tests) : pas horaire reproductible et selon l'activité (sommeil, ronde, fuite), bornes, peur sans menace ; repas et boisson au point de repas seulement, réserve vide ; horaire hors écran (jour, nuit, guet, envie de dormir, expédition) ; montée de peur par genre, trait et rôle ; même résultat à l'écran (observations de la cascade) et hors écran sur 24 h ; activité observée prioritaire ; envies transmises à la cascade (fatigue → `sleep`, faim et soif → `home`, peur → fuite d'un non-combattant d'une menace à 9 cases ou de la source de sa peur, abri pour un combattant) ; jauges du registre lues par `Decisions.needsOf` ; 30 pas horaires = un rattrapage de 30 h après un arrêt ; jauges relues après redémarrage, malformées remises à neuf ; rattrapage borné à 24 h par membre puis un pas par membre et par heure ; trois jours hors écran sans soif ni fatigue extrêmes ; pile MP : aucune jauge ni registre chez les clients, peur montée une fois par menace et par heure, ouvrier qui fuit quand il a peur, combattant qui regarde.
- `tests/test_lk_simulation.py` : rattrapage borné comparé avec le même crochet des besoins (`advance(…, nil, Needs.advanceGroup)`).
- VM Kahlua : sans objet (additions d'entiers, aucune fonction de bibliothèque particulière).
- En jeu : aucun pour LK05-T06 (cible « hors jeu »).
- Repas réels (LK05-T07) : banc lupa `tests/test_lk_meals.py` (14 tests) : cascade (faim et soif → `meal` au foyer, `home` loin ou sans routine, besoin mis de côté → règle suivante, menace d'abord) ; gestes `rummage` et `sit` présents dans `tools/anim_table.json` ; fenêtre de mise de côté ; `findMeal` qui écarte pourri, cru, gelé, eau croupie et bouteille vide ; `takeMeal` : un objet retiré, référence sans lui, relecture sans perte ni vol, « gone » puis « none », conteneur disparu ; pénurie au journal une fois par fenêtre et par catégorie ; pile solo : membre affamé à la caisse, tourné vers elle, objet pris une fois, assis, faim baissée une fois de 60 × part de ration, puis retour au poste ; boisson d'eau propre ; stock vide : pénurie, besoin mis de côté, rien de retiré ; menace après la prise : effet appliqué une fois ; plus de repas abstrait pour un membre vu avec un stock réel (repas abstrait gardé sans référence) ; pile MP : prise par le serveur, une seule suppression envoyée, mêmes consignes et gestes chez A et B, ni routine ni stock chez les clients ; suite `lk.meals` déroulée sur les doublures.
- En jeu : suite `lk.meals` (solo, tags `world`), puis séance MP finale.
- Provisions (LK05-T20) : banc lupa `tests/test_lk_provisions.py` (18 tests) : cascade pure (loin du foyer : provision ou gourde, rien sur soi : retour, au foyer : repas du stock ; combat : décrochage à faim ≥ 90 au-delà de 3 cases, combat au contact, sous 90 ou sans provision, retraite aux constantes mauvaises ; rangs gardés, registre qui refuse une extension mal formée ou un comportement de la liste fermée) ; don reproductible ; pile solo : chaque corps porte 2 provisions et une gourde pleine, jamais deux fois ; affamé loin du foyer : une provision en moins, faim − 60 une fois, assis puis debout, stock intact ; soif loin du foyer : soif − 60, gourde à 0,9 l, deux fois ; rien sur soi : retour au foyer ; remplacement au foyer : l'objet du stock (pas un neuf), retiré du meuble et de la référence, relecture sans perte ni vol ; aliment périssable écarté, stock vide : rien de créé, essais bornés ; combat : décrochage en courant à l'opposé, case derrière un mur choisie, repas assis, faim − 60, retour au combat ; ennemi au contact : combat, rien mangé ; contact pendant le repas : interrompu, rien consommé ; pile MP (serveur + deux clients) : effet décidé par le serveur, mêmes consignes et gestes chez A et B, aucun module chez les clients ; butin (`LootBase`) : provisions et gourde par le registre du contenu, poches gardées, cadavre avec la provision restante et la gourde ; suite `lk.provisions` déroulée sur les doublures.
- En jeu : suite `lk.provisions` (solo et MP, campagnes `solo-lk` et `mp`) ; le décrochage en combat n'est prouvé qu'au banc (la suite retire les zombies).

## Points ouverts

- ⚠ Toutes les valeurs (taux, seuils, montées de peur) sont des points de départ à recalibrer en jeu.
- ⚠ Repas réels (LK05-T07) pour les membres vus seulement ; hors écran, repas abstrait jusqu'à LK09-T06 (eau supposée disponible au foyer).
- ⚠ Part de ration : un repas sous rationnement soulage moins, donc le membre a faim plus tôt et prend plus d'objets par jour, à l'inverse du but du rationnement (décision à confirmer : quota d'objets par jour, ou seuil plus haut).
- ⚠ Aucun clip de repas n'est généré : fouille puis assis. Clip vanilla à relever et à générer avec `tools/gen_animsets.py` (tâche à part).
- ⚠ Les objets non consommables (pourris, crus, gelés, eau croupie) restent comptés dans le stock : réserves et rationnement surestimés.
- ⚠ Hors écran, la peur ne monte jamais (combats abstraits, morts du groupe) ; à relier aux événements de la simulation si besoin.
- ⚠ Les jauges ne changent pas encore la santé, le moral du groupe ni la vigilance ; l'alerte de groupe (LK05-T08) pourra s'appuyer sur la peur.
- ⚠ Envies hors écran limitées à la fatigue (sommeil) et aux repas ; un groupe hors écran ne fuit pas.
- ⚠ Provisions (LK05-T20), à voir en jeu : gourde `Base.CanteenMilitaryFull` créée pleine d'eau, inventaire du corps relu après une sauvegarde (`reanimated.bin`), cadavre pillable avec ses provisions en MP, décrochage réel (course de 8 cases, case cachée trouvée dans une vraie maison). Hors écran, les provisions ne sont ni mangées ni remplacées (repas abstrait inchangé).
- ⚠ Provisions : un membre qui ne repasse jamais au foyer au calme (guetteur dehors en permanence, menace perçue au foyer) ne les remplace pas ; le remplacement n'a pas de geste visible.
