# ADR — Des voix qui aident à trouver une recette

| | |
|---|---|
| Date | 2026-11-17 |
| Statut | Accepté |
| Décideur | utilisateur |
| Plan associé | [E27 — Recettes par la radio](../../annexes/plans/E27-recettes-radio.md) |
| Références | ADR [voix déclarées](adr-personas-declaratives.md) ; ADR [atelier des voix](adr-atelier-voix.md) (D12 : rien de technique à saisir) ; ADR [Living Knox et RadioSurvivor séparés](adr-coreai-separation.md) (D01, D02) ; `CA_Reputation.lua` (niveaux `bad`, `neutral`, `good`) ; `IsoGameCharacter.learnRecipe`, `getKnownRecipes` (sources 42.22) |

## Contexte

Demande de l'utilisateur du 2026-11-17 : une voix peut aider le joueur à trouver une information du jeu, par exemple
la recette d'un objet, recettes des mods comprises. L'échange reste une conversation, pas une fiche technique. Deux
subtilités : la voix n'aide que si la réputation est bonne, et elle peut répondre tout de suite ou demander du temps
(« je fouille dans mes manuels, rappelle dans une heure »).

Faits relevés (confirmé statiquement) :

- Le jeu 42.22 traduit les objets (`ItemName.json`) et les recettes (`Recipes.json`) en 29 langues, dont `FR`, `UA` et
  `KO`. Un mod sans traduction retombe sur l'anglais.
- Les recettes sont rangées par catégorie (`category =` : `Tailoring`, `Cooking`, `Carpentry`, `Blacksmithing`,
  `Electrical`, `Farming`, `Metalworking`…). Les mods utilisent ces catégories ou les leurs.
- Une recette peut devoir être apprise ; `IsoGameCharacter.learnRecipe(nom)` l'ajoute aux recettes connues
  (`getKnownRecipes`), comme le fait un magazine.
- La réputation d'un joueur auprès d'une voix a trois niveaux : `bad`, `neutral`, `good` (« Mauvaise », « Neutre »,
  « Bonne »).
- Sur un serveur multijoueur, `getText` côté serveur rend des clés brutes : les noms traduits se résolvent côté joueur.

## Architecture retenue (utilisateur, 2026-11-17) : « le manuel de la voix »

- Le serveur exporte un index des recettes chargées (vanilla et mods) dans le dossier d'échange : identifiant, nom
  anglais, catégorie, ingrédients, outils, niveau requis, recette à apprendre ou non, mod d'origine.
- Le pont y cherche les recettes qui répondent à la question et les donne à l'IA, qui répond en personnage.
- Le serveur garde la main sur la réputation, le délai, la mémoire de chaque appelant et l'apprentissage.

## Décisions

- **D01 — Plusieurs langues sans liste de mots (utilisateur, 2026-11-17).** Le joueur demande dans sa langue. L'IA
  traduit la question en quelques mots-clés anglais ; le pont cherche ces mots dans l'index anglais (noms et
  identifiants) et rend à l'IA les 3 à 5 recettes les plus proches. La voix répond dans la langue du joueur avec ses
  propres mots. Le carnet note la recette avec les noms exacts du jeu, traduits par le jeu du joueur. Rien trouvé : la
  voix le dit, sans inventer. Aucune liste de mots par langue (règle « pas d'heuristique de langue »).
- **D02 — Métiers dans une liste (utilisateur, 2026-11-17).** Dans l'atelier, on coche un ou plusieurs métiers pour
  une voix (Couturière, Cuisinier, Menuisier, Forgeron, Électricien…). Chaque métier regroupe des catégories de
  recettes du jeu. Une recette de mod sans catégorie connue va dans le métier « Débrouille ». Une voix sans métier
  n'aide pas sur les recettes.
- **D03 — Un palier de réputation par voix (utilisateur, 2026-11-17).** Dans l'atelier, on choisit à partir de quel
  niveau la voix aide. En dessous, elle refuse à sa façon ; au-dessus, elle aide normalement.
- **D04 — Délai réglé par voix, le joueur rappelle (utilisateur, 2026-11-17).** Dans l'atelier : « répond tout de
  suite » ou « cherche d'abord », avec une durée en mots simples (une heure, une demi-journée, un jour, en heures de
  jeu). Si elle cherche, la voix dit de rappeler ; rappelée après le délai, elle donne la réponse ; trop tôt, elle n'a
  « pas encore trouvé ».
- **D05 — La voix apprend la recette (utilisateur, 2026-11-17).** Pour une recette qui doit être apprise, la voix
  l'apprend au joueur pour de vrai, comme un magazine, si sa réputation auprès d'elle est très haute. Sinon elle
  explique la recette et ce qu'il faut pour l'apprendre, sans la débloquer.

### Confirmé par défaut (2026-11-17)

- **D06 — Seuils.** Palier d'aide au choix : « tout le monde », « Neutre » ou « Bonne ». « Très haute » (D05) =
  niveau « Bonne ». Le joueur n'apprend que les recettes des métiers de la voix.
- **D07 — Une recherche en attente par joueur et par voix.** Une nouvelle question pendant une recherche remplace
  l'ancienne. La réponse prête attend que le joueur rappelle, sans date limite.
- **D08 — Index rangé dans RadioSurvivor.** Seules les voix s'en servent aujourd'hui (D02 de l'ADR de séparation).
  Le pont, commun, lit le fichier sans savoir qui l'écrit.
- **D09 — Recette notée au carnet.** Chaque recette donnée laisse une entrée « Recette » dans le carnet : résultat,
  ingrédients, outils, niveau, et « apprise » quand la voix l'a apprise.
- **D10 — Langue des noms.** Noms du carnet traduits côté joueur ; un nom sans traduction reste en anglais.

## Conséquences

- La fiche d'une voix gagne une section `[help]` (métiers, palier, délai), éditée dans l'atelier avec des listes.
- Le pont fait deux appels à l'IA pour une question de recette (recherche, puis réponse) ; le coût est compté dans les
  plafonds existants.
- L'apprentissage par la radio est un avantage de jeu réel, gardé par la réputation la plus haute et par les métiers.
- Living Knox n'est pas concerné ; il pourra lire le même index plus tard.
