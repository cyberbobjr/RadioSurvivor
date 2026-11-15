# Passage entre PNJ : priorités, arbitrage, places d'arrêt

- Tâches : LK18-T01 (registre des priorités, arbitrage), LK18-T03 (places d'arrêt) ; LK18-T02 (action « s'écarter », signalement) à venir
- ADR : [Les PNJ se cèdent le passage](../../architecture/decisions/adr-ceder-le-passage.md) (D01 à D06)
- Code : `Contents/mods/batman_LivingKnox/42.21/media/lua/shared/LivingKnox/LK_Passage.lua` (registre), `.../shared/LivingKnox/LK_PassageArbiter.lua` (arbitrage pur), `.../server/LivingKnox/LK_StopPlace.lua` (règle des places d'arrêt) ; bancs `tests/test_lk_passage.py`, `tests/test_lk_stop_place.py`
- Build : 42.22 (Java décompilé **J/** = `E:\pz-source-42.22\java\zombie\`) — Date : 2026-11-15 — Statut : testé hors jeu seulement

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

- `mover`, `blocker` : `{ id, kind, x, y, z }` ; `blocker.canMove == false` (blessé, en combat, mort) : rien.
- Le demandeur passe si sa priorité est plus haute, ou égale et son numéro de PNJ plus petit (`Identity.idNumber`) ;
  sinon rien (le demandeur garde le traitement actuel du blocage, « stuck »).
- `{ action = "stepAside", to }` : case libre voisine du bloqueur (distance 1), ni la sienne ni celle du demandeur, hors
  des cases `path` du demandeur ; la plus proche, puis la plus loin du demandeur, puis y et x.
- Sans case de côté : `{ action = "backOff", to }` : case libre derrière le bloqueur (côté opposé au demandeur), hors
  du trajet, la plus proche.
- `free` : cases libres où le bloqueur peut se tenir et qu'il peut joindre, relevées par l'autorité (LK18-T02).

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
