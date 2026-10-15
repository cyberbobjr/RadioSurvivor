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
- Choix (à confirmer) : contourner par la porte un zombie vu derrière une vitre (comme le ferait un joueur) au lieu d'attendre derrière la vitre ; zone en cases autour de la **place** (pas du corps) ; les zombies qui frappent le bâtiment restent à l'offensive à la fenêtre.
- Joueur : seulement la cible retenue par la cascade (`Hostility.chooseTarget`, aide de LK06-T05 : trêve et reddition respectées), aux mêmes conditions.
- **Laisse de l'ordre de combat** (`Combat.engage(..., { leash = { x, y, z, r, around } })` : r = zone de sortie, sinon `COMBAT_LEASH` = 1) : à chaque pas du combat (250 ms, sans attendre la cascade), une cible à plus de r cases de la place (ou à un autre niveau) n'est jamais approchée : frappe à portée ou tir dégagé seulement, sinon fin de l'ordre ; le défenseur revient à sa place au passage suivant. La laisse est gardée quand l'arme à feu se vide (mêlée de repli). LK06-T14 : une cible n'est **choisie** que si cette laisse la garde (`Defense.held` : dans la laisse, ou à portée de l'arme) ; avant, une menace à 2 cases du corps mais à plus d'une case de la place était choisie puis abandonnée aussitôt, à chaque passage (« target out of the defense leash » en boucle).
- Hors de ces conditions, aucune cible : pendant la défense, la règle `fight` libre de LK06-T04 n'est plus choisie.

### Cascade et exécution

- Règle `threat` : reddition, retraite (LK06-T05), puis **`defend`** (avant le combat libre, le regard et la fuite). Un combattant à bout de nerfs se terre toujours (retraite) ; un blessé au foyer défend depuis un abri. Clé de l'état : `def:<rôle> x,y,z` ; durée d'un état : 1 minute de jeu (cible relue à chaque passage).
- `Defense.apply` : engagement (source `decisions`, fin par `Combat.leave`), sinon course vers la place, regard (`face`, renouvelé à 30° d'écart), geste `guard` (membre valide, place marquée `fighter`) ou `crouch` (constantes mauvaises) posé après la consigne ; vigilance `guard` (portée par la consigne `vg` en MP).
- Les clés `def:` ne comptent pas comme menaces connues du groupe (notation horaire des objectifs).

### Après l'attaque (point d'appel LK07-T03)

- Fin de la défense : marque `Defense.after(gid)` = `{ id, minute, minutes, wounded = { mid… }, why }` (blessé : santé < 0,75, `CARE_HEALTH`), entrée `defense` au journal du groupe (« home defense def-N over after M min (…); wounded: … »), puis appel de `LivingKnox.Care.afterAttack(gid, marque)` **s'il existe** (LK07-T03, pas encore fait). Aucun soin n'est fait ici. LK14-T06 lit aussi cette marque (`Fortify.urgent`, [fortification.md](fortification.md) §9) : pendant un jour de jeu, les réparations des barricades et ouvrages abîmés passent en tête des chantiers.

### Offensive à la fenêtre (LK06-T09)

Décision de l'utilisateur du 2026-10-12 : « le PNJ se défend et prends l'offensive et peut faire comme dans Walking Dead : ouvrir la fenêtre pour laisser le zombie tomber à terre afin de l'achever, comme le font les joueurs humains de Project Zomboid ». Point 7 de l'en-tête de `LK_Defense.lua`.

Moteur (Java 42.21.0) : un zombie en `ThumpState` dont la fenêtre frappée s'ouvre perd sa cible de coups (`IsoWindow.getThumpableFor` rend `nil` pour une fenêtre ouverte sans barricade, J/iso/objects/IsoWindow.java:455-465) et l'enjambe aussitôt (`climbThroughWindow` si `canClimbThrough`, J/ai/states/ThumpState.java:183-193) ; l'issue `success` des nœuds zombie le met au sol de l'autre côté (événement `OnFloor` à 10 % puis 66 % de `Zombie_ClimbWindowEnd`, 3,67 s à la vitesse 0,88 : environ 2 s à terre, J/ai/states/ClimbThroughWindowState.java:105-127, 296-308, `M/AnimSets/zombie/climbwindow/end.xml`). De l'intérieur, une fenêtre verrouillée s'ouvre quand même (`OpenWindowState` n'arrête que l'ouvreur sur une case extérieure, J/ai/states/OpenWindowState.java:128, 167 ; `ToggleWindow` déverrouille, J/iso/objects/IsoWindow.java:701-731). Rien n'est simulé : le mod n'ouvre que la fenêtre.

- **Quand** : à chaque plan en phase `hold` seulement — jamais en repli (groupe débordé, `assess`) ; une fenêtre (`IsoWindow`) du bâtiment du foyer, au niveau du foyer, frappée de l'extérieur par un zombie recensé (`getThumpTarget`), fermée, intacte, non barricadée, ni bloquée (`isPermaLocked`), ni d'une maison à alarme armée (`Obstacles.alarmArmed`), avec un sol dehors ; une seule offensive à la fois par groupe.
- **Rapport favorable** (choix documenté) : zombies qui attendent à la fenêtre (2 cases autour de la case extérieure, dehors) ≤ `OFFENSE_RATIO` (1) x combattants valides comptés (corps ou place de défense à 3 cases de la case intérieure). Raison : les zombies entrent un par un et tombent ; un PNJ valide par zombie qui attend suffit à achever chacun au sol, au-delà la fenêtre reste fermée (garde derrière la vitre, LK06-T08). Fenêtre retenue : la moins assiégée. Membre inapte (blessé, apeuré) : jamais compté ni ouvreur.
- **Ouvreur** : le défenseur posté à cette fenêtre s'il est valide, sinon le plus proche du bord. Il court à la case intérieure, joue le geste `openwindow` du joueur tourné vers la fenêtre ; la fenêtre est basculée avec son corps (`ToggleWindow`) à l'instant du clip (1 s après le début du geste, `Defense.tick` sur `OnTick`).
- **Après l'ouverture** : la case de chute reste libre ; l'ouvreur prend la case d'un pas vers l'intérieur, le défenseur posté à la fenêtre (s'il est un autre) une case voisine ; tous deux à une case de la chute, dans la laisse du combat, ils l'achèvent au sol (coup au sol, [combat.md](combat.md#coup-au-sol-lk06-t09) : chaque coup non mortel le garde à terre).
- **Fin** : plus aucun zombie à 2 cases de la fenêtre (des deux côtés), 45 s après l'ouverture, fenêtre refermée ou disparue. Abandon (fenêtre écartée 5 min de jeu) si elle n'est pas ouverte en 20 s ; annulée avant l'ouverture si le groupe passe en repli, si l'ouvreur devient inapte, si la fenêtre est cassée ou barricadée. Entrées `defense` au journal du groupe (« window offensive at … : m-1 opens it … », « … opened the window … », « … over: … »).
- **Refermeture** (LK06-T11, décision de l'utilisateur du 2026-10-14 : « après l'offensive (zombie mort), un membre referme la fenêtre, par le même geste que l'ouverture, sans refermer sur un corps ou un zombie dans l'embrasure ») : au lieu de finir l'offensive (plus aucun zombie près de la fenêtre, ou 45 s écoulées), l'offensive passe à l'état `closing`. Auteur : l'ouvreur s'il est encore valide, sinon le membre valide le plus proche du milieu du bord. À 1,6 case au plus du milieu du bord (sa place de recul suffit), sinon après une course vers la case intérieure, il joue le geste `closewindow` du joueur tourné vers la fenêtre ; `Defense.tick` la ferme avec son corps à l'instant du clip (1,08 s, `Obstacles.CLOSE_TOGGLE_MS` ; geste 2,08 s). **Embrasure** : aucun objet mobile vivant (zombie, corps de PNJ, joueur ; véhicule) sur les deux cases du bord, l'auteur excepté ; un personnage mort pendant son animation de mort ne compte pas, le cadavre (`IsoDeadBody`) n'est pas un objet mobile de la case. Occupée : geste arrêté, nouvel essai au passage suivant (`stats.closeWaits`) ; non fermée en 20 s (`OFFENSE_CLOSE_MS`) : fenêtre laissée ouverte (« over: window left open … », `stats.closeGivenUp`). Les autres membres gardent leurs places de recul (case intérieure libre) ; la défense ne finit pas tant qu'une offensive (refermeture comprise) est en cours. Fenêtre déverrouillée par l'ouverture : laissée déverrouillée. Journal : « …: no zombie left at the window, m-1 closes the window », « … m-1 closed the window », « … over: window closed (…) ». Compteurs `closeGestures`, `windowsClosed`.
- **Retenue jusqu'à la chute** (demande du 2026-10-15, campagne MP `20261015-010324-mp-29017ca19a4f` : rapport de coups accepté, fenêtre ouverte par m-1, puis m-1 et m-2 frappent le zombie **debout** pendant qu'il enjambe, mort debout, « floor hits 0 ») : comme un joueur vanilla, pendant l'ouverture et l'attente de la chute (états `opening` et `open`), aucun membre n'engage (mêlée ni tir) un zombie de l'offensive tant qu'il n'est pas au sol. Zombies de l'offensive (`Defense.noteHeld`, à chaque plan) : zombies recensés qui attendent dehors à 2 cases de la case extérieure, ou qui enjambent (`climbwindow`), pas déjà au sol. `Defense.offenseHolds`, lu par `Defense.targetFor` (ordre en cours, cible au contact, candidats) : retenue levée pour de bon quand le zombie est au sol (`isOnFloor` : coup au sol), entré debout (dans le bâtiment, hors de `climbwindow`, depuis `OFFENSE_STAND_MS` = 1 s), `OFFENSE_FALL_MS` (15 s) après l'ouverture, ou à la fin de l'offensive ; ensuite combat normal (relevé compris). Interrupteur `OFFENSE_HOLD`. Journal : « zombie z:… left alone until it falls inside », « zombie z:… on the floor, members may hit it » ; compteurs `offenseHeld`, `offenseFreed`. Non vérifié : ce que la copie serveur d'un zombie simulé par un client rend pour `isOnFloor` et `getActionStateName` pendant l'enjambée (à lire dans les lignes de la campagne MP) ; au pire la retenue se lève par « came in standing » ou le délai.
- Une porte : non traitée (décision complémentaire de LK06-T08 : rien d'équivalent chez le joueur vanilla, qui ne laisse pas un zombie tomber par une porte ; une porte ouverte le laisse entrer debout). Reste noté.

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
- Banc `tests/test_lk_window_kill.py` (LK06-T09) : choix pur (ouvreur le plus proche ou posté, égalités, fenêtre la moins assiégée, jamais en repli, rapport défavorable, personne près de la fenêtre) ; bord et regard ; pile complète en solo avec une fenêtre verrouillée frappée par un zombie qui l'enjambe et tombe à l'intérieur (doublures) : offensive, geste `openwindow` avant la bascule, une seule bascule avec le corps de l'ouvreur, fenêtre déverrouillée, recul d'un pas, zombie achevé au sol sans s'être relevé ; LK06-T11 : refermeture par l'ouvreur (geste `closewindow` avant la bascule, deuxième bascule avec son corps, fin « window closed ») ; joueur dans l'embrasure : pas de fermeture, puis fermée une fois libre ; toujours occupée : laissée ouverte après le délai ; serveur : fenêtre retenue seulement sur rapport du propriétaire (aucune déduction par proximité), rapport refusé pour une fenêtre absente à la case ou au bord indiqués, un zombie inconnu, un client qui ne simule pas le zombie, une copie hors de portée, un autre foyer, un rapport de plus de 5 s, rejoué, ou remplacé par un rapport sans fenêtre ; case courante absente ou en retard sans effet ; entrées mal formées refusées ; `tests/test_lk_senses.py` (`ThumpReportTests`) : collecte chez le propriétaire seul (copie distante jamais rapportée), propriétaire du zombie sans aucun corps qui rapporte, renvoi toutes les 2 s, liste vidée, contrôles du serveur ; trois zombies : pas d'ouverture ; groupe débordé : jamais ; membre blessé : jamais ouvreur ; repli pendant l'ouverture : annulée, fenêtre fermée ; fenêtre barricadée ou bloquée : rien.
- En jeu : `RST.run({ suite = "lk.defense", tags = "world" })` en solo (rstest, joueur dans une maison avec une porte ou une fenêtre près de lui) ; MP à la séance finale.
- En jeu (LK06-T09) : solo, sauvegarde `rstest*`, joueur dans une maison à 8 cases au plus d'une fenêtre extérieure fermée, intacte, sans barricade ni rideau fermé, sans alarme : `RST.run({ suite = "lk.windowkill", tags = "world" })` en regardant la fenêtre : trois PNJ apparaissent, un zombie dehors vient taper la vitre, un PNJ fait le geste d'ouvrir, la fenêtre s'ouvre, le zombie l'enjambe et tombe, les PNJ le frappent au sol (batte visée au sol ou piétinement) jusqu'à la mort ; lignes `[LKX] measure` (offensive, ouverture, chute, mort, coups au sol, relevé avant la mort). Attendu `OK`.

## Points ouverts

- ⚠ Seuils (12 cases, rapports 3 et 2, poids 3 d'un hostile, laisses 3 et 1) à recalibrer en jeu.
- ⚠ **Décision à confirmer** (LK06-T09) : offensive à la fenêtre si zombies qui attendent ≤ 1 x combattants valides à 3 cases de la fenêtre ; ouvreur = défenseur posté, sinon le plus proche ; aucune offensive à une porte. LK06-T11 : refermeture par l'ouvreur (sinon le plus proche), abandon après 20 s d'embrasure occupée, fenêtre laissée déverrouillée.
- ⚠ LK06-T09, à voir en jeu : le PNJ frappe-t-il le zombie dans les 2 s où il est à terre (un passage de décision par seconde) ; geste `openwindow` joué sans consigne de marche ; un zombie qui frappe la vitre la casse avant l'ouverture (alors pas d'offensive, combat à travers la vitre cassée).
- ⚠ Un zombie vanilla qui casse une fenêtre ou une porte et entre : combattu à 2 cases ; aucune barricade ni réparation pendant la défense (LK14).
- Abris relevés au même niveau que le foyer seulement ; étage et sous-sol ignorés.
- Tir depuis un poste qui ne donne pas sur la menace : possible si la ligne de tir est dégagée (fenêtre latérale).
- Soins : seulement la marque et le point d'appel (LK07-T03).

## Serveur MP : cible de coups rapportée par le propriétaire (LK06-T11, 2026-10-15)

Sur un serveur, un zombie simulé par un client n'a jamais de `getThumpTarget()` (le paquet `Thump` du propriétaire est
seulement relayé aux autres clients, `ThumpPacket.processServer`, J/network/packets/character/ThumpPacket.java:54-63).
L'approximation du 2026-10-14 (« zombie dehors collé à une vitre fermée du foyer ») est **retirée** (décision de
l'utilisateur du 2026-10-14). `Defense.thumpTargetOf(z, bid)` :

1. `z:getThumpTarget()` s'il existe (solo, zombie simulé par le serveur) ;
2. sinon, sur un serveur seulement, la fenêtre que le client qui simule le zombie rapporte (commande `zombieThumps`,
   [perception.md](perception.md#fenêtres-frappées-lk06-t11)), via `Senses.thumpOf(onlineId)` : dernier rapport
   accepté de moins de 5 s, puis contrôlée à l'usage : fenêtre encore présente à la case et au bord indiqués, un de ses
   côtés dans le bâtiment `bid` du foyer défendu, zombie dehors (hors de `bid`), au même niveau, copie du serveur à
   4 cases au plus du milieu du bord (`THUMP_REACH`). Case du zombie lue d'après `getX/getY/getZ`
   (`Defense.squareOf`) : campagne MP du 2026-10-15, rapport ignoré « zombie inside the home » pour un zombie à
   10653,4 dehors contre la vitre (case courante de la copie du serveur absente ou en retard, hypothèse). Une ligne
   INFO par zombie, fenêtre et issue (« zombie … thumps window … kept / ignored, … »). Compteur
   `Defense.stats.thumpReported`.

Sert à l'offensive à la fenêtre et à l'exclusion de la sortie (LK06-T14). Limite : un client ne rapporte que les
zombies proches (30 cases) d'un corps de PNJ chargé chez lui.
