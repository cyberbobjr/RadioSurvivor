# Registre et corps des PNJ

- Tâches : LK02-T02 (création), E04-T06 (mort et tueur), LK03-T04 (corps sans propriétaire et retrait), LK09-T03 (matérialisation des groupes) ; utilisée par LK02-T03 (apparence), LK02-T04 (neutralisation), LK02-T07 (consignes), LK07 (mort), LK09 (vie hors écran)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-09 — Statut : brouillon

Code : `media/lua/shared/LivingKnox/LK_Identity.lua` (logique pure), `media/lua/server/LivingKnox/LK_Store.lua` (fichier), `media/lua/server/LivingKnox/LK_Bodies.lua` (corps), abonnements dans `LK_Server.lua`. Base du corps et chemin de création : [corps-et-animations.md](corps-et-animations.md) et décision LK02 du 2026-10-09 (base B, joueur réanimé).

## Problème

Chaque PNJ de Living Knox a une identité stable, tenue par l'autorité (serveur dédié ou solo), et au plus un corps dans le monde. Le registre doit survivre au redémarrage sans ModData globale ; le corps doit être retrouvé comme « le même » après déchargement de sa zone et après redémarrage, sans doublon ni corps abandonné.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Création du corps : `addZombiesInOutfit` → `DoZombieInventory` → `square:createCorpse(zombie)` → `body:reanimate()` ; le cadavre **copie** les ModData du zombie, le zombie réanimé les recopie (`LuaManager.copyTable`). Liste vide sur une case non chargée. | `J/Lua/LuaManager.java:8355-8445` ; `J/iso/IsoGridSquare.java:10109-10124` ; `J/iso/objects/IsoDeadBody.java:378, 1865` | confirmé statiquement ; chemin confirmé en jeu en solo (LK02-T10) |
| `reanimate()` marque le zombie `isReanimatedPlayer()` et crée le descripteur partagé (figé) ; rend `nil` sur un serveur sans identifiant libre. | `J/iso/objects/IsoDeadBody.java:1837-1840, 1897-1900` | confirmé statiquement |
| Déchargement du chunk : `RemoveZombie` met un joueur réanimé **vivant** de côté (même objet, ModData gardées) ; un joueur réanimé mort n'est pas gardé. | `J/VirtualZombieManager.java:677-684` ; `J/ReanimatedPlayers.java:68-114` | confirmé statiquement ; retour du même objet mesuré en solo (LK02-T10 : `found=object`) |
| Rechargement : l'objet mis de côté est remis dans la liste des zombies, avec un **nouvel** `onlineId` sur le serveur, **sans** `OnZombieCreate` ; `LoadChunk` part ensuite. | `J/ReanimatedPlayers.java:39-66` ; `J/iso/IsoChunk.java:3516, 3612` | confirmé statiquement |
| Sauvegarde : joueurs réanimés vivants (monde et mis de côté) écrits par `IsoZombie.save` dans `reanimated.bin`, relus au chargement du monde (`setReanimatedPlayer(true)`), remis en monde avec leur chunk. | `J/ReanimatedPlayers.java:116-196` ; `J/iso/IsoWorld.java:2252` ; `J/network/ServerMap.java:375` | confirmé statiquement ; ⚠ redémarrage à mesurer |
| `isDead()` = santé ≤ 0 : `setHealth(0)` avant `removeFromWorld` évite la mise de côté. | `J/characters/IsoGameCharacter.java:4645-4647` | confirmé statiquement ; retrait mesuré en solo (LK02-T10) |
| `hasModData()` = table de ModData non vide (filtre bon marché avant `getModData()`, qui crée la table). | `J/iso/IsoObject.java:1137-1139` | confirmé statiquement |
| `OnInitGlobalModData(isNewGame)` reçoit `WorldDictionary.isIsNewGame()`, avant la cellule (`getCell()` nil). | `J/world/moddata/GlobalModData.java:56` ; base `world-placement.md` | confirmé statiquement |
| Fichiers `getFileWriter` du serveur nommés d'après la partie : ils survivent à l'effacement du monde. | base `multiplayer.md` (liste MP, point 8) | confirmé statiquement |
| Aucune ModData globale pour un état privé (lisible par tout client). | base `multiplayer.md` | confirmé statiquement |

## Choix

Retenu le 2026-10-09 (LK02-T02), dans le cadre des décisions LK02 (base B) et de `docs/annexes/plans/README.md` (autorité serveur, aucun secret en ModData globale, charge bornée).

**Registre** (`LK_Identity`, schéma 1, passé au **schéma 2** par LK02-T03 : profil d'apparence résolu, migration du schéma 1 à la relecture, voir [apparence.md](apparence.md)) : `{ schema = 2, nextId, npcs = { ["lk-<n>"] = { id, generation, state, profile, want, last, weapon, clothes } } }` ; `weapon` (LK02-T06, facultatif, sans changement de schéma) : type d'objet de l'arme, voir [equipement.md](equipement.md) ; `clothes` (LK02-T12, facultatif, sans changement de schéma) : vêtements concrets relevés sur le premier corps et rejoués aux suivants, voir [apparence.md](apparence.md). `death` (E04-T06, facultatif, sans changement de schéma) : cause de la mort du dernier corps, voir « Mort et tueur » ci-dessous. `hp` (LK03-T04, facultatif, sans changement de schéma, 0..32,767 contrôlé à la relecture) : santé du dernier corps quand il a été rendu à la simulation abstraite, voir « Retrait loin des joueurs » ; depuis LK07-T02, c'est aussi la **santé de référence** tenue par l'autorité pendant l'incarnation, avec `wounds` (blessures récentes), voir [sante.md](sante.md), « Santé de référence (LK07-T02) ». `hpMax` (LK09-T03, facultatif, sans changement de schéma, ]0 ; 32,767] contrôlé à la relecture) : santé du corps courant à sa naissance, voir « Matérialisation ».
- Identifiant `lk-<n>` tiré de `nextId`, qui ne recule jamais : un numéro n'est jamais réattribué, même après l'oubli d'un PNJ ou une création ratée.
- `generation` : compteur d'incarnations ; chaque nouveau corps du PNJ l'incrémente (validé seulement si la réanimation réussit).
- `state` : `virtual` (aucun corps attendu), `embodied` (un corps de la génération courante existe, chargé ou non), `dead` (corps courant mort, `OnZombieDead` ; cause dans `death`).
- `profile` (données seulement) : schéma 1 (LK02-T02) `female`, `outfit` parmi les tenues civiles vanilla `Generic01` à `Generic05` (présentes pour les deux sexes, `media/clothing/clothing.xml`), `preset = "clean"` ; schéma 2 (LK02-T03) : profil résolu `{ female, outfit, preset, look, skin, hair, hairColor, beard, variant }` tiré avec le numéro du PNJ et appliqué **avant** `DoZombieInventory` et le cadavre ([apparence.md](apparence.md)).
- `want` : position demandée à la création (`spawn`/`embody`), la case retenue pouvant différer (case libre, LK02-T11) ; `last` : dernière position vue (rafraîchie au balayage, écrite à `OnSave`).

**Persistance** (`LK_Store`) : `Zomboid/Lua/batman_RadioSurvivor/livingknox/registry-<hex du mode/nom de partie>-<0|1>.txt`, deux emplacements en alternance, chaque fichier = `LKREG1=<numéro>`, octets RSV2 en hex (`RS_Codec`, couche octets), somme de contrôle, `end`. Positions vues et santé de référence (`Store.markDirty`) écrites à `OnSave` ou avec l'écriture suivante. Relecture à `OnInitGlobalModData` (monde neuf : registre vide, numéros d'écriture poursuivis pour que le neuf gagne) ; rattrapage paresseux au premier usage après une remise à zéro du Lua. **Refus propre** : schéma inconnu, structure fausse ou deux fichiers illisibles → registre bloqué, journal `ERROR`, fichiers conservés, aucune création **ni retrait** de corps (sinon tous les corps passeraient pour orphelins).

**Écriture regroupée (LK13-T10, même règle que le registre des groupes LK13-T06, [groupes.md](groupes.md) « Persistance »)** : un changement d'identité ou d'état — création (`spawn`, `embody`, numéro consommé d'une création ratée), retrait (`despawn`, `release`), arme (`Equipment.setWeapon`) — marque seulement le registre « à écrire » (`Store.markChanged`, `state.queued`) ; l'écriture complète a lieu **une fois par image** :
- à la fin de l'image : abonné `OnTick` `Store.flush`, remis en fin de liste au premier `OnTickEvenPaused` (il passe devant celui du registre des groupes, `LK_Groups` chargeant `LK_Store` avant de s'inscrire) ; au début de l'image suivante (`Store.flushPaused`) pour des changements restés une image entière sans écriture (serveur en pause) ; à `OnSave` (`Store.saveIfDirty`, solo) ; avant une relecture (`Store.init`) ;
- **tout de suite** pour la mort d'un corps (`Bodies.onZombieDead` : `Store.save()`, mort unique LK07-T04) : rare, et le cadavre avec son butin (LK07-T05, marques ModData `MD_BUILT` / `MD_DEAD` sur le corps, sans dépendance au registre) est un objet du monde que le moteur peut sauvegarder avec son chunk sans attendre la fin de l'image ;
- relecture de contrôle à la première écriture de la session et sur demande (`Store.flush({ verify = true })`, `Store.verifyFile()`), plus à chaque écriture.

Ordre registre / monde des écritures différées : un corps neuf est un joueur réanimé, jamais sauvegardé avec son chunk (`ReanimatedPlayers`, table ci-dessus) mais seulement dans `reanimated.bin` à la sauvegarde du monde, qui passe en tête d'image sur un serveur dédié (avant le Lua, base `world-placement.md` « Registre Lua en fichier écrit souvent ») et après `OnSave` en solo : le registre est donc écrit avant que le monde ne garde le corps, comme avant. Un retrait n'a rien à garder dans le monde. Arrêt brutal : au plus les changements de l'image en cours (le monde de cette image est perdu aussi). Mesure : [charge-registre-pnj-2026-10-12.md](../tests/validation/charge-registre-pnj-2026-10-12.md).

**Création** (`LivingKnox.Bodies.spawn(profile, x, y, z)`) : autorité seulement, option `Enabled` vraie, registre prêt, cellule chargée ; **case non chargée → refus**, rien n'est créé (l'attente d'une case relève de la vie hors écran, LK09). **Case libre** (LK02-T11, `Bodies.findFreeSquare`) : le corps naît couché et ne se relève jamais tant qu'un personnage debout est sur sa case ou une voisine (`isBeingSteppedOn`, `J/characters/IsoGameCharacter.java:10240-10258` ; compte à rebours relancé, `J/ai/states/ZombieOnGroundState.java:107-111`). Recherche en anneaux autour de la case voulue, la plus proche d'abord, rayon `FREE_RADIUS = 4` : case chargée, `isFree(false)`, aucun personnage debout (hors véhicule et pas `isOnFloor`, ou corps Living Knox étiqueté même couché, qui se relève) sur elle ni ses 8 voisines, ni plante cultivée ou feu de camp sur elle ou ses voisines (LK04-T06, [neutralisation.md](neutralisation.md)) ; sinon refus avec raison, rien créé, aucun numéro consommé. Le registre garde `want` (demandé) et `last` (retenu). Au plus `MAX_EMBODIED = 50` corps. Étiquette `lkNpcId` + `lkNpcGen` posée sur le zombie temporaire (copiée par le cadavre puis par le zombie réanimé), puis retirée du temporaire ; `useless` posé sur le corps réanimé. Création ratée : zombie temporaire ou cadavre étiqueté retirés, numéro consommé.

**Liaison** : `Bodies.bound[id]` garde l'objet du corps courant. `find(id)` ne fait aucun parcours Lua : objet lié, vivant et présent dans la liste des zombies (`ArrayList.contains`, côté Java). Un **balayage borné** examine `SCAN_BUDGET = 64` zombies toutes les `SCAN_EVERY = 15` images (≈ 256 zombies par seconde à 60 images/s, coût fixe quelle que soit la population ; un tour de 2 000 zombies ≈ 8 s), avec un curseur qui recule d'un cran après un retrait. Pour chaque joueur réanimé vivant étiqueté :
- génération courante, objet déjà lié → position vue rafraîchie ;
- génération courante, aucun corps lié présent → **liaison** (retour de chunk avec un autre objet, redémarrage), `useless` réappliqué ;
- génération courante, un autre corps lié présent → **doublon retiré** (le corps lié est gardé) ;
- génération antérieure (`stale`), postérieure (`ahead`), identifiant inconnu, PNJ virtuel ou mort → **orphelin retiré**.
Retrait = `setHealth(0)`, `removeFromWorld()`, `removeFromSquare()`. Un joueur réanimé **sans étiquette** (vrai joueur mort), un zombie ordinaire ou une étiquette malformée ne sont jamais touchés.

**API interne** (aucune commande joueur) : `spawn(profile, x, y, z)` → id, zombie ; `embody(id, x, y, z)` (nouvelle génération d'un PNJ virtuel) ; `find(id)` → zombie, `"bound"` ou nil, état ; `despawn(id, forget)` (corps retiré, PNJ virtuel ; `forget` le retire du registre) ; `release(id, raison)` (LK03-T04 : rendu à la simulation abstraite avec son état, voir « Retrait loin des joueurs ») ; `list()` ; `scanAll()` (tests et console de dev) ; `createBody(sq, profile, id, gen)` (bas niveau, sans registre, pour les suites). Console de dev (mod de test) : `LKB.spawn/list/despawn/forget/scan/clear`.

## Mort et tueur

Tâche E04-T06 (2026-10-09). Code : `LK_Bodies.lua` (`onHitZombie`, `deathCause`, `onZombieDead`, `onDied`), abonnement `OnHitZombie` dans `LK_Server.lua`, contrôle `Identity.validDeath`.

| Cause de la mort (serveur) | Ce que sait le serveur à `OnZombieDead` | Preuve (J/ = `java/zombie/`, 42.21.0) | Statut |
|---|---|---|---|
| Coup de mêlée d'un joueur (MP) | `getAttackedBy()` = joueur de la **connexion** ; arme = objet de **son inventaire serveur** ; `OnHitZombie(zombie, joueur, partie, arme)` juste avant, dans le même appel | `network/fields/character/PlayerID.java:43` ; `network/fields/hit/Weapon.java:30-49` ; `network/fields/hit/WeaponHit.java:66-79` ; `characters/IsoZombie.java:1098-1124` ; `characters/IsoGameCharacter.java:5704-5741, 5826-5845, 13463-13486` ; `characters/IsoZombie.java:4599-4609` | confirmé statiquement ; chemin `Hit` par code en jeu : suite `rs.killer` |
| Tir d'arme à feu (MP) | même paquet `PlayerHitZombie`, même chemin ; arme `isRanged()` | mêmes références ; `inventory/types/HandWeapon.java:823` | confirmé statiquement ; tir réel : protocole |
| Solo, coup mortel | `Kill(arme, attaquant)` puis `OnZombieDead` | `characters/IsoGameCharacter.java:5843-5844` | confirmé statiquement |
| Bombe, piège avec lanceur | `Hit(arme du piège, lanceur)` sur l'autorité : comme un coup, arme explosive (`isExplosive` = catégorie d'affichage `Explosives`) | `iso/objects/IsoTrap.java:760-790` ; `HandWeapon.java:1360, 2339` | confirmé statiquement ; protocole |
| Piège à minuterie sans lanceur | attaquant = faux zombie (`getFakeZombieForHit`) | `iso/objects/IsoTrap.java:784` | confirmé statiquement |
| Feu (Molotov, essence, feu de camp) | chaque brûlure pose `setAttackedBy(null)` ; à la mort `OnZombieDead` direct, puis encore par `die()` ; le Molotov (mode `Fire`) ne fait aucun `Hit` | `characters/IsoGameCharacter.java:5542-5577, 6031-6066` ; `iso/objects/IsoTrap.java:754-755` | confirmé statiquement ; `SetOnFire` par code : `rs.killer` |
| Véhicule | `setAttackedBy(joueur de la connexion qui envoie le choc)` puis dégâts, **sans** `OnHitZombie` ; mort plus tard (santé du propriétaire) ; hors réseau `Kill(attackedBy)` | `network/fields/hit/Hit.java:52-63` ; `network/fields/hit/VehicleHitField.java:60-70` ; `characters/IsoGameCharacter.java:11663-11722` ; `vehicles/BaseVehicle.java:7796-7801` | confirmé statiquement ; protocole |
| Chute | `setAttackedBy(null)` | `characters/IsoZombie.java:2579` | confirmé statiquement |
| Zombie, autre PNJ | aucun chemin : un zombie n'attaque pas un zombie (`AttackState` pose l'attaquant sur sa cible joueur) ; un PNJ Living Knox est un zombie | `ai/states/AttackState.java:225` | confirmé statiquement |
| `Kill(nil)` d'un mod, armure à pointes | aucun attaquant | `characters/BodyDamage/BodyDamage.java:1362` | confirmé statiquement |
| Mort rapportée par le client propriétaire (MP) | le paquet de zombie du propriétaire pose la santé ; nulle → `die()` → `Kill(getAttackedBy())` : **ancien** attaquant possible, même après une chute ou un feu simulés chez le client | `popman/NetworkZombiePacker.java:80-101, 215-230` | confirmé statiquement |
| Paquet de mort | `DeadZombiePacket` / `DeadCharacterPacket` : serveur → clients seulement (`processClient`) ; aucun client ne déclare une mort | `network/packets/character/DeadCharacterPacket.java:90-122` ; `DeadZombiePacket.java:7-28` | confirmé statiquement |

**Règle retenue** (`Bodies.deathCause`, sur l'autorité seulement) :
1. `OnHitZombie` relève, pour un corps courant étiqueté, le dernier coup d'un **joueur** (`IsoPlayer` hors `IsoAnimal`) : objet joueur, compte (`getUsername`), type de l'arme, catégorie (`fire` si explosive, `firearm` si `isRanged`, sinon `melee`, mains nues comprises), heure réelle.
2. À `OnZombieDead`, `k = getAttackedBy()` :
   - `k` joueur, et dernier coup relevé du **même** objet joueur depuis `HIT_WINDOW_MS = 5000` ms au plus → catégorie et arme de ce coup, tueur = son compte ;
   - sinon `k` joueur au volant d'un véhicule (`getVehicle():getDriver() == k`) → `vehicle`, tueur = `k` ;
   - sinon corps en feu → `fire`, sans tueur ; sinon `k` joueur → `other`, sans tueur (attaquant périmé) ;
   - `k` non joueur (faux zombie, zombie) → `other` ; `k` absent → `fire` si le corps brûle, sinon `unknown`.
   `burning = true` est ajouté si le corps brûlait. Le dernier coup relevé est consommé.
3. La cause est écrite dans `npc.death` (`{ cause, killer, weapon, burning }`, contrôlée à la relecture par `Identity.validDeath`), journalisée (`npc lk-<n> died ... cause ...`) et passée en copie à l'écouteur facultatif `Bodies.onDied(id, zombie, cause)` (erreur de l'écouteur journalisée, mort gardée). Le fournisseur Living Knox du carnet (E17-T03) s'y branchera pour émettre `death(id, objet, cause)` de `RS_NPCProvider`. Aucune sanction ici (E04-T07).
4. Second `OnZombieDead` (feu) : le PNJ n'est plus courant, rien n'est refait.
5. LK07-T04 ([sante.md](sante.md), « Mort unique et cadavre ») : causes `zombie` (attaque d'un zombie vanilla décidée par `LK_Zombies`) et `bleeding` (perte de sang), décidées par `Health.kill` avant la règle ci-dessus, sans tueur ; fait `npcDied` pour toute mort ; cadavre traîné jamais retiré, cadavre relevé remis à terre.

**Cas couverts** : mêlée et tir d'un joueur (MP et solo), explosif avec lanceur, dernier frappeur parmi plusieurs, mort rapportée par le propriétaire peu après un coup (attribuée) ou longtemps après (non attribuée), conducteur (attribué) et passager (non attribué), feu, chute, piège sans lanceur, coups sur un autre zombie et sur un client MP ignorés.

**Limites** : « tueur probable » : un coup récent suivi d'une mort rapportée par le propriétaire (chute, feu chez le client) est attribué au frappeur ; véhicule : aucun relevé du choc (pas d'événement Lua), seul le conducteur au moment de la mort compte, un conducteur passé près du corps puis resté au volant peut être retenu à tort si le corps meurt d'autre chose sans coup récent ; Molotov et feu jamais attribués (choix du moteur) ; solo : `getUsername` = nom du personnage, non stable ([base `multiplayer.md`](../../../../.claude/pz-knowledge/multiplayer.md)) ; le relevé des coups est en mémoire seulement (un redémarrage entre coup et mort donne `other`). Les causes `other`/`unknown` et `fire` ne désignent personne : E04-T07 ne sanctionne que `killer`.

## Retrait loin des joueurs

Tâche LK03-T04 (2026-10-10). Code : `LK_Bodies.lua` (`releasePass`, `release`, `keptHealth`, `livingPlayers`), suspension des consignes dans `LK_Directives.lua` (`serverHeld`, `suspend`, reprise dans `transfer`), réglages `Config.BODIES` (`LK_Config.lua`), champ `hp` contrôlé par `Identity.validHealth`. Problème relevé par `docs/annexes/recherches/alife-analyse.md` §1 (corps possédés par le serveur, PNJ figés ou abandonnés).

| Fait | Preuve (J/ = `java/zombie/`, 42.21.0) | Statut |
|---|---|---|
| Sans connexion pertinente, le serveur simule le zombie lui-même (`getOwner()` nil) ; un client n'est choisi propriétaire qu'à 48-80 cases et ne voit les zombies qu'à 64-96 cases. | `popman/NetworkZombieManager.java:121-127` ; `network/GameServer.java:2615-2616` ; base `multiplayer.md` | confirmé statiquement |
| Le serveur ne cherche jamais de chemin pour un zombie (`pathToAux` sans `bPathfind`). | `characters/IsoGameCharacter.java:5923-5958` | confirmé statiquement |
| Solo : zone chargée de 13 à 19 chunks de large autour du joueur (± 48 à 79 cases) ; au-delà, le corps est mis de côté. | `iso/IsoChunkMap.java:131-139` ; base `world-placement.md` | confirmé statiquement |
| Un joueur réanimé mis de côté n'est pas accessible depuis Lua ; il est sauvegardé et remis en monde avec son chunk sans filtre sur la mort. | `ReanimatedPlayers.java:39-66, 101-110, 116-131` ; base `zombies-as-npc-bodies.md` | confirmé statiquement |
| Un corps retiré par le serveur après avoir été envoyé reste jusqu'à 5 s chez un client qui en avait la copie (`deleteZombie` inaccessible). | base `zombies-as-npc-bodies.md` | confirmé statiquement |

**Corps sans propriétaire (serveur MP)** : il ne reçoit plus de consigne d'action. La consigne ouverte est **suspendue** (`Directives.suspend`) : ni close, ni rejouée, ni perdue ; le temps suspendu ne compte pas dans le délai maximal d'un trajet (180 s). **État neutre** : corps arrêté (`setMoving(false)`), trajet fermé donc `useless` rendu par la garde, sans cible, geste `idle` diffusé aux clients, debout là où il était ; aucune ligne droite ni téléport. Un client qui redevient propriétaire reçoit le nouveau bail (LK03-T01/T03) et reprend la même consigne depuis la position actuelle et l'étape publiée, geste rétabli (journal `… suspended …` puis `… resumed by <client> after <ms> ms suspended`). Détail : [consignes.md](consignes.md), « Corps simulé par le serveur ». Solo : un joueur est toujours propriétaire, rien n'est suspendu.

**Retrait** (`Bodies.releasePass`, toutes les 4 tranches de balayage, soit 1 s) : un PNJ `embodied` est rendu à la simulation abstraite quand **aucun joueur vivant** n'est à `RELEASE_RADIUS = 120` cases ou moins (écart en x et en y, niveaux ignorés) pendant `RELEASE_DELAY_MS = 60 s` d'affilée.

- **Rayon** : au-delà de la portée réseau d'un client (96 cases au plus), du rayon d'envoi des consignes (100) et de la zone chargée en solo (79) : au moment du retrait, aucun client ne voit ni ne simule le corps et aucun ne détient sa consigne. Marge de 20 cases contre l'alternance retrait / réapparition au bord.
- **Délai** : plus long qu'un tour complet du balayage (≈ 8 s pour 2 000 zombies), qu'une reconnexion (liste des joueurs vide un moment) ou qu'un aller-retour au bord du rayon. Il repart de zéro dès qu'un joueur revient dans le rayon. Un écart de plus de `RELEASE_GAP_MS = 10 s` entre deux passages (pause, serveur figé ; en `PauseEmpty`, `OnTick` ne tourne pas) remet tous les délais à zéro.
- **Position mesurée** : celle du corps s'il est dans le monde ; sinon la dernière position vue (`last`, à défaut `want`). Un corps mis de côté hors zone chargée (cas normal en solo, joueur à plus de 79 cases) est donc rendu lui aussi quand plus aucun joueur n'est à 120 cases de sa dernière position.
- **Jamais rendu** : un corps qu'un client simule (serveur MP, `getOwner()` non nil : un joueur est forcément proche pour le moteur), un PNJ virtuel ou mort. Serveur sans joueur et sans pause : tous les corps sont rendus au bout du délai.
- Réglages lus à chaque passage (`LivingKnox.Config.BODIES`), modifiables par la console de dev et les suites.

**Passage en simulation abstraite** (`Bodies.release(id, raison)`, aussi utilisable directement) :

| Élément | Devenir |
|---|---|
| Corps | retiré s'il est dans le monde (`setHealth(0)`, `removeFromWorld`, `removeFromSquare`) ; mis de côté : laissé tel quel, il revient avec son chunk et le balayage le retire comme orphelin (`notEmbodied`), personne ne le voit entre-temps |
| État du PNJ | `virtual` ; génération inchangée (la prochaine incarnation prend la suivante, un ancien corps qui revient est retiré) |
| Position | `last` = case du corps au retrait (position approximative, à la case), ou dernière vue s'il était mis de côté |
| Santé | `hp` (nouveau champ facultatif du registre, 0..32,767, schéma 2 inchangé) = la plus basse de la santé du dernier rapport d'état accepté pour ce corps (LK03-T02) et de celle de la copie de l'autorité quand elle simule le corps ; jamais relevée ; absente si aucune n'est connue |
| Équipement | `weapon` et `clothes` gardés au registre (table des armes inchangée) |
| Consigne en cours | **abandonnée** (`Directives.forget` : détenteurs prévenus par `{ gone }`, remise oubliée) ; la simulation abstraite n'a pas de consigne, la matérialisation suivante en recevra une à jour (LK05, LK09-T03), comme après un redémarrage |
| Rapports, geste | état des rapports oublié (`Reports.forget`), geste remis à `idle` |
| Groupe | le membre lié garde son lien `npc` vers ce PNJ, toujours présent au registre ; depuis LK09-T03, sa santé est convertie en blessure abstraite (`wound`) et il redevient un membre ordinaire de la simulation horaire, présent au foyer (voir « Matérialisation ») |

Journal : `INFO npc lk-<n> released to the offscreen simulation (no player within 120 squares for 60 s): body removed|out of the loaded area, last seen x,y,z, health h, weapon w, directive move #v abandoned|none`.

**Aucun corps orphelin** : après le retrait, aucun corps étiqueté du PNJ n'est dans la liste des zombies (corps retiré) ou il est hors de toute zone chargée (mis de côté, retiré à son retour) ; `Bodies.bound` et la remise des consignes sont vidés ; registre des groupes intact. Le PNJ continue en abstrait et peut être réincarné (`Bodies.embody`, génération suivante, même lien de groupe).

**Limites** : un corps mis de côté reste dans `reanimated.bin` tant que son chunk n'est pas rechargé (moteur, voir ci-dessus) ; la santé gardée est convertie en blessure abstraite du membre de groupe lié et réappliquée à l'incarnation suivante depuis LK09-T03 (« Matérialisation ») ; un PNJ sans groupe garde seulement `hp` ; le chiffre de la santé est celui du moteur (zombie), pas l'échelle de la simulation ; un corps retiré par le serveur peut rester 5 s chez un client qui l'aurait encore en copie (cas impossible à 120 cases, sauf position de joueur périmée) ; « joueur » = joueur connecté vivant, en écran partagé chaque joueur local compte (solo) ; un PNJ dont le corps est perdu (point ouvert ci-dessous) est rendu virtuel par la même règle, ce qui le débloque.

## Matérialisation

Tâche LK09-T03 (2026-10-10). Code : `media/lua/server/LivingKnox/LK_Materialize.lua` (passage, conversions, création, mort et retrait du membre), appels depuis `LK_Bodies.lua` (`tick`, `release`, `onZombieDead`), santé de naissance `hpMax` posée par `embodyOn`, `Bodies.freeSquare` et `Bodies.ring` exposés, `Groups.applyDeath(g, mid, day, quiet)` (`LK_Groups.lua`), membres incarnés dans `LK_Simulation.lua` ([simulation.md](simulation.md), « Membres incarnés »), réglages `Config.MATERIALIZE` (`LK_Config.lua`).

| Fait | Preuve (J/ = `java/zombie/`, 42.21.0) | Statut |
|---|---|---|
| `reanimate()` réécrit la santé selon l'option `Toughness` : une santé posée avant est perdue ; celle posée **après**, dans le même appel Lua, est celle de la copie de l'autorité. | `J/iso/objects/IsoDeadBody.java:1876-1889` ; [sante.md](sante.md) | confirmé statiquement |
| Un client MP lit la santé d'un zombie à la **création de sa copie** (premier paquet) : la santé posée par le serveur avant le premier envoi lui parvient. | `J/popman/NetworkZombieSimulator.java:164-200` ; `J/characters/NetworkZombieAI.java:180` | confirmé statiquement |
| `IsoGridSquare.getBuildingDef()` = bâtiment de la **pièce** de la case (`getRoom()`), `nil` pour une case sans pièce, même dans l'emprise d'un bâtiment ; `BuildingDef.getIDString()` l'identifie (le `long` de `getID()` dépasse 2^53, base `world-placement.md`). | `J/iso/IsoGridSquare.java:7805-7816` ; `J/iso/BuildingDef.java:213-219` | confirmé statiquement |
| Solo : zone chargée de 48 à 79 cases autour du joueur ; client MP : copies des zombies à 64-96 cases. | `J/iso/IsoChunkMap.java:131-139` ; `J/network/GameServer.java:2615-2616` | confirmé statiquement |

**Déclenchement** (`Materialize.pass`, à chaque tranche de balayage : 15 images, ≈ 0,25 s en solo, 1,5 s sur un serveur dédié à 10 images/s) : groupe dont le foyer `home` est connu, avec un joueur vivant (`Bodies.livingPlayers`) à `RADIUS` = 80 cases ou moins du foyer (écart en x et en y, niveaux ignorés), et dont la case du foyer est **chargée** (sinon on attend). Groupe sans foyer (`home` absent) : jamais matérialisé. Les pillards en repaire (foyer bâtiment isolé, LK08-T08) suivent la même règle.

**Hystérésis avec le retrait** (LK03-T04 : aucun joueur à 120 cases du corps pendant 60 s) : les corps naissent à `PLACE_RADIUS` = 8 cases au plus du foyer, donc à 88 cases au plus du joueur qui les a fait naître, sous le rayon de retrait. Entre 80 et 120 cases, rien ne change : ni création, ni retrait. Au-delà de 120 cases pendant 60 s, retrait ; il faut revenir à 80 cases pour une nouvelle matérialisation. `RADIUS` est plafonné à `RELEASE_RADIUS − PLACE_RADIUS − 1` (111) quel que soit le réglage, pour que l'hystérésis tienne. Rayon de 80 : zone chargée d'un client solo (79 cases au plus) ; les corps peuvent apparaître à la vue d'un client MP (64-96 cases), sur la case la plus proche du foyer d'abord.

**Qui reçoit un corps** : les membres **présents au foyer** : vivants (`alive`), hors équipe d'une expédition en route (`expedition.team`, LK09-T02), chef d'abord puis par ancienneté. Selon le lien `npc` du membre au registre des corps :

| Lien | Effet |
|---|---|
| PNJ `virtual` | nouvelle incarnation du même PNJ (`Bodies.embody` : même `lk-<n>`, même apparence et vêtements, même arme, génération suivante) |
| aucun lien, ou PNJ absent du registre (oublié) | nouveau PNJ (`Bodies.spawn`) : sexe du membre ; apparence parmi les `looks` du profil de type compatibles avec ce sexe et tenue parmi ses `outfits` (choix stable par groupe et membre), sinon tirées avec le numéro du PNJ ; arme parmi les `weapons` du profil (`Equipment.setWeapon`, refus journalisé) ; lien posé par `Groups.setNpc` (refus : PNJ oublié aussitôt). Couvre la population initiale (membres sans corps, LK08-T05) et les **nouveaux venus** (recrues d'expédition ou d'événement), matérialisés comme les autres |
| PNJ `embodied` | rien : son corps existe (chargé, ou mis de côté jusqu'au retrait) |
| PNJ `dead` alors que le membre est vivant | incohérence d'une version antérieure : membre marqué mort (`onBodyDied`, sans publication), **jamais recréé** (journal `WARN … marked dead, not materialized`) |

Un membre mort (`alive = false`), parti (retiré du groupe) ou absent (expédition) n'a jamais de corps.

**Santé** : `npc.hpMax` = santé du corps juste après `reanimate()` (robustesse du moteur), gardée au registre à chaque incarnation (champ facultatif, contrôlé à la relecture : `]0 ; 32,767]`). Corps neuf : santé = `hpMax × (100 − wound) / 100` (`wound` 0..99), posée sur la copie de l'autorité dans le même appel Lua que la création ; indemne : santé du moteur inchangée. `FULL_HEALTH` = 1,8 (robustesse normale) sert quand `hpMax` est inconnu (corps créé avant cette tâche).

**Place** : cases au niveau du foyer, en anneaux de 0 à `PLACE_RADIUS` = 8 autour de la case du foyer, la plus proche d'abord ; foyer dans un bâtiment (case du foyer avec une pièce) : cases du **même bâtiment** (`getBuildingDef():getIDString()`) ; foyer hors bâtiment (camp de clairière) : cases **hors de tout bâtiment** ; jamais un escalier (`isFree(false)` y est vrai, `HasStairs`, `J/iso/IsoGridSquare.java:2173-2175`, base `world-placement.md`) ; chaque case doit être libre au sens de LK02-T11/LK04-T06 (`Bodies.freeSquare` : praticable, aucun personnage debout ni corps Living Knox sur elle ou ses voisines, ni plante ni feu de camp), ce qui espace les corps d'au moins deux cases. Aucune case : on attend (avertissement unique par approche), jamais de corps posé dehors à la place.

**Bornes** : `PER_PASS` = 2 corps par passage (création étalée), `MAX_PER_GROUP` = 8 corps de membres par groupe, `MAX_TOTAL` = 24 corps de membres en tout, sous `Bodies.MAX_EMBODIED` = 50 (tous PNJ). Au-delà, les membres restants restent hors écran (avertissement unique par approche). Coût sans joueur proche : groupes × joueurs par passage ; avec un groupe proche, un parcours des membres des groupes (≤ 64 × 32).

**Retrait** (règle de LK03-T04 inchangée) : `Bodies.release` appelle `Materialize.onReleased` : blessure du membre lié = `round(100 × (1 − hp / hpMax))`, bornée à 0..99 (la conversion ne tue jamais ; santé inconnue : blessure inchangée), membre de nouveau présent au foyer pour la simulation horaire (aucune position propre au membre : le foyer). Aller-retour exact : `wound → santé → wound` rend la même valeur (banc, 0..99 pour quatre robustesses).

**Mort d'un corps de membre** (`Bodies.onZombieDead`) : après le fait `memberDied` (`offscreen = false`, corps présent, E08-T07), `Materialize.onBodyDied` marque le membre mort **une seule fois** (`Groups.applyDeath(…, quiet = true)` : entrée `died` sans second `memberDied`), succession immédiate si c'était le chef (règle de succession, comme hors écran), moral `MORALE_DEATH` (−10). Un second `OnZombieDead` (feu) ne trouve plus de corps courant : rien.

**MP** : autorité seulement (`LK_Materialize` s'arrête sur un client) ; les clients voient les corps par le mécanisme existant (copies du moteur, liste de garde LK03-T06, armes LK02-T06).

Journal : `INFO group grp-<n> member m-<k> materialized as npc lk-<n> at x,y,z (wound w, health h)` ; au retrait `INFO group … member … back to the offscreen simulation at home (npc …): health h of full, wound w`.

**Limites** : un PNJ resté `embodied` sans corps (point ouvert ci-dessous) n'est pas réincarné tant qu'il n'est pas rendu virtuel par le retrait ; un corps parti loin du foyer et rendu loin des joueurs alors qu'un joueur reste près du foyer est recréé au foyer (aucune position propre au membre) ; un client MP peut voir un corps apparaître (rayon 80 sous sa portée de 96) ; l'arme d'un profil absente du jeu (mod retiré) est refusée et le PNJ reste sans arme.

## Alternatives écartées

- **Matérialiser à la portée réseau (96) ou au rayon de retrait** : aucune marge d'hystérésis, corps créés et retirés en alternance.
- **Garder la blessure abstraite pendant l'incarnation** (simulation qui blesse ou tue un membre visible) : l'état visible et l'état simulé divergeraient ; la santé du corps fait foi tant qu'il existe.
- **Poser les corps hors du bâtiment faute de place** : contredit « dans le bâtiment du foyer » ; on attend une case libre.
- **Retirer un corps sans délai dès la sortie du rayon** : un joueur qui va et vient au bord ferait disparaître et réapparaître le PNJ ; une reconnexion (liste vide un instant) viderait le monde.
- **Rayon de retrait = rayon d'envoi (100) ou portée réseau (96)** : aucune marge contre l'alternance au bord.
- **Retirer avant la mise de côté en solo** (rayon sous 48 cases) : le retrait se verrait à l'écran ; le corps mis de côté est rendu par sa dernière position.
- **Tuer le corps mis de côté** (`setHealth(0)` sur la référence gardée) : sans effet, il est sauvegardé et remis en monde quand même (`ReanimatedPlayers.java:116-131, 39-66`).
- **Laisser le serveur marcher en ligne droite** (comportement de LK02-T07) : un corps loin de tous les clients n'est vu de personne, la ligne droite échouait derrière tout obstacle et contredisait l'exigence « aucune consigne d'action sans client propriétaire ».
- **Rejouer la consigne en cours à la prochaine incarnation** : sa raison a pu disparaître (même règle que le redémarrage, [consignes.md](consignes.md)).
- **Registre en ModData globale** : lisible par tous les clients (règle du plan).
- **Liaison par `OnZombieCreate`** : non déclenché quand un joueur réanimé revient avec son chunk ni au redémarrage (`ReanimatedPlayers.java:39-66`).
- **Balayage des cases d'un chunk à `LoadChunk`** : 64 cases × niveaux par chunk chargé, coût lié au déplacement des joueurs ; le balayage à budget fixe suffit (liaison en quelques secondes). Reste une optimisation possible si la population de zombies devient très grande.
- **Parcours complet de la liste à chaque `find`** : coût proportionnel à la population à chaque appel.
- **Clé `onlineId`** : réattribué à chaque retour en monde.
- **Mettre la demande en attente sur une case non chargée** : demande la vie hors écran (LK09) ; refus pour l'instant.
- **Adopter un corps de génération périmée** quand le corps courant manque : un ancien corps mis de côté reviendrait comme second PNJ ; voir ⚠ ci-dessous.

## Idées reprises

- Aucune.

## Tests

- Banc lupa (`tests/test_lk_bodies.py`) : mort et tueur (E04-T06, `KillerTests` et `KillerSoloTests` : doublures du chemin `Hit`, santé du propriétaire, véhicule, chute, feu à double `OnZombieDead`, relecture et refus d'une cause fausse, suite `rs.killer` sur les doublures) ; création (chemin B, étiquette, `useless`, préréglage avant le cadavre, fichier `LKREG1`), profil femme et refus de profils faux, case non chargée, case libre (LK02-T11 : deux PNJ sur la même case, joueur debout et case impraticable évités, personnage couché ou en véhicule sans effet, `embody`, refus quand tout est occupé), réanimation ratée sans débris, garde `Enabled` (rien créé, aucun corps retiré tant que coupé), client MP qui ne crée rien et n'écrit aucun fichier, aller-retour hors zone (même objet, nouvel `onlineId`), reliaison, **redémarrage** (nouveau banc relisant le fichier, corps recréés depuis un `reanimated.bin` simulé, `nextId` conservé), doublons (même génération, doublon mis de côté qui revient), orphelins (périmé, en avance, inconnu, PNJ virtuel ; non étiquetés intacts), mort → `dead`, `despawn`/`forget`, schéma inconnu bloqué sans écriture ni retrait, emplacement corrompu, deux emplacements illisibles, structure fausse, monde neuf, rattrapage paresseux et positions à `OnSave`, coût d'une tranche = budget avec 500 zombies, console `LKB` en solo et routage MP avec refus sans capacité, suite `lk.bodies` (4 tests sans aller-retour) sur les doublures, sources Kahlua.
- VM Kahlua (`tests/test_kahlua.py`, `test_identity_logic_in_kahlua`) : identifiants `lk-1`, classement, registre RSV2 relu et validé, schéma inconnu refusé.
- Serveur dédié de test (`run_dedicated_smoke.ps1 -Filters rst`, 2026-10-09) : 6/6, aucune erreur Lua de nos mods ; `[LivingKnox] INFO registry: new world, empty registry` puis `engine 0.1.0 started` ; fichier `registry-…-1.txt` écrit par la VM réelle.
- Serveur dédié de test (`-Filters rst`, 2026-10-09, après E04-T06) : 6/6, aucune erreur Lua de nos mods (abonnement `OnHitZombie` et suite `rs.killer` chargés par la VM réelle ; `rs.killer` porte le tag `world`, non lancée sans joueur).
- En jeu, à faire (E04-T06) : suite `rs.killer` en solo puis sur serveur dédié, et protocole manuel (`docs/annexes/tests/tests-en-jeu.md` § 12).
- En jeu, à faire : suite `lk.bodies` (6 tests, dont l'aller-retour et le retrait LK03-T04) en solo, puis redémarrage à la main (protocole du compte rendu de LK02-T02).
- Retrait loin des joueurs (LK03-T04) : banc `tests/test_lk_reports.py` (`MultiplayerReleaseTests`, 5 tests ; `SoloReleaseTests`, 2 tests) : corps rendu au bout du délai avec sa santé acceptée (1,5 rapportée par le propriétaire), son arme, sa dernière position, sa consigne abandonnée (clients sans consigne), aucun corps restant, aucun orphelin au balayage, membre de groupe présent avec son lien, réincarnation en génération 2 ; corps vu d'un joueur (même au bord, 118 cases) jamais rendu, délai qui repart de zéro ; corps qu'un client simule jamais rendu ; pause qui ne compte pas ; corps mis de côté rendu par sa dernière position puis retiré comme orphelin à son retour ; solo (joueur éloigné, corps mis de côté). Suspension des consignes : `tests/test_lk_directives.py` (4 tests, voir [consignes.md](consignes.md)). Suite en jeu `lk.bodies`, test `release` (délai abaissé à 3 s, joueur déplacé à 300 cases puis ramené : PNJ virtuel, aucun corps restant après le retour) : à lancer en solo.

- Matérialisation (LK09-T03) : banc `tests/test_lk_materialize.py` (15 tests, pile complète de `test_lk_reports.py` + doublure `getBuildingDef`) : membres présents seulement (chef d'abord, ni mort ni absent en expédition), santé selon la blessure, apparence et arme du profil, places distinctes autour du foyer ; deux allers-retours approche/départ/approche (mêmes PNJ, génération suivante, `nextId` inchangé, blessure tirée de la santé, aucun orphelin ni doublon) ; hystérésis 80/120 et plafond du rayon ; mort d'un corps (membre mort une fois, un seul `memberDied`, succession, moral), PNJ mort réconcilié sans publication, jamais recréé ; recrue et retour d'expédition matérialisés ; bornes (`PER_PASS`, `MAX_PER_GROUP`, `MAX_TOTAL`, foyer absent, foyer non chargé puis chargé) ; place dans le bâtiment ou hors bâtiment (camp), attente faute de place ; simulation horaire qui laisse les membres incarnés à leur corps (ni blessure, ni expédition, ni événement) ; clients MP sans matérialisation ; solo ; conversions santé ↔ blessure ; `hpMax` contrôlé à la relecture ; suite `lk.materialize` jouée sur les doublures (solo).

### Protocole solo (LK09-T03, nominal d'abord)

1. Partie de test `rstest…` neuve, Living Knox activé, population initiale faite (`console.txt` : `population: grp-1 …, home x,y,z`).
2. `RST.run({ suite = "lk.materialize", tags = "world" })` : 1/1 ; notes `member m-<k> npc lk-<n> wound w health h` ; ligne `[LKM] measure materialize: group grp-<n>, <n> bodies after the round trip`.
3. À la main : se téléporter à 20 cases du foyer d'un groupe : les membres présents apparaissent dans le bâtiment (ou le camp) en quelques secondes, `console.txt` : `materialized as npc …` ; s'éloigner à plus de 120 cases 1 min : `released …` puis `back to the offscreen simulation at home …` ; revenir : mêmes PNJ (même `lk-<n>`), aucun corps en double, aucun mort revenu.

### Protocole solo (LK03-T04, nominal d'abord)

1. `RST.run({ suite = "lk.bodies", tags = "world" })` : 6/6, ligne `[LKB] measure release: …`.
2. À la main : `LKB.spawn()`, `LKB.moveTo(1, 9, 0)`, puis s'éloigner à plus de 120 cases (véhicule) et attendre 1 min : journal `released to the offscreen simulation (…): body out of the loaded area …` ; `LKB.list()` → `virtual`. Revenir : aucun PNJ sur place, journal `body removed … (orphan lk-1 …: notEmbodied)` au retour de la zone.
3. MP (séance finale) : deux joueurs s'éloignent pendant un trajet → serveur `suspended`, le corps reste au repos (vu de loin, à 80-96 cases, il ne marche pas) ; un joueur revient → `resumed by …` ; les deux partent à plus de 120 cases → `released …` après 1 min.

## Points ouverts

- ⚠ Écriture du registre **avant** la sauvegarde du monde : après un arrêt brutal entre une création et la sauvegarde suivante, le registre peut annoncer la génération N alors que `reanimated.bin` ne contient que le corps N−1, retiré comme périmé ; le PNJ reste `embodied` sans corps. Depuis LK03-T04, il est rendu virtuel dès qu'aucun joueur n'est à 120 cases de sa dernière position pendant 1 min ; tant qu'un joueur reste près de cette position, il reste `embodied` sans corps (LK09-T03 ne le réincarne pas : la matérialisation saute un PNJ `embodied` ; il revient après le retrait).
- ⚠ LK03-T04 : rayon (120 cases), délai (60 s) et état neutre établis sur le banc (Java relevé, doublures) ; à vérifier en jeu (suite `lk.bodies`, test `release`) puis à deux clients (séance MP finale). Santé gardée (`hp`) réappliquée par la matérialisation pour un membre de groupe (LK09-T03, via `wound`) ; reste LK07 (santé de référence serveur).
- ⚠ LK09-T03 : rayon de matérialisation (80), hystérésis, place dans le bâtiment et santé de naissance établis sur le banc ; à vérifier en jeu (suite `lk.materialize` en solo, séance MP finale) : apparition visible à la portée d'un client MP, temps de création sur un serveur dédié (2 corps par 1,5 s), choix des cases dans un vrai bâtiment.
- Corrigé le 2026-10-09 (LK03-T06, fiche `neutralisation.md`, « Apparition chez les clients MP ») : le zombie temporaire n'est **jamais** envoyé aux clients (créé et retiré dans le même appel Lua, avant l'envoi des zombies par `NetworkZombiePacker.postupdate`) ; l'ancien constat « visible 5 s » était une déduction erronée. Reste : un corps retiré par le serveur disparaît chez les clients faute de paquets (5 s).
- ⚠ `useless` d'un corps possédé par un client : la valeur du propriétaire l'emporte (`NetworkZombieVariables`) ; à reprendre par LK02-T04.
- ⚠ À mesurer en jeu : retour du même objet après redémarrage (ModData relues de `reanimated.bin`), délai de liaison, taille de `reanimated.bin`.
