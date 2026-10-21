# Chronique du serveur : journal des faits du jour (E14-T01)

Fichier : `media/lua/server/RadioSurvivor/RS_Facts.lua` (autorité seulement : serveur dédié ou solo). Bancs :
`tests/test_facts.py` (lupa) ; suite en jeu `rs.facts` (`dev/batman_RadioSurvivorTests/.../suites/RS_Facts.lua`).

Le journal rassemble les faits **confirmés par le serveur** que le bulletin du soir (E14-T02) racontera et dont le
mémorial (E14-T03) lira les morts. Il ne contient ni coordonnée, ni texte de conversation, ni secret.

## Sources

| Sorte | Origine | Champs |
|---|---|---|
| `death` | `OnCharacterDeath` d'un `IsoPlayer` (déclenché aussi sur le serveur dédié, contrairement à `OnPlayerDeath` : base `multiplayer.md`) ; zombies et corps de PNJ écartés | `name` (descripteur du personnage), `place` |
| `mission` | `RS_Missions.onFinished`, chaîné après l'écouteur des observations (`RS_ObservationTriggers`) : `success`, `failed`, `abandoned` ; les annulations (`cancelled_*`) ne sont pas des nouvelles | `template`, `result`, `requester` (nom de la fiche ou de la voix), `participants` (noms), `place` (corps du demandeur s'il est chargé) |
| `rescue` | réservé à E12-T04/T05 : `RS_Facts.record('rescue', { result, requester, participants, place })` | |
| `passage` | réservé au passeur (E13) : `RS_Facts.record('passage', { event, name, place })` | |
| `power_cut` | sondage `EveryHours` de `SandboxOptions.doesPowerGridExist()` (aucun événement Lua : base `power-and-lights.md`) : passage de présent à absent | — |
| `water_cut` | sondage `EveryHours` : `GameTime.getWorldAgeDaysSinceBegin() < SandboxOptions.getWaterShutModifier()` passe de vrai à faux (même test que `IsoObject.java:2544`, `ParameterWaterSupply.java:18`) | — |
| `weather` | sondage `EveryHours` (`RS_ObservationTriggers.weatherNow`) : début d'un orage, d'une tempête tropicale ou d'un blizzard | `weather` |
| `group_death` | événement public `OnLivingKnoxMemberDied` | `group` (nom lu par `LivingKnox.API.getGroup`), `role`, `cause`, `byPlayer`, `offscreen`, `place` (maille `area`) |
| `group_gone` | `OnLivingKnoxGroupGone` | `group`, `reason` |
| `group_new` | `OnLivingKnoxGroupCreated` | `group`, `typeKey`, `place` |

Non retenus : rencontres, attitudes et besoins de Living Knox (ils ne concernent qu'un joueur ou sont internes),
brouillard (dépend du réglage graphique). Une coupure déjà en place au premier sondage n'est pas un fait (aucun passage
vu). Rien n'est sondé sur un serveur vide en pause : l'heure n'avance pas, `EveryHours` ne part pas.

## Lieu

Arrondi à la **ville** par `RS_Rescue.town` (même règle que les indices de secours : centre des annotations de la
carte vanilla, rayon par ville) : `{ key = TownIn | TownOutskirts | TownCountry | TownFar, town = nom ou nil }`. Sans
la carte vanilla chargée, aucun lieu. `RS_Facts.placeText(place)` rend la phrase anglaise du prompt (« in Muldraugh »,
« on the outskirts of West Point »…). Le quartier n'est pas disponible (aucune table de quartiers ni zone de carte
lisible sans chargement) : reste de la tâche.

## Bornes et validation

- Liste fermée de sortes et de champs (`RS_Facts.KINDS`) ; un champ inconnu (par exemple `x`) refuse le fait.
- Texte : une ligne, sans balise, au plus 48 caractères ; une chaîne qui contient trois chiffres de suite est retirée
  (un nom ne peut pas porter de coordonnée) ; au plus 8 noms par liste ; lieu limité à `key` et `town` connus.
- Au plus 80 faits ; plein, le plus ancien fait **qui n'est pas une mort** part le premier (le mémorial garde ses
  noms). Plafond par sorte et par jour : 32 morts, 3 nouveaux groupes, 3 épisodes météo, 1 coupure de chaque, 16
  par défaut.
- Un fait par clé tant qu'il est gardé (mort d'un personnage, mission, membre de groupe…) : un événement répété ne
  donne qu'une entrée.

## Stockage

État privé du carnet (`RS_State`, fichier serveur `state-<monde>-<0|1>.txt`), champ `facts` : jamais de ModData
globale (base `multiplayer.md` : lisible par tout client). Le fait est écrit dès qu'il est consigné (`S.save()`).
Avant le chargement de l'état (`OnInitGlobalModData`), les faits attendent en mémoire et sont versés au premier accès.

## Lecture et purge (API du bulletin)

- `RS_Facts.list([since])` -> `{ day, next, facts }` : copies des faits de numéro `> since`, les plus anciens d'abord.
- `RS_Facts.purge(through)` : le bulletin (E14-T02) purge ce qu'il a lu (`list().next - 1`) **après** sa diffusion ;
  un fait consigné entre la lecture et la purge reste pour le bulletin suivant.
- **Sans bulletin** (tant qu'E14-T02 n'existe pas, ou bulletin manqué) : à chaque sondage horaire, les faits des jours
  antérieurs à la veille sont retirés (jour < aujourd'hui - 1). Un fait de fin de soirée, après le bulletin, atteint
  donc le bulletin du lendemain ; le journal ne dépasse jamais deux jours de jeu.

## Décision à confirmer

Le lieu est arrondi à la ville (et « campagne », « loin de toute ville ») faute de quartiers lisibles : la décision du
plan dit « quartier ou ville ». La durée de garde sans bulletin (veille comprise) est un choix de cette tâche.

## Bulletin du soir (E14-T02)

Code : `RS_Facts.bulletin` / `RS_Facts.airBulletin` (même fichier), API radio `RS_RadioServer` exposée par
`RadioSurvivor_Server.lua` (`frequency`, `submit`, `air`, `date`, `language`), pont `bridge/bulletin.py` et
`radio_bridge.evening_bulletin`. Contrat : `docs/specifications-techniques/protocole-carnet-v2.md`, « Bulletin du soir ». Bancs :
`tests/test_bulletin.py` ; suite en jeu `rs.bulletin` (même fichier de suites que `rs.facts`).

- **Heure** : option sandbox `RadioSurvivor.ChronicleHour` (entier 0 à 23, défaut 20 h, dans les heures d'écoute
  19 h - 22 h du Night Owl), lue à chaque sondage. Le jour des faits va de 7 h à 7 h (`Facts.now`) : le bulletin d'un
  jour est dû dès que son heure est atteinte dans ce jour (`bulletinDue`), et une heure avant 7 h appartient à la nuit
  du jour précédent. Un sondage manqué (serveur vide en pause, sommeil qui saute des heures) est rattrapé au sondage
  suivant du même jour.
- **Une fois par soirée** : `book.aired = jour` (état privé `RS_State`) après la diffusion. Un bulletin perdu par un
  redémarrage avant sa diffusion (demande en mémoire seulement) est redemandé au sondage suivant du même soir.
- **Faits envoyés** : au plus 12, les morts d'abord puis les plus anciens, en phrases anglaises construites depuis les
  champs fermés du journal (`factText` : heure ronde, nom, lieu arrondi, issue) ; jamais de coordonnée, de
  conversation, de fréquence ni de secret. Le prompt (fiche sans secrets + `bulletin.situation`) interdit tout ajout
  et demande de dire simplement « rien de confirmé » sans fait.
- **Diffusion** : sur la première fréquence servie du chroniqueur (`Facts.CHRONICLER = nightowl`, fiche active),
  encadrée de parasites, au plus 6 lignes du pont. Pont muet 60 s réelles, absent ou antérieur : bulletin de secours
  traduit (ouverture, au plus 5 faits, « et N autres nouvelles », clôture), dans la langue de l'autorité (clés
  `IGUI_RS_Bulletin_*`, rechargées une fois sur un serveur MP comme les appels fixes). Puis purge des faits lus ; un
  fait consigné pendant l'écriture du pont reste pour le bulletin suivant.
- **Sans bulletin possible** : mod désactivé, chroniqueur absent, silencieux ou parti (une ligne de journal par jour),
  serveur radio absent : rien n'est diffusé ni purgé ; l'expiration (veille comprise) borne le journal. Un chroniqueur
  qui quitte sa fréquence pendant l'écriture du pont : bulletin abandonné, redemandé au sondage suivant.
- **Mémorial** : voir la section E14-T03 ci-dessous (les morts ne sont plus des faits racontés par le pont ni par
  le secours).

### Décisions à confirmer (E14-T02)

- Heure par défaut 20 h ; le bulletin passe même hors des heures d'écoute de la fiche si l'admin choisit une autre heure.
- Langue du bulletin du pont : celle de l'option `CallLanguage` (appels spontanés) ; secours dans la langue du serveur.
- Chroniqueur fixé à la voix `nightowl` (pas d'option ni de champ de fiche) ; bulletin hors plafond horaire et budget.
- Délai du pont 60 s réelles (contre 30 s pour un appel spontané) ; 12 faits au plus pour le pont, 5 pour le secours.

## Mémorial (E14-T03)

Code : `RS_Facts.split`, `RS_Facts.deathsText`, `RS_Facts.memorialLines` et `RS_Facts.airBulletin` (même fichier).
Bancs : `tests/test_memorial.py` (et `tests/test_bulletin.py` adapté) ; suite en jeu `rs.facts` (test « memorial »).

- **Qui** : chaque fait `death` lu par le bulletin, c'est-à-dire chaque personnage joueur mort depuis le bulletin
  précédent (un fait par personnage et par jour grâce à la clé du journal : une mort signalée deux fois n'est lue
  qu'une fois). Les membres de groupes Living Knox (`group_death`) n'ont pas de nom dans le journal : ils restent des
  faits racontés par le pont ou le secours.
- **Sans LLM** : les noms ne sont jamais envoyés au pont. Il reçoit à leur place une phrase construite par le serveur
  (`deathsText` : « One survivor / N survivors died since the last bulletin. Their names are read at the very end,
  after your sign-off: do not name them… »), pour qu'il puisse en parler sans nommer personne ni inventer de lieu.
  Le secours ne raconte plus les morts (`IGUI_RS_Bulletin_Death` remplacée par `IGUI_RS_Bulletin_Memorial`) et ne dit
  « rien de confirmé » que s'il n'y a aucun fait, morts comprises.
- **Lecture** : une ligne d'ouverture traduite (`IGUI_RS_Bulletin_Memorial`, langue de l'autorité ; absente : les
  noms seuls), puis les noms dans l'ordre des morts, séparés par des virgules, sur des lignes d'au plus
  `Const.MAX_LINE_CHARS` (140) caractères. Avec le pont : après ses lignes (bornées à 6) ; en secours : avant la
  ligne de clôture. Le mémorial n'entre pas dans la borne des 6 lignes du pont (au plus 32 morts par jour, noms de
  48 caractères : une douzaine de lignes au pire).
- **Purge** : les morts lues partent avec les autres faits lus ; une mort consignée pendant l'écriture du pont reste
  pour le mémorial suivant. Un bulletin manqué (chroniqueur absent) laisse les morts de la veille au mémorial
  suivant tant que l'expiration ne les a pas retirées.

### Décisions à confirmer (E14-T03)

- Les noms ne sont dits qu'une fois, par le mémorial : le pont reçoit seulement le nombre des morts, le secours ne
  les raconte plus (le lieu de la mort n'est donc plus dit à l'antenne).
- Noms seuls (sans lieu ni heure), regroupés par lignes ; ligne d'ouverture : « One more thing. The names of those we
  lost today, so that somebody says them: » / « Une dernière chose. Les noms de ceux que nous avons perdus
  aujourd'hui, pour que quelqu'un les dise : ».
- Seuls les personnages joueurs sont nommés (les PNJ de Living Knox n'ont pas de nom dans le journal).
