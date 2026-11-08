# Défense coordonnée du foyer

- Tâches : LK05-T09 (création, 2026-10-12), LK06-T07 (tout le monde se bat, 2026-10-12, [decisions.md](decisions.md)), LK06-T09 (offensive à la fenêtre, 2026-10-12) ; s'appuie sur LK05-T02 (cascade, [decisions.md](decisions.md)), LK05-T03 (postes relevés, [routines.md](routines.md)), LK05-T08 (alerte, [alerte.md](alerte.md)), LK06-T02 à T04 (combat, [combat.md](combat.md), [zombies.md](zombies.md)), LK06-T05 (retraite, reddition, aide, [fuite-reddition.md](fuite-reddition.md)) ; suite : LK07-T03 (soins après l'attaque, point d'appel seulement ici), LK14 (fortification)
- Build : 42.21.0 — Date : 2026-10-12 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Defense.lua` (`LivingKnox.Defense`, autorité seulement), branché dans `LK_Decisions.lua` (contexte `ctx.defense`, comportement `defend` de la règle `threat`, `Decisions.apply`), laisse de l'ordre de combat dans `LK_Combat.lua` (`opts.leash`), activité `watch` dans `LK_Needs.lua`. Réglages : `Defense.CFG`. Tests : `tests/test_lk_defense.py`, `tests/test_lk_window_kill.py` (LK06-T09), suites en jeu `lk.defense` (`dev/.../suites/RST_LKDefense.lua`) et `lk.windowkill` (`RST_LKWindowKill.lua`).

## Problème

Quand une menace arrive au foyer (petite horde, pillards), le groupe doit le défendre ensemble : les combattants aux portes et fenêtres qui donnent sur la menace, les autres à l'abri à l'intérieur, tir ou mêlée depuis les postes, repli à l'intérieur si la menace est trop forte, renfort des membres proches. Rien d'incohérent : personne ne sort chercher un zombie, personne ne reste à pousser contre un mur. L'autorité décide seule et de façon reproductible : deux joueurs voient le même déroulé.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Le serveur ne déplace ni n'anime un corps simulé par un client : seules les consignes LK03 (`move`, `face`, `stop`), les gestes et les ordres de combat passent ; ils sont relayés à l'identique aux clients proches. | [consignes.md](consignes.md), [combat.md](combat.md) ; base `multiplayer.md` (« zombies en MP : un seul simulateur ») | confirmé statiquement |
| Ligne de vue et de tir : `LosUtil.lineClear(cell, x0, y0, z0, x1, y1, z1, false)` (entiers), même appel que `IsoGameCharacter.CanSee` ; `Clear` ou `ClearThroughOpenDoor` admis. | base `perception.md` ; `LK_Combat.lua` (`Combat.lineOfFire`) | confirmé statiquement |
| Aucun zombie vanilla ne cible un zombie : les attaques des zombies sur un corps de PNJ sont décidées par l'autorité au contact (`LK_Zombies.pass`). | base `zombies-as-npc-bodies.md` ; [zombies.md](zombies.md) | confirmé statiquement |
| Pièce et bâtiment d'une case : `getBuildingDef()` par la pièce seulement (`nil` hors pièce), comparé par `getIDString`. | base `world-placement.md` ; `J/iso/IsoGridSquare.java:7805-7816` | confirmé statiquement |
| Une consigne `face` remet le geste au repos (`LK_Directives.issue`) : le geste de défense se pose après la consigne. | `LK_Directives.lua` ; [alerte.md](alerte.md) | confirmé par le banc |
| Un ordre de combat approche la cible en course (`approach`, consigne `move` vers la case de la cible) dès qu'elle est hors de portée, à chaque pas de 250 ms : sans laisse, un défenseur suivrait un zombie qui recule. | `LK_Combat.lua` (`Combat.step`, `approach`) | confirmé par le banc |

## Choix (2026-10-12)

### Déclenchement et fin

- Défense active quand le groupe a une **alerte en cours** (LK05-T08) **et** que le recensement de l'autorité compte au moins une menace près du foyer : zombies vanilla (`Zombies.isVanilla`) et joueurs **hostiles** pour le groupe (`Alert.playerKind`) à 12 cases au plus de la case du foyer (en x et en y), au plus un étage d'écart. Un intrus (joueur inconnu ou méfiant) donne l'alerte mais pas la défense.
- Pas de défense sans poste relevé (relevé pas encore fait) : la cascade reste celle de LK05-T08 et LK06 (regard, combat libre). Foyer en camp : défense en plein air (section « Campement », LK05-T18).
- Fin : plus aucune menace recensée depuis 2 minutes de jeu (`END_MINUTES`). Le recensement de l'autorité prolonge la défense même si plus personne ne voit la menace (un zombie collé au mur arrière reste une menace).
- Plan du groupe refait au plus une fois par seconde réelle ou par minute de jeu (`PLAN_MS`), lu par chaque membre évalué.

### Rapport de forces et repli (I6.3, I6.6)

- Menace = zombies + 3 × hostiles (`HOSTILE_WEIGHT`). Combattants valides = membres présents **de tout rôle** (LK06-T07 ; avant : rôle qui permet `fight` ou `defend`) aux constantes bonnes : santé ≥ 0,5 (`VALID_HEALTH`, comme `WOUND_RATIO`) et peur < 70 (`NEED_HIGH.fear`), à 30 cases au plus du foyer.
- **Repli** (`withdraw`) si aucun combattant valide ou menace > 3 × combattants valides ; **retour aux postes** (`hold`) quand menace ≤ 2 × combattants valides (hystérésis, pas de va-et-vient). Une petite horde de 3 à 5 zombies contre deux combattants : `hold`. Décision collective, journalisée au nom du chef (« leader m-1 orders everyone inside »).

### Places (affectations pures, déterministes)

- `hold` : chaque combattant valide, par numéro de membre, reçoit un **poste de guet** du relevé LK05-T03 (case intérieure contre une porte ou une fenêtre, direction extérieure). Postes classés : ceux qui **donnent sur la menace** d'abord (direction extérieure à 90° au plus de la direction poste → menace), puis par distance à la menace, puis rang du relevé. Un poste par membre ; un membre **garde son poste** tant qu'il reste parmi les postes retenus (pas d'échange quand la horde bouge). Regard : vers la menace (poste qui donne sur elle), sinon vers l'extérieur du poste (il garde son côté).
- **Abris** : cases praticables du bâtiment du foyer (même niveau, 10 cases au plus) dont les quatre voisines sont du bâtiment (ni bord, ni porte, ni fenêtre), hors postes, triées de la plus éloignée à la plus proche de la menace (8 au plus, refaites au départ et à chaque changement de phase). Membres aux constantes mauvaises (blessés, apeurés) aux plus éloignées, membres valides (surnombre en `hold`, tous en `withdraw`) aux plus proches de la menace. Plus de membres que d'abris : case du foyer.
- **Renforts** : un membre incarné à 30 cases au plus du foyer (`REINFORCE_RADIUS`, comme `Alert.CFG.REACH`), même dehors en ronde ou en corvée, reçoit sa place et y **court**. Plus loin : hors de la défense (alerte et cascade habituelles).
- Place injoignable (deux trajets refusés ou manqués, `MAX_FAILS`) : notée bloquée 5 minutes de jeu, le plan suivant en donne une autre ; en attendant, regard sur place. Aucun membre ne reste coincé à essayer.

- LK05-T14 ([decisions.md](decisions.md), « Seuils de danger réglables ») : `THREAT_RADIUS` = option `LivingKnox.DefenseRadius` (défaut 8), zombies recensés seulement à `LivingKnox.ZombieAlertDistance` cases du foyer au plus ; `WITHDRAW_RATIO` = option `LivingKnox.DefenseWithdrawRatio` (défaut 3), `HOLD_RATIO` = rapport − 1 ; `REINFORCE_RADIUS` = option `LivingKnox.AlertReach` (défaut 20). Sans les options : valeurs ci-dessus.

### Combat autour des postes (LK06-T14 : sortie jusqu'à la portée d'engagement)

Décision de l'utilisateur du 2026-10-13 (constat en jeu : « les colons n'ont attaqué que les zombies qui venaient au corps à corps ») : un membre apte attaque les zombies jusqu'à 10 cases, sans attendre le corps à corps, y compris en défense du foyer. Point 4 de l'en-tête de `LK_Defense.lua`.

- **Sortie** (phase `hold`, place de combattant valide `fighter` : poste, ou abri d'un combattant en surnombre) : zone = `Defense.engageRange(npc)` cases (option `ZombieEngage<Rôle>` du rôle du membre, défaut 10, bornée par `ZombieAlertDistance`) autour de sa place, en x et en y, même niveau. Corps dans la zone (à zone + 1 case de sa place) : cible = zombie vanilla le plus proche **du corps** dans la zone (recensé autour du foyer ou non), donc plusieurs zombies se répartissent selon les positions des membres. Ligne directe de coup (`Combat.lineOfStrike`) : il y va ; zombie vu seulement derrière une vitre (`Zombies.sees`) et qui ne frappe pas le bâtiment (`getThumpTarget` nil) : il le rejoint **par son chemin** (porte ouverte et refermée par `LK_Obstacles`, ordre `leash.around` : pas d'attente en garde derrière la vitre, LK06-T08) ; zombie qui frappe une fenêtre, une porte ou une barricade : laissé au contact et à l'offensive à la fenêtre (LK06-T09). Au plus 3 lignes essayées par passage (`MAX_TARGET_TRIES`). Laisse de l'ordre = la zone : il frappe, puis revient à sa place dès qu'aucune cible n'est dans la zone. Un corps sorti de la zone en contournant le bâtiment garde sa cible tant que la laisse la garde (pas de demi-tour à mi-chemin).
- Tir (poste, arme à feu chargée, `Combat.weaponOf`) : menace la plus proche à portée de l'arme avec une ligne de tir dégagée (3 lignes essayées au plus), recensée ou dans la zone.
- **Sans sortie** : repli (`withdraw`, groupe débordé) et membre aux constantes mauvaises (abri, place non `fighter`) : mêlée seulement sur une menace à 2 cases au plus du corps (`MELEE_ENGAGE`), laisse `COMBAT_LEASH` = 1 ; membre en route (corps hors de la zone) : seulement une menace au contact.
- Choix : contourner par la porte un zombie vu derrière une vitre (comme le ferait un joueur) au lieu d'attendre derrière la vitre, y compris un zombie qui frappe le bâtiment (E18-T34) ; zone en cases autour de la **place** (pas du corps).
- Joueur : seulement la cible retenue par la cascade (`Hostility.chooseTarget`, aide de LK06-T05 : trêve et reddition respectées), aux mêmes conditions.
- **Laisse de l'ordre de combat** (`Combat.engage(..., { leash = { x, y, z, r, around } })` : r = zone de sortie, sinon `COMBAT_LEASH` = 1) : à chaque pas du combat (250 ms, sans attendre la cascade), une cible à plus de r cases de la place (ou à un autre niveau) n'est jamais approchée : frappe à portée ou tir dégagé seulement, sinon fin de l'ordre ; le défenseur revient à sa place au passage suivant. La laisse est gardée quand l'arme à feu se vide (mêlée de repli). LK06-T14 : une cible n'est **choisie** que si cette laisse la garde (`Defense.held` : dans la laisse, ou à portée de l'arme) ; avant, une menace à 2 cases du corps mais à plus d'une case de la place était choisie puis abandonnée aussitôt, à chaque passage (« target out of the defense leash » en boucle).
- Hors de ces conditions, aucune cible : pendant la défense, la règle `fight` libre de LK06-T04 n'est plus choisie.

### Cascade et exécution

- Règle `threat` : reddition, retraite (LK06-T05), puis **`defend`** (avant le combat libre, le regard et la fuite). Un combattant à bout de nerfs se terre toujours (retraite) ; un blessé au foyer défend depuis un abri. Clé de l'état : `def:<rôle> x,y,z` ; durée d'un état : 1 minute de jeu (cible relue à chaque passage).
- `Defense.apply` : engagement (source `decisions`, fin par `Combat.leave`), sinon course vers la place, regard (`face`, renouvelé à 30° d'écart), geste `guard` (membre valide, place marquée `fighter`) ou `crouch` (constantes mauvaises) posé après la consigne ; vigilance `guard` (portée par la consigne `vg` en MP).
- Les clés `def:` ne comptent pas comme menaces connues du groupe (notation horaire des objectifs).

### Après l'attaque (point d'appel LK07-T03)

- Fin de la défense : marque `Defense.after(gid)` = `{ id, minute, minutes, wounded = { mid… }, why }` (blessé : santé < 0,75, `CARE_HEALTH`), entrée `defense` au journal du groupe (« home defense def-N over after M min (…); wounded: … »), puis appel de `LivingKnox.Care.afterAttack(gid, marque)` **s'il existe** (LK07-T03, pas encore fait). Aucun soin n'est fait ici. LK14-T06 lit aussi cette marque (`Fortify.urgent`, [fortification.md](fortification.md) §9) : pendant un jour de jeu, les réparations des barricades et ouvrages abîmés passent en tête des chantiers.

### Zombie à une fenêtre (E18-T34, 2026-11-07)

Décision de l'utilisateur du 2026-11-07 : l'offensive à la fenêtre (LK06-T09 : un membre ouvrait la fenêtre pour que le
zombie tombe à l'intérieur, puis les autres l'achevaient au sol ; refermeture LK06-T15, retenue des coups, rapport de la
fenêtre frappée par le client propriétaire) est **retirée**. En multijoueur le zombie est simulé par un client : le
serveur ne voit pas ses coups et l'enchaînement vanilla (enjamber au moment où la fenêtre s'ouvre) se ratait souvent
(`lk.windowkill` : 24 réussites pour 44 échecs en MP sur les passages enregistrés ; zombie qui griffe l'ouvreur puis
s'en va, zombie qui ne frappe pas sans PNJ en vue, porte voisine frappée). Un zombie qui frappe le bâtiment est
désormais une cible de **sortie** comme une autre (LK06-T14) : vu derrière la vitre, un membre valide le rejoint par une
porte et l'attaque dehors, puis revient à son poste ; débordé, le groupe reste à l'intérieur (repli). Un zombie qui
casse la vitre et entre est combattu à l'intérieur (coup au sol s'il tombe, LK_Combat).

Deux règles tiennent la sortie par la porte (passages MP du 2026-11-08) : un trajet guidé par une porte (`Directives.moveTo`,
`e.dr`) n'ouvre aucune fenêtre au contact (`Obstacles.checkWindows` : un membre arrêté le temps d'ouvrir sa porte ouvrait
la fenêtre voisine) ; un membre parti contourner (ordre de combat `leash.around`) garde son zombie dans la zone de sa place
même quand il ne le voit plus en route vers la porte (`Defense.targetFor`), au lieu de revenir à son poste.

### Campement (LK05-T18)

Décision de l'utilisateur du 2026-10-14 : un groupe en campement (foyer hors de tout bâtiment : feu de camp, tentes) attaqué par des zombies se bat sur place au lieu de rester sans défense. Avant : relevé « camp » = aucune défense ; chaque membre valide frappait seul un zombie à sa portée (LK06-T07, LK06-T14), sans place, sans regroupement des non-combattants ni repli collectif. Point 8 de l'en-tête de `LK_Defense.lua`.

- **Mêmes** déclencheurs (alerte + menace recensée), seuils, rapport de forces et hystérésis, sorties dans la portée du rôle autour de la place, blessés, fin, marque et appel des soins que la défense d'une maison.
- **Postes** (`Defense.campPosts`) : jusqu'à 8 places en couronne à 3 cases du foyer (N, E, S, W, puis diagonales), regard vers l'extérieur ; point de la couronne occupé (tente, feu, meuble) : voisine praticable restée à 2-4 cases du foyer. Classés et donnés comme les postes d'une maison (face à la menace d'abord, puis distance).
- **Abris** (`Defense.campShelters`) : cases praticables à 1 case du foyer, hors postes : membres aux constantes mauvaises, surnombre et repli regroupés au centre du camp, derrière la couronne.
- **Repli** (groupe débordé) : tout le monde au centre, mêlée au contact seulement (pas de bâtiment où entrer).
- Pas d'offensive à la fenêtre. Journal : « home defense def-N (hold, …), threat from x,y, camp ». Interrupteur `CFG.CAMP` (faux : ancien comportement).
- Tests : banc `tests/test_lk_defense.py`, classe `CampDefenseTests` (couronne et centre, camp attaqué par 3 zombies : défense ouverte, postes en couronne, sortie dans la portée du rôle puis retour aux places, défense close ; blessé au centre, repli au centre ; interrupteur) ; suite `lk.defense`, second test « camp attacked by a small horde » (terrain dégagé hors de tout bâtiment, `RST.Places` outdoor).

### Mémoire

Plans, places bloquées, marques d'après l'attaque et mémoire d'exécution : mémoire seulement (un redémarrage les oublie, la cascade les refait au passage suivant).

### Contrôle en jeu stable (décision 6 de l'utilisateur, 2026-10-14)

Constat : en solo, `lk.defense` échouait 1 fois sur 2 environ (`tools/autoclient/runs/20261014-190409-…`, `-191156-…`, `-192222-…`, `-193252-…` : « able worker neither in guard nor fighting », geste `run`) : le contrôle des gestes suivait aussitôt l'arrivée large aux places (ARRIVE + 0,5 case) alors que l'ouvrier courait encore les derniers pas vers son poste. La suite attend maintenant un état stable borné (`STABLE_MS` = 30 s : chaque défenseur valide à sa place en garde, ou au combat) avant les contrôles ; aucun contrôle retiré.

## Alternatives écartées

- Déclencher la défense à l'entrée d'un intrus dans le bâtiment seulement (I6.1 littéral) : trop tard contre des zombies qui cassent une fenêtre ; on défend le bâtiment dès l'alerte, mais sans jamais sortir (même esprit : on ne poursuit pas à distance).
- Recompter les menaces par les clés d'alerte (`Alert.state.known`) : en solo tous les zombies partagent la clé `z?` ; le recensement direct de la cellule par l'autorité compte juste et ne dépend pas de la perception.
- Repli par simple seuil sans hystérésis : va-et-vient entre postes et abris quand un zombie de plus entre ou sort du rayon.
- Laisse vérifiée seulement par la cascade (une évaluation par membre et par seconde au plus) : le combat a le temps d'émettre une consigne `move` vers un zombie qui recule (constaté au banc) ; la laisse est donc portée par l'ordre de combat lui-même.
- Retrait tactique « revenir par un autre côté » (I6.4) : demande une recherche de chemin qu'on ne lit pas en Lua ; on garde le repli vers les abris intérieurs.

## Idées reprises

- I6.1 (défense déclenchée par l'intrusion dans **leur** bâtiment) : la défense est celle du bâtiment du foyer, sans poursuite à distance ; déclenchée par l'alerte et une menace recensée près du foyer.
- I6.3 (critères de repli) : rapport menace / combattants valides (santé), avec hystérésis ; munitions : un tireur vide passe à la mêlée (LK06-T03), peur : retraite de LK06-T05.
- I6.4 (retrait tactique) : repli dans les pièces intérieures, loin de la menace ; « revenir par un autre côté » non repris.
- I6.6 (repli collectif du chef) : décision de groupe journalisée au nom du chef ; succession et dispersion à sa mort : LK08.

## Tests

- Banc lupa (`tests/test_lk_defense.py`, 13 tests) : rapport de forces et hystérésis ; classement des postes face à la menace ; affectations déterministes, uniques, stables, places bloquées ; `defend` après reddition et retraite, avant le combat libre ; pile complète en solo : petite horde au sud, combattants à la porte et à la fenêtre ouest, ouvrier accroupi à l'abri, aucune mêlée à 6 cases, mêlée depuis la porte quand un zombie y arrive, fin de la mêlée et retour au poste quand il recule, aucun défenseur hors du bâtiment, fin de la défense, marque et appel des soins ; repli contre 7 zombies puis retour aux postes ; combattant blessé à l'abri ; renfort qui revient en courant ; membre trop loin hors de la défense ; place injoignable remplacée ; foyer en camp sans défense (avant LK05-T18 ; depuis : défense en plein air, section « Campement ») ; serveur dédié + deux clients : mêmes consignes, gestes et vigilance chez A et B, même déroulé pour le même monde, aucune défense côté client ; suite `lk.defense` jouée sur les doublures.
- VM Kahlua (`tests/test_kahlua.py`) : sans objet (sources contrôlées : aucun `next`, `goto`, opérateur binaire ni littéral non ASCII).
- En jeu : `RST.run({ suite = "lk.defense", tags = "world" })` en solo (rstest, joueur dans une maison avec une porte ou une fenêtre près de lui) ; MP à la séance finale.

## Points ouverts

- ⚠ Seuils (12 cases, rapports 3 et 2, poids 3 d'un hostile, laisses 3 et 1) à recalibrer en jeu.
- ⚠ Un zombie vanilla qui casse une fenêtre ou une porte et entre : combattu à 2 cases ; aucune barricade ni réparation pendant la défense (LK14).
- Abris relevés au même niveau que le foyer seulement ; étage et sous-sol ignorés.
- Tir depuis un poste qui ne donne pas sur la menace : possible si la ligne de tir est dégagée (fenêtre latérale).
- Soins : seulement la marque et le point d'appel (LK07-T03).

