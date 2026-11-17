# E19 — Banc hors jeu mimétique

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 7 / 8 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E19-T01 | Table de l'API du jeu et doublures conformes | `testé hors jeu` | hors jeu | — |
| ☑ | E19-T02 | Appels du mod conformes à l'API 42.22 | `testé hors jeu` | hors jeu | E19-T01 |
| ☑ | E19-T03 | Doublures corrigées et nombre d'arguments contrôlé | `testé hors jeu` | hors jeu | E19-T01 |
| ☑ | E19-T04 | Potager sur le vrai Lua vanilla | `testé hors jeu` | hors jeu | LK15-T06 |
| ☑ | E19-T05 | Horloge fidèle et balayage des phases | `testé hors jeu` | hors jeu | — |
| ☑ | E19-T06 | Réseau en désordre dans les bancs multijoueurs | `testé hors jeu` | hors jeu | — |
| ☑ | E19-T07 | Règle de travail et registre des écarts | `testé hors jeu` | hors jeu | — |
| ☐ | E19-T08 | Site réel des campagnes rejoué au banc | `à faire` | hors jeu | E19-T03 |

<!-- fin du tableau de bord -->

**Mod (après la séparation).** les trois mods (bancs et outils du dépôt ; rien n'est livré aux joueurs).

**Objectif.** Que le banc hors jeu fasse l'essentiel de la validation : doublures contrôlées contre la vraie API du
jeu, vrai Lua vanilla, horloge et réseau fidèles, site réel rejoué. Le jeu ne sert plus qu'à confirmer.

**ADR.** [Banc hors jeu mimétique](../../architecture/decisions/adr-banc-mimetique.md) (accepté le 2026-11-13) ; ce
plan en est l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** E01 (moteur de tests en jeu, suites jouées au banc), banc Kahlua réel (`tests/coreai/test_kahlua.py`).

**Sources.** Inventaire du 2026-11-13 des 40 défauts vus seulement en jeu (ADR, section Contexte) ; sources de
référence 42.22 du poste de l'auteur ; `tests/commun/harness.py`.

## Décisions

- 2026-11-13 — **E19** (utilisateur) : le banc hors jeu doit être assez mimétique pour faire l'essentiel du travail ;
  moyens délégués, décisions D01 à D08 de l'ADR confirmées par défaut.

## Hors périmètre

Rendu, animation, son, interface ; IA et chemins vanilla écrits en Java. Les campagnes en jeu restent, pour confirmer.

## Tâches

- [x] **E19-T01** — Table de l'API du jeu et doublures conformes
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `tools/pz_api.py` (lecture des sources de référence) ; `tests/coreai/test_doubles_api.py` ; `tests/commun/fixtures/doubles-api-baseline.txt` (cliquet)
  - Faire : ADR D01 : table classe exposée → méthodes publiques (héritées comprises) et nombres de paramètres, fonctions globales `@LuaMethod`, événements, lue sur le poste (jamais versionnée) ; banc qui relève les doublures de classes Java de `tests/commun/harness.py` et des bancs (`H.class`, `C.<Classe>`, fonctions `function <Classe>:m`), et refuse une méthode absente du Java ; écarts existants dans une liste de référence qui ne peut que diminuer.
  - Accepté si : une doublure qui invente une méthode fait échouer le banc (test du contrôle lui-même) ; la liste de référence est produite et chiffrée ; banc sauté proprement sans les sources.
  - Tests : `python tests/coreai/test_doubles_api.py`.
  - Preuve : 2026-11-13 : `tools/pz_api.py` (classes exposées, méthodes publiques héritées comprises, nombres de paramètres, constructeurs sous `new`, fonctions globales, événements, fonctions Lua vanilla ; lu sur le poste, rien de versionné) ; `tests/coreai/test_pz_api.py` (`Ran 10 tests … OK`, analyse Java sur des extraits écrits pour le test) ; `tests/coreai/test_doubles_api.py` : `76 classes contrôlées, 602 méthodes contrôlées, 21 fonctions globales contrôlées, 5 écarts (5 en liste de référence)`, `Ran 13 tests … OK` ; une méthode inventée sur `IsoZombie` est signalée, une méthode héritée d'`IsoGameCharacter` acceptée ; sans les sources : contrôle sauté avec le message de ce qui manque ; liste de référence `tests/commun/fixtures/doubles-api-baseline.txt` (5 lignes : `IsoGridSquare.Is` retirée en 42.22, `IsoZombie.getUsername`, `Literature.pageCount`, `ItemVisual.getTotalDirt`, `InventoryItem.getDeviceData`) ; le mod n'appelle pas `:Is(` (recherche du 2026-11-13) ; bancs inscrits dans `tests/run_all.py`
  - Reste : limite principale : les faux objets anonymes des bancs (tables Lua sans nom de classe, environ 1 400 définitions de méthodes) ne sont pas contrôlés, seuls le sont les objets marqués d'un nom de classe ; à traiter par `E19-T03` (contrôle à l'exécution dans `H.class`, faux objets rattachés à une classe) ; 8 formes dynamiques et les fonctions globales définies par les bancs non contrôlées ; liste des événements du harnais non comparée
- [x] **E19-T02** — Appels du mod conformes à l'API 42.22
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E19-T01
  - Fichiers : `tests/coreai/test_mod_calls_api.py` ; `tools/pz_api.py`
  - Faire : ADR D02 : contrôle statique du Lua des trois mods et du mod de test : méthodes appelées par `:` et fonctions globales appelées connues du Java exposé, du Lua vanilla ou du mod ; liste de référence en cliquet pour les faux positifs justifiés.
  - Accepté si : un appel à une méthode retirée en 42.22 (`dropHeldItems`) placé dans un fichier d'essai est refusé ; les trois mods passent.
  - Tests : `python tests/coreai/test_mod_calls_api.py`.
  - Preuve : 2026-11-13 : `tests/coreai/test_mod_calls_api.py` : `371 fichiers, 14183 appels de méthode contrôlés, 14184 appels globaux contrôlés, 0 écarts`, `Ran 16 tests … OK` ; `tests/coreai/test_pz_api.py` `Ran 22 tests … OK` ; analyse lexicale du Lua (commentaires et chaînes ignorés) et bibliothèque de base relevée dans Kahlua et `stdlib.lua` du jeu (`next`, `xpcall`, `load`, `dofile`, `rawlen` absents) dans `tools/pz_api.py` ; `obj:dropHeldItems(…)`, `sq:Is(x)` et `next(t)` sont signalés sur des extraits d'essai ; liste de référence `tests/commun/fixtures/mod-calls-api-baseline.txt` vide (les 40 faux positifs de la carte du monde venaient de classes exposées par délégation, absentes de l'index de la référence : suivies désormais) ; aucun défaut trouvé dans les trois mods ; banc inscrit dans `tests/run_all.py`
  - Reste : contrôle par union de noms : le type du receveur n'est pas connu (un nom retiré d'une classe et encore présent ailleurs passe), les appels `a.b(` et dynamiques ne sont pas vus, le nombre d'arguments non plus (`E19-T03`) ; pour aller plus loin : garder le type de retour des méthodes Java et propager les types dans les variables locales
- [x] **E19-T03** — Doublures corrigées et nombre d'arguments contrôlé
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E19-T01
  - Fichiers : `tests/commun/harness.py`, bancs `tests/<dossier>/test_*.py` cités par la liste de référence
  - Faire : ADR D01 : vider la liste de référence (doublure renommée, supprimée ou justifiée comme aide de test préfixée) ; les doublures de classe refusent un nombre d'arguments qu'aucune surcharge Java n'accepte.
  - Accepté si : liste de référence vide ou réduite aux aides de test nommées ; un appel à deux arguments d'une méthode à un paramètre échoue au banc comme en jeu (cas « expected 1 argument, got 2 » du 2026-10-11).
  - Tests : suite complète `python tests/run_all.py`.
  - Preuve : 2026-11-13 : `HARNESS.class` strict à l'exécution pour une classe exposée (méthode absente du jeu refusée à la définition avec le nom proche ; nombre d'arguments refusé comme Kahlua, « expected N argument(s), got M » ou « No implementation found » selon les surcharges ; méthode du jeu non doublée : erreur « doublure incomplète » ; méthodes statiques comptées sans `self`) ; `HARNESS.fake('Classe', {…})` pour les faux objets ; convention des aides de test : nom de classe terminé par `Double` ; table de l'API mise en cache hors du dépôt ; coût : 7,0 ms par `Harness()` au lieu de 6,1 ms ; cas réel du 2026-10-11 (`w:ToggleWindow(B().find(id))`, commit `9211603`) refusé au banc avec le message du jeu (`StrictDoublesTests.test_wrong_arity_refused_like_kahlua`) ; liste de référence vide (5 doublures fautives supprimées ou corrigées) ; 9 doublures de bancs fautives corrigées (méthodes inexistantes en Java, méthodes du jeu jamais doublées que le mod teste par `x.m ~= nil`) ; aucun défaut du mod ; `python tests/coreai/test_harness.py` : `Ran 43 tests … OK` ; `test_doubles_api.py` : `86 classes contrôlées, 630 méthodes contrôlées, 0 écarts`, `Ran 17 tests … OK` ; `test_mod_calls_api.py` 16 OK ; `test_pz_api.py` 23 OK ; `python tests/run_all.py` : `166 passed, 0 failed` (491 s, +37 s) ; luacheck `Contents` 8, `dev` 0
  - Reste : faux objets anonymes : 872 définitions sur receveurs sans classe (907 avant), plafond par fichier en cliquet dans `tests/commun/fixtures/doubles-api-baseline.txt` ; la plupart dans des bancs qui n'utilisent pas le harnais (carnet, protocole, module radio, suites RS) ; types des arguments non contrôlés, seulement leur nombre
- [x] **E19-T04** — Potager sur le vrai Lua vanilla
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK15-T06
  - Fichiers : `tests/commun/harness.py` (chargement de fichiers vanilla) ; bancs du potager (`tests/livingknox/test_lk_food.py`, `tests/livingknox/test_lk_upkeep.py`, banc de `LK15`)
  - Faire : ADR D03 : charger `SFarmingSystem`, `SPlantGlobalObject`, les définitions des légumes et leurs dépendances depuis l'installation du jeu (`tools/pz_paths.py`) au-dessus des doublures Java ; rejouer arrosage, récolte, sillon et semis dessus ; bancs sautés sans le jeu.
  - Accepté si : sillon, semis, arrosage et récolte passent sur le Lua vanilla réel ; un écart avec les anciennes doublures est corrigé dans le mod ou consigné.
  - Tests : bancs du potager.
  - Preuve : 2026-11-13 : `h.load_vanilla(machine, rel…)` (une exécution par machine comme le jeu, `require` vanilla résolus, saut propre sans le jeu ni les sources de référence) ; vrai Lua du potager chargé depuis l'installation du jeu dans l'ordre du jeu (`ISBaseObject`, `luautils`, curseurs de pelle et de retrait de plante, définitions des légumes et des herbes, `farmingCommands`, `SFarmingSystem`, `SPlantGlobalObject`, `SGlobalObject`, `SGlobalObjectSystem`, saisons, puis `OnSGlobalObjectSystemInit`), rien copié dans le dépôt ; doublures Java strictes du système d'objets globaux (refus du Java : case déjà prise, objet étranger, clé non chaîne) ; banc `tests/livingknox/test_lk_vanilla_farming.py` (7 tests OK) ; classes « vanilla réel » de `test_lk_garden.py` (arrosage, récolte avec repousse, sillon, cases refusées, semis, MP, suite `lk.garden`) et `test_lk_upkeep.py` (suite `lk.upkeep` sur une cour de terre, horloge des campagnes 3,75 s par minute) ; écarts trouvés avec les anciennes doublures : besoin en eau au semis, retrait d'une plante par l'événement du jeu, nom vanilla `Base.Strewberrie`, plante morte non recreusée en solo ; le défaut `lk.upkeep` de la campagne MP du 2026-11-13 est reproduit au banc (« upkeep jobs not all done ») et sa vraie cause trouvée : voir `LK15-T07` ; `python tests/run_all.py` : `167 passed, 0 failed` (561 s)
  - Reste : non reproduits : croissance sur des jours de jeu, maladies, pluie et saison réelles (posées par le banc), miroir client `CFarmingSystem` d'un client MP, sauvegarde du système de cultures, vrai `ISBuildingObject` ; anciennes doublures de `transmitRemoveItemFromSquare` (entretien, foyers) sans l'événement du jeu ; `LK_Job_Glass` déclenche `OnObjectAboutToBeRemoved` en plus du jeu (sans effet aujourd'hui) ; durée de la suite complète +70 s (dont 6 s expliquées)
- [x] **E19-T05** — Horloge fidèle et balayage des phases
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `tests/commun/harness.py` ; `tests/coreai/test_harness.py` ; bancs des suites jouées au banc (`SuiteTests`)
  - Faire : ADR D04 : `EveryHours` et `EveryDays` déclenchés par `advance()` dans l'ordre du Java ; aide de balayage qui rejoue un scénario avec l'heure décalée par pas (changement d'heure, de jour, passage à la nuit) ; suites en jeu jouées au banc passées sous le balayage, en commençant par `lk.meals`.
  - Accepté si : le défaut `lk.meals` du 2026-11-13 est attrapé par le balayage sans crochet écrit pour lui ; les suites balayées sont vertes.
  - Tests : `python tests/coreai/test_harness.py`, bancs des suites.
  - Preuve : 2026-11-13 : `advance()` de `tests/commun/harness.py` déclenche minute par minute `EveryDays`, `EveryHours`, `EveryTenMinutes`, `EveryOneMinute` dans l'ordre de `GameTime.update` (aucun sur une machine en pause), horloge lue pendant l'événement déjà à la nouvelle valeur ; `h.jump_to`, `h.skip` (heures manquées), doublures `getNightsSurvived` et `setTimeOfDay` ; surcouche `TIME_OF_DAY` des bancs supprimée (16 bancs) ; aide `tests/commun/phase_sweep.py` (9 phases : 1 à 30 minutes avant un changement d'heure, avant la nuit, avant minuit, avant l'aube ; un harnais neuf par phase, l'échec nomme la phase) ; suites passées sous balayage, vertes sur les 9 phases : `lk.meals`, `lk.provisions`, `lk.garden`, `lk.upkeep`, `lk.care`, `lk.chores`, `lk.expedition`, `lk.forage`, `lk.alert`, `lk.warn`, `lk.routines` ; bancs qui supposaient une horloge sans heures corrigés (double `EveryHours` à la main retiré, heures manquées par `h.skip`, boucles de `lk.chores` et `lk.routines` qui n'avançaient pas l'heure) ; `python tests/coreai/test_harness.py` : `Ran 33 tests … OK` ; `python tests/run_all.py` : `166 passed, 0 failed` (434 s, inchangé) ; `test_doubles_api.py` vert sans nouvelle ligne de référence ; luacheck `Contents` 8, `dev` 0 ; axe « monde déjà peuplé » du balayage (un groupe voisin de 3 membres incarné et déjà évalué par les vrais modules, à 40 cases) : cause du retard confirmée au banc (`LK_Decisions` ne refait la liste des membres incarnés que toutes les `ROSTER_MS` = 5 s quand elle n'est pas vide) ; l'ancienne suite `lk.meals` échoue sur `populated/hour-3` et `populated/hour-4` avec le message vu en jeu (« hungry member did not take an item »), la suite actuelle est verte ; onze suites vertes dans les deux mondes (20 rejeux chacune) ; test à crochet de `test_lk_meals.py` supprimé (cas couvert par le vrai mécanisme) ; `python tests/run_all.py` : `166 passed, 0 failed` (454 s, +20 s)
  - Reste : non reproduit : vitesse ×2 ou ×3 et sommeil (plusieurs minutes par image), jour d'un client reçu par le réseau, horloge propre à chaque machine ; un seul monde peuplé (un groupe de 3 : le tour à tour au-delà de 4 membres incarnés n'est exercé qu'en partie)
- [x] **E19-T06** — Réseau en désordre dans les bancs multijoueurs
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `tests/commun/harness.py` ; bancs serveur + deux clients
  - Faire : ADR D06 : rejouer les bancs multijoueurs avec livraison aléatoire à graines fixes et changement de propriétaire du corps pendant l'action ; zone d'envoi des paquets liés à une case d'après le Java.
  - Accepté si : les cas « réponse avant la demande » et « cadavre non reçu après une téléportation » de l'inventaire sont reproduits au banc sur l'ancien code, verts sur le code actuel.
  - Tests : bancs multijoueurs.
  - Preuve : 2026-11-13 : relevé Java 42.22 : commandes Lua `RELIABLE` non ordonnées dans les deux sens (`PacketTypes.java:611-613`), paquets du monde `RELIABLE_ORDERED` par canal, envois liés à une case filtrés par `UdpConnection.isRelevantTo` (88 cases pour une grille de 19) ; harnais : `SendZone` (position signalée par le client, livrée au pompage suivant), `HARNESS.sendToRelative` / `onPacket`, canaux ordonnés, `pump(delay=…)`, changement de propriétaire par le réseau (`set_owner(via_network=True)`) ; aide `tests/commun/net_disorder.py` (`fifo`, `lifo`, trois graines `random` avec retard, changement de propriétaire pendant la scène, l'échec nomme l'ordre) ; bancs sous désordre ou zone : `tests/radiosurvivor/test_rs_net_disorder.py` (vraie suite de parole du carnet), `test_mission_retrieve.py` (vraie suite `rs.mission.retrieve` sous la zone d'envoi), `test_lk_reports.py` (relève A→B→A pendant une marche), `test_lk_relay.py` (gestes périmés écartés) ; preuves sur le code d'avant le correctif `a469d1f` : `rs.npctalk` échoue sur `random-1` (« no npc_talk request »), `rs.mission.retrieve` échoue (« corpse of the spot not received »), les deux verts sur le code actuel ; `test_harness.py` 56 OK ; les 79 bancs qui utilisent le harnais verts un par un ; `test_doubles_api.py`, `test_mod_calls_api.py` verts ; commentaire trompeur de `LK_Reports.lua` (bail plus ancien « ignoré » alors qu'il est refusé) corrigé
  - Reste : non simulés : perte définitive d'un paquet non fiable (`ZombieList`), latence en temps réel, reconnexion, paquets de zombie et interpolation des copies (`lk.executor`), copie retirée d'un client sorti de zone (`LK03`) ; en 42.22 la copie serveur d'un joueur et sa zone viennent du même paquet, le banc déplace la copie aussitôt : le symptôme du 2026-11-05 est reproduit par le mécanisme de zone, pas forcément par le chemin exact
- [x] **E19-T07** — Règle de travail et registre des écarts
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/developpement.md` ; `docs/annexes/tests/ecarts-banc-jeu.md`
  - Faire : ADR D07, D08 : règle « un défaut vu en jeu se reproduit d'abord au banc » ; registre des 40 cas de l'inventaire avec catégorie et mécanisme de couverture.
  - Accepté si : règle écrite ; registre rempli et lié depuis l'index des documents.
  - Tests : `python tools/plan.py check`.
  - Preuve : 2026-11-13 : règle « le banc hors jeu fait l'essentiel, le jeu confirme » et « un défaut vu en jeu se reproduit d'abord au banc » dans `docs/developpement.md` (Méthode du plan) ; registre `docs/annexes/tests/ecarts-banc-jeu.md` : 41 lignes classées (1 couverte, 6 non reproductibles, 34 à couvrir), lié depuis l'ADR et `docs/developpement.md` ; `python tools/plan.py check` : 0 erreur
  - Reste : lien depuis `docs/README.md` à ajouter quand ses modifications en cours (autre session) seront commitées ; compte du registre à tenir à chaque tâche de `E19`
- [ ] **E19-T08** — Site réel des campagnes rejoué au banc
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E19-T03
  - Fichiers : outil d'export en jeu (mod de test) ; `tests/commun/harness.py` (monde chargé d'un export) ; export local non versionné
  - Faire : ADR D05 : exporter une fois le site des campagnes (cases, murs, portes et fenêtres avec leur état, pièces, conteneurs, lits), le charger comme monde du banc avec déchargement des cases loin des joueurs ; rejouer dessus les suites de déplacement et de foyer.
  - Accepté si : les cas « corps posé derrière une cloison » et « dépôt déchargé à 65 cases » de l'inventaire sont reproduits au banc ; bancs sautés sans l'export.
  - Tests : bancs sur le site exporté.
  - Preuve : outillage du 2026-11-14 : suite manuelle `site.export` (`dev/.../RST/suites/RST_SiteExport.lua` : cases chargées à 70 cases du joueur, niveaux 0 et 1, murs, portes, fenêtres, clôtures basses, escaliers, conteneurs, lits, un fichier texte `site-export.txt` copié dans le dossier du passage) ; lecture et chargement au banc `tests/livingknox/site_world.py` (registre des sortes d'enregistrement, doublures des murs, portes et fenêtres de `test_lk_obstacles.py`, cases hors de l'export ou loin des joueurs déchargées) ; `tests/commun/fixtures/local/` ignoré par Git ; `python tests/livingknox/test_site_replay.py` : `Ran 15 tests` / `OK (skipped=4)` (aller-retour de l'exporteur au banc, itinéraire par la porte puis évité une fois barricadée) ; `python tests/livingknox/test_lk_obstacles.py` : `Ran 177 tests` / `OK`
  - Reste : produire l'export en jeu (`python tools/autoclient/autoclient.py --save <partie rstest du site> --suite site.export --tags world --wait-idle 3600`, session libre), puis faire passer les 4 bancs sautés et écrire les cas « corps posé derrière une cloison » et « dépôt déchargé à 65 cases ».
