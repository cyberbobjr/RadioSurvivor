# ADR — Registres des routines et des tâches du foyer de Living Knox

| | |
|---|---|
| Date | 2026-11-13 (création, acceptation) |
| Statut | Accepté (utilisateur, 2026-11-13) |
| Décideur | utilisateur |
| Portée | `batman_LivingKnox`, côté autorité (`media/lua/server/LivingKnox`) : aiguillage des routines (`LK_Routines.lua`), entretien du foyer (`LK_Upkeep.lua`), et les tâches ajoutées ensuite (creuser, semer, graines du jardinier) |
| Plan associé | [LK15 — Registres des routines et potager du jardinier](../../annexes/plans-termines/LK15-registre-routines.md) (suivi des tâches dans le plan) |
| Références | [fiche entretien](../../annexes/conception/entretien.md) ; [fiche routines](../../annexes/conception/routines.md) ; base `pz-knowledge/mod-loading.md` (chargement récursif, fichier qui s'inscrit à un registre) ; sources vanilla 42.22 du potager (relevé du 2026-11-13, ci-dessous) |

## Contexte

L'utilisateur veut des routines « bien codées et bien isolées », sans mélange de code entre elles, et pouvoir en ajouter
sans toucher au code partout (principe ouvert/fermé). Le relevé du code du 2026-11-13 montre l'inverse :

- `Routines.apply` (`LK_Routines.lua:892-911`) appelle en dur, dans l'ordre, les barricades (`LK_Fortify`), l'entretien
  (`LK_Upkeep`), puis les corvées visibles, par une suite de `if st.b == "chore"` ; ajouter une activité modifie cet
  aiguillage.
- `LK_Routines.lua` (1 170 lignes) porte dans un seul fichier le guet, les rondes, les relèves, le sommeil, les repas,
  les corvées et les outils d'exécution partagés (`Routines.exec`).
- `LK_Upkeep.lua` (779 lignes) mêle ses six tâches (`refuel`, `repair`, `harvest`, `water`, `clean`, `glass`) dans les
  mêmes fonctions : la liste `Upkeep.JOBS`, le relevé `Upkeep.jobs`, l'effet `Upkeep.apply` et la place `placeFor`
  testent `job.kind` à une dizaine d'endroits (`:478-603`). La priorité du jardinier ajoutée par `LK05-T21`
  (`Upkeep.GARDEN_JOBS`) suit le même défaut : une liste de noms dans le moteur.

Ajouter le potager (creuser un sillon, semer, recevoir des graines) dans cet état toucherait chacune de ces fonctions.

Faits du moteur retenus (sources vanilla 42.22, relevé du 2026-11-13, confirmé statiquement) :

- Tout fichier de `media/lua/server` est chargé par le jeu, sous-dossiers compris, trié par chemin en minuscules ; un
  fichier qui s'inscrit à un registre commence par `require` du registre (`pz-knowledge/mod-loading.md`). Un fichier
  ajouté dans un sous-dossier est donc chargé sans qu'aucun autre fichier le cite.
- Sillon : `SFarmingSystem:plow(square)` crée l'objet du potager sans joueur (`server/Farming/SFarmingSystem.lua:508-536`,
  objet transmis aux clients par `SPlantGlobalObject:addObject`, `:208-217`). Conditions du menu vanilla : rez-de-chaussée,
  case libre, sol de terre, ni tombe ni plante (`client/Farming/ISUI/ISFarmingMenu.lua:514-534`). Outil facultatif (mains
  nues admises, deux fois plus lent).
- Semis : `SPlantGlobalObject:seed(type, niveau)` sans joueur (`SPlantGlobalObject.lua:715-732`), une graine par plante
  (`ISSeedActionNew.lua:56-73`), refusé hors état « labouré » (`farmingCommands.lua:86-97`). Hors saison
  (`sowMonth`), la plante n'est pas refusée mais maudite si l'option `PlantGrowingSeasons` est active
  (`farming_vegetableconf_vegetables.lua`, carotte `:137-139`).
- Graines : objets `Base.<Légume>Seed` (`CarrotSeed`, `TomatoSeed`, `PotatoSeed`, `CabbageSeed`…) ; sachets
  `Base.<Légume>BagSeed2` (5 graines par sachet, `recipes_farming.txt:111-127`).

## Décisions

- **D01 — Registre des tâches du foyer.** `LK_Upkeep.lua` devient le moteur commun des tâches : relevé périodique,
  réservation d'une tâche par un membre (`claims`), marche jusqu'à la case, regard, geste, durée, effet appliqué une
  seule fois, libération, compteurs. Il ne nomme aucune tâche. Une tâche s'inscrit par
  `LivingKnox.Upkeep.registerJob(spec)` ; `spec` déclare : `kind` (nom unique), `order` (priorité, plus petit d'abord),
  `prefer` (comportement de rôle qui la prend avant les autres, facultatif : `"garden"`, `"maintain"`…), `gesture`,
  `minutes`, `survey(gid, g, area)` (tâches ouvertes autour du foyer), `place(job)` (case où se tenir, facultatif :
  case voisine par défaut), `apply(job, gid, who)` (effet, matériaux relus au moment de l'effet). Le moteur trie les
  tâches inscrites par `order` puis `kind` (ordre stable, aucun `next` : Kahlua).
- **D02 — Une tâche par fichier, chargée seule.** Chaque tâche vit dans
  `media/lua/server/LivingKnox/Jobs/LK_Job_<Nom>.lua`, commence par `require "LivingKnox/LK_Upkeep"` et s'inscrit au
  premier niveau. Le jeu charge le dossier tout seul : ajouter une tâche = ajouter un fichier, sans modifier le moteur ni
  une liste. Les tâches actuelles en sortent telles quelles : `Refuel`, `Repair`, `Harvest`, `Water`, `Clean`,
  `Glass`. Les aides propres à un domaine (eau du stock, plante d'une case, produits de récolte) vont dans le fichier
  de la tâche, ou dans un petit module de domaine partagé par deux tâches (`LK_Garden.lua` pour l'arrosage, la récolte,
  le sillon et le semis).
- **D03 — Préférence par rôle déclarée par la tâche.** La priorité d'un métier (jardinier, bricoleur) est le champ
  `prefer` de la tâche : le moteur donne d'abord à un membre les tâches dont `prefer` est dans les comportements de son
  rôle, puis les autres par `order`. `Upkeep.GARDEN_JOBS` (`LK05-T21`) disparaît au profit de `prefer = "garden"` sur
  l'arrosage et la récolte.
- **D04 — Registre des activités des routines.** `Routines.apply` ne connaît plus les modules : une activité s'inscrit
  par `LivingKnox.Routines.registerActivity(spec)` avec `id`, `behaviour` (`"chore"`, `"meal"`, `"sentry"`, `"sleep"`…),
  `order` et `run(id, st, ctx, g)` qui rend vrai quand elle a pris le membre. `Routines.apply` essaie, pour le
  comportement courant, les activités inscrites par `order` ; la première qui rend vrai l'emporte. Ordre actuel gardé :
  barricades (`order` 10, poste `builder`), entretien (20), corvée visible (90).
- **D05 — Une routine par fichier.** `LK_Routines.lua` est découpé sans changer de comportement : outils d'exécution
  partagés (`LK_RoutineExec.lua` : aller, regarder, s'asseoir, case voisine, geste, quitter), relevé du foyer (postes,
  lits, ronde), puis une activité par fichier sous `media/lua/server/LivingKnox/Routines/` : guet et rondes, sommeil,
  repas, corvées visibles. `LK_Fortify.lua` et `LK_Upkeep.lua` s'inscrivent comme activités du comportement `chore`.
- **D06 — Découpage d'abord, sans changement de comportement.** Les étapes de découpage (D01 à D05) ne changent rien
  pour un joueur : mêmes bancs hors jeu verts avant et après (seuls les chemins de chargement des doublures changent),
  campagnes solo et MP vertes après. Aucun ajout de comportement dans ces étapes.
- **D07 — Potager du jardinier.** Deux nouvelles tâches, chacune dans son fichier, préférées par `garden` :
  `LK_Job_Dig` (creuser un sillon : case de terre libre au rez-de-chaussée, dehors, dans la zone du foyer, au plus
  `MAX_PLOTS` sillons par foyer, outil `DIG_PLOW` du stock s'il y en a un, mains nues sinon, durée doublée comme le
  vanilla ; effet `SFarmingSystem.instance:plow`) et `LK_Job_Sow` (semer dans un sillon vide une graine du stock dont
  le mois est dans `sowMonth` ; effet `plant:seed(type, 0)`, graine retirée du stock et de sa référence).
- **D08 — Graines reçues par le jardinier.** Décision de l'utilisateur du 2026-11-13 : les graines du jardinier
  arrivent automatiquement. Un fichier `LK_Job_SeedSupply.lua` (ou une activité du jardinier) dépose au foyer des
  graines de saison quand le stock en compte moins de `SEED_LOW`, au plus une fois tous les `SEED_DAYS` jours de jeu par
  groupe qui a un jardinier. Les graines des récoltes s'ajoutent au même stock.

## Arbitrages ouverts

- **Q01 — Quantités par défaut du potager** (`MAX_PLOTS`, `SEED_LOW`, `SEED_DAYS`, nombre et variétés des graines
  reçues). Valeurs proposées, confirmées par défaut sans réponse contraire : 6 sillons par foyer ; dépôt quand le stock a
  moins de 2 graines semables ; au plus une fois tous les 7 jours de jeu ; 5 graines (un sachet) d'une variété de
  saison tirée parmi carotte, pomme de terre, chou, tomate. Ne bloque que D07 et D08. **Rendu le 2026-11-13** : ADR accepté sans changement de ces valeurs, confirmées par défaut.

## Alternatives écartées

| Alternative | Pour | Contre | Verdict |
|---|---|---|---|
| Garder l'état actuel et ajouter des `if` | Aucun travail de découpage | Chaque tâche nouvelle touche le relevé, l'effet, la place et la priorité ; contraire à la demande (principe ouvert/fermé) | écartée |
| Liste des tâches écrite dans le moteur (`JOBS = { ... }`), une fonction par tâche | Ordre lisible en un endroit | Ajouter une tâche modifie encore le moteur ; un autre mod ne peut pas en ajouter une | écartée |
| Tâches décrites par des données seules (tables sans code) | Simple à lire | Les effets (plein, récolte, semis) sont du code propre à chaque tâche : il faudrait un `if` par nature d'effet dans le moteur | écartée |
| Classes avec héritage (métatables Kahlua) | Forme objet classique | Plus lourd pour aucun gain ici ; le registre de tables suffit et reste lisible dans les bancs | écartée |
| **Registre + un fichier par tâche, chargé par le jeu** | Ajout sans toucher au moteur ; tâche testable seule ; ordre et préférence déclarés par la tâche | Découpage à faire une fois ; l'ordre de chargement impose le `require` du registre en tête de fichier (fait connu du moteur) | **retenue** |

## Conséquences

- Multijoueur : inchangé. Tout se passe sur l'autorité ; un client MP charge aussi `media/lua/server`, chaque fichier
  de tâche s'arrête sur `isClient()` comme les modules actuels. Les effets passent par les mêmes appels vanilla
  synchronisés.
- Sauvegardes : rien n'est sauvegardé par l'entretien ni les routines (mémoire recalculée) ; les sillons et plantes
  sont des objets vanilla sauvegardés par le jeu.
- Bancs hors jeu : les harnais chargent le dossier `Jobs/` et `Routines/` (liste des fichiers du dossier) au lieu d'un
  fichier ; un banc du moteur emploie une fausse tâche inscrite par le test ; chaque tâche garde ses bancs actuels.
- Un autre mod pourrait ajouter une tâche par un seul fichier à un chemin propre (protégé par `if LivingKnox and
  LivingKnox.Upkeep then … end`).
