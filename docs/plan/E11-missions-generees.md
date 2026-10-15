# E11 — Missions générées à partir de gabarits

**Objectif.** Au-delà de la livraison M01, le LLM choisit un gabarit que le serveur sait vérifier (signaler, retrouver, reconnaître, nettoyer, récupérer), le lieu, le prétexte et la récompense dans des bornes, puis raconte. Valable pour les voix radio et pour les PNJ Bandits!.

**Dépend de.** E00-T03 (missions répétables), E07-T01 (actions structurées) ; E04-T05 pour le filtrage par réputation.

**Sources.** Note de travail §08 (gabarits, Signal Smoke) ; spécification ADR B16 (choix contextualisé des missions), spécification M01 ; base `quest-building-blocks.md` (carte d'identité nominative `Base.IDcard`, objet dans un cadavre à `OnZombieDead`) ; base `world-placement.md` (placement différé, caches) ; base `combat-and-xp.md` et `multiplayer.md` (tueur d'un zombie connu du serveur, feu non attribué) ; projet `Workshop\SignalSmoke` (API serveur `SignalSmoke.start{x, y, color, kind, minutes}`).

## Décisions

- 2026-10-15 — **E11-T19 — choix utilisateur** : livraisons radio en boîte convenue ou sac caché, objets retirés seulement après éloignement pour simuler un contact discret. **Confirmé par défaut** : modes alternés par mission ; point `place=` de la voix ; boîte existante exacte près du point et repère individuel, sinon sac au sol ; tous les joueurs à au moins 40 cases horizontalement, toute hauteur, durant 10 secondes réelles continues ; retour ou redémarrage relance le délai ; case exacte chargée avant retrait. Boîte conservée, seuls objets demandés retirés ; sac entier retiré, contenu étranger refusé. Reprise libre avant collecte, compte rendu radio après collecte.

- 2026-10-15 — **Récompenses étendues — confirmé par défaut** : rotation serveur `cache,frequency,stashmap,lesson` parmi les effets autorisés et disponibles, persistée par donneur et bénéficiaire, sans choix du modèle. Fiches sans `rewards` : ancien repère conservé. Cache de récompense seulement après réussite, lieu issu de la fiche. Leçon : 25 XP par mission, 100 XP par jour de jeu et personnage avant multiplicateurs vanilla ; multiplicateur sandbox 0..5 (0 désactive). Carte : une par personnage/voix ou personnage/groupe, prise dans les cachettes vanilla encore possibles et bâtiments non visités.
- 2026-10-15 — **PNJ — confirmé par défaut** : un retrait partagé par mission (règle du lot commun), réservé au premier participant réclamant ; stock réel rationné en priorité, puis table fermée selon groupe, puis lot commun historique. Réputation et relation personnelle conditionnent les gestes de confiance. Demandeur mort ou groupe décimé : aucun nouveau retrait.
- 2026-10-15 — **Missions de voix — confirmé par défaut** : `missions` absent conserve `scout` ; alias de fiche `retrieve` vers gabarit moteur `retrieve_id`. Dépôt de livraison à un lieu de la voix, vérification serveur, puis compte rendu radio. Aucun nouvel appel LLM hors quotas.

- Acquises : gabarits fermés vérifiables ; une mission à la fois par appelant pour les voix radio ; Signal Smoke prérequis (`require=` dans `mod.info`, décision du 2026-10-15 ; remplace « facultatif, sans dépendance ») ; récompenses : informations, caches, confiance.
- 2026-10-08 — **E11-T01 (1)** : premier gabarit après M01 : **reconnaître**.
- 2026-10-08 — **E11-T01 (2)** : délai par défaut = même règle que M01 (temps réel de fonctionnement du serveur).
- 2026-10-08 — **E11-T01 (3)** : réputation : même barème que M01 pour tous les gabarits.
- 2026-10-10 — **E11-T08** : pour la première publication (Living Knox désactivé par défaut), une **voix radio peut donner une mission** : action `start_mission`, compte rendu **à la radio** sur sa fréquence, donneur sans corps ; récompense en réputation et information (repère), cache sur place quand `E11-T06` existe.
- 2026-10-11 — **E11-T10** : pour aider à trouver le lieu d'une mission de reconnaissance, **seulement une zone approximative tracée sur la carte** du joueur (pas le point exact) ; pas de direction depuis la position du joueur ni de guidage au rappel ; les cibles **ne doivent pas être rapprochées** (une cible lointaine reste souhaitable).
- 2026-10-14 — **E11-T04** : cercle exact centré ; formule et bornes de N ; un zombie pour une seule mission ; PNJ seulement ; règle d'E04-T06 réécrite dans le gabarit (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : plus de réussite automatique, l'objectif rempli se rapporte au PNJ demandeur : tâche E11-T13.
- 2026-10-14 — **E11-T05** : papiers sur un cadavre plutôt que sur un zombie (confirmé par l'utilisateur) ; remise par « Livrer » ; proposé par les PNJ seulement ; offre conditionnée à `RandomizedWorldBase` (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E11-T06** : sac de sport et 4 tables ; identifiant seul ; PNJ seulement ; `place_cache` sur la dernière mission de la voix ; plafond de 6 offres (environ 800 jetons de plus au plus par requête) (confirmé par défaut, valeurs techniques) ; cercle « Dépôt » au foyer du groupe, qui révèle sa position au participant (confirmé par l'utilisateur) ; changement (décision de l'utilisateur) : plus de réussite automatique, l'objectif rempli se rapporte au demandeur : tâche E11-T13.
- 2026-10-14 — **E11-T07** : API `onSignal` existante au lieu de l'événement `batman_OnSignalLit` prévu (Signal Smoke non modifié) ; cercle de 20 cases ; 4 couleurs, tout type de signal ; fenêtre de 2 h valable chaque jour ; PNJ seulement (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : plus de réussite automatique sans compte rendu, le participant revient le dire au PNJ (ou l'annonce à la radio pour une voix) : tâche E11-T13.
- 2026-10-15 — **Signal Smoke est un mod prérequis** (décision de l'utilisateur, remplace « mod facultatif, aucune dépendance dans mod.info ») : `require=` dans `mod.info`, objet requis sur Steam et mention dans les descriptions ; plus aucun chemin « sans Signal Smoke » dans le code ni dans les tests (suite `rs.mission.nosignal` retirée).

## Tâches

- [x] **E11-T01** — Ordre des gabarits et barèmes
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier
  - Faire : faire trancher l'ordre de développement et les bornes.
  - Accepté si : décisions consignées.
  - Tests : —
  - Preuve : décisions du 2026-10-08 (section Décisions) ; **en jeu solo le 2026-10-11** (nouvelle partie `2026-10-11_17-54-58`) : mission de Walt, zone sur la carte puis retirée, validé par l'utilisateur
  - Reste : —

- [x] **E11-T02** — Moteur de gabarits commun (M01 réécrit dessus)
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E11-T01
  - Fichiers : `RS_Missions.lua` (interface `template.offer`, `template.check`, `template.complete`) ; `RS_Config.lua` (catalogue par gabarit)
  - Faire : extraire de M01 ce qui est commun (offre admissible, acceptation, chrono, résultat collectif, récompense, purge) ; chaque gabarit fournit ses offres et sa vérification ; M01 devient le gabarit `deliver` sans changement de comportement.
  - Accepté si : tous les tests M01 existants passent sans modification de leurs assertions.
  - Tests : `test_carnet.py` complet.
  - Preuve : `RS_Missions.lua` réécrit en moteur commun (`M.offers`, `create`, `accept`, `advance`, `finish`, `prune`, `report` transactionnel, `claim`, `projection`, `context`, `register`) + gabarit `deliver` (`offer`, `create`, `check`, `prepare`, `apply`, `progress`, `complete`, `project`, `context`) ; catalogue `RS_Config.Missions.deliver` aux valeurs M01 inchangées (`C.Delivery` alias) ; mission sauvegardée sans `template` relue comme `deliver` ; contrat Lua ↔ Python inchangé ; assertions existantes inchangées (`git diff --stat tests/` : ajouts seuls dans `test_carnet.py`, références de lignes recalées) ; `test_carnet.py` 35/35 dont `MissionTemplateTests` (gabarit factice, mission sans `template`), `rs.missions` 14/14, VM Kahlua 20/20, luacheck 17/0 (référence abaissée : `require` inutilisé retiré) ; vérifié le 2026-10-10 dans un worktree propre (seuls échecs : fins de ligne CRLF du checkout des fiches, sans rapport) ; LK14-T01 : commit `f272b5b`
  - Reste : gabarit `deliver` dans le même fichier que le moteur (E11-T03 pourra le séparer) ; commandes `prepare_delivery`/`confirm_delivery` du carnet propres à la livraison

- [x] **E11-T03** — Gabarit « reconnaître »
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E11-T02
  - Fichiers : `RS_Missions.lua` ; gabarit `scout`
  - Faire : atteindre un lieu (zone serveur) puis en rendre compte au donneur (radio ou proximité) ; le serveur vérifie la présence dans la zone par sondage.
  - Accepté si : la position d'un client n'est jamais crue sans contrôle serveur ; mission réussie seulement après le compte rendu.
  - Tests : banc `lupa` ; suite en jeu.
  - Preuve : `RS_MissionScout.lua` : gabarit `scout` (`scout_v1`) du moteur E11-T02 ; lieu = bâtiment habitable de la métagrille (`RS_Rescue.check`) à 60–250 cases du demandeur et à 60 cases au moins de toute base, sans charger, gardé 10 min pour que l'offre racontée et la mission désignent le même bâtiment ; zone = emprise élargie de 2 cases, dans l'état privé ; sondage serveur chaque seconde de la position des joueurs identifiés (jamais une position venue du client) → `zoneReached` ; compte rendu de vive voix au PNJ demandeur après la visite seulement, puis réussite, réputation et lot par le moteur commun ; offre au pont avec type de lieu et indices sans chiffre ; carnet : page Missions pour `scout` ; `test_carnet.py` 44/44 (`ScoutMissionTests` : commandes forgées refusées, compte rendu sans visite refusé, expiration, redémarrage ; assertions M01 inchangées), `scenario_scout_offer` ; suite en jeu `rs.missions.scout` ; `tests/run_all.py` 38/38 le 2026-10-10, luacheck 17/0 et 0 ; `docs/carnet-implementation-04221.md`, `docs/protocole-carnet-v2.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.missions 14 PASS, rs.missions.scout (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.missions.scout 1/1, rs.missions 14/14 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : bout en bout avec un PNJ Living Knox abandonné (règle du 2026-10-14 : chemin serveur couvert par `rs.missions.scout`) ; ⚠ mission rattachée à un PNJ du carnet : pas encore proposable par une voix radio (demandeur sans corps : à décider pour la publication) ; ⚠ compte rendu de vive voix et non à la radio comme dans la note de travail (à arbitrer)

- [ ] **E11-T04** — Gabarit « nettoyer »
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : E11-T02, E04-T06
  - Fichiers : gabarit `clear`
  - Faire : tuer N zombies autour d'un lieu ; décompte à `OnZombieDead` côté serveur avec attribution établie en E04-T06 ; morts par le feu non comptées si non attribuées.
  - Accepté si : décompte cohérent entre deux participants ; aucun double compte.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_mission_clear.py` du 2026-10-12 (9 tests OK, contrôlés par mutation : cercle de comptage sur la carte, N tiré de la densité des en-têtes de lot (6 à 25), décompte à `OnZombieDead` côté serveur avec l'attribution d'E04-T06 (feu, piège sans lanceur, chute, PNJ, hors cercle, non-participant et doublon exclus), réussite automatique et récompense par le moteur commun) ; carnet 79/79 et `mission_retrieve` inchangés ; run_all 86/86 ; luacheck 16/0 ; conception `docs/conception/mission-nettoyer.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.missions 14 PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.mission.clear 1/1 et rs.mission.clearcount 1/1 (deux participants, un seul décompte k / N, zombie hors du cercle non compté) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; solo : `rs.mission.clear` 2 PASS deux fois (`tools/autoclient/runs/20261015-133822-8f444d87d714/20261015-113910-solo.txt`, `tools/autoclient/runs/20261015-133930-90bb14f64203/20261015-114015-solo.txt`) : mêlée, tir et voiture du joueur comptés, zombie brûlé non compté, carnet « À rapporter », compte rendu, réussite et « Réclamer »
  - Reste : MP : mêlée, tir et voiture d'un client distant, réussite et « Réclamer » vus côté client ; choc de voiture par la physique réelle non couvert (`Hit` du véhicule par script) ; N = ordre de grandeur ; derniers comptes perdus sur arrêt brutal

- [x] **E11-T05** — Gabarit « retrouver »
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E11-T02
  - Fichiers : gabarit `retrieve_id`
  - Faire : un cadavre ou un zombie porteur d'une carte d'identité nominative ; rapporter la carte au donneur ; vérification par identifiant d'objet côté serveur.
  - Accepté si : une autre carte d'identité est refusée.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_mission_retrieve.py` du 2026-10-12 (9 tests OK, suite RST jouée sur le serveur simulé : offre `retrieve_id_v1` par une fiche de PNJ, zone tracée sur la carte, cadavre posé au chargement du bâtiment avec une `Base.IDcard` nommée, carte trouvée chez un participant, remise par « Livrer » vérifiée par identifiant d'objet (toute autre carte refusée avant effet), récompense par le moteur commun) ; carnet 79/79 inchangé ; `test_protocol.py` OK (branche hors ligne du pont) ; run_all 84/84 ; luacheck 16/0 ; conception `docs/conception/mission-retrouver.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.missions 14 PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.mission.retrieve 1/1 (corps posé une fois, autre carte refusée, carte du corps acceptée par identifiant), rs.mission.zones « retrieve: search circle drawn, kept once found, removed after the success » PASS avec étapes map.zones des deux clients et world.keys du corps (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/client2/20261015-090729-steps.txt`)
  - Reste : Limites : pas de zombie porteur ; corps posé seulement si un participant est connecté ; arrêt brutal entre pose et sauvegarde = second corps possible ; corps retiré par `HoursForCorpseRemoval` = mission expirée

- [x] **E11-T06** — Gabarit « récupérer » et action `place_cache`
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E11-T02
  - Fichiers : `RS_Actions.lua` (`place_cache`) ; gabarit `recover`
  - Faire : cache tirée d'une table serveur fermée, posée au chargement de la case (placement différé) ; la porter à un dépôt ; une cache par mission.
  - Accepté si : la cache n'apparaît qu'une fois, même après redémarrage ; le dépôt vérifie l'objet marqué.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_mission_recover.py` du 2026-10-12 (12 tests OK, contrôlés par mutation : cache = sac marqué tiré d'une table fermée du serveur, posée une seule fois même après un arrêt entre pose et sauvegarde, action `place_cache` contrôlée par le serveur, dépôt qui reconnaît le sac par identifiant d'objet (pas par sa marque), réussite et récompense par le moteur commun, plafond d'offres porté à 6 côté serveur et pont) ; M01, E11-T03 à T05 inchangés ; run_all 88/88 ; luacheck 16/0 ; conception `docs/conception/mission-recuperer.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.missions 14 PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; phases réelles du 2026-10-15 6 h 07 (reconnexion des clients puis `quit` et relance du serveur sur la même partie, `tools/autoclient/runs/20261015-060712-mp-1a0abb0c888e`) : rs.mission.recover.after-restart « one bag after the restart » PASS ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.mission.recover 1/1 (cache posée une fois, autre sac refusé, cache acceptée au dépôt par identifiant), rs.mission.zones « recover: cache and depot circles drawn, kept once found, removed after the success » PASS avec étapes map.zones (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/client2/20261015-090729-steps.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : rs.mission.recover.before et .after-restart PASS (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093457-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`)
  - Reste : —

- [ ] **E11-T07** — Gabarit « signaler » et événement Signal Smoke
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : E11-T02
  - Fichiers : gabarit `signal` ; projet SignalSmoke (événement facultatif `batman_OnSignalLit(joueur, x, y, z, couleur, type)`, à ajouter dans **son** dépôt et son suivi)
  - Faire : lancer la couleur demandée à un lieu et une heure ; RadioSurvivor écoute l'événement de Signal Smoke, mod prérequis (2026-10-15 : plus de cas « sans le mod »).
  - Accepté si : signal de la bonne couleur, au bon lieu et dans les heures = objectif rempli ; autre signal = rien ; module de Signal Smoke cassé = erreur claire au journal et aucune offre (Signal Smoke est prérequis depuis le 2026-10-15).
  - Tests : banc `lupa` (mod absent / présent) ; suite en jeu.
  - Preuve : banc `tests/test_mission_signal.py` du 2026-10-13 (10 tests OK, contrôlés par mutation : fenêtre, couleur, cercle, détection du mod, type d'événement) : gabarit `signal` (offre `signal_v1`, PNJ seulement) : lieu tiré comme `scout`, cercle de 20 cases centré sur le bâtiment, couleur vert/rouge/jaune/violet, fenêtre de 2 h de jeu commençant 2 à 4 h après le tirage ; réussite au premier signal d'un participant, de la bonne couleur (`SignalSmoke.COLORS`), dans le cercle, pendant la fenêtre ; abonnement unique sur l'autorité à l'API existante `SignalSmoke.onSignal` (mod détecté par `getActivatedMods` + `require`, absent : aucune offre ni erreur) ; carnet (page Missions, cercle « Zone du signal »), traductions EN/FR, texte hors ligne du pont ; suite `rs.mission.signal` ; `carnet` 84 OK ; luacheck 16/0 ; conception `mission-signaler.md`, `protocole-carnet-v2.md`, `carnet-implementation-04221.md`, `tests-en-jeu.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.mission.signal 1/1 avec Signal Smoke (`20261013-093505-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.missions 14 PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.mission.signal 1/1 avec Signal Smoke actif (signal de la couleur demandée allumé par le participant dans le cercle : réussite ; autres signaux sans effet), rs.mission.nosignal 1/1 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`)
  - Reste : contrôles côté client non branchés : offre acceptée, cercle sur la carte, signal hors des heures sans effet, « Réclamer ». Fusées toujours rouges ; bâton lumineux attribué au joueur le plus proche ; grenade sans lanceur ignorée.

- [x] **E11-T08** — Voix radio donneuse de missions (« reconnaître » par radio)
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E11-T03, E07-T04
  - Fichiers : `RS_Missions.lua`, `RS_MissionScout.lua` (donneur sans corps), exécuteur `start_mission` (`RS_Actions`), pont (`EXECUTABLE_ACTIONS`), `RadioSurvivor_Server.lua`, carnet (page Missions)
  - Faire : décision du 2026-10-10 : une voix radio propose une mission `scout` par l'action `start_mission` (gabarit en liste fermée, lieu choisi par le serveur sans coordonnée dans le prompt, indices comme E11-T03) ; une mission à la fois par appelant ; le moteur accepte un donneur « voix » sans fiche ni corps ; visite vérifiée par sondage serveur comme E11-T03 ; **compte rendu à la radio** : une phrase dite à cette voix sur sa fréquence après la visite ; réussite → réputation (barème M01) et information (repère `mark_map` d'un lieu utile de la fiche) ; cache sur place quand `E11-T06` sera fait ; mission visible dans le carnet.
  - Accepté si : la voix ne lance qu'une mission par appelant ; compte rendu radio avant la visite refusé ; réussite après visite et compte rendu ; aucune coordonnée dans le prompt ; fonctionne Living Knox désactivé.
  - Tests : banc `lupa` (`test_carnet.py`, `test_protocol.py`) ; suite en jeu.
  - Preuve : `RS_MissionVoice.lua` : donneur « voix » sans fiche ni corps (`voice:<voix>:<personnage>` dans l'état privé, `M.donorOf`), action `start_mission` (gabarit `scout` seul, `budget.start_mission`, délai 60 s, refus motivés `no_player`, `no_character`, `mission_open`, `recent_mission`, `no_place`), une mission ouverte par appelant et par voix, mission créée et acceptée, ligne de carnet « Mission reçue : <type de lieu> » ; visite par le sondage serveur d'E11-T03 ; compte rendu à la radio jugé dans `onTalk` (avant la visite : `not_yet` ; après : réussite) ; contexte `mission=` sans coordonnée joint aux requêtes et ajouté au prompt par le pont ; récompense : réputation (+5) et repère `MapMarks.give` du premier lieu de la fiche pas encore donné ; carnet : donneur = nom de la voix, seul « Abandonner » proposé, `invite`/`claim` refusés ; `test_carnet.py` 49/49 (`VoiceMissionTests` sans moteur de PNJ), `test_protocol.py` (`scenario_voice_mission_bridge`), `test_radio_history.py` 30/30, `test_rs_suites.py` 35/35 ; suite en jeu `rs.missions.radio` ; luacheck 17/0 ; assertions M01 et `scout` inchangées ; `docs/protocole-carnet-v2.md`, `persona-format.md`, `carnet-implementation-04221.md`, `tests-en-jeu.md` ; LK03-T03 : commit `ac74b3d` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : Walt (fiche de test) lance la mission par `start_mission`, lieu atteint par téléportation, compte rendu radio → réussite, ligne « Repère reçu » et repère du poste de police sur la carte ; `rs.missions.radio` 1/1 (`20261011-135347-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.missions.radio 1 PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.missions.radio 1/1 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : indices non transmis par la voix et absents du carnet (E11-T09) ; titre de mission faux et ligne `CharacterReputation` (E11-T09)

- [x] **E11-T09** — Mission de reconnaissance : indices transmis et fiche correcte
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E11-T08
  - Fichiers : `RS_MissionScout.lua`, `RS_MissionVoice.lua`, `RS_Notebook.lua`, pont, traductions
  - Faire : constaté en jeu le 2026-10-11 : la voix n’a pas donné les indices du lieu (le joueur ne peut pas trouver la maison) ; les indices doivent être dits par la voix (prompt explicite) et affichés dans la page Missions du carnet (traduits) ; titre de la mission « First aid for a survivor » faux pour une reconnaissance ; ligne « CharacterReputation: business API unavailable » à retirer ou reformuler.
  - Accepté si : indices visibles dans le carnet et cités par la voix ; titre propre au gabarit ; aucune ligne technique dans la fiche
  - Tests : banc ; essai solo
  - Preuve : causes : réponse `start_mission` diffusée avant le choix du lieu (indices seulement à l'appel suivant, aucune consigne) ; titre de liste toujours `IGUI_RS_FirstAid` ; ligne `ReputationUnavailable` sans condition ; corrigé : demande de consigne `…-brief` mise en file par le serveur après la création (tour `briefing`, hors plafond et budget, sans blocage de l'appelant), prompt « dire le type de lieu et tous les indices » et rappel des indices sur demande ; indices du carnet en données `{key, args}` (`RS_Rescue.clueData`, sans chiffre ni coordonnée) traduits côté client (59 clés EN/FR) ; titre par `titleKey` du gabarit ; ligne technique retirée de la fiche ; `test_carnet.py` 59, `test_protocol.py`, `test_rescue.py` 22, `test_rs_suites.py` OK ; suite `rs.missions.radio` (titre, indices, tour `briefing`) ; `run_all.py` 44/44 le 2026-10-11, luacheck 17/0 et 0 ; `docs/protocole-carnet-v2.md`, `carnet-implementation-04221.md`, `rescue.md`, `persona-format.md`, `tests-en-jeu.md` ; **en jeu solo le 2026-10-11** (partie `2026-10-11_17-54-58`) : indices dits par Walt et affichés au carnet, titre correct, validé par l'utilisateur
  - Reste : en jeu solo, pont connecté (FR puis EN) : demander du travail à Walt → seconde réponse avec type de bâtiment et indices ; page Missions : « Reconnaissance pour un survivant », indices traduits, aucune ligne CharacterReputation ; « c’est où ? » → indices redits ; langue de la consigne à confirmer en FR ; anciennes missions sans indices ; ligne ReputationUnavailable encore sur la page Réputation

- [x] **E11-T10** — Zone approximative du lieu sur la carte
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E11-T09
  - Fichiers : `RS_MissionScout.lua`, `RS_MapMarks.lua` (+ client `RS_MapActions`), traductions
  - Faire : constaté en jeu le 2026-10-11 : missions de reconnaissance trop difficiles, indices insuffisants pour trouver le bâtiment ; décision du 2026-10-11 : à la création, une zone approximative (environ un pâté de maisons, décentrée pour ne pas désigner le bâtiment) est tracée sur la carte du joueur ; distance des cibles inchangée ; précision du 2026-10-11 : la zone est **effacée** de la carte à la fin de la mission (réussite, abandon, expiration).
  - Accepté si : la zone apparaît sur la carte à la création d'une mission scout, contient le bâtiment sans en marquer le centre exact ; retirée ou marquée terminée à la fin de la mission
  - Tests : banc ; essai solo
  - Preuve : zone calculée par le serveur à la création (`Scout.mapZone` : cercle de 30 cases, agrandi pour un grand bâtiment, emprise contenue, centre décalé par tirage à graine `mission:lieu`), gardée dans l'état privé, projetée au seul participant (`p.mapZone`) ; client `MapActions.zones` : symbole vanilla `Circle` mis à l'échelle du monde (`WorldMapBaseSymbol` `applyZoom`, `getDisplayScale`) + libellé traduit `addTranslatedText`, reconnu par couleur/alpha, **retiré** à la réussite, l'abandon, l'expiration et à la reconnexion si la fin a eu lieu hors connexion, reposé une fois par session (persistance `map_symbols.bin`) ; ligne du carnet « zone entourée sur votre carte » ; consigne du pont (la voix peut renvoyer à la carte) ; `test_carnet.py` 64 (5 nouveaux), suite `rs.missions.radio` (zone, retrait) ; `run_all.py` 44/44 le 2026-10-11, luacheck 16/0 et 0 ; `docs/carnet-implementation-04221.md`, `tests-en-jeu.md` ; base `world-map.md`
  - Reste : en jeu solo : mission de Walt → cercle orange « Zone de reconnaissance (Walt) » sur la carte, bâtiment dedans hors centre ; rechargement sans doublon ; compte rendu ou abandon → cercle retiré ; rendu du trait à voir ; missions antérieures sans zone ; MP à la séance finale

- [x] **E11-T11** — Zone sur la carte pour une mission de reconnaissance donnée par un PNJ
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E11-T10
  - Fichiers : `RS_MissionScout.lua`, `RS_Carnet_Server.lua`, `RS_MapActions.lua`
  - Faire : constaté en jeu le 2026-10-11 : une mission de reconnaissance proposée par un PNJ Living Knox et reçue par le joueur n'est pas entourée sur la carte (la zone `mapZone` existe pourtant dans l'état serveur) ; trouver pourquoi (offre, acceptation, participant, projection) et afficher la zone comme pour Walt, retirée à la fin.
  - Accepté si : mission d'un PNJ acceptée → zone sur la carte ; retirée à la fin
  - Tests : banc ; essai solo
  - Preuve : aucun défaut de code : dans la partie de l'essai, la mission du PNJ (Maggie Velez, `scout_v1`) était encore une **offre** non acceptée (`state = offer`, `participants` vide, `mapZone` déjà calculé) ; une mission de voix radio est acceptée d'office (`RS_MissionVoice.lua:110`), celle d'un PNJ par le bouton « Accepter » du carnet (`RS_Notebook.lua:496`) ; la zone n'est tracée qu'après acceptation (`p.engaged`) ; test `ScoutMissionTests.test_npc_offer_area_only_after_acceptance_then_removed` (offre sans zone, acceptation → zone au nom du PNJ, autre joueur sans rien, abandon → retrait) vert sans correction ; `test_carnet.py` 65, `run_all.py` 44/44 le 2026-10-11, luacheck 16/0 et 0 (référence abaissée à 16) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.missions.solo « npc scout mission: zone only after Accept, removed after Abandon » PASS (`20261013-202155-solo.txt`)
  - Reste : en jeu solo : carnet → Missions → offre du PNJ → Accepter → cercle au nom du PNJ sur la carte, retiré à l’abandon ou au compte rendu ; le dialogue du PNJ peut laisser croire que la mission est déjà donnée (décision à prendre)

- [x] **E11-T12** — Avertissements « Missing arguments » des indices du carnet
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E11-T09
  - Fichiers : `RS_Notebook.lua` (`clueText`)
  - Faire : constaté dans `console.txt` le 2026-10-11 : des dizaines de `Translator ... Missing arguments for "IGUI_RS_Clue_*"` à chaque affichage de la fiche ; `getTextOrNull(key)` appelé sans arguments sur des clés à `%1` ; tester l'existence d'une clé sans déclencher l'avertissement.
  - Accepté si : plus aucun avertissement « Missing arguments » à l'affichage d'une fiche avec indices
  - Tests : banc
  - Preuve : cause : `getTextOrNull(key)` formate le texte d'une clé existante (`Translator.java:386-419`, `reportMissingArgumentsFromPastAbuse`) et, sans arguments sur un texte à `%1`, journalise « Missing arguments » (95 lignes dans `console.txt` le 2026-10-11) ; `clueText` passe désormais les mêmes arguments au test d'existence et à l'affichage (texte identique) ; `test_carnet.py` `test_clues_read_without_missing_arguments` (doublures fidèles au Java, en échec avant, vert après) ; `run_all.py` 44/44 le 2026-10-11, luacheck 16/0 et 0 ; base `load-warnings.md`
  - Reste : en jeu : ouvrir une fiche de mission avec indices, plus aucune ligne « Missing arguments for IGUI_RS_Clue_ » dans console.txt

- [ ] **E11-T13** — Compte rendu au demandeur : la mission se valide en le disant au PNJ ou à la radio
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : E11-T04, E11-T06, E11-T07
  - Fichiers : `RS_Missions.lua` ; `RS_MissionClear.lua`, `RS_MissionRecover.lua`, `RS_MissionSignal.lua` ; `RS_MissionVoice.lua` ; `RS_Carnet_Server.lua` ; pont et `docs/protocole-carnet-v2.md` (contexte du compte rendu) ; carnet (état de la mission) ; traductions
  - Faire : décision de l'utilisateur du 2026-10-14 (E11-T04, E11-T06, E11-T07) : plus de réussite automatique pour les gabarits `clear`, `recover` et `signal`. L'objectif rempli (décompte atteint, sac déposé, signal vu) met la mission dans un état « à rapporter » vérifié par le serveur ; elle ne réussit que lorsqu'un participant revient le dire : au PNJ demandeur en personne (en lui parlant) ; pour une mission donnée par une voix radio, en l'annonçant à la radio sur la fréquence de cette voix. Le serveur vérifie que l'objectif est rempli et que l'interlocuteur est le demandeur ; une affirmation sans objectif rempli ne valide rien. « Réclamer » et la récompense suivent la réussite comme aujourd'hui. Le reste des choix (cercles, tables, couleurs, `place_cache`) est inchangé. `scout` suit la même règle (réponse « mission d'une voix radio : le dire à la radio », 2026-10-14) : donné par une voix, il se valide en l'annonçant sur sa fréquence ; donné par un PNJ, compte rendu de vive voix (déjà le cas) ; demandeur mort ou groupe disparu entre l'objectif et le compte rendu : à traiter dans la tâche.
  - Accepté si : au banc : objectif rempli sans compte rendu = mission non réussie (état « à rapporter » affiché au carnet) ; parler au PNJ demandeur après l'objectif = réussite ; parler à un autre PNJ ou affirmer sans objectif rempli = rien ; mission d'une voix : annonce sur sa fréquence = réussite, autre fréquence = rien ; mêmes résultats pour `clear`, `recover`, `signal`.
  - Tests : banc `lupa` (`tests/test_mission_clear.py`, `test_mission_recover.py`, `test_mission_signal.py`, `test_protocol.py`) ; suites `rs.mission.clear`, `rs.mission.recover`, `rs.mission.signal` dans la campagne MP automatique.
  - Preuve : plus de réussite automatique pour `clear`, `recover`, `signal` et `scout` : objectif rempli = mission active « à rapporter » (carnet : « Objectif rempli — à rapporter au demandeur », court « À rapporter ») ; réussite seulement par l'intention fermée `report_done` du modèle sur `context.reportable` revérifié par le serveur (demandeur, participant, objectif), bouton « Rendre compte » près du corps du demandeur sans pont, ou action radio `report_mission` d'une voix (refus `not_done`, `no_mission`) ; demandeur mort = `cancelled_dead` sans malus ; aucune lecture du texte du joueur par mots-clés ; bancs `ReportCases` ×3, test_mission_clear 12, test_mission_recover 15, test_mission_signal 13, test_carnet, `scenario_report_done_bridge` ; run_all 127/127 ; luacheck 15/0 ; `protocole-carnet-v2.md` « Compte rendu au demandeur » ; commit `a4d88b9` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.mission.clear, rs.mission.clearcount, rs.mission.recover, rs.mission.retrieve, rs.mission.signal 1/1 chacune (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`), rs.missions.radio 1/1 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; vrai modèle deepseek-v4-flash en solo : suite `rs.missionreport.llm` 2/2 trois fois (voix Darlene : `start_mission` puis `report_mission` à la radio ; PNJ demandeur : `report_done`), `tools/autoclient/runs/20261015-133617-1f165e1e489c`, `20261015-133120-f2e6e922b012`, `20261015-133351-dc81e1b10d79` ; Darlene et Cody donnent des missions `scout` (commit `15134f3`)
  - Reste : compte rendu par le vrai modèle en MP non vu ; seules les missions `scout` peuvent être données par une voix (`RS_MissionVoice.TEMPLATES`, pont `MISSION_TEMPLATES`) ; la réponse de consigne repropose `start_mission` (refusé par le serveur, appel inutile)

- [x] **E11-T14** — Écouteur Signal Smoke abonné deux fois après `Signal.resetForTests`
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E11-T07
  - Fichiers : `RS_MissionSignal.lua`
  - Faire : relevé le 2026-10-15 (agent des campagnes) : `Signal.resetForTests()`, appelé par les suites `rs.mission.signal` et `rs.mission.nosignal`, réabonne l'écouteur de mission à Signal Smoke à l'installation suivante : le mod peut s'abonner deux fois dans la même session (signal compté deux fois). Abonnement idempotent (une seule fois par session, quelle que soit la remise à zéro).
  - Accepté si : au banc, deux installations après une remise à zéro = un seul abonnement ; un signal compté une fois.
  - Tests : banc `tests/test_mission_signal.py`.
  - Preuve : abonnement par module gardé pour la session (`subscribedTo`), `resetForTests` ne l'efface plus ; banc `test_mission_signal.py` 14 OK dont `test_reset_does_not_subscribe_the_listener_twice` (3 abonnés avant la correction, 1 après, signal jugé une fois) ; luacheck 15/0 ; commit `f1b0d6c`
  - Reste : —

- [x] **E11-T15** — Fiches et contrat fermé des missions et récompenses
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E11-T08
  - Fichiers : modules RadioSurvivor, bridge, tests, dev/batman_RadioSurvivorTests, docs
  - Faire : Lecteurs Python/Lua strictement identiques, fiches livrées et empreintes ; protocole, faux modèle déterministe.
  - Accepté si : mécanismes et isolation bénéficiaire vérifiés, sans récompense doublée ni secret dans le prompt.
  - Tests : tests/test_personas.py ; tests/test_protocol.py
  - Preuve : `tests/run_all.py --keep-going` : 140 étapes vertes le 2026-10-15 ; 15 avertissements Contents et 0 dev (références inchangées) ; suites en jeu ajoutées, pas encore exécutées.
  - Reste : campagnes solo/MP pour les tâches de cible MP. Les contrats supply dont le lot a déjà été prélevé conservent ce lot ; pas de second prélèvement.

- [ ] **E11-T16** — Récompenses serveur des voix : cache, fréquence, carte et leçon
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E11-T15
  - Fichiers : modules RadioSurvivor, bridge, tests, dev/batman_RadioSurvivorTests, docs
  - Faire : Registre privé anti-doublon, rotation, cache différée au lieu de fiche, répertoire individuel, carte vanilla et XP serveur plafonnée.
  - Accepté si : mécanismes et isolation bénéficiaire vérifiés, sans récompense doublée ni secret dans le prompt.
  - Tests : banc récompenses ; suites solo/MP et client 2
  - Preuve : `tests/run_all.py --keep-going` : 140 étapes vertes le 2026-10-15 ; 15 avertissements Contents et 0 dev (références inchangées) ; suites en jeu ajoutées, pas encore exécutées.
  - Reste : campagnes solo/MP pour les tâches de cible MP. Les contrats supply dont le lot a déjà été prélevé conservent ce lot ; pas de second prélèvement.

- [ ] **E11-T17** — Gabarits de missions des voix avec compte rendu radio
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E11-T15
  - Fichiers : modules RadioSurvivor, bridge, tests, dev/batman_RadioSurvivorTests, docs
  - Faire : scout, deliver, retrieve, clear, signal selon fiche ; objectifs vérifiés côté serveur, règles des gabarits préservées.
  - Accepté si : mécanismes et isolation bénéficiaire vérifiés, sans récompense doublée ni secret dans le prompt.
  - Tests : banc missions ; campagnes solo/MP ; voix vrai modèle
  - Preuve : `tests/run_all.py --keep-going` : 140 étapes vertes le 2026-10-15 ; 15 avertissements Contents et 0 dev (références inchangées) ; suites en jeu ajoutées, pas encore exécutées.
  - Reste : campagnes solo/MP pour les tâches de cible MP. Les contrats supply dont le lot a déjà été prélevé conservent ce lot ; pas de second prélèvement.

- [ ] **E11-T18** — Récompenses et offres des PNJ Living Knox
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E11-T16
  - Fichiers : modules RadioSurvivor, bridge, tests, dev/batman_RadioSurvivorTests, docs
  - Faire : Stock réel rationné, tables selon groupe, fréquence, carte, leçon par rôle ; retrait partagé, contrôle décès et relations.
  - Accepté si : mécanismes et isolation bénéficiaire vérifiés, sans récompense doublée ni secret dans le prompt.
  - Tests : banc PNJ ; campagnes solo/MP ; confidentialité client 2
  - Preuve : `tests/run_all.py --keep-going` : 140 étapes vertes le 2026-10-15 ; 15 avertissements Contents et 0 dev (références inchangées) ; suites en jeu ajoutées, pas encore exécutées.
  - Reste : campagnes solo/MP pour les tâches de cible MP. Les contrats supply dont le lot a déjà été prélevé conservent ce lot ; pas de second prélèvement.


- [ ] **E11-T19** — Livraison radio discrète après éloignement
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E11-T17
  - Fichiers : module serveur de dépôt, `RS_MissionVoice.lua`, configuration, carnet, traductions EN/FR, bancs et suites ; protocole et wiki EN/FR
  - Faire : alterner boîte convenue et sac caché près d'un `place=` avec repère exact individuel et repli sac ; constater le lot complet, attendre 10 secondes réelles sans joueur à moins de 40 cases horizontalement, puis retirer une seule fois avec la case exacte chargée. Refuser le contenu étranger du sac, permettre la reprise avant collecte, relancer le délai au redémarrage ; rendre ensuite l'objectif rapportable à la radio.
  - Accepté si : aucun retrait devant un joueur, même à un autre étage ; lot incomplet ou repris non validé ; boîte et autres objets préservés ; sac admissible retiré entièrement une seule fois ; compte rendu prématuré refusé ; client 2 voit le retrait physique sans données privées du participant.
  - Tests : banc `lupa` (distance, délai, reprise, redémarrage, case déchargée, contenu étranger, anti-doublon) ; suites solo et MP à deux clients
  - Preuve : `tests/test_voice_delivery.py` 22/22 ; suite `rs.voicedelivery` ajoutée aux campagnes solo et MP ; aucune preuve en jeu à ce stade
  - Reste : campagnes solo/MP ; reprise ambiguë après interruption bloquée sans crédit automatique.
