# E19 — Banc hors jeu mimétique

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 1 / 8 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | E19-T01 | Table de l'API du jeu et doublures conformes | `à faire` | hors jeu | — |
| ☐ | E19-T02 | Appels du mod conformes à l'API 42.22 | `à faire` | hors jeu | E19-T01 |
| ☐ | E19-T03 | Doublures corrigées et nombre d'arguments contrôlé | `à faire` | hors jeu | E19-T01 |
| ☐ | E19-T04 | Potager sur le vrai Lua vanilla | `à faire` | hors jeu | LK15-T06 |
| ☐ | E19-T05 | Horloge fidèle et balayage des phases | `à faire` | hors jeu | — |
| ☐ | E19-T06 | Réseau en désordre dans les bancs multijoueurs | `à faire` | hors jeu | — |
| ☑ | E19-T07 | Règle de travail et registre des écarts | `testé hors jeu` | hors jeu | — |
| ☐ | E19-T08 | Site réel des campagnes rejoué au banc | `à faire` | hors jeu | E19-T03 |

<!-- fin du tableau de bord -->

**Mod (après la séparation).** les trois mods (bancs et outils du dépôt ; rien n'est livré aux joueurs).

**Objectif.** Que le banc hors jeu fasse l'essentiel de la validation : doublures contrôlées contre la vraie API du
jeu, vrai Lua vanilla, horloge et réseau fidèles, site réel rejoué. Le jeu ne sert plus qu'à confirmer.

**ADR.** [Banc hors jeu mimétique](../../architecture/decisions/adr-banc-mimetique.md) (accepté le 2026-11-13) ; ce
plan en est l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** E01 (moteur de tests en jeu, suites jouées au banc), banc Kahlua réel (`tests/test_kahlua.py`).

**Sources.** Inventaire du 2026-11-13 des 40 défauts vus seulement en jeu (ADR, section Contexte) ; sources de
référence 42.22 du poste de l'auteur ; `tests/harness.py`.

## Décisions

- 2026-11-13 — **E19** (utilisateur) : le banc hors jeu doit être assez mimétique pour faire l'essentiel du travail ;
  moyens délégués, décisions D01 à D08 de l'ADR confirmées par défaut.

## Hors périmètre

Rendu, animation, son, interface ; IA et chemins vanilla écrits en Java. Les campagnes en jeu restent, pour confirmer.

## Tâches

- [ ] **E19-T01** — Table de l'API du jeu et doublures conformes
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `tools/pz_api.py` (lecture des sources de référence) ; `tests/test_doubles_api.py` ; `tests/fixtures/doubles-api-baseline.txt` (cliquet)
  - Faire : ADR D01 : table classe exposée → méthodes publiques (héritées comprises) et nombres de paramètres, fonctions globales `@LuaMethod`, événements, lue sur le poste (jamais versionnée) ; banc qui relève les doublures de classes Java de `tests/harness.py` et des bancs (`H.class`, `C.<Classe>`, fonctions `function <Classe>:m`), et refuse une méthode absente du Java ; écarts existants dans une liste de référence qui ne peut que diminuer.
  - Accepté si : une doublure qui invente une méthode fait échouer le banc (test du contrôle lui-même) ; la liste de référence est produite et chiffrée ; banc sauté proprement sans les sources.
  - Tests : `python tests/test_doubles_api.py`.
  - Preuve : —
  - Reste : —
- [ ] **E19-T02** — Appels du mod conformes à l'API 42.22
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E19-T01
  - Fichiers : `tests/test_mod_calls_api.py` ; `tools/pz_api.py`
  - Faire : ADR D02 : contrôle statique du Lua des trois mods et du mod de test : méthodes appelées par `:` et fonctions globales appelées connues du Java exposé, du Lua vanilla ou du mod ; liste de référence en cliquet pour les faux positifs justifiés.
  - Accepté si : un appel à une méthode retirée en 42.22 (`dropHeldItems`) placé dans un fichier d'essai est refusé ; les trois mods passent.
  - Tests : `python tests/test_mod_calls_api.py`.
  - Preuve : —
  - Reste : —
- [ ] **E19-T03** — Doublures corrigées et nombre d'arguments contrôlé
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E19-T01
  - Fichiers : `tests/harness.py`, bancs `tests/test_*.py` cités par la liste de référence
  - Faire : ADR D01 : vider la liste de référence (doublure renommée, supprimée ou justifiée comme aide de test préfixée) ; les doublures de classe refusent un nombre d'arguments qu'aucune surcharge Java n'accepte.
  - Accepté si : liste de référence vide ou réduite aux aides de test nommées ; un appel à deux arguments d'une méthode à un paramètre échoue au banc comme en jeu (cas « expected 1 argument, got 2 » du 2026-10-11).
  - Tests : suite complète `python tests/run_all.py`.
  - Preuve : —
  - Reste : —
- [ ] **E19-T04** — Potager sur le vrai Lua vanilla
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK15-T06
  - Fichiers : `tests/harness.py` (chargement de fichiers vanilla) ; bancs du potager (`tests/test_lk_food.py`, `tests/test_lk_upkeep.py`, banc de `LK15`)
  - Faire : ADR D03 : charger `SFarmingSystem`, `SPlantGlobalObject`, les définitions des légumes et leurs dépendances depuis l'installation du jeu (`tools/pz_paths.py`) au-dessus des doublures Java ; rejouer arrosage, récolte, sillon et semis dessus ; bancs sautés sans le jeu.
  - Accepté si : sillon, semis, arrosage et récolte passent sur le Lua vanilla réel ; un écart avec les anciennes doublures est corrigé dans le mod ou consigné.
  - Tests : bancs du potager.
  - Preuve : —
  - Reste : —
- [ ] **E19-T05** — Horloge fidèle et balayage des phases
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `tests/harness.py` ; `tests/test_harness.py` ; bancs des suites jouées au banc (`SuiteTests`)
  - Faire : ADR D04 : `EveryHours` et `EveryDays` déclenchés par `advance()` dans l'ordre du Java ; aide de balayage qui rejoue un scénario avec l'heure décalée par pas (changement d'heure, de jour, passage à la nuit) ; suites en jeu jouées au banc passées sous le balayage, en commençant par `lk.meals`.
  - Accepté si : le défaut `lk.meals` du 2026-11-13 est attrapé par le balayage sans crochet écrit pour lui ; les suites balayées sont vertes.
  - Tests : `python tests/test_harness.py`, bancs des suites.
  - Preuve : —
  - Reste : —
- [ ] **E19-T06** — Réseau en désordre dans les bancs multijoueurs
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `tests/harness.py` ; bancs serveur + deux clients
  - Faire : ADR D06 : rejouer les bancs multijoueurs avec livraison aléatoire à graines fixes et changement de propriétaire du corps pendant l'action ; zone d'envoi des paquets liés à une case d'après le Java.
  - Accepté si : les cas « réponse avant la demande » et « cadavre non reçu après une téléportation » de l'inventaire sont reproduits au banc sur l'ancien code, verts sur le code actuel.
  - Tests : bancs multijoueurs.
  - Preuve : —
  - Reste : —
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
  - Fichiers : outil d'export en jeu (mod de test) ; `tests/harness.py` (monde chargé d'un export) ; export local non versionné
  - Faire : ADR D05 : exporter une fois le site des campagnes (cases, murs, portes et fenêtres avec leur état, pièces, conteneurs, lits), le charger comme monde du banc avec déchargement des cases loin des joueurs ; rejouer dessus les suites de déplacement et de foyer.
  - Accepté si : les cas « corps posé derrière une cloison » et « dépôt déchargé à 65 cases » de l'inventaire sont reproduits au banc ; bancs sautés sans l'export.
  - Tests : bancs sur le site exporté.
  - Preuve : —
  - Reste : l'export demande une session de jeu libre.
