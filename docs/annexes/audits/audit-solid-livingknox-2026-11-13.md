# Audit SOLID et Clean Code : moteur Living Knox

| Champ | Valeur |
| --- | --- |
| Date | 2026-11-13 |
| Portée | `RadioSurvivor/Contents/mods/batman_LivingKnox/42.21/media/lua` : `server/LivingKnox`, `client/LivingKnox`, `shared/LivingKnox` (et `shared/RadioSurvivor/RS_LivingKnox.lua` seulement pour une dépendance) |
| Exclus | `tests/`, `dev/`, RadioSurvivor hors adaptateur, `Data/Stories.lua` (structure seulement) |
| Commit | non relevé (lecture seule, pas de `git` lancé) |
| Règles du projet | `Workshop/AGENTS.md`, `RadioSurvivor/docs/developpement.md` lignes 50-56 (SOLID : registre dès le troisième cas, interdiction de `if kind == ...` et des listes de noms dans un moteur). ADR lus par les zones A, C, D : `adr-registre-routines.md` (partiel) et `adr-separation-mods.md`. Les zones B, E, F, G, H ont lu peu ou pas les ADR (voir Limites). |
| Mesures | `wc -l` des 110 fichiers ; mesure des fonctions longues (grep `function`) sur les trois plus gros fichiers ; grep des chaînes `if x == "..."` ; grep des `require` ; pas de churn git (lecture seule, dépôt absent de la racine) |
| Lu en entier | zones A (Fortify), B (Decisions), C (Expéditions, Stock, Trade, Loot, Ammo, Materialize, Provisions), D (Obstacles), E (Combat, Defense, Raids, Homes, Hostility, Alert, CombatClient) ; F et G lus par blocs ; H lu en entier pour 17 fichiers sur 19 |

## Synthèse

Le moteur suit les bonnes intentions : les registres `Upkeep.registerJob`, `Routines.registerActivity`, `Decisions.registerExtension` et `Loot.registerContent` sont sains et servent de modèle. Mais la règle SOLID du projet (au troisième cas, extraire un registre) est enfreinte dans la plupart des zones : 34 constats P0 sont des chaînes `if kind == ...` de 3 cas ou plus, ou des listes de noms codées dans un moteur. Le problème est aussi transversal : presque chaque « genre » (aménagement, sorte de chantier, expédition, événement, corvée, requête de parole, fait public, opération d'admin, geste, cible) est énuméré à la main, et la plupart des modules se lient entre eux par `LivingKnox.X` lu à l'exécution avec une garde `nil`, ce qui crée des cycles invisibles. La plus forte opportunité : un **helper de registre commun** (`LivingKnox.Registry`, déjà réclamé par F-R10) puis la migration des « genres » vers des registres, module par module, en commençant par les chaînes P0 les plus utilisées.

| Gravité | Constats |
| --- | --- |
| P0 critique | 34 |
| P1 haute | 69 |
| P2 moyenne | 90 |
| P3 basse | 21 |
| **Total** | **214** |

Répartition par zone (identifiants des rapports d'agents conservés) : A Fortify 30 (3 P0, 9 P1) ; B Decisions 23 (6 P0, 7 P1) ; C Expéditions/Stock 30 (3 P0, 10 P1) ; D Obstacles 15 (3 P0, 4 P1) ; E Combat/Défense/Raids/Homes/Hostilité/Alerte 29 (2 P0, 12 P1) ; F Noyau et registres 25 (9 P0, 8 P1) ; G Social/besoins/santé/talk 19 (3 P0, 2 P1) ; H Shared/client 43 (5 P0, 17 P1).

Note sur les identifiants : chaque zone a son préfixe d'origine (`A01`, `C01`, `X01`, `OBS-01`, `F01`, `R-01`, `Z01`, `D-01`). Les `F01...` de la zone E ne sont pas le `F` de Fortify. Les `C01...` de la zone B ne sont pas la zone C.

### Les cinq qui comptent le plus

| # | Constat | Lieu | Effort | Gain |
| --- | --- | --- | --- | --- |
| 1 | Registre commun `LivingKnox.Registry` (register / list / get, politique unique de doublon) pour les quatre registres et tous les nouveaux | `Upkeep.lua:77-103`, `Routines.lua:486-497`, `Decisions.lua:809-835`, `Loot.lua:186-200`, `GroupTypes.lua:327-340` (R-10, F) | faible | une seule règle de doublon, un seul patron pour tous les genres |
| 2 | Extension de Decisions : 14 modules nommés en dur dans `Decisions.context` et chaîne `b == ...` de 5 cas dans `Decisions.apply` | `LK_Decisions.lua:1573-1633`, `1816-1909` (B-C02, B-C01) | moyen | ajouter un comportement ou un fournisseur de contexte sans toucher au moteur de décision |
| 3 | Registre des sortes de chantier Fortify (barricade, wall, palisade, repair) | `LK_Fortify.lua:1570-1577`, `88`, `1731`, `1784-1785`, `373-404` (A-A01 à A04) | moyen | une sorte de plus = un fichier ; supprime quatre tables de codes parallèles |
| 4 | Genres d'expédition (pêche, cueillette, bâtiment) par chaîne `t.kind == Ex.FISH` et `tryDepart` copié | `LK_Expeditions.lua:1062-1078`, `584-638`, `1348-1370` (C-X01, X02, X03) | moyen | `Expeditions.registerKind`, Food s'inscrit lui-même (supprime la dépendance `Ex` -> `LK_Food`) |
| 5 | Dépendances cycliques à l'exécution (Decisions <-> Defense / Encounters / Expeditions / Care ; Simulation <-> Relations <-> Raids ; Combat <-> Zombies ; Fortify <-> Stock / Simulation / Decisions) | `LK_Decisions.lua:1614-1617`, `LK_Simulation.lua:534-551`, `LK_Relations.lua:501`, `LK_Combat.lua:332`, `LK_Fortify.lua:2122-2130` (B-C12, F-R06, E-F23, A-A21) | moyen à fort | casser les cycles par publication d'événements (`LivingKnox.publish` existe) ; une modification de signature ne casse plus en silence |

### Gains rapides (faible effort, risque faible)

- Supprimer le paramètre mort `travelling` de `Guard.apply` (H-D41, `LK_ZombieGuard.lua:106-129`).
- Remplacer les `3600000` en dur par une constante `HOUR_MS` (G-Z19, `LK_Talk.lua:175`, `LK_Conversations.lua:109,117`, `LK_Initiatives.lua:143,150`).
- Centraliser le nom de module réseau `"LivingKnox"` (H-D42, dix copies plus deux littéraux).
- Supprimer les boucles d'initialisation de compteurs redondantes (E-F21, `LK_Combat.lua:164-176`, `LK_CombatClient.lua:85-97`, `LK_Alert.lua:76-77`, `LK_Raids.lua:88-89`) et créer un helper `count` (A-A25, H-D37).
- Supprimer les deux gardes doublées de `Fortify.applyPending` / `offscreen` (A-A27).
- Remplacer la liste `Obstacles` de passes par un enregistrement dans l'ordre (D-OBS-04) : mais voir P1 sur `pass()`.
- Supprimer le `pcall` autour de `Homes.applyAction` (E-F22, `LK_Homes.lua:683`) : le plus douteux de la zone E (voir Décisions à prendre).
- Constante partagée `HOSTILE_WEIGHT` / `RADIUS` (B-C19, `LK_Decisions.lua:183-187` dupliquent `Defense.CFG`).
- Retirer les références de tâches (`LK05-T07`, `E09-T05`...) du code, qui vont dans le plan (B-C23, D-OBS-15 pour les en-têtes de 163 lignes).
- Déplacer `Hostility.hookStats` en tête de fichier (E-F28, `LK_Hostility.lua:195`).

### Ordre de correction proposé (respecte les dépendances)

1. **Socle** : `LivingKnox.Registry` (R-10) ; `LK_Util` (`cheb`, `isInt`, `finite`, `angleGap`, `angleTo`, `HOUR_MS`) (E-F19, G-Z14, H-D27) ; `LivingKnox.Counters` (H-D37) ; `LivingKnox.Every` / cadence (H-D28) ; `NET_MODULE` (H-D42). Aucun changement de comportement.
2. **Casser les cycles par événements** : `Activity.hookAlert` triple inscription remplacée par `listen` (F-R22) ; `Bodies` diffuse `bodyDied` / `bodyReleased` / `bodyTick` (F-R11, H-D11) ; `Materialize` publie `memberReleased` au lieu d'appeler `Expeditions` (C-X25) ; `Decisions` cesse de lire `Defense` / `Encounters` / `Expeditions` / `Care` (B-C12) ; `Fortify` reçoit ses ports (A-A20, A-A21).
3. **Registres de genres**, par ordre d'impact :
   - `Decisions` : migrer `fight`, `defend`, `expedition`, `revenge`, `warn` vers `registerExtension` (B-C01, C03, C04, C06) ; `surrender`, `retreat`, `watch`, `alert` vers un fichier `Decisions/Defence.lua` qui s'inscrit lui-même. Le contrat `registerExtension` n'a qu'un utilisateur à ce jour (ProvisionMeal, vérifié).
   - `Routines` : corvées (F-R03, G-Z09), formes de plan (F-R02 `execPlan` `plan.kind`), gestes (H-D15).
   - `Simulation` : événements de groupe (F-R05), retours d'expédition (F-R06), horaire (F-R07).
   - `API` : faits publics (F-R08) ; `Admin` : opérations (F-R09, `Admin.OPS` existe déjà et ne sert pas au dispatch).
   - `Executor` : opérations `move` / `stop` / `face` (H-D01), escalades de `Movement` (H-D02), colonnes et champs de tri (H-D03, H-D04).
   - `Fortify` : sortes de chantier (A-A01 à A03), matériaux (A-A05, A-A06).
   - `Homes` : aménagements (E-F01). `Raids` : signes (E-F02) et phases (E-F03, E-F04). `Hostility` : règles de cible (E-F06). `Alert` : genres (E-F25). `Combat` : modes et genres de cible (E-F09, E-F11).
   - `Expeditions` : genres (C-X01, X02, X03, X07 phases), origines d'objets portés (C-X05).
   - `Stock` : catégories (C-X08, X17) et écarts (C-X21, un registre d'opérations).
   - `Talk` : genres de requête (G-Z01) et intents (G-Z02).
   - `Chatter` : sujets (G-Z08). `Guard` : neutralisations et dangers (H-D13). `Senses` : genres de cible (H-D09).
   - `Config` : chaque module porte son `CFG` (H-D19, F-R21). `Roles` et types de groupe enregistrés (H-D19, H-D20).
4. **Découper les gros fichiers** une fois les registres en place : `Obstacles` (2849), `Fortify` (2726), `Decisions` (2366), `Expeditions` (1506), `Stock` (1543), `Combat` (1259), `Directives` (1351), `Simulation` (1321), `API` (1151), `Groups` (1122), `Bodies` (1092), `Relations` (1103), `Senses` (977), `Admin` (962), `Executor` (906), `ZombieGuard` (682), `Load` (724), `Talk` (685), `Agreements` (743), `Health` (738).
5. **Protocoles et UI** (H-D14, H-D22, H-D24, H-D21) : `LK_Synced` pour les tables publiées, `LK_AdminClient` et `LK_UiKit` pour les cinq vues, `LK_Views` pour la navigation, `Store.registerSlot` pour `LK_Load`.

## Santé de l'architecture

- **Couches** : le sens des dépendances n'est pas respecté. Les modules `shared` lisent l'état d'exécutants `client` (H-D10, `LK_Senses.lua:319-342`) ; les modules bas niveau appellent les hauts (C-X25 `Materialize` -> `Expeditions`, F-R11 `Bodies` -> sept modules) ; l'API publique lit l'état interne de quatre modules (F-R15, `LK_API.lua:1121-1148`).
- **Contextes** : cycles relevés (tous à l'exécution, avec garde `nil`, donc invisibles à `require`) : Decisions <-> Defense / Encounters / Expeditions / Care / Needs ; Simulation <-> Relations ; Relations <-> Raids ; Raids -> Hostility -> Relations -> Raids ; Combat <-> Zombies ; Fortify <-> Stock / Simulation / Decisions ; Executor <-> Senses ; AdminView <-> DebugView <-> NpcSheet ; Directives <-> Bodies. L'arête la moins chère à casser : `Relations.revengeAgainst` appelé depuis `Hostility` (événement `revengeDue`), puis `Raids.memberHunt` appelé depuis `Relations` (événement déjà disponible via `LivingKnox.publish`).
- **Extension par les données** : presque tout nouveau contenu (genre, aménagement, corvée, événement, sujet, sorte de chantier, règle de cible, opération admin) exige aujourd'hui du code dans un moteur. Seuls `Loot.registerContent` (butin), `Upkeep.registerJob`, `Routines.registerActivity` (partiellement) et `Decisions.registerExtension` (un seul utilisateur) ont le bon patron.
- **Points chauds** : pas de churn mesuré (pas de dépôt git à la racine). Par la taille et le nombre de responsabilités : `LK_Obstacles.lua`, `LK_Fortify.lua`, `LK_Decisions.lua`, `LK_Expeditions.lua`, `LK_Stock.lua`, `LK_Combat.lua`, `LK_Simulation.lua`, `LK_Directives.lua`. Le churn réel (fichiers modifiés récemment) reste à relever sur le dépôt.
- **Lignes propres au projet** : garde `isClient()` et autorité serveur respectées partout où elles ont été lues (aucune violation trouvée, `LK_Combat.onHit` vérifie expéditeur, ordre, cadence, ligne de tir) ; aucun littéral non ASCII hors commentaire dans le code lu ; aucun `next(`, aucun `fonction.flag`, aucun `addXp`.

## Règles du projet

| Règle | Verdict | Constats |
| --- | --- | --- |
| « Au plus tard au troisième cas du même genre, extraire un registre ; interdit `if kind == ...` et listes de noms dans un moteur » (developpement.md 50-56) | **enfreinte** dans la quasi-totalité des zones | P0 : A01, A02, A03, B-C01, B-C03, B-C04, B-C05, B-C06, C-X01, C-X02, C-X05, D-OBS-01, D-OBS-02, D-OBS-03, E-F01, E-F02, F-R01 à F-R09, G-Z01, G-Z02, G-Z09, H-D01 à H-D05 |
| « Gardes nil pour l'optionnel seulement, pas de pcall généralisé » (AGENTS.md) | **enfreinte** (pcall englobant des corps entiers) | A-A28 (6 pcall), E-F22 (`Homes.applyAction` et autres), H-D35 (16 pcall), F-R11 (cinq pcall autour des abonnés), F-R18 |
| Gardes `LivingKnox.X ~= nil` pour des modules du même mod | **enfreinte en pratique** (dépendances cachées, cycles) | B-C13, A-A20, H-D16, G-Z13, F-R12 |
| Kahlua : aucun littéral non ASCII dans un `.lua` | respectée dans le code lu (accents seulement en commentaires) | aucun constat ; vérification non exhaustive (grep sur la zone, commentaires de fin de ligne ignorés) |
| Kahlua : pas de `next()`, pas de fonction traitée comme table | respectée | aucun constat |
| Serveur autoritaire ; client sans API d'autorité | respectée dans le code lu | aucun constat ; H-D10 et H-D07 sont des défauts de couplage, pas d'autorité |
| Messages console en anglais, texte joueur via `getText` | respectée dans le code lu | D-38 (langues codées dans les fragments de récits, zone non lue en entier) |

## Constats

Format condensé : chaque constat cite la zone, l'identifiant du rapport, la gravité, le principe ou smell, le lieu, la conséquence et la correction. La confiance est `certain` (lu et vérifié dans le code), `probable` (lu mais un élément est hors zone ou seulement vu par grep) ou `potentiel` (à confirmer). Un extrait a été copié dans le rapport de zone quand il était pertinent ; il n'est pas reproduit ici.

### P0 critique (34)

Règle normative du projet : chaîne de trois cas ou plus, ou liste de noms codée dans un moteur.

**Zone A, Fortify (3)**

- **A01** — OCP, Switch Statements. `LK_Fortify.lua:1570-1577` (`workOf`). Une sorte de plus (porte blindée, tranchée) oblige à éditer huit fonctions. Correction : `Fortify.registerKind{ id, code, work, unit, nextStage, remaining, applyOffscreen }`, un fichier par sorte (Kinds/barricade.lua, wall.lua, palisade.lua, repair.lua). Patron : `Upkeep.registerJob`. Confiance certaine (vérifiée : ligne 1570 confirmée).
- **A02** — OCP. Chaînes à trois branches sur `site.kind` et `site.target` (`1557`, `1539-1541`, `1992-1998`, `2440-2444`). Correction : même registre, plus `Fortify.registerRepair{ target, run }`. Certaine.
- **A03** — Shotgun Surgery. Quatre tables de codes parallèles (`88`, `1731`, `1784-1785`, plus `[bwp]` en dur dans `SITE_PATTERN`). Un code oublié casse la persistance hors écran sans erreur. Correction : dériver les tables du registre. Certaine.

**Zone B, Decisions (6)**

- **B-C01** — OCP, Switch Statements sur `b` dans `Decisions.apply` (`LK_Decisions.lua:1841-1909`, 97 lignes). Huit cas. Correction : migrer `fight`, `defend`, `expedition`, `revenge`, `warn` vers `registerExtension` (contrat `behaviour` + `apply` + `leave` déjà présent) ; `surrender`, `retreat`, `watch`, `alert` vers `Decisions/Defence.lua` qui s'inscrit lui-même. Certaine.
- **B-C02** — OCP, Divergent Change. `Decisions.context` (`1573-1635`, 66 lignes) nomme quatorze modules en dur (Routines, Expeditions, Relations, Senses, Combat, Zombies, Alert, Defense, Encounters, Needs, Bodies...). Correction : chaque module s'inscrit via `registerExtension` avec un hook `input`, avec une bande d'ordre explicite. Certaine. Décision à prendre : l'ordre entre champs de contexte (voir Décisions à prendre).
- **B-C03** — OCP. Cinq cas sur `b` dans `Decisions.decide` (`878-900`) pour l'angle de visée. Correction : `BEHAVIOURS[b].aim(ctx, rnd, key)`. Certaine.
- **B-C04** — OCP. Liste de six comportements dans le calcul du geste (`1821-1828`). Correction : chaque applicateur pose et retire son geste. Certaine.
- **B-C05** — OCP. Postes et objectifs codés en dur : `RULES.duty` (`748-763`), `DUTY_NEEDS` (`98-103`), `assignDuties` (`457-462`), `scoreObjectives` (`351-422`). Correction : registres `registerObjective` et `registerDuty`. Certaine (règle), ampleur probable.
- **B-C06** — OCP. `RULES.threat` (`639-695`) enchaîne six sous-règles dont l'ordre est l'invariant du jeu, mais il est invisible. Correction : liste ordonnée `THREAT_STEPS` ; une extension ne peut aujourd'hui s'insérer que avant toute la fonction (`before = "threat"`), ce qui ne suffit pas pour `warn` et `defend`. Certaine.

**Zone C, Expéditions et stock (3)**

- **C-X01** — OCP, `spotFor` (`LK_Expeditions.lua:1062-1078`) : chaîne `t.kind == Ex.FISH` / `Ex.FORAGE` avec sept autres sites. Correction : `Ex.registerKind{ id, pickTarget, spot, round, minutes, done, abstractRun, verb }`, un fichier par genre (Kinds/Building.lua, Forage.lua, Fish.lua). Certaine.
- **C-X02** — OCP + Long Method. `tryDepart` (`584-638`) copie deux blocs (pêche et cueillette) quasi identiques. Correction : boucle sur `Kinds.byPriority()`, le bâtiment en repli. Certaine.
- **C-X05** — OCP, `deliver` (`1191-1212`) : trois origines d'objets codées par deux drapeaux `e.a` / `e.f`. Correction : `Ex.registerCarrySource{ id, matches, make }`. Certaine (règle), modèle probable.

**Zone D, Obstacles (3)**

- **D-OBS-01** — OCP, Switch Statements sur le modèle d'itinéraire (sept modes : zombie, zombie-door, npc, detour, exit, exit-loose, trapped) dans `edgeCost` (`LK_Obstacles.lua:1532-1598`) et six autres sites (1649, 1656, 1675, 1707, 1908, 2065-2131). Correction : `Obstacles.Routing.registerModel(name, { edgeCost, maxNodes, ... })`, un fichier par modèle. Certaine (ligne 1536 vérifiée).
- **D-OBS-02** — OCP, nature d'obstacle (porte, fenêtre, clôture, mur) codée par `edgeElement` (`1487-1495`) et dix consommateurs ; paires parallèles `decide`/`decideWindow`, `setDoor`/`setWindow`, `check`/`checkWindows`, `closePass`/`closeWindowsPass`. Correction : `Obstacles.registerKind(name, { find, decide, set, blocks, closeDue, strike, cost })`. Certaine.
- **D-OBS-03** — OCP, politique de passage bloqué force / wait / detour (`1146-1153`, `1277-1298`, `1410-1454`) codée en trois endroits. Correction : `Obstacles.Blocked.registerPolicy`. Certaine.

**Zone E, Combat, Défense, Raids, Foyers, Hostilité, Alerte (2)**

- **E-F01** — OCP, `LK_Homes.lua:70-71`, `498-524`, `529-542`, `553-565`, `700-701`, `749-758`. Six aménagements (barricade, lamp, bed, crate, fire, tent) énumérés à sept endroits, plus un cas particulier pour la lampe. Correction : `Homes.registerFurnishing(kind, { plan, place, tag, clear })`, un fichier par sorte. Certaine (`LK_Homes.lua:71` vérifiée).
- **E-F02** — OCP, `LK_Raids.lua:58`, `87`, `299-336`. Quatre signes d'occupation (safehouse, generator, barricades, constructions) : `SIGNS` n'est jamais utilisé pour dispatcher ; la chaîne de score est écrite en dur. Correction : `Raids.registerSign(name, { weight, min, visit })`. Probable (chaîne `out.X >= seuil`, équivalente par effet).

**Zone F, Noyau et registres (9)**

- **F-R01** — OCP, `LK_Routines.lua:441-466` (`Routines.plan` : `guard`, `patrol`, `sleep`) et `123-130` (`sentryKind`). Correction : chaque activité fournit son `plan`, `runPlanned` appelle `activity.plan`. Certaine.
- **F-R02** — OCP, `LK_RoutineExec.lua:212-241` : `plan.kind` (face, sit, round, sinon) ; plus `plan.chore` (`189-198`). Correction : `Routines.registerPlanKind`. Certaine.
- **F-R03** — OCP, liste fermée `Routines.CHORES` (`LK_Routines.lua:31-33`) et `chorePlan` (`Routine_Chores.lua:222-243`). Six endroits à modifier pour une corvée (CHORES, CHORE_GESTURE, CHORE_DUTY, CHORE_ROLE, CHORE_TRAIT, avail). Correction : `Routines.registerChore`. Certaine.
- **F-R04** — OCP / DIP, `LK_RoutineExec.lua:253-276` : le moteur nomme `Upkeep` et `Fortify` dans `leave` et `forget`. Correction : la mémoire de routine porte sa fonction `release`. Certaine.
- **F-R05** — OCP, `LK_Simulation.lua:1060-1072` : cinq événements de groupe (departure, recruit, conflict, illness, clash). Correction : `Simulation.registerEvent`, un fichier par événement. Certaine.
- **F-R06** — OCP / DIP, `LK_Simulation.lua:534-551` : retours d'expédition par `place == "revenge"` / `"raid"`. Cycle Simulation -> Relations -> Simulation (`LK_Relations.lua:501`, `218`). Correction : `Simulation.registerExpeditionReturn`. Certaine.
- **F-R07** — OCP, `LK_Simulation.lua:1148-1163` : ordre des modules hors écran (Relations, Raids, Stock, Fortify) dans une boucle codée en dur, sans `require`. Correction : `Simulation.registerHourly{ id, order, run }`. Certaine.
- **F-R08** — OCP, `LK_API.lua:968-1003` : cinq genres de faits publics (created, died, left, removed, encounter), trois endroits à éditer par fait. Correction : table `FACT_HANDLERS`. Certaine.
- **F-R09** — OCP, `LK_Admin.lua:906-929` : dix opérations en `elseif op ==`, alors que `Admin.OPS` et `Admin.DEBUG_OPS` listent déjà les mêmes noms. La branche `else` avale les opérations inconnues. Correction : `Admin.OPS[op] = { debug, onNpc, run }`. Certaine.

**Zone G, Social et besoins (3)**

- **G-Z01** — OCP, `LK_Talk.lua:543-569` (`reply`) : six genres de requête (npc_talk, npc_enrich, npc_member, npc_incident, npc_initiative, npc_converse) avec un ordre significatif. Correction : `Talk.registerKind{ kind, validate, reply }`. Certaine.
- **G-Z02** — OCP, `LK_Talk.lua:547-552` et `478-499` : liste blanche d'intents codée en dur, plus une chaîne de quatre intents dans `talkReply`. Correction : `Talk.registerIntent{ id, kinds, validate, apply }`. Certaine.
- **G-Z09** — OCP, `Routine_Chores.lua:222-243` (`chorePlan`) : six cas de corvée + la table `avail`. Recouvre F-R03 : même correction. Certaine.

**Zone H, Shared et client (5)**

- **H-D01** — OCP, `client/LK_Executor.lua:350-372` (start), `129-137` (validEntry), `657`, `645` : opérations `move`, `stop`, `face` codées en dur. Correction : `Executor.registerOp(name, { validate, start, follow })`. Certaine.
- **H-D02** — OCP, `client/LK_Executor.lua:398-415` et `shared/LK_Movement.lua:247-268` : jeton de stratégie (`repath`, `unblock`, `fail`) réinterprété par une chaîne. Correction : `Movement.registerEscalation`. Certaine.
- **H-D03** — OCP, `client/LK_DebugView.lua:266-271`, `308-313`, `324-327`, `334-337` : une fonction `*Sort` par tableau, en chaîne `if key ==`. Correction : champ `sort` dans le descripteur de colonne. Certaine.
- **H-D04** — OCP, `client/LK_NpcSheet.lua:377-391` : `fieldValue` en chaîne sur `field`, plus `530`. Correction : descripteurs `Sheet.FIELDS`. Certaine.
- **H-D05** — OCP, `client/LK_AdminView.lua:105-134` : cinq cas sur `reply.op`, et les listes d'opérations des autres vues. `NpcSheet` fait de même (`243-255`). Correction : `AdminClient.onReply(op, handler)`. Certaine.

### P1 haute (69)

Ces constats rendent le prochain ajout plus cher. Les correctifs sont listés dans l'ordre de correction ci-dessus ; chaque ligne donne l'emplacement principal, la conséquence et la correction. Confiance certaine sauf mention.

**Zone A, Fortify (9)**
- **A04** `LK_Fortify.lua:373-404` (ringSite) — matériaux et entité recopiés au lieu de `STAGES`. Dériver du registre.
- **A05** `2029-2030` (offAvail) — liste de types codée (plank, nails, log, ties) ; un matériau comme `Base.Screws` diverge hors écran. Dériver des recettes.
- **A06** `1324`, `2074`, `1518`, `628`, `1072-1075` — cas spécial « clous = boîte de clous » copié cinq fois. `Materials/nails.lua`.
- **A13** `2424-2508` (applyPending, 85 lignes) — cinq responsabilités ; découper en `applyOps`, `applyBoxes`, `commitApplied`, `reportApplied`.
- **A14** `2137-2196` (offscreenHour) — boucle à cinq branches, six accumulateurs ; `canWorkOffscreen` partagé.
- **A20** `76-81` (requires) contre `621`, `777-781`, `1587`, `1629`, `2089`, `2647` — Stock, Defense, Decisions, Anim, Movement, Simulation lus à l'exécution avec garde. Ports injectés (`Fortify.bind{...}`).
- **A21** `2122-2130`, `2090` — cycles Fortify <-> Stock / Simulation / Decisions. Probable (modules lus seulement par grep).
- **A22** `2652`, `1971-1978`, `2474-2490`, `2283-2299`, `2620-2622` — Fortify lit `G.state.data`, hacke `G.update` pour obtenir un groupe mutable et écrit le champ `g.fort`. Extraire `Fortify/Store.lua`, demander à Groups une API `Groups.field(gid, "fort")`.
- **A24** tout le fichier (2726 lignes, douze responsabilités) — découper en `Fortify/` (Survey, Plan, Materials, Needs, Work, Kinds, Crew, Store, Offscreen, Queue).

**Zone B, Decisions (7)**
- **B-C07** `LK_Decisions.lua:1-2366` — sept responsabilités ; découper en `Decisions/` (Objectives, Cascade, Context, Defence, Apply, Contest), façade `Decisions`.
- **B-C08** `1040-1111` (scoreGroup, 74 lignes) — extraire `groupChanged`, `isScheduledChange`, `describeDuties`, `logObjectiveChange`.
- **B-C09** `1044-1049`, `1061-1062` — trois appels identiques à `assignDuties` ; extraire `dutiesFor`.
- **B-C10** `351-422` (scoreObjectives) — accumulateur `add`, bonus de traits, classement ; extraire `traitBonuses`, `rank`.
- **B-C11** `1802-1814`, `1954-1955` — Decisions écrit l'état de gestes d'Anim et appelle Needs sur `st.b`. Déplacer `setAlertGesture` vers Anim ; Needs s'abonne.
- **B-C12** `1614-1617`, `1845-1869` contre `LK_Defense.lua:85`, `LK_Encounters.lua:46`, `LK_Expeditions.lua:83`, `LK_Care.lua:38` — cycle Decisions <-> Defense / Encounters / Expeditions / Care. Certaine (cycle), conséquence silencieuse probable.
- **B-C13** garde `X ~= nil and X.f ~= nil` répétée près de trente fois dans Decisions (`571`, `920-921`, `1581-1617`, ...). Retirer les gardes pour les modules du même mod ; le reste passe par le registre. Probable.

**Zone C, Expéditions et stock (10)**
- **C-X03** (`LK_Expeditions.lua:227-228`, `988-990`, `1016-1017`, `1051`, `1127`, `1248`, `1348-1370`) — le genre est dispersé dans sept fonctions ; `Ex.DRAWN` disparaît avec le registre.
- **C-X04** (`94-95`, `463`, `584`, `599`, `1065`, `1073`, `1348`) — `Ex` recopie les identifiants de `LK_Food` et lit ses fonctions avec garde ; `LK_Food` s'inscrit lui-même.
- **C-X06** `LK_Expeditions.lua` (1506 lignes, dix responsabilités) — découper en `Expeditions/` (Record, Site, Depart, Phases, Containers, Deliver, Offscreen, Kinds/).
- **C-X07** `1107-1143`, `1412-1420` — machine d'états par chaînes de phase (`out`, `search`, `back`) ; `Phases[phase] = { active, span, step, onDue }`. Probable.
- **C-X08** `LK_Expeditions.lua:100-116` ; `LK_Stock.lua:108`, `120-126`, `130-137`, `143-165`, `175-182` — sept tables par catégorie à éditer pour une catégorie de plus ; `Stock.registerCategory`.
- **C-X09** `LK_Expeditions.lua:712-722`, `752-762` ; `LK_Stock.lua:354-366` — énumération de conteneurs et clé `"x,y,z,type,n"` fabriquée à trois endroits. Extraire `LK_Containers.lua`.
- **C-X10** `LK_Expeditions.lua:849-850`, `1215-1216` ; `LK_Stock.lua:433`, `890`, `1025`, `1304`, `1323` ; `LK_Trade.lua:314-338` ; et hors zone (Fortify, Traces, Relations, MissionRewards) — règle MP « annoncer le retrait et l'ajout de conteneur » recopiée une vingtaine de fois. Extraire `LK_Items.lua` (`remove`, `add`, `move`).
- **C-X17** `LK_Stock.lua:820-831`, `909-911`, `929-930` ; `LK_Expeditions.lua:840-841` ; `LK_Trade.lua:110` — comportements par nom de catégorie (food, water, medical). Polymorphisme via le registre de catégories.
- **C-X18** `LK_Stock.lua` (1543 lignes, onze responsabilités) — découper en `Stock/` (Categories, Reference, Containers, Supply, Takes, Offscreen, Scheduler).
- **C-X21** `LK_Stock.lua:262-264`, `309`, `1104`, `1179`, `1207`, `1229`, `1300` — types d'écart `take` / `add` testés à sept endroits. `Stock.registerOp` (probable). Décision à prendre : format persistant.

**Zone D, Obstacles (4)**
- **D-OBS-04** `LK_Obstacles.lua:2804-2830` (`pass`) — sept passes codées en dur, signatures hétérogènes ; `registerPass` ou `LivingKnox.Upkeep.registerJob`.
- **D-OBS-05** `LK_Obstacles.lua:1-2849` — une seule table, huit responsabilités ; extraire Keys, Homes, Routing, Blocked, Windows, Doors.
- **D-OBS-06** `LK_Obstacles.lua:2011-2300` (`planDoorRoute`, 290 lignes, imbrication de cinq) — extraire `chooseRoute` (cascade de stratégies), `Waypoints.thin`, `Routing.describe`.
- **D-OBS-08** `1184-1185`, `1310-1311`, `1954-1958`, `2335-2336`, `2380-2384` — lecture directe de `Directives.entries` (champs `op`, `done`, `v`), de `Decisions.state.members[..].b == "flee"`, de `Groups.peek`. Une renommée de champ casse les obstacles sans erreur. Hide Delegate : `Directives.openMove(id)`, `Decisions.isFleeing(id)`.

**Zone E, Combat, Défense, Raids, Foyers, Hostilité, Alerte (12)**
- **E-F03** `LK_Raids.lua:84`, `591-662`, `666-689`, `695-700`, `740` — machine d'états par `r.phase` ; `offscreenHour` (70 lignes) ; `PHASE_HANDLERS`.
- **E-F04** `LK_Raids.lua:530-586` — booléen `scouting` (flag argument), six `if scouting` ; table de stades.
- **E-F05** `LK_Raids.lua:597`, `741` ; `LK_Simulation.lua:542` ; `LK_Decisions.lua:741-743` ; `LK_Relations.lua:698-704`, `897-908` — chaîne `place == "raid"` ; cycle Raids <-> Relations. Probable (hors zone, lu par grep). Note : un ADR pourrait trancher, non vérifié.
- **E-F06** `LK_Hostility.lua:624`, `627-628`, `691-702`, `732-736` — règles de cible en chaîne ; `Hostility.registerRule`.
- **E-F07** `LK_Hostility.lua:62-76`, `232-377`, `381-601`, `603-761` — format de sauvegarde (LKATT1), attitudes et ciblage dans un seul fichier de 770 lignes. Probable. Persistance : décision à prendre.
- **E-F08** `LK_Alert.lua:129-156` ; `LK_Defense.lua:421-460` ; `LK_Hostility.lua:749-761` ; `LK_Combat.lua:473-486` — quatre énumérations indépendantes de menaces (zombie, joueur). Probable.
- **E-F09** `LK_Combat.lua` (plusieurs), `LK_Defense.lua:675`, `693`, `706`, `840`, `LK_CombatClient.lua:268`, `295`, `307` — deux genres de cible testés à quinze endroits dans deux représentations (`o.k`, `tg.kind`). `Combat.registerTarget`. Certaine.
- **E-F10** `LK_Combat.lua:1-1259` — décision, exécution, validation, rendu et réseau dans un seul fichier. Découper en `LK_CombatGeometry`, `LK_CombatBallistics`, `LK_CombatReports`, `LK_CombatWire`, `LK_CombatEffects`.
- **E-F11** `LK_Combat.lua:100`, `386-392`, `422`, `429`, `883`, `907`, `1104-1126` ; `LK_CombatClient.lua:73`, `378-379` — mode `ranged` / melee dispersé en neuf sites. `Combat.registerMode`.
- **E-F12** `LK_Defense.lua:674-676` ; `LK_CombatClient.lua:177-183` — lecture de la table `Combat.orders` (champs `o.k`, `o.zt`, `o.leash`) depuis l'extérieur. `Combat.engagedTargetOf(id)`.
- **E-F13** `LK_Defense.lua:662-771` (`targetFor`, 110 lignes, quatre `return` précoces) — chaîne de règles ; `Defense.targetRules` (liste de stratégies).
- **E-F14** `LK_Defense.lua:315-351` et `391-416` (`shelters`, `campShelters`) — même tri et même plafond ; Strategy `building` / `camp`.

**Zone F, Noyau et registres (8)**
- **F-R10** `LK_Upkeep.lua:77-103`, `LK_Routines.lua:486-497`, `LK_Decisions.lua:809-835`, `LK_Loot.lua:186-200`, `GroupTypes.lua:327-340` — même code de remplacement quatre fois, politique de doublon différente pour GroupTypes (refus). `LivingKnox.Registry.new{...}` avec une politique unique et un avertissement à l'écrasement. Certaine. **Socle à faire en premier.**
- **F-R11** `LK_Bodies.lua:1033-1092`, `813-851`, `903-920` — `Bodies` appelle Health, Loot, Materialize en dur, avec un `pcall` répété ; `LivingKnox.publish("npcDied")` existe déjà (LK_Core.lua:107, signalé par l'agent F) ; proposer `bodyDied` / `bodyReleased` pour les autres cas. Certaine.
- **F-R12** `LK_Simulation.lua:62-1321` — une seule table : RNG, config d'expédition, simulation horaire, cinq événements, avance, ordonnanceur. Découper (`Scheduler`, `SimRandom`, `SimExpedition`, `Events/`).
- **F-R13** `LK_Directives.lua:886-1010` (`onReport`, 125 lignes), `1311-1322` (chaîne de commandes réseau), `1012-1220` (transfert de propriétaire) — découper en `LK_DirectivePath`, `LK_DirectiveOwner`, `Directives.COMMANDS`.
- **F-R14** `LK_API.lua:262-430`, `606-920`, `925-1076` — quatre domaines derrière un seul nom public. Découper en `API/` (Stories, Supply, Events), façade conservée.
- **F-R15** `LK_API.lua:1121-1148` — quatre raisons codées, accès direct à `Co.orders`, `En.state.list`, `B.lastHits`. `API.registerEngagedReason`.
- **F-R16** `GroupTypes.lua:53-61` contre `Decisions.lua:809-835` — un comportement déclaré par extension est refusé par `behaviourOk` de GroupTypes ; deux listes à tenir. Probable.
- **F-R17** `LK_Server.lua:20-170` — vingt abonnements `EveryHours` centralisés ici, alors que trente autres fichiers s'abonnent eux-mêmes. Chaque module s'abonne dans son fichier.

**Zone G, Social et besoins (2)**
- **G-Z03** `LK_Talk.lua:1-685` — file, persistance, validation, décisions de groupe, polling dans un seul fichier. Découper en `LK_Talk_Queue`, `LK_Talk_Store`, `LK_Talk_Group`, plus les fichiers par genre.
- **G-Z04** `LK_Talk.lua:293-306` (`decisionFact`, `NEED_WORDS`) — liste de besoins et trois genres de décision codés en dur ; `DECISION_FACTS[kind]`, `NEED_WORDS` lu depuis `LK_Stock.CATEGORIES`.

**Zone H, Shared et client (17)**
- **H-D06** `client/LK_Executor.lua` (906 lignes, sept responsabilités ; `follow` 135 lignes) — découper en `ExecutorNet`, `BodyProbe`, `MoveFollow`, `StateReporter`.
- **H-D07** `client/LK_Executor.lua:677-688`, `697-713`, `786-821` — perception, rapport au sol, rapports d'état et remise d'équipement câblés en dur ; écriture dans `Equipment.remote` depuis l'Executor. `Executor.registerPass`, `Equipment.applyHandover`.
- **H-D08** `shared/LK_Senses.lua` (977 lignes, cinq responsabilités) — découper en `LK_SensesModel`, `LK_SensesScan`, `LK_SensesAuthority`, `LK_ZombieFloor`.
- **H-D09** `shared/LK_Senses.lua:393-401`, `489-515`, `527-539`, `679`, `772-791` — genres de cible (player, zombie) en `if`. `Senses.registerTargetKind`.
- **H-D10** `shared/LK_Senses.lua:319-342` ; `client/LK_Executor.lua:678-684` — un module `shared` lit `Executor.remote.d` (client). Cycle Executor <-> Senses. Pose et activité vers un module neutre. Certaine.
- **H-D11** `shared/LK_Anim.lua:257-275` (`knownBodies`) — registre des corps dans Anim, lit `Bodies.bound` et les internes de `ZombieGuard`. Déplacer vers `BodyRegistry.known()`.
- **H-D12** `shared/LK_ZombieGuard.lua` (682 lignes, cinq responsabilités) — découper en `LK_BodyOwnership`, `LK_GuardNeutralize`, `LK_GuardRoster`, `LK_GuardAdopt`.
- **H-D13** `shared/LK_ZombieGuard.lua:235-262`, `269-286` — neutralisations et dangers codés en dur ; `Guard.registerNeutralizer`, `Guard.registerHazard`.
- **H-D14** `shared/LK_ZombieGuard.lua:325-390` ; `shared/LK_Equipment.lua:320-393` ; `shared/LK_Anim.lua:202-227` ; `client/LK_Executor.lua:185-210` — protocole « table publiée + rev + hello » recopié quatre fois. `LivingKnox.Synced.new{...}`. Certaine.
- **H-D15** `shared/LK_Anim.lua:42-60` ; `shared/LK_Equipment.lua:55` ; `shared/LK_Config.lua:435` — liste des gestes éclatée (vingt gestes). `Anim.registerGesture{ name, holdsWeapon, keepOnRelay, act, clip }`.
- **H-D16** `shared/LK_Equipment.lua` (556 lignes, cinq responsabilités) — découper en `EquipmentRegistry`, `EquipmentServer`, `EquipmentDisplay`, `EquipmentForeign`, `Compat`.
- **H-D17** `shared/LK_Appearance.lua:263-264`, `277-291`, `311-316`, `403-414`, `447-453` — schéma d'un vêtement dans cinq fonctions ; table de descripteurs de champ.
- **H-D18** `shared/LK_Identity.lua:236-252`, `104-105` — validateur central qui connaît les champs des autres modules. `Identity.registerField(name, validator)`.
- **H-D19** `shared/LK_Config.lua` (480 lignes, réglages de douze modules) — `Config.register(namespace, defaults, bounds)` ; `LivingKnox.Roles.register{...}` (six éditions pour un rôle).
- **H-D20** `shared/LK_GroupTypes.lua:53-63` ; `server/LK_Decisions.lua:97-131` — listes de comportements réservés dupliquées entre deux modules. Probable (Decisions lu seulement sur 97-131).
- **H-D21** `shared/LK_Load.lua:400-438`, `537` — l'outil de mesure connaît la structure interne de trois registres et des champs de groupe. `Store.registerSlot`.
- **H-D22** cinq vues client (`LK_NpcSheet.lua:35-258`, `LK_AdminView.lua:28-289`, `LK_DebugView.lua:39-446`, `LK_TradeView.lua:25-219`) — transport, constantes copiées (synchronisées par des tests), `canUse`, `button` recopiés. TradeView teste `isAuthority()` là où les autres testent `isClient()` (divergence déjà présente). `LK_AdminClient` et `LK_UiKit`.

## Décisions à prendre

Ces corrections changent un format persistant, un contrat public ou une garde de sécurité : elles ne sont pas des refactorings sans risque, et l'auteur doit trancher.

1. **Format persistant des écarts de stock** (C-X21, C-X20) : passer les écarts `take` / `add` en registre change le schéma sauvé. Brouillon : « Les écarts de stock sont désormais décrits par un registre d'opérations ; le format sauvé est inchangé ou versionné ainsi : ... ». À trancher : format inchangé, ou nouvelle version.
2. **Suppression de la compatibilité du format 1 de Fortify** (A-A26) : `FORT_FORMAT_OLD`, `migrate` et la branche `validView` (environ 120 lignes). À retirer seulement si le mod n'est pas publié (règle mémoire : pas de format versionné ni de reprise avant publication). Décision à prendre : publié ou non.
3. **Persistance des attitudes Hostility** (E-F07) : découpage du fichier LKATT1 ; même question de format.
4. **Gardes `pcall`** (A-A28, E-F22, H-D35, F-R11, F-R18) : la règle AGENTS interdit le `pcall` généralisé, mais LK13-T11 et E18-T34 ont motivé des protections. À arbitrer avec l'auteur pour chaque site : supprimer, ou limiter à l'appel Java incertain.
5. **Ordre des champs de contexte dans `Decisions.context`** (B-C02) : l'ordre entre perception, cible, alerte, défense, besoins est une dépendance réelle. Décision : bandes d'ordre explicites (proposition) ou passage d'`overwhelmed` en extension tardive.
6. **Contrat public de l'API** (F-R14) : le découpage de `LK_API.lua` touche les mods tiers qui lisent ce fichier. Décision : conserver la façade, ou versionner l'API.
7. **Routage hors écran et tests à graine fixe** (D-OBS-01, D-OBS-06) : tout changement d'`edgeCost` ou du plan de route change les résultats aux graines de test. Décision : figer les résultats avant refactoring, ou accepter une nouvelle référence.

## Écartés

| Signal | Lieu | Raison |
| --- | --- | --- |
| Liste `Obstacles`, « W » / « N » en chaîne | `LK_Obstacles.lua:260, 272, 750, 817` | Valeurs binaires, sans enjeu OCP (agent D) |
| `LK_Stand.lua` (154 lignes) | `shared/LivingKnox/LK_Stand.lua` | Une seule responsabilité, pas de constat (agent H) |
| `LK_Loot.registerContent` | `LK_Loot.lua:186-200` | Registre conforme, modèle à garder (agent C, F) |
| `LK_Upkeep.registerJob` | `LK_Upkeep.lua:77-103` | Ouvert, validé, modèle à garder (agent F) ; ses réserves (remplacement silencieux, `release` non déclaré) sont listées en F-R10 |
| `LK_Routine_Watch.lua`, `LK_Routine_Sleep.lua` | `server/LivingKnox/Routines/` | Bonnes inscriptions via `registerActivity` (agent G) ; relais vers `runPlanned` à corriger en F-R01 |
| `LK_Journal.lua` | `LK_Journal.lua:34-43` | Déjà piloté par table (`KINDS`, `TECH`) ; pas de chaîne de genre (agent G) |
| `LK_Agreements` `KIND_RANK`, `DECISION`, `INCIDENT_FACT` | `LK_Agreements.lua:397`, `472`, `672-690` | Tables ; seule la fin de `decideIncident` a une chaîne à deux cas, sous le seuil (agent G) |
| Séparation des mods, registres Upkeep / Routines / Decisions / Loot | `adr-separation-mods.md`, `adr-registre-routines.md` | Décisions acceptées ; le constat porte sur ce qu'elles n'ont pas couvert (les genres à l'intérieur des moteurs) |
| Garde `isClient()` et autorité serveur | `LK_Combat.onHit`, `LK_Fortify.lua:74`, `LK_Obstacles.lua:164` | Conformes (agents A, D, E, H) |
| `pcall` dans `LK_Core.publish` | `LK_Core.lua` | Isolation d'abonné, défendable (agent F) |

## Limites

- **Vérification contradictoire non faite.** La méthode du skill exige, pour chaque P0 et P1, un vérificateur distinct qui tente de réfuter le constat. Ce passage n'a pas été lancé (103 constats P0 et P1). Les P0 sont classés selon la règle du projet ; certains reposent sur une lecture partielle. Avant tout ADR, relire les P0 au moins une fois.
- **Lecture partielle.** Les zones F, G et H n'ont pas lu en entier certains fichiers (`LK_Relations` 500-750, `LK_Routines` corps des jobs, `LK_Relay` au-delà de `sizeOf`, `LK_API` missions 606-920, `LK_Stories`, `LK_Traces`, `LK_Food`, `LK_Garden`, `LK_Encounters`, `LK_Reports`, `LK_Observations`). Les constats qui en dépendent sont marqués probable ou potentiel dans les rapports d'agents.
- **Lecture des règles incomplète.** Plusieurs zones n'ont pas relu `docs/developpement.md` (hors lignes 50-56), ni les ADR en entier, ni les références du skill. Des constats peuvent être déjà tranchés par une décision non lue (en particulier E-F05 sur les expéditions, et les registres de la zone F). Le croisement avec les ADR est à faire.
- **Pas de churn.** Aucun historique git relevé : le classement par impact × churn × effort n'est pas fait. Il faut le relever dans le dépôt de `batman_LivingKnox` (non trouvé à la racine de `RadioSurvivor`).
- **Non lancé.** Aucun test, lint ni build : conforme à la consigne lecture seule.
- **Commande de vérification refusée.** Une commande `grep` de vérification a été refusée par le classifieur automatique (un hook a modifié son entrée) : je ne l'ai pas relancée. Les références clés ont été vérifiées avec l'outil Grep à la place (Fortify 1570, Obstacles 1536 et 1649, Decisions 1573 et 1816, Homes 71, Raids 87, Chores 222, `registerExtension` utilisé uniquement par Decisions et ProvisionMeal).
- **Constats à ne pas corriger sans trancher** : voir la section « Décisions à prendre ».

## Annexe : fichiers lus

- **Zone A** (lu en entier) : `server/LivingKnox/LK_Fortify.lua`.
- **Zone B** (lu en entier) : `server/LivingKnox/LK_Decisions.lua` ; lignes 50-56 de `RadioSurvivor/docs/developpement.md`.
- **Zone C** (lu en entier) : `LK_Expeditions.lua`, `LK_Stock.lua`, `LK_Trade.lua`, `LK_Loot.lua`, `LK_Ammo.lua`, `LK_Materialize.lua`, `LK_Provisions.lua`, `LK_ProvisionMeal.lua`.
- **Zone D** (lu en entier) : `server/LivingKnox/LK_Obstacles.lua`.
- **Zone E** (lu en entier) : `LK_Combat.lua`, `LK_Defense.lua`, `LK_Raids.lua`, `LK_Homes.lua`, `LK_Hostility.lua`, `LK_Alert.lua`, `client/LivingKnox/LK_CombatClient.lua`.
- **Zone F** (lu par blocs) : `LK_Upkeep.lua`, `LK_Routines.lua`, `LK_RoutineExec.lua`, `LK_Activity.lua`, `LK_Load.lua`, `LK_API.lua`, `LK_Admin.lua`, `LK_Simulation.lua`, `LK_Server.lua`, `LK_Groups.lua`, `LK_Relations.lua`, `LK_Directives.lua`, `LK_Bodies.lua`, `LK_Relay.lua`, `shared/LK_Config.lua`, `shared/LK_Identity.lua`, `shared/LK_GroupTypes.lua`.
- **Zone G** (lu par blocs ou par grep structurel) : `LK_Talk.lua`, `LK_Care.lua`, `LK_Needs.lua`, `LK_Death.lua`, `LK_Journal.lua`, `LK_Agreements.lua`, `LK_Conversations.lua`, `LK_Initiatives.lua`, `LK_Chatter.lua`, `LK_Zombies.lua`, `LK_Health.lua`, `LK_Stories.lua`, `Routines/LK_Routine_Chores.lua`, `Routines/LK_Routine_Meal.lua` ; survolés : `LK_Speech`, `LK_Food`, `LK_Garden`, `LK_Traces`, `LK_PersonalRelation`, `LK_TalkAlone`, `LK_Reports`, `LK_Observations`, `LK_ObservationTriggers`, `LK_Encounters`, `LK_MissionRewards`, `LK_Incidents`, `LK_Store`, `LK_Sites`.
- **Zone H** (lu en entier) : `client/LK_Executor.lua`, `LK_NpcSheet.lua`, `LK_AdminView.lua`, `LK_DebugView.lua`, `LK_SpeechView.lua`, `LK_TradeView.lua` ; `shared/LK_Senses.lua`, `LK_ZombieGuard.lua`, `LK_Equipment.lua`, `LK_Appearance.lua`, `LK_Movement.lua`, `LK_Anim.lua`, `LK_Stand.lua`, `LK_Config.lua`, `LK_Load.lua`, `LK_Identity.lua`, `LK_GroupTypes.lua` ; survolés : `shared/Data/Stories.lua` (structure), `client/LK_RelationsView.lua` (1-60).
