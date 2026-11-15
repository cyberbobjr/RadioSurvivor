# ADR — Atelier des voix : créer et corriger les voix radio sans écrire de fiche

| | |
|---|---|
| Date | 2026-11-15 |
| Statut | Accepté |
| Décideur | utilisateur |
| Plan associé | [E22 — Atelier des voix](../../annexes/plans/E22-atelier-voix.md) |
| Références | Maquettes et comparaison : artefact « Atelier des voix » (https://claude.ai/artifact/GFFcsBVMpmRD6bRXphDss5) ; format des fiches `docs/specifications-techniques/persona-format.md` ; ADR [voix déclarées](adr-personas-declaratives.md) |

## Contexte

Depuis E20, une voix radio tient entière dans une fiche texte `personas/<id>.txt` : en-tête, lieux, missions,
récompenses, catégories, troc, note de fréquence et personnalité en anglais. Une fiche fait 80 à 130 lignes, une
cinquantaine de clés, des coordonnées, des noms de script d'objets et des identifiants qui se répondent d'une section à
l'autre. Une erreur fait refuser la fiche et ne se lit que dans `console.txt`. Le serveur relit le dossier de travail
`Zomboid/Lua/batman_RadioSurvivor/personas/` toutes les 30 s.

L'utilisateur veut un outil pour un adolescent qui crée des voix, des personnalités et des missions : Windows, Linux et
macOS, tout ajouter, modifier, corriger et supprimer, simple à utiliser. Quatre solutions ont été maquettées et
comparées (page web hors ligne, atelier servi par le pont, atelier dans le jeu, atelier du pont avec relevé de lieux en
jeu).

## Décisions

- **D01 — Atelier servi par le pont, relevé des lieux en jeu** (solution D, utilisateur, 2026-11-15). Le pont Python
  ouvre l'atelier dans le navigateur ; le mod ajoute seulement un clic droit qui relève un lieu. **Rester simple**
  (utilisateur) : bibliothèque standard Python, HTML et JavaScript sans framework ni étape de construction, écoute sur
  `127.0.0.1` seulement, un lanceur par système (`.bat`, `.sh`, `.command`).
- **D02 — L'atelier écrit dans le dossier de travail des fiches.** Jamais dans le dossier du mod. Le jeu relit la fiche
  en 30 s, sans redémarrage. Les règles existantes s'appliquent : une fiche livrée modifiée est gardée ; « revenir à la
  version livrée » supprime le fichier, que le jeu recopie au chargement suivant ; « retirer » une voix livrée vide la
  fiche (seule façon que le jeu connaît) ; une voix créée par le joueur se supprime.
- **D03 — Le jeu reste le seul juge d'une fiche.** L'interface empêche la plupart des erreurs par construction (listes,
  cartes, plages) à partir d'un **catalogue** (types de mission et leurs paramètres, natures de récompense, catégories,
  actions, plages de fréquence prises) **généré depuis le mod** et tenu à jour par un test ; aucune seconde copie des
  règles du lecteur Lua. Le verdict du jeu (refus et ligne, lus dans `console.txt`) s'affiche dans l'atelier, à la
  section fautive.
- **D04 — L'IA du pont aide à écrire** (utilisateur). L'atelier utilise le fournisseur déjà configuré pour le pont, avec
  les mêmes plafonds de coût : rédiger la personnalité en anglais à partir de quelques phrases du joueur, proposer
  l'histoire d'une mission, essayer la voix en conversation avant de la mettre en jeu. Sans fournisseur (mode
  `--offline`), ces boutons sont grisés et tout le reste fonctionne.
- **D05 — Interface en français et en anglais** (utilisateur), choisie par la langue du navigateur, anglais à défaut.
- **D06 — Exporter et importer** (utilisateur). Exporter donne la fiche `.txt` elle-même (une voix = un fichier) ;
  importer en accepte une, la soumet au même circuit, et demande un nouvel identifiant si la voix existe déjà.
- **D07 — Note de fréquence et appel spontané écrits dans la fiche** (utilisateur, 2026-11-15). Le mod fournit une
  note manuscrite générique dont le texte et les lieux de butin viennent de la fiche ; le texte de l'appel spontané peut
  être écrit dans la fiche au lieu d'une clé de traduction. Les voix livrées gardent leurs objets et leurs clés.
- **D08 — Relevé de lieux en jeu.** Clic droit « Atelier des voix : relever ce lieu » (case, conteneur, bâtiment), en
  solo ou par un admin ; le jeu ajoute le relevé à un fichier du dossier de travail que l'atelier affiche dans
  « Lieux relevés ».

- **D09 — Journal en direct dans l'atelier** (utilisateur, 2026-11-15). Le pont tourne comme avant ; l'option
  `--atelier` ouvre en plus l'atelier, dans le même programme (sans IA configurée, l'atelier reste ouvert seul). L'atelier devient aussi l'écran d'administration en direct des voix : le
  journal du pont (demandes, réponses, erreurs, coûts) et les lignes des fiches dans `console.txt` s'y lisent en
  direct, filtrables par voix. Lecture seule, sur la machine seulement : le journal peut contenir les dialogues des
  joueurs.

## Conséquences

- Le pont gagne un second rôle (atelier) ; il reste un seul programme à installer.
- Un nouveau type de mission ou une nouvelle récompense entre au catalogue par la génération, sans toucher l'interface
  (ouvert/fermé : l'interface lit les déclarations).
- Sur un serveur loué, l'atelier tourne sur la machine du serveur, ou l'on exporte la fiche et la copie à la main.

## Hors périmètre

- Hébergement en ligne de l'atelier, partage de voix entre joueurs par un service.
- Édition des fiches de Living Knox.
