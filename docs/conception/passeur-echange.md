# Échange sans contact sur la berge

- Tâche : E13-T04 (échange sans contact sur la berge) ; s'appuie sur E13-T03 ([passeur-rendezvous.md](passeur-rendezvous.md) : passage réservé, barque arrivée au signal), E13-T02 ([passeur-offre.md](passeur-offre.md) : offre figée, `Trade.close`), E13-T01 (table validée [passeur-table.md](../passeur-table.md), décisions du 2026-10-08 et du 2026-10-10), E13-T05 (journal du dehors), E04-T01 (faits de réputation enregistrés, non appliqués)
- Code : `media/lua/server/RadioSurvivor/RS_TradeExchange.lua` (sondage, évaluation, application) ; `RS_Trade.lua` (`Trade.finishRun`) ; `RS_TradeRun.lua` (`Run.say`, textes de repli) ; traductions `IGUI_RS_TradeRun_Done`, `_Cheated`, `_Cancel_nodrop`, `IGUI_RS_Event_trade_cheated` (EN, FR) ; banc `tests/test_rs_trade_exchange.py` ; suite en jeu `rs.trade_exchange`
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\`) — Date : 2026-10-13 — Statut : brouillon, testé hors jeu seulement

## Problème

Le joueur dépose un sac au lieu convenu et s'éloigne ; le serveur vérifie le contenu contre l'offre, retire les objets, pose la contrepartie au même endroit ; tricherie (contenu insuffisant) = échange refusé et réputation en baisse. Acceptation : aucun doublon d'objets ; contrepartie posée une seule fois même si le joueur revient pendant l'échange.

## Contraintes

| Fait | Preuve | Statut |
|---|---|---|
| Un objet lâché au sol n'a pas d'événement fiable : sonder les cases côté serveur (`getWorldObjects`). | base `world-placement.md` (« Objet posé au sol par le joueur ») | confirmé statiquement |
| Un sac posé au sol est un `IsoWorldInventoryObject` ; son conteneur se modifie par `DoRemoveItem` / `AddItem`, et `sendRemoveItemFromContainer` / `sendAddItemToContainer` l'envoient aux clients proches du sac (`container.inventoryContainer.getWorldItem()`). | `J/network/GameServer.java:2239-2247, 2269-2277`, `J/Lua/LuaManager.java:9701-9741` ; base `multiplayer.md` | confirmé statiquement |
| Le contenu d'un chunk n'est écrit qu'au déchargement de sa cellule ou à une sauvegarde complète, jamais au milieu d'un appel Lua. | base `world-placement.md` (« registre en fichier », « ordre d'une image ») | confirmé statiquement |
| Un papier nominatif porte un nom affiché différent du nom du script ; le nom du script est traduit sur la machine qui le lit (`Item.displayName = Translator.getItemNameFromFullType`). | `J/scripting/objects/Item.java:3777`, `J/inventory/InventoryItem.java:2943, 4768-4774` ; base `api-42-21.md` | confirmé statiquement |
| `getUnequippedWeight` = poids propre + contenu (fluide, contenu d'un sac). | `J/inventory/InventoryItem.java:3160-3162`, `InventoryContainer.java:253` | confirmé statiquement |
| La réputation réelle n'a pas d'API : un fait est enregistré non appliqué (`RS_Reputation.record`). | `RS_Reputation.lua`, décision E04-T01 | confirmé (code) |

## Choix (2026-10-13)

### Déroulement

1. **Barque au ponton** : passage `arrived` (signal vu, E13-T03). Avant le signal, rien n'est sondé.
2. **Sac déposé** : tout sac (`InventoryContainer`) posé au sol dans un carré de 7 × 7 cases centré sur le ponton (`Trade.PIER`, rayon 3), étage 0.
3. **Personne à moins de 20 cases** du ponton (tout joueur vivant, quelle que soit son équipe) et case du ponton chargée : le passeur accoste. Sondage à chaque minute de jeu (`EveryOneMinute`), seulement tant que la barque attend.
4. **Évaluation** de chaque sac, puis choix du sac qui vaut le plus (un seul sac échangé) :
   - premier niveau du sac seulement ; un **portefeuille** compte avec son contenu (un niveau de plus) et part entier (les objets sans valeur qu'il contient partent avec lui) ; les autres contenants ne sont pas ouverts (un coffret à bijoux vaut 0 et reste) ;
   - barème `RS_TradeValues` des quatre classes que le passeur prend (argent et bijoux, images, papiers, matériel militaire) ; objets hors `Base`, objets portant une ModData de ce mod (clés `RS_…`, `RadioSurvivor…`, `LK…`), objets non listés : 0, laissés ;
   - conditions de la table : état ≥ 50 % (`getCondition / getConditionMax`) pour l'arme, les vêtements, les masques et l'outil ; filtre à moitié plein (`getCurrentUsesFloat`) ; sac ALICE vide ; papiers **nominatifs** (nom affiché ≠ nom du script, sans le « Prénom Nom » d'un joueur en ligne) sauf le portefeuille ; billets par **lots entiers de 10**, 100 billets au plus ;
   - plafonds : par type (`cap` de la table), par classe (60 / 40 / 30 / 60 points), 10 pièces de papiers, 120 points, 20 kg ;
   - le passeur prend **dans l'ordre du sac, jusqu'à couvrir le prix** de l'offre figée du passage ; le dépassement du dernier objet pris reste au passeur (décision E13-T01 (5)) ; le reste demeure dans le sac.
5. **Assez** : en **un seul appel Lua** : objets pris retirés du sac (`DoRemoveItem` + `sendRemoveItemFromContainer`), contrepartie de l'offre créée dans le **même sac** (`instanceItem`, journal du dehors par `RS_OutsideNewsServer.create(passage)`), chaque objet marqué `RS_TradeGiven` = révision de l'offre (`AddItem` + `sendAddItemToContainer`), passage clos `done` (`Trade.finishRun` → `Trade.close` : quantités vendues) et état privé écrit aussitôt (`RS_State.save`). Annonce « Done » sur la fréquence de la voix.
6. **Pas assez** (sac de valeur positive mais sous le prix) : **tricherie**. Rien n'est pris ni donné, passage clos `cheated` (marge du passeur au plus haut pour cet appelant, 0,50), fait de réputation `trade.cheated` (−5, `Config.Reputation.failure`) enregistré non appliqué au personnage du carnet de l'appelant ; annonce « Cheated ».
7. **Sac sans rien que le passeur prenne** : ignoré, pas de tricherie.
8. **Personne n'a rien laissé** 2 heures de jeu après l'arrivée : le passeur repart, passage annulé `no_drop` (réserve rendue, aucune baisse de réputation) ; annonce « Cancel_nodrop ». Si la zone n'est pas chargée à ce moment, même issue : le sac éventuel reste intact.

### Aucun doublon, contrepartie une seule fois

- Le joueur ne peut pas agir pendant l'échange : il est à plus de 20 cases (aucune action de transfert possible sur le sac) et l'échange tient dans un appel Lua.
- Une fois le passage clos (`done`, `cheated`, `cancelled`), il n'est plus sondé : un joueur qui revient, un second sondage ou un autre sac ne déclenchent rien.
- Reprise : si un sac de la zone contient déjà un objet marqué de la révision du passage (échange appliqué au monde, état non écrit), le passage est clos `done` (raison `recovered`) **sans rien reposer**, même joueur présent. L'état est écrit dans le même appel que l'application ; un chunk n'est jamais sauvegardé au milieu d'un appel Lua, donc ce cas ne survient que si l'écriture de l'état échoue.
- État revenu en arrière sans le monde (impossible en pratique, sauvegarde du monde plus ancienne que l'état) : le joueur garde ses objets et ne reçoit rien ; jamais de doublon.
- Les marques restent sur la contrepartie : le passeur ne reprend jamais ce qu'il a vendu (règle « objet portant une ModData du mod »).

### État

`S.data.trade.run` (E13-T03) reçoit `reason` (`done`, `recovered`, `cheated`, `no_drop`, `no_offer`), `exchange = { value, price, took, given, bag }` et `endedAt`. Fait de tricherie : `S.data.outcomes["trade-<rév>-cheated"]` (format de `RS_Reputation.record`, affiché « non appliqué » dans l'onglet Réputation du carnet, clé `IGUI_RS_Event_trade_cheated`).

## Alternatives écartées

- **Prendre tout ce qui a de la valeur** (l'écart entier au passeur) : lecture trop dure de la décision E13-T01 (5) ; prendre jusqu'au prix laisse « l'écart non compensé » du dernier objet seulement.
- **Contrepartie posée au sol à côté du sac** : la décision demande l'endroit exact du sac ; la poser dans le sac garde tout au même point et se ramasse d'un geste.
- **Retirer le sac entier et en reposer un autre** : perdrait le sac du joueur et les objets sans valeur, contraire à « laissé sur la berge ».
- **Délai de traversée après le départ du joueur** : ouvrirait une fenêtre pendant laquelle il pourrait revenir ; l'échange immédiat en un appel est plus sûr.
- **Sac sans valeur = tricherie** : un vieux sac oublié au ponton punirait le joueur à tort.

## Décisions à confirmer

1. Le passeur prend dans l'ordre du sac jusqu'à couvrir le prix (pas tout ce qui a de la valeur).
2. Contrepartie mise **dans le sac** du joueur, marquée par la révision de l'offre (marque gardée).
3. Distances et délais : zone de dépôt 7 × 7 autour du ponton ; personne (toutes équipes) à moins de 20 cases ; attente 2 heures de jeu après l'arrivée ; sondage chaque minute de jeu.
4. Un seul sac échangé (le plus riche) ; sac sans valeur ignoré, pas une tricherie ; aucune baisse de réputation sans sac.
5. Portefeuille pris entier ; autres contenants non ouverts.
6. Tricherie : fait de réputation −5 (valeur d'un échec de mission) non appliqué, et marge du passeur à 0,50 (mémoire E13-T02) ; annonce à la radio des trois issues.
7. Papiers au nom d'un joueur : seuls les joueurs **en ligne** sont reconnus.

## Tests

- Banc `tests/test_rs_trade_exchange.py` (18 tests) : barème et conditions (état, filtre, sac vide, papiers nominatifs et nom d'un joueur, ModData du mod, hors `Base`, billets par lots, plafond de billets), portefeuille compté et pris entier, plafonds par type, classe, pièces, points et kilos, prise limitée au prix ; échange fait une fois (joueur proche = attente, envois exacts, contrepartie marquée, offre et affaire `done`, stock vendu, annonce, joueur revenu et sondages suivants sans effet, nouvelle offre `run_over`) ; joueur d'une autre équipe qui bloque ; tricherie (rien bougé, marge 0,50, fait non appliqué, annonce) ; sac sans valeur ignoré puis départ `no_drop` (réserve rendue) ; zone non chargée ; sac hors zone ; meilleur sac ; reprise par la marque sans rien reposer ; journal du dehors en contrepartie ; passage réservé non échangé avant le signal ; traductions et replis ; code ASCII ; suite en jeu compilée.
- En jeu : suite `rs.trade_exchange` (autorité, partie `rstest*`) : `RST.run({ suite = "rs.trade_exchange", tags = "world" })` en solo, `RST.server({ suite = "rs.trade_exchange", tags = "world" })` sur un serveur dédié.

## Limites et restes

- Rien d'essayé en jeu ; en MP, l'envoi du retrait et de l'ajout aux clients proches du sac et la relecture par un client éloigné restent à voir.
- Un joueur qui part au-delà de la zone chargée du ponton (environ 60 cases sur un serveur) avant le passage du passeur fait échouer l'échange (`no_drop`) : son sac reste intact.
- Le sondage chaque minute de jeu peut manquer un joueur très rapide qui traverse la couronne de 20 cases.
- Les objets sans valeur d'un portefeuille partent avec lui.
- L'échange et la tricherie ne sont pas consignés dans la chronique (E14) ; la réputation réelle attend E04-T03.
