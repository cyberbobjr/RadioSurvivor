# Neutralisation des corps de PNJ

- Tâches : LK02-T04 (création) ; s'appuie sur LK02-T02 (corps, liaison), LK02-T10 (mesures A/B) et la décision LK02 du 2026-10-09 (base B, voix coupées, `useless` hors des trajets) ; LK02-T07 posera l'état « en trajet »
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-09 — Statut : brouillon

Code : `media/lua/shared/LivingKnox/LK_ZombieGuard.lua` (`LivingKnox.ZombieGuard`). Contraintes de base (effet de `useless`, `noTeeth`, voix, drapeaux transmis) : [corps-et-animations.md](corps-et-animations.md), section 3. Corps et liaison : [corps-registre.md](corps-registre.md).

## Problème

Un corps de PNJ est un zombie « joueur réanimé ». Il ne doit ni attaquer, ni mordre, ni crier, ni poursuivre les joueurs, ni réagir aux bruits comme un zombie, chez tous les clients et quel que soit le client qui le simule ; les zombies vanilla voisins gardent leur comportement.

## Contraintes du moteur (compléments de LK02-T04)

| Fait | Preuve | Statut |
|---|---|---|
| La morsure est décidée par le **simulateur** : `AttackState` teste `noTeeth` à l'événement `AttackCollisionCheck` ; un client n'envoie `ZombieHitPlayer` que s'il possède le zombie **et** que la cible est son joueur ; le serveur vérifie seulement `getOwner() == connexion` puis applique les dégâts sans relire `noTeeth`. Quand le serveur simule, `AttackState` tourne chez lui. `noTeeth` n'est ni transmis ni sauvegardé : chaque machine qui peut devenir propriétaire doit déjà le porter. | `J/ai/states/AttackState.java:137, 226` ; `J/network/GameClient.java:1133-1144` ; `J/network/packets/hit/ZombieHitPlayerPacket.java:63-74` ; `J/network/fields/hit/Bite.java:58-80` | confirmé statiquement |
| Réaction au bruit : `RespondToSound` sort si `useless`, et aussi sur le serveur et sur un client non propriétaire : seule la valeur du propriétaire compte. Repérage (`spottedNew`/`spottedOld`), errance (`ZombieIdleState`) et regroupement testent `useless`. | `J/characters/IsoZombie.java:1303-1316, 1700, 2005` ; `J/ai/states/ZombieIdleState.java:78` ; `J/ai/ZombieGroupManager.java:70` | confirmé statiquement |
| Voix : préfixe porté par le `SurvivorDesc` **propre à chaque zombie** (`getDescriptor`), lu à chaque son (`getVoiceSoundName`, cris d'attaque `LungeState`, mort `BurntToDeath`) ; le serveur ne joue aucune voix (`updateVocalProperties`). Le constructeur remplace un préfixe sans « Zombie » : le préfixe choisi, `LKSilentZombie`, le contient. Cris de douleur, chute, mort, repas et relevé sont des états de cette voix ; `hurtSound` n'est jamais joué par un zombie (section « Cri de douleur »). | `J/characters/IsoZombie.java:393-395, 411, 2888-2929` ; `J/characters/SurvivorDesc.java:118-124, 317` ; `J/ai/states/LungeState.java:37` | confirmé statiquement ; silence mesuré en solo (LK02-T10) |
| Un client MP ne reçoit **pas** les ModData d'un zombie ; le descripteur partagé d'un joueur réanimé ne porte ni ModData ni préfixe de voix. Seul le drapeau joueur réanimé arrive. Le client ne peut donc reconnaître un corps de PNJ que par une liste du serveur. | `J/SharedDescriptors.java:44-96, 157-230` ; `J/characters/IsoZombie.java:3792-3805` ; `J/characters/NetworkZombieVariables.java:10-64` | confirmé statiquement |
| Repas : `updateSearchForCorpse` ne cherche qu'un cadavre **non zombie** (joueur mort) en ligne dégagée, toutes les 10000 unités de `ThirtyFPSMultiplier` (≈ 5,5 min), sauf si le zombie a une cible ; la création d'un cadavre de non-zombie pousse aussi les zombies à 2 cases vers lui. Le repas commence quand `bodyToEat` est à moins d'une case (`updateEatBodyTarget`). `setEatBodyTarget(nil, false)` l'annule et vide `bodyToEat` ; le champ `bodyToEat` n'a pas de mutateur. | `J/characters/IsoZombie.java:2940-2980, 4136-4184` ; `J/iso/objects/IsoDeadBody.java:414-429` ; `J/ai/states/ZombieEatBodyState.java:33-60` | confirmé statiquement |
| Plante cultivée sous le corps : détruite au hasard (≈ 1 chance sur 100 par image à vitesse 1), feu de camp allumé : éteint par un corps **en mouvement** (≈ 1 sur 10000 par image). Aucun drapeau ne les coupe. Détails et évitement : section « Plantes cultivées et feux de camp » ci-dessous. | `J/characters/IsoZombie.java:2837-2847` ; `J/iso/IsoGridSquare.java:9713-9777` | confirmé statiquement |
| Cible de coups (`thumpTarget`) : posée sans cible ni marche par un véhicule à sirène voisin (`updateInternal`), sinon seulement en marche (`tryThump`) ; `setThumpTarget(nil)` l'efface (`IsoMovingObject`). Alarme d'un véhicule jamais ouvert : déclenchée au hasard par tout zombie voisin. | `J/characters/IsoZombie.java:2689-2697, 3016-3026` ; `J/iso/IsoMovingObject.java:407-413` | confirmé statiquement |

## Choix (2026-10-09)

| Mesure | Simulateur (client propriétaire, serveur s'il simule, solo) | Autres clients | Serveur quand un client possède le corps |
|---|---|---|---|
| `useless` (toujours, trajet compris depuis LK06-T10) | oui | non (valeur du propriétaire reçue) | non (écrasé par le propriétaire) |
| `noTeeth` | oui | oui (prêt pour un transfert) | oui |
| cible effacée | oui | non | non |
| repas annulé (`setEatBodyTarget(nil, false)`) | oui | non | non |
| cible de coups effacée | oui | non | non |
| voix : préfixe `LKSilentZombie`, `hurtSound` `LKSilentZombieHurt`, voix vanilla en cours arrêtée par son nom (au changement de préfixe et à chaque passage lent) | oui hors serveur (solo) | oui | non (aucune voix jouée) |

- **Reconnaissance** : autorité = `LivingKnox.Bodies.bound` (étiquette ModData relue par le sondage borné de `LK_Bodies`) ; client MP = liste `guardRoster` du serveur `{ rev, bodies = { { o = onlineId, id, t = trajet } } }`, renvoyée à tous quand elle change (corps relié ou retiré, nouvel `onlineId`, trajet) et à un client qui la demande (`guardHello`, envoyé à l'entrée en partie puis toutes les 600 images tant que rien n'est reçu) ; une liste de numéro plus ancien est ignorée (`ClientCommand` fiable mais non ordonné). Le client retrouve ses copies par un sondage borné et ne prend une copie que si son `onlineId` est dans la liste **et** qu'elle est joueur réanimé : un zombie ordinaire n'est jamais touché, même s'il porte le même numéro. La liste ne contient que les corps présents dans le monde avec un `onlineId` attribué.
- **Réapplication** : tout est idempotent et repris à chaque passage ; un nouveau propriétaire réapplique au passage suivant ; une copie client recréée (nouvel objet, même `onlineId`) ou un corps revenu avec son chunk (nouvel `onlineId`, nouvelle liste) est retrouvé par le sondage.
- **Trajets** : `ZombieGuard.setTravelling(npcId, vrai|faux)` sur l'autorité, `ZombieGuard.isTravelling(npcId)` partout ; ouvert par LK02-T07 seulement pour la marche en ligne droite d'un corps simulé par le serveur (un client propriétaire marche en `pathfind` avec `useless` gardé, voir [consignes.md](consignes.md)). Depuis LK06-T10, le drapeau ne lève plus `useless` : un corps non `useless` réagissait aux bruits sans source des PNJ, jusqu'à son propre pas (état `turnalerted`, chemin remplacé), voir [zombies.md](zombies.md), section 5. Toute marche passe par l'état `pathfind`.
- **Indépendant de l'option `Enabled`** : un corps existant n'est jamais rendu à son comportement de zombie.
- **Coût** : un passage toutes les 3 images sur les seuls corps connus (au plus `Bodies.MAX_EMBODIED` = 50), 1 à 6 appels Java par corps quand rien ne change ; passage lent toutes les 15 images : liste du serveur (test `contains` dans la liste des zombies par corps relié), tranche client de 64 zombies (seulement si la liste n'est pas vide ; un appel `getOnlineID` puis une lecture de table par zombie), contrôle des dangers. Aucun abonné `OnZombieUpdate` (il serait appelé pour chaque zombie à chaque image).
- **Comportements résiduels** : repas annulé à chaque passage (au plus 3 images de repas) ; la marche vers un cadavre de joueur reste possible quand la ligne n'est pas dégagée (état `pathfind`, qui ignore `useless`) ; plante et feu de camp **non empêchables** : un avertissement unique par case (`npc <id> is on a farming plant…`) sert de mesure ; évitement par LK04-T06 (section « Plantes cultivées et feux de camp »). Alarme de véhicule non traitée ; cri de douleur : section « Cri de douleur » (LK06-T06).

## Plantes cultivées et feux de camp (LK04-T06, 2026-10-09)

### Comportement du moteur (Java 42.21.0)

| Fait | Preuve | Statut |
|---|---|---|
| À chaque mise à jour d'un zombie (`updateInternal`), sur **toute machine qui le met à jour** (solo, serveur, chaque client qui en a une copie, distante comprise : aucun test `isRemoteZombie` avant ces lignes) : si **sa** case (`getSquare()`, pas les voisines) porte une plante cultivée, `destroyFarmingPlant()` avec une chance de 1 sur `max(1, (int)(100 / TrueMultiplier))`, **en marche ou à l'arrêt** ; si elle porte un feu de camp **allumé** et que le zombie est en mouvement (`isMoving()`, drapeau `bMoving`), `putOutCampfire()` avec une chance de 1 sur `max(1, (int)(10000 / TrueMultiplier))`. Sautés dans les états à terre, chancelant, brûlé, faux mort (retour anticipé). | `J/characters/IsoZombie.java:2655, 2778-2781, 2837-2847` | confirmé statiquement |
| `TrueMultiplier` = vitesse de jeu × `perObjectMultiplier` (pas d'un zombie lointain mis à jour moins souvent, qui compense) : la fréquence par seconde vaut ≈ mises à jour par seconde ÷ 100 (plante), ÷ 10000 (feu), à vitesse 1. Client et solo : une mise à jour par image (≈ 60/s) ; serveur dédié : ≈ 10/s (`UpdateLimit(100)`). | `J/GameTime.java:947-949` ; `J/MovingObjectUpdateSchedulerUpdateBucket.java:43-76` ; `J/network/GameServer.java:835` | confirmé statiquement |
| Plante : `hasFarmingPlant` lit le système `farming` des `CGlobalObjects` sur un client MP, des `SGlobalObjects` ailleurs ; une plante détruite compte encore. La destruction appelle `CFarmingSystem.destroyPlant` sur un client (commande `destroy` au serveur, acceptée sans contrôle) ou `SFarmingSystem.destroyPlant` ; une plante semée passe à l'état `destroyed` (reste sur la case, morte), un sol seulement labouré est retiré. | `J/iso/IsoGridSquare.java:9713-9738` ; `J/globalObjects/GlobalObject.java:86-101` ; vanilla `client/Farming/CFarmingSystem.lua:176-183`, `server/Farming/farmingCommands.lua:118-125`, `server/Farming/SPlantGlobalObject.lua:695-705` | confirmé statiquement |
| Feu de camp : `hasLitCampfire`, `getCampfire` et `putOutCampfire` passent par les `SGlobalObjects` seulement ; sur un client MP le système `campfire` n'existe pas (`SGlobalObjectSystem.lua:1` et `SCampfireSystem.lua:1` : `if isClient() then return end`) : **seul le serveur (ou le solo) éteint un feu**. `putOut` éteint (combustible × 0,9) sans retirer le feu. | `J/iso/IsoGridSquare.java:9740-9776` ; vanilla `server/Camping/SCampfireSystem.lua:186-192`, `SCampfireGlobalObject.lua:343-348` | confirmé statiquement |
| Recherche de chemin d'un zombie : `PathFindRequest.avoidFarmingPlants` n'est vrai que pour un `IsoPlayer` et rien ne le pose pour un zombie ; le chemin trouvé (`Path`) n'est pas exposé à Lua (seul `PathFindBehavior2` l'est). Le bit « plante » d'une case ne sert donc qu'aux joueurs. Une case de feu de camp **allumé** est marquée « solide transparente + frappable » pour le chercheur natif, mais seulement sur une machine où `hasLitCampfire` est vrai (solo, serveur ; jamais sur un client MP, qui exécute pourtant nos trajets). Effet exact dans le code natif (C++) non lisible. | `J/pathfind/nativeCode/PathFindRequest.java:51-81`, `PathfindNative.java:310`, `SquareUpdateTask.java:228-256` ; `J/Lua/LuaManager.java:2401-2402` | confirmé statiquement ; contournement du feu en solo : hypothèse |

### Règles retenues

- **Zone dangereuse** : une case qui porte une plante cultivée (vivante ou détruite) ou un feu de camp (allumé ou non : un feu éteint peut être rallumé), et ses 8 voisines (`Bodies.HAZARD_AVOID = 1` : marge pour la tolérance d'arrivée d'une case et la séparation des personnages). Lue par l'autorité seulement (`Bodies.hazardOn`, `Bodies.hazardNear`), qui voit les deux systèmes.
- **Destination** (`Directives.moveTo`) : une case visée dans la zone est **décalée** vers la case praticable la plus proche sans danger à 2 cases (`HAZARD_AVOID + 1`), à `Directives.SHIFT_RADIUS = 3` cases au plus (journal `move target … shifted to …`) ; sans case de ce genre (champ cultivé), la consigne est **refusée** (`… next to a farming plant at … and no safe square within 3`).
- **Trajet** : aucun moyen Java de rendre ces cases impraticables pour un zombie (ci-dessus). Depuis LK05-T12 (2026-10-10), une ligne droite départ → arrivée qui traverse la zone est **découpée en points de passage** choisis par l'autorité autour de la boîte englobante des dangers (à 3 cases), chaque segment hors zone ; entre deux points, le chemin reste celui du jeu (risque réduit, pas supprimé). Sans contournement simple, la destination reste directe et les cases dangereuses de la ligne sont signalées (`WARN … straight line crosses N farming plant or campfire square(s) (first x,y …) and <raison>: the vanilla path may cross them`). Règles et format : [consignes.md](consignes.md), « Points de passage ».
- **À l'arrêt** (`Bodies.hazardPass`, autorité, toutes les 4 tranches du balayage, ≈ 1 s) : un corps sans consigne en cours (aucune, ou close) dont la case est dans la zone reçoit une consigne `move` courte (`walk`) vers la case praticable la plus proche sans danger à 2 cases, à `Bodies.HAZARD_RADIUS = 4` cases au plus ; au plus une tentative par PNJ toutes les `HAZARD_RETRY_MS` (10 s) ; une consigne en cours n'est jamais interrompue. Grâce à la marge de 2 cases, un corps arrêté à la tolérance d'arrivée est hors de la zone et le déplacement ne se répète pas. Un geste accroupi d'arrivée est perdu (`walk` puis `idle`).
- **Création** (`Bodies.findFreeSquare`, donc `spawn` et `embody`) : la case retenue est hors de la zone.
- **Mesure gardée** : l'avertissement de `ZombieGuard.checkHazards` (une ligne par case) reste ; sur un client MP il ne peut signaler que les plantes (feu invisible côté client).

### Risque résiduel : traversée pendant un trajet

Vitesses mesurées : 0,8 case/s (marche `pathfind`, LK02-T10) à 1,8 case/s (`lk.executor`, démarrage compris), soit 0,56 à 1,25 s par case traversée en ligne droite (moins en coupant un coin).

| Cas | Plante cultivée traversée | Feu de camp allumé traversé |
|---|---|---|
| Solo (≈ 60 tirages/s) | 1 − 0,99^(33 à 75) ≈ **28 à 53 %** par case | 1 − 0,9999^(33 à 75) ≈ 0,3 à 0,7 % par case (contournement probable par le chercheur natif, non vérifié) |
| MP, client simulateur seul près du corps | client (60/s) + serveur (10/s) : ≈ **32 à 58 %** par case | serveur seul (10/s, et seulement si sa copie a `bMoving` : hypothèse) : ≈ 0,06 à 0,12 % par case ; chemin du client jamais détourné |
| MP, chaque autre client qui voit le corps | + 33 à 75 tirages chacun | aucun ajout |
| Corps **arrêté** sur une plante (avant l'écart : au plus ≈ 1 s de détection, puis le trajet) | 0,6 tirage/s en solo : 45 % en 1 s, 99 % en 7,7 s | sans objet (à l'arrêt) |

Conséquence : la règle d'arrêt et la destination suppriment l'essentiel du risque à l'arrêt ; un trajet qui traverse un potager détruit très probablement une plante par case traversée. Remèdes possibles plus tard : points de passage choisis par l'autorité (LK05) autour des zones signalées, ou trajet découpé ; non traités ici.

### Tests (LK04-T06)

- Banc lupa : `test_lk_bodies.py` (création hors des plantes et feux, feu invisible sur un client MP, message de refus), `test_lk_directives.py` (cible sur une plante décalée puis refusée dans un champ, ligne droite signalée, corps à l'arrêt écarté une seule fois et jamais pendant une consigne en cours, feu vu par l'autorité seulement, solo sur un feu allumé), `test_lk_guard.py` (feu signalé par le serveur seulement, plante par le client simulateur). Doublures : `hasFarmingPlant` partout, `getCampfire`/`hasLitCampfire` nuls sur un client MP (`IsoGridSquare.java:9713-9765`).
- En jeu : suite `lk.farm` (tags `world`, `server`, autorité seulement) — plante semée (`SFarmingSystem:plow` puis `SPlantGlobalObject:seed("Carrots", 0)`) et feu de camp allumé (`SCampfireSystem:addCampfire`, `addFuel`, `lightFire`) posés près du PNJ ; `move` sur la plante puis sur le feu (cible décalée, arrivée hors de la zone, objet intact 60 s après) ; plante posée à côté du corps arrêté (écart en quelques secondes, plante intacte 60 s après) ; mesure seule d'un trajet dont la ligne droite traverse une plante. Lignes `[LKF] measure`. Nettoyage `t:defer` : plante (`removePlant`), feu (`removeCampfire`), PNJ.

### Protocole solo court (`rstest-solo`, dehors, terrain dégagé)

1. `RST.run({ suite = "lk.farm", tags = "world" })` (≈ 5 min, sans pause) ; relever les lignes `[LKF] measure` et le résumé (3 tests vérifiés et 1 mesure).
2. Facultatif : planter soi-même une graine, `LKB.spawn()` à 4 cases, `LKB.moveTo(1, <dx>, <dy>)` sur la plante : journal `shifted to`, la plante reste vivante.

## Cri de douleur (LK06-T06, 2026-10-09)

### Sons d'un zombie (Java 42.21.0, scripts `media/scripts/generated/sounds/zombies/`)

Un zombie n'a **pas** de son de blessure, de chute, de mort ou de repas distinct : les scripts ne définissent que ses voix (`Male|FemaleZombie[Sprinter]VoiceA|B|C`, événement FMOD `Zombie/Voice/…`) et ses morsures (`…BiteA|B|C`). Les cris sont des **états** (paramètre FMOD local `ZombieState` : `Idle`, `Eating`, `Hit`, `Death`, `Pushed`, `GettingUp`, `AttackBite`, `RunOver`…) de l'unique événement de voix, lancé par `ZombieVocalsManager` sous le nom `getVoiceSoundName()`.

| Événement | Origine | Machine | Réglable depuis Lua | Traitement |
|---|---|---|---|---|
| Frappé, renversé (cri) | `IsoZombie.playHurtSound` (surcharge) **ne joue rien** : état `Hit` de la voix ; `ZombieHitReactionState` pose `Hit` ou `RunOver` ; paquet `ZombieSound.Hurt` reçu par un client → même appel | chaque client et le solo (voix locale) | préfixe (`SurvivorDesc:setVoicePrefix`) | coupé avec la voix |
| `hurtSound` (= préfixe + `Hurt`, posé au constructeur et par `setFemaleEtc`) | lu seulement par `IsoGameCharacter.playHurtSound`, surchargé par le zombie, et par un test `isPlaying` sous un véhicule ; aucun son `…ZombieHurt` dans les scripts | aucune | `getHurtSound` / `setHurtSound(String)` (`IsoGameCharacter`, classe exposée) | nom inexistant posé par prudence (`LKSilentZombieHurt`) |
| Poussé, chancelant, relevé, repas, cible | états `Pushed`, `GettingUp`, `Eating`, `SearchTarget` de la voix | chaque client, solo | préfixe | coupé avec la voix |
| Mort (cri) | `playDeadSound` pose l'état `Death` | chaque client, solo | préfixe | coupé avec la voix |
| Mort (impact) | `playDeadSound` : `HeadStab`, `HeadSlice` ou `HeadSmash` (sons d'impact, pas de voix) | chaque client, solo (rien sur le serveur) | non | gardé (bruit d'un coup, plausible pour un humain) |
| Brûlé, attaque surprise, élan, repas dans un véhicule | préfixe + `Death`, `Attack`, `Eating` ; paquets `Burned`, `Lunge` | clients, solo | préfixe | noms déjà absents des scripts : muets même pour un zombie vanilla |
| Morsure | préfixe + `[Sprinter]Bite` + A/B/C sur l'émetteur de la victime | simulateur et victime | préfixe ; `noTeeth` empêche la morsure | coupé (préfixe et `noTeeth`) |
| Griffure, vêtement déchiré | `ZombieScratch`, `ZombieRipClothing` sur la victime | victime | non | évité : `useless` + cible effacée (pas d'attaque) |
| Chute | `LandLight`, `LandHeavy`, `FirstAidFracture` (`handleLandingImpact`), `BodyHitGround` (événement d'animation `PlaySound` des AnimSets `falldown`) | là où le zombie est animé | non | gardé (bruits de corps, humains) |
| Coup reçu (impact de l'arme) | `getZombieHitSound()` de l'arme sur l'émetteur de **l'attaquant** (+ paquet `PlaySound`), paramètre `CharacterHitResult` | attaquant, relayé | non (son de l'arme) | gardé : même son qu'un coup sur un humain |
| Pas | `ZombieFootstepsCombined` (`ZombieFootstepManager`) | clients à moins de 15 cases | non | hors tâche (pas un cri) ; non coupable |

Preuves : `J/characters/IsoZombie.java:393-395, 411, 2573, 2589-2599, 2888-2929, 3473-3476, 3732-3747, 3792-3805` ; `J/characters/IsoGameCharacter.java:2950-2956, 9513-9545, 11601-11602` ; `J/characters/ZombieVocalsManager.java:171-200` ; `J/characters/CharacterSoundEmitter.java:65-82, 327-347` ; `J/audio/parameters/ParameterZombieState.java` ; `J/ai/states/ZombieHitReactionState.java:126-129`, `StaggerBackState.java:81`, `ZombieGetUpState.java:39`, `ZombieEatBodyState.java:58`, `LungeState.java:37-39`, `BurntToDeath.java:42-46`, `FakeDeadAttackState.java:40-41`, `AttackNetworkState.java:105-109` ; `J/characters/BodyDamage/BodyDamage.java:1243-1333` ; `J/network/GameClient.java:1911-1960` ; `J/CombatManager.java:230-242, 702-790` ; `fmod/fmod/FMODSoundEmitter.java:166-186, 484-490, 603-614, 910, 937` ; scripts `sounds_zombie_voice_male.txt`, `sounds_zombie_voice_female.txt`, `sounds_zombie_foley.txt`. Statut : confirmé statiquement.

### Cause retenue et correction

- Le préfixe muet suffit pour toute voix **lancée après** lui : le nom construit n'existe pas, `playSoundImpl` rend 0 et rien ne joue. Une voix vanilla **déjà en cours** garde en revanche son événement et crie à chaque coup (état `Hit`). Deux cas la laissent vivre : une voix lancée avant le premier passage de la garde dont le nom n'est plus celui que `getVoiceSoundName()` construit (vitesse `speedType` ou choix de voix changés entre-temps), et un préfixe remis par le moteur (`setFemaleEtc` : habillage `PersistentOutfits`, descripteur partagé reçu par un client `useDescriptor`) puis voix relancée avant le passage suivant.
- Correction (`LK_ZombieGuard.lua`, chaque machine qui joue les voix) : au changement de préfixe **et** à chaque passage lent (15 images), arrêt par `stopSoundByName` de toute voix vanilla que `isPlaying(nom)` trouve sur l'émetteur du corps (`ZombieGuard.ZOMBIE_VOICES`, 10 noms, plus le nom courant pour une voix de mod) ; `hurtSound` reçoit `LKSilentZombieHurt`. Compteur `ZombieGuard.stats.voicesStopped`. Silence par défaut.
- **Option non activée** (aucune fonctionnalité nouvelle sans validation) : donner au PNJ un cri humain en le remplaçant à la main sur un coup, par exemple `VoiceMalePainFromHitBlunt` / `VoiceFemalePainFromHitBlunt` (`sounds_player_voice_male.txt`, `…_female.txt`) joué par `getEmitter():playVocals(nom)` sur chaque client à la réception d'un coup. Rien ne l'appelle ; à décider avec le combat (LK06).

### Limites

- Fenêtre résiduelle : une voix relancée juste après une remise du préfixe peut jouer jusqu'au passage suivant (3 images) ; une voix vanilla restée en cours alors que le préfixe est déjà muet est trouvée au plus 15 images plus tard.
- Client MP : la copie n'est reconnue qu'après la liste du serveur et la tranche du sondage (jusqu'à ≈ 2 s pour 500 zombies chargés, voir « Points ouverts ») : un coup porté dans ce délai peut encore faire crier.
- Les bruits d'impact (arme, chute, `HeadSmash`…) restent : ce ne sont pas des voix et ils sont les mêmes pour un humain.

### Tests (LK06-T06)

- Banc lupa (`tests/test_lk_guard.py`, 15 tests) : voix lancée en sprinteur avant la liaison puis vitesse changée (arrêtée par son nom) ; coup ensuite (`playHurtSound` sans son, aucune voix relancée) ; voisin vanilla qui garde voix et `hurtSound` ; préfixe remis par `setFemaleEtc` puis voix relancée (coupée au passage suivant) ; voix restée en cours sous préfixe muet (trouvée au passage lent seulement) ; copies clientes MP qui gémissaient déjà ; idempotence. Doublures fidèles : `isPlaying(String)` par nom de `GameSound`, `stopSoundByName` sans effet sur un nom inconnu, voix lancée seulement si le nom existe dans les scripts.
- En jeu : suite `lk.pain` (tag `world`, solo) — le joueur frappe le PNJ par l'API vanilla (`z:Hit(batte, joueur, 0.0, false, 1.0)` : chemin de coup complet, réaction, dégâts nuls donc PNJ vivant), puis 3 s d'écoute de l'émetteur (`isPlaying` sur les 10 voix vanilla) : aucune ; témoin : un zombie vanilla (`useless` et `noTeeth` pour ne pas attaquer) frappé de même doit être entendu au moins une fois, sinon la sonde ne prouve rien. Lignes `[LKP] measure`.
- Serveur dédié de test (`run_dedicated_smoke.ps1 -Filters rst`, 2026-10-09) : 6/6, aucune erreur Lua de nos mods.

### Protocole solo court (`rstest-solo`)

1. `RST.run({ suite = "lk.pain", tags = "world" })` (≈ 1 min, sans pause) ; relever les deux lignes `[LKP] measure` (PNJ : 0 échantillon avec une voix ; témoin : au moins un).
2. Écoute : `LKB.spawn()`, frapper le PNJ à la batte puis le pousser (aucun cri ni gémissement de zombie ; seuls les bruits d'impact) ; frapper ensuite un zombie vanilla : il crie.

## Apparition chez les clients MP (LK03-T06, 2026-10-09)

Deux défauts signalés par le rapport de jalon 1 (§ 8) : zombie temporaire de la création visible jusqu'à 5 s chez les clients proches ; copie cliente d'un PNJ qui peut gémir jusqu'à ≈ 2 s avant d'être reconnue par la liste `guardRoster`.

### Envoi des zombies aux clients (Java 42.21.0, J = `zombie/...`)

| Fait | Preuve | Statut |
|---|---|---|
| Le serveur n'envoie les zombies qu'une fois par image, dans `NetworkZombiePacker.postupdate`, appelé par `ServerMap.postupdate` **après** le Lua de l'image (commandes clientes, `OnTick`). | `J/network/GameServer.java:888-931, 1010, 1073` ; `J/network/ServerMap.java:548` | confirmé statiquement |
| Seuls partent les zombies de la liste de la cellule : attribution d'un propriétaire (`updateAuth` sur `getZombieList()`), puis données au propriétaire (`zombiesRequest`) et relais aux autres clients des paquets du propriétaire (`zombiesProcessing`). | `J/popman/NetworkZombiePacker.java:115-183` ; `J/popman/NetworkZombieManager.java:60-131` | confirmé statiquement |
| `addZombiesInOutfit` donne au zombie un `onlineId` et l'ajoute à la liste sans rien envoyer ; `createCorpse(zombie)` → `IsoDeadBody(zombie)` le retire aussitôt (`removeFromWorld` : `onlineId` rendu, sorti de la liste, aucun propriétaire). Le cadavre n'est envoyé par aucune de ces fonctions ; `reanimate` le retire. | `J/VirtualZombieManager.java:197-223` ; `J/iso/IsoGridSquare.java:10109-10124` ; `J/iso/objects/IsoDeadBody.java:252-442` (retrait 378-380), `1450-1462`, `1832-1946` ; `J/characters/IsoZombie.java:3554-3589` | confirmé statiquement |
| Un retrait côté serveur n'est annoncé aux clients que par `NetworkZombiePacker.deleteZombie` (paquet `ZombieDeleteOnClient`), non exposé à Lua ; sinon la copie cliente disparaît après 5 s sans paquet. | `J/popman/NetworkZombiePacker.java:66-71, 175-178` ; `J/characters/IsoZombie.java:2716-2722` | confirmé statiquement |
| Copie cliente : `parseZombie` crée le zombie par `createRealZombieAlways(outfitId du paquet)` ; l'identifiant de tenue persistante est posé **avant** `OnZombieCreate`, `onlineId` et drapeaux (dont joueur réanimé) **après**. | `J/popman/NetworkZombieSimulator.java:164-219` ; `J/VirtualZombieManager.java:197-210, 265-271` ; `J/characters/NetworkZombieVariables.java:40` | confirmé statiquement |
| Identifiant de tenue d'un joueur réanimé = tenue « ReanimatedPlayer » + emplacement de son **descripteur partagé**, unique parmi les joueurs réanimés présents, rendu quand le corps quitte le monde et repris à son retour (comme `onlineId`). | `J/SharedDescriptors.java:44-117` ; `J/ReanimatedPlayers.java:63, 99` | confirmé statiquement |
| Ordre d'une image client : paquets (`GameClient.update`, dont `OnServerCommand` et la création des copies), monde (`IsoWorld.update` : mises à jour des zombies, gestionnaire de voix toutes les 500 ms), `OnTick` en dernier. L'habillage d'une copie de joueur réanimé (`useDescriptor` → `setFemaleEtc`) remet le préfixe de voix vanilla. | `J/GameWindow.java:296-302` ; `J/gameStates/IngameState.java:1543, 1681` ; `J/CollisionManager.java:297` ; `J/characters/ZombieVocalsManager.java:55-63` ; `J/characters/IsoZombie.java:3732-3747, 3792-3805` ; `J/core/skinnedmodel/ModelManager.java:506-512` | confirmé statiquement |

### Voies étudiées

1. **Zombie temporaire** : aucune voie à ajouter. Créé et retiré dans le même appel Lua, il n'est jamais dans la liste quand le serveur envoie les zombies ; aucun client ne le reçoit. Le constat « visible jusqu'à 5 s » du jalon 1 était une déduction erronée (il supposait un envoi). Règle gravée dans `Bodies.createBody` : ne jamais différer une étape entre `addZombiesInOutfit` et `reanimate`. Écartées sans objet : cadavre `IsoDeadBody` créé directement ou `createRandomDeadBody` (même chemin `createCorpse`, et `sendCorpse` en MP), case hors portée puis déplacement, commande de retrait côté client.
2. **Copie muette dès son apparition** : écartées la seule liste envoyée plus tôt (la copie reste à retrouver par le sondage), `OnZombieCreate` sur l'`onlineId` (pas encore posé), un repère dans le descripteur (ni ModData ni préfixe transmis) et `OnZombieUpdate` (un appel Lua par zombie et par image). Retenue : la liste porte l'identifiant de tenue du corps, publiée dès la liaison, et le client s'abonne à `OnZombieCreate`.

### Correction retenue

- Serveur (`LK_Bodies` → `ZombieGuard.bodyBound`) : à chaque liaison (création, retour de chunk, redémarrage), garde posée tout de suite et liste publiée dans la même image, donc **avant** l'envoi des paquets de zombies. Entrée : `{ o = onlineId, p = identifiant de tenue, id, t }`.
- Client, `OnZombieCreate` : si l'identifiant de tenue est dans la liste, voix coupée sur-le-champ (avant que le gestionnaire de voix puisse passer dans l'image). Image suivante (`bornPass`) : confirmation par `onlineId` + joueur réanimé ; sinon voix rendue (liste périmée : descripteur repris entre-temps par un vrai joueur réanimé).
- Client, liste reçue après la copie (livraison non ordonnée, client arrivé après) : les zombies nés depuis moins de `SEEN_MS` (10 s, au plus 1024) sont gardés par `onlineId` ; la copie est adoptée et sa voix arrêtée à la réception même de la liste. Au-delà, le sondage borné reste le repli.
- Copie adoptée : repassée à chaque image pendant `FRESH_MS` (3 s), pour recouper la voix après l'habillage ; ensuite tous les `APPLY_EVERY` images, comme avant.
- Solo : la garde est posée dans `Bodies.spawn`, avant la première image.
- Retour de chunk, copie née avant la nouvelle liste (campagne MP du 2026-10-15, `lk.spawnclean` : préfixe vanilla pendant 54 images, aucune voix jouée, « pre-silenced 0, adopted 1 ») : le corps déchargé était sorti de la liste, son identifiant de tenue aussi. Le client retient désormais les identifiants de tenue des corps sortis de la liste pendant `GONE_MS` (5 min, au plus 256 ; effacés quand le corps revient dans la liste ou au passage lent suivant leur échéance) : la copie recréée est muette dès `OnZombieCreate`. À l'image suivante, un joueur réanimé ainsi reconnu par sa tenue mais sans entrée à son `onlineId` n'a plus sa voix rendue tout de suite : il est gardé muet (`held`, recoupé à chaque image) jusqu'à son adoption à la réception de la liste, `HOLD_MS` (3 s) au plus, puis sa voix lui est rendue (zombie ordinaire de même tenue). Banc : `test_lk_guard.py` (`test_chunk_return_copy_born_before_the_new_roster_stays_silent`, liste périmée rendue après `HOLD_MS`). Non revérifié en jeu.

### Ce qui reste

- Liste reçue **après** la copie : la copie peut gémir entre sa création et la réception (en pratique la liste part dans la même image serveur que le corps ; client propriétaire : paquets de la même image ; autres clients : la copie n'arrive qu'après un aller-retour par le propriétaire).
- Client arrivé après : copies muettes à la réponse au `guardHello`, soit environ un aller-retour réseau après son premier `OnTick`.
- Habillage après `FRESH_MS` (copie hors de vue plus de 3 s) : préfixe recoupé au passage suivant (≤ 3 images, ≈ 50 ms) ; une voix lancée entre-temps est arrêtée par son nom.
- Zombie rendu muet à tort par une liste périmée : muet une image au plus.
- Hors de cette tâche : un corps **retiré** par le serveur (renvoi, doublon, orphelin) reste visible jusqu'à 5 s chez les clients (`deleteZombie` inaccessible).

### Tests (LK03-T06)

- Banc lupa `tests/test_lk_guard.py`, classe `AppearanceTests` (7 tests) : zombie temporaire jamais dans la liste du serveur en fin d'image (envoi) et liste publiée dès `spawn` ; copie créée après la liste (doublure `NET_CREATE` fidèle à `parseZombie`) muette au gestionnaire de voix de son image de création, puis recoupée après `setFemaleEtc` ; copie née avant la liste rendue muette à la réception (ordre `lifo`, sans sondage) ; client arrivé après ; liste périmée (voix rendue, `hurtSound` compris) et zombie ordinaire au même `onlineId` jamais pris ; retour de chunk publié aussitôt avec les nouveaux identifiants ; tables bornées et purgées. `SoloGuardTests.test_silent_from_creation`.
- `tests/test_lk_bodies.py` : doublure du descripteur partagé (`TAKE_DESCRIPTOR`, `RELEASE_DESCRIPTOR`) et `test_temporary_zombie_gone_before_the_call_returns_and_body_descriptor`.
- Serveur dédié de test (`run_dedicated_smoke.ps1 -Filters rst`, 2026-10-09, `version=42.21.0`) : 6/6, aucune erreur Lua de nos mods (chargement des fichiers modifiés seulement).

### Protocole MP à deux clients (séance finale)

Serveur dédié de test, option sandbox `LivingKnox.Debug` activée (lignes `DEBUG`), clients A et B à 5-10 cases l'un de l'autre.
1. A crée un PNJ (`LKB.spawn()` : 2 cases à l'est et au sud de A ; B se place à 3 cases). Chez A **et** B : aucun second zombie visible, même un instant, à côté du PNJ ; aucun gémissement ni cri à l'apparition ni pendant 30 s à 2 m.
2. Journaux clients (`console.txt`, niveau debug) : `guard: npc lk-1 copy adopted at its appearance` dans la seconde de l'apparition ; jamais `voice cut failed`. Serveur : `guard roster N sent` à la même seconde que `npc lk-1 embodied`.
3. B s'éloigne à 300 cases puis revient : à son retour, aucun gémissement à la réapparition de la copie.
4. B se déconnecte puis se reconnecte près du PNJ : au plus un bref son à l'entrée (avant la réponse à `guardHello`), puis silence.
5. Témoin : un zombie vanilla apparu (menu debug) à côté du PNJ gémit normalement chez A et B.

## Alternatives écartées

- Abonné `OnZombieUpdate` : appelé pour chaque zombie chargé à chaque image, sur chaque machine : coût proportionnel à la population.
- Silence de tous les joueurs réanimés côté client (sans liste) : toucherait les zombies de vrais joueurs morts.
- `setReanimatedForGrappleOnly(true)` pour les voix : change l'état « traîné » du zombie (drapeau transmis, comportement de saisie) ; non retenu à l'essai.
- `noTeeth` chez le propriétaire seulement : un transfert de propriété laisserait une fenêtre de morsure avant le premier passage du nouveau propriétaire.

## Idées reprises

- Aucune.

## Tests

- Banc lupa (`tests/test_lk_guard.py`, 15 tests depuis LK06-T06) : corps simulé par le serveur, liste envoyée aux deux clients, voix coupée chez eux seulement, drapeaux de repos chez le simulateur seulement ; client propriétaire puis transfert (le nouveau propriétaire réapplique, le serveur ne garde que `noTeeth`) ; trajet (useless levé puis remis) ; retour de chunk (nouvel `onlineId`) et copie recréée ; zombie sans étiquette et zombie ordinaire au même `onlineId` jamais touchés ; `guardHello` répondu au seul demandeur, liste ancienne ignorée ; coût (aucun sondage sans liste, 64 zombies par tranche) ; solo (tout appliqué, voisin vanilla intact, idempotence) ; danger signalé une fois, feu de camp signalé par le serveur seulement (LK04-T06) ; échec de la voix journalisé une fois.
- Serveur dédié de test (`run_dedicated_smoke.ps1 -Filters rst`, 2026-10-09) : 6/6, aucune erreur Lua de nos mods (chargement de la garde).
- En jeu : suite `lk.guard` (tags `world`) — voisin vanilla, contact 60 s, aller-retour hors zone. Protocole ci-dessous.

### Protocole solo (`rstest-solo`, nominal d'abord)

1. `RST.run({ suite = "lk.guard", tags = "world" })` ; attendre la fin (≈ 3 min, sans pause) ; relever les lignes `[LKG] measure`.
2. Écoute : `LKB.spawn()`, se tenir à 2 m du PNJ 30 s (aucun gémissement), puis faire apparaître un zombie vanilla (menu debug) à côté : il gémit et attaque.
3. Faire du bruit (coup de feu, klaxon) près du PNJ : il ne se tourne pas vers la source et ne marche pas.
4. Facultatif : planter une graine, faire apparaître le PNJ sur la case (`LKB.spawn` avec décalage) : noter le délai de destruction et la ligne `WARN … farming plant` (mesure du comportement résiduel).

### Deux clients (séance MP finale)

Chez chaque client, à 2 m : silence ; un client au contact 60 s, puis l'autre (transfert de propriété) : aucune attaque ; zombie vanilla voisin normal chez les deux.

## Points ouverts

- ⚠ Silence chez un client MP (préfixe posé localement à la copie reçue) et après une recréation : mesuré en solo seulement.
- Délai entre l'apparition d'une copie chez un client et la coupure de sa voix : réglé par LK03-T06 (voir « Apparition chez les clients MP ») ; reste à écouter à deux clients.
- ⚠ Marche vers le cadavre d'un joueur mort derrière un obstacle (`pathfind` ignore `useless`) : fréquence à mesurer avant de forcer l'arrêt.
- ⚠ Plante détruite et feu de camp éteint : non empêchables ; évités à la destination, à l'arrêt et à la création (LK04-T06), contournés pendant le trajet par points de passage (LK05-T12) mais **pas entre deux points** (chemin vanilla) (risque chiffré dans la section « Plantes cultivées et feux de camp »).
- ⚠ Cri de douleur (LK06-T06) : coupé en statique et au banc ; mesure `lk.pain` en solo et écoute chez deux clients MP à faire.
