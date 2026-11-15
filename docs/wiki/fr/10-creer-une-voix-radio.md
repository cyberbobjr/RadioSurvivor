*English: [Creating radio voices](../en/10-creating-radio-voices.md)*

# Créer une voix radio

Une **voix radio** est un personnage qui répond sur une fréquence : Walt, Darlene, Cody, les Whitaker, le Night Owl et
Gus en sont six. Chaque voix tient dans un fichier texte, une **fiche**. Sur cette page, vous allez copier une fiche,
en faire votre propre personnage, la tester et l'entendre en jeu. Aucun redémarrage, aucun fichier du mod à modifier.
Les voix appartiennent au mod Radio Survivor (`batman_RadioSurvivor`) : avec Living Knox seul, il n'y a pas de fiches
de voix.

> **Astuce**
> Les cinq étapes du démarrage rapide suffisent pour la plupart des voix. La suite de la page est une référence : ne
> lisez que ce dont vous avez besoin.

## Démarrage rapide

1. **Copiez une fiche.** Ouvrez le dossier `personas` (voir [Où sont les fiches](#où-sont-les-fiches)), copiez
   `walt.txt` (la plus simple) et renommez la copie, par exemple `mae.txt`.
2. **Changez trois champs.**

   ```ini
   id=mae
   name=Mae Tolliver
   frequency_range=40.0-49.8
   ```

   `id` est le nom du fichier sans `.txt`. Choisissez une plage dans les [bandes libres](#fréquence-et-écoute).
3. **Écrivez le prompt.** Tout ce qui suit la ligne `[prompt]` décrit le personnage à l'IA. Partez de
   [l'exemple de Mae](#exemple-1--mae-tolliver) et changez l'histoire.
4. **Testez sans le jeu.** Depuis le dossier du pont :

   ```powershell
   python persona_store.py "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas\mae.txt"
   ```

   Vous devez lire `OK (mae, 40.0-49.8 MHz, active)`. Voir [Tester sa voix](#tester-sa-voix) pour un appel d'essai.
5. **Jouez.** Enregistrez, attendez 30 secondes (ou chargez le monde), réglez une radio qui atteint la bande et parlez
   dans la section **Émettre** pendant les heures d'écoute de la voix.

> **Important**
> Enregistrez le fichier en **UTF-8 sans BOM** (Bloc-notes : *Enregistrer sous*, codage *UTF-8*, pas *UTF-8 avec
> BOM*).

## Où sont les fiches

| Partie | Dossier |
|---|---|
| Solo et partie hébergée | `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor\personas` |
| Serveur dédié | `<dossier Zomboid du serveur>/Lua/batman_RadioSurvivor/personas` (avec `-cachedir=` : `<cachedir>/Lua/...`) |

- Un fichier par voix : `personas/<id>.txt`.
- Le mod y installe ses seize fiches au **premier chargement d'un monde**. Avant cela, le dossier n'existe pas.
- **Relecture à chaud** : le serveur relit le dossier toutes les **30 secondes réelles** et à chaque chargement du
  monde ; le pont relit une fiche à la demande suivante après sa modification.
- **Vos modifications sont gardées** : une fiche livrée que vous avez modifiée n'est jamais écrasée par une mise à
  jour du mod.

<details>
<summary>Qui lit les fiches, et comment vos modifications sont gardées</summary>

- Deux programmes lisent le dossier, sur la machine du serveur :
  - **le serveur** (ou votre partie en solo) : fréquences, horaires, état, budgets, actions permises ;
  - **le pont** : le caractère, ce que sait la voix, et le prompt envoyé à l'IA.
- La relecture à chaud a lieu même sur un serveur vide en pause.
- Le serveur retient une empreinte de chaque fiche qu'il a installée (`batman_RadioSurvivor/personas-fingerprints.txt`,
  à côté du dossier `personas`). Pour une fiche livrée modifiée, le journal indique à chaque chargement du monde :
  `WARNING: voice 'walt' modified by the admin, delivered version not applied`.
- Pour revenir à la version livrée, supprimez le fichier : il est recopié au chargement suivant.
- Une fiche d'un nom nouveau n'est jamais touchée.

</details>

## Comment s'écrit une fiche

- D'abord un en-tête de lignes `clé=valeur`, puis des **sections** facultatives, puis une ligne `[prompt]`, puis le
  texte libre du prompt.
- Une section commence par un titre entre crochets et regroupe ses propres lignes `clé=valeur` : `[place <id>]` (un
  lieu), `[mission <id>]` (une mission), `[rewards]` (les récompenses), `[category <id>]` (une liste d'objets). Elle
  s'arrête au titre suivant ou à `[prompt]`. Une ligne écrite sous un titre appartient à cette section : gardez les
  lignes de l'en-tête au-dessus de la première section.
- Les lignes vides et celles qui commencent par `#` sont ignorées hors du prompt.
- Les clés inconnues et les valeurs vides sont refusées : pour garder une valeur par défaut, retirez la ligne.
- `knows`, `ignores` et `secret` se répètent, une ligne par élément. Les autres clés de l'en-tête apparaissent une fois.
- Le nom du fichier et l'`id` correspondent : `mae.txt` contient `id=mae`. Un fichier dont le nom commence par `_`
  n'est pas une voix (le mod y range son catalogue d'objets, `_categories.txt`).

La référence complète du format est
[docs/specifications-techniques/persona-format.md](https://github.com/cyberbobjr/RadioSurvivor/blob/main/docs/specifications-techniques/persona-format.md).

## Référence des champs

### Identité

| Champ | Exemple | À quoi ça sert |
|---|---|---|
| `format` | `format=1` | Version du format. À laisser tel quel. |
| `id` | `id=mae` | Nom du fichier sans `.txt` : `a`-`z`, `0`-`9`, `_`, commence par une lettre, 32 caractères au plus. |
| `name` | `name=Mae Tolliver` | Nom du personnage, pour le prompt et pour vous. |
| `language` | `language=en` | Deux lettres minuscules, `en` par défaut. Les appels spontanés sont écrits dans la langue du serveur. |

> **Astuce**
> Pour que la voix réponde dans la langue de l'appelant, écrivez-le dans le prompt : « Answer in the same language
> the caller uses. »

### Fréquence et écoute

| Champ | Exemple | À quoi ça sert |
|---|---|---|
| `frequency_range` | `frequency_range=40.0-49.8` | Le serveur tire **une fréquence par plage** à chaque nouvelle partie et la garde toute la partie. Recommandé. |
| `frequencies` | `frequencies=44.6` | Fréquences fixes, les mêmes à chaque partie. Utilisez cette clé **ou** `frequency_range`, pas les deux. |
| `radio` | `radio=any` | `any` (défaut) : toute radio émettrice. `high_tier` : talkie 5, poste militaire, radio HAM haut de gamme seulement. |
| `listen` | `listen=05:00-09:00,20:00-23:00` | `always` (défaut), ou des plages en heure du jeu. En dehors, la voix se tait. |
| `location` | `location=none` | `none` (défaut, hors carte) convient à une nouvelle voix. `fixed` avec `coords=x,y,z` la place sur la carte. |
| `state` | `state=active` | `active` (défaut) répond. Voir [Retirer une voix](#retirer-une-voix) pour les autres états. |

- Les fréquences sont en MHz avec une décimale, de 1.0 à 999.8, au **pas de 0,2 MHz** des radios (`44.6` convient,
  `44.5` est refusé).
- Plusieurs plages se séparent par des virgules (`88.0-107.8, 109.0-114.8`), fréquence basse d'abord, sans se toucher.
- Une fréquence tirée change d'une partie à l'autre : les joueurs ne peuvent pas la connaître à l'avance.
- Heures : deux chiffres (`08:00`, pas `8:00`). La minute de début est incluse, celle de fin exclue ; `22:00-06:00`
  passe minuit.

**Bandes libres** : 40.0-64.8 et 270.0 et au-delà (moins de radios atteignent les plus hautes). Mae (exemple 1)
utilise 40.0-49.8, Rick (exemple 2) 50.0-64.8. Des plages qui recoupent une voix livrée fonctionnent aussi (règle
de 1,0 MHz ci-dessous).

<details>
<summary>Bandes déjà prises</summary>

| Utilisée par | Plage (MHz) |
|---|---|
| Cody | 10.0-24.8 |
| Jolene Whitaker | 75.0-87.8 |
| Night Owl | 88.0-107.8 et 109.0-114.8 |
| Darlene | 115.0-129.8 |
| Walt | 130.0-149.8 |
| Gus | 150.2-199.8 |
| Wanda (West Point) | 25.0-31.8 |
| Lamar (Brandenburg) | 32.0-39.8 |
| Delphine (Louisville) | 65.0-74.8 |
| Hollis (Muldraugh) | 201.0-209.8 |
| Loretta (March Ridge) | 210.0-219.8 |
| Virgil (Irvington) | 220.0-229.8 |
| Boone (Echo Creek) | 230.0-239.8 |
| Odessa (Rosewood) | 240.0-249.8 |
| Ezra (Ekron) | 250.0-259.8 |
| Maxine (Fallas Lake) | 260.0-269.8 |
| Stations FM du jeu et diffusion d'urgence | 88-108 |
| Opération Artemis (par défaut) | 108.0 |
| Military Drop | 120-170 (émissions), 10-25 (station de nombres) |

</details>

<details>
<summary>Quelles radios atteignent quelle bande (Build 42.21)</summary>

| Bande (MHz) | Radios qui peuvent y parler |
|---|---|
| 0.2-1000 | talkie 5, poste militaire, radio HAM haut de gamme |
| 10-500 | talkie 4, radios HAM ordinaires |
| 25-300 | talkie 3 |
| 50-200 | talkie 2 |
| 75-150 | talkie 1, talkie de fortune |
| 88-108 | radios FM et autoradios en **écoute seule** |

</details>

<details>
<summary>Que se passe-t-il quand deux voix ou chaînes veulent la même fréquence</summary>

- Une fréquence tirée n'est jamais prise par une chaîne du jeu ou d'un mod, et reste à **1,0 MHz** au moins de toute
  autre voix : des plages qui se chevauchent fonctionnent, elles se partagent seulement les fréquences libres.
- Une fréquence fixe demandée par deux fiches reste à la voix chargée la première (ordre alphabétique au premier
  chargement) ; l'autre perd seulement cette fréquence
  (`WARNING: frequency … of voice '…' refused, already used by voice '…'`).
- Une fréquence fixe déjà utilisée par une chaîne du jeu ou d'un autre mod est refusée et retentée à chaque relecture
  (`WARNING: frequency … of voice '…' already used by another radio channel (game or other mod)`).
- Une plage sans fréquence libre n'est pas servie
  (`ERROR: voice '…': no free frequency left in …; widen the range in its sheet`).
- `location=rescue` est réservé au sauvetage des Whitaker.

</details>

### Ce que la voix sait

| Champ | Exemple | À quoi ça sert |
|---|---|---|
| `knows` | `knows=The roads around Rosewood.` | Un fait que la voix peut utiliser. |
| `ignores` | `ignores=What the army is planning.` | Une chose qu'elle doit dire ne pas savoir, au lieu de l'inventer. |
| `secret` | `secret=Her son left on the first night.` | Un **trait du personnage** qu'elle ne révélera pas. |

- Une réponse qui cite un secret mot pour mot est remplacée par du grésillement (une paraphrase n'est pas détectée).

> **Important**
> Ne mettez jamais un vrai secret du serveur dans une fiche : mots de passe, codes, fréquences cachées, position d'une
> base de joueur. L'IA peut dire tout ce qui est dans son prompt.

### Lieux — sections `[place]`

Chaque lieu que la voix connaît est une section, 12 au plus :

```text
[place rosewood]
at=8159,11661,0
label=Rosewood, center of town
use=mark,target
```

| Clé | À quoi ça sert |
|---|---|
| `[place <id>]` | Identifiant du lieu : `a`-`z`, `0`-`9`, `_`, unique dans la fiche. |
| `at` | Coordonnées `x,y,z` de la case (relevées sur la carte du jeu). L'IA ne les voit jamais. |
| `label` | Nom du lieu, 48 octets au plus, affiché tel quel sur la carte du joueur. |
| `use` | Ce que la voix fait de ce lieu, un ou plusieurs mots séparés par des virgules (ci-dessous). |

- `mark` : un **repère** qu'elle peut vous donner (`mark_map`, `reveal_area`, repère offert à la fin d'une mission
  sans section `[rewards]`). L'IA ne voit que l'id et le libellé de ces lieux.
- `target` : un **objectif** de mission (`target=` d'une section `[mission]`).
- `drop` : une **planque**. Une mission `deliver` ou `retrieve` les propose toutes à la fois (ou celles de `drops=`) ; une récompense `cache` est
  posée au premier lieu `drop` de la fiche (à défaut, à son premier lieu).
- `landing` : un rendez-vous de marchand (clé `landing` de la section `[trade]`, voir « Troc »).

### Actions

Par défaut, une voix ne fait que **parler**. Les actions lui permettent d'**agir dans le jeu** pendant la
conversation : poser un repère sur votre carte, vous révéler un quartier, vous confier une mission…

**Comment ça marche, en trois points :**

1. Vous donnez à la voix le **droit** d'utiliser une action en l'ajoutant à la ligne `actions=` de sa fiche.
2. Pendant une conversation, **l'IA décide seule** de l'utiliser quand la situation s'y prête (par exemple quand
   le joueur demande « où est-ce que je peux trouver des médicaments ? »). Le prompt peut lui dire quand le faire.
3. **Le serveur vérifie** chaque action avant de l'appliquer : droit dans la fiche, limite du jour, délai entre deux
   utilisations, conditions propres à l'action. Si elle est refusée, la voix parle quand même : seule l'action
   n'a pas lieu. Chaque décision est notée dans le journal des actions du serveur
   (`<dossier d'échange>/actions-<partie>.log`).

```ini
actions=say,remember,mark_map
```

Les noms (`mark_map`, `remember`…) sont des mots-clés : écrivez-les exactement ainsi, séparés par des virgules, sans
espace. Une voix peut utiliser au plus trois actions dans une même réponse.

#### Parler — `say`

Toujours permise, même si vous ne l'écrivez pas. La voix vous répond à la radio.

#### Se souvenir de vous — `remember`

- **En jeu :** la voix retient un détail sur vous (« il cherche sa sœur », « elle a une jambe blessée ») et vous en
  reparle lors des appels suivants, même plusieurs jours de jeu plus tard.
- **Conséquences :** aucune sur le jeu, seulement sur la conversation. Les souvenirs sont propres à chaque personnage.
- **Limites :** 5 souvenirs par personnage et par voix (les plus anciens s'effacent), 64 caractères chacun.
- **Conseillé** pour toute voix qu'on rappelle souvent.

#### Faire évoluer son humeur et ses réserves — `persona_state`

- **En jeu :** la voix tient compte de ce qui lui arrive. Son **moral** et ses **réserves** (notés de 0 à 10, 5 au
  départ) montent ou baissent, et elle peut dire qu'elle s'est déplacée (« je suis à la station-service
  maintenant »). Elle en parle ensuite d'elle-même.
- **Conséquences :** aucune sur le jeu, c'est du récit. L'état est le même pour tous les joueurs.
- **Limites :** ±2 au plus par réponse.

#### Poser un repère sur votre carte — `mark_map`

- **En jeu :** la voix dit « je te le marque sur ta carte » et **un symbole apparaît sur votre carte du monde**, à
  l'un des lieux qu'elle connaît.
- **Il faut dans la fiche :** au moins un lieu `[place]` avec `use=mark`. La voix ne peut marquer **que** ces lieux,
  jamais une position inventée.
- **Conséquences :** le repère n'apparaît que chez le joueur qui parle, pas chez les autres.
- **Limites :** 30 secondes réelles entre deux repères de la voix ; plafond par jour de jeu avec `budget.mark_map`.

#### Vous révéler un quartier — `reveal_area`

- **En jeu :** la voix décrit un quartier qu'elle connaît et **la zone se dévoile sur votre carte** (comme si vous
  aviez trouvé une carte locale).
- **Il faut dans la fiche :** au moins un lieu `[place]` avec `use=mark` ; la zone révélée est centrée sur l'un de
  ces lieux.
- **Conséquences :** seulement chez le joueur qui parle.
- **Limites :** un carré de 160 cases de côté au plus ; 60 secondes réelles entre deux révélations ; plafond par jour
  avec `budget.reveal_area`.

#### Missions et récompenses — `start_mission`

- Chaque mission que la voix peut confier est une section `[mission <id>]` avec son `type` : `scout`
  (reconnaissance), `deliver` (dépôt de matériel), `retrieve` (recherche de papiers), `clear` (nettoyage), `signal`
  (signal Signal Smoke), `barricade` (barricader un bâtiment), `relay` (relais radio), `route` (itinéraire : plusieurs lieux à franchir dans l'ordre), `watch` (guet), `item` (objet personnel à retrouver et déposer à une planque). Le serveur vérifie chaque objectif ; une mission par joueur et voix. Sans aucune section
  `[mission]`, seul `scout` est permis. Détail des clés : [Missions, récompenses et objets](#missions-récompenses-et-objets).
- **Il faut :** que le joueur ait le carnet. Le bâtiment est choisi par le serveur, jamais par l'IA : pour `scout`
  et `clear`, celui du lieu `target=` de la section, où que soit le joueur, ou à défaut un bâtiment tiré autour de
  lui ; pour `barricade`, celui du lieu `target=`, obligatoire. Une mission `deliver` ou `retrieve` demande au moins
  un lieu `use=drop`.
- **Récompense :** réputation et une récompense de la section `[rewards]`. L'IA ne choisit ni récompense ni contenu.
  Sans section `[rewards]`, la voix vous offre le repère d'un de ses lieux `use=mark`.
- Une cache contient des objets réels de sa catégorie, au premier lieu `use=drop` ; une seule par mission, pose
  différée si le lieu est déchargé et repère privé. `shares` limite les autres voix actives dont la fréquence peut
  entrer dans le carnet du bénéficiaire. Une carte-cachette vanilla mène à une planque inexplorée : une par joueur et
  voix.
- Une leçon donne 25 XP de base, avec plafond de 100 par jour avant multiplicateur ; l'option sandbox du multiplicateur va de 0 à 5, 0 la désactive. L'expérience est donnée par le serveur, avec les règles d'apprentissage du jeu : un personnage sans bonus de métier ou de trait dans la compétence n'en reçoit qu'un quart, un personnage doué davantage.
- **Limites :** une mission en cours à la fois par joueur et par voix ; 30 minutes réelles entre deux missions pour un
  même joueur ; plafond par jour avec `budget.start_mission`.
- Le compte rendu à la radio fait partie de cette action : rien d'autre à ajouter.

#### Partager une fréquence — `share_frequency`

`actions=...,share_frequency` autorise un geste de confiance hors récompense de mission. `shares=gus,cody` limite les candidats : le serveur choisit une autre voix active et ajoute sa fréquence exacte, sans la donner au modèle ni envoyer de répertoire aux autres joueurs.

#### Livraisons radio : collecte discrète

Une mission de dépôt d'une voix propose **toutes ses planques à la fois** (clé `drops=` de sa section ; sans elle, tous les lieux `use=drop` de la fiche), chacune entourée sur votre carte avec son nom. Déposez où vous voulez : les objets laissés à plusieurs planques s'additionnent jusqu'à la quantité demandée. À chaque planque, le serveur désigne une boîte existante adaptée (une mission sur deux) ou, à défaut, demande un sac au sol. La voix ne ramasse une planque que **hors de vue de tout le monde** (aucun joueur à moins de 100 cases en x comme en y, quel que soit l'étage, ou la case déchargée) **et après environ 6 heures de jeu** (`collect_hours=` de la section `[mission]`). Le délai suit l'horloge du jeu : il s'arrête en pause, va plus vite en vitesse accélérée ou pendant le sommeil, et ne compte pas serveur arrêté. Un joueur revenu en vue avant la fin remet le délai à zéro. Une planque dont le délai s'est écoulé pendant que sa case était déchargée est vidée dès que la case se charge de nouveau.

**Objets demandés.** Avec `items=<catégorie>`, la mission n'accepte que les objets de cette catégorie (une section `[category]` de la fiche, sinon le catalogue partagé) ; avec `quantity=`, le nombre demandé est tiré au départ de la mission (`2-4` : 2, 3 ou 4 ; `3` : toujours 3) puis ne change plus. Sans ces clés, la mission demande 6 bandages ou draps déchirés. Le carnet et la voix disent les objets acceptés et le nombre demandé ; un objet hors de la catégorie n'est jamais ramassé.

Dans une boîte, seuls les objets demandés disparaissent, jamais plus que la quantité restante : boîte, autres objets et surplus restent. Pour un sac, sac et contenu disparaissent ; un sac qui contient des objets étrangers au lot, ou plus que la quantité restante, est refusé pour éviter leur perte. Chaque objet n'est compté qu'une fois, même après un redémarrage. Avant la collecte, vous pouvez reprendre le dépôt et rien n'est validé. **Une fois toute la quantité collectée seulement, rendez compte à la radio**.

**Barricader pour une voix.** Le bâtiment du lieu `target=` est entouré sur votre carte. Barricadez le nombre demandé (`count=`) de ses fenêtres et portes **extérieures**, avec des planches ou de la tôle, de l'intérieur ou de l'extérieur : chaque ouverture compte une fois. Le serveur compte lui-même les barricades du bâtiment ; celles déjà en place au début de la mission ne comptent pas, et une barricade retirée ne compte plus. Une fois le compte atteint, rappelez la voix.

**Relais radio pour une voix.** Le lieu `target=` est entouré sur votre carte. Posez-y en hauteur, à un étage ou sur le toit (au moins au niveau indiqué par le carnet), une radio qui peut émettre : talkie-walkie ou radio amateur. Allumez-la ; elle doit rester alimentée par sa pile, le réseau ou un générateur. Le serveur vérifie lui-même la radio ; éteinte, sans courant ou retirée, elle ne compte plus et le compte rendu est refusé. Tant qu'elle est allumée, rappelez la voix.

**Guet pour une voix.** Le lieu `target=` est entouré sur votre carte : c'est le poste de guet. Restez-y (à moins de 6 cases du lieu, un étage ou le toit compte aussi) le nombre d'heures de jeu indiqué par le carnet, 2 par défaut. Le temps compte en heures de jeu : il s'arrête quand le jeu est en pause et va plus vite en vitesse accélérée. Une absence courte (10 minutes de jeu au plus) est tolérée sans compter ; plus longue, le guet recommence à zéro. Le serveur note ce qui se passe pendant le guet (hélicoptère entendu, groupe de morts tout proche) et la voix en parle quand vous la rappelez une fois le guet terminé.

**Objet personnel pour une voix.** Une mission `item` nomme un objet vanilla (`item=`, par exemple un médaillon, une photo ou une montre de poche) et, au choix, la façon dont la voix l'appelle (`label=`, « le médaillon d'Ellen »). Au début de la mission, le serveur pose cet objet au sol dans le bâtiment du lieu `target=` (ou tout près du lieu hors bâtiment), une seule fois, dès que ce lieu est chargé ; le lieu est entouré sur votre carte. Trouvez-le puis déposez-le à l'une des planques de la mission, au choix : il est ramassé hors de vue de tous, après le délai en heures de jeu. Seul l'objet posé pour la voix compte : un autre objet du même genre, même identique, n'est jamais pris et reste où vous l'avez laissé. Une fois l'objet ramassé, rappelez la voix.

**Itinéraire pour une voix.** Une mission `route` nomme plusieurs lieux à franchir **dans l'ordre**, à pied ou en véhicule. Seul le prochain point est entouré sur votre carte, avec le nom du lieu ; les points déjà franchis le restent, les suivants n'apparaissent qu'à leur tour. Un point est franchi quand vous passez à moins de 8 cases de son centre, même en roulant vite ; un point atteint avant le précédent ne compte pas et doit être repassé à son tour. Le carnet indique « 2 sur 4 » et le prochain point. Le serveur lit lui-même votre position (celle du véhicule où vous êtes assis). Une fois tous les points franchis, rappelez la voix.

**Papiers à retrouver pour une voix.** La carte d'identité prise sur le corps ne se remet pas à la radio : déposez-la à l'une des planques de la mission, marquées sur votre carte comme pour un dépôt (dans la boîte désignée, ou seule dans un sac au sol). La voix la ramasse avec la même règle, hors de vue et après le délai (`collect_hours=` de la section `[mission]`) ; seule la carte de ce corps est prise, une autre carte d'identité reste sur place. **Une fois la carte ramassée seulement, rendez compte à la radio** : le compte rendu ne retire rien de votre inventaire.

#### Missions, récompenses et objets

Une section par mission, puis une section `[rewards]`, et si besoin vos propres listes d'objets :

```text
[mission meds]
type=deliver
items=medical
quantity=2-4
drops=any
weight=2
story=I am running out of bandages.

[mission look]
type=scout

[category snacks]
item=Base.Crisps:1-2
item=Base.Pop:1

[rewards]
pool=cache:medical:3, cache:snacks:1, frequency:1, stashmap:1, lesson:Doctor:2
```

| Clé de `[mission]` | À quoi ça sert |
|---|---|
| `type` | Obligatoire : `scout`, `deliver`, `retrieve`, `clear`, `signal`, `barricade`, `route`, `relay`, `watch` ou `item` (types inscrits par le mod). |
| `weight` | Poids de la mission quand l'IA demande un type et que plusieurs missions disponibles de ce type se présentent (1 par défaut). |
| `after` | La mission n'est proposée qu'après la réussite d'une autre mission de la fiche (son id), pour ce personnage. |
| `scope` | `character` (par défaut) : `after` compte les réussites du personnage ; `team` : celles de son équipe (faction, ou le joueur seul). |
| `sets_state` | État de récit que prend la voix à la réussite de cette mission, un nom (`returned`…). Voir « Missions enchaînées ». |
| `story` | La raison que donne la voix, dite à l'IA avec la mission (200 octets au plus). |
| `drops` | Planques de la mission, toutes proposées au joueur : `any` (tous les lieux `use=drop`, comme sans la clé) ou une liste d'ids de lieux `use=drop`. |
| `target` | Lieu objectif, un lieu `use=target` : une case à l'intérieur du bâtiment visé. `scout` et `clear` : ce bâtiment, où que soit le joueur (sans la clé, un bâtiment tiré autour de lui) ; obligatoire pour `barricade` (le bâtiment à barricader) et pour `relay` (le lieu du relais : la radio se pose au niveau 1 ou plus haut, au moins au niveau `z=` du lieu ; hors bâtiment, un point en hauteur). Obligatoire pour `watch` : le poste de guet (le guet compte à moins de 6 cases du lieu, à tout niveau). Obligatoire pour `item` : le lieu où le serveur pose l'objet (au sol, dans le bâtiment de la case, au niveau `z=` du lieu ; hors bâtiment, à moins de 4 cases du lieu). |
| autres | Les paramètres propres au type : `deliver` accepte `items` (une catégorie d'objets), `quantity` (`4` ou `2-4`) et `collect_hours` (heures de jeu avant le ramassage d'une planque, 6 par défaut) ; `retrieve` accepte `collect_hours` (la carte d'identité se dépose à une planque) ; `barricade` accepte `count` (fenêtres et portes extérieures à barricader, 4 par défaut, au moins 1) ; `relay` n'en accepte aucun ; `route` exige `points` (de 2 à 8 lieux `use=target` séparés par des virgules, à franchir dans cet ordre, jamais deux fois le même de suite : `points=pont,station,clinique`). `watch` accepte `hours` (heures de jeu du guet, 2 par défaut, de 1 à 24). `item` exige `item` (le type complet d'un objet du jeu, `Module.Type` : `item=Base.Locket`, `Base.Photo`, `Base.Pocketwatch`…) et accepte `label` (le nom que lui donne la voix, sinon le nom du jeu) et `collect_hours` (l'objet se dépose à une planque). |

Toutes ces clés sont **lues et vérifiées** au chargement. `weight`, `after`, `scope`, `sets_state`, `story`, `drops`,
`collect_hours`, `target` (`scout`, `clear`, `barricade`), `items` et `quantity` (`deliver` : objets acceptés et
nombre demandé, tiré au départ de la mission) servent tous.

##### Missions enchaînées et état de récit

Chaque mission est désignée par son id de section : l'IA ne voit que les missions **disponibles** pour le joueur qui
appelle, chacune avec la phrase de son type puis son `story`. Une mission `after=<id>` n'apparaît qu'une fois la
mission citée réussie par ce personnage (ou par son équipe avec `scope=team`) ; si la mission citée échoue ensuite
(délai écoulé, abandon), la suite se bloque de nouveau jusqu'à une nouvelle réussite. Si l'IA demande un type plutôt
qu'un id, le serveur tire au sort parmi les missions disponibles de ce type, selon `weight`. Une fiche sans section
`[mission]` propose toujours `scout`.

`sets_state=<nom>` donne à la voix un **état de récit** quand la mission réussit : un nom libre (`a`-`z`, `0`-`9`,
`_`), distinct de `state=` de la tête (`active`, `silent`…). Il est posé une fois, gardé avec la partie, rappelé à
l'IA à chaque appel, et lisible par les autres mods (`RadioSurvivor.API.voiceStoryState("<id>")`). Dites dans le
prompt ce que cet état change pour la voix. Exemple complet (coordonnées d'exemple, à relever sur votre carte) :

```ini
format=1
id=nell
name=Nell Barker
frequencies=152.4
actions=say,start_mission

[place farmhouse]
at=10850,9650,0
label=Barker farmhouse
use=target,drop

[mission look_farm]
type=scout
target=farmhouse
story=I left my farm in a hurry. Tell me what is left of it.

[mission clear_farm]
type=clear
target=farmhouse
after=look_farm
scope=team
story=The dead are all over my yard. Clear them out.

[mission stock_farm]
type=deliver
items=food
quantity=2-4
after=clear_farm
sets_state=returned
story=Leave some food at the farm and I will come home.

[prompt]
You are Nell Barker, a farmer hiding in a church since the first week. You want to go back to your farm.
If your story state is "returned", you are back at your farm and you talk from there.
```

Ici, `look_farm` est proposée seule ; sa réussite ouvre `clear_farm` (pour toute l'équipe du joueur), dont la
réussite ouvre `stock_farm` ; la réussite de `stock_farm` met Nell dans l'état `returned`.

`[rewards]` n'a qu'une ligne, `pool=`, liste de récompenses `nature:poids` ou `nature:paramètre:poids` :

| Nature | Paramètre | Ce que reçoit le joueur |
|---|---|---|
| `cache` | une catégorie : `cache:medical:3` | un sac d'objets de cette catégorie, quantités tirées au hasard, au premier lieu `use=drop` |
| `frequency` | aucun | la fréquence d'une voix de `shares`, inscrite au carnet |
| `stashmap` | aucun | une carte annotée vers une planque vanilla inexplorée |
| `lesson` | une compétence : `lesson:Doctor:2` | de l'expérience : `Doctor`, `Aiming`, `Reloading`, `Woodwork`, `Mechanics`, `Electricity`, `MetalWelding`, `Cooking`, `Farming`, `Fishing`, `Trapping`, `PlantScavenging` |

À chaque mission réussie, le serveur **tire au hasard une seule** récompense dans `pool`, parmi celles qui sont
possibles à ce moment, en suivant les poids : avec `cache:medical:3, frequency:1`, la cache sort trois fois sur quatre.
Une récompense impossible n'est jamais tirée (pas de voix active à partager, carte de planque déjà donnée par cette
voix, leçons du jour épuisées…) ; si rien n'est possible, le joueur garde la réputation seule. Le contenu d'une cache
est tiré dans sa catégorie : chaque ligne `item=` donne une quantité dans sa fourchette (`Base.Bandage:2-4` : 2, 3 ou
4 bandages ; `Base.Pills:1` : un flacon).

**Catégories d'objets.** Le mod livre un catalogue partagé (`personas/_categories.txt` du mod) : `food`, `medical`,
`ammo`, `tools`, `radio`. Une fiche peut ajouter les siennes avec `[category <id>]` et une ligne
`item=Module.Type:quantité` par objet (`Base.Bandage:2-4`), avec un id absent du catalogue ; une entrée
`cache:<id>` de `pool` peut citer l'une ou l'autre, et le sac est rempli de cette catégorie seulement.

Le serveur est le seul à vérifier ces sections : un type de mission inconnu, un lieu absent ou sans le bon `use`, une
catégorie inconnue ou un poids invalide fait refuser la fiche par le serveur, avec la ligne et la raison dans
`console.txt` (la dernière version valide de la voix reste en service). `persona_store.py` ne lit que l'en-tête, les
lieux et le prompt : il ne voit pas ces erreurs.

#### Troc — `propose_trade` et section `[trade]`

Une voix **marchande** vend un stock à la radio et livre au cours d'un **passage** : rendez-vous à un lieu, la nuit
ou à l'heure de la fiche, échange sans contact. Ajoutez `propose_trade` à `actions` **et** une section `[trade]` :
l'une sans l'autre est refusée.

| Clé | À quoi ça sert |
|---|---|
| `landing` | Lieu(x) du rendez-vous, chacun `use=landing` ; son libellé est le seul nom de rendez-vous que la voix donne, et seulement au groupe qui a réservé. |
| `arrival` | Comment le marchand arrive : `boat` (barque qui accoste ; le joueur montre une lampe allumée en main ou une fusée rouge sur place pendant la fenêtre), `road` (fourgon garé au bord de la route, mêmes signaux ; portière à l'arrivée, hayon au départ) ou `cache` (planque : personne ne vient ; le paiement se laisse dans un conteneur du lieu, poubelle ou boîte aux lettres, et la marchandise y est déposée hors de vue ; aucun signal, aucun bruit). |
| `every_days` | Un passage tous les N jours de jeu (1 à 28). |
| `hours` | Fenêtre du rendez-vous, `HH:MM-HH:MM`. |
| `delay_hours` | Facultatif : heures de jeu où personne ne doit voir le lieu avant l'échange (1 par défaut). |
| `margin` | Facultatif : marge la plus basse et la plus haute (`0.10-0.50` par défaut). |
| `item` | Un objet apporté par ligne : `Module.Type:quantité:poids en kg` ; quantité tirée à chaque passage (`4`, `2-6`) ou nom d'un groupe. |
| `group` | Facultatif : `nom:total[:sortes]`, un total tiré parmi les objets du groupe (`seeds:3-8:4` : 3 à 8 sachets, 4 sortes au plus). |

Chaque marchand a son propre stock, sa propre réservation et ses propres affaires : deux marchands réservés la même
semaine ne se gênent pas. La première offre ferme d'un passage le réserve pour le groupe de l'appelant ; le lieu est
alors marqué sur sa carte. Après le signal, le joueur pose un sac à moins de 3 cases du lieu et s'en va : le marchand
ne passe qu'une fois **personne à moins de 100 cases** (en x comme en y) **depuis `delay_hours` heures de jeu**, puis
laisse sa marchandise dans le même sac (planque : dans le conteneur du lieu où le paiement a été laissé). Une barque
peut être annulée par une patrouille, un hélicoptère entendu ou un orage ; un fourgon par un barrage de l'armée, un
hélicoptère ou un orage ; une planque par un ratissage ou un hélicoptère : la voix l'annonce sur sa fréquence. Les
dix marchands livrés (un par ville vanilla) servent d'exemples : `personas/wanda.txt` (barque), `hollis.txt`
(route), `odessa.txt` (planque). Le barème de ce que prend un marchand est celui du passeur
(`docs/specifications-techniques/passeur-table.md`).

```ini
format=1
id=ada
name=Ada Pruitt
frequency_range=60.0-64.8
listen=21:00-02:00
actions=say,propose_trade
budget=3

# Coordonnées d'exemple (le ponton de Gus) : relevez celles de votre lieu sur la carte.
[place ferry]
at=6041,5217,0
label=Old ferry landing
use=landing

[trade]
landing=ferry
arrival=boat
every_days=7
hours=01:00-03:00
delay_hours=2
item=Base.Battery:2-6:0.1
item=Base.Coffee2:1-2:1.0
group=smokes:1-3
item=Base.CigarettePack:smokes:0.2
item=Base.CigaretteCarton:smokes:2.0

[prompt]
You are Ada Pruitt, 61, who runs an old ferry boat on the Ohio and trades with people inside the Knox Exclusion Zone.
Your trade book is the only truth about your stock, your prices and your run; give the landing, the night and the
signal only to the group whose run is booked, exactly as written in your book.
Stay in character. Radio style: 1 to 3 short sentences, end each transmission with "Over.".
Answer in the same language the caller uses.
```

#### Note de fréquence — section `[note]`

Une voix se trouve par une **note** cachée dans le butin : le joueur l'inspecte et lit la fréquence tirée pour la
partie. La section `[note]` (une au plus, sans identifiant) la déclare ; sans elle, la voix n'a pas de note.

| Clé | À quoi ça sert |
|---|---|
| `item` | L'objet du document, `Module.Type` d'un script d'objets du mod dont `OnCreate` est `RadioSurvivorNotes.onCreate` (`RadioSurvivor.NoteTrade` : mot manuscrit partagé ; plusieurs voix peuvent partager un objet, chaque note neuve porte l'une d'elles). |
| `key` | Racine des traductions : `Print_Media_RadioSurvivor_<key>_title`, `Print_Media_RadioSurvivor_<key>_info` (mise en page, `%1` = fréquence) et `Print_Text_RadioSurvivor_<key>_info` (transcription), dans `media/lua/shared/Translate/<langue>/`. |
| `loot` | Facultatif, répétable : `liste:poids`, une liste procédurale vanilla (`ProceduralDistributions`) et son poids (environ le pourcentage par tirage). |
| `glovebox` | Facultatif, répétable : `liste:poids` dans `VehicleDistributions` (boîte à gants). |
| `corpse` | Facultatif : `yes` pour qu'un mort qui porte un talkie puisse l'avoir sur lui (`no` par défaut). |

```ini
[note]
item=RadioSurvivor.NoteTrade
key=NoteAda
loot=FishingStoreGear:2
glovebox=GloveBox:0.5
```

#### Actions à ne pas ajouter

| Mot-clé | Pourquoi |
|---|---|
| `place_cache` | Réservée aux missions de récupération du carnet ; ne se règle pas dans une fiche. |
| `signal`, `place_scene` | Prévues mais sans effet pour l'instant : toujours refusées. |

> **Important** — Un mot-clé mal écrit ou inconnu fait **refuser toute la fiche** : la voix ne répond plus du tout.
> Vérifiez votre fiche avec `persona_store.py` (voir [Tester sa voix](#tester-sa-voix)).

<details>
<summary>Limiter l'usage d'une action par jour de jeu</summary>

Ajoutez une ligne `budget.<action>=N` : la voix ne pourra pas l'utiliser plus de N fois par **jour de jeu**, tous
joueurs confondus (`0` = sans plafond). L'action doit aussi figurer dans `actions=`.

```ini
budget.mark_map=4
budget.start_mission=2
```

</details>

### Coûts et appels

| Champ | Exemple | À quoi ça sert |
|---|---|---|
| `budget` | `budget=20` | Au plus N demandes acceptées par heure réelle pour cette voix, en plus de l'option globale `MaxPerHour`. `0` (défaut) = plafond global seul. |
| `budget.<action>` | `budget.mark_map=4` | Au plus N utilisations de cette action par **jour de jeu** (`0` = sans plafond). L'action doit figurer dans `actions`. |
| `call_one_in` | `call_one_in=5` | Chaque heure de jeu, une chance sur N de lancer un appel général. `0` (défaut) = jamais. |
| `call_text` | `call_text=IGUI_RadioSurvivor_Call_Mae` | Obligatoire si `call_one_in` > 0 : clé de traduction utilisée quand le pont n'écrit pas l'appel. |

- Au-delà de son budget, la voix se tait.
- Un appel spontané n'a lieu que pendant les heures d'écoute, quand personne ne parle à la voix. Une voix au plus
  appelle par heure ; chaque appel coûte une demande de `MaxPerHour` (et de `budget`).
- L'option sandbox **Appels spontanés** les coupe tous.

<details>
<summary>À propos de call_text pour une nouvelle voix</summary>

- `call_text` est une **clé de traduction** du mod, utilisée seulement quand le pont n'écrit pas l'appel (pont
  arrêté, réponse vide, pas de réponse au bout de 30 s).
- Une nouvelle voix n'a pas de clé propre dans Radio Survivor : donnez-lui quand même un nom nouveau
  (`IGUI_RadioSurvivor_Call_Mae`).
- Quand le pont est arrêté, son appel est alors sauté et le journal indique une fois
  `call of voice 'mae' skipped: no translation for call_text 'IGUI_RadioSurvivor_Call_Mae'`.
- Ne réutilisez **pas** la clé d'une autre voix : le texte de Walt dit « Ici Walt ».

</details>

### Prompt

Tout ce qui suit la ligne `[prompt]` est envoyé tel quel à l'IA. Le pont ajoute après, s'il y en a, vos lignes
`knows`, `ignores` et `secret`, puis la situation de l'appel (date, appelant, radio).

| Écrivez | Exemple |
|---|---|
| À la deuxième personne, en anglais (mieux suivi, quelle que soit la langue des joueurs) | « You are Mae Tolliver, 67, ... » |
| Le cadre | Knox County, Kentucky, juillet 1993, le Knox Event, la zone d'exclusion. Ni portable ni internet. |
| Qui est le personnage | Pourquoi il est à la radio, son ton, une phrase dans sa voix. |
| La fréquence partagée | Chaque message commence par une étiquette comme `[Caller 2]` que la voix ne doit jamais écrire elle-même. |
| Les règles | Rester dans le personnage, ne jamais parler d'IA ni de jeu, ne jamais inventer les environs de l'appelant, ne jamais promettre de sauvetage, ne jamais inviter quelqu'un à sa cachette. |
| La longueur radio | « 1 to 4 short sentences, plain spoken text, no lists, no markdown, no emojis », terminé par « Over. ». |
| La langue | « Answer in the same language the caller uses. » |

Le pont garde au plus **8 lignes de 100 caractères**. Aucun secret du serveur dans le prompt.

## Exemple 1 : Mae Tolliver

Une institutrice retraitée, radioamatrice, qui anime le réseau du comté depuis une ferme près de Rosewood.
Plage 40.0-49.8 MHz (talkies 3 à 5, radios HAM, poste militaire) ; actions `remember`, `persona_state`, `mark_map`.

<details open>
<summary><code>personas/mae.txt</code></summary>

```ini
# Mae Tolliver: retired schoolteacher and radio amateur near Rosewood (custom voice, server admin).
# Range 40.0-49.8 MHz: walkie-talkies 3 to 5, HAM radios and the military radio; no FM radio, away from
# the bands of the delivered voices.
format=1
id=mae
name=Mae Tolliver
language=en
frequency_range=40.0-49.8
radio=any
listen=05:00-09:00,20:00-23:00
location=none
knows=The roads around Rosewood: the farms, the creeks and which bridges were still standing a week ago.
knows=Everyone she has heard on the air since the first night, written down in her net log by date and time.
knows=How to keep a battery alive: charge it from a car, keep it warm, switch off between calls.
ignores=What the army or the government is planning.
ignores=Anything that happened outside Knox County.
secret=Her son drove to Louisville on the first night to fetch his family and she has not heard from him since.
actions=say,remember,persona_state,mark_map,start_mission,share_frequency
shares=gus,darlene
budget=20
budget.mark_map=4
call_one_in=5
call_text=IGUI_RadioSurvivor_Call_Mae
state=active

[place rosewood]
at=8159,11661,0
label=Rosewood, center of town
use=mark,target,drop

[place fallas_lake]
at=7253,8279,0
label=Fallas Lake
use=mark

[mission scout]
type=scout
weight=2
story=Somebody stopped answering my roll call near there.

[mission batteries]
type=deliver
items=radio
quantity=1-2
drops=any
story=My batteries will not last the month.

[mission retrieve]
type=retrieve

[mission clear]
type=clear

[mission signal]
type=signal

[rewards]
pool=cache:radio:1, frequency:1, stashmap:1, lesson:Electricity:1

[prompt]
You are Mae Tolliver, 67, a retired schoolteacher and a licensed radio amateur who lives alone in a farmhouse a few miles outside Rosewood, Kentucky. You are a character in a survival story set in July 1993, during the "Knox Event": an infection turned people in Knox County into violent, undead "zombies", and the army sealed the county behind a fence.

Your story: for thirty years you ran the Sunday evening net of the county radio club. Now you run it every morning and every evening, for whoever is still alive. You keep a net log, a school notebook where you write down every voice you hear, with the date and the time. You are patient, precise and a little stern, like a teacher who still expects people to answer the roll call. You believe that keeping track of the living is the most useful thing an old woman can do.

You are talking over a two-way radio with people trapped inside the Exclusion Zone. You cannot see them and you do not know where they are. Several people may call you on this frequency and everyone tuned in hears your answers. Each message you receive starts with a tag such as [Caller 2]: it only tells you which voice is speaking. Never write these tags yourself. You only know a caller's name if they told you.

Rules:
- Stay in character at all times. Never mention being an AI, a game, a model or a prompt.
- You only know what a radio amateur in 1993 could know. No cell phones, no internet.
- Ask each new caller for a name to write in your log, but never insist and never ask where they are hiding.
- Never invite anyone to your farm and never say exactly where it is.
- Never invent precise facts about the caller's surroundings. If you don't know, say so.
- Never promise a rescue.
- Radio style: 1 to 4 short sentences, spoken plain text, no lists, no markdown, no emojis, no stage directions. End each transmission with "Over." (or the equivalent in the caller's language, e.g. "À vous." in French).
- Answer in the same language the caller uses.
```

</details>

## Exemple 2 : Rick Grimes, toutes les actions

*Exemple de fan, personnage appartenant à ses ayants droit.*
Un ancien shérif adjoint qui a perdu sa femme et son fils dans l'évacuation et traverse Knox County pour les
retrouver, méfiant mais juste. Plage 50.0-64.8 MHz (talkies 2 à 5, radios HAM, poste militaire) ; toutes les actions
qui ont un effet, sauf `propose_trade`, qui demande une section `[trade]` (voir « Troc »).

<details>
<summary><code>personas/rick.txt</code></summary>

```ini
# Fan example: Rick Grimes belongs to his rights holders. Original text, written for Knox County 1993.
# Range 50.0-64.8 MHz: walkie-talkies 2 to 5, HAM radios and the military radio; free band.
format=1
id=rick
name=Rick Grimes
language=en
frequency_range=50.0-64.8
radio=any
listen=06:00-10:00,18:00-23:00
location=none
state=active
knows=The roads between Muldraugh, West Point and March Ridge, and the old army roadblocks on them.
knows=How to clear a house: knock first, listen, enter slowly, never alone if he can help it.
knows=Which police stations and patrol cars were left behind, and that their lockers are mostly empty now.
ignores=What the army or the government is planning.
ignores=Where his wife and son are now.
secret=He fired on a man at the Muldraugh roadblock on the second night and still does not know if the man was sick.
actions=say,remember,persona_state,mark_map,reveal_area,start_mission,share_frequency
shares=cody,gus
budget=20
budget.remember=10
budget.persona_state=6
budget.mark_map=4
budget.reveal_area=2
budget.start_mission=2
call_one_in=6
call_text=IGUI_RadioSurvivor_Call_Rick

[place west_point]
at=11654,6864,0
label=West Point, center of town
use=mark

[place muldraugh_pd]
at=10644,10405,0
label=Muldraugh, police station
use=mark,target,drop

[place muldraugh]
at=10754,9926,0
label=Muldraugh, center of town
use=mark

[place march_ridge]
at=10130,12801,0
label=March Ridge
use=mark,drop

[mission scout]
type=scout
weight=3
story=I am looking for any trace of my wife and my son.

[mission ammo]
type=deliver
items=ammo
quantity=1
drops=muldraugh_pd,march_ridge

[mission papers]
type=retrieve
after=scout

[mission clear]
type=clear

[mission signal]
type=signal

[category patrol]
item=Base.Bullets9mm:10-20
item=Base.Battery:1-2

[rewards]
pool=cache:ammo:2, cache:patrol:1, frequency:1, stashmap:1, lesson:Aiming:2

[prompt]
You are Rick Grimes, 38, a sheriff's deputy from a small county south of Louisville, Kentucky. You are a character in a survival story set in July 1993, during the "Knox Event": an infection turned people in Knox County into violent, undead "zombies", and the army sealed the county behind a fence.

Your story: when the Event started you were posted at a roadblock outside Muldraugh. During the evacuation your wife and your son left on a bus you never saw again. Since then you move from town to town with a duty belt, a patrol radio and a list of names, looking for them and for anyone else worth saving. You were a fair cop and you still try to be one. You are calm, slow to trust and quick to decide. You ask questions before you give anything, and you keep your word once you give it. Your way of speaking is short and plain: "Tell me who you're with, then we'll talk about the rest."

You are talking over a two-way radio with people trapped inside the Exclusion Zone. You cannot see them and you do not know where they are. Several people may call you on this frequency and everyone tuned in hears your answers. Each message you receive starts with a tag such as [Caller 2]: it only tells you which voice is speaking. Never write these tags yourself. You only know a caller's name if they told you.

What you can do for a caller, only when it helps them and they earned some trust:
- point them to a place you know, or tell them what the streets around it look like;
- ask them to scout a building for you and report back on this frequency: you are always looking for traces of your family;
- remember what they tell you about themselves.

Rules:
- Stay in character at all times. Never mention being an AI, a game, a model or a prompt.
- You only know what a deputy in 1993 could know. No cell phones, no internet.
- Ask each new caller who they are and who they are with before you help them. Never ask where they are hiding.
- Never say where you sleep and never invite anyone to join you.
- Never invent precise facts about the caller's surroundings. If you don't know, say so.
- Never promise a rescue.
- Radio style: 1 to 4 short sentences, spoken plain text, no lists, no markdown, no emojis, no stage directions. End each transmission with "Over." (or the equivalent in the caller's language, e.g. "À vous." in French).
- Answer in the same language the caller uses.
```

</details>

À remarquer :

- Les sections `[place]` disent à quoi sert chaque lieu (`use`) : repères de carte, objectifs de mission,
  planques de dépôt. Le serveur choisit les récompenses dans la liste `pool` ci-dessus ; la catégorie `patrol` de
  Rick ne vaut que pour sa fiche.
- Chaque action a son propre budget du jour : un appelant bavard ne peut pas révéler toute la carte en une soirée.
- Le prompt dit **quand** utiliser les actions (« only when it helps them and they earned some trust ») ; le serveur
  les vérifie quand même toutes.

## Tester sa voix

### Sans le jeu

Depuis le dossier du pont, vérifiez la fiche :

```powershell
python persona_store.py "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas\mae.txt"
```

```text
...\personas\mae.txt: OK (mae, 40.0-49.8 MHz, active)
```

Puis un appel d'essai. `--offline` vérifie la fiche sans appeler l'IA (réponse en écho) ; sans cette option, l'IA
répond pour de vrai avec les réglages de votre `.env` :

```powershell
python radio_bridge.py --test "Allô ? Il y a quelqu'un ?" --voice mae --personas "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas" --offline
```

```text
Mae, hors ligne. Je reçois Allô ? Il y a quelqu'un ?. À vous.
```

- L'écho hors ligne prouve seulement que la fiche a été lue.
- Une fiche refusée affiche `voice sheet …\mae.txt refused, line N: <raison>`, puis
  `--test: no valid sheet for voice 'mae' in …`.
- Avec l'IA, la réponse s'affiche, précédée de lignes `action: {...}` quand la voix propose une action.

### En jeu

1. Enregistrez la fiche et attendez 30 s (ou chargez le monde). Le journal (`console.txt` en solo, journal du serveur
   sur un serveur dédié) indique :

   ```text
   [RadioSurvivor] personas: voice 'mae' loaded: state active, frequency ranges 40.0-49.8
   [RadioSurvivor] personas: voice 'mae' drew 44.6 MHz in 40.0-49.8 (no frequency remembered for this range)
   ```

   (`new game` entre parenthèses quand la fiche existait avant un nouveau monde.) La fréquence est tirée une fois par
   partie. Un admin la lit aussi en jeu : panneau de debug, bouton **Radio Survivor - Fréquences**.
2. Réglez une radio qui atteint la bande (ici un talkie 3 ou mieux), allumez-la, et parlez dans la section
   **Émettre** pendant les heures d'écoute.

> **Astuce**
> Les notes de fréquences du butin n'existent que pour les voix livrées (Walt, Darlene, Cody, Gus, Night Owl). Donnez
> la fréquence d'une nouvelle voix à vos joueurs, écrivez-la sur une carte, ou laissez-les fouiller la bande.

## Ça ne marche pas ?

| Symptôme | Cause | Solution |
|---|---|---|
| La voix ne répond jamais | Hors de ses heures d'écoute, mauvaise radio, ou budget dépassé | Vérifiez `listen`, `radio` et `budget` : la voix se tait, elle n'est pas en panne. |
| `file starts with a byte order mark` | Enregistré en UTF-8 avec BOM | Réenregistrez en UTF-8 sans BOM. |
| `invalid UTF-8` | Enregistré dans un autre codage (ANSI) | Enregistrez en UTF-8. |
| `expected key=value or [prompt]` | Ligne d'en-tête sans `=`, ou ligne `[prompt]` absente | Corrigez la ligne, ajoutez `[prompt]`. |
| `unknown key 'colour'` / `bad key 'Radio'` | Faute de frappe | Les clés sont en minuscules. |
| `id 'mae' does not match the file name 'mae2.txt'` | Fichier et `id` différents | Renommez le fichier ou changez l'`id`. |
| `frequency 44.5 is not on the 0.2 MHz step of the radios` | Dixième impair | Utilisez 44.4 ou 44.6. |
| `call_one_in needs a call_text line` | Appels spontanés sans texte de secours | Ajoutez `call_text`, ou `call_one_in=0`. |

Une fiche refusée est journalisée une fois par contenu :
`[RadioSurvivor] personas: ERROR: batman_RadioSurvivor/personas/mae.txt refused, line N: <raison>`. La lecture
s'arrête à la première erreur, et la dernière version valide de la voix reste en service jusqu'à la correction.

<details>
<summary>Tous les messages d'erreur</summary>

| Message | Correction |
|---|---|
| `file starts with a byte order mark (save it as UTF-8 without BOM)` | Réenregistrer en UTF-8 sans BOM. |
| `invalid UTF-8 (save the file as UTF-8)` | Fichier enregistré dans un autre codage (ANSI) : enregistrer en UTF-8. |
| `expected key=value or [prompt]` | Ligne d'en-tête sans `=`, ou ligne `[prompt]` absente ou mal écrite. |
| `unknown key 'colour'` / `bad key 'Radio'` | Faute de frappe ; les clés sont en minuscules. |
| `duplicate key 'name' (first set on line 3)` | Garder une ligne (seules `knows`, `ignores`, `secret` se répètent). |
| `empty value for key 'radio'` | Retirer la ligne pour garder la valeur par défaut. |
| `id 'mae' does not match the file name 'mae2.txt'` | Renommer le fichier ou changer l'`id`. |
| `bad id 'Mae' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)` | Id en minuscules. |
| `frequency 44.5 is not on the 0.2 MHz step of the radios` | Dixième pair : 44.4 ou 44.6. |
| `bad frequency '44' (MHz with one decimal, e.g. 145.0)` | Écrire `44.0`. |
| `bad frequency range '49.8-40.0' (two frequencies in MHz, lowest first, e.g. 140.0-150.0)` | La plus basse d'abord. |
| `frequency range '…' overlaps another range of the sheet` | Séparer les plages de la fiche. |
| `missing key 'frequencies' or 'frequency_range'` | Ajouter l'une des deux. |
| `frequencies and frequency_range cannot be used together …` | N'en garder qu'une. |
| `bad listening hours '8:00-12:00' (always, or HH:MM-HH:MM ranges separated by commas)` | Deux chiffres : `08:00-12:00`. |
| `unknown action 'fly'` | Voir [Actions](#actions). |
| `budget.mark_map set but action 'mark_map' is not in actions` | Ajouter l'action ou retirer le budget. |
| `call_one_in needs a call_text line` | Ajouter `call_text`, ou `call_one_in=0`. |
| `unknown key 'radio' in [place mill]` | Une ligne de l'en-tête écrite sous une section : la remonter au-dessus de la première section. |
| `missing key 'use' in [place mill]` | Un lieu demande `at`, `label` et `use`. |
| `bad use entry 'hide' (expected mark, target, drop, landing)` | Voir [Lieux](#lieux--sections-place). |
| `place label of 'mill' too long (48 bytes of UTF-8 at most)` | Raccourcir le libellé. |
| `unknown section 'shop' (expected place, mission, rewards, category or prompt)` | Faute de frappe dans un titre de section. |
| `unknown mission type 'fly'` (journal du serveur seulement) | Un type du mod : `scout`, `deliver`, `retrieve`, `clear`, `signal`, `barricade`, `route`, `relay`, `watch`, `item`. |
| `bad item 'Locket' (Module.Type of an item script, e.g. Base.Locket)` (journal du serveur seulement) | La clé `item=` d'une mission `item` donne le module et le type : `Base.Locket`. |
| `unknown item 'Base.Lockett'` (journal du serveur seulement) | Aucun objet du jeu (ni des mods actifs) ne porte ce type : vérifier l'orthographe. |
| `bad place list (2 to 8 places with use=target)` | La clé `points=` d'une mission `route` nomme de 2 à 8 lieux `use=target`, séparés par des virgules. |
| `place 'clinic' has no use=drop` (journal du serveur seulement) | Ajouter `drop` au `use` de ce lieu, ou citer un autre lieu. |
| `unknown category 'weapons'` (journal du serveur seulement) | Une catégorie du catalogue ou une `[category]` de la fiche. |
| `bad reward weight '0' (whole number from 1 to 999999)` (journal du serveur seulement) | Les poids commencent à 1. |
| `missing [prompt] line before the prompt text` / `empty prompt text after [prompt]` | Ajouter la ligne, puis le texte. |

</details>

## Retirer une voix

| Vous voulez | Faites ceci |
|---|---|
| La mettre en pause | `state=silent` : elle écoute mais ne répond jamais ; sa fréquence reste réservée. |
| La retirer de l'antenne | `state=gone` (a quitté le réseau) ou `state=dead` (morte dans l'histoire) : sa chaîne est retirée et sa fréquence libérée. La fréquence tirée est retenue et revient avec la voix si elle est encore libre. |
| Supprimer votre propre voix | Supprimez son fichier. |
| Retirer une voix **livrée** | Ne supprimez pas le fichier, il serait recopié au chargement suivant. Mettez `state=gone`, ou videz le fichier (0 octet) : un fichier vide retire la voix et n'est pas recopié. |

## Multijoueur

- Les fiches se modifient **sur la machine du serveur**, dans le dossier d'échange du serveur. Le pont, qui tourne sur
  la même machine, lit le même dossier.
- Aucune fiche, aucun prompt ni aucune fréquence tirée n'est envoyé aux joueurs : leur jeu ne sait même pas quelles
  fréquences ont une voix. Seul ce que dit la voix passe à l'antenne.
- Le journal du serveur cite les fréquences tirées : réservez-le aux admins.

Voir aussi : [Le pont sur un serveur dédié](06-pont-sur-serveur-dedie.md), [Dépannage](11-depannage.md),
[FAQ](12-faq.md).
