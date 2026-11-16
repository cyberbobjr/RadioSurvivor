# ADR — Les PNJ se cèdent le passage

| | |
|---|---|
| Date | 2026-11-15 |
| Statut | Accepté |
| Décideur | utilisateur |
| Plan associé | [LK18 — Céder le passage](../../annexes/plans-termines/LK18-ceder-le-passage.md) |
| Références | [Déplacements des PNJ : chemin du jeu](adr-chemin-vanilla.md) ; [Registre des routines](adr-registre-routines.md) ; [Remise en ordre SOLID](adr-remise-en-ordre-solid.md) |

## Contexte

Observation de l'utilisateur, le 2026-11-15 : des PNJ immobiles restent sur le passage d'autres PNJ, qui se bloquent
contre eux. Le corps d'un PNJ est un zombie : deux corps ne se traversent pas.

Aujourd'hui, un PNJ bloqué ne sait pas ce qui le bloque. Mur, porte ou autre PNJ, il réessaie, puis abandonne (« stuck »).
Aucun PNJ ne s'écarte pour un autre, et rien n'empêche de s'arrêter dans une porte ou un couloir.

L'utilisateur propose que les PNJ « communiquent entre eux », à la manière d'un automate cellulaire, et demande des
systèmes, comportements et actions conformes aux principes SOLID.

## Décisions (confirmées par défaut, le 2026-11-15)

- **D01 — Règle locale entre voisins, pas de plan global.**
  - Un PNJ qui avance sans progresser regarde les cases devant lui, sur son trajet.
  - Un autre PNJ y fait-il obstacle ? Le PNJ bloqué demande à l'autorité un passage.
  - L'autorité tranche avec deux seules informations : la priorité des deux PNJ et les cases libres autour du bloqueur.
  - Aucun trajet ne tient compte des autres PNJ d'avance (pas de retour à un calcul d'itinéraire maison).
- **D02 — Priorité déclarée par chaque comportement.**
  - Chaque comportement ou directive (fuite, combat, soin, défense, expédition, corvée, garde, repos…) déclare sa priorité
    de passage là où il est défini, par un registre (`Passage.priority(kind, n)`).
  - Le système de passage ne connaît aucune liste de comportements (ouvert/fermé).
  - Un comportement sans déclaration a la priorité par défaut, la plus basse.
  - À priorité égale, le plus petit identifiant de PNJ passe.
- **D03 — Céder est une action.**
  - Le bloqueur de priorité plus basse reçoit l'action « s'écarter » : un pas vers une case libre voisine, hors du trajet
    du demandeur. Il attend que l'autre soit passé, ou une durée bornée, puis reprend ce qu'il faisait.
  - L'action passe par le registre des actions et directives existant, comme les autres.
  - Face à face dans un couloir sans case libre : celui de priorité plus basse recule jusqu'à une case libre.
  - Le bloqueur a la priorité ou ne peut pas bouger (blessé, en combat, mort) : le demandeur garde le traitement actuel
    de « stuck ».
- **D04 — Prévenir les bouchons.** Une place d'arrêt (garde, attente, bavardage, repas, corvée) n'est jamais une case de
  porte ou de portail, ni un seuil, ni un passage d'une seule case de large ; elle se décale à la case libre la plus
  proche. La règle vit dans le choix des places d'arrêt, en un seul endroit, pas dans chaque comportement.
- **D05 — Responsabilités séparées (SOLID).**
  - Détection du blocage par un PNJ (exécutant, données de progression).
  - Arbitrage (autorité, fonction pure : deux PNJ, deux priorités, cases libres → décision).
  - Registre des priorités.
  - Action « s'écarter ».
  - Règle des places d'arrêt.

  Chacun dans son propre module, dépendances injectées. Aucun `if kind ==` sur une liste fermée.
- **D06 — Autorité et MP.** L'autorité seule arbitre et ordonne. Le client propriétaire signale le blocage (cible voisine
  vue) et exécute l'action. Le serveur vérifie que les deux PNJ sont voisins et que la case de retrait est libre.

## Mise à jour du 2026-11-15 (soir) : un PNJ immobile cède toujours

Constat de l'utilisateur et campagne MP du 2026-11-15 (serveur, `rs-mp-server`) : des PNJ immobiles ne bougent pas
quand ils bloquent. Les signalements arrivent bien à l'autorité, mais tous les arbitrages ont rendu « rien » :
« blocker has priority (patrol vs chore) », « blocker has priority (guard vs meal) », « no free square for the blocker
(chore vs guard) ». La règle D02 seule laisse un PNJ en corvée ou au repas planté sur le passage d'un PNJ de garde.

- **D07 — Un PNJ immobile cède toujours à un PNJ en marche**, quelle que soit sa priorité, sauf s'il ne peut pas bouger
  (mort, en combat, soigné ou soignant). La priorité de D02 ne départage que deux PNJ en marche. Remplace, pour ce cas,
  la dernière puce de D03 (« le bloqueur a la priorité »).
- **D08 — Pas de case libre voisine : on cherche plus loin.** Le bloqueur recule ou s'écarte vers la case libre
  joignable la plus proche, jusqu'à 3 cases (cases de passage comprises : il s'agit de libérer le passage quelques
  secondes, pas de s'y arrêter durablement).

Décisions D01 à D06 inchangées par ailleurs.

## Conséquences

- Les PNJ se croisent dans les portes et les couloirs du foyer sans s'arrêter longtemps. Un PNJ immobile ne bloque plus
  un passage.
- Un nouveau comportement déclare sa priorité dans son propre fichier ; le système de passage ne change pas.
- La preuve est au banc pour l'arbitrage (fonction pure) et le registre, et en jeu en solo et en MP pour l'action (suite
  dédiée : deux PNJ face à face dans une porte, un PNJ de garde sur un seuil).
