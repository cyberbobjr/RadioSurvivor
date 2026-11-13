# ADR — Banc hors jeu mimétique

| | |
|---|---|
| Date | 2026-11-13 (création, acceptation) |
| Statut | Accepté (utilisateur, 2026-11-13 : « arrange-toi pour que le moteur de test pour les tests offline soit suffisamment mimétique pour que la simulation offline fasse l'essentiel du travail » ; les moyens sont délégués, décisions ci-dessous confirmées par défaut) |
| Décideur | utilisateur |
| Portée | bancs hors jeu des trois mods (`tests/harness.py`, `tests/test_*.py`, banc Kahlua `tests/kahlua/`), outils `tools/`, règle de travail de `docs/developpement.md` ; aucun fichier livré aux joueurs |
| Plan associé | [E19 — Banc hors jeu mimétique](../../annexes/plans/E19-banc-mimetique.md) (suivi des tâches dans le plan) |
| Références | inventaire du 2026-11-13 des défauts vus seulement en jeu (ci-dessous) ; sources de référence 42.22 du poste de l'auteur (Java décompilé, Lua vanilla, index des classes exposées et des fonctions Lua) ; [méthode du plan](../../annexes/plans/README.md) |

## Contexte

Les campagnes en jeu occupent le poste (un seul jeu à la fois, le joueur ne peut pas jouer pendant ce temps) et durent
de vingt minutes à plus d'une heure. L'utilisateur veut que le banc hors jeu fasse l'essentiel de la validation et que
le jeu ne serve plus qu'à confirmer.

Inventaire du 2026-11-13 (plans, commentaires des suites en jeu, commits) : 40 défauts découverts seulement en jeu
alors que les bancs étaient verts.

| Catégorie d'écart entre le banc et le jeu | Cas | Exemples |
|---|---|---|
| E. Monde réel (murs, portes et fenêtres verrouillées, cases déchargées, zombies de la partie) | 12 | corps posé derrière une cloison, dépôt déchargé à 65 cases, garde en ronde qui tire pendant une autre scène |
| F. Réseau (propriétaire du corps, ordre et zone d'envoi des paquets) | 6 | cadavre jamais reçu par un client téléporté, réponse livrée avant la demande |
| D. Temps et ordre des événements (heure, nuit, budget horaire, passe périodique) | 5 | `lk.meals` du 2026-11-13 : heure changée entre la faim posée et la première décision |
| B. API Java au comportement différent de la doublure | 5 | `isFree` sur serveur dédié, zombie recyclé resté `useless`, identifiant qui déborde du `short` |
| C. Lua et IA vanilla | 5 | fenêtre refermée par le geste vanilla, multiplicateur d'XP ×0,25, chemin vanilla par la fenêtre |
| I. Défaut du test en jeu lui-même | 3 | lecture unique trop tôt, joueurs de test qui bouchent un couloir |
| A. API Java absente, renommée ou de signature différente | 2 | `getGameMode()` devenu objet en 42.22, « expected 1 argument, got 2 » |
| H. Rendu, animation, son | 2 | bulle non dessinée, animation d'ouverture absente |
| G. Particularité de la VM Kahlua | 0 | déjà couvert par le banc Kahlua réel (`tests/test_kahlua.py`) |

Constat sur le banc actuel : les doublures Java sont écrites à la main, références Java en commentaire, sans contrôle
automatique ; les systèmes Lua vanilla (potager) sont réécrits en doublure ; le monde est une carte fictive de cases
libres ; `advance()` déclenche les minutes, pas les événements horaires au milieu d'une scène ; le réseau sait déjà
livrer dans le désordre (`pump(order='random')`) mais peu de bancs l'emploient.

## Décisions

- **D01 — Doublures conformes à l'API Java, contrôlées automatiquement.** Un outil lit les sources de référence 42.22
  (classes exposées à Lua, méthodes publiques héritées comprises, nombre de paramètres de chaque surcharge) et un banc
  compare chaque doublure de classe Java : une méthode qui n'existe pas dans la classe, ou appelée dans le banc avec un
  nombre d'arguments qu'aucune surcharge n'accepte, fait échouer le banc. Même contrôle pour les fonctions globales
  doublées (`@LuaMethod`) et les événements. Les écarts existants entrent dans une liste de référence qui ne peut que
  diminuer (cliquet), puis sont corrigés. Vise les catégories A et une partie de B.
- **D02 — Appels du mod conformes.** Contrôle statique du Lua des trois mods : chaque `objet:methode(` doit nommer une
  méthode d'une classe exposée, une fonction du Lua vanilla ou une fonction du mod ; chaque fonction globale appelée
  doit exister (index `@LuaMethod`, Lua vanilla, mod). Rejoue le diff d'API à chaque montée de version du jeu. Vise A.
- **D03 — Le vrai Lua vanilla plutôt qu'une doublure.** Quand le mod s'appuie sur un système écrit en Lua par le jeu
  (potager `SFarmingSystem`, définitions des légumes, actions), le banc charge les fichiers vanilla de l'installation du
  jeu (chemins de `tools/pz_paths.py`, comme le banc Kahlua) au-dessus des seules doublures Java nécessaires. Premier
  système : le potager. Vise C (la part Lua).
- **D04 — Horloge du jeu fidèle et balayage des phases.** `advance()` déclenche `EveryHours` et `EveryDays` à leur
  place dans l'ordre du Java (`GameTime.update`) ; une aide rejoue un scénario avec l'heure de jeu décalée par pas
  (changement d'heure, de jour, nuit) et les suites en jeu jouées au banc passent sous ce balayage. Vise D et I.
- **D05 — Site réel rejoué.** Un export du site des campagnes (cases, murs, portes et fenêtres avec leur état,
  pièces, conteneurs, lits) est produit une fois par le jeu et chargé par le banc comme monde, avec des cases qui se
  déchargent loin des joueurs. L'export décrit un bâtiment du jeu : il reste **local, jamais versionné** (comme
  `tests/kahlua/ecj.jar`), et les bancs qui en dépendent sont sautés s'il manque. Vise E. Demande une session de jeu
  libre : dernière étape.
- **D06 — Réseau en désordre par défaut dans les bancs multijoueurs.** Les bancs serveur + deux clients des suites se
  rejouent avec livraison aléatoire à graines fixes et changement de propriétaire du corps pendant l'action ; la zone
  d'envoi d'un paquet lié à une case (cadavre, objet) est simulée d'après le Java. Vise F.
- **D07 — Un défaut vu en jeu se reproduit d'abord au banc.** Règle de travail ajoutée à `docs/developpement.md` : tout
  échec de campagne est classé (catégories ci-dessus), reproduit au banc par un test rouge quand la catégorie le
  permet, puis corrigé ; si le banc ne peut pas le reproduire, le manque est consigné dans le registre de D08.
- **D08 — Registre des écarts.** `docs/annexes/tests/ecarts-banc-jeu.md` tient la liste des défauts vus seulement en
  jeu, leur catégorie et le mécanisme du banc qui les couvre désormais (ou « non reproductible »). Il mesure le
  progrès : la part des catégories A, B, D, F et I couverte par le banc.

## Hors périmètre

- Catégorie H (rendu, animation, son, interface) et la part Java de C (IA et chemins vanilla) : non simulées. Elles
  restent validées en jeu ; le banc les signale comme telles.
- Aucun remplacement des campagnes en jeu : elles confirment, moins souvent.
- Aucune donnée tirée du code décompilé n'entre dans le dépôt (public) : l'outil de D01 et D02 lit les sources sur le
  poste et le banc est sauté quand elles manquent.

## Alternatives écartées

| Alternative | Pour | Contre | Verdict |
|---|---|---|---|
| Garder les doublures écrites à la main, relues à chaque tâche | Aucun outil à écrire | L'inventaire montre que la relecture ne suffit pas ; rien ne signale une API changée par une mise à jour du jeu | écartée |
| Exécuter le vrai Java du jeu hors écran (JVM du jeu sans fenêtre, monde chargé) | Fidélité maximale | Le moteur ne démarre pas sans son environnement natif et graphique ; coût et fragilité élevés ; un serveur dédié reste « le jeu » et occupe le poste | écartée |
| Tout passer au banc Kahlua réel | VM identique | Ne règle que la catégorie G, déjà couverte ; les doublures Java restent nécessaires | complément, pas réponse |
| **Contrôles automatiques contre les sources de référence, Lua vanilla réel, horloge et réseau fidèles, site réel exporté** | Vise 28 des 40 cas ; chaque mécanisme se livre seul | Travail d'outillage ; le site réel demande une session de jeu | **retenue** |

## Conséquences

- Les bancs D01 à D03 dépendent de fichiers présents sur le poste de l'auteur (sources de référence, installation du
  jeu) : sautés ailleurs, avec un message qui dit ce qui manque.
- Une montée de version du jeu se contrôle hors jeu avant toute campagne (D01, D02).
- Le coût d'écriture d'une doublure augmente (elle doit exister dans le Java) ; le coût d'une campagne ratée baisse.
