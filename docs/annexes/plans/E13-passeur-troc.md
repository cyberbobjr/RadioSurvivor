# E13 — Le passeur de l'Ohio (troc)

**Objectif.** Un contrebandier de la rive de l'Indiana, joué par le LLM, négocie à la radio dans les bornes d'une table serveur, traverse une fois par semaine de jeu et échange sans contact sur une berge (note de travail §09).

**Dépend de.** E05 (voix), E07-T01 (actions) ; E11-T07 pour le signal (facultatif).

**Sources.** Note de travail §09 et §10 (points techniques du troc) ; base `knox-geography.md` (l'Ohio en deux bassins, pont Clark Memorial, quais ; pontons de Riverside vers 6041,5215 et de Brandenburg vers 1631,5576) ; base `world-placement.md` (objet préparé posé au sol, objet lâché par le joueur) ; base `loot-distributions.md` (repérer les objets par catégorie).

## Décisions

- Acquises : un seul passeur pour le serveur ; un passage par semaine de jeu, réservé à la radio ; quatre catégories prises (argent et bijoux, images, papiers des morts, matériel militaire) ; apports : piles, antibiotiques, munitions de chasse, graines, cigarettes, alcool, café, pièces radio, journaux récents ; prix et stocks dans une table serveur ; échange sans contact ; risques (patrouille, hélicoptère, orage, retard) ; réputation en baisse en cas de tricherie.
- 2026-10-08 — **E13-T01 (1)** : lieu = **toujours le même ponton** (à choisir en `E13-T03` parmi les quais relevés dans `.claude/pz-knowledge/knox-geography.md`).
- 2026-10-08 — **E13-T01 (2)** : contrepartie déposée à l'endroit exact du sac laissé par le joueur.
- 2026-10-08 — **E13-T01 (3)** : pas de monnaie : valeur par objet, barème commun avec le troc des groupes Living Knox (`LK11-T08`).
- 2026-10-10 — **E13-T01 (4)** : table de valeurs `docs/specifications-techniques/passeur-table.md` **validée telle quelle** (valeurs en points, marge selon la réputation, multiplicateur du cordon et de la rareté, plafonds par passage, barème commun avec les groupes Living Knox `LK11-T08`).
- 2026-10-10 — **E13-T01 (5)** : l'écart non compensé d'un échange **reste au passeur** (ni crédit, ni appoint).
- 2026-10-10 — **E13-T01 (6)** : le passeur **accepte les armes militaires** (M16 20 points, un par passage ; boîte de 5.56 8 points) dans le plafond du matériel militaire.
- 2026-10-10 — **E13-T01 (7)** : « journaux récents » = **document propre au mod** (`printMedia`, nouvelles du dehors renouvelées à chaque passage) : tâche `E13-T05`.
- 2026-10-14 — **E13-T02** : passage = semaine de jeu ; livre par appelant (pas par équipe) ; marge plancher 0,25 − 0,05 par affaire (plancher 0,10, 0,50 après tricherie) faute d'API de réputation ; plafonds 120 points, 8 lignes, 99 par ligne ; activation sur Gus reportée à E13-T03 ; nouvelles du dehors non envoyées au passeur (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E13-T03** : ponton de Riverside, fenêtre 01:00-03:00 (confirmé par l'utilisateur) ; réservation par la première offre figée (aucune action nouvelle) ; 6 h après la réservation ; valeurs (cordon, patrouille, hélicoptère, 15 cases, tout signal rouge) ; annonce en texte fixe ; repère au seul appelant (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E13-T04** : prise jusqu'au prix ; contrepartie dans le sac du joueur, marque laissée ; zone 7 x 7, 20 cases, 2 h ; un seul sac ; portefeuille entier ; tricherie −5 (non appliqué) et marge 0,50, annonces en texte fixe ; joueurs en ligne seulement pour les papiers (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E13-T05** : journal du dehors en gabarits fixes plutôt que texte du LLM (confirmé par l'utilisateur) ; numéro d'édition = numéro du passage ; date = jour de création ; commande de test globale ; nouvelles non transmises au contexte du passeur (avec E13-T02) (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **E13-T01** — Valeurs, objets et lieu de l'échange
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier ; `docs/specifications-techniques/passeur-table.md`
  - Faire : lieu, contrepartie et monnaie tranchés le 2026-10-08 (section Décisions) ; reste à proposer la table (objets vanilla 42.21 par catégorie, valeur, stocks par passage) commune avec `LK11-T08`, puis la faire valider.
  - Questions : La table de valeurs proposée convient-elle ? Options : la valider telle quelle [recommandé] / ajuster certaines valeurs / réduire le catalogue.
  - Accepté si : table validée et consignée.
  - Tests : —
  - Preuve : table `docs/specifications-techniques/passeur-table.md` (objets vanilla 42.21 vérifiés dans les scripts) validée par l’utilisateur le 2026-10-10 ; questions ouvertes tranchées (section Décisions : écart au passeur, armes acceptées avec plafond, journal du dehors = E13-T05)
  - Reste : —

- [x] **E13-T02** — Table serveur et action `propose_trade`
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E13-T01
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Trade.lua` ; pont ; contrat
  - Faire : le LLM ne propose qu'à l'intérieur des fourchettes et des stocks ; le serveur fige l'offre (révision) ; mémoire des affaires passées ; refus possible.
  - Accepté si : aucune offre hors table acceptée ; stocks jamais négatifs.
  - Tests : banc `lupa`.
  - Preuve : banc `tests/test_rs_trade.py` du 2026-10-13 (23 tests OK, chaîne complète dans le serveur radio solo) : livre du passeur `RS_Trade.lua` : stock du passage tiré dans les fourchettes de la table validée (Park-Miller, graine en état privé), passage = semaine de jeu ; action `propose_trade` (`items` « Nom:quantité,… » 64 caractères, `margin` facultative) ; prix calculé par le serveur ⌈V × q × (1+marge) × M⌉ (cordon × rareté borné à 1,75, exemples de la table retrouvés) ; refus `not_in_stock`, `over_stock`, `bad_margin`, `over_weight` (10 kg), `over_cap` (120 points), `bad_params` ; offre figée (révision, quantités réservées, remplacée par la suivante, expirée au passage suivant) ; mémoire des 8 dernières affaires (marge plancher) ; contexte `trade=` (RSV2) pour une voix qui autorise l'action ; pont : validation, prompt « Your trade book », contrôle de forme ; luacheck 16/0 ; conception `passeur-offre.md` ; base `api-42-21.md` (poids d'un objet à fluide)
  - Reste : cible hors jeu ; premier essai avec E13-T03 (action activée sur Gus) : console `trade: offer N frozen…`, prix exact cité à l'appel suivant. Non chargé dans la VM Kahlua réelle du banc ; comportement réel du LLM non mesuré ; contrat `protocole-carnet-v2.md` complété au commit de fin de nuit.

- [x] **E13-T03** — Réservation hebdomadaire et rendez-vous
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E13-T02
  - Fichiers : `RS_Trade.lua`
  - Faire : un passage par semaine de jeu pour tout le serveur, réservé à la radio par une équipe ; rendez-vous de nuit au lieu choisi ; signal convenu (fusée rouge Signal Smoke ou lampe) ; annulation par patrouille, orage ou retard selon des règles serveur.
  - Accepté si : une seule réservation par passage ; annulation annoncée à la radio.
  - Tests : banc `lupa` ; suite en jeu.
  - Preuve : banc `tests/test_rs_trade_run.py` du 2026-10-13 (22 tests OK), `test_rs_trade` 23, `test_personas` 20, `test_personas_server` 106 OK : la première offre figée de la semaine réserve le passage pour l'équipe de l'appelant (`RS_Factions.idOf`, une réservation par passage, état privé), autre équipe refusée `booked`, `run_over` après annulation ou échange ; rendez-vous au ponton de Riverside (6041,5217,0) de 01:00 à 03:00, première nuit au moins 6 h après la réservation, repère « Ponton du passeur » sur la carte de l'appelant, champ `run` du livre (lieu donné à la seule équipe, jamais en coordonnées) ; cordon tiré par passage (60/30/10 %), monte d'un cran au premier hélicoptère vanilla (`OnWorldSound`) ; annulations la nuit du rendez-vous (patrouille 5/15/30 %, hélicoptère depuis 22:00, orage, retard à 03:00) annoncées une fois par texte traduit sur la fréquence de la voix ; barque arrivée sur lampe allumée en main (`isEmittingLight`) ou signal rouge de Signal Smoke à 15 cases ; Gus `actions=say,propose_trade`, « Business rule » renvoyée au livre, empreinte `KNOWN_DELIVERED` ; suite `rs.trade_run` ; luacheck 16/0 ; conception `passeur-rendezvous.md`, `passeur-offre.md` ; base `power-and-lights.md` (lampe allumée lue par le serveur) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.trade_run 4/4 (`20261013-093716-solo.txt`); campagne MP complète du 2026-10-15 (client 2 actif, règle « les tests font foi ») : rs.trade_run 4/4 (une réservation par passage, seconde équipe refusée `booked` ; annulation annoncée sur la fréquence de la voix) (`tools/autoclient/runs/20261015-024734-mp-348bee78d4b7/server/20261015-004928-server.txt`)
  - Reste : parcours complet avec le pont (Gus, repère, lampe au ponton) non rejoué en campagne, hors critère. Lampe vérifiée toutes les 10 min de jeu ; passage annulé non remis en jeu ; annulation non consignée dans la chronique ; échange et tricherie : E13-T04.

- [x] **E13-T04** — Échange sans contact sur la berge
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E13-T03
  - Fichiers : `RS_Trade.lua`
  - Faire : le joueur dépose un sac au lieu convenu et s'éloigne ; le serveur vérifie le contenu contre l'offre, retire les objets, pose la contrepartie au même endroit ; tricherie (contenu insuffisant) = échange refusé et réputation en baisse (E04).
  - Accepté si : aucun doublon d'objets ; contrepartie posée une seule fois même si le joueur revient pendant l'échange.
  - Tests : suite en jeu MP.
  - Preuve : banc `tests/test_rs_trade_exchange.py` du 2026-10-13 (18 tests OK), `rs_trade` 23, `rs_trade_run` 22 OK : `RS_TradeExchange.lua` (après l'arrivée de la barque, sondage chaque minute de jeu) : sacs au sol dans 7 x 7 cases autour du ponton, passage du passeur quand personne n'est à moins de 20 cases et la case chargée ; évaluation au barème `RS_TradeValues` (premier niveau du sac, portefeuille entier, conditions de la table, papiers nominatifs seulement, objets du mod et hors `Base` refusés, plafonds par type, catégorie, 10 papiers, 120 points, 20 kg) ; prise dans l'ordre du sac jusqu'au prix, sac le plus riche ; échange en un seul appel : objets pris retirés, contrepartie créée dans le sac (journal du dehors compris, marque `RS_TradeGiven`), passage clos « done », état écrit, annonce radio ; tricherie : rien déplacé, « cheated », marge 0,50, fait `trade.cheated` enregistré (non appliqué, API E04 absente), annonce ; sac sans valeur ignoré ; rien de valable en 2 h : annulation « no_drop » ; reprise sans doublon ; `Trade.finishRun`, `Run.say` ; luacheck 16/0 ; conception `passeur-echange.md` ; base `api-42-21.md` (papiers nominatifs, nom du script déjà traduit) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.trade_exchange 2/2 (`20261013-093725-solo.txt`); campagne MP complète du 2026-10-15 (client 2 actif, règle « les tests font foi ») : rs.trade_exchange 2/2 (échange sur un sac au sol, contrepartie donnée une seule fois, rien de plus aux sondages suivants) (`tools/autoclient/runs/20261015-024734-mp-348bee78d4b7/server/20261015-004928-server.txt`)
  - Reste : parcours de bout en bout avec le pont non rejoué en campagne, hors critère. Joueur au-delà de la zone chargée : « no_drop » ; sondage par minute ; papiers refusés seulement au nom d'un joueur en ligne ; échange non consigné dans la chronique.

- [x] **E13-T05** — Journal du dehors : document du mod apporté par le passeur
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E13-T01
  - Fichiers : `media/lua/server/RadioSurvivor/` (création du document), traductions `printMedia`, `docs/specifications-techniques/passeur-table.md`
  - Faire : objet lisible propre au mod (document `printMedia`, base `quest-building-blocks.md` : document de mod au rendu des journaux, document en lecture seule) portant des nouvelles du dehors datées après l'épidémie, renouvelées à chaque passage du passeur (gabarits FR/EN, aucun secret), valeur au barème ; décision du 2026-10-10.
  - Accepté si : le journal se lit en jeu, son texte change d'un passage à l'autre, il ne peut pas être revendu au passeur.
  - Tests : banc ; essai solo.
  - Preuve : banc `tests/test_outside_news.py` du 2026-10-12 (25 tests OK : objet `RadioSurvivor.OutsideNews` lisible par « Inspecter », éditions numérotées composées de gabarits FR/EN sans secret ni fréquence (une jamais répétée d'une édition à la suivante, prix qui montent), serveur qui n'écrit que des clés et des nombres, texte composé côté client, marque « lu » par édition, point d'appel `RS_OutsideNewsServer.create(passage)`, valeur au barème) ; suite `rs.outside_news` 6/6 sous lupa ; luacheck 16/0 ; conception `docs/annexes/conception/journal-du-dehors.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "rs.outside_news", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-180303-solo.txt`)
  - Reste : Solo validé le 2026-10-12. essai solo `RST.run({ suite = "rs.outside_news", tags = "world" })`, puis `RadioSurvivorOutsideNews.give(1)` et `give(2)` : « Inspecter », texte français différent, sans clé ni `%1`, rien hors page ; jeu en anglais : même contenu. Rendu réel non vu ; pas d'appel par l'échange (E13-T03/T04) ; commande de test en solo seulement ; illisible pour un illettré.
