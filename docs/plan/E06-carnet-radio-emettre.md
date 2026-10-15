# E06 — Carnet radio et module « Émettre »

**Objectif.** Remplacer le parcours en cinq gestes (clic droit, « Parler », champ, saisie, envoi) par un module « Émettre » dans la fenêtre radio vanilla et un onglet Radio dans le carnet qui garde les conversations par fréquence (note de travail §03).

**Dépend de.** E05-T03 (routage par voix).

**Sources.** Note de travail §03 ; base `ui-windows.md` (section de mod dans la fenêtre radio `ISRadioWindow` : modules `RWMPanel`, `readFromObject`, manette ; `ISTextEntryBox` et focus clavier ; `ISRichTextPanel`) ; base `multiplayer.md` (micro d'une radio non transmis au serveur ; état d'une radio d'inventaire appliqué par le serveur en main seulement ; radio posée sans contrôle d'accès) ; base `radio-dynamic.md` (le joueur qui parle dans une radio, `processSayMessage` relayé en `RadioChat` en MP, talkie à la ceinture sans menu de réglage).

## Décisions

- Acquises : carnet radio ouvert depuis la radio et depuis le module, sans touche dédiée ; module ajouté par `ISRadioWindow:addModule` sans remplacer la fenêtre ; module visible seulement pour une radio émettrice ; talkies, radio posée (HAM) et autoradio.
- Note : la note de travail disait « pas de touche dédiée » pour le carnet radio ; le carnet unique (0.2) a depuis reçu un bouton latéral et Ctrl+G. E06-T01 confirme l'articulation.
- 2026-10-08 — **E06-T01 (1)** : historique radio gardé **côté serveur**, dans l'état privé, par personnage, borné à 40 lignes par fréquence.
- 2026-10-08 — **E06-T01 (2)** : le carnet radio est un **onglet « Radio »** du carnet unique (historique par fréquence, voyant).
- 2026-10-08 — **E06-T01 (3)** : le menu « Parler sur 145.0 MHz » est **retiré** une fois le module « Émettre » validé en jeu.
- 2026-10-09 — **Refonte du carnet** : l'interface actuelle est jugée à revoir entièrement (essai solo). Direction retenue : **maquette A « carnet papier »** (`docs/maquettes/carnet-papier.dc.html`, artefact https://claude.ai/artifact/Ra7q7mWqrAT1879DRxaWG2) : papier ligné, reliure à anneaux, onglets en marque-pages sur le bord droit, répertoire des fréquences à gauche avec le bouton « Régler ma radio » sous la liste (déplacé par l'utilisateur pour ne pas recouvrir les onglets), conversation au centre, saisie « Dire : » + « Émettre » dans l'onglet, point orange par fréquence non lue.

## Tâches

- [x] **E06-T01** — Historique radio et articulation avec le carnet unique
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier ; note de travail §10
  - Faire : poser les questions une à une.
  - Accepté si : décisions consignées.
  - Tests : —
  - Preuve : décisions du 2026-10-08 (section Décisions)
  - Reste : —

- [x] **E06-T02** — Module « Émettre » dans la fenêtre radio
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E06-T01
  - Fichiers : `media/lua/client/RadioSurvivor/RS_RadioModule.lua`
  - Faire : module `RWMPanel` : ligne de saisie (Entrée émet), deux dernières lignes reçues, bouton qui ouvre le carnet ; visible seulement si la radio émet (`getIsTwoWay`), allumée, micro ouvert ; focus clavier rendu à la fermeture (piège `ISTextEntryBox`) ; manette.
  - Accepté si : talkie en main, sur le dos, radio HAM posée et autoradio affichent le module ; une radio réceptrice ne l'affiche pas ; les touches du jeu reviennent après fermeture.
  - Tests : suite en jeu `rs.radiomodule` (présence selon le type de radio) + protocole visuel.
  - Preuve : 2026-10-09 : `RS_RadioModule.lua` (section ajoutée par enveloppe de `ISRadioWindow.createChildren`, visibilité relue à chaque image), chemin d'envoi partagé `RS_RadioTalk.lua` (menu et module), deux dernières lignes par fréquence (`OnDeviceText`), focus rendu (envoi, Échap, fermeture), manette (A, Y, X) ; radio posée = `IsoWaveSignal`, autoradio = `VehiclePart`, émettrice seulement en `Radio_HAM` ; `tests/test_radio_module.py` 19/19, suites `rs.radiomodule` ; `tests/run_all.py` 25/25 ; serveur dédié de test 50 PASS / 3 SKIP ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.radiomodule 7/7 dont l'envoi par Entrée vers Walt avec le pont (`20261013-202155-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.radiomodule 5/5 sur un client MP (passage 20261014-143503-mp-933f87610eb9) (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`)
  - Reste : protocole visuel solo (`docs/tests-en-jeu.md`, E06-T02) ; HAM posée et autoradio : envoi refusé (`NoRadio`) jusqu'à E06-T03 ; Entrée du clavier à l'écran à vérifier ; la campagne MP automatique passe (2026-10-14) ; restent pour la séance finale les contrôles à deux joueurs actifs et à la main ci-dessus

- [x] **E06-T03** — Validation serveur d'une émission depuis radio posée ou autoradio
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E06-T02
  - Fichiers : `RadioSurvivor_Server.lua` (contrôles), `RadioSurvivor_Client.lua`
  - Faire : étendre les contrôles serveur (aujourd'hui : radio émettrice en main ou sur le dos) aux radios posées à portée et à l'autoradio du véhicule occupé ; l'état allumé et le canal se vérifient comme aujourd'hui côté client quand le serveur ne les connaît pas.
  - Accepté si : un joueur loin de la radio posée est refusé ; un passager d'un véhicule avec autoradio émet.
  - Tests : banc `lupa` ; suite en jeu MP.
  - Preuve : 2026-10-09 : le serveur connaît allumage et canal d'une radio posée ou d'une autoradio (`RadioDeviceDataState`, `GameServer.java:3480-3530`), micro jamais transmis ; commande `talk` avec `source=world` (case + index) ou `source=vehicle` (`vehicleId`, pièce) ; contrôles serveur : portée `MicRange` même étage (`TooFar`), joueur assis dans le véhicule (`NotInVehicle`), émettrice, éteinte (`Off`), canal du serveur prioritaire ; ancien client inchangé ; banc `WorldRadioServerTests` 16 tests, `scenario_world_radios_mp` ; `tests/run_all.py` 25/25 ; serveur dédié de test 50 PASS / 3 SKIP. ; suite en jeu écrite le 2026-10-15 (`rs.carnet.load`/`rs.worldradio`/`rs.radio`/`rs.observations`/`rs.factions.mandate` selon la tâche, étapes client `RST_PeerChecksRadio.lua`), banc `tests/test_rs_mp_suites.py` 29 OK (échoue sur les défauts injectés), commit `446a39d` ; suite corrigée (`0d1b6fa` : `Base.HamRadio1` installé avant `Radio_HAM`) ; campagne MP complète du 2026-10-15 4 h 08 : rs.worldradio 2/2 (radio posée acceptée à 1 case, refusée à 10, éteinte refusée, passager de l'autoradio accepté, client 2 dehors refusé) (`tools/autoclient/runs/20261015-040851-mp-5c884ff76aeb/server/20261015-021039-server.txt`)
  - Reste : —

- [x] **E06-T04** — Onglet Radio du carnet : historique par fréquence et voyant
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E06-T01
  - Fichiers : `RS_Notebook.lua` ; stockage selon E06-T01
  - Faire : conversation par fréquence (dit, répondu, entendu), voyant de réception quand le carnet est réduit, répertoire des fréquences entendues réglables d'un clic sur la radio en main.
  - Accepté si : une réponse reçue carnet fermé est relue à l'ouverture ; le réglage d'un clic change bien la fréquence de la radio équipée.
  - Tests : banc `lupa` (historique borné) ; protocole visuel.
  - Preuve : 2026-10-09 : `RS_RadioLog.lua` (état privé par personnage, 40 lignes × 8 fréquences, dit/répondu/entendu, effacé à la mort) ; « entendu » signalé par le client et admis seulement si diffusé par le serveur sur cette fréquence depuis moins de 5 min (sondage borné) ; onglet Radio (`RS_RadioHistory.lua` : répertoire, conversation colorée, « Régler ma radio » par `ISRadioAction SetChannel`, voyant sur le bouton Carnet) ; `tests/test_radio_history.py` 20/20 ; `tests/run_all.py` 26/26 ; serveur dédié de test 50 PASS / 3 SKIP. ; **en jeu solo le 2026-10-10** (partie `rstest-1010`, retour de l’utilisateur) : onglet Radio du carnet affiche la fréquence et l’historique après un échange
  - Reste : protocole visuel solo (`docs/tests-en-jeu.md`, E06-T04) ; réglage d'une radio sur le dos à vérifier ; voyant éteint après reconnexion.

- [x] **E06-T05** — Validation multijoueur du carnet radio
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E06-T03, E06-T04
  - Fichiers : protocole
  - Faire : deux joueurs sur la même fréquence et sur deux fréquences ; reconnexion (historique conservé selon E06-T01) ; aucun historique d'un autre joueur reçu.
  - Accepté si : suites et protocole passés.
  - Tests : `RST.server('rs.radio')`.
  - Preuve : suite en jeu écrite le 2026-10-15 (`rs.carnet.load`/`rs.worldradio`/`rs.radio`/`rs.observations`/`rs.factions.mandate` selon la tâche, étapes client `RST_PeerChecksRadio.lua`), banc `tests/test_rs_mp_suites.py` 29 OK (échoue sur les défauts injectés), commit `446a39d` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.radio 2 PASS (`NoRadio` sans radio, onglets Radio des deux joueurs sur une puis deux fréquences, étapes rs.talk et rs.history du client 2 vertes) + 1 SKIP renvoyé à la base `rs.radiotab` (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : rs.radiotab.before et rs.radiotab.after-reconnect PASS (historique gardé après reconnexion) (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093457-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093730-server.txt`)
  - Reste : —

- [x] **E06-T06** — Refonte visuelle du carnet (maquette A « carnet papier »)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E06-T04
  - Fichiers : `RS_Notebook.lua`, `RS_RadioHistory.lua`, textures du carnet (`media/textures/`), traductions
  - Faire : appliquer la maquette A à tout le carnet (quatre onglets en marque-pages, papier ligné et reliure par textures du mod, polices du jeu ; aucune police externe) ; onglet Radio : répertoire à gauche avec « Régler ma radio » dessous, conversation, saisie « Dire : » et « Émettre » (même chemin d'envoi que le module), point orange par fréquence non lue ; Contacts, Missions, Réputation dans le même style ; lisibilité (contraste, largeurs selon la langue).
  - Accepté si : l'utilisateur valide l'aspect en jeu ; aucun texte qui déborde en français et en anglais ; les fonctions existantes du carnet restent identiques.
  - Tests : banc `lupa` (`test_carnet.py`, `test_radio_history.py`) ; protocole visuel solo.
  - Preuve : 2026-10-09 : interface du carnet réécrite d'après la maquette A (papier, reliure à anneaux, marque-pages à droite, boutons tampons) ; onglet Radio : fréquences entendues avec « Régler ma radio » dessous, point non lu par fréquence, conversation colorée, saisie « Dire : » par `Talk.send` ; textures générées par `tools/gen_notebook_textures.py` (facultatives) ; tests carnet, historique, module à jour ; `tests/run_all.py` 27/27 ; serveur dédié de test 50 PASS / 3 SKIP. ; **en jeu solo le 2026-10-10** (partie `rstest-1010`, retour de l’utilisateur) : correctif `8eddfc3` vérifié (aucun ascenseur vanilla au milieu des panneaux, message PNJ seulement dans Contacts)
  - Reste : validation visuelle en jeu par l'utilisateur (`docs/tests-en-jeu.md`, « Carnet papier (E06-T06) ») ; ⚠ étiquette « Réponse » au lieu du nom de la voix, fenêtre de livraison restée vanilla.
