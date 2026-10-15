# Vengeance différée après la perte d'un membre

- Tâche : LK11-T05 (création) ; s'appuie sur LK11-T03 (attitude, [attitude.md](attitude.md)), LK07-T04 (tueur identifié par le serveur, fait `npcDied`, [sante.md](sante.md)), LK09-T01/T02/T03 (simulation hors écran, expéditions abstraites, matérialisation, [simulation.md](simulation.md), [corps-registre.md](corps-registre.md)), LK05-T02 (cadre de décision, [decisions.md](decisions.md)), LK06-T01 (choix de cible, [cibles.md](cibles.md)), LK11-T04 (répliques, [parole.md](parole.md)) ; à garder cohérente avec LK11-T07 (raids « rares et annoncés », effectif réel parti du foyer)
- Code : section « vengeance » de `media/lua/server/LivingKnox/LK_Relations.lua` (`LivingKnox.Relations`, autorité). Branchements (modifications minimales) : `LK_Simulation.lua` (`Relations.offscreenHour` avant chaque heure simulée, `Relations.revengeReturn` au retour de l'expédition `revenge`), `LK_Decisions.lua` (comportement `revenge`, `ctx.hunt`, règle `duty`, besoins au retour), `LK_Hostility.lua` (raison de cible `revenge`, `Hostility.isRevengeTarget`). Réplique `IGUI_LK_Revenge_Sworn` (`Translate/EN|FR/IG_UI.json`). Banc `tests/test_lk_revenge.py` ; suite en jeu `lk.revenge` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKRevenge.lua`)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\`) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement
- Réutilisé par les raids (LK11-T07, [raids.md](raids.md), 2026-10-12) : trajet abstrait, corps à distance (`Relations.embodyTeam`, extrait de `huntPass` sans changement de comportement), marche (`applyHunt`, rayon `hu.patrol`), retour retardé (`delayReturn`), `turnBack`, `say`.

Idée de jeu : I9.6 ([idees-bandits-alife.md](../idees-bandits-alife.md) : vengeance différée et annoncée, abandonnée après plusieurs échecs). Aucune ligne de Bandits! ni de Project A-Life n'a été lue pour cette tâche ; la section « Écarté » s'applique (aucun vengeur créé de rien ni surgissant près du joueur, rancunes non effacées à la mort du joueur par une règle cachée).

## Problème

Quand un joueur tue un membre d'un groupe, le groupe peut vouloir se venger plus tard : il le fait savoir, attend quelques jours, envoie de vrais membres depuis son foyer là où il pense trouver le joueur, et finit par renoncer s'il échoue plusieurs fois ou si sa colère retombe. Les vengeurs ne doivent jamais apparaître à côté du joueur ni être créés de rien. Tout est décidé par l'autorité et survit au redémarrage.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Le tueur d'un corps de PNJ est connu du serveur (`getAttackedBy` à `OnZombieDead`, dernier coup relevé) ; le fait `npcDied` porte son compte (`killer`). | [sante.md](sante.md) ; `LK_Bodies.deathCause` ; base `multiplayer.md` (« tueur d'un zombie connu du serveur ») | confirmé statiquement (banc) |
| `OnCharacterDeath` part sur le serveur (`IsoGameCharacter.java:4604`) ; `OnPlayerDeath` jamais sur un serveur dédié. | base `multiplayer.md` | confirmé statiquement |
| `SafeHouse.hasSafehouse(compte)` rend le premier refuge vanilla dont le compte est propriétaire ou membre, sans rien charger, joueur déconnecté compris. | `J/iso/areas/SafeHouse.java:93-98` ; base `multiplayer.md` (ajout du 2026-10-12) | confirmé statiquement |
| Cases chargées autour d'un joueur : 48 à 79 cases selon l'écran en solo ; sur un serveur, `getGridSquare` rend `nil` hors d'une cellule serveur chargée. | base `world-placement.md` (« Taille de la zone chargée », « Serveur : cases lisibles par cellule ») | confirmé statiquement |
| Un corps sans joueur à 120 cases pendant 60 s est rendu à la simulation (`Materialize.onReleased`) ; `Materialize.presentMembers` exclut l'équipe d'une expédition abstraite. | [corps-registre.md](corps-registre.md), `LK_Materialize.lua` | confirmé statiquement (banc) |
| Une consigne `move` est refusée au-delà de 60 cases (`Directives.MAX_TRIP`) et vers une case non chargée. | [consignes.md](consignes.md) | confirmé statiquement (banc) |

## Choix (2026-10-12)

Valeurs de départ propres au mod (`Relations.REVENGE`), à recalibrer en jeu. Aucune décision `à décider` dans LK11 pour cette tâche : les choix non tranchés par le plan sont listés à la fin (« Décisions à confirmer »).

### Meurtre et serment

- Abonné au fait `npcDied` (`Relations.onNpcDied`) : membre d'un groupe, `killer` = compte d'un joueur vivant retrouvé parmi les joueurs (`Bodies.livingPlayers`), clé de joueur = identité du carnet (`Hostility.keyOf`). Sans identité : rien (ni fait, ni serment ; journal du moteur).
- `Relations.memberKilled(gid, mid, clé, opts)` : fait d'attitude **`kill` attribuable** (identifié par le serveur : `Hostility.record`, −60, marque « meurtre », déclin plafonné). Aucun module ne l'enregistrait jusqu'ici.
- Règle du serment (`Relations.oathRule`, pure, déterministe) : option `ENABLED` ; pas déjà en cours contre ce joueur (« already sworn ») ; **une vengeance au plus par groupe** (« busy ») ; attitude **après le meurtre** dans `LEVELS` = `hostile` ; au moins `TEAM_MIN` = 2 combattants vivants hors chef (rôle qui permet `fight` ou `defend`), sinon « too weak ».
  - Par type (attitude de départ de [attitude.md](attitude.md)) : **pillards** (−50) et **neutres** (6) jurent dès le premier meurtre (−100, −54) ; **colons** (50) restent prudents après un premier meurtre (−10 : pas de serment, mais méfiance par la provocation et le déclin plafonné) et jurent au second (−70).
- Serment : champ `revenge` du groupe (ci-dessous), départ à `sworn + délai` ; zone = lieu de la mort. Délai (LK11-T10, décision de l'utilisateur du 2026-10-14) : option sandbox `LivingKnox.RevengeDelayHours` (page LivingKnox, heures de jeu, entier de 12 à 336, **défaut 72**), lue au serment par `Relations.revengeDelayHours()` (`Config.readInt` : options enregistrées puis `SandboxVars` ; absente, non entière ou hors bornes : 72 avec un avertissement). Une vengeance jurée garde son heure `due` quand l'option change. `REVENGE.DELAY_HOURS` (nil par défaut) n'est plus qu'un forçage des bancs et des suites en jeu (0 admis).
- **Annonce perceptible** : entrée `revenge` au journal du groupe (`m-4 killed by <clé>: revenge sworn, leaving in 72 h`, mémoire commune des membres) ; réplique `IGUI_LK_Revenge_Sworn` (« Tu as tué l'un des nôtres. On te retrouvera, et tu paieras. ») par le membre incarné le plus proche du lieu de la mort (30 cases), bande `hostile`, bulle et ligne de chat traduites par chaque client ; fait `revengeSworn` publié (point d'appel de la radio, ci-dessous).

### Départ d'une équipe réelle (hors écran)

Dans le pas de la simulation (`Relations.offscreenHour(g, gid, heure)`, appelé par `Simulation.advance` avant chaque heure de chaque groupe, même écriture, aucun tirage, aucun accès aux cases), à partir de l'heure `due` :

- Bloqué tant qu'une expédition (abstraite ou physique) est en cours, sans foyer, ou si l'équipe est trop petite (attente, journal du moteur une fois par raison).
- Partants : vivants **au foyer**, hors chef, combattants, blessure abstraite ≤ `WOUND_MAX` (20), **sans corps** (un corps au foyer veut dire un joueur proche : on attend), par numéro ; taille = min(`TEAM_MAX` = 3, candidats, présents − `MIN_HOME` = 1), au moins `TEAM_MIN` = 2. **Aucun membre créé** : l'équipe vient de l'effectif du registre.
- Dernière zone connue du joueur : son **refuge vanilla** s'il en a un (`SafeHouse.hasSafehouse(compte)`, centre du rectangle, niveau 0), sinon le lieu de la mort.
- Trajet abstrait : `ceil(distance / SPEED)` heures (300 cases par heure, une heure au moins), traque de `HUNT_HOURS` = 12 h à la zone.
- L'équipe devient une **expédition abstraite** `{ place = "revenge", team, departed, returns }` (LK09-T02) : absente du foyer (ni consommation ni blessure horaire, jamais matérialisée au foyer, jamais candidate d'une autre expédition), retour prévu à `leave + travel`. Journal `revenge` : `attempt 1 on <clé>: m-2 m-3 m-5 left for 1000,1600 (kill), 2 h away` ; fait `revengeStarted`.

### Traque à l'écran (à distance)

- Phase `hunt` de `arrive` à `leave`. Chaque minute de jeu (`Relations.huntPass`, `EveryOneMinute`) : si un joueur vivant est à `MAT_RADIUS` = 80 cases de la zone, chaque membre vivant de l'équipe sans corps en reçoit un par le **chemin existant de la matérialisation** (`Materialize.embodyMember` : même PNJ s'il existe, apparence et arme du profil, santé selon la blessure), `PER_PASS` = 2 au plus par passage.
- **Case d'apparition** (`Relations.spawnSquare`) : niveau 0, du côté du foyer (le groupe arrive de chez lui), de `SPAWN_MAX` = 75 cases de la zone vers elle (pas de 5 cases, 12 directions autour de l'axe zone → foyer), **à `SPAWN_MIN` = 40 cases au moins de tout joueur vivant**, chargée, libre (`Bodies.freeSquare`), sans escalier. Aucune case qui convient : **pas de corps** (attente, journal une fois) : jamais d'apparition près d'un joueur, même si le joueur se tient à la zone.
- Comportement `revenge` du cadre de décision (règle `duty`, `ctx.hunt`, clé `hunt<n>`, vigilance `guard`) : marche par étapes de `STEP` = 40 cases (case libre la plus proche, `Bodies.findFreeSquare`) vers une ronde de 4 points à `PATROL` = 8 cases de la zone (départ selon le rang), point suivant à chaque arrivée ou échec ; au retour (`back`), vers le foyer. Faim, soif et fatigue attendent ; menace, peur et blessure passent avant.
- **Engagement par le choix de cible existant** : `Hostility.targetRule` reçoit `revenge` (après le joueur couvert par une trêve, avant la provocation) : la cible d'une vengeance en cours est **attaquée** par tout combattant du groupe qui la voit (raison `revenge`, `Combat.targetFor` → règle `threat` → `fight`). Les autres joueurs suivent les règles ordinaires.
- Corps rendus à la simulation quand plus aucun joueur n'est à 120 cases : les membres restent dans l'équipe (absents du foyer).

### Fin d'une tentative, abandon

| Événement | Effet |
|---|---|
| `leave` atteint, cible vivante | tentative **manquée** : `fails + 1`, journal `attempt n on <clé> failed (k/3): heading home`, phase `back`, retour dans `travel` heures |
| Équipe entière morte | manquée aussi, rien ne revient (`no one came back`) |
| Retour (`returns`, appelé par `simulateHour`) | expédition close (`n back home`), membres présents au foyer ; un membre encore incarné à plus de 10 cases du foyer (joueur qui le suit) retarde le retour d'une heure |
| Après le retour | fin en attente → fin ; `fails` ≥ `MAX_FAILS` = **3** → fin `given_up` (ou `wiped` si la dernière équipe a péri) ; sinon nouveau départ après `RETRY_HOURS` = 24 h |
| **Rancune éteinte** : attitude sortie de `LEVELS` (déclin quotidien vers le plafond du meurtre, ou actes : dons, missions) | pendant le délai : fin `faded` aussitôt ; dehors : l'équipe rentre, fin au retour |
| Cible morte (`OnCharacterDeath`, par clé ou par compte) | fin `avenged` si un corps de l'équipe était à 30 cases, sinon `target_dead` ; l'équipe rentre |

Fin : champ effacé, journal `revenge on <clé> ended: <raison> (n attempt(s), k failed)`, fait `revengeEnded`. La cible n'est plus attaquée pour la vengeance (les règles ordinaires restent : un groupe hostile reste hostile).

Durée de la rancune selon le type, sans autre acte : neutres −54 → méfiants (−44) en 5 jours (la rancune s'éteint souvent avant ou pendant la première traque) ; colons après deux meurtres −70 → −44 en 13 jours ; pillards jamais (plafond −50, hostiles) : seuls les échecs les arrêtent.

### Registre (schéma 1 inchangé)

Champ facultatif du groupe, contrôlé par `Relations.validRevenge` (malformé : oublié avec un avertissement, le groupe garde le reste), ignoré par `LK_Groups` :

```
revenge = { v = 1, key = clé de joueur, u = compte, victim = "m-<k>", sworn = heure, phase = sworn | out | hunt | back,
            due = heure de départ (sworn), n = tentatives, fails = traques manquées,
            zone = { x, y, z, src = kill | safehouse }, team = { "m-<k>" }, dep, arrive, leave, travel (heures),
            ending = avenged | target_dead | faded | given_up | wiped (fin en attente du retour) }
```

Persistant avec le registre des groupes (fichier privé, jamais en ModData globale) ; mémoire seulement : étapes de marche des corps.

### Radio

La radio du carnet (`RadioSurvivor_Server.lua`) n'expose aucune fonction publique pour passer une ligne à l'antenne (`queueAir`, `airCall` sont locales). **Point d'appel** : les faits `revengeSworn`, `revengeStarted`, `revengeEnded` (`LivingKnox.listen`, [api.md](../api.md), « Faits publiés ») ; un abonné du carnet pourra y diffuser une rumeur (« le groupe de … cherche quelqu'un ») quand une API d'antenne existera. Reste à faire (tâche E).

### MP

Tout sur l'autorité (`if isClient() then return end`) : serment, départ, traque, fin. Les clients reçoivent seulement les corps (création serveur), les consignes relayées (LK03), la bulle de la réplique (LK11-T04). Deux joueurs voient donc les mêmes vengeurs, au même endroit, et le serveur seul décide que le joueur visé est une cible.

### Coût

Pas horaire : une lecture de l'attitude par groupe en vengeance. Passage de chaque minute : groupes × joueurs, puis, pour une traque proche d'un joueur, au plus 16 distances × 12 directions par membre à placer.

## Alternatives écartées

- **Vengeurs créés à la zone ou près du joueur** : interdit (section « Écarté » des idées) ; les corps viennent de l'équipe partie du foyer, et à 40 cases au moins de tout joueur.
- **Marche physique depuis le foyer** : le foyer est d'ordinaire hors de toute zone chargée et une consigne ne porte qu'à 60 cases ; le trajet est abstrait, la matérialisation se fait au bord de la zone, côté foyer.
- **Position actuelle du joueur** comme zone : le groupe serait omniscient ; retenu : son refuge déclaré ou le lieu du meurtre.
- **Plusieurs vengeances par groupe** (une par joueur) : équipes concurrentes sur le même effectif ; une à la fois (décision à confirmer).
- **Échec à chaque rencontre perdue** : impossible à juger proprement (fuite, mort d'un vengeur, joueur parti) ; l'échec est la fin de la fenêtre de traque sans la mort de la cible.
- **Tirage aléatoire du serment** : non reproductible et peu lisible ; règle fixe par l'attitude.

## Tests

- Banc lupa `tests/test_lk_revenge.py` (27 tests) : serment selon le type (pillards, neutres, colons au second meurtre), une vengeance par groupe, déjà jurée, trop faible, désactivée ; fait `kill` attribuable et marque « meurtre » ; `npcDied` sans identité du carnet ou sans tueur : rien ; choix de cible : attaque `revenge` (trêve d'abord) ; délai de 72 h puis équipe de combattants hors chef, effectif inchangé, absents du foyer (matérialisation et simulation) ; attente si blessés ou expédition en cours ; trois traques manquées puis abandon `given_up`, journal complet, tous revenus ; rancune éteinte par le déclin (neutres, 5 jours) et par des actes pendant le trajet (retour puis fin `faded`) ; cible morte (`target_dead`, fin immédiate pendant le délai) ; équipe anéantie ; refuge vanilla comme zone ; relecture après redémarrage et contrôle de forme ; mêmes octets du registre heure par heure ou en rattrapage ; pile des corps (MP et solo) : corps de l'équipe seulement, à 40 cases au moins de chaque joueur, côté foyer, jamais au foyer, aucun corps si seules des cases proches sont chargées, ni sans joueur à la zone, comportement `revenge` et marche vers la zone par le cadre de décision, rien chez les clients, équipe rendue à la simulation qui ne reparaît pas au foyer ; suite `lk.revenge` qui passe et qui échoue sur une apparition injectée à côté du joueur ; traductions EN/FR en Latin-1, code ASCII.
- VM Kahlua : non lancée pour ce module (motifs interdits contrôlés dans la source).

### Protocole en jeu

1. Solo (`rstest-solo`, mod de dev, Living Knox activé), dehors, terrain dégagé : `RST.run({ suite = "lk.revenge", tags = "world" })` → PASS pour les deux tests (deux corps notés à 40 cases ou plus, abandon en fin de suite ; délai du serment lu dans l'option `RevengeDelayHours`, changé en mémoire puis remis).
   Les options sandbox de la page Living Knox montrent « Heures avant une vengeance » (FR) / « Hours before a revenge » (EN) avec son infobulle.
2. Solo, carnet lié (personnage créé) : tuer un membre d'un groupe de pillards ou de neutres près de son foyer → bulle « You killed one of ours… », entrée `revenge` dans `LivingKnox.Groups.get("grp-<n>").log` ; pour raccourcir : option sandbox « Heures avant une vengeance » à 12, ou forçage `LivingKnox.Relations.REVENGE.DELAY_HOURS = 2` (remettre à `nil` ensuite), `SPEED = 100000` puis attendre deux heures de jeu loin du foyer ; vérifier que les vengeurs arrivent à pied d'assez loin et attaquent.
3. MP (séance finale) : A tue, B l'accompagne : les vengeurs visent A, pas B (sauf s'il les attaque) ; mêmes corps chez A et B.

## Limites et restes

- ⚠ À vérifier en jeu : cases d'apparition réellement chargées à 40-75 cases (petit écran : zone de 48 cases, apparition alors limitée), trajet réel des étapes de 40 cases (clôtures, portes), engagement contre le joueur, bulle du serment.
- Le serment n'est annoncé par une bulle que si un membre incarné est près de la mort ; aucune réplique au départ ni à la traque (les corps apparaissent à 40 cases au moins) ; radio : point d'appel seulement.
- Zone : refuge vanilla ou lieu du meurtre ; une base non déclarée n'est pas connue (LK11-T07 détectera les signes d'occupation) ; un joueur absent pendant la traque fait échouer la tentative.
- Une seule vengeance par groupe : un second meurtrier pendant une vengeance en cours n'en déclenche pas (son attitude baisse quand même).
- Un groupe matérialisé (joueur près du foyer) ne fait pas partir son équipe : elle attend que le joueur s'éloigne.
- Le fait `kill` est désormais enregistré ici ; une future détection des agressions (LK06) devra éviter de le compter deux fois.
- Les faits `revenge*` ne sont pas relayés en événements publics (`LK_API`).

## Décisions à confirmer

- Serment seulement si l'attitude après le meurtre est `hostile` (colons : au second meurtre) ; rancune vivante tant qu'elle reste `hostile`.
- Une vengeance à la fois par groupe.
- Valeurs : délai 72 h, nouvelle tentative 24 h après le retour, traque de 12 h, 3 échecs, équipe de 2 à 3 combattants hors chef, un membre au foyer, 300 cases par heure.
- Zone = refuge vanilla du compte, sinon lieu du meurtre.
- Apparition à 40 cases au moins de tout joueur, côté foyer, jusqu'à 75 cases de la zone.
- Cible d'une vengeance attaquée par tout combattant du groupe (pas seulement l'équipe), une trêve passant avant.
