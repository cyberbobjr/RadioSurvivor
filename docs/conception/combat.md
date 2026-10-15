# Mêlée et tir des PNJ contre les joueurs

- Tâches : LK06-T02 (création, 2026-10-12), LK06-T03 (tir, section [Tir](#tir-lk06-t03), 2026-10-12), LK06-T09 (coup au sol, section [Coup au sol](#coup-au-sol-lk06-t09), 2026-10-12), LK06-T11 (sons de la mêlée, section [Sons de la mêlée](#sons-de-la-mêlée-lk06-t11), 2026-10-13), LK06-T13 (sons à la mort du corps, section [Sons et mort du corps](#sons-et-mort-du-corps-lk06-t13), 2026-10-13) ; s'appuie sur LK06-T01 (cible, [cibles.md](cibles.md)), LK02-T05 (gestes, [corps-et-animations.md](corps-et-animations.md)), LK02-T06 (arme, [equipement.md](equipement.md)), LK03 (consignes, [consignes.md](consignes.md)), LK05-T02 (cascade, [decisions.md](decisions.md)) ; suite : LK06-T03 (tir), LK06-T04 (zombies), LK06-T05 (fuite, reddition)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-12 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Combat.lua` (`LivingKnox.Combat`, autorité), `media/lua/server/LivingKnox/LK_Ammo.lua` (`LivingKnox.Ammo`, munitions, LK06-T03), `media/lua/client/LivingKnox/LK_CombatClient.lua` (`LivingKnox.CombatView`, machine qui simule le corps), branchement dans `LK_Decisions.lua` (comportement `fight`). Réglages `LivingKnox.Config.COMBAT` (définis dans `LK_Combat.lua`). Tests : `tests/test_lk_combat.py`, suites en jeu `lk.melee` (`dev/.../suites/RST_LKMelee.lua`) et `lk.ranged` (`RST_LKRanged.lua`).

## Problème

Un PNJ combattant dont le groupe a retenu un joueur comme cible d'attaque doit aller vers lui, le frapper avec l'animation humaine de son arme (ou à mains nues), à la portée et à la cadence de l'arme ; chaque coup doit blesser le joueur **une seule fois**, et aucun coup hors de portée ne doit compter, quel que soit le client qui simule le corps.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Le serveur ne peut pas animer ni déplacer un zombie qu'un client simule ; le propriétaire exécute les consignes, le serveur ne fait confiance qu'à lui (`getOwnerPlayer`). | [consignes.md](consignes.md) ; base `multiplayer.md` | confirmé statiquement |
| Blesser un joueur depuis le serveur : `getBodyDamage():DamageFromWeapon(arme, -1)` (partie tirée au hasard, défense des vêtements, blessure selon la catégorie, douleur ; `Rand(min, max) × 15`, × 4 tête et cou, × 2 haut du torse ; **sur un serveur, × modificateur PvP de mêlée** `PVPMeleeDamageModifier`, défaut 30) puis `syncDamage` ; un client ignore l'appel pour un joueur non local. | `J/characters/BodyDamage/BodyDamage.java:1014-1100` ; `J/network/ServerOptions.java:149` ; `J/characters/NetworkPlayerAI.java:583-590` | confirmé statiquement |
| `sendDamage(joueur)` envoie l'état complet des blessures (`PlayerDamage`) au client du joueur (sans effet hors serveur) : rejoué, il ne double rien. | `J/Lua/LuaManager.java:3743-3748` ; `J/network/packets/character/PlayerDamagePacket.java` | confirmé statiquement |
| Les coups entre joueurs passent par le même appel (`IsoPlayer.hitConsequences`, arme `null`-safe : `weapon.getUsingPlayer()` peut être nul). Les mains nues sont l'arme vanilla `Base.BareHands` (catégorie `unarmed`, `MaxRange` 1,1). | `J/characters/IsoPlayer.java:3861-3866` ; `J/characters/BodyDamage/BodyDamage.java:961-984` ; `media/scripts/generated/items/weapon.txt` (`item BareHands`) | confirmé statiquement |
| Le mode dieu n'empêche pas `DamageFromWeapon` : la santé est rendue entière à la mise à jour suivante (`RestoreToFullHealth`). | `J/characters/BodyDamage/BodyDamage.java:1821-1825` | confirmé statiquement |
| Clips de frappe : `Bob_AttackBat01_Hit` et `Bob_Attack1Hand01_Hit` durent 1,0 s (4800 tics à 4800 tics/s) ; nos nœuds les jouent en boucle à la vitesse 0,80, soit **1,25 s par frappe** ; le contrôle de touche vanilla (`AttackCollisionCheck`) est à 25 % du clip. | `media/anims_X/Bob/*.x` ; `media/AnimSets/player/melee/2handed/2HDefault.xml`, `1handed/1HDefault.xml` ; `tools/anim_table.json` | confirmé statiquement |
| Portée vanilla : `MaxRange × getRangeMod` mesurée jusqu'au point le plus proche de la cible. | `J/CombatManager.java:1669-1722` ; `J/inventory/types/HandWeapon.java:455-463, 808-817` | confirmé statiquement |

## Choix (2026-10-12)

### Engagement (autorité)

- `Combat.engage(npcId, compte, { source, why })` : ordre numéroté `c` (croissant sur la session), cible joueur, arme et réglages ; même cible déjà engagée : ordre gardé. Mémoire seulement (un redémarrage l'oublie ; la cascade le reprend).
- **Arme** : celle du PNJ (`Equipment.wantedOf`) si c'est une arme de mêlée ; arme à feu, absente ou inconnue : **mains nues** (`Base.BareHands`). Le tir est LK06-T03.
- **Portée** = `MaxRange` de l'arme (au moins `MIN_REACH` = 1) + `REACH_BONUS` = 0,5 (rayon des deux corps, le moteur visant le point le plus proche). Batte 1,75 (MaxRange 1,25) ; mains nues 1,6 (1,1) ; couteau de cuisine 1,5 (0,9 relevé au minimum de 1) (scripts `media/scripts/generated/items/weapon.txt`).
- **Cadence** = une frappe par boucle du clip joué (`STRIKE_MS` = 1250 ms), premier impact `IMPACT_MS` = 312 ms après l'apparition du geste.
- **Passage** toutes les `PASS_MS` = 250 ms, au plus `MAX_ENGAGED` = 16 PNJ :
  - hors de portée (ou autre niveau, ou cible en véhicule) : consigne `move` en course vers la case du joueur, renouvelée quand il s'éloigne de `REPATH` = 2 cases ou après `RETRY_MS` = 3 s, au plus une par `MOVE_MS` = 1 s ; geste de frappe remplacé par la garde ;
  - à portée, même niveau : consigne `face` vers le joueur (renouvelée à 30° d'écart), puis geste `strike` (après `face`, qui remet le repos) ;
  - fin : joueur parti, mort, à plus de `GIVE_UP` = 30 cases, corps absent ou mort décidée, décision changée ; geste de frappe retiré, marche du combat arrêtée.
  - laisse (LK05-T09, `opts.leash = { x, y, z, r }`, défense du foyer, [defense.md](defense.md)) : une cible à plus de `r` cases (x et y) de la case de la laisse, ou à un autre niveau, n'est jamais approchée ; frappe à portée ou tir à ligne dégagée seulement, sinon fin de l'ordre (« target out of the defense leash »). Laisse remplacée quand la même cible est engagée de nouveau, gardée par la mêlée de repli d'un tireur à court de munitions (dont la cible zombie est désormais l'objet, et non sa clé).
- Les consignes du combat sont notées comme celles du cadre de décision (`Decisions.noteIssued`) : jamais « externes ».

### Branchement dans la cascade (LK_Decisions, modification minimale)

- Contexte d'un **combattant** (rôle qui permet `fight` ou `defend`) : `ctx.target = Combat.targetFor(gid, npcId, perception, joueurs)` = cible de `Hostility.chooseTarget` parmi les joueurs **vus**, seulement si l'action est `attack`.
- Règle `threat`, en tête : cible présente et comportement `fight` permis → `fight` (clé `p<compte>`, raison `attack player A at 4.0 (hostile)`), avant le regard et la fuite. LK06-T07 : un non-combattant ne prend jamais un joueur pour cible, mais se bat contre un zombie à portée ([decisions.md](decisions.md), « Tout le monde se bat »).
- `Decisions.apply` : `fight` → `Combat.apply` (engagement de source `decisions`) ; tout autre comportement → `Combat.leave` (fin d'un engagement de la cascade seulement ; un engagement de l'API ou d'une suite reste). `Decisions.forget` → `Combat.forget`.
- Comportement `fight` : vigilance `guard`, échéance 1 minute de jeu (réévalué chaque minute ; perte de la cible = interruption).

### Touche : rapportée par le propriétaire, contrôlée et appliquée une fois par le serveur

- **Machine qui simule le corps** (`LK_CombatClient.lua`, client propriétaire en MP, solo) : corps simulé ici (`ZombieGuard.simulatedHere`) et geste affiché `strike` → minuterie d'impact ; à chaque impact, cible vivante, même niveau, à la portée de l'ordre sur **sa** copie → rapport `combatHit { id, c, n, u, x, y, z }` (appel direct de `Combat.onHit` en solo), sinon coup manqué (rien n'est envoyé). `n` croît par ordre sur cette machine.
- **Contrôles du serveur** (`Combat.onHit`), dans l'ordre :

| Contrôle | Échec |
|---|---|
| ordre courant `c` | ignoré (`stale`, course) |
| corps présent, mort non décidée | ignoré |
| expéditeur = propriétaire du corps (`Directives.isOwner`) | ancien propriétaire non prévenu (`Directives.isPreviousOwner`, 4 s) : ignoré ; sinon refus `not the owner` |
| `n` > dernier `n` de cet expéditeur pour cet ordre | ignoré (`duplicates`) ; le numéro est retenu **avant** les autres contrôles : un rapport refusé n'est jamais rejoué |
| même cible, vivante, présente, hors véhicule | refus |
| phase de frappe en cours | refus `not striking` |
| même niveau ; distance des copies du serveur ≤ portée + `REACH_SLACK` (1 case) | refus `other level`, `out of reach` |
| au moins `CADENCE_MIN` × `STRIKE_MS` (750 ms) depuis la dernière touche appliquée de l'ordre | refus `too fast` |

- **Application** : `DamageFromWeapon(arme de l'ordre, -1)` sur le joueur, puis `sendDamage` (serveur). Journal `INFO npc lk-1 hit A with bare hands (melee #1, hit 3, 1.45 squares, reported by A)` ; refus : une ligne par (expéditeur, raison) et par minute (`WARN` pour les raisons suspectes). Compteurs `Combat.stats` (`applied`, `refused`, `ignored`, `duplicates`, `stale`, `why`).
- **Cible zombie** : point d'appel `Combat.applyToZombie(id, ordre, cible)`, rempli par LK06-T04 ([zombies.md](zombies.md)) : `Combat.engage` accepte un zombie vanilla, `Combat.targetFor` le rend faute de cible joueur.

### Diffusion (serveur MP)

`combatState { d = { [npcId] = { r, c, u, k, rc, iv, im } | { r, gone = true } } }` aux destinataires des consignes (`Directives.targets` : joueurs à 100 cases et propriétaire), seulement à ceux qui n'ont pas la révision courante ; `{ gone }` aux détenteurs à la fin ; tout est renvoyé après `guardHello`. Un nouveau propriétaire est déjà parmi les proches : la remise `npcHand` (champ réservé `tgt`) n'est pas utilisée.

## Alternatives écartées

- **Touche décidée par le serveur seul** (minuterie sur ses copies) : contraire au contrat de la tâche (« rapportée par le propriétaire ») et décalée de l'animation que voit le propriétaire.
- **Événements d'animation** (`AttackCollisionCheck` d'un nœud de mod) pour marquer l'impact : l'événement vanilla est traité par l'état d'attaque du joueur ; un `SetVariable` à 25 % demanderait de régénérer les AnimSets et la somme de contrôle MP, pour un gain de quelques images.
- **Valeur de dégâts envoyée par le client** : inutile, le serveur la calcule avec l'arme de l'ordre.
- **Seau à jetons comme pour les coups des joueurs** ([sante.md](sante.md)) : autoriserait des rafales ; un intervalle minimal par ordre suffit à une cadence fixe.
- **Cadence propre à chaque arme** (vitesse de combat vanilla `0,8 × BaseSpeed`, bornée 0,8 à 1,6) : le clip joué par nos nœuds a une vitesse fixe ; une cadence différente décalerait les touches de l'animation (voir points ouverts).

## Idées reprises

- Aucune.

## Tests

- Banc lupa `tests/test_lk_combat.py` (13 tests) : approche en course puis regard et geste de frappe chez les deux clients, une touche par boucle du clip pendant 6 s, rapportée par le seul propriétaire, dommages et `sendDamage` une fois par touche, joueur éloigné : aucune touche rapportée ni appliquée et nouvelle course ; aucune touche hors de portée ou d'un autre niveau acceptée (même forgée) ; doublon ignoré, rafale refusée (`too fast`), rapport refusé jamais rejoué, rapport plus ancien ignoré ; non-propriétaire refusé, ancien propriétaire ignoré, nouveau accepté ; ordre périmé, mauvaise cible, cible morte (fin de l'engagement, geste rendu, `{ gone }` chez les clients) ; ordre envoyé aux seuls proches, une fois, renvoyé après `guardHello`, envoi plus ancien ignoré ; arme à feu → mains nues, batte → portée 1,75 ; client MP sans autorité ; solo sans message ; suite `lk.melee` jouée sur les doublures ; cascade complète (groupe hostile matérialisé : le combattant qui voit le joueur engage la mêlée avec sa batte, l'ouvrier non ; joueur perdu de vue : fin de la mêlée) ; sources compatibles Kahlua.
- VM Kahlua : sans objet (aucun mécanisme de VM nouveau).
- En jeu : suite `lk.melee` (tags `world`, `server`), à lancer.

### Protocole en jeu

1. Solo (`rstest*`, Living Knox activé, mod de dev) : `RST.run({ suite = "lk.melee", tags = "world" })` en regardant le PNJ : il court vers le joueur, se tourne et frappe ; relever les lignes `[LKM] measure` (touches appliquées, plus petit écart, santé du joueur). Attendu `OK`.
2. Solo, à la main : `LKB.spawn(3, 0)`, puis `LivingKnox.Combat.engage("lk-<n>", getPlayer():getUsername())` ; s'éloigner en courant : le PNJ suit ; revenir à côté : il frappe toutes les 1,25 s environ, des blessures apparaissent ; `LivingKnox.Combat.disengage("lk-<n>", "test")`.
3. MP (séance finale, serveur dédié + clients A et B) : `RST.server({ suite = "lk.melee", tags = "world" })` depuis A ; B voit le geste de frappe ; journal serveur : lignes `hit A with` sans `refused` ; A à l'étage ou en voiture : aucune touche.

## Points ouverts

- ⚠ **Décision à confirmer** : dégâts = chemin vanilla des coups entre joueurs (`DamageFromWeapon`), donc **× `PVPMeleeDamageModifier` du serveur en MP** (défaut 30) et aucun modificateur en solo : un même coup est bien plus fort en MP qu'en solo. Autre option : appliquer soi-même blessure et dégâts avec un multiplicateur propre au mod.
- ⚠ **Décision à confirmer** : cadence commune à toutes les armes de mêlée (boucle du clip, 1,25 s) ; une cadence par arme demanderait une vitesse de nœud variable (`m_SpeedScale` par variable, AnimSets à régénérer).
- ⚠ Portée : la consigne d'approche vise la case du joueur et s'arrête à 1 case de son centre ; avec une arme courte (couteau), le PNJ peut s'arrêter juste hors de portée jusqu'au nouvel essai (`RETRY_MS`). À mesurer en jeu.
- ⚠ Réaction du joueur frappé (recul) : aucune ajoutée (son du coup : LK06-T11, section [Sons de la mêlée](#sons-de-la-mêlée-lk06-t11)) ; `DamageFromWeapon` ne joue un son que si l'armure arrête le coup.
- ⚠ Zones non-PvP, refuges et option PvP du serveur : non consultées (le PNJ n'est pas un joueur).
- ⚠ Rendu réel du clip de frappe en boucle sur un corps de zombie (dérive du clip) : à voir en jeu.
- Cibles zombies (LK06-T04) et tir (LK06-T03) : hors périmètre.

## Tir (LK06-T03)

### Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Tir vanilla du joueur : son `playRangedWeaponShootSound(SwingSound)` (émetteur du personnage ; sur un client MP, paquet `RangedWeaponSound` pour les autres), bruit `addWorldSoundUnlessInvisible(SoundRadius × FirearmNoiseMultiplier, moitié à l'intérieur, SoundVolume)`, puis `DoAttack` ; munitions retirées à `OnWeaponSwingHitPoint`. | `media/lua/shared/TimedActions/ISReloadWeaponAction.lua:409-542` ; `J/characters/IsoPlayer.java:6799-6805` | confirmé statiquement |
| Éclair vanilla d'un tir : `EffectsManager.startMuzzleFlash` = lumière `IsoLightSource(x, y, z, 0,8 i, 0,8 i, 0,6 i, 18, vie 6)` avec i = max(nuit × 0,8, 0,2), plus un modèle de flamme accroché au canon. `EffectsManager` n'est pas exposé à Lua ; `IsoLightSource` et `IsoCell:addLamppost` le sont. Une lumière à durée de vie est passée au moteur d'éclairage comme lumière temporaire puis retirée de la liste. | `J/EffectsManager.java:45-58` ; `J/CombatManager.java:629-631` ; `J/iso/LightingJNI.java:275-280` ; `J/Lua/LuaManager.java:2145` | confirmé statiquement ; rendu à vérifier |
| Munitions : `HandWeapon:getAmmoType():getItemKey()` donne le type des cartouches (`Base.Bullets9mm`), `getMagazineType()` le chargeur (`Base.9mmClip`, nil pour un fusil à pompe), `getMaxAmmo()`, `getAmmoPerShoot()` ; un chargeur porte `getCurrentAmmoCount()`. Une cartouche est un objet. | `J/scripting/objects/AmmoType.java:47-49` ; `J/inventory/types/HandWeapon.java:1886-1997` ; `media/scripts/generated/items/weapon.txt` (`Pistol`, `Shotgun`) | confirmé statiquement |
| Chance de toucher vanilla : `CombatManager.calculateHitChanceData` (base, Visée, distance avec et sans viseur, temps de visée, mouvement, météo, lumière, moodles) ; reproductible en Lua. | base `combat-and-xp.md` ; `J/CombatManager.java:2036-2215` | confirmé statiquement |
| Clips : `Bob_AttackHandgun` 0,667 s, `Bob_AttackRifle` 0,5 s (coup de feu à 0,1 % du clip, `AttackCollisionCheck`), `Bob_Reload_Handgun_Load` 1,5 s, `Bob_Reload_Rifle_Load` 1,733 s (tics de `media/anims_X/Bob/*.x` à 4800 par seconde). | `AnimSets/player/ranged/*/…Default.xml`, `actions/LoadHandgun.xml`, `LoadRifle.xml` | confirmé statiquement |
| Blessure par balle pour un joueur : `DamageFromWeapon(arme à feu, -1)` ; sur un serveur, × `PVPFirearmDamageModifier` (défaut 50). | base `combat-and-xp.md` | confirmé statiquement |

### Choix (2026-10-12)

- **Tir ou mêlée** : `Combat.weaponOf` retient le tir si l'arme du registre est une arme à feu **et** que le corps a des munitions (`Ammo.available` > 0) ; sinon mêlée à mains nues, comme LK06-T02. Le choix vaut pour tout engagement (cascade `fight` ou API) : aucun changement de `LK_Decisions`.
- **Munitions** (`LK_Ammo.lua`, autorité) : l'arme du PNJ est un type du registre, jamais un objet ; son contenu est donc noté dans les ModData du corps (`LKAmmo = { t, n }`, sauvegardées avec le joueur réanimé, jamais envoyées). La **réserve est réelle** : cartouches et chargeurs de l'inventaire du corps (premier niveau). Rechargement : échange avec le chargeur de réserve le plus plein (contenus échangés, aucun objet créé ni détruit), sinon cartouches libres jusqu'à `getMaxAmmo()` (objets retirés), sinon plus de munition. `Ammo.give(id, arme, cartouches, chargeurs)` pour l'API et les suites ; munitions de départ posées à la naissance du corps d'après le niveau du groupe et cartouches de l'arme rendues en objets à la mort (LK07-T05, `sante.md`, « Butin réel du cadavre »).
- **Ordre de tir** (`m = "ranged"`) : portée = `MaxRange` (au plus `FIRE_RANGE` = 20 ; pistolet 15), cadence `SHOT_MS` = 1 000 ms (une boucle des nœuds de tir), coup de feu `SHOT_IMPACT_MS` = 100 ms après le début de la boucle. Passage de l'autorité :
  - arme vide : rechargement **sur place** (regard vers la cible, qui remplace une marche ; geste `reload` pendant `RELOAD_MS` : 1 875 ms pistolet, 2 167 ms arme longue, × `RELOAD_ROUNDS_LOOPS` = 2 pour des cartouches libres), puis `Ammo.reload` ; plus rien : fin de l'ordre (`out of ammo`) et nouvel engagement, à mains nues ;
  - tir possible (même niveau, portée, cible hors véhicule, **ligne de tir** `LosUtil.lineClear` = `Clear` ou `ClearThroughOpenDoor`) : regard, geste `aim` pendant `AIM_MS` = 600 ms, puis `shoot` ;
  - sinon approche en course comme la mêlée (geste `aim` au lieu de `guard`). Une fenêtre (`ClearThroughWindow`, vitre même fermée) ou une porte vitrée fermée ne laisse pas tirer.
- **Coup de feu** : rapporté par le propriétaire comme une touche (même message `combatHit`, même minutage sur le geste `shoot`), puis contrôlé par le serveur dans l'ordre de la mêlée (ordre, propriétaire, numéro, cible, phase `shoot`, niveau, portée + `REACH_SLACK`), puis **ligne de tir** sur ses copies (`no line of fire`), cadence (`too fast`), et **une cartouche retirée de l'arme avant tout effet** (`no ammo` sinon : ni bruit, ni son, ni dommage). Accepté :
  - bruit `addSound(nil, x, y, z, SoundRadius × FirearmNoiseMultiplier (× 0,5 à l'intérieur), SoundVolume)` sur l'autorité (relayé par le serveur) ;
  - son vanilla de l'arme et éclair : entrée `{ k, npc, o, x, y, z, snd }` envoyée (`combatShot`) aux destinataires du relais (`Directives.targets` : joueurs à 100 cases et propriétaire), appel direct en solo ; chaque client la joue **une fois par clé** (`k` = session du serveur + numéro du tir ; doublon ignoré) : `SwingSound` sur l'émetteur de sa copie du corps (sinon émetteur libre), lumière temporaire comme l'éclair vanilla ;
  - touche **décidée par le serveur seul et reproductible** : chance `Combat.hitChance` (portage de `calculateHitChanceData` réduit à la base, à la Visée prêtée `AIM_LEVEL` = 3 et aux deux termes de distance ; constantes `CombatConfigKey` par défaut ; pistolet : 90 % à 1 case, 76 % à 4, 72 % à 5, 44 % à 10), comparée à `Combat.roll(PNJ, ordre, numéro du tir)` (Park et Miller, 0..99, `roll <= chance` comme `Rand.Next(100) <= chance`) ; touché : `DamageFromWeapon(arme à feu, -1)` puis `sendDamage`.
  - Journal `INFO npc lk-1 shot at A with Base.Pistol (ranged #1, shot 2, 4.00 squares, chance 76, roll 77: missed, 1 round(s) left, reported by A)` ; compteurs `shots`, `hits`, `misses`, `reloads`, `outOfAmmo`, `noises`, `shotMessages`, `volleys`.
- **Gestes** (`tools/anim_table.json`, `LK_Anim`) : `shoot` (`LKActorShootHandgun`, `LKActorShootRifle` si `Weapon=firearm`) et `reload` (`LKActorReloadHandgun`, `LKActorReloadRifle`), arme en main (`Equipment.HAND_GESTURES`). Clips du joueur en boucle, posture fixe (pas de 2D blends ni de masques d'os), aucun son de rechargement.

### Alternatives écartées

- **Tir minuté par le serveur seul** : décalé de l'animation que voit le propriétaire ; refusé comme pour la mêlée.
- **Son et éclair joués par le propriétaire avant le contrôle** : un tir refusé (sans munition) aurait été entendu ; tout passe donc par l'entrée du serveur (un aller-retour de délai chez le propriétaire).
- **Arme et chargeur réels dans l'inventaire du corps** : l'arme du PNJ n'est qu'un type du registre (LK02-T06) ; un objet réel demanderait de le tenir synchronisé avec le registre et la pose en main côté client.
- **Chance vanilla complète** (temps de visée, lumière par joueur, météo, moodles) : la lumière est propre à chaque joueur local et le temps de visée n'a pas de sens pour un corps de zombie ; gardés hors calcul (points ouverts).
- **Tirage `ZombRand`** : non reproductible ; un rejeu ou un doublon de rapport ne doit jamais changer l'issue.

### Tests

- Banc lupa `tests/test_lk_combat.py` (25 tests, dont 12 du tir) : rechargement sur place puis un tir par cartouche, jamais plus, puis mêlée à mains nues contre la même cible ; tirs rapportés par le seul propriétaire ; bruit (rayon, volume, intérieur, multiplicateur) une fois par tir ; son et éclair reçus et joués une fois par chaque client proche, doublon ignoré, corps inconnu → émetteur libre, son invalide refusé ; tir forgé arme vide refusé sans effet ; ligne de tir bloquée refusée sans cartouche retirée, fenêtre → approche, porte ouverte → visée ; hors de portée, non-propriétaire, cadence ; échange de chargeurs sans objet créé, cartouches libres, fusil à pompe sans chargeur ; chance identique à la formule vanilla de référence, tirage reproductible ; solo sans message ; suite `lk.ranged` jouée sur les doublures. `tests/test_gen_animsets.py` : nœuds de tir et de rechargement choisis selon `Weapon`.
- En jeu : suite `lk.ranged` (tag `world`), à lancer.

### Protocole en jeu

1. Solo (`rstest*`, Living Knox activé, mod de dev) : `RST.run({ suite = "lk.ranged", tags = "world" })` en regardant le PNJ : geste de rechargement, visée, un tir par seconde avec le son du pistolet et un éclair, trois tirs puis il court frapper à mains nues. Relever les lignes `[LKR] measure`. Attendu `OK`.
2. Solo, à la main : `LKB.spawn(6, 0)`, `LivingKnox.Equipment.setWeapon("lk-<n>", "Base.Shotgun")`, `LivingKnox.Ammo.give("lk-<n>", "Base.Shotgun", 4, 0)`, `LivingKnox.Combat.engage("lk-<n>", getPlayer():getUsername())` : rechargement (clip d'arme longue), son du fusil à pompe ; se cacher derrière un mur : le PNJ se rapproche sans tirer.
3. MP (séance finale) : `RST.server({ suite = "lk.ranged", tags = "world" })` depuis A (mesures du serveur ; son et éclair non mesurés sur un serveur) ; A et B entendent chaque tir une fois et voient l'éclair ; journal du serveur : lignes `shot at A with` sans `refused`, puis `out of ammo`.

### Points ouverts

- ⚠ **Décision à confirmer** : munitions de réserve = objets réels de l'inventaire du corps, contenu de l'arme dans ses ModData ; aucune munition donnée automatiquement aux PNJ (stock du groupe, butin, matérialisation : à décider avec LK08/LK10).
- ⚠ **Décision à confirmer** : chance de toucher réduite à la base, à la Visée prêtée (3) et à la distance ; ni lumière, ni météo, ni mouvement de la cible, ni blessures du PNJ.
- ⚠ **Décision à confirmer** : cadence unique d'un tir par seconde pour toutes les armes, rechargement en une boucle (chargeur) ou deux (cartouches libres), sans son de rechargement.
- ⚠ **Décision à confirmer** : pas de tir à travers une fenêtre (même ouverte ou cassée : `lineClear` ne les distingue pas) ni une porte vitrée fermée.
- ⚠ Éclair : constructeur `IsoLightSource.new` à 8 nombres (surcharge `int` attendue face à `IsoBuilding`) et lumière temporaire : à vérifier en jeu ; pas de flamme 3D au canon.
- ⚠ Rendu des clips de tir et de rechargement en boucle sur un corps de zombie : à voir en jeu. `MuzzleFlashModelKey`, douilles, enrayage, bruit de l'arme vide : non traités.
- Cible zombie (LK06-T04), tir depuis un véhicule, zones non-PvP : hors périmètre.

## Coup au sol (LK06-T09)

Ajout du 2026-10-12, pour l'offensive à la fenêtre ([defense.md](defense.md#offensive-à-la-fenêtre-lk06-t09)) : un zombie tombé à l'intérieur doit être achevé au sol, « comme le font les joueurs humains de Project Zomboid » (décision de l'utilisateur du 2026-10-12).

### Contraintes du moteur

- Une cible couchée n'est touchée que par une attaque au sol, une cible debout que par une attaque debout (`CombatManager.calcValidTargets`, filtre `isProne() && !attackingGround`, J/CombatManager.java:1578, 1688).
- Attaque au sol avec une arme : dégâts `x max(5, CriticalDamageMultiplier)` (J/characters/IsoGameCharacter.java:5817-5821) ; à mains nues c'est un **piétinement** (poussée visée au sol) : dégâts de base `Rand(0,7, 1,0) + Force x 0,2`, `x StompPower` des chaussures (`x 0,5` pieds nus), sans le `x 5` (J/CombatManager.java:868-872, StompPower 1,0 par défaut : J/scripting/objects/Item.java:392). La hausse dès le 4e coup et le `x 0,15` final de la mêlée s'appliquent aussi (J/characters/IsoGameCharacter.java:5709-5714, J/CombatManager.java:3237-3242).
- Le nœud d'attaque au sol du joueur pose `ZombieHitReaction=Floor` ; `processHit` la recopie sur la cible (`setHitReaction("Floor")`, J/CombatManager.java:2410, 2433-2436). Un zombie à terre qui la reçoit passe par `hitreaction-onfloor` (depuis `onground`) ou `hitreaction-gettingUp` (depuis `climbwindow`, à terre) puis `onground`, qui arme un nouveau délai de 30 à 89 images avant de se relever (`ZombieOnGroundState.startReanimateTimer`, actiongroups `zombie/onground`, `zombie/climbwindow`). Nos coups ne passent pas par `Hit` (dégâts appliqués par `Zombies.hurt`) : la réaction doit être posée à la main.
- Clips du joueur : `Bob_AttackFloorBat` (2HOnFloor) et `Bob_AttackFloor1Hand` (1HOnFloor) durent 1,0 s comme la frappe debout, impact à 25 % (hérité de 2HDefault, 1HDefault) ; `Bob_AttackFloorStamp` (StompDefault) dure 1,233 s, impact à 33 %.

### Choix

- `Combat.strikeGesture` : contre un zombie au sol (`isOnFloor`, non rampant : un rampant se frappe debout), geste `strikefloor` (nœuds `LKActorStrikeFloor2H`, `LKActorStrikeFloor1H` selon `Weapon`) avec une arme, `stomp` (`LKActorStomp`, vitesse 0,99 : une boucle de 1,25 s) à mains nues ; même ordre, même cadence, mêmes rapports et contrôles ; le client minute ces gestes comme `strike` (premier impact à 312 ms, 412 ms pour `stomp`).
- `Zombies.damageOf(…, floor)` : formules vanilla ci-dessus, Force prêtée `STRENGTH` = 5 et chaussures `STOMP_POWER` = 1,0 ; un coup est « au sol » si le zombie l'est au moment où l'autorité accepte la touche.
- Coup non mortel au sol : `setHitReaction("Floor")` sur la copie de l'autorité ; sur un serveur, champ `r = "Floor"` de `zombieHurt`, posé par le client qui simule le zombie (`LK_ZombiesClient.lua`).

### Tests

- Banc `tests/test_lk_window_kill.py` : geste selon l'arme et l'état du zombie (debout, rampant, au sol), retiré à la fin de l'engagement ; dégâts identiques aux formules vanilla (arme `x max(5, critique)`, piétinement, hausse du 4e coup, arme à feu inchangée) ; coups au sol minutés, appliqués une fois, réaction « Floor » à chaque coup non mortel, aucune réaction debout ; mort au sol ; MP : réaction posée chez le seul client qui simule le zombie.

### Points ouverts

- ⚠ **Décision à confirmer** : Force 5 et chaussures ordinaires prêtées à tous les PNJ pour le piétinement (chaussures réelles du corps non lues).
- ⚠ Rendu des clips au sol en boucle sur un corps de zombie, et pied du piétinement 100 ms après l'impact minuté si la boucle a commencé debout : à voir en jeu.

## Sons de la mêlée (LK06-T11)

Ajout du 2026-10-13, après un essai en jeu de l'utilisateur : « quand un PNJ frappe un zombie avec une arme de mêlée je n'entendais pas le bruit du coup porté ». Le tir jouait déjà le son de l'arme (`combatShot`) ; la mêlée ne jouait rien. Fait générique dans la base : `.claude/pz-knowledge/sounds-and-noise.md`, « Sons d'un coup de mêlée du joueur ».

### Contraintes du moteur

- **Élan** : l'événement d'animation `PlaySwingSound`, au début (`Start`) des nœuds de frappe `1HDefault`, `2HDefault` et des coups au sol `1HOnFloor`, `2HOnFloor` qui en héritent, joue le `SwingSound` de l'arme sur la machine du joueur local (`owner.playSound`, J/ai/states/SwipeStatePlayer.java:348-373) ; un client MP l'envoie aux autres par le paquet `PlaySound` (fmod/fmod/FMODSoundEmitter.java:380-398). Sans arme, l'attaque est une **poussée** : `AttackShove` debout, `AttackStomp` sur une cible au sol, joués à l'entrée de l'état (SwipeStatePlayer.java:212-223) ; le nœud `StompDefault` n'a pas de `PlaySwingSound`. `Base.BareHands` n'a pas de `SwingSound` dans son script (défaut `BaseballBatSwing`, J/scripting/objects/Item.java:133), inutilisé en pratique.
- **Impact** (J/CombatManager.java:723-790), joué par l'attaquant local pour chaque cible touchée, puis envoyé aux autres (`PlaySound` avec la surface `Body`) : l'élan en cours est d'abord arrêté (`stopSoundByName(SwingSound)`), puis attaque au sol : `HitFloorSound` du script (défaut `BatOnFloor`), sinon `HitSound` ; debout : `HitSound` (lu par `getZombieHitSound`, Item.java:1668, 1968-1972), **le même contre un zombie ou un joueur** ; aucun impact pour une poussée debout ni pour un coup critique de près au couteau. Coup manqué : élan seul.
- **Bruit pour les zombies** : aucun en mêlée vanilla (`SoundRadius` 0 des armes de mêlée, base `sounds-and-noise.md`) ; rien n'est ajouté.
- Le `HitSound` d'une arme peut valoir `null` (Item.java:1970-1972) : aucun impact.

### Choix

- **Élan local, sans message** : chaque machine qui connaît l'ordre de mêlée (client proche qui reçoit `combatState`, ou solo) et voit un geste de frappe (`strike`, `strikefloor`, `stomp`) sur une copie du corps joue l'élan au début de chaque boucle du clip (apparition du geste, puis toutes les `iv` ms), sur l'émetteur du corps (`playSoundImpl(nom, nil)`, local). Nom : champ `sw` de l'ordre diffusé (`Combat.swingSound` : `SwingSound` de l'arme, `AttackShove` à mains nues), `AttackStomp` pour le geste `stomp`. Coup manqué compris, comme le vanilla.
- **Impact relayé par l'autorité** : pour chaque touche **acceptée** (`Combat.onHit`), `Combat.meleeEffects` choisit le nom (`Combat.impactSound` : `HitFloorSound` pour `strikefloor`/`stomp`, sinon `HitSound`) et l'envoie une fois à chaque client proche (`combatMelee` { m = { k, npc, o, x, y, z, sw, hit } }, mêmes destinataires `Directives.targets` que `combatShot` ; appel direct de `View.onMelee` en solo). Le client le joue une seule fois par clé : élan arrêté (`stopSoundByName`), impact sur l'émetteur de la copie du corps ; depuis LK06-T13, rien quand le corps est mort, à terre, retiré ou absent ici (l'émetteur libre n'est plus utilisé pour la mêlée, section [Sons et mort du corps](#sons-et-mort-du-corps-lk06-t13)).
- ⚠ **Décision à confirmer** : à mains nues debout, impact `BareHandsHit` (`HitSound` de `Base.BareHands`) alors que la poussée vanilla n'en a pas : la frappe du PNJ blesse comme un coup, elle doit s'entendre (demande de l'utilisateur, « mains nues comprises »).
- ⚠ **Décision à confirmer** : élan joué localement d'après le geste vu (pas d'après la touche acceptée), pour l'entendre au bon moment et même quand le coup manque ; l'impact seul passe par l'autorité.

### Tests

- Banc `tests/test_lk_combat.py` (`MeleeSoundMultiplayerTests`, `MeleeSoundSoloTests`, doublures `MELEE_SCRIPTS` et `BODY_EMITTER` : surcharges `playSoundImpl(String, IsoObject)` à deux arguments, `stopSoundByName(String)`) : touche acceptée = un `combatMelee` par client proche, rien pour un client lointain ni pour une touche refusée, livraison répétée ignorée, élan arrêté puis impact sur la copie du corps, aucun son sur le serveur, aucun bruit ; noms tirés du script (batte, couteau, mains nues, arme sans `HitFloorSound`, arme sans `HitSound`), piétinement `AttackStomp` + `BareHandsHit` ; six secondes de frappes : un élan par boucle et un impact par touche chez A et B ; solo par appels directs. Échoue sur l'ancien code (5 tests sur 5).
- Suites en jeu : mesure `[LKM] measure melee sounds: …` dans `lk.melee` et `[LKX] measure melee sounds: …` dans `lk.windowkill` (impacts envoyés = touches ; en solo, impacts joués = touches, élans >= touches).

### Protocole en jeu

1. Solo, partie `rstest*` : `RST.run({ suite = "lk.melee", tags = "world" })` : élan (poussée) et coup entendus à chaque frappe ; ligne `[LKM] measure melee sounds: impacts sent N, played here: swings S, impacts N (last swing AttackShove, last impact BareHandsHit)`.
2. Dans une maison : `RST.run({ suite = "lk.windowkill", tags = "world" })` : coups de batte au sol entendus ; ligne `[LKX] measure melee sounds: … last impact BaseballBatHit`.
3. MP (séance finale) : `RST.server({ suite = "lk.melee", tags = "world" })`, deux clients près du PNJ : chacun entend chaque coup une fois.

### Points ouverts

- ⚠ Paramètre FMOD `MeleeHitSurface` (surface `Body`) non posé : le vanilla le règle sur le joueur attaquant (`setMeleeHitSurface`), sans équivalent sur un corps de zombie ; rendu de l'impact à vérifier à l'oreille.
- ⚠ Voix d'effort du joueur (`PlayerVoiceSound` `MeleeAttack`, `MeleeStomp`) non jouée : un PNJ reste muet en frappant.
- ⚠ Élan entendu sur les copies seulement quand le geste de frappe est reçu ; un client qui voit le corps sans recevoir l'ordre (hors `Directives.targets`) n'entend rien.

## Sons et mort du corps (LK06-T13)

Ajout du 2026-10-13, après un essai solo de l'utilisateur (`console.txt`, f:74138-74205) : un PNJ armé d'une machette frappe le joueur (`melee #18`, une touche à f:74160), le joueur le tue au marteau (f:74204) ; « le son du coup en mêlée s'est répété en boucle quand le corps est tombé au sol ». Fait générique dans la base : `.claude/pz-knowledge/sounds-and-noise.md`, « Émetteur d'un zombie mort ou retiré : jamais arrêté ».

### Contraintes du moteur

- L'émetteur d'un personnage (`IsoGameCharacter.emitter`, `CharacterSoundEmitter`) n'est avancé que par la mise à jour du personnage (`updateEmitter`, J/characters/IsoGameCharacter.java:1355-1368). À la mort d'un zombie, `IsoDeadBody` le fait avancer **une seule fois** (hors client MP, J/iso/objects/IsoDeadBody.java:358-361) ; ni `die`/`becomeCorpse` (IsoGameCharacter.java:13480-13541), ni `IsoZombie.removeFromWorld` (seul `BurningFlesh` arrêté, IsoZombie.java:3554-3580), ni le recyclage (voix seule : `IsoZombie.resetForReuse`, IsoZombie.java:3598-3601 ; VirtualZombieManager.java:128-133) n'arrêtent ses sons. `IsoObject.removeFromWorld` arrête `IsoObject.emitter`, un **autre** champ, nul pour un personnage (IsoObject.java:4220-4223, 229 ; IsoGameCharacter.java:457). Un joueur ou un animal retiré garde au contraire son émetteur avancé 5 s puis `stopAll` (IsoPlayer.java:1525-1540, AnimalPopulationManager.java:112-123) ; rien de tel pour un zombie.
- Un son lancé sur le corps juste avant la mort est donc abandonné : jamais suivi, jamais libéré, jamais arrêté par le moteur ; sur un client MP, un son encore en attente de départ (`toStart`) n'est même jamais lancé.
- `stopSoundByName(nom)` arrête l'instance FMOD sur-le-champ, sans avoir besoin d'un tick de l'émetteur, et sans paquet (fmod/fmod/FMODSoundEmitter.java:166-186, 1042-1052 ; CharacterSoundEmitter.java:327-332).

### Cause relevée

- Code (LK06-T11) : l'élan (`playSwing`) et l'impact (`View.onMelee`), comme le son d'un tir (`View.onShot`), étaient joués sur l'émetteur du corps sans jamais être arrêtés à sa mort (`LK_CombatClient.lua`, ancien `z:getEmitter():playSoundImpl(name, nil)` de `playSwing` et `em:playSoundImpl(e.hit, nil)` de `onMelee`) ; le seul arrêt était celui de l'élan à l'impact. Un impact reçu pour un corps déjà mort était rejoué sur un émetteur libre (`Anim.knownBodies` exclut les morts, donc branche « émetteur libre »).
- Solo, journal du constat : l'ordre de mêlée tombe une image après la mort (`melee #18 … ended … no body`, f:74205) et `pass` testait déjà `z:isDead()` : aucun élan n'a été **rejoué** par notre code dans ce cas (statiquement). La répétition entendue vient donc d'un son déjà lancé sur le corps et abandonné avec son émetteur ; le contenu de l'événement FMOD (boucle ou non) n'est pas lisible ici (banques FMOD) : **hypothèse** à confirmer par la suite en jeu.
- MP (statique) : la copie d'un client meurt à la réception de la mort (`DeadZombiePacket`) alors que l'ordre peut encore être connu (commandes non ordonnées) ; un impact envoyé avant la mort peut arriver après : rejoué sur un émetteur libre.

### Choix

- Élan et impact joués seulement sur un corps **vivant et debout**, connu de cette machine (`View.bodyAlive` : `not isDead()` et `not isOnFloor()`) ; un impact reçu pour un corps mort, à terre, retiré ou absent n'est joué nulle part (compteur `meleeNoBody`). Le tir garde son repli sur un émetteur libre quand le tireur est inconnu ici (un coup de feu s'entend de loin).
- Chaque son lancé sur l'émetteur d'un corps (élan, impact, coup de feu) est noté par PNJ (`View.bodySounds[id] = { z, names, t }`). Il est arrêté par son nom (`stopSoundByName`, local) : à la mort du corps sur cette machine (`OnZombieDead`, solo comme client MP), ou, en repli, au premier passage où l'objet n'est plus le corps vivant et debout connu du PNJ (mort, à terre, retiré, autre corps). Compteurs `bodySoundsStopped` (corps) et `bodySoundStops` (noms).
- Coup normal inchangé : sans mort, la note est oubliée `SOUND_HOLD_MS` (5 s) après le dernier son, sans rien arrêter.
- ⚠ **Décision à confirmer** : à la mort, l'impact en cours et le coup de feu en cours du PNJ sont coupés eux aussi (pas seulement l'élan), comme un émetteur vanilla vidé ; un tir et la mort à la même image sont rares.
- ⚠ **Décision à confirmer** : un corps à terre (renversé, vivant) ne fait entendre ni élan ni impact.

### Tests

- Banc `tests/test_lk_combat.py`, `DeathSoundSoloTests` et `DeathSoundMultiplayerTests` (doublure `BODY_EMITTER` complétée de `isPlaying(String)` ; un son n'y finit jamais seul, pire cas d'un émetteur abandonné) : mort pendant un élan (machette, chemin solo `Kill(arme, tueur)`) → élan arrêté à l'instant de la mort, aucun son pendant 4 s, rien ne joue plus sur le corps, impact tardif joué nulle part ; client MP dont la copie meurt avec l'ordre encore connu → élan et coup de feu arrêtés, aucun élan rejoué, impact tardif ignoré ; corps à terre sans élan ; frappes normales inchangées (seuls les arrêts vanilla de l'élan à l'impact). Sur l'ancien code : 4 échecs sur 4.
- Suite en jeu `lk.melee`, second test « npc killed during a swing » (solo) : mesure `[LKM] measure death during a swing (…)`.

### Protocole en jeu

1. Solo, partie `rstest*`, personnage debout dehors : `RST.run({ suite = "lk.melee", tags = "world" })`. Le second test arme le PNJ d'une machette, le tue juste après un élan et écoute 4 s : rien ne doit s'entendre pendant la chute. Ligne attendue : `[LKM] measure death during a swing (MacheteSwing, impact MacheteHit): playing at the death true, stopped at the death 1 (… name(s)), swing still playing false; in the next 4000 ms: swings played 0, impacts played 0, body emitter playing swing false, impact false`.
2. MP (séance finale) : deux clients près d'un PNJ qui frappe, le tuer pendant sa frappe ; aucun son de mêlée après la chute chez les deux clients.

### Points ouverts

- ⚠ Cri d'alerte (`LK_AlertView.lua`) et voix vanilla d'un corps : non concernés (voix coupées par `LK_ZombieGuard`), non modifiés.
- ⚠ La nature exacte du son répété (événement FMOD qui boucle, ou autre) reste à confirmer par la suite en jeu.
