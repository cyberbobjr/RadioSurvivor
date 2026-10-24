# Radio Survivor — documentation

Voix radio jouées par une IA et groupes de survivants Living Knox pour Project Zomboid Build 42.21, serveur
autoritaire, solo et multijoueur. Ce dossier suit la structure commune des projets
(`Zomboid\Workshop\docs\structure-documentaire.md`) ; la documentation de développement est en français, le wiki en
anglais et en français.

## Documents

| Document | Rôle |
|---|---|
| [developpement.md](developpement.md) | Contraintes de développement du projet : périmètre, architecture à préserver, méthode du plan, écriture indépendante, dépôt |
| [architecture/](architecture/README.md) | Architecture logicielle : modules par côté, flux réseau, persistance, extensions, outillage |
| [architecture/ia-multijoueur.md](architecture/ia-multijoueur.md) | Analyse comparative de l'IA des PNJ en multijoueur (décision LK00-T02) |
| [architecture/decisions/](architecture/decisions/README.md) | Journal des décisions d'architecture et ADR |
| [specifications-fonctionnelles/](specifications-fonctionnelles/README.md) | Fonctionnalités `Fnn` vues par le joueur et l'administrateur |
| [specifications-techniques/](specifications-techniques/README.md) | Contrats : objets, commandes réseau, fichiers, options sandbox, traductions, API, protocole du pont |
| [ameliorations-et-idees.md](ameliorations-et-idees.md) | Améliorations de code et idées de fonctionnalités (propositions, sans autorisation d'implémenter) |
| [wiki/en/](wiki/en/Home.md), [wiki/fr/](wiki/fr/Home.md) | Source du wiki GitHub : guides joueur et administrateur, dont l'installation complète du pont (page 07) |
| [images/](images/) | `screenshots/` (captures du wiki), `art/maquettes/` (illustrations des maquettes) |
| [annexes/plans/](annexes/plans/README.md) | Plan d'implémentation (étapes `E` et `LK`, seule source des états), [SUIVI.md](annexes/plans/SUIVI.md) généré par `tools/plan.py suivi` |
| [annexes/conception/](annexes/conception/README.md) | Fiches de conception par sous-système (Living Knox, missions, secours, troc, carnet 0.2) |
| [annexes/tests/](annexes/tests/tests-en-jeu.md) | Tests en jeu RST ([tests-en-jeu.md](annexes/tests/tests-en-jeu.md)), validation du carnet 0.2, [zip de test local](annexes/tests/lisezmoi-test-local.md), mesures et essais datés ([validation/](annexes/tests/validation/)) |
| [annexes/recherches/](annexes/recherches/) | Analyses de Bandits! et de Project A-Life, idées reprises, ancien document de travail Bandits/LLM, investigation des dernières pages |
| [annexes/maquettes/](annexes/maquettes/) | Maquettes HTML (carnet, échanges, présentation), [fonctionnalites.html](annexes/maquettes/fonctionnalites.html) (page d'état publiée en artifact), [simulateur-pnj.html](annexes/maquettes/simulateur-pnj.html), [note-de-travail.html](annexes/maquettes/note-de-travail.html) |

À la racine du projet : [README.md](../README.md) (GitHub, anglais), [README_fr.md](../README_fr.md),
[CHANGELOG.md](../CHANGELOG.md), descriptions Workshop dans `workshop/`. Aucun fichier d'instructions d'agent dans
ce dépôt : les règles communes sont dans le dossier de développement parent, les contraintes du projet dans
[developpement.md](developpement.md).

## Anciens chemins

La documentation a été réorganisée le 2026-10-21. Les commentaires du code (`Contents/`) et du mod de tests (`dev/`)
citent encore les anciens chemins ; cette table donne leur équivalent.

| Ancien chemin | Nouveau chemin |
|---|---|
| `docs/plan/` | [`docs/annexes/plans/`](annexes/plans/README.md) |
| `docs/conception/` | [`docs/annexes/conception/`](annexes/conception/README.md) |
| `docs/validation/` | [`docs/annexes/tests/validation/`](annexes/tests/validation/) |
| `docs/maquettes/` | [`docs/annexes/maquettes/`](annexes/maquettes/) (illustrations : [`docs/images/art/maquettes/`](images/art/maquettes/)) |
| `docs/wiki/<Page>.md`, `docs/wiki/<Page>-FR.md` | `docs/wiki/en/NN-<page>.md`, `docs/wiki/fr/NN-<page>.md` (voir les barres latérales [en](wiki/en/_Sidebar.md), [fr](wiki/fr/_Sidebar.md)) |
| `docs/wiki/images/` | [`docs/images/screenshots/`](images/screenshots/) |
| `docs/api.md` | [`docs/specifications-techniques/api-living-knox.md`](specifications-techniques/api-living-knox.md) |
| `docs/protocole-carnet-v2.md`, `docs/persona-format.md`, `docs/reputation-contract.md`, `docs/passeur-table.md`, `docs/factions.md`, `docs/rescue.md`, `docs/notes-frequences.md` | même nom sous [`docs/specifications-techniques/`](specifications-techniques/README.md) |
| `docs/architecture-ia-multijoueur.md` | [`docs/architecture/ia-multijoueur.md`](architecture/ia-multijoueur.md) |
| `docs/adr-b17-chat-proximite-pnj.md` | [`docs/architecture/decisions/adr-b17-chat-proximite-pnj.md`](architecture/decisions/adr-b17-chat-proximite-pnj.md) |
| `docs/tests-en-jeu.md`, `docs/carnet-validation-04221.md` | même nom sous [`docs/annexes/tests/`](annexes/tests/tests-en-jeu.md) |
| `docs/LISEZMOI-test-local.md` | [`docs/annexes/tests/lisezmoi-test-local.md`](annexes/tests/lisezmoi-test-local.md) |
| `docs/carnet-implementation-04221.md` | [`docs/annexes/conception/carnet-implementation-04221.md`](annexes/conception/carnet-implementation-04221.md) |
| `docs/alife-analyse.md`, `docs/bandits-analyse.md`, `docs/bandits-llm-specifications.md`, `docs/idees-bandits-alife.md`, `docs/derniers-pages-cadavre.md` | même nom sous [`docs/annexes/recherches/`](annexes/recherches/) |
| `docs/fonctionnalites.html`, `docs/simulateur-pnj.html`, `docs/note-de-travail.html` | même nom sous [`docs/annexes/maquettes/`](annexes/maquettes/) |
| `docs/bridge-setup.md` | [`docs/wiki/en/07-bridge-server-setup.md`](wiki/en/07-bridge-server-setup.md) |
| `docs/installation-pont.md` | [`docs/wiki/fr/07-installation-du-pont.md`](wiki/fr/07-installation-du-pont.md) |

## Règles

- Un nouveau document prend sa place dans cette arborescence avant d'être écrit ; à défaut, dans un sous-dossier
  thématique d'`annexes/`. Mettre à jour cet index dans le même changement.
- Les images vont sous `images/` ; le wiki les cite par `../../images/screenshots/…`.
- Les pages du wiki se lient entre elles par liens relatifs `.md` ; un outil de synchronisation vers le dépôt
  `RadioSurvivor.wiki` doit les convertir en noms de pages du wiki (aucun outil n'existe encore dans ce projet).
