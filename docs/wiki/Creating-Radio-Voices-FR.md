*English: [[Creating radio voices|Creating-Radio-Voices]]*

# Créer une voix radio

Chaque voix radio (Walt, Darlene, Cody, les Whitaker, le Night Owl, Gus) est une **fiche** en texte brut. En tant
qu'admin du serveur, ou en partie solo, vous pouvez modifier une fiche pour changer une voix, ou en ajouter une pour
créer une nouvelle voix. Aucun redémarrage n'est nécessaire et aucun fichier du mod n'est à modifier.

Cette page est le guide pratique. La référence complète du format est
[docs/persona-format.md](https://github.com/cyberbobjr/RadioSurvivor/blob/main/docs/persona-format.md).

## Où sont les fiches

- Un fichier par voix : `<dossier d'échange>/personas/<id>.txt`.
  - Partie solo et partie hébergée : `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor\personas`.
  - Serveur dédié : `<dossier Zomboid du serveur>/Lua/batman_RadioSurvivor/personas` (avec `-cachedir=`,
    `<cachedir>/Lua/...`).
- Le mod y installe ses six fiches au **premier chargement d'un monde**. Avant cela, le dossier n'existe pas.
- Deux programmes lisent ce dossier, sur la machine du serveur :
  - **le serveur** (ou votre partie en solo) : fréquences, horaires, état, budgets, actions permises ;
  - **le pont** : le caractère, ce que sait la voix, et le prompt envoyé à l'IA.
- **Relecture à chaud** : le serveur relit le dossier toutes les **30 secondes réelles** (même sur un serveur vide en
  pause) et à chaque chargement du monde ; le pont relit une fiche à la demande suivante après sa modification.
  Enregistrez, attendez 30 s, appelez.
- **Vos modifications sont gardées** : le serveur retient une empreinte de chaque fiche qu'il a installée
  (`batman_RadioSurvivor/personas-fingerprints.txt`, à côté du dossier `personas`). Une fiche livrée que vous avez
  modifiée n'est jamais écrasée par une mise à jour du mod ; le journal indique
  `WARNING: voice 'walt' modified by the admin, delivered version not applied` à chaque chargement du monde. Pour
  revenir à la version livrée, supprimez le fichier : il est recopié au chargement suivant. Une fiche d'un nom nouveau
  n'est jamais touchée.

## Le format en bref

- UTF-8 **sans BOM** (Bloc-notes : *Enregistrer sous*, codage *UTF-8*, pas *UTF-8 avec BOM*).
- D'abord un en-tête de lignes `clé=valeur`, puis une ligne `[prompt]`, puis le texte libre du prompt.
- Dans l'en-tête, les lignes vides et celles qui commencent par `#` sont ignorées. Une clé inconnue ou une valeur vide
  est refusée : pour garder la valeur par défaut, retirez la ligne.
- `knows`, `ignores`, `secret` et `place` se répètent, une ligne par élément. Toute autre clé n'apparaît qu'une fois.
- Le nom du fichier et l'`id` doivent correspondre : `mae.txt` contient `id=mae`.

## Pas à pas

### 1. Copier une fiche

Copiez une fiche existante proche de ce que vous voulez (`walt.txt` est la plus simple) sous un nouveau nom : lettres
minuscules, chiffres et `_`, commençant par une lettre, 32 caractères au plus. Exemple : `mae.txt`.

### 2. Identité

```text
format=1
id=mae
name=Mae Tolliver
language=en
```

- `format=1` ne change pas.
- `id` = nom du fichier sans `.txt`.
- `name` : nom du personnage (pour le prompt et pour vous).
- `language` : deux lettres minuscules, `en` par défaut. Les appels spontanés sont écrits dans la langue du serveur ;
  répondre dans la langue de l'appelant est une consigne à écrire dans le prompt.

### 3. Fréquences

Choisissez **une** des deux formes :

- `frequency_range=40.0-49.8` : le serveur tire **une fréquence par plage** à chaque nouvelle partie et la garde toute
  la partie. Plusieurs plages sont séparées par des virgules (`88.0-107.8, 109.0-114.8`). Recommandé : les joueurs ne
  retrouvent pas la fréquence d'une partie à l'autre.
- `frequencies=44.6` : fréquences fixes, les mêmes dans toutes les parties.

Règles : MHz avec une décimale, de 1.0 à 999.8, au **pas de 0,2 MHz** des radios (`44.6` convient, `44.5` est
refusé). Une plage commence par sa fréquence la plus basse, et les plages d'une même fiche ne se touchent pas.

La plage décide qui peut parler à la voix (bornes de réglage des radios en 42.21) :

| Bande (MHz) | Radios qui peuvent y parler |
|---|---|
| 0,2-1000 | talkie-walkie 5, poste militaire, radio HAM haut de gamme |
| 10-500 | talkie-walkie 4, radios HAM ordinaires |
| 25-300 | talkie-walkie 3 |
| 50-200 | talkie-walkie 2 |
| 75-150 | talkie-walkie 1, talkie-walkie bricolé |
| 88-108 | radios FM et autoradios **en écoute seulement** |

Évitez ce qui est déjà pris :

| Utilisé par | Plage (MHz) |
|---|---|
| Cody | 10.0-24.8 |
| Jolene Whitaker | 75.0-87.8 |
| Night Owl | 88.0-107.8 et 109.0-114.8 |
| Darlene | 115.0-129.8 |
| Walt | 130.0-149.8 |
| Gus | 150.2-199.8 |
| Stations FM vanilla et alerte d'urgence | 88-108 |
| Opération Artemis (par défaut) | 108.0 |
| Military Drop | 120-170 (diffusions), 10-25 (station de chiffres) |

Restent libres notamment 25.0-74.8 et au-delà de 200.2 (moins de radios atteignent les hautes fréquences). En cas de
conflit :

- une fréquence tirée n'est jamais prise sur une chaîne du jeu ou d'un mod, et reste à **1,0 MHz** au moins de toute
  autre voix : des plages qui se recoupent fonctionnent, elles se partagent seulement les fréquences libres ;
- une fréquence fixe demandée par deux fiches reste à la voix chargée la première (ordre alphabétique au premier
  chargement) ; l'autre perd seulement cette fréquence
  (`WARNING: frequency … of voice '…' refused, already used by voice '…'`) ;
- une fréquence fixe déjà prise par une chaîne du jeu ou d'un autre mod est refusée et réessayée à chaque relecture
  (`WARNING: frequency … of voice '…' already used by another radio channel (game or other mod)`) ;
- une plage sans fréquence libre n'est pas servie
  (`ERROR: voice '…': no free frequency left in …; widen the range in its sheet`).

### 4. Radio et heures d'écoute

```text
radio=any
listen=05:00-09:00,20:00-23:00
```

- `radio=any` (défaut) : toute radio émettrice ; `radio=high_tier` : postes haut de gamme seulement (talkie 5, poste
  militaire, HAM haut de gamme). Avec un poste ordinaire, la voix se tait.
- `listen=always` (défaut), ou plages d'heure du jeu `HH:MM-HH:MM` séparées par des virgules. Minute de début incluse,
  minute de fin exclue ; `22:00-06:00` passe minuit. Hors de ses heures, la voix se tait.

### 5. Lieu

`location=none` (défaut, hors carte) convient à une nouvelle voix. `location=fixed` avec `coords=x,y,z` la place sur
la carte ; `location=rescue` est réservé au secours des Whitaker.

### 6. État

`state=active` (défaut) répond. `state=silent` écoute sans jamais répondre (sa fréquence reste réservée) : une pause.
`state=gone` (partie du réseau) et `state=dead` (morte dans l'histoire) retirent sa chaîne et libèrent sa fréquence.

### 7. Ce que la voix sait, ignore et cache

```text
knows=The roads around Rosewood: the farms, the creeks and which bridges were still standing a week ago.
ignores=What the army or the government is planning.
secret=Her son drove to Louisville on the first night and she has not heard from him since.
```

- `knows` : faits que la voix peut utiliser.
- `ignores` : ce qu'elle doit dire ne pas savoir, au lieu de l'inventer.
- `secret` : un **trait du personnage** qu'elle ne révélera pas. Une réponse qui cite un secret mot pour mot est
  remplacée par des parasites (une paraphrase n'est pas détectée).
- Ne mettez jamais un vrai secret du serveur dans une fiche : mots de passe, codes, fréquences cachées, position d'une
  base de joueur. L'IA peut dire tout ce qui est dans son prompt.

### 8. Lieux connus (pour `mark_map` et `reveal_area`)

```text
place=rosewood 8159,11661,0 Rosewood, center of town
```

`<id> <x>,<y>,<z> <libellé>`, 12 lignes au plus. L'id utilise `a`-`z`, `0`-`9`, `_` ; le libellé (48 octets au plus)
s'affiche tel quel sur la carte du joueur. L'IA ne voit que l'id et le libellé, jamais les coordonnées.

### 9. Actions permises

`actions=` liste ce que la voix peut faire en plus de parler. Défaut : `say` seule. Le serveur contrôle chaque action
(catalogue, fiche, budget du jour, délai) et n'applique que celles qui ont un effet :

| Action | Effet | Limites |
|---|---|---|
| `say` | Parle à la radio. | Toujours permise. |
| `remember` | Retient un fait court sur l'appelant et s'en souvient aux appels suivants. | 64 caractères, 5 faits par appelant et par personnage, 50 appelants par voix. Aucun effet de jeu. |
| `persona_state` | Change son propre `morale` et ses `supplies` (0 à 10, départ 5) et le lieu où elle dit être (`place`, 40 caractères). | ±2 au plus par appel ; récit seulement, aucun effet de jeu. |
| `mark_map` | Marque une de ses lignes `place=` sur la carte du seul appelant. | 30 secondes réelles entre deux repères de la voix. Pas proposée sans ligne `place=`. |
| `reveal_area` | Révèle sur la carte de l'appelant le quartier autour d'un de ses lieux. | Carré de 160 cases au plus, 60 secondes réelles entre deux révélations. Pas proposée sans ligne `place=`. |
| `start_mission` | Confie à l'appelant une mission **reconnaître** (bâtiment choisi par le serveur près de lui), avec compte rendu à la radio. | Carnet requis. Une mission ouverte par appelant et par voix ; 60 s entre deux missions de la voix, 30 min après la précédente de l'appelant. Récompense : réputation, puis le premier `place=` pas encore donné. |
| `propose_trade` | Offre de troc du passeur de l'Ohio, contrôlée d'après son livre. | Conçue pour Gus et son passage : laissez-la-lui. |

`report_mission` accompagne `start_mission` (inutile de la lister). `place_cache` n'est pas encore proposée à l'IA ;
`signal` et `place_scene` n'ont pas encore d'effet (refusées `not_available`). Une action inconnue fait refuser toute
la fiche.

### 10. Budgets

```text
budget=20
budget.mark_map=4
```

- `budget=N` : au plus N demandes acceptées par heure réelle pour cette voix, en plus de l'option sandbox globale
  `MaxPerHour`. `0` (défaut) = plafond global seul. Au-delà, la voix se tait.
- `budget.<action>=N` : au plus N utilisations de cette action par **jour de jeu** (`0` = pas de plafond). L'action doit
  figurer dans `actions`.

### 11. Appels spontanés

```text
call_one_in=5
call_text=IGUI_RadioSurvivor_Call_Mae
```

- `call_one_in=N` : à chaque heure de jeu, pendant ses heures d'écoute et quand personne ne lui parle, une voix active a
  une chance sur N de lancer un appel général. `0` (défaut) = jamais. Une seule voix appelle par heure au plus ; chaque
  appel coûte une demande de `MaxPerHour` (et de `budget`). L'option sandbox **Appels spontanés** les coupe tous.
- `call_text` : obligatoire avec `call_one_in` > 0. C'est une **clé de traduction** du mod, utilisée seulement quand le
  pont n'écrit pas l'appel (pont arrêté, réponse vide, rien après 30 s). Une nouvelle voix n'a pas de clé à elle dans le
  mod : donnez-lui quand même un nom nouveau. Pont absent, son appel est sauté et le journal l'indique une fois :
  `call of voice 'mae' skipped: no translation for call_text 'IGUI_RadioSurvivor_Call_Mae'`. Ne **reprenez pas** la
  clé d'une autre voix : le texte de Walt dit « Ici Walt ».

### 12. Le prompt

Tout ce qui suit la ligne `[prompt]` part tel quel vers l'IA. Le pont y ajoute ensuite, s'il y en a, vos lignes
`knows`, `ignores` et `secret`, puis la situation de l'appel (date, appelant, radio). Conseils d'écriture :

- À la deuxième personne, en anglais (les consignes sont mieux suivies en anglais, quelle que soit la langue des
  joueurs) : « You are Mae Tolliver, 67, ... ».
- Le décor : comté de Knox, Kentucky, juillet 1993, l'événement de Knox, la zone d'exclusion. Ni téléphone portable,
  ni internet.
- Qui est le personnage, pourquoi il est à la radio, son ton, un exemple de phrase dans sa voix.
- Plusieurs appelants partagent la fréquence : précisez que chaque message commence par une étiquette comme
  `[Caller 2]` que la voix ne doit jamais écrire elle-même.
- Règles : rester dans le personnage, ne jamais parler d'IA ni de jeu, ne jamais inventer de faits sur les environs de
  l'appelant, ne jamais promettre de secours, ne jamais inviter quelqu'un à sa cachette.
- Longueur radio : le pont garde **8 lignes de 100 caractères** au plus. Demandez « 1 à 4 phrases courtes, texte parlé
  simple, sans listes, sans markdown, sans émojis », terminées par « Over. ».
- Langue : « Answer in the same language the caller uses. »
- Aucun secret du serveur dans le prompt (étape 7).

## Exemple complet : Mae Tolliver

Une institutrice retraitée, radioamatrice, qui anime le réseau du comté depuis une ferme près de Rosewood. Plage
40.0-49.8 MHz : talkies 3 à 5, radios HAM et poste militaire, loin des voix livrées. À enregistrer sous
`personas/mae.txt` (UTF-8 sans BOM) :

```text
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
place=rosewood 8159,11661,0 Rosewood, center of town
place=fallas_lake 7253,8279,0 Fallas Lake
actions=say,remember,persona_state,mark_map
budget=20
budget.mark_map=4
call_one_in=5
call_text=IGUI_RadioSurvivor_Call_Mae
state=active

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

## Tester sa voix

### Sans le jeu

Depuis le dossier du pont :

```powershell
python persona_store.py "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas\mae.txt"
```

```text
...\personas\mae.txt: OK (mae, 40.0-49.8 MHz, active)
```

Puis un échange d'essai. `--offline` vérifie la fiche sans appeler l'IA (réponse en écho) ; sans cette option, l'IA
répond pour de vrai avec les réglages de votre `.env` :

```powershell
python radio_bridge.py --test "Allô ? Il y a quelqu'un ?" --voice mae --personas "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas" --offline
```

```text
Mae, hors ligne. Je reçois Allô ? Il y a quelqu'un ?. À vous.
```

(L'écho hors ligne prouve seulement que la fiche a été lue.) Une fiche refusée affiche
`voice sheet …\mae.txt refused, line N: <raison>`, puis `--test: no valid sheet for voice 'mae' in …`. Avec l'IA, la
réponse s'affiche, précédée de lignes `action: {...}` quand la voix propose une action.

### En jeu

1. Enregistrez la fiche et attendez 30 s (ou chargez le monde). Le journal (`console.txt` en solo, journal du serveur
   sur un serveur dédié) indique :

   ```text
   [RadioSurvivor] personas: voice 'mae' loaded: state active, frequency ranges 40.0-49.8
   [RadioSurvivor] personas: voice 'mae' drew 44.6 MHz in 40.0-49.8 (no frequency remembered for this range)
   ```

   (`new game` entre parenthèses quand la fiche existait avant un nouveau monde.) La fréquence est tirée une fois par
   partie. Un admin la lit aussi en jeu : panneau de debug, bouton **Radio Survivor - Fréquences**.
2. Réglez une radio qui atteint la bande (ici un talkie 3 ou mieux), allumez-la, parlez dans la section **Émettre**
   pendant les heures d'écoute. Rappel : hors de ses heures, avec la mauvaise radio ou au-delà de son budget, la voix
   se tait ; elle n'est pas en panne.

**Notes de fréquences** : les notes trouvées dans le butin n'existent que pour les voix livrées (Walt, Darlene, Cody,
Gus, Night Owl). Une nouvelle voix n'en a pas : donnez sa fréquence à vos joueurs, écrivez-la sur une carte, ou
laissez-les fouiller la bande.

### Erreurs courantes

Une fiche refusée est journalisée une fois par contenu :
`[RadioSurvivor] personas: ERROR: batman_RadioSurvivor/personas/mae.txt refused, line N: <raison>`. La dernière
version valide de la voix reste en service jusqu'à la correction. La lecture s'arrête à la première erreur.

| Message | Correction |
|---|---|
| `file starts with a byte order mark (save it as UTF-8 without BOM)` | Réenregistrer en UTF-8 sans BOM. |
| `invalid UTF-8 (save the file as UTF-8)` | Fichier enregistré dans un autre codage (ANSI) : enregistrer en UTF-8. |
| `expected key=value or [prompt]` | Ligne d'en-tête sans `=`, ou ligne `[prompt]` absente ou mal écrite. |
| `unknown key 'colour'` / `bad key 'Radio'` | Faute de frappe ; les clés sont en minuscules. |
| `duplicate key 'name' (first set on line 3)` | Garder une ligne (seules `knows`, `ignores`, `secret`, `place` se répètent). |
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
| `unknown action 'fly'` | Voir la liste de l'étape 9. |
| `budget.mark_map set but action 'mark_map' is not in actions` | Ajouter l'action ou retirer le budget. |
| `call_one_in needs a call_text line` | Ajouter `call_text`, ou `call_one_in=0`. |
| `bad place 'mill 10600,9300,0' (id x,y,z label, …)` | Le libellé manque. |
| `place label of 'mill' too long (48 bytes of UTF-8 at most)` | Raccourcir le libellé. |
| `missing [prompt] line before the prompt text` / `empty prompt text after [prompt]` | Ajouter la ligne, puis le texte. |

## Retirer une voix

- Pause : `state=silent` (la fréquence reste réservée).
- Hors antenne : `state=gone` ou `state=dead` (fréquence libérée ; la fréquence tirée est retenue et revient avec la
  voix si elle est encore libre).
- Votre propre voix : supprimez son fichier.
- Une voix **livrée** : ne supprimez pas le fichier, il serait recopié au chargement suivant. Mettez `state=gone`, ou
  videz le fichier (0 octet) : un fichier vide retire la voix et n'est pas recopié.

## Multijoueur

- Les fiches se modifient **sur la machine du serveur**, dans le dossier d'échange du serveur. Le pont, qui tourne sur
  la même machine, lit le même dossier.
- Aucune fiche, aucun prompt ni aucune fréquence tirée n'est envoyé aux joueurs : leur jeu ne sait même pas quelles
  fréquences ont une voix. Seul ce que dit la voix passe à l'antenne.
- Le journal du serveur cite les fréquences tirées : réservez-le aux admins.

Voir aussi : [[Le pont sur un serveur dédié|Bridge-on-a-Dedicated-Server-FR]], [[Dépannage|Troubleshooting-FR]],
[[FAQ|FAQ-FR]].
