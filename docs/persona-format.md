# Format des fiches de voix radio (format 1)

Une fiche décrit une voix du réseau radio (E05) : identité, fréquences, horaires, lieu, connaissances, actions
autorisées, état, et le texte du prompt donné au LLM. Elle est lue par deux lecteurs qui appliquent **les mêmes
règles et les mêmes messages** :

- le pont : `bridge/persona_store.py` (`load_file`, `parse_bytes`, `parse_lines`) ;
- le serveur : `media/lua/server/RadioSurvivor/RS_Persona.lua` (`RS_Persona.readFile`, `RS_Persona.parseLines`),
  qui lit le fichier avec `getFileReader`, sans `loadstring`.

`tests/test_personas.py` compare les deux lecteurs sur les mêmes fichiers (lupa) ; `tests/test_kahlua.py` refait une
partie des cas dans la VM Kahlua réelle (accents, BOM, UTF-8 invalide).

État : format et lecteurs (E05-T01) ; chargement et relecture à chaud côté serveur (E05-T02) ; routage par voix,
radio exigée, budget et prompt construit par le pont (E05-T03, « Routage par voix » ci-dessous) ; fréquences tirées
au hasard dans des plages, à chaque nouvelle partie (E05-T07, « Tirage des fréquences » ci-dessous) ; appels spontanés
de chaque voix (E05-T05, « Appels spontanés » ci-dessous). Les actions autres que `say` sont E07 : depuis E07-T01, la
voix peut les proposer et le serveur les juge (catalogue, fiche, `budget.<action>` par jour de jeu, distance, délai),
mais seules celles dotées d'un exécuteur ont un effet ; les autres sont refusées `not_available`. Depuis E07-T03,
`remember` est effective : la voix retient un fait court sur l'appelant, rangé par le serveur et rappelé au pont comme
souvenir non vérifié (`docs/protocole-carnet-v2.md`, « Mémoire des voix »). Depuis E07-T06, `persona_state` est
effective : la voix fait évoluer son propre moral, ses réserves et le lieu où elle dit se trouver, rangés par le
serveur dans son état privé (jamais dans la fiche, qui reste celle de l'admin) et rappelés au pont
(`docs/protocole-carnet-v2.md`, « État dynamique des voix »). Depuis E07-T04, `mark_map` est effective : la fiche
liste ses lieux connus (`place=`, « Lieux connus » ci-dessous), la voix en choisit un par son identifiant et le
serveur le marque sur la carte du seul appelant (`docs/protocole-carnet-v2.md`, « Repère sur la carte »). Les fiches livrées n'existent qu'en un exemplaire, dans le mod (E05-T10) ; le prompt de secours
`bridge/persona.txt` est retiré.

## Fichier

- Un fichier par voix, nommé `<id>.txt` ; l'`id` de la fiche doit être exactement ce nom sans `.txt`.
- Emplacement de travail : `Zomboid\Lua\batman_RadioSurvivor\personas\` sur la machine du serveur (ou de la
  partie solo ; `<cachedir>\Lua\...` pour un serveur lancé avec `-cachedir`). Les fiches livrées (Walt et les
  autres voix) sont dans le mod, `Contents/mods/batman_RadioSurvivor/42.21/personas/`, seul exemplaire du dépôt (voir
  « Chargement par le serveur »).
- Texte **UTF-8 sans BOM**. Fins de ligne `\n`, `\r\n` ou `\r` (découpage de `BufferedReader.readLine`, celui de
  `getFileReader`).
- Deux parties : un en-tête de lignes `clé=valeur`, puis une ligne `[prompt]` suivie du texte libre du prompt.

```text
# commentaire
format=1
id=walt
name=Walt Hensley
frequency_range=130.0-149.8
call_one_in=3
call_text=IGUI_RadioSurvivor_Call

[prompt]
You are Walt Hensley, 54, ...
```

### En-tête

- Les lignes vides et les lignes dont le premier caractère non blanc est `#` sont ignorées.
- Toute autre ligne est `clé=valeur`, coupée au **premier** `=` ; espaces et tabulations retirés autour de la clé et
  de la valeur. Une valeur peut donc contenir `=` et `#`.
- Clés en minuscules (`a` à `z`, `_`, et un seul `.` pour `budget.<action>`). Une clé inconnue est refusée.
- Une clé ne peut apparaître qu'une fois, sauf `knows`, `ignores` et `secret`, répétables (une ligne par élément).
- Une valeur vide est refusée : pour garder la valeur par défaut, retirer la ligne.
- Les listes (`frequencies`, `frequency_range`, `listen`, `actions`) sont séparées par des virgules, espaces
  tolérés autour.

### Prompt

- La ligne de séparation est `[prompt]` seule (espaces autour tolérés). Elle est obligatoire.
- Tout ce qui suit est du texte libre, gardé tel quel, `#` et `=` compris ; seules les lignes vides (ou blanches) du
  début et de la fin sont retirées. Les lignes sont rejointes par `\n`. Le texte ne peut pas être vide.
- Le prompt décrit le caractère, l'histoire, le ton et les règles de parole de la voix (pour Walt, le texte de son
  ancien prompt, inchangé depuis E05-T03).

## Champs

| Clé | Type et valeurs admises | Défaut | Rôle |
|---|---|---|---|
| `format` | `1` | obligatoire | Version du format. |
| `id` | `a`-`z`, `0`-`9`, `_`, commence par une lettre, 32 caractères au plus | obligatoire | Identifiant stable de la voix (historiques, journaux) ; égal au nom du fichier. |
| `name` | texte non vide | obligatoire | Nom du personnage (pour l'admin et le prompt). |
| `language` | deux lettres minuscules (`en`, `fr`…) | `en` | Langue par défaut de la voix. Répondre dans la langue de l'appelant reste une consigne du prompt. |
| `frequencies` | liste de MHz à une décimale, de `1.0` à `999.8`, au pas de 0,2 MHz des radios, sans doublon | `frequencies` **ou** `frequency_range` obligatoire, pas les deux | Fréquences fixes où la voix écoute et répond, les mêmes dans toutes les parties. Lues en kHz (`145.0` → 145000). |
| `frequency_range` | liste de plages `bas-haut` (deux fréquences au format de `frequencies`, la plus basse d'abord, espaces tolérés autour du `-`), sans chevauchement entre elles | voir `frequencies` | Plages de tirage (E05-T07) : à chaque nouvelle partie, le serveur tire **une fréquence par plage** et la garde pour toute la partie. Voir « Tirage des fréquences ». |
| `radio` | `any`, `high_tier` | `any` | Radio exigée de l'appelant : toute radio émettrice, ou poste haut de gamme (`getIsHighTier`, par exemple pour les ondes courtes). |
| `listen` | `always`, ou liste de plages `HH:MM-HH:MM` (heure du jeu, deux chiffres, 00:00 à 23:59) | `always` | Horaires d'écoute. Une plage dont la fin précède le début passe minuit (`22:00-06:00`). Début et fin égaux : refusé. Minute de début incluse, minute de fin exclue. |
| `location` | `none`, `fixed`, `rescue` | `none` | `none` : hors carte ; `fixed` : point fixe de la carte (`coords` obligatoire) ; `rescue` : point choisi par le serveur pour un secours (E12), pas de `coords`. |
| `coords` | `x,y,z` entiers, `x` et `y` de 0 à 999999, `z` de -32 à 31 | aucun | Seulement avec `location=fixed`. |
| `knows` | texte non vide, répétable | aucun | Ce que la voix sait. |
| `ignores` | texte non vide, répétable | aucun | Ce que la voix ignore (pour qu'elle ne l'invente pas). |
| `secret` | texte non vide, répétable | aucun | Ce que la voix cache. Voir « Secrets » ci-dessous. |
| `place` | `<id> <x>,<y>,<z> <libellé>`, répétable, 12 lignes au plus : `id` en `a`-`z`, `0`-`9`, `_` (32 caractères au plus, unique dans la fiche), coordonnées comme `coords`, libellé non vide de 48 octets UTF-8 au plus ; un ou plusieurs espaces ou tabulations entre les trois parties | aucun | Lieu connu de la voix (E07-T04), qu'elle peut marquer sur la carte de l'appelant par l'action `mark_map` ou dont elle peut révéler le quartier par `reveal_area` (E07-T05). Le pont ne montre au LLM que `id` et libellé ; les coordonnées restent sur le serveur, qui les envoie au seul appelant d'un `mark_map` accepté. Le libellé est affiché tel quel sur la carte du joueur : pas de secret ni de texte réservé à l'admin. Voir « Lieux connus » ci-dessous. |
| `actions` | liste parmi `say`, `mark_map`, `reveal_area`, `signal`, `place_cache`, `place_scene`, `start_mission`, `persona_state`, `remember`, `propose_trade`, `report_mission`, `share_frequency`, sans doublon | `say` | Actions que la voix peut proposer (catalogue fermé, note de travail §02). Seules les actions dotées d'un exécuteur côté serveur ont un effet (`say`, diffusée comme avant ; `remember` depuis E07-T03 : un fait de 64 caractères au plus sur l'appelant, 5 par appelant et par personnage, 50 appelants par voix, sans effet de jeu ; `persona_state` depuis E07-T06 : paramètres `morale` et `supplies`, entiers de 0 à 10 (5 par défaut), changés d'au plus 2 par appel, une demande au-delà ou hors bornes étant ramenée, et `place`, lieu dit de 40 caractères au plus, simple récit sans effet sur `coords` ni sur la distance ; au moins un paramètre, aucun autre ; état propre à la voix, rangé dans l'état privé du serveur, jamais dans la fiche ; sans effet de jeu ; plafond `budget.persona_state`) ; `mark_map` depuis E07-T04 : paramètre unique `place`, identifiant d'une ligne `place=` de la fiche, repère posé sur la carte du monde du seul appelant, 30 s réelles au moins entre deux repères de la voix, plafond `budget.mark_map` ; une fiche `mark_map` sans ligne `place=` ne la propose pas au LLM ; `reveal_area` depuis E07-T05 : même paramètre `place`, le quartier autour du lieu devient connu sur la carte du monde du seul appelant, carré de 5 blocs de 32 cases (160 cases de côté au plus, moins en bord de carte), 60 s réelles au moins entre deux révélations de la voix, plafond `budget.reveal_area`, conditions de proposition identiques à `mark_map` ; `start_mission` depuis E11-T08 : paramètre unique `template`, `scout` seul, mission « reconnaître » confiée à l'appelant (bâtiment choisi par le serveur autour de lui, décrit à la voix sans coordonnée juste après, par une demande de consigne où elle dit les indices (E11-T09), puis aux appels suivants), une mission ouverte à la fois par appelant et par voix, 60 s réelles au moins entre deux missions de la voix et 30 min après la clôture de la précédente du même appelant, compte rendu à la radio sur la fréquence de la voix après la visite (E11-T13 : action `report_mission`, sans paramètre, rendue par le modèle quand l'appel en rend compte et revérifiée par le serveur ; permise à toute fiche qui autorise `start_mission`, sans la lister), récompense en réputation et repère du premier lieu `place=` pas encore donné à ce personnage, plafond `budget.start_mission` ; carnet du joueur requis) ; `place_cache` depuis E11-T06 : paramètre unique `table` (`food`, `medical`, `ammo`, `tools`), sac marqué rempli de cette table fermée et posé une seule fois au bâtiment de la dernière mission donnée par la voix à l'appelant (ouverte, sinon sa dernière réussite), une cache par mission, 60 s réelles au moins entre deux caches de la voix, plafond `budget.place_cache` ; serveur seulement pour l'instant : le pont ne la propose pas encore au LLM ; `propose_trade` depuis E13-T02 : paramètres `items` (« `Nom:quantité` » séparés par des virgules, objets du stock du passage) et `margin` facultative, offre du passeur contrôlée contre la table validée et figée par le serveur, qui joint le livre du passeur (`trade=`) aux demandes de cette voix (`docs/conception/passeur-offre.md`) ; les autres sont refusées `not_available` et journalisées. Une fiche qui autorise une action autre que `say` fait passer le pont en réponse structurée (`docs/protocole-carnet-v2.md`, « Réponse radio structurée »). |
| `budget` | entier de 0 à 999999 | `0` | Demandes par heure réelle pour cette voix, en plus du plafond global `MaxPerHour` ; `0` = seul le plafond global. |
| `budget.<action>` | entier de 0 à 999999 | aucun | Utilisations par jour de jeu de cette action ; `0` = pas de plafond. L'action doit figurer dans `actions`. |
| `call_one_in` | entier de 0 à 1000 | `0` | Appel général spontané : une chance sur N à chaque heure de jeu, pendant les heures d'écoute, quand personne ne parle à la voix ; `0` = jamais. Voir « Appels spontanés ». |
| `call_text` | clé de traduction (`A`-`Z`, `a`-`z`, `0`-`9`, `_`) | aucun | Texte fixe de l'appel, diffusé quand le pont n'en écrit pas, `%1` = fréquence affichée. Obligatoire si `call_one_in` > 0. Clé du fichier `IG_UI.json` du mod (préfixe `IGUI_`). |
| `state` | `active`, `silent`, `gone`, `dead` | `active` | `active` : répond ; `silent` : écoute mais ne répond pas (pause) ; `gone` : retirée du réseau ; `dead` : morte dans l'histoire. Traitement : « Chargement par le serveur » et « Routage par voix ». |

Les deux lecteurs rendent la fiche avec ces noms (`secret` devient la liste `secrets`, `place` la liste `places` de
lieux `{ id, x, y, z, label }` dans l'ordre du fichier (Python : `Place`), les `budget.<action>` la
table `budgets`, `listen` une liste de plages `(début, fin)` en minutes du jour de jeu, vide pour `always`,
`frequency_range` la liste `frequency_ranges` de plages `(bas, haut)` en kHz ; `frequencies` est alors vide, et
`frequency_ranges` est vide pour une fiche à fréquences fixes).

## Chargement par le serveur (E05-T02)

Module `media/lua/server/RadioSurvivor/RS_Personas.lua`, côté autorité (serveur dédié ou hébergé, partie solo).

- **Fiches livrées** : dossier `personas/` de la variante du mod (`Contents/mods/batman_RadioSurvivor/42.21/personas/`,
  hors de `media/`), lu par `listFilesInModDirectory` et `getModFileReader`. C'est le seul exemplaire des fiches
  livrées dans le dépôt (E05-T10) : le pont le lit aussi pour ses tests et son mode `--test`, par chemin relatif à
  son propre fichier (`bridge/../Contents/mods/batman_RadioSurvivor/42.21/personas`) ou `--personas <dossier>` ;
  `tests/test_personas_server.py` vérifie que les six fiches y sont valides.
- **Installation et mise à jour** (E05-T11) : à chaque chargement d'un monde (`OnLoadRadioScripts`), pour chaque fiche
  livrée :
  - absente du dossier de travail : copiée ;
  - présente et **non modifiée** par l'admin, mais différente de la version livrée (mise à jour du mod) : remplacée
    par la version livrée, journal `INFO: voice 'x' updated to the delivered version` ;
  - présente et **modifiée** par l'admin (même invalide ou vidée) : gardée, journal `WARNING: voice 'x' modified by
    the admin, delivered version not applied` à chaque chargement du monde. Pour revenir à la version livrée, supprimer
    le fichier : il est recopié au chargement suivant.

  Une fiche est non modifiée quand son **empreinte** (Adler-32 de `RS_Codec.checksum` sur les octets UTF-8, lignes
  rejointes par `\n` : indépendante des fins de ligne) est celle que le serveur a mémorisée en l'écrivant, dans
  `Zomboid/Lua/batman_RadioSurvivor/personas-fingerprints.txt` (hors du dossier des fiches ; en-tête `RSFP1`, puis
  `nom.txt empreinte`). Sans empreinte mémorisée (installation antérieure à E05-T11, fichier absent ou vidé), elle
  est non modifiée si son empreinte est celle d'une version livrée connue (`RS_Personas.KNOWN_DELIVERED` : versions
  des commits `09d7474`, `24832ea`, `486b21e` et actuelle ; toute nouvelle version livrée y ajoute la sienne,
  contrôlé par `tests/test_personas_server.py`) ; sinon elle est traitée comme modifiée. Une installation à
  fréquences fixes (avant E05-T07) reçoit ainsi les fiches à plages. Un fichier d'empreintes **abîmé** (en-tête ou
  ligne illisible) est ignoré prudemment : aucune fiche n'est remplacée, il n'est pas réécrit, un avertissement
  indique de le vider ; les fiches absentes sont copiées quand même. Une fiche de l'admin sans équivalent livré n'est
  jamais touchée.
- **Migration unique de l'ancienne option sandbox** `RadioSurvivor.Frequency` (retirée en E05-T02) : à la première
  copie de `walt.txt`, une valeur lisible différente de 145,0 remplace la ligne `frequencies`. En 42.21, cette
  valeur n'est **plus lisible** une fois l'option retirée du mod : `SandboxOptions.load` saute les noms inconnus de
  `map_sand.bin` (`SandboxOptions.java:470-488`), `toLua` n'écrit que les options déclarées, et un serveur dédié
  réécrit `<serveur>_SandboxVars.lua` sans elle avant tout événement Lua du monde (`GameServer.java:1413-1424`).
  En pratique, la fiche livrée (145,0) est copiée et le journal porte une note : un admin qui avait changé la
  fréquence doit la reporter dans `walt.txt`. Ensuite, seule la fiche compte. Une copie migrée est un choix de
  l'admin : aucune empreinte n'est mémorisée et elle n'est jamais remplacée.
- **Relecture** : toutes les 30 s réelles (`RS_Personas.RELOAD_MS`, `OnTickEvenPaused` : aussi sur un serveur dédié
  vide en pause) et à chaque chargement du monde. Seuls les fichiers dont le texte a changé sont analysés. Les fichiers
  pris en compte sont les `*.txt` du dossier ; un autre nom (`walt.txt.bak`) est ignoré.
- **Fiche invalide** : refusée, journalisée une fois par contenu avec sa ligne
  (`[RadioSurvivor] personas: ERROR: batman_RadioSurvivor/personas/walt.txt refused, line N: ...`) ; la dernière
  version valide de la même voix reste en service jusqu'à la correction ou au chargement suivant du monde.
- **Fichier retiré ou vidé** (0 octet) : la voix et ses chaînes sont retirées. Lua ne pouvant supprimer aucun fichier,
  vider une fiche est la façon scriptée de retirer une voix ; un fichier vide n'est pas recopié depuis le mod.
- **Chaînes** : une chaîne radio dynamique par fréquence servie (identifiant `batman_RadioSurvivor-voice-<id>-<kHz>`,
  nom retiré du panneau de la radio comme avant). États : `active` = chaîne et réponses ; `silent` = chaîne gardée,
  fréquence réservée, la phrase du joueur part sur la radio mais rien n'est envoyé au pont, ni réponse ni appel ;
  `gone` et `dead` = aucune chaîne, fréquence libérée ; la phrase du joueur y obtient le même silence que sur toute
  fréquence sans voix (E05-T08).
- **Heures d'écoute** (`listen`) : minute de début incluse, minute de fin exclue (`06:00-12:00` = 06:00 à 11:59) ;
  hors horaire, même traitement que `silent`.
- **Conflits** : une fréquence fixe demandée par deux fiches reste à la voix chargée la première dans la session (au
  premier chargement : ordre alphabétique des fichiers) ; l'autre voix perd seulement cette fréquence, avertissement
  journalisé une fois. Une fréquence tirée ne crée jamais de conflit : voir « Tirage des fréquences ». Une fréquence déjà prise par une chaîne du jeu ou d'un autre mod (`AddChannel` refusé) est
  journalisée et réessayée à chaque relecture.
- **Fréquence modifiée à chaud** : une chaîne n'a pas de mutateur de fréquence ; l'ancienne est retirée
  (`RadioScriptManager:RemoveChannel`) et une nouvelle créée (`AddChannel` hors `OnLoadRadioScripts`). Une diffusion
  en cours sur l'ancienne fréquence est perdue, une réponse en attente pour elle est abandonnée.
- **Client** : il ne lit jamais les fiches et **ne reçoit aucune fréquence de voix** (E05-T08, décision du
  2026-10-09 : les fréquences se découvrent en jeu, par des notes du butin, E05-T09). L'ancienne commande
  `frequencies` est retirée ; une demande d'un client antérieur reste sans réponse. Le client envoie la fréquence de
  sa radio avec chaque phrase dite dans une radio émettrice allumée ; le serveur trie (« Routage par voix »).
  `RS_Personas.heldFrequencies()` donne la liste côté autorité seulement (tests, diagnostic).

## Tirage des fréquences (E05-T07)

Décision du 2026-10-09 : **toutes les voix, Walt compris**, tirent leur fréquence au hasard à chaque nouvelle partie,
dans une plage propre à chaque voix qui garde les radios capables de la joindre. Code : `RS_Personas.lua`, section
« Tirage » ; les fréquences fixes d'E05-T04 ne sont plus que des exemples (commentaires des fiches).

### Plages des six voix livrées

Radios : bornes `MinChannel`/`MaxChannel` de `media/scripts/generated/items/radio.txt` (42.21), bornes incluses
comme le contrôle du serveur ; talkie 1 = `WalkieTalkie1` et talkie bricolé (75-150 MHz), talkie 2 (50-200),
talkie 3 (25-300), talkie 4 et radios HAM ordinaires (10-500), talkie 5, poste militaire et HAM haut de gamme
(0,2-1 000) ; radios FM, lecteur CD et autoradio standard (88-108, réception seule) ; téléviseurs (tout, réception
seule). Chaque fréquence de chaque plage est jointe par exactement les mêmes radios que la fréquence d'exemple
(`tests/test_personas.py`, `test_ranges_keep_the_radios_that_reach_the_voice`).

| Voix | Plage(s) (MHz) | Fréquences possibles | Exemple (E05-T04) | Peuvent parler à la voix | L'entendent seulement |
|---|---|---|---|---|---|
| Walt (`walt`) | 130.0-149.8 | 100 | 145.0 | tous les talkies (1 à 5, bricolé) et toutes les radios HAM | téléviseurs |
| Darlene (`darlene`) | 115.0-129.8 | 75 | 115.6 | idem | téléviseurs |
| Jolene Whitaker (`whitaker`) | 75.0-87.8 | 65 | 81.4 | idem | téléviseurs |
| Cody (`cody`) | 10.0-24.8 (ondes courtes) | 75 | 17.4 | talkies 4 et 5, radios HAM, poste militaire (pas le talkie 3) | téléviseurs |
| Night Owl (`nightowl`), FM | 88.0-107.8 | 100 | 106.2 | tous les talkies et toutes les radios HAM | radios FM, autoradios, téléviseurs |
| Night Owl (`nightowl`), VHF | 109.0-114.8 | 30 | 112.4 | tous les talkies et toutes les radios HAM | téléviseurs |
| Gus (`gus`) | 150.2-199.8 | 249 | 156.6 | talkies 2 à 5, radios HAM (ni le talkie 1 ni le bricolé) | téléviseurs |

Les plages sont disjointes. Seule la plage FM du Night Owl recoupe des chaînes vanilla (huit stations FM et l'alerte
d'urgence AEBS, tirée par le jeu dans 88-108) : elles ne sont jamais tirées. 108.0 (Opération Artemis par défaut)
n'est dans aucune plage. Les plages de Darlene, Walt et Gus recoupent la bande de diffusion de Military Drop
(120-170) et celle de Cody sa station de chiffres (10-25) : la voix ou le mod inscrit en second évite la fréquence
de l'autre (règles ci-dessous ; Military Drop prend la suivante si la sienne est occupée).

### Règles

- **Tirage** : une fréquence par plage, uniforme (`ZombRand`) parmi les fréquences **libres** de la plage, au pas
  de 0,2 MHz. Non libre : fréquence d'une chaîne qui n'est pas une voix de ce module (chaînes vanilla de
  `RadioData.xml`, AEBS, chaînes des mods déjà inscrites : `RadioScriptManager.getChannelsList`), fréquence de
  l'AEBS notée dans la ModData de `GameTime` (`dynamicRadio`), ou fréquence à moins de **1,0 MHz**
  (`RS_Personas.MIN_GAP_KHZ`) d'une fréquence d'une autre voix chargée (fixe, tirée ou mémorisée, quel que soit son
  état : une voix `gone` peut revenir). Voix traitées dans leur ordre de chargement. Aucune fréquence libre : erreur
  journalisée, la plage n'est pas servie (élargir la plage).
- **Ordre de création de l'AEBS** : elle existe déjà au moment du tirage. Les fichiers Lua vanilla sont chargés
  avant ceux des mods (`LuaManager.LoadDirBase`, `LuaManager.java:1197-1198`, 42.21.0), donc l'abonné
  `OnLoadRadioScripts` de `ISDynamicRadio.lua` (qui tire et crée l'AEBS) passe avant celui du mod. La lecture de
  `dynamicRadio` couvre aussi l'ordre inverse. Une chaîne inscrite après nous et tirée par
  `ZomboidRadio.getRandomFrequency` évite nos fréquences (`knownFrequencies`, `ZomboidRadio.java:139-147, 179-183`).
- **Monde neuf** : second argument d'`OnLoadRadioScripts`, vrai quand `savedWorldVersion == -1`
  (`ZomboidRadio.java:246` : `map_t.bin` absent sur un serveur, `map_ver.bin` en solo ; base `multiplayer.md`). Toutes
  les plages sont tirées ; un ancien fichier de tirage du même nom (monde effacé puis recréé sous le même nom) est
  ignoré puis réécrit.
- **Mémoire** : fichier `Zomboid/Lua/batman_RadioSurvivor/frequencies-<hex>.txt` sur la machine qui fait autorité,
  `<hex>` = octets hexadécimaux de `« mode/nom de la partie »` (`getWorld():getGameMode()`, `getWorld():getWorld()`,
  comme l'état du carnet). Jamais de ModData globale (lisible par tout client). Contenu : `RSFREQ1`, puis une ligne
  `<id> <bas>-<haut> <kHz>` par plage. Écrit à chaque changement.
- **Redémarrage** (monde existant) : les fréquences mémorisées sont reprises, sans tirage. Partie antérieure à
  E05-T07 (pas de fichier) : tirage, une seule fois. Une ligne abîmée est ignorée (avertissement) et sa plage tirée
  de nouveau.
- **Collision au chargement** (improbable) : une fréquence mémorisée prise par une chaîne étrangère, ou à moins de
  1,0 MHz d'une fréquence fixe ou déjà attribuée d'une autre voix, est tirée de nouveau dans sa plage, avec une
  ligne de journal (`voice 'walt' drew 137.4 MHz in 130.0-149.8 (145.0 taken by the radio channel '…')`). Une
  fréquence fixe d'une autre voix l'emporte toujours sur une fréquence tirée. Une chaîne étrangère qui arrive en
  cours de partie et remplace une chaîne de voix est vue à la relecture suivante (30 s) : nouveau tirage.
- **Fiche modifiée à chaud** : seule une plage changée (ou ajoutée) est tirée de nouveau, pour cette voix seulement ;
  les autres plages et les autres voix gardent leurs fréquences. Une fiche passée à `frequencies` fixe perd son
  tirage mémorisé. Fichier retiré : le tirage reste en mémoire et revient avec la fiche (s'il est encore libre).
- **Journal** : chaque tirage est écrit dans le journal du serveur (`[RadioSurvivor] personas: voice '…' drew …`).
  Les fréquences tirées sont un secret de partie : jamais dans une fiche, un prompt, une commande au pont ni une
  commande aux clients (E05-T08). Limites : voir « Ce qui pourrait révéler une fréquence ».
- **Installation existante** : un serveur qui a installé les fiches avant E05-T07 reçoit les fiches à plages au
  chargement suivant pour chaque fiche qu'il n'a pas modifiée (reconnue par les versions livrées connues, E05-T11 :
  « Installation et mise à jour ») ; une fiche modifiée garde ses fréquences fixes, avec un avertissement.
- **Pont** : il n'a pas besoin de la fréquence. Le serveur choisit la voix d'après la fréquence de la radio et
  envoie `voice=<id>` (E05-T03) ; le pont lit la fiche (ses plages comprises, `persona_store.py`) pour le prompt.

## Routage par voix (E05-T03)

Le serveur décide (`RadioSurvivor_Server.lua`, `onTalk`), le pont exécute (`bridge/radio_bridge.py`).

- **Fréquence → voix** : la fréquence envoyée par le client désigne la voix qui tient la chaîne de cette fréquence
  (`RS_Personas.voiceAt`). Le serveur ne peut pas comparer avec le canal réel de la radio : il ne le connaît que pour
  une radio tenue en main, et il reste périmé si le réglage a été fait hors de la main (base `multiplayer.md`). Il
  contrôle ce qu'il sait : fréquence entière, dans les bornes de réglage de la radio (`getMinChannelRange`,
  `getMaxChannelRange`, données du script de l'objet), servie par une voix. Sinon : **silence** (ci-dessous), comme
  sur toute fréquence sans voix. Client sans fréquence : silence (plus de repli sur Walt depuis E05-T08).
- **Ordre des contrôles** (E05-T08) : tout ce qui peut refuser une phrase avec un message est jugé **avant** de
  regarder la fréquence, de la même façon sur toutes : mod désactivé (`Disabled`), pas de radio émettrice portée
  (main, dos, ceinture ou inventaire principal, pas un sac : `NoRadio`), anti-spam (`Spam`), demande déjà en attente
  (`Waiting`), délai `PlayerCooldown` depuis la dernière demande acceptée (`Cooldown`), plafond global `MaxPerHour`
  ou file pleine (`Busy`). Un refus n'indique donc jamais si une voix écoute la fréquence. Aucun de ces contrôles ne consomme le plafond ni un budget.
- **Anti-spam** (E05-T08) : le client impose entre deux phrases le délai du serveur `PlayerCooldown` plus 1 s de marge,
  au moins 5 s (`Const.clientIntervalMs`, option grisée « Vous parlez sans arrêt » ; depuis le 2026-10-09, pour que le
  refus `Cooldown` n'apparaisse plus en usage normal) ; le serveur refuse au-delà de 15 phrases par minute réelle glissante et par joueur,
  toutes fréquences (`Const.SPAM_MAX`, `Const.SPAM_WINDOW_MS`), compteur en mémoire. Seul un client modifié atteint
  la limite du serveur.
- **Silence** : fréquence sans voix ou hors de portée de la radio, voix `gone`/`dead`, voix `silent`, hors de ses
  heures d'écoute, budget de la voix épuisé, ou `radio=high_tier` avec un poste ordinaire
  (`DeviceData.getIsHighTier()` faux ; vrai pour `WalkieTalkie5`, `ManPackRadio`, `HamRadio2` et certaines radios
  bricolées, `DeviceData.java:249`, `Item.java:1806`, 42.21.0). La phrase part sur la radio, personne ne répond,
  rien n'est envoyé au pont : ni coût, ni délai, ni plafond, ni budget consommés. Silence plutôt que parasites :
  même règle que `silent` depuis E05-T02, et des parasites trahiraient une présence sur la fréquence. Le client
  reçoit `accepted` puis aussitôt `done` : la même suite partout, aucun message.
- **Budget** : `budget=N` (> 0) limite la voix à N demandes acceptées par heure réelle glissante, en plus du plafond
  global `MaxPerHour` ; au-delà, la voix se tait (silence : un refus `Busy` propre à la voix trahirait sa présence,
  E05-T08). Compteurs en mémoire, remis à zéro au redémarrage du serveur.
- **Demande au pont** : champ `voice=<id>` (`docs/protocole-carnet-v2.md`). Le pont relit la fiche dans
  `<dossier d'échange>/personas/<id>.txt`, le dossier même du serveur (option `--exchange` existante), à chaque
  demande dont le fichier a changé ; une fiche refusée garde côté pont sa dernière version valide.
- **Prompt** : texte libre de la fiche, puis, s'ils existent, `knows` (« ce que tu sais »), `ignores` (« dis que tu
  ne sais pas, n'invente pas ») et `secret` (« ne jamais révéler, ni laisser deviner, ni confirmer »). Une fiche sans
  ces lignes (Walt) donne exactement son texte libre : le prompt de Walt est inchangé. Puis la situation de l'appel
  (date, appelant, radio), comme avant.
- **Historique** : par partie et par voix ; Walt garde son fichier d'avant (`history_<empreinte>.json`), les autres
  voix `history_<empreinte>_<id>.json`. Appelants numérotés par voix.
- **Sans fiche** : une voix sans fiche valide côté pont, Walt compris, reçoit des parasites (le prompt de secours
  `bridge/persona.txt` est retiré en E05-T10 : le serveur installe toujours les fiches livrées). Le mode `--test` du
  pont lit les fiches livrées du mod, pas le dossier d'échange (`--personas <dossier>` pour un autre dossier).

## Ce qui pourrait révéler une fréquence (E05-T08)

Vérifié statiquement (42.21.0) et par `tests/test_protocol.py` (`scenario_server_sorts`) :

- **Commandes serveur → client** : `accepted` (`text` = la phrase du joueur), `rejected` (`reason`), `done` ; aucune
  ne porte de fréquence. Plus de `frequencies`, plus d'envoi à tous les clients.
- **Noms de chaînes** : `ZomboidRadio.WriteRadioServerDataPacket` envoie à chaque client, à sa connexion, la liste
  `categorizedChannels` (fréquence → nom). `removeChannelName` juste après `AddChannel` retire nos chaînes de cette
  liste (`ZomboidRadio.java:151-160, 190-201`) ; le panneau de la radio affiche « Chaîne inconnue ». Vérifié en jeu
  par la suite `rs.personas` (« voice frequencies never published to the clients »).
- **ModData** : aucune ModData globale ; la ModData de `GameTime` (`dynamicRadio`) est seulement lue (chaînes
  vanilla) ; le tirage est dans un fichier du serveur (`frequencies-<hex>.txt`).
- **Journaux** : le client n'écrit aucune fréquence. Le journal de l'autorité les cite (tirage, chaînes) : sur un
  serveur, réservé à l'admin ; ⚠ en solo, `console.txt` et le fichier de tirage sont sur la machine du joueur
  (limite acceptée : il faut aller les lire).
- **Notes de fréquences** (E05-T09, [notes-frequences.md](notes-frequences.md)) : la fréquence d'une voix est écrite
  par l'autorité dans la ModData de la note à sa création ; elle n'arrive chez un client qu'avec l'objet (conteneur
  ouvert, objet au sol proche, inventaire), jamais par une commande. Une voix `silent` (Whitaker) n'a pas de note.
- **Texte fixe des appels spontanés** : cite `%1` = la fréquence, diffusé sur cette fréquence seulement : le joueur
  qui l'entend y est déjà.
- ⚠ **Limite vanilla** : chaque diffusion d'une chaîne passe par `ZomboidRadio.SendTransmission`, et le serveur MP
  envoie le paquet `WaveSignal` (fréquence, texte) à **toutes** les connexions, réglées ou non
  (`GameServer.sendIsoWaveSignal`, `GameServer.java:3537-3547`). Un client modifié qui lit ses paquets apprend la
  fréquence d'une voix dès qu'elle parle (réponse ou appel spontané). Rien à faire sans renoncer aux chaînes vanilla ;
  un client non modifié n'affiche rien sans radio réglée.
- **Panneau de debug des fréquences** (E05-T14, section suivante) : seule commande qui porte les fréquences, envoyée
  au seul administrateur qui la demande, après contrôle de ses droits par l'autorité.

## Panneau de debug des fréquences (E05-T14)

Les fréquences étant tirées par partie, l'administrateur les lit dans le jeu, sans chercher le fichier de tirage :
bouton **« Radio Survivor - Fréquences »** du panneau debug vanilla (`ISDebugMenu`, onglet principal, à côté de
« Living Knox - PNJ »), ou `RS_FreqDebugView.open()` dans la console Lua.

- **Fenêtre** (`client/RadioSurvivor/RS_FreqDebugView.lua`, lecture seule, tableaux de `LK_Table.lua`) : une ligne
  par voix chargée, dans l'ordre de chargement : id, nom, état (active, silencieuse, partie, morte), fréquences de la
  partie en MHz (une fréquence qu'aucune chaîne ne sert est suivie de « (pas à l'antenne) » : conflit avec une autre
  voix ou une chaîne étrangère, voix `gone` ou `dead`), plages de tirage (ou « fixe »), radio requise, heures
  d'écoute (ou « toujours »), rôle (chroniqueur du bulletin). Second tableau : autres fréquences du mod, aujourd'hui
  le **bulletin du soir** (E14-T02) : voix du chroniqueur, sa première fréquence servie (ou « pas à l'antenne »),
  heure (option `ChronicleHour`). Le mod n'a aucune autre chaîne que celles des voix. Bouton « Actualiser » : les
  fiches sont relues toutes les 30 s par le serveur, la fenêtre ne se relit pas seule.
- **Autorité** (`server/RadioSurvivor/RS_FreqDebug.lua`) : vue copiée de `RS_Personas` (`ids`, `get`,
  `frequencies`, `served`, `holdsFrequencies`) et de `RS_Facts` / `RS_RadioServer.frequency` ; rien n'est relu ni
  écrit.
- **Droits**, revérifiés par l'autorité **à chaque requête** : ceux des outils de debug Living Knox (LK13-T13,
  `LK_Admin.isAllowed` pour une opération de `DEBUG_OPS`), recopiés dans un module propre à RadioSurvivor (aucune
  dépendance à `LK_Admin.lua` ; le banc compare les deux règles sur 96 cas) : solo = mode debug ; serveur MP =
  `checkPermissions(joueur, Capability.PopmanManage)` **et** `getRole():hasCapability` (rôles `moderator` et
  `admin`) ; client MP = jamais. Le bouton n'apparaît qu'avec ce droit (affichage seulement).
- **Refus** : réponse `{ n, op, ok = false, err = "denied" }` sans aucune donnée ; une ligne `WARNING` par joueur et
  par minute réelle au plus dans le journal de l'autorité.
- **Transport** : commande client `freqRequest` du module `RadioSurvivorDebug` `{ op = "frequencies", n }` → réponse
  `freqReply` au **seul** demandeur ; en solo, appel direct. Aucun envoi spontané : le serveur ne répond qu'à une
  requête, la fenêtre n'en envoie qu'ouverte (ouverture, « Actualiser ») et ignore une réponse arrivée après sa
  fermeture.
- **Tests** : banc `tests/test_rs_freqdebug.py` ; suite en jeu `rs.freqdebug` (solo, mode debug :
  `RST.run({ suite = "rs.freqdebug" })` ; serveur : `RST.server({ suite = "rs.freqdebug" })` depuis un client admin) ;
  protocole court dans `docs/tests-en-jeu.md`.

## Appels spontanés (E05-T05)

Le serveur décide (`RadioSurvivor_Server.lua`, `onEveryHours`), le pont écrit le texte (`radio_bridge.py`,
`spontaneous_call`). L'option sandbox `SpontaneousCalls` (« Appels spontanés ») coupe tout.

- **Tirage** : à chaque heure de jeu (`EveryHours`), chaque voix `active` (jamais `silent`, `gone` ni `dead`) avec
  `call_one_in` > 0, dans ses heures d'écoute, sur sa **première fréquence servie** (fixe ou tirée), et sans
  conversation en cours (aucune demande d'un joueur en attente pour elle, rien en file ni à l'antenne sur cette
  fréquence) tire une chance sur `call_one_in`.
- **Une voix par heure** : si plusieurs gagnent, une seule est tirée au sort parmi elles. Choix de lisibilité et de
  coût : une heure de jeu dure quelques dizaines de secondes réelles par défaut, et chaque appel coûte une demande au
  LLM.
- **Plafond** : un appel prend une place du plafond global `MaxPerHour` (heure réelle glissante), le même que les
  réponses, et une place du `budget` de la voix s'il existe. Plafond ou budget atteint : pas d'appel cette heure-là.
  La place est prise au tirage, que le texte vienne du pont ou de la fiche.
- **Texte** : demande `kind=radio_call` au pont (`docs/protocole-carnet-v2.md`). Le pont écrit un appel court (une
  ou deux phrases, trois lignes radio au plus) depuis la fiche **sans ses secrets** (texte libre, `knows`,
  `ignores`), dans la langue de l'autorité, sans fréquence (il ne la connaît pas) ni fait absent de la fiche.
  L'appel entre dans l'historique de la voix (message `[General call]`), sans numéro d'appelant.
- **Secours** : pont absent, réponse vide, parasites seuls, ou rien après `Const.CALL_TIMEOUT_MS` (30 s réelles) :
  texte fixe de la clé `call_text`, `%1` = fréquence affichée, composé par l'autorité. Une ligne radio n'est jamais
  traduite par le client : sur un serveur MP, dont les traductions des mods sont lues avant les mods (`getText` y
  rendrait la clé brute), le serveur appelle une fois `Translator.loadFiles()` quand la clé manque ; le texte est
  dans la langue du processus serveur. Une clé introuvable même après ce rechargement : pas d'appel, une ligne de
  journal par clé.
- **Revérification à la diffusion** : option, état `active`, heures d'écoute et fréquence servie sont revérifiés
  quand le texte arrive ; sinon l'appel est abandonné (`call of voice 'x' dropped`). Aucun appel n'est donc diffusé
  hors des heures d'écoute, même si le texte arrive après leur fin.
- **Valeurs livrées** : Walt 3, Darlene 6, Cody 6, Gus 8 ; Night Owl 0 (ses bulletins sont E14) ; Whitaker 0
  (silencieuse). Textes fixes `IGUI_RadioSurvivor_Call`, `…_Call_Darlene`, `…_Call_Cody`, `…_Call_Gus` (EN, FR).

## Secrets et données du serveur

- Les fiches restent **sur la machine du serveur** : jamais en ModData globale (lisible par tout client), jamais dans
  une commande `sendServerCommand`, jamais sur la chaîne radio telles quelles.
- `secret` est lu par le pont, pour construire le prompt avec la consigne de ne pas le révéler (E05-T03), et par le
  serveur, qui ne fait que valider la fiche. Le serveur n'envoie au client que ce que la voix dit (`say`), après
  ses filtres habituels (8 lignes, 140 caractères, balises retirées). Garde-fou du pont : une réponse qui cite un
  secret mot pour mot (casse et espaces ignorés) est remplacée par des parasites et n'entre pas dans l'historique ;
  une paraphrase n'est pas détectée.
- Un `secret` est un trait du personnage (« elle a abandonné son frère »), pas un secret de jeu : codes, graines,
  fréquences cachées et positions exactes des bases de joueurs ne vont **jamais** dans une fiche ni dans un prompt
  (note de travail §02). Le serveur ajoute ces valeurs après coup quand une action en a besoin.
- Seule exception à « jamais dans une commande `sendServerCommand` » : un `mark_map` accepté envoie au **seul
  appelant** les coordonnées et le libellé d'**un** lieu `place=` (commande `map_mark`), rien d'autre de la fiche ;
  un `reveal_area` accepté lui envoie de même un rectangle de 160 cases de côté au plus autour d'un lieu (commande
  `map_reveal`, E07-T05). Autre exception, réservée à l'administration : la réponse `freqReply` du panneau de debug
  des fréquences (E05-T14), au seul demandeur autorisé, sans aucun texte de fiche (ni prompt, ni `knows`, ni secret).

## Lieux connus (E07-T04)

Une ligne `place=` par lieu que la voix connaît, pour les actions `mark_map` et `reveal_area` (E07-T05) :

```text
place=mill 10600,9300,0 Vieux moulin
place=west_pharmacy 11920,6905,0 Pharmacie de West Point
```

- `id` : identifiant que le LLM choisit (`[a-z0-9_]`, 32 caractères au plus, unique dans la fiche) ; coordonnées
  entières comme `coords` (`x`, `y` de 0 à 999999, `z` de -32 à 31) ; libellé : le reste de la ligne, espaces
  intérieurs gardés, 48 octets UTF-8 au plus (environ 24 lettres accentuées ; les deux lecteurs comptent les mêmes
  octets, Kahlua depuis ses unités UTF-16). Au plus 12 lieux.
- Le prompt (mode structuré, `mark_map` autorisée) liste `id: libellé` de chaque lieu, jamais ses coordonnées ;
  `bounded_actions` (pont) et l'exécuteur (serveur, `RS_MapMarks.lua`) refusent un identifiant absent de la fiche.
- Le repère est posé au centre de la case `x,y` (le niveau `z` est lu mais la carte du monde est plane), sur la carte
  du seul appelant, comme une annotation du joueur : icône vanilla et libellé, sauvegardés avec ses annotations
  (`docs/protocole-carnet-v2.md`, « Repère sur la carte »). Le joueur peut l'effacer ; un nouveau `mark_map` du même
  lieu le repose, sans doublon.
- `reveal_area` (E07-T05) : le quartier autour du lieu devient connu sur la carte du seul appelant, carré de 5 blocs de
  32 cases centré sur le bloc du lieu (160 cases de côté au plus, rogné en bord de carte), comme une carte vanilla lue ;
  persistant (sauvegarde solo, ou carte du compte gardée par le serveur MP), sans retour en arrière
  (`docs/protocole-carnet-v2.md`, « Quartier révélé »). Un lieu hors de la carte est refusé `off_map`.
- `start_mission` (E11-T08) : à la réussite d'une mission confiée par la voix, le premier lieu de la fiche (ordre du
  fichier) pas encore donné à ce personnage par cette voix est marqué sur sa carte comme par `mark_map` (hors budget et
  délai de `mark_map`) ; sans lieu restant, réputation seule (`docs/protocole-carnet-v2.md`, « Mission donnée par une
  voix »). Le bâtiment de la mission, lui, n'est jamais un lieu de la fiche : le serveur le choisit. Voix livrées qui
  donnent des missions (E11-T13) : Darlene et Cody (`actions=say,start_mission`, gabarit `scout`, compte rendu à la
  radio par `report_mission` implicite) ; sans ligne `place=`, leur récompense est la réputation seule. Night Owl,
  Whitaker et Walt n'en donnent pas ; Gus garde `propose_trade`.
- Les lieux n'ont aucun autre effet : ni distance (`too_far`), ni `coords` de la voix, ni `persona_state`.

## Erreurs

La lecture s'arrête à la **première** erreur. Message en anglais, identique dans les deux lecteurs :
`line N: <raison>` (Python : exception `PersonaError` avec `.line` et `.reason` ; Lua : `nil, "line N: …"`).
Les numéros de ligne commencent à 1 et comptent toutes les lignes du fichier.

Erreurs sur une ligne (dans l'ordre du fichier) :

| Cas | Message |
|---|---|
| BOM en tête de fichier | `line 1: file starts with a byte order mark (save it as UTF-8 without BOM)` |
| Octet UTF-8 invalide (ou U+FFFD), en-tête ou prompt | `line N: invalid UTF-8 (save the file as UTF-8)` |
| Ligne sans `=` avant `[prompt]` | `line N: expected key=value or [prompt]` |
| Clé mal formée | `line N: bad key 'Radio'` |
| Clé inconnue | `line N: unknown key 'colour'` |
| `budget.<action>` inconnue | `line N: unknown action 'fly' in key 'budget.fly'` |
| Clé répétée | `line N: duplicate key 'name' (first set on line 3)` |
| Valeur vide | `line N: empty value for key 'radio'` |
| `format` | `line N: unsupported format '2' (expected 1)` |
| `id` | `line N: bad id 'Walt' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)` |
| `language` | `line N: bad language 'eng' (two lowercase letters, e.g. en)` |
| Fréquence mal écrite | `line N: bad frequency '145' (MHz with one decimal, e.g. 145.0)` |
| Fréquence hors bornes | `line N: frequency 0.8 out of range (1.0 to 999.8 MHz)` |
| Fréquence hors pas | `line N: frequency 145.1 is not on the 0.2 MHz step of the radios` |
| Fréquence en double | `line N: duplicate frequency 145.0` |
| Plage mal écrite, inversée ou réduite à une fréquence | `line N: bad frequency range '150.0-140.0' (two frequencies in MHz, lowest first, e.g. 140.0-150.0)` |
| Borne de plage mal écrite, hors bornes ou hors pas | messages de la fréquence ci-dessus (`bad frequency '140'`, `frequency 0.8 out of range …`, `frequency 150.1 is not on …`) |
| Plages qui se chevauchent (ou se touchent) | `line N: frequency range '109.0-120.0' overlaps another range of the sheet` |
| `radio`, `location`, `state` | `line N: bad radio 'ham' (expected any, high_tier)` (même forme pour les autres) |
| Plage horaire mal écrite | `line N: bad listening hours '8:00-12:00' (always, or HH:MM-HH:MM ranges separated by commas)` |
| Plage vide | `line N: empty listening range '06:00-06:00'` |
| `coords` | `line N: bad coords '10600,9300' (x,y,z whole numbers, z from -32 to 31)` |
| `place` en moins de trois parties | `line N: bad place 'mill 10600,9300,0' (id x,y,z label, e.g. mill 10600,9300,0 Old mill)` |
| Identifiant de lieu | `line N: bad place id 'Mill' (a to z, 0 to 9 and _, 32 characters at most)` |
| Coordonnées de lieu | `line N: bad place coords '10600,9300' (x,y,z whole numbers, z from -32 to 31)` |
| Libellé de lieu trop long | `line N: place label of 'mill' too long (48 bytes of UTF-8 at most)` |
| Lieu répété | `line N: duplicate place 'mill' (first set on line 5)` |
| Treizième lieu | `line N: too many places (12 at most)` |
| Action inconnue ou répétée | `line N: unknown action 'fly'`, `line N: duplicate action 'say'` |
| Nombre (`budget`, `budget.<action>`, `call_one_in`) | `line N: bad budget '-1' (whole number from 0 to 999999)` (`… 0 to 1000` pour `call_one_in`) |
| `call_text` | `line N: bad call_text 'IGUI Call' (translation key: A to Z, a to z, 0 to 9 and _)` |

Erreurs de la fiche entière, contrôlées ensuite dans cet ordre :

| Cas | Ligne indiquée | Message |
|---|---|---|
| Pas de ligne `[prompt]` | dernière ligne (1 si le fichier est vide) | `missing [prompt] line before the prompt text` |
| Prompt vide | ligne `[prompt]` | `empty prompt text after [prompt]` |
| Clé obligatoire absente (`format`, `id`, `name`, dans cet ordre) | ligne `[prompt]` | `missing key 'name'` |
| Ni `frequencies` ni `frequency_range` | ligne `[prompt]` | `missing key 'frequencies' or 'frequency_range'` |
| `frequencies` et `frequency_range` ensemble | la seconde des deux lignes | `frequencies and frequency_range cannot be used together (fixed frequencies or ranges to draw from)` |
| `id` différent du nom du fichier | ligne `id` | `id 'other' does not match the file name 'case.txt'` |
| `location=fixed` sans `coords` | ligne `location` | `location fixed needs a coords line` |
| `coords` sans `location=fixed` | ligne `coords` | `coords is only allowed with location=fixed` |
| `call_one_in` > 0 sans `call_text` | ligne `call_one_in` | `call_one_in needs a call_text line` |
| `budget.<action>` hors `actions` | ligne du budget | `budget.signal set but action 'signal' is not in actions` |

Fichier absent : Lua rend `nil, "cannot read <chemin>"` ; Python lève l'`OSError` habituel.

Vérifier une fiche à la main : `python bridge/persona_store.py chemin\vers\fiche.txt` (une ligne `OK` ou l'erreur par
fichier, code de sortie 1 si une fiche est refusée).

## Différences connues entre les lecteurs

- Le jeu lit le fichier en UTF-8 par `InputStreamReader` : un octet invalide devient U+FFFD et le BOM reste en tête de
  la première ligne. Le lecteur Python décode de la même façon (`errors='replace'`), d'où les deux mêmes refus ; une
  fiche contenant volontairement le caractère U+FFFD est aussi refusée des deux côtés.
- En Kahlua, une chaîne compte des unités UTF-16 ; sous Lua 5.1 (lupa), des octets. Aucune règle ne mesure donc la
  longueur d'un texte libre (`name`, `knows`, prompt) : seules les valeurs ASCII contrôlées (`id`, nombres) ont une
  longueur maximale.
- Les classes de caractères sont écrites en plages explicites (`[a-z]`, `[0-9]`), jamais `%a`/`%d` en Lua ni `\d` en
  Python, qui acceptent des lettres et chiffres non ASCII selon le moteur.

## Exemple complet

Fiche fictive de démonstration (ce n'est pas une des voix livrées ; les six fiches réelles sont dans
`Contents/mods/batman_RadioSurvivor/42.21/personas/`, E05-T04).
Elle a des fréquences fixes ; pour un tirage à chaque partie, remplacer la ligne `frequencies` par par exemple
`frequency_range=5.0-9.8, 140.0-150.0` (une fréquence tirée par plage) :

```text
format=1
id=case
name=Hélène Dupré
language=fr
frequencies=7.2, 145.0
radio=high_tier
listen=22:00-06:00,12:30-13:00
location=fixed
coords=10600,9300,0
knows=Le pont de Muldraugh est tombé.
ignores=Ce qui se passe en Ohio.
secret=Elle a laissé son frère à West Point.
actions=say,signal
budget=12
budget.signal=2
call_one_in=4
call_text=IGUI_Test_Call
state=silent

[prompt]
Tu es Hélène, ...
```

## Missions et récompenses des voix

Les cinq clés facultatives suivantes sont strictes, non répétables, et identiques dans les lecteurs Python et Lua.
Les listes sont séparées par des virgules, sans doublons ni entrée vide ; la casse compte.

| Clé | Valeurs | Défaut |
|---|---|---|
| `cache_table` | `medical`, `ammo`, `tools`, `food`, `radio` | aucune table |
| `shares` | IDs de voix, même syntaxe que `id` ; présence et état vérifiés par le serveur | aucun destinataire |
| `teaches` | `Doctor`, `Aiming`, `Reloading`, `Woodwork`, `Mechanics`, `Electricity`, `MetalWelding`, `Cooking`, `Farming`, `Fishing`, `Trapping`, `PlantScavenging` | aucune leçon |
| `missions` | `scout`, `deliver`, `retrieve`, `clear`, `signal` | `scout` |
| `rewards` | `cache`, `frequency`, `stashmap`, `lesson` | ancien repère de reconnaissance |

`actions=...,share_frequency` autorise aussi le partage direct d'une fréquence comme geste de confiance.
Le modèle propose uniquement cette action : le serveur choisit une voix active autorisée par `shares`, puis ajoute
la fréquence exacte ; le modèle ne reçoit jamais cette fréquence. Les lieux `place=` servent aux caches et aux
objectifs ; leurs coordonnées restent côté serveur. Les tables de matériel sont fermées côté serveur.

À la réussite, le serveur conserve la réputation et choisit une seule récompense réalisable dans l'ordre cyclique
`cache`, `frequency`, `stashmap`, `lesson`, par joueur et voix. L'ordre de la liste `rewards` ne change pas ce cycle.
L'IA n'en choisit ni le type ni le contenu. Sans `rewards`, les fiches existantes gardent leur comportement antérieur.

```text
cache_table=medical
shares=gus,cody
teaches=Doctor
missions=scout,deliver,retrieve,clear,signal
rewards=cache,frequency,stashmap,lesson
```
