*English: [[Creating radio voices|Creating-Radio-Voices]]*

# Créer une voix radio

Une **voix radio** est un personnage qui répond sur une fréquence : Walt, Darlene, Cody, les Whitaker, le Night Owl et
Gus en sont six. Chaque voix tient dans un fichier texte, une **fiche**. Sur cette page, vous allez copier une fiche,
en faire votre propre personnage, la tester et l'entendre en jeu. Aucun redémarrage, aucun fichier du mod à modifier.

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
- Le mod y installe ses six fiches au **premier chargement d'un monde**. Avant cela, le dossier n'existe pas.
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

- D'abord un en-tête de lignes `clé=valeur`, puis une ligne `[prompt]`, puis le texte libre du prompt.
- Les lignes vides et celles qui commencent par `#` sont ignorées dans l'en-tête.
- Les clés inconnues et les valeurs vides sont refusées : pour garder une valeur par défaut, retirez la ligne.
- `knows`, `ignores`, `secret` et `place` se répètent, une ligne par élément. Les autres clés apparaissent une fois.
- Le nom du fichier et l'`id` correspondent : `mae.txt` contient `id=mae`.

La référence complète du format est
[docs/persona-format.md](https://github.com/cyberbobjr/RadioSurvivor/blob/main/docs/persona-format.md).

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

**Bandes libres** : 25.0-39.8, 50.0-74.8, et 200.2 et au-delà (moins de radios atteignent les plus hautes). Mae
(exemple 1) utilise 40.0-49.8, Rick (exemple 2) 50.0-64.8.

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
| `place` | `place=rosewood 8159,11661,0 Rosewood, center of town` | Un lieu qu'elle connaît, pour `mark_map`, `reveal_area` et `start_mission`. |

- Une réponse qui cite un secret mot pour mot est remplacée par du grésillement (une paraphrase n'est pas détectée).
- `place=` s'écrit `<id> <x>,<y>,<z> <libellé>`, 12 lignes au plus. L'id utilise `a`-`z`, `0`-`9`, `_` ; le libellé
  (48 octets au plus) s'affiche tel quel sur la carte du joueur. L'IA ne voit que l'id et le libellé, jamais les
  coordonnées.

> **Important**
> Ne mettez jamais un vrai secret du serveur dans une fiche : mots de passe, codes, fréquences cachées, position d'une
> base de joueur. L'IA peut dire tout ce qui est dans son prompt.

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
- **Il faut dans la fiche :** au moins une ligne `place=` (les lieux que la voix connaît). La voix ne peut marquer
  **que** ces lieux, jamais une position inventée.
- **Conséquences :** le repère n'apparaît que chez le joueur qui parle, pas chez les autres.
- **Limites :** 30 secondes réelles entre deux repères de la voix ; plafond par jour de jeu avec `budget.mark_map`.

#### Vous révéler un quartier — `reveal_area`

- **En jeu :** la voix décrit un quartier qu'elle connaît et **la zone se dévoile sur votre carte** (comme si vous
  aviez trouvé une carte locale).
- **Il faut dans la fiche :** au moins une ligne `place=` ; la zone révélée est centrée sur l'un de ces lieux.
- **Conséquences :** seulement chez le joueur qui parle.
- **Limites :** un carré de 160 cases de côté au plus ; 60 secondes réelles entre deux révélations ; plafond par jour
  avec `budget.reveal_area`.

#### Vous confier une mission — `start_mission`

- **En jeu :** la voix vous demande d'aller **reconnaître un bâtiment** près de vous. La mission apparaît dans
  l'onglet **Missions** du carnet, avec un cercle sur la carte. Quand vous y êtes allé, **rappelez la voix sur sa
  fréquence et racontez-lui** ce que vous avez vu : la mission est alors réussie.
- **Il faut :** que le joueur ait le carnet. Le bâtiment est choisi par le serveur, jamais par l'IA.
- **Récompense :** votre réputation monte ; si la voix a des lignes `place=`, elle vous marque en plus sur la carte le
  premier de ses lieux qu'elle ne vous a pas encore donné.
- **Limites :** une mission en cours à la fois par joueur et par voix ; 30 minutes réelles entre deux missions pour un
  même joueur ; plafond par jour avec `budget.start_mission`.
- Le compte rendu à la radio fait partie de cette action : rien d'autre à ajouter.

#### Actions à ne pas ajouter

| Mot-clé | Pourquoi |
|---|---|
| `propose_trade` | Le troc du passeur Gus : il vend le stock de **son** bateau et fixe un rendez-vous à **son** ponton. Une autre voix vendrait le bateau de Gus. |
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
- Une nouvelle voix n'a pas de clé propre dans le mod : donnez-lui quand même un nom nouveau
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

</details>

## Exemple 2 : Rick Grimes, toutes les actions

*Exemple de fan, personnage appartenant à ses ayants droit.*
Un ancien shérif adjoint qui a perdu sa femme et son fils dans l'évacuation et traverse Knox County pour les
retrouver, méfiant mais juste. Plage 50.0-64.8 MHz (talkies 2 à 5, radios HAM, poste militaire) ; toutes les actions
qui ont un effet, sauf `propose_trade`, qui appartient au passage de Gus.

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
place=west_point 11654,6864,0 West Point, center of town
place=muldraugh_pd 10644,10405,0 Muldraugh, police station
place=muldraugh 10754,9926,0 Muldraugh, center of town
place=march_ridge 10130,12801,0 March Ridge
actions=say,remember,persona_state,mark_map,reveal_area,start_mission
budget=20
budget.remember=10
budget.persona_state=6
budget.mark_map=4
budget.reveal_area=2
budget.start_mission=2
call_one_in=6
call_text=IGUI_RadioSurvivor_Call_Rick

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

- Les lignes `place=` servent à trois actions : `mark_map` et `reveal_area` les désignent, et `start_mission` donne en
  récompense la première pas encore donnée (ici West Point).
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
| `unknown action 'fly'` | Voir [Actions](#actions). |
| `budget.mark_map set but action 'mark_map' is not in actions` | Ajouter l'action ou retirer le budget. |
| `call_one_in needs a call_text line` | Ajouter `call_text`, ou `call_one_in=0`. |
| `bad place 'mill 10600,9300,0' (id x,y,z label, …)` | Le libellé manque. |
| `place label of 'mill' too long (48 bytes of UTF-8 at most)` | Raccourcir le libellé. |
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

Voir aussi : [[Le pont sur un serveur dédié|Bridge-on-a-Dedicated-Server-FR]], [[Dépannage|Troubleshooting-FR]],
[[FAQ|FAQ-FR]].
