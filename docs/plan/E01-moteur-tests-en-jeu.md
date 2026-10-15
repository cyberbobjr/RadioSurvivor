# E01 — Moteur de tests Lua lancé depuis la console du jeu

**Objectif.** Exécuter des suites de tests **dans le jeu réel** (API Java, Bandits!, réseau) depuis la console Lua du mode debug, côté client comme côté serveur, avec un rapport écrit dans un fichier qui sert de preuve. Les mêmes suites, quand elles ne dépendent que de la logique, tournent aussi dans le banc `lupa` hors jeu.

**Dépend de.** Rien. Toutes les étapes suivantes s'en servent pour leurs cibles `solo` et `MP`.

**Sources vérifiées (42.21).**
- Console Lua : fenêtre `UIDebugConsole`, basculée par la touche `ToggleLuaConsole` (défaut `KEY_GRAVE`, `²` sur clavier AZERTY) seulement si `Core.debug` (`zombie/GameWindow.java:756`, `768-769` ; `media/lua/shared/keyBinding.lua:360-361`). La ligne saisie est compilée par `LuaCompiler.loadstring(…, "console", LuaManager.env)` et exécutée dans l'environnement Lua global du client (`zombie/ui/UIDebugConsole.java:281-303`) : `RST.run()` y est appelable directement.
- Droits : capacité `Capability.DebugConsole` (`zombie/characters/Capability.java:91`), utilisée par les commandes serveur de debug (`zombie/commands/serverCommands/LogCommand.java:27`). Côté Lua : `player:getRole():hasCapability(Capability.X)` (`media/lua/client/Chat/ISChat.lua:469`). ⚠ À vérifier côté serveur pour un joueur distant.
- Base de connaissances : `logs-and-tools.md` (fichiers `getFileWriter` dans `Zomboid\Lua`, extensions admises, banc `lupa`), `kahlua-lua.md` (`pcall` et « Break On Error », `next` absent), `multiplayer.md` (`sendClientCommand` / `sendServerCommand`, tables imbriquées admises).

## Conception proposée

```text
console (client)                   serveur dédié ou solo
RST.run('carnet')  ──────────────  suites client, OnTick
RST.server('carnet') ─ sendClientCommand('RST','run') ─▶ contrôle des droits ─▶ suites serveur (OnTickEvenPaused)
                    ◀─ sendServerCommand('RST','report') ─ rapport résumé + fichier serveur
rapport : Zomboid\Lua\batman_RadioSurvivor\tests\<horodatage>-<côté>.txt
```

- **API d'écriture** : `RST.suite(nom, {tags = {'client'|'server'|'shared', 'world'}}, function(s) s.test('…', function(t) … end) end)`, assertions `t:eq`, `t:ok`, `t:fails`, `t:near`, crochets `s.before` / `s.after`, attente `t:waitUntil(condition, délaiMs)` et `t:sleep(ms)` pour les tests asynchrones (le moteur avance au rythme des ticks).
- **Isolation** : chaque test sous `pcall` ; une erreur ne bloque pas la suite. Les suites marquées `world` (spawn, inventaire, téléportation) refusent de tourner si le nom de partie ne commence pas par `rstest` (`getWorld():getWorld()`).
- **Rapport** : une ligne par test (`PASS`, `FAIL`, `SKIP`, durée, message), un résumé, la version du jeu (`getCore():getVersion()`), les mods actifs (`getActivatedMods()`), le côté et le nom de partie.

## Décisions

- 2026-10-08 — **E01-T01** : mod de développement séparé `batman_RadioSurvivorTests`, rangé dans le dépôt sous `dev/batman_RadioSurvivorTests/` (structure B42 : `common/`, `42.21/mod.info`, `42.21/media/`), copié vers `%USERPROFILE%\Zomboid\mods` par `tools/install_tests.py`, jamais publié. Le mod publié ne contient aucun code de test. Les suites couvrent aussi Living Knox (étapes `LK`).
- 2026-10-08 — **E01-T06** : la fixture « bandit amical via l'API Bandits! » est retirée (Bandits! abandonné, `E17-T01`). T06 garde la garde `rstest*` et les fixtures objets, déplacement et case chargée ; la fixture PNJ devient `E01-T10`, branchée sur le fournisseur de PNJ (`RS_NPCProvider`, Living Knox).
- 2026-10-08 — **E01-T08** : la suite `env` ne vérifie plus `Bandits2` (conséquence directe de `E17-T01`).
- 2026-10-08 — **Attente sans coroutine** (`E01-T11`) : en Kahlua, une erreur levée par `error()`/`assert`/Java dans une coroutine n'est pas rendue par `resume` (« coroutine changed in pcall », base `kahlua-lua.md`) ; un échec d'assertion figeait donc tout passage asynchrone en jeu. Choix de l'utilisateur : plus aucune coroutine ; tests synchrones sous `pcall`, attente écrite en étapes `t:waitUntil(cond, ms, function(t) ... end)` (et `t:sleep(ms, suite)`), chaque étape sous `pcall` à un tick.

- 2026-10-14 — **Les tests font foi** (utilisateur) : plus de séance MP manuelle ; `testé MP` = suite verte dans la campagne MP automatique, `testé solo` = suite verte dans la campagne solo automatique (voir `README.md`). Le client 2 devient actif (`E01-T16`) ; reconnexion et redémarrage seulement pour les tâches dont « Accepté si » l'exige (`E01-T17`).
- 2026-10-14 — **E01-T15** (confirmé) : banc MP par défaut sans zombie ambiant, mode dieu, point d'apparition fixe 10656,10137,0, 4 Go par client et 3 Go pour le serveur ; petite campagne `mp-ambient` (zombies vanilla, sans mode dieu) pour la robustesse (`E01-T19`).
- 2026-10-14 — **E01-T10** : l'API de test exige aussi le mode debug, en plus de l'autorité et du nom de partie `rstest*` (`E01-T18`) ; les deux autres choix confirmés (fichier séparé dans le mod publié, seuls les PNJ de `testSpawnNpc` retirables).
- 2026-10-14 — **E01-T14** : liste de mods minimale et client sans Steam (objets des autres mods absents de la copie) (confirmé par défaut, valeurs techniques).

## Hors périmètre

Interface graphique du moteur (la console suffit), intégration continue distante.

## Tâches

- [x] **E01-T01** — Choisir l'emplacement du code de test
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier
  - Faire : poser la question, consigner la décision.
  - Questions : Où vivent le moteur et les suites ? Options : mod de développement séparé `batman_RadioSurvivorTests` dans le dépôt (`RadioSurvivor/dev/`), copié vers `Zomboid\mods` par un script, jamais publié [recommandé] / dans le mod principal, chargé seulement en mode debug / projet Workshop local séparé `Zomboid\Workshop\RadioSurvivorTests`, chargé directement par le jeu.
  - Accepté si : décision consignée ; chemins des tâches suivantes ajustés.
  - Tests : —
  - Preuve : décision du 2026-10-08 (section Décisions) ; chemins des tâches E01 ajustés
  - Reste : —

- [x] **E01-T02** — Noyau RST : registre, suites, assertions, filtres, rapport texte
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E01-T01
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/mod.info` ; `dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/RST.lua` ; `tools/install_tests.py` (copie vers `Zomboid\mods`) ; `tests/test_rst.py`
  - Faire : `RST.suite`, `s.test`, `s.before/after`, assertions avec message clair (attendu / obtenu), filtres par nom de suite, motif de test et tags, `RST.list()`, rapport en lignes, aucune dépendance à l'interface. Compatible Kahlua (pas de `next`, pas de `goto`, pas d'opérateurs binaires).
  - Accepté si : une suite qui échoue n'arrête pas les autres ; un test sans assertion est signalé ; le rapport compte réussites, échecs, ignorés.
  - Tests : `tests/test_rst.py` charge `RST.lua` dans `lupa` (avec `next = nil`) et vérifie le moteur sur des suites factices.
  - Preuve : `tests/test_rst.py` 33/33, `test_protocol.py` 3/3, `test_carnet.py` 17/17, luacheck 23 (Contents) et 0 (dev), `plan.py check` du 2026-10-08
  - Reste : statut `EMPTY` compté comme échec ; filtres chaîne = nom exact ou préfixe `nom.` ; objet levé par `error(table)` rendu intact par `pcall` (confirmé en jeu, E01-T11) ; ⚠ `getTimestampMs` depuis la console client

- [ ] **E01-T03** — Tests asynchrones pilotés par les ticks
  - État : `abandonné`
  - Cible : `solo`
  - Dépend de : E01-T02
  - Fichiers : `RST.lua` (ordonnanceur)
  - Faire : un test peut rendre la main (`t:waitUntil(fn, ms)`, `t:sleep(ms)`) ; l'ordonnanceur reprend sur `OnTick` côté client et `OnTickEvenPaused` côté serveur, avec délai maximal par test et par suite ; un seul passage à la fois.
  - Accepté si : un test qui attend une réponse du pont se termine ou échoue au délai, sans bloquer le jeu ; deux `RST.run` simultanés sont refusés.
  - Tests : `test_rst.py` avec une horloge simulée ; suite en jeu `rst.selftest` (attente de 2 s mesurée).
  - Preuve : `tests/test_rst.py` 54/54 (horloge simulée), `test_protocol.py` 3/3, `test_carnet.py` 17/17, luacheck 23/0, `plan.py check` du 2026-10-08 ; E01-T02 : commit `5f969b9`
  - Reste : conception par coroutines invalide en Kahlua (une erreur `error()` dans une coroutine n'est pas rendue par `resume`) ; remplacée par `E01-T11` (attente par étapes, décision de l'utilisateur du 2026-10-08), validée en jeu solo

- [x] **E01-T04** — Lanceur console client et fichier de résultats
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E01-T03
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/media/lua/client/RST/RST_Client.lua`
  - Faire : `RST.run(filtre)`, `RST.list()`, `RST.last()` (dernier rapport) ; sortie dans la console (`print`), résumé en texte au-dessus du joueur, fichier `batman_RadioSurvivor/tests/<horodatage>-client.txt` ; refus hors mode debug (`isDebugEnabled()`), message explicite.
  - Accepté si : depuis la console (`²`), `RST.run('rst')` exécute l'auto-test et écrit le fichier ; le rapport contient version, mods actifs, nom de partie.
  - Tests : suite `rst.selftest` en solo.
  - Preuve : `tests/test_rst.py` 75/75 (classe `ClientTests`, suite `rst.selftest` sous horloge simulée), `test_protocol.py` 3/3, `test_carnet.py` 17/17, luacheck 23/0, `plan.py check` du 2026-10-08 ; E01-T03 : commit `ece3972` ; **en jeu solo le 2026-10-08** (partie `rstest-solo`, 42.21.0 4a0e9546ec, console `²`) : `RST.run('rst')` → 6/6 PASS (dont `sleep 2 s` mesuré 2005 ms sous `OnTick`), « Break On Error » coupé puis rétabli, en-tête complet (version, côté `solo`, partie, 28 mods actifs), fichier `Zomboid/Lua/batman_RadioSurvivor/tests/20261008-213444-solo.txt`
  - Reste : retour au menu pendant un passage non traité (« Break On Error » resterait coupé) ; horodatage en UTC

- [x] **E01-T05** — Lancement des suites serveur depuis un client
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E01-T04
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/media/lua/server/RST/RST_Server.lua`, `RST_Client.lua`
  - Faire : `RST.server(filtre)` envoie `sendClientCommand('RST', 'run', {filter})` ; le serveur vérifie `Capability.DebugConsole` (ou administrateur), exécute les suites `server` et `shared`, écrit son propre fichier, renvoie le résumé et les échecs par `sendServerCommand` ; en solo, appel direct sans réseau.
  - Accepté si : un joueur sans droit est refusé et journalisé ; un admin reçoit le résumé dans sa console ; le fichier serveur existe dans le cache du serveur.
  - Tests : banc `lupa` serveur + deux clients (réutiliser `Simulation`) ; en jeu : serveur dédié de test.
  - Preuve : `tests/test_rst.py` 92/92 (`ServerTests` : serveur + deux clients lupa ; `SoloServerTests`), `test_protocol.py` 3/3, `test_carnet.py` 17/17, luacheck 23/0, `plan.py check` du 2026-10-08 ; E01-T04 : commit `a63db26` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : RST.server lancé depuis un client admin (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rst.rights 2/2 (compte `user` refusé sur `RST.server`, client admin informé `busy` pendant une exécution) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`), rs.freqdebug, lk.admin, lk.npcsheet, lk.debugview : client `user` refusé sans donnée (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : rst.disconnect.before, rst.disconnect.slow, rst.disconnect.after-reconnect2 PASS (exécution coupée par la déconnexion finie, rapport gardé, serveur non laissé `busy`) (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093501-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093504-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093552-server.txt`) ; date `os.date` écrite par le serveur dans l'en-tête de chaque rapport
  - Reste : —

- [x] **E01-T06** — Garde « partie de test » et fixtures du monde
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E01-T04
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/RST_Fixtures.lua`
  - Faire : refus des suites `world` hors partie `rstest*` ; fixtures : donner et retirer des objets, déplacer le joueur, attendre le chargement d'une case ; nettoyage en `after`.
  - Accepté si : sur une partie normale, la suite `world` est ignorée avec la raison ; sur `rstest-solo`, un objet donné puis le déplacement du joueur sont annulés après la suite (inventaire et position d'origine).
  - Tests : suite `rst.fixtures` en solo.
  - Preuve : `tests/test_rst.py` 131/131 (`GuardTests`, `DeferTests`, `FixtureTests`, `LauncherContextTests`), `test_protocol.py` 3/3, `test_carnet.py` 17/17, luacheck 23/0, `plan.py check` du 2026-10-08 ; E01-T05 : commit `1c4b39a` ; **en jeu solo le 2026-10-08** sur `rstest-solo` : `RST.run({suite='rst', tags='world'})` → `rst.fixtures` 6/6 PASS (objets donnés puis retirés, déplacement puis retour vérifiés par les tests suivants), fichiers `20261008-213631-solo.txt` et `20261008-213639-solo.txt` ; le passage tient en un tick (15 ms) : ni le crayon ni le déplacement ne sont visibles à l'écran ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rst.guard 2/2 (partie normale simulée : tests world refusés avec la raison) (`20261013-202155-solo.txt`)
  - Reste : refus de la suite `world` sur une partie normale à vérifier en jeu ; chemin serveur (`/teleportto` exige `TeleportToCoordinates`) ; ⚠ `removeItem` ne rééquipe pas, `movePlayer` ne remet pas en véhicule

- [x] **E01-T07** — Exécution automatique sur le serveur dédié de test
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E01-T05
  - Fichiers : `RST_Server.lua` ; `tests/run_dedicated_smoke.ps1`
  - Faire : si le fichier `batman_RadioSurvivor/tests/autorun.txt` existe dans le cache du serveur (liste de filtres), lancer les suites serveur à `OnServerStarted` puis écrire `autorun-result.txt` ; le script PowerShell crée ce fichier dans son cache temporaire, attend le résultat, affiche le résumé et renvoie un code d'erreur en cas d'échec.
  - Accepté si : `run_dedicated_smoke.ps1` termine seul avec le résumé des suites serveur, sans client connecté.
  - Tests : exécution du script.
  - Preuve : `tests/test_rst.py` 142/142 (`AutorunTests`), `test_protocol.py` 3/3, `test_carnet.py` 17/17, luacheck 23/0, `plan.py check` ; exécution réelle de `tests/run_dedicated_smoke.ps1` le 2026-10-08 (serveur dédié 42.21.0 local, sans client, sans Bandits2) : `RST-RESULT ok=true total=3 pass=3`, code 0 en 34 s, aucune erreur Lua de nos mods ; E01-T06 : commit `b60c2ab`
  - Reste : —

- [x] **E01-T08** — Suites de base : environnement, codec, état, missions
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E01-T04, E01-T11
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RS_Env.lua`, `RS_Codec.lua`, `RS_Missions.lua`
  - Faire : `env` vérifie la version 42.21, les fonctions Java utilisées par le mod (`sendRemoveItemFromContainer`, `sendAddItemToContainer`, `detectBadWords`, `getItemWithIDRecursiv`, `getEffectiveCapacity`, `CharacterTrait.DEAF`…) ; `codec` et `missions` reprennent la logique pure et tournent aussi dans `lupa`.
  - Accepté si : les suites passent en solo et dans `lupa` ; une fonction Java absente donne un échec explicite.
  - Tests : `test_rst.py` exécute `codec` et `missions` ; console en solo.
  - Preuve : `tests/test_rs_suites.py` 20/20, `test_rst.py` 142/142, `test_protocol.py` 3/3, `test_carnet.py` 17/17, luacheck 23/0, `plan.py check` ; VM Kahlua du jeu hors jeu : `rs.missions` 14/14, `rs.codec` 13/14 (échec attendu `E00-T08`), `rs.env` 6 + 1 SKIP ; serveur dédié de test le 2026-10-08 : `RST-RESULT ok=true total=17 pass=17` (`rst` + `rs.missions`) ; E01-T07 : commit `c4760ca` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.env 7/7, rs.codec 15/15, rs.missions 14/14 (`20261013-202155-solo.txt`)
  - Reste : passage complet en jeu après `E01-T11` (un échec figeait le moteur à coroutines) ; échecs attendus en jeu : `rs.codec` au-delà de U+00FF (`E00-T08`), `rs.env` sur `InventoryItemFactory` (`E00-T10`) ; groupe client de `rs.env` à voir en solo ; littéraux non ASCII écrits en échappements d'octets (lexeur Kahlua)

- [x] **E01-T09** — Mode d'emploi et entrée de la base de connaissances
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E01-T08
  - Fichiers : `docs/tests-en-jeu.md` ; `.claude/pz-knowledge/logs-and-tools.md` (console Lua, générique)
  - Faire : lancer le jeu en debug, ouvrir la console, commandes `RST.*`, où lire les rapports, partie `rstest`, serveur dédié de test ; entrée générique sur la console Lua et l'exécution de code depuis celle-ci.
  - Accepté si : un nouvel utilisateur lance une suite en suivant le document.
  - Tests : —
  - Preuve : `docs/tests-en-jeu.md` vérifié contre le code (lanceurs, fixtures, suites, `install_tests.py`, `run_dedicated_smoke.ps1`, `test_kahlua.py`) ; base `logs-and-tools.md` complétée (BOM devant `quit`) ; E01-T12 : commit `2128012` ; validé par l'utilisateur le 2026-10-09 (il lance les suites en suivant ce mode d'emploi depuis le 2026-10-08)
  - Reste : —

- [x] **E01-T10** — Fixture PNJ par le fournisseur de PNJ
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E01-T06, E17-T02, LK12-T03
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/RST_Fixtures.lua`
  - Faire : faire apparaître un PNJ de test près du joueur par l'API publique de Living Knox (côté serveur), le retrouver par l'interface `RS_NPCProvider`, le retirer en `after` ; suites `world` seulement.
  - Accepté si : sur `rstest-solo`, un PNJ apparaît, est vu par le fournisseur et disparaît après la suite ; refus clair si aucun fournisseur actif.
  - Tests : suite `rst.fixtures.npc` en solo.
  - Preuve : bancs du 2026-10-12 : `tests/test_lk_apitest.py` 8 OK (moteur réel avec doublures, fournisseur `RS_LivingKnox` réel : la suite `rst.fixtures.npc` passe de bout en bout) et `tests/test_rst.py` 163 OK (`NpcFixtureTests` : attente du corps vu par `RS_NPCProvider`, retrait en `after`, tous les refus, suite PASS et SKIP) ; API de test `LK_APITest.lua` réservée à l'autorité et aux parties `rstest*` ; run_all 85/85 ; luacheck 16/0 ; conception `docs/conception/pnj-de-test.md`, `docs/api.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "rst.fixtures.npc", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-180255-solo.txt`)
  - Reste : Solo validé le 2026-10-12. essai solo après réinstallation du mod de test et redémarrage complet, partie `rstest-solo` Living Knox activé : `RST.run({ suite = "rst.fixtures.npc", tags = "world" })` (PNJ à 2 cases à l'est, 2 PASS, corps retiré) ; Living Knox coupé : 2 SKIP « no NPC provider active ». Liste des PNJ de test en mémoire seulement ; PNJ sans groupe ; chemin `RST.server` non testé. Décisions du 2026-10-14 : mode debug exigé en plus (`E01-T18`), le reste confirmé

- [x] **E01-T11** — Attente par étapes, sans coroutine
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E01-T03
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/RST.lua` ; lanceurs, fixtures et suites du mod de dev qui attendent ; `tests/test_rst.py`, `tests/test_rs_suites.py`
  - Faire : retirer les coroutines ; chaque test, crochet, nettoyage et étape tourne sous `pcall` ; `t:waitUntil(cond, ms, suite)` et `t:sleep(ms, suite)` enregistrent l'étape suivante, exécutée à un tick ; délais, annulation, `t:defer`, garde `world` et rapports inchangés ; réécrire `rst.selftest`, `rst.fixtures` et l'attente de déplacement du serveur dans ce style.
  - Accepté si : dans la VM Kahlua du jeu (exécutée hors jeu) et sur le serveur dédié de test, un test en échec, une erreur `error()` et une exception Java dans une étape donnent `FAIL`/`ERROR` sans figer le passage ; `run_dedicated_smoke.ps1 -Filters "rst,rs"` se termine.
  - Tests : `test_rst.py` ; VM Kahlua ; serveur dédié de test.
  - Preuve : `tests/test_rst.py` 151/151, `test_rs_suites.py` 20/20, `tests/test_kahlua.py` 6/6 (VM Kahlua de `projectzomboid.jar` : `rst` 6/6, `rst.failures` terminé avec 4 FAIL + 8 ERROR attendus, `rs.codec` 13/14 attendu, `rs.missions` 14/14), `test_protocol.py` 3/3, `test_carnet.py` 17/17, luacheck 23/0 ; serveur dédié de test le 2026-10-08 : `-Filters "rst,rs"` → `RST-RESULT ok=false total=41 pass=38 fail=2 skip=1` (échecs attendus `E00-T08`, `E00-T10`), `-Filters "rst.failures"` → passage terminé, 13 tests ; E01-T08 : commit `ba039de` ; **en jeu solo le 2026-10-08** (`rstest-solo`) : attentes par étapes sous `OnTick` client (`rst.selftest` 6/6, `sleep 2 s` mesuré 2005 ms ; `rst.fixtures` 6/6 avec `waitSquare` puis `movePlayer`)
  - Reste : ECJ non versionné (`tests/kahlua/ecj.jar` ou `RS_ECJ_JAR`, Maven Central `org/eclipse/jdt/ecj/3.40.0`) ; une attente par étape, le code après l'appel d'attente s'exécute avant l'attente

- [x] **E01-T12** — `quit` envoyé sans BOM au serveur dédié de test
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E01-T07
  - Fichiers : `tests/run_dedicated_smoke.ps1`
  - Faire : lancé depuis PowerShell, le script écrit `quit` précédé d'un BOM sur l'entrée du serveur (« Unknown command »), le serveur est tué au délai et le code de sortie vaut 2 malgré `ok=true` ; écrire l'entrée en UTF-8 sans BOM (encodage d'entrée de la console ou flux explicite).
  - Accepté si : depuis PowerShell et depuis Git Bash, le serveur s'arrête sur `quit` et le script renvoie 0 quand `ok=true`.
  - Tests : exécution réelle du script.
  - Preuve : exécutions réelles du 2026-10-08, `-Filters "rst"` : depuis PowerShell `RST-RESULT ok=true total=6 pass=6`, `server stopped` sans kill, code 0 (33 s) ; depuis Git Bash idem, code 0 (31 s) ; E01-T11 : commit `c5161dc`
  - Reste : le filtre d'erreurs du script remonte encore la ligne attendue `.fail> Exception thrown` (signal d'assertion rattrapé)

- [x] **E01-T13** — Filtre d'erreurs du script de fumée : ignorer les signaux d'assertion volontaires
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E01-T12
  - Fichiers : `tests/run_dedicated_smoke.ps1` (`Show-ModErrors`)
  - Faire : le journal 42.21 écrit `).fail> Exception thrown` pour un signal d'assertion rattrapé par `pcall` (auto-test RST), alors que le filtre attend `).fails>` ; ignorer les lignes produites par les signaux du moteur RST (ou les suites `rst.*` volontairement en échec) sans masquer une vraie erreur du mod.
  - Accepté si : `run_dedicated_smoke.ps1 -Filters "rst"` n'affiche aucune erreur de nos mods quand l'auto-test passe ; une vraie erreur Lua du mod reste affichée (vérifié sur un journal de test).
  - Tests : exécution réelle ; journal conservé d'une exécution précédente ou extrait synthétique.
  - Preuve : filtre vérifié hors ligne (extrait synthétique : 3 lignes volontaires masquées, 4 vraies erreurs affichées ; journal conservé d'une exécution précédente : « none found ») ; exécution réelle du 2026-10-08 depuis Git Bash `-Filters "rst"` : 6/6, « Lua errors mentioning our mods: none », code 0 ; LK01-T02 : commit `6cd29f6`
  - Reste : —


- [x] **E01-T14** — Lanceur client automatique : campagne en jeu sans geste
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E01-T11, E01-T12
  - Fichiers : nouveau dossier `tools/autoclient/` (agent Java, lanceur), `dev/batman_RadioSurvivorTests` (pilote Lua), `docs/tests-en-jeu.md`
  - Faire : demande de l'utilisateur (2026-10-14) : pouvoir manipuler le jeu par code pour valider sans lui. Une commande lance le vrai client 42.21 (sans modifier aucun fichier du jeu : lanceur personnel sur `jre64\bin\java.exe` avec les options de `ProjectZomboid64.json` et `-javaagent`, base `logs-and-tools.md`), charge une partie de test `rstest*` (aucun argument de lancement ne charge une sauvegarde : passer par le menu en Lua ou en Java depuis l'agent), lance une campagne RST nommée, attend le rapport, copie captures et rapport, quitte proprement (sauvegarde puis sortie), avec délai maximal et arrêt forcé ; aucun clavier ni souris. Étape 1 : étude de faisabilité (mécanisme de chargement d'une partie, fil Lua, arrêt) et preuve minimale ; étape 2 : outil complet.
  - Décisions (2026-10-14, utilisateur) : piloter le vrai jeu par code plutôt que le cloner ; tâche ouverte et étude commencée le jour même.
  - Accepté si : une commande unique, PC sans personne devant, exécute `RST.campaign("solo-rs")` dans le vrai client et rend le rapport et les captures ; échec propre (code de sortie, journal) si le jeu ne démarre pas ou bloque.
  - Tests : exécution réelle sur ce PC ; banc du lanceur hors jeu.
  - Preuve : exécution réelle du 2026-10-14 sur ce PC, personne devant : `tools/autoclient/autoclient.py` (cache temporaire `-cachedir=` avec copie de la partie `rstest*` et des mods, TooltipLib lu en lecture seule dans le Workshop, `-debug -nosound -nosteam`, `vmArgs` de `ProjectZomboid64.json`) ; pilote `RST_AutoClient.lua` : menu principal (`OnMainMenuEnter`/`OnFETick`) → `MainScreen.continueLatestSave(mode, partie)` (MainScreen.lua:1194, 1283), état gardé dans un fichier (rechargement Lua si la liste de mods diffère, Core.java:4176-4179), clic de l'écran de chargement envoyé par `PostMessage` `WM_LBUTTONDOWN/UP` (GameLoadingState.java:803-826 n'avance qu'au clic), sortie `getCore():quitToDesktop()` après sauvegarde (code 0 en 2 s) ; piège : cache neuf qui vide `mods/default.txt` sans `mods/reset-mods-42_00.txt` (GameWindow.java:986) ; preuve courte `rs.env` 7/7 en 47 s ; campagne `solo-rs` 75/81 en 14 min (5 échecs = pont non lancé, 1 vrai défaut de mise en page) dans `tools/autoclient/runs/20261014-103818-03b2c452d0bf/` avec 27 captures ; banc `tests/test_autoclient.py` 14 OK ; run_all 126/126 ; luacheck 15/0 ; `docs/tests-en-jeu.md` § 6 bis ; base `logs-and-tools.md` (client solo piloté sans personne)
  - Reste : étape 2 : lancer et arrêter le pont Python avec le client (suites `rs.npctalk`, `rs.radiomodule.world`, `rs.relation` avec le vrai modèle) ; clic tardif possible pendant l'entrée en jeu (fenêtre Infos du personnage vue sur une capture) ; Windows seulement.

- [x] **E01-T15** — Multijoueur automatique : serveur dédié de test et clients pilotés
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E01-T14, E01-T12
  - Fichiers : `tools/autoclient/` (mode MP), `tests/run_dedicated_smoke.ps1` ou équivalent, `RST_AutoClient.lua`, `docs/tests-en-jeu.md`
  - Faire : demande de l'utilisateur (2026-10-14, « carte blanche » pour l'après-midi) : étendre le client automatique au multijoueur pour vérifier sans lui les tâches qui attendent la séance MP finale. Une commande démarre le serveur dédié de test (cache temporaire, mods copiés, sans Steam), y connecte un puis deux clients automatiques (comptes distincts, caches distincts, mémoire bornée), lance les suites MP (côté client, `RST.server` côté serveur, suites à deux joueurs), récupère rapports et journaux des trois processus, arrête tout proprement ; délais et arrêts forcés de ses seuls processus.
  - Décisions (2026-10-14, utilisateur) : étendre le client automatique au multijoueur.
  - Accepté si : une commande unique exécute des suites MP réelles avec un et deux clients et rend les rapports ; échec propre sinon.
  - Tests : exécutions réelles sur ce PC ; banc de l'outil.
  - Preuve : exécutions réelles du 2026-10-14 sur ce PC, personne devant : `tools/autoclient/autoclient.py --mp` (serveur `rstest_mp` en cache temporaire sans Steam, comptes admin créés par la console pour les clients `-debug`, connexion par `ConnectToServer.instance:connect`, personnage créé par les deux « Suivant », mode dieu par défaut, pont sur le dossier d'échange du serveur) ; 1 client : 25 PASS + 3 SKIP (`runs/20261014-140206-mp-4aee3b4df357`) ; 2 clients, campagne `mp` (53 suites) avec le vrai modèle : 182/215 PASS, 16 FAIL (suites `lk.*`), 17 SKIP en 41 min (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; défauts trouvés et corrigés : noms d'appelants de `RS_Voices`, rayon de bruit borné dans `LK_Senses` ; bancs test_autoclient 34, test_rs_suites 36, test_lk_senses 27, run_all 126/126 ; commit `90e7b9b`
  - Reste : seconde campagne après les correctifs MP (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1`, serveur sans zombie ambiant par défaut, `--ambient-zombies`) : 197/215 PASS, 1 FAIL (`lk.windowkill`, LK06-T11), 17 SKIP ; client 2 passif ; clients sur la même machine ; ni reconnexion ni redémarrage du serveur ; `LK_Senses` revu en jeu (aucun « bad report »). Réglages du banc confirmés le 2026-10-14 ; client 2 actif : `E01-T16` ; reconnexion et redémarrage : `E01-T17` ; campagne `mp-ambient` : `E01-T19`

- [ ] **E01-T16** — Client 2 actif dans la campagne MP
  - État : `codé`
  - Cible : `MP`
  - Dépend de : E01-T15
  - Fichiers : `tools/autoclient/`, `RST_AutoClient.lua`, suites client du mod de test, `docs/tests-en-jeu.md`
  - Faire : décision de l'utilisateur du 2026-10-14 : le client 2 exécute des suites qui vérifient ce qu'il voit et entend (même cadavre et même contenu, même apparence, bulles, sons, carnet, caisses et constructions, refus d'un compte `user`). Coordination client 1 / serveur / client 2 par étapes nommées (le serveur annonce l'étape, chaque client rapporte), rapports des deux clients rangés avec celui du serveur, échec si un client manque une étape. Chaque contrôle « à automatiser par le client 2 (E01-T16) » d'un champ « Reste » devient une suite ou un test de la campagne `mp`.
  - Accepté si : la campagne `mp` fait tourner des suites sur le client 2 et rend son rapport ; les contrôles « client 2 » listés dans le plan ont chacun un test vert, ou sont abandonnés avec leur raison.
  - Tests : banc de l'outil ; campagne MP réelle.
  - Preuve : étapes nommées `RST.Steps` + `RST_PeerChecks` (commits `7443d01`, `db6f787`) : client 2 en rôle « peer » avec son rapport d'étapes ; banc `test_rst_steps.py` 12 OK, `test_autoclient.py` 36 OK ; MP réel : refus d'un compte `user` 12/12 sans donnée (lk.admin, lk.npcsheet, lk.debugview, rs.freqdebug), caisses vues (`tools/autoclient/runs/20261015-010646-mp-e8fba085accd`) ; cri, reddition, barricade et mur vus par le client 2, 5/5 PASS (`tools/autoclient/runs/20261015-013413-mp-dd1e5224efda`) ; suites du carnet par le chemin réseau 7/14 (`tools/autoclient/runs/20261015-012607-mp-c75ba6661b1c`) ; solo 14/14 (`tools/autoclient/runs/20261015-013843-c83b1a2b660c`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : étapes du client 2 : tranche 1 82/83 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`), tranche 2 61/61 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/client2/20261015-090729-steps.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : étapes du client 2 vertes ; campagne avec un mod en plus (LK02-T03) : lk.look du client 2 vert (`tools/autoclient/runs/20261015-121241-run-54087fb0f84f/run/server/20261015-101651-server.txt`)
  - Reste : étape lk.track #51 FAIL (lk.traversal « broken window » : « copy never at the target: lk-61 … 3.0 squares from the target », `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`) ; `mp-ambient` : lk.facing et lk.positions FAIL chez le client 2 (`tools/autoclient/runs/20261015-120139-run-54087fb0f84f/run/client2/20261015-100347-steps.txt`) ; contrôles « client 2 » encore non branchés (liste de `docs/tests-en-jeu.md`, à mettre à jour : groupe renommé E10-T04 couvert par carnet.contact, cercle de mission E11-T05 par map.zones, arme braquée LK11-T02 par lk.weapon.state, troc LK11-T08 par lk.tradeview, revendication E00-T01 par rs.claim) ; campagne MP complète verte

- [x] **E01-T17** — Reconnexion et redémarrage du serveur dans la campagne MP
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E01-T16
  - Fichiers : `tools/autoclient/`, suites concernées
  - Faire : étapes de campagne qui déconnectent puis reconnectent un client, et qui arrêtent proprement (`quit`) puis relancent le serveur sur la même partie, avec des suites « avant » et « après ». Seulement pour les tâches dont « Accepté si » l'exige (E00-T01, E10-T04, E11-T06, E12-T05, LK03-T01, LK08-T04, LK11-T08, LK14-T04).
  - Accepté si : chaque contrôle « à automatiser (E01-T17) » du plan a un test vert après reconnexion ou redémarrage réels.
  - Tests : campagne MP réelle.
  - Preuve : option `--phases reconnect,restart` : suites `B.before`, reconnexion réelle des clients (relance sur leur cache, personnage existant chargé par « load » à `OnConnected`), `quit` serveur puis relance sur le même monde, suites `B.after-reconnect`/`B.after-restart` ; pilote : exécutions serveur successives ; bases `mp-persist` = `rs.identity`, `lk.homes` (nouvelles suites `lk.homes.before`/`.after-restart`) ; bancs `test_autoclient.py` 50 OK (`PhaseTests` 9) ; base `logs-and-tools.md` ; commit `6f11326` ; action `reconnect2` (client 2 seul reconnecté, client 1 gardé par « reload »), `mp-persist` à 7 bases (`rs.identity`, `lk.homes`, `lk.leave`, `rs.mission.recover`, `rs.rescue.missed`, `lk.walls`, `lk.rejoin`), instantanés `RST_Persist.lua` ; bancs `test_autoclient.py` 55 OK, `test_persist_suites.py` 9 OK (défauts injectés détectés) ; commit `931a04d` ; premier passage réel le 2026-10-15 (`tools/autoclient/runs/20261015-043927-mp-e129a29e832d`, 9 min) : étape 0 « before » 7/7 PASS, reconnexion du seul client 2 (client 1 gardé par « reload »), reconnexion des deux clients, `quit` du serveur (code 0) et relance : les trois actions réelles ont tourné ; `rs.identity.after-reconnect` 3 PASS + 1 SKIP ; second passage réel (`tools/autoclient/runs/20261015-051633-mp-f2739c903f59`) : reconnexion du client 2 seul, des deux clients et redémarrage du serveur ; 9 PASS après les actions (lk.walls après reconnexion et redémarrage, lk.leave, rs.mission.recover) ; troisième passage (`tools/autoclient/runs/20261015-060712-mp-1a0abb0c888e`) : toutes les suites après reconnexion et après redémarrage PASS sauf lk.rejoin (trajet de 60,5 cases refusé, corrigé à 55 cases par `e6d7174`, non rejoué) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : reconnexion du client 2 seul, des deux clients et redémarrage du serveur ; lk.rejoin.before + lk.rejoin.after-reconnect2 PASS (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093501-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093552-server.txt`), lk.walls (avant, après reconnexion, après redémarrage), lk.homes, lk.leave, rs.identity, rs.mission.recover, rs.rescue.missed, rs.reputation, rs.radiotab, rst.disconnect PASS (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093457-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093730-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`) ; seuls SKIP : chrono de mission sans mission engagée (E00-T01, E03-T04)
  - Reste : —

- [ ] **E01-T18** — API de test réservée au mode debug
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : E01-T10
  - Fichiers : `LK_APITest.lua`, bancs concernés
  - Faire : décision de l'utilisateur du 2026-10-14 (E01-T10) : l'API de test (`testSpawnNpc` et voisines) refuse aussi hors mode debug (`isDebugEnabled()` sur la machine qui l'exécute ; le serveur dédié de test tourne en `-debug`).
  - Accepté si : refus clair hors debug ; campagnes solo et MP toujours vertes.
  - Tests : banc `test_lk_apitest.py` ; campagnes solo et MP.
  - Preuve : `LK_APITest.testAllowed` : autorité, puis `isDebugEnabled()`, puis partie `rstest*` ; refus journalisé en anglais ; serveur de test lancé avec la propriété Java `-Ddebug` (GameServer lit `System.getProperty("debug")`, `GameServer.java:483`, l'argument `-debug` est ignoré) ; bancs `test_lk_apitest.py` 12 OK, `test_autoclient.py` 36 OK ; base `logs-and-tools.md` ; commit `2af4f77` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : fixtures de PNJ admises sur le serveur dédié lancé en debug (suites lk.* vertes, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : lk.bodies 7/7, lk.spawnclean 2/2 (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`, `tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`)
  - Reste : campagne solo du 2026-10-15 non verte (187/212, 19 FAIL dont 11 « npc spawn refused: square … is not loaded » (régression du harnais : le test n'a pas tourné), `tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`, `tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`) ; suite `rst.fixtures.npc` absente des campagnes : à passer

- [ ] **E01-T19** — Campagne `mp-ambient` et suites de gabarits dans la campagne `mp`
  - État : `codé`
  - Cible : `MP`
  - Dépend de : E01-T15
  - Fichiers : `tools/autoclient/`, liste des campagnes du mod de test
  - Faire : petite campagne `mp-ambient` (zombies vanilla, sans mode dieu) pour la robustesse ; ajouter à la campagne `mp` les suites de gabarits de mission non sélectionnées par le filtre `rs.missions` (`rs.mission.clear`, `.retrieve`, `.recover`, `.signal` avec Signal Smoke) (Signal Smoke est prérequis depuis le 2026-10-15 : plus de test sans le mod).
  - Accepté si : `--server-campaign mp-ambient` tourne de bout en bout ; les suites de gabarits passent dans la campagne `mp`.
  - Tests : campagnes MP réelles.
  - Preuve : campagne `mp` complétée (+31 suites dont `rs.mission`, `rs.factions.*`, `rs.trade_*`, `rs.actions.*`, `rs.groupradio`, `lk.traversal`, `lk.force`, `lk.stuck`, `lk.meals`, `lk.repair`, `lk.expedition`, `lk.forage`, suites à deux clients, `lk.routines` en dernier), tag `server` ajouté aux suites jouables sur le serveur, campagne `mp-ambient`, campagnes solo complétées, groupe de test près du point d'apparition (`RST_LKGroupFixture`), étapes de vue (`RST_ViewSteps`), `rs.mission.nosignal` ; bancs `test_autoclient.py` 40 OK (`CampaignContentTests`), `test_rst_steps.py` OK ; commit `446a39d` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : 485/503, 7 FAIL ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : 187/212, 19 FAIL ; campagne `mp-ambient` du 2026-10-15 (copie figée du commit `54087fb`, zombies vanilla, sans mode dieu) : 17/24, 7 FAIL (`tools/autoclient/runs/20261015-120139-run-54087fb0f84f/run/server/20261015-100346-server.txt`)
  - Reste : aucune campagne verte : `mp` (FAIL rs.carnet.leader, rs.factions.accord, lk.traversal ×2, lk.windowkill, lk.handover, étape client lk.track ; `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; solo (19 FAIL dont 11 « npc spawn refused: square … is not loaded » (régression du harnais : le test n'a pas tourné) ; réels : lk.traversal ×2, lk.windowlure, lk.forage ×2, lk.upkeep, rs.relation ; `tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`, `tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`) ; `mp-ambient` (lk.alert ×2, lk.defense ×2, lk.zombies, étapes client lk.facing et lk.positions ; `tools/autoclient/runs/20261015-120139-run-54087fb0f84f/run/server/20261015-100346-server.txt`)
