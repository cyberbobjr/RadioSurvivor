# Avertissements et sommations

- Tâches : LK11-T02 (création, 2026-10-12) ; s'appuie sur LK06-T01 (action `warn` de `Hostility.chooseTarget`, [cibles.md](cibles.md)), LK11-T03 ([attitude.md](attitude.md)), LK11-T04 et LK11-T09 (parole, [parole.md](parole.md)), LK06-T02 et T03 (engagement, tir, [combat.md](combat.md)), LK05-T09 ([defense.md](defense.md))
- Build : 42.21.0 — Date : 2026-10-12 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Encounters.lua` (`LivingKnox.Encounters`, autorité seulement), branché dans `LK_Decisions.lua` (contexte `ctx.warn`, comportement `warn` de la règle `threat`, `Decisions.apply`, `Decisions.forget`), activité `watch` dans `LK_Needs.lua`, répliques `IGUI_LK_Warn_*` dans `Translate/EN|FR/IG_UI.json`. Réglages : `Encounters.CFG`. Tests : `tests/test_lk_encounters.py`, suite en jeu `lk.warn` (`dev/.../suites/RST_LKWarn.lua`).

## Problème

Un joueur que le groupe tient pour méfiant (ou hostile, pour un type qui ne tire pas le premier) approche du foyer ou du groupe. Le groupe ne doit ni l'ignorer ni lui tirer dessus d'emblée : il le somme de s'arrêter, montre son arme, laisse un délai, puis durcit le ton s'il insiste, et se calme s'il recule. Critères : séquence identique pour deux observateurs ; **jamais de tir sans sommation pour un groupe neutre**.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Un client MP charge aussi `media/lua/server` : garde `isClient()` en tête du module. | base `mod-loading.md` | confirmé statiquement |
| Le serveur n'anime ni ne déplace un corps : seuls les consignes LK03 (`face`, `stop`), les gestes (relais `animState`), les répliques (`speech`) et les effets de tir (`combatShot`) partent vers les clients proches, tous décidés par l'autorité. | [consignes.md](consignes.md), [parole.md](parole.md), [combat.md](combat.md) | confirmé statiquement (banc) |
| Une consigne `face` remet le geste au repos : le geste de sommation se pose après elle. | `LK_Directives.lua` ; [alerte.md](alerte.md) | confirmé par le banc |
| Le serveur MP ne traduit pas : les répliques partent en clés, traduites par chaque client. | base `api-42-21.md` ; [parole.md](parole.md) | confirmé statiquement |
| Les gestes `guard`, `aim` et `shoot` mettent l'arme en main sur chaque machine d'affichage (`Equipment.HAND_GESTURES`). | [equipement.md](equipement.md) | confirmé statiquement |

## Choix

Retenu le 2026-10-12 (LK11-T02) dans le cadre des décisions LK11-T01 et de la règle de cible de LK06-T01.

### Qui est averti, par qui

- Joueur **vu** par un membre combattant (`Hostility.candidatesOf`), pour qui `Hostility.chooseTarget` rend l'action `warn` (raisons `wary`, ou `hostile` d'un type qui ne tire pas le premier), et **dans la zone** :
  - foyer : à `HOME_ZONE` (14) cases en x et en y de la case du foyer, un étage d'écart au plus ;
  - groupe : à `MEMBER_ZONE` (10) cases du guetteur (groupe sans foyer, membre loin du foyer).
  - LK05-T14 : rayons réglables par les options `LivingKnox.WarnHomeRadius` (défaut 14) et `LivingKnox.WarnGroupRadius` (défaut 10), distances de sécurité = la moitié (`Encounters.radii`) ; sans les options, `HOME_ZONE`/`HOME_SAFE` et `MEMBER_ZONE`/`MEMBER_SAFE`. Voir [decisions.md](decisions.md), « Seuils de danger réglables ».
- **Distance de sécurité** (rayon documenté) : `HOME_SAFE` (7) cases du foyer, `MEMBER_SAFE` (5) cases du guetteur. La franchir presse l'escalade (étape suivante dès `MIN_STEP_MS`).
- Une rencontre par (groupe, compte), menée par **un guetteur** : le premier combattant évalué qui voit le joueur (ordre des membres de la cascade, déterministe) ; remplacé par un autre combattant qui voit le joueur si le guetteur n'est plus évalué depuis `WARNER_MS` (10 s). Les autres membres gardent leur cascade (regard, alerte, défense).
- **Aucune interprétation du texte du joueur** : seuls comptent la distance, la vue et les actes enregistrés par `LK_Hostility` (règle du projet : aucune heuristique de langue).

### Séquence (`Encounters.advance`, pure)

| Étape | Réplique | Geste | Passage à la suivante |
|---|---|---|---|
| 1 `warned` | `IGUI_LK_Warn_1_1` ou `_1_2` | `guard` (arme en main), arrêt, regard vers le joueur | réplique **entendue** par le joueur, puis tolérance `TOLERANCE_MS` (méfiant 10 s, hostile 6 s) ou distance de sécurité franchie après `MIN_STEP_MS` (2,5 s) |
| 2 `aimed` | `IGUI_LK_Warn_2_1` ou `_2_2` (dernière sommation) | `aim` (arme braquée) | même règle |
| 3 `final` | `IGUI_LK_Warn_3_shot` après un coup de semonce, sinon `IGUI_LK_Warn_3_hold` | `aim` (`shoot` pendant `SHOT_MS` pour le coup de semonce) | aucune : l'arme reste braquée |

- **Entendue** : le compte du joueur figure parmi les auditeurs rendus par `Speech.say` (règle de lecture complète de la bulle vanilla) ; sinon la réplique est redite après `MIN_STEP_MS` et la séquence n'avance pas. Une étape n'est donc jamais sautée.
- **Coup de semonce** (`Encounters.mayShoot`) : seulement à l'étape finale, pour un **type qui tire le premier** (`Hostility.firstStrike`), avec une arme à feu chargée (`Combat.weaponOf`, `Ammo.loaded`), après les **deux sommations entendues**, au plus un par rencontre. Une cartouche est retirée de l'arme (`Ammo.consume`) avant tout effet, puis `Combat.shotEffects` : bruit pour les zombies, son vanilla de l'arme et éclair joués une fois par chaque client proche. **Aucun dégât, aucun ordre de combat.**
- **Groupe neutre** (type qui ne tire pas le premier : colons, neutres) : **jamais de tir** pendant la séquence ; l'étape finale garde l'arme braquée.
- **Engagement** : seulement quand `Hostility.targetRule` rend `attack` pour ce joueur (provocation : coup, tir ou meurtre vu ou attribuable ; incident ouvert). La cascade prend alors `fight` (`Combat.apply` → `Combat.engage`), ou `defend` si la défense du foyer est en cours, avant la sommation ; la rencontre est close (`escalated`). La séquence elle-même n'appelle jamais `Combat.engage`.
- **Repli** : recul de `BACKOFF` (2) cases depuis la distance la plus courte de l'étape : une étape de moins (arme abaissée, sans réplique) ; sortie de la zone ou joueur perdu de vue depuis `LOST_MS` (4 s) : fin de la sommation, réplique `IGUI_LK_Warn_Back`, le membre reprend sa cascade. Attitude remontée (le joueur n'est plus averti) : fin sans réplique.
- **Reprise** : retour dans la zone dans les `RESUME_MS` (2 min) : `IGUI_LK_Warn_Again`, puis l'étape la plus haute atteinte ; au-delà, la rencontre est oubliée et tout recommence à l'étape 1.

### Place dans la cascade

Règle `threat` de `LK_Decisions` : reddition, retraite, **sommation** (`warn`, si aucune cible d'attaque `ctx.target` ni cible de défense), défense, combat, regard ou fuite, alerte. Comportement `warn` (vigilance `guard`, réservé aux rôles qui permettent `fight` ou `defend`), état d'une minute, clé `p<compte>` (même clé de menace que le regard : la menace n'est comptée qu'une fois par heure). Activité des besoins : `watch`.

### Diffusion et déterminisme

Tout est décidé par l'autorité, sans tirage : réplique choisie par une empreinte de (groupe, compte, étape, numéro de la rencontre), étapes réglées par l'horloge de l'autorité. Les clients reçoivent les mêmes consignes, les mêmes gestes, les mêmes répliques (une par auditeur, même identifiant) et le même coup de semonce : deux observateurs voient la même séquence. Mémoire seulement (au plus `MAX` = 64 rencontres) : un redémarrage oublie les rencontres, la cascade les refait.

## Décision à confirmer

Le plan ne dit pas qui peut tirer un coup de semonce ni comment finit l'escalade d'un groupe neutre. Retenu (option la plus simple, la plus proche de la règle de LK06-T01) : coup de semonce réservé aux types qui tirent le premier (pillards), au plus un par rencontre ; un groupe neutre n'y tire jamais et garde l'arme braquée ; l'engagement ne vient que de `targetRule` (provocation, incident), jamais de la seule insistance du joueur. Écarté : coup de semonce pour tous les types (contraire à « l'escalade sans tir » de [cibles.md](cibles.md) pour les neutres) ; engagement après une sommation ignorée (ferait tirer un groupe neutre sans provocation).

## Alternatives écartées

- Sommation par tous les membres : bruit, répliques en double ; un guetteur suffit, les autres regardent.
- Réplique par `Speech.bark` : délais `GAP_MS` / `SAME_MS` trop longs pour une escalade de quelques secondes ; `Speech.say` avec des clés propres.
- Délais en minutes de jeu : une sommation dure quelques secondes réelles, quelle que soit la durée du jour ; horloge réelle de l'autorité.
- Lecture du chat du joueur (« je m'en vais », « ami ») : interdit (aucune heuristique de langue).

## Idées reprises

- I9.2 (avertissements gradués à l'approche d'un foyer, arme braquée, délai de tolérance) : séquence en trois étapes, tolérance selon l'attitude, distance de sécurité, repli et reprise. Écriture indépendante : aucun code d'A-Life consulté pour l'écrire.

## Tests

- Banc lupa (`tests/test_lk_encounters.py`) : séquence (tolérance méfiant et hostile, sommation non entendue qui bloque, distance de sécurité, étape finale), recul d'une étape, fin hors zone, reprise à l'étape atteinte, oubli après `RESUME_MS` ; coup de semonce permis (type, arme chargée, deux sommations, un seul) ; zones ; répliques déterministes et traduites (EN, FR) ; place de `warn` dans la cascade ; pile complète en solo (groupe neutre armé : deux sommations, arme braquée, aucun tir, repli, reprise, provocation qui engage ; type qui tire le premier : un coup de semonce après deux sommations, cartouche retirée, aucun dégât ; sommations non entendues : aucune escalade ni tir ; attitude remontée : fin sans réplique) ; serveur dédié + deux clients (mêmes gestes, mêmes consignes et mêmes répliques chez A, averti, et B, témoin ; rien côté client).
- En jeu : suite `lk.warn` (tag `world`) : `RST.run({ suite = "lk.warn", tags = "world" })`.

## Points ouverts

- ⚠ Rayons et délais à recalibrer en jeu (lisibilité des bulles, temps de réaction du joueur).
- ⚠ Un joueur en véhicule est traité comme à pied (aucune règle propre).
- ⚠ Un guetteur ne s'adresse qu'à un joueur à la fois (sa rencontre la plus avancée) ; ses autres rencontres attendent sans avancer (réplique non dite, donc non entendue). Plusieurs intrus : un guetteur chacun seulement si d'autres combattants les voient.
- ⚠ MP à valider à la séance finale (deux clients).
