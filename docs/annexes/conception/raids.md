# Raids des groupes pillards sur les bases des joueurs

- Tâche : LK11-T07 (création) ; décision datée du 2026-10-08 (`docs/annexes/plans/LK11-interactions-joueurs.md` : raids **rares et annoncés**, base repérée par ses signes d'occupation, éclaireurs qu'on peut éliminer pour annuler le raid, attaque par l'effectif réel parti du foyer pillard, fréquence réglable et désactivable). S'appuie sur LK11-T05 ([vengeance.md](vengeance.md) : trajet abstrait, apparition à distance, marche), LK11-T03 ([attitude.md](attitude.md)), LK09-T01/T02/T03 ([simulation.md](simulation.md), [corps-registre.md](corps-registre.md)), LK04-T04 (forçage, [deplacement.md](deplacement.md)), LK06-T01 ([cibles.md](cibles.md)), LK11-T04 ([parole.md](parole.md)), LK05-T14 (options sandbox)
- Code : `media/lua/server/LivingKnox/LK_Raids.lua` (`LivingKnox.Raids`, autorité). Partagé avec la vengeance (modifications de `LK_Relations.lua`, sans changement de comportement) : `Relations.travelHours`, `livingTeam`, `turnBack`, `delayReturn`, `embodyTeam` (corps à distance des joueurs, extrait de `huntPass`), `say`, `memberHunt` (repli vers `Raids.memberHunt`), `applyHunt` (rayon de ronde `hu.patrol`, mémoire par genre). Branchements : `LK_Simulation.lua` (`Raids.offscreenHour` après la vengeance, `Raids.raidReturn` au retour de l'expédition `raid`), `LK_Decisions.lua` (raison `raid <n> <phase>` et clé `raid<n>` de la règle `duty`), `LK_Config.lua` (`Config.raids()`), `sandbox-options.txt` (`LivingKnox.RaidsEnabled`, `LivingKnox.RaidDays`), `Translate/EN|FR/Sandbox.json`, réplique `IGUI_LK_Raid_Scouted` (`IG_UI.json`). Banc `tests/test_lk_raids.py` ; suite en jeu `lk.raid` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKRaid.lua`)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\`) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement

Idée de jeu : I9.7 ([idees-bandits-alife.md](../recherches/idees-bandits-alife.md)). Aucune ligne de Bandits! ni de Project A-Life n'a été lue pour cette tâche ; aucun pillard n'est créé de rien ni ne surgit près d'un joueur.

## Problème

Un groupe pillard doit pouvoir découvrir qu'un joueur s'est installé quelque part, envoyer d'abord quelques-uns de ses membres voir de près, puis, si ces éclaireurs reviennent, attaquer avec ses propres membres. Le joueur peut deviner ce qui se prépare (éclaireurs aperçus, réplique) et l'empêcher en tuant les éclaireurs. Les raids restent rares, réglables et désactivables. Tout est décidé par l'autorité et survit au redémarrage.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `SafeHouse.getSafeHouse(case)` rend le premier refuge dont le rectangle contient la case (`x` dans `[getX, getX2)`), sans test de compte quand aucun nom n'est passé. | `J/iso/areas/SafeHouse.java:137-150, 184-200` | confirmé statiquement |
| `sq:getBuildingDef()` passe par la pièce : `nil` dehors ; `BuildingDef:getX2/getY2` exclusifs, `getMaxLevel`, `getIDString`. | `J/iso/BuildingDef.java:92, 189-219` ; base `world-placement.md` | confirmé statiquement |
| `IsoGenerator:isActivated()` ; aucun index des générateurs : balayer les cases chargées. | `J/iso/objects/IsoGenerator.java:458` ; base `power-and-lights.md` | confirmé statiquement |
| Ouvertures barricadables (`IsoDoor`, `IsoWindow`, `IsoWindowFrame`, `IsoThumpable`) : `isBarricaded()`. | base `barricades-and-constructions.md` (« Relever depuis Lua les ouvertures barricadables ») | confirmé statiquement |
| Le jeu barricade lui-même des maisons (cachettes, histoires de bâtiment) et pose des `IsoThumpable` (cachettes, établis d'histoire) : ces signes seuls ne prouvent pas un joueur. | `J/core/stash/StashSystem.java:250-265, 314` ; `J/randomizedWorld/randomizedBuilding/RandomizedBuildingBase.java:481-500` ; `J/randomizedWorld/RandomizedWorldBase.java:1426-1428` ; `RBBasic.java:160` | confirmé statiquement |
| Les lumières des pièces sont allumées au hasard au chargement des cartes (une pièce sur deux ou sur quatre) tant que le réseau fonctionne. | `J/iso/NewMapBinaryFile.java:247`, `J/iso/IsoMetaGrid.java:2047`, `J/iso/objects/IsoLightSwitch.java:92-101` | confirmé statiquement |
| Forçage des barricades et des portes verrouillées par un PNJ d'un type d'hostilité ≥ 75 pendant un `move`. | [deplacement.md](deplacement.md), `LK_Obstacles.lua` (« passage bloqué », LK04-T04) | confirmé statiquement (banc) |
| Corps créés à 40 cases au moins de tout joueur, côté foyer, par le chemin de la matérialisation. | [vengeance.md](vengeance.md) | confirmé statiquement (banc) |

## Choix (2026-10-12)

Valeurs de départ propres au mod (`Raids.CFG`), à recalibrer en jeu ; les choix non tranchés par le plan sont listés à la fin (« Décisions à confirmer »).

### Repérage : signes d'occupation

Relevé `Raids.survey` à chaque heure de jeu (`EveryHours`, autorité), pour chaque joueur vivant :

- **Base** (`Raids.baseOf`) : le refuge vanilla qui contient sa case, sinon le bâtiment de sa case (rectangle du `BuildingDef`, niveaux 0 à `getMaxLevel`) ; dehors, rien (un camp en plein air n'est pas une base).
- **Signes** (`Raids.signs`), lus sur les cases **chargées** de la base (bords sud et est compris, générateurs à 3 cases autour, 8 000 cases au plus) :

| Signe | Points | Raison |
|---|---|---|
| refuge vanilla | 3 | déclaré par un joueur ; lisible sans charger |
| générateur allumé (`IsoGenerator:isActivated`) | 2 | le jeu n'en allume aucun |
| 2 ouvertures barricadées ou plus | 1 | le jeu en barricade aussi (cachettes, histoires) |
| 2 `IsoThumpable` ou plus sans marque `LKHome` | 1 | constructions du menu, mais aussi objets d'histoires |

  Base retenue à **2 points** : refuge seul, générateur seul, ou barricades et constructions ensemble.
- **Écartés** : lumières (allumées au hasard au départ du monde), véhicules (épaves partout), bruit (passager, couvert par les zombies). Ils restent possibles plus tard si une preuve d'origine joueur est trouvée.
- Base à **60 cases** ou moins du foyer d'un groupe : ignorée (les groupes barricadent et fortifient leur foyer, LK14).
- **Groupe qui repère** (`Raids.watcherFor`) : type pillard (un rôle permet `raid` : adjoint, combattants, éclaireurs, casseurs des pillards livrés), présent, un vivant au moins, foyer à **3 000 cases** au plus ; le plus proche. Il note la base (phase `watch`, journal `spotted a player base at x,y (signes)`) avec ses occupants (compte et identité du carnet).
- **Occupation** : signes vus sur **2 jours de jeu différents** ; une base surveillée sans nouveau signe depuis 7 jours est oubliée. Un groupe surveille une base à la fois.

### Éclaireurs (hors écran)

Dans le pas de la simulation (`Raids.offscreenHour(data, g, gid, hour)`, après la vengeance, même écriture, aucun tirage, aucun accès aux cases) :

- Conditions : base occupée ; `RaidsEnabled` ; **`RaidDays` jours** de jeu depuis le départ du raid précédent (tous groupes : `raidLast` et raids en cours) et depuis le début du monde ; aucun autre raid en cours (un à la fois dans le monde) ; un occupant **hostile** au groupe (attitude LK11-T03 ; occupant sans identité du carnet : niveau de départ du type, hostile pour les pillards) ; aucune expédition en cours. Sinon attente (raison journalisée une fois).
- **Éclaireurs réels** : 1 à 2 vivants au foyer, hors chef, de rôle `raid` (rôle `scout` d'abord), blessure ≤ 20, sans corps ; un vivant au moins reste. Expédition abstraite `{ place = "raid", team, departed, returns }` (absents du foyer, jamais matérialisés au foyer) ; trajet `ceil(distance / 300)` heures ; **4 heures** de guet à la base. Journal `scouts m-2 m-3 left for the base at x,y, n h away` ; fait `raidScouting`.
- **À la base** : si un joueur vivant est à 80 cases, corps par `Relations.embodyTeam` (case côté foyer, 40 à 75 cases de la base, à **40 cases au moins de tout joueur**, sinon aucun corps), comportement `revenge` du cadre de décision (raison `raid 1 hunt`) : ronde de 4 points à **30 cases** autour de la base. Ils sont des pillards : un joueur qu'ils voient est engagé par les règles ordinaires (hostile, ils tirent les premiers).
- **Éclaireurs tous morts** (pendant le trajet ou le guet ; pas horaire) : **raid annulé** — journal `scouts … did not come back: raid on x,y called off`, fin `cancelled`.

### Annonce

À la fin du guet, au moins un éclaireur vivant :

- journal du groupe `scouts saw the base at x,y (signes): attack in about n h` (mémoire commune des membres) ;
- réplique `IGUI_LK_Raid_Scouted` (« Jolie planque que vous avez là. On reviendra la prendre. ») par un éclaireur incarné, bande `hostile`, dite au passage suivant (hors de l'écriture du registre) et entendue selon la règle de la bulle ;
- fait public `raidAnnounced` (`{ group, base, x, y, src, players, day, hours, team }`), point d'appel de la radio du carnet ;
- retour des éclaireurs, puis **24 heures** d'attente (`ready`).

### Attaque

- À l'heure prévue, occupants encore hostiles (sinon fin `peace`) : **effectif réel** de rôle `raid` au foyer (éclaireurs revenus compris), hors chef, valides, sans corps, **2 à 6**, un vivant au moins reste ; aucun membre créé. Même trajet abstrait ; **3 heures** à la base ; fait `raidLaunched`.
- À la base : corps à distance des joueurs comme les éclaireurs ; marche par étapes de 40 cases vers une ronde serrée (**2 cases**) autour du centre de la base, donc dans le bâtiment : portes verrouillées et barricades sur le chemin sont **forcées** par LK04-T04 (pillards) ; engagement par le choix de cible existant.
- Fin du temps à la base : journal `raid on x,y: n still standing, heading home`, retour ; au foyer : fin `done`. Équipe anéantie : fin `wiped`.

### Fin

| Raison | Quand |
|---|---|
| `cancelled` | éclaireurs tous morts (ou expédition effacée par l'administration) |
| `done` | attaque revenue |
| `wiped` | attaque anéantie |
| `peace` | plus aucun occupant hostile au moment de l'attaque |
| `disabled` | raids désactivés pendant la surveillance ou l'attente |
| `forgotten` | base surveillée sans signe depuis 7 jours |

Champ `raid` effacé, `raidLast` = heure du départ des éclaireurs (s'il y en a eu), journal `raid on x,y ended: <raison>`, fait `raidEnded`.

### Registre (schéma 1 inchangé)

Champs facultatifs du groupe, contrôlés par `Raids.validRaid` (malformé : oublié avec un avertissement), ignorés par `LK_Groups` :

```
raid = { v = 1, phase = watch | scout | ready | raid, base = { id = "b:<IDString>" | "sh:x,y", x1, y1, x2, y2 (inclus),
         x, y, z = centre, src = building | safehouse }, signs = "generator barricades", seen = jours, last = jour,
         occ = { { u = compte, k = clé du carnet ou nil } } (4 au plus), k = départs, start = heure du départ des
         éclaireurs, due = heure de l'attaque (ready), step = out | at | back, team = { "m-<k>" }, dep, arrive, leave,
         travel (heures) }
raidLast = heure du départ des éclaireurs du dernier raid
```

Persistant avec le registre des groupes (fichier privé, jamais en ModData globale) ; mémoire seulement : répliques en attente, raisons déjà journalisées, étapes de marche.

### Options sandbox

- `LivingKnox.RaidsEnabled` (booléen, vrai) : désactive le repérage et tout nouveau départ (surveillance et attente closes, fin `disabled`) ; une équipe déjà dehors finit sa sortie.
- `LivingKnox.RaidDays` (entier 3 à 90, **14**) : jours de jeu au moins entre deux raids (départs des éclaireurs), et avant le premier. Lu à chaque heure ; absente : défaut sans avertissement ; invalide : défaut, un avertissement.

### MP

Tout sur l'autorité (`if isClient() then return end`) : relevé, décisions, corps. Les clients reçoivent les corps, les consignes relayées et la bulle. Deux joueurs voient les mêmes pillards au même endroit.

### Coût

Relevé : une base par joueur et par heure, 8 000 cases au plus ; pas horaire : une lecture d'attitude par occupant d'une base occupée ; passage de chaque minute : groupes × joueurs, puis la recherche de case de la vengeance pour chaque corps à placer.

## Alternatives écartées

- **Pillards créés près de la base** : interdit ; les corps viennent de l'équipe partie du foyer et apparaissent à 40 cases au moins de tout joueur.
- **Tirage aléatoire du raid** : peu lisible et non reproductible ; la rareté vient de la fréquence réglable, de l'occupation sur deux jours et d'un raid à la fois.
- **Lumières, véhicules, bruit** comme signes : voir plus haut.
- **Position actuelle du joueur** comme cible : omniscient ; retenu : la base vue par le relevé.
- **Raison de cible « raid »** dans `Hostility.targetRule` : inutile pour les pillards livrés (hostiles, ils tirent les premiers) ; un occupant non hostile n'est pas attaqué et un raid n'est pas lancé contre lui.

## Tests

- Banc lupa `tests/test_lk_raids.py` (20 tests) : signes et score (barricades, constructions marquées d'un foyer exclues, générateur éteint ou allumé, refuge prioritaire, dehors), relevé sur deux jours par le groupe pillard le plus proche (colons ignorés, trop loin, occupants A et B), signes faibles, foyer de groupe voisin et raids désactivés ; éclaireurs réels (rôle scout d'abord, jamais le chef, absents du foyer, effectif inchangé), monde trop jeune, un seul jour ; éclaireurs tués → `cancelled` sans attaque ; annonce, retour, attaque par l'effectif réel, retour, `done`, faits publiés ; un raid à la fois et fréquence de 3 jours ; occupant non hostile (pas d'éclaireurs ; `peace` pendant l'attente) ; désactivation, occupant sans identité ; relecture et contrôle de forme ; mêmes octets heure par heure ou en rattrapage ; pile des corps (MP et solo) : corps des éclaireurs et des pillards à 40 cases au moins de chaque joueur, côté foyer, jamais au foyer, aucun corps si seules des cases proches sont chargées ou sans joueur à la base, comportement de traque (`raid 1 hunt`) vers la base, réplique d'annonce d'un éclaireur incarné dite hors écriture ; suite `lk.raid` qui passe et qui échoue sur une apparition injectée à côté du joueur ; options, traductions EN/FR en Latin-1, code ASCII.
- VM Kahlua : non lancée pour ce module (motifs interdits contrôlés dans la source).

### Protocole en jeu

1. Solo (`rstest-solo`, mod de dev, Living Knox activé), dans une maison avec du terrain dégagé autour : `RST.run({ suite = "lk.raid", tags = "world" })` → 2 PASS (corps notés à 40 cases ou plus, fin `done`, puis `cancelled`).
2. Solo, à la main : allumer un générateur dans sa maison (ou poser 2 barricades et 2 constructions), y rester deux jours de jeu ; `LivingKnox.Groups.get("grp-<n>").raid` du groupe pillard le plus proche passe en `watch` puis `scout` après `RaidDays` jours (régler l'option à 3 pour l'essai) ; éclaireurs aperçus à distance, réplique à leur départ ; les tuer → `ended: cancelled`. Sinon, un jour plus tard, les pillards arrivent de loin et forcent portes et barricades.
3. MP (séance finale) : deux joueurs dans la même base voient les mêmes pillards ; un joueur ami du groupe (attitude non hostile) seul dans la base n'est pas visé.

## Limites et restes

- ⚠ À vérifier en jeu : `SafeHouse.getSafeHouse(case)` depuis Lua (surcharges), lecture des générateurs et barricades sur un serveur dédié, cases d'apparition chargées à 40-75 cases (petit écran), marche et forçage jusque dans la base, bulle de l'annonce.
- Une base n'est repérée que pendant qu'un joueur s'y trouve (cases chargées) ; un camp en plein air ou une base sans signe n'est jamais visé ; un joueur absent pendant l'attaque : rien ne se passe (aucun pillage abstrait de la base).
- Les éclaireurs se battent s'ils voient un joueur (pillards hostiles) : le guet discret à 30 cases n'est qu'une ronde.
- Radio : point d'appel seulement (`raidAnnounced`) ; les faits `raid*` ne sont pas relayés en événements publics (`LK_API`).
- Aucune fenêtre d'administration dédiée (le journal du groupe et le champ `raid` se lisent par la console ou `LK_Admin`).

## Décisions à confirmer

- Signes retenus et points (refuge 3, générateur 2, barricades 1, constructions 1, seuil 2) ; lumières, véhicules et bruit écartés.
- Occupation = signes sur 2 jours différents ; groupe pillard le plus proche à 3 000 cases au plus ; base ignorée à 60 cases d'un foyer de groupe.
- Un raid à la fois dans le monde ; `RaidDays` = 14 par défaut (3 à 90), compté entre deux départs d'éclaireurs et depuis le début du monde.
- Raid seulement contre une base dont un occupant est hostile au groupe.
- Valeurs : 1 à 2 éclaireurs (rôle scout d'abord), 4 h de guet à 30 cases, annonce puis 24 h d'attente, attaque de 2 à 6 membres de rôle `raid` hors chef, 3 h à la base, ronde à 2 cases, 300 cases par heure.
- Annonce = réplique d'un éclaireur incarné, journal et fait public (pas de message radio tant que le carnet n'a pas d'API d'antenne).
