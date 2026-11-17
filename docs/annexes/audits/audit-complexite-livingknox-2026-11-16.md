# Audit de complexité et SOLID : Living Knox (runtime Lua)

| Champ | Valeur |
| --- | --- |
| Date | 2026-11-16 |
| Portée | `Contents/mods/batman_LivingKnox/42.21/media/lua` (153 fichiers `.lua`) ; hors portée : `batman_CoreAI`, dossiers `dev/` et `tests/` (utilisés seulement pour repérer le code qui n'a que des tests comme appelant) |
| Mode | Lecture seule. Aucun fichier du dépôt modifié pendant l'audit. Suites données : ADR [`adr-simplification-livingknox.md`](../../architecture/decisions/adr-simplification-livingknox.md), plan LK20. |
| Règles lues | `Workshop/AGENTS.md`, `RadioSurvivor/docs/developpement.md` (section « Architecture validée » et règle SOLID dès la conception), `docs/architecture/decisions/README.md`, ADR `adr-remise-en-ordre-solid.md`, `adr-bords-des-cases.md`, `adr-registre-routines.md`, plan `LK16` (clos) et `LK17` (en cours) |
| Audit précédent | Audit SOLID du 2026-11-13 (`docs/annexes/audits/audit-solid-livingknox-2026-11-13.md`, 214 constats) et son chantier de remise en ordre `LK16` (tâche `LK16-T12` « testé MP ») : **déjà traités**, à ne pas redécouvrir. Le « Reste » de `LK16` (ex. client d'administration commun) est repris ci-dessous. |
| État du dépôt | Au moment de l'audit, `git status` montre des modifications non commitées de LK17 (`server/LivingKnox/LK_Obstacles.lua`, `Jobs/LK_Job_*.lua`). Les mesures portent sur cet arbre de travail. |
| Méthode | Mesures par script Python (lignes, fonctions, longueur des fonctions par indentation, comptage des appelants par `rg`), puis lecture ciblée des en-têtes de section, des listes de fonctions et des extraits cités. Aucun sous-agent : le volume tenait en mesures scriptées. |
| Limites | Longueur de fonction estimée par l'indentation (`end` de même niveau). Code mort détecté par nom : un nom banal (`now`, `log`, `count`) peut masquer un appel mort. Tests non exécutés. Rien n'est validé en jeu. |

## 1. Verdict

1. **Le ressenti « usine à gaz » est justifié, mais il tient à la structure, pas à la masse de code inutile.** Le code mort est négligeable (4 fonctions, 28 lignes).
2. **Où** : cinq moteurs dépassent 1 500 lignes et mêlent 8 à 11 responsabilités chacun (`LK_Fortify`, `LK_Decisions`, `LK_Obstacles`, `LK_Stock`, `LK_Expeditions`). Ils pèsent **10 258 lignes, soit 18 % du mod**. Le déplacement d'un PNJ est réparti sur une dizaine de fichiers (**≈ 1 700 lignes**).
3. **Combien** : 153 fichiers, 55 541 lignes (42 359 hors lignes vides et commentaires), environ 3 450 fonctions, médiane de 186 lignes par fichier, 16 fichiers de plus de 800 lignes, 18 fonctions de plus de 80 lignes. Il y a aussi des ballasts répétés : 166 accesseurs d'une ligne qui ne font rien, 17 copies d'une même fonction de distance, 5 files d'attente recopiées.
4. **Pas justifié** : la galaxie de registres (chacun a au moins 4 inscriptions réelles), la configuration (les 33 options sandbox sont toutes lues), la discipline Kahlua (aucun `next(`, aucun littéral non ASCII), la séparation autorité / client / partagé (ADR en vigueur, respectée).
5. **Coût réel** : environ **600 lignes retirables sans changer de comportement (≈ 1 %)**. Le vrai chantier est le découpage des cinq moteurs, qui est un changement d'architecture (ADR puis plan), à conduire après la fin de LK17.

## 2. Mesures

### 2.1 Vue d'ensemble

| Indicateur | Valeur |
| --- | --- |
| Fichiers `.lua` | 153 |
| Lignes totales / lignes de code (sans vides ni commentaires) | 55 541 / 42 359 |
| Fonctions définies (heuristique, nommées et anonymes) | 3 456 |
| Médiane de lignes par fichier | 186 |
| Fichiers > 500 lignes / > 800 lignes | 42 / 16 |
| Fonctions > 50 lignes / > 80 lignes | 76 / 18 |
| Imbrications à 6 niveaux ou plus (lignes) : `LK_Obstacles`, `LK_Homes`, `LK_Fortify` | 33, 32, 24 |

### 2.2 Les plus gros fichiers

| Fichier (`media/lua/`) | Lignes | Code | Fonctions | Plus longue fonction |
| --- | ---: | ---: | ---: | --- |
| `server/LivingKnox/LK_Fortify.lua` | 2 877 | 2 273 | 150 | 110 (`Fortify.build`, l. 684) |
| `server/LivingKnox/LK_Decisions.lua` | 2 330 | 1 781 | 134 | 72 |
| `server/LivingKnox/LK_Obstacles.lua` | 1 933 | 1 394 | 99 | 68 |
| `server/LivingKnox/LK_Expeditions.lua` | 1 567 | 1 265 | 84 | 89 |
| `server/LivingKnox/LK_Stock.lua` | 1 551 | 1 204 | 77 | 111 (`Stock.applyPending`, l. 1277) |
| `server/LivingKnox/LK_Directives.lua` | 1 350 | 1 021 | 75 | 116 (`Directives.onReport`, l. 874) |
| `server/LivingKnox/LK_Combat.lua` | 1 272 | 982 | 74 | 65 |
| `server/LivingKnox/LK_API.lua` | 1 169 | 899 | 73 | 71 |
| `server/LivingKnox/LK_Relations.lua` | 1 135 | 889 | 73 | 93 |
| `server/LivingKnox/LK_Groups.lua` | 1 123 | 818 | 84 | 70 |
| `server/LivingKnox/LK_Simulation.lua` | 1 095 | 821 | 65 | 140 (`Simulation.simulateHour`, l. 556) |
| `client/LivingKnox/LK_Executor.lua` | 944 | 732 | 46 | 143 (`Executor.follow`, l. 478) |

### 2.3 Les fonctions les plus longues (plus de 80 lignes)

| Lignes | Fonction | Emplacement |
| ---: | --- | --- |
| 143 | `Executor.follow` | `client/LivingKnox/LK_Executor.lua:478` |
| 140 | `Simulation.simulateHour` | `server/LivingKnox/LK_Simulation.lua:556` |
| 139 | `Care.apply` | `server/LivingKnox/LK_Care.lua:362` |
| 130 | `onDouble` (vue de débogage) | `client/LivingKnox/LK_DebugView.lua:463` |
| 116 | `Directives.onReport` | `server/LivingKnox/LK_Directives.lua:874` |
| 111 | `Stock.check` | `server/LivingKnox/LK_Stock.lua:569` |
| 110 | `Defense.targetFor` | `server/LivingKnox/LK_Defense.lua:663` |
| 110 | `Fortify.build` | `server/LivingKnox/LK_Fortify.lua:684` |
| 110 | `Stock.applyPending` | `server/LivingKnox/LK_Stock.lua:1277` |
| 93 | `Relations.requestAid`, `Routines.survey` | `LK_Relations.lua:218`, `LK_Routines.lua:166` |
| 81 à 89 | `Ex.deliver`, `Homes.check`, `Zombies.pass`, `Encounters.contextFor`, `Simulation.resolveExpedition`, `Routines.runMeal`, `Fortify.applyPending` | voir le fichier de chaque fonction |

### 2.4 Configuration

| Élément | Nombre | Constat |
| --- | ---: | --- |
| Options sandbox (`media/sandbox-options.txt`) | 33 | Toutes lues. `InitiativeFrequency` est lue en direct par `SandboxVars` (`server/LivingKnox/LK_Initiatives.lua:61-68`) au lieu de passer par `Config.readInt` : contournement mineur. |
| Entrées de `LK_Config.lua` : `DEFAULTS` 13, `INT_BOUNDS` 10, `DANGER` 17, `FITNESS` 2, `SIMULATION` 67 | 109 | Aucune clé morte trouvée. Les six `ZombieEngage*` (une par rôle) sont une décision utilisateur (`LK_Config.lua`, commentaire LK06-T14) : pas un défaut. |
| Valeurs par défaut et bornes écrites **deux fois** | 23 | `DEFAULTS` et `INT_BOUNDS` (`LK_Config.lua:12-35`) répètent les valeurs de `sandbox-options.txt`, vérifiées seulement par des tests de cohérence. `DANGER` range déjà min/max/défaut dans une seule table. |

### 2.5 Duplication et indirection

| Motif | Occurrences | Exemples |
| --- | ---: | --- |
| `local function cheb(...)` (distance de Chebyshev), **corps identique** | 17 | `server/LivingKnox/LK_Care.lua:79`, `LK_Defense.lua:153`, `LK_Decisions.lua:1311`, `LK_Fortify.lua:319`, `shared/LivingKnox/LK_PassageArbiter.lua:50` |
| `local function finite(v)`, **corps identique** | 15 | `LK_Decisions.lua:244`, `LK_Health.lua:114`, `LK_Care.lua:78` |
| `local function isInt(v, lo, hi)` (version locale ; la version officielle est dans `LK_Config.lua:73`) | 16 | `LK_Admin.lua:119`, `LK_Expeditions.lua:155`, `LK_Homes.lua:178` |
| `local function now()` (horodatage) | 27 | `LK_Decisions.lua:242`, `LK_Health.lua:113` |
| `angleGap`, `clamp` | 4 chacun | `angleGap` : `LK_Combat.lua:206`, `LK_Decisions.lua:299`, `LK_Defense.lua:159`, `LK_Encounters.lua:91` |
| Accesseurs d'une ligne `local function X() return LivingKnox.Y end` | **166** | `LK_Care.lua:71-74`, `LK_Health.lua:107-110`, `LK_Directives.lua:133-136` |
| Boucles de balayage de cases (`for dy = -R, R do … for dx`) | ≈ 45 réparties dans une douzaine de fichiers | `LK_Homes.lua:311-312` et `402-403` ; `LK_Movement.lua`, `LK_Directives.lua` (7), `LK_Bodies.lua` (6) |
| `if kind == "…"` / `elseif … == "…"` | 47 `elseif` à chaîne ; 17 `kind ==` dans `LK_Decisions` ; 10 dans `LK_Obstacles` | Pour l'essentiel des états de résultat (`"done"`, `"stale"`, `"timeout"`), pas des genres ouverts. |
| File d'attente par image ou par heure, recopiée | 5 implémentations | `LK_Stock.lua:1468` (`onFrameStart`), `:1477` (`onFrame`), `:1505` (`finishQueue`) ; `LK_API.lua:1053` (`enqueue`) ; `LK_Talk.lua:131` (`enqueue`) ; `LK_Fortify.lua:2733-2772` ; `LK_Decisions.lua:1202-1238` (`hourScoringPending`, `hourStep`, `finishHourQueue`) |
| Réseau client (`sendClientCommand`, `OnServerCommand`, relais) recopié | 3 vues | `client/LivingKnox/LK_AdminView.lua:72`, `:154`, `:501-504` ; `LK_NpcSheet.lua:112`, `:277`, `:698-701` ; `LK_TradeView.lua` (2 envois). Déjà signalé dans le « Reste » de `LK16`. |

### 2.6 Code mort et seuls les tests l'appellent

Quatre fonctions n'ont **aucun appelant** (ni runtime, ni `tests/`, ni `dev/`) :

| Fonction | Emplacement | Lignes |
| --- | --- | ---: |
| `Homes.furnishingOf` | `server/LivingKnox/LK_Homes.lua:145` | 3 |
| `Relations.huntMemory` | `server/LivingKnox/LK_Relations.lua:1095` | 3 |
| `Notebook.relationTitle` | `client/LivingKnox/LK_NotebookPages.lua:29` | 7 |
| `LK.supplyDeliver` | `shared/LivingKnox/LK_NotebookProvider.lua:569` | 15 |

Vingt et une autres fonctions du runtime n'ont **que des appelants dans les tests** (ex. `Ex.cancel` `server/LivingKnox/LK_Expeditions.lua:1512`, `Reports.rejectedOf` `LK_Reports.lua:311`, `Bodies.scanAll` `LK_Bodies.lua:692`, `Decisions.refusalFor` `LK_Decisions.lua:2265`). Environ 150 lignes. Ce sont des points d'accès pour les tests, pas du code mort.

`server/LivingKnox/LK_APITest.lua` (94 lignes) est un module de test chargé dans le runtime. Il est gardé (`isClient()`, mode debug, préfixe de partie `rstest`) et documenté : **à garder**, mais c'est le seul vrai « code de test dans la production ».

## 3. Les dix constats, par gain

Les lignes « retirables » sont des estimations. Les risques renvoient au format sauvegardé, à la synchronisation réseau et aux bancs hors jeu.

### F01 — Cinq moteurs géants, chacun avec 8 à 11 responsabilités

- **Preuve** :
  - `LK_Fortify.lua` (2 877 lignes) : dix sections déclarées, `:98` sortes de chantier, `:328` lecture du monde, `:522` plan (pur), `:795` stock, `:877` autorité, `:1140` barricades, `:1274` pourtour, `:1543` réparations, `:1836` rattrapage hors écran, `:1931` forme compacte. S'y ajoutent la file par image (`:2724-2772`), les événements de chunk et de minute (`:2842-2858`) et le scan (`:2790`).
  - `LK_Decisions.lua` (2 330) : `:345` objectifs et postes (pur), `:478` cascade (pur), `:779` et `:852` registres, `:942` entrées autorité, `:1245` membres, `:1294` aide et reddition, `:2150` refus d'ordres (≈ 180 lignes autonomes, `:2213-2311`).
  - `LK_Obstacles.lua` (1 933) : onze sections, dont les clés de foyer (`:312`, ≈ 175 lignes), les alarmes et foyers verrouillés (`:1657`, `:1815`), les fenêtres (`:616`), le passage bloqué (`:1021`).
  - `LK_Stock.lua` (1 551) et `LK_Expeditions.lua` (1 567) : dix sections chacun, dont le hors écran (`LK_Stock.lua:1072`, `LK_Expeditions.lua:1288`).
- **Conséquence** : le moindre ajout de chantier, de genre d'expédition ou de règle de refus oblige à relire 1 500 à 2 900 lignes, et les conflits d'édition se multiplient (le travail LK17 en est la preuve).
- **Correction** : *Extraire le module* (Fowler : Extract Class / Move Function) en suivant les en-têtes déjà écrits. `Fortify/` contient déjà 4 fichiers (`Barricade`, `Palisade`, `Repair`, `Wall`) : y mettre le plan pur, la lecture du monde, la persistance (`parseFort`, `packFort`, `migrate`), le hors écran et la file. Pour `Decisions`, sortir les refus dans `Decisions/Refusal.lua` et la file horaire dans F02. Pour `Obstacles`, sortir les clés et les alarmes.
- **Gain** : fichiers de 200 à 500 lignes, aucune suppression nette (≈ 0 à 100 lignes).
- **Effort** : fort. **Risque** : élevé pour `Fortify` (format compact sauvegardé, `LK13-T07`, à garder testable), moyen ailleurs.
- **Décision à prendre** : ADR puis plan, comme l'exige `developpement.md` (« aucun changement de pattern sans décision »). Brouillon : « Les cinq moteurs de Living Knox dépassent 1 500 lignes. Chacun est découpé selon les sections déjà présentes, sans changement de comportement ni de format, en un fichier par responsabilité, par chantiers vérifiés sur le banc. »

### F02 — Cinq files d'attente recopiées

- **Preuve** : voir § 2.5 (`LK_Stock.lua:1468-1505`, `LK_API.lua:1053`, `LK_Talk.lua:131`, `LK_Fortify.lua:2733-2772`, `LK_Decisions.lua:1202-1238`). Chacune a son budget par image, son compteur et son drapeau d'attente.
- **Conséquence** : un bogue de temporisation ou de reprise doit être corrigé cinq fois. Un changement de budget (par exemple pour le serveur) se fait à cinq endroits.
- **Correction** : *Extraire une abstraction* : `LivingKnox.FrameQueue` (sur le modèle de `LK_Registry.lua`), qui gère l'enfilage, le budget par image ou par heure, et la fin. Chaque module n'apporte que sa fonction de travail.
- **Gain** : ≈ 150 à 200 lignes.
- **Effort** : moyen. **Risque** : moyen (ordre d'exécution et seuils, à valider sur le banc et en campagne MP).

### F03 — Fonctions utilitaires copiées (distance, nombres, horloge, balayage)

- **Preuve** : § 2.5. `cheb` 17 fois à corps identique, `finite` 15 fois identique, `isInt` 16 fois (la version officielle existe déjà, `LK_Config.lua:73`), `now` 27 fois, `clamp` et `angleGap` 4 fois, environ 45 boucles de balayage de cases. Les variantes `dist` (`LK_Directives.lua:142`, `LK_Obstacles.lua:178`, `LK_Movement.lua:63`) ne sont **pas** identiques : à vérifier avant fusion.
- **Conséquence** : une correction de bord (par exemple `finite` sur `NaN`) doit être répétée 15 fois. Une règle de distance peut diverger d'un module à l'autre sans que personne ne le remarque.
- **Correction** : *Extraire une fonction partagée* : `LivingKnox.Num` (`finite`, `isInt`, `clamp`) et `LivingKnox.Geo` (`cheb`, `angleGap`, `squaresAround(cx, cy, r)` comme itérateur), chargés par `LK_Core` et appelés au moment de l'exécution.
- **Gain** : ≈ 90 lignes, plus environ 45 boucles réduites à un appel.
- **Effort** : faible. **Risque** : très faible (fonctions pures).

### F04 — 166 accesseurs d'une ligne qui n'ajoutent rien

- **Preuve** : `local function Bodies() return LivingKnox.Bodies end` (`LK_Health.lua:107-110`, `LK_Directives.lua:133-136`, `LK_Care.lua:71-74`), répété dans une soixantaine de fichiers. Chaque accesseur lit `LivingKnox.X` au moment de l'appel, comme le ferait une référence directe.
- **Conséquence** : le lecteur doit savoir qu'un `Bodies()` est une table et non une fonction, et chaque module ajoute 4 à 6 lignes de déclarations.
- **Correction** : *Inline* (Fowler : Inline Function). Remplacer `Bodies()` par `LivingKnox.Bodies` dans le corps des fonctions. **Vérifier** qu'aucun module ne capture la valeur au chargement (`local B = LivingKnox.Bodies` au niveau du fichier) : ce cas-là a besoin d'un accesseur, ou d'un chargement dans l'ordre des `require`.
- **Gain** : ≈ 166 lignes et une indirection en moins. Churn important (≈ 60 fichiers).
- **Effort** : moyen (scriptable, à vérifier par `rg` des captures au niveau fichier). **Risque** : faible.

### F05 — Trois sources pour les mêmes valeurs par défaut et bornes

- **Preuve** : `LK_Config.lua:12-35` (`DEFAULTS` et `INT_BOUNDS`) répète `sandbox-options.txt`. Les commentaires disent « = default de sandbox-options.txt » et renvoient à des tests (`tests/livingknox/test_lk_population.py`). `DANGER` (`LK_Config.lua:~45`) utilise déjà `{min, max, défaut}`. `LK_Initiatives.lua:61-68` lit `SandboxVars` directement.
- **Conséquence** : modifier une option oblige à toucher trois endroits. Le test de cohérence protège, mais il faut le maintenir.
- **Correction** : *Une seule table de vérité* `{min, max, défaut}` par option (même forme que `DANGER`). `DEFAULTS` et `INT_BOUNDS` en sont dérivés. Faire passer `LK_Initiatives` par `Config.readInt`.
- **Gain** : ≈ 25 lignes, un risque de désynchronisation en moins. **Effort** : faible. **Risque** : faible (les valeurs ne changent pas).

### F06 — Code mort et points d'accès de test dans le runtime

- **Preuve** : § 2.6 (4 fonctions sans appelant, ≈ 28 lignes ; 21 fonctions avec appelants de test seulement, ≈ 150 lignes ; `LK_APITest.lua`, 94 lignes).
- **Conséquence** : bruit à la lecture, surface de maintenance inutile.
- **Correction** : *Supprimer* les 4 fonctions mortes, avec leurs tests s'il y en a (règle du projet : supprimer du code, c'est supprimer aussi ses tests). Pour les 21 autres, décider au cas par cas : si la fonction sert à un test qui vérifie un comportement réel, la garder ; sinon la supprimer avec son test. Déplacer `LK_APITest.lua` dans le mod de test si le moteur de tests le permet (sinon, le garder tel quel).
- **Gain** : 28 lignes immédiatement, jusqu'à 150 lignes ensuite. **Effort** : faible pour les 4 ; moyen pour le reste. **Risque** : faible pour les 4 ; moyen pour les points d'accès (utilisés par la campagne en jeu).

### F07 — Dix-huit fonctions de plus de 80 lignes

- **Preuve** : § 2.3. Exemples : `Executor.follow` (`client/LivingKnox/LK_Executor.lua:478-620`, avec gestes, relance de chemin et erreurs), `Simulation.simulateHour` (`LK_Simulation.lua:556`, tirages, faim, expéditions, rencontres), `Care.apply` (`LK_Care.lua:362`, 139 lignes, dont les gardes au début).
- **Conséquence** : impossible à relire d'un coup ; une branche oubliée dans un élément de 140 lignes devient un bogue silencieux.
- **Correction** : *Extract Function* par étape nommée (gardes, calcul, effet). Pour `Care.apply` : une fonction de garde et une fonction par effet. Pour `simulateHour` : une fonction par phase horaire, à l'image des registres déjà en place.
- **Gain** : 0 ligne nette ; lisibilité. **Effort** : moyen, à faire fichier par fichier quand on y touche. **Risque** : faible, couvert par les bancs.

### F08 — Le déplacement est réparti sur dix fichiers

- **Preuve** : `shared/LivingKnox/LK_Movement.lua` (372), `LK_Passage.lua` (58), `LK_PassageArbiter.lua` (105), `server/LivingKnox/LK_PassageAuthority.lua` (261), `client/LivingKnox/LK_PassageSignal.lua` (106), `LK_StopPlace.lua` (80), `LK_Detour.lua` (354), `Detour/LK_DetourCorridor.lua` (167), `shared/LivingKnox/Edges/LK_Edges.lua` (131), `Edges/LK_EdgeRules.lua` (85). Total ≈ 1 700 lignes. `LK_Passage.lua:54-55` n'est qu'une fonction qui appelle `LivingKnox.PassageArbiter.decide` (`LK_PassageArbiter.lua:83`) en lui passant la table de priorités.
- **Conséquence** : une règle de passage traverse trois ou quatre fichiers. `Edges` et `EdgeRules` sont en revanche une bonne conception (ADR bords des cases) : à garder.
- **Correction** : *Fusionner les façades* après LK17 : `Passage` (58 lignes) peut être absorbé par `PassageArbiter` ou l'inverse. Le reste dépend de ce que LK17 aura supprimé. **Ne pas toucher avant la fin de LK17.**
- **Gain** : 50 à 300 lignes selon le résultat de LK17. **Effort** : moyen. **Risque** : moyen (déplacements en MP, à valider en campagne).

### F09 — Client : transport réseau recopié entre trois vues

- **Preuve** : `LK_AdminView.lua:72` (envoi), `:154` (réception), `:501-504` (abonnement) ; `LK_NpcSheet.lua:112`, `:277`, `:698-701` ; `LK_TradeView.lua` (2 envois). Le « Reste » de `LK16` le signale déjà.
- **Conséquence** : chaque nouvelle vue client refait la même tuyauterie, avec ses propres erreurs d'aiguillage.
- **Correction** : *Extraire un client de requêtes* commun (`LivingKnox.ClientRequest` : envoi, réception par module et commande, relais solo). Les trois vues ne gardent que leur présentation.
- **Gain** : ≈ 60 à 80 lignes. **Effort** : moyen. **Risque** : moyen (MP, à valider en campagne client).

### F10 — Imbrication profonde dans quelques fichiers

- **Preuve** : 33 lignes à 6 niveaux ou plus dans `LK_Obstacles.lua`, 32 dans `LK_Homes.lua` (boucles de balayage `:311-312`, `:402-403`), 24 dans `LK_Fortify.lua`.
- **Conséquence** : les branches d'exception se cachent dans les blocs imbriqués.
- **Correction** : *Guard clauses* (retours anticipés) et *Extract Function* sur les boucles de balayage (F03).
- **Gain** : 0 ligne nette. **Effort** : faible à moyen. **Risque** : faible.

## 4. Ce qui est bien et doit rester

- **Registres** : `LK_Registry.lua` (utilisé 24 fois) et ses 10 registres ont chacun au moins 4 inscriptions réelles (`registerJob` 10, `registerActivity` 8, `registerExtension` 14, `registerContext` 14, `registerKind` 8, `registerChore` 8, `registerHourly` 6, `registerEvent` 5, `registerFurnishing` 7, `registerContent` 4). Aucun registre à un seul utilisateur : pas de sur-abstraction à retirer.
- **Règles pures** : `shared/LivingKnox/Edges/LK_EdgeRules.lua` et les sections « (pur) » de `LK_Decisions` ne dépendent d'aucune fonction du jeu. Garder cette séparation : c'est elle qui rend les bancs rapides.
- **Découpage existant** : `server/LivingKnox/Fortify/`, `Decisions/`, `Routines/`, `Jobs/`, `Expeditions/`, `Chores/`. C'est le modèle à étendre, pas à défaire.
- **Dimensionnement des six valeurs `ZombieEngage*`** : décision utilisateur du 2026-10-13 (rôle par rôle), pas un excès de réglages.
- **Options sandbox** : 33 options, toutes lues. Pas de clé morte.
- **Kahlua** : 0 appel à `next(` ; aucun littéral non ASCII détecté (contrôle rapide, hors commentaires). Rien à corriger.
- **Compteurs `count(...)`** : chaque module a son propre `count` sur sa propre table de statistiques (24 fichiers). Ce n'est pas une duplication à fusionner aveuglément.
- **Règles de refus des ADR** : la liste « à ne pas faire » de l'ADR `adr-remise-en-ordre-solid.md` (D04) reste valable : pas de registre pour les verbes de l'exécutant (`LK_Executor`, trois verbes), pas de registre pour la nature d'obstacle, pas d'escalade de déplacement. Ne pas sur-corriger ces points.
- **Bonne séparation autorité / client / partagé** : `server/` décide, `client/` présente et exécute, `shared/` porte les règles. Aucun constat sur ce point.
- **Garde du module de test** : `LK_APITest.lua` refuse toute action hors mode débogage et hors partie de test. Documenté, à conserver.

## 5. Ordre de travail proposé (LK17 d'abord)

Phase 0 : **terminer LK17**, banc vert. Ne toucher ni `LK_Obstacles.lua`, ni `LK_Directives.lua` (`planDetour`, `hazardsOnLine`), ni le cluster de déplacement (F08) avant sa clôture.

Phases 1 et 2 : sans conflit avec LK17, risque faible.
1. F03 : `LivingKnox.Num` et `LivingKnox.Geo` (fonctions pures). Commencer par les fichiers hors LK17.
2. F06 (4 fonctions mortes), puis F04 (accesseurs) hors fichiers LK17.
3. F05 : une table `{min, max, défaut}` par option.

Phases 3 et 4 : mécanique commune.
4. F02 : `LivingKnox.FrameQueue`, en commençant par `LK_Talk` et `LK_API` (les plus simples), puis `LK_Stock`, `LK_Fortify`, `LK_Decisions`.
5. F09 : client de requêtes commun (`AdminView`, `NpcSheet`, `TradeView`).

Phase 5 : découpage des moteurs (un ADR, puis un plan par moteur, selon `chantier-adr`).
6. F01a : `LK_Fortify`, en premier car les sections et le dossier `Fortify/` existent déjà.
7. F01b : `LK_Stock` et `LK_Expeditions`.
8. F01c : `LK_Decisions` (refus et file horaire) puis `LK_Obstacles` (clés et alarmes), après LK17.
9. F08 : cluster de déplacement, après LK17.

Phase 6 : au fil des modifications.
10. F07 (fonctions longues) et F10 (imbrication), fichier par fichier, sans chantier dédié.

Chaque étape : bancs hors jeu verts sans changer un attendu, luacheck sans hausse, puis campagne solo et MP à la fin de la phase (règle « les tests font foi »).

## 6. Décisions à trancher (une à la fois)

1. **Découpage de `LK_Fortify`** : (a) étendre le dossier `Fortify/` existant, (b) fichiers plats `LK_Fortify_*.lua` à côté, (c) ne pas découper et seulement extraire la file (F02) et les utilitaires (F03).
2. **Accesseurs (F04)** : (a) tout inliner maintenant, (b) inliner seulement hors fichiers chargés au niveau fichier, (c) garder les accesseurs, par prudence sur l'ordre de chargement.
3. **Points d'accès de test (F06)** : (a) les garder tous, (b) supprimer les 21 avec leurs tests, (c) déplacer ce qui peut l'être dans le mod de test.

## 7. Limites et points à vérifier

- Les mesures portent sur l'arbre de travail du 2026-11-16, avec les modifications non commitées de LK17. Les chiffres bougeront après LK17.
- **LK17 et ses noms** : `LK_Routing.lua`, `windowRefusedAt` et `planDoors` n'apparaissent pas dans l'arbre actuel (`rg` nul). LK17 les a peut-être déjà retirés, ou ils portent un autre nom : à confirmer auprès de l'agent qui édite. Aucun constat ci-dessus ne repose sur ces noms.
- Longueurs de fonction estimées par indentation : une erreur de ±2 lignes est possible, pas davantage.
- Code mort détecté par nom (`rg -w`) : un nom partagé peut masquer un appel mort. Les 4 fonctions retenues ont été vérifiées à la main (aucune occurrence hors définition, dans `media/lua`, `tests/` et `dev/`).
- Les corps de `cheb` et de `finite` ont été comparés sur 3 exemples chacun (identiques). Les 17 et 15 occurrences n'ont pas été comparées une à une : à vérifier au moment du chantier F03.
- Aucun test exécuté, aucun test en jeu. Les estimations de lignes sont des estimations.
- Passe de lecture : les listes de fonctions et les en-têtes de section ont été lus en entier ; les fichiers eux-mêmes ont été survolés (extraits de 3 à 25 lignes autour des constats). Aucun fichier n'a été lu en entier.

## Annexe : fichiers et mesures

- Mesures brutes : script de mesure local (lignes, fonctions, longueur par indentation, appelants par `rg`), non versionné.
- Fichiers cités : `server/LivingKnox/LK_Fortify.lua`, `server/LivingKnox/LK_Decisions.lua`, `server/LivingKnox/LK_Obstacles.lua`, `server/LivingKnox/LK_Stock.lua`, `server/LivingKnox/LK_Expeditions.lua`, `server/LivingKnox/LK_Directives.lua`, `server/LivingKnox/LK_Simulation.lua`, `server/LivingKnox/LK_Care.lua`, `server/LivingKnox/LK_Homes.lua`, `server/LivingKnox/LK_Talk.lua`, `server/LivingKnox/LK_API.lua`, `server/LivingKnox/LK_Relations.lua`, `server/LivingKnox/LK_Health.lua`, `server/LivingKnox/LK_Defense.lua`, `server/LivingKnox/LK_Admin.lua`, `server/LivingKnox/LK_Initiatives.lua`, `server/LivingKnox/LK_Passage.lua`, `server/LivingKnox/LK_APITest.lua`, `shared/LivingKnox/LK_Config.lua`, `shared/LivingKnox/LK_Registry.lua`, `shared/LivingKnox/LK_Movement.lua`, `shared/LivingKnox/LK_PassageArbiter.lua`, `shared/LivingKnox/LK_NotebookProvider.lua`, `shared/LivingKnox/Edges/LK_EdgeRules.lua`, `client/LivingKnox/LK_Executor.lua`, `client/LivingKnox/LK_AdminView.lua`, `client/LivingKnox/LK_NpcSheet.lua`, `client/LivingKnox/LK_NotebookPages.lua`, `client/LivingKnox/LK_DebugView.lua`, `media/sandbox-options.txt`.
- Documents lus : `Workshop/AGENTS.md`, `RadioSurvivor/docs/developpement.md`, `docs/architecture/decisions/` (index, `adr-remise-en-ordre-solid.md`, `adr-bords-des-cases.md`), `docs/annexes/audits/audit-solid-livingknox-2026-11-13.md` (en-tête), `docs/annexes/plans-termines/LK16-remise-en-ordre-solid.md` (état et « Reste »), `docs/annexes/plans-termines/LK17-chemin-vanilla.md` (en-tête).
