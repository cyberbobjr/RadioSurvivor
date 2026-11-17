# E27 — Recettes par la radio

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 1 / 5 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E27-T01 | Index des recettes exporté par le serveur | `testé hors jeu` | hors jeu | — |
| ☐ | E27-T02 | Section `[help]` des voix et réglages dans l'atelier | `à faire` | hors jeu | E27-T01 |
| ☐ | E27-T03 | Recherche dans la langue du joueur et réponse en personnage | `à faire` | hors jeu | E27-T02 |
| ☐ | E27-T04 | Délai, rappel, carnet et apprentissage | `à faire` | solo | E27-T03 |
| ☐ | E27-T05 | Wiki, exemples et CHANGELOG des recettes par la radio | `à faire` | hors jeu | E27-T04 |

<!-- fin du tableau de bord -->

**Mod.** RadioSurvivor (`batman_RadioSurvivor`) pour l'index, la fiche des voix, le délai et l'apprentissage ; le pont
(`bridge/`) pour la recherche et l'atelier.

**Objectif.** Une voix qui a un métier aide le joueur à trouver une recette, mods compris, dans sa langue, en
conversation ; selon la réputation, tout de suite ou après un délai, et parfois en lui apprenant la recette.

**ADR.** [Recettes par la radio](../../architecture/decisions/adr-recettes-radio.md), décisions D01 à D10
(2026-11-17).

**Dépend de.** E26.

## Décisions

- 2026-11-17 — **E27** (utilisateur) : architecture « manuel de la voix » ; question dans la langue du joueur, recherche
  en mots-clés anglais ; métiers dans une liste ; un palier de réputation par voix ; délai réglé par voix, le joueur
  rappelle ; la voix apprend la recette à réputation très haute.
- 2026-11-17 — **E27** (confirmé par défaut) : palier « tout le monde », « Neutre » ou « Bonne » ; apprentissage au
  niveau « Bonne », métiers de la voix seulement ; une recherche en attente par joueur et par voix ; index rangé dans
  RadioSurvivor ; entrée « Recette » au carnet ; noms traduits côté joueur, anglais à défaut.

## Hors périmètre

- Living Knox.
- Autres informations que les recettes (lieux, objets rares…).

## Tâches

- [x] **E27-T01** — Index des recettes exporté par le serveur
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : D02, D08 ; au démarrage du serveur, lire les recettes chargées (vanilla et mods) et écrire l'index dans le
    dossier d'échange : identifiant, nom anglais, catégorie, ingrédients, outils, niveau requis, à apprendre ou non,
    mod d'origine ; table des métiers (métier → catégories, « Débrouille » pour le reste) ; D11 : classe du pont qui
    lit l'inventaire à son lancement et le relit quand le serveur le refait ; spécification dédiée.
  - Accepté si : bancs de l'export (recette vanilla, recette de mod, recette à apprendre, catégorie inconnue →
    « Débrouille ») et du lecteur du pont ; taille et durée de l'export mesurées.
  - Preuve : 2026-11-17, `RS_RecipeCatalog` (recettes lues par `ScriptManager.getAllCraftRecipes`, ingrédients et produits en listes `items` ou `fluids`, fluides des récipients compris, en litres ; `RightClickOnly`, énergie, automatisation et « n'importe quel objet/fluide » écartés), `RS_RecipeJobs` (11 métiers, `makeshift` par défaut), `RS_Json` (ASCII, `\uXXXX`), `RS_RecipeIndex` (`batman_CoreAI/recipes.json` à `OnServerStarted` ou `OnGameStart`, une ligne de console nombre/octets/ms), classe `RecipeIndex` de `bridge/recipe_index.py` (lue au lancement du pont, relue quand l'heure ou la taille du fichier change, index précédent gardé si le fichier est illisible) ; `docs/specifications-techniques/index-recettes.md`. Bancs : `recipe_index` 14 tests OK, `recipe_index_bridge` 6 tests OK, luacheck 0 ; coût mesuré hors jeu : 965 recettes synthétiques ≈ 521 Ko, encodage ≈ 0,15 ms par recette dans la VM Kahlua du jeu (durée réelle : ligne de console au prochain passage en jeu) ; `python tests/run_all.py --mod radiosurvivor --keep-going` `Summary: 111 passed, 0 failed, 0 skipped` (259,7 s).

- [ ] **E27-T02** — Section `[help]` des voix et réglages dans l'atelier
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E27-T01
  - Faire : D02 à D04, D06 ; `[help]` : métiers, palier (tout le monde, Neutre, Bonne), délai (tout de suite, une
    heure, une demi-journée, un jour) ; mêmes règles et messages dans les lecteurs du serveur et du pont ; atelier :
    métiers à cocher, palier et délai en listes, mots simples ; voix livrées dotées de métiers quand leur personnage
    s'y prête.
  - Accepté si : bancs des lecteurs (métier inconnu, palier ou délai inconnus, mêmes messages des deux côtés), fiches
    livrées acceptées, atelier vérifié par `atelier_smoke`.

- [ ] **E27-T03** — Recherche dans la langue du joueur et réponse en personnage
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E27-T02
  - Faire : D01, D03, D10 ; l'IA signale une question de recette et donne des mots-clés anglais ; le pont cherche
    dans l'index, filtré par les métiers de la voix, et rend 3 à 5 recettes à un second appel qui répond en personnage
    dans la langue du joueur ; refus en personnage sous le palier ; rien trouvé dit sans inventer ; appels comptés dans
    les plafonds.
  - Accepté si : bancs du pont avec un faux modèle (question en français, ukrainien, coréen → bonne recette ; hors
    métier ; sous le palier ; rien trouvé) ; un essai avec le vrai modèle noté dans la preuve.

- [ ] **E27-T04** — Délai, rappel, carnet et apprentissage
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E27-T03
  - Faire : D04, D05, D06, D07, D09 ; le serveur garde une recherche en attente par joueur et par voix (heure de jeu
    où elle est prête), « pas encore trouvé » si le joueur rappelle trop tôt, réponse au rappel ; entrée « Recette »
    du carnet, noms traduits côté joueur ; recette à apprendre : `learnRecipe` au niveau « Bonne », sinon explication
    de ce qu'il faut pour l'apprendre ; réputation, délai et apprentissage décidés par le serveur.
  - Accepté si : bancs du serveur (trop tôt, à l'heure, question remplacée, apprentissage à « Bonne » seulement,
    recette hors métiers jamais apprise) ; en jeu : une recette demandée, « rappelle dans une heure », rappel après le
    délai, entrée au carnet, recette à apprendre apprise.

- [ ] **E27-T05** — Wiki, exemples et CHANGELOG des recettes par la radio
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E27-T04
  - Faire : page du wiki joueur et du wiki des serveurs (métiers, palier, délai), CHANGELOG, page des fonctionnalités.
  - Accepté si : wiki publié, `plan.py check` sans erreur.
