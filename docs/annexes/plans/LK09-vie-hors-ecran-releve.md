# LK09 — Vie hors écran et relève

**Objectif.** Faire vivre les groupes loin des joueurs et assurer la relève après une décimation.

**Dépend de.** LK08-T01, LK03-T04.

**Sources.** Décisions LK00 (simulation abstraite, relève).

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-14 — **LK09-T04** : dispersion à 1 vivant, hors écran seulement, le survivant part ; type de relève tiré selon les poids de population ; délai figé au constat ; sans site, nouvel essai toutes les 24 h (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK09-T06** : eau jamais rapportée hors écran (ration « out » au bout de quelques jours) ; un repas par jour à 18 h ; 5 points de réserve par objet ; types de butin (TinnedBeans, CannedCorn, TinnedSoup, Bandage, Pills, Bullets9mmBox, ShotgunShellsBox) ; monde modifié avant l'écriture du registre (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **LK09-T01** — Simulation abstraite par heure de jeu
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK08-T01
  - Fichiers : `LK_Simulation.lua` (server)
  - Faire : consommation des réserves, moral, repos, blessures qui guérissent ou s'aggravent, selon le temps de jeu écoulé, y compris après un arrêt du serveur (rattrapage borné).
  - Idées : I1.6 (choix de tâche hors écran par priorités) (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : résultats reproductibles avec une graine ; aucun calcul proportionnel à toute la carte.
  - Tests : banc.
  - Preuve : `LK_Simulation.lua` : pas horaire par groupe (tâche par priorités I1.6 : soigner, se reposer, fouiller, journalisée au changement ; consommation par membre vivant, fouille sans déplacement, blessures abstraites `wound` qui guérissent avec des soins ou s'aggravent jusqu'à la mort par `applyDeath` et succession immédiate, repos, moral) ; taux dans `LK_Config.SIMULATION` ; rattrapage borné à 72 h d'après `simHour` et `getWorldAgeHours`, une écriture par pas ; tirages Park-Miller par (graine, groupe, heure) et arrondi aléatoire reproductible ; aucun pas sur serveur vide en `PauseEmpty` (`IngameState.java:1528-1530`, `GameTime.java:553-554`) ; `LK_Groups` : champs facultatifs `simHour`, `rest`, `task`, `wound` (schéma 1 relu sans perte), `update` groupé ; `tests/test_lk_simulation.py` 23/23 (24 pas d'une heure = rattrapage de 24 h = 5 h + 19 h, octets identiques), VM Kahlua 23/23 (mêmes valeurs que lupa) ; `tests/run_all.py` 33/33 le 2026-10-10, luacheck 17/0, `check_case.py` PASS ; `docs/annexes/conception/simulation.md` ; base `api-42-21.md` ; LK10-T01 : commit `4c9ebe0`
  - Reste : taux de départ à recalibrer (LK09-T02, T05) ; accroche `EveryHours` réelle et absence de pas en `PauseEmpty` confirmées statiquement seulement ; succession immédiate à la mort d’un chef hors écran (choix documenté dans `simulation.md`)

- [x] **LK09-T02** — Expéditions abstraites
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK09-T01
  - Fichiers : `LK_Simulation.lua`
  - Faire : équipe envoyée vers un type de lieu ; gain de ressources, blessés, pertes ou recrues selon le risque ; journal du groupe.
  - Accepté si : probabilités réglables et testées ; journal lisible.
  - Tests : banc.
  - Preuve : `LK_Simulation.lua` : expédition à la place de `scavenge` quand une réserve est sous 35 (chance horaire 0,25), équipe de 2 à 4 membres valides hors chef (2 gardés au foyer), lieu tiré selon son rendement sur la réserve manquante parmi `houses`, `stores`, `pharmacy`, `police`, `farm`, `forest` (durée, risque, recrue, rendements en données `Config.SIMULATION.EXPEDITIONS`), absents figés pendant la durée ; au retour, tirage par membre (perte par `applyDeath` ou blessure), gains selon les survivants et les rôles, une recrue au plus par `applyMember`, journal `expedition`/`return`/`loss`/`recruit` ; réglages bornés ; flux de tirages séparé, reproductibilité au découpage près conservée ; champ facultatif `expedition` (schéma 1) ; `tests/test_lk_simulation.py` 34/34 (fréquences sur 2 000 tirages proches des réglages, cas extrêmes), VM Kahlua 24/24 (mêmes valeurs que lupa) ; `tests/run_all.py` 35/35 le 2026-10-10, luacheck 17/0 et 0, `check_case.py` PASS ; `docs/annexes/conception/simulation.md` ; LK08-T05 : commit `9a1707e`
  - Reste : journal de 32 entrées vite rempli par les changements de tâche de LK09-T01 (pousse dehors les expéditions : nouvelle tâche possible) ; calibrage à revoir avec LK09-T05 ; LK09-T03 devra traiter `expedition.team` comme absents du foyer

- [x] **LK09-T03** — Matérialisation et retrait cohérents
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK09-T01, LK03-T04
  - Fichiers : `LK_Bodies.lua`
  - Faire : à l'approche d'un joueur, corps créés selon l'état simulé (membres manquants, blessés, nouveaux venus) ; retrait au départ avec mise à jour de l'état.
  - Accepté si : l'état visible correspond à l'état simulé ; aucun membre mort réapparu.
  - Tests : suite en jeu.
  - Preuve : `LK_Materialize.lua` : à 80 cases d'un foyer chargé (plafonné à 111 pour l'hystérésis avec le retrait à 120), les membres vivants présents au foyer (hors expédition, chef d'abord) reçoivent un corps : `Bodies.embody` du même `lk-<n>` ou `Bodies.spawn` + `Groups.setNpc` (apparence et arme du profil du type, recrues comprises) ; santé `hpMax × (100 − wound)/100` posée dans l'appel de création ; placement en anneaux jusqu'à 8 cases dans le bâtiment du foyer (ou hors bâtiment pour un camp), jamais un escalier ; bornes 2 corps par passage, 8 par groupe, 24 au total ; au retrait : `wound` recalculée (aller-retour exact, jamais mortelle) ; mort d'un corps = membre mort une fois, un seul `memberDied` (`applyDeath(..., quiet)`) ; simulation : membre incarné sans blessure horaire, expédition ni événement ; `tests/test_lk_materialize.py` 15/15 (deux allers-retours sans doublon, aucun mort revenu, bornes, placement), `test_lk_simulation.py` 45/45, VM Kahlua 29/29 ; suite en jeu `lk.materialize` ; `tests/run_all.py` 42/42 le 2026-10-10, luacheck 17/0 et 0 ; `docs/annexes/conception/corps-registre.md`, `simulation.md`, `groupes.md`, `tests-en-jeu.md` ; base `world-placement.md` ; E08-T08 : commit `5d5f45e` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : 7 colons matérialisés au foyer, retrait après départ, retour avec les mêmes `lk-<n>` (génération 2), mort non revenu, orphelins supprimés au retour de la zone ; `lk.materialize` 1/1 (`20261011-135114-solo.txt`, chef blessé conservé) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.materialize PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.materialize 1/1 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : rapports d’état envoyés pour un corps déchargé (LK03-T07)

- [x] **LK09-T04** — Décimation et relève
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK09-T01, LK07-T04
  - Fichiers : `LK_Groups.lua`
  - Faire : groupe sans membre (ou dispersé) marqué disparu ; foyer abandonné et traces conservés ; nouveau groupe installé ailleurs après le délai.
  - Idées : I8.4 (renforts sous la moitié de l'effectif, abandon du foyer) (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : relève dans le délai réglé, loin de l'ancien site.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_relief.py` du 2026-10-12 (17 tests OK, suite `lk.relief` jouée dans le vrai moteur RST : groupe décimé ou dispersé marqué `gone` sans effacer foyer, aménagement ni stock ; délai tiré dans `[ReliefDaysMin, ReliefDaysMax]` reproductible et figé ; une seule relève par groupe même après redémarrage ; nouveau groupe à au moins `GROUP_DISTANCE` de l'ancien foyer) ; `lk_population` 30, `lk_groups` 17, `lk_homes` 18 OK ; run_all 68/68 ; luacheck 16/0 ; conception `groupes.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.relief 2/2 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.relief 2/2 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : persistance après redémarrage abandonné (règle du 2026-10-14 : non exigée par le critère, une seule relève prouvée au banc). Renforts sous la moitié de l'effectif (I8.4) non faits ; groupes disparus comptés dans `MAX_GROUPS` (64), relève repoussée en boucle si plein.

- [x] **LK09-T05** — Événements de groupe
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK09-T01
  - Fichiers : `LK_Simulation.lua`
  - Faire : départ d'un membre, recrue, conflit interne, maladie : liste fermée d'événements avec effets bornés, consignés au journal.
  - Idées : I9.1 (combat abstrait entre groupes loin des joueurs, vaincus retrouvés en cadavres) (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : chaque événement a un effet vérifiable.
  - Tests : banc.
  - Preuve : `LK_Simulation.lua` : tirage quotidien (12 h) d'au plus un événement par groupe, somme des chances plafonnée à 0,5, flux séparé ; `departure` (moral < 30, jamais le chef, un absent ni un membre lié à un PNJ), `recruit` (réserves et moral corrects, place libre), `conflict` (moral −6, chef contesté journalisé sans changement, blessure possible), `illness` (contagion bornée à 3, soins consommés), `clash` I9.1 (pillards contre un autre type, foyers à ≤ 2000 cases et à ≥ 300 cases de toute base connue, issue selon les effectifs, pertes par `applyDeath` bornées à 3, butin borné, entrée `remains` avec lieu approximatif) ; chances et effets en données `Config.SIMULATION.EVENTS` ; `Groups.applyLeave` pur ; `tests/test_lk_simulation.py` 45/45 (un test par événement), VM Kahlua 25/25 (`KR-EVT` identique à lupa) ; `tests/run_all.py` 35/35 le 2026-10-10, luacheck 17/0 et 0, `check_case.py` PASS ; `docs/annexes/conception/simulation.md` ; LK09-T02 : commit `da87010`
  - Reste : morts d’un combat seulement consignées (`remains`, aucun cadavre posé ; peut sortir du journal de 32 entrées) ; combat sans moral ni munitions dans l’issue ; calibrage à vérifier ; bases lues une fois par pas

- [x] **LK09-T06** — Stock abstrait cohérent avec les conteneurs
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK09-T01, LK08-T06
  - Fichiers : `LK_Stock.lua`, `LK_Offscreen.lua`
  - Faire : pendant la simulation hors écran, consommation et butin d'expédition modifient l'inventaire de référence ; à l'arrivée d'un joueur, les conteneurs réels sont mis à jour (objets retirés ou ajoutés) avant qu'il puisse les ouvrir.
  - Accepté si : après une absence, contenu réel = inventaire de référence ; aucun objet perdu ni dupliqué lors d'un chargement pendant une mise à jour.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_stock.py` du 2026-10-12 (44 tests OK dont `OffscreenTests` 13 et `OffscreenMultiplayerTests` 1 : repas abstrait quotidien selon la portion, butin d'expédition abstraite, journal d'écarts borné, application avant toute ouverture ou prise, marque `LKStockOp` idempotente sans double création, écart arrivé pendant l'application gardé, 72 h d'un coup = heure par heure) ; `test_lk_simulation.py` OK ; luacheck des fichiers de la tâche sans nouvel avertissement ; conception `stock.md` (Hors écran), `simulation.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.offscreen_stock", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-175800-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.offscreen_stock PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.offscreen_stock 1/1 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : second client voit la caisse à jour. Réserves abstraites et stock réel restent deux comptes ; soins, maladie, combats non reportés ; objets pris hors écran non examinés.
