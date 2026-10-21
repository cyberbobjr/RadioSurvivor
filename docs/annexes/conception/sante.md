# Santé des corps de PNJ : dégâts subis et synchronisation

- Tâches : LK07-T01 (création, investigation), LK07-T02 (santé de référence, section du même nom, 2026-10-11), LK07-T03 (saignement et soins, section du même nom, 2026-10-12), LK07-T05 (butin réel du cadavre, section du même nom, 2026-10-12) ; sert LK07-T02 (santé de référence serveur), LK07-T03 (saignement, soins), LK07-T04 (mort unique), LK07-T05 (butin) et LK06-T04 (PNJ contre zombies)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté `J/` = `java/zombie/` ; Lua vanilla `media/lua`) — Date : 2026-10-10 — Statut : brouillon
- Lecture statique seulement : **aucun essai en jeu** pour cette fiche. Chaque fait porte sa preuve et son statut ; ce qui reste à observer est marqué « à mesurer ».

## Problème

Un corps de PNJ est un zombie (joueur réanimé, voir [corps-et-animations.md](corps-et-animations.md) et [corps-registre.md](corps-registre.md)). Quand un joueur le frappe, lui tire dessus, l'écrase en voiture, le brûle ou le fait exploser, le moteur vanilla applique des dégâts de **zombie**, sur plusieurs machines à la fois, et décide seul de sa mort. LK07 veut au contraire une santé de PNJ **tenue par le serveur**, identique pour tous les clients, une mort unique et un cadavre qui ne se relève pas. Cette fiche établit où et comment le moteur applique ces dégâts, où vit la santé, ce que le réseau transporte, et ce qu'un moteur de PNJ doit intercepter.

## Contraintes du moteur

### 1. Chaîne d'un coup d'arme sur un zombie

| Fait | Preuve | Statut |
|---|---|---|
| Le **client attaquant** calcule les dégâts : `attackCollisionCheck` tire `Rand(min, max)` de l'arme, applique les modificateurs de l'attaquant (force, douleur aux bras, panique, stress, endurance, fatigue, partage entre plusieurs cibles), puis appelle `cible:Hit(arme, attaquant, damageSplit, ignore, rangeDel)` sur **sa copie** locale. | `J/CombatManager.java:591`, `810-921`, `966-970` | confirmé statiquement |
| `Hit` à 5 arguments = `Hit(…, bRemote = false)` : `processHitDamage` multiplie encore (distance `modDelta`, ×1,5 de face, `NON_PLAYER_RECEIVED_DAMAGE_MULTIPLIER` = 1,5 pour une cible non joueur, niveau d'arme `0,3 + 0,1 × niveau`, critique ×max(2, `CriticalDamageMultiplier`), visée au sol ×max(5, …), arme à deux mains tenue d'une main). La valeur rendue est envoyée telle quelle. | `J/characters/IsoGameCharacter.java:5699-5743`, `5773-5829` ; `J/combat/CombatConfigKey.java:11-14` | confirmé statiquement |
| `hitConsequences` applique ensuite, **pour la mêlée seulement**, `GLOBAL_MELEE_DAMAGE_REDUCTION_MULTIPLIER` = 0,15, puis `health -= dégâts` (plancher 0). Une arme à feu n'a pas cette réduction. | `J/characters/IsoGameCharacter.java:5831-5835`, `14499-14504` ; `J/CombatManager.java:1097-1102`, `3237-3242` ; `J/combat/CombatConfigKey.java:61` | confirmé statiquement |
| Coup de pied d'écrasement : dégâts propres (`StompPower` des chaussures) ; poussée (`isDoShove` sans visée au sol) = coup **sans dégâts** (`bIgnoreDamage`). Couteau à la mâchoire (`KnifeDeath`) : `rangeDel × 1000`, donc mort assurée. | `J/CombatManager.java:866-872`, `924-929` ; `J/characters/IsoGameCharacter.java:5716-5719` | confirmé statiquement |
| À partir du 4ᵉ coup de mêlée sur le même zombie, les dégâts sont multipliés par `(hitTime − 2) × 1,5` (uniquement si `bRemote` est faux, donc chez l'attaquant ou en solo). | `J/characters/IsoGameCharacter.java:5709-5715` | confirmé statiquement |
| Ordre dans `IsoZombie.Hit` : partie du corps tirée **au hasard** (torse, 1/7 tête, 1/3 tête sur critique), `OnHitZombie(zombie, attaquant, partie, arme)`, puis `IsoGameCharacter.Hit` : `OnWeaponHitCharacter(attaquant, cible, arme, damageSplit)`, `OnPlayerGetDamage(cible, "WEAPONHIT", damageSplit)` (aussi pour un zombie), crochet `WeaponHitCharacter`, `avoidDamage`, `noDamage`, puis dégâts. | `J/characters/IsoZombie.java:1098-1125` ; `J/characters/IsoGameCharacter.java:5720-5732` | confirmé statiquement |
| `zombie:Hit(...)` déclenche aussi, sur chaque machine qui l'exécute, l'abonné vanilla `DamageModelDefinitions.OnHitZombie` : texture de blessure et **trous dans les vêtements** tirés au hasard, donc différents d'une machine à l'autre. | `media/lua/shared/Definitions/DamageModelDefinitions.lua:24-69` | confirmé statiquement ; écart visuel entre clients à mesurer |
| Après les dégâts, si le zombie vit : réaction (`processHit` choisit `ZombieHitReaction`, `wasHit`), cible = attaquant (`setTarget(wielder)`), renversé si coup critique, déjà au sol ou `alwaysKnockedDown` (chez l'attaquant), **1 chance sur 30 de devenir rampant** (1/15 ou 1/7 sur un écrasement), recul (`StaggerBackState`) si le zombie attaquait à moins de 0,9. La santé n'influence pas la réaction, seule la mort la change. | `J/characters/IsoZombie.java:1117-1120`, `3444-3471`, `3526-3551` ; `J/CombatManager.java:2408-2448` | confirmé statiquement ; animations sur un corps de PNJ à mesurer |
| Mort par une arme : `hitConsequences` voit `isDead()` (`health ≤ 0`) ; **serveur** → `die()` ; **solo** → `Kill(arme, attaquant)` ; **client MP** → rien (il attend le paquet de mort). | `J/characters/IsoGameCharacter.java:4645-4647`, `5836-5846` | confirmé statiquement |
| `Kill` pose la santé à 0, puis, une seule fois (`isOnKillDone`), `onKilled` : `DoZombieInventory()` hors client (inventaire **vidé puis rempli** au hasard ; **sans effet pour un joueur réanimé**, donc pour un corps de PNJ : `IsoZombie.java:3129-3133`, relevé en LK04-T12), `OnZombieDead(zombie)`, `DoDeath` (`OnCharacterDeath`). `die()` ajoute, sur le serveur, la chute des objets tenus puis `becomeCorpse()` et l'envoi du paquet de mort. | `J/characters/IsoGameCharacter.java:13463-13500`, `1813-1816`, `4603-4605` ; `J/characters/IsoZombie.java:4599-4620` | confirmé statiquement |

### 2. Ce qui empêche ou réduit les dégâts

| Moyen | Effet | Portée réseau | Preuve | Statut |
|---|---|---|---|---|
| `setInvulnerable(true)` | Drapeau de triche `GOD_MODE`. `CombatManager.applyDamage` sort sans rien retirer : coups, explosions, chute, choc de véhicule (`isGodMod`), feu (`ReduceHealthWhenBurning` éteint le zombie). `setHealth(0)` est ignoré, `setBecomeCrawler` aussi. Le zombie reste une cible valide (exception `isZombie()` dans le choix des cibles) : coup, événements et réaction ont lieu. | Local, à poser **sur chaque machine** (absent des 14 drapeaux transmis) ; remis à faux par `resetForReuse`. Sauvegarde : `getCheats().save` est écrit par `IsoGameCharacter.save`, appelé pour un joueur réanimé (`ReanimatedPlayers.java:132`) : à mesurer. | `J/characters/IsoGameCharacter.java:2903-2908`, `6036-6039`, `11069-11075`, `11714`, `5102` ; `J/CombatManager.java:1097-1110`, `1578` ; `J/characters/IsoZombie.java:3680`, `3701-3705` | confirmé statiquement |
| `setGodMod(true)` et l'argument `isInvulnerable` d'`addZombiesInOutfit` | **Sans effet sur un zombie** hors solo en mode debug : `setGodMod` exige la capacité `ToggleGodModHimself`, que `Role.hasCapability` refuse à tout non-joueur, et remet alors le drapeau à faux. | — | `J/characters/IsoGameCharacter.java:11110-11118` ; `J/characters/Role.java:176-193` ; `J/Lua/LuaManager.java:8427` | confirmé statiquement |
| `setAvoidDamage(true)` | **Un seul coup** annulé entièrement (retour 0 avant attaquant, dégâts et réaction), puis remis à faux. Chemin `Hit` seulement. | Local, par machine. | `J/characters/IsoGameCharacter.java:5725-5728`, `10959-10961` | confirmé statiquement |
| `setNoDamage(true)` | **Un seul coup** changé en coup sans dégâts (réaction gardée), puis remis à faux. Chemin `Hit` seulement. | Local, par machine. | `J/characters/IsoGameCharacter.java:5729-5732` ; `J/iso/IsoMovingObject.java:1958-1964` | confirmé statiquement |
| `setOnlyJawStab(true)` | `hitConsequences` sort avant les dégâts, la réaction et `wasHit` sauf mise à mort au couteau (`closeKilled`). Les événements de `Hit` partent quand même. | Local (absent des drapeaux). | `J/characters/IsoZombie.java:3444-3448`, `4490-4496` | confirmé statiquement |
| Crochet Lua `Hook.WeaponHitCharacter` | `TriggerHook` rend vrai **dès qu'un abonné existe**, quelle que soit sa valeur de retour : **tous** les coups d'arme sur **tous** les personnages (joueurs compris) rendent 0. Inutilisable pour cibler un PNJ. | Par machine. | `J/Lua/LuaHookManager.java:129` ; `J/Lua/Event.java:29-64` ; `J/characters/IsoGameCharacter.java:5722-5724` | confirmé statiquement |
| `setImmortalTutorialZombie(true)` | Seulement en tutoriel ou en mode debug. | — | `J/characters/IsoZombie.java:1099-1101` | confirmé statiquement |

### 3. Qui applique les dégâts d'un coup en MP

| Fait | Preuve | Statut |
|---|---|---|
| Le client attaquant envoie `PlayerHitZombie` : joueur (connexion, drapeau critique), arme, puis par cible la valeur **déjà calculée** `damage` (plafonnée à 100), force et direction du coup, partie touchée (tête, jambes, autre), couteau planté, `ignoreDamage`, réactions d'animation et drapeaux du zombie (recul, faux mort, rampant à venir, couteau…), position de chute. | `J/CombatManager.java:1032-1037` ; `J/network/GameClient.java:1166-1189` ; `J/network/packets/hit/PlayerHit.java:37-61` ; `J/network/fields/hit/Hit.java:29-34`, `WeaponHit.java:40-64`, `Zombie.java:36-49`, `Character.java:56-73`, `Player.java:64-70, 135` | confirmé statiquement |
| Le serveur ne recalcule rien : seul l'anti-triche `HitDamage` refuse une valeur > 100 (plus `HitLongDistance`, `HitWeapon`). L'attaquant est le joueur de la **connexion**. | `J/network/anticheats/AntiCheatHitDamage.java` ; `J/network/packets/hit/PlayerHitZombiePacket.java:32` ; `J/network/fields/character/PlayerID.java:43` | confirmé statiquement |
| Le serveur relaie d'abord le paquet à toutes les connexions **pertinentes** sauf l'envoyeur, puis le traite lui-même (`processClient`). Chaque destinataire (serveur compris) appelle `zombie:Hit(arme, attaquant, damage, ignoreDamage, range, bRemote = true)` : dégâts = valeur reçue, sans `processHitDamage`, puis `hitConsequences`. Les drapeaux du paquet sont réappliqués après (`postProcess`) : le tirage « rampant » de l'attaquant l'emporte. | `J/network/packets/hit/HitCharacter.java:37-50` ; `J/network/GameServer.java:2923-2932` ; `J/network/packets/hit/PlayerHitZombiePacket.java:86-103` ; `J/network/packets/hit/PlayerHitCharacter.java:68-74` ; `J/network/fields/hit/WeaponHit.java:66-80` | confirmé statiquement |
| Dans `hitConsequences`, un **client** ignore les dégâts d'un zombie qu'il ne simule pas (`GameClient.client && isRemoteZombie()`). Appliquent donc les dégâts : **le serveur** (toujours) et **le client propriétaire** (le sien ou celui qu'il reçoit en relais). L'attaquant non propriétaire ne change pas sa copie. | `J/characters/IsoZombie.java:3449` | confirmé statiquement |
| Les événements `OnHitZombie`, `OnWeaponHitCharacter` et `OnPlayerGetDamage` partent **sur chaque machine** qui exécute `Hit` : client attaquant, serveur, chaque client pertinent. La partie du corps d'`OnHitZombie` est retirée au hasard sur chacune. Sur le serveur, `damageSplit` d'`OnWeaponHitCharacter` est la valeur envoyée par l'attaquant, **avant** la réduction de mêlée × 0,15 ; le drapeau `ignoreDamage` n'est pas visible. | mêmes références ; `J/characters/IsoZombie.java:1102-1109` | confirmé statiquement ; valeurs réelles à mesurer |
| La santé que le **propriétaire** envoie dans chaque paquet zombie (`ZombiePacket.health`) **remplace** celle du serveur ; si elle est nulle ou négative, le serveur appelle `die()` (mort avec `getAttackedBy()`, éventuellement ancien). | `J/popman/NetworkZombiePacker.java:75-101`, `215-231` ; `J/characters/NetworkZombieAI.java:180` | confirmé statiquement |
| Un client ne reçoit la santé d'un zombie **qu'à la création de sa copie** ; ensuite le champ des paquets est ignoré. Un client non propriétaire garde donc la santé de création. | `J/popman/NetworkZombieSimulator.java:164-200`, `263-270` ; `J/characters/NetworkZombieAI.java` (aucune lecture de `health`) | confirmé statiquement |
| **Changement de propriétaire** : `becomeLocal` ne remet pas la santé à jour. Le nouveau propriétaire repart de sa copie périmée (santé de création) et l'envoie au serveur, qui l'applique : **la santé remonte sans soin**. | `J/popman/NetworkZombieSimulator.java:100-130` ; `NetworkZombiePacker.java:231` | confirmé statiquement ; à mesurer |
| La santé voyage en `short` × 1000 : précision 0,001 et **maximum 32,767**. Au-delà, la conversion Java (`(short)(float)`) boucle : 33 donne −32,5, le serveur voit un zombie mort et appelle `die()`. Une santé « géante » posée pour rendre un corps increvable le **tue** en MP. | `J/characters/NetworkZombieAI.java:180` ; `J/network/packets/character/ZombiePacket.java:58, 112` ; `J/popman/NetworkZombiePacker.java:97-99, 231` | confirmé statiquement |
| Le paquet de mort ne va que du serveur vers les clients (`DeadZombiePacket`) ; chaque client appelle `dieNetwork` → `Kill` → `onKilled` : `OnZombieDead` part **aussi sur chaque client** qui reçoit la mort (sans `DoZombieInventory`). | `J/network/GameServer.java:2934-2936` ; `J/network/packets/character/DeadCharacterPacket.java:108-147` ; `J/characters/IsoGameCharacter.java:13503-13506` | confirmé statiquement |
| Un `zombie:Hit(...)` ou `setHealth` lancé par Lua **sur le serveur** ne change que la copie du serveur : aucun paquet n'en part, et le prochain paquet du propriétaire écrase la santé. Il tue seulement si la mort tombe avant ce paquet. | `J/characters/IsoGameCharacter.java:5704-5743` ; `J/popman/NetworkZombiePacker.java:231` | confirmé statiquement |
| Sans propriétaire (aucun joueur pertinent), le serveur simule le zombie : il est seul à appliquer les dégâts et la santé n'est pas écrasée. | base `multiplayer.md`, « Zombies en MP : un seul simulateur » ; `J/popman/NetworkZombieManager.java:60-131` | confirmé statiquement |

### 4. Autres sources de dégâts

| Source | Chemin et autorité | Preuve | Statut |
|---|---|---|---|
| **Véhicule** | La collision est testée sur la copie **locale** (propriétaire) et sur les copies distantes (`updateNetworkHitByVehicle`) ; chaque machine qui la détecte applique des dégâts à **sa** copie (`onHitByVehicleApplyDamage`, `Kill(attaquant)` si elle en meurt, même sur un client). Seul le client **du conducteur** envoie `VehicleHitZombie` (dégâts, vitesse, renversé, recul) ; le serveur pose l'attaquant (conducteur de la connexion) et applique `applyDamageFromVehicleHit`, **sans** `OnHitZombie` ni `die()` : la mort vient ensuite de la santé du propriétaire. | `J/characters/IsoZombie.java:2756-2765`, `3281-3285` ; `J/vehicles/BaseVehicle.java:5155-5191`, `9547-9578` ; `J/characters/IsoGameCharacter.java:11585-11640`, `11662-11754`, `13607-13625` ; `J/network/GameClient.java:1202-1225` ; `J/network/fields/hit/VehicleHitField.java:60-80` | confirmé statiquement ; nombre d'applications réelles à mesurer |
| **Feu** | Une case en feu allume le zombie (`FireCheck`) chez son simulateur seulement ; la brûlure retire `fireKillRate / 20 × multiplicateur` (0,0038 / 20) par mise à jour, pose `attackedBy = nil`, et à la mort déclenche `OnZombieDead` **directement** (y compris sur le client propriétaire), puis une seconde fois par `die()` sur le serveur. L'état « en feu » fait partie des drapeaux transmis. | `J/characters/IsoGameCharacter.java:546`, `5542-5583`, `6033-6073` ; `J/characters/NetworkZombieVariables.java:10-64` | confirmé statiquement |
| **Explosion** (bombe, piège) | `IsoTrap.explosion` appelle `Hit(arme du piège, lanceur ou faux zombie, Rand(p/20, p/10) + extra, false, 1)` sur les zombies de la case : sur un client, seulement ceux qu'il simule ; sur le serveur, tous. Deux tirages indépendants (serveur, propriétaire) ; la santé du propriétaire écrase ensuite celle du serveur. Passe par `OnHitZombie`, arme `isExplosive()`. | `J/iso/objects/IsoTrap.java:760-792` ; `J/characters/IsoGameCharacter.java:5776-5777` | confirmé statiquement ; machines qui déclenchent l'explosion à mesurer |
| **Chute** | `handleLandingImpact` du zombie : dégâts × option sandbox `ZombiesFallDamage`, `attackedBy = nil`, et sur une chute lourde le zombie peut devenir **rampant** ou **faux mort**. Appliqué là où le zombie atterrit. | `J/characters/IsoGameCharacter.java:2050-2062` ; `J/characters/IsoZombie.java:2564-2601` | confirmé statiquement ; machine concernée à mesurer |
| **Vrais zombies** | Un zombie ne repère que des joueurs (`spotted` n'est appelé que par `IsoPlayer.TestZombieSpotPlayer`, et par le serveur pour un joueur cible) : aucun zombie vanilla ne prend un corps de PNJ pour cible ni ne le mord. Exception possible : `hitConsequences` pose `setTarget(attaquant)` ; un zombie frappé par code avec un corps de PNJ comme attaquant le prendrait pour cible, et `AttackState` le traiterait comme un `IsoGameCharacter` (comportement à mesurer). La morsure d'un PNJ par un zombie est donc entièrement à écrire (LK06-T04). | `J/characters/IsoPlayer.java:1013-1027` ; `J/characters/IsoZombie.java:1662-1700`, `3459-3461` ; `J/ai/states/AttackState.java:137-141` | confirmé statiquement (repérage) ; cible forcée à mesurer |

### 5. Santé d'un zombie : échelle, régénération, réanimation, événements

| Fait | Preuve | Statut |
|---|---|---|
| Échelle : `health` flottant, mort à ≤ 0. Normal 1,8-2,1 ; robuste 3,5-3,8 ; fragile 0,5-0,8 ; aléatoire 0,5-3,8 (option `Toughness`). Une arme de mêlée retire typiquement `damage × 0,15` par coup après tous les multiplicateurs ; une arme à feu, sa valeur entière. | `J/characters/IsoZombie.java:381`, `3648-3659` ; `J/combat/CombatConfigKey.java:61` | confirmé statiquement |
| Le cadavre réanimé (chemin de création de nos corps) **réécrit la santé** selon `Toughness` dans `reanimate()` (sauf réglage aléatoire, qui garde la valeur du constructeur) : une santé posée avant la réanimation est perdue. | `J/iso/objects/IsoDeadBody.java:1876-1889` | confirmé statiquement |
| Aucune régénération de santé de zombie : aucune écriture croissante de `health` hors `setHealth` (création, réanimation, paquet réseau). Seule « remontée » : le changement de propriétaire (section 3). | recherche de `setHealth(` et `health +=` dans `J/` | confirmé statiquement (par recherche exhaustive) |
| Réanimation d'un cadavre de zombie : seuls les cadavres de joueurs (`IsoPlayer`, `reanimateLater`) et les **faux morts** se relèvent. Le cadavre **hérite** de `zombie:isFakeDead()` à sa création : un corps mort pendant qu'il était faux mort (par exemple après une chute lourde) donne un cadavre qui se relève en zombie près d'un joueur. | `J/iso/objects/IsoDeadBody.java:298-301`, `1636-1653`, `1754-1760` ; `J/characters/IsoPlayer.java:7758` | confirmé statiquement |
| Événements Lua utiles : `OnHitZombie(zombie, attaquant, partie, arme)` et `OnWeaponHitCharacter(attaquant, cible, arme, dégâts)` avant les dégâts, sur chaque machine qui exécute `Hit` ; `OnPlayerGetDamage(cible, "WEAPONHIT", dégâts)` idem ; `OnZombieUpdate(zombie)` à chaque mise à jour, sur le serveur et chez tous les clients ; `OnZombieDead(zombie)` sur le serveur (une fois, deux pour le feu) et chez chaque client qui reçoit la mort ; `OnCharacterDeath` dans `DoDeath` ; `OnWeaponHitXp` sur le serveur. Aucun événement pour un choc de véhicule, une brûlure ni une chute. | `J/Lua/LuaEventManager.java:650, 676, 728, 855, 872` ; `J/characters/IsoZombie.java:1109, 2738, 4610` ; `J/characters/IsoGameCharacter.java:4604, 5577, 5720-5721, 6068` ; `J/network/fields/hit/WeaponHit.java:110-114` | confirmé statiquement |

## Choix

Aucun choix n'est arrêté par cette fiche (tâche d'investigation). Voici la conduite que les faits imposent, à trancher dans LK07-T02 :

1. **Rendre la santé vanilla inerte sur toutes les machines.** `setInvulnerable(true)` sur chaque copie d'un corps étiqueté (serveur à l'incarnation, clients à la réception, comme `noTeeth` et la voix muette), et santé vanilla fixe **≤ 32,767** (par exemple la valeur rendue par la réanimation). Effets : plus de mort vanilla par coup, choc, feu ou chute ; plus de corps rampant ; plus de santé qui remonte au changement de propriétaire, puisque toutes les copies gardent la même valeur. Le coup reste visible (événements, réaction, son). `setAvoidDamage` et `setNoDamage` ne valent qu'un coup et que pour le chemin `Hit` ; ils ne suffisent pas.
2. **Santé de référence dans le registre serveur** (`LK_Health.lua`, serveur seulement) : points de vie du PNJ, blessures, saignement, état `vivant`/`mourant`/`mort`. Jamais lue sur le zombie.
3. **Coups d'arme** : sur le serveur, `OnWeaponHitCharacter` (avec `OnHitZombie` pour l'attaquant, déjà utilisé par `LK_Bodies.onHitZombie`) donne arme, attaquant de la connexion et dégâts proposés par le client. Le serveur **plafonne** cette valeur à ce que l'arme peut faire (maximum de l'arme × critique × multiplicateurs connus, réduction de mêlée × 0,15), vérifie la distance, puis retire les points du registre. Ne jamais tirer la partie du corps de l'événement sur un client : elle est aléatoire par machine.
4. **Sources sans événement** (véhicule, feu, chute) : sondage serveur borné aux corps courants (`OnZombieUpdate` ou tranche du registre) de `getAttackedBy()`, `isOnFire()`, `isVehicleCollision()`… puis dégâts calculés par le moteur de PNJ. Méthode et valeurs à mesurer.
5. **Mort décidée par le serveur, une seule fois** : registre à `mort` d'abord, puis `setFakeDead(false)`, `setInvulnerable(false)` et mort vanilla côté serveur (`die()`, qui crée le cadavre et l'envoie). Tous les abonnés `OnZombieDead` de nos corps ne décident rien hors serveur, et ignorent un corps déjà `mort` dans le registre.
6. **Retransmission** : la santé de référence ne passe pas par le paquet zombie. Le serveur l'envoie lui-même (`sendServerCommand`) au propriétaire si son comportement en dépend (fuite, LK06-T05) et aux clients proches si un affichage l'exige ; la santé vanilla du zombie reste constante.

## Alternatives écartées

- **Laisser la santé vanilla du zombie faire foi** : le propriétaire l'écrase sur le serveur, elle remonte au changement de propriétaire, chaque source de dégâts est appliquée par plusieurs machines, et la mort vient d'un paquet client. Contraire à l'autorité serveur (LK07-T02, critère « aucune remontée sans soin »).
- **Santé géante (par exemple 1000) pour rendre le corps increvable** : bouclage du `short` au-delà de 32,767, donc mort immédiate en MP.
- **`setGodMod` ou l'argument `isInvulnerable` d'`addZombiesInOutfit`** : ignorés pour un zombie hors solo debug.
- **`Hook.WeaponHitCharacter`** : annule tous les coups de tous les personnages dès qu'un abonné existe.
- **`setAvoidDamage`/`setNoDamage` posés dans `OnHitZombie`** : possibles sur chaque machine, mais limités au chemin `Hit` (rien pour véhicule, feu, chute) et à exécuter partout au bon moment ; gardés comme complément si l'on veut annuler la réaction d'animation.
- **Corriger la santé du serveur par `setHealth`** : écrasée au paquet suivant du propriétaire.

## Idées reprises

- I7.2 (endurance, halètement) : **non reprise** par LK07-T02, non triviale (aucune endurance de zombie exposée ni animation de halètement relayée ; à traiter avec le combat des PNJ, LK06, ou le saignement, LK07-T03).

## Tests

- Banc lupa (`tests/harness.py`) : sans objet pour cette fiche ; LK07-T02 devra simuler `OnWeaponHitCharacter` serveur, le plafonnement, le changement de propriétaire (santé périmée envoyée) et une santé > 32,767.
- VM Kahlua (`tests/test_kahlua.py`) : sans objet.
- En jeu : aucun essai pour cette fiche.

## Points ouverts

- ⚠ À mesurer en solo : réaction d'animation d'un corps invulnérable frappé (recul, renversé, au sol) ; trous et blessures ajoutés aux vêtements ; `setInvulnerable` conservé après sauvegarde et rechargement d'un joueur réanimé.
- ⚠ À mesurer en MP (séance finale) : santé qui remonte au changement de propriétaire sans protection ; valeur de `damageSplit` reçue par `OnWeaponHitCharacter` sur le serveur (mêlée, arme à feu, poussée) ; nombre de machines qui appliquent un choc de véhicule et une explosion ; `OnZombieDead` et `OnHitZombie` reçus par chaque client ; bouclage d'une santé > 32,767.
- ⚠ À mesurer : un zombie frappé par code avec un corps de PNJ comme attaquant le prend-il pour cible et que fait `AttackState` contre lui (LK06-T04).
- ⚠ LK07-T05 : correction du 2026-10-11 (LK04-T12) : `DoZombieInventory` ne fait **rien** pour un joueur réanimé (`IsoZombie.java:3129-3133`) ; l'inventaire du corps de PNJ (clé du foyer comprise) passe tel quel au cadavre (`IsoDeadBody.java:327-332`), un objet posé de son vivant suffit (fiche `deplacement.md`, « Clés »). Note d'origine : `onKilled` refait l'inventaire du zombie au hasard (`DoZombieInventory`) **avant** `OnZombieDead` (vrai pour un zombie ordinaire) ; le butin réel se pose dans `OnZombieDead` côté serveur (base `quest-building-blocks.md`, « Objet dans le cadavre »). État des vêtements (trous tirés par machine) du cadavre vu par chaque client : à mesurer.

## Santé de référence (LK07-T02)

Tâche LK07-T02 (2026-10-11). Code : `media/lua/server/LivingKnox/LK_Health.lua` (autorité ; un client MP s'arrête à la garde), `media/lua/client/LivingKnox/LK_HealthClient.lua` (client MP), appels depuis `LK_Bodies.lua` (`guardNow`, `keptHealth`, `removeBody`, `onZombieDead`) et `LK_Materialize.lua` (`embodyMember`). Réglages `Config.HEALTH` (définis dans `LK_Health.lua`). Lecture statique et banc seulement : **aucun essai en jeu**.

### Voie retenue : choix 1 et 2 de LK07-T01

| Élément | Règle | Preuve |
|---|---|---|
| Santé vanilla inerte | `setInvulnerable(true)` sur la copie de l'autorité (à la liaison, `Bodies.guardNow`, puis toutes les `APPLY_EVERY = 3` images) et sur chaque copie client reconnue par la garde (`ZombieGuard.cache`, même cadence). Santé vanilla jamais relevée ni « géante » (≤ 32,767). | sections 2 et 3 ci-dessus ; `J/characters/IsoGameCharacter.java:2903-2908, 11069-11075` |
| Référence | `npc.hp` du registre des corps (même échelle que le moteur ; `npc.hpMax` = santé de naissance), sauvegardé avec le registre (`Store.markDirty`), donc conservé au redémarrage et au retrait (`Bodies.keptHealth` la rend en priorité). Initialisée à la liaison : valeur connue gardée (au plus `hpMax`), sinon santé du corps. Matérialisation d'un membre : `Health.setBirth` (santé tirée de la blessure abstraite par la simulation de l'autorité). | `LK_Health.lua` (`bodyBound`, `setBirth`, `reference`) |
| Blessures | `npc.wounds` = `{ { p = partie, d = dégâts } }`, les `WOUNDS_MAX = 8` plus récentes ; partie = celle tirée par l'autorité dans `OnHitZombie` (seule source, donc la même pour tous). Base de LK07-T03 (saignement). | `J/characters/IsoZombie.java:1102-1109` |
| Hausse | **Seulement** `Health.noteHeal(id, montant)` (soin connu de l'autorité, LK07-T03), plafonnée à `hpMax`. Aucune autre écriture croissante ; changement de propriétaire sans effet (la référence ne vient pas du paquet zombie). | banc : propriétaire changé 4 fois, référence inchangée |

### Coups des joueurs : contrôlés puis appliqués

Abonné `OnWeaponHitCharacter` sur l'autorité (cible = corps courant relié). L'événement part **avant** les dégâts vanilla. Les drapeaux de l'attaquant (visée au sol, poussée, critique) sont posés par le paquet avant `Hit` (`J/network/packets/hit/PlayerHit.java:88-90`, `J/network/fields/hit/Player.java:113-125`).

| Étape | Serveur MP (attaquant joueur) | Solo |
|---|---|---|
| Valeur | dégâts envoyés par le client (après `processHitDamage`, avant × 0,15) | valeur de l'événement × `NON_PLAYER_RECEIVED_DAMAGE_MULTIPLIER` × (0,3 + 0,1 × niveau d'arme) × critique × coup au sol (estimation, coup de face supposé) |
| Refus (rien n'est retiré ; une ligne WARN par attaquant et raison et par minute) | attaquant mort ; mêlée depuis un véhicule ; hors de portée (`getMaxRange(attaquant)` + 2 cases en mêlée, + 5 à distance) ; autre niveau (1 en mêlée, 2 à distance) ; cadence (10 coups/s, 5 d'avance, par attaquant et par PNJ) ; explosif encore dans l'inventaire de l'attaquant (une bombe lancée l'a quitté) | aucun (rien à soupçonner) |
| Valeur au-delà du maximum de l'arme (les deux) | **laissée passer** (décision du 2026-10-11, LK07-T06) : aucun plafond tiré de l'arme, la valeur est crue telle quelle. Un coup de grâce au couteau (× 1000 chez l'attaquant, `J/CombatManager.java:924-929`) tue d'un coup. Bornes : valeur non numérique, `NaN`, infinie (ou ≥ 10⁹) ou négative refusée (`bad damage`) ; montant retiré borné par la santé restante (blessure notée à cette valeur). Jusqu'au 2026-10-11 (LK07-T02), la valeur était ramenée à un plafond calculé depuis l'arme, ce qui empêchait en jeu le coup de grâce de tuer. | idem |
| Poussée sans visée au sol | aucun dégât (comme le moteur, `J/characters/IsoGameCharacter.java:5716-5719`) | idem |
| Application | mêlée × `GLOBAL_MELEE_DAMAGE_REDUCTION_MULTIPLIER` (0,15) ; arme à feu et explosion telles quelles | idem |

Attaquant non joueur (piège sans lanceur, code du moteur de PNJ) : contrôle du format de la valeur seulement.

### Mort unique

À 0 : `Health.decided[id]`, référence 0, santé nulle envoyée aux destinataires, invulnérabilité et faux mort levés, puis chemin vanilla de l'autorité : serveur `setAttackedBy(attaquant)` + `die()`, solo `Kill(arme, attaquant)` (`J/characters/IsoGameCharacter.java:5836-5846`). `OnZombieDead` → `Bodies.onZombieDead` (registre `dead`, cause et tueur, `Materialize.onBodyDied`, une fois par corps courant) → `Health.onBodyDied`. Les coups suivants sur le corps mort sont ignorés. Mort du moteur non décidée (un `Kill` d'un autre mod ; santé négative forgée par un client propriétaire, `J/popman/NetworkZombiePacker.java:97-101`) : WARN `died without a decision of the authority`, invulnérabilité levée et santé posée à 0 pour que le moteur crée le cadavre (`Kill` sur un corps invulnérable déclenche `onKilled` mais laisse `isDead()` faux, `J/characters/IsoGameCharacter.java:13463-13474, 4645`) ; le registre ne la compte qu'une fois. `Bodies.removeBody` lève aussi l'invulnérabilité avant `setHealth(0)` (sinon ignoré : le corps serait mis de côté au lieu d'être retiré).

### Retransmission

Serveur MP : commande `npcHealth` `{ d = { [npcId] = { r, hp, mx, w } } }` (`w` = nombre de blessures) envoyée **aux seuls destinataires des consignes** (`Directives.targets` : joueurs à 100 cases et propriétaire), un message par client et par passage (`SEND_MS = 500`), uniquement à ceux qui n'ont pas la révision `r` courante (croissante ; le client garde la plus grande, livraison non ordonnée). Client entré en partie (`guardHello`) : tout lui est renvoyé. Lecture : `LivingKnox.HealthView.get(id)` → `{ hp, max, wounds }` (en solo, lue sur l'autorité). Aucune réaction visible ajoutée : le coup garde la réaction vanilla sur chaque machine. Le relais des gestes (`LK_Relay.lua`) n'est pas modifié.

### Sources couvertes

| Source | Effet avec LK07-T02 |
|---|---|
| Coup de mêlée, tir, écrasement d'un joueur | contrôlé et appliqué (ci-dessus) |
| Explosion (bombe, piège) | chemin `Hit`, arme explosive : appliquée sans plafond (machine qui déclenche l'explosion : à mesurer) |
| Véhicule | **non couvert** : choc ignoré par l'invulnérabilité (`isGodMod`), aucun dégât de référence ; aucun événement Lua (section 4). À traiter après mesure. |
| Feu | **neutralisé** : un corps invulnérable est éteint aussitôt ; aucun dégât |
| Chute | **neutralisée** (dégâts retirés par `applyDamage`) ; faux mort après une chute lourde possible (non bloqué par l'invulnérabilité) : levé à la mort |
| Rampant tiré par un coup | bloqué localement (`setBecomeCrawler`) ; drapeau rampant renvoyé par le paquet de l'attaquant : à mesurer |

### Alternatives écartées (LK07-T02)

- **Refuser un coup au-dessus du plafond de l'arme** : un coup de grâce légitime (× 1000) ne tuerait plus.
- **Ramener un coup au plafond de l'arme** (retenu par LK07-T02, retiré par LK07-T06 le 2026-10-11) : en jeu, le coup de grâce au couteau ne tuait plus ; l'anti-triche est peu prioritaire sur un serveur entre amis, la valeur du client est crue.
- **Exiger l'arme en main** : le serveur relit l'arme dans l'inventaire de l'attaquant par identifiant (`J/network/fields/hit/Weapon.java:30-49`) ; l'état des mains vu par le serveur n'est pas vérifié ici, et un refus à tort rendrait le PNJ increvable en MP, pour un gain faible.
- **Passer la santé par le relais des gestes** : fichier modifié en parallèle (LK11-T04) ; les destinataires des consignes suffisent pour une valeur qui change rarement.
- **Recopier la référence dans la santé vanilla** : écrasée par le paquet du propriétaire, et une copie recréée ferait refuser les rapports d'état (santé qui remonte).

### Tests

- Banc lupa `tests/test_lk_health.py` (16 tests) : copies serveur et clients invulnérables, référence initialisée ; coup d'un joueur reçu par le serveur (3 → 0,45 retiré), santé vanilla inchangée, même valeur chez A et B, aucun envoi sans changement, rapports du propriétaire jamais refusés ; refus (hors de portée, autre niveau, véhicule, attaquant mort, bombe dans l'inventaire, cadence) ; coup de grâce au couteau au-delà du maximum de l'arme qui tue d'un coup (blessure bornée par la santé restante), même coup hors de portée refusé, valeurs `NaN`, infinie, négative ou non numérique refusées (LK07-T06) ; poussée sans dégâts ; aucune remontée sur 4 changements de propriétaire, `noteHeal` seule hausse et plafonnée ; mort unique décidée par le serveur (un seul `OnZombieDead`, coups suivants ignorés, santé 0 chez A et B, tueur retenu) ; mort du moteur signalée et menée à terme une fois ; retrait puis réincarnation sans remontée ; client reconnecté servi à nouveau ; solo (estimation, aucune portée contrôlée, mort unique) ; suites `lk.health` et `rs.killer` jouées sur les doublures avec la santé de référence ; sources compatibles Kahlua, aucun envoi à tous.
- Suite en jeu `lk.health` (`dev/.../suites/RST_LKHealth.lua`, tags `world`, `server`) : coup de batte (dégâts 1) qui baisse la référence sans toucher la santé vanilla, pas de remontée 3 s plus tard ; coup mortel (dégâts 100, au-delà du maximum de la batte) qui tue d'un seul coup (LK07-T06), une seule mort décidée, aucune mort du moteur, écouteur appelé une fois. `rs.killer` adaptée : référence abaissée avant le coup mortel ; test du feu : corps éteint, PNJ vivant.

### Protocole en jeu

1. Solo (`rstest*`, Living Knox activé) : `RST.run({ suite = "lk.health", tags = "world" })` puis `RST.run({ suite = "rs.killer", tags = "world" })` → `OK` ; relever les lignes `[LKH] measure` et `[RSK] measure`.
2. Solo, à la main : `LKB.spawn()`, frapper le PNJ à la batte 2 ou 3 fois : `LivingKnox.Health.get("lk-<n>").hp` baisse, le PNJ ne devient jamais rampant ; le tuer : une seule ligne `death decided by the authority` puis une seule `died`.
3. MP (séance finale : serveur dédié + clients A et B près du PNJ) : A frappe le PNJ ; sur A et B, `LivingKnox.HealthView.get("lk-<n>").hp` égal à `LivingKnox.Health.get("lk-<n>").hp` du serveur ; B s'approche pour devenir propriétaire : valeur inchangée ; A le tue : une seule mort au journal serveur, cadavre vu par A et B. Coup impossible (A à un autre étage ou au loin) : `WARN hit on npc … refused`.
4. Mesures ouvertes : réaction d'un corps invulnérable frappé (recul, renversé), voiture (PNJ intact), bombe (appliquée une fois, sur le serveur), drapeau rampant renvoyé par l'attaquant.

### Limites

- Aucun essai en jeu ; doublures fidèles au Java relevé mais non prouvées.
- Jusqu'à 3 images entre l'adoption d'une copie par un client et son invulnérabilité : un coup encaissé là par une copie propriétaire ne change pas la référence (au pire la santé vanilla rapportée baisse).
- Valeur solo estimée (coup de face supposé, `modDelta` = 1) ; valeur serveur crue sans plafond (un client modifié peut tuer un PNJ d'un coup à portée, accepté : LK07-T06). L'anti-triche vanilla (`J/network/anticheats/AntiCheatHitDamage.java`) peut refuser en amont un paquet de coup au-dessus de 100 : coup de grâce en MP à mesurer.
- Véhicule non couvert ; feu et chute neutralisés (PNJ incombustible) : à revoir avec LK07-T03/T04.
- Une santé négative forgée par un client propriétaire tue encore le corps (le moteur appelle `die()`) : signalée, pas empêchée.

## Saignement et soins (LK07-T03)

Tâche LK07-T03 (2026-10-12). Code : `media/lua/server/LivingKnox/LK_Health.lua` (saignement : `Health.bleeding`, `bleedPass`, `stopBleeding`, blessure qui fait saigner dans `applyHit`) et `media/lua/server/LivingKnox/LK_Care.lua` (qui soigne, objet pris au stock, gestes, soin appliqué) ; point d'appel ajouté dans `LivingKnox.Decisions.apply` ; `LK_Defense` appelle `Care.afterAttack`. Réglages `Config.BLEEDING` (dans `LK_Health.lua`) et `Care.CFG`. Banc et suite sur doublures seulement : **aucun essai en jeu**.

### Partage entre modules (choix)

- **Saignement dans `LK_Health`** : il baisse la santé de référence, dont `LK_Health` est le seul écrivain ; la mort par perte de sang prend le même chemin unique (`Health.kill`, sans arme ni attaquant).
- **Soins dans un module distinct, `LK_Care.lua`** : choisir le soigneur, aller au stock, prendre un objet et mener les gestes relèvent des routines et du stock, pas de la santé ; `LK_Health` reste centré sur la référence, les coups et l'envoi. `LK_Care` ne touche la santé que par `Health.stopBleeding` et `Health.noteHeal` (seule hausse, inchangée depuis LK07-T02).

### Saignement

| Élément | Règle | Source |
|---|---|---|
| État | Champ facultatif `npc.bleed` du registre des corps (fraction de `hpMax` perdue par heure de jeu), sauvegardé ; absent = aucun saignement. Lecture : `Health.bleeding(id)`, `Health.get(id).bleed`. | `LK_Identity.lua` (en-tête) |
| Début | Toute blessure non mortelle (coup d'un joueur contrôlé, attaque d'un zombie : `Health.applyHit`) ajoute `PER_DAMAGE` (0,5) × dégâts / `hpMax`, borné à `MAX` (0,6). Morsure d'un zombie (20 % de `hpMax`) : 0,10/h ; griffure (5 %) : 0,025/h. | choix ; vanilla : `BodyPart.generateBleeding` (base `api-42-21.md`) |
| Perte | Chaque minute de jeu (`EveryOneMinute`, autorité), corps relié vivant : `bleed` × `hpMax` × minutes / 60 ; minutes manquées rattrapées d'après l'âge du monde (au plus 60). | vanilla : perte continue d'une partie non bandée (`BodyPart.java:161-166`) |
| Arrêt seul | Saignement non soigné divisé par deux toutes les `HALF_HOURS` (3) heures, arrêté sous `STOP` (0,005/h). Perte totale sans soin ≈ `bleed` × 4,3 × `hpMax` : une griffure coûte ≈ 11 % de plus, une morsure ≈ 43 %, deux morsures tuent. | vanilla : `bleedingTime` décroît seul, lentement sans pansement (`BodyPart.java:202-218`) |
| Mort | Référence à 0 : `Health.kill(id, corps, nil, nil)` (mort unique, `die()`), ligne `bled to death`. Cause enregistrée par `Bodies.deathCause` : celle du dernier coup d'un joueur s'il est récent, sinon « other ». | LK07-T02 |
| Arrêt par un soin | `Health.stopBleeding(id)` (appelé par `LK_Care`) ; aussi à la mort (`onBodyDied`). | |
| PNJ virtuel | Corps retiré : saignement suspendu (pas de corps relié), repris à la prochaine incarnation. | limite |

### Soins

| Étape | Règle |
|---|---|
| Blessés | Membres présents au foyer (`Routines.present`), incarnés, qui saignent, ou notés après une attaque repoussée (`Care.afterAttack`, appelé par `LK_Defense` avec les blessés sous `CARE_HEALTH` ; note gardée 6 h, oubliée si la santé est pleine). Ordre : saignement décroissant, santé croissante, numéro. |
| Soigneur | Le médecin d'abord : membre dont le rôle permet `heal` (rôle `medic` des types du mod) ou de poste `carer`, présent, incarné, libre, qui ne saigne pas, plus petit numéro ; sinon le blessé lui-même. Un médecin qui saigne se soigne d'abord. Tâches refaites au plus une fois par minute de jeu et par groupe. |
| Quand | Pendant un comportement calme au foyer (`home`, `rest`, `sleep`, `guard`, `patrol`, `chore`, `meal`) : `Decisions.apply` appelle `Care.apply` après la sortie du combat ; s'il tient le membre, la routine est quittée (repas pris appliqué, entretien libéré) et rien d'autre n'est fait. Menace, fuite, alerte, combat, défense, retraite, reddition : soin quitté. |
| Objet | Objet du foyer que le vanilla accepte pour panser (`isCanBandage`), propre d'abord (`getBandagePower` ≥ 1,5), pris par `Stock.takeItem` : retiré du conteneur (et des clients sur un serveur), ôté de la référence du stock dans la même écriture, donc ni perte ni vol à la relecture ; un seul objet par soin ; rien n'est créé. Les bandes de tissu (`RippedSheets`, catégorie `Household`) ne sont pas suivies par la référence : leur retrait ne change rien au suivi. |
| Gestes | Existants seulement : fouille (`rummage`, 1 minute de jeu) devant le conteneur, puis le médecin va à côté du blessé (place refaite si le blessé a bougé de plus de 2 cases), se tourne vers lui et s'agenouille (`kneel`, 5 minutes) ; seul, le blessé s'agenouille devant le conteneur. |
| Effet | Une seule fois, à la fin ou dès une interruption après la prise (comme un repas) : saignement arrêté, santé + 0,03 × `BandagePower` × `hpMax` (× 1,5 pour un médecin : pansement 4 → +18 %), entrée `care` au journal du groupe. |
| Rien au stock | Pénurie au journal (`no bandage to treat a wound left for …`, `Stock.reportShortage`, catégorie `medical`, au plus une fois par 6 h), soins du groupe mis de côté 60 minutes ; le saignement continue et peut tuer. Soigneur qui n'atteint pas le conteneur ou le blessé : aucune tâche pour lui pendant 30 minutes. |

La corvée visible « care » de LK05-T04 (s'agenouiller près d'un blessé, sans effet) reste inchangée.

### Alternatives écartées (LK07-T03)

- **Soin abstrait sans déplacement** (santé rendue sur place) : rien de visible, objet sorti du stock sans geste ; le modèle des repas (aller, fouiller, prendre, geste) est déjà éprouvé.
- **Comportement `heal` ajouté à la cascade** : changerait la liste fermée des comportements et l'ordre fixe des priorités (décision du 2026-10-08) ; le point d'appel dans `Decisions.apply` suffit et laisse la menace passer avant.
- **Objet choisi par `DisplayCategory = FirstAid`** : `Pills` ou `Disinfectant` y sont et ne pansent pas ; `isCanBandage` est le test du menu vanilla.
- **Saignement qui ne s'arrête jamais seul** : contraire au vanilla ; une griffure non soignée tuerait.
- **Infection et transformation après une morsure (I6.10)** : hors périmètre (reste).

### Tests

- Banc `tests/test_lk_care.py` (15 tests, pile complète des repas réels + `LK_Health` + `LK_Care`, solo) : gestes existants ; objets de soin (`isCanBandage`) ; blessure qui fait saigner (0,5 × fraction), saignement sauvegardé, perte de la première heure entre 17 et 20 % (décroissance), mort par perte de sang décidée une fois sans mort du moteur ; petite blessure qui s'arrête seule ; borne `MAX`, `stopBleeding` qui arrête toute perte ; médecin qui fouille, prend le pansement propre (pas les bandes sales), va au blessé, s'agenouille, saignement arrêté, santé + 0,03 × 4 × 1,5, un seul objet retiré, ôté de la référence, relecture sans perte ni vol, une entrée `care` ; blessé seul sans médecin (× 1) ; médecin blessé qui se soigne d'abord ; stock vide : pénurie une fois, saignement qui continue ; blessé noté après une attaque soigné sans saignement, une fois ; menace après la prise : soin appliqué une fois ; suite `lk.care` jouée sur les doublures ; sources ASCII hors commentaires ; client MP arrêté à la garde.
- Suite en jeu `lk.care` (`dev/.../suites/RST_LKCare.lua`, tags `world`, `server`).

### Protocole en jeu

1. Solo (`rstest*`, Living Knox activé, joueur dans une maison avec un meuble à conteneur) : `RST.run({ suite = "lk.care", tags = "world" })` → `OK` ; relever les lignes `[LKC] measure` ; regarder le médecin fouiller (`rummage`) puis s'agenouiller (`kneel`) près du blessé.
2. Solo, à la main : groupe au foyer avec un médecin et des pansements dans un meuble ; frapper un membre à la batte : `LivingKnox.Health.get("lk-<n>").bleed` > 0, la santé baisse chaque minute de jeu ; le médecin vient ; journal `care`, un pansement de moins dans le meuble.

### Limites

- Aucun essai en jeu ; doublures fidèles au Java relevé mais non prouvées.
- Toute blessure saigne (contondant compris), sans partie du corps ni type de plaie ; aucun effet visible du saignement (sang, halètement) ; la santé et le saignement ne sont pas affichés ni envoyés aux clients.
- Saignement suspendu hors incarnation ; la simulation hors écran (blessure abstraite) ne saigne pas.
- Soins seulement au foyer, pendant un comportement calme ; aucun soin en expédition ni pendant un combat ; un médecin endormi ou de guet est mobilisé.
- Objet pris au premier conteneur qui en contient (ordre des clés) : peut être loin dans un grand bâtiment.
- Cause de mort « other » pour une perte de sang sans coup récent : corrigé par LK07-T04 (cause `bleeding`).

## Mort unique et cadavre (LK07-T04)

Code : `LK_Health.lua` (`Health.kill`, `causeOf`, `bleedPass`), `LK_Bodies.lua` (`deathCause`, `examine`, `layDown`,
`isDragged`, `onZombieDead`), `LK_Identity.lua` (`DEATH_CAUSES`). Banc `tests/test_lk_death.py`, suite `lk.death`.

### Une seule mort, un seul chemin

- `Health.kill(id, z, attaquant, arme, cause)` est le **seul** point d'entrée d'une mort voulue : coup de joueur et
  attaque d'un zombie (`Health.applyHit` à 0), saignement (`Health.bleedPass`), appel direct (futur LK12, outils de
  dev : `Health.kill(id)`, corps relu dans `Bodies.bound`). Refus : mort déjà décidée, PNJ non incarné, **corps hors
  du monde** (corps mis de côté au déchargement de son chunk, encore dans `Bodies.bound` : `die()` y ferait un cadavre
  sans case et le corps resterait dans `reanimated.bin`, base `zombies-as-npc-bodies.md`). Le saignement d'un corps
  mis de côté est suspendu (il saignait jusqu'ici dans `bleedPass`, qui ne testait que `isDead`).
- Sans attaquant (saignement, appel direct), `setAttackedBy(nil)` avant `die()` : l'auteur d'un ancien coup n'est ni le
  tueur du moteur (`DoDeath`, cadavre `getKilledBy`) ni celui du registre.
- Toute autre mort du corps (moteur, autre mod, second `OnZombieDead` du feu, cadavre traîné puis lâché, cadavre
  remis à terre) passe par `Bodies.onZombieDead`, qui ne la compte que pour le **corps courant** : le PNJ passe à
  `dead` une seule fois, `Materialize.onBodyDied` marque le membre mort une seule fois (`alive = false`, succession),
  `Bodies.bound` est vidé ; consignes, rapports et gestes s'éteignent d'eux-mêmes (`Bodies.find` rend `dead`).

### Cause enrichie

`npc.death.cause` gagne `zombie` (attaque d'un zombie vanilla décidée par `LK_Zombies`, attaquant passé à
`Health.kill`) et `bleeding` (perte de sang), sans tueur, décidées avec la mort (`Health.causes`, lues par
`Bodies.deathCause` avant sa règle). L'attaquant zombie n'est jamais déduit de `getAttackedBy()` seul : un piège sans
lanceur attaque par un faux zombie (`J/iso/objects/IsoTrap.java:784`). Le registre relu accepte les deux causes
(`Identity.DEATH_CAUSES`) ; une version antérieure du mod refuserait un registre qui les contient (pas de retour
arrière du mod sur une partie où un PNJ est mort ainsi).

### Cadavre

- Chemin vanilla de l'autorité (serveur `die()`, solo `Kill` puis `die()` par l'état du zombie) : un seul cadavre
  (`becomeCorpse` une fois, `J/characters/IsoGameCharacter.java:13478-13541`), vêtements portés, objets accrochés et
  inventaire réel (`DoZombieInventory` sans effet sur un joueur réanimé), conteneur marqué exploré (aucun butin
  vanilla ajouté), faux mort levé avant la mort. ModData copiées : l'**étiquette du PNJ reste sur le cadavre** (elle
  désigne le PNJ pour LK07-T05) ; un PNJ mort n'a plus de corps courant, donc aucune garde ni consigne.
- Chez les clients MP : `DeadZombiePacket` porte l'inventaire du cadavre serveur et son identifiant ; chaque client
  recrée le même cadavre (`J/network/packets/character/DeadCharacterPacket.java:98-178`) : même contenu pour tous.
  Les ModData du cadavre client sont celles de sa copie (sans étiquette) : seule l'autorité identifie le cadavre.
- Objets en main : `die()` sur un serveur les pose au sol à côté du cadavre (`dropHeldItems`,
  `J/characters/IsoGameCharacter.java:10351-10376`), mais la copie du serveur d'un corps de PNJ ne tient jamais rien
  en main (`LK_Equipment`) ; l'arme accrochée est gardée dans le cadavre par LK07-T05 (section « Butin réel du
  cadavre »).

### Jamais de PNJ qui redevient un zombie

Deux chemins vanilla refont un zombie du cadavre, ModData (étiquette) comprises (`IsoDeadBody.reanimate`,
`J/iso/objects/IsoDeadBody.java:1832-1946`) :

| Chemin | Zombie obtenu | Règle (`Bodies.examine`) |
|---|---|---|
| Cadavre traîné par un joueur (prise B42, `J/iso/objects/IsoDeadBody.java:1777-1831`) | joueur réanimé `isReanimatedForGrappleOnly`, remis en cadavre par `die()` au lâcher (`J/ai/states/ZombieOnGroundState.java:80-91`), second `OnZombieDead` | **jamais touché**, quel que soit l'état du PNJ (avant LK07-T04 il était retiré comme orphelin : cadavre et contenu détruits) |
| Cadavre devenu faux mort en pourrissant (`ZombieLore.DisableFakeDead` = 2, 1/100 par stade, `J/iso/objects/IsoDeadBody.java:1576-1581`), relevé près d'un joueur (`1636-1653`) | zombie ordinaire étiqueté | **remis à terre** (`Bodies.layDown` : invulnérabilité et faux mort levés, `setAttackedBy(nil)`, `die()`) ; WARN `npc … is dead but its corpse rose again`, `Bodies.stats.laidDown` |
| Joueur réanimé étiqueté d'un PNJ mort (réanimation par un autre mod) | joueur réanimé | remis à terre de même |

Le balayage regarde désormais aussi les zombies ordinaires, mais n'en lit l'étiquette que s'ils ont des ModData
(`hasModData`, base `zombies-as-npc-bodies.md`) ; un zombie étiqueté d'un PNJ inconnu ou virtuel reste un orphelin
retiré, comme avant. Entre le relevé et le balayage (au plus un tour de liste, quelques secondes), le cadavre relevé
peut attaquer.

Serveur MP (LK07-T09, 2026-10-15) : la remise à terre attend `Bodies.RISEN_DELAY_MS` (2 s) depuis le premier passage
du balayage sur le zombie relevé (balayage suivant, environ 2 à 3,5 s). Un client ne retire l'ancien cadavre qu'en
recevant la copie du zombie relevé (`ZombieOnGroundState`, `reanimatedBodyId`) et ignore le paquet de mort d'un zombie
dont il n'a pas la copie : remis à terre aussitôt, le PNJ laissait chez les clients l'ancien cadavre (fantôme) et
jamais le nouveau, et ce fantôme bloquait ensuite tout cadavre de la même case (base `zombies-as-npc-bodies.md`, « Copie
cliente d'un zombie »). Solo : remis à terre au premier passage, comme avant.

### Fait publié

`LivingKnox.publish("npcDied", { npc, generation, cause, killer, weapon, burning, group, member, x, y, z, body })`
pour **toute** mort de corps courant (membre de groupe ou non), après le registre des groupes ; `memberDied` (mort
d'un corps de membre) gagne `cause`, `killer`, `weapon`. Aucun événement public n'existe encore : `npcDied` est le
point d'appel de LK12-T02 (`docs/specifications-techniques/api-living-knox.md`, « Faits publiés »). Autorité seulement, jamais envoyé tel quel à un client.

### Alternatives écartées (LK07-T04)

- **Effacer l'étiquette du cadavre** : le cadavre traîné ou relevé ne serait plus retiré à tort, mais LK07-T05 et les
  suites en jeu ne retrouveraient plus le cadavre du PNJ, et le zombie relevé errerait.
- **Suivre chaque cadavre pour lui ôter le faux mort** : aucun événement de pourriture, cadavres non suivis après un
  redémarrage ; coût et état supplémentaires pour un cas rare (option non par défaut).
- **Retirer le zombie relevé** : perdrait le cadavre et son inventaire.

### Tests

- Banc `tests/test_lk_death.py` (11 tests, MP et solo) : mort par coups de joueur (un `OnZombieDead`, un cadavre
  étiqueté, non faux mort, un fait `npcDied` melee / A / batte, coups suivants ignorés) ; perte de sang (cause
  `bleeding`, aucun tueur, ancien attaquant effacé) ; zombie vanilla (cause `zombie`, tueur du moteur = le zombie) ;
  corps mis de côté jamais tué (saignement, appel direct), appel direct unique ; cadavre traîné laissé tranquille puis
  lâché (mort vanilla en plus, aucune mort ni fait Living Knox de plus) ; cadavre relevé (faux mort) et joueur réanimé
  étiqueté remis à terre, PNJ jamais réincarné ; registre relu avec les nouvelles causes ; suite `lk.death` sur
  doublures ; sources compatibles Kahlua. `tests/test_lk_materialize.py` : `npcDied` avec groupe et membre,
  `memberDied` avec cause.
- Suite en jeu `lk.death` (`dev/.../suites/RST_LKDeath.lua`, tags `world`, `server`) : coups mortels (une mort, un fait,
  un cadavre étiqueté avec vêtements, aucun zombie étiqueté vivant 2 s plus tard) ; perte de sang ; mort directe puis
  `IsoDeadBody:reanimate()` réel et balayage : remis à terre.

### Protocole en jeu

1. Solo (`rstest*`, Living Knox activé) : `RST.run({ suite = "lk.death", tags = "world" })` → `OK` ; relever les
   lignes `[LKD] measure`.
2. Solo, à la main : `LKB.spawn()`, tuer le PNJ à la batte ; fouiller le cadavre (vêtements, clé du foyer) ; le
   traîner puis le lâcher : il reste, même contenu ; une seule ligne `died` au journal.
3. MP (séance finale) : A tue le PNJ ; A et B voient le même cadavre, même contenu ; l'arme en main est au sol.

### Limites

- Aucun essai en jeu de cette tâche ; doublures fidèles au Java relevé mais non prouvées (prise et faux mort de
  pourriture non reproduits en jeu).
- Mort par saignement sans tueur, même si un joueur a fait la blessure (décision à confirmer).
- Le cadavre relevé peut agir quelques secondes avant d'être remis à terre ; ses voix et un coup porté restent vanilla.
- Arme du PNJ : voir « Butin réel du cadavre (LK07-T05) » (sans lui, l'arme accrochée était perdue en MP).

## Butin réel du cadavre (LK07-T05)

Code : `LK_Loot.lua` (autorité), `LK_Ammo.lua` (`setLoaded`, `hasState`, `addReserve`, `unload`), branchement dans
`Bodies.onZombieDead`. Banc `tests/test_lk_loot.py`, suite `lk.loot`.

### Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| L'inventaire d'un joueur réanimé passe tel quel au cadavre (`DoZombieInventory` sans effet) ; il n'existe que sur la copie de l'autorité. | `J/characters/IsoZombie.java:3129-3133` ; `J/iso/objects/IsoDeadBody.java:327-332` | confirmé statiquement |
| `OnZombieDead` part dans `onKilled`, **avant** la création du cadavre (serveur `die()` → `Kill` → `onKilled` ; solo `Kill`, cadavre à la mise à jour suivante) : un objet posé alors part dans le cadavre. | `J/characters/IsoZombie.java:4599-4609` ; `J/characters/IsoGameCharacter.java:13478-13541` | confirmé statiquement |
| Chaque client MP reçoit le contenu du cadavre serveur (conteneur, objets portés, objets accrochés **par leur index dans le conteneur**) et en refait le sien. | `J/iso/objects/IsoDeadBody.java:2345-2376` ; `J/network/packets/character/DeadCharacterPacket.java:150-174` | confirmé statiquement |
| Un objet accroché absent du conteneur n'est ajouté au conteneur du cadavre qu'en **solo** (`setAttachedItems` saute client et serveur) ; sur un serveur il est envoyé avec l'index -1 et perdu (relecture et sauvegarde ignorent un index < 0). | `J/iso/objects/IsoDeadBody.java:565-585, 2360-2371, 793` | confirmé statiquement |
| Les objets en main d'un zombie ne sont pas repris par le cadavre (le constructeur ne lit pas les mains). | `J/iso/objects/IsoDeadBody.java:252-400` | confirmé statiquement |

L'arme d'un PNJ est un objet créé par `LK_Equipment` et accroché, jamais rangé dans l'inventaire : sans LK07-T05, le
cadavre la montrait en solo mais la perdait sur un serveur (ni pillable, ni vue des clients).

### Construction (une fois par corps)

- `Loot.build(id, z)` : passage toutes les `LOOT.EVERY_MS` (1 s) sur les corps reliés dans le monde, et au plus tard à
  la mort. Marque `LKLoot` (version) dans les ModData du corps, posée avant tout ajout : sauvegardée avec le corps
  (`reanimated.bin`), un corps relu ou relié de nouveau n'est jamais rempli deux fois. Une nouvelle incarnation est un
  nouveau corps (ModData neuves) : elle reçoit son butin, l'ancien corps a quitté le monde avec le sien.
- L'arme et le lien de groupe sont posés dans le même appel Lua que la création (`Materialize.embodyMember`) : le
  passage suivant les voit. Un changement d'arme après la construction ne rajoute pas de munitions.
- **Munitions** (arme à feu du registre, `Ammo.spec`) selon le niveau de munitions du groupe (`needs.ammo` 0..100 ;
  hors groupe : `LOOT.AMMO_LEVEL` = 50), f = niveau / 100 : cartouches dans l'arme = arrondi(capacité × f) (état
  `LKAmmo`, non réécrit s'il existe déjà) ; réserve = arrondi(`RESERVE_MAGS` (2) × f) chargeurs pleins pour une arme à
  chargeur, sinon arrondi(`RESERVE_ROUNDS` (12) × f) cartouches libres. Niveau 0 : aucune munition (mêlée).
- **Poches** selon le rôle du membre (`LOOT.POCKETS`, vrais objets vanilla relevés dans `media/scripts/generated/items`) :
  chef (`deputy`) carnet, crayon, briquet ; combattant bandage, chocolat ; éclaireur carte, lampe, barre de céréales ;
  médecin 2 bandages, lingettes, pince ; ouvrier 5 clous, tournevis ; casseur ruban adhésif, allumettes. Hors groupe :
  rien. Aucun nom affiché n'est lu ni écrit.
- **Objets de mission** : aucune API ne confie encore d'objet à un PNJ ; point d'appel `Loot.missionItems = function(id,
  info) return { { t = "Module.Objet", n = 1..5 }, ... } end` (`info` : `npc`, `group`, `member`, `role`), contrôlé
  (type bien formé, nombre borné à `MISSION_MAX`, type inconnu du jeu sauté et journalisé une fois).

### Mort (une fois par corps)

`Loot.onDeath(id, z)`, appelé par `Bodies.onZombieDead` pour le seul corps courant (marque `LKLootDead`) :

1. construction si elle n'a pas eu lieu ;
2. **arme gardée dans le cadavre**, de la même façon partout : objet accroché de la copie de l'autorité, sinon objet
   en main (solo, geste de visée ou de frappe), sinon objet neuf ; mains vidées hors serveur (sur un serveur rien n'est
   en main et la pose en main d'un zombie y lèverait l'exception `Equip`) ; objet accroché à son emplacement **et**
   ajouté au conteneur : le cadavre le montre accroché, il est pillable et chaque client le reçoit ;
3. cartouches de l'arme rendues en objets (`Ammo.unload`) : arme à chargeur → le chargeur engagé, avec ses
   cartouches (même vide) ; sinon une cartouche libre par cartouche. État `LKAmmo` effacé.

Aucune duplication : une construction et une mort comptées par corps ; cadavre traîné puis lâché, cadavre relevé :
ni nouvelle construction ni nouveau butin (`Bodies.onZombieDead` ne traite que le corps courant) ; l'arme n'est créée
que si le corps n'en porte aucune.

### Alternatives écartées

- **Arme posée au sol à côté du cadavre** : visible de tous, mais un objet au sol passe par une autre voie réseau et
  se perd du cadavre ; la garder dans le cadavre reprend le cas d'un joueur mort en solo.
- **Marque dans le registre (une construction par PNJ)** : chaque incarnation naîtrait les poches vides ; la marque
  par corps suit la règle de la clé du foyer (`deplacement.md`, « Clés »).
- **Munitions tirées au hasard** : déterministes d'après le niveau du groupe, sans graine à garder.

### Tests

- Banc `tests/test_lk_loot.py` (16 tests depuis LK07-T07, MP et solo) : construction unique d'après le niveau du groupe et le rôle,
  rien de plus aux passages suivants ni après relecture de `reanimated.bin` ; cadavre serveur avec le pistolet dans
  le conteneur et accroché, chargeur engagé rendu en objet (contenu identique en solo, arme alors en main) ; témoin
  du fait du moteur (sans `LK_Loot`, l'arme accrochée n'atteint pas les clients) ; arme créée et butin construit à
  la mort avant tout passage (fusil à pompe : cartouches libres) ; cadavre traîné puis lâché sans doublon ; nouvelle
  incarnation, niveau 0 sans munition ; point d'appel des missions contrôlé ; clients arrêtés à la garde ; arme
  accrochée non doublée par le cadavre solo ; suite `lk.loot` sur doublures ; sources Kahlua ; objets de poche
  présents dans les scripts vanilla installés.
- Suite en jeu `lk.loot` (`dev/.../suites/RST_LKLoot.lua`, tags `world`, `server`) : construction unique (munitions,
  poches de médecin par un point d'essai sur `Loot.contextOf`) ; mort directe : pistolet une fois dans le cadavre,
  accroché et dans le conteneur, cartouches dans les chargeurs, aucun pistolet au sol.

### Protocole en jeu

1. Solo (`rstest*`, Living Knox activé) : `RST.run({ suite = "lk.loot", tags = "world" })` → `OK` ; relever les lignes
   `[LKL] measure`.
2. Solo, à la main : approcher un groupe jusqu'à sa matérialisation, tuer un membre armé, fouiller le cadavre (arme,
   munitions, objets de son rôle, clé du foyer) ; le traîner puis le lâcher : même contenu.
3. MP (séance finale) : A tue un PNJ armé ; A et B voient le même cadavre, la même arme accrochée et le même contenu ;
   rien au sol ; `server-console.txt` sans erreur `LivingKnox`.

### Limites

- Aucun essai en jeu ; doublures fidèles au Java relevé mais non prouvées.
- Les munitions de départ font tirer d'emblée les PNJ armés d'une arme à feu dont le groupe a des munitions
  (`LK_Combat` engage le tir dès qu'une munition est disponible).
- Les munitions dépensées ou gardées par un corps ne reviennent pas au niveau abstrait du groupe au retrait du corps
  (la simulation hors écran tient son propre compte).
- Poches selon le rôle seulement (traits de personnalité, I7.3, non repris) ; un PNJ hors groupe n'a pas de poches.

### Butin absent du cadavre en jeu (LK07-T07, 2026-10-12)

- Constat (`console.txt`, `lk-67`) : « death loot: weapon Base.Pistol (created) … 15 item(s) in the corpse », puis
  cadavre sans pistolet ni chargeur (même le chargeur de réserve posé à la construction), poches présentes.
- Le chemin de mort est conforme au Java : `Health.kill` → `die()` → `Kill(getAttackedBy())` → `onKilled` →
  `OnZombieDead` (`IsoZombie.java:4599-4610`, `IsoGameCharacter.java:13463-13474, 13480-13484`), puis
  `becomeCorpse()` → `new IsoDeadBody(this)` (`IsoGameCharacter.java:13495, 13536-13541`) qui prend **le même**
  conteneur et les objets accrochés (`IsoDeadBody.java:327-332`, `setContainer(died.getInventory())`), après le butin.
  `DoZombieInventory` ne fait rien pour un joueur réanimé (`IsoZombie.java:3131`). Rien ne copie l'inventaire avant.
- Cause : le mod d'armes actif **Guns of Marz** (Workshop 3722134990, `id=GunsOfMarz`, variante 42.16, avec le cadre
  `SWMG` 3722064198), option sandbox `MarzGuns.VanillaWeaponReplacement` (et `VanillaAmmoReplacement`) **vraie par
  défaut** (`media/sandbox-options.txt:3-15`). Il pose un `OnCreate` (`MarzGuns_OnCreate.VanillaReplace`) sur les
  armes à feu, chargeurs et munitions vanilla (`Hooks/ItemPatcher.lua:70-97`) ; l'objet créé est mis en attente tant
  qu'il est dans l'inventaire d'un zombie ou nulle part, puis, à un `OnTick` suivant, remplacé dans son conteneur par
  une arme Marz tirée au hasard plus des bonus (`SpawnerSystems/ItemSpawnCore.lua:110-138, 31-51`). Dans le cadavre,
  le pistolet, le chargeur engagé et le chargeur de réserve sont donc échangés ; les poches (aucun crochet) restent.
  Son abonné `OnZombieDead` remplace aussi les objets vanilla déjà dans l'inventaire du mort
  (`Hooks/ZombieAttachmentHooks.lua:21-27`, `OnCreate/ZombieAttachmentReplacer.lua:44-81`).
- Choix (le plus simple, le plus proche du vanilla) : **aucun changement du butin de mort**. Le remplacement est le
  comportement voulu de ce mod pour tout objet vanilla, PNJ compris ; le contourner (marque interne du mod,
  désinscription) lierait le moteur au code d'un tiers. La suite `lk.loot` liste les crochets de création
  (`Item.getLuaCreate`, aucun en vanilla pour `Base.Pistol`/`Base.9mmClip`/`Base.Bullets9mm`) et tout le contenu du
  cadavre, et passe le test de mort en SKIP avec le nom du crochet au lieu d'un échec trompeur.
- Banc : `ON_CREATE` (appel de l'`OnCreate` par `instanceItem`, `InventoryItem.java:4022-4027`) et doublure du
  remplacement relevé ; le test de reproduction perd le pistolet et les chargeurs dans le cadavre comme en jeu.
- Protocole : relancer `RST.run({ suite = "lk.loot", tags = "world" })` sur une sauvegarde `rstest*` où
  `MarzGuns.VanillaWeaponReplacement` et `MarzGuns.VanillaAmmoReplacement` sont décochées (ou sans Guns of Marz) :
  `OK`, mesure « creation hooks none ». Avec l'option active, la mesure doit nommer le crochet et montrer des objets
  `MarzGuns.*` dans le cadavre.

### Décisions à confirmer

- LK07-T07 : laisser un mod de remplacement d'armes échanger le butin vanilla du cadavre (aucune exception pour les
  PNJ) ; la suite saute le contrôle de mort quand un crochet de création est actif.
- Arme gardée dans le cadavre, accrochée et dans son conteneur (plutôt que posée au sol).
- Munitions de départ = fraction du niveau `needs.ammo` du groupe (50 hors groupe), réserve de 2 chargeurs ou 12
  cartouches au niveau 100.
- Objets de poche par rôle (liste `LOOT.POCKETS`).

## Cadavre renvoyé à un client sans copie (LK07-T10)

Tâche LK07-T10 (2026-10-15). Code : `media/lua/server/LivingKnox/LK_Death.lua` (serveur MP seulement ; appelé par
`Bodies.onZombieDead` et `Bodies.layDown` via `Bodies.trackCorpse`), `media/lua/client/LivingKnox/LK_DeathClient.lua`
(client MP). Banc `tests/test_lk_death.py` (`CorpseResendTests`) ; suite `lk.death`, test « killed before any client
copy ». Lecture statique et banc : **essai MP à faire**.

- **Cause** : un client ne crée le cadavre d'un zombie que par le paquet de mort, ignoré s'il n'a pas la copie du
  zombie (copie retirée « stale », client arrivé juste avant, corps tué avant l'envoi de sa copie). Sa case garde un
  objet statique de moins que celle du serveur, ce qui bloque aussi les cadavres suivants de la case (base
  `zombies-as-npc-bodies.md`, « Copie cliente d'un zombie »).
- **Renvoi** : `sendCorpse` part vers toutes les connexions proches et crée un doublon chez un client qui a déjà le
  cadavre ; aucune fonction Lua ne vise une seule connexion. Donc, `Death.CHECK_DELAY_MS` (7 s) après la mort, le
  serveur demande aux joueurs à `Death.NEAR` cases (commande `corpseCheck` : identifiant d'objet `DeadBody-<n>`, case,
  nombre d'objets statiques) ; un client qui ne trouve pas ce cadavre (case et voisines) répond `corpseMissing`. Le
  serveur retire alors le cadavre chez tous (`removeCorpse(body, false)`, identifiant de personnage mis à -1 le temps
  de l'envoi), puis `Death.RESEND_GAP_MS` (1 s) plus tard le remet sur sa case (`addCorpse(body, true)`) et l'envoie
  (`sendCorpse`). Nouvelle demande `Death.RECHECK_MS` (3 s) après ; au plus `Death.MAX_RESENDS` (2) renvois, puis
  avertissement « corpse still missing ».
- **Contrôles** : réponse acceptée seulement pendant `Death.REPLY_MS` après une demande, d'un joueur proche, une fois
  par demande ; cadavre traîné, retiré ou brûlé avant la demande : abandon (`stats.gone`) ; personne à portée :
  `stats.nobody`. Rien en solo ni sur un client.
- **Limites** : un joueur qui fouille ce cadavre à l'instant du renvoi voit la fenêtre se fermer ; un arrêt du
  serveur pendant la seconde où le cadavre est hors de sa case le perd ; le cadavre fantôme en trop chez un client
  (LK07-T09) n'est pas traité ici. Identifiant d'objet lu par `tostring(body:getObjectID())` (confirmé statiquement) ;
  sous une autre forme, le client compare le nombre d'objets statiques.
