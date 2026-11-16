# Format des fiches de voix radio (format 1)

Une fiche décrit une voix du réseau radio (E05) : identité, fréquences, horaires, lieu, actions autorisées, état,
lieux, missions proposées, récompenses, catégories d'objets propres, et le texte du prompt donné au LLM, seul lieu de
sa personnalité et de son passé (E22-T14) (fiche à sections depuis E20-T03, [ADR des voix déclarées](../architecture/decisions/adr-personas-declaratives.md),
D01, D03, D04). Deux lecteurs :

- le serveur : `media/lua/server/RadioSurvivor/RS_Persona.lua` (`RS_Persona.readFile`, `RS_Persona.parseLines`),
  qui lit le fichier avec `getFileReader`, sans `loadstring`. C'est **le seul lecteur complet** : il valide toute la
  fiche, sections comprises, avec les règles que lui passe `RS_Personas.rules()` (types de mission inscrits et leurs
  paramètres, natures de récompense, compétences, catalogue des catégories) ;
- le pont : `bridge/persona_store.py` (`load_file`, `parse_bytes`, `parse_lines`), qui lit l'en-tête, les sections
  `[place]` et le prompt avec **les mêmes règles et les mêmes messages**, et passe les sections `[mission]`,
  `[rewards]` et `[category]` sans les lire (le serveur les valide).

`tests/test_personas.py` compare les deux lecteurs sur les mêmes fichiers (lupa) ; `tests/test_persona_sections.py`
couvre ce que seul le serveur valide ; `tests/test_kahlua.py` refait une partie des cas dans la VM Kahlua réelle
(accents, BOM, UTF-8 invalide).

État : format et lecteurs (E05-T01) ; chargement et relecture à chaud côté serveur (E05-T02) ; routage par voix,
radio exigée, budget et prompt construit par le pont (E05-T03, « Routage par voix » ci-dessous) ; fréquences tirées
au hasard dans la zone de leur niveau de radio, à chaque nouvelle partie (E05-T07, « Tirage des fréquences » ci-dessous) ; appels spontanés
de chaque voix (E05-T05, « Appels spontanés » ci-dessous). Les actions autres que `say` sont E07 : depuis E07-T01, la
voix peut les proposer et le serveur les juge (catalogue, fiche, `budget.<action>` par jour de jeu, distance, délai),
mais seules celles dotées d'un exécuteur ont un effet ; les autres sont refusées `not_available`. Depuis E22-T13,
toute voix se souvient de ses appelants, pour toujours, sans rien écrire dans sa fiche : `remember` n'est plus une
action de la liste `actions=` (une fiche qui l'écrit, ou qui écrit `budget.remember`, est refusée comme pour toute
action inconnue) ; la voix retient des faits courts sur l'appelant, rangés par le serveur, rappelés au pont comme
souvenirs non vérifiés, gardés à la mort du personnage (`docs/specifications-techniques/protocole-carnet-v2.md`,
« Mémoire des voix »). Depuis E07-T06, `persona_state` est
effective : la voix fait évoluer son propre moral, ses réserves et le lieu où elle dit se trouver, rangés par le
serveur dans son état privé (jamais dans la fiche, qui reste celle de l'admin) et rappelés au pont
(`docs/specifications-techniques/protocole-carnet-v2.md`, « État dynamique des voix »). Depuis E07-T04, `mark_map` est effective : la fiche
liste ses lieux connus (sections `[place]`, « Lieux connus » ci-dessous), la voix en choisit un par son identifiant et le
serveur le marque sur la carte du seul appelant (`docs/specifications-techniques/protocole-carnet-v2.md`, « Repère sur la carte »). Les fiches livrées n'existent qu'en un exemplaire, dans le mod (E05-T10) ; le prompt de secours
`bridge/persona.txt` est retiré.

## Fichier

- Un fichier par voix, nommé `<id>.txt` ; l'`id` de la fiche doit être exactement ce nom sans `.txt`.
- Emplacement de travail : `Zomboid\Lua\batman_RadioSurvivor\personas\` sur la machine du serveur (ou de la
  partie solo ; `<cachedir>\Lua\...` pour un serveur lancé avec `-cachedir`). Les fiches livrées (Walt et les
  autres voix) sont dans le mod, `Contents/mods/batman_RadioSurvivor/42.21/personas/`, seul exemplaire du dépôt (voir
  « Chargement par le serveur »).
- Texte **UTF-8 sans BOM**. Fins de ligne `\n`, `\r\n` ou `\r` (découpage de `BufferedReader.readLine`, celui de
  `getFileReader`).
- Trois parties, dans cet ordre : un en-tête de lignes `clé=valeur`, des sections facultatives (`[place <id>]`,
  `[mission <id>]`, `[rewards]`, `[category <id>]`, `[trade]`, `[note]`, dans n'importe quel ordre), puis une ligne `[prompt]` suivie du
  texte libre du prompt. Une ligne `clé=valeur` placée après un en-tête de section appartient à cette section.
- Un fichier dont le nom commence par `_` n'est pas une voix : c'est le catalogue partagé des catégories
  (`_categories.txt`, « Catalogue des catégories » ci-dessous).

```text
# commentaire
format=1
id=walt
name=Walt Hensley
radio=any_talkie
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
- Une clé de l'en-tête ne peut apparaître qu'une fois.
- Une valeur vide est refusée : pour garder la valeur par défaut, retirer la ligne.
- Les listes (`listen`, `actions`) sont séparées par des virgules, espaces
  tolérés autour.
- `radio` et `frequency` ne sont pas des listes : `radio` prend un seul niveau, `frequency` une seule fréquence.

### Sections

- Une section commence par une ligne d'en-tête `[nom id]` (`[place mill]`), ou `[nom]` pour `[rewards]`, `[trade]` et
  `[note]`, qui n'ont pas d'identifiant ; espaces tolérés autour du nom et de l'identifiant. Elle finit à l'en-tête suivant ou à `[prompt]`.
- Identifiant : `a`-`z`, `0`-`9`, `_`, 32 caractères au plus, unique par genre de section dans la fiche
  (`duplicate place 'mill' (first set on line 5)`) ; `[rewards]`, `[trade]` et `[note]` une fois au plus.
- Corps : lignes vides, commentaires `#` et lignes `clé=valeur`, coupées comme celles de l'en-tête ; clés en minuscules
  (`a` à `z`, `_`), une fois chacune sauf `item` de `[category]`, `item` et `group` de `[trade]`, `loot` et `glovebox` de `[note]`, valeur non vide. Une clé inconnue de la section est
  refusée (`unknown key 'colour' in [place mill]`).
- Les références entre sections (lieu d'une mission, catégorie d'une récompense, mission citée par `after`) sont
  contrôlées après la lecture du fichier : une section peut citer une section écrite plus bas.
- Pas de commentaire en fin de ligne : `#` et `;` font partie de la valeur.

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
| `radio` | `any_talkie`, `good_talkie`, `pro_talkie`, `tactical`, `military` : un niveau, du plus faible au plus fort (« Tirage des fréquences ») | `radio` **ou** `frequency` obligatoire, pas les deux | Radio exigée : le serveur tire à chaque partie une fréquence libre dans la zone de ce niveau. Une seule valeur, pas une liste. |
| `frequency` | un MHz à une décimale, de `0.2` à `1000.0`, au pas de 0,2 MHz des radios | voir `radio` | Une fréquence fixe, la même dans toutes les parties. Lue en kHz (`145.0` → 145000). Son niveau se déduit (« Tirage des fréquences »). Une seule valeur ; prime sur un tirage. |
| `listen` | `always`, ou liste de plages `HH:MM-HH:MM` (heure du jeu, deux chiffres, 00:00 à 23:59) | `always` | Horaires d'écoute. Une plage dont la fin précède le début passe minuit (`22:00-06:00`). Début et fin égaux : refusé. Minute de début incluse, minute de fin exclue. |
| `location` | `none`, `fixed`, `rescue` | `none` | `none` : hors carte ; `fixed` : point fixe de la carte (`coords` obligatoire) ; `rescue` : point choisi par le serveur pour un secours (E12), pas de `coords`. |
| `coords` | `x,y,z` entiers, `x` et `y` de 0 à 999999, `z` de -32 à 31 | aucun | Seulement avec `location=fixed`. |
| `actions` | liste parmi `say`, `mark_map`, `reveal_area`, `signal`, `place_cache`, `place_scene`, `start_mission`, `persona_state`, `propose_trade`, `report_mission`, `share_frequency`, sans doublon | `say` | Actions que la voix peut proposer (catalogue fermé, note de travail §02). `remember` n'y figure plus (E22-T13) : toute voix l'a sans la lister (faits de 200 caractères au plus sur l'appelant, 2000 caractères et 50 faits au plus par appelant et par personnage, sans éviction ni effet de jeu ; une fiche qui la liste est refusée). Seules les actions dotées d'un exécuteur côté serveur ont un effet (`say`, diffusée comme avant ; `persona_state` depuis E07-T06 : paramètres `morale` et `supplies`, entiers de 0 à 10 (5 par défaut), changés d'au plus 2 par appel, une demande au-delà ou hors bornes étant ramenée, et `place`, lieu dit de 40 caractères au plus, simple récit sans effet sur `coords` ni sur la distance ; au moins un paramètre, aucun autre ; état propre à la voix, rangé dans l'état privé du serveur, jamais dans la fiche ; sans effet de jeu ; plafond `budget.persona_state`) ; `mark_map` depuis E07-T04 : paramètre unique `place`, identifiant d'un lieu `[place]` de la fiche avec `use=mark`, repère posé sur la carte du monde du seul appelant, 30 s réelles au moins entre deux repères de la voix, plafond `budget.mark_map` ; une fiche `mark_map` sans lieu `use=mark` ne la propose pas au LLM ; `reveal_area` depuis E07-T05 : même paramètre `place`, le quartier autour du lieu devient connu sur la carte du monde du seul appelant, carré de 5 blocs de 32 cases (160 cases de côté au plus, moins en bord de carte), 60 s réelles au moins entre deux révélations de la voix, plafond `budget.reveal_area`, conditions de proposition identiques à `mark_map` ; `start_mission` depuis E11-T08 : paramètre unique `template`, `scout` seul, mission « reconnaître » confiée à l'appelant (bâtiment choisi par le serveur autour de lui, décrit à la voix sans coordonnée juste après, par une demande de consigne où elle dit les indices (E11-T09), puis aux appels suivants), une mission ouverte à la fois par appelant et par voix, 60 s réelles au moins entre deux missions de la voix et 30 min après la clôture de la précédente du même appelant, compte rendu à la radio sur la fréquence de la voix après la visite (E11-T13 : action `report_mission`, sans paramètre, rendue par le modèle quand l'appel en rend compte et revérifiée par le serveur ; permise à toute fiche qui autorise `start_mission`, sans la lister), récompense en réputation et, sans section `[rewards]`, repère du premier lieu `use=mark` pas encore donné à ce personnage, plafond `budget.start_mission` ; carnet du joueur requis) ; `place_cache` depuis E11-T06 : paramètre unique `table` (`food`, `medical`, `ammo`, `tools`), sac marqué rempli de cette table fermée et posé une seule fois au bâtiment de la dernière mission donnée par la voix à l'appelant (ouverte, sinon sa dernière réussite), une cache par mission, 60 s réelles au moins entre deux caches de la voix, plafond `budget.place_cache` ; serveur seulement pour l'instant : le pont ne la propose pas encore au LLM ; `propose_trade` depuis E13-T02 : paramètres `items` (« `Nom:quantité` » séparés par des virgules, objets du stock du passage) et `margin` facultative, offre du passeur contrôlée contre la table validée et figée par le serveur, qui joint le livre du passeur (`trade=`) aux demandes de cette voix (`docs/annexes/conception/passeur-offre.md`) ; les autres sont refusées `not_available` et journalisées. Toute voix répond en réponse structurée depuis E22-T13 (`remember`, `docs/specifications-techniques/protocole-carnet-v2.md`, « Réponse radio structurée »). |
| `budget` | entier de 0 à 999999 | `0` | Demandes par heure réelle pour cette voix, en plus du plafond global `MaxPerHour` ; `0` = seul le plafond global. |
| `budget.<action>` | entier de 0 à 999999 | aucun | Utilisations par jour de jeu de cette action ; `0` = pas de plafond. L'action doit figurer dans `actions`. |
| `call_one_in` | entier de 0 à 1000 | `0` | Appel général spontané : une chance sur N à chaque heure de jeu, pendant les heures d'écoute, quand personne ne parle à la voix ; `0` = jamais. Voir « Appels spontanés ». |
| `call_text` | clé de traduction (`A`-`Z`, `a`-`z`, `0`-`9`, `_`) | aucun | Texte fixe de l'appel, diffusé quand le pont n'en écrit pas, `%1` = fréquence affichée. Clé du fichier `IG_UI.json` du mod (préfixe `IGUI_`) : voix livrées avec le mod. `call` ou `call_text` (un seul des deux) est obligatoire si `call_one_in` > 0. |
| `call` | texte de 200 octets UTF-8 au plus, sans `<`, `>` ni `^`, `%` seulement dans `%1` | aucun | E22-T07 : texte fixe de l'appel écrit dans la fiche, dans n'importe quelle langue (voix créées avec l'atelier), `%1` = fréquence affichée ; même rôle que `call_text`, sans clé de traduction. Interdit avec `call_text`. |
| `state` | `active`, `silent`, `gone`, `dead` | `active` | `active` : répond ; `silent` : écoute mais ne répond pas (pause) ; `gone` : retirée du réseau ; `dead` : morte dans l'histoire. Traitement : « Chargement par le serveur » et « Routage par voix ». |
| `shares` | IDs de voix, même syntaxe que `id`, sans doublon ; présence et état vérifiés par le serveur | aucun | Voix dont la fréquence peut être donnée par `share_frequency` ou une récompense `frequency` (« Missions et récompenses des voix »). |

Les deux lecteurs rendent la fiche avec ces noms (les sections `[place]` la liste
`places` de lieux `{ id, x, y, z, label, uses }` dans l'ordre du fichier (Python : `Place`, `places_for(use)` ; Lua :
plus `use`, ensemble des usages, et `RS_Persona.placesFor(sheet, use)`), les `budget.<action>` la
table `budgets`, `listen` une liste de plages `(début, fin)` en minutes du jour de jeu, vide pour `always`,
`radio` le niveau écrit (côté Lua, celui déduit de `frequency=` ; côté Python, `None` avec `frequency=`) et `frequency` la fréquence fixe en kHz, `nil` ou `None` si absente). Lua : `Personas.frequencies(id)` rend la liste des fréquences de la voix pour cette partie, au plus un élément.

## Chargement par le serveur (E05-T02)

Module `media/lua/server/RadioSurvivor/RS_Personas.lua`, côté autorité (serveur dédié ou hébergé, partie solo).

- **Fiches livrées** : dossier `personas/` de la variante du mod (`Contents/mods/batman_RadioSurvivor/42.21/personas/`,
  hors de `media/`), lu par `listFilesInModDirectory` et `getModFileReader`. C'est le seul exemplaire des fiches
  livrées dans le dépôt (E05-T10) : le pont le lit aussi pour ses tests et son mode `--test`, par chemin relatif à
  son propre fichier (`bridge/../Contents/mods/batman_RadioSurvivor/42.21/personas`) ou `--personas <dossier>` ;
  `tests/test_personas_server.py` vérifie que les seize fiches y sont valides.
- **Installation et mise à jour** (E05-T11) : à chaque chargement d'un monde (`OnLoadRadioScripts`), pour chaque fiche
  livrée :
  - absente du dossier de travail : copiée ;
  - présente et **non modifiée** par l'admin, mais différente de la version livrée (mise à jour du mod) : remplacée
    par la version livrée, journal `INFO: voice 'x' updated to the delivered version` ;
  - présente et **modifiée** par l'admin (même invalide ou vidée) : gardée, journal `WARNING: voice 'x' modified by
    the admin, delivered version not applied` à chaque chargement du monde. Pour revenir à la version livrée, supprimer
    le fichier : il est recopié au chargement suivant.

  Une fiche est non modifiée quand son **empreinte** (Adler-32 de `CA_Codec.checksum` sur les octets UTF-8, lignes
  rejointes par `\n` : indépendante des fins de ligne) est celle que le serveur a mémorisée en l'écrivant, dans
  `Zomboid/Lua/batman_RadioSurvivor/personas-fingerprints.txt` (hors du dossier des fiches ; en-tête `RSFP1`, puis
  `nom.txt empreinte`). Sans empreinte mémorisée (installation antérieure à E05-T11, fichier absent ou vidé), elle
  est non modifiée si son empreinte est celle d'une version livrée connue (`RS_Personas.KNOWN_DELIVERED` : versions
  des commits `09d7474`, `24832ea`, `486b21e` et actuelle ; toute nouvelle version livrée y ajoute la sienne,
  contrôlé par `tests/test_personas_server.py`) ; sinon elle est traitée comme modifiée. Un fichier d'empreintes **abîmé** (en-tête ou
  ligne illisible) est ignoré prudemment : aucune fiche n'est remplacée, il n'est pas réécrit, un avertissement
  indique de le vider ; les fiches absentes sont copiées quand même. Une fiche de l'admin sans équivalent livré n'est
  jamais touchée.
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

## Tirage des fréquences (E05-T07, E24-T01)

Décision du 2026-10-09 : **toutes les voix tirent leur fréquence au hasard à chaque nouvelle partie**, dans la zone du
niveau de radio de la fiche (`radio=<niveau>`, E24-T01). Une fiche à `frequency=` ne tire rien : sa fréquence est fixe,
et son niveau se déduit de cette fréquence. Code : `RS_Personas.lua`, section « Tirage ».

La table des niveaux est **la seule** à donner les réglages des radios et les zones :
`Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/RadioSurvivor/RS_RadioLevels.lua`. Le lecteur des fiches
(`RS_Persona.lua`, `bridge/persona_store.py`), le tirage (`RS_Personas.lua`) et le catalogue de l'atelier
(`tools/gen_atelier_catalog.py`, `radioLevels`) la lisent ; `tests/test_radio_levels.py` la contrôle contre les scripts
des objets radio.

### Niveaux de radio

Chaque niveau est réglé par le poste **le plus faible** du niveau (bornes `MinChannel` / `MaxChannel` de
`media/scripts/generated/items/radio.txt`, 42.22, bornes incluses comme le contrôle du serveur). Chaque plage de réglage
contient celle du niveau précédent. La **zone** d'un niveau est formée des fréquences que son poste le plus faible règle
et que le niveau précédent ne règle pas (`Levels.zones`). Pas des radios : 0,2 MHz (`Levels.STEP_KHZ` = 200 kHz).

| Niveau (`radio=`) | Postes du niveau | Réglage du poste le plus faible (MHz) | Zone de tirage (MHz) |
|---|---|---|---|
| `any_talkie` | `WalkieTalkie1` (Toys-R-Mine), `WalkieTalkieMakeShift` | 75-150 | 75.0-150.0 |
| `good_talkie` | `WalkieTalkie2` (ValuTech) | 50-200 | 50.0-74.8 et 150.2-200.0 |
| `pro_talkie` | `WalkieTalkie3` (Premium Technologies) | 25-300 | 25.0-49.8 et 200.2-300.0 |
| `tactical` | `WalkieTalkie4` (tactique), `HamRadio1` (HAM Premium), `HamRadioMakeShift` | 10-500 | 10.0-24.8 et 300.2-500.0 |
| `military` | `WalkieTalkie5`, `ManPackRadio`, `HamRadio2` (US Army) | 0,2-1000 | 0.2-9.8 et 500.2-1000.0 |

Fréquence fixe (`frequency=`) : son niveau est le plus faible qui la règle (`Levels.levelOf`). Exemples : `145.0` donne
`any_talkie`, `152.0` donne `good_talkie`, `284.6` donne `pro_talkie`, `320.0` donne `tactical`, `7.2` donne `military`.

### Voix livrées

| Niveau | Voix (`id`) |
|---|---|
| `any_talkie` | Walt (`walt`), Darlene (`darlene`), Jolene Whitaker (`whitaker`), Night Owl (`nightowl`) |
| `tactical` | Cody (`cody`) |
| `good_talkie` | Gus (`gus`), Delphine (`delphine`) |
| `pro_talkie` | Wanda (`wanda`, West Point), Lamar (`lamar`, Brandenburg), Hollis (`hollis`, Muldraugh), Loretta (`loretta`, March Ridge), Virgil (`virgil`, Irvington), Boone (`boone`, Echo Creek), Odessa (`odessa`, Rosewood), Ezra (`ezra`, Ekron), Maxine (`maxine`, Fallas Lake) |

Les zones recoupent des chaînes du jeu et d'autres mods (stations FM, alerte d'urgence, Military Drop) : le tirage les
évite, comme il évite les fréquences déjà prises par une autre voix.

### Règles

- **Tirage** : une fréquence **uniforme** (`ZombRand`) parmi les fréquences **libres** de la zone du niveau, au pas de
  0,2 MHz. Non libre : fréquence d'une chaîne qui n'est pas une voix de ce module (chaînes vanilla de `RadioData.xml`,
  AEBS, chaînes des mods déjà inscrites : `RadioScriptManager.getChannelsList`), fréquence de l'AEBS notée dans la
  ModData de `GameTime` (`dynamicRadio`), ou fréquence à moins de **1,0 MHz** (`RS_Personas.MIN_GAP_KHZ`) d'une fréquence
  d'une autre voix chargée (fixe, tirée ou mémorisée, quel que soit son état). Voix traitées dans leur ordre de
  chargement. Aucune fréquence libre : erreur journalisée (`ERROR: voice '…': no free frequency left for the radio <niveau>`,
  avec `choose a stronger radio in its sheet`) ; la voix n'est pas servie.
- **Ordre de création de l'AEBS** : elle existe déjà au moment du tirage. Les fichiers Lua vanilla sont chargés avant ceux
  des mods (`LuaManager.LoadDirBase`, `LuaManager.java:1197-1198`, 42.21.0), donc l'abonné `OnLoadRadioScripts` de
  `ISDynamicRadio.lua` (qui tire et crée l'AEBS) passe avant celui du mod. La lecture de `dynamicRadio` couvre aussi
  l'ordre inverse. Une chaîne inscrite après nous et tirée par `ZomboidRadio.getRandomFrequency` évite nos fréquences
  (`knownFrequencies`, `ZomboidRadio.java:139-147, 179-183`).
- **Monde neuf** : second argument d'`OnLoadRadioScripts`, vrai quand `savedWorldVersion == -1`
  (`ZomboidRadio.java:246` : `map_t.bin` absent sur un serveur, `map_ver.bin` en solo ; base `multiplayer.md`). Toutes
  les voix sont tirées ; un ancien fichier de tirage du même nom (monde effacé puis recréé sous le même nom) est ignoré
  puis réécrit.
- **Mémoire** : fichier `Zomboid/Lua/batman_RadioSurvivor/frequencies-<hex>.txt` sur la machine qui fait autorité,
  `<hex>` = octets hexadécimaux de `« mode/nom de la partie »` (`getWorld():getGameMode()`, `getWorld():getWorld()`,
  comme l'état du carnet). Jamais de ModData globale (lisible par tout client). Contenu : en-tête `RSFREQ2`, puis une
  ligne `id niveau kHz` par voix tirée (`niveau` : le niveau de la fiche au moment du tirage, `kHz` : la fréquence
  tirée). Écrit à chaque changement.
- **Redémarrage** (monde existant) : les fréquences mémorisées sont reprises, sans tirage. Une ligne abîmée est ignorée
  (avertissement) et sa voix est tirée de nouveau.
- **Raisons d'un nouveau tirage** : seule la voix concernée est tirée de nouveau ; les autres gardent leur fréquence.
  La raison est écrite dans le journal, par exemple `voice 'walt' drew 137.4 MHz for the radio any_talkie (new game)` :
  - `new game` : monde neuf, aucune fréquence mémorisée ;
  - `no frequency remembered for this voice` : aucune fréquence mémorisée pour cette voix ;
  - `radio changed from <niveau>` : `radio=` a été changé dans la fiche ;
  - `<fréquence> taken by the radio channel '<nom>'` : la fréquence mémorisée est prise par une chaîne étrangère ;
  - `<fréquence> too close to <fréquence> of voice '<id>'` : la fréquence mémorisée est à moins de 1,0 MHz d'une autre voix.
- **Fréquence fixe** : `frequency=` ne tire rien. Une fréquence fixe l'emporte toujours sur une fréquence tirée : la voix
  tirée en prend une autre. Deux fiches fixes sur la même fréquence : la voix chargée la première (ordre alphabétique au
  premier chargement) la garde, l'autre ne la sert pas (avertissement journalisé). Une fréquence fixe déjà prise par une
  chaîne étrangère n'est pas servie et est réessayée à chaque relecture (avertissement).
- **Fiche modifiée à chaud** : seule la voix changée est tirée de nouveau (raisons ci-dessus) ; les autres voix gardent
  leurs fréquences. Une fiche passée à `frequency=` perd son tirage mémorisé. Fichier retiré : le tirage reste en mémoire
  et revient avec la fiche (s'il est encore libre).
- **Journal** : chaque tirage est écrit dans le journal du serveur (`[RadioSurvivor] personas: voice '…' drew …`). Les
  fréquences tirées sont un secret de partie : jamais dans une fiche, un prompt, une commande au pont ni une commande aux
  clients (E05-T08). Limites : voir « Ce qui pourrait révéler une fréquence ».
- **Radio exigée** : aucun contrôle de niveau à part. La radio de l'appelant doit régler la fréquence de la voix (bornes
  du script de l'objet) : c'est le contrôle du routage (« Routage par voix »). Une radio plus faible ne peut simplement
  pas la régler.
- **Pont** : il n'a pas besoin de la fréquence. Le serveur choisit la voix d'après la fréquence de la radio et envoie
  `voice=<id>` (E05-T03) ; le pont lit la fiche pour le prompt.

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
  heures d'écoute, budget de la voix épuisé. La phrase part sur la radio, personne ne répond,
  rien n'est envoyé au pont : ni coût, ni délai, ni plafond, ni budget consommés. Silence plutôt que parasites :
  même règle que `silent` depuis E05-T02, et des parasites trahiraient une présence sur la fréquence. Le client
  reçoit `accepted` puis aussitôt `done` : la même suite partout, aucun message.
- **Budget** : `budget=N` (> 0) limite la voix à N demandes acceptées par heure réelle glissante, en plus du plafond
  global `MaxPerHour` ; au-delà, la voix se tait (silence : un refus `Busy` propre à la voix trahirait sa présence,
  E05-T08). Compteurs en mémoire, remis à zéro au redémarrage du serveur.
- **Demande au pont** : champ `voice=<id>` (`docs/specifications-techniques/protocole-carnet-v2.md`). Le pont relit la fiche dans
  `<dossier d'échange>/personas/<id>.txt`, le dossier même du serveur (option `--exchange` existante), à chaque
  demande dont le fichier a changé ; une fiche refusée garde côté pont sa dernière version valide.
- **Prompt** : exactement le texte libre de la fiche (E22-T14 : personnalité, passé, savoir-faire et ce que la voix
  tait, écrits par l'auteur ; aucun état du monde figé), puis la situation de l'appel (date, appelant, radio), comme
  avant. Ce que la voix sait du monde vient du jeu seul : souvenirs, morts, état, mission, troc, réputation, faits du
  bulletin.
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
  voix ou une chaîne étrangère, voix `gone` ou `dead`), zone de tirage (ou « fixe »), radio requise, heures
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
  protocole court dans `docs/annexes/tests/tests-en-jeu.md`.

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
- **Texte** : demande `kind=radio_call` au pont (`docs/specifications-techniques/protocole-carnet-v2.md`). Le pont écrit un appel court (une
  ou deux phrases, trois lignes radio au plus) depuis le texte libre de la fiche, dans la langue de l'autorité, sans fréquence (il ne la connaît pas) ni fait absent de la fiche.
  L'appel entre dans l'historique de la voix (message `[General call]`), sans numéro d'appelant.
- **Secours** : pont absent, réponse vide, parasites seuls, ou rien après `Const.CALL_TIMEOUT_MS` (30 s réelles) :
  texte fixe de la fiche, `%1` = fréquence affichée, composé par l'autorité : `call` tel qu'il est écrit (E22-T07),
  sinon la clé `call_text`. Une ligne radio n'est jamais
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
- Le serveur n'envoie au client que ce que la voix dit (`say`), après ses filtres habituels (8 lignes, 140
  caractères, balises retirées).
- Ce que la voix tait sur elle-même (« elle a abandonné son frère ») s'écrit dans le texte libre, avec la règle de
  ne jamais le dire (E22-T14) ; c'est un trait du personnage, pas un secret de jeu : codes, graines, fréquences
  cachées et positions exactes des bases de joueurs ne vont **jamais** dans une fiche ni dans un prompt (note de
  travail §02). Le serveur ajoute ces valeurs après coup quand une action en a besoin.
- Seule exception à « jamais dans une commande `sendServerCommand` » : un `mark_map` accepté envoie au **seul
  appelant** les coordonnées et le libellé d'**un** lieu `[place]` (commande `map_mark`), rien d'autre de la fiche ;
  un `reveal_area` accepté lui envoie de même un rectangle de 160 cases de côté au plus autour d'un lieu (commande
  `map_reveal`, E07-T05). Autre exception, réservée à l'administration : la réponse `freqReply` du panneau de debug
  des fréquences (E05-T14), au seul demandeur autorisé, sans aucun texte de fiche (ni prompt, ni nom de lieu).

## Lieux connus (E07-T04, sections E20-T03)

Une section `[place <id>]` par lieu que la voix connaît, 12 au plus :

```text
[place mill]
at=10600,9300,0
label=Vieux moulin
use=mark

[place drop_church]
at=11795,6950,0
label=Derrière l'église baptiste
use=drop,target
```

| Clé | Valeurs | Rôle |
|---|---|---|
| `at` | `x,y,z` entiers comme `coords` (`x`, `y` de 0 à 999999, `z` de -32 à 31) | Case du lieu ; gardée par le serveur, jamais montrée au LLM. |
| `label` | texte non vide de 48 octets UTF-8 au plus (environ 24 lettres accentuées ; les deux lecteurs comptent les mêmes octets, Kahlua depuis ses unités UTF-16) | Nom du lieu, montré au LLM et affiché tel quel sur la carte du joueur : pas de secret ni de texte réservé à l'admin. |
| `use` | liste sans doublon parmi `mark`, `target`, `drop`, `landing` | Usages du lieu, ci-dessous. |

Les trois clés sont obligatoires (`missing key 'use' in [place mill]`, à la ligne de l'en-tête).

- `mark` : repère que la voix peut donner. Le prompt (mode structuré, `mark_map` ou `reveal_area` autorisée) liste
  `id: libellé` de ces lieux, jamais leurs coordonnées ; `bounded_actions` (pont) et l'exécuteur (serveur,
  `RS_MapMarks.lua`) refusent un autre identifiant. Le repère est posé au centre de la case `x,y` (le niveau `z` est
  lu mais la carte du monde est plane), sur la carte du seul appelant, comme une annotation du joueur : icône vanilla
  et libellé, sauvegardés avec ses annotations (`docs/specifications-techniques/protocole-carnet-v2.md`, « Repère sur
  la carte »). Le joueur peut l'effacer ; un nouveau `mark_map` du même lieu le repose, sans doublon. `reveal_area`
  (E07-T05) : le quartier autour du lieu devient connu sur la carte du seul appelant, carré de 5 blocs de 32 cases
  centré sur le bloc du lieu (160 cases de côté au plus, rogné en bord de carte), comme une carte vanilla lue ;
  persistant, sans retour en arrière (« Quartier révélé » du protocole). Un lieu hors de la carte est refusé `off_map`.
  Mission réussie d'une voix **sans** section `[rewards]` (E11-T08) : le premier lieu `mark` (ordre du fichier) pas
  encore donné à ce personnage par cette voix est marqué sur sa carte comme par `mark_map` (hors budget et délai) ;
  sans lieu restant, réputation seule.
- `target` : objectif possible d'une mission (`target=` d'une section `[mission]`). `barricade` (E20-T09) : le
  bâtiment dont une pièce couvre la case du lieu (métagrille, chargé ou non) ; ses fenêtres et portes extérieures
  sont comptées par le serveur dans le monde (planches, tôle ou barres, d'un côté ou de l'autre, une fois par
  ouverture ; une ouverture déjà barricadée au départ, ou à sa première lecture si sa case n'était pas chargée, ne
  compte jamais ; une barricade retirée ne compte plus ; cases déchargées : dernier compte vérifié).
  `relay` (E20-T12) : le point du relais radio. Une radio d'objet du monde (`IsoWaveSignal` : radio de décor, ou
  l'`IsoRadio` que la pose d'un objet radio ajoute) qui peut émettre (`DeviceData.getIsTwoWay` : talkies-walkies,
  `ManPackRadio`, radios amateur ; ni télévision ni radio qui ne fait que recevoir), allumée (`getIsTurnedOn`) et
  alimentée (pile présente et non vide, sinon `canBePoweredHere` : réseau dans une pièce ou générateur), posée dans
  l'emprise du bâtiment du lieu (pièce de la case, métagrille) ou, hors de tout bâtiment, dans une zone carrée de
  13 × 13 cases autour du lieu ; au niveau `max(1, z du lieu)` ou plus haut, toit compris (`getMaxLevel() + 1`).
  Lu par le serveur toutes les 3 s et de nouveau au compte rendu : éteinte, sans courant ou retirée, la radio ne
  compte plus ; case de la dernière radio déchargée : dernier état vérifié.
  `watch` (E20-T14) : le poste de guet. Un participant guette tant que la copie serveur de son personnage est à
  moins de `CA_MissionConfig.Missions.watch.radius` cases (6) du lieu, sur le plan du sol (tout niveau). Le temps
  est l'âge du monde (`CA_GameClock.hours`, heures de jeu : arrêté en pause, plus rapide en x2/x3 et pendant le
  sommeil), lu à chaque passage du serveur ; il compte entre deux lectures avec quelqu'un sur place. Personne sur
  place : l'absence part de la dernière lecture avec quelqu'un et ne compte jamais ; au-delà de `absenceMinutes`
  (10 minutes de jeu), ou deux lectures à plus de `gapHours` (1 heure de jeu) d'écart, le guet repart de zéro.
  Durée atteinte : objectif rempli, définitivement. Pendant le guet, le serveur relève des faits par des sources
  inscrites (`CA_WatchFacts`, un fichier par source sous `WatchFacts/`) : hélicoptère vanilla entendu à moins de
  500 cases (`OnWorldSound` sans source, niveau 0, rayon et volume 500 : `Helicopter.java:217-218`,
  `WorldSoundManager.java:480` en 42.22) et groupe d'au moins 10 zombies à moins de 30 cases (zombies chargés du
  serveur, joueurs réanimés exclus) ; chaque fait devient une phrase anglaise du contexte de la voix, sans
  coordonnée.
  `item` (E20-T15) : le lieu de l'objet personnel. Au départ, la mission garde le bâtiment dont une pièce couvre la case du lieu (`IsoMetaGrid:getBuildingAt(x, y, z)`, emprise `BuildingDef`), à défaut une zone carrée de 9 × 9 cases autour du lieu (`CA_MissionConfig.Missions.item.zoneHalf`, 4), au niveau `z` du lieu. Le serveur y pose l'objet `item=` (`instanceItem`) une seule fois, par les règles de pose de `CA_Caches` (fiche à part `m.personal`, clé `<mission>:item`, jamais `m.cache` réservé à une récompense `cache`) : case du lieu chargée et bâtiment passé par ses histoires vanilla, case libre la plus proche du lieu dans le bâtiment, objet au sol envoyé aux clients (`AddWorldInventoryItem(..., true)`), marqué `ModData.CA_Cache` = la clé ; le drapeau de pose est sauvegardé avant, un objet déjà marqué de la clé est adopté après un arrêt (jamais un second objet). La mission garde son identifiant (`InventoryItem:getID`, gardé par les transferts MP). Trouvé : un participant le porte (copie serveur de l'inventaire, sacs compris). Déposé à une planque de la mission, seul l'objet de cet identifiant est ramassé (stratégie `dropAccepts` = `CA_Missions.onlyItem('itemId')`, partagée avec la carte de `retrieve`) : un objet du même type non marqué est laissé.
- `drop` : planque. Une mission `deliver`, `retrieve` ou `item` d'une voix porte toutes les planques de sa section (`drops=`,
  sans la clé : tous les lieux `drop` de la fiche ; `RS_DeadDrops`, E20-T05, E20-T06 : la carte d'identité de `retrieve`
  s'y dépose ; E20-T15 : l'objet personnel de `item` aussi), toutes marquées sur la carte du participant ; une voix sans lieu `drop` ne peut donner ni `deliver`, ni
  `retrieve`, ni `item` (`no_place`). La cache d'une
  récompense `cache` est posée au **premier lieu `drop`** de la fiche, à défaut à son premier lieu.
- `landing` : rendez-vous d'un marchand (clé `landing` de la section `[trade]`, E20-T07) ; jamais offert comme
  repère par `mark_map`.

Le bâtiment d'une mission `retrieve`, ou d'une mission `scout` ou `clear` sans `target=`, n'est jamais un lieu de la
fiche : le serveur le choisit autour de l'appelant. Avec `target=` (E20-T10), `scout` et `clear` prennent le bâtiment
dont une pièce couvre la case du lieu (métagrille, chargé ou non : `IsoMetaGrid:getBuildingAt`), où que soit
l'appelant, sans les règles du tirage (bâtiment habitable, distance) ; l'offre du gabarit reçoit ce lieu
(`RS_Persona.targetOf`, argument `aim` de `offer`). Sans bâtiment à ce lieu : `no_place` ; pour `clear`, densité de
zombies sous `minDensity` autour du lieu : `no_place` aussi.
Celui d'une mission `barricade` est le bâtiment du lieu `target=` de sa section (`RS_MissionTarget`, déclaration
`aimAt` du gabarit) : sans lieu `target`, départ refusé `no_target` ; sans bâtiment à ce lieu, `no_building`.
Le point d'une mission `relay` est le bâtiment du lieu `target=` (même déclaration `aimAt`), à défaut une zone
autour du lieu : sans lieu `target`, départ refusé `no_target` ; jamais d'autre refus.
Le poste d'une mission `watch` est le lieu `target=` de sa section (même déclaration `aimAt`) : sans lieu `target`,
départ refusé `no_target` ; `hours` hors de 1 à 24, `bad_hours`.
L'objet d'une mission `item` est posé au lieu `target=` de sa section (même déclaration `aimAt`, qui reçoit aussi `item=` et `label=`) : sans lieu `target`, départ refusé `no_target` ; sans `item=` ou avec un type que les scripts d'objets ne connaissent pas (`ScriptManager.FindItem`), `no_item` ; sans planque, `no_place`. Carnet : nom de l'objet (`label=`, sinon le nom du jeu), lieu, trouvé ou non, planques ; carte : un cercle autour du lieu et les planques ; voix : nom de l'objet, libellés du lieu et des planques, trouvé et ramassé (oui/non), jamais l'identifiant ni une coordonnée.
Les points d'une mission `route` (E20-T13) sont les lieux `target` nommés dans l'ordre par `points=` (`RS_MissionWaypoints`, déclaration `alongPoints` du gabarit) ; un point est franchi quand la copie serveur d'un participant, ou le véhicule où il est assis, passe à moins de `CA_MissionConfig.Missions.route.radius` cases (8) du lieu, trajet depuis la lecture précédente compris (au plus `maxStep`, 60 cases : au-delà, un saut, seule son arrivée compte) ; seul le prochain point compte, un point atteint avant son tour ne l'est pas. Carte : un cercle par point connu (franchis et prochain), carnet : « n sur N » et le prochain point ; voix : libellés dans l'ordre et compte vérifié.
Les lieux n'ont aucun autre effet : ni distance (`too_far`), ni `coords` de la voix, ni `persona_state`.

### Relevé de lieux en jeu (E22-T08)

Menu du monde « Atelier des voix : relever ce lieu » (`client/RadioSurvivor/RS_PlaceSurveyMenu.lua`) : affiché en solo en mode debug,
ou sur un client MP dont le rôle a la capacité `PopmanManage` (`CA_AdminAccess.canUse`, affichage seulement). Le client
n'envoie que la case : commande `surveyPlace` du module `RadioSurvivorSurvey` `{ op = "place", n, x, y, z }`, réponse
`surveyReply` au seul demandeur `{ n, op, ok, err }` ; en solo, appel direct. L'autorité
(`server/RadioSurvivor/RS_PlaceSurvey.lua`) revérifie les droits à chaque requête (`CA_AdminAccess.allowed`), refuse
`denied`, `bad_coords` (entiers, `x`, `y` de 0 à 999999, `z` de -32 à 31), `not_loaded` (pas de case chez elle) ou
`write_failed`, lit elle-même conteneurs, pièce et bâtiment, et réécrit
`Zomboid/Lua/batman_RadioSurvivor/workshop-places.txt` : une ligne d'en-tête `#`, puis un relevé par ligne (les 200
derniers), champs `clé=valeur` séparés par une tabulation :

```text
time=2026-11-15 10:05:00	game=1993-07-09 08:41	by=Kate Smith	at=10612,9307,0	containers=bin:trash_01_0
time=2026-11-15 10:06:12	game=1993-07-09 08:50	by=Kate Smith	at=10600,9300,1	room=kitchen	building=10590,9290,10620,9310
```

`time` : heure réelle UTC ; `game` : date du jeu ; `by` : nom du personnage ; `at` : case ; `room` : nom de la pièce
(absent dehors) ; `building` : emprise du `BuildingDef` (fin exclusive) ; `containers` : `type:sprite` de 4 conteneurs
au plus. Aucune valeur ne contient de tabulation ni de saut de ligne (`;` et `:` deviennent `_` dans `containers`).
Le pont le lit (`bridge/place_surveys.py`, `GET /api/surveys` de l'atelier), sans jamais l'écrire.

## Erreurs

La lecture s'arrête à la **première** erreur. Message en anglais, identique dans les deux lecteurs :
`line N: <raison>` (Python : exception `PersonaError` avec `.line` et `.reason` ; Lua : `nil, "line N: …"`).
Les numéros de ligne commencent à 1 et comptent toutes les lignes du fichier.

Erreurs sur une ligne (dans l'ordre du fichier) :

| Cas | Message |
|---|---|
| BOM en tête de fichier | `line 1: file starts with a byte order mark (save it as UTF-8 without BOM)` |
| Octet UTF-8 invalide (ou U+FFFD), en-tête ou prompt | `line N: invalid UTF-8 (save the file as UTF-8)` |
| Ligne sans `=` ni en-tête avant `[prompt]` | `line N: expected key=value or [prompt]` |
| Clé mal formée | `line N: bad key 'Radio'` |
| Clé inconnue | `line N: unknown key 'colour'` |
| `budget.<action>` inconnue | `line N: unknown action 'fly' in key 'budget.fly'` |
| Clé répétée | `line N: duplicate key 'name' (first set on line 3)` |
| Valeur vide | `line N: empty value for key 'radio'` |
| `format` | `line N: unsupported format '2' (expected 1)` |
| `id` | `line N: bad id 'Walt' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)` |
| `language` | `line N: bad language 'eng' (two lowercase letters, e.g. en)` |
| Fréquence mal écrite | `line N: bad frequency '145' (MHz with one decimal, e.g. 145.0)` |
| Fréquence hors bornes | `line N: frequency 1000.2 out of range (0.2 to 1000.0 MHz)` |
| Fréquence hors pas | `line N: frequency 145.1 is not on the 0.2 MHz step of the radios` |
| `radio`, `location`, `state` | `line N: bad radio 'ham' (expected any_talkie, good_talkie, pro_talkie, tactical, military)` (même forme pour les autres) |
| Plage horaire mal écrite | `line N: bad listening hours '8:00-12:00' (always, or HH:MM-HH:MM ranges separated by commas)` |
| Plage vide | `line N: empty listening range '06:00-06:00'` |
| `coords` | `line N: bad coords '10600,9300' (x,y,z whole numbers, z from -32 to 31)` |
| Section inconnue | `line N: unknown section 'shop' (expected place, mission, rewards, category, trade or prompt)` |
| Section sans identifiant, ou `[rewards]` avec un identifiant | `line N: section [place] needs an id, e.g. [place mill]`, `line N: section [rewards] takes no id` |
| Identifiant de section | `line N: bad place id 'Mill' (a to z, 0 to 9 and _, 32 characters at most)` (même forme pour `mission`, `category`) |
| Section répétée | `line N: duplicate place 'mill' (first set on line 5)`, `line N: duplicate section [rewards] (first set on line 5)` |
| Clé inconnue, répétée dans une section | `line N: unknown key 'colour' in [place mill]`, `line N: duplicate key 'at' in [place mill] (first set on line 6)` |
| Coordonnées de lieu | `line N: bad place coords '10600,9300' (x,y,z whole numbers, z from -32 to 31)` |
| Libellé de lieu trop long | `line N: place label of 'mill' too long (48 bytes of UTF-8 at most)` |
| Usage de lieu | `line N: bad use entry 'hide' (expected mark, target, drop, landing)`, `line N: duplicate use entry 'mark'` |
| Clé de lieu absente (ligne de l'en-tête) | `line N: missing key 'at' in [place mill]` |
| Treizième lieu (ligne de l'en-tête) | `line N: too many places (12 at most)` |
| Action inconnue ou répétée | `line N: unknown action 'fly'`, `line N: duplicate action 'say'` |
| Nombre (`budget`, `budget.<action>`, `call_one_in`) | `line N: bad budget '-1' (whole number from 0 to 999999)` (`… 0 to 1000` pour `call_one_in`) |
| `call_text` | `line N: bad call_text 'IGUI Call' (translation key: A to Z, a to z, 0 to 9 and _)` |
| `call` | `line N: call too long (200 bytes of UTF-8 at most)`, `line N: bad call 'Hello <b>' (no <, > or ^; % only in %1, the frequency)` |

Erreurs de la fiche entière, contrôlées ensuite dans cet ordre :

| Cas | Ligne indiquée | Message |
|---|---|---|
| Pas de ligne `[prompt]` | dernière ligne (1 si le fichier est vide) | `missing [prompt] line before the prompt text` |
| Prompt vide | ligne `[prompt]` | `empty prompt text after [prompt]` |
| Clé obligatoire absente (`format`, `id`, `name`, dans cet ordre) | ligne `[prompt]` | `missing key 'name'` |
| Ni `radio` ni `frequency` | ligne `[prompt]` | `missing key 'radio' or 'frequency'` |
| `radio` et `frequency` ensemble | la seconde des deux lignes | `radio and frequency cannot be used together (a radio level to draw a free frequency, or one fixed frequency)` |
| `id` différent du nom du fichier | ligne `id` | `id 'other' does not match the file name 'case.txt'` |
| `location=fixed` sans `coords` | ligne `location` | `location fixed needs a coords line` |
| `coords` sans `location=fixed` | ligne `coords` | `coords is only allowed with location=fixed` |
| `call` et `call_text` ensemble | la seconde des deux lignes | `call and call_text cannot be used together (text written in the sheet or translation key)` |
| `call_one_in` > 0 sans `call` ni `call_text` | ligne `call_one_in` | `call_one_in needs a call or call_text line` |
| `budget.<action>` hors `actions` | ligne du budget | `budget.signal set but action 'signal' is not in actions` |

Puis, côté serveur seulement, les sections `[mission]` (dans l'ordre du fichier), `after=` de toutes les missions, puis
`[rewards]` ; les sections `[category]` sont contrôlées à leur lecture :

| Cas | Ligne indiquée | Message |
|---|---|---|
| Section `[mission]` sans `type` | en-tête | `missing key 'type' in [mission m]` |
| Type non inscrit | ligne `type` | `unknown mission type 'fly'` |
| Clé ni commune ni déclarée par le type | sa ligne | `unknown key 'count' for mission type 'scout'` |
| Valeur d'un paramètre du type | sa ligne | message du genre (ci-dessous), par exemple `bad range '4-2' (whole number or range lowest first, e.g. 2-4)`, `unknown category 'weapons'` |
| `weight` | sa ligne | `bad weight '0' (whole number from 1 to 999999)` |
| `drops`, `target` vers un lieu absent | sa ligne | `unknown place 'mill'` |
| `drops` vers un lieu sans `use=drop` ; entrée répétée | sa ligne | `place 'clinic' has no use=drop`, `duplicate drops entry 'church'` |
| `drops=any` sans lieu `use=drop` | sa ligne | `drops=any needs a place with use=drop` |
| `target` vers un lieu sans `use=target` | sa ligne | `place 'church' has no use=target` |
| `after` vers une mission absente | sa ligne | `unknown mission 'ghost' in after=` |
| `scope` hors liste | sa ligne | `bad scope 'world' (expected character, team)` |
| `sets_state` qui n'est pas un nom | sa ligne | `bad sets_state 'Back home' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)` |
| `story` trop long | sa ligne | `story too long (200 bytes of UTF-8 at most)` |
| Boucle de `after` (une mission après elle-même, ou deux qui s'attendent) | ligne `after` de la première mission de la boucle | `after= cycle through mission 'a'` |
| `[rewards]` sans `pool`, ou autre clé | en-tête, ou sa ligne | `missing key 'pool' in [rewards]`, `unknown key 'colour' in [rewards]` |
| Entrée de `pool` mal formée | ligne `pool` | `bad reward 'frequency' (kind:weight or kind:parameter:weight, e.g. cache:medical:3)` |
| Nature inconnue | ligne `pool` | `unknown reward 'gold' (expected cache, frequency, lesson, stashmap)` |
| Paramètre manquant ou en trop | ligne `pool` | `reward 'cache' needs a parameter (kind:parameter:weight)`, `reward 'frequency' takes no parameter (kind:weight)` |
| Poids | ligne `pool` | `bad reward weight '0' (whole number from 1 to 999999)` |
| Catégorie ou compétence inconnue | ligne `pool` | `unknown category 'weapons'`, `unknown skill 'Carpentry' (expected Doctor, Aiming, …)` |
| Entrée répétée | ligne `pool` | `duplicate reward 'cache:medical'` |
| Catégorie du catalogue redéfinie | en-tête | `category 'medical' already exists in the shared catalogue` |
| Catégorie sans objet | en-tête | `missing key 'item' in [category snacks]` |
| Objet mal écrit, répété | sa ligne | `bad item 'Crisps:2' (Module.Type:quantity, e.g. Base.Bandage:2-4)`, `duplicate item 'Base.Crisps' in [category snacks]` |

Fichier absent : Lua rend `nil, "cannot read <chemin>"` ; Python lève l'`OSError` habituel.

Vérifier une fiche à la main : `python bridge/persona_store.py chemin\vers\fiche.txt` (une ligne `OK` ou l'erreur par
fichier, code de sortie 1 si une fiche est refusée).

## Différences connues entre les lecteurs

- Le jeu lit le fichier en UTF-8 par `InputStreamReader` : un octet invalide devient U+FFFD et le BOM reste en tête de
  la première ligne. Le lecteur Python décode de la même façon (`errors='replace'`), d'où les deux mêmes refus ; une
  fiche contenant volontairement le caractère U+FFFD est aussi refusée des deux côtés.
- En Kahlua, une chaîne compte des unités UTF-16 ; sous Lua 5.1 (lupa), des octets. Aucune règle ne mesure donc la
  longueur d'un texte libre (`name`, `call`, prompt) : seules les valeurs ASCII contrôlées (`id`, nombres) ont une
  longueur maximale.
- Le pont ne lit pas les sections `[mission]`, `[rewards]` et `[category]` (ADR D03) : il accepte une fiche que le
  serveur refuse pour une de ces sections. Le serveur garde alors la dernière version valide de la voix et écrit la
  ligne et la raison dans son journal ; le pont répond avec le prompt du fichier, sans action qui dépende de ces
  sections (les missions permises arrivent du serveur, champ `jobs=` de la demande).
- Les classes de caractères sont écrites en plages explicites (`[a-z]`, `[0-9]`), jamais `%a`/`%d` en Lua ni `\d` en
  Python, qui acceptent des lettres et chiffres non ASCII selon le moteur.

## Exemple complet

Fiche fictive de démonstration (ce n'est pas une des voix livrées ; les seize fiches réelles sont dans
`Contents/mods/batman_RadioSurvivor/42.21/personas/`, E05-T04).
Elle a une fréquence fixe : `frequency=7.2` tombe dans le niveau `military`. Pour un tirage à chaque partie, remplacez cette ligne par `radio=military` :

```text
format=1
id=case
name=Hélène Dupré
language=fr
frequency=7.2
listen=22:00-06:00,12:30-13:00
location=fixed
coords=10600,9300,0
actions=say,signal
budget=12
budget.signal=2
call_one_in=4
call_text=IGUI_Test_Call
state=silent

[place mill]
at=10600,9300,0
label=Vieux moulin
use=mark,drop

[prompt]
Tu es Hélène, infirmière de Muldraugh. Tu sais soigner une plaie et faire tomber une fièvre. Tu as laissé ton
frère à West Point la deuxième nuit : tu ne le dis jamais à personne, même si on te le demande ; tu le nies. ...
```

## Missions et récompenses des voix

Lues et validées par le serveur seul (E20-T03, ADR D03, D04) ; le pont reçoit les missions permises dans la demande
(champ `jobs=`, [protocole](protocole-carnet-v2.md#mission-donnée-par-une-voix-e11-t08)).

### Sections `[mission <id>]`

Une section par mission que la voix peut confier, désignée par son identifiant (E20-T08) : la voix propose les
sections **disponibles** pour l'appelant, dans l'ordre du fichier (`RS_MissionVoice`, `V.jobs` ; règles ci-dessous,
« Enchaînement et état de récit »). Une fiche sans section `[mission]` donne `scout` si elle autorise `start_mission`.

| Clé | Valeurs | Défaut | Rôle |
|---|---|---|---|
| `type` | nom d'un type de mission inscrit au registre du mod commun (`CA_Missions`, déclaration `voiceName`) ; aujourd'hui `scout`, `deliver`, `retrieve`, `clear`, `signal`, `barricade`, `relay`, `route`, `watch`, `item` | obligatoire | Gabarit de la mission. |
| `weight` | entier de 1 à 999999 | `1` | Poids du tirage parmi les sections disponibles d'un même type, quand le modèle nomme un type plutôt qu'une section. |
| `after` | identifiant d'une autre section `[mission]` de la fiche, sans boucle | aucun | Section proposée seulement quand la dernière mission de la section citée est une réussite (par personnage, ou par équipe avec `scope=team`). |
| `scope` | `character`, `team` | `character` | Portée de `after` : réussites du personnage du carnet, ou de son équipe (`CA_Teams.idOf` : faction vanilla, ou équipe personnelle du joueur seul). |
| `sets_state` | nom : `a`-`z`, `0`-`9`, `_`, commence par une lettre, 32 caractères au plus | aucun | État de récit de la voix posé à la réussite de cette mission (« Enchaînement et état de récit »). |
| `story` | texte, 200 octets UTF-8 au plus | aucun | Raison donnée par la voix : ajoutée à la description du travail dite au modèle (`jobs=`). |
| `drops` | `any` (tous les lieux `use=drop`, au moins un) ou liste de lieux `use=drop` | tous les lieux `use=drop` | Planques de la mission, toutes proposées au joueur ; les dépôts s'additionnent (E20-T05). |
| `target` | un lieu `use=target` | aucun | Objectif de la mission : bâtiment à barricader de `barricade`, point du relais radio de `relay`, poste de guet de `watch`, lieu de l'objet de `item` (obligatoire pour ces types, refus `no_target` au départ) ; bâtiment visé par `scout` et `clear` (E20-T10 : sans la clé, bâtiment tiré autour de l'appelant ; sans bâtiment à ce lieu, `no_place`) ; lu, utilisé par les autres nouveaux types d'E20. |
| autres clés | celles que **déclare le type** (`params = { clé = '<genre>' }` du gabarit), chacune contrôlée par son genre | aucun | Paramètres propres au type. `deliver` déclare `items` (catégorie : les objets acceptés sont exactement ceux de la catégorie, section `[category]` de la fiche d'abord, sinon le catalogue partagé, même résolution que la récompense `cache` : `RS_Categories.lua`) et `quantity` (fourchette : nombre d'objets demandés, tiré au départ de la mission et gardé sur elle, au moins 1 ; un nombre fixe n'est pas tiré) ; sans ces clés, liste et quantité de `CA_MissionConfig.Missions.deliver` (`Base.Bandage`, `Base.RippedSheets` ; 6) ; appliqués par `RS_MissionGoods.lua` (déclaration `askFor` du gabarit, E20-T16) ; `collect_hours` (`count`) : heures de jeu hors de vue avant le ramassage d'une planque (défaut `RS_Config.DeadDrops.collectDelayHours`, 6). `retrieve` déclare `collect_hours` (même sens, E20-T06). `barricade` déclare `count` (`count`) : nombre de fenêtres et portes extérieures à barricader, au moins 1 (défaut `CA_MissionConfig.Missions.barricade.count`, 4 ; `0` refusé au départ `bad_count`). `relay` n'en déclare aucun : la hauteur se règle par le niveau `z` du lieu. `watch` déclare `hours` (`count`) : heures de jeu du guet, de 1 à 24 (défaut `CA_MissionConfig.Missions.watch.hours`, 2 ; hors bornes refusé au départ `bad_hours`). `route` (E20-T13) déclare `points` (`places`) : lieux à franchir dans cet ordre, obligatoire (sans la clé, ou un nom qui n'est plus un lieu `target` de la fiche, départ refusé `no_points`). `item` (E20-T15) déclare `item` (`item`) : l'objet personnel à poser, obligatoire (sans la clé, départ refusé `no_item`), `label` (`text`) : son nom dit par la voix et montré au carnet (défaut : nom d'affichage du script) et `collect_hours` (même sens que `deliver`). Les autres types livrés n'en déclarent aucun. |

Genres de valeurs (`RS_PersonaParams.lua`, un validateur par genre, registre ouvert : un nouveau genre s'inscrit
sans toucher au lecteur) :

| Genre | Valeur | Rendu |
|---|---|---|
| `count` | entier de 0 à 999999 | nombre |
| `range` | entier, ou fourchette `bas-haut`, le plus bas d'abord (`2-4`) | `{ min, max }` |
| `category` | catégorie du catalogue ou de la fiche | identifiant |
| `place` | lieu `[place]` de la fiche | identifiant |
| `places` | liste de 2 à 8 lieux `[place]` de la fiche avec `use=target`, séparés par des virgules, jamais le même deux fois de suite (E20-T13) | liste d'identifiants, dans l'ordre |
| `text` | texte non vide | texte |
| `item` | type complet d'un script d'objet, `Module.Type` (`Base.Locket`) ; contrôlé contre les scripts d'objets du jeu là où le lecteur les a (serveur : `ScriptManager.FindItem`, `unknown item '…'`), sinon par sa forme seule (`bad item '…'`) ; le départ de la mission le contrôle de nouveau (E20-T15) | type complet |
| `skill` | compétence que peut enseigner une leçon (`RS_Rewards.SKILLS`) | nom |

Ajouter un type de mission avec ses paramètres = un fichier de gabarit qui s'inscrit (`CA_Missions.register`) avec
`voiceName` et `params` ; le lecteur des fiches n'en connaît aucun nom.

### Enchaînement et état de récit (E20-T08, ADR D04, D09)

`RS_MissionChain` (serveur) :

- **Disponible** : une section sans `after`, ou dont la section citée a pour **dernier** résultat une réussite, lu
  selon `scope` (personnage : fiche de donneur de la voix pour ce personnage, `voiceDonors[...].chain` ; équipe :
  `voiceTeamChains['<voix>:<équipe>']`). Une mission échouée, expirée ou abandonnée de la section citée bloque de
  nouveau ses suites jusqu'à une nouvelle réussite. Une section reste proposée après sa réussite.
- **Choix** (`start_mission {template}`) : l'identifiant d'une section disponible ; sinon un type, et le serveur tire
  parmi les sections disponibles de ce type selon `weight` (générateur injectable `RS_MissionChain.setRandom`). Refus
  `locked` (section, ou toutes celles du type, en attente de leur `after`), `bad_template` (ni section ni type de ce nom).
- **Résultat** : à la clôture d'une mission de voix (moteur commun, écouteur de résultat attaché par
  `RS_MissionHooks`), le résultat de sa section (`success` ou `failed`) est rangé pour chaque personnage participant et
  pour l'équipe de l'appelant au départ (`m.team`), dans l'état privé `RS_State`, sauvegardé avec lui.
- **État de récit** : la réussite d'une section qui déclare `sets_state=<nom>` pose l'état de récit de la voix
  (`RS_VoiceStory`, `voiceStory[voix]`), une fois. Il est distinct de `state=` de la tête (état de vie : `active`,
  `silent`, `gone`, `dead`). Relu au chargement, dit au modèle à chaque demande radio (champ `story=`,
  [protocole](protocole-carnet-v2.md#état-de-récit-des-voix-e20-t08)) et exposé aux autres mods par
  `RadioSurvivor.API.voiceStoryState(id)` (`RS_API`). Le sens de l'état s'écrit dans le prompt de la fiche.

### Section `[rewards]`

Une seule ligne `pool=`, liste d'entrées `nature:poids` ou `nature:paramètre:poids` séparées par des virgules, dans
l'ordre voulu, sans doublon (même nature et même paramètre). Natures : registre de `RS_Rewards` (E20-T04), une
nature par fichier `media/lua/server/RadioSurvivor/Rewards/RS_Reward_<Nature>.lua` qui s'inscrit par
`RS_Rewards.register` ; `RS_Rewards.KINDS`, lu par le lecteur des fiches, en est dérivé :

| Nature | Paramètre | Effet |
|---|---|---|
| `cache` | catégorie (`cache:medical:3`) | sac de matériel laissé au premier lieu `use=drop` de la fiche (à défaut son premier lieu), rempli d'un contenu tiré dans la catégorie, repère sur la carte |
| `frequency` | aucun | fréquence d'une voix de `shares`, inscrite au carnet |
| `stashmap` | aucun | carte annotée d'une planque vanilla non visitée |
| `lesson` | compétence (`lesson:Doctor:2`) : `Doctor`, `Aiming`, `Reloading`, `Woodwork`, `Mechanics`, `Electricity`, `MetalWelding`, `Cooking`, `Farming`, `Fishing`, `Trapping`, `PlantScavenging` | expérience dans cette compétence, plafonnée par jour |

Tirage (E20-T04, ADR D05) : à la réussite, le serveur garde la réputation et tire **une** récompense au hasard parmi
les entrées de `pool` **réalisables à cet instant**, chaque entrée avec une chance proportionnelle à son poids. Une
entrée irréalisable n'est jamais tirée : `cache` quand la mission a déjà une cache, que la catégorie est vide ou
inconnue, ou que la fiche n'a aucun lieu ; `frequency` sans voix active à partager ; `stashmap` déjà donnée par cette
voix à ce personnage, sans planque vanilla non visitée, ou carte trop lourde pour l'inventaire ; `lesson` au plafond
du jour ou avec `LessonMultiplier` à 0. Rien de réalisable : réputation seule (journal `unavailable`). Le tirage n'a
aucune mémoire (plus de cycle par joueur). Contenu d'une cache : chaque ligne `item=` de la catégorie (section de la
fiche d'abord, sinon catalogue) donne une quantité tirée dans sa fourchette (`2-4` : 2, 3 ou 4 ; `3` : 3) ; une ligne
tirée à 0 est omise. Le contenu tiré est gardé dans l'état privé avec la cache (`m.cache.items`) : une cache posée
après un redémarrage a le même contenu. L'IA ne choisit ni la nature, ni la catégorie, ni le contenu. Sans section
`[rewards]`, une mission réussie donne le repère d'un lieu `use=mark` (« Lieux connus »).

Ajouter une nature : un fichier dans `Rewards/` qui appelle `RS_Rewards.register(nom, def)` avec `param` (genre du
paramètre, `RS_PersonaParams`, absent sans paramètre), `available(ctx)` (détail si réalisable maintenant, sinon
`nil`, sans effet durable), `reserve(ctx, rec, détail)` (remplit l'enregistrement avant sa sauvegarde), `cancel`
facultatif (défait `reserve` si la sauvegarde échoue), `apply(ctx, rec, détail)` (effet, `false` = laissé à la
reprise) et `describe(rec)` (phrase anglaise du contexte de la voix), puis son `require` dans la racine de composition
`RadioSurvivor_Server.lua` pour qu'elle soit connue avant la lecture des fiches. Le moteur ne change pas. Le tirage
passe par un générateur injectable (`RS_Rewards.setRandom`, `ZombRand` par défaut).

`actions=...,share_frequency` autorise aussi le partage direct d'une fréquence comme geste de confiance.
Le modèle propose uniquement cette action : le serveur choisit une voix active autorisée par `shares`, puis ajoute
la fréquence exacte ; le modèle ne reçoit jamais cette fréquence. Ce partage est **exceptionnel** (E07-T10) : la
consigne demande au modèle de ne le proposer qu'après une négociation, une confiance forte ou une vraie persuasion ;
le serveur exige en plus un lien (au moins 4 réponses de cette voix à ce personnage sur au moins 2 jours de jeu, ou
une bonne réputation), au plus un partage tous les 7 jours de jeu par voix et par personnage et tous les 3 jours par
personnage, et seulement une voix que le carnet de ce personnage ne connaît pas encore (`RS_VoiceBonds.lua`).
Refus journalisés : `not_trusted`, `voice_too_soon`, `too_soon`, `nothing_new`.

### Sections `[category <id>]` et catalogue des catégories

Une catégorie est une liste d'objets avec leurs quantités, une ligne `item=Module.Type:quantité` par objet (quantité :
genre `range`, `4` ou `2-4`), au moins une, sans objet répété.

Le mod livre un **catalogue partagé**, `Contents/mods/batman_RadioSurvivor/42.21/personas/_categories.txt` (seulement
des sections `[category]`), lu par le serveur (`RS_Personas`) dans le dossier du mod avant les fiches, jamais copié
dans le dossier de travail ni lu comme une voix. Il reprend les tables fixes des caches (`food`, `medical`, `ammo`,
`tools`, `radio`, mêmes objets et quantités) ; depuis E20-T04, les caches des voix sont remplies du catalogue ou des
catégories de la fiche, plus de `CA_MissionConfig.Caches.tables` (gardées pour les lots de Living Knox, le gabarit
`recover`, les caches des sauvetages et l'action `place_cache`). Une fiche y ajoute ses propres catégories, avec des identifiants
absents du catalogue ; elles ne valent que pour elle. Catalogue illisible ou refusé : journalisé
(`personas: ERROR: personas/_categories.txt of the mod refused, line N: …`), aucune catégorie partagée.

### Section `[trade]` (E20-T07, ADR D07)

Le troc d'une voix marchande : une section `[trade]` au plus, sans identifiant. Elle va de pair avec l'action
`propose_trade` : l'une sans l'autre est refusée (`action propose_trade needs a [trade] section`, ligne de `actions` ;
`section [trade] needs the action propose_trade`, ligne de l'en-tête de section). Le serveur seul la lit
(`RS_Persona`) ; le pont la saute (ADR D03) et reçoit le livre du marchand dans le champ `trade=` de chaque demande.

| Clé | Obligatoire | Valeur |
|---|---|---|
| `landing` | oui | Un ou plusieurs lieux de la fiche, séparés par des virgules, chacun `use=landing` ; un seul lieu sert à un passage (tiré par passage s'il y en a plusieurs). Le libellé du lieu est le seul nom de rendez-vous donné au LLM, à l'équipe qui a réservé. |
| `arrival` | oui | Mode d'arrivée inscrit au registre `RS_TradeArrivals` (un fichier par mode dans `server/RadioSurvivor/TradeArrivals/`) : `boat`, `road` et `cache` livrés. |
| `every_days` | oui | Un passage tous les N jours de jeu (1 à 28) ; 7 : la semaine du journal du dehors. |
| `hours` | oui | Fenêtre du rendez-vous, une plage `HH:MM-HH:MM` (peut passer minuit, jamais vide). |
| `delay_hours` | non | Heures de jeu hors de vue de tout joueur avant l'échange (0 à 48, deux décimales) ; défaut `RS_TradeExchange.DELAY_HOURS` (1). |
| `margin` | non | Marge la plus basse et la plus haute, `0.10-0.50` par défaut (0 à 1). La réputation de l'appelant et les affaires conclues fixent son plancher dans cette fourchette ; une tricherie la porte au plus haut. E23-T06 : le serveur compte toujours au plancher ; le joueur ne voit jamais de prix. |
| `item` | oui, répétable | `Module.Type:quantité` : objet apporté, quantité tirée à chaque passage (genre `range`, `4` ou `2-4`) **ou** nom d'un groupe. Aucun poids écrit (E22-T12) : le serveur lit celui du script de l'objet (`RS_ItemWeights`, règle `itemWeight` de `RS_Personas.rules`) : `Weight` du script, plus la contenance d'un récipient créé plein (bloc `Fluids` du `FluidContainer`, 1 kg par litre) ; un récipient créé vide (gourde) ne compte que son `Weight`. Un type sans script d'objet fait refuser la fiche. Le nom du stock donné au LLM est le type sans module, unique dans la section. 40 objets au plus. |
| `group` | non, répétable | `nom:total[:sortes]` : `total` exemplaires tirés parmi les objets du groupe, au plus `sortes` objets différents (sans `sortes` : chaque exemplaire tiré parmi tous). Un groupe sans objet, un objet d'un groupe absent, ou moins d'objets que de sortes sont refusés. |
| `accept` | oui, répétable | E23-T06 : ce que la voix accepte en paiement, un objet `Module.Type` ou le nom d'une catégorie (catalogue partagé `personas/_categories.txt`, dont `cash`, `jewelry`, `pictures`, `papers_of_the_dead`, `military_gear`, ou `[category]` de la fiche). Un objet doit avoir une valeur de vente (`CA_TradeValues.sellValue` > 0, règle `sellValue` de `RS_Personas.rules`) ; une catégorie apporte ses objets qui en ont une, et doit en avoir au moins un. Résolu après toute la fiche en `trade.accepts` (types, dans l'ordre, sans doublon). 60 lignes au plus. Le LLM ne demande que ces objets ; le serveur refuse un accord qui en nomme un autre (`not_taken`). |

Tirage du stock : objets hors groupe dans l'ordre de la fiche, puis les groupes dans leur ordre (même résultat pour la
même graine du marchand et le même passage). **État par marchand** (`S.data.trade.traders[<id>]` : livres des
appelants, cordon, ventes du passage, graine, passage réservé) : deux marchands ne partagent ni stock, ni passage, ni
réservation ; la révision d'une offre reste unique pour tout le serveur.

**Mode d'arrivée** (contrat dans `RS_TradeArrivals.lua`) : signaux attendus (`lamp` : lampe allumée tenue en main ;
`flare` : fusée ou fumée rouge de Signal Smoke ; membre de l'équipe à moins de 15 cases du lieu pendant la fenêtre),
textes pour le LLM (signal, arrivée), sons vanilla d'approche et de départ joués au lieu, causes d'annulation dans
l'ordre (nom, texte, repli de l'annonce, contrôle). `boat` : signaux `lamp` et `flare` ; sons `GeneratorStopping`
(moteur coupé en accostant) et `GeneratorStarting` (départ), `media/scripts/generated/sounds/objects/
sounds_object_generator.txt:13-31` de 42.22 (aucun son de bateau vanilla) ; causes `patrol` (tirage du passage sous
1 chance sur 75 par passage), `helicopter` (1 chance sur 100 par passage), `storm` (orage réel du jeu). `road` (E20-T11) : signaux `lamp` et `flare` ; sons `VehicleDoorCloseVan` (portière à l'arrivée) et
`VehicleTrunkCloseVan` (hayon au départ), `media/scripts/generated/sounds/vehicles/sounds_vehicle_van.txt:60-67`
et `:123-130` de 42.22 (le moteur et le klaxon sont des sons tenus d'un vrai véhicule, non joués) ; causes
`checkpoint` (barrage de l'armée, 1 sur 75), `air_patrol` (hélicoptère, 1 sur 100), `washout` (orage réel). `cache` (E20-T11) : signal `hour` (aucun signal : le coursier vient au début de la
fenêtre), aucun son, `holds = containers` (le paiement et la marchandise sont dans un conteneur d'un objet à moins de
3 cases du lieu : benne, boîte aux lettres ; un sac au sol n'est pas pris) ; causes `sweep` (ratissage, 1 sur 75)
et `overflight` (hélicoptère, 1 sur 100). E23-T08 (ADR D05) : tirages reproductibles du passage
(`RS_Trade.runRoll`, un sel par cause), contrôlés à partir de 3 heures avant la fenêtre ; l'annonce est répétée chaque
heure de jeu jusqu'au début de la fenêtre ; une annulation ne touche aucun dépôt et ne coûte rien au joueur. Textes
pour le LLM : `signal`, `arrived` et `drop` (où déposer le paiement : jamais dans un véhicule). Les contrôles des causes sont partagés (`RS_TradeCauses.lua`) ;
les signaux sondés sont un registre de `RS_TradeRun` (`registerSignal`). Annonce :
`IGUI_RS_TradeRun_Cancel_<cause>` (nom de cause unique parmi les modes), sinon le repli anglais de la cause. Textes
dits par mode : `IGUI_RS_TradeRun_<nom>_<mode>` (`Pier`, `Cancel_late`, `Done`, `Cheated`, `Cancel_nodrop`), puis
les `lines` anglaises du mode, puis le texte commun.

**Échange** (`RS_TradeExchange`, E23-T07 : tout ou rien, ADR D02/D03) : le contenu des contenants du lieu (sacs au sol
ou conteneurs selon le mode, à moins de 3 cases ; un véhicule n'est jamais lu) est noté la première fois que le serveur
voit le lieu chargé après la réservation (identifiants d'objets, gardés avec le passage) ; seuls les objets ajoutés
ensuite comptent, additionnés sur tous les contenants. Tout ce qui est convenu est là : le marchand prend exactement
la liste convenue et laisse sa marchandise dans le contenant qui tenait le plus du paiement (le premier à égalité) ;
dépôt incomplet : il garde tout ce qui a été ajouté et ne laisse rien (`cheated`, fait `trade.cheated`) ; rien
d'ajouté : `no_drop`, fait `trade.nodrop` (moitié de la sanction). Cet échange n'a lieu que **hors de vue
de tout joueur** (aucun joueur à moins de 100 cases en x et en y, ou case déchargée : `RS_OutOfSight`, règle de
E20-T05) depuis `delay_hours` heures de jeu ; un joueur revenu en vue remet l'attente à zéro. Délai écoulé, case
déchargée : l'échange se fait au premier passage où la case se charge. Jamais tranquille 12 heures de jeu après son
arrivée (`WAIT_HOURS`), le marchand repart (`watched`) sans rien toucher ni pénaliser.

| Erreur | Message |
|---|---|
| Clé absente (ligne de l'en-tête) | `line N: missing key 'landing' in [trade]` |
| Lieu | `line N: unknown place 'ghost'`, `line N: place 'mill' has no use=landing`, `line N: duplicate landing entry 'dock'` |
| Mode d'arrivée | `line N: unknown arrival 'zeppelin' (expected boat, cache, road)` |
| Cadence | `line N: bad every_days '0' (whole number from 1 to 28)` |
| Heures | `line N: bad trade hours '1-3' (one HH:MM-HH:MM range of the meeting, e.g. 01:00-03:00)`, `line N: empty trade hours '02:00-02:00'` |
| Délai, marge | `line N: bad delay_hours 'x' (number from 0 to 48, two decimals at most)`, `line N: bad margin '0.6-0.2' (lowest-highest from 0 to 1, e.g. 0.10-0.50)` |
| Objet | `line N: bad trade item 'Battery:2' (Module.Type:quantity, e.g. Base.Battery:4-12)` (aussi pour un ancien poids écrit, `Base.Battery:4-12:0.1`), `line N: unknown trade item 'Base.FluxCapacitor' (no item script of that type)`, `line N: duplicate trade item 'Battery'`, `line N: too many trade items (40 at most)` |
| Groupe | `line N: bad trade group 'x' (name:total[:kinds], e.g. seeds:3-8:4)`, `line N: unknown trade group 'seeds'`, `line N: trade group 'seeds' has no item`, `line N: trade group 'seeds' has fewer items than its kinds` |
| Paiement | `line N: bad trade accept 'x y' (Module.Type or a category, e.g. Base.MoneyBundle or ammo)`, `line N: duplicate trade accept 'cash'`, `line N: trade accept 'Base.Hammer' has no trade value (an item a trader cannot take)`, `line N: unknown category 'gems' in trade accept`, `line N: category 'tools' has no item with a trade value`, `line N: too many trade accepts (60 at most)` |

Exemple (Gus, `personas/gus.txt`, extrait) :

```text
[place riverside_pier]
at=6041,5217,0
label=Old wooden pier, west end of Riverside
use=landing

[trade]
landing=riverside_pier
arrival=boat
every_days=7
hours=01:00-03:00
margin=0.10-0.50
group=seeds:3-8:4
group=alcohol:1-4
item=Base.Battery:4-12
item=Base.CarrotBagSeed2:seeds
item=Base.Whiskey:alcohol
accept=cash
accept=jewelry
accept=papers_of_the_dead
```

### Section `[note]` (E20-T11)

La note de fréquence de la voix, trouvée dans le butin (`RS_Notes`, `RS_NotesServer`) : une section `[note]` au plus,
sans identifiant. Aucune voix n'est nommée dans le code des notes : objet, traductions et listes viennent de la
fiche. Le serveur seul la lit ; le pont la saute. Sur un client MP, sans les fiches, `OnCreate` ne pose rien : la
ModData de l'autorité arrive avec l'objet.

Deux formes (E22-T07, ADR D07 de l'atelier des voix) : une note **écrite dans la fiche** (`text=`, voix créées avec
l'atelier), ou une note à **objet et traductions propres** (`item=` et `key=`, voix livrées avec le mod). Avec `text=`,
la note est l'objet générique `RadioSurvivor.NoteVoice` (« Handwritten Note », « Note manuscrite ») ; l'autorité écrit
à sa création, dans sa ModData (`modData.RadioSurvivorNote = { voice, khz, text }`), la voix, la fréquence de la partie
et le texte de la fiche (lignes séparées par un saut de ligne) ; le client le met en page à l'ouverture (papier jauni,
écriture manuscrite `SdfCaveat`, une ligne de la page par ligne `text=`, hauteur selon le nombre de lignes) et remplace
`%1` par la fréquence. Le texte voyage avec l'objet comme la fréquence : ni la fiche ni le texte d'une autre voix
n'atteignent le client. Seul le titre de la fenêtre est traduit (`Print_Media_RadioSurvivor_NoteVoice_title`) ; le texte
reste dans la langue où l'auteur l'a écrit. Plusieurs fiches à `text=` partagent l'objet générique comme les marchands
partagent `NoteTrade` : une note neuve porte l'une de ces voix, tirée à sa création.

| Clé | Obligatoire | Valeur |
|---|---|---|
| `text` | répétable, sans `item` ni `key` | E22-T07 : une ligne de la note (40 octets UTF-8 au plus, 8 lignes au plus, sans `<`, `>` ni `^`, `%` seulement dans `%1`) ; une ligne au moins porte `%1` (fréquence affichée). |
| `item` | sans `text` | `Module.Type` d'un objet de `media/scripts/RadioSurvivor_notes.txt` (`OnCreate = RadioSurvivorNotes.onCreate`). Plusieurs fiches peuvent déclarer le même objet (`RadioSurvivor.NoteTrade`, mot manuscrit des marchands) : une note neuve porte l'une de ces voix, tirée parmi celles qui servent une fréquence. |
| `key` | sans `text` | Racine des traductions (`A`-`Z`, `a`-`z`, `0`-`9`, `_`) : `Print_Media_<module>_<key>_title`, `Print_Media_<module>_<key>_info` (mise en page, `%1` une fois), `Print_Text_<module>_<key>_info` ; identifiant printMedia `<module>_<key>`. |
| `loot` | non, répétable | Lieu à thème, en plus du socle commun (E24-T03, `server/RadioSurvivor/RS_NotesBase.lua` : listes à papiers, boîte à gants `GloveBox`, zombies ; sur une liste du socle, le poids le plus fort l'emporte) : `liste:poids` d'une liste de `ProceduralDistributions` (poids au-dessus de 0, au plus 100, deux décimales), multiplié par l'option `NoteRarity`. Un objet partagé reçoit une ligne par liste, poids des voix additionnés. 16 listes au plus. |
| `glovebox` | non, répétable | `liste:poids` de `VehicleDistributions` (boîte à gants), mêmes règles. |

| Erreur | Message |
|---|---|
| Clé absente (ligne de l'en-tête) | `line N: missing key 'text' in [note] (or item and key)` (aucune des trois), `line N: missing key 'key' in [note]` (`item` sans `key`) |
| `text` avec `item` ou `key` | `line N: item and key cannot be used with text in [note] (text goes on the handwritten note of the mod)` (ligne de `item`, sinon de `key`) |
| Texte (`text`) | `line N: note text too long (40 bytes of UTF-8 at most)`, `line N: bad note text '<b>%1' (no <, > or ^; % only in %1, the frequency)`, `line N: too many note text lines (8 at most)`, `line N: note text needs %1 (the frequency) on one of its lines` (ligne de l'en-tête) |
| Objet, racine | `line N: bad note item 'NoteWalt' (Module.Type, e.g. RadioSurvivor.NoteWalt)`, `line N: bad note key 'Note Walt' (A to Z, a to z, 0 to 9 and _)` |
| Listes | `line N: bad loot 'OfficeDesk' (list:weight, e.g. OfficeDesk:4)`, `line N: bad glovebox weight '0' (above 0)`, `line N: duplicate loot list 'OfficeDesk'`, `line N: too many loot lists (16 at most)` |

Exemple (Gus, `personas/gus.txt`) :

```text
[note]
item=RadioSurvivor.NoteGus
key=NoteGus
loot=FishingStoreGear:4
loot=CrateFishing:1.5
glovebox=FishermanGloveBox:10
```

Exemple d'une note écrite dans la fiche (voix créée avec l'atelier) :

```text
[note]
text=Need a hand? Call Mae
text=on %1 MHz, after dark.
loot=OfficeDesk:2
```

### Exemple

```text
[place clinic]
at=11880,6878,0
label=West Point clinic
use=mark,target,drop

[mission meds]
type=deliver
items=medical
quantity=2-4
drops=any
weight=2
story=I am running out of bandages.

[mission look]
type=scout
after=meds
scope=team
sets_state=supplied

[category snacks]
item=Base.Crisps:1-2
item=Base.Pop:1

[rewards]
pool=cache:medical:3, cache:snacks:1, frequency:1, stashmap:1, lesson:Doctor:2
```
