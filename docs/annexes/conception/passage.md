# Passage entre PNJ : priorités, arbitrage, places d'arrêt

- Tâches : LK18-T01 (registre des priorités, arbitrage), LK18-T02 (signalement du blocage, action « s'écarter »), LK18-T03 (places d'arrêt)
- ADR : [Les PNJ se cèdent le passage](../../architecture/decisions/adr-ceder-le-passage.md) (D01 à D06)
- Code : `Contents/mods/batman_LivingKnox/42.21/media/lua/shared/LivingKnox/LK_Passage.lua` (registre), `.../shared/LivingKnox/LK_PassageArbiter.lua` (arbitrage pur), `.../server/LivingKnox/LK_StopPlace.lua` (règle des places d'arrêt), `.../client/LivingKnox/LK_PassageSignal.lua` (signalement par l'exécutant), `.../server/LivingKnox/LK_PassageAuthority.lua` (contrôles, arbitrage, ordre), `.../server/LivingKnox/Decisions/LK_Decide_StepAside.lua` (action « s'écarter ») ; bancs `tests/test_lk_passage.py`, `tests/test_lk_stop_place.py`, `tests/test_lk_step_aside.py` ; suite en jeu `lk.passage`
- Build : 42.22 (Java décompilé **J/** = `E:\pz-source-42.22\java\zombie\`) — Date : 2026-11-15 — Statut : testé hors jeu seulement (LK18-T02 : suite `lk.passage` à passer en solo et en MP)

## Problème

Le corps d'un PNJ est un zombie : deux corps ne se traversent pas. Un PNJ arrêté dans une porte ou un couloir bloque les
autres, et un PNJ bloqué par un autre ne sait pas qu'il peut lui demander le passage.

## Contraintes du moteur

- Une porte (IsoDoor, ou IsoThumpable porte : portail) est un élément de bord ; `IsoGridSquare.getDoorTo(voisine)` la
  rend vue des deux cases du bord (J/iso/IsoGridSquare.java:3077-3112) : confirmé statiquement.
- `isBlockedTo` = mur, fenêtre ou porte fermée, ou escalier entre deux cases (J/iso/IsoGridSquare.java:936-938) ;
  `LivingKnox.Movement.edgeBlocked` y ajoute porte, fenêtre, cadre et clôture du bord : confirmé statiquement.
- `isFree(false)` est faux pour une case impraticable (meuble plein, mur, arbre), sans compter les personnages
  (J/iso/IsoGridSquare.java:2890) : confirmé statiquement.

## Choix

### Priorités de passage (registre, LK18-T01)

`LivingKnox.Passage.priority(kind, n)` inscrit la priorité d'un comportement ; `Passage.priorityOf(kind)` la lit
(`Passage.DEFAULT` = 0 pour un comportement non déclaré ; une déclaration plus basse est refusée). Le registre repose
sur `LivingKnox.Registry` (clé `kind`, ordre d'inscription). Le module ne nomme aucun comportement : chacun déclare la
sienne dans son propre fichier, à côté de son extension de décision.

| Rang | Comportements | Priorité | Fichier qui déclare |
|---|---|---|---|
| 1 | `fight` ; `flee`, `retreat` | 100 | `LK_Combat.lua` ; `Decisions/LK_Decide_Defence.lua` |
| 2 | `care` | 80 | `LK_Care.lua` |
| 3 | `defend` ; `surrender`, `watch`, `alert` ; `warn` ; `revenge` | 70 | `LK_Defense.lua` ; `Decisions/LK_Decide_Defence.lua` ; `LK_Encounters.lua` ; `LK_Relations.lua` |
| 4 | `expedition` | 60 | `LK_Expeditions.lua` |
| 5 | `chore` ; `meal` ; `provision` | 50 | `Routines/LK_Routine_Chores.lua` ; `Routines/LK_Routine_Meal.lua` ; `LK_ProvisionMeal.lua` |
| 6 | `guard`, `patrol` | 30 | `Decisions/LK_Decide_Post.lua` |
| 7 | `rest`, `home`, `sleep` et tout comportement non déclaré | 0 (défaut) | — |

`care` n'est pas un comportement de la cascade (`Decisions.BEHAVIOURS`) : le soin prend un membre calme. Le genre de
passage d'un membre (son comportement, ou `care` quand le soin le mène) est résolu par l'appelant de l'arbitrage
(LK18-T02).

### Arbitrage (fonction pure, LK18-T01)

`LivingKnox.PassageArbiter.decide(mover, blocker, free, path, priorityOf)` ; `Passage.arbitrate(mover, blocker, free,
path)` l'appelle avec `Passage.priorityOf`. Données simples, aucune lecture du monde :

- `mover`, `blocker` : `{ id, kind, x, y, z }` ; `blocker.canMove == false` (mort, en combat, soigné ou soignant) : rien.
- D07 (mise à jour de l'ADR du 2026-11-15, soir) : un bloqueur immobile (`blocker.moving` pas vrai) cède toujours au
  demandeur, quelle que soit sa priorité ; la priorité ne départage que deux PNJ en marche.
- Entre deux PNJ en marche, le demandeur passe si sa priorité est plus haute, ou égale et son numéro de PNJ plus petit (`Identity.idNumber`) ;
  sinon rien (le demandeur garde le traitement actuel du blocage, « stuck »).
- `{ action = "stepAside", to }` : case libre voisine du bloqueur (distance 1), ni la sienne ni celle du demandeur, hors
  des cases `path` du demandeur ; la plus proche, puis la plus loin du demandeur, puis y et x.
- Sans case de côté : `{ action = "backOff", to }` : case libre derrière le bloqueur (côté opposé au demandeur), hors
  du trajet, la plus proche.
- D08 : ni côté ni recul : `{ action = "stepAside", to }` vers la case libre utilisable la plus proche du relevé.
- `free` : cases libres où le bloqueur peut se tenir et qu'il peut joindre, relevées par l'autorité (LK18-T02).

### Signalement du blocage (exécutant, LK18-T02)

`LivingKnox.PassageSignal` (client propriétaire du corps, solo), appelé par `LK_Executor` avant le traitement du blocage
de `LK_Movement` (nouvelle requête, point de déblocage, échec « stuck ») :

- PNJ devant : autre corps de PNJ connu ici (`Executor.loadedBodies`), même niveau, à `RANGE` (1,5) case au plus, du
  côté de l'étape visée (cosinus de l'écart positif) ; le plus proche.
- Signal remis à l'autorité une fois par étape du trajet : `{ id, v, l, b, x, y, z, bx, by, bz, tx, ty }` (solo :
  appel direct de `PassageAuthority.onSignal` ; client MP : commande `Passage.CMD_BLOCKED`, `"passageBlocked"`).
- Recherche dès `STILL_MS` (1,5 s) sans progrès, sans attendre `Movement.STUCK_MS` (6 s) : campagne MP du
  2026-11-15, deux corps qui se poussent dans une porte se dégageaient seuls avant 6 s, ou restaient plantés sans signal.
- Attente bornée `WAIT_MS` (6 s) sans essai compté ; chemin relancé dès que le PNJ a quitté le couloir devant
  (cosinus de l'écart sous `LANE_COS`, 0,75) ; l'attente passée, traitement habituel du blocage. En solo, un refus
  rend aussitôt le traitement habituel ; un client MP n'a pas de réponse et attend `WAIT_MS` au plus.

### Contrôles et ordre (autorité, LK18-T02)

`LivingKnox.PassageAuthority.onSignal(player, args)`, seule à arbitrer et à ordonner (D06) :

| Contrôle | Refus |
|---|---|
| Demandeur et bloqueur incarnés (`Bodies.find`) | « mover has no body », « blocker ... has no body » |
| Expéditeur propriétaire du corps du demandeur (`Directives.isOwner`) | « not the owner of ... » |
| Consigne `move` ouverte du demandeur, du numéro signalé | « no open move » |
| Corps voisins vus par l'autorité : même niveau, `NEIGHBOUR` (2) cases au plus (Tchebychev) | « not neighbours » |
| Un signal par demandeur et par `SIGNAL_MS` (1 s) | « too soon » |

- Genre de passage (`kindOf`) : « care » quand le soin le mène (`Care.get`), sinon son comportement au cadre
  (`Decisions.get(id).b`), sinon aucun (priorité par défaut).
- Bloqueur en marche (`movingOf` : consigne `move` ouverte) ou immobile (D07).
- Bloqueur capable de bouger (`canMove`, D07) : vivant, hors combat (comportement de `Decisions.COMBAT_BEHAVIOURS`,
  engagement `Combat.get`), ni soigné (`Care.caredFor`) ni soignant (`Care.get`, `Care.taskOf`), pas déjà à l'écart.
  Le seuil de blessure ne compte plus (la liste de D07 ne le cite pas).
- Cases libres (`freeAround`, D08) : joignables à pied en `FREE_RADIUS` (3) pas au plus (parcours en largeur par les
  côtés : case praticable, sans personnage debout `Bodies.standingOn`, bord libre au sens de `Movement.edgeBlocked`),
  sans plante ni feu (`Bodies.hazardOn`, on y passe sans s'y arrêter) ; cases de passage comprises (l'écart dure
  quelques secondes). La ligne droite (`Movement.clearLine`) refusait une case joignable par un coin.
- Trajet du demandeur (`pathAhead`) : case du bloqueur, case juste au-delà, puis 4 cases de la ligne vers l'étape.
- Décision `stepAside` ou `backOff` : ordre `StepAside.order` ; la marche vise la case libre juste au-delà de la case
  décidée, dans le même sens (`walkTarget`), car un corps « arrive » à `Directives.ARRIVE` (1 case) du centre visé :
  sans ce dépassement il resterait au bord du couloir (banc : arrivé à 0,5 case de sa place, encore sur le chemin).
  Consigne du demandeur excusée (`Movement.excuse`) : un échec « stuck » de cette consigne n'est pas noté (ni case
  évitée, ni échéance avancée par `Movement.takeStuck`).
- Décision nil : rien ; le demandeur garde le traitement habituel du blocage (D03).

### Action « s'écarter » (LK18-T02)

`LivingKnox.StepAside` (`server/LivingKnox/Decisions/LK_Decide_StepAside.lua`) :

- `order(id, decision, moverId)` : marche aussitôt vers la case décidée ; fin quand le demandeur est passé (au-delà
  de la case quittée, côté opposé à son départ, à `PASSED` (1,5) case au moins ; consigne du demandeur close ; corps
  parti) ou après `HOLD_MS` (8 s) ; vérifiée par `StepAside.tick` (OnTick de l'autorité) toutes les `CHECK_MS`.
- Membre mené par le cadre de décision : extension `stepAside` (`Decisions.registerExtension`, règle placée devant
  `threat`, comportement `stepAside`, vigilance de garde) tant que l'ordre dure ; la consigne de l'écart est notée comme
  celle du cadre (`Decisions.noteIssued`). Ordre fini : la règle se tait, la cascade rend au membre son comportement
  (état neuf : la routine le ramène à son poste). Extension menante (sans `overlay`) : le soin et la routine ne
  reprennent pas la main pendant l'écart.
- PNJ hors du cadre (consigne ouverte d'un autre module, suite de test, API ; PNJ sans groupe) : sa marche
  interrompue est relancée vers la même case à la fin, sinon retour à la case quittée.

La règle est placée devant `threat` : l'arbitrage a déjà écarté un bloqueur en combat ou prioritaire ; une menace
apparue pendant l'écart attend au plus `HOLD_MS`.

### Campagne MP du 2026-11-15 : les trois refus

Tous au poste de guet 10656,10136 du foyer de test (10656,10137, maison du joueur de la campagne) : poste relevé par
`Routines.survey` pour la fenêtre 10654,10136 W, décalé de 2 cases par `StopPlace.nearest` (rayon `SHIFT_RADIUS`) ; la
case respecte la règle (ni bord de porte, ni passage d'une case) mais se trouve sur le chemin d'une corvée vers la case
de la fenêtre (10654,10136). Ce n'est pas une place hors de `StopPlace` : déduit des journaux (« group grp-10 home
10656,10137,0 surveyed: 6 post(s) », « move #26 to 10656,10136 » du guetteur puis « face #29 to 180 degrees »), non
vérifié sur la carte. Réponse : D07 (le guetteur immobile cède) et D08, pas un changement de la règle des places.

### Places d'arrêt (LK18-T03)

`LivingKnox.StopPlace` porte seul la règle : une place d'arrêt n'est ni une case dont un bord porte une porte (case de
porte ou seuil, des deux côtés), ni un passage d'une case de large (deux côtés opposés fermés : voisine absente ou
impraticable, ou bord fermé au sens de `Movement.edgeBlocked`).

- `StopPlace.nearest(x, y, z, radius, accept, rank)` : la rank-ième case, dans l'ordre des anneaux de
  `Bodies.ring`, qui satisfait les critères de l'appelant (`accept`) et la règle ; sans elle, la rank-ième qui
  satisfait `accept` seul (repli : un PNJ doit pouvoir s'arrêter quelque part).
- `StopPlace.firstAllowed(squares)` : première candidate qui respecte la règle, sinon la première.

Appelants :

| Place | Fonction | Règle par |
|---|---|---|
| Attente et repos au foyer, retour au foyer, apparition | `Materialize.placeFor` | `nearest` |
| Corvée, repas, soin, entretien, barricade, fouille à côté d'un objet | `Routines.exec.placeBeside` | `firstAllowed` (l'objet doit rester voisin) |
| Poste de guet et de défense (relevé du foyer) | `Routines.survey` | `nearest`, rayon `StopPlace.SHIFT_RADIUS` (2), même regard |
| Place au bâtiment d'une expédition, retour d'expédition | `Expeditions.freeNear` | `nearest` |
| Cueillette, rive de pêche | `Food.spotIn`, `Food.shoreSpot` | `nearest` |
| Arrosage, récolte, semis | `Garden.placeNear` (`freeSquareAtHome`) | `nearest` |

Non concernés : les couchages (sommeil, D04 ne les cite pas), les points de passage d'un trajet (`Directives.moveTo`,
`standTarget` ne décale que hors des plantes et feux), les apparitions loin du foyer (vengeance, raids).

Un relevé de postes sauvegardé avant LK18-T03 garde ses anciennes places jusqu'au prochain relevé (foyer déplacé ou
relevé invalide).

## Alternatives écartées

| Alternative | Contre | Verdict |
|---|---|---|
| Champ `passage` dans `Decisions.registerExtension` | Lie le passage au cadre de décision ; un comportement hors cascade (`care`) ne pourrait pas déclarer | écartée |
| Liste des priorités dans `LK_Passage.lua` | Ajouter un comportement modifierait le module de passage (ADR D02) | écartée |
| Règle des places d'arrêt dans `Bodies.freeSquare` | Mêle la règle aux apparitions et aux contrôles de case libre ; touche des appelants qui ne s'arrêtent pas | écartée |
| Règle appliquée à toute cible de `Directives.moveTo` | Une porte doit rester une cible (ouvrir, barricader, passer) | écartée |
| Écart mené seulement au passage de décision du bloqueur | Réaction lente (un membre évalué toutes les quelques secondes) ; aucun effet sur un PNJ hors du cadre | écartée : marche donnée dès l'ordre |
| Extension `overlay` | Le soin ou la routine passeraient avant l'écart et garderaient le membre à sa tâche | écartée |
| Option « arrivée serrée » ajoutée à `Directives.moveTo` | Change un module partagé par tous les comportements | écartée : dépassement `walkTarget` |
