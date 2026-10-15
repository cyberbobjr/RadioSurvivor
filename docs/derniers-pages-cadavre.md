# Dernières pages : où poser le document d'un mort (E15-T02)

Investigation pour l'étape E15 (« Les dernières pages ») : **quand** l'inventaire du corps d'un joueur existe côté serveur après sa mort, et **comment** y mettre un objet que tous les clients voient. Le document lui-même (texte, `addPage`, `setLockedBy`) est E15-T03.

- Java décompilé **42.21.0** (`<decompiled>\42.21.0\java`), relu le 2026-10-12. Statut : **confirmé statiquement** ; logique vérifiée au banc (`tests/test_lastpages_corpse.py`, doublures) ; **non mesuré en jeu** (suite `rs.lastpages.corpse` et protocole manuel plus bas).
- Fait générique versé dans la base : `.claude/pz-knowledge/multiplayer.md`, « Mort d'un joueur : inventaire et cadavre côté serveur ».

## Conclusion

1. **`OnCharacterDeath` part avant le cadavre, sur toutes les machines.** Sur l'autorité (solo, serveur dédié, serveur d'un hôte), le cadavre n'existe pas encore pendant l'événement. Le mort a **encore son inventaire**, et ce conteneur deviendra celui du cadavre.
2. **Méthode retenue, à la mort** : sur l'autorité, dans `OnCharacterDeath`, ajouter l'objet à `joueur:getInventory()` (`AddItem`). Aucun envoi réseau n'est nécessaire : le paquet de mort `PlayerDeath`, construit juste après avec le cadavre, porte l'inventaire du cadavre serveur à chaque client à portée. Le client du mort lui-même remplace son inventaire par celui du serveur. Hors de portée, le cadavre est sauvegardé avec son conteneur et chargé avec la case.
3. **Méthode retenue, plus tard** (texte du LLM arrivé après la mort) : retrouver le cadavre sur sa case, puis `body:getContainer():AddItem(objet)` et `sendAddItemToContainer(conteneur, objet)` sur le serveur. Le conteneur du cadavre a pour parent l'`IsoDeadBody`, et l'envoi part à tous les clients à portée de la case.
4. **Repli** : poser l'objet au sol à côté du corps, `case:AddWorldInventoryItem(objet, dx, dy, 0, true)` (objet préparé, transmis). À utiliser quand le mort brûle (son cadavre brûle avec son contenu, pas un objet au sol), quand le cadavre a disparu (relevé en zombie, porté, retiré) ou quand il est introuvable.
5. **Ne rien ajouter côté client** : chez un client MP, `OnCharacterDeath` est déclenché aussi (cadavre créé à réception du paquet), mais un objet ajouté là n'existe que sur cette machine.

## Preuves (42.21.0)

### Ordre sur l'autorité

| Étape | Code |
|---|---|
| `die()` : `Kill` d'abord si la mort n'est pas encore traitée ; sur un serveur, objets **en main** posés au sol (`dropHeldItems`), puis `becomeCorpse()` ; client MP : rien, il attend le paquet. | `zombie/characters/IsoGameCharacter.java:13480-13501` |
| `Kill` → `onKilled` (une seule fois, `isOnKillDone`). | `IsoGameCharacter.java:13463-13475` |
| `IsoPlayer.onKilled` → `DoDeath` → `OnDeath` → `triggerEvent("OnCharacterDeath", this)`. | `zombie/characters/IsoPlayer.java:7736-7754`, `IsoGameCharacter.java:1813-1815, 4603-4604` |
| `IsoPlayer.OnDeath` sort aussitôt sur un serveur (`OnPlayerDeath` jamais sur un dédié). | `IsoPlayer.java:6094-6110` |
| `becomeCorpse()` : `new IsoDeadBody(this)` une seule fois, puis les écouteurs de mort. | `IsoGameCharacter.java:13536-13542` |
| Qui appelle `die()` pour un joueur sur le serveur : coup mortel (`hitConsequences`), personnage mort hors de sa case (`update`), état au sol. | `IsoGameCharacter.java:5836-5842, 8185-8188`, `zombie/ai/states/PlayerOnGroundState.java:33-35` |

En solo, `Kill` peut venir plus tôt (coup, chute, réaction) et `die()` à une mise à jour suivante : l'ordre est le même, avec un délai possible entre l'événement et le cadavre. Aucun chemin ne crée le cadavre avant `onKilled` (`die`, `dieNetwork`, `becomeCorpseItem` appellent tous `Kill` d'abord).

### Ce que prend le cadavre

| Fait | Code |
|---|---|
| Le cadavre prend **le même objet** `ItemContainer` (`setContainer(died.getInventory())`), puis les objets portés et accrochés ; le mort reçoit un inventaire neuf et vide. | `zombie/iso/objects/IsoDeadBody.java:327-333` |
| `setContainer` fait du cadavre le parent du conteneur. | `zombie/iso/IsoObject.java:1883-1886` |
| Conteneur marqué exploré pour un joueur : aucune table de butin ne le remplit. | `IsoDeadBody.java:336-339` |
| Sur un serveur, `player` est posé pour un mort `IsoPlayer` (`isPlayer()` vrai). | `IsoDeadBody.java:368-375, 2110-2112` |
| ModData du mort copiées sur le cadavre (`LuaManager.copyTable`) : une marque posée pendant `OnCharacterDeath` suit le cadavre. | `IsoDeadBody.java:378` |
| Mort en feu : feu allumé sur la case du cadavre (hors client, si `FireSpread`), conteneur marqué exploré. | `IsoDeadBody.java:392-399` |
| `OnContainerUpdate` et `OnDeadBodySpawn` ne partent **pas** sur un serveur : aucun événement Lua serveur pour « cadavre créé ». | `IsoDeadBody.java:401-407` |
| Joueur qui doit se relever : `reanimateLater()` sur le cadavre ; son inventaire suit le zombie jusqu'au cadavre suivant (base, `zombies-as-npc-bodies.md`). | `IsoPlayer.java:7756-7759`, `IsoDeadBody.java:1754-1756` |

### Envoi aux clients

| Fait | Code |
|---|---|
| Écouteur de mort du joueur, sur un serveur : `GameServer.sendCharacterDeath(body)`. | `IsoPlayer.java:550, 7756-7765` |
| `PlayerDeath` envoyé aux connexions à portée de la position du cadavre. | `zombie/network/GameServer.java:2934-2942`, `zombie/network/packets/INetworkPacket.java:174-181` |
| Envoi synchrone (`setData` puis écriture) : l'inventaire écrit est celui du cadavre à cet instant. | `INetworkPacket.java:127-138` |
| `DeadPlayerPacket` ajoute l'inventaire du cadavre (`writeInventory` : conteneur, portés, accrochés par index). | `zombie/network/packets/character/DeadPlayerPacket.java:19-28`, `IsoDeadBody.java:2345-2375` |
| Client : inventaire de sa copie vidé puis relu depuis le paquet, puis `dieNetwork` (donc `OnCharacterDeath` chez lui) crée son cadavre avec le même `ObjectID`. | `DeadCharacterPacket.java:108-147, 155-174` |

### Ajout après coup et repli au sol

| Fait | Code |
|---|---|
| `sendAddItemToContainer` (global Lua) n'agit que sur un serveur. | `zombie/Lua/LuaManager.java:9701-9705` |
| Conteneur dont le parent n'est pas un joueur : `AddInventoryItemToContainer` envoyé aux connexions à portée du parent. | `GameServer.java:2239-2247` |
| Le conteneur d'un cadavre est désigné par sa case et son **rang** dans `getStaticMovingObjects()` (comme le paquet de mort). | `zombie/network/fields/ContainerID.java:164-172`, `DeadCharacterPacket.java:64` |
| Objet préparé posé au sol avec transmission : `AddWorldInventoryItem(InventoryItem, x, y, h, transmit)`. | `zombie/iso/IsoGridSquare.java:5200-5205` (base, `world-placement.md`) |

## Conséquences pour E15-T03 (proposition, à confirmer)

Le texte du LLM n'est pas prêt pendant `OnCharacterDeath` (pont asynchrone). Option la plus simple et la plus proche du vanilla :

1. Pendant `OnCharacterDeath` (serveur ou solo, joueur seulement) : noter la case de la mort, le jeton de la mort et `isOnFire()` ; poser le jeton dans la ModData du joueur (recopié sur le cadavre, ligne 378). Ce jeton n'est pas un secret.
2. Texte prêt (ou journal de secours) : chercher sur la case notée, et ses voisines, un `IsoDeadBody` dont la ModData porte le jeton ; y ajouter le document puis `sendAddItemToContainer`.
3. Sinon (mort en feu, cadavre absent, relevé ou porté) : poser le document au sol sur la case notée (`AddWorldInventoryItem(..., true)`), après avoir écrit ses pages et son nom (un objet transmis n'est plus modifiable pour les clients, base `world-placement.md`).
4. Case non chargée sur le serveur : attendre son chargement (placement différé, base `world-placement.md`) ; ce cas reste à coder en E15-T03.

Variante non retenue : mettre un document vide dans l'inventaire à la mort et l'écrire plus tard. Les pages ajoutées ensuite au serveur devraient être renvoyées aux clients, et aucun envoi vanilla de pages n'a été vérifié (hypothèse, non étudiée).

## Suite en jeu et protocole

Suite `rs.lastpages.corpse` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RS_LastPagesCorpse.lua`, étiquettes `world` et `server`, sauvegarde `rstest*`) :

- **Écart documenté** : tuer le joueur de test dans une suite n'est pas raisonnable. Le test automatique prend un cadavre créé par `RandomizedWorldBase.createRandomDeadBody` (cadavre de zombie, `isPlayer()` faux, déjà créé). Il prouve l'ajout après coup (méthode 3) et le repli au sol, pas l'ajout à la mort.
- Commandes : solo `RST.run({ suite = "rs.lastpages.corpse", tags = "world" })` ; serveur dédié, depuis un client admin, `RST.server({ suite = "rs.lastpages.corpse", tags = "world" })`. Résultat attendu : 3 PASS.

Protocole sur une vraie mort (méthode 2), serveur dédié `rstest*`, deux clients A (admin) et B :

1. A : `RST.server({ suite = "rs.lastpages.corpse.arm", tags = "manual" })` (1 PASS, ligne serveur `[RST] lastpages armed …`).
2. A meurt (zombies, chute…), sans être en feu. Console serveur : `[RST] lastpages witness … inventory true, added true, … corpses already on the square 0`.
3. B ouvre le cadavre de A : une feuille « RST corpse witness … » s'y trouve. A, après sa réapparition, la voit aussi. Déconnexion puis reconnexion de B : elle y est encore.
4. A : `RST.server({ suite = "rs.lastpages.corpse.check", tags = "manual" })` : 1 PASS (cadavre trouvé près de la case notée avec la feuille, `isPlayer true`).
5. Solo (facultatif) : `RST.run({ suite = "rs.lastpages.corpse.arm", tags = "manual" })`, mourir, puis lancer `RST.run({ suite = "rs.lastpages.corpse.check", tags = "manual" })` depuis la console Lua (mode debug) avant de quitter la partie.

## Limites

- Rien n'a été mesuré en jeu. Le banc ne prouve que la logique de la suite sur des doublures qui reproduisent l'ordre lu dans le Java.
- Hôte : le jeu héberge par un serveur (`GameServer.server`), le même code que le dédié. **Déduit**, non vérifié.
- Le rang du cadavre dans `getStaticMovingObjects()` doit être le même sur le serveur et le client (même contrainte que le paquet de mort vanilla, `NetworkCharacterAI.onDied`). S'il diffère, un ajout après coup peut viser un autre cadavre de la case.
- Un objet en main du mort est posé au sol par le serveur (`dropHeldItems`), pas dans le cadavre : ne jamais mettre le document en main.
