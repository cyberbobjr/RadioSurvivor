# Troc direct avec un groupe ami

- Tâche : LK11-T08 (création) ; s'appuie sur LK11-T03 (attitude, [attitude.md](attitude.md)), LK08-T06 et LK08-T07 (stock réel et seuils, [stock.md](stock.md)), LK11-T06 (modèle de demande et de remise, [aide.md](aide.md)) ; barème commun avec le passeur de l'Ohio (E13, [passeur-table.md](../../specifications-techniques/passeur-table.md), validé le 2026-10-10)
- Code : `media/lua/server/LivingKnox/LK_Trade.lua` (`LivingKnox.Trade`, autorité), fenêtre et menu `media/lua/client/LivingKnox/LK_TradeView.lua` (`LivingKnox.TradeView`, client MP et solo), barème partagé `media/lua/shared/RadioSurvivor/RS_TradeValues.lua` (rendu par `require "RadioSurvivor/RS_TradeValues"`), conteneurs du foyer par `Stock.homeContainers` (`LK_Stock.lua`), textes `Translate/EN|FR/IG_UI.json` (`IGUI_LK_Trade_*`) ; banc `tests/test_lk_trade.py` ; suite en jeu `lk.trade` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKTrade.lua`)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\`, Lua vanilla **M/** = `media/lua`) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement

Décision du 2026-10-08 (LK11-T01) : avec un groupe ami, un joueur troque directement contre des objets de son stock réel. Aucune ligne de Bandits! ni de Project A-Life n'a été lue.

## Problème

Un joueur propose des objets de son inventaire contre des objets du stock réel d'un groupe. Le groupe juge l'échange (valeur, besoins, attitude) ; s'il l'accepte, chaque objet change de côté exactement une fois, sans création ni perte, même si le joueur se déconnecte ou si deux joueurs visent le même objet. Le groupe ne cède pas ce qui lui manque.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| En MP, l'inventaire d'un joueur vu par le serveur est tenu à jour par les transactions Java ; un objet garde son identifiant d'un conteneur à l'autre. | `J/core/Transaction.java:258-262` ; base `world-placement.md` (« suivre un objet précis par son identifiant ») | confirmé statiquement |
| Retirer un objet de l'inventaire d'un joueur côté serveur : `DoRemoveItem` puis `sendRemoveItemFromContainer` (paquet au seul joueur) ; d'un meuble : même appel, paquet aux clients proches. | `J/inventory/ItemContainer.java:1944-2027`, `J/network/GameServer.java:2269-2277` ; base `multiplayer.md` | confirmé statiquement |
| `isEquipped(objet)` = porté ou en main ; un objet accroché (ceinture, dos) se teste par `isAttachedItem`. | `J/characters/IsoGameCharacter.java:9420-9432` ; base `multiplayer.md` | confirmé statiquement |
| Remettre un objet comme le vanilla : `AddItem`, `sendAddItemToContainer` ; trop lourd : au sol, `AddWorldInventoryItem(objet, x, y, h, true)`. | `M/shared/ActionManager.lua:4-24` ; `J/iso/IsoGridSquare.java:5200-5266` | confirmé statiquement |
| Un serveur MP ne traduit pas les textes des mods : réplique envoyée en clé. | base `api-42-21.md` | confirmé statiquement |
| Arguments de `sendServerCommand`/`sendClientCommand` : tables imbriquées de nombres et de textes admises ; livrés sans ordre garanti. | base `multiplayer.md` | confirmé statiquement |

## Choix (2026-10-12)

### Barème (partagé avec E13)

`RS_TradeValues.lua` reprend la table validée (`docs/specifications-techniques/passeur-table.md`) : `VALUES["Base.X"] = { v, k, cond, cap, lot }`, classes `valuables`, `images`, `papers`, `military`, `supply`, `food`, `medical`, `ammo`. Fonctions : `entry`, `isBase`, `value(type, catégorie)`, `linePrice(v, n, k)` = ⌈V × n × k⌉ (tolérance 1e-9 : 10 × 1,1 n'arrondit pas à 12), `askTotal(lignes, k)` (groupé par type), `giveTotal(valeurs)` = ⌊Σ⌋. Le même fichier est chargé par le serveur et par la fenêtre : les totaux affichés sont ceux du serveur.

**Valeur de repli (décision à confirmer)** : un objet des catégories du stock réel absent du barème (biscuits, bouteille d'eau, matériaux) prend `FALLBACK` de sa catégorie (données de script : `DisplayCategory`, fluide) : nourriture 2, eau 2, soins 1, matériaux 1 ; munitions en vrac : 0. Le barème ne couvrait ni l'eau ni les matériaux, que les kits des groupes contiennent.

### Règles du groupe

| Règle | Détail | Refus |
|---|---|---|
| Attitude | `Hostility.get(gid, clé)` : confiant ou favorable, marge 0,10 ; prudent, marge 0,30 ; méfiant ou hostile : pas de troc (`CFG.MARGIN`, section 5 du barème : « ami 0,10, neutre 0,30 »). | `attitude` |
| Ce que le groupe prend | Objet de premier niveau de l'inventaire principal, module `Base`, ni porté, ni en main, ni accroché, ni favori (`worn`), sac vide ; classe hors `valuables`, `images`, `papers` (aucun débouché pour un groupe) ; état minimal `cond` du barème ; nourriture et eau consommables (`Stock.consumable`). | `unwanted`, `worn` |
| Valeur reçue | V × multiplicateur de besoin de sa catégorie de stock : niveau du barème = 60 × have / want (la réserve visée de LK08-T07 correspond à `NEED_TARGET` = 60) ; sous 25 : × 1,5 ; sous 60 : × 1 ; sous 100 : × 0,5 ; au-delà : 0 (refusé, « réserve pleine »). Objet hors catégories (piles, alcool, matériel militaire) : × 1. Total arrondi au point inférieur. | `unwanted` |
| Ce que le groupe cède | Objets des catégories du stock (valeur > 0, consommables pour la nourriture et l'eau) de tous les conteneurs du foyer ; et objets du barème hors catégories posés dans les conteneurs du groupe (caisse, tentes) : ce qu'un joueur y a laissé se rachète. L'offre ne montre que le surplus de chaque catégorie au-dessus de sa réserve visée. | — |
| Ne pas céder ce qui manque | Pour chaque catégorie d'où le groupe cède : have − cédés + reçus ≥ want (réserve visée de LK08-T07, règle du don LK11-T06). **Décision à confirmer** : le barème disait « sous `NEED_OK` = 40 » sur l'échelle abstraite ; la règle retenue (réserve visée, 60) est plus prudente et identique au don. | `short` |
| Prix | ⌈V × quantité × (1 + marge)⌉ par type ; accepté si valeur reçue ≥ prix ; l'écart reste au groupe (décision E13-T01 (5)). | `price` |
| Présence | Chaque identifiant relu au moment de la proposition (inventaire du joueur, conteneurs du foyer relus, écarts hors écran appliqués d'abord). | `gone` |
| Foyer | Référence absente, zone illisible, aucun conteneur, registre non écrit. | `away` |
| Listes | Identifiants entiers, sans doublon, `MAX_LINES` = 24 au plus de chaque côté, aucun côté vide. | `empty` |

### Application (une seule transaction serveur)

`Trade.propose` évalue (`Trade.evaluate`, lecture seule) puis applique (`Trade.apply`) dans le **même appel Lua** : aucun paquet, aucune action ni aucun autre code du jeu ne s'exécute entre la vérification de présence et le déplacement. Ordre d'écriture :

1. **Registre des groupes** (une écriture) : objets cédés ôtés de la référence du stock, entrée `trade` au journal du groupe (`trade with <clé>: got <types>; gave <types> (<valeur> for <prix>)`). Écriture refusée : refus `away`, rien n'a bougé.
2. **Objets du joueur**, un par un : `DoRemoveItem` de son inventaire (+ `sendRemoveItemFromContainer`), puis `AddItem` dans la caisse du groupe (premier conteneur posé par LK_Homes, sinon le premier du foyer) (+ `sendAddItemToContainer`). D'abord eux : le poids du joueur baisse avant qu'il reçoive.
3. **Objets du groupe**, un par un : retirés de leur meuble, remis au joueur (inventaire ; trop chargé : au sol à ses pieds).
4. **Relecture** `Stock.check(gid, { force = true })` : les objets reçus entrent dans la référence comme des dépôts ; rationnement relu.

Un seul objet est en transit à la fois. Un déplacement qui lève une erreur remet l'objet dans son conteneur d'origine (compté `failed`, journalisé). Pourquoi la référence d'abord, sans les objets reçus : si un déplacement n'a pas lieu, un objet cédé resté dans son meuble est relu comme un ajout, et un objet du joueur resté chez lui n'est attendu nulle part : **jamais un vol compté à tort, jamais un objet en double**. Écrire la référence après aurait fait relire l'objet cédé, retrouvé chez le joueur, comme un vol.

Fait publié `tradeDone` ([api-living-knox.md](../../specifications-techniques/api-living-knox.md)) ; réplique du PNJ `IGUI_LK_Trade_Done` (bande `friendly`) ou `IGUI_LK_Trade_Refuse_<raison>` (bande de l'attitude), clé traduite par chaque client.

### Déconnexion, doublons, deux joueurs

- La proposition est traitée à sa réception, joueur présent ; un paquet d'un joueur déjà parti n'arrive à aucun abonné Lua (le banc le livre sans joueur : rien ne bouge). Un joueur qui part après le traitement a ses objets dans son inventaire côté serveur, sauvegardé avec lui ; la réponse est seulement perdue.
- Double envoi de la même proposition : le second voit les objets partis, refus `gone`.
- Deux joueurs qui demandent le même objet : le premier traité l'obtient, l'autre reçoit `gone` ; chacun reçoit une offre à jour.

### Fenêtre et menu (client)

- Menu « Troquer » quand un corps de PNJ connu ici est près de la case cliquée et du joueur (même repérage que « Demander de l'aide », `LivingKnox.RelationsView.bodyNear`) ; sondage manette : `setTest()` seulement. Option offerte sur tout PNJ : le client ne connaît pas l'attitude (E09-T01), le serveur refuse avec une réplique.
- Fenêtre `LKTradeWindow` (`ISCollapsableWindow`) : à gauche les objets du joueur que le groupe prendrait et leur valeur pour lui, à droite les objets cédés (V) ; clic = cocher ; totaux « vous donnez / vous demandez » par le barème partagé (k de l'offre) ; boutons « Proposer l'échange » et « Actualiser » ; ligne d'état = réplique du PNJ ou attente.
- Transport : `tradeRequest { op = open | propose, n, npc, give, take }` → `tradeReply { op, n, npc, ok, reason, detail, item, line, offer, given, asked, ground, failed }` au seul demandeur ; solo : `LivingKnox.Trade.request` appelé directement (attente posée avant l'appel). Une réponse d'un numéro dépassé est ignorée.
- Contrôles du serveur (`Trade.request`) : opération connue, numéro entier, PNJ membre d'un groupe, corps présent, joueur vivant à `RANGE` = 4 cases au plus, même niveau ; sans identité de carnet : réplique `stranger`. Requête invalide ou trop loin : réponse sans réplique (« Trop loin pour troquer »).
- Divulgation : l'offre envoyée au joueur montre ce que le groupe cède et ses prix (donc la marge). Elle part à lui seul, à portée du PNJ ; la référence complète du stock reste au serveur.

## Alternatives écartées

- **Transfert par actions chronométrées du joueur** (`ISInventoryTransferAction` vers et depuis la caisse) : le serveur ne voit pas ces transactions en Lua ; la prise serait relue comme un vol et l'échange ne serait plus atomique.
- **Créer la contrepartie** (objets neufs) : interdit, l'objet sort du stock réel.
- **Session d'offre gardée par le serveur** (prix figés à l'ouverture) : plus d'état à purger à la déconnexion ; la réévaluation complète à la proposition donne le même résultat, au pire un refus motivé si les besoins ont changé.
- **Sacs du joueur ouverts** : le contenu d'un sac compterait avec lui ; seul le premier niveau de l'inventaire principal compte (comme le passeur, sac déposé au premier niveau).
- **Seuil `NEED_OK` = 40 du barème pour céder** : voir « Ne pas céder ce qui manque ».

## Tests

- Banc lupa `tests/test_lk_trade.py` (30 tests) : barème (valeurs de la table validée, objets présents dans les scripts vanilla 42.21, arrondis, repli) ; multiplicateur de besoin ; offre (surplus seulement, objets refusés absents) ; troc accepté : chaque objet une seule fois (conteneurs, inventaires, sol), référence = contenu réel, relecture sans perte ni vol, journal, fait, réplique ; double envoi `gone` ; rachat depuis la caisse ; refus `price`, `short` (et réserve compensée par un objet reçu), `unwanted` (bijou, objet du mod, réserve pleine, sac non vide, matériel usé), `worn` (porté, favori), `attitude`, `gone`, `empty`, `away` ; registre non écrit : rien ne bouge ; déplacement en erreur : objet remis ; joueur trop chargé : au sol ; contrôles de `request` ; menu, coche, totaux, proposition par la fenêtre ; MP : deux clients sur le même objet (un seul l'obtient, 5 retraits et 5 ajouts envoyés), déconnexion avant traitement (rien), après traitement (objets chez le joueur côté serveur), joueur trop loin ; traductions EN/FR Latin-1 ; code ASCII ; suite `lk.trade` qui passe et qui échoue sur un objet dupliqué injecté.
- En jeu : `RST.run({ suite = "lk.trade", tags = "world" })` debout dans une maison (solo) ; serveur dédié : `RST.server({ suite = "lk.trade", tags = "world" })`.

### Protocole en jeu

1. Solo (`rstest-solo`, mod de dev, Living Knox activé), debout dans une maison : `RST.run({ suite = "lk.trade", tags = "world" })` → PASS.
2. Solo, près d'un PNJ de colons incarné (carnet lié) avec des piles dans l'inventaire : clic droit sur le PNJ → « Troquer » : la fenêtre liste les piles et le surplus du groupe ; cocher 3 piles et 2 conserves → « Proposer l'échange » : « Marché conclu », conserves dans l'inventaire, piles dans la caisse du foyer, deux conserves de moins.
3. MP (séance finale) : A et B ouvrent la fenêtre, cochent la même conserve et proposent : un seul l'obtient, l'autre lit « Ce n'est plus là » ; A se déconnecte juste après « Proposer » puis revient : ses objets sont cohérents (soit l'échange entier, soit rien).

## Limites et restes

- ⚠ À vérifier en jeu : fenêtre (mise en page, listes, coche au clic), objets visibles chez le client MP après l'échange, réplique.
- Aucun effet sur l'attitude (un échange honnête ne fait pas monter la confiance) : hors périmètre, à décider avec le calibrage de LK11-T03.
- Le groupe ne cède que ce que la relecture voit : objets de premier niveau des conteneurs du foyer ; les objets hors catégories ne se vendent que depuis ses propres conteneurs.
- Pas de point d'entrée du LLM du carnet (même raison que pour l'aide : le pont n'admet pas d'intention de troc).
- Les plafonds par passage (`cap`) et les conditions nominatives des papiers servent au passeur (E13) ; ils ne sont pas appliqués aux groupes.
- Décisions à confirmer : valeurs de repli, seuil de cession à la réserve visée, marges par niveau (prudent admis à 0,30), échelle du multiplicateur (réserve visée = 60), sacs du joueur non ouverts, menu sur tout PNJ.
