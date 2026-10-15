# Rapports d'état du propriétaire

- Tâches : LK03-T02 (création, 2026-10-10), LK03-T03 (remise d'état au nouveau propriétaire, ancien propriétaire ignoré, 2026-10-10) ; s'appuie sur LK03-T01 (bail, exécutant désigné, réémission : [consignes.md](consignes.md)) et LK07-T01 ([sante.md](sante.md)) ; suite : LK03-T03 (transfert d'état), LK03-T04 (corps sans propriétaire), LK07-T02 (santé de référence)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-10 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Reports.lua` (`LivingKnox.Reports`, autorité ; un client MP s'arrête à la garde `isClient()` après les constantes), envoi par `media/lua/client/LivingKnox/LK_Executor.lua` (`Executor.stateReports`), seuils dans `media/lua/shared/LivingKnox/LK_Config.lua` (`Config.REPORTS`).

## Problème

Le serveur doit connaître l'état d'un corps de PNJ (position, orientation, activité, santé, pose) pour décider (LK05), transférer l'état (LK03-T03) et répondre à l'API, alors que seul le client propriétaire simule le corps. Il ne doit croire que ce client, et seulement pour des valeurs plausibles : un client modifié ne doit ni téléporter un PNJ, ni le soigner, ni parler à la place d'un autre (`docs/alife-analyse.md` §1 : « confiance au propriétaire »).

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Un seul simulateur par zombie ; côté serveur `getOwnerPlayer()` est le joueur de la connexion propriétaire, `nil` quand le serveur simule. | base `multiplayer.md` ; `J/popman/NetworkZombieManager.java:137-181` | confirmé statiquement |
| `sendClientCommand` : fiable, **non ordonné** ; l'expéditeur vu par `OnClientCommand` est le joueur de la connexion. | base `multiplayer.md` | confirmé statiquement |
| Anti-triche vanilla de vitesse d'un joueur à pied : distance mesurée sur des fenêtres d'au moins 1 s, refus au-delà de **20 cases/s**. | `J/network/anticheats/AntiCheatSpeed.java:16, 33` ; `J/characters/NetworkCharacterAI.java:339-376` | confirmé statiquement |
| Course d'un corps mesurée à 4,78 cases/s, marche 2,3 cases/s (`lk.milestone1`, solo). | `docs/validation/jalon1-2026-10-09.md`, section 5 | mesure en jeu |
| Chute : vitesse verticale + 5,001 niveaux/s par seconde, distance `v·dt + 2,5·dt²` (dt = `GameTime.getTimeDelta()`, `multiplier / 0,8 / 60`, soit des secondes à vitesse normale). | `J/characters/IsoGameCharacter.java:8679-8685` ; `J/GameTime.java:913-919` | confirmé statiquement |
| Santé : `getHealth()` flottant ; voyage en `short` × 1000 (précision 0,001, maximum 32,767) ; aucune régénération ; **au changement de propriétaire, le nouveau propriétaire repart de sa copie (santé de création) et l'envoie** : la santé vanilla remonte sans soin. | [sante.md](sante.md), sections 3 et 5 ; `J/characters/IsoGameCharacter.java:2898` ; `J/network/packets/character/ZombiePacket.java:58, 112` ; `J/popman/NetworkZombieSimulator.java:100-130` | confirmé statiquement |
| Pose lisible : `isOnFloor()` (`J/iso/IsoMovingObject.java:2038`), `isCrawling()` (`J/characters/IsoZombie.java:3998`). | Java | confirmé statiquement |
| Niveaux de carte −32..31. | base `map-files.md` | confirmé statiquement |
| Accéléré solo : `getGameSpeed()` rend la vitesse des commandes de temps (0 pause, 1 normale, plus en accéléré). | `J/Lua/LuaManager.java:6458-6462` | confirmé statiquement |

## Choix (2026-10-10)

### Message

| Commande | Sens | Contenu |
|---|---|---|
| `bodyReport` | propriétaire réel → serveur (appel direct `Reports.onReport` en solo) | `{ id, l, n, x, y, z, a, act, hp, pose, t[, sen] }` |

- `sen` (LK05-T01, facultatif) : résumé de perception, contrôlé avec le rapport puis filtré et gardé par `LivingKnox.Senses` ; un changement de ce que voit ou entend le PNJ avance le rapport comme un changement d'activité. Voir [perception.md](perception.md). LK06-T11 : les fenêtres que frappent les zombies d'un client voyagent dans une commande à part, `zombieThumps` (le propriétaire d'un zombie ne simule pas toujours de corps) : [perception.md](perception.md#fenêtres-frappées-lk06-t11).

- `l` : bail courant connu de l'exécutant (`dirState`, LK03-T01), **0** pour un PNJ sans consigne ; `n` : numéro de l'exécutant (compteur partagé avec `dirReport`, croissant) ; `a` : `getDirectionAngle()` ; `act` : phase de l'exécution (`idle`, `moving`, `arrived`, `failed`, `stopped`, `faced`) ; `hp` : `getHealth()` de la copie simulée ; `pose` : `stand`, `floor` (`isOnFloor`), `crawl` (`isCrawling`) ; `t` : heure serveur synchronisée (mesure).
- **Qui envoie** : la machine qui simule le corps (`ZombieGuard.simulatedHere`) et, sur un client MP, seulement si elle est l'exécutant désigné `o` du bail courant quand une consigne existe (même règle que l'exécution des consignes) **et** si elle a reçu et appliqué à cette copie la remise d'état du serveur (`npcHand`, LK03-T03 : santé acceptée posée sur la copie avant le premier rapport ; [consignes.md](consignes.md), « Transfert de propriété sans perte d'état »). Rien n'est envoyé si `LivingKnox.Reports` n'est pas chargé.
- **Corps déchargé** (LK03-T07, essai du 2026-10-11) : seule une copie **présente dans le monde** de l'émetteur compte (`Executor.inWorld` : vivante et dans `getCell():getZombieList()`, même critère que `Bodies.inWorld`). Un joueur réanimé dont le chunk se décharge est mis de côté : même objet Java, ni mort ni retiré, encore tenu par `Bodies.bound` (solo) ou le cache de la garde (client), mais hors de la liste des zombies. Avant ce contrôle, l'exécutant en solo le rapportait toutes les `IDLE_MS` et l'autorité le refusait (`no body (embodied)`). Désormais : exécution lâchée, aucun rapport ; à son retour (même objet remis dans la liste), premier rapport aussitôt et consigne reprise au même bail.
- **Cadence** (`Config.REPORTS`) : passage de l'exécutant toutes les 10 images ; par PNJ, un rapport au plus toutes les `STATE_MS = 1000` ms s'il a bougé de `MOVED = 0,1` case ou si sa santé a changé, dès qu'activité ou pose change (au plus toutes les `MIN_MS = 250` ms), sinon toutes les `IDLE_MS = 5000` ms. Soit au plus 4 par seconde et en pratique 1.

### Bail des consignes closes

Le bail de LK03-T01 désigne désormais aussi l'expéditeur des rapports : `Directives.watch` et `Directives.onHello` donnent un nouveau bail au changement de propriétaire **même quand la consigne est close** (ligne du journal en DEBUG, l'exécutant n'a rien à reprendre). Sans cela, un nouveau propriétaire n'aurait jamais de bail valable pour un PNJ dont la dernière consigne est finie.

### Contrôles (serveur et solo), dans l'ordre

Tout écart **refuse le rapport entier** : l'état gardé n'est pas modifié, `stats.rejected` et `stats.why[raison]` sont incrémentés, une ligne par (expéditeur, raison) et par minute (`WARN` si suspect, `INFO` pour une course attendue du réseau : `previous lease`, `replayed or older report`, `no body`). `no body` (LK03-T07) : une seule ligne par PNJ, expéditeur et absence, de nouveau après un rapport qui retrouve le corps. Aucun contrôle ne déplace le corps.

| # | Contrôle | Raison du refus | Seuil et justification |
|---|---|---|---|
| 1 | forme | `bad report` | champs typés, nombres finis |
| 1 | bornes | `out of bounds` | activité et pose de listes fermées ; x, y dans 0..1 000 000 ; niveau −32..31 ; santé 0..32,767 ; angle −360..360 |
| 2 | corps présent | `no body` (INFO) | `Bodies.find` ; PNJ oublié, mort ou virtuel : état oublié |
| 2 | propriétaire | `not the owner` | `Directives.isOwner` (`getOwnerPlayer`), réutilisé de LK02-T07 ; **ancien propriétaire** pas encore prévenu (détient encore la remise, ou l'a rendue depuis au plus 4 s, LK03-T03) : `previous owner`, rapport **ignoré** (`stats.ignored`, `INFO`), ni refusé ni gardé |
| 3 | bail | `unknown lease`, `not the designated executor`, `previous lease` (INFO) | consigne présente : `l` = bail courant et expéditeur = `o` ; `l` plus petit : course ; plus grand : refusé. Sans consigne : `l = 0` (un `l` plus grand que tout bail donné est refusé) |
| 4 | cadence | `too many reports` | seau à jetons par PNJ : `RATE = 5`/s, `BURST = 10` (l'exécutant en envoie 1/s, 4/s au plus) |
| 5 | ordre | `replayed or older report` (INFO) | `n` croissant pour un même expéditeur et un même bail ; numéros oubliés à l'entrée en partie de l'expéditeur (`guardHello`, nouvel état Lua) |
| 6 | copie du serveur | `far from the body`, `other level than the body` | `MAX_GAP = 22` cases (2026-10-14 : le propriétaire n'envoie la position d'un zombie que toutes les 4 s, la copie du serveur ne la rattrape qu'à chaque paquet ; 6 refusait une course légitime ; 3 + course mesurée 4,78 × 4 s), `MAX_LEVEL_GAP = 1` |
| 6 | santé | `health rose without a known heal` | hausse au-delà de `HP_EPSILON = 0,002` refusée sauf crédit de soin (`Reports.noteHeal(id, montant)`, consommé par la hausse) |
| 6 | vitesse | `too fast` | depuis le dernier rapport accepté du **même objet** de corps : `SLACK + MAX_SPEED × durée`, `MAX_SPEED = 8` cases/s (1,7 fois la course mesurée, bien sous les 20 du moteur), `SLACK = 3` (gigue, poussée) ; durée = horloge réelle du serveur entre réceptions (l'heure du client n'est pas crue) |
| 6 | étage | `impossible climb`, `impossible fall` | montée ≤ `CLIMB_SLACK 0,5 + CLIMB_RATE 2 × durée` (volée d'escalier : 1 niveau sur 3 cases, 0,6 s à la course) ; descente ≤ `FALL_SLACK 1 + max(2 × durée, FALL_ACCEL 6 / 2 × durée²)` (chute du moteur : 2,5 × durée²) |

`MAX_SPEED`, `SLACK` et `MAX_GAP` sont ceux des rapports d'exécution (`Directives.MAX_SPEED`… lisent désormais `Config.REPORTS`) : une seule valeur.

- Autre objet de corps (nouvelle génération) : repère de vitesse, d'étage et de santé repris à zéro.
- **Solo** : mêmes contrôles (le joueur local est le propriétaire, bail lu dans `Directives.entries`), sauf vitesse et étage en **accéléré** (`getGameSpeed() > 1`, compteur `stats.fastForward`) : l'horloge réelle ne mesure plus le temps de jeu.

### État gardé

`Reports.get(id)` → `{ x, y, z, a, act, hp, pose, ms, by, l, n, t }` (copie ; `ms` = heure de réception), mémoire seulement comme les consignes. Lecture pour l'API (`npcsNear` garde pour l'instant la position du corps du serveur, plus fraîche) et pour LK03-T03. `Reports.forget(id)` ; nettoyage paresseux quand le PNJ n'a plus de corps à suivre.

## Alternatives écartées

- **Accepter la santé et refuser le reste**, ou l'inverse : le contrat demande un rapport entier refusé ; un rapport partiellement cru serait un état composite jamais observé.
- **Numéros remis à zéro par bail seul** pour un PNJ sans consigne : il n'y a pas de bail ; ordre par expéditeur et remise à zéro à `guardHello`.
- **Durée mesurée avec l'heure `t` du client** : un client modifié pourrait gonfler la durée et cacher un téléport ; seule l'horloge du serveur compte.
- **Renvoyer au propriétaire une correction de position** : ce serait un téléport, que le paquet zombie contredirait (la position réseau vient du propriétaire).
- **Bail propre aux rapports** : dupliquerait la désignation de LK03-T01 ; le bail des consignes est étendu aux consignes closes.

## Idées reprises

- Aucune (le contrôle des rapports du propriétaire est un problème relevé par `alife-analyse.md` §1, pas une idée reprise ; aucun code lu).

## Tests

- Banc lupa `tests/test_lk_reports.py` (12 tests) : rapports du propriétaire acceptés en marchant, cadence bornée (≤ 1/s + changements d'activité), B (non simulateur) n'envoie rien ; refus : non-propriétaire, bail jamais donné, bail plus ancien, exécutant non désigné (propriétaire changé avant le nouveau bail), numéro rejoué, loin de la copie du serveur, saut de 50 cases en 1 s (copie du serveur déplacée aussi), 3 niveaux en 1 s, 8 niveaux, santé qui remonte sans soin puis acceptée une fois après `noteHeal`, valeurs hors bornes et forme fausse ; état serveur inchangé après chaque refus ; une ligne par minute et par (expéditeur, raison) ; transfert au milieu d'un trajet (le nouveau propriétaire n'envoie qu'après son bail, aucun refus) ; bail d'une consigne close qui suit le propriétaire ; reconnexion (numéros repartis de 1) ; seau à jetons ; client MP arrêté à la garde ; solo par appel direct (au sol, santé refusée, accéléré allégé) ; suite `lk.executor` sur les doublures avec rapports chargés ; sources compatibles Kahlua, aucun déplacement ni `setHealth` dans `LK_Reports.lua`. LK03-T07 : corps mis de côté en solo (aucun rapport, exécution lâchée, reprise au retour jusqu'à l'arrivée, aucun refus), copie sortie de la liste des zombies d'un client propriétaire (aucun `bodyReport`, puis un rapport accepté au retour), refus `no body` compté à chaque fois mais écrit une fois par absence.
- `tests/test_lk_directives.py` (42) et `tests/test_lk_milestone.py` (13) inchangés et verts (bail des consignes closes compris).
- LK03-T03 : `OwnershipHandoverTests` (3 tests, même fichier) : propriétaire qui alterne, santé acceptée remise et appliquée, aucun rapport refusé, ancien propriétaire ignoré puis refusé après le délai, demande de remise ; détail et mesures dans [consignes.md](consignes.md).
- VM Kahlua : sans objet (aucun mécanisme de VM nouveau ; `LK_Reports.lua` n'est pas chargé par `test_kahlua.py`).
- En jeu : suite `lk.executor`, test « move 9 squares » : ligne `[LKX] measure state reports during the move: N accepted, 0 refused, last arrived …` ; non encore lancée en jeu.

### Protocole

1. Solo : `RST.run({ suite = "lk.executor", tags = "world" })` ; relever la ligne `state reports during the move`.
2. Deux clients (séance MP finale) : client 1 propriétaire, client 2 à côté : `LKB.moveTo(1, 10, 0)` ; sur le serveur, `LivingKnox.Reports.get("<id>")` (`by` = client 1) ; transfert pendant le trajet : `state now reported by <client 2>` ; aucune ligne `state report … refused` hors `INFO previous lease` au journal du serveur.

## Points ouverts

- Santé après un changement de propriétaire (LK03-T03) : le serveur remet la dernière santé acceptée au nouveau propriétaire, qui l'applique à sa copie (abaissée seulement) avant son premier rapport ; plus aucun refus dû au transfert sur le banc. ⚠ Restent : un coup reçu par l'ancienne copie et pas encore rapporté (au plus 1 s) est perdu ; la santé de référence complète (santé vanilla inerte, mort unique) relève de LK07-T02.
- ⚠ Seuils (`MAX_SPEED` 8, étages, cadence) établis par le Java et la mesure solo de la course ; à confirmer à deux clients (gigue réseau réelle, regroupement de paquets).
- ⚠ Écran partagé non traité (N7) : un rapport du joueur 1 d'une connexion dont le joueur 2 est propriétaire est refusé (`not the owner`).
- ⚠ Corps simulé par le serveur : aucun rapport (aucun client) ; l'état gardé est celui du dernier rapport client (LK03-T04).

## Constats de la campagne MP automatique (2026-10-14)

- Copie du serveur en retard sur le propriétaire (paquets de zombie toutes les 4 s) : position et orientation lues sur
  le serveur avec plusieurs cases ou degrés de retard. `MAX_GAP` porté à 22 cases (confirmé par l'utilisateur le 2026-10-14 : plus
  tolérant, le déplacement entre deux rapports reste borné par `MAX_SPEED`). La suite `lk.executor` lit, sur un
  serveur, la position et l'angle du dernier rapport accepté du propriétaire.
- Refus comptés par PNJ (`Reports.rejectedOf(id)` : total, suspects) ; un « previous lease » au moment où un client
  prend le corps est une course attendue (INFO), pas un défaut.
- Rapport d'exécution d'une consigne remplacée : « stale » avant le contrôle de l'état (plus de WARN
  « state stopped for move »).
- Perception : un zombie rapporté par un client mais inconnu du serveur (copie fantôme d'un corps retiré, gardée
  ~5 s par le client) est retiré du résumé (`Senses.stats.ghosts`).

