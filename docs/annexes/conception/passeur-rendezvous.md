# Passage de la semaine : réservation et rendez-vous du passeur

- Tâche : E13-T03 (réservation hebdomadaire et rendez-vous) ; s'appuie sur E13-T02 ([passeur-offre.md](passeur-offre.md) : livre, offre figée), E13-T01 (décisions du 2026-10-08 : toujours le même ponton ; table validée [passeur-table.md](../../specifications-techniques/passeur-table.md) : cordon 1 / 1,25 / 1,5), E09-T03 (identifiant d'équipe `RS_Factions.idOf`), E11-T07 (Signal Smoke, mod requis depuis le 2026-10-15)
- Code : `media/lua/server/RadioSurvivor/RS_Trade.lua` (réservation, rendez-vous, cordon, état) ; `media/lua/server/RadioSurvivor/RS_TradeRun.lua` (règles de la nuit, signal, annonces, repère) ; traductions `IGUI_RS_TradeRun_*` (EN, FR) ; pont `bridge/radio_bridge.py` (`trade_run`, `trade_run_lines`) ; fiche `personas/gus.txt` ; banc `tests/test_rs_trade_run.py` ; suite en jeu `rs.trade_run`
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\`) — Date : 2026-10-13 — Statut : brouillon, testé hors jeu seulement

## Problème

Un passage par semaine de jeu pour tout le serveur, réservé à la radio par une équipe ; rendez-vous de nuit au ponton choisi ; signal convenu (fusée rouge Signal Smoke ou lampe) ; annulation par patrouille, orage ou retard selon des règles serveur. Acceptation : une seule réservation par passage ; annulation annoncée à la radio.

## Contraintes

| Fait | Preuve | Statut |
|---|---|---|
| Ponton de Riverside : `floors_interior_tilesandwood_01_40` x 6041-6042, y 5215-5220, eau juste à l'ouest ; bassin ouest de l'Ohio. | base `knox-geography.md` (« L'Ohio en deux bassins ») | confirmé statiquement |
| L'état allumé d'un objet en main est connu du serveur : `syncItemActivated` (menu, raccourcis, équipement) envoie `SyncItemActivatedPacket`, que le serveur applique à l'objet de l'inventaire principal du joueur. | `J/network/packets/SyncItemActivatedPacket.java:78-96`, `client/ISUI/ISInventoryPaneContextMenu.lua:2880-2885` | confirmé statiquement |
| `isEmittingLight()` : force lumineuse positive, usages restants d'un consommable, activé si activable. | `J/inventory/InventoryItem.java:2804-2817` | confirmé statiquement |
| Hélicoptère vanilla reconnu sur l'autorité par `OnWorldSound` (source `nil`, étage 0, rayon et volume 500). | base `staging-effects.md` | confirmé statiquement |
| Orage ou tempête tropicale en cours : `getClimateManager():getIsThunderStorming()`, lu sur l'autorité. | base `api-42-21.md` | confirmé statiquement |
| Nuit noire en juillet vers 1 h – 3 h seulement. | base `staging-effects.md` | confirmé statiquement |
| Une ligne radio n'est pas traduite par le client : le serveur compose le texte dans sa langue (traductions des mods rechargées une fois sur un serveur MP). | `RadioSurvivor_Server.lua` (`callText`), base `api-42-21.md` | confirmé (banc) |

## Choix (2026-10-13)

### Réservation

- **Réservée par la première offre figée** du passage (action `propose_trade` jugée par `RS_Actions`) : l'offre est l'accord, le passage est pris pour l'**équipe** de l'appelant (`RS_Factions.idOf` : faction vanilla, sinon équipe personnelle ; sans état privé ni joueur en ligne : `caller:<compte>`). Pas d'action nouvelle (catalogue du pont et des fiches inchangé).
- Ensuite : une autre équipe est refusée `booked` ; une offre de la même équipe (même d'un autre membre) remplace celle du passage ; passage annulé, fait (`Trade.close`, E13-T04) ou trop tard dans la semaine : `run_over`. Un passage annulé n'est **pas** remis en jeu dans la semaine.
- Un seul passage gardé : `S.data.trade.run = { passage, team, key, caller, cid, rev, state, bookedAt, start, voice, khz, reason, signal, arrivedAt, endedAt }`, état privé (jamais en ModData globale). États : `booked`, `arrived`, puis `cancelled`, `done`, `cheated`.
- Appel direct de `Trade.propose` sans équipe (bancs, outils) : aucune réservation, comportement d'E13-T02.

### Rendez-vous

- **Ponton de Riverside** (6041, 5217, étage 0), le même à chaque passage (décision E13-T01) ; décrit au LLM sans chiffre (« the old wooden pier on the river at the west end of Riverside »).
- **Nuit** : de 01:00 à 03:00 heure du jeu, la première nuit au moins 6 heures de jeu après la réservation, et dans la semaine du passage (sinon pas de réservation possible). 03:00 est l'heure où Gus reprend l'écoute.
- À la réservation, le ponton est **marqué sur la carte de l'appelant** (`RS_MapMarks.give`, libellé traduit « Ponton du passeur », ligne « mark » de son historique radio). Les autres membres l'apprennent à la radio.
- Le LLM ne reçoit le lieu, la nuit et le signal **que pour l'équipe qui a réservé** (`trade=`, champ `run`) ; une autre équipe apprend seulement que le passage est pris ; tous les auditeurs de la fréquence entendent pourtant la réponse (risque assumé, comme en vanilla).

### Signal

- Pendant la fenêtre, un **membre de l'équipe à 15 cases au plus du ponton** et : une **lampe allumée tenue en main** (`isEmittingLight`, sondage toutes les 10 minutes de jeu), ou une **fusée ou fumée rouge** de Signal Smoke allumée à 15 cases du ponton (événement `started`, mod requis). La barque arrive : `state = arrived` (suite : échange sans contact, E13-T04).

### Annulations (règles du serveur)

À chaque `EveryTenMinutes`, pour un passage attendu (`booked`), dès 00:00 (une heure avant la fenêtre, pour que l'annonce précède le départ) :

| Règle | Condition | Clé de l'annonce |
|---|---|---|
| Patrouille | tirage du passage (0 à 99, reproductible) sous 5 / 15 / 30 selon le cordon (calme / patrouilles / serré) | `IGUI_RS_TradeRun_Cancel_patrol` |
| Hélicoptère | hélicoptère vanilla entendu depuis 22:00 la veille de la fenêtre | `..._helicopter` |
| Orage | `getIsThunderStorming()` | `..._storm` |
| Retard | fenêtre finie sans signal | `..._late` |

- **Annonce** : `Trade.cancelRun` (offre du passage close `cancelled`, réserve rendue) puis trois lignes (`<fzzt>`, texte, `<szzt>`) sur la fréquence actuelle de la voix qui a pris la réservation (`RS_RadioServer.air`), texte traduit dans la langue de l'autorité, repli anglais. Voix silencieuse ou retirée : journal seulement. Un retard constaté plus de 2 heures après la fin de la fenêtre (serveur arrêté) n'est pas annoncé.
- Une fois la barque arrivée, plus d'annulation (E13-T04 décide de la suite).

### Cordon

- Tiré par passage (60 % calme 1,0 ; 30 % patrouilles 1,25 ; 10 % serré 1,5), reproductible (graine du livre). Le premier hélicoptère vanilla entendu dans le passage le monte d'un cran (`setCordon`). Les offres déjà figées gardent leur prix.

### Fiche de Gus

`actions=say,propose_trade` (décision 5 d'E13-T02) ; la « Business rule » renvoie au livre : prix, stock et passage n'en viennent que ; lieu, nuit et signal donnés seulement à l'équipe qui a réservé, sans rien inventer ; sans livre, aucun prix ni rendez-vous.

## Alternatives écartées

- **Action `book_run` séparée** : un nouveau type dans les catalogues du pont, des fiches et du serveur, et une réservation possible sans affaire. La première offre suffit.
- **Lieu choisi par le LLM** : contraire à la décision « toujours le même ponton ».
- **Annonce écrite par le LLM** : une demande au pont de plus à un moment où la voix n'écoute pas ; le texte fixe traduit est sûr et immédiat.
- **Brandenburg** : même bassin, mais plus à l'écart des villes du centre de la carte.

## Décisions à confirmer

1. Réservation = première offre figée d'une équipe (pas d'action dédiée) ; un passage annulé n'est pas remis en jeu dans la semaine.
2. Ponton de Riverside plutôt que celui de Brandenburg.
3. Fenêtre 01:00-03:00, au moins 6 heures après la réservation, dans la semaine du passage.
4. Probabilités : cordon 60/30/10 % ; patrouille 5/15/30 % selon le cordon ; hélicoptère depuis 22:00 ; rayon du signal 15 cases ; tout signal rouge de Signal Smoke (fusée ou fumée).
5. Annonce en texte fixe traduit (pas le LLM), sur la fréquence de la voix ; retard ancien non annoncé.
6. Repère du ponton envoyé au seul appelant qui réserve.

## Tests

- Banc `tests/test_rs_trade_run.py` (22 tests) : fenêtre de nuit (01:00, ≥ 6 h, dans la semaine) sur 1 600 heures ; cordon tiré reproductible et réparti ; une réservation par passage (refus `booked`, autre membre de la même équipe, passage suivant libre) ; `run_over` après annulation ou en fin de semaine ; échange fait = passage fini ; contexte par équipe relu par le pont et prompt (lieu seulement pour l'équipe, aucune coordonnée) ; livre mal formé ignoré ; orage, patrouille (selon le cordon), hélicoptère (cordon monté une fois, annulation près de la nuit), retard annoncés une fois sur la fréquence, retard ancien muet, voix hors antenne ; lampe d'un membre au ponton pendant la fenêtre seulement ; fusée rouge Signal Smoke ; traductions EN/FR et repli ; code ASCII ; suite en jeu compilée ; fiche de Gus.
- Banc `tests/test_rs_trade.py` (E13-T02) inchangé dans ses attentes (cordon du passage 1 fixé à 1 dans son `setUp`).
- En jeu : suite `rs.trade_run` (autorité, partie `rstest*`) : `RST.run({ suite = "rs.trade_run", tags = "world" })`.

## Limites et restes

- Rien d'essayé en jeu ; le multijoueur (deux équipes, annonce entendue, lampe d'un client) reste à valider.
- La lampe est sondée toutes les 10 minutes de jeu : un signal de moins de 10 minutes peut être manqué.
- Un passage non signalé n'abaisse pas la réputation ; la tricherie est E13-T04.
- Le passage annulé n'est pas consigné dans la chronique (E14) ; le journal du dehors n'est pas encore remis (E13-T04).
