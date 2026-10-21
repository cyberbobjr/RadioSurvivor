# E03 — Valider en jeu le carnet 0.2 et les correctifs E00

**Objectif.** Faire passer le carnet existant (dialogue de proximité, livraison M01, récompense) et les correctifs E00 de « testé hors jeu » à « testé solo » puis « testé MP », avec le moteur E01 et un protocole manuel pour ce qui demande un œil humain.

**Dépend de.** E00, E01-T04 à E01-T06.

**Sources.** [Validation 0.2](../tests/carnet-validation-04221.md) (parcours en huit points) ; [implémentation 0.2](../conception/carnet-implementation-04221.md) ; mémoire utilisateur : protocole nominal court d'abord, cas limites ensuite.

## Décisions

- 2026-10-08 — Bandits! abandonné le 2026-10-08 (`E17-T01`) : plus de parcours du carnet sur Bandits!. Le parcours complet (dialogue, livraison, récompense, deux joueurs, charge, LLM réel) sera rejoué avec un PNJ Living Knox dans `E17-T03`. Restent ici le rendu du carnet et les identités de personnage, indépendants du moteur de PNJ.
- 2026-10-09 — **E03-T02** reportée après `E17-T03` (choix de l'utilisateur) : le contrôle visuel se fera avec un carnet alimenté par des PNJ Living Knox (contacts, missions, fenêtre de livraison réels).
- 2026-10-14 — **E03-T02** : libellés d'état courts dans la liste, libellé long dans le détail (confirmé par l'utilisateur) ; changement (décision de l'utilisateur) : la clé `IGUI_RS_None` (FR « personne ») est inutilisée et sera supprimée de toutes les langues : tâche E03-T08.

## Règles

- Partie de test neuve `rstest-…` en 42.21, jamais une sauvegarde importante. Même variante Bandits! et mêmes mods côté serveur et clients.
- Un seul pont, `--offline` pour le parcours, puis un passage avec le LLM réel en fin d'étape.
- Chaque défaut trouvé devient une **nouvelle tâche** dans l'étape concernée (ou ici), pas une correction silencieuse.

## Tâches

- [ ] **E03-T01** — Suite en jeu « carnet » en solo, parcours nominal
  - État : `abandonné`
  - Cible : `solo`
  - Dépend de : E01-T06
  - Fichiers : suite `rs.carnet.solo`
  - Faire : bandit amical par fixture, Ctrl+G, `/say`, réponse du pont hors ligne, offre, acceptation, livraison de 6 pansements en deux fois, retrait du lot, état « expirée » d'une seconde offre ignorée (horloge simulée si nécessaire), réouverture du carnet.
  - Accepté si : la suite passe ; le fichier de rapport est consigné en preuve.
  - Tests : `RST.run('rs.carnet.solo')`.
  - Preuve : —
  - Reste : Bandits! abandonné le 2026-10-08 (`E17-T01`) : parcours rejoué avec un PNJ Living Knox dans `E17-T03`.

- [x] **E03-T02** — Protocole visuel du carnet (rendu ISUI)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E17-T02, E01-T04, E17-T03
  - Fichiers : `docs/annexes/tests/carnet-validation-04221.md` (résultats) ; captures dans `docs/annexes/tests/validation/`
  - Faire : rendu en 1280×720 et 1920×1080, petite et grande police, FR et EN, défilement, redimensionnement, réduction, fermeture, bouton latéral, raccourci, fenêtre de livraison et confirmations ; vérifier que le détail ne saute pas au rafraîchissement.
  - Accepté si : aucun texte tronqué ni bouton hors fenêtre ; anomalies transformées en tâches.
  - Tests : protocole manuel avec captures.
  - Preuve : banc `tests/test_notebook_visual.py` du 2026-10-14 (12 tests OK : la suite détecte bouton hors fenêtre, texte plus large que son bouton, chaîne FR trop longue, ancien minimum 660×480, confirmation d'une ligne, détail qui saute) ; suite `rs.notebook.visual` (carnet réel rempli d'un instantané fixe : ~430 chaînes EN/FR mesurées contre leur place à la police courante et une taille au-dessus ; 22 captures en 1280×720 et 1920×1080 fenêtré avec restauration ; défilement, détail stable à la mise à jour, repli, fermeture, bouton latéral, raccourci) ; défauts corrigés dans `RS_Notebook.lua` : taille minimale qui suit la police, colonne gauche élargie, libellés d'état courts `StateShort_*` dans la liste, confirmations coupées en lignes (FR `ConfirmSupply` 1 101 px) ; run_all OK (rs_suites recalé), luacheck 15/0 ; `docs/annexes/tests/carnet-validation-04221.md` ; base `ui-windows.md` (vérifier une fenêtre par script, taille de police au redémarrage), `logs-and-tools.md` (`setResolutionAndFullScreen` synchrone, `getScreenModes`, `takeScreenshot`) ; essai en jeu du 2026-10-14 : client automatique avec le pont et le vrai modèle (E01-T14) : rs.notebook.visual 3/3, 25 captures (`tools/autoclient/runs/20261014-111501-57d2c373af5b/20261014-091544-solo.txt`)
  - Reste : essai solo (n'importe quelle partie, ~30 s, sans toucher la souris) : `RST.run({ suite = "rs.notebook.visual" })` puis regarder les captures `Zomboid/Screenshots/rs_notebook_*.png` (encre et signets, anneaux après redimensionnement, points « non lu », défilement, carnet replié, dialogues) ; vraie grande police et seconde langue : relancer le jeu avec ce réglage et rejouer. Défauts restants (tâche E03-T07) : fenêtre de livraison ouverte au coin haut gauche ; noms d'objets de la livraison non coupés à la largeur de la liste.

- [ ] **E03-T03** — Parcours deux joueurs sur serveur dédié
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : E03-T01, E01-T05
  - Fichiers : suite `rs.carnet.mp` (serveur) ; protocole points 2 à 5 de la validation 0.2
  - Faire : A parle, B entend une seule réponse ; invitation et acceptation personnelle ; livraisons concurrentes ; deux retraits simultanés = un seul lot ; note privée de A invisible pour B ; canaux général, faction et privé sans effet.
  - Accepté si : suites serveur au vert et protocole passé ; inventaires cohérents après reconnexion.
  - Tests : `RST.server('rs.carnet.mp')` + protocole manuel.
  - Preuve : —
  - Reste : Bandits! abandonné le 2026-10-08 (`E17-T01`) : parcours rejoué avec un PNJ Living Knox dans `E17-T03`.

- [x] **E03-T04** — Reconnexion, redémarrage et mort réels (E00-T01, E00-T02)
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E01-T05
  - Fichiers : suite `rs.identity`
  - Faire : A se déconnecte et se reconnecte (même identité, notes, engagement) ; redémarrage du serveur (temps d'arrêt exclu du chrono) ; A meurt (identité retirée), crée un personnage (nouvelle identité, anciennes missions non reprises).
  - Accepté si : comportements conformes ; E00-T01 et E00-T02 passent à `testé MP`.
  - Tests : suite + protocole.
  - Preuve : suite `rs.identity` (invariants à tout moment) et étapes manuelles `rs.identity.before`, `.after-reconnect`, `.after-restart`, `.after-death` (tag `manual`, relevé dans `identity-snapshot.txt`) ; `run_dedicated_smoke.ps1 -Manual -CacheDir` pour relancer le même monde ; `tests/test_carnet.py` `IdentitySuiteTests` 8 (dont régressions E00-T01 et E00-T02 repérées), `tests/run_all.py` 21/21 le 2026-10-09 ; serveur dédié de test : 48 tests dont 45 PASS et 3 SKIP sans joueur ; protocole MP `docs/annexes/tests/tests-en-jeu.md` § 11 ; E03-T02 reportée : commit `abad8dd` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.death 2/2 (vraie mort du client 2, nouvelle identité, ancienne jamais revendiquée) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : rs.identity.after-reconnect et .after-restart : même monde, mêmes identités, notes et engagements gardés (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093730-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`) ; deux clients sur un même PC ; chrono de mission d'un vrai PNJ Living Knox (commit `76f4692`) : solo rs.identity 7/7 (`tools/autoclient/runs/20261015-133255-2f6bf7bfcb20/20261015-113348-solo.txt`) ; MP `--phases reconnect,restart --server-suite rs.identity --restart-pause 120` sans SKIP : après reconnexion 4/4, après redémarrage 4/4 (chrono arrêté pendant 150 s d'arrêt), `tools/autoclient/runs/20261015-134033-mp-c6559a321d3e` (`server/20261015-114241-server.txt`, `server/20261015-114834-server.txt`, preuve de la reconnexion dans `server/Logs-2026-10-15_13-40_DebugLog-server.txt`) ; mort réelle : rs.death 2/2 (`tools/autoclient/runs/20261015-134912-mp-6a36ce8817b0/server/20261015-115114-server.txt`)
  - Reste : —

- [ ] **E03-T05** — Mesures de charge avec une population réaliste
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : E03-T03, E02-T03
  - Fichiers : `docs/annexes/tests/validation/charge-<date>.md`
  - Faire : avec 50 à 100 bandits (dont 5 contactés), mesurer la taille des fichiers d'état, la durée de `S.save()`, le nombre de commandes réseau du mod par minute, les appels LLM par heure ; comparer au plafond de 4 Mio.
  - Accepté si : aucune sauvegarde au-delà de 20 ms ; aucun envoi sans changement ; E00-T04 passe à `testé MP`.
  - Tests : compteurs temporaires dans une suite `rs.charge`.
  - Preuve : —
  - Reste : Bandits! abandonné le 2026-10-08 (`E17-T01`) : parcours rejoué avec un PNJ Living Knox dans `E17-T03`.

- [ ] **E03-T06** — Passage avec le LLM réel
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : E03-T03
  - Fichiers : `bridge/` (si correctifs)
  - Faire : même parcours avec le pont réel : réponses dans la langue de chaque joueur, offre décrite fidèlement, aucune promesse hors catalogue, coût par heure relevé.
  - Accepté si : aucune réponse rejetée pour format ; aucune offre inventée acceptée.
  - Tests : protocole manuel + journal du pont.
  - Preuve : —
  - Reste : Bandits! abandonné le 2026-10-08 (`E17-T01`) : parcours rejoué avec un PNJ Living Knox dans `E17-T03`.

- [x] **E03-T07** — Fenêtre de livraison : position et noms d'objets coupés
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E03-T02
  - Fichiers : `RS_Notebook.lua` (`Delivery`)
  - Faire : relevé par `rs.notebook.visual` (2026-10-14) : la fenêtre de livraison s'ouvre au coin haut gauche de l'écran (`Delivery:new(0, 0, …)`), sous la barre latérale : l'ouvrir centrée ou près du carnet ; les noms d'objets de sa liste ne sont pas coupés à la largeur de la liste (coupure « … » mesurée).
  - Accepté si : fenêtre ouverte près du carnet, dans l'écran ; nom long coupé proprement ; `rs.notebook.visual` vert.
  - Tests : banc ; `rs.notebook.visual`.
  - Preuve : banc `tests/test_notebook_visual.py` du 2026-10-14 (17 tests OK, 6 en échec sur l'ancien code) : fenêtre de livraison centrée sur le carnet (`Notebook.newDelivery(mission, anchor)`, sans carnet centrée sur l'écran), ramenée dans l'écran ; noms d'objets coupés par `fit` (mesure `MeasureStringX`, « ... ») à la largeur réservant la marque et la barre de défilement ; suite `rs.notebook.visual` étendue (nom très long dans l'inventaire d'essai, position sur le carnet et hors barre latérale, carnet poussé aux quatre coins, aux deux résolutions) ; run_all 125/125 ; luacheck 15/0 ; `docs/annexes/tests/carnet-validation-04221.md` ; essai en jeu du 2026-10-14 : client automatique avec le pont et le vrai modèle (E01-T14) : rs.notebook.visual 3/3 (fenêtre de livraison sur le carnet, nom long coupé) (`tools/autoclient/runs/20261014-111501-57d2c373af5b/20261014-091544-solo.txt`)
  - Reste : essai solo : `RST.run({ suite = "rs.notebook.visual" })` (3 PASS) ; captures `rs_notebook_delivery_*` : fenêtre sur le carnet, rangée « Sterilized Bandage… » terminée par « ... » ; pansement d'essai retiré de l'inventaire ; carnet déplacé à la main non essayé

- [ ] **E03-T08** — Supprimer la clé de traduction inutilisée `IGUI_RS_None`
  - État : `abandonné`
  - Cible : `hors jeu`
  - Dépend de : E03-T02
  - Fichiers : `media/lua/shared/Translate/*/IG_UI.json` (toutes les langues du mod, EN et FR aujourd'hui)
  - Faire : décision de l'utilisateur du 2026-10-14 (E03-T02) : la clé `IGUI_RS_None` (FR « personne ») n'est lue nulle part ; la retirer de tous les fichiers de traduction. Vérifier d'abord dans `Contents` (Lua et scripts, y compris les clés composées `"IGUI_RS_" .. variable`) qu'aucune lecture ne subsiste ; aucune autre clé modifiée.
  - Accepté si : `rg IGUI_RS_None Contents` ne trouve plus rien ; fichiers JSON valides ; aucune clé brute nouvelle dans le carnet.
  - Tests : banc `lupa` (`tests/test_carnet.py`, contrôle des traductions) ; luacheck ; suite `rs.notebook.visual` dans la campagne solo (aucune clé brute affichée).
  - Preuve : —
  - Reste : abandonné le 2026-10-15 : la clé n'est pas inutilisée, contrairement à l'énoncé de la question du 2026-10-14 : `RS_Notebook.lua` la compose par `tr('None')` (lignes 776 et 983, pied « Interlocuteur → personne » quand aucun interlocuteur n'est choisi). La supprimer afficherait la clé brute. Libellés courts confirmés ; clé gardée (FR « personne », EN « no target »). À redire à l'utilisateur.
