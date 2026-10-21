# Spécifications fonctionnelles de Radio Survivor

Ce que fait le mod `batman_RadioSurvivor` (version 0.3.0, Build 42.21) du point de vue du joueur et de l'administrateur.
Chaque fonctionnalité a un identifiant stable `Fnn` ; les numéros ne se réutilisent pas. L'état d'avancement (solo,
MP) vit dans [fonctionnalites.html](../annexes/maquettes/fonctionnalites.html) (colonnes recalculées par
`tools/features_status.py`) et dans le [suivi du plan](../annexes/plans/SUIVI.md) ; il n'est pas recopié ici.

| Page | Contenu |
|---|---|
| [radio-et-carnet.md](radio-et-carnet.md) | Voix radio, émission, carnet, missions, secours, troc, chronique, dernières pages, réputation (F01 à F15) |
| [living-knox.md](living-knox.md) | Groupes de survivants Living Knox (F20 à F31) |
| [administration.md](administration.md) | Pont LLM, options sandbox, outils d'administration, compatibilité (F40 à F45) |

Guides joueur et administrateur pas à pas : [wiki](../wiki/fr/Home.md). Contrats précis :
[spécifications techniques](../specifications-techniques/README.md).

## Principes visibles par le joueur

- Le **serveur décide de tout** : le modèle de langage écrit seulement des mots et choisit dans des listes fermées ;
  objets, fréquences, coordonnées, récompenses et réputation sont tirés et vérifiés par le serveur.
- **Sans le pont**, le jeu reste jouable : les voix répondent « Rien que des parasites... », les PNJ restent muets,
  mais les groupes Living Knox vivent normalement.
- **Solo et multijoueur** : même comportement ; en multijoueur, l'autorité est le serveur dédié (ou l'hôte).

## Fonctionnalités

| ID | Fonctionnalité | Étapes du plan |
|---|---|---|
| F01 | Réseau de six voix radio | E05 |
| F02 | Notes de fréquences dans le butin | E05 |
| F03 | Émettre depuis la fenêtre radio | E06 |
| F04 | Carnet de terrain (onglets Radio, Contacts, Missions, Réputation, Équipe) | E00, E03, E06 |
| F05 | Dialogue de proximité avec un PNJ (Ctrl+G) | E00, E03, LK11 |
| F06 | Actions des voix en liste fermée | E07 |
| F07 | Missions générées | E11 |
| F08 | Survivants à secourir | E12 |
| F09 | Le passeur de l'Ohio (troc) | E13 |
| F10 | Chronique du soir et mémorial | E14 |
| F11 | Dernières pages | E15 |
| F12 | Réputation | E04 |
| F13 | Parler fait du bien | E05-T15 |
| F14 | Initiatives et échanges entre PNJ | E08 |
| F15 | Relations, accords de faction, chef et départ | E09, E10 |
| F20 | Groupes et foyers | LK08 |
| F21 | Corps et gestes humains | LK02 |
| F22 | Exécution multijoueur des PNJ | LK03 |
| F23 | Déplacement et obstacles | LK04 |
| F24 | Perception, besoins, décisions et routines | LK05 |
| F25 | Combat | LK06 |
| F26 | Santé, mort et butin | LK07 |
| F27 | Vie hors écran et relève | LK09 |
| F28 | Récits | LK10 |
| F29 | Interactions avec les joueurs (sommations, aide, troc, vengeance, raids) | LK11 |
| F30 | API pour RadioSurvivor | LK12 |
| F31 | Fortification progressive | LK14 |
| F40 | Pont LLM et fournisseur d'IA | E05, E16 |
| F41 | Options sandbox | toutes |
| F42 | Fenêtre d'administration et fiche d'un PNJ | LK13 |
| F43 | Fiches de voix éditables par l'admin | E05 |
| F44 | Compatibilité et prérequis | E16, E17 |
| F45 | Tests en jeu automatiques (développement) | E01, LK13 |

## Limites connues (version 0.3.0)

- Version de test : de nombreuses fonctionnalités sont validées hors jeu ou en solo seulement ; la validation MP passe
  par la campagne automatique (règle « les tests font foi » du 2026-10-14).
- Une nouvelle partie est recommandée ; les états `RS_State` et les registres Living Knox d'un autre schéma bloquent
  l'écriture plutôt que d'être écrasés.
- Les PNJ n'utilisent pas de véhicules (reporté, [LK00](../annexes/plans/LK00-cadrage.md)).
- Incompatible avec Bandits! et Project A-Life.
