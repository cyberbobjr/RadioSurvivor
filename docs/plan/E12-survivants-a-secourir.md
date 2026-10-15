# E12 — Survivants à secourir

**Objectif.** Une voix radio rattachée à un vrai bâtiment appelle à l'aide avec des indices ; ses réserves baissent ; l'équipe qui la secourt à temps reçoit une cache et une note, sinon elle trouve une scène et les dernières pages (note de travail §05).

**Dépend de.** E05 (voix), E07-T01 (actions), E11-T06 (`place_cache`) ; E09-T03 (identifiant d'équipe) ; E15 pour l'issue « trop tard ».

**Sources.** Note de travail §05 ; base `world-placement.md` (point lointain choisi sans le charger par la métagrille `getBuildingAt`, placement différé `LoadGridsquare`, faux cadavres en tenue, terre ferme sans charger) ; base `staging-effects.md` (zombies en tenue, reconnaissance par `getPersistentOutfitID`) ; base `quest-building-blocks.md`.

## Décisions

- Acquises : un groupe à secourir par équipe ; une équipe = une faction vanilla (propriétaire et membres), un joueur sans faction forme une équipe ; les réserves ne baissent que si au moins un joueur est connecté ; indices plutôt que coordonnées ; survivants hors carte puis décor, cadavres ou zombies (pas de survivant humain contrôlé par le jeu en B42).
- 2026-10-14 — **E12-T02** : délai = réserve (livraison repousse, serveur vide gèle) ; 3 jours par défaut, 1 à 10, plafond 10 ; issues `saved`/`missed`/`abandoned` ; faction dissoute garde son secours sous l'ancien identifiant (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : délai réglable par une option sandbox (défaut 3 jours, 1 à 10) : tâche E12-T06.
- 2026-10-14 — **E12-T03** : définition du dépôt réel ; valeurs 8/4/6 h, 40 et 8 cases, sans option ; approche une fois par venue, 12 h, fumée verte 30 min à 2 cases ; phrase fixe traduite (pas de pont) ; nouveau fichier `RS_RescueVisit.lua` (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E12-T04** : déclencheur (dépôt réel puis départ de tous) ; aidants (8 au plus) ; contenu de la cache tiré dans la liste existante ; note fixe traduite ; nouvel endroit porté par le lieu dit, moral +2 ; textes des deux souvenirs ; libellé de `RS_LifeLog.rescue` = nom du demandeur (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E12-T05** : survivants tirés au départ (2 ou 3) ; liste des 10 tenues ; dernières pages en texte fixe traduit ; `LastPages` coupée = pas de cahier ; nouveau fichier `RS_RescueLost.lua` (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : survivants « trop tard » en **zombies** dans les tenues décrites (au lieu de cadavres), cahier des dernières pages dans l'inventaire de l'un d'eux : tâche E12-T07.
- 2026-10-15 — **Scène de secours « trop tard » près d'un groupe** : les PNJ voisins peuvent tuer les zombies de la scène (comportement actuel gardé) ; confirmé par défaut (2026-10-15, l'utilisateur ne souhaite pas être interrogé sur le détail).

## Tâches

- [x] **E12-T01** — Choix du bâtiment sans charger la zone et indices
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Rescue.lua`
  - Faire : tirer un bâtiment habitable par la métagrille, loin des bases connues des joueurs, sur la terre ferme ; produire des indices descriptifs (type de bâtiment, repères voisins) sans coordonnées dans le prompt.
  - Accepté si : aucun chargement de chunk lors du choix ; indices suffisants pour un joueur de test.
  - Tests : suite en jeu `rs.rescue.pick`.
  - Preuve : `RS_Rescue.lua` : `Rescue.pick(opts)` tire au plus 300 bâtiments de `getMetaGrid():getBuildings()` (graine Park-Miller facultative), sans lecture de case ni chargement ; habitable = liste fermée par noms de pièces (église, école, police, caserne, hôpital, clinique, motel, ferme, immeuble, maison avec garage, maison), au moins 20 cases ; loin (≥ 600 cases) des refuges `SafeHouse`, des joueurs connectés et de `opts.avoid` ; zone `Water` écartée ; clé stable `getIDString` ; indices en anglais sans chiffres (type, taille, étages, jusqu'à 3 repères voisins avec direction et distance en mots, voisinage, ville vanilla) ; `tests/test_rescue.py` 21/21 (doublures qui comptent toute lecture de case : 0) ; suite en jeu `rs.rescue.pick` (6 tests : `LoadChunk` comptés, sonde des centres de chunk, `isFullyStreamedIn`) ; `tests/run_all.py` vert le 2026-10-10 hors `plan-check` (deux tâches en cours en parallèle), luacheck 17/0 et 0, `check_case.py` PASS ; `docs/rescue.md` ; base `world-placement.md` ; LK05-T12 : commit `21e99e2` ; **en jeu solo le 2026-10-10** (partie `rstest-1010`, retour de l’utilisateur) : `RST.server("rs.rescue.pick")` 6/6, aucun `LoadChunk`, fichiers `20261010-151520-server.txt` et `20261010-155522-server.txt` ; indices jugés suffisants sur les sites visités
  - Reste : —

- [x] **E12-T02** — Réserves, délai et équipe
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E12-T01, E09-T03
  - Fichiers : `RS_Rescue.lua`
  - Faire : délai en jours de jeu, réserves décomptées seulement quand au moins un joueur est connecté ; un secours actif par équipe.
  - Accepté si : serveur vide = réserves figées ; deux équipes ont deux secours distincts.
  - Tests : banc `lupa` ; suite MP.
  - Preuve : banc `tests/test_rescue.py` du 2026-10-12 (36 tests OK dont `RunTests` 14 : délai = réserves en heures de jeu, décompte seulement avec un joueur connecté sans rattrapage d'un serveur vide, un secours actif par équipe (`team_busy`), bâtiments pris exclus, issue `missed` à zéro réserve, fait du jour `rescue`, persistance dans l'état privé) ; suite `rs.rescue.run` ; run_all 82/82 ; luacheck 16/0 ; conception `docs/conception/secours.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : RST.server rs.rescue.run 5/5 (`20261013-093701-server.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.rescue.* 20/20 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.rescue.run 5/5 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : refus `team_busy` pour deux joueurs d'une même faction (banc seulement) ; serveur réellement vide abandonné (règle du 2026-10-14 : décompte figé vérifié par `rs.rescue.run`). Factions vanilla prouvées par doublures ; appels au pont et affichage du carnet hors périmètre ; `RS_LifeLog.rescue` à appeler en E12-T04/T05.

- [x] **E12-T03** — Livraison sur place et approche
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E12-T02, E11-T07
  - Fichiers : `RS_Rescue.lua`
  - Faire : dépôt de vivres ou médicaments dans un conteneur du bâtiment qui fait remonter les réserves ; à l'approche, la voix lance une fumée colorée (Signal Smoke, mod prérequis depuis le 2026-10-15) ou décrit ce qu'elle voit.
  - Accepté si : seul un dépôt réel compte ; si Signal Smoke refuse la fumée, la description la remplace (refus journalisé).
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_rescue_visit.py` du 2026-10-13 (22 tests OK, contrôlés par 5 mutations), `tests/test_rescue.py` 36 OK : livraison = dépôt réel seulement (objet vu dans l'inventaire d'un membre dehors à moins de 40 cases, retrouvé par son identifiant dans un meuble du bâtiment à 8 cases du membre, à son étage, retiré) ; vivres et médicaments utilisables (ni pourris, ni gelés, ni crus dangereux) : +8 h par aliment, +4 h par eau propre, +6 h par médicament ; butin du bâtiment, objet au sol ou hors du bâtiment, dépôt d'une autre équipe ignorés ; approche à moins de 40 cases, une fois par venue et au plus toutes les 12 h : fumée verte de 30 min à 2 cases (Signal Smoke facultatif) sinon phrase traduite de la voix (direction, nombre, véhicule) sur sa fréquence ; lecture de cases dans le nouveau `RS_RescueVisit.lua` (le choix du bâtiment ne charge rien) ; suite `rs.rescue.visit` ; luacheck 16/0 ; conception `secours-livraison.md`, `rescue.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : RST.server rs.rescue.visit 3/3 (`20261013-093633-server.txt` : réserves 24 -> 32 h, description et fumée verte) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.rescue.* 20/20 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.rescue.visit 3/3 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : Aucun secours encore branché au pont (phrase diffusée seulement si le secours a une voix) ; mémoire des objets apportés perdue au redémarrage ; objet du bâtiment sorti puis rapporté compté ; seules l'eau et les vivres comptent.

- [x] **E12-T04** — Issue « à temps »
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E12-T03
  - Fichiers : `RS_Rescue.lua` ; fiches (nouvel emplacement de la voix)
  - Faire : au chargement de la zone, cache et note posées ; les survivants partent et restent une voix du réseau depuis un nouvel endroit, en se souvenant de l'équipe.
  - Accepté si : scène posée une seule fois ; la voix mentionne l'équipe ensuite.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_rescue_scene.py` du 2026-10-13 (18 tests OK, joue aussi la suite `rs.rescue.saved` avec le vrai moteur RST ; mutations détectées), `rescue` 36, `rescue_visit` 22, `personas_server` 106 OK : issue « à temps » = dépôt réel compté (E12-T03) pendant le secours actif puis départ de tous les membres de l'équipe (plus aucun vivant connecté à 40 cases) ; aidants notés au dépôt (8 au plus), participants du fait du jour ; sac de cache existant (E11-T06) avec table tirée par l'identifiant du secours et note `Base.SheetPaper2` écrite et verrouillée (remerciements nominatifs, EN/FR), posé une seule fois quand la case est chargée, scène marquée « placed » ; nouvel endroit = vrai bâtiment tiré par la métagrille, lieu dit de la voix, moral +2 ; souvenirs de l'équipe par `memory=` ; `RS_LifeLog.rescue` pour chaque aidant lié ; règle ajoutée à `whitaker.txt` et empreinte `KNOWN_DELIVERED` ; luacheck 16/0 ; conception `secours-issue.md`, `rescue.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : RST.server rs.rescue.saved 3/3 (`20261013-093645-server.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.rescue.* 20/20 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.rescue.saved 3/3 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : Aucun secours encore lancé par le pont et voix `whitaker` silencieuse : lieu et souvenirs entendus seulement une fois la voix active ; s'éloigner de plus de 40 cases juste après le dépôt déclenche le départ ; issue « missed » : E12-T05.

- [x] **E12-T05** — Issue « trop tard »
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E12-T02, E15-T03
  - Fichiers : `RS_Rescue.lua`
  - Faire : cadavres ou zombies portant les tenues décrites, et leurs dernières pages ; posés au chargement de la zone.
  - Accepté si : tenues conformes à la description ; aucun doublon après redémarrage.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_rescue_lost.py` du 2026-10-13 (23 tests OK), `rescue` 36, `rescue_visit` 22, `rescue_scene` 18, `last_pages` 24 OK : survivants décrits au départ (2 ou 3, le premier = demandeur, tenues distinctes dans une liste fermée de 10 tenues vanilla des deux sexes, tirage par l'identifiant du secours et le site, phrases `rec.looks`) ; `RS_RescueLost.lua` (issue `missed`) : dernières pages composées des seuls faits du secours (jours attendus, survivants, approche sans dépôt, dépôt insuffisant, signature ; EN/FR ; rien si `LastPages` coupée), relevé de vie `missed` des aidants ; scène posée quand la case est chargée et les histoires vanilla passées : chaque survivant en cadavre dans sa tenue (`createRandomDeadBody`, jamais faux mort, marqué `RS_RescueBody`), `Base.Notebook` verrouillé dans le cadavre du demandeur ; état « placing » sauvegardé avant toute création (aucun doublon après un arrêt) ; suite `rs.rescue.missed` ; luacheck 16/0 ; conception `secours-trop-tard.md`, `rescue.md` ; base `world-placement.md` (tenue nommée d'un faux cadavre : sexe au hasard, tenues des deux sexes) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : RST.server rs.rescue.missed 3/3 (`20261013-093654-server.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.rescue.* 20/20 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; phases réelles du 2026-10-15 6 h 07 (reconnexion des clients puis `quit` et relance du serveur sur la même partie, `tools/autoclient/runs/20261015-060712-mp-1a0abb0c888e`) : rs.rescue.missed.after-restart « same zombies and one notebook after the restart, nothing placed again » PASS (survivants comptés par leur zombie ou leur cadavre marqué, `1bc001a`)
  - Reste : aucun secours lancé par le pont : `rec.looks` encore dit par aucune voix

- [x] **E12-T06** — Délai du secours réglable par une option sandbox
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E12-T02
  - Fichiers : `RS_Rescue.lua` ; `media/sandbox-options.txt` ; `Translate/*/Sandbox.json`
  - Faire : décision de l'utilisateur du 2026-10-14 (E12-T02) : le délai du secours (réserve en jours) devient une option sandbox `RadioSurvivor.RescueDays` (entier, défaut 3, de 1 à 10) au lieu d'une constante. Lue au lancement d'un nouveau secours ; un secours en cours garde son délai. Règles d'E12-T02 inchangées (livraison repousse, serveur vide gèle, plafond 10).
  - Accepté si : au banc : option à 5 = nouveau secours de 5 jours ; option absente ou hors bornes = 3 ; secours en cours inchangé quand l'option change ; en jeu, option traduite visible dans les options sandbox.
  - Tests : banc `lupa` ; suite `rs.rescue.run` dans la campagne solo.
  - Preuve : option sandbox `RadioSurvivor.RescueDays` (1-10, défaut 3) lue au lancement d'un secours (`Const.rescueDays`, repli `SandboxVars` puis 3) ; banc `tests/test_rescue.py` 44 OK (option 5 → 5 jours, absente ou hors bornes → 3, secours en cours inchangé ; suite `rs.rescue.run` 6/6 sur doublures, échoue sans l'option) ; luacheck 15/0 ; commit `de1bf89` ; campagne solo automatique du 2026-10-15 (`tools/autoclient/runs/20261015-034525-e24ab0eb77eb/20261015-014609-solo.txt`, 195 tests : 167 PASS, 11 FAIL dont 8 dus à la panne du fournisseur LLM) : rs.rescue.run 6/6 dont « a new rescue takes its delay from the RescueDays option »
  - Reste : aucun appelant de production ne lance encore `Rescue.start` sans `days`

- [x] **E12-T07** — Issue « trop tard » : survivants transformés en zombies
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E12-T05
  - Fichiers : `RS_RescueLost.lua` ; `RS_Rescue.lua` ; suite `rs.rescue.missed`
  - Faire : décision de l'utilisateur du 2026-10-14 (E12-T05) : à l'issue « missed », les survivants tirés (2 ou 3) deviennent des **zombies** habillés dans les tenues décrites (liste des 10 tenues) au lieu de cadavres. Le cahier des dernières pages est placé dans l'**inventaire** de l'un d'eux (le demandeur) pour se retrouver dans son cadavre quand il est tué sur un serveur (un objet seulement accroché est perdu). Pose une seule fois, même après un arrêt brutal ; `LastPages` coupée = zombies sans cahier.
  - Accepté si : au banc : issue « missed » = 2 ou 3 zombies dans les tenues tirées, aucun cadavre posé, cahier dans l'inventaire d'un seul ; ce zombie tué : cahier dans son cadavre ; pas de doublon après un redémarrage simulé ; `LastPages` coupée : pas de cahier.
  - Tests : banc `lupa` ; suite `rs.rescue.missed` dans la campagne MP automatique (zombie porteur tué, cahier vu dans le cadavre côté client).
  - Preuve : survivants « trop tard » = 2 ou 3 joueurs réanimés dans les tenues tirées (`addZombiesInOutfit` → `createCorpse` → `reanimate`, jamais virtualisés), aucun cadavre ; cahier verrouillé dans l'inventaire du seul demandeur, retrouvé dans son cadavre à sa mort ; reprise après arrêt sans doublon (zombies ou cadavre marqués adoptés) ; banc `test_rescue_lost.py` 27 OK ; suite `rs.rescue.missed` adaptée ; luacheck 15/0 ; commit `83aefe5` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.rescue.missed 3/3, étapes lk.present et world.keys du client 2 (copie du zombie, cadavre et cahier) vertes (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/client2/20261015-090729-steps.txt`) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : rs.rescue.missed 3/3 (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : rs.rescue.missed.before et .after-restart PASS (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093457-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`)
  - Reste : Limite : zombies laissés dans le monde jusqu'à leur mort
