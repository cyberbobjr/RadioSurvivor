# Retraite, reddition et appel à l'aide des PNJ

- Tâches : LK06-T05 (création, 2026-10-12) ; s'appuie sur LK05-T02 (cascade, [decisions.md](decisions.md)), LK05-T06 (peur, [besoins.md](besoins.md)), LK05-T08 (alerte, [alerte.md](alerte.md)), LK06-T01 (cible, [cibles.md](cibles.md)), LK06-T02 à T04 (combat, [combat.md](combat.md), [zombies.md](zombies.md)), LK07-T02 (santé de référence, [sante.md](sante.md)) ; suite : LK05-T09 (défense coordonnée du foyer), LK11 (attitude qui suit les agressions, sommations)
- Build : 42.21.0 — Date : 2026-10-12 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Decisions.lua` (règle `threat`, comportements `retreat` et `surrender`, fonctions pures `fleeAngle`, `surrenderTo`, `retreatOf`, `playerSpot` ; autorité : `noteHit`, `callHelp`, `helpFor`, `helpTarget`, `spared`, `defenceContext`, `applyDefence`), `LK_Health.lua` (`Health.applyHit` appelle `Decisions.noteHit` après chaque coup accepté), `LK_Alert.lua` (`Alert.raise`, extrait d'`Alert.observe`). Réglages : `Decisions.CFG.RETREAT`, `SURRENDER`, `HELP`, `HIT_MINUTES`. Tests : `tests/test_lk_decisions.py` (`RetreatSurrenderTests`), `tests/test_lk_combat.py` (`DefenceStackTests`, `SoloDefenceStackTests`, `RetreatSuiteTests`), suite en jeu `lk.retreat` (`dev/.../suites/RST_LKRetreat.lua`).

## Problème

Un PNJ blessé ou à bout de nerfs ne doit pas se battre jusqu'à la mort : il rentre au foyer, ou fuit en s'éloignant de toutes les menaces. Un PNJ pacifique frappé par un joueur peut se rendre plutôt que mourir, et son groupe cesse alors de viser ce joueur tant qu'il ne frappe plus. Un membre attaqué appelle les autres, et les combattants proches viennent l'aider. Tout est décidé par l'autorité, de façon reproductible, et ne produit que des consignes LK03 et des gestes `lkactor_*` existants.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Les coups reçus par un corps de PNJ ne passent que par la santé de référence de l'autorité : `Health.applyHit` (coup d'un joueur contrôlé par `Health.judge`, attaque d'un zombie décidée par `LK_Zombies`). C'est le seul endroit où un coup est su accepté, avec son auteur. | [sante.md](sante.md) ; `LK_Health.lua`, `LK_Zombies.lua` | confirmé statiquement (banc) |
| Gestes affichables : seulement les nœuds générés (`tools/anim_table.json`). `surrender` = `Bob_EmoteSurrender` (emote vanilla de reddition, mains levées, LK06-T12), `crouch` = `Bob_IdleSneak`. | `tools/anim_table.json` ; `LK_Anim.lua` ; `AnimSets/player/emote/surrender.xml` | confirmé statiquement |
| Une réplique de gabarit (`LivingKnox.Speech.say`, clé `IGUI_…`) est traduite par chaque client et n'atteint que les joueurs qui l'entendent ; personne à portée : rien n'est envoyé. | [parole.md](parole.md) ; `LK_Speech.lua` | confirmé statiquement (banc) |
| Une consigne `face` ou `stop` remet le geste au repos : le geste se pose après la consigne, et se repose à chaque passage s'il a changé (même mécanique que le geste d'alerte). | [decisions.md](decisions.md) ; `LK_Directives.issue` | confirmé statiquement (banc) |

## Choix (2026-10-12)

### Place dans la cascade

Aucune règle nouvelle dans `PRIORITIES` (les rangs, donc les tirages, restent ceux de LK05-T02) : la règle `threat` essaie, dans l'ordre, **reddition**, **retraite**, puis combat (`fight`), puis regard, fuite et alerte comme avant.

### Retraite (I6.3, I6.5)

- **Danger** : cible d'attaque (`ctx.target`, joueur ou zombie, renfort compris), coup reçu depuis `HIT_MINUTES` = 2 minutes de jeu, ou menace à fuir (zombie, joueur hostile) à `RETREAT.DIST` = 15 cases au plus.
- **Blessé** : santé de référence / santé de naissance < `RETREAT.HEALTH` = 0,35 (tout membre). **À bout de nerfs** : peur (LK05-T06) ≥ `RETREAT.FEAR` = 85 (tout rôle depuis LK06-T07 ; à partir de 70, un membre apeuré ne se bat plus et fuit ou s'abrite, [decisions.md](decisions.md) « Tout le monde se bat »).
- **Moral du groupe** (`group.morale`, baissé par les morts, LK09-T03) < `RETREAT.LOW_MORALE` = 30 : santé limite relevée de 0,15 (0,50) et peur limite abaissée de 20 (65).
- **Où** : loin du foyer → course vers une case libre du foyer (I6.5, « blessé qui rentre au foyer ») ; sans foyer → fuite pondérée ; au foyer → un combattant à bout de nerfs se terre (arrêt, regard vers la menace, geste `crouch`) ; un **blessé au foyer s'y défend** (pas de retraite) ; LK06-T07 : sous `WOUND_RATIO` (50 %), il ne se bat plus et s'abrite au foyer (comportement `retreat`, accroupi).
- Comportement `retreat` : vigilance `guard`, échéance 3 minutes ; le combat s'arrête (`Combat.leave`). Réengagement : à l'échéance ou quand la règle ne s'applique plus (peur retombée, danger parti).
- **Fuite pondérée** (`Decisions.fleeAngle`, aussi pour `flee`) : somme des directions opposées aux menaces à fuir (à 15 cases au plus), chacune pesée par 1 / distance ; une seule menace donne l'angle d'avant. Menaces symétriques : direction tirée (reproductible). Les écarts ±45°, ±90° de la fuite existante évitent de rester figé.

- LK05-T14 ([decisions.md](decisions.md), « Seuils de danger réglables ») : `RETREAT.DIST` = option `LivingKnox.RetreatDangerDistance` (défaut 8) ; un zombie au-delà de `LivingKnox.ZombieAlertDistance` n'est plus une menace perçue. `HELP.RADIUS` = option `LivingKnox.ReinforcementRadius` (défaut 15). Sans les options : 15 et 20.

### Reddition (I6.11)

- **Qui** : un **non-combattant** (rôle sans `fight` ni `defend`) d'un groupe qui **ne tire pas le premier** (`Hostility.firstStrike` faux : colons, neutres ; jamais un pillard ni un combattant).
- **Quand** : frappé par un joueur depuis 2 minutes, ce joueur à `SURRENDER.KEEP` = 15 cases au plus (perçu, sinon lieu du coup), et santé < `SURRENDER.HEALTH` = 0,6 ; ou **acculé** : joueur hostile vu à `SURRENDER.DIST` = 2 cases au plus.
- **Geste** : arrêt de ses marches, regard vers le joueur, mains levées (geste `surrender`, voir « Reddition visible » ; geste `kneel` jusqu'au 2026-10-13). Comportement `surrender`, vigilance `guard`, échéance 2 minutes, gardé tant que le joueur reste perçu à 15 cases, puis encore `LINGER` = 2 minutes hors de vue.
- **Fin d'hostilité** : tant que la reddition est revue (`Decisions.spared`), le **groupe** ne prend plus ce joueur pour cible : une cible de `Hostility.chooseTarget` épargnée est retirée (le combattant se rabat sur un zombie proche, sinon regarde) et une demande d'aide contre lui n'arme personne. Aucun texte n'est interprété.
- **Rupture** : un nouveau coup accepté de ce joueur sur un membre du groupe rompt la reddition (journal), la défense reprend (appel à l'aide), et aucun membre ne se rend plus à ce joueur pendant `BETRAYED` = 60 minutes.

### Reddition visible (LK06-T12, 2026-10-13)

Demande de l'utilisateur après l'essai `rs.factions.incident` (un ouvrier rendu sans rien dire ni montrer).

- **Geste** : `surrender`, nœud généré `LKActorSurrender` (état `idle`) qui joue `Bob_EmoteSurrender`, le clip de l'emote vanilla « Se rendre » (`ISEmoteRadialMenu`, nœud `player/emote/surrender.xml`, vitesse 0,48 reprise). Le clip anime tout le squelette : joué en corps entier (le joueur ne le prend que pour le haut du corps, sur sa marche). Posé par `Decisions.applyDefence` après l'arrêt et le regard (`setAlertGesture`), reposé à chaque passage tant que dure la reddition ; aucune arme en main (geste hors de `Equipment.HAND_GESTURES`), aucune consigne de marche.
- **Fin** : le geste est retiré quand le comportement change (`Decisions.apply`), **aussitôt** à la trahison (`noteHit`, sans attendre la décision suivante) et quand le membre est oublié (mort, corps parti : `Decisions.forget` passe par `setAlertGesture(id, nil)`), seulement s'il est encore le nôtre.
- **Parole** : une réplique de gabarit `IGUI_LK_Surrender_<1..4>` dite **une fois par reddition**, à sa création (`afterDecision`, même endroit que le journal « surrenders to ») : une reddition revue ou prolongée ne redit rien ; une nouvelle reddition (après la fin) en dit une nouvelle. Trahison : une réplique `IGUI_LK_Surrender_Betrayed_<1..2>` du membre rendu. Variante tirée de (PNJ, minute) par `Decisions.stream` : reproductible, sans LLM. Canal `LivingKnox.Speech.say` (comme les refus d'ordre, E10-T03) : bulle et ligne du chat « dire » chez les joueurs qui entendent, traduite par chaque client (EN, FR). Personne à portée : journal debug seul, la réplique n'est pas retentée.
- **Choix le plus simple (décision à confirmer)** : variantes et textes ci-dessus, aucune réplique propre au type de groupe ni au rôle (le catalogue des « barks » n'a pas de situation `surrender`) ; aucune entrée au journal du groupe (le journal de la console suffit) ; mêmes répliques qu'il soit frappé ou acculé.

### Appel à l'aide

- `Health.applyHit` → `Decisions.noteHit(id, corps, auteur)` pour chaque coup accepté d'un **joueur** ou d'un **zombie vanilla** : coup noté (danger, reddition), puis `Decisions.callHelp` :
  - **alerte du groupe** (`Alert.raise`, menace `help:<clé>` de genre `hostile` ou `zombie`) : alerte nouvelle ou plus grave → journal du groupe (« called by m-2 »), cri vanilla et réplique (LK05-T08) ;
  - **demande d'aide** du groupe (une à la fois, la plus récente), valable `HELP.MINUTES` = 3 minutes : chaque **combattant** sans cible, au même niveau et à `HELP.RADIUS` = 20 cases de la victime, prend l'agresseur pour cible (`reason = "help"`) : zombie encore là, ou joueur présent, vivant, **ni couvert** (trêve, `Hostility.isCovered`) **ni épargné** (reddition). La victime elle-même, si elle combat, se défend aussi.
- Un **combattant qui se retire** passe sa cible aux autres de la même façon (demande d'aide « retreat »).
- Cette défense ne crée aucun fait d'attitude (`hit`, `shot`) : la provocation durable reste à LK11 (voir points ouverts).

### Autorité, déterminisme, coût

Autorité seule (fichier serveur derrière `isClient()`), fonctions de décision pures, aucun tirage hors du flux Park-Miller existant. Mémoire seulement (`Decisions.state.hits`, `help`, `surrenders`, `betrayed`) : un redémarrage les oublie. Coût : une demande d'aide par groupe, une lecture par membre évalué ; pas de parcours de zombies ajouté.

## Alternatives écartées

- **Nouvelle règle de priorité** (« défense ») dans `PRIORITIES` : déplace les rangs et change tous les tirages de LK05-T02 ; la règle `threat` les porte déjà.
- **Reddition de tout membre gravement blessé** (combattants compris) : un combattant blessé se retire déjà ; la reddition reste l'issue des pacifiques (I6.11).
- **Reddition dès qu'un joueur frappe de près** : tout coup de mêlée est porté de près, chaque coup aurait suffi ; la blessure est exigée.
- **Renfort par la seule alerte** (`alert` : regard vers la dernière position) : les combattants restent sur place ; le contrat demande un renfort réel.
- **Écrire un fait `hit` dans l'attitude** à chaque coup : ferait de LK06-T05 le registre des agressions de LK11 (vu, attribuable, trêves, incidents E09-T06).

## Idées reprises

- I6.3 (critères de repli) : santé basse et peur ; réengagement par l'échéance. Munitions épuisées et épuisement : non retenus (le combattant à court passe déjà aux mains nues, LK06-T03).
- I6.5 (fuite pondérée, blessé qui fuit vers le foyer) : retenue.
- I6.11 (reddition) : retenue pour les non-combattants des groupes qui ne tirent pas les premiers.
- I4.6 (se réarmer sur les corps) : non traitée (reste).

## Tests

- Banc lupa `tests/test_lk_decisions.py` (`RetreatSurrenderTests`, 4 tests) : seuils de santé, de peur et de moral, blessé au foyer qui se défend, sans foyer qui fuit, non-combattant blessé qui rentre au lieu de fuir, coup reçu = danger ; fuite pondérée (166° au lieu de 180° avec une seconde menace, symétrie tirée et reproductible) ; reddition (blessé frappé, acculé, regard vers le joueur ou le lieu du coup, jamais en bonne santé, jamais un combattant ni après une trahison, durée et fin hors de vue) ; mêmes entrées → même décision.
- Banc lupa `tests/test_lk_combat.py` : `DefenceStackTests` (serveur + deux clients) et `SoloDefenceStackTests` : coup sur l'ouvrier d'un groupe pacifique → appel à l'aide, alerte aggravée, combattant engagé (« (help) ») ; ouvrier blessé frappé → reddition, geste `kneel`, joueur épargné, combat arrêté ; nouveau coup → reddition rompue, défense reprise ; aide expirée → fin ; combattant blessé loin du foyer → retraite en courant vers le foyer, cible passée au second combattant ; moral bas → retraite à 45 % ; aucune erreur chez les clients. `RetreatSuiteTests` : suite `lk.retreat` jouée sur les doublures.
- Banc lupa `tests/test_lk_surrender.py` (LK06-T12 ; MP serveur + deux clients, puis solo) : une reddition → une seule réplique `IGUI_LK_Surrender_<n>` et le geste `surrender` (aussi chez les deux clients proches par le relais), aucune marche ; aucune deuxième réplique pendant la même reddition ; trahison → mains baissées aussitôt, une réplique de trahison ; fin de reddition → mains baissées, nouvelle reddition → nouvelle réplique ; membre mort → geste retiré ; personne à portée → réplique non retentée. Sur l'ancien code (copie hors dépôt) : 11 échecs sur 12 (aucune réplique, geste `kneel`, clés absentes) ; sans le retrait du geste dans `Decisions.forget` : `test_death_lowers_the_hands` échoue (mains toujours levées).
- En jeu : suite `lk.retreat` (tag `world`), à lancer ; mesure aussi la réplique de reddition et de trahison.

### Protocole en jeu

1. Solo (`rstest*`, Living Knox activé, mod de dev), dans une maison : `RST.run({ suite = "lk.retreat", tags = "world" })` ; rester près des deux PNJ. Attendu `OK` et les lignes `[LKT] measure` : le combattant vient frapper (mode dieu posé par la suite), l'ouvrier lève les mains face au joueur et dit une phrase de reddition (bulle ; ligne `[LKT] measure surrender line: 1 said`), le combattant s'arrête, puis reprend après le nouveau coup (l'ouvrier baisse les mains et dit une phrase de trahison : `measure betrayal: 1 line(s)`) ; enfin le combattant blessé court vers l'est (foyer déplacé).
2. Solo, à la main : groupe de colons matérialisé, frapper un ouvrier à la batte jusqu'à ce qu'il lève les mains en disant sa phrase ; s'écarter à plus de 15 cases : il baisse les mains après 2 minutes de jeu environ.
3. MP (séance finale) : mêmes étapes, les deux clients voient les mains levées, la bulle de reddition et la course de retraite.

## Points ouverts

- ⚠ **Décision à confirmer** : seuils de départ (retraite 35 % de santé ou peur 85 ; moral < 30 : 50 % et 65 ; reddition sous 60 % ou joueur hostile à 2 cases ; aide 3 minutes à 20 cases).
- ⚠ **Décision à confirmer** : profils qui se rendent = non-combattants des groupes qui ne tirent pas le premier ; geste `surrender` (`Bob_EmoteSurrender`, emote vanilla, LK06-T12) ; rendu en corps entier à vérifier à l'œil.
- ⚠ **Décision à confirmer** : un coup reçu arme la défense des combattants proches contre son auteur (même d'un groupe pacifique, sauf trêve ou reddition), sans fait d'attitude ; la provocation durable reste à LK11.
- ⚠ Un blessé au foyer s'y défend ; le chemin de retour au foyer peut passer près de la menace (chemin le plus court, LK04-T15).
- Aucune réplique de demande d'aide propre (réplique `alert` existante seulement) ; aucune fouille des corps pour se réarmer (I4.6) ; mémoire seulement ; aucune retraite hors écran.
