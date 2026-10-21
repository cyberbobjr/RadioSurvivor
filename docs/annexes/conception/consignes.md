# Consignes de déplacement et relais de pose

- Tâches : LK02-T07 (création), LK03-T01 (révisions, envoi aux proches, bail et réémission, 2026-10-10), LK03-T02 (bail des consignes closes, seuils dans `Config.REPORTS` : [rapports.md](rapports.md)), LK03-T03 (transfert de propriété sans perte d'état, remise, reprise rapide, 2026-10-10) ; s'appuie sur LK02-T02 (corps, liaison), LK02-T04 (garde, trajets), LK02-T05 (gestes), LK02-T10 (mesures de marche) ; suite : LK02-T08 (mesures de jalon), LK04 (obstacles), LK05 (décisions), LK09 (hors écran)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-09 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Directives.lua` (`LivingKnox.Directives`, autorité), `media/lua/client/LivingKnox/LK_Executor.lua` (`LivingKnox.Executor`, machine qui simule le corps), `media/lua/client/LivingKnox/LK_Presentation.lua` (`LivingKnox.Presentation`, autres clients). Contraintes de base : [corps-et-animations.md](corps-et-animations.md) (marche, états réseau), [neutralisation.md](neutralisation.md) (garde, `useless`, trajets), [corps-registre.md](corps-registre.md).

## Problème

Le serveur décide où va un PNJ (aller à une case, s'arrêter, se tourner) ; le corps doit y aller quel que soit le client qui le simule, sans demi-tour ni arrêt durable quand le propriétaire change, et les autres clients doivent voir la marche, l'arrêt et l'orientation. Le serveur ne fait confiance qu'au propriétaire du corps.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Un seul simulateur par zombie : le client propriétaire, sinon le serveur. Un zombie distant suit la position réseau (destination réécrite à chaque paquet, téléport au-delà de 3 cases) et ne peut pas chercher de chemin. | base `multiplayer.md` « un seul simulateur » ; `J/characters/NetworkZombieAI.java:235-276` | confirmé statiquement |
| Côté serveur, `getOwnerPlayer()` est le joueur de la connexion propriétaire (posé avec `setOwner`), `nil` quand le serveur simule. | `J/popman/NetworkZombieManager.java:137-181` ; `J/characters/component/NetworkZombieComponent.java:23-41` | confirmé statiquement |
| `pathToLocation(int, int, int)` n'est pas bloqué par `allowRepathDelay` (seuls `pathToLocationF` et `pathToCharacter` le sont chez `IsoZombie`). | `J/characters/IsoGameCharacter.java:5962-5966` ; `J/characters/IsoZombie.java:944-958` | confirmé statiquement |
| `pathToAux` : ligne dégagée → `bMoving` (état `walktoward`), sinon `bPathfind` ; **sur le serveur, jamais `bPathfind`**. `WalkTowardState.enter` renvoie un zombie `useless` au repos ; `PathFindState` ne teste pas `useless`. | `J/characters/IsoGameCharacter.java:5923-5958` ; `J/ai/states/WalkTowardState.java:56` ; base `zombies-as-npc-bodies.md` | confirmé statiquement ; marche `pathfind` + `useless` mesurée (6,5 cases en 8 s, LK02-T10) |
| `PathFindState` efface `bPathfind` et `bMoving` en échec comme en succès : la fin d'une recherche ne dit pas si la case est atteinte. | `J/ai/states/PathFindState.java:51-71` | confirmé statiquement |
| `bPathfind` et `bMoving` faux → transition vers `idle` (propriétaire, `bClient` faux). | `media/actiongroups/zombie/pathfind/to_idle.xml` | confirmé statiquement |
| Direction : `setDirectionAngle(degrés)` pose le vecteur (cos, sin) ; est = 0, sud (y croissant) = 90. Chaque paquet zombie porte la direction et la réécrit chez le destinataire ; le serveur force un envoi quand la direction (8 secteurs) change. | `J/characters/IsoGameCharacter.java:2626-2635` ; `J/iso/IsoDirections.java:13-20` ; `J/characters/NetworkZombieAI.java:196, 271, 282-294` | confirmé statiquement |
| `sendClientCommand` / `sendServerCommand` : fiables, **non ordonnées** ; table vide reçue `nil` ; en solo, pas d'envoi serveur. | base `multiplayer.md` | confirmé statiquement |
| Heure serveur synchronisée sur un client : `GameTime.getServerTimeMills()`, 0 avant la synchronisation. | base `multiplayer.md` « Horloge réelle synchronisée » | confirmé statiquement |

## Choix (2026-10-09)

### Messages (module `LivingKnox`)

| Commande | Sens | Contenu | Ordre |
|---|---|---|---|
| `dirState` | serveur → joueurs à `NEAR_RADIUS` cases du corps et propriétaire (LK03-T01), réémis (voir « Révisions, envoi aux proches et réémission ») | `{ rev, d = { [npcId] = { r, v, l, o, op, x, y, z, g, a, done, s, w, k } \| { r, gone = true } } }`, PNJ par PNJ | `r` croissant à chaque envoi ; envoi de `r` inférieur ou égal au dernier reçu pour ce PNJ ignoré |
| `dirReport` | exécutant désigné → serveur | `{ id, v, l, s, x, y, z, a, n, t, why, k, wd }` (`wd` : détail d'un échec, LK04-T05) | `n` croissant dans un même bail `l` ; plus ancien ignoré |
| `dirAsk` | client → serveur, copie d'un corps apparue chez lui (LK03-T01) | `{ ids = { npcId, … } }` (16 au plus) | réponse `dirState` à ce client seul |
| `animState` (pose et geste, LK03-T05) | serveur → joueurs à `NEAR_RADIUS` cases et propriétaire, regroupé et borné (`LK_Relay.lua`, voir `corps-et-animations.md`, « Relais des gestes ») ; au client qui envoie `guardHello` (états à sa portée) | `{ d = { [npcId] = { r, g, p = { pr, v, s, a, x, y, z, t, ts } } \| { r, gone = true } } }` | `r` croissant à chaque envoi, `pr` croissant par PNJ |
| `npcHand` | serveur → nouveau propriétaire et ancien détenteur (LK03-T03), et au propriétaire qui la demande | `{ r, d = { [npcId] = { r, o, l, hp, w, er } } }` (réservés : `rs`, `tgt`, `am`) | `r` croissant par PNJ (même compteur que `dirState`) ; plus ancien ignoré |
| `dirClaim` | client dont la copie est locale sans remise (LK03-T03) | `{ ids = { npcId, … } }` (16 au plus, une demande par PNJ et par 2 s) | réponse `npcHand` (et bail) au seul propriétaire réel |

- Consigne `op` : `move` (case `x, y, z`, geste `g` = `walk` | `run` | `crouch` ; facultatifs depuis LK05-T12 : points de passage `w = { { x, y }, … }` et étape courante `k`, voir « Points de passage »), `stop`, `face` (angle `a` en degrés : `N`, `NE`… ou nombre). `v` : numéro de consigne, croissant sur toute la session, jamais réutilisé ; `s` : `issued`, `moving`, puis `arrived` | `failed` | `stopped` | `faced` avec `done = true`.
- Rapport `s` : `moving` (au départ, puis au plus une fois par seconde), `arrived`, `failed` (avec `why`), `stopped`, `faced`. `t` = heure serveur synchronisée du propriétaire (mesure du relais). `k` (facultatif, LK05-T12) : étape en cours chez l'exécutant.

### Autorité (`LK_Directives`)

- `Directives.moveTo(id, x, y, z, geste)`, `stop(id)`, `face(id, dir)` : PNJ relié à un corps présent, Living Knox activé ; case visée chargée, praticable (`isFree(false)`), à 60 cases au plus. Rendent le numéro `v`, ou `nil` et une raison. Geste réglé par `LivingKnox.Anim` (geste de la consigne en route ; `idle` à l'arrivée, à l'arrêt et en échec, `crouch` conservé à l'arrivée d'un trajet accroupi).
- **Mémoire seulement** : un redémarrage abandonne le trajet (le corps reste à sa position sauvegardée, au repos). Persister rejouerait un ordre périmé ; les décisions (LK05) réémettront une consigne à jour.
- **Contrôles d'un rapport** (serveur) : consigne courante (`v`) non close, sinon ignoré (`stale`) ; état cohérent avec l'opération ; corps présent ; **expéditeur = `getOwnerPlayer()`** et **bail courant `l`** (LK03-T01 ; bail plus ancien : ignoré, bail inconnu : refusé ; exception du rapport final de l'ancien bail, ci-dessous) ; `n` supérieur au dernier accepté dans ce bail ; position à 6 cases au plus de la copie du serveur ; distance depuis le rapport accepté précédent ≤ 3 + 8 × durée (s) ; `arrived` à 1,25 case au plus du centre visé, même niveau. Refus : une ligne `WARN` par (expéditeur, raison) et par minute, compteur `stats.rejected`.
- Rapport accepté : pose confiée au relais des gestes (clients proches, regroupé, borné : LK03-T05) ; un expéditeur différent du précédent est journalisé (`now executed by B (was A)`) ; un état final clôt la consigne et republie `dirState`.
- Consignes de PNJ oubliés, virtuels ou morts : retirées au passage suivant (toutes les 15 images). `move` sans fin après 180 s : `failed (timeout)`.

### Exécution (`LK_Executor`, client MP et solo)

- Seule la machine qui simule (`ZombieGuard.simulatedHere` : client = `not isRemoteZombie()`, solo = toujours) exécute ; passage toutes les 10 images.
- `move` : `pathToLocation` puis `bPathfind` vrai et `setMoving(false)` (mode `pathfind` mesuré). **`useless` reste posé** : c'est la combinaison mesurée ; le lever exposerait le corps au repérage et aux bruits pendant tout le trajet. Le drapeau de trajet de la garde n'est donc **pas** ouvert par l'exécutant (écart avec la formulation du contrat, voir Points ouverts) ; il servait au trajet en ligne droite du serveur, retiré par LK03-T04.
- Arrivée : à 1 case du centre de la case visée, même niveau → arrêt, rapport `arrived`. Recherche finie sans arrivée, ou moins de 0,5 case de progrès en 4 s → nouvel essai, au plus 3 ; depuis LK04-T05, essais épuisés ou aucun progrès vers l'étape pendant 6 s → nouvelle requête, point de déblocage, puis `failed` avec la raison `stuck` et un détail (`no path` / `no progress` / `no approach`) : [deplacement.md](deplacement.md), « Blocage et déblocage ». Rapport : champ facultatif `wd` (détail), raison et détail gardés dans la consigne close (`why`, `wd`).
- `stop` : `bPathfind` et `bMoving` effacés. `face` : arrêt puis `setDirectionAngle`.
- Portes (LK04-T02, [deplacement.md](deplacement.md), « Portes ») : corps arrêté contre une porte fermée de sa copie → attente de 4 s sans compter d'essai, chemin relancé dès qu'elle est ouverte par l'autorité. Consigne close par l'autorité pendant la marche (`Directives.abort` devant une porte refusée, délai dépassé) → corps arrêté une fois (phase `failed` ou `stopped`).
- Solo : consignes lues dans `Directives.entries`, rapport remis par appel direct à `Directives.onReport` (aucun message).

### Changement de propriétaire

- L'ancien propriétaire voit sa copie devenir distante, ou reçoit un bail donné à un autre : il abandonne l'exécution sans toucher à la copie (`stats.released`) ; un rapport tardif de sa part est ignoré (ancien bail) ou refusé (`not the owner`), sauf le rapport final de l'ancien bail (LK03-T01, ci-dessous).
- Le nouveau n'exécute qu'après avoir reçu le **bail** que le serveur lui donne quand il voit le changement (LK03-T01 ; depuis LK03-T03 à l'image suivante, voir « Transfert de propriété sans perte d'état ») : il lance alors `pathToLocation` **depuis la position actuelle** vers la case de l'**étape publiée**. Pas de retour au départ ni à un point déjà atteint ; reprise au plus 3 images après que le client se sait propriétaire et a le bail (banc), plus le réseau.
- Le serveur qui reprend la simulation (plus aucun client) n'exécute rien : la consigne ouverte est suspendue, le corps au repos, jusqu'au client suivant (LK03-T04, ci-dessous).

### Révisions, envoi aux proches et réémission (LK03-T01, 2026-10-10)

Faits du moteur (Java 42.21.0, base `multiplayer.md`, « Changement de propriétaire d'un zombie ») : le serveur recalcule le propriétaire de chaque zombie à chaque image, **après** le Lua (`J/popman/NetworkZombiePacker.java:118-165`), au plus une fois par 2 s sauf déconnexion (réattribution immédiate, `J/popman/NetworkZombieManager.java:60-131, 209-224`) ; le client l'apprend par le paquet `ZombieList`, **non fiable** et sans ordre avec nos commandes (`J/network/packets/character/ZombieListPacket.java:15`) ; une connexion ne voit les zombies qu'à 64-96 cases (écart en x et en y), le propriétaire est choisi à 48-80 cases (`J/network/GameServer.java:2615-2616`, `J/core/raknet/UdpConnection.java:216-240`, `NetworkZombieManager.java:121-127`).

**Numéros.**

| Numéro | Portée | Rôle |
|---|---|---|
| `v` | consigne, global à la session (jamais réutilisé) | révision de la consigne d'un PNJ : croissant par PNJ ; une nouvelle consigne remplace la courante |
| `l`, `o` | bail, global (jamais réutilisé) ; `o` = compte du propriétaire ou `server` | exécutant désigné : nouveau bail à chaque consigne, à chaque changement de propriétaire vu par le serveur, et quand l'exécutant désigné entre de nouveau en partie |
| `r` | envoi, global | ordre des messages : chaque envoi porte l'état courant, un `r` plus grand = un état au moins aussi récent |
| `n` | rapport, par client | rapports d'un même bail dans l'ordre |

**Destinataires** (`Directives.targets`) : joueurs connectés (`getOnlinePlayers`) à `NEAR_RADIUS = 100` cases du corps (écart en x et en y, niveaux ignorés : au-delà de la portée maximale de 96 cases, tout client qui peut voir le corps ou le simuler a la consigne), plus le propriétaire. Le serveur garde les détenteurs par PNJ (`holders`).

**Envois et réémissions** (`Directives.sync`, `Directives.watch` au passage du serveur, toutes les 15 images) :

| Déclencheur | Détection | Envoi |
|---|---|---|
| nouvelle consigne, étape atteinte, fin | appel de l'autorité | consigne à tous les destinataires |
| joueur entré dans le rayon | passage : destinataire absent des détenteurs | consigne à lui seul |
| joueur sorti du rayon | passage : détenteur absent des destinataires | `{ gone }` à lui seul (il oublie la consigne) |
| changement de propriétaire (consigne ouverte ; close aussi depuis LK03-T02, le bail désignant l'expéditeur des rapports d'état, [rapports.md](rapports.md)) | passage : `ownerName(z)` ≠ `o` | nouveau bail, consigne à tous ; journal `… leased to B (was A, lease n)` (DEBUG pour une consigne close) |
| apparition du corps côté serveur (autre objet, nouvel `onlineId` : retour de chunk) | passage : `bodySeen` | consigne à tous |
| apparition d'une copie chez un client (chargement, recréation après 5 s sans paquet) | client : objet de la copie changé (`Executor.askNew`), une demande par PNJ et par 2 s | `dirAsk` → consigne (ou `{ gone }`) à ce client |
| entrée en partie, reconnexion (`guardHello`) | commande | consignes des corps proches en un message ; consigne ouverte dont il était l'exécutant désigné : nouveau bail (sa session précédente est close, ses `n` repartent de 1) |
| PNJ oublié, corps retiré | `forget` | `{ gone }` aux détenteurs |

Liste des joueurs connectés vide (déconnexion, redémarrage) ou corps hors de la zone chargée : aucun détenteur retiré (base `multiplayer.md`, « État suivi par sondage »).

**Côté client** (`LK_Executor`) : consigne reçue gardée par PNJ si son `r` dépasse le dernier reçu (sinon `stats.older`) ; `{ gone }` la retire. Exécution seulement si le corps est simulé ici **et** `o` = son compte. Jamais une consigne de `v` inférieur à la dernière commencée ici (`stats.stale`), ni un couple (`v`, `l`) déjà mené ici jusqu'à un état final (`Executor.mayStart`) ; une exécution interrompue (corps disparu ou devenu distant) reprend au même bail depuis la position actuelle et l'étape publiée. Solo : pas de bail à attendre ni de message, mêmes règles d'historique (réapparition du corps = reprise).

**Cas de course** (livraison fiable non ordonnée) :

| Cas | Effet |
|---|---|
| deux envois du même PNJ inversés, ou doublon | le plus ancien (`r`) ignoré ; une consigne remplacée n'est jamais commencée |
| le client se sait propriétaire avant de recevoir le bail | il attend (`stats.waiting`) : rien n'est exécuté sur un état non publié |
| le bail arrive avant que le client se sache propriétaire | il attend que la copie soit locale |
| rapport de l'ancien exécutant en vol pendant le transfert | « en marche » : ignoré sans avertissement, le nouveau reprend la position actuelle ; **état final** (arrivé, arrêté, tourné, échec) : accepté pendant `LEASE_GRACE_MS = 2 s` après le nouveau bail tant que le nouvel exécutant n'a rien rapporté (contrôles de position inchangés), journal `final report … accepted after the transfer to …` : la consigne n'est ni perdue ni rejouée |
| rapport final de l'ancien bail après le délai, ou après un rapport du nouveau | ignoré ; le nouvel exécutant clôt la consigne |
| client qui se croit encore propriétaire (paquet `ZombieList` perdu) | le bail donné à un autre l'arrête (consigne fiable) ; ses rapports sont refusés |
| reconnexion de l'exécutant | nouvel état Lua ; consignes reçues à l'entrée ; s'il redevient propriétaire, nouveau bail, reprise à l'étape publiée ; ses anciens numéros `n` ne bloquent pas les nouveaux (contrôle par bail) |

**Limites** : un `stop`/`face` dont le rapport final de l'ancien exécutant arrive après le délai de grâce est réappliqué par le nouveau (sans effet visible : même arrêt, même angle) ; la consigne reste en mémoire seulement (redémarrage du serveur : abandonnée, voir plus haut) ; écran partagé non traité (N7).

### Transfert de propriété sans perte d'état (LK03-T03, 2026-10-10)

Problème relevé par `docs/annexes/recherches/alife-analyse.md` §1 (« perte d'état au transfert ») : l'état utile d'un PNJ ne doit pas vivre seulement dans la copie du client qui le simule. Il vit sur le serveur et est **remis** au nouveau propriétaire.

**État remis** (`Directives.handState`, message `npcHand`) :

| Champ | Contenu | Source serveur |
|---|---|---|
| consigne, `v`, étape `k` | consigne courante et étape publiée | `dirState` (LK03-T01), inchangé : la remise ne la répète pas |
| `o`, `l` | nouveau propriétaire, bail courant (0 sans consigne) | `Directives.entries` |
| `hp` | santé du **dernier rapport d'état accepté** pour ce même objet de corps | `Reports.states` (LK03-T02) |
| `w`, `er` | arme voulue `{ t, l, h }` et révision de la table des armes | `Equipment.wantedOf`, `Equipment.state.rev` (LK02-T06) |
| `rs` | étape de routine | **réservé** : aucune routine n'existe encore (LK05) ; champ absent |
| `tgt` | cible courante (identifiant) | **réservé** : aucune cible tenue par le serveur avant LK06 ; champ absent |
| `am` | munitions | **réservé** : `LK_Equipment` ne connaît que l'arme visible, aucune munition ; champ absent |

**Serveur** :

1. `Directives.ownerWatch`, **à chaque image** (et non plus au passage lent de 15 images) : pour chaque corps relié, propriétaire (`ownerName`) comparé au détenteur de la remise (`Directives.hands`). Le moteur change le propriétaire après le Lua de l'image (`J/popman/NetworkZombiePacker.java:118-165`) : le changement est vu à l'image suivante. Coût : une lecture de `getOwner()` par corps relié et par image (50 corps au plus).
2. Au changement (`Directives.handover`) : nouveau bail si la consigne désignait un autre exécutant (`Directives.transfer`, même journal `leased to …` qu'en LK03-T01, consigne envoyée à tous les destinataires) ; remise envoyée au nouveau propriétaire et à l'ancien détenteur (`o` = nouveau : il la rend). Corps hors du monde (chunk déchargé) : seul le détenteur change, l'ancien rend la remise, aucun bail.
3. `dirClaim` d'un client : remise (et bail) renvoyée au seul propriétaire réel (`isOwner`) ; autre expéditeur ignoré (`stats.claimIgnored`, course). `guardHello` oublie les remises détenues par ce compte (nouvel état Lua), renvoyées à l'image suivante.
4. **Ancien propriétaire pas encore prévenu** (`ZombieList` non fiable, jusqu'à 3 s, base `multiplayer.md`) : son rapport d'exécution (`dirReport`) ou d'état (`bodyReport`) est **ignoré**, ni refusé ni gardé, s'il détient encore la remise (changement pas encore traité) ou l'a rendue depuis au plus `OWNER_GRACE_MS = 4 s` (`Directives.isPreviousOwner` ; compteurs `Directives.stats.previousOwner`, `Reports.stats.ignored`, raison `previous owner`, ligne `INFO` par minute). Au-delà : refus `not the owner` (`WARN`).
5. **Mesure** : délai entre le nouveau bail et le premier rapport accepté du nouvel exécutant pour une consigne ouverte, journal `INFO npc <id>: <op> #v resumed by <compte> <ms> ms after the owner change (lease l)`, `Directives.stats.resumeLast`, `resumeMax`.

**Client** (`LK_Executor`) :

- Remise pour soi gardée (`Executor.hands`, plus récente selon `r`), **appliquée dès que la copie est locale**, une fois par objet de copie : santé **abaissée** à `hp` si la copie est plus haute (jamais relevée : aucun soin ; bornes 0 à 32,767 de [sante.md](sante.md)) ; table des armes du PNJ reprise de la remise si celle reçue par `equipState` est plus ancienne (`er`) ; le passage d'affichage d'`LK_Equipment` accroche ou met en main l'arme comme d'habitude. Remise pour un autre compte : rendue, rapports d'état arrêtés.
- **Rapports d'état seulement avec la remise appliquée** à cette copie : le premier rapport du nouveau propriétaire porte la santé acceptée, il n'est pas refusé (`health rose without a known heal`). La santé de la remise suit les rapports envoyés (plancher pour une copie recréée).
- Copie locale sans remise pour soi : `dirClaim` (une demande par PNJ et par `CLAIM_MS = 2 s`).
- **Reprise rapide** : un bail ou une remise reçus pour soi déclenchent le passage de l'exécutant à l'image suivante ; un bail reçu avant que la copie soit locale est surveillé à chaque image (`Executor.waitLocal`) et le passage part dès qu'elle l'est.
- **L'ancien cesse d'agir** : en plus de l'abandon au passage (copie distante, bail donné à un autre), chaque rapport d'exécution revérifie au moment de l'envoi que la copie est simulée ici et que le bail courant est le sien (`stats.muted`).

**Mesure sur le banc** (`tests/test_lk_reports.py`, `OwnershipHandoverTests`, 60 images/s, commandes livrées à la fin de chaque image) : 7 transferts A ↔ B au moins 2 s d'écart (règle du moteur) pendant un trajet à 3 étapes, changement vu par les clients 0 à 9 images après le serveur : reprise **10 images au plus après le changement sur le serveur (160 ms, moyenne 94 ms), 2 images au plus après que le client se sait propriétaire** ; plus long arrêt du corps 16 ms ; mesure du serveur `resumeMax` 144 ms. Avant LK03-T03 : jusqu'à 15 images (passage du serveur) + 10 (passage de l'exécutant), soit ≈ 0,4 s plus le réseau. En jeu s'ajoutent l'aller-retour réseau des commandes et le délai du paquet `ZombieList`.

**Limites** : la santé remise est la dernière **acceptée** (rapport au plus toutes les secondes) : un coup reçu par l'ancienne copie juste avant le transfert et pas encore rapporté est perdu ; la santé vanilla du zombie reste celle que chaque copie calcule (LK07-T02, santé de référence complète, non fait ici) ; entre le changement et la remise, le paquet zombie du nouveau propriétaire peut porter brièvement sa santé de création au serveur (sans effet sur l'état accepté) ; étape de routine, cible et munitions : champs réservés ; écran partagé non traité (N7).

### Corps simulé par le serveur

Révisé le 2026-10-10 (LK03-T04 ; jusque-là, ligne droite tentée par le serveur, LK02-T07). Le serveur ne peut pas chercher de chemin (`pathToAux` sans `bPathfind`, `J/characters/IsoGameCharacter.java:5923-5958`) et un corps sans client propriétaire est loin de tous les clients (propriétaire choisi à 48-80 cases, `J/popman/NetworkZombieManager.java:121-127`) : il n'est vu, au mieux, que de loin (64-96 cases). Règle : **aucune consigne d'action n'est exécutée par le serveur**.

1. **Suspension** (`Directives.suspend`, appelée dès l'émission d'une consigne pour un corps sans propriétaire, au transfert vers `server` et, en filet, au passage lent) : la consigne ouverte (`move`, `stop`, `face`) reste ouverte et publiée, bail donné à `server` (aucun client ne l'exécute) ; champ `suspended` = heure de la suspension ; journal `INFO npc <id>: <op> #v suspended, no client simulates the body: at rest until a client owns it`, compteur `stats.suspended`.
2. **État neutre** : `setMoving(false)` ; trajet fermé, donc `useless` rendu et cible effacée par la garde au passage suivant (corps qui n'erre pas, ne poursuit personne) ; geste `idle` relayé aux clients proches (`animState`, LK03-T05) ; le corps reste debout où il s'est arrêté, sans téléport. Un client qui le voit de loin voit un PNJ au repos, jamais figé en pleine marche.
3. **Délai** : le temps suspendu ne compte pas dans `TRIP_TIMEOUT_MS` (180 s ; `issued` décalé d'autant à la reprise) : la consigne n'est pas perdue.
4. **Reprise** : un client devient propriétaire → nouveau bail (`Directives.transfer`, LK03-T01/T03), geste de la consigne rétabli, exécution depuis la position actuelle et l'étape publiée `k` ; journal `… resumed by <client> after <ms> ms suspended`, compteur `stats.unsuspended`. Une consigne n'est donc ni rejouée (même `v`, menée une fois) ni perdue.
5. **Retrait** : un corps resté loin de tous les joueurs (120 cases, 60 s) est retiré et le PNJ repasse en simulation abstraite, consigne abandonnée : [corps-registre.md](corps-registre.md), « Retrait loin des joueurs ».

Solo : la seule machine est propriétaire, rien n'est suspendu.

### Plantes cultivées et feux de camp (LK04-T06)

Règle de `moveTo` : une case visée qui porte une plante cultivée ou un feu de camp, ou dont une voisine en porte, est décalée vers la case praticable la plus proche sans danger à 2 cases (au plus 3 cases), sinon la consigne est refusée ; une ligne droite qui traverse la zone est découpée en étapes (ci-dessous) ; sans contournement simple, elle est signalée (`WARN … straight line crosses … and <raison> …`), le chemin vanilla pouvant traverser les plantes. Un corps à l'arrêt dans cette zone reçoit une consigne `move` courte (`Bodies.hazardPass`). Faits du moteur, règles complètes et risque résiduel : [neutralisation.md](neutralisation.md).

### Points de passage (LK05-T12, 2026-10-10)

**Calcul** (`Directives.planDetour`, autorité seulement, appelé par `moveTo` après le décalage de la destination) :

1. Ligne droite position du corps → centre de la case visée testée par `hazardsOnLine(…, margin = Bodies.HAZARD_AVOID)` : une case d'échantillon compte si un danger est à 1 case ou moins (zone dangereuse). Ligne hors zone : aucun point (format antérieur). Corps parti **de** la zone (arrêt à côté d'une plante, consigne d'écart) : le premier segment n'est testé que sur les cases portant un danger, puisqu'il quitte forcément la zone.
2. Boîte englobante des dangers à 1 case de la ligne, étendue de proche en proche aux dangers à `LINK = 4` cases ou moins (deux plants plus proches ne laissent aucun passage hors zone) ; côté supérieur à `MAX_BOX = 24` cases : pas de contournement.
3. Coins de la boîte élargie de `DETOUR_MARGIN = 3` cases (zone à 1 case, corps arrivé à la tolérance d'une case encore à 2 cases au moins, donc hors zone) ; un coin non chargé, impraticable (`isFree(false)`) ou dans la zone est remplacé par la case sûre la plus proche à `NUDGE = 1` case, sinon écarté.
4. Candidats, ordre fixe : un coin (4), deux coins voisins dans les deux sens (8), soit 3 étapes au plus (`MAX_STEPS = 4`). Chaque segment vérifié par `hazardsOnLine` (marge 1, mémo partagé) ; longueur totale au plus ligne droite + `MAX_DETOUR = 30` cases ; le plus court gagne, le premier à égalité : **déterministe**. Aucune case chargée par le calcul (`getGridSquare` d'une case absente rend `nil` : coin écarté).
5. Aucun candidat : destination directe, `WARN … and <raison>: the vanilla path may cross them` (raisons : `hazard area wider than 24 squares`, `no clear detour around the hazards in x,y-x,y`). Le trajet n'est jamais refusé.

**Schéma** (compatible) : la consigne `move` reçoit `w` (liste de cases `{ x, y }`, même niveau que `z`) et `k` (étape courante, 1 = premier point, `#w + 1` = destination). Absents quand il n'y a pas de point : la table d'une consigne sans détour est identique à l'ancienne. Un exécutant antérieur ignorerait `w` et irait tout droit. `v` reste le numéro de la consigne entière : le découpage n'émet pas de consignes supplémentaires et la réémission (LK05) remplace le tout.

**Exécution** : `pathToLocation` vers le point de l'étape `k` (même mode `pathfind`) ; à `Directives.ARRIVE` case de son centre, étape suivante, nouvelle recherche, compteur de nouveaux essais remis à zéro, rapport `moving` immédiat avec `k`. Le serveur accepte `k` d'une étape à la fois (`k = e.k + 1`, position à `ARRIVE + 0,25` case du point atteint), sinon l'ignore sans refuser le rapport (`stats.stepIgnored`) ; il journalise `npc <id>: move #v step i/n reached (by X), next x,y` et republie la table, si bien qu'un **nouveau propriétaire reprend à l'étape publiée** (pas de retour à un point déjà atteint). Corps simulé par le serveur : consigne suspendue, étape `k` inchangée jusqu'à la reprise par un client (LK03-T04). Arrivée finale inchangée (destination, contrôle de tolérance). Journal de l'exécutant : `… step i/n reached here at …` (INFO sur un client MP, DEBUG en solo où l'autorité écrit déjà la ligne).

**Limites** : entre deux points, le chemin reste celui du jeu (non exposé) et peut couper un coin ; un potager à l'intérieur duquel se trouve le départ ou la destination, ou deux potagers éloignés tous deux sur la ligne (une seule boîte englobante, vite trop large ou contournée de loin), peuvent rester sans contournement ; la marge est calculée sur les dangers vus à l'instant de la consigne (plante semée ensuite : ignorée jusqu'à la consigne suivante).

### Autres clients (`LK_Presentation`, client MP)

- Pose reçue gardée par PNJ (la plus récente selon `pr`). **Orientation** appliquée une fois par pose à la copie distante, seulement pour un arrêt (`arrived`, `stopped`, `faced`, `failed`) et si la copie ne se déplace pas ; le paquet zombie suivant garde le dernier mot. **Position jamais touchée** (aucun `pathToLocation`, `setX`, `teleportTo`, `setMoving`, `setVariable` dans le fichier, test de source).
- **Geste** : relayé avec la pose (`animState`, LK03-T05) et appliqué par `LK_Anim`, que le serveur règle d'après la consigne et les rapports ; `LK_Presentation` ne réécrit pas `LKGesture` (sinon il lutterait avec le passage d'affichage d'`Anim`).
- **Délai de relais** : heure serveur à la réception − heure serveur du rapport chez le propriétaire (`t`) ; dernier, maximum, moyenne dans `Presentation.stats`, lus par `LKB.pose(id)` ; échantillon ignoré tant qu'une des deux horloges n'est pas synchronisée.

## Alternatives écartées

- Lever `useless` pendant tout trajet (drapeau de trajet ouvert par l'exécutant) : non mesuré en `pathfind`, expose le corps aux repérages et bruits ; seul le serveur en ligne droite en avait besoin (`WalkTowardState`).
- Marche en ligne droite par le serveur quand aucun client n'est propriétaire (LK02-T07, retirée par LK03-T04) : échoue derrière tout obstacle, se voit seulement de loin, et exécute une consigne d'action sans client propriétaire ; remplacée par la suspension.
- Appliquer `stop` et `face` directement sur le serveur (LK02-T07) : remplacé par la même suspension que `move` (règle unique ; le corps est déjà arrêté, l'orientation attend le client).
- Envoyer la consigne au seul propriétaire : un transfert exigerait un renvoi au bon moment ; les joueurs proches l'ont déjà, et le bail désigne le nouvel exécutant.
- Table complète de toutes les consignes à tous les clients (LK02-T07) : remplacée par LK03-T01 (coût proportionnel au nombre total de joueurs ; un client lointain gardait une consigne qu'il pouvait exécuter, périmée, en devenant propriétaire avant la table suivante).
- Laisser chaque client décider seul sur `isRemoteZombie()` (sans bail) : le client apprend son rôle par un paquet non fiable et non ordonné avec nos commandes ; le nouveau pourrait rejouer une consigne que l'ancien vient de clore.
- Relais de la position aux autres clients : le paquet zombie la porte déjà ; l'appliquer contredirait la position réseau.
- Téléporter un corps simulé par le serveur vers sa destination : invisible pour personne mais trompeur ; relève de la simulation hors écran (LK09).
- Persister la consigne dans le registre : rejouerait après un redémarrage un ordre dont la raison a disparu.
- Pose relayée sous forme de table complète à chaque rapport : coût proportionnel au nombre de PNJ × fréquence ; une pose par message, numérotée par PNJ.

## Idées reprises

- Aucune.

## Tests

- Banc lupa (`tests/test_lk_directives.py`, 42 tests, dont 6 pour LK04-T06, 8 pour LK05-T12 et 8 pour LK03-T01 : découpage autour d'un plant et d'un rang de 5 plants avec segments hors zone et corps jamais dans la zone, calcul déterministe, table envoyée avec `w`/`k`, cas sans contournement (boîte trop large, coins impraticables), bornes `MAX_DETOUR` et `MAX_STEPS`, départ dans la zone, reprise par un nouveau propriétaire à l'étape publiée, `k` contrôlé une étape à la fois, corps simulé par le serveur, solo) : consigne versionnée envoyée aux deux clients, seul le propriétaire exécute (chemin depuis la position de départ, `useless` gardé, aucun trajet ouvert), arrivée, geste `walk` puis `idle` chez les deux clients, pose relayée et orientation appliquée chez l'autre client seulement ; rapports refusés (non-propriétaire, loin de la copie, arrivée loin de la case, état incohérent, trop rapide), périmés ou plus anciens ignorés, une ligne `WARN` par minute ; transfert à mi-chemin (le nouveau repart de la position actuelle dans la passe suivante, distance à la cible jamais croissante, l'ancien cesse, rapport tardif refusé) ; livraison non ordonnée (table et pose plus anciennes ignorées, `move` périmé jamais exécuté) ; client arrivé après (tables et poses reçues en réponse à `guardHello`) ; délai de relais mesuré seulement avec horloge synchronisée ; corps simulé par le serveur (LK03-T04 : `move` suspendu au repos, sans chemin ni déplacement pendant 6,4 s puis au-delà du délai maximal d'un trajet, geste `idle` chez les deux clients, puis reprise par un client avec le geste `run`, chemin depuis la position d'arrêt, une seule arrivée ; propriétaire perdu en route : arrêt, reprise par l'autre client depuis l'arrêt ; `face` et `stop` suspendus puis menés par le client suivant ; consigne à étapes suspendue à l'étape 2, reprise par un autre client à l'étape publiée, corps jamais dans la zone d'une plante) ; échec de chemin (3 nouveaux essais puis `failed`) ; PNJ oublié ; validations ; solo sans message (marche, arrêt, orientation) ; sources compatibles Kahlua. LK03-T01 (serveur et deux clients) : envoi au seul client proche, joueur entré dans le rayon (consigne reçue au passage suivant, rien exécuté), sorti (`{ gone }`) ; doublons et envois plus anciens ignorés, consigne de `v` inférieur ou déjà menée à son terme jamais commencée ; transfert au milieu d'une consigne à étapes (le nouveau propriétaire attend son bail, reprend à l'étape publiée, l'ancien ne relance rien, une seule arrivée, rapport tardif de l'ancien bail ignoré sans avertissement) ; rapport final de l'ancien bail en vol accepté une fois (aucune reprise chez le nouveau), refusé après le délai de grâce ; reconnexion de l'exécutant (corps passé à l'autre client puis rendu : une seule reprise, sans retour, une seule arrivée, aucun refus) et reconnexion rapide sans changement de propriétaire (nouveau bail, numéros `n` repartis de 1 acceptés) ; réapparition du corps (nouvel `onlineId` sur le serveur : réémission aux deux clients ; copie recréée chez un client : `dirAsk`, réponse à lui seul, reprise de la même consigne) ; solo : reprise après réapparition du corps, consigne périmée ou déjà menée refusée par `Executor.mayStart`.
- LK03-T03 (`tests/test_lk_reports.py`, `OwnershipHandoverTests`, 3 tests) : propriétaire qui alterne 7 fois pendant un trajet à étapes, changement connu des clients avec 0 à 9 images de retard (ancienne copie qui continue pendant ce temps) : une seule consigne (`v` = 1) close une fois, étape `k` jamais en recul, aucun rapport ni chemin de l'ancien propriétaire une fois prévenu, reprise mesurée (ci-dessus), santé acceptée 1,4 appliquée à la copie de B (création 2) avant son premier rapport, aucun rapport refusé, arme reprise par B depuis la remise alors qu'il avait manqué la table des armes, accrochée sur les deux copies ; rapport de l'ancien propriétaire non prévenu ignoré (même image, puis en vol), remise rendue, refusé après `OWNER_GRACE_MS` ; `dirClaim` d'un non-propriétaire ignoré, remise renvoyée après une reconnexion et rapports d'état repris. `test_lk_directives.py` 42/42 inchangés (deux adaptations du banc : demandes d'entretien filtrées dans un test, état de remise remis à zéro par `reset_client`).
- VM Kahlua : sans objet (aucun mécanisme de VM nouveau).
- Serveur dédié de test (`run_dedicated_smoke.ps1 -Filters rst`, 2026-10-09) : 6/6, aucune erreur Lua de nos mods (chargement de `LK_Directives`).
- En jeu : suite `lk.executor` (tags `world`, `server`) — `move` de 9 cases (arrivée, `walk` puis `idle`, trajet fermé, `useless`), `stop` en route (corps immobile 2 s), `face S` (90° à 20° près) ; LK03-T01, solo seulement (sauté sur un serveur) : corps retiré des corps connus le temps d'un passage puis rendu, `move` ouvert repris et clos une fois, puis consigne plus ancienne ou déjà menée jamais recommencée. Lignes `[LKX] measure`. Ce test passe sur les doublures (`tests/test_lk_milestone.py`, `ExecutorSuiteTests`) ; il n'a pas encore été lancé en jeu.

### Protocole solo (`rstest-solo`, nominal d'abord)

1. `LKB.spawn()` ; attendre qu'il soit debout ; `LKB.moveTo(1, 9, 0)` : il marche (clip humain) jusqu'à la case et s'arrête ; `LKB.directive(1)` → `arrived`.
2. `LKB.moveTo(1, -9, 0, "run")` puis, en route, `LKB.stop(1)` : il s'arrête net ; `LKB.face(1, "S")` : il se tourne vers le sud.
3. `RST.run({ suite = "lk.executor", tags = "world" })` (≈ 2 min, sans pause) ; relever les lignes `[LKX] measure`.
4. Facultatif : `LKB.moveTo(1, 8, 0, "crouch")` (marche accroupie), cible derrière un mur (contournement).

### Deux clients (séance MP finale)

1. Client 1 près du PNJ (propriétaire), client 2 à ~15 cases : `LKB.moveTo(1, 10, 0)` ; les deux voient la marche ; `LKB.directive(1)` (serveur) : `executed by` = client 1.
2. Pendant le trajet, client 2 se colle au PNJ et client 1 s'éloigne : changement de propriétaire ; aucun demi-tour, arrêt bref ; journal serveur `now executed by …`.
3. `LKB.face(1, "W")` : orientation vue chez les deux ; `LKB.pose(1)` chez le client non propriétaire : délais de relais (dernier, maximum, moyenne) à consigner.
4. Les deux joueurs s'éloignent hors de portée (80 à 96 cases, PNJ encore visible au loin) : le serveur simule ; `LKB.moveTo(1, 5, 0)` : journal `suspended`, le PNJ reste au repos (aucune marche) ; un client revient : `resumed by …`, il marche et arrive une fois (LK03-T04).
5. LK03-T01 : client 2 à plus de 100 cases, `LKB.moveTo(1, 10, 0)` : `LKB.directive(1)` sur le client 2 → aucune ; il s'approche : consigne reçue, `o` = client 1. Transfert pendant un trajet à points de passage (`lk.farm`) : journal serveur `leased to …`, reprise à l'étape publiée, une seule ligne `arrived`. Client 1 se déconnecte pendant un trajet puis revient : une seule arrivée, aucun `refused` au journal.
6. LK03-T03 (mesure) : sur le serveur, blesser le PNJ (coup d'un client) puis attendre une ligne d'état ; `LKB.moveTo(1, 20, 0)` ; les deux clients se rapprochent tour à tour du PNJ (au moins 3 changements, un toutes les 3 à 5 s) : journal serveur `leased to …` puis `resumed by <client> <ms> ms after the owner change` à chaque changement (relever les valeurs, critère < 1000 ms ; `LivingKnox.Directives.stats.resumeMax`) ; aucune ligne `refused` (seulement `INFO … ignored: previous owner` au plus) ; `LivingKnox.Reports.get("<id>").hp` inchangé après chaque transfert ; arme toujours visible (dos) chez les deux clients ; une seule ligne `arrived`. À l'œil : aucun arrêt perceptible, aucun demi-tour.

## Points ouverts

- ⚠ Délai d'un relais de pose (propriétaire → serveur → autre client) : à mesurer à deux clients (`LKB.pose`).
- ⚠ Écart avec la formulation du contrat LK02-T07 : l'exécutant n'ouvre pas le drapeau de trajet (`useless` gardé en `pathfind`, combinaison mesurée) ; à confirmer par l'utilisateur. LK06-T10 : un trajet `useless` levé rend le corps sensible aux bruits (il se retourne vers son propre pas) ; le drapeau ne lève donc plus `useless` ([zombies.md](zombies.md), section 5).
- ⚠ Écran partagé : le propriétaire côté serveur peut être le joueur 2 d'une connexion alors que le rapport part du joueur 1 : rapport refusé (`not the owner`) ; non traité.
- ⚠ LK03-T04 : état neutre d'un corps que le serveur simule (arrêt, `useless`, geste `idle`) établi sur le banc ; à vérifier à deux clients (étape 4 du protocole). Un corps dont le serveur prend la main au milieu d'une marche peut, selon l'état du paquet réseau, glisser encore un instant avant l'arrêt (non mesuré).
- ⚠ Tolérance d'arrivée (1 case) et vitesse maximale plausible (8 cases/s) : à recalibrer sur les mesures de `lk.executor` et de la course.
- ⚠ Cases à éviter (plante cultivée, feu de camp) : destination décalée ou refusée par `moveTo`, corps à l'arrêt écarté, création exclue (LK04-T06), trajet découpé en points de passage autour de la zone (LK05-T12) ; entre deux points, le chemin vanilla peut encore couper la zone (≈ 28 à 58 % de plante détruite par case traversée) : voir [neutralisation.md](neutralisation.md), « Plantes cultivées et feux de camp ». Effet des points en jeu : suite `lk.farm` (rang de 5 plants), à exécuter.
- ⚠ LK03-T01 : bail, rayon d'envoi (100 cases) et réémissions établis sur le banc (Java relevé, doublures) seulement ; à vérifier à deux clients (séance MP finale, étape 5 du protocole).
- ⚠ LK03-T03 : reprise mesurée sur le banc seulement (≤ 160 ms après le changement sur le serveur, réseau idéal) ; à mesurer à deux clients (étape 6 du protocole, ligne `resumed by`). Santé remise = dernière acceptée (coup non encore rapporté perdu) ; étape de routine, cible, munitions réservées.
- ⚠ Option serveur `SwitchZombiesOwnershipEachUpdate` (propriétaire changé toutes les 2 s) : un nouveau bail toutes les 2 s, reprise à chaque fois depuis la position actuelle ; non mesuré.
