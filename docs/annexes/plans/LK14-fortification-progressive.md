# LK14 — Fortification progressive

**Objectif.** Les groupes renforcent leur foyer au fil du temps avec des matériaux réels : barricades des ouvertures, puis défenses plus lourdes, entretien et réparation après une attaque. Le travail est visible quand un joueur est proche et rattrapé hors écran sinon.

**Dépend de.** LK08-T06 (stock réel), LK05-T02 (objectifs du groupe), LK04-T04 (barricades et passage bloqué).

**Sources.** Décisions LK00 (2026-10-08, comportements autonomes) ; Java et Lua vanilla 42.21 (barricades, constructions, synchronisation des objets) ; base `custom-tiles-entities.md`, `power-and-lights.md` (portes, grillages et portails posés par script).

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-08 — **LK14-T04** : défenses lourdes = **murs et palissades en bois** des constructions vanilla, avec matériaux réels du stock ; mécanisme à établir d'abord par `LK14-T01`.
- 2026-10-14 — **LK14-T02** : 4 planches au rez-de-chaussée (vue des guetteurs bloquée au-delà de 2) et 2 aux étages ; murs en bois autour d'un bâtiment, palissade autour d'un camp ; marge 2 cases, carré de 7, brèche de 3 segments sans portail ; pondération 3/1/2 et +5 par menace (plafond 20) (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK14-T03** : geste `hammer` (clip vanilla `Build`) au lieu de `strike`/`kneel` ; barricade côté extérieur, ouvrier dedans ; branchement en corvée prioritaire ; 2 min de jeu par planche (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK14-T04** : santé = niveau requis par la recette (cadre 90, mur 490, palissade 500) ; geste `rummage` pour la palissade ; 2 min de jeu par étape ; un seul poteau d'angle (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK14-T05** : 30 min utiles par bâtisseur et par heure, de jour, groupe sans membre incarné ; portes ouvertes exclues du relevé (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK14-T06** : besoin de matériaux par le journal et `Fortify.needOf` (sans toucher `Stock.needs` ni `supply`) ; seuil 0,75 ; urgence un jour ; réparations toujours réussies ; scie exigée ; planche abîmée rendue ; durées 4 et 10 min (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **LK14-T01** — Investigation : barricades et constructions vanilla posées par script
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/annexes/conception/fortification.md` ; base de connaissances
  - Faire : comment le jeu pose une barricade (planches, tôles) et une construction (murs, palissades, portails) ; ce qui est synchronisé en MP, sur quelle autorité, avec quels matériaux et quels outils.
  - Accepté si : chaque mécanisme cité avec sa preuve vanilla ; entrée de base de connaissances si un fait générique est établi.
  - Tests : —
  - Preuve : `docs/annexes/conception/fortification.md` (Java 42.21.0, Lua, scripts et tuiles vanilla, chaque fait avec `fichier:ligne` ou « à mesurer ») : barricade par entités `BarricadePlanks`/`BarricadeMetalSheet`/`BarricadeMetalBar` (`ISBarricadeAction` hors menu), pose serveur `IsoBarricade.AddBarricadeToObject` + `addPlank(nil, …)` + `transmitCompleteItemToClients` (`IsoWindow.java:1329-1336`, vérifié), barricade qui bloque la porte pour tous (`IsoDoor.java:1320`), constructions `IsoThumpable` par `ISBuildIsoEntity:setInfo` à reproduire côté serveur, seuls les murs en bois et la palissade de rondins arrêtent un zombie (portail en bois enjambé), serveur seule autorité, dégâts et réparation ; base : `barricades-and-constructions.md` (8 entrées) ; E07-T07 : commit `4b78fff`
  - Reste : points « à mesurer » listés (pose scriptée sur serveur dédié et persistance, `IsoBarricade.Thump` sans branche client, réparation d’un mur, rendu du geste sur un corps) ; ⚠ le portail en bois vanilla est enjambé par les zombies : à prendre en compte pour LK14-T04

- [x] **LK14-T02** — Plan de fortification du foyer
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK14-T01, LK08-T04
  - Fichiers : `LK_Fortify.lua` (server)
  - Faire : le serveur dresse la liste des chantiers du foyer par priorité (portes et fenêtres du rez-de-chaussée, puis étages, puis défenses extérieures), avec matériaux et durée ; le cadre de décision choisit d'y travailler selon le stock et les menaces.
  - Accepté si : plan reproductible pour un foyer donné ; aucun chantier hors du foyer.
  - Tests : banc.
  - Preuve : banc `tests/test_lk_fortify.py` du 2026-10-12 (15 tests OK : chantiers par priorité rez-de-chaussée, étages, pourtour ; porte d'entrée et brèche laissées libres ; matériaux et durées des scripts vanilla ; plan reproductible quel que soit l'ordre des objets ; aucun chantier hors du foyer ; niveau 0..100 par `Fortification.levelOf` ; chantier faisable selon le stock ; `siteFor` sans double attribution) ; run_all 66/66 ; luacheck 16/0 ; conception `fortification.md` §6
  - Reste : pose réelle à vérifier avec LK14-T03/T04 ; compétences de Menuiserie ignorées ; draps déchirés non comptés comme liens ; case extérieure d'une ouverture d'étage à vérifier ; poteaux d'angle (LK14-T04) ; pas de pourtour au-delà de 96 segments.

- [x] **LK14-T03** — Barricader portes et fenêtres
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK14-T02, LK08-T06
  - Fichiers : `LK_Fortify.lua`, `LK_Routines.lua`
  - Faire : un membre prend planches et clous dans le stock, va à l'ouverture, travaille avec un geste visible, la barricade apparaît chez tous ; matériaux consommés une seule fois.
  - Idées : I8.5 (planches réparties, entrée dégagée) (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : barricade identique pour deux clients ; stock diminué exactement ; ouverture laissée praticable pour les membres si elle sert de passage.
  - Tests : suite en jeu + protocole.
  - Preuve : banc `tests/test_lk_barricade.py` du 2026-10-12 (12 tests OK : chantier de `siteFor` verrouillé pour un seul membre, planche et clou retirés une seule fois par `Stock.takeItem` sans vol, barricade posée par `AddBarricadeToObject` + `addPlank` et transmise comme le code vanilla, entrée du foyer jamais barricadée, interruption sans prise, boîte de clous ouverte comme `OpenBox100`) ; run_all 67/67 ; luacheck 16/0 ; conception `fortification.md` §7 ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.barricade PASS (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`); campagne MP complète du 2026-10-15 (client 2 actif, règle « les tests font foi ») : lk.barricade 1/1 (planches et clous retirés exactement du stock, entrée du foyer sans planche), étapes world.keys vertes chez les clients 1 et 2 (9 cases comme sur le serveur) (`tools/autoclient/runs/20261015-024734-mp-348bee78d4b7/server/20261015-004928-server.txt`)
  - Reste : reconnexion abandonné (règle du 2026-10-14 : non exigée par le critère). Suite non jouée sur doublures ; pas de son de marteau ni de bruit ; porte ouverte = chantier refusé ; clous au-delà de 128 objets suivis non comptés.

- [x] **LK14-T04** — Défenses plus lourdes
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK14-T03
  - Fichiers : `LK_Fortify.lua`
  - Faire : construire murs et palissades en bois vanilla autour du foyer selon le plan de fortification (`LK14-T02`), avec planches, clous et outils du stock, travail visible, objets synchronisés et persistants.
  - Accepté si : décision appliquée ; défenses synchronisées et persistantes.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_walls.py` du 2026-10-12 (10 tests OK : cadre puis mur en bois ou palissade posés par l'autorité comme `ISBuildIsoEntity:setInfo` (entité, santé, poteau d'angle), matériaux retirés une seule fois et remis si une prise échoue, brèche libre, aucun segment hors du foyer) ; `lk_barricade` 12, `lk_fortify` 15 OK ; run_all 72/72 ; luacheck 16/0 ; conception `fortification.md` §8 ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.walls PASS (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; phases réelles du 2026-10-15 6 h 07 (reconnexion des clients puis `quit` et relance du serveur sur la même partie, `tools/autoclient/runs/20261015-060712-mp-1a0abb0c888e`) : lk.walls.after-reconnect et lk.walls.after-restart « same wall … seen by every client » PASS
  - Reste : rendu réel non vérifié à l'œil (abandonné, règle du 2026-10-14) ; aucun son de construction ; palissade testée au banc seulement

- [x] **LK14-T05** — Rattrapage hors écran de la fortification
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK14-T03, LK09-T06
  - Fichiers : `LK_Fortify.lua`, `LK_Offscreen.lua`
  - Faire : hors écran, les chantiers avancent selon le temps écoulé, les membres disponibles et les matériaux ; à l'arrivée d'un joueur, les barricades et défenses terminées sont posées avant qu'il approche.
  - Accepté si : état posé = état simulé ; matériaux consommés une seule fois.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_fortify_offscreen.py` du 2026-10-12 (12 tests OK : relevé du plan au registre, chantiers avancés hors écran selon les bâtisseurs et les matériaux pris une seule fois par le journal d'écarts du stock, pose à l'arrivée par les fonctions existantes avant tout chantier, marque `LKFortOp` idempotente (sur l'ouverture, la ModData d'une barricade n'étant pas sauvegardée), application interrompue reprise sans double, serveur + 2 clients) ; bancs voisins OK ; luacheck des fichiers de la tâche sans nouvel avertissement ; conception `fortification.md` §10 ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.fortify_offscreen PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.fortify_offscreen 1/1 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : Suite qui appelle l'heure hors écran directement ; planches posées neuves ; relevé en retard d'une minute possible ; boîtes de clous en attente non comptées ; pas de réparation hors écran ; écart impossible abandonné sans remboursement.

- [ ] **LK14-T06** — Entretien et réparation après une attaque
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK14-T03, LK05-T09
  - Fichiers : `LK_Fortify.lua`
  - Faire : les barricades endommagées par les zombies ou les joueurs sont repérées et réparées en priorité après une attaque, avec les matériaux du stock ; à défaut, un besoin de matériaux remonte au groupe.
  - Accepté si : réparation visible et synchronisée ; besoin de matériaux créé si le stock manque.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_repair.py` du 2026-10-12 (13 tests OK : usure des barricades (`getThumpCondition`) et santé des murs relevées, chantiers `repair` en tête pendant un jour après `Defense.after`, planche abîmée remplacée avec un seul `sendObjectChange`, mur et palissade réparés selon les recettes vanilla `Wood`/`Log`, matériaux retirés une seule fois, manque journalisé et lisible par `Fortify.needOf`) ; `lk_fortify` 15, `lk_barricade` 12, `lk_walls` 10 OK ; run_all 73/73 ; luacheck 16/0 ; conception `fortification.md` §9 ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.repair 1/1 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; santé du mur après reconnexion et redémarrage : lk.walls.after-reconnect et .after-restart PASS dans la campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093730-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`) ; campagne solo-lk (`tools/autoclient/runs/20261015-135627-parallel-2-c6a500a78137`) : lk.repair « builder repairs a damaged barricade after an attack » PASS
  - Reste : MP : même planche chez deux clients (aucune étape client) ; barricades de métal non réparées ; pas de son