# LK03 — Exécution multijoueur complète

**Objectif.** Rendre l'exécution des PNJ robuste à plusieurs joueurs : consignes serveur versionnées, rapports contrôlés, transferts de propriété, corps sans propriétaire, relais des gestes filtré par distance.

**Dépend de.** LK02-T09 (décision « continuer »).

**Sources.** Base `multiplayer.md` ; mesures du jalon (`docs/annexes/tests/validation/jalon1-*.md`) ; liste de problèmes à prévoir dans `docs/annexes/recherches/alife-analyse.md` §1 (confiance au propriétaire, perte d'état au transfert, corps possédés par le serveur, diffusion sans filtre).

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Tâches

- [ ] **LK03-T01** — Consignes serveur versionnées et réémission
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK02-T09
  - Fichiers : `LK_Directives.lua`
  - Faire : file de consignes par PNJ avec révision ; envoi aux seuls clients proches ; réémission à l'apparition du corps, à l'arrivée d'un joueur et au changement de propriétaire ; consigne périmée ignorée.
  - Accepté si : aucune consigne exécutée deux fois ni perdue lors d'un transfert ou d'une reconnexion.
  - Tests : banc (transferts, reconnexions) ; suite `lk.directives`.
  - Preuve : `LK_Directives.lua` : numéro de consigne `v` croissant par PNJ, bail `l` et exécutant désigné `o` (nouveau bail à chaque consigne, changement de propriétaire ou retour de l'exécutant), numéro d'envoi `r`, ordre des rapports `n` ; envoi aux seuls joueurs à 100 cases et au propriétaire (`GameServer.java:2615-2616`, `NetworkZombieManager.java:121-127`), `{ gone }` à la sortie du rayon ; réémission par `Directives.watch` (changement de propriétaire, réapparition du corps, arrivée d'un joueur), `dirAsk` du client et `guardHello` à la reconnexion ; `LK_Executor.lua` : exécution seulement si le corps est simulé localement et `o` est son compte, consigne périmée ou déjà menée refusée (`mayStart`), reprise à l'étape `k` publiée ; rapports acceptés du seul bail courant, rapport final de l'ancien bail accepté 2 s ; solo inchangé ; `test_lk_directives.py` 42/42 (8 nouveaux : désordre, doublon, transfert au milieu d'une consigne à étapes, reconnexion, réapparition), `test_lk_milestone.py` 13/13, VM Kahlua 28/28 ; suite `lk.executor` étendue ; `tests/run_all.py` 37/37 le 2026-10-10, luacheck 17/0 et 0 ; `docs/annexes/conception/consignes.md` ; base `multiplayer.md` (changement de propriétaire d'un zombie) ; E07-T08 : commit `40c2658` ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.executor 3 PASS + 2 SKIP (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : lk.executor 5/5, dont « unloaded body: no state report refused, reports and walk resumed on return » (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.executor 4 PASS + 1 SKIP, « body reappearance » PASS (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : lk.rejoin.before et lk.rejoin.after-reconnect2 PASS (reconnexion de l'exécutant sans consigne doublée ni perdue) (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093501-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093552-server.txt`)
  - Reste : transfert au milieu d'une consigne : lk.handover FAIL, reprise mesurée à 3,4 s après le changement de propriétaire (> 1 s) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; `poseState` encore diffusé à tous (LK03-T05)

- [x] **LK03-T02** — Rapports du propriétaire contrôlés
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK03-T01
  - Fichiers : `LK_Executor.lua`, `LK_Reports.lua` (server)
  - Faire : position, activité, santé et pose rapportées par le seul propriétaire réel, à cadence bornée ; le serveur vérifie propriétaire, génération, vitesse de déplacement plausible, santé non croissante sans soin ; écart = rapport refusé et journalisé.
  - Accepté si : un rapport d'un autre client ou incohérent est refusé ; aucun « téléport » accepté.
  - Tests : banc (rapports forgés) ; suite en jeu.
  - Preuve : `LK_Reports.lua` : rapports d'état (position, angle, activité, santé, pose, bail `l`) du seul propriétaire et exécutant `o` du bail courant (`Directives.isOwner`), contrôles dans l'ordre forme et bornes, propriétaire, bail, cadence (seau de 5/s), numéro `n` croissant, plausibilité (≤ 6 cases de la copie serveur, ≤ 3 + 8 cases × durée à l'horloge du serveur, montée et chute bornées d'après `IsoGameCharacter.java:8679-8685`, santé jamais en hausse sans `noteHeal`) ; écart = rapport refusé, journalisé, état serveur inchangé ; aucun déplacement du corps (pas de « téléport ») ; seuils dans `Config.REPORTS` (vitesse 8 cases/s ; anti-triche vanilla des joueurs à 20 cases/s, `AntiCheatSpeed.java:16, 33`) ; `LK_Executor.stateReports` (1/s en mouvement, à chaque changement d'activité, sinon toutes les 5 s) ; bail renouvelé aussi pour une consigne close ; `tests/test_lk_reports.py` 12/12 (rapports forgés refusés, transfert, reconnexion), `test_lk_directives.py` 42/42 ; suite `lk.executor` étendue ; `tests/run_all.py` 38/38 le 2026-10-10, luacheck 17/0 et 0 ; `docs/annexes/conception/rapports.md` ; base `multiplayer.md` ; E07-T05 : commit `62bb327` ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.executor 3 PASS + 2 SKIP (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; suite en jeu écrite le 2026-10-15 (`lk.ownerreports`/`lk.handover`/`lk.relay`/`lk.spawnclean`/`lk.deathswing` selon la tâche, étapes client `RST_PeerChecksLK.lua`), banc `tests/test_lk_peer_suites.py` 26 OK (échoue sur les défauts injectés), commit `446a39d`; campagne MP complète du 2026-10-15 (client 2 actif, règle « les tests font foi ») : lk.ownerreports 2/2 (rapport d'un client qui ne simule pas le corps refusé et journalisé ; téléport puis hausse de santé refusés), étapes lk.report.forge client 2 #91, client 1 #92/#93 (`tools/autoclient/runs/20261015-024734-mp-348bee78d4b7/server/20261015-004928-server.txt`)
  - Reste : —

- [x] **LK03-T03** — Transfert de propriété sans perte d'état
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK03-T01
  - Fichiers : `LK_Executor.lua`
  - Faire : l'état utile (consigne, étape de routine, cible, arme, munitions) vit sur le serveur et est remis au nouveau propriétaire ; l'ancien cesse d'agir dès qu'il n'est plus propriétaire.
  - Accepté si : à deux joueurs qui s'approchent tour à tour, le PNJ poursuit son action sans arrêt de plus d'une seconde.
  - Tests : banc ; protocole à deux clients avec mesure.
  - Preuve : remise d'état `npcHand` au nouveau propriétaire (consigne et étape `k` de LK03-T01, bail, dernière santé acceptée appliquée seulement à la baisse dans 0..32,767 avant tout rapport, arme et révision de la table des armes ; munitions, étape de routine et cible en champs réservés) et à l'ancien qui se tait ; propriétaire comparé à chaque image côté serveur (`ownerWatch`), demande `dirClaim` du client, `waitLocal` ; rapports d'exécution revérifiés à l'envoi ; rapports d'un ancien propriétaire ignorés 4 s (`previous owner`) puis refusés ; mesure serveur `resumed by X <ms>` ; banc (serveur + 2 clients, 7 transferts, retard client de 0 à 9 images) : reprise ≤ 160 ms (moyenne 94 ms), arrêt le plus long 16 ms, aucun rapport refusé, consigne menée une seule fois ; `tests/test_lk_reports.py` 15/15 (`OwnershipHandoverTests`), `test_lk_directives.py` 42/42 ; `tests/run_all.py` 38/38 le 2026-10-10, luacheck 17/0 et 0 ; `docs/annexes/conception/consignes.md`, `rapports.md` ; base `multiplayer.md` ; LK03-T02 : commit `e6629db` ; suite en jeu écrite le 2026-10-15 (`lk.ownerreports`/`lk.handover`/`lk.relay`/`lk.spawnclean`/`lk.deathswing` selon la tâche, étapes client `RST_PeerChecksLK.lua`), banc `tests/test_lk_peer_suites.py` 26 OK (échoue sur les défauts injectés), commit `446a39d` ; passages MP ciblés du 2026-10-15 (commit `da1016e`, AWAY 20 cases) : lk.handover « two clients approach in turn » PASS deux fois (`tools/autoclient/runs/20261015-123958-mp-bd5895687617`, `tools/autoclient/runs/20261015-130404-mp-79b7311a6ebc`)
  - Reste : —

- [x] **LK03-T04** — Corps sans propriétaire et retrait
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK03-T02
  - Fichiers : `LK_Bodies.lua`
  - Faire : un corps possédé par le serveur (aucun joueur pertinent) ne reçoit plus de consigne d'action ; au-delà d'un rayon, le corps est retiré et le PNJ repasse en simulation abstraite (LK09) avec son état.
  - Accepté si : aucun PNJ figé visible d'un joueur ; aucun corps orphelin après retrait.
  - Tests : banc ; suite en jeu.
  - Preuve : corps possédé par le serveur en MP : consigne suspendue (`Directives.suspend`, bail `server`, temps suspendu hors délai), état neutre (arrêt, garde `useless`, geste `idle`, sans téléport), reprise de la même consigne et de l'étape `k` par le nouveau propriétaire client ; plus aucune exécution par le serveur (marche en ligne droite retirée) ; retrait loin des joueurs (`Bodies.releasePass`) : 120 cases (au-delà de la portée réseau de 96 et du rayon d'envoi de 100) pendant 60 s d'affilée, dernière position vue si hors zone chargée, jamais un corps simulé par un client ; passage en simulation abstraite : PNJ `virtual`, position à la case, santé `hp` (la plus basse, jamais relevée), arme et tenue gardées, consigne abandonnée (`{ gone }`), groupe et lien `npc` intacts ; `tests/test_lk_reports.py` 22/22 (`MultiplayerReleaseTests`, `SoloReleaseTests`), `test_lk_directives.py` 42/42, `test_lk_bodies.py` 54/54 ; suite en jeu `lk.bodies` (test `release`) ; `tests/run_all.py` 39/39 le 2026-10-10, luacheck 17/0 et 0 ; `docs/annexes/conception/corps-registre.md`, `consignes.md`, `simulation.md` ; base `zombies-as-npc-bodies.md` ; E11-T08 : commit `db95d77` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : retrait loin des joueurs observé (corps retirés après départ, réincarnés au retour) ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.bodies 6 PASS + 1 SKIP (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : corps possédé par le serveur à l'arrêt neutre puis consigne reprise par le nouveau propriétaire client ; corps mis de côté gardé dans `reanimated.bin` jusqu’au retour de son chunk (limite du moteur) ; `hp` pas encore réappliquée à l’incarnation suivante (LK09-T03, LK07)

- [x] **LK03-T05** — Relais des gestes filtré et borné
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK02-T07
  - Fichiers : `LK_Presentation.lua`, relais serveur
  - Faire : gestes envoyés seulement aux clients à portée de vue, à cadence bornée, avec regroupement ; budget réseau par tick ; mesure du trafic.
  - Accepté si : trafic proportionnel aux joueurs proches et non au nombre total de joueurs ; geste visible en moins de 300 ms sur réseau local.
  - Tests : suite `lk.presentation` + mesures.
  - Preuve : `LK_Relay.lua` : gestes et poses envoyés seulement aux clients des consignes (`Directives.targets`, 100 cases, propriétaire compris), état courant à l'entrée dans le rayon, `{ gone }` à la sortie ou à la disparition du PNJ, tout à `guardHello` ; message unique `animState` regroupé par client (`poseState` supprimé), numéro d'envoi `r` ; fenêtre de 150 ms par PNJ, budget de 16 messages par image (reste différé en tête), gestes importants (`strike`, poses finales) jamais écrasés ; mesures `Relay.stats` (messages, octets, délai d'émission) et ligne DEBUG ; serveur dédié à 10 images/s (`GameServer.java:261, 835-836`) : délai d'émission ≤ 250 ms ; `tests/test_lk_relay.py` 11/11 (2 puis 20 joueurs dont 2 proches : même trafic, 18 messages ; budget ; `strike` avant `idle`), `test_lk_anim.py` 9/9, `test_lk_directives.py` 42/42, `test_lk_equipment.py` 19/19 ; suite `lk.executor` (mesure du relais) ; `tests/run_all.py` 40/40 le 2026-10-10, luacheck 17/0 et 0 ; `docs/annexes/conception/corps-et-animations.md` ; base `multiplayer.md` ; E08-T07 : commit `20ff0be` ; suite en jeu écrite le 2026-10-15 (`lk.ownerreports`/`lk.handover`/`lk.relay`/`lk.spawnclean`/`lk.deathswing` selon la tâche, étapes client `RST_PeerChecksLK.lua`), banc `tests/test_lk_peer_suites.py` 26 OK (échoue sur les défauts injectés), commit `446a39d`; campagne MP complète du 2026-10-15 (client 2 actif, règle « les tests font foi ») : lk.relay 2/2, étapes client 2 lk.gesture.watch/seen #96-#101 (gestes vus 17 à 31 ms après leur pose) et lk.gesture.not #102 (client hors portée sans geste) (`tools/autoclient/runs/20261015-024734-mp-348bee78d4b7/server/20261015-004928-server.txt`)
  - Reste : —

- [x] **LK03-T06** — Apparition propre chez les clients MP (N1)
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK02-T02, LK02-T04
  - Fichiers : `LK_Bodies.lua`, `LK_ZombieGuard.lua`
  - Faire : le zombie temporaire de la création (chemin B) ne doit plus rester visible jusqu'à 5 s chez les clients proches, et la copie cliente d'un PNJ doit être muette dès son apparition, avant de recevoir la liste du serveur.
  - Accepté si : à deux clients, aucun zombie fantôme ni gémissement à l'apparition d'un PNJ.
  - Tests : banc ; séance MP finale.
  - Preuve : zombie fantôme : inexistant, le zombie temporaire de la création n'est jamais envoyé aux clients (Java : envoi après le Lua de l'image, retrait immédiat par `createCorpse`), règle écrite dans `Bodies.createBody` ; gémissement initial : liste `guardRoster` publiée dans l'image de la liaison avec l'identifiant de tenue du descripteur partagé, copie cliente rendue muette dès `OnZombieCreate` puis confirmée par `onlineId`, zombies récents retenus si la liste arrive après, voix recoupée 3 s après l'habillage ; `tests/test_lk_guard.py` 23/23 (`AppearanceTests`), `test_lk_bodies.py` 35/35, `tests/run_all.py` 19/19 le 2026-10-09 ; serveur dédié de test 6/6 ; protocole MP dans `docs/annexes/conception/neutralisation.md` ; LK06-T06 : commit `ecca303` ; suite en jeu écrite le 2026-10-15 (`lk.ownerreports`/`lk.handover`/`lk.relay`/`lk.spawnclean`/`lk.deathswing` selon la tâche, étapes client `RST_PeerChecksLK.lua`), banc `tests/test_lk_peer_suites.py` 26 OK (échoue sur les défauts injectés), commit `446a39d` ; dernière campagne MP complète du 2026-10-15 5 h 24 (client 2 actif) : lk.spawnclean 2/2, étape lk.appear.check verte chez les deux clients (apparition et retour de chunk : un seul corps, aucun fantôme, aucune voix) (`tools/autoclient/runs/20261015-052439-mp-4cf10c2eed18/server/20261015-032638-server.txt`)
  - Reste : reconnexion non automatisée (le critère ne l'exige pas)

- [x] **LK03-T07** — Pas de rapport d’état pour un corps déchargé
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK03-T02
  - Fichiers : `LK_Executor.lua`
  - Faire : constaté en jeu le 2026-10-11 : `state report on npc lk-n … refused: no body (embodied)` répété après la sortie de zone d’un corps ; l’émetteur cesse d’envoyer dès qu’il n’a plus de copie chargée.
  - Accepté si : plus de rapports refusés « no body » après un départ du joueur
  - Tests : banc
  - Preuve : cause : corps mis de côté au déchargement de son chunk = même objet Java, `isDead()` faux, gardé dans `Bodies.bound` mais retiré de `getZombieList()` (`IsoChunk.java:2987, 3005`, `IsoZombie.removeFromWorld`, `VirtualZombieManager.RemoveZombie`) ; l'exécutant le rapportait toujours (`knownBodies`), refusé `no body` (6 refus dans le journal du 2026-10-11 14:45) ; corrigé : `Executor.loadedBodies()` (vivant et dans `getZombieList()`) pour rapports, exécution, `dirAsk`/`dirClaim`, reprise au retour (premier rapport immédiat, consigne au même bail) ; refus serveur gardé, écrit une fois par PNJ, expéditeur et absence (`rejectAbsent`) ; `test_lk_reports.py` 25 (3 nouveaux, échouaient avec l'ancienne ligne) ; luacheck des deux fichiers sans avertissement ; `docs/annexes/conception/rapports.md` ; base `zombies-as-npc-bodies.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo lk.executor « unloaded body: no state report refused, reports and walk resumed on return » PASS (`20261013-202155-solo.txt`)
  - Reste : en jeu solo : s’éloigner d’un PNJ jusqu’au déchargement, aucune ligne « refused: no body », revenir : rapports et marche repris ; LK_Presentation, LK_SpeechView, LK_Equipment utilisent encore knownBodies sans ce filtre (sans effet réseau)
