# Cadre de décision des PNJ : objectifs du groupe et cascade par membre

- Tâches : LK05-T02 (création, 2026-10-11), LK06-T07 (tout le monde se bat, 2026-10-12, section [Tout le monde se bat](#tout-le-monde-se-bat-lk06-t07-2026-10-12)) ; suite : LK05-T03 (routines : sommeil, garde, patrouille), LK05-T04 (corvées), LK05-T05 (expéditions), LK05-T06 (besoins individuels), LK05-T07 (repas), LK05-T08 (alerte), LK05-T09 (défense), LK06 (combat), LK14 (fortification)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-11 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Decisions.lua` (`LivingKnox.Decisions`, autorité seulement), accroché par `server/LivingKnox/LK_Server.lua` (`EveryHours`, `OnTick`). Entrées : [perception.md](perception.md) (`Senses.perceived`), [alerte.md](alerte.md) (`Alert.observe`, `Alert.forMember`, LK05-T08), [besoins.md](besoins.md) (`Needs.get`, LK05-T06), [sante.md](sante.md) (`Health.get`), [attitude.md](attitude.md) (`Hostility`), [groupes.md](groupes.md) (registre, types et rôles). Sorties : [consignes.md](consignes.md) (`Directives.moveTo`, `face`, `stop`).

## Problème

Les PNJ doivent agir d'eux-mêmes : le groupe se donne un but pour les heures qui viennent (se reposer, monter la garde, se ravitailler, soigner, fortifier), et chaque membre réagit vite à ce qui l'entoure (une menace, une blessure, un besoin) sans perdre le fil de ce que le groupe attend de lui. Les décisions doivent être prises par le seul serveur (ou le jeu en solo), être reproductibles (mêmes entrées, mêmes choix et mêmes raisons), coûter peu par image et ne produire que des consignes LK03 existantes. Modèle tranché par l'utilisateur le 2026-10-08 (hybride, section « Décisions » de [LK05](../plan/LK05-perception-decisions-routines.md)).

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `EveryHours` ne part qu'une fois par mise à jour de `GameTime`, même si plusieurs heures passent ; un serveur vide en pause (`PauseEmpty`) n'en émet aucun. Une notation « par heure » compare donc `math.floor(getWorldAgeHours())` à la dernière heure notée. | base `api-42-21.md`, « `EveryHours` : déclenchement, heures sautées » ; `J/GameTime.java:553-554` ; `J/gameStates/IngameState.java:1528-1530` | confirmé statiquement |
| Heure du jour = (âge du monde + 7) % 24 (âge 0 à 7 h le premier jour). | base `api-42-21.md` | confirmé statiquement |
| Un client MP charge aussi `media/lua/server` : le fichier s'arrête par `if isClient() then return end`, aucune décision côté client. | base `mod-loading.md` (« `media/lua/server` chargé aussi par un client MP ») ; même garde dans tous les modules serveur du moteur | confirmé statiquement |
| Le serveur ne peut pas chercher de chemin pour un zombie (`pathToAux` ne pose jamais `bPathfind`) : il émet une consigne, le client propriétaire l'exécute. | [consignes.md](consignes.md) ; `J/characters/IsoGameCharacter.java:5923-5958` | confirmé statiquement |
| Kahlua : `math.atan2` existe (`MathLib`), aucun opérateur binaire, `%` faux au-delà d'un quotient de 2^31 : tirages Park-Miller à quotients bornés, aucun modulo d'un négatif. | `se/krka/kahlua/j2se/MathLib.java:20-56, 276-280` ; base `kahlua-lua.md` ; VM Kahlua du jeu (`tests/test_kahlua.py`, `KR-DECIDE`) | confirmé statiquement et dans la VM |

## Choix

### Objectifs du groupe (long terme, `Decisions.scoreObjectives`)

Liste fermée `OBJECTIVES` (ordre = départage à score égal) : `settle` (vie ordinaire au foyer), `rest` (repos), `guard` (garde), `heal` (soins), `supply` (ravitaillement), `fortify` (fortification). Chaque heure de jeu (`EveryHours`, après le pas de la simulation hors écran), chaque groupe **matérialisé** (au moins un membre vivant incarné) note chaque objectif de 0 à 100 :

| Objectif | Utilité (valeurs de départ, à recalibrer) |
|---|---|
| `settle` | 30 fixe (`SETTLE`) |
| `rest` | 70 la nuit (`NIGHT_REST`, nuit de `Config.SIMULATION`) ; de jour (60 − repos du groupe) × 1,5 si le repos est sous 60 |
| `guard` | 20 par menace connue (au plus 80) + 10 % de l'hostilité du type |
| `heal` | 0,9 × blessure la plus grave, si elle atteint 30 et qu'il reste des soins (`medical` > 0) |
| `supply` | (60 − réserve la plus basse) × 1,5 si elle est sous 60 ; réserves = niveaux du stock réel du foyer (nourriture, eau, soins, munitions : `Stock.assessGroup`, LK08-T07, [stock.md](stock.md)) quand sa référence existe, sinon besoins abstraits du registre (eau ignorée) |
| `fortify` | si toutes les réserves sont à 50 ou plus et qu'un chantier est faisable avec le stock du foyer (LK14-T02, `fortWork` = `LivingKnox.Fortification.hasWork` ; inconnu : on note quand même) : (100 − fortification) × 0,5, plus 5 par menace connue (plafond 20) quand un chantier est faisable ; fortification inconnue (zone jamais relevée) : 50 neutre (`Decisions.fortificationOf`, interface `LivingKnox.Fortification.levelOf`, [fortification.md](fortification.md) §6) |

Personnalité du chef : bonus par trait du chef (`CFG.TRAITS` : `nervous` +15 garde, `keenHearing` +5 garde, `tidy` +5 vie ordinaire et +10 fortification, `strong` +10 fortification, `smoker`/`drinker` +5 repos). Écart déterministe de −3 à +3 par (groupe, jour, objectif), pour que deux groupes semblables ne choisissent pas toujours la même chose. Menaces connues : menaces distinctes (zombie, joueur) qui ont fait réagir un membre ces 6 dernières heures (`THREAT_HOURS`), mémoire seulement. Le meilleur score l'emporte ; la raison écrite donne le score, ses facteurs et le second : `guard 62 (threats 2, hostility 90, leader nervous) > settle 31`.

Postes (`Decisions.assignDuties`, liste fermée `DUTIES`) : un membre blessé (blessure ≥ 50) a le poste `rest` ; puis `sentry` (guet : 1, ou la moitié du groupe pour `guard`) parmi les membres dont le rôle permet `guard`, `patrol` ou `defend` ; `carer` (soins, rôle qui permet `heal`) pour `heal` ; `forager` (rôle qui permet `scavenge`, `forage`, `expedition`, `raid` ou `scout`, la moitié du groupe au plus) pour `supply` ; `builder` (`fortify`, `maintain`) pour `fortify` ; les autres `rest` (objectif repos, ou nuit hors garde) ou `keeper` (au foyer). L'ordre des candidats tourne d'un jour à l'autre (rotation tirée de (groupe, jour)) : le guetteur change, la nuit est veillée à tour de rôle (I3.1). Les comportements permis par rôle sont ceux des fichiers de données des types (`LivingKnox.GroupTypes`, `roles[rôle].behaviours`, LK08-T02).

Journal : quand l'objectif ou un poste change, une entrée `objective` au journal du groupe (registre `LK_Groups`, LK10-T02 n'existant pas encore), texte anglais borné à 200 caractères : raison puis postes (`settle 31 > rest 15; sentry m-1, keeper m-2 m-3`). Persistance : `group.objective`, `member.duty` (champs facultatifs, schéma 1 inchangé). Un groupe qui se matérialise entre deux heures est noté à son premier passage.

### Cascade du membre (court terme, `Decisions.decide`, pur)

Priorités fixes `PRIORITIES` : **menace, peur, blessure, faim, soif, fatigue, poste du groupe, routine**. La première règle qui propose un comportement permis par le rôle l'emporte :

| Règle | Condition | Comportement |
|---|---|---|
| `threat` | (LK06-T02) combattant dont le groupe a une cible d'attaque parmi les joueurs vus (`Combat.targetFor`, [combat.md](combat.md)) ; sinon menace la plus proche : zombie vu ou entendu ; joueur vu ou entendu envers qui le groupe est `hostile` (fuite permise) ou `wary` (regard seulement) ; sans menace perçue, alerte du groupe en cours qui le concerne (LK05-T08, [alerte.md](alerte.md)) | LK06-T07 : `flee` si le membre a des **constantes mauvaises** (santé < `WOUND_RATIO`, peur ≥ 70) et une menace à 6 cases ou moins (`FLEE_DIST`), ou 12 cases s'il a peur (`FLEE_DIST_AFRAID`, LK05-T06) ; au foyer, `retreat` (abri) à la place ; membre valide de tout rôle : `watch` (« able member holds ») ; alerte du groupe : `alert` ; cible d'attaque : `fight`. LK06-T05 ([fuite-reddition.md](fuite-reddition.md)) : avant tout, `surrender` (non-combattant pacifique blessé par un joueur, ou acculé) puis `retreat` (membre en danger blessé ou combattant à bout de nerfs) ; cible de renfort après un coup reçu par un membre. LK05-T09 ([defense.md](defense.md)) : après la retraite, `defend` pendant une défense du foyer (`ctx.defense`) |
| `fear` | peur ≥ 70 (`NEED_HIGH`) | membre (tout rôle depuis LK06-T07) dont la source récente de la peur (`Needs.fearSource`, 10 min) est à 12 cases ou moins : `flee` à l'opposé ; sinon `rest` à l'abri au foyer |
| `hunger`, `thirst`, `fatigue` | jauge ≥ 70, 70, 80 (`NEED_HIGH`) | `home` (point de repas : repas abstrait au pas horaire de [besoins.md](besoins.md) en attendant LK05-T07), `home`, `sleep` (au foyer) |
| `wound` | santé de référence / santé de naissance < 0,5 | `rest` au foyer |
| `duty` | poste attribué | `sentry` → `guard` (si le rôle le permet), `rest` → `sleep` la nuit ou `rest`, autres postes → `chore` de jour si les routines sont chargées (LK05-T04), sinon `home` |
| `routine` | toujours | `chore` de jour si les routines sont chargées (LK05-T04), sinon `home` ; de nuit `rest` |

Une règle qui place le membre au foyer le renvoie d'abord au foyer (`home`) s'il en est loin (écart de plus de 10 cases en x ou en y, `HOME_RADIUS`, au-delà de la place d'un membre matérialisé, 8 cases ; ou autre étage). Combattant = rôle qui permet `fight` ou `defend` (`COMBAT_BEHAVIOURS`).

Comportements (liste fermée `BEHAVIOURS`) et consignes produites :

| Comportement | Vigilance (`Senses.setVigilance`) | Consigne LK03 |
|---|---|---|
| `home` | `rest` | loin du foyer : `moveTo` (marche) vers une case libre du bâtiment du foyer (`Materialize.placeFor`, 6 cases) ; au foyer : `stop` seulement s'il reste une de nos marches ouverte (fin d'une fuite) |
| `rest` | `rest` | idem |
| `sleep` | `sleep` | au foyer : routine de sommeil près d'un lit ([routines.md](routines.md), LK05-T03) ; loin : retour au foyer |
| `guard` | `guard` | `face` vers l'extérieur du foyer, ± 45° tirés ; rôle `guard`, `patrol` ou `defend` exigé |
| `patrol` | `guard` | ronde autour du foyer (LK05-T03, [routines.md](routines.md)) ; poste `sentry` à l'aube et la première heure d'un quart de jour ; mêmes rôles que `guard` |
| `chore` | `rest` | corvée visible au foyer, de jour (LK05-T04, [routines.md](routines.md), « Corvées ») ; loin du foyer : retour d'abord, comme `home` |
| `watch` | `guard` | `face` vers la menace ; nouvelle consigne si elle a tourné d'au moins 30° |
| `flee` | `guard` | `moveTo` (course) à 10 cases à l'opposé de la menace, ou à ±45°, ±90° si la case est prise (tout rôle depuis LK06-T07) ; à défaut, `face` |
| `alert` | `guard` | alerte du groupe (LK05-T08) : `face` vers la dernière position connue de la menace (nouvelle consigne si elle tourne d'au moins 30°), puis geste `guard` (membre valide) ou `crouch` (constantes mauvaises, LK06-T07 ; avant : selon le rôle) ; membre aux constantes mauvaises loin du foyer : `moveTo` (course) vers le foyer d'abord. Le même geste accompagne `watch` pendant une alerte ; il est retiré à la sortie de `alert`/`watch` |
| `fight` | `guard` | mêlée contre la cible (LK06-T02, `LivingKnox.Combat`) : `moveTo` (course) vers le joueur, puis `face` et geste `strike` à portée ; rôle `fight` ou `defend` exigé ; tout autre comportement met fin à la mêlée |
| `retreat` | `guard` | LK06-T05 : loin du foyer, `moveTo` (course) vers le foyer ; sans foyer, fuite pondérée par la proximité des menaces ; au foyer, `stop`, `face` vers la menace et geste `crouch` |
| `surrender` | `guard` | LK06-T05 : `stop`, `face` vers le joueur, geste `kneel` ; le groupe épargne ce joueur tant qu'il ne frappe plus |
| `defend` | `guard` | LK05-T09 : `LivingKnox.Defense.apply` : engagement depuis la place (laisse), sinon `moveTo` (course) vers le poste ou l'abri, `face` vers la menace, geste `guard` ou `crouch` |

États à échéance : un comportement dure jusqu'à son échéance en minutes de jeu (tirée : `watch` 1, `flee` 2, `alert` 2, `guard` 10 à 20, `home` 15 à 30, `rest` 20 à 40, `sleep` 30 à 60, `chore` 20 à 40). La cascade est réévaluée à chaque passage, mais l'état n'est remplacé qu'**à l'échéance** ou **sur interruption** : autre règle gagnante, autre comportement ou autre cible (`Decisions.replaces`). Un état gardé n'émet aucune nouvelle consigne (sauf le regard qui suit une menace). Exception (LK04-T05, [deplacement.md](deplacement.md), « Blocage et déblocage ») : une consigne de ce cadre close en échec `stuck` avance l'échéance (`LivingKnox.Movement.takeStuck`) ; la cascade décide de nouveau, et `Directives.moveTo` refuse à ce PNJ la case du blocage pendant 60 s.

Hasard déterministe : flux Park-Miller (`Decisions.stream`) tiré de l'identité du PNJ (`lk-<n>`), de la minute de jeu de la décision et du rang de la règle ; pour le groupe, de son numéro et du jour. Mêmes entrées, mêmes choix, mêmes échéances et mêmes raisons, quelle que soit la machine.

### Tout le monde se bat (LK06-T07, 2026-10-12)

Décision de l'utilisateur après un essai en jeu (groupe de colons : un combattant au poste, deux ouvriers accroupis aux abris, personne n'attaque le zombie dehors, un PNJ fuit en le voyant) : « Les cas où le PNJ s'enfuit doivent rester les cas où ses constantes vitales sont mauvaises et s'il est débordé. Tous les PNJs doivent pouvoir combattre, nous vivons dans un monde de survie comme The Walking Dead, et tout le monde se bat. »

- **Constantes mauvaises** (`Decisions.unfitOf`, pur, tout rôle) : santé de référence < `WOUND_RATIO` (0,5, seuil de la règle `wound`) **ou** peur ≥ `NEED_HIGH.fear` (70). Sinon le membre est **valide**.
- **Combat** : tout membre valide prend pour cible le zombie vanilla le plus proche à portée d'engagement (`Zombies.targetFor` : option `ZombieEngage<Rôle>` du rôle du membre, LK06-T14, ligne dégagée) et le combat (`fight`, mêlée avec l'arme qu'il porte, sinon mains nues, ou tir s'il a une arme à feu chargée : `Combat.weaponOf`). Un **joueur** reste la cible des seuls rôles qui permettent `fight` ou `defend` (attitude du groupe, `Hostility.chooseTarget`) ; un non-combattant vient aussi en renfort contre un **zombie** (demande d'aide, LK06-T05), jamais contre un joueur.
- **Membre valide face à une menace proche sans cible** (zombie hors de portée ou sans ligne dégagée) : `watch` (« able member holds »), plus de fuite.
- **Constantes mauvaises** : aucune attaque libre ; devant une cible, `retreat` (abri accroupi au foyer, retour en courant au foyer, fuite pondérée sans foyer) ; menace à `FleeDistance` (ou `FleeDistanceAfraid` s'il a peur) : `flee` hors du foyer, `retreat` (abri) au foyer ; peur sans menace perçue : fuite de sa source (règle `fear`), pour tout rôle. La retraite de LK06-T05 (santé < 35 %, peur ≥ 85) vaut désormais pour tout rôle.
- **Groupe débordé** hors de la défense du foyer (`Decisions.overwhelmedOf`, pur) : menace perçue pondérée (`Decisions.threatWeight` : zombie 1, joueur hostile 3, à `RetreatDangerDistance` cases au plus) > `DefenseWithdrawRatio` × membres valides du groupe, incarnés, au même niveau, à 20 cases au plus (`Decisions.ableNear`, le membre compris) → `retreat` (clé `overwhelmed`) ; il le reste tant que menace > (rapport − 1) × valides (hystérésis). Seulement pour un membre valide (un membre aux constantes mauvaises se retire déjà). Pendant une défense du foyer, le repli collectif de [defense.md](defense.md) s'applique à la place.
- **Défense du foyer** ([defense.md](defense.md)) : tout membre valide, quel que soit son rôle, est un défenseur aux postes (geste `guard`) ; les membres aux constantes mauvaises vont aux abris (geste `crouch`) et ne frappent qu'une menace au contact.
- **Alerte** : geste `guard` pour un membre valide, `crouch` aux constantes mauvaises (qui rentre d'abord au foyer s'il en est loin).
- Les rôles gardent : le poste de guet et la ronde, la sommation (LK11-T02), l'attaque d'un joueur, la reddition (non-combattants des groupes qui ne tirent pas le premier) et la montée de peur moitié moindre d'un combattant (LK_Needs).
- ⚠ **Décision à confirmer** (choix par défaut du contrat) : seuils des constantes = `WOUND_RATIO` et `NEED_HIGH.fear` ; débordé = rapport `DefenseWithdrawRatio` sur les membres valides de tout rôle ; un non-combattant se bat avec l'arme qu'il porte, sinon à mains nues ; un blessé au foyer s'abrite au lieu de s'y défendre (LK06-T05 disait « un blessé au foyer s'y défend »).
- ⚠ Peur : un ouvrier (×1) qui voit 4 zombies proches dans l'heure atteint 80 et cesse de se battre ; un combattant (×0,5) en supporte 7. À recalibrer en jeu.
- Tests : `tests/test_lk_fight_all.py` (pur : constantes, débordement et hystérésis, combat d'un ouvrier, joueur réservé aux combattants, retraite et fuite aux constantes mauvaises, défense prioritaire ; pile solo : ouvrier valide qui attaque un zombie loin du foyer puis se retire blessé, combattant seul débordé par quatre zombies, ouvrier à un poste de la défense qui frappe le zombie à sa fenêtre). Bancs adaptés à la nouvelle règle (ancienne règle figée) : `test_lk_decisions.py` (fuite selon le rôle, seuils de retraite, fuite pondérée, pile MP/solo, rejeu, expression Kahlua `KR-DECIDE` aussi dans `test_kahlua.py`), `test_lk_defense.py` (ouvrier aux postes, repli quand l'ouvrier prend peur), `test_lk_alert.py`, `test_lk_needs.py`, `test_lk_thresholds.py` ; suites en jeu `lk.defense` et `lk.alert` (texte).

### Seuils de danger réglables (LK05-T14, 2026-10-12)

Demande de l'utilisateur : sur un serveur très peuplé en zombies, les distances figées tenaient un groupe en alerte permanente. Constat dans le code d'avant : tout zombie vu ou entendu (perception jusqu'à 30 cases) devenait la menace de la cascade (`watch`, peur qui monte) ; l'alerte prenait un zombie à 10 cases du membre ou 15 du foyer ; le cri (15 cases) attirait d'autres zombies, qui relançaient l'alerte.

Options sandbox entières de la page Living Knox (`sandbox-options.txt`, libellés et infobulles `Translate/EN|FR/Sandbox.json`, unité « cases ») :

| Option `LivingKnox.*` | Bornes | Défaut | Avant (repli) | Lue par | Raison du défaut |
|---|---|---|---|---|---|
| `ZombieAlertDistance` | 1..30 | 10 | aucune limite | `Decisions.threatsOf`, `Alert.threatsOf`, `Defense.radii`, `Zombies.engageRange` | nouveau seuil : un zombie perçu à plus de 10 cases **du membre** est ignoré par la cascade (ni regard, ni fuite, ni retraite, ni peur), par l'alerte (même près du foyer) et par la défense ; 10 = ancien rayon de l'alerte près du membre, au-delà de la marche d'un zombie en quelques secondes |
| `AlertReach` | 5..60 | 20 | 30 (`Alert.CFG.REACH`, `Defense.CFG.REINFORCE_RADIUS`) | `Alert.reach`, `Defense.reinforceRadius` | prévient les membres autour du foyer (place des corps : 8 cases) sans tirer ceux d'une expédition proche |
| `AlertShoutZombie` | 1..30 | 10 | 15 (`Alert.CFG.SHOUT.zombie`) | `Alert.shoutRadius` | le cri attire les zombies : un rayon égal à la distance d'alerte n'en amène pas de plus loin ; intrus (20) et hostile (30) inchangés |
| `FleeDistance` | 1..20 | 4 | 6 | `Decisions.fleeDist` | (LK06-T07 : membre aux constantes mauvaises) un non-combattant ne court plus devant chaque zombie qui passe ; 4 cases laissent le temps de s'écarter |
| `FleeDistanceAfraid` | 1..30 | 8 | 12 | `Decisions.fleeDistAfraid` | même rapport (×2) que l'ancien couple 6 / 12, sous la distance d'alerte |
| `ZombieEngageDeputy`, `ZombieEngageFighter`, `ZombieEngageScout`, `ZombieEngageMedic`, `ZombieEngageWorker`, `ZombieEngageBreaker` (LK06-T14, une par rôle ; remplacent `ZombieEngageDistance`, défaut 4, retirée) | 1..15 | 10 | 10 (`Config.ZOMBIES.DEFEND_RANGE`, avant LK06-T14 : 5) | `Zombies.engageRange(npc)`, `Defense.engageRange` | décision de l'utilisateur du 2026-10-13 : un membre apte attaque les zombies jusqu'à 10 cases sans attendre le corps à corps, y compris en défense du foyer (zone autour de son poste) ; rôle d'un autre mod : `Fighter` ; jamais au-delà de `ZombieAlertDistance` |
| `DefenseRadius` | 3..30 | 8 | 12 (`Defense.CFG.THREAT_RADIUS`) | `Defense.radii` | le bâtiment et ses abords (foyer : 10 cases) ; zombies recensés au plus à `ZombieAlertDistance` cases du foyer |
| `DefenseWithdrawRatio` | 2..10 | 3 | 3 / 2 (`WITHDRAW_RATIO`, `HOLD_RATIO`) | `Defense.ratios` | inchangé ; retour aux postes à rapport − 1 (hystérésis gardée, d'où le minimum 2) |
| `RetreatDangerDistance` | 2..30 | 8 | 15 (`RETREAT.DIST`) | `Decisions.retreatDist` | un blessé ne fuit plus un zombie lointain ; sous la distance d'alerte |
| `ReinforcementRadius` | 3..50 | 15 | 20 (`HELP.RADIUS`) | `Decisions.helpRadius` | les renforts restent près de la victime (moins de combattants tirés hors du foyer) |
| `WarnHomeRadius` | 4..30 | 14 | 14 / 7 (`HOME_ZONE`, `HOME_SAFE`) | `Encounters.radii` | sommations d'un joueur : non liées aux zombies, inchangées ; sécurité = la moitié |
| `WarnGroupRadius` | 2..30 | 10 | 10 / 5 (`MEMBER_ZONE`, `MEMBER_SAFE`) | `Encounters.radii` | idem |

Lecture (`LK_Config.lua`, `Config.danger(nom, repli)`, `Config.zombieAlertDistance()`) : `getSandboxOptions():getOptionByName("LivingKnox.<nom>"):getValue()`, repli `SandboxVars`, à chaque appel (sondage : aucun événement ne suit un changement d'option et `SandboxVars` reste périmé en solo, base `load-warnings.md`) ; une valeur par décision, coût négligeable. Option absente (sandbox-options.txt non chargé : bancs, autre mod) : valeur d'avant LK05-T14, prise dans le `CFG` du module (les tests qui règlent un `CFG` restent valables) ; valeur invalide (non entière, hors bornes) : même repli et une ligne d'avertissement par valeur. Les seuils de besoin (`NEED_HIGH`) et les rayons propres aux joueurs (`NEAR_MEMBER`/`NEAR_HOME` des intrus et hostiles) ne sont pas des options.

Décision prise sans consigne du plan (la plus simple, à confirmer) : une seule option pour les rapports de la défense (retour = rapport − 1, au lieu de deux options) ; distances de sécurité des sommations = moitié du rayon ; la limite des zombies se mesure depuis le membre qui perçoit (la perception rend cette distance), le recensement de la défense la reprend autour du foyer.

### Seuils blessé et apeuré réglables (LK05-T16, 2026-10-12)

Décision de l'utilisateur (2026-10-12) : « Pour les seuils, il faut que ce soit des options de mod dans sandbox options ». Les deux constantes qui rendent un membre inapte au combat (LK06-T07, `Decisions.unfitOf`) deviennent des options entières de la page Living Knox, lues comme celles de LK05-T14 (`Config.danger`, table `Config.FITNESS` de `LK_Config.lua`, à chaque appel, valeur d'avant si l'option manque ou est invalide, une ligne d'avertissement par valeur invalide) :

| Option `LivingKnox.*` | Bornes | Défaut = avant (repli) | Lue par |
|---|---|---|---|
| `WoundedHealth` | 10..90 (pour cent de la santé de naissance) | 50 (`Decisions.CFG.WOUND_RATIO` 0,5) | `Decisions.woundRatio()` |
| `AfraidFear` | 30..100 (peur 0..100) | 70 (`Decisions.CFG.NEED_HIGH.fear`) | `Decisions.fearHigh()`, `Decisions.needHigh("fear")` |

Portée (décision prise sans consigne du plan, la plus lisible pour un administrateur, **à confirmer**) : une option = une notion, appliquée partout où le moteur employait la constante, et non à la seule inaptitude au combat. « Blessé » : inaptitude (`unfitOf`), règle `wound` (repos au foyer), combattant valide de la défense du foyer (`LK_Defense`, ancien `VALID_HEALTH` 0,5 retiré). « Apeuré » : inaptitude, fuite apeurée à `FleeDistanceAfraid` (règle threat), règle `fear` de la cascade (abri au foyer, fuite de la source), défense du foyer, membre écarté d'une expédition (LK05-T15, `Expeditions.needBlocker`), seuil affiché par la fiche admin. Restent des constantes : seuils de retraite (`RETREAT.HEALTH` 0,35, `RETREAT.FEAR` 85, corrections du moral bas), de reddition, autres envies (`NEED_HIGH.hunger/thirst/fatigue`) et `Needs.CFG.ENVY` (pas horaire hors écran). Ces seuils de retraite étant fixes, un `WoundedHealth` sous 35 ou un `AfraidFear` au-dessus de 85 laisse la retraite d'un membre en danger intervenir avant l'inaptitude (comportement voulu : la retraite garde ses propres seuils).

### Sortie, autorité et coût

- Autorité seule : le fichier s'arrête sur un client MP ; `tick` et `scorePass` refusent hors autorité. Les consignes passent par `LK_Directives` (bail, envoi aux proches, exécution par le propriétaire, suspension d'un corps sans client propriétaire).
- Une consigne **ouverte émise par un autre module** (suite de test, API) n'est jamais remplacée : le membre est ignoré tant qu'elle est ouverte (`stats.external`).
- Cadence : un passage au plus par seconde réelle (`PASS_MS`), au plus 4 membres évalués par passage (`MEMBERS_PER_PASS`, tour à tour), liste des membres incarnés refaite toutes les 5 s (`ROSTER_MS`, ou à chaque passage tant qu'elle est vide). Une évaluation lit une copie de la perception (au plus 4 joueurs et 6 zombies), la santé et l'attitude envers les joueurs connus, et émet au plus une consigne. Notation horaire : proportionnelle aux groupes matérialisés (au plus 64 groupes, 32 membres), une écriture du registre seulement si un objectif ou un poste change. Compteurs : `Decisions.stats` (`evaluated`, `decided`, `kept`, `issued`, `refused`, `external`, `maxPerPass`, `scored`, `objectiveChanges`).
- Besoins individuels (LK05-T06, [besoins.md](besoins.md)) : `LivingKnox.Needs.get(gid, mid)` → `{ hunger, thirst, fatigue, fear }` (0..100), jauges tenues par l'autorité dans le registre des groupes ; module absent ou valeur invalide : 0 (neutre). À chaque évaluation, la cascade transmet d'abord les menaces perçues (`Needs.perceive` : la peur monte aussitôt), lit les jauges et la source récente de la peur (`Needs.fearSource`), puis note le comportement retenu (`Needs.observe`, activité de l'heure pour le pas horaire des besoins).
- Alerte de groupe (LK05-T08, [alerte.md](alerte.md)) : à chaque évaluation, la perception du membre est transmise à `Alert.observe` (déclenchement une fois par menace, cri), puis `Alert.forMember` donne l'alerte qui le concerne (`ctx.alert`) ; chaque passage ferme les alertes retombées (`Alert.update`) ; une menace notée pour l'objectif du groupe (`knownThreats`) ne compte pas le comportement `alert` (déjà comptée chez le membre qui l'a vue) ; dormeur réveillé : `Alert.noteWoken`.
- Mémoire seulement : états des membres, consignes émises, menaces connues, gestes d'alerte posés, heure de la dernière notation ; un redémarrage les recalcule (la notation retrouve le même objectif sans nouvelle entrée de journal).

## Alternatives écartées

- **Arbre de comportement ou machine à états par PNJ** : plus expressif, mais coûteux à tenir reproductible et à borner ; la cascade fixe suffit au court terme décidé (décision du 2026-10-08).
- **Notation par utilité au niveau du membre** : réservée au groupe (long terme) ; au court terme, une priorité fixe est plus lisible et testable (une menace passe toujours avant la routine).
- **Décision chez le client propriétaire** (il connaît la perception) : refusée, autorité serveur (règle Living Knox) ; le client mesure, le serveur décide.
- **Une entrée de journal par décision de membre** : noierait le journal de 32 entrées ; les décisions de membre vont au journal du moteur (niveau debug) et dans `Decisions.get`, les objectifs au journal du groupe.
- **Même objectif pour un groupe hors écran** : la simulation abstraite (LK09-T01) garde sa propre tâche horaire ; les deux seront rapprochées quand les routines (LK05-T03 à T05) existeront.

## Idées reprises

- I1.1 (cascade de priorités fixe) : retenue, avec nos propres règles (menace, peur, blessure, besoins, poste, routine) ; ni arme braquée ni renfort (LK06) ; dernière position partagée par l'alerte (LK05-T08), sans recherche en spirale.
- I1.2 (comportements permis par rôle) : rôle = liste de comportements des fichiers de types (LK08-T02) ; registre fermé `BEHAVIOURS` avec conditions de rôle.
- I1.3 (états à échéance) : retenue (échéance en minutes de jeu, interruption par la cascade).
- I1.4 (hasard tiré d'une empreinte stable) : retenue (identité du PNJ et minute de jeu ; groupe et jour).
- I1.5 (budget de réflexion) : budget fixe par passage ; la modulation par la distance aux joueurs viendra avec LK13-T02.
- I1.6 (choix de tâche du groupe par priorités) : remplacé au niveau du groupe matérialisé par la notation d'utilité (synthèse recommandée) ; la simulation hors écran garde sa liste de priorités.
- I3.1 (veille de nuit, horaires décalés) : esquissée par la rotation quotidienne des postes et le guetteur de nuit.

## Tests

- Banc lupa (`tests/test_lk_decisions.py`, 20 tests) : champs `objective` et `duty` contrôlés à la relecture ; mêmes entrées → même décision, même raison et même échéance ; ordre de la cascade (menace avant peur, blessure, faim, soif, fatigue, poste, routine) ; fuite d'un non-combattant, regard d'un combattant, guet refusé à un rôle sans `guard` ; échéance et interruption ; besoins neutres puis fournis ; menaces d'après la perception et l'attitude ; objectifs et raisons (nuit, réserve basse, menaces, blessés, fortification, chef nerveux), écart borné et reproductible, postes selon rôles, blessures et rotation ; pile complète en MP (serveur + deux clients) et en solo : aucun module de décision chez les clients, objectif journalisé une fois, consignes `face`, `move` en course puis `stop` et retour au foyer à l'échéance, coût de 4 membres par passage, changement d'objectif horaire journalisé avec sa raison, même monde rejoué deux fois → mêmes états et même journal.
- VM Kahlua (`tests/test_kahlua.py`, `KR-DECIDE`) : décisions, scores et tirage identiques à lupa.
- LK05-T14 (`tests/test_lk_thresholds.py`, 17 tests) : options déclarées (bornes, défaut, page, traductions EN/FR avec l'unité) et identiques à `Config.DANGER` ; chaque seuil lu depuis son option, repli sans option, valeur invalide (une ligne d'avertissement), changement relu à l'appel suivant ; effets sur la cascade (fuite, peur), la retraite, les renforts, l'alerte (portée, zombies au-delà ignorés), la défense (rapport, recensement) et les sommations ; pile solo : groupe face à 50 zombies perçus au-delà de la distance d'alerte resté dans sa routine (aucune alerte, aucune règle `threat`, peur nulle), même foule sans l'option qui l'interrompt, zombie dans la distance qui donne l'alerte avec un cri au rayon de l'option. `test_lk_zombies.py` : portée d'engagement lue depuis l'option et bornée par la distance d'alerte. Suite en jeu `lk.alert`, second test (foule fictive au-delà de la distance d'alerte).
- En jeu : aucun pour l'instant (cible « hors jeu »). Protocole solo proposé dans le compte rendu de la tâche.

## Points ouverts

- ⚠ Valeurs de départ (scores, seuils, durées) à recalibrer en jeu.
- Vigilance de l'autorité transmise à l'exécutant MP par la consigne (champ `vg`, LK05-T03, voir [routines.md](routines.md)). Avec les routines chargées, `guard` va au poste de guet relevé (sinon regard vers l'extérieur) et la rotation des postes suit les quarts de 4 h (`Decisions.rotation`).
- Alerte de groupe (LK05-T08) : comportement `alert`, voir [alerte.md](alerte.md) ; ⚠ hors écran, aucune alerte.
- ⚠ PNJ rivaux non perçus (perception), donc jamais menace. Mêlée (LK06-T02, [combat.md](combat.md)) : un combattant dont le groupe a une cible d'attaque parmi les joueurs vus prend le comportement `fight` (règle `threat`, en tête ; vigilance `guard`, échéance 1 minute), mené par `LivingKnox.Combat` ; tout autre comportement y met fin. Sans cible d'attaque (avertissement, zombie), il regarde la menace sans l'attaquer.
- Postes `keeper`, `carer`, `forager`, `builder` : corvées visibles au foyer de jour (LK05-T04, poids selon le poste) ; ⚠ fortification LK14 à venir.
- Expédition (LK05-T05, [expeditions.md](expeditions.md)) : les fourrageurs d'un groupe `supply` partent avec `LK_Expeditions` ; un membre de l'équipe d'une expédition en cours (`ctx.trip`) prend le comportement `expedition` par la règle `duty`, quel que soit son poste du moment ; faim, soif et fatigue attendent le retour ; menace, peur et blessure passent avant.
- Vengeance (LK11-T05, [vengeance.md](vengeance.md)) : un membre de l'équipe d'une vengeance en traque ou au retour (`ctx.hunt`, `LivingKnox.Relations.memberHunt`, hors expédition) prend le comportement `revenge` (vigilance `guard`, échéance 10 minutes) par la règle `duty`, clé `hunt<n>` ; marche par étapes de 40 cases vers une ronde autour de la zone, ou vers le foyer au retour (`Relations.applyHunt`) ; faim, soif et fatigue attendent ; la cible vue est engagée par la règle `threat` (raison `revenge` du choix de cible).
- Raid (LK11-T07, [raids.md](raids.md)) : un éclaireur ou un pillard d'un raid à la base ou au retour (`ctx.hunt` par `LivingKnox.Raids.memberHunt`, kind `raid`) prend le même comportement `revenge`, raison `raid <n> hunt|back`, clé `raid<n>` ; ronde à 30 cases (éclaireurs) ou 2 cases (attaque) autour de la base, portes et barricades forcées en chemin par LK04-T04.
- ⚠ Retour au foyer : case libre du bâtiment du foyer cherchée dans 6 cases ; foyer non chargé : aucun déplacement.
