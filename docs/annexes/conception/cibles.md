# Choix de cible des groupes

- Tâches : LK06-T01 (création) ; servira LK06-T02 (mêlée), LK06-T03 (tir), LK11-T02 (sommations), E09-T05 (trêves), E09-T06 (incidents), E10-T04 (trêves gardées par un PNJ parti)
- Build : 42.21.0 — Date : 2026-10-12 — Statut : brouillon

Code : fin de `media/lua/server/LivingKnox/LK_Hostility.lua` (`Hostility.targetRule`, `chooseTarget`, `candidatesOf`, `provoked`, `firstStrike`, `isCovered`, `isIncidentAuthor`, réglages `Hostility.TARGET`). Tests : `tests/test_lk_hostility.py` (`TargetTests`, `SoloTargetTests`).

## Problème

Avant tout combat, le serveur doit dire **qui** un membre d'un groupe peut viser et **comment** (attaquer, ou seulement avertir), d'après l'attitude du groupe envers chaque personnage joueur ([attitude.md](attitude.md)). Critères : un groupe neutre n'ouvre jamais le feu sans provocation ; la décision est la même pour tous les clients ; un joueur couvert par une trêve n'est pas une cible, sauf l'auteur d'un incident ouvert.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Un client MP charge aussi `media/lua/server` : la décision reste derrière la garde `isClient()` du module. | base `mod-loading.md` | confirmé statiquement |
| Le client propriétaire d'un corps n'est qu'un exécutant (consignes LK03) ; une décision prise par le serveur seul, sans tirage, est la même pour tous. | [decisions.md](decisions.md), [consignes.md](consignes.md) | confirmé statiquement (banc) |
| La perception d'un PNJ arrive au serveur par le rapport d'état (`Senses.perceived`, comptes `u`, vu `s`, entendu `h`, `stale`). | [perception.md](perception.md) | confirmé statiquement (banc) |
| Le jour de jeu change à 7 h (`getWorldAgeHours() / 24`). | base `api-42-21.md` | confirmé statiquement |

## Choix

### Règle par joueur (`Hostility.targetRule`, pure)

Dans l'ordre, la première qui s'applique :

| # | Condition | Résultat | Raison |
|---|---|---|---|
| 1 | auteur d'un incident ouvert avec ce groupe (crochet `LivingKnox.Hooks.incident`) | attaque | `incident` |
| 2 | joueur couvert (crochet `LivingKnox.Hooks.covered`) | rien | `covered` |
| 2b | cible d'une vengeance jurée par ce groupe (LK11-T05, `Hostility.isRevengeTarget` → `LivingKnox.Relations.revengeAgainst`, [vengeance.md](vengeance.md)) ; une trêve passe avant | attaque | `revenge` |
| 3 | provocation : agression `hit`, `shot` ou `kill` envers le groupe (vue ou attribuable, faits gardés de la paire d'attitude) datée du jour ou des `PROVOKE_DAYS` (1) jours précédents | attaque (défense) | `provoked` |
| 4 | niveau `hostile` | attaque si le type **tire le premier**, sinon avertissement | `hostile` |
| 5 | niveau `wary` (méfiant) | avertissement | `wary` |
| 6 | sinon (`cautious`, `favorable`, `trusting`) | rien | — |

- **Tirer le premier** : hostilité du type de groupe ≥ `TARGET.FIRST_STRIKE` (75). Pillards (90) : oui ; colons (10) et neutres (45) : non. Un groupe qui ne tire pas le premier n'attaque donc **jamais** sans incident ni provocation : il avertit. La séquence d'avertissement (sommation, distance, délai, escalade) est LK11-T02 ; ici, seule l'action `warn` est décidée.
- **Vol** (`theft`) et faits de mission ne sont pas des provocations : ils baissent l'attitude (jusqu'à `hostile`), donc au plus un avertissement chez un groupe neutre.
- Une agression sort de la provocation après `PROVOKE_DAYS` jours, ou quand trois faits plus récents la poussent hors de la paire (des actes positifs valent réparation). Le marqueur de meurtre n'est pas une provocation à lui seul : il plafonne le déclin de l'attitude ([attitude.md](attitude.md)).

### Choix entre plusieurs joueurs (`Hostility.chooseTarget(groupId, npcId, candidats, jour)`)

- Candidats `{ u = compte, key = clé de joueur ou nil, d = distance }` ; un compte en double n'est compté qu'une fois (la première entrée).
- Sortie `{ target, list }` : décisions avec action seulement, triées **attaque avant avertissement**, puis raison (`incident`, `revenge`, `provoked`, `hostile`, `wary`), distance, compte. `target` = la première. Aucun tirage : même entrée, dans n'importe quel ordre, même sortie.
- Joueur sans clé (aucune identité de personnage du carnet) : niveau de départ du type, ni couvert ni provocateur (les crochets ne sont pas appelés).
- Lecture seule : aucune paire d'attitude n'est créée.
- `Hostility.candidatesOf(perception, joueurs)` : joueurs **vus** (`s`) de la perception, vivants et présents dans la liste des joueurs du serveur, avec leur clé (`keyOf`) ; perception absente ou périmée : aucun. Un joueur seulement entendu n'est pas un candidat (on ne vise pas un bruit).

### Crochets facultatifs

| Crochet | Signature | Absent | Erreur | Valeur autre que `true` |
|---|---|---|---|---|
| `LivingKnox.Hooks.covered` | `(groupId, playerKey, npcId) -> boolean` | personne couvert | **couvert** (prudence : on ne tire pas sur la foi d'une erreur) | non couvert |
| `LivingKnox.Hooks.incident` | `(groupId, playerKey, npcId) -> boolean` | aucun incident | pas d'incident | pas d'incident |

Erreur : isolée par `pcall` (code d'un autre sous-système), journalisée (`ERROR hook <nom> failed for <grp>/<clé>: ...`) et comptée (`Hostility.hookStats`). Une seule implémentation prévue, dans `RS_Factions` (E09-T05 pour les trêves de groupe, E10-T04 pour celles gardées par un PNJ parti, E09-T06 pour les incidents).

**Décision à confirmer** : le plan ne nomme qu'un crochet (`covered`) ; l'exception « auteur d'un incident ouvert » demande de savoir quels incidents sont ouverts, état tenu par `RS_Factions` (E09-T06). Retenu : un second crochet `incident`, plutôt que de laisser `covered` rendre faux pour l'auteur (l'exception resterait alors cachée dans `RS_Factions`) ou de déduire l'incident de la provocation de LK (elle ne suit pas la décision du LLM : maintien, réparation, rupture).

### Déterminisme et autorité

La décision n'est calculée que par l'autorité (serveur dédié ou hébergé, solo), à partir de son registre d'attitudes, de ses crochets et de la perception acceptée ; rien n'est tiré au hasard ; l'ordre de départage est total. Les clients ne reçoivent que la consigne qui en découlera (LK06-T02/T03, LK11-T02).

## Alternatives écartées

- Groupe neutre qui tire sur un joueur hostile après un délai sans provocation : contraire au critère d'acceptation ; l'escalade sans tir appartient à LK11-T02.
- Provocation dérivée du niveau d'attitude seul : un vol répété ferait tirer un groupe neutre.
- Cible choisie par le client propriétaire : décisions différentes selon les machines.
- Tirage pondéré entre cibles : inutile pour la justice et source de divergences.

## Idées reprises

- I6.7 (tempérament, novice qui ne tire pas le premier, agression mémorisée par le groupe) : retenu au niveau du **groupe** (type qui tire le premier ou non ; agression mémorisée par la paire d'attitude du groupe, provocation pendant `PROVOKE_DAYS` jours). Le tempérament **individuel** (novice) n'est pas fait ici.

## Tests

- Banc lupa (`tests/test_lk_hostility.py`, `TargetTests`, serveur dédié + deux clients ; `SoloTargetTests`, solo) : table de vérité complète de la règle (aucune attaque sans incident ni provocation hors type qui tire le premier), colons et neutres à chaque niveau et après vols répétés (avertissement seulement), fenêtre de provocation, agression attribuable, réparation par actes positifs, pillards qui attaquent, crochet `covered` (absent, vrai, non booléen, erreur), crochet `incident` (perte de protection, erreur), ordre et indépendance de l'ordre d'entrée, doublons, lecture seule, refus, candidats tirés de la perception (vus, vivants, connus, périmée).
- En jeu : aucun (pas encore de combat branché).

## Points ouverts

- Branchement dans la cascade (LK06-T02, [combat.md](combat.md)) : `chooseTarget` est appelé pour chaque combattant par `Combat.targetFor` ; une cible d'action `attack` donne le comportement `fight` (mêlée). ⚠ Reste le tir (LK06-T03). Sommation (action `warn`) : LK11-T02, [sommations.md](sommations.md).
- Crochet `covered` implémenté par `RS_Factions.covered` (E09-T05, [accords.md](accords.md)) ; le constat d'application lit `Decisions.aims` (numéro d'évaluation de chaque membre, joueur visé). ⚠ Crochet `incident` et trêves gardées par un PNJ parti : E09-T06, E10-T04.
- ⚠ Tempérament individuel d'un membre (novice qui ne tire pas le premier, I6.7) : à décider avec le combat.
- ⚠ Calibrage de `FIRST_STRIKE` et `PROVOKE_DAYS` en jeu.
