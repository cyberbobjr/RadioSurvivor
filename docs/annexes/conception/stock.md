# Stock réel du groupe dans les conteneurs du foyer

- Tâches : LK08-T06 (création), LK08-T07 (seuils, rationnement, besoins dérivés du stock, section « Seuils ») ; sert LK09-T06 (stock abstrait cohérent avec les conteneurs), LK11-T06 (dons tirés du stock), LK11-T08 (troc), LK05-T07 (repas pris dans le stock)
- Code : `Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/LivingKnox/LK_Stock.lua` (accroche hors écran dans `LK_Simulation.lua`) ; banc `tests/test_lk_stock.py` ; suites en jeu `lk.stock` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKStock.lua`) et `lk.offscreen_stock` (`RST_LKOffscreenStock.lua`, LK09-T06)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\` ; scripts vanilla `media/scripts/generated/items`) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement (LK08-T06, LK08-T07 et LK09-T06)

Base de connaissances : [world-placement.md](../../../../.claude/pz-knowledge/world-placement.md) (conteneurs, butin qui n'efface rien, détecter qu'un joueur a pris un objet), [combat-and-xp.md](../../../../.claude/pz-knowledge/combat-and-xp.md) (transferts MP en transactions Java sans Lua serveur), [api-42-21.md](../../../../.claude/pz-knowledge/api-42-21.md) (récipient rempli d'un fluide, `instanceItem`), [multiplayer.md](../../../../.claude/pz-knowledge/multiplayer.md). Idées de jeu : I5.1 (index par conteneur), I5.2 (stock surveillé, vol constaté) ; I3.7 (périssables au froid) non retenue ici (voir Limites). Aucune ligne de Bandits! ni de Project A-Life n'a été lue.

## Problème

Les réserves d'un groupe n'étaient qu'un niveau abstrait (besoins `food`/`medical`/`ammo` de LK08-T01, simulation LK09-T01). Un joueur qui entre dans un foyer doit y trouver de vrais objets, et le groupe doit savoir ce qu'il possède et s'apercevoir qu'on l'a pillé, sans que le serveur voie passer les transferts d'objets.

## Catégories

Tirées des données de script de l'objet, jamais de son nom affiché :

| Catégorie | Règle | Exemples vanilla |
|---|---|---|
| `water` | Récipient (`getFluidContainer()`) non vide dont le fluide principal est `Fluid.Water` ou `Fluid.TaintedWater` (testé en premier) | `Base.WaterBottle` remplie |
| `food` | `DisplayCategory = Food` | conserves, biscuits, sodas |
| `medical` | `DisplayCategory = FirstAid` ou `Bandage` | bandages, cachets, désinfectant, lingettes |
| `ammo` | `DisplayCategory = Ammo` | boîtes de cartouches |
| `materials` | `DisplayCategory = Material` ou `MaterialWeapon` (planches) | clous, corde, ruban adhésif, ferraille |

Tout autre objet est ignoré : il n'est ni compté ni surveillé.

## Conteneurs du foyer

Zone de `LK_Homes` : `RADIUS` (10) cases autour du foyer, au niveau du foyer.

- Bâtiment : tous les conteneurs des objets des cases du bâtiment du foyer (frigo et congélateur, placards, caisse posée par LK_Homes...).
- Camp : seulement les conteneurs des objets posés pour le groupe par LK_Homes (tentes, ModData `LKHome`).
- Seuls les objets au premier niveau d'un conteneur comptent : un sac rangé dans une caisse n'est pas ouvert.
- Clé d'un conteneur : `x,y,z,type,n` (n = rang parmi les conteneurs du même type sur la case).

## Inventaire de référence (privé)

Champ facultatif `stock` du groupe dans le registre privé des groupes (schéma 1 inchangé, contrôlé par `LK_Stock`, ignoré par `LK_Groups`) :

```
stock = { v = 1, hx, hy, hz, fill = "filling" | "done", day, ration = 0..3 (facultatif, LK08-T07),
          items = { { i = identifiant, t = type complet, c = catégorie, k = clé du conteneur }, ... } }
```

- Identité d'un objet : `InventoryItem.getID()`, tirée au hasard à la création (J/inventory/InventoryItemFactory.java:126) et sauvegardée avec l'objet (J/inventory/InventoryItem.java:1521, 1740). Un transfert MP déplace le même objet (J/core/Transaction.java:258-262 : `Remove` puis `addItem`).
- `MAX_ITEMS` = 128 entrées au plus : les objets déjà suivis passent d'abord, puis les nouveaux dans l'ordre des conteneurs.
- Lecture : `Stock.reference(gid)` (copie : objets, totaux, jour) et `Stock.totals(gid)` (totaux par catégorie, pour LK08-T07). Serveur seulement : la composition du stock ne part jamais vers un client.

## Remplissage initial (une seule fois par foyer)

| Règle | Raison |
|---|---|
| Après l'aménagement (marque LK_Homes valide) et seulement si toute la zone est lisible. | La caisse ou les tentes existent ; un conteneur d'une case non chargée paraîtrait vide. |
| Kit du type de groupe (`Stock.KITS`), objets vanilla, sans périssable ; type inconnu = kit `settlers`. | Quantités modestes : colons 18 objets, pillards 15 (plus de munitions), neutres 14. |
| Objets créés par `instanceItem`, bouteilles d'eau vidées puis remplies d'eau (`Empty`, `addFluid(Fluid.Water, capacité)`). | Une bouteille est créée avec un fluide tiré au hasard (`PickRandomFluid`). |
| Rangés tour à tour dans les conteneurs posés par LK_Homes (caisse ; tentes d'un camp), marqués explorés avant. | Un conteneur non exploré recevrait le butin vanilla en plus à sa première ouverture (`fillContainer` n'efface rien). |
| Chaque objet porte `ModData.LKStock = <groupe>` ; `sendAddItemToContainer` sur un serveur. | Garde contre un registre plus ancien que le monde ; les clients qui ont déjà le chunk reçoivent les objets. |
| Marque écrite **avant** la création (`fill = "filling"`) ; une marque `filling` relue vaut « fait ». | Un arrêt en plein remplissage ne fait jamais recréer (perte possible, jamais de doublon). |
| Registre sans marque mais objets `LKStock` du groupe présents : référence rétablie, rien créé. | Fichier des groupes restauré plus ancien que le monde. |
| Foyer sans conteneur posé (`Homes.skip` des suites) : rien n'est créé ; les conteneurs du bâtiment sont quand même suivis. | Les suites de test ne remplissent pas leurs sites d'essai. |

## Relecture et pillage

Moment : `LoadChunk` (au plus une fois par seconde) et chaque minute de jeu, pour chaque groupe dont le foyer est aménagé et la case chargée ; au plus une relecture par groupe toutes les 2 s. Rien si une case de la zone n'est pas lisible.

La référence devient le contenu réel ; la différence avec l'ancienne référence se lit ainsi :

| Constat | Traitement |
|---|---|
| Objet ajouté (joueur qui dépose, butin d'un conteneur ouvert plus tard) | Accepté dans le stock. |
| Objet déplacé d'un conteneur du foyer à un autre | Accepté. |
| Objet disparu, retrouvé par son identifiant dans l'inventaire d'un joueur connecté (sacs compris, `getItemWithIDRecursiv`) | Vol attribuable à ce joueur : fait `theft` rapporté à `LivingKnox.Hostility.record(gid, clé, "theft", { attributable = true })`, une fois par joueur et par relecture, et au plus une fois par heure de jeu par groupe et par joueur. Sans identité de carnet (`Hostility.keyOf`), le vol est journalisé sans être compté. |
| Objet disparu, introuvable (mangé sur place, posé au sol, donné) | Perte journalisée sans coupable. |

**Relecture étalée (LK13-T09)** : la relecture de la minute ne relit plus tous les groupes dans l'image de l'`EveryOneMinute` (4,6 ms lupa par minute au banc de charge, 5 groupes, jusqu'à 12 ms) : les groupes candidats (foyer aménagé, case chargée, triés) rejoignent une file sans doublon (`Stock.queueScan`), un groupe est relu par image (`OnTick`, `Stock.onFrame`) à partir de l'image qui suit la minute, puis une image écrit seule le registre (écriture retenue `Groups.hold("stock")`, fiche [groupes.md](groupes.md)). Même relecture (`Stock.check`) et même ordre : avec 5 groupes, la dernière relecture a lieu 500 ms après la minute sur un serveur dédié, bien sous le délai d'une minute de jeu (2,5 s réelles par défaut). La relecture `LoadChunk` reste immédiate (au plus une fois par seconde). `Stock.scan(reason)` (relecture de tous les groupes tout de suite) est gardé pour les suites, l'administration et `LoadChunk` ; `Stock.finishQueue()` vide la file tout de suite (bancs).
Depuis le relevé de fortification en trois images (LK13-T11, 2026-10-15, [fortification.md](fortification.md)
§ 10.4), un groupe dont le relevé de la minute est encore en file attend sa fin : la file du stock s'arrête (aucune
relecture dans cette image, écriture retenue d'autant) jusqu'à la dernière étape du relevé ; `Stock.finishQueue()`
fait d'abord les étapes restantes. Le stock est donc toujours relu après le relevé de son groupe, comme quand le relevé
tenait dans une image.

**Choix de la méthode** (consigne de la tâche : « diff à la relecture ou événement serveur fiable ») : aucun événement serveur fiable ne signale un transfert. En MP, `ISInventoryTransferAction` crée une transaction que le serveur exécute en Java, sans Lua côté serveur (base combat-and-xp.md) ; en solo, `transferItem` passe dans le Lua client. La différence à la relecture, avec l'objet retrouvé par son identifiant dans l'inventaire du joueur, est la seule preuve côté serveur, identique en solo et en MP.

## Seuils, rationnement et besoins du groupe (LK08-T07)

Calculés à partir de la référence (`Stock.count`) et du nombre de **membres vivants** n du registre (membres en expédition compris : ils mangent aussi). Rien n'est calculé sans référence valide ou sans membre vivant (`Stock.needs` rend nil ; `Stock.portion` rend 1).

| Grandeur | Règle (réglages `Stock.SUPPLY`, valeurs de départ à recalibrer en jeu) |
|---|---|
| Réserve visée | nourriture et eau : `DAILY` (1 portion par membre et par jour) × n × `TARGET_DAYS` (3) ; soins : 1 par membre ; munitions : 0,5 par membre ; matériaux : 1 par membre (`PER_MEMBER`) ; arrondi au-dessus |
| Niveau | 0..100 = objets / visée (arrondi, plafonné à 100) |
| Jours d'autonomie | nourriture et eau : objets / (`DAILY` × n), au dixième inférieur ; autonomie du groupe = la plus basse des deux |
| Rationnement | `normal` ; `reduced` (part 0,75) si l'autonomie passe sous 2 jours ; `strict` (0,5) sous 1 jour ; `out` (0) si la nourriture ou l'eau est à zéro (`RATION_DAYS`, `PORTIONS`). On durcit aussitôt ; on n'adoucit qu'avec 0,5 jour d'avance sur le seuil quitté (`RATION_MARGIN`), pour qu'un objet déplacé ne fasse pas osciller le journal. |
| Besoins | catégories sous leur visée : `empty` (0 objet), `critical` (niveau < 25), `low` ; ordre fixe : statut, niveau croissant, puis ordre de `CATEGORIES` (nourriture, eau, soins, munitions, matériaux). Même stock et même nombre de membres = même liste. |

**Unité « portion »** : un objet de nourriture ou une bouteille d'eau compte pour la journée d'un membre. C'est une abstraction (une conserve n'est pas un repas de toute une journée) en attendant les repas réels de LK05-T07, qui pourront compter des calories ou des litres sans changer l'interface.

**Rationnement** : niveau en vigueur dans le champ facultatif `stock.ration` (0..3) de la référence ; une valeur invalide vaut `normal` et ne fait jamais écarter la référence (sinon le kit serait recréé). Recalculé à la fin de chaque `Stock.check` (stock ou membres changés). Changement : entrée `ration` au journal du groupe et ligne `stock: group <gid> ration <niveau> (was <ancien>): <j> day(s) of food and water for <n> (food <a>, water <b>)` au journal du moteur. Le kit de départ des colons (4 membres : 8 vivres avec la cuisine, 3 bouteilles) donne 0,7 jour d'eau : le groupe démarre en rationnement strict et cherche à se ravitailler (choix de calibrage à confirmer).

**Lecture** :

| Fonction | Usage |
|---|---|
| `Stock.assess(totals, n)` | pur : `{ members, have, want, levels, days, autonomy, needs = { { c, have, want, missing, level, status } } }` |
| `Stock.rationLevel(a, courant)` | pur : niveau que la relecture appliquerait |
| `Stock.assessGroup(g)` | évaluation d'un groupe du registre, plus `ration`, `rationName`, `portion`, `next` |
| `Stock.needs(gid)` | idem par identifiant (copie, serveur seulement) |
| `Stock.portion(gid)` | part d'une ration normale |

**Branchements** :

- Cadre de décision (fait) : `LK_Decisions.groupInput` remplace les besoins abstraits du registre (`needs.food/medical/ammo`) par les niveaux du stock réel quand la référence existe, et ajoute `water` ; `scoreObjectives` prend la plus basse des réserves (eau comprise si elle est connue) pour l'objectif `supply` (raison écrite : `supply 53 (water 25)`). Sans référence (groupe jamais chargé, foyer absent) : comportement d'avant, eau ignorée.
- Expéditions (LK05-T05, fait : [expeditions.md](expeditions.md)) et missions RadioSurvivor : `Stock.needs(gid).needs`, premier élément = ce qui manque le plus ; les objets rapportés sont rangés au foyer et ajoutés à la référence dans la même écriture (ni ajout inexpliqué, ni perte).
- Fortification (LK14) : entrée `materials` de la même liste.
- Repas réels (LK05-T07), stock hors écran (LK09-T06), simulation (`FOOD_PER_MEMBER`) : `Stock.portion(gid)` ; aucun n'existe encore, le rationnement n'a donc pour l'instant d'effet que sur le journal.

## Repas réels (LK05-T07)

- `Stock.consumable(item, cat)` : nourriture ni pourrie, ni gelée, ni crue dangereuse non cuite ; eau propre (`Fluid.Water`).
- `Stock.findMeal(gid, cat)` : premier objet consommable dans l'ordre des clés de conteneur, avec la case du meuble (`Stock.containers` rend désormais `x`, `y`, `z`).
- `Stock.takeMeal(gid, cat, key, apply, who)` : relit le conteneur, retire **un** objet (`DoRemoveItem`, `sendRemoveItemFromContainer` sur un serveur), l'ôte de la référence dans la même écriture que `apply(g)`, relit le rationnement. Prélèvement du groupe : jamais compté comme perte ni comme vol. Aucun objet créé.
- `Stock.reportShortage(gid, cat, who)` : entrée `shortage` au journal du groupe, au plus une fois par `SHORTAGE_HOURS` (6) et par catégorie.
- Limite : les objets non consommables restent comptés dans les totaux (niveaux et rationnement surestimés).

## Matériaux d'entretien (LK05-T10)

- `Stock.findItem(gid, pred)`, `Stock.findFluid(gid, fluides, minimum)` : lecture des conteneurs du foyer, même ordre que le stock.
- `Stock.drawFluid(gid, fluides, voulu, minimum, qui, usage)` : verse au plus `voulu` litres d'**un** récipient (`adjustAmount(contenu - prise)`), quantité exacte rendue ; `sendItemStats` sur un serveur (objet resté dans son meuble).
- `Stock.takeItem(gid, pred, qui, usage, apply)` : retire **un** objet (pièce), ôté de la référence s'il y était suivi ; rend aussi l'objet retiré, et `apply(g)` facultatif s'exécute dans la même écriture du registre (LK11-T06 : don remis au joueur et marque de période, [aide.md](aide.md)).
- Essence, Javel, produit ménager et pièces électroniques ne sont dans aucune catégorie du stock : leur usage ne change pas la référence. Voir [entretien.md](entretien.md).

## Production de nourriture (LK05-T11)

- `Stock.findFluid` rend aussi `fluid` et `amount` (champs annoncés par son commentaire, lus au moment de l'appel).
- `Stock.untrack(gid, id)` : objet resté au foyer mais sorti des catégories suivies (bouteille vidée pour arroser) ôté de la référence ; la relecture suivante ne le compte pas perdu.
- Produits de la cueillette rangés au foyer et ajoutés à la référence par le dépôt des expéditions ; graines non suivies (hors catégories). Voir [nourriture.md](nourriture.md).

## Hors écran (LK09-T06)

Retenu le 2026-10-12 dans le cadre du contrat de la tâche (aucune décision `à décider` dans LK09). Code : `Stock.offscreenHour`, `Stock.offscreenLoot`, `Stock.applyPending` (`LK_Stock.lua`) ; accroche dans `Simulation.advance` (après chaque heure de chaque groupe) et `Simulation.simulateHour` (retour d'une expédition abstraite LK09-T02). Réglages `Stock.OFFSCREEN`. Le fichier `LK_Offscreen.lua` cité par la tâche n'existe pas : la simulation hors écran est `LK_Simulation.lua`.

**Pendant la simulation** (logique pure, dans l'écriture du pas de `LK_Simulation`, aucun accès au monde, aucun tirage : même registre octet pour octet que les heures passent une par une ou en rattrapage) :

| Règle | Détail |
|---|---|
| Repas abstrait | Une fois par jour simulé, à l'heure dont l'heure du jour de début vaut `MEAL_HOUR` = 18. Mangeurs = membres vivants au foyer, hors équipe d'une expédition (leurs vivres sont dans le rendement net du lieu, LK09-T02) et hors membres incarnés (repas réels, LK05-T07). Prise par catégorie (nourriture, eau) = `floor(mangeurs × DAILY × part + 0,5)`, la part étant celle de `Stock.portion` (LK08-T07 : 1, 0,75, 0,5, 0). Ce qui manque n'est pas pris (journal du moteur seulement). Rationnement relu aussitôt (jour de l'heure simulée au journal du groupe). |
| Objets pris | D'abord les ajouts en attente de la même catégorie (les plus récents, annulés sans jamais exister), puis les objets suivis dans l'ordre de la référence (ordre des clés de conteneur). L'objet ne peut pas être examiné hors écran (pourri, eau croupie) : il compte comme une portion. |
| Butin d'une expédition abstraite | Au retour (`Simulation.resolveExpedition`), `floor(gain / LEVEL_PER_ITEM)` objets par réserve gagnée (`LEVEL_PER_ITEM` = 5 points de réserve abstraite par objet ; nourriture, soins, munitions), types vanilla `OFFSCREEN.ITEMS` pris tour à tour d'après le numéro d'écart. Plafond : objets suivis + ajouts en attente ≤ `MAX_ITEMS`. |
| Expédition physique passée hors écran (LK05-T05) | Inchangée : son butin abstrait est déjà créé au dépôt quand le foyer redevient lisible ([expeditions.md](expeditions.md)). |

**Journal d'écarts en attente** : champ facultatif `stock.pend = { n = dernier numéro, ops = { { u, o = "take", i, t, c, k } | { u, o = "add", t, c } } }` de la référence (schéma 1 inchangé). Un objet pris quitte `items` (son identifiant reste dans l'écart) ; un objet ajouté n'a pas encore d'identifiant. Borné : prises ≤ objets suivis, ajouts ≤ `MAX_ITEMS` − objets suivis, `PEND_MAX` = 256 au plus. Les totaux (`Stock.count(items, pend)`, besoins, rationnement, cadre de décision) comptent les ajouts en attente : l'inventaire de référence est celui que le groupe aura. Journal invalide : ignoré (avertissement à la prochaine écriture hors écran), **jamais** une raison d'écarter la référence (le kit serait recréé).

**À l'arrivée d'un joueur** : `Stock.check` (`LoadChunk` au plus une fois par seconde, chaque minute de jeu) applique le journal dès que **toute** la zone du foyer est lisible, avant la différence et donc avant la recherche de vol ; toute prise du groupe dans les conteneurs (`findMeal`, `takeMeal`, `findItem`, `findFluid`, `drawFluid`, `takeItem`) l'applique aussi d'abord. Un joueur n'ouvre un conteneur du foyer qu'à côté de lui : la zone (rayon 10) est alors entièrement chargée et la relecture a eu lieu.

| Écart | Application |
|---|---|
| `take` | Objet cherché par son identifiant dans les conteneurs du foyer : retiré (`DoRemoveItem`, `sendRemoveItemFromContainer` sur un serveur) ; déjà absent (mangé par un repas réel, pris entre-temps) : rien, jamais cherché ailleurs. |
| `add` | Type `Base.*` seulement (sinon abandonné avec un avertissement) ; `instanceItem`, eau vidée puis remplie (`Empty`, `addFluid(Fluid.Water, capacité)`), marques `LKStock` = groupe et `LKStockOp` = `<groupe>:<numéro>`, rangé dans le conteneur posé par LK_Homes sinon le premier, `sendAddItemToContainer` sur un serveur. Aucun conteneur : l'écart reste en attente. Erreur inattendue : gardé, réessayé. |

Puis **une** écriture du registre : seuls les écarts traités sont ôtés (par numéro : un écart inscrit pendant l'application, par exemple par un pas de simulation, reste en attente), les objets créés entrent dans la référence ; les marques `LKStockOp` sont effacées après cette écriture. **Marque d'application idempotente** : si l'écriture n'a pas eu lieu (erreur, arrêt brutal entre la création et l'écriture), l'application suivante reprend l'objet qui porte déjà sa marque au lieu d'en créer un second, et un objet déjà retiré n'est pas compté deux fois : ni perte ni doublon. Journal du moteur : `stock: group <gid> offscreen changes applied into <clé>: <n> removed, <n> already gone, <n> created, <n> resumed, <n> dropped, <n> kept`.

**Fortification hors écran (LK14-T05)** : `Stock.offscreenCount(s, types)` et `Stock.offscreenTake(g, gid, types, n)` (tout ou rien, ajouts en attente des mêmes types annulés d'abord, puis écarts `take`) prennent planches, clous, rondins et liens par type complet dans la référence, dans l'écriture du pas de simulation ; appliqués à l'arrivée comme les autres écarts. Boîtes de clous entamées : suivies par `LK_Fortify` (la boîte reste dans la référence jusqu'à son ouverture réelle). Voir [fortification.md](fortification.md) §10.

**Multijoueur** : tout sur l'autorité ; le journal d'écarts reste dans le registre privé. Les clients qui ont déjà le chunk reçoivent retraits et créations par les paquets vanilla ; un client qui charge le chunk plus tard le reçoit tel que le serveur l'a modifié.

**Alternatives écartées.** Consommation horaire avec arrondi aléatoire : un tirage de plus par heure et un flux à réserver, pour la même moyenne ; un repas par jour est lisible et sans hasard. Entrées provisoires dans `items` pour les ajouts : la relecture les verrait perdus. Écriture du registre avant les changements du monde (comme le remplissage initial) : un arrêt ferait perdre les objets créés ; la marque sur l'objet permet de reprendre sans doublon. Lier les réserves abstraites de la simulation (`needs`) au stock réel : hors périmètre (voir les limites).

**Limites LK09-T06.**

- ⚠ À vérifier en jeu (`lk.offscreen_stock`, solo puis séance MP finale) : objets retirés et créés visibles dans la caisse, aucun autre changement du stock à l'arrivée, second client MP à jour.
- Plantage du serveur après l'écriture du registre mais avant la sauvegarde du monde : comme pour tout objet du jeu, le monde revient à sa dernière sauvegarde (objets retirés revenus, acceptés comme ajoutés ; objets créés absents, comptés perdus sans coupable). Un arrêt propre n'est pas concerné.
- L'eau n'est jamais rapportée hors écran (les expéditions abstraites LK09-T02 ne rapportent que nourriture, soins et munitions) : après quelques jours, l'eau tombe à zéro, la ration passe à `out` (part 0) et le repas abstrait ne prend plus rien. Décision à confirmer (eau abstraite au rendement des lieux, ou point d'eau du foyer).
- Les réserves abstraites de la simulation (`needs`, LK09-T01) et le stock réel restent deux comptes séparés : seuls le repas quotidien et le butin des expéditions abstraites passent au stock. Soins consommés hors écran, maladie, butin et pertes d'un combat (LK09-T05) : non reportés au stock.
- Les objets pris hors écran ne sont pas examinés (un objet pourri ou une eau croupie compte comme une portion).
- Valeurs à confirmer : `MEAL_HOUR` = 18, `LEVEL_PER_ITEM` = 5, types du butin abstrait.

## Multijoueur

Tout se fait sur l'autorité (`if isClient() then return end`). Les objets créés partent aux clients par `sendAddItemToContainer` ; un client qui charge le chunk plus tard les reçoit avec la sauvegarde de la case. L'inventaire de référence n'est jamais envoyé. La recherche du voleur lit les inventaires des joueurs côté serveur, tenus à jour par les transactions Java.

## Limites et restes

- ⚠ À vérifier en jeu : objets créés visibles dans la caisse (solo, puis second client MP), bouteilles pleines d'eau, aucun butin vanilla ajouté à la caisse à sa première ouverture, vol attribué après un transfert réel.
- Prélèvements du groupe lui-même (repas LK05-T07, dons LK11-T06, troc LK11-T08) : ils passent par `LK_Stock` pour mettre la référence à jour dans le même pas, sinon ils seraient vus comme des pertes (repas : `takeMeal` ; dons : `takeItem`, [aide.md](aide.md) ; troc : objets cédés ôtés de la référence avant les déplacements, puis relecture par `Stock.check`, conteneurs par `Stock.homeContainers`, [troc.md](troc.md)).
- Mise à jour des conteneurs réels d'après la référence pendant la simulation hors écran : faite par LK09-T06 (section « Hors écran »).
- LK08-T07 : la référence n'est relue que foyer chargé ; hors écran, rationnement et besoins ne suivent (depuis LK09-T06) que le repas abstrait quotidien et le butin des expéditions abstraites, tandis que la simulation continue d'user des besoins abstraits du registre. Un membre mort hors écran ne change les visées qu'à la relecture suivante. Le cadre de décision lit la référence même ancienne.
- Choix LK08-T07 à confirmer : portion abstraite (1 objet = 1 journée d'un membre), visée de 3 jours, seuils 2 jours / 1 jour, marge 0,5 jour, visées par membre des autres catégories (soins 1, munitions 0,5, matériaux 1), critique sous 25 %, groupe de départ en rationnement strict, eau ajoutée au calcul de `supply`.
- I3.7 (périssables au frigo) non faite : les kits ne contiennent aucun périssable ; à reprendre quand le groupe rapportera des vivres frais (LK09-T06).
- Un voleur qui pose aussitôt l'objet au sol ou le passe à un autre joueur entre deux relectures n'est pas identifié (perte sans coupable) ; un objet volé par un joueur puis rendu n'est pas compensé.
- Étages : seul le niveau du foyer est examiné.
- Choix à confirmer : contenu et quantités des kits, conteneurs du bâtiment comptés comme stock du groupe (piller la cuisine d'un foyer = vol), un seul fait `theft` par heure de jeu et par joueur.
