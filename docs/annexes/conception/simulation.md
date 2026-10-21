# Simulation hors écran

- Tâches : LK09-T01 (création), LK09-T02 (expéditions, section « Expéditions »), LK09-T05 (événements, section « Événements »), LK09-T03 (membres incarnés, section « Membres incarnés »), LK09-T06 (stock réel, section « Stock réel ») ; servira LK09-T04 (relève)
- Build : 42.21.0 — Date : 2026-10-10 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Simulation.lua` (règles, rattrapage, tirages, expéditions), taux et seuils dans `media/lua/shared/LivingKnox/LK_Config.lua` (`Config.SIMULATION`, lieux et probabilités des expéditions dans `Config.SIMULATION.EXPEDITIONS`, événements dans `Config.SIMULATION.EVENTS`), champs ajoutés au registre et fonctions pures `applyDeath`, `applyLeader`, `applyLeave`, `update` dans `LK_Groups.lua` ([groupes.md](groupes.md)), accroche dans `LK_Server.lua`.

## Problème

Les groupes vivent loin des joueurs : leurs réserves baissent, leur moral varie, leurs blessés guérissent ou meurent, selon le temps de jeu écoulé, y compris pour les heures manquées (registre arrêté, moteur désactivé). La simulation est **abstraite** : aucun corps, aucun déplacement, aucun accès au monde. Elle doit être reproductible (même état et mêmes heures, même résultat) et sa charge bornée.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `EveryHours` est déclenché par `GameTime.update` quand l'heure du jour change (`getHour() != previousHour`), une fois par mise à jour même si plusieurs heures passent d'un coup. | `J/zombie/GameTime.java:553-554` | confirmé statiquement |
| `GameTime.update` est appelé par `IngameState.UpdateStuff`, lui-même après le test de pause : un serveur dédié sans joueur avec `PauseEmpty` (`paused = Players.isEmpty() && pauseEmpty && readyToPause()`) n'appelle pas `UpdateStuff`, donc l'heure n'avance pas et `EveryHours` ne part pas ; rien n'est simulé. | `J/zombie/gameStates/IngameState.java:548-561, 1528-1530, 1574` ; base `logs-and-tools.md` (serveur sans joueur, `OnTickEvenPaused` seul) | confirmé statiquement |
| `getWorldAgeHours()` = `nuitsSurvécues × 24 + heure − 7` (ou `+ 17` avant 7 h) : continu, 0 à 7 h le premier jour ; l'heure du jour d'un âge `a` vaut `(a + 7) % 24`. | `J/zombie/GameTime.java:830-834` ; base `api-42-21.md` | confirmé statiquement |
| Kahlua : pas d'opérateurs binaires ; `%` faux au-delà d'un quotient de 2^31 ; littéraux non ASCII altérés. | base `kahlua-lua.md` | confirmé statiquement ; contrôlé dans la VM réelle (`test_kahlua.py`) |
| Un client MP charge aussi `media/lua/server` : garde `isClient()`. | base `mod-loading.md` | confirmé statiquement |

## Choix

Retenu le 2026-10-10 (LK09-T01), dans le cadre du contrat de la tâche (aucune décision `à décider` dans LK09).

**Heures.** L'heure simulée `k` est l'intervalle d'âge du monde `[k−1, k[` ; son heure du jour de début vaut `(k + 6) % 24`. La dernière heure simulée `simHour` est rangée dans le registre des groupes (privé, persistant, écrit avec lui). Chaque pas simule `simHour + 1 .. floor(getWorldAgeHours())`, en une seule sauvegarde.

- **Accroche** : `EveryHours` (et un pas au démarrage, `OnServerStarted` ou `OnGameStart`, si le registre est déjà relu). Si plusieurs heures passent dans une seule mise à jour du jeu, le pas suivant les simule toutes : rien ne dépend du nombre d'événements reçus.
- **Rattrapage borné** : au plus `MAX_CATCHUP_HOURS` = 72 heures, les plus récentes ; le reste est ignoré et journalisé (`WARN simulation: <n> hour(s) missed, 72 simulated, <n−72> skipped`). Cas réels : moteur désactivé (`LivingKnox.Enabled`) puis réactivé, registre bloqué puis réparé, registre relu après une remise à zéro du Lua, plusieurs heures dans une même mise à jour. **Le temps de jeu ne court pas quand le serveur est arrêté** : un arrêt propre ne crée aucune heure manquante.
- **Registre sans `simHour`** (créé avant cette tâche, ou valeur invalide oubliée au chargement) : départ à l'heure courante, sans rattrapage (`INFO simulation: starts at world hour <h>`).
- **Horloge en retard** sur `simHour` (monde rechargé d'une sauvegarde plus ancienne que le fichier des groupes, par exemple après un plantage) : rien n'est simulé tant que l'horloge ne l'a pas dépassée (`WARN … is behind …`, une fois), pour ne pas consommer deux fois les mêmes heures.

**Règles par heure et par groupe** (groupes triés par numéro, membres vivants par ancienneté ; groupe sans vivant ignoré, LK09-T04 le traitera) :

1. **Tâche hors écran (I1.6)**, priorités : `heal` (un vivant blessé à `WOUND_SERIOUS` = 40 ou plus, et des soins en réserve) ; `rest` la nuit (22 h – 6 h) ; `rest` si fatigué (repos < 25) ; `scavenge` si une réserve est sous `NEED_TARGET` = 60 (raison : la plus basse) ; sinon `rest` (`idle`). Gardée dans `task` ; un changement est inscrit au journal du groupe (`task`, texte `<tâche>: <raison>`, par exemple `scavenge: food`).
2. **Consommation** : nourriture 0,08 et munitions 0,02 par membre vivant et par heure (6 membres : ~11,5 de nourriture et ~2,9 de munitions par jour sur 100).
3. **Fouille** (`scavenge`) : gain tiré de 0 à `SCAVENGE_MAX` = 3 sur la réserve la plus basse. Seul effet de la tâche, borné ; aucun déplacement.
4. **Blessures abstraites** (`wound` 0..100 par membre) : nouvelle blessure de 10 à 40 avec une chance de 0,2 % par heure (~5 % par jour), 1 % pendant une fouille (journal `wounded`) ; au-dessus de `WOUND_MINOR` = 20 : guérit de 1 par heure avec des soins (2 en tâche `heal`), chaque blessé consommant 0,25 de soins, sinon s'aggrave de 0,5 ; en dessous : guérit seule de 0,25 ; faim (nourriture à 0) : +0,3 pour chacun. À 100 : **mort** (`Groups.applyDeath`, même code que `markDead` : `alive = false`, entrée `died`) ; un chef mort est aussitôt remplacé par le successeur de la règle de succession (`pickSuccessor`, entrée `leader`), puisqu'aucun comportement ne tourne hors écran.
5. **Repos** (`rest` 0..100, 50 au départ) : +6 en tâche `rest`, −4 en fouille, −2 de jour pour une autre tâche.
6. **Moral** : −0,5 par réserve sous `NEED_LOW` = 25, −0,5 si repos sous 25, −1 si nourriture à 0, +0,1 si toutes les réserves sont à `NEED_OK` = 40 ou plus et le repos à 50 ou plus ; −10 par mort.

Valeurs de départ propres au mod (aucune reprise d'un autre mod), à recalibrer en jeu : un groupe de six sans incident se stabilise autour de 55-60 sur chaque réserve, des blessés qui guérissent en quelques jours et un moral qui monte lentement ; sans soins ni nourriture, il perd des membres en quelques jours. Les expéditions (LK09-T02) et les événements (LK09-T05) ajouteront le risque.

**Reproductibilité.** Un flux de tirages par (graine, numéro du groupe, heure) : Park-Miller (multiplicateur 48271, module 2^31 − 1) suivi d'un mélange non linéaire, quotients sous 2^31 ; graine = `Config.SIMULATION.SEED` si fixée, sinon hachage du « mode/nom » de la partie (`Store.worldKey`). Les quantités fractionnaires passent par un **arrondi aléatoire reproductible** (partie entière, plus 1 avec la probabilité de la fraction) : le registre ne garde que des entiers, sans reste caché. Même état et mêmes heures donnent donc le même registre, octet pour octet, que les heures soient simulées une par une ou en un rattrapage, avant ou après un redémarrage.

**Charge bornée.** Travail = heures simulées (≤ 72 par pas, 1 en régime normal) × groupes (≤ 64) × membres (≤ 32) ; aucune case, aucun chunk, aucun joueur lu ; une seule écriture du registre par pas (`Groups.update`).

**Schéma.** Le registre reste au **schéma 1** : champs facultatifs `simHour` (registre), `rest` et `task` (groupe), `wound` (membre ; absent = 0). Un fichier sans ces champs se relit tel quel ; une version antérieure du mod les ignore et les garde. Au chargement, `wound`, `rest` ou `task` invalides écartent le groupe (règle commune de `validGroup`) ; `simHour` invalide est seulement oublié.

## Expéditions

Retenu le 2026-10-10 (LK09-T02), dans le cadre du contrat de la tâche (aucune décision `à décider`). Valeurs de départ propres au mod, à recalibrer en jeu avec LK09-T05. Réglages : `Config.SIMULATION.EXPEDITIONS` ; code : `LK_Simulation.lua` (`expeditionSettings`, `tryDepart`, `resolveExpedition`, `drawRecruit`).

**Départ** (intégré à la tâche par priorités) : quand la tâche choisie est `scavenge` pour la réserve la plus basse, qu'aucune expédition n'est en route, que cette réserve est sous `NEED_TRIGGER` = 35 et que l'effectif le permet, un tirage `DEPART_CHANCE` = 0,25 par heure éligible décide du départ. Équipe : membres vivants au foyer, **hors chef**, blessure sous `WOUND_MINOR`, triés par `TEAM_ROLES` (`scout`, `fighter`, `worker`, `breaker`, `medic`, `deputy`) puis ancienneté ; taille = min(`TEAM_MAX` = 4, candidats, vivants au foyer − `MIN_HOME` = 2), départ refusé sous `TEAM_MIN` = 2. Lieu tiré parmi `PLACES` selon son rendement sur la réserve qui manque (aucun lieu ne la rapporte : simple fouille) ; durée tirée dans `hoursMin..hoursMax`. La tâche devient `expedition` (entrée `task`, texte `expedition: <réserve>`), suivie d'une entrée `expedition`. Tant que l'équipe est dehors, la tâche `scavenge` du foyer reste `expedition` (pas de fouille au foyer ; effets : ceux d'une autre tâche de jour).

**Absence.** Les membres de l'équipe sont **absents du foyer** : ni consommation (leurs vivres sont comptés dans le rendement **net** du lieu), ni repos, ni blessure, ni soins au foyer (blessure figée). Si plus personne n'est au foyer, rien d'autre ne se passe pendant l'heure. Une heure de retour tombée dans des heures ignorées par le rattrapage borné est traitée à la première heure simulée qui suit.

**Lieux** (liste fermée, données de `EXPEDITIONS.PLACES`, pas de code) :

| Lieu | Durée (h) | Risque | Recrue | Rendement par survivant (food / medical / ammo) |
|---|---|---|---|---|
| `houses` | 4–8 | 0,10 | 0,04 | 4 / 1 / 0,5 |
| `stores` | 6–10 | 0,20 | 0,05 | 6 / 1 / 0,5 |
| `pharmacy` | 4–8 | 0,25 | 0,03 | 0,5 / 6 / 0 |
| `police` | 6–10 | 0,35 | 0,03 | 0,5 / 1 / 6 |
| `farm` | 8–12 | 0,08 | 0,06 | 5 / 0 / 0,5 |
| `forest` | 8–14 | 0,05 | 0,02 | 3 / 0,5 / 0 |

**Retour** (au début de l'heure `returns`), pour les membres de l'équipe encore présents et vivants (un membre retiré ou mort entre-temps est ignoré) :

- **Risque effectif** = `risk` × (1 − sécurité), sécurité = somme de `ROLE_SAFETY` des rôles de l'équipe (`fighter` 0,15, `scout` 0,1, `deputy` 0,1, `breaker` 0,05), plafonnée à `SAFETY_MAX` = 0,5.
- **Un tirage par membre** : sous risque × `DEATH_SHARE` (0,2) → **perte** (`Groups.applyDeath`, entrée `died`, succession si c'était le chef, moral `MORALE_DEATH` = −10) ; sinon sous le risque → **blessé** (`wound` + `WOUND_MIN..WOUND_MAX` = 15..45, borné à `WOUND_DEATH` − 1 : une expédition ne tue que par le tirage de perte, les règles horaires font ensuite guérir ou s'aggraver la blessure). Fréquences : perte = risque × part, blessure = risque × (1 − part).
- **Gains** par réserve : moyenne = rendement × survivants (blessés compris) × (1 + bonus), bonus = somme de `ROLE_YIELD` (`scout` 0,15, `worker` 0,1, `breaker` 0,1) plafonnée à `YIELD_BONUS_MAX` = 0,5 ; tirage uniforme de 0 au double de la moyenne, arrondi aléatoire reproductible, réserve bornée à 100.
- **Recrue** : s'il reste un survivant, chance `recruit` du lieu d'un nouveau membre (`Groups.applyMember`), profil tiré du type comme la population (rôle selon le poids des rôles qui ont un profil disponible, profil selon son poids et son `max` compté sur les vivants, sexe imposé ou tiré, traits à leur chance) ; aucune recrue si le groupe a déjà `size.max` vivants (type) ou `MAX_MEMBERS` membres (registre, morts compris), ou si le type n'est plus enregistré. Une recrue au plus par retour.
- **Moral** : +`MORALE_RETURN` = 2 pour un retour sans perte avec un gain.

**Probabilités bornées.** `Simulation.expeditionSettings()` relit la table à chaque pas et borne chaque valeur : probabilités 0..1, entiers dans leurs bornes (équipe 1..32, durée 1..72 h, blessure 0..99), bonus de sécurité 0..1, de rendement 0..10 ; valeur non numérique = borne basse ; `TEAM_MAX` < `TEAM_MIN` → `TEAM_MIN` ; lieu malformé ou en double ignoré avec un avertissement unique (`WARN simulation: expedition place <id> ignored: <raison>`) ; table absente : aucun départ (une expédition en route revient quand même ; lieu inconnu au retour : entrée `return` `<lieu>: unknown place, <n> back`, sans résultat).

**Journal du groupe** (anglais, textes ≤ 200, kinds stables) : au départ `task` (`expedition: food`) puis `expedition` (`houses: m-4 m-5 m-3 m-6, 7 h`) ; au retour, dans cet ordre, `return` (`houses: 4 back, 0 lost, 1 wounded, food +26 medical +2 ammo +5`), `loss` (`police: m-3 m-5`, si perte) suivie d'une entrée `died` par perte, `recruit` (`stores: m-7 scout`) suivie de `joined`. Au plus 2 + 2 × équipe + 2 entrées par expédition. Extrait (banc, colons de six membres, réserves à 20, `DEPART_CHANCE` = 1) :

```
day 28 task        expedition: food
day 28 expedition  houses: m-4 m-2 m-5 m-3, 7 h
day 28 return      houses: 4 back, 0 lost, 0 wounded, food +26 medical +2 ammo +5
day 28 expedition  police: m-4 m-2 m-5 m-3, 7 h
day 28 return      police: 4 back, 0 lost, 2 wounded, food +2 medical +2 ammo +38
```

**Reproductibilité.** Les tirages des expéditions viennent d'un **flux séparé** de la même heure (`Simulation.stream(base, groupe, heure, EXPEDITION_SALT)`) : le flux principal de LK09-T01 n'est pas décalé ; l'état de l'expédition est entièrement dans le registre. Même découpage ou rattrapage → mêmes octets (banc : 24 pas d'une heure = 24 h d'un coup = 5 h + 19 h, avec une expédition partie et revenue ; VM Kahlua identique).

**Schéma.** Champ facultatif du groupe `expedition = { place, team = { "m-<k>", ... }, departed, returns }` (schéma 1 inchangé) : `place` de la forme d'un `kind`, `team` liste de 1 à `MAX_MEMBERS` identifiants bien formés (< `nextMember`, sans doublon), `departed` entier ≥ 0, `returns` ≥ `departed`. Invalide : groupe écarté à la relecture (`bad expedition place|hours|team`, `expedition is not a table`). Un registre sans ce champ se relit tel quel ; une version antérieure du mod l'ignore et le garde (l'équipe redevient présente pour elle).

**Charge.** Inchangée en ordre de grandeur : un retour coûte un tirage par membre de l'équipe et deux par réserve ; aucun accès au monde.

**Expédition physique passée hors écran (LK05-T05).** Une expédition de `LK_Expeditions` dont les corps sont retirés loin des joueurs devient une expédition abstraite `{ place = "trip", team, departed, returns, trip = n }` (équipe absente, jamais matérialisée) ; à l'heure `returns`, `simulateHour` appelle `LivingKnox.Expeditions.resolveAbstract` au lieu de `resolveExpedition` : aucun mort ni blessé, butin abstrait tiré du même flux des expéditions (reproductible), dépôt réel au foyer ensuite. Voir [expeditions.md](expeditions.md).

**Vengeance (LK11-T05).** `Simulation.advance` appelle `LivingKnox.Relations.offscreenHour(g, gid, hour)` avant chaque heure simulée de chaque groupe (serment, départ d'une équipe, arrivée, fin de traque, rancune éteinte : logique pure dans la même écriture, aucun tirage, aucun accès aux cases) ; l'équipe partie est une expédition abstraite `{ place = "revenge", team, departed, returns }` (absente du foyer) et, à l'heure `returns`, `simulateHour` appelle `LivingKnox.Relations.revengeReturn` au lieu de `resolveExpedition` (aucun gain, aucune perte tirée). Module absent : expédition résolue comme un lieu inconnu. Voir [vengeance.md](vengeance.md).

**Raids (LK11-T07).** Après la vengeance, `Simulation.advance` appelle `LivingKnox.Raids.offscreenHour(data, g, gid, hour)` (départ des éclaireurs ou de l'attaque, arrivée, fin du guet ou de l'attaque, annulation : même écriture, aucun tirage, aucun accès aux cases) ; l'équipe est une expédition abstraite `{ place = "raid", team, departed, returns }` et, à l'heure `returns`, `simulateHour` appelle `LivingKnox.Raids.raidReturn`. Voir [raids.md](raids.md).

**Alternatives écartées (expéditions).** Délai de recharge mémorisé entre deux expéditions (un champ de plus) : la chance de départ par heure suffit. Consommation réduite des absents prélevée au foyer : le rendement net est plus simple et ne dépend pas de l'ordre des heures. Mort par aggravation de la blessure d'expédition : deux causes de mort mêlées dans un même tirage, moins lisibles au journal. Chef dans l'équipe : la succession pendant une absence serait ambiguë.

## Événements

Retenu le 2026-10-10 (LK09-T05), dans le cadre du contrat de la tâche (aucune décision `à décider`). Valeurs de départ propres au mod, à recalibrer en jeu. Réglages : `Config.SIMULATION.EVENTS` ; code : `LK_Simulation.lua` (`eventSettings`, `eventChances`, `drawEvent`, `applyEvent`, `runEvents`, `clashTargets`, `knownBases`) ; `Groups.applyLeave` dans `LK_Groups.lua` (partagée avec `removeMember`).

**Rythme.** Un tirage par groupe et par **jour**, à l'heure simulée dont l'heure du jour de début vaut `EVENTS.HOUR` = 12, **après** les règles horaires de tous les groupes de cette heure. Groupes dans l'ordre de leur numéro ; un groupe sans vivant ou sans personne au foyer ne tire rien. **Au plus un événement par groupe et par jour** : un seul tirage choisit au plus un événement de la liste, et un groupe déjà touché ce jour (y compris comme **cible** d'un combat) ne tire plus et ne peut plus être pris pour cible. Un tirage qui ne donne rien ne compte pas : le groupe peut encore être attaqué plus tard dans la même heure. Biais assumé : les groupes de petit numéro tirent les premiers. Un jour dont l'heure du tirage tombe dans des heures ignorées par le rattrapage borné (72 h) n'a pas d'événement.

**Tirage.** Chaque événement a une chance du jour (0..1) calculée d'après ses conditions ; la somme est plafonnée à `MAX_DAILY` = 0,5 (proportions conservées) ; un nombre `r` choisit l'événement dont la bande contient `r`, dans l'ordre `departure`, `recruit`, `conflict`, `illness`, `clash`. Un événement choisi qui ne peut rien faire (aucune recrue tirable) ne compte pas.

**Liste fermée** (identifiant = `kind` de l'entrée de journal, textes anglais ≤ 200) :

| Événement | Conditions | Chance par jour | Effets bornés | Journal |
|---|---|---|---|---|
| `departure` | moral < `MORALE_MAX` = 30 ; au moins `MIN_LEFT` = 2 vivants restent ; un candidat : membre au foyer, **jamais le chef**, ni un absent (expédition), ni un membre lié à un PNJ (`npc`, référence gardée par le registre des corps) | `CHANCE` = 0,2 × (30 − moral) / 30 (0,2 à moral 0) | membre retiré (`Groups.applyLeave`, comme `removeMember`), moral `MORALE` = −4 | `departure` `m-4 worker: low morale`, puis `left` `m-4` |
| `recruit` | nourriture ≥ `FOOD_MIN` = 40, moral ≥ `MORALE_MIN` = 40, place dans le groupe (type enregistré, moins de `size.max` vivants, moins de `MAX_MEMBERS` membres, comme LK09-T02) | `CHANCE` = 0,03 | un membre (`Groups.applyMember`, profil tiré du type par `drawRecruit`, comme les expéditions), moral `MORALE` = +2 | `recruit` `wanderer: m-7 scout`, puis `joined` `m-7` (même forme que la recrue d'expédition, origine `wanderer`) |
| `conflict` | au moins `MIN_MEMBERS` = 2 au foyer, et moral < `MORALE_MAX` = 50 ou une réserve sous `NEED_LOW` = 25 | `CHANCE` = 0,02 + `CHANCE_LOW_NEED` = 0,03 par réserve basse | deux membres au foyer (le premier hors chef) ; avec `CONTEST_CHANCE` = 0,25 le second est le chef (**chef contesté : journal seulement, aucun changement de chef**, E10/LK) ; avec `WOUND_CHANCE` = 0,3 l'un des deux prend une blessure de 5 à 15 ; moral `MORALE` = −6 | `conflict` `m-3 vs m-1, leader contested, m-3 wounded` |
| `illness` | au moins un membre au foyer | `CHANCE` = 0,02 (+ `CHANCE_HUNGRY` = 0,04 si nourriture sous `NEED_LOW`) | un malade, puis chaque autre membre au foyer avec `SPREAD` = 0,25, `MAX_SICK` = 3 au plus ; blessure 10 à 25 par malade ; un malade **soigné** (réserve `medical` ≥ `MEDICAL_PER_SICK` = 3 et non vide) consomme 3 de soins et ne prend que la moitié (5 à 12) ; moral `MORALE` = −3 | `illness` `m-2 m-5 sick, 1 treated, medical -3` |
| `clash` (I9.1) | attaquant d'un type de `ATTACKERS` (`raiders`), cible d'un **autre** type (jamais pillards contre pillards) ; deux foyers connus à `MAX_DISTANCE` = 2 000 cases au plus ; **chaque foyer à `PLAYER_DISTANCE` = 300 cases au moins de toute base connue** ; au moins `MIN_FORCE` = 2 attaquants au foyer et un défenseur ; cible sans événement ce jour | `CHANCE` = 0,05 (+ `CHANCE_NEEDY` = 0,05 si une réserve de l'attaquant est sous `NEED_LOW`) ; cible tirée uniformément | voir ci-dessous | voir ci-dessous |

Les blessures d'événement sont bornées à `WOUND_DEATH` − 1 (99) : un événement ne tue que par le tirage de perte d'un combat ; les règles horaires font ensuite guérir ou s'aggraver la blessure.

**Combat abstrait** (`clash`, idée I9.1, écriture propre) :

- **Issue selon les effectifs au foyer** (absents en expédition exclus) : force = 1 par membre, 0,5 par blessé grave (`WOUND_SERIOUS` = 40) ; le défenseur combat chez lui, force × `DEFENSE_BONUS` = 1,25 ; victoire de l'attaquant avec la chance force A / (force A + force D). Ni le moral ni les munitions n'entrent dans l'issue (simplification ; I9.1 cite santé, armes et moral).
- **Pertes et blessés** : un tirage par membre au foyer de chaque côté ; vainqueur : perte `LOSS_WIN` = 0,05, blessure `WOUND_WIN` = 0,2 ; vaincu : perte `LOSS_LOSE` = 0,2, blessure `WOUND_LOSE` = 0,4 ; au plus `MAX_DEATHS` = 3 morts par côté (au-delà, la perte tirée devient une blessure) ; blessure 15 à 40. Morts par `Groups.applyDeath`, puis **une seule** succession par côté si le chef en était (jamais au profit d'un mort du même combat).
- **Ressources** : chaque côté dépense `AMMO_COST` = 4 munitions ; attaquant vainqueur : butin = `LOOT_SHARE` = 25 % de chaque réserve de la cible, `LOOT_MAX` = 20 au plus, sans dépasser 100 (ce que l'attaquant gagne, la cible le perd : transfert conservatif). Défenseur vainqueur : aucun transfert.
- **Moral** : vainqueur `MORALE_WIN` = +3, vaincu `MORALE_LOSE` = −8, et `MORALE_DEATH` = −10 par mort.
- **Journal des deux groupes** : `clash` (`attack grp-1 won: 0 lost, 1 wounded, food +15 medical +10 ammo +9` chez l'attaquant ; `defend grp-2 lost: 2 lost, 1 wounded, food -15 medical -10 ammo -13` chez la cible), puis une entrée `died` par mort, `leader` si succession, et **`remains`** `m-1 m-3 at 1000,1000,0` : morts du combat et **lieu approximatif** (foyer de la cible, x et y arrondis à `PLACE_ROUND` = 10 cases), pour une tâche ultérieure. **Aucun cadavre n'est posé dans le monde** (hors périmètre).
- **« Loin des joueurs »** : `Simulation.step` lit une fois par pas `RS_Rescue.knownBases({})` (refuges vanilla, joueurs connectés sur un serveur, joueurs locaux en solo ; mêmes sources que les sites des foyers, [sites.md](sites.md)) et la passe à `advance(data, now, bases)` ; écart mesuré comme `RS_Rescue.gap` (foyer = case, base = rectangle à fin exclusive). `PLAYER_DISTANCE` est borné à 80 cases au moins (zone chargée autour d'un joueur : 79 cases au plus, [rescue.md](../../specifications-techniques/rescue.md)). `bases = nil` (bases inconnues, par exemple `advance` appelé sans elles) : **aucun combat** ; liste vide : aucun joueur connu, combat permis.

**Réglages bornés.** `Simulation.eventSettings()` relit `EVENTS` à chaque pas : chances 0..1, entiers dans leurs bornes (`HOUR` 0..23, effectifs 1..32, blessures 0..99, distances 0..100 000, `PLAYER_DISTANCE` ≥ 80, `PLACE_ROUND` 1..1 000), moral −100..100, `DEFENSE_BONUS` 0,1..10 ; valeur non numérique = 0 ramené dans ses bornes (chance nulle) ; `WOUND_MAX` < `WOUND_MIN` → `WOUND_MIN` ; `ATTACKERS` : chaînes seulement. `EVENTS` absent : aucun événement ; sous-table d'un événement absente : cet événement seul désactivé.

**Reproductibilité.** Tirages d'un **flux séparé** par (graine, groupe, heure, `EVENT_SALT`) : les flux de LK09-T01 et LK09-T02 ne sont pas décalés. Une heure est toujours simulée en entier dans un même appel (toutes les règles horaires, puis les événements), donc le découpage du rattrapage est sans effet (banc : 240 pas d'une heure = rattrapages de 72 h = 31 + 69 + 72 + 68 h, combats compris ; VM Kahlua identique). Les bases sont lues une fois par pas : un rattrapage applique à toutes ses heures les positions des joueurs du moment du pas (limite : un joueur qui s'est déplacé pendant les heures manquées n'est pas suivi).

**Schéma.** Aucun champ ajouté : schéma 1 inchangé, nouvelles entrées de journal seulement (kinds de la forme habituelle, contrôlés par `validGroup`).

**Charge.** Une fois par jour et par groupe : chances (membres du groupe) et, pour un attaquant possible, parcours des autres groupes et des bases connues (64 × 64 couples au plus) ; aucun accès au monde dans la logique pure.

Extrait (banc, trois groupes, moral 20, chances relevées, `MAX_DAILY` = 1 ; entrées `task`, `left` et `joined` omises) :

```
grp-1 day 1 conflict   m-6 vs m-2
grp-2 day 1 recruit    wanderer: m-6 fighter
grp-3 day 1 departure  m-4 worker: low morale
grp-3 day 2 illness    m-2 sick, 1 treated, medical -3
grp-1 day 4 illness    m-8 m-1 m-6 sick, 3 treated, medical -9
grp-1 day 6 conflict   m-7 vs m-1, m-7 wounded
grp-2 day 8 clash      attack grp-1 lost: 0 lost, 6 wounded, food +0 medical +0 ammo -4
grp-1 day 8 clash      defend grp-2 won: 0 lost, 1 wounded, food +0 medical +0 ammo -4
```

**Alternatives écartées (événements).** Tirage horaire avec un champ « dernier événement » par groupe : un champ de plus pour la même règle d'un événement par jour. Remplacement du chef contesté : hors périmètre (E10/LK). Cadavres posés au foyer des vaincus : demande la matérialisation (LK09-T03) et l'accès au monde ; seul le lieu est consigné. Champ facultatif pour les morts d'un combat : l'entrée `remains` suffit sans toucher au schéma. Combat entre deux groupes de pillards : écarté pour l'instant (`ATTACKERS` décrit les seuls attaquants ; la cible doit être d'un autre type).

## Membres incarnés

Retenu le 2026-10-10 (LK09-T03, matérialisation des groupes à l'approche d'un joueur : [corps-registre.md](corps-registre.md), « Matérialisation »). Code : `Simulation.isEmbodied(m)` (lien `npc` vers un PNJ `embodied` du registre des corps ; registre des corps absent ou non prêt : faux) et `Simulation.materialized(g)` (au moins un membre vivant incarné), dans `LK_Simulation.lua`.

Tant qu'un membre a un corps dans le monde, **l'état visible fait foi** :

| Règle | Membre incarné | Membre abstrait (inchangé) |
|---|---|---|
| Présence, consommation, repos, moral | présent au foyer, compté | idem |
| Blessure horaire (nouvelle blessure, guérison, aggravation, faim, mort à 100) | **aucune** : sa santé est celle de son corps ; aucun tirage pour lui | règles de LK09-T01 |
| Expédition | **jamais** dans une équipe (`teamCandidates`) | candidats de LK09-T02 |
| Événements du jour | groupe **matérialisé** : aucun tirage, et jamais cible d'un combat | règles de LK09-T05 |
| Départ (`departure`) | déjà exclu (membre lié à un PNJ) | — |

Passages entre les deux états : à la **matérialisation**, la blessure `wound` du membre devient la santé du corps (`hpMax × (100 − wound) / 100`) ; au **retrait** (LK03-T04), la santé gardée redevient la blessure (`round(100 × (1 − hp / hpMax))`, 0..99 : la conversion ne tue jamais) et le membre est de nouveau traité ici, présent au foyer. La mort d'un corps marque le membre mort une seule fois, sans second fait `memberDied`, avec la succession et le moral d'une mort hors écran (`Groups.applyDeath(g, mid, day, quiet)`). Les membres absents (expédition) ne sont jamais matérialisés ; à leur retour, ils le sont s'il y a toujours un joueur près du foyer. Une recrue (expédition ou événement) est matérialisée comme les autres.

**Reproductibilité** : inchangée pour un registre sans membre incarné (aucun tirage ajouté ni retiré) ; avec des membres incarnés, les tirages de blessure de ces membres sont sautés (même état, même résultat). La VM Kahlua des bancs n'a pas de registre des corps prêt : aucun membre incarné.

**Alternatives écartées.** Suspendre toute la simulation d'un groupe matérialisé : ses réserves et son moral cesseraient d'évoluer tant qu'un joueur campe à côté. Laisser la simulation blesser ou tuer un membre visible : un corps resterait debout alors que le registre le dit mort.

## Stock réel (LK09-T06)

Après chaque heure simulée de chaque groupe, `Simulation.advance` appelle `LivingKnox.Stock.offscreenHour` (repas abstrait quotidien pris dans l'inventaire de référence du stock réel, à l'heure du jour 18) ; au retour d'une expédition abstraite (`resolveExpedition`), `simulateHour` passe les gains à `Stock.offscreenLoot` (objets vanilla ajoutés). Ces règles sont pures, sans tirage ni accès au monde, dans la même écriture que le pas : la reproductibilité au découpage près est conservée (banc `test_lk_stock.py`, 72 h d'un coup = 72 pas d'une heure, expéditions comprises). Sans référence de stock (groupe jamais chargé), rien ne change : les bancs de la simulation restent identiques. Les écarts sont appliqués aux conteneurs à l'arrivée d'un joueur : voir [stock.md](stock.md), « Hors écran ». Les réserves abstraites `needs` restent un compte séparé.

## Alternatives écartées

- **Restes fractionnaires mémorisés** (accumulateurs par réserve) : un champ de plus par groupe et par réserve ; l'arrondi aléatoire reproductible donne la même moyenne sans état caché.
- **Taux par type de groupe** dans `LK_GroupTypes` : le format 1 refuse tout champ inconnu ; changer le format pour cette tâche aurait touché les trois fichiers de données et leurs tests. Taux globaux pour l'instant ; un réglage par type pourra passer par un format 2.
- **Écriture par l'API publique** (`addNeed`, `markDead`…) : une sauvegarde par appel, donc des dizaines par heure et un état intermédiaire écrit au milieu d'une heure ; `Groups.update` écrit une fois par pas.
- **Mort par `markDead` laissant le groupe sans chef** : hors écran, aucun comportement n'appliquerait la succession (LK05-T09) ; elle est appliquée aussitôt.
- **Rattrapage des heures les plus anciennes** : l'état final refléterait une période lointaine ; les plus récentes sont gardées.
- **`OnTickEvenPaused` ou horloge réelle** : ferait vivre les groupes sur un serveur vide en pause, alors que le temps de jeu, lui, est arrêté.

## Idées reprises

- I1.6 (choix de tâche hors écran par priorités) : seulement une priorité calculée et journalisée par groupe (soigner, se reposer, fouiller), dont l'effet est une petite variation bornée des réserves et du repos ; renfort, fortification, patrouille et voyage ne sont pas repris ici (LK09-T02, LK14).

## Tests

- Banc lupa `tests/test_lk_simulation.py` (23 tests) : 24 `EveryHours` d'une heure = un rattrapage de 24 h après un redémarrage = 5 h puis 19 h (mêmes octets du registre) ; graine fixe reproductible, graine différente qui change le résultat ; rattrapage borné à 72 h (les plus récentes, avertissement), plafond configurable ; même heure deux fois sans écriture, une écriture par pas ; horloge en retard qui attend (avertissement unique) ; registre sans `simHour` sans rattrapage ; moteur désactivé puis rattrapage ; registre bloqué refusé ; priorités de tâche ; mort par blessure sans soins, succession et moral ; soins qui guérissent et consomment ; faim ; groupe sans vivant intact ; arrondi sans biais ; champs ajoutés relus (schéma 1), champs invalides refusés ; clients sans simulation ; source sans accès au monde et sûre pour Kahlua ; 64 groupes × 32 membres × 72 h en une écriture ; solo (`OnGameStart`) ; mêmes valeurs que la VM Kahlua.
- Expéditions (LK09-T02, `ExpeditionTests`, 11 tests) : départ (réserve basse, équipe sans chef ni blessé, ordre des rôles, durée du lieu, journal `task` puis `expedition`) ; pas de départ (réserves correctes, groupe trop petit, chance 0, aucun lieu utile) ; absents sans consommation ni guérison ; journal du retour dans l'ordre `return`, `loss`, `died`…, `recruit`, `joined`, borné ; cycles sur 30 jours (chaque retour suit son départ, journal ≤ 32) ; banc de fréquences sur 2 000 tirages (pertes, blessés, recrues, gain par survivant proches des réglages) ; cas extrêmes (risque 0 et 1, part mortelle 0 et 1, recrue 1, groupe plein, blessure bornée à 99) ; effets des rôles (sécurité plafonnée, bonus de rendement) ; réglages bornés et lieux malformés ignorés une fois ; lieu inconnu au retour ; champ `expedition` relu, valeurs invalides refusées, membre retiré toléré. La règle de LK09-T01 seule (`test_state_evolves_consistently`) se teste avec `DEPART_CHANCE = 0`.
- Événements (LK09-T05, `EventTests`, 10 tests) : un test par événement (`departure` : moral bas, jamais le chef ni un membre lié à un PNJ, `MIN_LEFT`, journal `departure` puis `left` ; `recruit` : conditions, recrue `m-7` au profil du type, journal `recruit` puis `joined`, groupe plein refusé ; `conflict` : chances selon le moral et les réserves basses, chef jamais changé, contestation ~25 %, blessure 5..15 ~30 % ; `illness` : chance de faim, `MAX_SICK`, blessures soignées 5..12 ou non 10..25, soins consommés, soins partiels) ; combat : conditions (type, foyers, distance, bases nulles ou trop proches, force minimale), 600 combats (victoire ≈ 0,4 selon les forces, ≤ 3 morts par côté, butin ≤ 20 et conservatif, aucun butin en défaite, journaux `clash`, `died`, `remains` au lieu arrondi, groupes valides, chef vivant) ; au plus un événement par groupe et par jour sur 20 jours (tous les événements observés, journaux bornés) et aucun sans `EVENTS` ; reproductibilité au découpage près (240 h, combats compris) ; réglages bornés ; `step` lit les bases une fois par pas.
- VM Kahlua (`tests/test_kahlua.py`, `test_simulation_in_kahlua`) : 24 pas d'une heure = un rattrapage de 24 h, valeurs identiques à lupa, expédition comprise (LK09-T02 : une équipe part et revient, dernier nombre de `KR-SIM`) ; `test_simulation_events_in_kahlua` (`KR-EVT`, LK09-T05) : 240 pas d'une heure = rattrapages de 72 h avec combats, mêmes valeurs que lupa (`CrossVmTests`).
- En jeu : rien de propre à cette tâche (hors jeu). À observer plus tard dans `console.txt` : `simulation: starts at world hour …` au premier démarrage, aucune ligne `skipped` en régime normal.

## Points ouverts

- ⚠ Calibrage des taux en jeu (équilibre des réserves, mortalité, fréquence et rendement des expéditions, chances et effets des événements).
- ⚠ Morts d'un combat : seulement consignées (`remains`, lieu arrondi au foyer de la cible) ; aucun cadavre dans le monde. L'entrée peut sortir du journal de 32 entrées avant qu'une tâche ultérieure ne la lise.
- ⚠ « Loin des joueurs » : bases lues une fois par pas (positions du moment du pas pour tout un rattrapage) ; joueurs hors ligne, constructions sans refuge et véhicules non couverts (limites de `RS_Rescue.knownBases`).
- ⚠ Groupe décimé par un combat ou des départs : laissé à LK09-T04 (relève).
- ⚠ Journal : les changements de tâche de LK09-T01 (`scavenge` ↔ `rest: idle` autour de `NEED_TARGET`) remplissent vite les 32 entrées et repoussent les entrées d'expédition ; une hystérésis ou un journal des tâches séparé serait une nouvelle tâche.
- Traité par LK09-T03 (section « Membres incarnés ») : membres de `expedition.team` jamais matérialisés ; membres incarnés distingués des membres virtuels ; santé convertie en blessure au retrait. ⚠ Reste à mesurer en jeu (suite `lk.materialize`).
- ⚠ `EveryHours` réel sur serveur dédié et solo, et absence de pas pendant `PauseEmpty`, à confirmer par une mesure en jeu (statique seulement ici).
