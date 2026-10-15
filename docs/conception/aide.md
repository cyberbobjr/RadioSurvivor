# Demandes d'aide à un groupe

- Tâche : LK11-T06 (création) ; s'appuie sur LK11-T03 (attitude, [attitude.md](attitude.md)), LK08-T06 et LK08-T07 (stock réel et seuils, [stock.md](stock.md)), LK11-T04 (répliques, [parole.md](parole.md)) ; servira LK11-T05 (vengeance, même module) et le dialogue du carnet (intention d'aide, voir « Point d'entrée du carnet »)
- Code : `media/lua/server/LivingKnox/LK_Relations.lua` (`LivingKnox.Relations`, autorité), menu `media/lua/client/LivingKnox/LK_RelationsView.lua` (`LivingKnox.RelationsView`, client MP et solo), retrait par `Stock.takeItem` (`LK_Stock.lua`), textes `Translate/EN|FR/IG_UI.json` (`IGUI_LK_Aid_*`) ; banc `tests/test_lk_aid.py` ; suite en jeu `lk.aid` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKAid.lua`)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\`, Lua vanilla **M/** = `media/lua`) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement

Idée de jeu : I5.3 ([idees-bandits-alife.md](../idees-bandits-alife.md)). Aucune ligne de Bandits! ni de Project A-Life n'a été lue. Décision du 2026-10-08 (LK11-T01) : avec un groupe ami, un joueur peut demander de l'aide.

## Problème

Un joueur doit pouvoir demander de la nourriture, de l'eau ou de quoi se soigner à un groupe. Le groupe décide selon ce qu'il pense du joueur et ce qu'il possède vraiment ; l'objet donné sort du stock réel (jamais créé), une seule fois, et arrive chez le joueur. Tous les membres savent ce qui a été décidé. Le texte du joueur n'est jamais interprété (règle absolue : aucune liste de mots).

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Donner un objet à un personnage, à la manière vanilla : `inv:AddItem(objet)`, si le poids dépasse `getEffectiveCapacity(personnage)` l'objet est retiré et posé au sol, sinon `sendAddItemToContainer(inv, objet)`. | `M/shared/ActionManager.lua:4-24` (`Actions.addOrDropItem`) ; base `api-42-21.md` | confirmé statiquement |
| `IsoGridSquare.AddWorldInventoryItem(objet, x, y, h, transmit)` crée l'objet au sol et, sur un serveur avec `transmit`, l'envoie aux clients (`transmitCompleteItemToClients`). | `J/iso/IsoGridSquare.java:5200-5266` | confirmé statiquement |
| Un objet retiré d'un meuble par le serveur part aux clients proches par `sendRemoveItemFromContainer`. | `J/network/GameServer.java:2269-2277` (cité par [stock.md](stock.md)) | confirmé statiquement |
| Un serveur MP ne traduit pas les textes des mods : la réplique part en clé, traduite par chaque client. | base `api-42-21.md` ; [parole.md](parole.md) | confirmé statiquement |
| Menu contextuel du monde : `OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)` ; sondage manette = `ISWorldObjectContextMenu.setTest()` sans rien ajouter. | `M/client/ISUI/ISWorldObjectContextMenu.lua:122-128, 213` ; base `quest-building-blocks.md` | confirmé statiquement |

## Choix (2026-10-12)

### API (autorité)

`LivingKnox.Relations.requestAid(gid, playerKey, kind, opts)` ; `kind` ∈ `food`, `water`, `care` (catégories du stock `food`, `water`, `medical`) ; `opts.player` = destinataire (sinon retrouvé par sa clé parmi les joueurs en ligne ou locaux), `opts.npc` = membre qui répond (facultatif). Rend `{ accepted, reason, decided, kind, item = { i, t, k }, where = "inventory" | "ground", line, said, wait, detail }`, ou `nil` et une raison pour une entrée invalide (genre inconnu, clé mal formée, groupe inconnu, PNJ d'un autre groupe, aucun destinataire) : rien n'est alors décidé ni dit.

Décision, dans l'ordre :

| Étape | Règle | Refus |
|---|---|---|
| Période | Une demande au plus **par groupe** et par période de `AID.PERIOD_HOURS` = 24 h de jeu, tous joueurs confondus. Marque `aid = { h = heure de jeu, k = genre }` du groupe dans le registre privé (champ facultatif, contrôlé par `LK_Relations`, ignoré par `LK_Groups`) ; marque invalide ou venue du futur : ignorée. | `again` (rien n'est écrit) |
| Attitude | Niveau de `LivingKnox.Hostility.get(gid, clé)` dans `AID.LEVELS` : `favorable` ou `trusting`. Colons : départ favorable ; neutres : prudent ; pillards : hostile. | `attitude` |
| Stock | Le groupe ne donne pas ce qui lui manque (seuils de LK08-T07) : il faut `have - 1 >= want` dans la catégorie (`Stock.needs`), c'est-à-dire garder sa réserve visée après le don ; puis un objet donnable dans les conteneurs du foyer, relus maintenant (nourriture et eau : `Stock.consumable` ; soins : tout objet `medical`). | `short` |
| Foyer | Référence absente ou zone du foyer illisible : le groupe n'a pas ses réserves sous la main. | `away` (rien n'est écrit, période non consommée) |

Les refus `attitude` et `short` et l'acceptation sont des **décisions** : la période est consommée, une entrée `aid` est écrite au journal du groupe (`aid food given to <clé>: Base.TinnedBeans`, `aid water refused to <clé>: short (have 3, keep 3)`, `aid food refused to <clé>: attitude wary`) et le fait interne `aidDecided` est publié (`{ group, player, kind, accepted, reason, item, where, npc, day }`, [api.md](../api.md)). Le journal du groupe est la mémoire commune de ses membres.

### Retrait et remise

- Retrait par `Stock.takeItem(gid, pred, qui, usage, apply)` : objet retiré du meuble (`DoRemoveItem`, `sendRemoveItemFromContainer` sur un serveur), ôté de la référence et marque de période posée par `apply` **dans la même écriture du registre** ; `takeItem` rend aussi l'objet retiré. La relecture suivante ne le voit ni perdu ni volé (même s'il est retrouvé chez le joueur). Nourriture et eau : rationnement relu aussitôt (`Stock.updateRation`).
- Remise du **même objet** (même identifiant) : inventaire du joueur comme `Actions.addOrDropItem` (`sendAddItemToContainer` sur un serveur) ; joueur trop chargé ou absent : au sol au pied du PNJ qui répond, sinon du joueur (`AddWorldInventoryItem(objet, 0.5, 0.5, 0, true)`). Aucun objet n'est créé.

### Réplique

Le PNJ `opts.npc` répond par `LivingKnox.Speech.say(npc, { key }, { player, band, chat = false })` : `IGUI_LK_Aid_Given_<genre>` (bande `friendly`) ou `IGUI_LK_Aid_Refuse_<raison>` (`attitude`, `short`, `again`, `away`, `stranger` ; bande de l'attitude). Clé traduite par chaque client (EN, FR, Latin-1). Sans corps ou sans auditeur, la décision tient quand même (seule la bulle manque).

### Point d'entrée du joueur : menu contextuel

- `LK_RelationsView.fill` (abonné à `OnFillWorldObjectContextMenu`) : option « Demander de l'aide » avec sous-choix nourriture, eau, soins, quand un corps de PNJ connu ici (`LivingKnox.Anim.knownBodies`) se tient à 1,5 case au plus d'une case cliquée et à 4 cases au plus du joueur, au même niveau. Sondage manette : `setTest()` seulement.
- Le client ne connaît pas l'attitude (serveur seulement, E09-T01) : l'option est proposée sur **tout** PNJ et le refus est motivé par la réplique. Décision à confirmer (le contrat parle d'un « PNJ ami »).
- Envoi : commande `aidRequest { npc, kind }` (module `LivingKnox`) en MP ; appel direct de `Relations.ask` en solo (même machine, comme `LK_AdminView`).
- Contrôles du serveur (`Relations.ask`) : genre connu, PNJ membre d'un groupe, corps présent, joueur vivant à `AID.RANGE` = 4 cases au plus, même niveau ; joueur sans identité de carnet : réplique `stranger`, rien n'est décidé.

### Point d'entrée du carnet (LLM)

Le chemin d'intentions existe (intention `accept` d'E17-T09, revérifiée par le serveur), mais le pont n'admet que `none`, `offer` et `accept` (`bridge/npc_protocol.py:313`, `RS_Carnet_Server.lua:389`) et ce dossier n'est pas modifiable dans cette tâche. Le branchement se fera ainsi : le pont admet une intention fermée `aid` avec `kind` ∈ `food`, `water`, `care`, sans jamais lire la phrase du joueur lui-même ; `RS_Carnet_Server` la revérifie (même PNJ, même personnage, joueur à portée) puis appelle `LivingKnox.Relations.requestAid(gid, clé du carnet, kind, { npc })` une fois ; la réponse du LLM est remplacée ou complétée par la réplique du serveur si la décision diffère. Reste à faire (pont et serveur du carnet).

## Alternatives écartées

- **Une demande par groupe ET par joueur** : plus généreux en MP, mais le texte de la tâche dit « par groupe » ; un groupe qui donne à chaque joueur d'un serveur nombreux se viderait. À revoir si l'essai MP le juge trop strict.
- **Ne compter que les dons dans la période** : un joueur pourrait réessayer chaque genre à la chaîne après un refus ; un refus est aussi une réponse du groupe.
- **Seuil plus souple pour un joueur « confiant »** (donner sous la réserve visée) : plus de règles pour un même résultat au départ ; à reconsidérer au calibrage.
- **Créer l'objet donné** : interdit (objets créés de rien, section « Écarté » des idées) ; l'objet sort du stock réel.
- **Transfert par action chronométrée du joueur** (`ISInventoryTransferAction` depuis la caisse) : c'est le joueur qui prendrait, et la relecture y verrait un vol ; le serveur décide et remet lui-même.

## Tests

- Banc lupa `tests/test_lk_aid.py` (20 tests) : don retiré une seule fois du stock (référence et conteneurs), arrivé dans l'inventaire du joueur, relecture suivante sans perte ni vol ; journal du groupe, fait publié, réplique ; une demande par groupe et par période (autre joueur compris), admise après 24 h ; refus « short » (eau à sa réserve visée, rien de donnable) ; refus « attitude » après des vols ; rationnement relu ; joueur trop chargé : au sol au pied du PNJ (et envoyé aux clients en MP) ; foyer illisible : « away » sans consommer la période ; entrées invalides sans effet ; joueur retrouvé par sa clé ; menu (trois sous-choix, rien loin du corps ou du joueur, sondage manette, choix appliqué en solo) ; MP : commande d'un client, objet chez lui seul, un envoi d'ajout et un de retrait, refus « again » pour le second client ; traductions EN/FR Latin-1 ; code ASCII ; suite `lk.aid` qui passe et qui échoue sur un double don injecté.
- En jeu, solo : `RST.run({ suite = "lk.aid", tags = "world" })` debout dans une maison (groupe de colons d'un membre, nourriture donnée une fois, refus « again », refus « short » des soins avec des seuils relevés). Serveur dédié : `RST.server({ suite = "lk.aid", tags = "world" })`.

### Protocole en jeu

1. Solo (`rstest-solo`, mod de dev, Living Knox activé), debout dans une maison : `RST.run({ suite = "lk.aid", tags = "world" })` → PASS.
2. Solo, près d'un PNJ de colons incarné (carnet lié : personnage créé) : clic droit sur le PNJ → « Demander de l'aide » → « De la nourriture » : bulle « Tiens, prends ça… », une conserve dans l'inventaire, une de moins dans la caisse du foyer ; redemander « De l'eau » : « On a déjà donné… » ; console `LivingKnox.Groups.get("grp-<n>").log` : entrée `aid`.
3. MP (séance finale) : A demande, l'objet n'arrive que chez A (B le voit dans la caisse en moins) ; B demande dans la même période : refus « again ».

## Limites et restes

- ⚠ À vérifier en jeu : option du menu au clic sur le corps (case cliquée proche du corps), objet visible dans l'inventaire du client MP, objet au sol visible des clients, bulle de réponse.
- Point d'entrée du LLM non branché (pont non modifiable ici) : voir « Point d'entrée du carnet ».
- Aucun effet sur l'attitude du joueur qui reçoit (ni gratitude attendue, ni dette) ; aucun fait d'attitude n'existe pour un don du groupe.
- Le fait `aidDecided` n'est pas relayé en événement public (`LK_API`) : à ajouter si un consommateur en a besoin.
- Les refus `again`, `away`, `stranger` ne sont pas journalisés dans le journal du groupe (journal du moteur seulement).
- Un arrêt brutal entre le retrait et la remise perd l'objet (comme tout objet en transit) ; une erreur de remise est journalisée (`taken but not delivered`).
- Seuils à confirmer : période de 24 h par groupe, niveaux favorable et confiant, garde de la réserve visée (au départ, un groupe de colons de 4 membres est en rationnement strict et ne donne ni nourriture ni eau : seuls les soins sont possibles), portée de 4 cases.
