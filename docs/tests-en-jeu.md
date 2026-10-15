# Tests en jeu (moteur RST)

Mode d'emploi du moteur de tests en jeu **RST** et de ses suites. Le moteur et les suites vivent dans un mod de
développement séparé, `batman_RadioSurvivorTests`, rangé dans le dépôt sous `dev/batman_RadioSurvivorTests/`
(structure B42 : `common/`, `42.21/mod.info`, `42.21/media/lua/`). Il exige `batman_RadioSurvivor`
(`require=\batman_RadioSurvivor`) et n'est **jamais publié** : le mod publié ne contient aucun code de test.

Référence détaillée (en anglais) dans les en-têtes des fichiers Lua :
`shared/RST/RST.lua` (moteur, assertions, filtres, attente par étapes), `client/RST/RST_Client.lua` (commandes
console), `server/RST/RST_Server.lua` (côté serveur, exécution automatique), `shared/RST/RST_Fixtures.lua`
(fixtures du monde).

## 1. Installer le mod de développement

Depuis `%USERPROFILE%\Zomboid\Workshop` :

```powershell
python RadioSurvivor/tools/install_tests.py --dry-run   # affiche seulement ce qui serait copié
python RadioSurvivor/tools/install_tests.py             # copie vers %USERPROFILE%\Zomboid\mods\batman_RadioSurvivorTests
python RadioSurvivor/tools/install_tests.py --dest D:\autre\mods
```

- La copie porte le marqueur `.rst-installed`. Une copie existante n'est remplacée que si elle a ce marqueur ;
  sinon le script refuse (code 2) au lieu d'écraser un dossier inconnu.
- Le dossier Workshop Steam (`steamapps\...\108600`) est refusé comme destination.
- Relancer le script après chaque modification du Lua de `dev/`, puis redémarrer le jeu (ou recharger le Lua).

**Mod requis Belt Walkie-Talkie (`batman_BeltRadio`)** : `batman_RadioSurvivor` déclare `require=\batman_BeltRadio`
et n'embarque plus le récepteur commun ; sans lui, le jeu ne charge pas Radio Survivor. Pour les essais locaux, rien à
copier : le jeu liste aussi les projets de `%USERPROFILE%\Zomboid\Workshop\<projet>\Contents\mods`, donc
`Workshop\BeltRadio\Contents\mods\batman_BeltRadio` apparaît dans **Mods** comme Radio Survivor lui-même (version de
travail du dépôt `BeltRadio`, celle que les tests hors jeu chargent aussi). `install_tests.py` ne le copie pas dans
`Zomboid\mods` : une seconde copie de même `id` y ferait doublon avec celle du dépôt. Ne pas s'abonner en même temps
à la version Workshop publiée (même `id`). Le serveur dédié de fumée (`tests/run_dedicated_smoke.ps1`) copie, lui,
`batman_BeltRadio` dans son cache temporaire et l'ajoute en tête de `Mods=`.

## 2. Lancer le jeu en mode debug

1. Steam → Project Zomboid → Propriétés → Options de lancement : ajouter `-debug`.
2. Dans **Mods**, activer `batman_BeltRadio` (« Belt Walkie-Talkie », activé d'office par le `require=`),
   `batman_RadioSurvivor` et `batman_RadioSurvivorTests` (« batman_RadioSurvivor Tests (dev only) »).
3. Charger ou créer une partie (voir § 5 pour une partie de test), puis ouvrir la **console Lua** :
   touche `²` en AZERTY (`` ` `` en QWERTY). La console n'existe qu'en mode debug.

Hors mode debug (`isDebugEnabled()` faux), `RST.run` et `RST.server` refusent avec
« debug mode is off (start the game with -debug); no test was run ».

## 3. Commandes de la console

| Commande | Effet |
|---|---|
| `RST.list(filtre)` | Liste les suites enregistrées qui correspondent au filtre (nom, tags, nombre de tests). |
| `RST.run(filtre)` | Lance les suites **dans ce client** (ou dans la partie solo). Rend `true`, ou `false` et la raison. |
| `RST.last()` | Réaffiche le dernier rapport du client et le rend. |
| `RST.server(filtre)` | Lance les suites **côté serveur** ; le résumé revient dans la console du client. |
| `RST.lastServer()` | Réaffiche le dernier rapport serveur reçu. |
| `RST.cancel()` | Arrête le passage en cours : le test courant et les suivants deviennent `SKIP cancelled` (les `after` et `t:defer` du test courant s'exécutent). |

Un seul passage à la fois par état Lua : un second `RST.run` (ou `RST.server` en solo) pendant un passage est
refusé. En multijoueur, un `RST.run` client et un passage serveur coexistent (états Lua séparés). Pendant un passage
client, « Break On Error » (débogueur Lua sur erreur) est coupé puis restauré à la fin.

### Filtres

- `nil` : toutes les suites.
- Chaîne `"nom"` : la suite `nom` et celles qui commencent par `nom.` (`"rst"` prend `rst` et `rst.selftest`,
  pas `rstx`). Une chaîne terminée par `.` est un simple préfixe (`"rs."` prend `rs.codec`).
- Table `{ suite = ..., test = ..., tags = ..., exclude = ... }` (tous les champs facultatifs, conditions combinées
  par ET) :
  - `suite` : nom ou liste de noms (même règle que la chaîne, OU entre eux) ;
  - `test` : motif Lua cherché dans le nom de chaque test ; les autres tests sont écartés (pas comptés) ;
  - `tags` : suites ayant au moins un de ces tags ;
  - `exclude` : suites ayant l'un de ces tags écartées.
- `RST.server` n'accepte que des chaînes dans le filtre (il passe par le réseau).

### Exclusions par défaut

- **Client (`RST.run`)** : un filtre `nil`, une chaîne, ou une table sans `tags` ni `exclude` reçoit
  `exclude = { "server", "world" }`. Une table qui donne `tags` ou `exclude` (même `exclude = {}`) est prise
  telle quelle : c'est la demande explicite d'inclure les suites `server` ou `world`.
- **Serveur (`RST.server`, exécution automatique)** : sans `tags`, `tags = { "server", "shared" }` (une suite
  sans tag ne s'exécute jamais côté serveur) ; sans `tags` ni `exclude`, `exclude = { "world" }` ; `client` est
  **toujours** ajouté aux exclusions.
- **`selfcheck`** : une suite portant ce tag (`rst.failures`, échecs volontaires) n'est retenue que si le filtre
  la nomme exactement (`RST.run("rst.failures")`, `{ suite = "rst.failures" }`) ou demande le tag
  (`tags = "selfcheck"`).
- **`manual`** : même règle pour les étapes d'un protocole joué entre des actions manuelles
  (`rs.identity.before`, `rs.identity.after-*`, § 11) : retenues seulement si le filtre les nomme exactement
  (`RST.server("rs.identity.before")`) ou demande `tags = "manual"`. `"rs"` et l'exécution automatique ne les
  prennent jamais.

Exemples :

```lua
RST.run("rst")                                 -- auto-test du moteur
RST.run("rs.codec")
RST.run({ suite = "rs", test = "decode" })     -- seulement les tests dont le nom contient "decode"
RST.run({ suite = "rst", tags = "world" })     -- fixtures du monde, sur une partie rstest* (§ 5)
RST.server("rs.missions")                      -- suite "server" exécutée par le serveur
RST.run("rst.failures")                        -- échecs volontaires : le rapport doit être FAILED
```

### Solo, client MP, serveur

- **Solo** : `RST.run` exécute dans la partie ; `RST.server` exécute les suites serveur dans le même état Lua,
  sans réseau, et écrit `<horodatage>-server.txt` dans le `Zomboid\Lua` local.
- **Client MP** : `RST.server` envoie la demande au serveur, qui exige la capacité `DebugConsole` (le rôle
  `admin` l'a). Réponses : `started`, `denied`, `busy`, `refused`, puis `report` (résumé et au plus 40 lignes
  d'échec). Le rapport complet reste dans le cache du serveur.

## 4. Rapports

À la fin d'un passage, le rapport s'affiche ligne par ligne dans la console (préfixe `[RST]`), un résumé apparaît
au-dessus du joueur, et un fichier est écrit :

- client ou solo : `Zomboid\Lua\batman_RadioSurvivor\tests\<AAAAMMJJ-HHMMSS>-client.txt` (client MP) ou
  `...-solo.txt` (partie solo) ;
- serveur : `<cache du serveur>\Lua\batman_RadioSurvivor\tests\<AAAAMMJJ-HHMMSS>-server.txt` (le dossier
  `-cachedir` d'un serveur dédié, le `Zomboid\Lua` local en solo).

L'horodatage est en **UTC** (pas l'heure locale). Le chemin écrit est rappelé dans la console.

Contenu : un en-tête (version du jeu, côté, demandeur, nom de la sauvegarde, filtre demandé → filtre effectif,
date UTC, mods actifs), une ligne par test `STATUT  suite :: test (durée ms) message`, puis une ligne de bilan
`OK - N test(s): ... pass, ... fail, ... error, ... skip, ... empty (D ms)` ou `FAILED - ...`.

| Statut | Sens |
|---|---|
| `PASS` | Le test a fait au moins une assertion, toutes réussies. |
| `FAIL` | Une assertion a échoué (test, `before` ou `after`), ou délai dépassé (`timeout: ...`). |
| `ERROR` | Erreur Lua ou Java inattendue, ou déclaration de suite en erreur (ligne `(declaration)`). |
| `SKIP` | Test ignoré (`s.skip`, `opts.skip`, `t:skip`), suite `world` refusée, ou passage annulé. |
| `EMPTY` | Le test s'est terminé sans aucune assertion : compté comme un échec. |

Le rapport est `OK` seulement si `fail + error + empty = 0`. Un `after` ou un `t:defer` qui échoue transforme un
`PASS` en `FAIL`/`ERROR` (message `after: ...` ou `cleanup <libellé>: ...`).

Aucun échec connu attendu depuis le 2026-10-09 (`E00-T08` et `E00-T10` corrigés).

## 5. Parties de test et suites `world`

Une suite taguée `world` modifie le monde (objets donnés, joueur déplacé). Elle ne s'exécute que si le nom de la
sauvegarde (`getWorld():getWorld()`) commence par `rstest`, sans tenir compte de la casse (`rstest-solo`,
`RSTest_2`). Sinon chacun de ses tests est `SKIP` avec la raison
« world suite refused: save '<nom>' is not a test save (rstest*) », même si le filtre la demande.

- **Solo** : à la création de la partie, saisir `rstest-solo` dans le champ « Nom de la sauvegarde » de l'écran
  de choix du lieu de départ. N'utiliser cette partie que pour les tests.
- **Serveur dédié** : le nom est celui de `-servername` ; un serveur de test s'appelle donc `rstest…`
  (le serveur automatique ci-dessous s'appelle `rstest_smoke`).
- **Client MP** : le nom vu par le client est `<ip>_<port>_<empreinte>` : les suites `world` ne s'exécutent jamais
  dans un client MP ; les lancer côté serveur par `RST.server({ suite = "rst", tags = "world" })`.

Les fixtures (`RST.Fixtures` : `player`, `giveItem`, `removeItem`, `movePlayer`, `waitSquare`) enregistrent leur
annulation par `t:defer` : objets retirés, joueur ramené à son point de départ après le test, même en cas d'échec.
Côté serveur, un passage sans demandeur (exécution automatique) n'a pas de joueur cible.

## 6. Serveur dédié de test automatique

`tests/run_dedicated_smoke.ps1` lance un serveur dédié isolé, exécute des suites et rend un code de sortie.
Depuis `%USERPROFILE%\Zomboid\Workshop` (PowerShell ou Git Bash) :

```powershell
powershell -ExecutionPolicy Bypass -File RadioSurvivor/tests/run_dedicated_smoke.ps1 -Filters "rst"
powershell -ExecutionPolicy Bypass -File RadioSurvivor/tests/run_dedicated_smoke.ps1 -Filters "rst,rs"
```

| Paramètre | Défaut | Rôle |
|---|---|---|
| `-Filters` | `rst` | Noms ou préfixes de suites, séparés par des virgules (une ligne de `autorun.txt` chacun). |
| `-TimeoutSec` | 600 | Attente maximale du résultat. |
| `-QuitTimeoutSec` | 90 | Attente de l'arrêt après `quit` ; au-delà, l'arbre de processus est tué. |
| `-KeepCache` | — | Garde le cache temporaire même en cas de succès. |
| `-Manual` | — | Ancien usage : même serveur, sans `autorun.txt`, au premier plan ; taper `quit` pour l'arrêter. |
| `-CacheDir` | — | Avec `-Manual` seulement : relance le serveur sur un cache existant (`RS_SMOKE_CACHE=` d'un lancement précédent), même monde, rien n'est recopié (redémarrage du § 11). |

Déroulement :

1. Nouveau cache temporaire `%TEMP%\rs-dedicated-<guid>` (affiché par `RS_SMOKE_CACHE=`) : copie de
   `batman_RadioSurvivor`, `batman_CharacterReputation` et `batman_RadioSurvivorTests` dans `<cache>\mods`,
   configuration `Server\rstest_smoke.ini` (ports 17381/17382, `PauseEmpty=true`). Aucun cache, aucune
   sauvegarde ni aucun dossier de mods existant n'est touché.
2. Écriture de `<cache>\Lua\batman_RadioSurvivor\tests\autorun.txt` : une suite ou un préfixe par ligne, lignes
   `#` ignorées, aucune ligne avec espace. Le serveur le lit à `OnServerStarted` (lecture seule), lance les suites
   (filtre serveur par défaut, donc sans `world`) et avance sur `OnTickEvenPaused`, qui tourne même serveur vide
   et en pause.
3. À la fin, le serveur écrit `autorun-result.txt` : première ligne
   `RST-RESULT ok=true total=6 pass=6 fail=0 error=0 skip=0 empty=0 durationMs=3740 report=...`, puis le
   rapport, puis `RST-END`. `ok=true` exige un rapport `OK` **et** au moins un test exécuté ; une raison
   éventuelle suit `reason=`.
4. Le script affiche le résultat et les lignes `FAIL`/`ERROR`/`EMPTY`, envoie `quit` sur l'entrée du serveur,
   attend l'arrêt, puis signale les erreurs Lua de nos mods trouvées dans `server-console.txt`.

Codes de sortie : `0` = `ok=true` ; `1` = suites en échec (ou aucun test choisi) ; `2` = délai dépassé, échec de
démarrage, `autorun.txt` refusé, ou serveur tué après `quit`. Le cache est supprimé en cas de succès (sauf
`-KeepCache`) et conservé, chemin affiché, en cas d'échec (`server-stdout.log`, `server-console.txt`, rapports).

La ligne `... .fail> Exception thrown` signalée après un passage `rst` réussi vient du test qui vérifie qu'une
assertion rattrapée par `pcall` revient intacte : chaque `error()`, même rattrapé, est journalisé par le jeu.

## 6 bis. Client solo automatique (E01-T14)

`tools/autoclient/autoclient.py` lance le **vrai client** 42.21, charge une copie d'une partie de test `rstest*`,
exécute une campagne ou des suites RST, rapporte le résultat et ferme le jeu. Personne devant le PC : aucun clavier,
aucune souris (le seul geste exigé par le jeu, le clic de l'écran de chargement, est envoyé à la fenêtre par message).
Depuis `%USERPROFILE%\Zomboid\Workshop` :

```powershell
python RadioSurvivor/tools/autoclient/autoclient.py --suite rs.env                    # preuve courte (~50 s)
python RadioSurvivor/tools/autoclient/autoclient.py --campaign solo-rs --timeout 1800   # pont lancé (auto)
python RadioSurvivor/tools/autoclient/autoclient.py --suite rs.npctalk --tags world --wait-idle 3600  # pont, vrai modèle
python RadioSurvivor/tools/autoclient/autoclient.py --save rstest-solo --suite rs.codec,rs.missions --keep-cache
python RadioSurvivor/tools/autoclient/autoclient.py --dry-run --suite rs.env          # prépare le cache seulement
```

| Option | Défaut | Rôle |
|---|---|---|
| `--campaign` / `--suite` | — | `RST.campaign(nom)` ou `RST.run({ suite = {...} })` (exclusion par défaut : ni `server` ni `world`). |
| `--tags`, `--exclude` | — | Avec `--suite` : filtre RST explicite (`tags=` / `exclude=` de la commande, `--exclude ""` = aucune exclusion) à la place de l'exclusion par défaut ; `--tags world` pour les suites `world` (`rs.npctalk`, `rs.relation`…). |
| `--save` | `rstest*` le plus récent | Partie de `Zomboid\Saves\<mode>` (nom `rstest*` obligatoire), **copiée**. |
| `--timeout` | 900 | Délai entre le lancement et le résultat ; au-delà, le processus lancé est tué. |
| `--menu-timeout` | 300 | Délai pour que le pilote Lua signale le menu principal (mods absents au menu sinon). |
| `--quit-timeout` | 120 | Délai de fermeture du jeu après le résultat. |
| `--wait-idle` | 0 | Attente qu'aucun `java.exe` / `ProjectZomboid64.exe` ne tourne (sinon code 3 ; jamais tués). |
| `--start-delay` | 5 | Secondes en jeu avant le passage. |
| `--no-quit`, `--no-screenshot`, `--keep-cache`, `--out` | — | Jeu laissé ouvert ; pas de capture finale ; cache conservé ; dossier de résultats. |
| `--bridge` | `auto` | Pont Python : `auto` (lancé si une suite choisie en a besoin : `rs.npctalk`, `rs.radiomodule`, `rs.relation`, `rs.conversations`, `rs.initiatives`, `rs.groupradio`, préfixes compris ; campagne lue dans `RST_Campaign.lua`, campagne inconnue = lancé), `on`, `off`, `offline` (réponses en écho, sans modèle). |
| `--bridge-timeout` | 60 | Délai pour la ligne « Bridge ready » du pont ; au-delà, ou si le pont s'arrête, le jeu n'est pas lancé (code 2). |

Déroulement :

1. Cache temporaire `%TEMP%\rs-autoclient-*` (`RS_AUTOCLIENT_CACHE=`) : copie de la partie (son `mods.txt` est
   réécrit avec la liste minimale `TooltipLib`, `batman_BeltRadio`, `batman_CharacterReputation`,
   `batman_SignalSmoke`, `batman_RadioSurvivor`, `batman_RadioSurvivorTests`), copie de ces mods dans `mods\`
   (TooltipLib lu dans le Workshop Steam `3694097672` ; les mods requis Belt Walkie-Talkie et Signal Smoke lus dans
   leurs dépôts locaux `Workshop\BeltRadio` et `Workshop\SignalSmoke\Contents\mods\batman_SignalSmoke`, sans rien y
   écrire, toujours copiés, en solo comme en MP), `mods\default.txt` (même liste : pas de rechargement Lua),
   `mods\reset-mods-42_00.txt` (sans lui le jeu vide `default.txt` au premier lancement d'un cache),
   `options.ini` copié de `Zomboid\options.ini` en fenêtré 1280 × 720, et la commande
   `Lua\batman_RadioSurvivor\tests\autoclient.txt`. Rien n'est écrit dans le jeu ni dans `%USERPROFILE%\Zomboid`.
   Pont (si `--bridge` le demande) : `python -u bridge/radio_bridge.py --exchange <cache>\Lua\batman_RadioSurvivor`
   (option existante du pont : il surveille le dossier Lua du **cache**, jamais `%USERPROFILE%\Zomboid`), lancé avant
   le jeu et attendu jusqu'à « Bridge ready ». Le pont lit lui-même sa configuration (`bridge/.env` ou variables
   d'environnement) : l'outil n'ouvre jamais ce fichier. Il est arrêté à la fin dans tous les cas (résultat, échec,
   délai, `--no-quit` compris) ; son journal est rangé en `bridge.log` après un contrôle des chaînes de forme « clé »
   (`sk-…`, `Bearer …`, `OPENAI_KEY=…`, valeur de `OPENAI_KEY` si elle est dans l'environnement) : masquées et code 2
   s'il y en avait. `token_usage.jsonl` (jetons consommés, sans texte ni clé) est copié aussi.
2. `jre64\bin\java.exe` lancé depuis le dossier du jeu avec les `vmArgs` de `ProjectZomboid64.json`
   (`zomboid.steam=0`) et `-cachedir=<cache> -debug -nosound -nosteam`.
3. Le pilote `client/RST/RST_AutoClient.lua` (mod de développement) coupe « Break On Error », attend le menu, appelle
   `MainScreen.continueLatestSave(mode, partie)` (comme le bouton « Charger »). L'écran de chargement attend un clic
   gauche : le lanceur envoie `WM_LBUTTONDOWN`/`UP` à la fenêtre du processus toutes les 3 s tant que le dernier
   état est `load` (sans focus ni déplacement du curseur).
4. En jeu (`OnGameStart`), le passage démarre après `--start-delay` ; à la fin, `autoclient-result.txt` (même format
   que `autorun-result.txt`, § 6), capture `autoclient-<jeton>.png`, puis `getCore():quitToDesktop()` (le jeu
   sauvegarde la **copie** avant de sortir).
5. Résultats copiés dans `tools/autoclient/runs/<date>-<jeton>/` (ignoré par git) : résultat, journal d'états
   `autoclient-status.txt`, rapport RST, captures du passage, `console.txt`, sortie du processus, `bridge.log`,
   `token_usage.jsonl`.

Codes de sortie : `0` rapport OK ; `1` tests en échec ; `2` délai, démarrage raté, partie refusée par le menu, pilote
muet ou jeu tué ; `3` un jeu ou un serveur tourne déjà. Le cache est supprimé en cas de succès (sauf `--keep-cache`).

Limites : liste de mods minimale (les autres mods de la partie d'origine ne sont pas chargés, leurs objets disparaissent
de la copie) ; sans Steam, aucun mod Workshop abonné n'est trouvé (`-nosteam`, voir la base) ; avec `--bridge on|auto`, les
suites du pont appellent le vrai modèle (coût, durée variable) ; un clic envoyé juste avant l'entrée en jeu peut tomber au
centre de l'écran de jeu ; Windows seulement. Banc hors jeu : `python RadioSurvivor/tests/test_autoclient.py`.

## 6 ter. Multijoueur automatique : serveur dédié de test et clients pilotés (E01-T15)

Le même outil, avec `--mp`, démarre un **serveur dédié de test** et y connecte **un à quatre vrais clients** sans personne
devant le PC. Depuis `%USERPROFILE%\Zomboid\Workshop` :

```powershell
python RadioSurvivor/tools/autoclient/autoclient.py --mp --server-suite rs.identity,rs.codec            # ~1 min 30
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --suite rs.env --server-suite rs.identity
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --server-campaign mp --bridge on --timeout 7200
python RadioSurvivor/tools/autoclient/autoclient.py --mp --server-suite lk.melee --server-tags world
python RadioSurvivor/tools/autoclient/autoclient.py --mp --server-suite rs.npctalk,rs.relation --server-tags world --bridge on
python RadioSurvivor/tools/autoclient/autoclient.py --mp --load --bridge off --timeout 3600 --wait-idle 3600   # charge LK13-T02
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --server-suite rs.mission.signal,rs.rescue,rs.trade_run --server-tags server,world --bridge on --llm fake
```

| Option | Défaut | Rôle |
|---|---|---|
| `--mp` | — | Mode multijoueur (sans lui : client solo du § 6 bis). |
| `--clients` | 1 (4 avec `--load`) | 1 à 4 clients (LK13-T02). Le client 1 exécute ; les clients 2..N (rôle « peer », E01-T16) répondent aux étapes des suites serveur (voir « Client 2 actif » ci-dessous ; cible `others` = tous les autres) et rendent chacun leur résultat. Comptes `rs_mp1`..`rs_mp4`, caches `rs-mp-client<N>-*`, lancés l'un après l'autre, `MaxPlayers=4`. |
| `--group-count` | défaut du mod | Option sandbox `LivingKnox.GroupCount` (3 à 5) du monde neuf, écrite dans `Server\rstest_mp_SandboxVars.lua` (table `LivingKnox`). |
| `--load` | — | Campagne de charge LK13-T02 (`docs/validation/charge-protocole.md`) : 4 clients, 5 groupes, campagne serveur `mp-load` si `RST_Campaign.lua` la déclare, sinon `--server-suite lk.load --server-tags server` ; monde neuf (cache serveur neuf à chaque passage) ; `--timeout` 3600 par défaut (passe serveur `lk.load` + `lk.loadmp` ≈ 20 min). Les options explicites priment. Pas avec `--phases`. |
| `--load-phase-ms N` | — | Durée d'une phase de `lk.loadmp` (au moins 30000 ; défaut de la suite 300000). Kahlua n'a pas `os.getenv` : le lanceur écrit la globale Lua `RST_LK_LOADMP_PHASE_MS = N` dans `RST/RST_LaunchGlobals.lua` de la COPIE du mod de test de chaque cache du passage (serveur et clients : même somme de contrôle), jamais dans le dépôt. `--mp` seulement. |
| `--suite` / `--campaign` (+ `--tags`, `--exclude`) | — | Passage **côté client 1** (`RST.run`, avant la demande serveur). Attention : la garde `world` refuse les suites `world` côté client (le monde du client s'appelle `127.0.0.1_17391_<empreinte>`, pas `rstest*`). |
| `--server-suite` / `--server-campaign` (+ `--server-tags`, `--server-exclude`) | — | Passage **sur le serveur** demandé par le client 1 (`RST.server`, il est admin). `--server-campaign mp` = `RST.CAMPAIGNS["mp"]` (`RST_Campaign.lua`), suites `manual` exclues. `--server-tags world` est l'exception explicite pour les suites `world` (le serveur s'appelle `rstest_mp` : garde satisfaite). |
| `--timeout` | 900 | Délai total ; c'est aussi le délai d'attente du rapport serveur par le client. |
| `--server-timeout` | 300 | Délai pour que le serveur écoute. |
| `--no-godmode` | — | Par défaut, dès qu'un client est en jeu, le lanceur tape `godmodeplayer <compte> -true` sur la console du serveur (`GodModePlayerCommand` : `setGodMod` + `sendPlayerExtraInfo`, appliqué au client aussi). Sans cela (passage du 2026-10-14), les zombies du quartier ont tué les deux joueurs immobiles en 3 min et toutes les suites suivantes ont échoué (« attacker is dead »). `--no-godmode` les laisse mortels. |
| `--ambient-zombies` | — | Par défaut, le serveur de test n'a **aucun zombie ambiant** : `Server\rstest_mp_SandboxVars.lua` partiel, `ZombieConfig.PopulationStartMultiplier = 0.0` et `PopulationPeakMultiplier = 0.0` (site calme comme les parties de test solo ; les suites créent leurs zombies). Passage du 2026-10-14 : la maison de Muldraugh, entourée de zombies, gardait chaque groupe de test en alerte et en défense (`lk.alert`, `lk.defense`, `lk.chores`, `lk.warn`…). Pas `Zombies = 6` (« None ») : `IsoWorld.getZombiesDisabled()` ferait refuser `addZombiesInOutfit` hors debug (« Cannot spawn. »), donc aucun corps de PNJ. `--ambient-zombies` garde la population vanilla. |
| `--client-xmx`, `--server-xmx` | 4096m, 3072m | Mémoire maximale des JVM (le client vanilla demande 16 Go : bornée ici). Au départ : mémoire libre, total des `-Xmx` et estimation avec la part native (+1,5 Go par client, +0,75 Go pour le serveur) ; avertissement si la mémoire libre est plus faible. Quatre clients à 4096m : 19 Go de `-Xmx`, environ 26 Go estimés. |
| `--bridge` | `auto` | Pont Python lancé sur le dossier d'échange **du serveur** (`<cache serveur>\Lua\batman_RadioSurvivor` : `RS_Transport.lua` est un fichier `server/`). `auto` le lance si une suite client ou serveur choisie en a besoin ; `on` toujours. |
| `--wait-idle`, `--start-delay`, `--quit-timeout`, `--no-screenshot`, `--keep-cache`, `--out`, `--dry-run` | — | Comme en solo (`--dry-run` affiche les trois commandes, mot de passe masqué). |

Déroulement :

1. Refus si un `java.exe` ou `ProjectZomboid64.exe` tourne (`--wait-idle` pour attendre ; rien n'est jamais tué hors des
   processus lancés par l'outil).
2. Serveur : cache `%TEMP%\rs-mp-server-*` (mods copiés comme en solo, `Server\rstest_mp.ini` : privé, `Open=true`,
   `PauseEmpty=true`, ports 17391/17392, `SpawnPoint=10656,10137,0` — une maison de Muldraugh, ce qui supprime l'écran de
   choix du point d'apparition), lancé `zombie.network.GameServer -nosteam -adminusername rs_mp1 -adminpassword <tiré au
   hasard pour ce passage>`, entrée standard en tube. Prêt à la ligne « server is listening on port ». Comptes des
   clients suivants créés et promus par la console : `adduser rs_mp2 <mdp>`, `setaccesslevel rs_mp2 admin` (un client
   `-debug` sans la capacité `ConnectWithDebug`, réservée à `admin`, est déconnecté à la connexion).
3. Clients lancés l'un après l'autre (le suivant quand le précédent est en jeu), caches `%TEMP%\rs-mp-client<N>-*`. Le
   pilote `RST_AutoClient.lua` (commande `connect=`, `user=`, `password=`, `control=true`) appelle au menu
   `ConnectToServer.instance:connect(...)` comme la fenêtre « Rejoindre un serveur », puis, dans l'état Lua recréé par
   la connexion, appuie sur « Suivant » de l'écran des métiers puis de l'écran du personnage (valeurs par défaut) ; le
   lanceur clique l'écran de chargement. États : `menu`, `connect`, `create`, `load`, `ingame`, `go`, `run`, `server`,
   `done` / `idle`, `quit`.
4. Quand tous les clients sont en jeu, le lanceur écrit `go` dans `autoclient-control.txt` de chaque client ; le
   client 1 fait son passage client puis la demande serveur, et écrit `autoclient-result.txt` : compteurs additionnés
   client + serveur, lignes du rapport client, `SERVER <résumé>` et jusqu'à 40 lignes d'échec du serveur,
   `serverReport=<fichier>` dans la première ligne. Ensuite `quit` dans tous les fichiers de contrôle (`quitToDesktop`),
   puis `quit` sur l'entrée standard du serveur ; arrêt forcé après `--quit-timeout`.
5. Résultats : `tools/autoclient/runs/<date>-mp-<jeton>/server/` (sortie, `server-console.txt`, rapports complets
   `*-server.txt`, `Logs-*`, `bridge.log`) et `client<N>/` (comme en solo).

Codes de sortie : ceux du § 6 bis ; `2` aussi si le serveur ne démarre pas ou s'arrête, si un client sort sans résultat,
si le client 2 n'a pas atteint son état ou n'a pas écrit le résultat de ses étapes au « quit » ; `1` si une étape du
client 2 a échoué. Banc hors jeu (pilote et orchestration simulés) :
`python RadioSurvivor/tests/test_autoclient.py`.

Déplacements du joueur par le serveur (`RST.Fixtures.movePlayer`) : l'attente se termine quand le joueur est arrivé
**et** que les cases à `F.LOAD_RADIUS` (12) autour de la cible sont chargées sur le serveur (sinon la suite suivante
trouvait « square … is not loaded »). `F.movePlayers` déplace aussi tous les autres joueurs connectés du même décalage
(et les ramène) : suites qui doivent décharger la zone (`lk.bodies`, `lk.guard`) avec deux clients.

Limites : clients sur la même machine (latence nulle : pas de mesure réseau réaliste) ; un serveur ne téléporte pas un
client, les suites qui cherchent un autre lieu (`RST.Places`) passent en SKIP ; personnage neuf à chaque passage (monde
neuf, aucune reconnexion ni redémarrage du serveur dans la même commande) ; Windows seulement.

### Lancements parallèles, tranches de campagne et faux modèle (2026-10-15)

Plusieurs commandes de l'outil peuvent tourner en même temps (machine de 63 Go et 24 cœurs : une campagne MP à deux
clients prend environ 11 Go ; viser 3 lancements).

| Option | Défaut | Rôle |
|---|---|---|
| `--max-parallel N` | 3 | Emplacements partagés par les lancements : fichiers `%TEMP%\rs-autoclient-slots\slot-<i>.json` (pid de l'outil, pids du jeu et du serveur qu'il a lancés). Un lancement attend (`--wait-idle`) un emplacement libre ; un emplacement dont l'outil est mort (arrêt brutal) est repris. Les `java.exe` des **autres lancements** ne bloquent plus ; un jeu ou un serveur non lancé par l'outil (le joueur) bloque toujours (code 3, jamais tué). |
| `--port-base P` | 17391 + 10 × emplacement | Ports du serveur de test (`UDPPort = P + 1`), décalés de 10 tant qu'ils sont pris (TCP et UDP essayés). Caches, comptes, fichiers de contrôle et dossier `runs/` sont déjà propres à chaque lancement. |
| `--shard K/N` | — | Tranche K sur N d'une `--campaign` ou `--server-campaign` : entrées réparties par la durée connue (rapports RST précédents de `runs/`, la plus longue d'abord vers la tranche la moins chargée), sinon tour à tour par nom ; ordre de la campagne gardé dans la tranche (`lk.routines` reste la dernière de la sienne) ; filtre de la campagne gardé (serveur : exclusion `manual`). Refusé avec `--phases` et pour `mp-persist`. En solo, la tranche est passée en `--suite` (exclusion vide) : l'ordre de `RST.campaign` n'est pas réappliqué. |
| `--llm real\|fake` | `real` | `fake` : `tools/fake_llm/fake_llm.py --port P` (port libre, ligne `FAKE LLM READY port=P`) puis pont lancé avec `OPENAI_BASE_URL=http://127.0.0.1:P/v1`, `OPENAI_MODEL=fake`, `OPENAI_KEY=fake` (l'environnement prime sur le `.env` du pont, jamais lu par l'outil) ; arrêté à la fin, journal `fake_llm.log` dans le dossier du run (`server/` en MP). Sans pont (ou `--bridge offline`) : rien n'est lancé. |

`tools/autoclient/campaign_parallel.py --shards N [--stagger 20] -- <options de autoclient.py>` lance les N tranches
(`--shard K/N`, `--out runs/<date>-parallel-N/shard<K>`, `--max-parallel` au moins N) à `--stagger` secondes d'écart,
attend, puis écrit `summary.txt` : totaux (premières lignes `RST-RESULT` de chaque client), lignes FAIL/ERROR des
rapports RST, code et journal de chaque tranche. Code de sortie : le pire des tranches.

```powershell
python RadioSurvivor/tools/autoclient/campaign_parallel.py --shards 3 -- --mp --clients 2 --server-campaign mp --bridge on --llm fake --timeout 5400 --wait-idle 3600
python RadioSurvivor/tools/autoclient/campaign_parallel.py --shards 2 -- --campaign solo-rs --timeout 1800 --wait-idle 3600
python RadioSurvivor/tools/autoclient/autoclient.py --mp --server-campaign mp --shard 2/3 --port-base 17500 --dry-run
```

**Copie figée (`--commit REF`)** : `campaign_parallel.py` crée un `git worktree` détaché de REF dans
`%TEMP%\rs-worktree-<12 premiers caractères du hash>` (suffixe `-2`, `-3`… si le dossier existe ; jamais dans le
dépôt), lance l'`autoclient.py` de **cette copie** (ses mods, sa campagne, son pont, son faux modèle), range les
résultats dans `tools/autoclient/runs/` du dépôt principal (`<date>-parallel-N-<hash>` ou `<date>-run-<hash>`, avec
`commit.txt`), puis retire **ce** worktree par `git worktree remove --force` (jamais `stash`, `checkout`, `reset` ni
`prune` du dépôt principal) : le travail en cours des autres agents ne change pas les mods pendant la campagne.
Variables données à l'`autoclient.py` de la copie : `RS_WORKSHOP_DIR` (vrai dossier `Workshop` : mods frères
`BeltRadio`, `CharacterReputation`, `SignalSmoke` ; `TooltipLib` vient du Workshop Steam) et `RS_AUTOCLIENT_RUNS`
(`runs/` du dépôt principal : durées des rapports pour `--shard`). Un commit antérieur à cette option (sans
`RS_WORKSHOP_DIR`) est refusé (code 2) ; une source de mod absente arrête `autoclient.py` (code 2, chemins cités). Le
pont de la copie n'a pas de fichier de configuration (ignoré par Git) : `--llm fake`, ou `OPENAI_*` dans
l'environnement pour un vrai modèle (avertissement sinon). Sans `--shards`, `--commit` fait **un seul** lancement,
options passées telles quelles (campagne à étapes `mp-persist` comprise), dossier `<parent>/run`. `--dry-run` affiche
le worktree et les commandes sans rien créer.

```powershell
python RadioSurvivor/tools/autoclient/campaign_parallel.py --commit HEAD --shards 3 -- --mp --clients 2 --server-campaign mp --bridge on --llm fake --timeout 5400 --wait-idle 3600
python RadioSurvivor/tools/autoclient/campaign_parallel.py --commit HEAD -- --mp --clients 2 --phases reconnect2,reconnect,restart --server-campaign mp-persist --llm fake --timeout 5400 --wait-idle 3600
```

**Faux modèle et E17-T13** : la première réplique `npc_talk` qu'un PNJ adresse à un inconnu (stade `stranger`, aucune
réplique précédente de ce PNJ dans l'historique) est longue (plus de 180 caractères, plusieurs phrases entières de
moins de 180) ; les tours suivants restent courts. Chaque test de `rs.npctalk` rencontre un nouveau PNJ : le test
E17-T13 (bulles découpées) reçoit donc toujours une réponse de plusieurs morceaux, sans que le faux modèle lise la
phrase du joueur.

### Client 2 actif : étapes nommées (E01-T16)

Une suite exécutée par l'autorité (serveur dédié par `RST.server`, ou solo) demande aux clients de vérifier ce
qu'**ils** voient, ou d'agir comme un joueur, par des **étapes nommées** : `RST.Steps.ask(t, étape, args, opts, suite)`
(`shared/RST/RST_Steps.lua`). Le serveur envoie `ask { seq, step, args, ms }` (module `RSTStep`) aux cibles
(`others` par défaut : tous les joueurs connectés sauf le demandeur ; `requester` ; `all` ; liste de comptes) ; chaque
client exécute le gestionnaire de l'étape (`RST.Steps.on`, à l'appel ou à chaque image jusqu'à son délai) et répond
`answer { seq, status, message, data }` (PASS, FAIL, ERROR, SKIP). Le serveur écrit une assertion par client dans son
rapport : réponse absente = FAIL « client <compte> missed step <étape> within N ms », FAIL ou ERROR = FAIL avec le
message du client, SKIP = note (un client qui ne peut pas vérifier, par exemple une case non chargée chez lui). Une
réponse d'un compte non interrogé est ignorée (journal `[RST-STEP]`). En solo, même code sans réseau : `requester`
et `all` = le joueur local, `others` = personne (étape notée, la suite continue).

Rapports : chaque client écrit `Zomboid/Lua/batman_RadioSurvivor/tests/<stamp>-steps.txt` (une ligne par étape
répondue), copié dans `runs/<passage>/client<N>/` ; le client 2 (`peer=true` dans sa commande) écrit en plus, au
« quit », son `autoclient-result.txt` (`RST-RESULT ok=… total=<étapes> pass= fail= error= skip=` puis une ligne
`STEP …` par étape), exigé par le lanceur comme celui du client 1.

Étapes fournies (`shared/RST/RST_PeerChecks.lua`) et suites qui les posent :

| Étape | Vérification ou action côté client | Suites |
|---|---|---|
| `world.keys` | Clés des cases (cadavres : vêtements portés et contenu ; barricades : planches ; constructions `IsoThumpable` par nom ; meubles à conteneur par sprite et contenu) égales à celles du serveur, calculées par la même fonction ; attente de la réplication jusqu'au délai | `lk.death`, `lk.loot` (même cadavre, même contenu), `lk.stock` (caisses, vol compris), `lk.barricade`, `lk.walls` |
| `lk.look` | Copie locale de chaque corps (trouvée par `getOnlineID`) : peau, coupe, barbe, couleur, clés de vêtements | `lk.appearance` (premier test) |
| `lk.speech.seen` | Chaque réplique entendue par ce compte (liste `names` de `LivingKnox.Speech.say`, enregistrée sur le serveur) reçue par sa vue de parole (`SpeechView.seen`) ; le serveur exige aussi que chaque autre client soit parmi les auditeurs | `lk.retreat` (reddition, trahison), `lk.alert` (cri), `rs.conversations`, `rs.initiatives` (demandeur) |
| `rst.access` | Le **demandeur** (admin) envoie `/setaccesslevel rs_mp<N> user` (ou `admin`) (`SendCommandToServer`) ; comptes de test du lanceur seulement, jamais lui-même | suites de droits (ci-dessous) |
| `rst.request` | Ce client envoie la commande réelle d'un outil (`LivingKnox/adminRequest`, `RadioSurvivorDebug/freqRequest`) et rend la réponse de même numéro | `lk.admin`, `lk.npcsheet`, `lk.debugview`, `rs.freqdebug` : test « a real client with the user role is refused without data (E01-T16) » (client 2 passé `user`, refus sans donnée, compteur de refus du serveur ; `admin` rendu à la fin ; SKIP en solo) |
| `carnet.send`, `carnet.talk`, `carnet.state` | Carnet du **demandeur** : `select` / `accept`, ligne « Dire » après la réponse attendue et le délai, état (dernière erreur, offre affichée, ligne de mission engagée) | `rs.npctalk`, `rs.relation`, `rs.conversations` |
| `lk.speech.pieces` | Morceaux de la bulle d'une réponse longue et ordre d'affichage (E17-T13) chez le demandeur | `rs.npctalk` |

Étapes Living Knox à deux clients (`shared/RST/RST_PeerChecksLK.lua`, fichier partagé chargé par le jeu sur chaque
machine ; suites dans des fichiers à part, étiquetées `world` et `server`) :

| Étape | Vérification ou action côté client | Suites |
|---|---|---|
| `lk.report.forge` | Ce client envoie un rapport d'état de corps construit par le serveur (commande réelle `LivingKnox/bodyReport` ; solo : appel direct de `Reports.onReport`) | `lk.ownerreports` (LK03-T02 : client non propriétaire refusé « not the owner » ; propriétaire qui « téléporte » le corps à 40 cases, puis santé en hausse : refusés, ligne WARN, état et corps inchangés ; partie non propriétaire SKIP en solo) |
| `lk.gesture.watch`, `lk.gesture.seen`, `lk.gesture.not` | Premier tick où le geste relayé ici (`Anim.gestureOf`) devient le geste posé, sur l'horloge serveur synchronisée (`GameTime.getServerTimeMills`) ; geste jamais reçu hors de portée | `lk.relay` (LK03-T05 : trois gestes vus en moins de 300 ms par le client 2 ; client 2 à 160 cases : aucun message du relais, le proche en reçoit ; SKIP en solo) |
| `lk.appear.watch`, `lk.appear.check` | Zombies vus à chaque tick autour d'une case (ceux déjà là exclus) : un seul à la fois, aucun d'un autre `onlineId`, aucune voix de zombie jouée ; client MP : préfixe de voix muet dès le premier tick et aucune voix arrêtée par la garde | `lk.spawnclean` (LK03-T06 : apparition et retour de chunk, vérifiés par chaque client ; solo sur la seule machine) |
| `lk.melee.swing`, `lk.melee.silence` | Élan joué sur la copie du corps (réponse immédiate, le serveur tue alors le PNJ), puis, 4 s après la mort vue ici : aucun élan ni impact joué, émetteur du corps mort muet, élan en cours arrêté à la mort | `lk.deathswing` (LK06-T13 : client 2 auditeur ; solo : joueur local) |

`lk.handover` (LK03-T03) n'a pas d'étape client : le serveur déplace tour à tour les deux clients près du corps
(`F.movePlayer`) pendant une consigne de 30 cases et mesure chaque changement de propriétaire, la reprise par le
nouvel exécutant (`Directives.stats.resumeLast` ≤ 1 s) et l'écart entre deux rapports d'exécution qui montrent un
progrès autour du changement (≤ 2 s, un rapport par seconde) ; SKIP en solo et avec un seul client. Banc des cinq
suites sur doublures (serveur + deux clients, solo, défauts injectés) : `python RadioSurvivor/tests/test_lk_peer_suites.py`.

Étapes radio, carnet et factions à deux clients (`shared/RST/RST_PeerChecksRadio.lua`, requis par les suites qui les
posent, donc chargé sur chaque machine qui charge les suites ; client MP : un écouteur `OnServerCommand` unique garde
les dernières commandes des modules `RadioSurvivor` et `RS_Carnet` ; solo : `RadioSurvivor_Const.clientHandler` et
`RS_CarnetClient.receive` enveloppés à la première étape qui en a besoin) :

| Étape | Vérification ou action côté client | Suites |
|---|---|---|
| `rs.talk` | Ce client envoie la vraie commande radio `talk` (radio d'inventaire `itemId`, radio posée `source=world` x y z index, autoradio `source=vehicle`) et rend la première réponse du serveur (`accepted` ou `rejected` et le motif) | `rs.worldradio` (E06-T03 : demandeur accepté à 1 case, refusé `TooFar` à 10 cases, `Off` radio éteinte, client 2 selon la règle du serveur à sa position ; passager de l'autoradio accepté, client 2 hors de la voiture refusé `NotInVehicle`), `rs.radio` (E06-T05 : `NoRadio` sans radio portée, phrases des deux joueurs sur une puis deux fréquences libres) |
| `rs.vehicle` | Ce client monte sur un siège (`BaseVehicle:enter`, comme `ISEnterVehicle`, paquet `VehicleEnter`) ou descend (`exit`) ; attend que le véhicule lui soit connu | `rs.worldradio` (autoradio) |
| `rs.history` | Onglet Radio de ce client : historique redemandé au serveur (`RS_RadioHistory.request`), lignes trouvées par texte (`khz:kind`), personnages nommés par toutes les commandes d'historique reçues depuis le chargement | `rs.radio` (ses phrases en `said` sur la bonne fréquence, celles de l'autre joueur seulement en `heard`, aucun historique d'un autre personnage) |
| `rs.faction` | Paquets du panneau des factions : création (`sendFactionCreate`), renommage (`sendFactionChangeTitle`), dissolution (`sendFactionDisband`) ; MP seulement | `rs.factions.mandate` |
| `carnet.mandate` | Commande `mandate` du carnet (onglet Équipe), dernière erreur rendue (`MandateOwner`…) | `rs.factions.mandate` (E09-T03 : le membre sans mandat refusé en se désignant lui-même ; désignation puis retrait par le propriétaire) |
| `carnet.count` | Pendant `ms`, instantanés du carnet reçus et demandes `snapshot` / `hello` envoyées par ce client | `rs.carnet.load` (E00-T04 : aucun instantané non demandé pendant 12 s d'inactivité) |

Suites (étiquettes `server` et `world`, autorité seulement ; même code en solo, parties à deux clients en SKIP ou
notées) : `rs.worldradio` (E06-T03), `rs.radio` (E06-T05 ; la reconnexion reste au protocole manuel), `rs.carnet.load`
(E00-T04 : 30 PNJ de test sans contact = 0 fiche et 0 demande d'enrichissement ; serveur inactif = aucun instantané non
demandé et aucune sauvegarde, puis une sauvegarde après un changement ; fiche contactée jamais purgée, une fiche sans
contact purgée à la purge suivante, `seenAt` reculé d'une heure), `rs.observations` (E08-T07 : `assault_seen`,
`group_death` devant les membres et hors écran, `player_return` avec `nearHour` reculé d'un jour, `mission_done` ;
un fait par témoin admissible, rien chez un PNJ qui n'a pu le voir, aucune fiche créée, lieux en maille `area-x-y`),
`rs.factions.mandate` (E09-T03 : faction créée et renommée par le client propriétaire, client 2 ajouté comme membre par
le serveur — `Faction:addPlayer`, sans la boîte d'invitation — ; même identifiant d'équipe et même accord après le
renommage). Exemple : `python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --server-suite
rs.worldradio,rs.radio,rs.carnet.load,rs.observations,rs.factions.mandate --server-tags world --bridge auto --timeout
3600 --wait-idle 3600`. Banc des cinq suites sur doublures (serveur + deux clients, solo, défauts injectés) :
`python RadioSurvivor/tests/test_rs_mp_suites.py`.

Suites du carnet en MP (`rs.npctalk`, `rs.relation`, `rs.conversations`, `rs.initiatives`) : étiquetées `world` et
`server`, dans la campagne `mp` (pont lancé sur le dossier d'échange du serveur : `--bridge auto` le voit dans la
campagne). Même suite en solo (`RST.run`, campagne `solo-rs` inchangée) : l'autorité crée le PNJ et lit les requêtes ;
ce que fait ou voit le joueur passe par le client demandeur, donc par le vrai chemin réseau en MP (client → commande
`talk` → serveur → pont → réponse → bulle et carnet du client).

Niveau d'accès `user` d'un client `-debug` : `ConnectWithDebug` n'est vérifié qu'à la connexion
(`ConnectToServerState.TestTCP`) ; ensuite, l'anti-triche « Power » rejette les paquets du joueur (drapeau debug sans
la capacité, `AntiCheatPower`, `IsoPlayer.getAnticheatMask`) et l'expulse quand le serveur n'est pas en debug. L'ini
du serveur de test porte donc `AntiCheatPermission=4` (désactivé) ; les droits des paquets
(`PacketTypes.PacketAuthorization`) et de Lua (`checkPermissions`) ne dépendent pas de cette option. Le passage à
`user` retire le mode dieu (rôle sans `ToggleGodModHimself`, `GameServer.changeRole`) ; le retour à `admin` le rend.

Contrôles « client 2 » du plan non automatisés (raison) : réplique de refus d'un membre entendue (E10-T03 : demande un
LLM en ligne pour la réplique, pas de suite qui la provoque sans pont) ; mort réelle d'un client (E14, E15 : aucune
suite ne tue un client, le mode dieu est posé par le lanceur) ; décompte de mission à deux participants, cartes,
sacs et fumigènes (E11-T04..T07 : gabarits dans la campagne `mp` depuis E01-T19, mais vus par un seul client ;
actions de joueur à ajouter aux étapes) ;
revendication de l'identité d'un autre compte (E00-T01 : commande à forger côté client) ; reprise d'une consigne
par un client reconnecté (LK02-T07, LK03-T01 ; LK03-T02, T03, T05 sont couverts par `lk.ownerreports`,
`lk.handover`, `lk.relay` ci-dessus) ; reconnexion d'un client pendant l'apparition d'un PNJ (LK03-T06) ; vengeance et
aide vues par le second client (LK11-T05/T06) ; troc par le menu « Troquer » d'un client et un seul gagnant quand A et
B demandent la même conserve (LK11-T08 : `lk.trade` se passe de corps et de fenêtre ; il faudrait un corps de PNJ près
des deux clients, des objets donnés aux deux inventaires et une étape client qui ouvre `LivingKnox.TradeView` et
propose) ; arme braquée pendant la sommation (LK11-T02 : `lk.weapon.state` demande l'emplacement et l'objet, non relevés
par `lk.warn`) ; cercle de mission retiré chez le client (E11-T05) ; groupe renommé dans le carnet (E10-T04).

Contrôles du second client branchés le 2026-10-15 (étapes de `shared/RST/RST_PeerChecksH.lua`, requis par les suites
qui les posent ; cible `all` : les deux clients, le joueur local en solo) :

| Étape | Vérification côté client | Suites |
|---|---|---|
| `lk.health.view` | `LivingKnox.HealthView.get(npc)` (copie `npcHealth` du serveur ; solo : l'autorité) égale à la santé de référence à 1 % du maximum près, même maximum ; sondée | `lk.health` (LK07-T02, après le coup) |
| `lk.alert.view` | Début / fin : cris reçus ici (`AlertView.stats` : reçus − doublons) = cris de l'autorité, chacun joué une fois, voix `Voice*ShoutHey`, aucun refus | `lk.alert` (LK05-T08) |
| `lk.facing` | Copie de chaque corps tournée vers un point (`getDirectionAngle`, écart ≤ `maxDeg`) ; sondée | `lk.alert` (membres vers la dernière position connue, 60°) |
| `lk.positions` | Copie de chaque corps à moins de `tol` cases de la position de l'autorité, même étage ; sondée | `lk.defense` (LK05-T09 : membres revenus à leurs places, 2,5 cases) |
| `world.upkeep` | Générateur de chaque case : carburant (0,05 l) et état de l'autorité ; ni verre brisé ni sang sur les cases nettoyées ; case non chargée : SKIP | `lk.upkeep` (LK05-T10) |

Étapes existantes rebranchées : `lk.speech.bubble` aussi chez les autres clients (chacun doit figurer parmi les
auditeurs, `lk.speech`, LK11-T04) ; `lk.weapon.state`, `lk.weapon.count` (`lk.equipment`, LK02-T06) et
`lk.combat.view` (`lk.ranged`, LK06-T03) passent de `requester` à `all` ; `lk.warn` (LK11-T02) : `lk.speech.seen` des
sommations chez les autres clients et, sur serveur dédié, coup de semonce joué une fois par chaque client
(`lk.combat.view`) ; `lk.alert` : réplique d'alerte aussi chez le demandeur (serveur dédié) ; `world.keys` des
cadavres : `lk.zombies` (LK06-T04, cases 3 × 3 autour de chaque mort), `rs.rescue.missed` (E12-T07 : copie du zombie
attendue chez les autres clients par `lk.present` avant sa mort, puis cadavre et cahier), `rs.mission.retrieve`
(E11-T05 : clients déplacés ensemble par `F.movePlayers`, corps avec la carte, puis sans elle) ; `map.known` chez
chaque autre client avant et après la révélation, état inchangé (`rs.actions.reveal`, E07-T05). Banc des nouvelles
étapes : `python RadioSurvivor/tests/test_rst_steps.py` (classe `HStepTests`).

### Campagnes solo et MP (E01-T19)

Listes nommées de `client/RST/RST_Campaign.lua` (`RST.campaigns()` les affiche ; banc de leur contenu :
`tests/test_autoclient.py`, classe `CampaignContentTests`). Une entrée choisit la suite de ce nom et les suites
`<entrée>.*`, jamais `<entrée>s` : `rs.missions` joue `rs.missions.radio`, `.scout`, `.solo` mais **pas** les gabarits
`rs.mission.*` (singulier : `clear`, `retrieve`, `recover`, `signal`), choisis par l'entrée `rs.mission`.

| Campagne | Où | Contenu et remarques |
|---|---|---|
| `solo-lk`, `solo-rs`, `solo` (= les deux) | `RST.campaign` (client solo, `--campaign`) | Ajouts E01-T19 : `lk.revenge`, `lk.traversal` (environ 7 min), `lk.upkeep` ; `rs.rescue` (cinq suites), `rs.conversations`, `rs.initiatives`, `rs.groupradio` (pont). |
| `mp` | serveur dédié (`--server-campaign mp`) | Le serveur ne garde que les suites étiquetées `server` ou `shared` de la liste (`RST_Server.lua` : étiquettes par défaut, `client` toujours exclu, `manual` exclu par le pilote) : une suite étiquetée seulement `world` n'y tourne **jamais** (contrôlé par le banc). Ajouts E01-T19 : `rs.mission` (cinq gabarits), `rs.factions.accord`, `rs.factions.incident`, `rs.trade_exchange`, `rs.trade_run`, `rs.actions.map`, `rs.actions.reveal`, `rs.groupradio`, `lk.equipment`, `lk.ranged`, `lk.speech`, `lk.traversal`, `lk.force`, `lk.stuck`, `lk.milestone1`, `lk.essai`, puis `lk.meals`, `lk.repair`, `lk.expedition`, `lk.forage` et **`lk.routines` en dernier** (elle met l'horloge à 23 h puis à l'aube ; les quatre précédentes la mettent à 6 h 59 ou 9 h hors de leur fenêtre). |
| `mp-ambient` | serveur dédié, zombies vanilla, joueurs mortels | `rs.identity`, `rs.facts`, `lk.load`, `lk.zombies`, `lk.alert`, `lk.defense`. La liste ne change pas le monde : c'est le lanceur qui le fait (commande ci-dessous). |

```powershell
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --server-campaign mp --bridge auto --timeout 7200 --wait-idle 3600
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --server-campaign mp-ambient --ambient-zombies --no-godmode --timeout 3600 --wait-idle 3600
```

`mp-ambient` sans `--ambient-zombies` ni `--no-godmode` revient à une partie de la campagne `mp` (site calme, mode
dieu) : les deux options sont ce qui la distingue. Mortels, les deux joueurs immobiles de la maison de Muldraugh
peuvent mourir pendant le passage (passage du 2026-10-14 : 3 min) : un échec « attacker is dead » ou une suite
interrompue est alors un résultat de robustesse, pas une régression des suites.

Suites qui étaient « solo seulement » et passent par le client demandeur sur un serveur (étapes de
`shared/RST/RST_ViewSteps.lua`, cible `requester`, aucun demandeur en ligne : SKIP ; depuis le 2026-10-15,
`lk.equipment` et `lk.ranged` les demandent à tous les clients, `lk.speech` au demandeur puis aux autres) :

| Étape | Vérification côté client demandeur | Suites |
|---|---|---|
| `lk.weapon.state` | Arme du corps telle qu'affichée : accrochée au repos (mains vides, variable `Weapon` vide), en main pour le geste (emplacement vidé, `Weapon`, nœud vivant), retirée (`none`) | `lk.equipment` |
| `lk.weapon.count` | Début / fin : événements `OnEquipPrimary` du corps, appels de pêche évités (`Equipment.stats.skipped`), erreurs Lua (`getLuaDebuggerErrorCount`) | `lk.equipment` |
| `lk.speech.bubble` | Réplique reçue (`SpeechView.seen`), une bulle du corps avec le texte **traduit sur le client** (un serveur n'a pas les traductions du mod), dessinée dans l'écran ; nouvelle livraison refusée | `lk.speech` |
| `lk.combat.view` | Début / fin : tirs joués ici (`CombatView` : un son et un éclair par tir, aucun doublon) | `lk.ranged` |
| `map.symbols` | Icône et libellé du repère au centre de la case, second repère « present », symboles retirés à la fin | `rs.actions.map` |
| `map.known` | Blocs de 32 cases connus de la carte du client (avant / après), anneau inchangé, blocs du test effacés à la fin | `rs.actions.reveal` |
| `radio.history` | Une ligne `mark` / `reveal` du libellé sur la fréquence, aucune sur la voisine, personnage du carnet, sans coordonnée, ligne traduite | `rs.actions.map`, `rs.actions.reveal` |

Limite de `rs.actions.reveal` en MP : la carte connue du compte tenue par le serveur (`WorldMapVisitedServer`) garde
les blocs révélés (aucun oubli ciblé dans le jeu) ; seul le client les efface. Monde de test seulement.

Groupe de test (`shared/RST/RST_LKGroupFixture.lua`, `RST.LKGroup.ensure`) : `rs.carnet.lk`, `rs.carnet.lk.supply`,
`rs.groupradio`, `rs.factions.accord` et `rs.factions.incident` faisaient SKIP loin d'un groupe de la population
initiale. Sur une partie `rstest*` (solo ou serveur de test), quand aucun corps de groupe n'est chargé près du
joueur (ou, pour `rs.groupradio`, quand aucun groupe ne tient d'émetteur), un groupe « settlers » (poste émetteur au
foyer) de deux membres est créé avec son foyer sur la case du joueur, sans ameublement, joueurs cachés à sa
perception (un joueur dans son foyer serait un intrus) ; la suite attend les deux corps debout, puis retire le
groupe, ses PNJ et sa voix radio à la fin. Hors partie de test : SKIP comme avant. Le carnet du joueur est lié s'il
ne l'est pas (`hello` demandé directement, `RST.RSHelpers.character`).

`rs.factions.incident` : le coup sur un membre est simulé sur l'autorité au nom du joueur
(`LivingKnox.Bodies.onHitZombie(corps, joueur, nil, Base.BaseballBat)`, l'abonné `OnHitZombie` qu'atteint un vrai
coup), au lieu d'attendre 60 s un coup du testeur ; le vrai geste (événement levé par le jeu chez le propriétaire du
corps puis sur l'autorité) reste un contrôle manuel.

Signal Smoke est un mod requis (2026-10-15, `require=` du `mod.info`) : `rs.mission.signal`, `rs.rescue.visit`
et `rs.trade_run` échouent (FAIL, jamais SKIP) si son module est inutilisable ; l'ancienne suite
`rs.mission.nosignal` (passe « sans le mod ») est retirée.

### Reconnexion et redémarrage du serveur (E01-T17)

`--phases reconnect2,reconnect,restart` (actions dans l'ordre donné, chacune facultative) enchaîne, dans le même
passage, des étapes séparées par de vraies déconnexions et un vrai redémarrage du serveur dédié de test.
`--server-suite` / `--server-campaign` donnent alors des **bases** `B` ; chaque base a une suite `B.before` (relevé,
tag `manual`) et au moins une suite `B.after-reconnect2`, `B.after-reconnect` ou `B.after-restart` (plan calculé par
`phase_plan`, refusé avant tout lancement s'il manque une suite).

| Étape | Ce que fait le lanceur | Exécutions serveur du client 1 |
|---|---|---|
| 0 | serveur, clients, « go » comme d'habitude | `B.before` de toutes les bases |
| `reconnect2` (`--clients 2`) | le client 1 reste connecté : à la fin de l'étape précédente il ne reçoit que « go » (jamais « quit »), puis sa commande de l'étape suivante (nouveau jeton) et le mot « reload » dans son fichier de contrôle (`RST_AutoClient` relit `autoclient.txt` une fois son exécution finie, statut « ingame » du nouveau jeton, attend « go ») ; seul le client 2 quitte et rejoint comme pour `reconnect`. Si l'étape précédente contient `rst.disconnect.before`, le « quit » du client 2 attend (15 s au plus, puis continue avec un `WARNING`) la ligne serveur `run started by account 'rs_mp2'` (`RST_Server.lua`), écrite après la fin de l'étape : l'exécution `rst.disconnect.slow` demandée par le client 2 doit avoir commencé avant son départ | `B.after-reconnect2` des bases qui l'ont (même règle de nouvel instantané) |
| `reconnect` | « quit » à tous les clients (`quitToDesktop` : déconnexion réelle), serveur laissé tourner, `setaccesslevel … admin` des comptes, puis chaque client relancé sur **son** cache avec **son** compte et un nouveau jeton | `B.after-reconnect` des bases qui l'ont, puis `B.before` de nouveau pour celles qu'une étape suivante revérifie (instantané frais juste avant l'action suivante) |
| `modswap` (seule, LK02-T12) | comme `restart` (clients arrêtés puis `quit` du serveur), puis `batman_RadioSurvivorTestClothes` (`dev/`) copié dans les mods du serveur et des clients, ajouté à `Mods=` de l'ini du serveur et au `default.txt` des clients (somme de contrôle MP), même cache et même monde | les MÊMES suites qu'à l'étape 0 (pas de `.before` / `.after-*`) : `lk.appearance` écrit `lk-appearance-restart.txt` à la phase 1 et compare les vêtements à la phase 2 |
| `restart` | clients arrêtés comme ci-dessus, `quit` sur la console du serveur (sauvegarde, code 0 exigé), `--restart-pause` s, relance du **même** serveur (même cache, même monde `rstest_mp`), comptes repassés admin, clients relancés | `B.after-restart` |

- Mort réelle d'un client (suite `rs.death`) : le pilote rejoue « Respawn » et la création, et écrit des lignes
  d'état dont le détail commence par `respawn: ` ; à chaque ligne `respawn: new character …`, le lanceur renvoie
  `godmodeplayer <compte> -true` sur la console du serveur (nouveau personnage mortel ; sauf `--no-godmode`). Un état
  « load » écrit après une reprise est cliqué comme à la première connexion.
- Personnage existant : `ConnectToServer:OnConnected` saute la création et passe directement au chargement ; le
  pilote (`RST_AutoClient.lua`) écrit alors « load » à `OnConnected` (`checkSavePlayerExists()`), le lanceur clique
  l'écran de chargement comme à la première connexion.
- Plusieurs exécutions serveur dans une étape : `serverSuite=a,b;c` dans `autoclient.txt` (la suivante est demandée à
  la réception du rapport de la précédente ; compteurs additionnés, `serverReport=` liste les rapports).
- Sans `--server-tags`, le filtre serveur d'un passage par étapes est `server,shared,world` sans exclusion (les noms
  sont exacts ; `client` reste toujours exclu par le serveur).
- Fichiers : ceux de chaque étape sont archivés `p<étape>-*.txt` dans le dossier de tests de chaque cache
  (`console.txt`, sortie du processus, `autoclient-result.txt` ; `server-console.txt` et sortie du serveur avant la
  relance), puis copiés avec les rapports dans `runs/<date>-mp-<jeton>/`. Code de sortie : le pire des étapes ; un
  échec d'infrastructure (code 2 : client qui ne quitte pas, serveur tué au lieu de s'arrêter) arrête la suite.
- Le délai `--timeout` couvre tout le passage (compter 2 à 3 minutes par reconnexion ou redémarrage).

Campagne `mp-persist` (`RST_Campaign.lua`, liste de bases, jamais jouée par `RST.campaign` ni par un `RST.server`
simple) :

| Base | Tâche | Étapes |
|---|---|---|
| `rs.identity` | E00-T01 : même identité, notes et engagements après reconnexion et redémarrage | `before`, `after-reconnect`, `after-restart` (§ 11) |
| `lk.homes` | LK08-T04 : aucun second aménagement après redémarrage | `lk.homes.before` (groupe « settlers » au foyer sur la case du demandeur, dans la maison du point d'apparition, aménagé, relevé `lk-homes-persist.txt` par type d'objet marqué), `lk.homes.after-restart` (même groupe et marque « done » dans le registre, un contrôle ne pose rien, mêmes objets marqués par type ; puis groupe et aménagement retirés) |
| `lk.leave` | E10-T04 : groupe `loners` et départ conservés après redémarrage | `before` (`RST_LKLeavePersist.lua` : groupe « settlers » à deux membres au foyer du demandeur, corps matérialisés, départ de m-2 par `RS_LivingKnox.leave`, relevé `leave-persist.txt`), `after-restart` (depuis le registre relu : groupe « loners » d'un membre vivant lié au même PNJ, ancien groupe sans m-2 et chef m-1, même départ sur l'ancienne composition refusé, jamais tiré par la population ; puis groupes, corps et consignes retirés) |
| `rs.radiotab`, `rst.disconnect`, `rs.reputation` | E06-T05, E01-T05, E04-T14 | voir leurs fichiers de suite ; `rst.disconnect` : le client 2 lance sa propre exécution à la fin de l'étape 0 et quitte (`reconnect2`) pendant qu'elle tourne (attente de la ligne serveur ci-dessus) |
| `rs.mission.recover` | E11-T06 : un seul sac après redémarrage | `before` (`RS_MissionRecoverPersist.lua` : fiche de cache `Caches.attach` sur la case du demandeur, posée par `Caches.place` ; le magasin du test écrit la fiche dans `recover-persist.txt` à chaque sauvegarde, à la place de l'état privé), `after-restart` (un seul sac marqué dans les bornes, même identifiant d'objet, aucune nouvelle pose, arrêt simulé entre « placing » et « placed » : le sac sauvegardé est adopté ; puis sac retiré) |
| `rs.rescue.missed` | E12-T05 : aucun doublon de zombies ni de cahier après un vrai redémarrage | `before` (`RS_RescuePersist.lua` : secours de l'équipe du demandeur dans un magasin de travail, sur le bâtiment où il se tient, issue « missed », scène posée : un zombie (joueur réanimé) par survivant, cahier dans l'inventaire du demandeur ; magasin entier dans `rescue-persist.txt`, zombies laissés au monde), `after-restart` (magasin remis, zombies marqués revenus avec leur morceau, attendus 60 s : exactement un par survivant, un seul cahier, porté par le demandeur, aucune pose au sondage, adoption après un arrêt simulé ; puis zombies et cadavres retirés) |
| `lk.walls` | LK14-T04 : mur conservé après reconnexion et redémarrage | variante courte de `lk.walls` (`RST_LKWallsPersist.lua`) : `before` (groupe « settlers » au foyer du demandeur, sans aménagement ; le premier chantier de mur libre du plan reçoit un `WoodenWallLvl1` par `Fortify.placeStructure`, sans bâtisseur ; relevé `walls-persist.txt` : chantier, santé, poteaux d'angle ; relancée alors que groupe et mur existent : gardés, relevé réécrit), `after-reconnect` et `after-restart` (un mur, aucun cadre, même santé, mêmes poteaux, chantier compté comme bâti, mur vu des autres clients par `RST.PeerChecks.checkSquares` ; `after-restart` retire mur, poteaux ajoutés et groupe) |
| `lk.rejoin` | LK03-T01 : reconnexion de l'exécutant sans consigne doublée ni perdue | `RST_LKRejoin.lua`, deux clients : `before` (demandeur envoyé 100 cases au nord, hors de la portée de candidat propriétaire et dans le rayon de retrait de 120 ; un PNJ à côté du client 2 lui appartient, consigne « move » de 45 cases vers l'est, fin de l'étape au premier rapport accepté du client 2 ; état gardé dans le Lua du serveur), action `reconnect2`, `after-reconnect2` (client 2 revenu avec un nouvel objet joueur, trajet « arrived » avec le MÊME numéro de consigne, au moins une reprise par un exécutant, aucun rapport suspect refusé, corps encore sur la case visée 5 s plus tard ; SKIP si le trajet a fini avant le départ du client 2 ; puis PNJ oublié et demandeur ramené). Dernière base de la liste : son `before` éloigne le demandeur |

```powershell
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --phases reconnect2,reconnect,restart --server-campaign mp-persist --bridge off --timeout 5400 --wait-idle 3600
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --phases reconnect2 --server-suite lk.rejoin --bridge off --timeout 2400 --wait-idle 3600
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --phases modswap --server-suite lk.appearance --bridge off --timeout 2400 --wait-idle 3600
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --phases reconnect,restart --server-suite lk.walls --bridge off --timeout 2400 --wait-idle 3600
python RadioSurvivor/tools/autoclient/autoclient.py --mp --phases restart --server-suite lk.leave,rs.mission.recover,rs.rescue.missed --bridge off --timeout 2400 --wait-idle 3600
python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --phases reconnect,restart --server-suite rs.identity --bridge off --timeout 2400 --wait-idle 3600
python RadioSurvivor/tools/autoclient/autoclient.py --mp --phases restart --server-suite lk.homes --bridge off --timeout 2400 --wait-idle 3600
```

Chrono des missions de `rs.identity.after-restart` : avec une mission engagée active dans le relevé, le test exige un
arrêt de plus de 2 minutes (`RESTART_MARGIN_MS`) : ajouter `--restart-pause 180`. Sans mission (cas de `mp-persist`),
ce test est `SKIP`.

`mp-persist` n'utilise pas `--restart-pause` : `rs.identity` y reste sans mission (chrono `SKIP`).

Instantanés : `RST_Persist.lua` (`RST.Persist.write/read/consume`, octets `RS_Codec` en hexadécimal avec somme de
contrôle, dans `Zomboid/Lua/batman_RadioSurvivor/tests/<nom>` du serveur, consommé par l'étape `after-restart`).
Quand le test travaille sur un état en mémoire (magasin de travail des secours, fiche de cache), l'instantané tient
lieu de l'état privé du carnet (`RS_State`), dont la persistance elle-même est prouvée par `rs.identity` ; le vrai
redémarrage prouve le monde (sacs, zombies réanimés, murs) et le registre des groupes Living Knox. `lk.rejoin` garde
son état dans le Lua du serveur (action `reconnect2` seulement : un redémarrage le perd).
Bancs : `tests/test_persist_suites.py` (listage, instantanés, plan de `mp-persist`, `rs.mission.recover.*` et
`rs.rescue.missed.*` joués sur les doublures de `test_mission_recover.py` et `test_rescue_lost.py`, défauts injectés :
second sac, cahier perdu) ; `tests/test_autoclient.py` (`Reconnect2Tests` : plan, orchestration, « reload » du pilote).

Contrôle « à automatiser (E01-T17) » sans suite : déconnexion pendant un troc (LK11-T08). `Trade.apply` déplace tout
dans le même appel Lua, à la réception de la proposition : une déconnexion ne tombe jamais « au milieu » ; l'essai utile
(proposition envoyée par le client 2 puis départ immédiat) demande une étape client qui propose et quitte, hors du
lanceur actuel.

## 7. Bancs hors jeu

Depuis `%USERPROFILE%\Zomboid\Workshop` (`lupa` requis pour les bancs Lua 5.1) :

| Commande | Ce qu'elle vérifie |
|---|---|
| `python RadioSurvivor/tests/test_rst.py` | Le vrai `RST.lua` et les lanceurs dans `lupa` (`next` retiré, horloge simulée), plus l'installateur. |
| `python RadioSurvivor/tests/test_rs_suites.py` | Les suites `rs.env`, `rs.codec`, `rs.missions` sur les vrais modules du mod, API Java simulée. |
| `python RadioSurvivor/tests/test_kahlua.py` | Le moteur et des suites dans la **VM Kahlua** de `projectzomboid.jar`, ticks pilotés depuis Java. |
| `python RadioSurvivor/tests/test_protocol.py` | Le Lua du mod et le pont `--offline` (solo, serveur + deux clients). |
| `python RadioSurvivor/tests/test_personas_server.py` | Les fiches de voix côté serveur (`RS_Personas.lua`, `RadioSurvivor_Server.lua`) : installation, migration, relecture à chaud, conflits ; la suite `rs.personas` sur le vrai moteur RST. |
| `python RadioSurvivor/tests/test_radio_module.py` | Le module « Émettre » de la fenêtre radio (`RS_RadioTalk`, `RS_RadioModule`) sur une interface vanilla simulée : visibilité selon l'état de la radio, refus des radios posées et autoradios, envoi commun avec le menu, deux dernières lignes par fréquence, focus clavier, manette. |
| `python RadioSurvivor/tests/test_notes.py` | Les notes de fréquences (`RS_Notes`, `RS_NotesServer`, `RS_NotesReader`) : fréquence écrite par l'autorité, client MP sans fréquence, texte FR/EN, butin selon `NoteRarity`, scripts, traductions et listes vanilla citées. |
| `python RadioSurvivor/tests/test_carnet.py` | Le carnet avec le pont, dossiers d'échange temporaires ; les suites `rs.identity*` sur le serveur simulé (reconnexion, redémarrage, mort, et la détection de leurs régressions). |
| `python RadioSurvivor/tests/test_rescue.py` | Le choix du bâtiment de secours (`RS_Rescue`, E12-T01) sur une métagrille simulée : bâtiment habitable, loin des bases, aucune lecture de case pendant le choix, essais bornés, graine, indices sans chiffres ; la suite `rs.rescue.pick` sur le vrai moteur RST ([rescue.md](rescue.md)). |
| `python RadioSurvivor/tests/test_lk_sites.py` | Le choix du site d'un foyer de groupe (`LK_Sites`, LK08-T03) sur une métagrille simulée : bâtiment admis pour colons et neutres, clairière en forêt connue pour les pillards ou repli sur un bâtiment isolé, loin des bases et des autres foyers, bâtiment exploré écarté, aucune lecture de case, essais bornés, graine ; la suite `lk.sites` sur le vrai moteur RST ([conception/sites.md](conception/sites.md)). |
| `python RadioSurvivor/tests/test_lk_materialize.py` | La matérialisation des groupes à l'approche d'un joueur (`LK_Materialize`, LK09-T03) : membres présents au foyer seulement, santé tirée de la blessure abstraite, allers-retours sans doublon ni perte, aucun mort revenu, hystérésis avec le retrait, bornes, place dans le bâtiment ou le camp ; la suite `lk.materialize` sur les doublures ([conception/corps-registre.md](conception/corps-registre.md), « Matérialisation »). |
| `python RadioSurvivor/tools/check_case.py` | La casse de tous les chemins des deux mods contre le dossier `media` vanilla (serveur Linux, § 10). |

`test_kahlua.py` compile `tests/kahlua/KRun.java` avec ECJ (le JRE du jeu n'a pas de `javac`) : fournir
`RS_ECJ_JAR` ou `tests/kahlua/ecj.jar`, jamais versionné (Maven Central
`org/eclipse/jdt/ecj/3.40.0/ecj-3.40.0.jar`). Le jeu est cherché dans `RS_PZ_DIR` ou `PZ_DIR`, sinon
dans la bibliothèque Steam `PZ_STEAM_LIBRARY`, sinon dans les bibliothèques déclarées par Steam (`tools/pz_paths.py`,
règle reprise par les bancs, les outils, `autoclient.py` et `run_dedicated_smoke.ps1`). Sans ces prérequis, les tests
sont sautés.

Aucun banc hors jeu ne prouve l'API Java réelle ni le chargement des mods : le serveur dédié de test et le jeu
restent nécessaires.

## 8. Écrire une suite

Un fichier par suite dans `dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/`. Le jeu exécute les
fichiers `shared` avant `client` et `server` ; chaque fichier fait `require "RST/RST"`. Redéclarer une suite
(rechargement) la remplace.

```lua
require "RST/RST"

RST.suite("rs.exemple", { tags = { "shared" } }, function(s)
    s.before(function(t) t.donnees = {} end)       -- avant CHAQUE test (t est propre à chaque test)
    s.after(function(t) end)                        -- après chaque test, toujours appelé

    s.test("addition", function(t)
        t:eq(4, 2 + 2)
        t:ok(true, "message si faux")
    end)

    s.test("attend un état, puis vérifie", function(t)
        local debut = RST.now()
        t:waitUntil(function() return RST.now() - debut >= 500 end, 5000, function(t2)
            t2:ok(true)
            t2:sleep(200, function(t3) t3:eq(1, 1) end)   -- étape suivante, 200 ms plus tard
        end, "attente trop longue")
    end)

    s.skip("plus tard", "raison")
end)
```

- **Tags** : `shared` (client et serveur), `server` (serveur seulement par défaut), `client` (jamais sur le
  serveur), `world` (modifie le monde, partie `rstest*`), `selfcheck` et `manual` (à la demande seulement).
- **Assertions** : `t:ok(v, msg)`, `t:eq(attendu, obtenu, msg)` et `t:ne` (comparaison profonde des tables),
  `t:near(attendu, obtenu, eps, msg)`, `t:fails(fn, motif, msg)`, `t:skip(raison)`. Une assertion qui échoue arrête
  l'étape en cours.
- **Attente par étapes** (passage asynchrone seulement, `RST.run`/`RST.server`) : le moteur n'utilise aucune
  coroutine. Une étape qui veut attendre **enregistre l'étape suivante** puis rend la main :
  `t:waitUntil(cond, ms, function(t, valeur) ... end, msg)` (le succès compte comme une assertion ; échec
  `condition not met within N ms`), `t:waitQuiet(...)` (même chose sans assertion), `t:sleep(ms, function(t) ... end)`.
  **Une seule attente par étape** : toute assertion ou seconde attente après l'appel, dans la même étape, est une
  `ERROR`. Le code écrit après l'appel d'attente s'exécute tout de suite, **avant** l'attente : tout ce qui en
  dépend va dans la fonction de suite. Ne pas attendre dans `t:fails`.
- **Nettoyage** : `t:defer(fn, libellé)` exécute `fn(t)` après le test et ses `after`, en ordre inverse, quoi qu'il
  arrive (échec, erreur, délai, annulation).
- **Délais** : 30 s par test, 120 s par suite par défaut ; `{ timeoutMs = ... }` sur un test,
  `{ testTimeoutMs = ..., timeoutMs = ... }` sur une suite.
- **Fixtures** : `require "RST/RST_Fixtures"`, puis `RST.Fixtures.giveItem(t, nil, "Base.Pencil")`, etc. (en-tête de
  `RST_Fixtures.lua`), dans des suites `world`.
- **Pièges Kahlua** : aucun littéral non ASCII dans le Lua (le lexeur le remplace par U+FFFD : écrire les octets
  UTF-8 en échappements `"\195\169"`) ; pas de `next`, pas de `goto`, pas d'opérateurs binaires, pas de coroutines,
  pas de `string.format("%q")` ni de `debug.traceback`. Messages de console en anglais.
- Ajouter la suite aux bancs hors jeu quand c'est possible (`test_rs_suites.py`, `test_kahlua.py`).

## 9. Limites connues

- **Pause solo** : en pause, `OnTick` n'est plus appelé et le passage client s'arrête, alors que l'horloge continue :
  ne pas mettre en pause pendant un passage (une attente mesurée échoue, un délai peut expirer).
- **Horodatage UTC** des fichiers de rapport et de l'en-tête.
- **Bruit dans `console.txt`** : chaque `error()`, même rattrapé par `pcall` (assertion en échec, `t:fails`), écrit
  une ligne `ERROR: General ... Exception thrown`. Ce n'est pas une panne ; se fier au rapport RST.
- **Retour au menu pendant un passage** : le passage tient en mémoire dans l'état Lua de la partie ; il est perdu,
  sans rapport, et les `t:defer` restants ne s'exécutent pas (déduit du code, non vérifié en jeu). Lancer
  `RST.cancel()` avant de quitter ; sinon, sur une partie `rstest*`, vérifier l'inventaire et la position.
- Un passage client est refusé si un autre est en cours ; `RST.cancel()` l'arrête.
- Les suites `world` ne s'exécutent jamais dans un client MP (nom de sauvegarde non `rstest*`).

## 10. Serveur Linux (protocole, non exécuté)

Un serveur dédié Linux distingue les majuscules des minuscules ; Windows masque ces erreurs. Ce protocole n'a **pas**
été exécuté (LK13-T05). Il vise un serveur **de test** Linux ; le moment et la manière d'essayer sur le serveur réel
de l'utilisateur se décident avec lui : rien ici ne s'applique d'office à ce serveur.

### Avant la séance : contrôle statique

Depuis `%USERPROFILE%\Zomboid\Workshop` : `python RadioSurvivor/tools/check_case.py` doit rendre
`RESULT: PASS` (aussi l'étape `case` de `tests/run_all.py`). Il compare, à la casse exacte, les dossiers du mod aux
dossiers vanilla (`media`, `lua/client|shared|server`, `AnimSets`, `actiongroups`, `textures`, `Translate/<LANG>`…),
vérifie que chaque dossier d'état d'animation existe en vanilla, les `require`, les chemins `media/...` cités par le
Lua et les scripts, `poster`/`icon` de `mod.info`, les fichiers de traduction, les clés de `sandbox-options.txt`, et
cherche les collisions (deux fichiers qui ne diffèrent que par la casse, fichier au chemin d'un fichier vanilla). Il
ne prouve pas la résolution par le moteur (chemins calculés en Java, `x_extends`) : d'où la séance.

### Installer (serveur de test)

1. Serveur dédié Project Zomboid **42.21** (SteamCMD, application 380870) sur une machine Linux de test ; noter la
   version affichée au démarrage du journal (`42.21.x`), le chemin du serveur et celui de `~/Zomboid`.
2. Mods, avec leur casse intacte (copie depuis le dépôt Git ou une archive, jamais par un outil qui renomme) :
   - `batman_RadioSurvivor` et `batman_CharacterReputation` **par le Workshop**, comme sur le serveur de
     l'utilisateur : `WorkshopItems=` dans l'`.ini`, donc dans `<serveur>/steamapps/workshop/content/108600/`,
     **dans** le dossier du jeu (cas où un chemin relatif peut passer en minuscules, base `file-path-case.md`). Si
     la version à essayer n'est pas encore publiée, une copie sous `~/Zomboid/mods/` est acceptable, mais ce cas
     n'est alors pas couvert : le noter dans le relevé ;
   - `batman_RadioSurvivorTests` (jamais publié) copié dans `~/Zomboid/mods/batman_RadioSurvivorTests`.
   Vérifier la casse sur place : `find <dossier du mod> -path '*media*' -type d | sort` doit montrer `media`,
   `AnimSets/zombie/idle`, `pathfind`, `walktoward`, `walktoward-network`, `lua/shared/Translate/EN`, `FR`…
3. Configuration `rstest_linux.ini`, sur le modèle de `tests/run_dedicated_smoke.ps1` :
   `Mods=\batman_CharacterReputation;\batman_RadioSurvivor;\batman_RadioSurvivorTests` (plus les IDs Workshop
   dans `WorkshopItems=`), `PauseEmpty=true`, sandbox par défaut. Le nom du serveur doit commencer par `rstest`
   (suites `world`, § 5) : lancer avec `-servername rstest_linux`. Donner au compte de test le rôle `admin`
   (capacité `DebugConsole`, § 3) ; le mode debug est exigé du client (§ 2).
4. Client Windows en `-debug`, mêmes versions des mods, connecté au serveur.

### Lancer

1. **Démarrage du serveur** : laisser charger jusqu'à `OnServerStarted`, puis se connecter.
2. **Suites radio et carnet** (console Lua du client) : `RST.server('rs')` ; attendu : rapport `OK`, hors échecs
   connus du § 4.
3. **Suites Living Knox côté serveur** : `RST.server({ suite = "lk", tags = "world" })` (`lk.anims`,
   `lk.appearance`, `lk.bodies`, `lk.equipment`, `lk.essai`, `lk.executor`, `lk.farm`, `lk.guard`,
   `lk.materialize`, `lk.milestone1`, `lk.pain`) ; noter chaque `FAIL`/`ERROR` et comparer au même passage sur un serveur Windows
   (`tests/run_dedicated_smoke.ps1` ou serveur local) : seule une différence entre les deux concerne la casse.
4. **PNJ près d'un joueur** : `LKB.spawn()` (deux cases à l'est et au sud), puis `LKB.gesture(1, "aim")`,
   `"guard"`, `"crouch"`, `"idle"` ; `LKB.moveTo(1, 9, 0, "walk")`, puis `"run"` et `"crouch"` ; `LKB.anim(1)`
   à chaque étape (état AnimSet, nœuds `lkactor_*` actifs, clips) ; `LKB.forget(1)` à la fin.
5. **Zombies ordinaires** : à côté du PNJ, observer quelques zombies ordinaires (attente, errance, marche vers le
   joueur, attaque, chute et relevé). Attendu : aucune pose de PNJ (visée, garde, accroupi) sur un zombie
   ordinaire, aucun zombie figé en T ou sans animation de marche. Avec un second client, observer aussi les
   copies distantes (`walktoward-network`).

### Relever dans les journaux

Serveur (`~/Zomboid/server-console.txt` et sortie standard) et client (`console.txt`) :

- version du jeu et liste des mods chargés (variante `42.21`, `common` lu) ;
- `AnimNode.Parse` ou `FileNotFoundException` sur un fichier `AnimSets`/`actiongroups` : **erreur de casse
  réelle** (chemin relatif mis en minuscules) ;
- `NoSuchFileException … AnimSets` ou `… actiongroups` : bruit sans effet, jamais un problème de casse (dossier
  absent dans toutes les casses, base `file-path-case.md`) ; le noter sans le compter comme échec ;
- `require("…") failed` et toute erreur Lua dans `LivingKnox/`, `RadioSurvivor/` ou `RST/` ;
- `failed to load poster`, clés de traduction brutes dans l'interface (une clé brute sur le serveur est un défaut
  connu du multijoueur, pas un problème de casse : vérifier le fichier `Translate/<LANG>` avant de conclure) ;
- options sandbox `LivingKnox` et `RadioSurvivor` présentes avec leurs libellés.

Résultat attendu : contrôle statique vert, aucune erreur de chargement ni de `require` propre au serveur Linux,
PNJ et zombies ordinaires animés normalement. Consigner le relevé (version, mode d'installation des mods, extraits
de journal) dans la preuve de LK13-T05.

## 11. Identité du carnet : reconnexion, redémarrage, mort (E03-T04)

Protocole à deux comptes pour `E00-T01` (identité gardée par le serveur) et `E00-T02` (identité retirée à la mort).
Les vérifications sont faites **par le serveur**, sur l'état réel du carnet et sans le modifier, par les suites de
`RS_Identity.lua` :

| Suite | Quand | Ce qu'elle vérifie |
|---|---|---|
| `rs.identity` | à tout moment (aussi dans `"rs"` et l'exécution automatique) | fiches bien formées ; chaque joueur en ligne lié à une identité utilisable de son compte ; aucune identité partagée ni retirée en usage ; membres des missions connus |
| `rs.identity.before` | avant chaque action manuelle | relève, pour chaque compte en ligne, l'identité, les notes, les missions engagées ou invitées et leur chrono, le monde, la session et l'heure, dans `<cache>\Lua\batman_RadioSurvivor\tests\identity-snapshot.txt` (fichier de test, pas l'état du carnet) |
| `rs.identity.after-reconnect` | après une reconnexion | même session ; même identité (ModData serveur et liaison) ; notes et engagements ; chrono écoulé pendant la déconnexion (± 5 s) |
| `rs.identity.after-restart` | après un redémarrage | nouvelle session du même monde ; même identité, notes, engagements ; chrono sans le temps d'arrêt |
| `rs.identity.after-death` | après la mort de A et son nouveau personnage | ancienne identité retirée et inutilisée ; nouvelle identité du même compte sans les anciennes missions ni notes ; B garde identité et missions |

Les étapes portent le tag `manual` (§ 3) : chacune se lance par son nom exact. Un compte du relevé hors ligne est
signalé (`note:`) et non vérifié. Sans fournisseur de PNJ (avant `E17-T03`), personne n'a de note ni de mission :
les contrôles portent sur des ensembles vides et les tests de chrono sont `SKIP`. Après un redémarrage, le chrono
consommé doit rester sous le temps de fonctionnement depuis le chargement du Lua du serveur, plus 2 minutes entre le
relevé et `quit` : un arrêt de plus de 2 minutes est donc nécessaire pour le distinguer.

### Préparer

1. Serveur dédié de test, depuis `%USERPROFILE%\Zomboid\Workshop` :
   `powershell -ExecutionPolicy Bypass -File RadioSurvivor/tests/run_dedicated_smoke.ps1 -Manual`. Noter le chemin
   `RS_SMOKE_CACHE=`. Le serveur est en `-nosteam` et n'écoute que `127.0.0.1` : les deux clients tournent sur ce PC,
   lancés en `-debug -nosteam`, le second avec un `-cachedir` distinct (deux instances sur un PC : non essayé).
2. Clients : mêmes versions de `batman_CharacterReputation`, `batman_RadioSurvivor` et `batman_RadioSurvivorTests`
   (§ 1) que le dépôt. A = `rs_smoke_admin` / `local-smoke-only` (rôle admin, donc `RST.server`) ; B = un nouveau
   compte.
3. A et B créent un personnage. Console Lua de A : `RST.server('rs.identity')` → `OK`.
4. Avec un fournisseur de PNJ seulement : A et B sélectionnent le même PNJ, A écrit une note, A accepte une mission,
   invite B, B accepte.

### Enchaînement (commandes dans la console Lua de A)

1. `RST.server('rs.identity.before')` → `OK` ; les lignes `note:` donnent l'identité de A et de B.
2. A quitte vers le menu, attend 30 s, se reconnecte (B reste connecté).
3. `RST.server('rs.identity.after-reconnect')` → `OK`.
4. `RST.server('rs.identity.before')`, puis dans les 2 minutes `quit` dans la console du serveur.
5. Serveur arrêté **au moins 3 minutes**, puis relance :
   `run_dedicated_smoke.ps1 -Manual -CacheDir <RS_SMOKE_CACHE>` ; A et B se reconnectent.
6. `RST.server('rs.identity.after-restart')` → `OK`.
7. `RST.server('rs.identity.before')`, puis A meurt en jeu (zombies, chute) : une mort décidée par le serveur, pas
   un appel Lua local du client.
8. A crée un nouveau personnage sur le même compte et attend d'être en jeu.
9. `RST.server('rs.identity.after-death')` → `OK` (le test « other accounts » exige B en ligne).
10. `RST.server('rs.identity')` → `OK`, puis `quit`.

### Relever

- Le résumé de chaque passage (console de A) et le rapport complet
  `<cache>\Lua\batman_RadioSurvivor\tests\<horodatage>-server.txt` avec ses lignes `note:` (identités avant et après,
  temps consommé, durée d'arrêt), ainsi que `identity-snapshot.txt`.
- `<cache>\server-console.txt` : version `42.21.x`, `[RS_Carnet] authoritative state ready` à chaque démarrage,
  aucune erreur Lua de `RadioSurvivor/` ou `RST/`.
- Avec un fournisseur : dans le carnet de B, la mission commune reste active après la mort de A.

Reconnexion et redémarrage sans personne : `--phases reconnect,restart --server-suite rs.identity` (§ 6 ter,
« Reconnexion et redémarrage du serveur ») joue les étapes 1 à 6 avec les deux clients automatiques (les deux se
reconnectent ; la mort de l'étape 7 reste manuelle).

Tout `OK` avec un fournisseur : `E00-T01` et `E00-T02` passent à `testé MP`. Sans fournisseur, seule l'identité
(liaison, retrait, nouvelle identité) est prouvée ; notes, engagements et chrono restent à rejouer après `E17-T03`.

## 12. Tueur d'un PNJ Living Knox (E04-T06)

Ce que l'autorité établit à la mort d'un PNJ : ligne `[LivingKnox] INFO npc lk-<n> died (generation <g>): cause
<catégorie>, killer <compte|nil>, weapon <type|nil>[, burning]` dans `console.txt` (solo) ou le journal du serveur.
Règle : fiche `docs/conception/corps-registre.md`, « Mort et tueur ».

### Automatique (par code)

Partie `rstest*`, option Living Knox `Enabled`, mod de développement actif.

- Solo : `RST.run({ suite = "rs.killer", tags = "world" })` → `OK` (5 tests, environ 30 s ; ne pas mettre en pause).
- Serveur dédié, depuis un client admin : `RST.server({ suite = "rs.killer", tags = "world" })` → `OK`.
- Relever les lignes `[RSK] measure ...` (cause, tueur, arme ; `getAttackedBy` après 6 s ; feu).

### Manuel (solo, puis client d'un serveur dédié)

Pour chaque cas : `LKB.spawn()` (PNJ à 2 cases), attendre qu'il se relève, le tuer comme indiqué, relever la ligne
`died`. Attendu :

| Cas | Attendu |
|---|---|
| Batte, coups jusqu'à la mort | `cause melee, killer <compte>, weapon Base.BaseballBat` |
| Pistolet, tir mortel | `cause firearm, killer <compte>, weapon Base.Pistol` (ou l'arme tirée) |
| Bombe artisanale lancée à ses pieds | `cause fire, killer <compte>, weapon <bombe>` |
| Cocktail Molotov, ou feu d'essence | `cause fire, killer nil, ..., burning` |
| Écrasé en voiture, joueur au volant | `cause vehicle, killer <conducteur>` |
| MP : B au volant, A passager, le PNJ écrasé | `cause vehicle, killer B` |
| Coup sans dégât (poussée), puis attendre 10 s, puis le faire tuer par le feu | `cause fire, killer nil` |

Écart à signaler : un tueur retenu là où le tableau dit `nil` (ou l'inverse), une seconde ligne `died` pour le même
PNJ, une erreur Lua de `LivingKnox/`.

## 13. Fiches des voix radio (E05-T02)

Les fiches sont dans `<cache>\Lua\batman_RadioSurvivor\personas\` de la machine qui exécute le serveur (le PC du
joueur en solo). À chaque chargement d'un monde, le mod y copie les fiches livrées absentes et remplace celles que
l'admin n'a pas modifiées par la version livrée si elle a changé (E05-T11 ; une fiche modifiée n'est jamais écrasée),
puis relit le dossier toutes les 30 s réelles. Lignes `[RadioSurvivor] personas: ...` dans `console.txt` (solo) ou
le journal du serveur.

### Automatique (par code)

Partie `rstest*`, mod de développement actif. La suite écrit sa propre fiche `rstest_probe.txt` (fréquences 999,8 et
999,6 MHz), la vide à la fin (Lua ne peut pas supprimer un fichier : le fichier vide reste, il compte comme une voix
retirée).

- Solo : `RST.run({ suite = "rs.personas", tags = { "world", "server" } })` → `OK` (5 tests, jusqu'à 35 s : la
  relecture périodique est attendue une fois). `RST.run("rs.personas")` lance 0 test : la suite porte les tags `world`
  et `server`, que les exclusions par défaut écartent (§ 3).
- Serveur dédié, depuis un client admin : `RST.server({ suite = "rs.personas", tags = { "world", "server" } })` →
  `OK` (`RST.server("rs.personas")` exclut `world` par défaut : 0 test). L'exécution automatique du serveur de
  test (§ 6) l'exclut (suite `world`).

### Réseau de voix (E05-T06)

Validation d'ensemble, solo puis MP : [validation/E05-reseau-voix.md](validation/E05-reseau-voix.md), qui renvoie aux
essais ci-dessous. Suites : `RST.server("rs.voices")` (lecture seule, 5 tests, aussi dans l'exécution automatique du
§ 6) et `RST.server({ suite = "rs.voices", tags = { "server", "world" } })` (plus `rs.voices.world`, 3 tests : phrases
simulées sur chaque voix, poste ordinaire refusé par une voix `high_tier`, fiche modifiée puis restaurée ; partie
`rstest*`, pont arrêté ou `--offline`, jeu non en pause).

### Manuel (solo, court)

1. Nouvelle partie `rstest-voix`, talkie en main, allumé, 145,0 MHz. Journal : `installed the bundled sheet`,
   `voice 'walt' loaded`, `channel of voice 'walt' created on 145.0 MHz`. Clic droit sur la radio → « Parler sur
   145.0 MHz » → Walt répond (pont lancé).
2. Sans quitter : dans `walt.txt`, `frequencies=147.0`, enregistrer. Dans les 30 s : `channel ... removed from 145.0`,
   `created on 147.0`. Sur 145,0 : la phrase part, plus de réponse (aucun message) ; régler 147,0 → Walt répond.
3. `state=silent` : la phrase part sur la radio, aucune réponse, rien dans `requests.txt`. `state=gone` : pareil,
   sans aucun message (E05-T08). Revenir à `state=active`.
4. `frequencies=147.1` (hors pas) : `ERROR: ... walt.txt refused, line N: frequency 147.1 is not on the 0.2 MHz step
   of the radios; the previous valid version stays in service` ; Walt répond toujours sur 147,0.
5. Remettre `frequencies=145.0` (ou supprimer `walt.txt` hors jeu : il est recopié au prochain chargement du monde).

Écart à signaler : une fiche de l'admin écrasée, une chaîne restée sur l'ancienne fréquence, une erreur Lua de
`RadioSurvivor/`.

### Mise à jour des fiches installées (E05-T11, solo, court)

Sur une partie solo **existante** installée avant E05-T07 (fiches à `frequencies=` fixes, aucun fichier
`personas-fingerprints.txt` dans `Lua\batman_RadioSurvivor\`), jamais retouchées à la main :

1. Charger la partie. Journal : une ligne `INFO: voice '<id>' updated to the delivered version` par fiche ; les fiches
   portent maintenant `frequency_range=` ; `personas-fingerprints.txt` existe (`RSFP1` puis une ligne par fiche) ;
   `voice '<id>' drew ...` pour chaque voix.
2. Quitter, ajouter une ligne `# essai` dans `gus.txt`, recharger : `WARNING: voice 'gus' modified by the admin,
   delivered version not applied` ; `gus.txt` garde la ligne ; aucune autre fiche touchée.
3. Supprimer `gus.txt` hors jeu, recharger : il est recopié depuis le mod (`installed the bundled sheet`).

Écart à signaler : une fiche retouchée remplacée, une fiche non retouchée restée à fréquence fixe, une erreur Lua.

### Routage par voix (E05-T03, solo, court)

Aucune voix n'est livrée en plus de Walt (E05-T04) : l'essai crée une voix jetable, à vider à la fin. Pont lancé
(`--offline` suffit : chaque voix répond « <Prénom>, hors ligne. Je reçois ... »).

1. Partie `rstest-voix`. Dans `personas\`, créer `essai.txt` :
   `format=1`, `id=essai`, `name=Essai Banc`, `frequencies=150.0`, `radio=high_tier`,
   `secret=Le code est sous la pierre.`, `budget=2`, puis `[prompt]` et une ligne de texte. Dans les 30 s :
   `voice 'essai' loaded`, `channel of voice 'essai' created on 150.0 MHz`.
2. Talkie ordinaire (`WalkieTalkie1` à 4) réglé sur 150,0 : le menu propose « Parler sur 150.0 MHz » ; la phrase
   part, **aucune réponse**, rien dans `requests.txt`.
3. Poste haut de gamme (`WalkieTalkie5`, ou `ManPackRadio` sur le dos) sur 150,0 : réponse « Essai, hors ligne... »
   sur 150,0 ; `requests.txt` portait `voice=essai`. Revenir sur 145,0 : Walt répond comme avant (« Walt, hors
   ligne... »). Dans le dossier d'échange : `history_<empreinte>.json` (Walt) et `history_<empreinte>_essai.json`,
   chacun avec ses seuls messages.
4. Sur 150,0, encore deux messages (10 s d'écart) : le premier reçoit une réponse, le second n'obtient que le silence
   (budget 2, sans message depuis E05-T08) ; Walt répond toujours sur 145,0.
5. Vider `essai.txt` (0 octet) : `voice 'essai' removed`, 150,0 ne répond plus.

Écart à signaler : une réponse de la voix d'essai sur 145,0 (ou de Walt sur 150,0), un historique qui mélange les
deux voix, une réponse à un poste ordinaire, le texte du secret entendu à la radio.

### Le serveur trie (E05-T08, solo, court)

Le client ne connaît aucune fréquence de voix : le menu « Parler sur X MHz » affiche la fréquence où la radio est
réglée, quelle qu'elle soit, et le serveur décide si une voix y répond. Pont lancé (`--offline` suffit).

1. Nouvelle partie `rstest-voix`. Journal : `voice 'walt' drew <X> MHz` (fréquence tirée de la partie). Talkie en
   main, allumé, micro ouvert, réglé sur X. Clic droit → « Parler sur X MHz » → la phrase part, Walt répond sur X.
2. Régler une fréquence sans voix (par exemple 160,0) → « Parler sur 160.0 MHz » → la phrase part (bulle), puis
   **rien** : aucun message, aucune réponse ; `requests.txt` ne contient pas la phrase.
3. Reparler aussitôt : option grisée « Vous parlez sans arrêt… » pendant 11 s (délai du serveur `PlayerCooldown`,
   10 s par défaut, plus 1 s de marge : même écart avec ou sans voix sur la fréquence) ; ensuite elle est de nouveau
   disponible. Jamais de refus rouge « Laissez-lui le temps de répondre. » en usage normal (correctif du 2026-10-09).
4. Panneau « Général » de la radio réglée sur X : « Chaîne inconnue » (aucun nom de chaîne).

Écart à signaler : une réponse ou un message sur une fréquence sans voix, un menu qui propose une autre fréquence que
celle de la radio, un nom de chaîne affiché sur X, une erreur Lua.

### Appels spontanés (E05-T05, solo, court)

Chaque voix active appelle d'elle-même, à l'heure pleine, pendant ses heures d'écoute (Walt une chance sur 3, Darlene
et Cody sur 6, Gus sur 8). L'essai force Walt à appeler à chaque heure. Pont lancé (`--offline` suffit : l'appel dit
« Walt, appel général hors ligne. À vous. »).

1. Partie `rstest-voix` (option sandbox « Appels spontanés » cochée, valeur par défaut). Journal : `voice 'walt' drew
   <X> MHz`. Dans `personas\walt.txt` : `call_one_in=1`, enregistrer (relecture dans les 30 s). Talkie en main,
   allumé, réglé sur X.
2. Avancer le temps jusqu'à l'heure pleine suivante : parasites, « Walt, appel général hors ligne. À vous. »,
   parasites, sur X. Pont : `general call of voice walt`.
3. Arrêter le pont. Heure pleine suivante : environ 30 s réelles plus tard, le texte fixe « Il y a quelqu'un ? Ici
   Walt, j'ai réussi à sortir de Knox. J'écoute sur X. À vous. » (en anglais si le jeu est en anglais).
4. Dans `walt.txt` : `listen=` avec une plage qui ne contient pas l'heure du jeu (par exemple `03:00-04:00` en
   journée) : deux heures pleines sans aucun appel.
5. Supprimer `walt.txt` hors jeu (recopié au prochain chargement du monde).

Écart à signaler : un appel hors des heures d'écoute, un appel d'une voix `silent` (Whitaker) ou du Night Owl, une clé
`IGUI_RadioSurvivor_Call…` lue telle quelle à la radio, une fréquence citée par le texte du pont, une erreur Lua.

### Notes de fréquences (E05-T09, solo, court)

Chaque voix qui parle (Walt, Darlene, Cody, Gus, Night Owl ; pas Whitaker) a une note lisible dans le butin, avec la
fréquence tirée pour la partie. Détails : [notes-frequences.md](notes-frequences.md). Jeu lancé en mode debug, langue
française.

1. Nouvelle partie `rstest-notes` (option sandbox « Notes de fréquences dans le butin » : Normales). Journal :
   `voice '<id>' drew <X> MHz` pour chaque voix, puis `[RadioSurvivor] notes: 20 loot entries added, rarity factor 1`.
2. `RST.run({ suite = "rs.notes", tags = { "world", "server" } })` → `OK` (4 tests ; les notes de la suite
   indiquent la fréquence de chaque voix). `RST.run("rs.notes")` lance 0 test (tags `world` et `server` exclus par
   défaut, § 3).
3. Console Lua : `for _, t in ipairs({"NoteWalt","NoteDarlene","NoteCody","NoteGus","NoteNightOwl"}) do
   getPlayer():getInventory():AddItem("RadioSurvivor." .. t) end`. Cinq objets : « Page de journal radio », « Fiche de
   consignes au patient », « Avis de recherche de la Garde nationale », « Note griffonnée », « Prospectus du Night
   Owl », chacun avec son icône (aucun « ? »).
4. Clic droit sur chacun → « Inspecter » : la fenêtre des documents s'ouvre en une seconde environ, texte en
   français, fréquence = celle du journal pour cette voix (Night Owl : sa première fréquence, dans 88,0-107,8),
   horaires de la voix (Walt : à toute heure). Bouton du bas : la transcription, même fréquence. Aucune ligne
   ne déborde de la page ; aucun avertissement `Missing arguments` ni `RICH TEXT ERROR` dans `console.txt`.
5. Régler un talkie sur la fréquence lue sur la note de Walt, « Parler sur … » : Walt répond (pont lancé).
6. Sauvegarder, quitter, passer le jeu en anglais (Options → Langue, redémarrage), recharger : relire deux notes de
   l'étape 3 → texte en anglais, **même fréquence** (le texte est composé à la lecture).
7. Fouille réelle : nouvelle partie `rstest-fouille` avec « Fréquentes », fouiller une ville (maisons : bureaux de
   chambre, tables de salon, garages ; commissariat ; pharmacie ou cabinet médical ; supérette ou station-service) :
   relever les notes trouvées, leur conteneur et la durée de jeu. Puis une partie en « Normales » : au moins une note
   en quelques heures de jeu ; Gus (magasins de pêche, cartons de pêche) peut manquer.
8. Option « Aucune » sur une partie neuve : `NoteRarity = none, no note added to the loot`, aucune note trouvée.

Écart à signaler : une note sans fréquence (`???.?`) alors que la voix est active, une fréquence différente de celle du
journal, une clé `Print_Media_…` ou `%1` affichée, un texte qui reste en français après le passage en anglais, une
icône « ? », une ligne qui sort de la page, une erreur Lua de `RadioSurvivor/`.

### Module « Émettre » de la fenêtre radio (E06-T02, solo, court)

La fenêtre radio vanilla gagne une section « Émettre » en bas : deux dernières lignes entendues sur la fréquence,
champ de saisie, boutons « Émettre » et « Carnet ». Le menu clic droit « Parler sur … » reste en place jusqu'à la
validation de cette section (décision E06-T01). Jeu en mode debug, langue française, pont lancé (`--offline`
suffit), partie `rstest-voix` (fréquence de Walt X lue dans le journal : `voice 'walt' drew <X> MHz`).

1. `RST.run("rs.radiomodule")` → `OK` (5 tests), puis
   `RST.run({ suite = "rs.radiomodule", tags = { "client", "world" } })` → `OK` (6 tests ; le sixième ouvre la vraie
   fenêtre avec un talkie en main et la referme).
2. Talkie en main, réglé sur X, allumé, micro ouvert : la fenêtre radio montre « Émettre » en dernier ; « Rien
   entendu sur X MHz pour le moment. », champ « Parler sur X MHz ». Couper le micro : la section disparaît ;
   le rouvrir : elle revient. Éteindre la radio : elle disparaît.
3. Cliquer dans le champ, taper « Walt, tu m'entends ? », Entrée : la phrase est dite (bulle), le champ se vide, les
   touches de déplacement répondent aussitôt (focus rendu). Pendant l'attente : champ et bouton grisés, motif
   « En attente d'une réponse... » ; puis la réponse de Walt apparaît dans les deux lignes ; jusqu'à 11 s après
   l'envoi : champ grisé, « Vous parlez sans arrêt... » ; jamais de refus rouge « Laissez-lui le temps de
   répondre. ».
4. Taper quelques lettres sans valider, puis Échap : les touches du jeu reviennent. Retaper, fermer la fenêtre par
   sa croix : les touches reviennent sans clic.
5. « Carnet » : le carnet s'ouvre (ou passe au premier plan s'il l'était déjà).
6. Radio portable réceptrice (`Base.RadioRed`) en main : aucune section « Émettre ». Radio militaire
   (`Base.ManPackRadio`) **sur le dos** : la section s'affiche et l'envoi part. Talkie **accroché à la ceinture** :
   clic droit → « Options de l'appareil » (Belt Walkie-Talkie), la fenêtre s'ouvre, la radio reste allumée, la
   section s'affiche mais la saisie est grisée avec « Prenez le talkie en main (ou portez la radio sur le dos) : il
   n'émet pas depuis la ceinture ni l'inventaire. » (règle commune, décision 4) ; une réponse de Walt reçue sur X
   s'affiche quand même par le talkie de la ceinture et dans les deux lignes.
7. Radio de radioamateur (`Base.HamRadio1`) posée au sol et allumée, micro ouvert : la section s'affiche ; l'envoi
   part depuis E06-T03 (protocole ci-dessous). Une autoradio ordinaire n'a pas de section.
8. Manette (si disponible) : RB jusqu'à la section, A ouvre le clavier à l'écran ; sa touche Entrée émet (à
   vérifier) ou Y émet ; X ouvre le carnet ; haut et bas passent aux autres sections.

Écart à signaler : une section sur une radio réceptrice ou micro coupé, une section absente sur un talkie émetteur
allumé, une clé `IGUI_RadioSurvivor_…` affichée telle quelle, des touches du jeu bloquées après envoi, Échap ou
fermeture, un texte qui déborde de la fenêtre, une erreur Lua de `RadioSurvivor/`.

### Radio posée et autoradio (E06-T03)

Le serveur retrouve la radio désignée (case et index pour une radio posée, véhicule et pièce pour une autoradio) et
contrôle la portée du micro (distance entière < 5 cases, même étage), la place dans le véhicule, l'allumage et le
canal qu'il connaît. Hors jeu : `tests/test_personas_server.py` (`WorldRadioServerTests`), `tests/test_radio_module.py`,
`tests/test_protocol.py` (`scenario_world_radios_mp`).

**Solo, court** (pont `--offline`, partie `rstest-voix`, fréquence de Walt X) :

1. `Base.HamRadio1` (avec pile) posée au sol, allumée, réglée sur X, micro ouvert ; joueur à 2 cases. Fenêtre radio,
   section « Émettre », « Walt, tu m'entends ? », Entrée : la phrase est dite, Walt répond sur X (deux lignes de la
   section).
2. Reculer à 6 cases, fenêtre ouverte (elle reste ouverte jusqu'à 10 cases, `ISRadioWindow.lua:125`) : Entrée →
   « Approchez-vous du micro de la radio. », rien n'est dit.
3. Monter d'un étage au-dessus de la radio (escalier proche) : même refus.
4. Véhicule de police (autoradio `Radio_HAM`), moteur ou batterie allumés, autoradio sur X : conducteur, « Émettre »
   → Walt répond. Passer sur un siège passager (attendre 10 s) : l'envoi part et Walt répond.
5. Fenêtre de l'autoradio ouverte, sortir du véhicule (la fenêtre reste ouverte à moins de 10 cases) : Entrée →
   « Montez dans le véhicule pour utiliser sa radio. »

**Multijoueur** (serveur dédié de test, deux clients A et B, séance finale) :

1. A pose une `HamRadio1` allumée sur X ; B à 2 cases émet par la section : Walt répond, A et B entendent la réponse
   (radio posée partagée, sans propriétaire : ⚠ comportement vanilla).
2. B à 8 cases : refus « Approchez-vous du micro de la radio. » chez B seulement, rien au pont.
3. A conduit un véhicule de police, B passager : B émet par l'autoradio, Walt répond. B descend : refus
   « Montez dans le véhicule… ».
4. A change la fréquence de la radio posée puis B émet aussitôt : réponse sur la nouvelle fréquence, ou silence si le
   réglage n'est pas encore arrivé au serveur (⚠ attendu, la phrase part sans réponse).
5. Vérifier que l'autre joueur entend la phrase de B sur la radio (relais vanilla du chat « dire » par les radios
   proches de `VoiceManager`, non confirmé).

Écart à signaler : une réponse à un joueur hors de portée ou hors du véhicule, un refus `NoRadio` sur une HAM posée à
portée, une erreur Lua de `RadioSurvivor_Server.lua`.

### Onglet Radio du carnet (E06-T04, solo, court)

Historique par fréquence tenu par l'autorité dans l'état privé du carnet (`docs/protocole-carnet-v2.md`, « Historique
radio du carnet »). Hors jeu : `tests/test_radio_history.py` (bornes, types, persistance, harnais MP : aucun
historique d'un autre joueur, aucune fréquence non réglée ; `SoloScenarioTests` : partie solo sans fournisseur de
PNJ, carnet jamais ouvert puis ouvert, rechargement), `tests/test_kahlua.py` (`KR-HISTORY`),
`tests/test_belt_radio.py` (talkie à la ceinture avec la vraie bibliothèque Belt Walkie-Talkie : réception,
couleur des voix, radio rangée sourde, émission refusée côté client et serveur).

Correctif du 2026-10-09 (essai `rstest-solo` : onglet vide, aucun voyant) : le premier `hello` d'un nouveau
personnage partait avec une table vide, reçue `nil` par le serveur et ignorée ; aucun personnage du carnet n'était
créé (`characters` vide dans `Zomboid\Lua\batman_RadioSurvivor\state-…-0.txt`), donc aucun historique. Sur une partie
déjà jouée avant le correctif, le personnage est créé au premier chargement : l'historique commence alors (les
échanges antérieurs ne sont pas rattrapés).

**Solo, court, nominal d'abord** (pont `--offline`, talkie émetteur en main, réglé sur la fréquence X de Walt) :

1. Carnet fermé. Section « Émettre » : « Walt, tu m'entends ? », Entrée. Walt répond : un point orange apparaît sur
   le bouton **Carnet** de la barre latérale.
2. Ouvrir le carnet, onglet **Radio** : X en tête de liste (« Dernier : MM/JJ hh:mm ») ; à droite, la phrase
   (« moi — », bleu encre) puis la réponse (« Réponse — », noir), dans l'ordre, la plus récente visible en bas
   (présentation refondue par E06-T06). Le point
   orange s'éteint.
3. Réduire le carnet (bouton de réduction de la barre de titre), refaire un envoi : le point orange s'allume sur le bouton latéral et dans la
   barre de titre du carnet réduit ; le rouvrir sur l'onglet Radio l'éteint.
4. Régler le talkie sur une autre fréquence Y (fenêtre radio), revenir à l'onglet Radio, sélectionner X, bouton
   **Régler ma radio** : bruit de réglage, la fenêtre radio montre X. Recliquer : « Déjà sur X MHz. »
5. Ranger le talkie dans le sac : **Régler ma radio** → « Tenez une radio en main ou portez-la sur le dos pour la
   régler. » ; talkie en main éteint : « La radio est éteinte. »
6. Attendre un appel spontané de Walt (ou d'une autre voix réglée) : ligne « Entendu » (gris) sur sa fréquence.
7. Sauvegarder, quitter, recharger : l'onglet Radio retrouve la conversation.

**Talkie à la ceinture (solo, court, après le nominal ci-dessus)** — mod requis Belt Walkie-Talkie
(`batman_BeltRadio`, § 1) : un talkie accroché entend les chaînes et affiche la ligne en bulle radio au-dessus du
joueur, dans la couleur de la ligne (voix : orange clair `Const.LINE_COLOR`) ; il **n'émet pas** (décision 4) ; une
radio rangée n'entend rien en solo (décision 3). Radio Survivor s'inscrit par `RS_BeltRadio.lua` (journal : aucune
ligne `[RadioSurvivor] WARN: Belt Walkie-Talkie`).

0. Affichage d'un appel spontané (prioritaire) : dans `personas\walt.txt`, `call_one_in=1`, enregistrer (relecture
   dans les 30 s), pendant les heures d'écoute de Walt. Talkie allumé sur X accroché à la ceinture, mains vides, jeu à
   vitesse normale. À l'heure de jeu suivante : l'appel de Walt s'affiche **au-dessus du personnage** dans la couleur
   des voix (orange clair, pas blanc), une seule fois par ligne, et le point orange du carnet s'allume. Remettre
   `call_one_in` à sa valeur ensuite.
1. Talkie (allumé, sur X) accroché à la ceinture, mains vides. Clic droit : « Parler sur X MHz » est **grisé**, info-
   bulle « Prenez le talkie en main (ou portez la radio sur le dos) : il n'émet pas depuis la ceinture ni
   l'inventaire. » ; « Options de l'appareil » → section « Émettre » grisée avec le même motif ; rien n'est dit.
2. Prendre le talkie en main : « Parler sur X MHz » part, Walt répond ; la réponse s'affiche une seule fois au-dessus
   du personnage (bulle vanilla), dans les deux lignes de la section et dans l'onglet Radio (« Vous » puis
   « Réponse »). Le raccrocher à la ceinture : un nouvel appel s'affiche toujours une seule fois.
3. Talkie rangé dans l'inventaire principal (ni en main, ni accroché) ou dans un sac : aucune option « Parler sur … »,
   aucune ligne reçue en solo (⚠ choix de la décision 3 ; en MP le vanilla sert toutes les radios allumées de
   l'inventaire principal).
4. Journal : aucune erreur Lua de `BatmanRadio_Core`, `RS_BeltRadio`, `RS_RadioTalk`, `RadioSurvivor_Server`.

Écart à signaler : une clé `IGUI_RS_…` affichée telle quelle, une ligne en double, une fréquence jamais réglée dans la
liste, le point orange qui reste allumé après lecture de l'onglet Radio, une erreur Lua de `RS_RadioLog`,
`RS_RadioHistory` ou `RS_Notebook`, un refus rouge « Laissez-lui le temps de répondre. » en parlant normalement.
Différé (cas limites) : radio portée sur le dos (réglage par l'action vanilla,
⚠ non vérifié en jeu), plus de 8 fréquences, réception brouillée (texte altéré : ligne non reconnue, ⚠ attendu). MP
(séance finale, E06-T05) : deux joueurs sur la même fréquence et sur deux fréquences, reconnexion, aucun historique de
l'autre ; talkie à la ceinture : le vanilla MP sert déjà toutes les radios allumées de l'inventaire principal
(réception et phrase relayée par `getTransmittingRadio`) — vérifier qu'un nouveau personnage a bien son historique
(premier `hello` corrigé) et qu'une réponse reçue à la ceinture n'apparaît qu'une fois : une ligne dans le chat radio
(vanilla) et une bulle au-dessus du personnage (Belt Walkie-Talkie, `BatmanRadio_Core.onDeviceTextMP`) **dans la
couleur des voix** (code `RSVO` reconnu par `RS_BeltRadio`, pas blanc ; une station vanilla reste blanche), pas deux
bulles avec deux talkies non tenus sur X, aucune bulle ajoutée si le talkie en main reçoit déjà X. Émission depuis la
ceinture : refusée côté client (option grisée) et côté serveur (`Reject_NoRadio` si un client modifié l'envoie). Cas limites différés : radio éteinte tenue en main
pendant qu'un talkie à la ceinture reçoit (les lignes « radio » sont masquées par le moteur, ⚠ attendu) ; Better
Walkie Talkies actif en MP (aucune bulle ajoutée, ⚠ non vérifié).

### Carnet papier (E06-T06, solo, court)

Refonte visuelle du carnet selon la maquette A (`docs/maquettes/carnet-papier.dc.html`) : papier crème, reliure à
anneaux, marque-pages colorés à droite, onglet Radio en deux colonnes avec la ligne « Dire : ». Textures du mod
`media/textures/RadioSurvivor/RS_Notebook_*.png`, produites par `python RadioSurvivor/tools/gen_notebook_textures.py`
(`--preview FICHIER.png` : aperçu composé hors jeu, polices Windows et non celles du jeu). Hors jeu :
`tests/test_radio_history.py` (`IntegrationTests` : sélection, point par fréquence, saisie par `Talk.send`, grisé,
focus, dessin avec et sans texture, aucun texte hors de sa page à la taille minimale), `tests/test_carnet.py`
(tampons, marque-pages), `tests/test_radio_module.py` (contraintes Kahlua, clés EN/FR). Le rendu réel (polices,
couleurs, textures chargées) n'est vérifiable qu'en jeu.

**Solo, court, nominal d'abord** (pont `--offline`, talkie émetteur en main sur la fréquence X de Walt) :

1. Ouvrir le carnet (bouton latéral **Carnet**) : fenêtre en papier crème, reliure brune à anneaux à gauche, barre
   de titre sombre fine avec « Carnet », croix et réduction ; quatre marque-pages à droite (Radio orange, Contacts
   ocre, Missions vert, Réputation bleu), l'onglet actif plus avancé sur la page. Aucun damier rose ni carré blanc
   (texture manquante).
2. Marque-page **Radio** : à gauche « Fréquences entendues », X en gros (bleu encre si sélectionnée, encadrée),
   « Dernier : MM/JJ hh:mm » dessous, bouton tampon **Régler ma radio** juste sous la liste ; séparation en
   pointillés ; à droite le titre « X MHz » en gros, la conversation (« moi — » bleu, « Réponse — » noir,
   « entendu — » gris), puis en bas « Dire : » + ligne soulignée (« Parler sur X MHz ») + bouton plein **Émettre**.
3. Cliquer dans la ligne, taper « Walt, tu m'entends ? », Entrée : la phrase est dite, la ligne se vide, les touches
   du jeu remarchent tout de suite (déplacement au clavier) ; la ligne est grisée avec « En attente d'une
   réponse... », puis « Vous parlez sans arrêt… » jusqu'à la fin du délai ; la réponse s'ajoute en bas.
4. Recommencer avec le bouton **Émettre** : même comportement ; Échap dans la ligne rend aussi le clavier.
5. Recevoir une ligne sur une autre fréquence Y (appel spontané, ou une 2e radio réglée sur Y) pendant la lecture de
   X : un point orange apparaît à côté de Y dans la liste ; cliquer Y l'éteint. Y sélectionnée, talkie toujours sur
   X : sous la conversation, « Radio réglée sur X MHz (pas sur Y MHz). » ; **Régler ma radio** règle le talkie.
6. Marque-pages **Contacts**, **Missions**, **Réputation** : même papier, textes inchangés en encre sombre, boutons
   tampons (bordure brune), bouton grisé (pas noir) quand l'action est impossible, note privée lisible.
7. Agrandir et réduire la fenêtre par le coin bas droit : rien ne déborde ni ne se chevauche (titres, liste,
   bouton Émettre, marque-pages) ; réduire le carnet (bouton de la barre de titre) puis le rouvrir.
8. Option du jeu « taille de police » au maximum, langue anglaise : relancer le jeu, rouvrir le carnet ; textes
   coupés par « ... » au lieu de déborder, libellé « Say: » masqué si la page est trop étroite.

Écart à signaler : texte clair illisible sur le papier, texte qui sort de sa colonne ou d'un marque-page, clé
`IGUI_RS_…` affichée telle quelle, touches du jeu bloquées après un envoi, point orange qui ne s'éteint pas à la
sélection, erreur Lua de `RS_Notebook`. Différé (cas limites) : manette (le carnet n'a pas de navigation manette,
⚠ inchangé), fenêtre de livraison et liste d'invitation restées au style vanilla (⚠), radio posée ou autoradio
(la ligne « Dire : » n'utilise que le talkie porté, ⚠).

### Repère sur la carte (E07-T04, solo, court)

Action `mark_map` (`docs/protocole-carnet-v2.md`, « Repère sur la carte ») : la voix marque un lieu `place=` de sa
fiche sur la carte de l'appelant. Hors jeu : `tests/test_protocol.py` (`scenario_map_bridge`, `scenario_map_client`,
`scenario_map_server`, `scenario_map_mp`), `tests/test_radio_history.py` (`MapMarkTests` : ligne « Repère reçu »
de l'historique radio, E07-T08), `tests/test_personas.py` et `tests/test_kahlua.py` (lignes `place=`).

**Automatique** (solo, partie `rstest*`, console Lua) :

1. Ouvrir le carnet une fois (personnage du carnet lié), puis `RST.run({ suite = "rs.actions.map", tags = { "world" } })` :
   3 PASS (lieu accepté marqué une fois, pas de doublon, délai ; lieu absent de la fiche refusé, rien de marqué ;
   ligne `mark` « Repère reçu : RST map test » dans l'historique radio du personnage sur 199,8 MHz seulement, côté
   serveur et client, sans coordonnée). Sans carnet lié, le troisième test est SKIP. Les symboles du test sont retirés
   et l'historique radio du personnage est rétabli à la fin.
2. Persistance : `RST.run({ suite = "rs.actions.map.before" })` (PASS, note « now save and quit… ») ; ouvrir la carte
   (M) : icône rouge brique « cible » et « RST persist » vers 10612,9318 (Muldraugh) ; **Sauvegarder et quitter** vers
   le menu, recharger la partie ; `RST.run({ suite = "rs.actions.map.after-reload" })` : PASS (MapItem nouveau,
   icône et libellé présents une fois), puis le repère est retiré.

**Manuel avec le pont** (pont connecté au LLM ; dans la fiche installée
`Zomboid/Lua/batman_RadioSurvivor/personas/darlene.txt`, relue à chaud, remplacer `actions=say` par `actions=say,mark_map` et ajouter avant `[prompt]` la ligne
`place=clinic 11880,6878,0 Clinique de Darlene`, à défaire après l'essai) :
demander à la voix « Où est ta clinique ? Marque-la sur ma carte. » ; aucun texte flottant ; l'onglet Radio du carnet,
sur la fréquence de Darlene, montre la ligne rouge brique « Repère reçu : Clinique de Darlene » (sans coordonnée ;
inscrite à l'acceptation de l'action, elle peut précéder les lignes de la réponse encore à l'antenne) ; la carte (M) montre la cible et le libellé ; le journal `actions-*.log` a une ligne
`mark_map … place=clinic … accepted ok`. Redemander : pas de second symbole (délai de 30 s ou repère déjà présent).

Écart à signaler : texte flottant, ligne « Repère reçu » absente, sur une autre fréquence ou chez un autre joueur,
texture d'erreur à la place de la cible, libellé décalé ou recouvrant la cible, doublon après une
seconde demande ou un rechargement, repère absent après rechargement, erreur Lua de `RS_MapActions`. MP (repère chez
le seul appelant, persistance après reconnexion du client) : séance MP finale.

### Quartier révélé (E07-T05, solo, court)

Action `reveal_area` (`docs/protocole-carnet-v2.md`, « Quartier révélé ») : le quartier autour d'un lieu `place=` de la
fiche devient connu sur la carte de l'appelant (carré de 5 blocs de 32 cases, 160 cases de côté au plus). Hors jeu :
`tests/test_protocol.py` (`scenario_reveal_bridge`, `scenario_reveal_rect`, `scenario_reveal_client`,
`scenario_reveal_server`, `scenario_reveal_mp`), `tests/test_radio_history.py` (`RevealTests`, ligne « Quartier
révélé »), `tests/test_kahlua.py` (`KR-REVEAL`).

**Automatique** (solo, partie `rstest*` **neuve de préférence** : la suite cherche à ~1 200 cases du joueur une zone
dont les 25 blocs sont encore inconnus ; console Lua) :

1. Ouvrir le carnet une fois, puis `RST.run({ suite = "rs.actions.reveal", tags = { "world" } })` : 2 PASS (zone
   acceptée révélée, 25 blocs connus, rectangle aligné et plafonné, anneau de blocs autour inchangé, délai ; ligne
   « Quartier révélé : RST reveal test » sur 199,8 MHz seulement, client et serveur ; lieu absent de la fiche et fiche
   sans `reveal_area` refusés, rien de révélé). Sans carnet lié, une note remplace le contrôle de la ligne. Les blocs
   révélés sont effacés à la fin (`clearKnownInSquares`, bloc par bloc), l'historique radio est rétabli. Note « no far
   test area… » (SKIP) : partie trop explorée, en prendre une neuve.
2. Persistance : `RST.run({ suite = "rs.actions.reveal.before" })` (PASS, note avec le rectangle) ; ouvrir la carte
   (M) : carré de fond de carte visible à cet endroit ; **Sauvegarder et quitter** vers le menu, recharger ;
   `RST.run({ suite = "rs.actions.reveal.after-reload" })` : PASS (WorldMapVisited nouveau, 25 blocs connus), puis la
   zone est effacée.

**Manuel avec le pont** (fiche installée `darlene.txt` relue à chaud : `actions=say,reveal_area` et la ligne
`place=clinic 11880,6878,0 Clinique de Darlene`, à défaire après l'essai) : demander « Décris-moi le quartier de ta
clinique. » ; la carte (M) montre un carré de fond de carte d'environ 160 cases autour de la clinique, rien ailleurs ;
l'onglet Radio montre « Quartier révélé : Clinique de Darlene » sur la fréquence de Darlene ; le journal
`actions-*.log` a `reveal_area … place=clinic … ok`. Redemander dans la minute : `cooldown`, rien de plus.

Écart à signaler : zone plus grande qu'environ 160 cases ou décalée du lieu, rien de révélé, révélation chez un
autre joueur, ligne absente ou sur une autre fréquence, zone perdue après rechargement, erreur Lua de
`RS_MapActions`. MP (zone chez le seul appelant, absente chez un second client, présente après reconnexion de
l'appelant) : séance MP finale.

### Mission donnée par une voix (E11-T08, solo, court)

Action `start_mission` (`docs/protocole-carnet-v2.md`, « Mission donnée par une voix ») : une voix confie une mission
« reconnaître », le compte rendu se fait à la radio sur sa fréquence. Hors jeu : `tests/test_carnet.py`
(`VoiceMissionTests`, sans moteur de PNJ), `tests/test_protocol.py` (`scenario_voice_mission_bridge`),
`tests/test_radio_history.py` (ligne « Mission reçue »).

**Automatique** (solo, partie `rstest*` en ville, console Lua) : `RST.run({ suite = "rs.missions.radio", tags = {
"world" } })` : 1 PASS (exécuteur enregistré, mission créée autour du joueur sur une fiche de test, deuxième mission
refusée `mission_open`, phrase avant la visite sans effet (`not_yet`, compte rendu refusé `not_done`), joueur déplacé
dans la zone par la fixture et vu par le sondage serveur, appel suivant au tour `report_due` (mission encore active,
« à rapporter »), compte rendu à une autre voix sans effet, compte rendu de cette voix (`RS_MissionVoice.report`,
exécuteur de `report_mission`, E11-T13) = réussite, événement `mission.success`, joueur ramené). Mission
dans un état en mémoire (ni carnet, ni historique, ni repère). Note « no building fits » (SKIP) : se placer en ville.
Depuis E11-T10, la suite vérifie aussi la zone approximative (`m.mapZone` contient l'emprise sans être centrée sur
le bâtiment, projetée au participant, absente du contexte du pont), puis, en solo, le cercle posé sur la carte du
monde et son retrait après la réussite (les zones des vraies missions du carnet sont conservées).

**Zone sur la carte (E11-T10, solo, court)** : après « Mission reçue », ouvrir la carte (M) : un cercle orange tracé à
la main, libellé « Zone de reconnaissance (<voix>) » au-dessus, à 60-250 cases ; le bâtiment est dans le cercle mais
pas en son centre ; page Missions : « Une zone approximative est entourée sur votre carte ». Sauvegarder, quitter,
recharger : le cercle est toujours là, sans doublon. Atteindre le lieu (le cercle reste), faire le compte rendu : le
cercle disparaît (seul le repère de récompense reste). Refaire une mission puis « Abandonner » : cercle retiré.
Écart à signaler : cercle absent, bâtiment hors du cercle, cercle centré sur le bâtiment, doublon après rechargement,
cercle resté après la fin, erreur Lua de `RS_MapActions`.

**Manuel avec le pont** (pont connecté au LLM, Living Knox désactivé ; dans la fiche installée
`Zomboid/Lua/batman_RadioSurvivor/personas/darlene.txt`, relue à chaud, remplacer `actions=say` par
`actions=say,start_mission` et ajouter avant `[prompt]` la ligne `place=clinic 11880,6878,0 Clinique de Darlene`, à
défaire après l'essai) : ouvrir le carnet une fois, puis demander à Darlene « Tu as du travail pour moi ? ». Attendu :
journal `actions-*.log` `start_mission … template=scout … accepted ok` ; onglet Radio du carnet, sur sa fréquence,
« Mission reçue : maison » (ou un autre type), puis, quelques secondes après, une seconde réponse de Darlene qui donne
le type de bâtiment et ses indices (E11-T09, consigne) ; page Missions : titre « Reconnaissance pour un survivant »
(liste et fiche), demandeur Darlene Pruitt, « Lieu : … », « Indices donnés sur le lieu : » et les indices en
français (mêmes repères que ceux dits par la voix), aucune ligne « CharacterReputation », « pas encore
atteint », consigne du compte rendu radio, « Récompense : une information de la voix », seul « Abandonner ». Redemander
du travail : pas de seconde mission (`mission_open` au journal). Dire « J'y suis allé » sans y aller : Darlene répond
que ce n'est pas fait, la mission reste ouverte. Lui demander où c'est : elle décrit le bâtiment par ses indices, sans
coordonnée. Aller au bâtiment (la page Missions passe à « Lieu atteint »), revenir ou non, puis lui parler sur sa
fréquence : la mission passe à « réussie », Darlene remercie, l'onglet Radio montre « Repère reçu : Clinique de
Darlene » et la carte (M) la cible ; page Réputation : l'événement de réussite (libellé historique de M01 « Livraison réussie », non appliqué).
E11-T13 : après la visite et avant le compte rendu, la page Missions affiche « Objectif rempli — à rapporter au
demandeur » (liste : « À rapporter ») et « rappelez Darlene Pruitt sur sa fréquence et annoncez-le » ; un appel sans
rapport avec la mission (« Il fait beau ») la laisse « à rapporter » ; le journal `actions-*.log` porte
`report_mission … accepted ok` au compte rendu.

Écart à signaler : mission créée sans ligne « Mission reçue » ou sur une autre fréquence, seconde mission acceptée,
réussite sans visite, visite non vue (page restée « pas encore atteint » dans le bâtiment), coordonnée dite par la voix,
indices ni dits ni affichés, titre « Premiers soins » sur une reconnaissance, ligne technique de réputation dans la fiche,
repère absent après la réussite, bouton « Réclamer » ou « Inviter » sur une mission de voix, erreur Lua de
`RS_MissionVoice`. MP (mission et repère chez le seul appelant, compte rendu d'un autre joueur sans effet, reconnexion) :
séance MP finale.

### Mission « retrouver » (E11-T05, solo, court)

Gabarit `retrieve_id` (`docs/carnet-implementation-04221.md`, « Gabarit retrouver ») : un corps porteur d'une carte
d'identité est posé dans un bâtiment tiré, la carte se rapporte au PNJ demandeur, vérifiée par identifiant d'objet.
Hors jeu : `tests/test_mission_retrieve.py` (doublures de métagrille, de cases et de cadavres).

**Automatique** (solo, partie `rstest*` en ville, console Lua) : `RST.run({ suite = "rs.mission.retrieve", tags = {
"world" } })` : 1 PASS (bâtiment tiré autour du joueur, mission en mémoire acceptée, joueur déplacé au point du lieu,
corps posé par le sondage serveur une fois la case chargée, carte du corps retrouvée par son identifiant, aucune
seconde pose, autre carte d'identité de même nom refusée `WrongCard`, bon identifiant refusé tant que la carte est
dans le corps, carte prise puis remise : réussite, carte retirée, événement `mission.success` ; nettoyage : carte en
trop reprise, corps retiré, joueur ramené). Note « no building fits » (SKIP) : se placer en ville.

**Manuel** (pont connecté, PNJ Living Knox connu) : demander du travail jusqu'à une offre « Les papiers d'un
disparu » (ou l'accepter au carnet) ; carte : cercle « Zone de recherche (<PNJ>) » ; aller au bâtiment : un corps
(nom affiché sur sa carte d'identité dans son inventaire) ; prendre la carte, page Missions « Carte d'identité
trouvée » ; revenir près du PNJ, « Livrer » : la fenêtre liste toutes vos cartes d'identité ; une autre carte →
refus « Ce n'est pas la carte d'identité prise sur le corps », la bonne → réussite, cercle retiré, lot commun.
Écart à signaler : aucun corps après plusieurs secondes sur place (`console.txt` : `retrieve:`), deux corps, carte
absente du corps, autre carte acceptée, erreur Lua de `RS_MissionRetrieve`.

### Mission « nettoyer » (E11-T04, solo, court)

Gabarit `clear` (`docs/carnet-implementation-04221.md`, « Gabarit nettoyer ») : tuer N zombies dans un cercle tracé
autour d'un bâtiment tiré, décompte par le serveur avec l'attribution d'E04-T06. Hors jeu :
`tests/test_mission_clear.py` (densité, zombies et joueurs en doublures).

**Automatique** (solo, partie `rstest*` en ville, console Lua) : `RST.run({ suite = "rs.mission.clear", tags = {
"world" } })` : 1 PASS (bâtiment tiré autour du joueur, N dans 6..25, mission en mémoire acceptée et cible ramenée à
2, compte rendu avant le décompte refusé, joueur déplacé au centre du cercle en mode dieu, trois zombies créés à
côté : coup de batte mortel compté une fois, second décompte du même zombie sans effet, `Kill(nil)` non compté, second
coup mortel : objectif rempli, mission encore active « à rapporter » (E11-T13), compte rendu au demandeur
(`RS_Missions.spoken`) : réussite, événement `mission.success` ; nettoyage : zombies et cadavres retirés, joueur
ramené). Note « no building with enough zombies »
(SKIP) : se placer en ville.

**Manuel** (pont connecté, PNJ Living Knox connu) : demander du travail jusqu'à une offre « Nettoyer les abords d'un
lieu » (N annoncé) puis l'accepter ; carte : cercle « Zone à nettoyer (<PNJ>) » ; tuer des zombies dans le cercle
(mêlée, arme à feu, voiture conduite) : page Missions « Décompte commun : k / N » et votre part ; un zombie tué hors du
cercle ou brûlé par un cocktail Molotov ne compte pas ; au N-ième : page Missions « Objectif rempli — à rapporter au
demandeur » (liste : « À rapporter »), plus aucun décompte ; revenir près du PNJ et le lui dire (« C'est fait, la zone
est nettoyée ») : réussite, cercle retiré, « Réclamer » près du PNJ ; variante sans pont : bouton « Rendre compte » près
de lui (grisé loin de lui). Le dire à un autre PNJ, ou avant le N-ième : rien (E11-T13).
MP (séance finale) : deux participants, même décompte chez les deux, parts justes, aucun double compte. Écart à
signaler : décompte qui saute de deux, zombie hors cercle compté, mort par le feu comptée, erreur Lua de
`RS_MissionClear`.

### Mission « récupérer » et caches (E11-T06, solo, court)

Gabarit `recover` et caches (`docs/carnet-implementation-04221.md`, « Caches et gabarit récupérer ») : sac marqué posé
une fois dans un bâtiment tiré, à porter au dépôt du groupe du demandeur, reconnu par son identifiant. Hors jeu :
`tests/test_mission_recover.py` (cases, sol, conteneurs et foyer en doublures).

**Automatique** (solo, partie `rstest*` en ville, console Lua) : `RST.run({ suite = "rs.mission.recover", tags = {
"world" } })` : 1 PASS (bâtiment tiré autour du joueur, mission en mémoire, joueur déplacé au bâtiment : sac posé une
seule fois avec la marque et un contenu ; joueur le ramasse : trouvé ; retour au point de départ (dépôt) : un autre sac
portant la même marque est ignoré, le vrai sac posé au sol quitte le monde et remplit l'objectif (mission encore
active « à rapporter », E11-T13 ; compte rendu refusé avant le dépôt), compte rendu au demandeur : réussite ;
nettoyage : sacs retirés, joueur ramené). Note « no building fits around the player » (SKIP) : se placer en ville.

**Manuel** (pont connecté, PNJ Living Knox connu dont le groupe a un foyer) : demander du travail jusqu'à une offre
« Rapporter une cache » puis l'accepter ; carte : cercles « Zone de la cache (<PNJ>) » et « Dépôt (<PNJ>) » ; au
bâtiment : un sac de sport au sol (contenu annoncé dans le carnet) ; le prendre : page Missions « Sac trouvé » ;
quitter le jeu et relancer avant de le prendre : toujours un seul sac ; le poser au sol ou dans une caisse dans le
cercle du dépôt : sac disparu, page Missions « Objectif rempli — à rapporter au demandeur » ; le dire au PNJ (ou bouton
« Rendre compte » près de lui) : réussite, cercles retirés, « Réclamer » près du PNJ (E11-T13). Un autre sac de sport déposé ne
compte pas. MP (séance finale) : sac visible des deux clients, réussite pour les deux participants. Écart à signaler :
aucun sac après plusieurs secondes sur place (`console.txt` : `cache:`), deux sacs, réussite avec un autre sac, erreur
Lua de `RS_Caches` ou `RS_MissionRecover`.

### Mission « signaler » (E11-T07, solo, court)

Gabarit `signal` (`docs/carnet-implementation-04221.md`, « Gabarit signaler ») : allumer un signal de la couleur
demandée dans un cercle, pendant une fenêtre horaire. Signal Smoke (`batman_SignalSmoke`) est un mod requis. Hors jeu :
`tests/test_mission_signal.py` (doublure du module ; module cassé : erreur au journal, aucune offre).

**Automatique** (solo, partie `rstest*` en ville, console Lua) : `RST.run({ suite =
"rs.mission.signal", tags = { "world" } })` : 1 PASS (bâtiment tiré autour du joueur, couleur connue de Signal Smoke,
mission en mémoire acceptée, fenêtre ramenée à l'heure courante ; trois fumigènes de 15 s par `SignalSmoke.start` :
autre couleur au centre et bonne couleur hors du cercle sans effet, bonne couleur au centre : objectif rempli, mission
encore active « à rapporter » (E11-T13 ; compte rendu refusé avant le signal), compte rendu au demandeur : réussite).
Module de Signal Smoke inutilisable (installation cassée) : FAIL.

**Manuel** (pont connecté, PNJ Living Knox connu) : aucune erreur `RS_MissionSignal` dans `console.txt` ; offre « Faire un signal sur un lieu » (couleur et heures
annoncées), l'accepter ; carte : cercle « Zone du signal (<PNJ>) » ; page Missions : couleur, heures, « Aucun signal
vu ». Lancer un fumigène d'une autre couleur dans le cercle : rien ; de la bonne couleur hors des heures : rien ; dans
les heures : « Objectif rempli — à rapporter au demandeur » ; revenir le dire au PNJ (ou « Rendre compte » près de
lui) : réussite, cercle retiré, « Réclamer » près du PNJ (E11-T13). Écart à signaler : réussite avec une mauvaise couleur,
hors du cercle ou hors des heures, erreur Lua de `RS_MissionSignal`.

### Journal du dehors (E13-T05, solo, court)

Document du mod apporté par le passeur, une édition par passage. Fiche :
[conception/journal-du-dehors.md](conception/journal-du-dehors.md). Jeu lancé en mode debug, langue française.

1. Partie `rstest-journal` (ou une partie `rstest*` existante). `RST.run({ suite = "rs.outside_news", tags = "world" })`
   → `OK` (6 tests) ; une fenêtre de document s'ouvre puis se referme pendant la suite ; une édition n° 2 reste dans
   l'inventaire.
2. Console Lua : `RadioSurvivorOutsideNews.give(1)` puis `RadioSurvivorOutsideNews.give(2)`. Journal :
   `[RadioSurvivor] outside news: edition 1 given to …`. Deux « Journal du dehors » avec l'icône du journal (aucun « ? »).
3. Clic droit → « Inspecter » sur chacun : fenêtre des documents en une seconde environ, titre « Nouvelles du dehors -
   n° 1 » (puis n° 2), date du jour de jeu, une, trois brèves, prix ; textes en français, différents d'une édition à
   l'autre ; aucune ligne hors de la page ; bouton du bas : la transcription. Aucun `Missing arguments`, `RICH TEXT
   ERROR` ni erreur Lua de `RadioSurvivor/` dans `console.txt`.
4. Après lecture, l'édition lue porte la marque « lu » de l'inventaire, l'autre non.
5. Sauvegarder, quitter, passer le jeu en anglais, recharger : relire l'édition 1 → texte en anglais, même une et
   mêmes prix.

Écart à signaler : une clé `Print_Text_…` ou `%1` affichée, deux éditions identiques, un texte qui reste en français
après le passage en anglais, une ligne qui sort de la page ou chevauche la suivante, une icône « ? ».

## 14. Carnet avec un PNJ Living Knox (E17-T03)

Fournisseur `shared/RadioSurvivor/RS_LivingKnox.lua` ([carnet-implementation-04221.md](carnet-implementation-04221.md),
« Fournisseur Living Knox »). Hors jeu : `tests/test_carnet.py` (`LivingKnoxCarnetTests` : vrai moteur, vrai pont
hors ligne), `tests/test_observations.py`, `tests/test_protocol.py` (`scenario_supply_offer`).

Les membres de la population initiale (LK08-T05) n'ont pas encore de corps tant que LK09-T03 (matérialisation) n'est
pas fait : l'essai relie à la main un PNJ créé par `LKB.spawn` à un membre vivant d'un groupe.

**Préparation** (solo, partie `rstest*` neuve, options Living Knox `Enabled` et sandbox par défaut, mod de
développement, jeu en `-debug`, pont lancé, `--offline` suffit). Journal au chargement :
`[RS_NPCProvider] provider livingknox registered` puis `NPC provider=livingknox, available=true`, et
`population: N group(s) created`. Console Lua :

1. `LKB.spawn(2, 0)` puis `LKB.list()` : relever l'identifiant `lk-<n>` du PNJ créé à 2 cases.
2. Relier ce PNJ au chef d'un groupe de colons et créer un besoin (remplacer `lk-1`) :
   `local G = LivingKnox.Groups; for _, gid in ipairs(G.list()) do local g = G.get(gid); if g.type == "settlers" and g.leader then print(gid, G.setNpc(gid, g.leader, "lk-1"), G.setNeed(gid, "food", 20), G.setNeed(gid, "medical", 80)) break end end`

**Automatique** : `RST.run("rs.carnet.lk")` → 3 PASS (fournisseur actif, corps nommés `lk-<n>`, contexte sans secret
ni foyer) ; `RST.run({ suite = "rs.carnet.lk.supply", tags = { "world" } })` → 1 PASS (offres du groupe sur des
objets réels ; note `grp-<n>-food-<k>: food level 20, 60 V left`).

**Manuel (parcours du carnet 0.2)** :

1. Ctrl+G près du PNJ : halo avec le nom du chef de l'histoire du groupe ; onglet Contacts : groupe `grp-<n>`.
2. `/say Avez-vous besoin de quelque chose ?` : réponse (bulle et chat) qui parle du manque de nourriture ; onglet
   Missions : « Nourriture pour un groupe », progression `0 / 60 points de valeur`, objets acceptés avec leur valeur
   (conserves, riz, pâtes… à 2), lot `2 × Antibiotiques`.
3. Accepter, puis livrer 31 conserves : refus « Trop d'objets », rien ne disparaît. Livrer 10 conserves : confirmation
   « 10 objet(s) d'une valeur de 20 points », progression `20 / 60` ; console : `print(LivingKnox.API.getGroup("grp-<n>").needs.food)` → 25.
4. Livrer 20 conserves : mission réussie, réserve 35 ; « Réclamer » donne 2 antibiotiques ; journal du groupe :
   `supply food +10 (..., 40 V), gives 2 Base.Antibiotics, done` ; `print(LivingKnox.API.attitude("grp-<n>", RS_CarnetServer.bound[getPlayer()]).trend)` → `up`.
5. Tuer le PNJ : ligne `[LivingKnox] INFO npc lk-<n> died ...` ; dans le carnet, contact « Mort », Ctrl+G ne le
   sélectionne plus.

Écart à signaler : une réserve qui monte deux fois pour une même livraison, un objet retiré sans progression, une
offre `first_aid_v1` statique (bandages) chez un PNJ Living Knox, un secret de l'histoire ou une coordonnée dans
`requests.txt` (pont réel : prompt du journal du pont), une erreur Lua de `RS_LivingKnox`, `RS_Missions` ou
`RS_Carnet_Server`. À deux clients (sélection sur la copie cliente, offre propre à chaque personnage, livraison
commune) : séance MP finale.

### Accord de faction avec un groupe (E09-T05, solo, court)

Même préparation que ci-dessus (PNJ relié au chef d'un groupe chargé à côté du joueur, carnet ouvert une fois).

**Automatique** : `RST.start({ suite = "rs.factions.accord", tags = { "world" } })` → 1 PASS (offre du serveur, trêve
conclue, joueur couvert aussitôt, accord applicable après les décisions suivantes du groupe, attitude inchangée ; note
`agreement agr-<n> applicable <d> ms after its conclusion`) ; l'accord est retiré à la fin.

**Manuel** (pont réel, sinon `RS_OFFLINE_INTENT=negotiate`) : provoquer le groupe (un coup sur un membre) pour qu'un
combattant attaque, puis Ctrl+G sur le chef et `/say Trêve ! On arrête de se battre.` : réponse du chef ; console
`agreement agr-<n> (truce) concluded ... pending application`, puis, une fois que le combattant a lâché le joueur,
`... applicable` et le halo « Trêve avec <groupe> désormais en vigueur » (jamais avant). MP (séance finale) : un
membre sans mandat dit la même phrase sans effet ; deux négociateurs concluent en même temps : un seul accord (journal
`refused: agreement revision changed`).

## 15. Outils d'administration Living Knox (LK13-T01)

Fiche [conception/administration.md](conception/administration.md). Hors jeu : `tests/test_lk_admin.py`.

**Automatique** (solo, partie `rstest*`, mod de développement, `-debug`) :
`RST.run({ suite = "lk.admin", tags = "world" })` → 3 PASS (refus sans joueur autorisé, liste / détail / foyer
déplacé / relève forcée). Serveur dédié : `RST.server({ suite = "lk.admin", tags = "world" })` depuis un client admin.

**Manuel (solo, court)** :

1. Console Lua : `LivingKnox.AdminView.open()` → fenêtre « Living Knox : groupes », une ligne par groupe avec
   `foyer x,y,z`, vivants et objectif.
2. Cliquer un groupe : membres et journal (le plus récent d'abord) sous la liste.
3. « Ma position » puis « Déplacer le foyer ici » loin des autres foyers : message « Foyer de grp-<n> déplacé en
   x,y,z », ligne `admin home ... by <compte>` en tête du journal ; près d'un autre foyer : « Refusé : too close to
   the home of grp-<m> ».
4. Tuer tous les membres d'un groupe (remplacer `grp-1`) :
   `local G = LivingKnox.Groups local g = G.get("grp-1") for mid, m in pairs(g.members) do if m.alive then G.markDead(g.id, mid) end end`,
   « Actualiser », sélectionner le groupe, puis « Forcer la relève » : « Relève de grp-1 installée : grp-<k> », nouveau
   groupe dans la liste.

**MP (séance finale)** : client admin, panneau d'admin → bouton « Groupes Living Knox » ; un second client au rôle
`user` n'a pas le panneau ; depuis sa console, `LivingKnox.AdminView.send("list")` → statut « Réservé aux
administrateurs. », liste vide, ligne serveur `admin: request list refused for <compte> (missing capability
PopmanManage)`.

Écart à signaler : une donnée (foyer, journal) reçue par un client non admin, une commande acceptée sans le droit, un
bouton absent du panneau d'un admin, une erreur Lua de `LK_Admin` ou `LK_AdminView`.

### Fiche d'un PNJ par clic droit (LK13-T13)

Hors jeu : `tests/test_lk_npcsheet.py`.

**Automatique** (solo, partie `rstest*`, `-debug`) : `RST.run({ suite = "lk.npcsheet", tags = "world" })` → 3 PASS
(refus sans joueur autorisé ; groupe de test matérialisé sur la case du joueur : fiche lue, faim réglée à 150 gardée à
100 et notée au journal, lue par la décision suivante ; santé réglée à 0 gardée à 1). Serveur dédié :
`RST.server({ suite = "lk.npcsheet", tags = "world" })` depuis un client admin.

**Manuel (solo `-debug`, court)** :

1. Clic droit sur un PNJ Living Knox → « Détails (Living Knox) » : fenêtre « Living Knox : PNJ lk-<n> » avec groupe,
   rôle, besoins, santé, comportement et règle, geste, vigilance, perception, arme et munitions, position, foyer ; les
   valeurs changent d'elles-mêmes (relecture toutes les 2 s).
2. Saisir `95` dans « Faim (0-100) » puis « Régler » : statut « Faim (0-100) : 20 -> 95 » ; en 1 à 2 s le comportement
   passe à `home` ou `meal`, règle `hunger` ; journal du groupe (fenêtre des groupes) : `hunger m-<k> (lk-<n>) 20 -> 95
   set by admin <compte>`.
3. Santé `30` : le PNJ se met au repos (règle `wound`) ; remettre `100`.
4. Sans `-debug` : l'option « Détails » n'apparaît pas.

**MP (séance finale)** : client admin : même option et mêmes réglages ; client `user` : aucune option ; depuis sa
console, `LivingKnox.NpcSheet.state.npc = "lk-1" LivingKnox.NpcSheet.refresh()` → statut « Réservé aux
administrateurs (mode debug en solo). », ligne serveur `admin: request npc refused for <compte>`.

Écart à signaler : option présente sans droit, fiche ou réglage accepté sans droit, valeur hors bornes acceptée,
requêtes qui continuent fenêtre fermée (console serveur), erreur Lua de `LK_NpcSheet` ou `LK_Admin`.

### Panneau de debug des PNJ (LK13-T14)

Hors jeu : `tests/test_lk_debugview.py`.

**Automatique** (solo, partie `rstest*`, `-debug`) : `RST.run({ suite = "lk.debugview", tags = "world" })` → 3 PASS
(refus sans joueur autorisé ; groupe de test matérialisé sur la case du joueur : groupe et membres dans la réponse
`activity`, faim mise à 95 par `npcSet` → ligne `behaviour` de m-2 avec `rule hunger` au journal d'activité et dans la
réponse incrémentale suivante). Serveur dédié : `RST.server({ suite = "lk.debugview", tags = "world" })` depuis un
client admin.

**Manuel (solo `-debug`, court)** :

1. Panneau debug vanilla (onglet Main) → bouton « Living Knox - PNJ » : fenêtre « Living Knox : debug des PNJ » avec la
   liste des groupes.
2. Choisir un groupe présent : une ligne par membre (présent, comportement, règle, cible, geste, position, besoins,
   santé) qui change d'elle-même toutes les 2 s ; journal d'activité (lignes `objective`, `behaviour`...) et journal
   sauvegardé du groupe en dessous.
3. Double clic sur un membre : sa fiche (LK13-T13) ; y mettre la faim à 95 : en 1 à 2 s une ligne « comportement »
   `... -> home` ou `meal (rule hunger: hunger 95 ...)` apparaît en tête du journal d'activité.
4. Fenêtre des groupes (`LivingKnox.AdminView.open()`) → bouton « Debug des PNJ » : même panneau, sur le groupe choisi.
5. Sans `-debug` : pas de bouton dans le panneau debug, `LivingKnox.DebugView.open()` rend `nil` (ligne WARN).

**MP (séance finale)** : client admin : même bouton (client `-debug`) et bouton de la fenêtre des groupes ; client
`user` : depuis sa console, `LivingKnox.DebugView.state.window = {} LivingKnox.DebugView.send()` → statut « Refusé
... », ligne serveur `admin: request activity refused for <compte>` ; fermer le panneau d'un admin : plus aucune ligne
`adminRequest` dans la console serveur.

Écart à signaler : bouton ou donnée sans droit, requêtes qui continuent panneau fermé, journal d'activité au-delà de
200 lignes, ligne de faim absente, bouton vanilla disparu du panneau debug, erreur Lua de `LK_DebugView`,
`LK_Activity` ou `LK_Admin`.

### Tableaux et actions d'administration (LK13-T15)

Hors jeu : `tests/test_lk_npcsheet.py`, `tests/test_lk_debugview.py`.

**Automatique** (solo, partie `rstest*`, `-debug`) : `RST.run({ suite = "lk.npcsheet", tags = "world" })` → 4 PASS
(dont rôle, nom et téléportation faits par l'autorité et notés au journal du groupe) ;
`RST.run({ suite = "lk.debugview", tags = "world" })` → 3 PASS. Serveur dédié : `RST.server({ ... })` avec les mêmes
suites depuis un client admin.

**Manuel (solo `-debug`, court)** :

1. Panneau « Living Knox : debug des PNJ » (écran de 1920 px ou plus) : quatre tableaux à fond opaque, colonnes
   alignées, en-têtes en petite police ; texte trop long coupé par « ... », texte entier en survolant la ligne ; clic
   sur un en-tête : tri (second clic : ordre inverse).
2. Choisir un membre présent → « Se téléporter » : le personnage arrive à côté du PNJ ; statut « Téléporté en x,y,z ».
3. « Ouvrir la fiche » : sections Identité, Besoins, Santé (en %), Comportement, Perception, Équipement ; champs de
   réglage déjà remplis avec les valeurs actuelles.
4. Fiche : choisir un autre rôle dans la liste → « Changer le rôle » : rôle mis à jour dans la fiche et le panneau,
   entrée « role ... set by admin » au journal sauvegardé.
5. Fiche : prénom « Jane », nom « Doe » → « Renommer » : nom affiché dans la fiche, le panneau (colonne Membre et Chef
   si c'est le chef) et le carnet (fiche du PNJ) ; « J4ne » : message d'erreur, rien envoyé.

**MP (séance finale)** : client admin : téléportation par `/teleportto` (le serveur l'accepte : rôle admin) ; rôle
sans `TeleportToCoordinates` : message « La téléportation exige le droit TeleportToCoordinates » ; client
`user` : `LivingKnox.NpcSheet.state.npc = "lk-<n>" LivingKnox.NpcSheet.setRole("fighter")` → « Refusé ... », ligne
serveur `admin: request npcRole refused for <compte>`.

Écart à signaler : colonne illisible ou chevauchante à 1920 px, fond transparent, champ vide à l'ouverture, action faite
sans droit, téléportation loin du PNJ, nom non repris par le carnet, erreur Lua de `LK_Table`, `LK_DebugView`,
`LK_NpcSheet` ou `LK_Admin`.

### Coordonnées des PNJ et téléportation hors écran (LK13-T16)

Hors jeu : `tests/test_lk_debugview.py` (`PositionTests`, `PositionSoloTests`), `tests/test_lk_npcsheet.py`.

**Automatique** (solo, partie `rstest*`, `-debug`) : `RST.run({ suite = "lk.debugview", tags = "world" })` → 4 PASS
(le 4e crée un groupe à 200 cases, vérifie la source « home » de ses membres et la destination de `homeGoto` avec un
joueur de substitution : le personnage ne bouge pas).

**Manuel (solo `-debug`, court)** :

1. Panneau « Living Knox - PNJ » : colonne « Foyer » dans la liste des groupes ; colonne « Position » de chaque membre
   vivant avec sa source : « (corps) » pour un PNJ présent, « (vu en dernier) » ou « (foyer du groupe) » sinon.
2. Choisir un groupe loin du personnage → « Aller au foyer du groupe » : le personnage arrive près du foyer affiché ;
   statut « Téléporté près du foyer du groupe x,y,z ».
3. Revenir loin, choisir un membre hors écran → « Se téléporter » : arrivée à sa dernière position connue, ou près du
   foyer de son groupe s'il n'a jamais été vu (statut correspondant).

**MP (séance finale)** : client admin : « Aller au foyer du groupe » par `/teleportto` ; client `user` :
`LivingKnox.NpcSheet.send("homeGoto", { gid = "grp-1" })` → « Refusé ... », ligne serveur
`admin: request homeGoto refused for <compte>`.

Écart à signaler : membre vivant sans position, source fausse (corps présent marqué « vu en dernier »), refus
« no known position » pour un membre d'un groupe qui a un foyer, arrivée loin du foyer, erreur Lua de `LK_DebugView`,
`LK_NpcSheet` ou `LK_Admin`.

### Panneau de debug des fréquences (E05-T14)

Hors jeu : `tests/test_rs_freqdebug.py`. Fiche : `docs/persona-format.md`, section « Panneau de debug des fréquences ».

**Automatique** (solo `-debug`, toute partie) : `RST.run({ suite = "rs.freqdebug" })` → 3 PASS. Serveur dédié :
`RST.server({ suite = "rs.freqdebug" })` depuis un client admin.

**Manuel (solo `-debug`, court)** :

1. Panneau debug (F11 ou bouton debug) : bouton « Radio Survivor - Fréquences » présent, trié avec les autres, les
   autres boutons (dont « Living Knox - PNJ ») toujours là.
2. Le bouton ouvre « Radio Survivor - fréquences de cette partie » : six voix (cody, darlene, gus, nightowl, walt,
   whitaker) avec leurs fréquences en MHz, plages, « toute radio », heures d'écoute ; Whitaker « silencieuse » ;
   Night Owl « chroniqueur (bulletin) » ; second tableau : « Bulletin du soir », fréquence du Night Owl, heure.
3. Régler une radio sur la fréquence affichée de Walt et lui parler : il répond (fréquence fidèle).
4. Bouton « Actualiser », puis fermer et rouvrir la fenêtre : même contenu, aucune erreur Lua.

**MP (séance finale)** : client admin : même fenêtre ; client `user` : aucun bouton, et
`RS_FreqDebugView.state.window = {} RS_FreqDebugView.send()` → « Refusé ... », ligne serveur
`frequency debug: WARNING: request refused for <compte>`.

Écart à signaler : fréquence différente de celle où la voix répond, voix manquante, bouton visible sans droit, donnée
reçue sans droit, erreur Lua de `RS_FreqDebugView` ou `RS_FreqDebug`.
