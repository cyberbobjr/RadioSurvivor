# Index des recettes

- Tâche : E27-T01 — ADR [recettes par la radio](../architecture/decisions/adr-recettes-radio.md) (D02, D08, D11)
- Build : 42.22 (sources de référence) — Date : 2026-11-17 — Statut : testé hors jeu (banc lupa, encodeur passé dans
  la VM Kahlua), non testé en jeu

Code : `server/RadioSurvivor/RS_RecipeCatalog.lua` (lecture des recettes du jeu), `RS_RecipeJobs.lua` (table des
métiers), `RS_Json.lua` (encodeur), `RS_RecipeIndex.lua` (écriture du fichier) ; pont : `bridge/recipe_index.py`
(`RecipeIndex`). Tests : `tests/radiosurvivor/test_recipe_index.py`, `tests/radiosurvivor/test_recipe_index_bridge.py`.

## Écriture par le jeu

- **Quand** : au démarrage de l'autorité, une fois par session Lua : `OnServerStarted` sur un serveur dédié,
  `OnGameStart` en solo (le premier des deux). Jamais sur un client MP (`isClient()`).
- **Quoi** : `ScriptManager.instance:getAllCraftRecipes()` (`ScriptManager.java:985`), soit toutes les recettes
  `craftRecipe` chargées, vanilla et mods actifs ; un mod qui remplace une recette vanilla du même nom y figure à sa
  place. Les recettes de construction des entités (meubles, établis) n'en font pas partie.
- **Où** : `Zomboid/Lua/batman_CoreAI/recipes.json`, le dossier d'échange du pont (dossier `Lua` du `-cachedir` sur un
  serveur). Kahlua ne sait pas renommer un fichier : le fichier est écrasé directement.
- **Mesure** : une ligne de console anglaise, `recipes: N recipes written to batman_CoreAI/recipes.json (H hidden
  skipped), B bytes, T ms`. Estimation hors jeu pour les 965 recettes vanilla, un objet par ligne : environ 350 à 520 Ko ;
les lignes à étiquette (`tags[...]`) listent tous leurs objets et peuvent porter le fichier vers le mégaoctet
(hypothèse, à relever dans la ligne de console) ; encodage
  mesuré dans la VM Kahlua du jeu à environ 0,15 ms par recette, soit 0,15 s pour l'encodage seul (hypothèse pour la
  durée totale en jeu : 0,2 à 0,5 s, appels Java compris ; à relever dans la ligne de console).

## Format (version 1)

Texte JSON en ASCII pur : tout caractère au-delà de U+007F est écrit `\uXXXX` (paires de substitution au-delà de
U+FFFF). Une recette par ligne, triées par identifiant.

```json
{"format":1,"written":<getTimestampMs au début de l'écriture>,"recipes":[
{"category":"Tailoring","id":"MakeSheetRope","inputs":[...],"job":"tailoring","learn":false,"learned_from":[],...}
]}
```

| Champ | Type | Source (Java 42.22) |
|---|---|---|
| `id` | texte | `CraftRecipe.getName` (146) |
| `name` | texte | nom anglais : `getTranslationName` (150) si la langue du jeu est la langue par défaut (`Translator.getLanguage` 447 = `getDefaultLanguage` 583) et que le jeu a un nom ; sinon l'identifiant coupé aux majuscules et aux `_` (`MakeTVStand` → `Make TV Stand`) |
| `category` | texte | `getCategory` (228), brute ; `Miscellaneous` quand le script n'en donne pas |
| `job` | texte | métier de la catégorie (table ci-dessous) |
| `inputs` | liste | lignes d'ingrédients, objets ou fluides (ci-dessous) |
| `outputs` | liste | lignes de produits, objets ou fluides (ci-dessous) |
| `skills` | liste | `{"perk", "level"}` : `getRequiredSkillCount` / `getRequiredSkill` (952, 956), `Perk.getId` (175), `RequiredSkill.getLevel` (1596) |
| `learn` | booléen | `needToBeLearn` (185) |
| `learned_from` | liste | types complets des objets dont `Item.getLearnedRecipes` (3812) cite la recette (magazines, livres), triés |
| `mod` | texte | `getModID` (132), `""` si `isVanilla` (128) |

### Lignes d'ingrédients et de produits

| Ligne | Forme | Source (Java 42.22) |
|---|---|---|
| ingrédient objet | `{"items": [{"item", "name"}, ...], "count", "tool"}` | `items` : tous les objets possibles, un seul suffit (« un marteau ou une masse ») : `InputScript.getPossibleInputItems` (110, étiquettes résolues), `Item.getFullName` (908), nom anglais `Item.getDisplayName` (514, même règle de langue que `name`, repli sur le type coupé) ; `count` = `getIntAmount` (384) ; `tool` = `isKeep` (212) ou `isTool` (216) : objet gardé, pas consommé |
| ingrédient fluide | `{"fluids": [{"fluid", "name"}, ...], "amount", "tool": false}` | `fluids` : tous les fluides possibles, un seul suffit : `getPossibleInputFluids` (123), `Fluid.getFluidTypeString` (285), nom anglais `Fluid.getDisplayName` (301, même règle de langue) ; `amount` = `getAmount` (388) |
| produit objet | `{"items": [...], "count"}` | `OutputScript.getPossibleResultItems` (143), `getIntAmount` (106) |
| produit fluide | `{"fluids": [...], "amount"}` | `getPossibleResultFluids` (151), `getAmount` (110) |

- **Unité de `amount`** : le litre, unité des scripts (`-fluid 1.0 [Water]` = 1 l ; `FluidContainer.java:321`
  multiplie par 1000 pour les millilitres). Le flottant Java est arrondi au millilitre (`0.3f` → `0.3`).
- **Fluides d'un récipient** : les lignes `-fluid` (consommé dans le récipient) et `+fluid` (versé dans le
  récipient) sous une ligne d'objet ne sont pas dans `getInputs` / `getOutputs` (`CraftRecipe.java:605-657`). Elles
  sont lues par `getConsumeFromItemScript` (163) et `getCreateToItemScript` (`InputScript` 155, `OutputScript` 81) :
  un `-fluid` devient un ingrédient fluide juste après la ligne de son récipient ; un `+fluid` sous un produit devient
  un produit fluide juste après lui ; un `+fluid` sous un ingrédient devient un produit fluide placé après les produits
  de la recette.
- **Écartées** : lignes d'énergie, lignes réservées à l'automatisation (`isAutomationOnly`, avec leurs fluides),
  ingrédient « n'importe quel objet » (`isAcceptsAnyItem` 480 ; le fluide de ce récipient est gardé) et « n'importe
  quel fluide » (`isAcceptsAnyFluid` 484).
- Ordre : celui des lignes du script ; `items` et `fluids` dans l'ordre que rend le jeu.

## Recettes écartées

Une recette portant l'étiquette `RightClickOnly` n'entre pas dans l'index : la fenêtre d'artisanat du jeu la cache
(`HandcraftLogic.java:184`), elle ne se fait que depuis un menu contextuel (ouvrir un parapluie, prendre un mouchoir,
lancer un dé). Les recettes `craftRecipe` n'ont pas d'autre marque « cachée » dans le Java 42.22.

## Table des métiers

`RS_RecipeJobs.JOBS` : métier → catégories, comparées sans tenir compte de la casse ; une catégorie n'appartient qu'à
un métier ; toute catégorie absente de la table va dans `makeshift` (« Débrouille »). Ajouter un métier ou une
catégorie = ajouter une donnée.

| Métier | Catégories | Raison |
|---|---|---|
| `tailoring` | Tailoring | couture |
| `cooking` | Cooking | cuisine |
| `carpentry` | Carpentry, Carving, Masonry | travail du bois, sculpture (os, bois), plâtre et ciment du bâtisseur |
| `smithing` | Blacksmithing, Metalworking, Tools, Blade, Cookware, Armor, Assembly | forge et métal ; `Tools`, `Blade`, `Cookware`, `Armor` sont des pièces forgées ; `Assembly` emmanche les lames et têtes forgées |
| `electrical` | Electrical | électronique |
| `mechanics` | Mechanics | aucune catégorie vanilla 42.22 ; nom attendu des recettes de mods mécaniques (hypothèse) |
| `farming` | Farming | remèdes des plantes, semis |
| `medical` | Medical | cataplasmes, soins |
| `weapons` | Weaponry | armes |
| `pottery` | Pottery, Glassmaking | four et four à verre, même savoir-faire |
| `makeshift` | toutes les autres | `Miscellaneous`, `Packing`, `Knapping`, `Fishing`, `Repair`, catégories des mods |

Catégories `craftRecipe` relevées dans les scripts vanilla 42.22 (965 recettes) : Tailoring 183, Cooking 89,
Farming 74, Blacksmithing 66, Weaponry 57, Metalworking 53, Tools 52, Miscellaneous 50 (+35 sans catégorie),
Carving 47, Pottery 44, Packing 32, Electrical 29, Carpentry 28, Blade 17, Cookware 17, Assembly 16, Armor 16,
Repair 14, Masonry 11, Knapping 11, Glassmaking 10, Medical 8, Fishing 6.

## Lecture par le pont

`RecipeIndex(exchange)` lit le fichier au lancement du pont (`Bridge.__init__`, nombre de recettes au journal), puis le
relit à chaque accès (`recipes()`, `for_jobs(jobs)`) dès que sa date de modification ou sa taille change. Validation :
`format` = 1, `recipes` liste, chaque recette porte les dix champs avec leur type, chaque ligne d'ingrédient ou de
produit a une liste `items` ou `fluids` non vide (entrées `item`/`fluid` et `name` en texte), un `count` ou un
`amount` numérique et, pour un ingrédient, un `tool` booléen. Fichier absent : index vide et une
ligne de journal. Fichier illisible (écriture du jeu en cours, format inconnu) : une ligne de journal qui dit pourquoi,
l'index précédent est gardé et le fichier est relu à son prochain changement. Le pont n'écrit jamais ce fichier et ne
sait pas quel mod l'écrit (D08).

## Recherche (E27-T03)

Code : `bridge/recipe_search.py` (`search`), `bridge/recipe_help.py` (palier, prompts, faits) ; tests :
`tests/radiosurvivor/test_recipe_search.py`, `tests/radiosurvivor/test_recipe_help_bridge.py`. Déroulé de l'appel :
[protocole](protocole-carnet-v2.md), « Recette demandée ».

- **Entrée** : les recettes des métiers de la voix (`RecipeIndex.for_jobs(help.jobs)`) et 1 à 4 mots-clés anglais
  donnés par l'IA (D01 : l'IA traduit, aucune liste de mots par langue). Mots-clés bornés : lettres et chiffres ASCII,
  espaces, tirets, 40 caractères chacun.
- **Mots d'une recette**, comparés sans casse, pluriel anglais simple toléré (`batteries` → `battery`, `boxes` →
  `box`, `ropes` → `rope`) : types des objets produits sans module, coupés aux majuscules (`Base.SheetRope` → `sheet`,
  `rope`), noms des objets et fluides produits (poids 3) ; identifiant coupé aux majuscules et aux `_` (poids 2) ; nom
  (poids 1). Le nom peut être dans la langue du serveur : l'identifiant et les types restent anglais.
- **Score** : chaque mot-clé est une expression ; elle ne compte pour une recette que si **tous** ses mots sont des
  mots de la recette, et apporte alors la somme du meilleur poids de chacun de ses mots. Score d'une recette = somme
  de ses expressions entièrement trouvées (`["bandage", "ripped sheets"]` ne donne pas la corde en draps : `ripped`
  n'en est pas un mot). Meilleur score d'abord, égalité par identifiant ; au plus 5 recettes, aucune à score nul.
- **Mots-clés demandés à l'IA** : la chose à fabriquer seulement, jamais ses ingrédients ni ses outils
  (`["sheet rope"]`, pas `["ripped sheets"]`). Sous le palier, aucun indice : ni ingrédient, ni outil, ni récipient,
  ni méthode, même générale.
- **Faits donnés à l'IA** (second appel) : nom, produits, ingrédients avec alternatives (« A or B ») et quantités,
  fluides en litres, outils gardés, niveaux de compétence, « Must be learned first, from: » et les objets qui
  l'apprennent ; consigne : en personnage, dans la langue de l'appelant, en conversation, sans rien inventer. Rien
  trouvé : la voix le dit.
