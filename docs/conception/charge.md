# Mesure de charge

- Tâches : LK13-T02 (création), LK13-T12 (ordre des abonnés gardé)
- Build : 42.21.0 — Date : 2026-10-12 — Statut : brouillon
- Idée : I1.5 (budget de réflexion selon la distance et le combat, mesuré par tick), voir
  [idees-bandits-alife.md](../idees-bandits-alife.md) ; seule la **mesure par tick** est faite ici, le budget de
  réflexion par distance reste une proposition (résultats, § « Points chauds »).

## Problème

Savoir ce que coûte le moteur Living Knox avec 5 groupes et 4 joueurs : temps du serveur par image et par module, coût
chez le propriétaire d'un corps et chez un observateur, trafic réseau, taille de l'état sauvegardé ; fixer des
budgets et repérer les points chauds avant la séance multijoueur finale. Le jeu ne fournit aucun profileur Lua ; la
mesure doit tourner dans une partie normale, sans rien changer au comportement du moteur.

Code : `shared/LivingKnox/LK_Load.lua` (mesure, toute machine), requête `load` de `server/LivingKnox/LK_Admin.lua`
(départ, rapport, arrêt par un administrateur), suite `lk.load` (`dev/.../RST_LKLoad.lua`), banc hors jeu
`tools/load_bench.py`. Résultats : [charge-hors-jeu-2026-10-12.md](../validation/charge-hors-jeu-2026-10-12.md) ;
protocole en jeu : [charge-protocole.md](../validation/charge-protocole.md).

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Seule horloge exposée à Lua : `getTimestampMs()` (pas de 1 ms) ; une moyenne sur beaucoup d'appels est l'estimation, un maximum est une borne à la milliseconde près | base `kahlua-lua.md` ; `RST_LKProbe.lua` (LK02-T08) | confirmé statiquement |
| Un abonné ajouté pendant le déclenchement de son événement est appelé aussitôt ; un abonné retiré depuis l'abonné courant ne décale rien | base `kahlua-lua.md` ; `Event.java:52-62` (boucle reproduite par `tests/harness.py`) | confirmé statiquement |
| `OnTickEvenPaused` précède `OnTick` dans une même image ; `OnTick` ne part pas sur un serveur vide en pause | base `kahlua-lua.md`, `logs-and-tools.md` | confirmé statiquement |
| Serveur dédié à 10 images par seconde (100 ms par image) | base `multiplayer.md` (`GameServer.FPS`) | confirmé statiquement |
| Envelopper une globale Java surchargée (`sendServerCommand` avec ou sans joueur) : transmettre `...` tel quel | base `kahlua-lua.md` | confirmé statiquement |
| Kahlua est environ 3,6 fois plus lent que lupa (Lua 5.1 en C) sur le chemin d'écriture d'un registre (encodage RSV2, hex, somme, relecture) | `tools/load_bench.py --kahlua` (VM de `projectzomboid.jar`, 2026-10-12 : 99-100 ms contre 27-28 ms) | mesuré hors jeu |
| Écriture du registre des groupes regroupée (LK13-T06) : encodage, hex par table, somme par blocs, sans relecture ; le rapport dépend du code (environ 3 ici) | `tools/load_bench.py --kahlua`, seconde ligne (2026-10-12 : 31,9-32,6 ms Kahlua contre 10,8-11,3 ms lupa) ; [charge-groupes-2026-10-12.md](../validation/charge-groupes-2026-10-12.md) | mesuré hors jeu |
| `table.sort` de Kahlua est un tri rapide écrit en Lua (`stdlib.lua`) : un comparateur Lua coûte un appel par comparaison ; trier des textes calculés une fois (LK13-T10, `RS_Codec`) donne les mêmes octets, encodage environ 17 % plus rapide en Kahlua | base `kahlua-lua.md` ; [charge-registre-pnj-2026-10-12.md](../validation/charge-registre-pnj-2026-10-12.md) | mesuré hors jeu |

## Choix

- **Enveloppes posées une fois, gardées ensuite.** Chaque abonné du moteur (`LivingKnox.handlers`, clés
  `<événement>/<Module>.<nom>`) est remplacé par une enveloppe qui lit l'horloge avant et après l'appel (mêmes
  arguments, mêmes valeurs rendues, aucun `pcall`). Hors session elle appelle directement l'original : l'arrêt ne
  retire rien, une nouvelle session réutilise les enveloppes sans `Remove`/`Add`. Pose différée : les abonnés de tous
  les événements sauf `OnTickEvenPaused` au premier `OnTickEvenPaused` suivant le départ, ceux d'`OnTickEvenPaused`
  au premier `OnTick` : jamais un abonné appelé deux fois ni sauté dans l'image de pose (vérifié par le banc). Les
  abonnés du module de mesure (`Load.*`) ne sont jamais enveloppés. Un module rechargé remplace son enveloppe et
  n'est plus mesuré jusqu'au départ suivant. **Ordre gardé** (LK13-T12) : `LivingKnox.subscribe` et
  `LivingKnox.requeue` notent le rang de chaque `Add` (`LivingKnox.handlerSeq`) ; par événement, à partir du premier
  abonné à envelopper, les abonnés du moteur (enveloppes neuves, enveloppes déjà posées, abonnés `Load.*`) sont
  retirés puis rajoutés en fin de liste **dans cet ordre réel**, pas dans l'ordre alphabétique des clés. Les remises
  en fin de liste du premier `OnTickEvenPaused` (`Groups.flush`, `Store.flush`) passent par `LivingKnox.requeue`, qui
  déplace aussi l'enveloppe de mesure : même place avec ou sans mesure. Banc `tools/load_bench.py` (`run_compare`,
  `tests/test_lk_load.py`, `BenchOrderTests`) : mêmes registres (PNJ, groupes, attitudes) et même nombre
  d'écritures par en-tête avec et sans mesure, mesure démarrée après la mise en route ou avant la première image.
  Limite : un abonné inscrit hors de `LivingKnox.subscribe` (autre mod, vanilla, code RadioSurvivor qui appelle
  `Events.X.Add` directement) peut se retrouver avant les abonnés du moteur déplacés.
- **Image** : temps des abonnés mesurés entre deux passages du compteur (`OnTick/Load.counter`) ; moyenne et maximum
  par image, par module (somme de ses abonnés) et par abonné. **Fenêtre** de `WINDOW_MS` = 60 s réelles par défaut
  (1 à 600 s) : dernière fenêtre close gardée, fenêtre de pointe des envois ; ligne de journal à chaque fenêtre close
  si la session le demande (`log = true`).
- **Réseau** : commandes du module `LivingKnox` envoyées (enveloppe de `sendServerCommand` sur l'autorité, de
  `sendClientCommand` sur un client MP, posée au départ, retirée à l'arrêt si elle est encore en place) et reçues
  (abonné permanent), par commande, à un joueur ou à tous, taille approchée (chaînes, 8 par nombre, 2 par table).
- **Écritures des registres** : enveloppe de `LivingKnox.Store.writeSlotFile` (PNJ `LKREG1`, groupes `LKGRP1`,
  attitudes `LKATT1`) : nombre, temps moyen et maximum par écriture.
- **Taille de l'état** (autorité, au rapport seulement : un encodage complet) : octets RSV2 × 2 (fichiers en hex) des
  trois registres, champs de groupe les plus lourds, nombre de groupes, membres, entrées de journal et de stock.
- **Accès** : sur l'autorité, requête d'administration `{ op = "load", action = "start" | "report" | "stop", windowMs,
  log }`, même contrôle que les autres (`PopmanManage` vérifié à chaque requête, refus sans donnée) ; réponse au seul
  demandeur `{ action, running, lines }` (40 lignes au plus), rapport et arrêt écrits aussi au journal du serveur
  (`[LivingKnox] INFO load: …`). Client MP : `LivingKnox.Load.ask(action)` envoie la requête et imprime la réponse ;
  `LivingKnox.Load.start()` / `.print()` / `.stop()` mesurent la machine locale (console du mode debug). Solo : les
  mêmes fonctions, ou la suite `lk.load`.
- **Budgets proposés** (`Load.BUDGET`, à confirmer par la mesure en jeu, détail dans les résultats) : autorité 2 ms par
  image en moyenne, 25 ms au plus pour une image, 0,5 ms par module, 40 messages et 8 Ko envoyés par seconde, 1 Mo par
  fichier de registre ; client 1 ms par image, 8 ms au plus, 0,5 ms par module, 5 messages et 1 Ko envoyés par
  seconde. Le rapport finit par `budget: ok` ou `budget: OVER …`.

## Pas horaire étalé (LK13-T09)

Point chaud 3 de LK13-T02 : les abonnés `EveryHours` (simulation, besoins, notation des objectifs, attitudes) partaient
tous dans la même image, qui portait aussi les abonnés de la minute (`GameTime.update` déclenche `EveryHours` puis
`EveryTenMinutes` et `EveryOneMinute` dans la même mise à jour, base `api-42-21.md`) et l'écriture du registre.

- **Dans l'image de l'heure** (`Simulation.runNow`, abonnés de `LK_Server.lua`) : population, simulation hors écran et
  besoins. Ils avancent les jauges des membres que les membres incarnés modifient en place à chaque image (peur montée
  par `Needs.perceive`, repas réels par `Needs.relieve`), bornées à 0..100 : les décaler change l'ordre de ces
  écritures, donc les jauges (essai au banc de charge : un groupe incarné diverge en trois heures de jeu). Logique
  pure, peu coûteuse au banc (0,3 et 0,1 ms lupa pour 5 groupes).
- **Une passe par image ensuite** (`Simulation.defer`, file de `LK_Simulation.lua`) : notation des objectifs
  (`Decisions.onEveryHours(heure)`, la passe la plus lourde : 2,4 ms lupa en moyenne, 8,7 au plus) puis déclin des
  attitudes, avec l'heure de jeu lue à l'`EveryHours` ; à partir de l'image suivante (marque effacée au début de
  l'image, `OnTickEvenPaused` : l'`EveryHours` du jeu part avant l'`OnTick` de son image), puis une image pour
  l'écriture seule. Une erreur dans une passe est journalisée (`ERROR simulation: hourly pass <nom> failed`) sans
  arrêter la suivante.
- **Une seule écriture** du registre des groupes pour tout le pas (écriture retenue `Groups.hold("hour")`,
  [groupes.md](groupes.md)), dans une image à elle (après la relecture du stock de la même minute, qui retient aussi).
- **Même résultat** : mêmes passes, même ordre, même heure. Banc `tests/test_lk_spread.py` : registre et journal
  identiques à l'octet entre l'ancien chemin (tout dans l'image de l'heure) et le nouveau, sur 30 heures du banc léger
  et 3 heures du banc de charge complet ; une journée complète du banc de charge mesurée à l'identique (validation
  `etalement-2026-10-12.md`).
- **Heure nouvelle avec une file non vide** (accéléré du temps en solo : un `EveryHours` par mise à jour, banc qui
  déclenche sans image) : les passes restantes de l'heure précédente partent d'abord, dans l'ordre ; seul
  `Raids.survey`, inscrit avant, passe alors devant elles. `OnSave` (solo) vide la file et écrit.
- **Écarté** : étaler aussi la simulation et les besoins (résultats changés, voir plus haut) ; découper la simulation
  par groupe (les événements et combats du jour lisent tous les groupes de la même heure) ; une file à budget en ms
  (horloge à la milliseconde en jeu, `getTimestampMs` : base `kahlua-lua.md`).

## Pointes du passage des membres et du relevé de la minute (LK13-T11)

Points chauds restants de LK13-T09 (`Decisions.tick` 7 à 13 ms lupa, `Fortify.onEveryOneMinute` 10 à 23 ms), profilés
au banc de charge en enveloppant chaque fonction des modules `LivingKnox.*` (temps inclusif par image) :

- **`Decisions.tick`** : la moitié du passage de 4 membres était la **copie profonde des types de groupe**
  (`GroupTypes.get`, une trentaine d'appels par passage : `Hostility.startFor` pour chaque joueur et chaque groupe,
  `Decisions.allowedOf`, `Hostility.firstStrike`, `Decisions.groupInput`). Lecture en place `GroupTypes.peek`
  (lecture seule, même règle que `Groups.peek`, contrôlée par la lecture du code de `tests/test_lk_groups.py`) dans
  ces quatre appelants : pointe 9,5 → 3,8 ms lupa, moyenne 0,15 → 0,06 ms par image, mêmes décisions.
  **Passage étalé (2026-10-15, décision : déterminisme du nouveau code seulement)** : `PASS_MS` (1000) et
  `MEMBERS_PER_PASS` (4) gardés, mais les membres choisis par un passage sont évalués `MEMBERS_PER_FRAME` (1) par
  image (`Decisions.memberStep`), le premier dans l'image du passage, les suivants aux images qui suivent (300 ms au
  plus sur un serveur dédié) : même fréquence par membre (un passage de `MEMBERS_PER_PASS = 1` toutes les 250 ms,
  proposé d'abord, évaluait quatre fois plus souvent les membres d'un petit groupe), coût d'une image borné à un
  membre. L'ordre des écritures en place des membres (peur, repas) change : décisions non identiques à l'octet à
  l'ancien code, identiques d'un passage du banc à l'autre (`tests/test_lk_peaks.py`, `DecisionSpreadTests`).
- **Notation de l'heure étalée** (2026-10-15) : la passe différée `Decisions.onEveryHours` (image qui suit l'heure)
  ne note plus tous les groupes : elle les met en file (`Decisions.hourQueue`, ordre trié) et un groupe matérialisé
  est noté par image à partir de l'image suivante, avec l'heure de la passe ; écriture retenue
  (`Groups.hold("decisions")`). Un membre évalué entre-temps ne déclenche plus la notation « à l'arrivée » de son
  groupe si la notation horaire l'attend (`Decisions.hourScoringPending`) : il garde quelques images l'objectif et
  les postes de l'heure précédente. Heure nouvelle, `OnSave` et `Simulation.finishHour` font d'abord les notations
  restantes (`Decisions.finishHourQueue`).
- **`Fortify.onEveryOneMinute`** : relevés des plans expirés en file, un par image, avec l'heure de la minute
  ([fortification.md](fortification.md) § 10.4).

## Décisions à confirmer

- LK13-T11 : `GroupTypes.peek` ajouté dans `LK_GroupTypes.lua` et utilisé par `LK_Hostility.lua` (hors des fichiers
  annoncés de la tâche) : le coût venait de là, aucun résultat changé.
- Mesure ouverte au droit `PopmanManage` (celui des outils d'administration, LK13-T01) plutôt qu'à `DebugConsole`.
- Budgets ci-dessus (proposés sur la mesure hors jeu et le facteur Kahlua ; le maximum par image est le plus incertain).
- Coût compté par image du serveur ; un client à 60 images par seconde a ses propres images (le banc les cadence
  comme le serveur).

## Limites

- La mesure ajoute deux lectures d'horloge par appel d'abonné (négligeable devant `getTimestampMs`, à vérifier en jeu).
- `getTimestampMs` en jeu : les coûts sous la milliseconde ne valent qu'en moyenne ; le maximum par image est arrondi.
- Ce qui n'est pas un abonné du moteur n'est pas mesuré : code appelé par un autre mod, fenêtres ISUI (`render`),
  Java déclenché par le moteur (chemins, animations).
- La taille réseau est approchée ; le Java sérialise autrement (`TableNetworkUtils`).
