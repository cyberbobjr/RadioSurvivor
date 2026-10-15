# Contrat RadioSurvivor Lua ↔ Python v2

Cible 42.21.0. Implémentation : `RS_Codec.lua`, `RS_Transport.lua`, `RS_Carnet_Server.lua`,
`bridge/npc_protocol.py`, `bridge/radio_bridge.py`. Le bridge unique garde le verrou `bridge.lock`,
sa configuration et le transport par fichiers dans `<cachedir>/Lua/batman_RadioSurvivor`.
Python ne modifie aucun inventaire, état du moteur de PNJ, accord ou score de réputation.

## Enveloppe et compatibilité

`requests.txt` est un fichier UTF-8 de champs **clé=valeur**, jamais du JSON. Exemple structurel :

```text
protocol=2
session=Multiplayer_nom-monde
generation=17
req=identifiant-radio-historique
sent=1790000000000
caller=appelant-historique
voice=walt
name=Nom
date=Date
days=1
radio=Radio
text=Phrase
req=identifiant-pnj
kind=npc_talk
payload=...hexadecimal...
commit=17
end
```

`session` conserve la séparation historique de Walt. Ses demandes sans `kind` et ses réponses
`resp=…`, `line=…`, `end` restent acceptées.

**Voix radio (E05-T03).** Une demande radio (sans `kind`) porte `voice=<id>` : l'identifiant de la fiche de voix
(`docs/persona-format.md`) que le serveur a choisie d'après la fréquence de la radio de l'appelant. Le serveur décide
seul : voix qui tient la fréquence, état `active`, heures d'écoute, radio exigée, plafond global et budget de la
voix ; une demande refusée ou tue n'atteint jamais le pont. Depuis E05-T08, toute phrase dite dans une radio
émettrice arrive au serveur avec la fréquence de la radio (commande client `talk` : `text`, `itemId`, `channel`) ;
une phrase sur une fréquence sans voix ne coûte ni demande au pont ni place de plafond. Les clients ne reçoivent
jamais les fréquences des voix (commande `frequencies` retirée) ; le pont ne les reçoit pas non plus (`voice=<id>`
seulement). Le pont lit la même fiche dans `<dossier
d'échange>/personas/<id>.txt` (mêmes règles, `persona_store.py`) et en construit le prompt : texte libre, puis
`knows`, `ignores` et `secret` (ces derniers avec la consigne de ne jamais les révéler) ; une réponse qui cite un
secret mot pour mot est remplacée par des parasites et n'entre pas en mémoire. Rien de la fiche ne repart vers le
serveur, sinon ce que la voix dit. Compatibilité : `voice` absent = `walt` (Lua antérieur) ; un Python antérieur
ignore `voice` et répond en Walt. Un `voice` qui n'est pas un identifiant de fiche, ou une voix sans fiche valide côté
pont (Walt compris : le prompt de secours `bridge/persona.txt` est retiré depuis E05-T10, le serveur installant
toujours les fiches livrées), reçoit des parasites (`<fzzt>`).
Un tour à la fois par voix et par partie ; deux voix répondent en parallèle.

**Appareil de l'appelant (E06-T03).** La commande client `talk` désigne l'appareil d'où part la phrase :

| `source` | Champs | Contrôles du serveur |
|---|---|---|
| absent ou `item` | `itemId` | radio d'inventaire émettrice en main ou sur le dos (`itemId` absent : n'importe laquelle) ; allumage et micro jugés par le client, fréquence `channel` donnée par le client |
| `world` | `x`, `y`, `z`, `index` (case et index de l'objet dans la case, la clé du paquet vanilla `RadioDeviceDataState`) | `IsoWaveSignal` sur la case (index périmé : la seule radio posée de la case), émettrice, joueur au même étage et à distance entière < `getMicRange()` de l'appareil (5 par défaut, règle de `ZomboidRadio`), allumée d'après le serveur ; fréquence = canal connu du serveur |
| `vehicle` | `vehicleId` (`BaseVehicle:getId()`), `part` (`VehiclePart:getId()`, `Radio`) | joueur assis dans ce véhicule, à n'importe quelle place (`getSeat` ≥ 0) ; pièce émettrice (gabarit `Radio_HAM`), allumée d'après le serveur ; fréquence = canal connu du serveur |

`channel` reste envoyé dans tous les cas. Radio posée ou autoradio : une fréquence annoncée qui diffère du canal
connu du serveur donne le silence (comme une fréquence sans voix). Refus visibles, avant tout regard sur la
fréquence (ordre d'E05-T08) : `NoRadio` (objet introuvable, pas une radio émettrice), `TooFar` (radio posée hors de
portée du micro ou à un autre étage), `NotInVehicle` (autoradio d'un véhicule où le joueur n'est pas assis), `Off`
(radio posée ou autoradio éteinte d'après le serveur). Haut de gamme et bornes de réglage : données de l'appareil
désigné. Le pont reçoit dans `radio=` le nom de l'appareil (`getDeviceName()` pour une radio posée ou une
autoradio). Compatibilité : un client antérieur n'envoie que `text`, `itemId`, `channel` et garde le comportement
d'avant ; un serveur antérieur ignore `source` et ses champs, et juge la radio en main. Une radio posée n'a pas de
propriétaire : tout joueur à portée de son micro peut s'en servir, comme en vanilla.

**Appels spontanés (E05-T05).** Une demande `kind=radio_call` demande au pont le court appel général d'une voix
(`docs/persona-format.md`, « Appels spontanés ») ; ce sont des champs radio en clair, sans `payload` RSV2 :

```text
req=1790000000000-100123-call
sent=1790000000000
kind=radio_call
voice=darlene
date=1993-07-12 08:00
language=FR
```

`language` est le code de langue de l'autorité (`Translator.getLanguage():name()`), celle du texte fixe de
secours ; ni appelant, ni phrase, ni fréquence. Le pont répond au format radio habituel, `resp=<id>` puis 0 à 3
`line=…` : aucune ligne (échec du LLM, fiche absente, secret cité, demande trop ancienne) signifie « texte fixe ».
Le serveur diffuse le texte fixe `call_text` de la fiche si la réponse est vide ou ne contient que des parasites, ou
s'il n'a rien lu après 30 s réelles (`Const.CALL_TIMEOUT_MS`). Compatibilité : un pont antérieur à E05-T05 passe
toute demande à `kind` par `npc.unpack_request`, qui refuse ce `kind` inconnu ; la demande est ignorée sans réponse
ni erreur, et le serveur diffuse le texte fixe après le délai. Un appel partage le tour de sa voix (`(voix, partie)`)
avec les réponses aux joueurs.

**Bulletin du soir (E14-T02).** Une demande `kind=bulletin` (`RS_Facts.bulletin`, par `RS_RadioServer.submit`)
demande le bulletin du chroniqueur ; champs radio en clair comme `radio_call`, plus `facts` :

```text
req=1790000000000-100123-bulletin
sent=1790000000000
kind=bulletin
voice=nightowl
date=1993-07-12 20:00
language=FR
facts=<hexadécimal RSV2 d'une liste de phrases anglaises>
```

`facts` : faits confirmés du jour (au plus 12, morts d'abord, 200 caractères chacun), phrases construites par le
serveur depuis les champs fermés du journal des faits (`RS_Facts.factText` : jamais de coordonnée, de conversation ni
de secret) ; absent = rien de confirmé. `language` : option `CallLanguage` comme les appels spontanés. Le pont
(`bridge/bulletin.py`) ajoute à la fiche sans secrets la consigne du bulletin (ces faits seuls, aucun ajout) et
répond `resp=<id>` puis 0 à 6 `line=…` ; aucune ligne (échec, fiche absente, secret cité, demande trop ancienne) =
bulletin de secours. Le serveur diffuse le texte du pont, ou après 60 s réelles (`RS_Facts.BULLETIN_TIMEOUT_MS`) son
bulletin de secours traduit (`IGUI_RS_Bulletin_*`, langue de l'autorité), sur la première fréquence du chroniqueur,
puis purge les faits lus. Hors plafond horaire et budget de voix (un bulletin par soirée). Compatibilité : un pont
antérieur à E14-T02 ignore la demande (comme `radio_call` avant E05-T05) ; le serveur lit son bulletin de secours.

**Historique radio du carnet (E06-T04).** Hors pont : tenu par l'autorité (`server/RadioSurvivor/RS_RadioLog.lua`)
dans l'état privé du carnet, `characters[<personnage>].radio = { seq, frequencies = { { khz, last, lines } } }`,
sauvegardé avec lui (`RS_State`, toutes les 5 s s'il a changé, à `OnSave`) : il survit au redémarrage du serveur et
à la reconnexion, et disparaît à la mort du personnage (`characterDeath`). Bornes : 40 lignes par fréquence,
8 fréquences par personnage (la moins récemment active est oubliée), 200 caractères par ligne (texte sur une ligne,
sans `<>[]`, parasites `<bzzt>` exclus) ; au pire environ 8 × 40 × 250 o = 80 Kio par personnage vivant, sous la
limite de 4 Mio de l'état privé jusqu'à une quarantaine de personnages pleins. Ligne : `kind` (`said`, `reply`,
`heard`, `mark`), `text`, `when` (heure de jeu `MM/JJ hh:mm`), `seq` (compteur du personnage, ordre et activité).

| Type | Source | Moment |
|---|---|---|
| `said` | phrase acceptée de ce joueur (commande `talk` : demande au pont **ou** silence), sur la fréquence contrôlée par le serveur (radio d'inventaire : annoncée et dans les bornes de la radio ; radio posée, autoradio : canal du serveur) | à l'acceptation |
| `reply` | lignes de la réponse d'une voix à ce joueur (personnage relevé avec la demande) | quand la diffusion passe à l'antenne |
| `heard` | ligne reçue par une radio de ce client (`OnDeviceText`), signalée par la commande `heard` et admise seulement si le serveur l'a diffusée sur cette fréquence depuis moins de 5 min (réponse à un autre joueur, appel spontané, phrase d'un autre joueur passée par `talk`), une fois par personnage | au signalement |
| `mark` | repère reçu (E07-T08) : action `mark_map` acceptée pour ce personnage (`ctx.cid` de la demande), sur la fréquence de la réponse (`ctx.khz`) ; `text` = libellé du lieu seul, jamais ses coordonnées ; onglet Radio du carnet : `IGUI_RS_Radio_mark` (« Repère reçu : <libellé> »), en rouge brique | à l'acceptation de l'action |
| `reveal` | quartier révélé (E07-T05) : action `reveal_area` acceptée pour ce personnage, mêmes règles que `mark` ; `text` = libellé du lieu seul ; onglet Radio : `IGUI_RS_Radio_reveal` (« Quartier révélé : <libellé> »), même rouge brique | à l'acceptation de l'action |

Le serveur ne sait pas quelle radio écoute quoi (canal d'une radio d'inventaire connu en main seulement ; en MP toute
radio allumée de l'inventaire reçoit) : le client dit ce qu'il a reçu, le serveur en garantit le texte et la
fréquence. Aucune fréquence n'entre dans l'historique d'un personnage sans que sa radio l'ait réglée (E05-T08).
Sondage borné : au plus 40 signalements par minute et 4 fréquences distinctes par 10 minutes et par personnage
(sans quoi un client modifié pourrait essayer le texte fixe d'un appel sur chaque fréquence).

Commandes (module `RadioSurvivor`) :

| Sens | Commande | Arguments |
|---|---|---|
| client → serveur | `heard` | `khz`, `text` |
| client → serveur | `history` | `v=1` (table jamais vide) ; à l'ouverture du carnet et de l'onglet Radio |
| serveur → client | `history` | `character`, `frequencies` = `{ khz, last }` (absent si vide), puis une commande `history_lines` par fréquence |
| serveur → client | `history_lines` | `character`, `khz`, `last`, `lines` (la fréquence entière, 40 lignes au plus) |
| serveur → client | `history_add` | `character`, `khz`, `last`, `line` (une ligne nouvelle, au joueur connecté de ce personnage) |

Le serveur n'envoie jamais que l'historique du personnage lié au joueur (`RS_CarnetServer.bound`, commande `hello`
du carnet) ; sans personnage lié ni état privé lisible, aucune ligne n'est tenue ni envoyée. Le client remplace ses
données si `character` change. Rien de cet historique ne part vers le pont.

L'ancien fichier sans `protocol/generation/commit` reste lisible par ce Python ; **l'ancien Python n'est pas compatible avec les demandes PNJ**.
Mettre à jour le bridge avec le Lua 0.2, sans lancer un deuxième processus.

Une génération v2 exige `commit` identique et `end`. Fichier incomplet, version inconnue,
identifiants répétés, champs répétés dans une demande, plus de 64 demandes ou plus de 1 Mio :
lecture refusée. Le Lua publie seulement la tête de file de chaque PNJ, Walt et les acquittements.
Il n'a pas d'API de renommage atomique confirmée : troncature, écriture, fermeture et marqueurs
de génération protègent la lecture des fichiers partiels. Python publie ses réponses par fichier
temporaire, `flush`, `fsync`, puis `os.replace`, avec reprise limitée en cas de partage Windows.

Réponse PNJ : `resp=<id>` puis `payload=<hex>` ; réponse d'acquittement au même format.
Le lecteur Lua exige le marqueur `end`, une enveloppe et un corps au même identifiant ; limite 1 Mio.

## Réponse radio structurée (E07-T01)

Une voix radio peut répondre par du texte **et** des actions du catalogue fermé (note de travail §02). Le pont
valide la forme, le serveur le fond ; le serveur seul exécute. Implémentation : `bridge/radio_bridge.py`
(`structured`, `actions_prompt`, `parse_structured`, `bounded_actions`), `RadioSurvivor_Server.lua`
(`readResponses`), `RS_Actions.lua` (registre et décisions).

**Deux modes, choisis par la fiche de la voix** (`actions=`, `docs/persona-format.md`) :

- **Mode texte** (fiche `say` seul : toutes les fiches livrées ; ou fiche dont aucune action autorisée n'a
  d'exécuteur, E07-T07) : prompt, `radio_lines` et sortie `line=` strictement identiques à ceux d'avant E07. Une fiche
  `actions=say,mark_map` **sans ligne `place=`** donne ainsi le même prompt que la même fiche `say` seul (E07-T04).
- **Mode structuré** (au moins une action autorisée par la fiche **et dotée d'un exécuteur** côté serveur, E07-T07) :
  le prompt système demande en plus un objet JSON `{"say": "...", "actions": [{"type": "...", <paramètres>}]}`, nomme
  les actions proposées et décrit chacune (paramètres, types, bornes, usage) avec un exemple d'objet JSON ; jamais de
  secret, de coordonnée ni de fréquence. `say` peut aussi être une liste de chaînes (jointes) ; un bloc
  ```` ```json ```` autour de l'objet est toléré. La consigne de format est en plus **rappelée à la fin du message de
  l'appelant** envoyé au LLM (`format_reminder` : objet attendu et types d'action proposés, sans lieu, secret ni
  coordonnée) ; l'historique garde la question sans ce rappel (E07-T09).
- **Actions proposées** (`EXECUTABLE_ACTIONS` et `offered_actions` du pont) : celles de la fiche qui ont un exécuteur
  (`Actions.register`), dans l'ordre de la fiche. Les autres ne sont pas proposées au LLM (journal anglais une fois
  par voix et par liste : `actions not offered to the LLM, no executor on the server yet`). Description envoyée, en
  anglais, bornes reprises de `RadioSurvivor_Const.lua` (un test compare noms et bornes au serveur) :

  | Action | Paramètres décrits |
  |---|---|
  | `remember` | `fact` : texte d'au plus `MEMORY_FACT_CHARS` (64) caractères, un fait court sur l'appelant (nom, lieu déclaré, service rendu) ; une note, pas une preuve |
  | `persona_state` | au moins un de : `morale`, `supplies` (vivres, eau, munitions) : entiers de 0 à `PERSONA_LEVEL_MAX` (10), au plus `PERSONA_LEVEL_STEP` (2) d'écart par appel ; `place` : texte d'au plus `PERSONA_PLACE_CHARS` (40) caractères, où la voix dit être |
  | `mark_map` | `place` : identifiant d'un lieu de la fiche ; suivi de la liste `id: libellé` des lieux (`place=`), jamais de coordonnées ; exemple au premier identifiant. Proposée seulement si la fiche a au moins un lieu (sinon journal anglais une fois par voix : `mark_map not offered to the LLM, the sheet has no place= line`) |
  | `reveal_area` | `place` : identifiant d'un lieu de la fiche, comme `mark_map` (E07-T05) ; mêmes conditions (au moins un lieu, sinon `reveal_area not offered to the LLM, the sheet has no place= line`) ; la liste `id: libellé` n'est écrite qu'une fois, sous la première de ces deux actions proposée ; aucune taille de zone demandée au LLM (le serveur la fixe) |
  | `start_mission` | `template` : `scout` seul (liste fermée, E11-T08) ; la voix ne choisit pas le bâtiment, décrit juste après par une demande de consigne (`turn = briefing`, E11-T09), puis à chaque appel par le champ `mission=` (« Mission donnée par une voix ») |
  | `report_mission` | aucun paramètre (E11-T13) : compte rendu, à la radio, de la mission de cette voix dont l'objectif est rempli (tour `report_due`) ; permise avec `start_mission` sans être listée ; refusée `no_mission` (pas de mission ouverte de cette voix pour l'appelant) ou `not_done` (objectif non rempli) |
  | `propose_trade` | `items` : texte d'au plus 64 caractères, « `Nom:quantité` » séparés par des virgules, noms du livre du passeur ; `margin` : nombre facultatif dans la fourchette du livre ; le serveur calcule le prix et fige l'offre (E13-T02, « Livre du passeur ») ; refuser = ne rien proposer |

  Un nouvel exécuteur côté serveur doit être ajouté à cette table du pont (sinon son action n'est jamais proposée).
- Pont `--offline` ou absent : jamais d'action (le mode hors ligne reste en mode texte, même pour une fiche à actions).
- Appels spontanés (`kind=radio_call`) : inchangés, jamais d'action.

**Validation du pont** (`bounded_actions`, forme seulement) : au plus 3 actions ; chacune un objet dont `type` est
dans `persona_store.ACTIONS` et dans `actions=` de la fiche, doté d'un exécuteur (`EXECUTABLE_ACTIONS`, E07-T07 :
le serveur la refuserait `not_available`), jamais `say` (le texte est déjà `say`) ; au plus 8
paramètres, noms `[a-z][a-z0-9_]{0,31}`, valeurs scalaires : chaîne passée par `safe_text` (contrôles et balises
retirés) d'au plus 64 octets UTF-8, nombre fini, booléen ; `mark_map` et `reveal_area` : seulement `place`,
identifiant d'un lieu de la fiche (E07-T04, E07-T05). Un élément invalide est retiré et journalisé (anglais), le reste passe. JSON illisible : le texte brut devient `say` seul, sans action (journalisé). `leaks_secret` s'applique au
texte et à chaque paramètre chaîne : une fuite donne les parasites `<fzzt>` en `line=`, rien en mémoire, aucune action.
La mémoire de conversation ne garde que le texte `say`, jamais le JSON.

**Robustesse de la réponse structurée (E07-T09)**, constatée en jeu le 2026-10-11 : après un long historique de
réponses en texte (seul `say` est mémorisé), le modèle a répondu en texte et l'action a été perdue. Parades :

- **Mode JSON de l'API** (`call_llm(..., json_mode=True)`, mode structuré seulement) : le premier essai ajoute
  `response_format = {"type": "json_object"}` (API compatible OpenAI ; le mot JSON figure toujours dans le prompt). Un
  refus HTTP 400 donne un nouvel essai sans, mêmes autres paramètres, puis le minimal (`model`, `messages`) comme
  avant ; si l'essai sans `response_format` réussit après ce refus, le couple (adresse, modèle) n'est plus sollicité
  en mode JSON jusqu'au redémarrage du pont (journal anglais : `LLM provider refused the JSON response mode`). Une
  erreur autre que 400 arrête les essais, comme avant. Le mode texte n'envoie jamais `response_format`.
- **Rappel de format en fin de prompt** (ci-dessus).
- **Extraction tolérante** (`parse_structured`) : premier objet JSON complet qui a `say` ou `actions`, cherché dans
  tout le texte (objet seul, précédé ou suivi de phrases, dans un bloc ```` ``` ```` ou ```` ```json ````, parmi
  plusieurs objets : un objet sans ces clés est ignoré) ; saut de ligne brut admis dans une chaîne. Seulement si rien
  n'est lisible tel quel : guillemets typographiques “ ” „ remplacés par des guillemets droits et virgule finale
  avant `}` ou `]` retirée, puis nouvelle recherche (un JSON valide n'est jamais réparé, ses guillemets typographiques
  restent dans `say`). Objet sans `say` (ou `say` vide) : le texte autour de l'objet devient `say`. `actions: null` =
  aucune action.
- **Journal** : réponse illisible = `structured reply unreadable (ValueError: no object | no reply object | say is not
  text)` comme avant, puis, en `--debug`, la réponse brute sur une ligne, tronquée à 300 caractères
  (`RAW_LOG_CHARS`) ; si elle cite un secret de la fiche, seule sa longueur est écrite. Aucune clé d'API n'est
  journalisée.

**Sortie** : sans action restante après validation, `line=` comme avant. Sinon :

```text
resp=<id de la demande>
payload=<RSV2 hexadécimal de { version = 2, kind = "radio_reply", id = <id>, say = { lignes }, actions = { ... } }>
```

Chaque action est une table `{ type = "signal", color = "green", ... }` : `type` puis les paramètres à plat.

**Lecture par le serveur** : `readResponses` accepte `line=` (inchangé) et `payload=` pour un identifiant radio :
corps décodé par `RS_Codec`, `version == 2`, `kind == "radio_reply"` et `id` égal à celui de `resp=`, sinon ignoré
(les réponses `npc_reply` et `ack_reply` du même fichier restent à `RS_Transport.readNpc`, qui ignore à son tour les
réponses radio). Les lignes `say` repassent par le filtrage de `line=` (balises, 140 caractères, 8 lignes), puis la
diffusion est mise en file comme une réponse texte ; ensuite seulement, `RS_Actions.decide` juge les actions contre la
fiche **actuelle** de la voix.

**Décisions du serveur** (`RS_Actions.decide(sheet, caller, actions, now, ctx)`, une décision
`{ type, params, accepted, reason }` par action, dans l'ordre reçu). Au plus 3 actions jugées par réponse, les
suivantes refusées `too_many`. Pour chacune, dans cet ordre :

| Raison | Refus quand |
|---|---|
| `unknown_action` | `type` hors catalogue (ou action qui n'est pas une table) |
| `not_allowed` | action absente de `actions=` de la fiche, ou voix sans fiche au moment de la réponse |
| `not_available` | aucun exécuteur enregistré (`say` n'en a jamais : il passe par la diffusion) |
| `bad_params` | paramètres non scalaires, nom invalide, chaîne de plus de 64 caractères, plus de 8 paramètres, ou refus de `validate` |
| `too_far` | l'exécuteur a `maxDistance` et l'appelant est plus loin (distance au sol en cases) de `coords=` de la fiche ; contrôle **ignoré** quand la voix n'a pas de lieu fixe ou que l'appelant n'est pas connecté (rien à comparer) |
| `budget` | `budget.<action>` de la fiche atteint pour le jour de jeu (par voix ; `0` ou absent = sans plafond) |
| `cooldown` | moins de `cooldownMs` (horloge réelle) depuis le dernier usage de cette action par cette voix |
| `<raison de l'exécuteur>` ou `failed` | `execute` a échoué (aucun compteur consommé) |
| `ok` (acceptée) | `execute` a réussi : usage compté pour le budget et le délai |

Chaque décision écrit une ligne console :
`[RadioSurvivor] action <type> voice=<id> caller=<clé> accepted|refused reason=<raison>` et une ligne du journal
admin fichier (ci-dessous).

**Exécuteurs** : `Actions.register(name, { validate = f(params, ctx) -> ok, cooldownMs = n, maxDistance = n,
execute = f(params, ctx) -> ok, reason })`, `ctx = { caller, voice, sheet, player, khz, cid, day }` (`sheet` : fiche
de la voix, E07-T04). `remember` (E07-T03, « Mémoire des voix » ci-dessous), `persona_state` (E07-T06, « État
dynamique des voix » ci-dessous), `mark_map` (E07-T04, « Repère sur la carte » ci-dessous), `reveal_area` (E07-T05,
« Quartier révélé » ci-dessous) et `start_mission` (E11-T08, « Mission donnée par une voix » ci-dessous) ont le leur ; toute autre action du catalogue autre que `say` est refusée
`not_available` tant que sa tâche (E11, E12, E13) n'a pas branché le sien.

**Compteurs** (budget du jour, dernier usage) : état privé du serveur, jamais en ModData globale. Rangés dans l'état
privé du carnet (`RS_State`, `data.actionCounters[<voix>][<action>] = { day, used, lastMs }`, sauvegardé par la
boucle du carnet) dès qu'il est chargé ; sinon en mémoire, perdus au redémarrage du serveur.

**Compatibilité** : un serveur antérieur à E07 lit `payload=` d'un identifiant radio comme une réponse sans ligne
(parasites seuls) ; les fiches livrées étant `say` seul, ce cas ne se produit pas sans fiche modifiée. Un pont
antérieur ne produit jamais de `payload=` radio ; ses réponses `line=` restent lues sans changement.

### Journal admin des actions (E07-T02)

`server/RadioSurvivor/RS_ActionLog.lua`, appelé par `RS_Actions.decide` : **une ligne par action proposée**
(acceptée ou refusée, `too_many` compris), écrite sur la machine du serveur (celle du joueur en solo) dans
`Zomboid/Lua/batman_RadioSurvivor/actions-<partie>.log`, où `<partie>` est l'hexadécimal de
`<mode de jeu>/<nom du monde>`, comme le fichier d'état `state-<partie>-<0|1>.txt` de `RS_State`. Fichier UTF-8, fin
de ligne `\n`. Une ligne d'en-tête `# RadioSurvivor action log v1 (tab-separated): ...` ouvre chaque fichier.

Huit champs séparés par une **tabulation** :

| Champ | Contenu |
|---|---|
| `real_utc` | date réelle `AAAA-MM-JJ HH:MM:SS UTC` (`os.date`, toujours en UTC dans Kahlua) |
| `game_time` | date de jeu `AAAA-MM-JJ HH:MM` |
| `voice` | identifiant de la voix (`-` si la fiche a disparu) |
| `caller` | clé de l'appelant, la même que dans la ligne console |
| `action` | nom de l'action (`?` hors `[a-z_]`, 32 caractères au plus, comme la console) |
| `params` | `clé=valeur` triés par clé, séparés par `;` ; `-` sans paramètre ; `<invalid>` quand les paramètres ont été rejetés (`bad_params` de forme : rien n'est recopié) |
| `decision` | `accepted` ou `refused` |
| `reason` | raison du tableau ci-dessus (`ok` si acceptée) |

Encodage des champs : `%`, `=`, `;` et tout caractère de contrôle (tabulation, retours compris) deviennent `%XX`
(hexadécimal majuscule) ; une valeur reste ainsi sur une ligne, sans séparateur, et se décode à l'identique. Champ
vide : `-`.

**Contenu** : seuls le nom d'action filtré, les paramètres déjà bornés par le serveur (`paramsOf` : scalaires, 64
caractères, 8 au plus) et la décision ; jamais de contenu de fiche (secret, prompt, coordonnées), jamais le texte
`say`. Les paramètres viennent du LLM et peuvent contenir ce que la voix a choisi d'y mettre : le pont a déjà refusé
toute réponse qui cite un secret (`leaks_secret`), et l'admin possède de toute façon les fiches.

**Rotation bornée** (`RadioSurvivor_Const.ACTION_LOG_MAX_LINES = 2000`, `ACTION_LOG_MAX_CHARS = 262144`, en-tête
compris, caractères comptés en unités Kahlua) : avant d'écrire les lignes d'une réponse qui feraient dépasser l'un
des seuils, le contenu courant est recopié dans `actions-<partie>.1.log` (l'ancien `.1` écrasé), puis le fichier
courant est vidé et repart avec l'en-tête. Le jeu ne permet pas de renommer un fichier depuis Lua : la rotation lit
le fichier courant (`getFileReader`) et le réécrit (`getFileWriter(..., true, false)`). Les lignes ordinaires sont
ajoutées (`getFileWriter(..., true, true)`), une ouverture par réponse. Le nombre de lignes et de caractères est
tenu en mémoire, initialisé par une seule lecture du fichier au premier usage (ou au changement de partie). Au plus
deux fichiers, soit environ deux fois les seuils sur le disque.

Écriture impossible (`getFileWriter` nil) : un avertissement console unique
`[RadioSurvivor] action log unavailable: ...`, la ligne console de chaque décision reste.

### Mémoire des voix (E07-T03)

Action `remember` : la voix retient un fait court sur l'appelant (nom de personnage, lieu déclaré, service rendu). Le
pont la propose, le serveur l'accepte et range le fait ; la mémoire vit **côté autorité**, jamais dans le pont ni en
ModData globale. Implémentation : `server/RadioSurvivor/RS_Memory.lua` (exécuteur, bornes, champ de demande),
`RadioSurvivor_Server.lua` (champ joint à la demande), `RS_Transport.lua`, `bridge/radio_bridge.py`
(`memory_facts`, `memory_prompt`).

**Exécuteur** (jugé par `RS_Actions.decide` comme toute action : catalogue, `actions=` de la fiche, paramètres,
`budget.remember` par jour de jeu et par voix, `0` ou absent = sans plafond) :

- paramètre unique `fact`, chaîne ; tout autre paramètre, ou un fait vide une fois nettoyé : `bad_params`. Nettoyage :
  contrôles, retours et `<>[]` en espaces, espaces réduits, coupé à 64 caractères (`Const.MEMORY_FACT_CHARS`, la borne
  des paramètres d'action) ;
- délai `cooldownMs = 0` : le délai de `RS_Actions` est par voix et non par appelant, il ferait refuser le souvenir d'un
  deuxième appelant juste après celui d'un premier ; le budget du jour, les 3 actions par réponse et les bornes
  ci-dessous limitent l'écriture ;
- **aucun effet de jeu** : seulement la mémoire (`S.dirty = true` quand l'état privé est chargé).

**Rangement** : `RS_State`, `data.memory[<voix>] = { seq, callers = { [<clé>] = { caller, cid, seq, facts = { { text,
seq } } } } }`, sauvegardé avec l'état du carnet ; sans état chargé (pas encore initialisé ou bloqué), table en
mémoire perdue au redémarrage du serveur, comme les compteurs d'actions. Clé = voix + appelant (`callerKey` : compte
en MP, `solo` en solo) + personnage du carnet (`cid` de la demande, `-` sans carnet lié) : un nouveau personnage en
solo n'hérite pas des souvenirs du précédent.

**Bornes** (`RadioSurvivor_Const`) : au plus `MEMORY_MAX_FACTS = 5` faits par (voix, appelant, personnage), le plus
ancien évincé ; un fait identique après normalisation (casse, espaces) est rafraîchi (repasse en dernier), pas
dupliqué ; au plus `MEMORY_MAX_CALLERS = 50` appelants par voix, le moins récemment servi par `remember` évincé ; au
pire 50 × 5 × 64 caractères par voix. Aucun souvenir entre voix, aucun pour les appels spontanés.

**Purge** : la mort d'un personnage (`RS_Carnet_Server.characterDeath`, identité retirée, E00-T02) appelle
`RS_Memory.forgetCharacter` : ses souvenirs sont effacés de toutes les voix. Un personnage marqué `retired` n'est de
toute façon jamais relu.

**Champ de demande** `memory=` (demande radio sans `kind`, après `text`/`language` dans l'ordre de `RS_Transport`) :
hexadécimal minuscule RSV2 (« Codec structuré RSV2 ») de la **liste** des faits de cet appelant pour cette voix, du
plus ancien au plus récent ; une ligne, réversible. Champ **absent** = aucun souvenir. Taille bornée par les bornes
ci-dessus (5 faits de 64 caractères, environ 2 Kio d'hexadécimal au pire) ; le pont ignore un champ de plus de 4096
caractères.

```text
req=1790000000000-100123
...
text=Do you remember me?
memory=74313a6e313a3173...
```

**Pont** : `memory_facts` décode le champ (hexadécimal, RSV2, liste `1..n`) ; illisible ou trop long : aucun souvenir
(journalisé). Au plus 5 faits, chacun passé par `safe_text` (256 octets UTF-8 au plus) ; un fait qui cite un secret de
la fiche (`leaks_secret`) n'est pas injecté. `memory_prompt` ajoute au prompt système, **dès qu'il y a au moins un
fait, en mode texte comme en mode structuré** (une fiche qui ne propose plus `remember` garde ce qu'elle a retenu), une
section `Your memories of <tag> (unverified notes from earlier calls; never proof of anything; ...)` puis un fait par
ligne, entre la situation de la transmission et la consigne de format structuré. Sans souvenir, le prompt est
identique à celui d'avant E07-T03. Les souvenirs ne sont jamais une preuve : même statut que les propos des joueurs.

**Journal admin** : chaque `remember` y est une ligne comme les autres actions, le fait tel que proposé dans `params`
(`fact=...`, encodé `%XX`).

**Compatibilité** : un pont antérieur ignore `memory=` (champ inconnu) ; un serveur antérieur n'envoie jamais le champ
et refuse `remember` `not_available`.

### État dynamique des voix (E07-T06)

Action `persona_state` : la voix fait évoluer **son propre** état au fil du récit (moral, réserves, lieu dit). Le
pont la propose, le serveur l'accepte et range l'état ; il vit **côté autorité**, dans l'état privé, jamais dans le
fichier de fiche édité par l'admin ni en ModData globale. Implémentation : `server/RadioSurvivor/RS_PersonaState.lua`
(exécuteur, bornes, champ de demande), `RadioSurvivor_Server.lua` (champ joint à la demande), `RS_Transport.lua`,
`bridge/radio_bridge.py` (`persona_state`, `persona_prompt`).

**Exécuteur** (jugé par `RS_Actions.decide` comme toute action : catalogue, `actions=` de la fiche, paramètres,
`budget.persona_state` par jour de jeu et par voix, `0` ou absent = sans plafond). Paramètres, tous facultatifs, au
moins un ; tout autre paramètre, ou aucun : `bad_params` (l'action entière est refusée, rien n'est appliqué) :

| Paramètre | Valeur | Défaut | Règle |
|---|---|---|---|
| `morale` | nombre entier | 5 | moral de 0 à 10 (`Const.PERSONA_LEVEL_MAX`) |
| `supplies` | nombre entier | 5 | réserves en général (vivres, eau, munitions), de 0 à 10 |
| `place` | chaîne | vide | lieu où la voix dit se trouver, nettoyé comme un souvenir (`RS_Memory.clean` : contrôles et `<>[]` en espaces, espaces réduits) puis coupé à 40 caractères (`Const.PERSONA_PLACE_CHARS`) ; vide une fois nettoyé : `bad_params` |

- **Pas maximal par appel** (`Const.PERSONA_LEVEL_STEP = 2`) : `morale` et `supplies` changent d'au plus ±2 par
  rapport à la valeur courante ; une valeur demandée au-delà du pas, ou hors de 0..10, est **ramenée** (pas refusée) ;
  un nombre non entier, une chaîne ou un booléen : `bad_params`. Les 3 actions par réponse permettent au plus ±6 en une
  réponse si la voix enchaîne trois `persona_state`, dans la limite du budget.
- `place` n'est qu'un récit : **aucun effet** sur `coords=` de la fiche, sur le contrôle `too_far` ni sur le jeu.
- La voix ne modifie que son propre état (`ctx.voice`), quel que soit l'appelant ; l'état est le même pour tous les
  appelants.
- Délai `cooldownMs = 0` (le budget du jour suffit) ; **aucun effet de jeu** (`S.dirty = true` quand l'état privé est
  chargé).

**Rangement** : `RS_State`, `data.personaState[<voix>] = { morale, supplies, place }`, sauvegardé avec l'état du carnet ;
sans état chargé (pas encore initialisé ou bloqué), table en mémoire perdue au redémarrage du serveur, comme les
compteurs d'actions. Réinitialisation : supprimer l'entrée de l'état privé (aucune commande dédiée).

**Champ de demande** `persona=` (demande radio sans `kind`, après `memory` dans l'ordre de `RS_Transport`) :
hexadécimal minuscule RSV2 de la table `{ morale = n, supplies = n, place = "..." }` (`place` omis s'il est vide).
Champ **absent** tant que la voix n'a jamais changé son état (aucun `persona_state` accepté) ; ensuite joint à chaque
demande radio à cette voix. Jamais joint aux appels spontanés (`kind=radio_call`). Le pont ignore un champ de plus de
1024 caractères.

```text
text=How are you holding up?
persona=74323a73363a6d6f72616c65...
```

**Pont** : `persona_state` décode le champ (hexadécimal, RSV2, table aux seules clés `morale`, `supplies`, `place`,
niveaux entiers de 0 à 10 tous deux présents) ; illisible, trop long ou invalide : champ ignoré (journalisé), prompt
inchangé. `place` passe par `safe_text` (160 octets UTF-8 au plus) ; vide, trop long ou citant un secret de la fiche
(`leaks_secret`), il est retiré, le reste de l'état gardé. `persona_prompt` ajoute au prompt système, **en mode texte
comme en mode structuré**, après les souvenirs et avant la consigne de format structuré :

```text
Your current state (stay consistent with it; change it only for a reason in the story):
- Morale: 3/10.
- Supplies (food, water, ammunition): 7/10.
- Where you say you are: an old barn.
```

Sans champ, le prompt est identique à celui d'avant E07-T06.

**Journal admin** : chaque `persona_state` y est une ligne comme les autres actions, les paramètres tels que proposés
(avant le pas et le nettoyage).

**Compatibilité** : un pont antérieur ignore `persona=` (champ inconnu) ; un serveur antérieur n'envoie jamais le champ
et refuse `persona_state` `not_available`.

### Repère sur la carte (E07-T04)

Action `mark_map` : la voix marque sur la carte du monde de l'appelant un des lieux qu'elle connaît. La fiche liste
ses lieux (`place=<id> <x>,<y>,<z> <libellé>`, `docs/persona-format.md`, « Lieux connus ») ; le pont ne montre au LLM
que leurs identifiants et libellés ; le serveur juge, puis envoie les coordonnées exactes au **seul appelant**.
Implémentation : `server/RadioSurvivor/RS_MapMarks.lua` (exécuteur), `client/RadioSurvivor/RS_MapActions.lua`
(symboles de la carte), `bridge/radio_bridge.py` (`places_prompt`, `bounded_actions`).

**Exécuteur** (jugé par `RS_Actions.decide` comme toute action : catalogue, `actions=` de la fiche, paramètres,
`budget.mark_map` par jour de jeu et par voix, délai) :

- paramètre unique `place`, identifiant d'une ligne `place=` de la fiche **actuelle** de la voix (`ctx.sheet`) ; lieu
  absent de la fiche (inconnu, d'une autre voix), autre paramètre, paramètre absent ou non texte : `bad_params` ;
- délai `cooldownMs = Const.MAP_MARK_COOLDOWN_MS` (30 000 ms réelles) entre deux repères **de la voix**, tous
  appelants confondus (le délai de `RS_Actions` est par voix) : `cooldown` ;
- appelant introuvable (déconnecté entre la demande et la réponse, `ctx.player` nil) : `no_player`, aucun usage
  compté ;
- accepté : `Const.toClient(ctx.player, "map_mark", { x, y, z, label })`, `sendServerCommand` à 4 arguments (un seul
  joueur) en multijoueur, appel direct du client en solo (où `sendServerCommand` ne fait rien) ; puis, si l'appelant a
  un personnage du carnet (`ctx.cid`), une ligne `mark` de son historique radio (E07-T08, « Historique radio du
  carnet ») sur la fréquence de la réponse (`ctx.khz`) : libellé seul, mêmes bornes que les autres lignes, envoyée à
  lui seul (`history_add`) et visible à la prochaine projection de l'onglet Radio. Inscrite à l'acceptation (les actions
  sont jugées dès la réponse du pont, la diffusion passe ensuite), elle précède les lignes `reply` de cette réponse. Sans personnage lié (carnet jamais
  ouvert), le repère est posé sans ligne. Rien d'autre n'est gardé côté serveur hors des compteurs d'actions, aucune
  coordonnée en ModData globale ni dans l'historique.

**Commande serveur → client** `map_mark` (module `RadioSurvivor`, `Const.CMD.MAP_MARK`) :

| Champ | Contenu |
|---|---|
| `x`, `y`, `z` | coordonnées entières du lieu (`z` reçu, non utilisé : la carte du monde est plane) |
| `label` | libellé du lieu, tel que dans la fiche (48 octets UTF-8 au plus) |

**Client** (`RS_MapActions.receive`, appelé par `RS_RadioTalk.handle` comme toute commande du module) : deux
symboles au centre de la case (`x + 0,5`, `y + 0,5`) dans les annotations du joueur (`MapItem.getSingleton()`, par une
`UIWorldMap` cachée créée une fois par partie, jamais affichée, puis `getAPIv3():setMapItem(...)` et
`getSymbolsAPIv2()`) : l'icône vanilla `Target` au-dessus du point (ancre 0,5 ; 1) et le libellé (`addTranslatedText`,
balises et contrôles retirés) au-dessous (ancre 0,5 ; 0), rouge brique, échelle des notes du joueur (0,666). Un symbole
déjà présent au même point (icône `Target`, ou tout texte : repéré par sa position, le texte d'un illettré étant
masqué) n'est pas ajouté de nouveau. Aucun texte flottant (retiré par E07-T08) : le joueur est averti par la ligne
`mark` de son historique radio. Carte indisponible ou arguments invalides : rien, une ligne console
`[RadioSurvivor] map mark not added: <raison>`.

**Persistance** : celle des annotations vanilla du joueur, sans état propre au mod. Symboles privés (aucun partage
réseau) : écrits dans `map_symbols.bin` de la sauvegarde courante **côté client** (`WorldMapSymbols.save`, symboles
`userDefined` sans `NetworkInfo`), à chaque sauvegarde du jeu (en solo aussi la sauvegarde périodique), relus au
chargement du monde avant `OnGameStart`. Sur un client MP, le fichier est dans le dossier local de ce serveur ; le
serveur ne les connaît pas. Le joueur peut effacer le repère ; un nouveau `mark_map` du même lieu le repose. Un
personnage illettré voit l'icône et un libellé en `?` (comportement vanilla).

**Journal admin** : chaque `mark_map` y est une ligne comme les autres actions (`place=<id>`, jamais les
coordonnées).

**Compatibilité** : un serveur antérieur refuse `mark_map` `not_available` ; un client antérieur ignore `map_mark`
(commande inconnue). Les fiches livrées n'ont ni `mark_map` ni `place=`.

### Quartier révélé (E07-T05)

Action `reveal_area` : la voix « remplit » la carte du monde de l'appelant autour d'un des lieux qu'elle connaît, comme
une carte vanilla lue (zone « connue » : le fond de carte apparaît). Mêmes lieux, même paramètre et mêmes contrôles de
pont que `mark_map` (« Repère sur la carte » ci-dessus) ; le LLM ne choisit jamais la taille de la zone.
Implémentation : exécuteur dans `server/RadioSurvivor/RS_MapMarks.lua` (rangé avec `mark_map` : il partage les lieux de
la fiche, `MapMarks.placeOf` et la validation de `place`), application dans `client/RadioSurvivor/RS_MapActions.lua`.

**Exécuteur** (jugé par `RS_Actions.decide` : catalogue, `actions=` de la fiche, paramètres, `budget.reveal_area` par
jour de jeu et par voix, délai) :

- paramètre unique `place`, identifiant d'une ligne `place=` de la fiche actuelle : sinon `bad_params` ;
- délai `cooldownMs = Const.MAP_REVEAL_COOLDOWN_MS` (60 000 ms réelles) entre deux révélations de la voix, compté à
  part de celui de `mark_map` (`cooldown`) ;
- appelant introuvable : `no_player` ; lieu hors de la carte (rien ne reste après rognage) : `off_map` ; ni l'un ni
  l'autre ne compte d'usage ;
- **rectangle** (`MapMarks.revealRect`) : le plus grand nombre **impair** de blocs de 32 cases qui tient dans
  `Const.MAP_REVEAL_MAX_SIDE` (160 cases, donc 5 blocs), centré sur le bloc du lieu ; bords multiples de 32 ; rogné aux
  bornes de la carte (`getWorld():getMetaGrid()`, cellules de 256 cases : l'alignement reste). Côté de 160 cases au
  plus, 25 600 cases au plus (un quartier), quel que soit le lieu ; plus petit en bord de carte ;
- accepté, en multijoueur : inscription dans la carte connue **du compte** de l'appelant tenue par le serveur
  (`WorldMapVisitedServer.getInstance():setKnownInSquares(player, x1, y1, x2 - 1, y2 - 1)`), puis
  `Const.toClient(ctx.player, "map_reveal", { x1, y1, x2, y2 })` au seul appelant ; en solo, appel direct du client ;
  puis, avec un personnage du carnet, une ligne `reveal` de son historique radio (« Quartier révélé : <libellé> »),
  comme la ligne `mark`. Aucune coordonnée gardée côté serveur hors du mécanisme vanilla, ni en ModData globale.

**Commande serveur → client** `map_reveal` (`Const.CMD.MAP_REVEAL`) :

| Champ | Contenu |
|---|---|
| `x1`, `y1` | coin haut gauche du rectangle, cases, multiples de 32 |
| `x2`, `y2` | coin bas droit **exclu**, multiples de 32 ; `x2 - x1` et `y2 - y1` de 32 à `MAP_REVEAL_MAX_SIDE` |

**Client** (`RS_MapActions.reveal`, par `RS_MapActions.receive`) : contrôle de nouveau l'alignement, le plafond et
l'ordre des bords (sinon rien, `[RadioSurvivor] map area not revealed: bad_args`), puis
`WorldMapVisited.getInstance():setKnownInSquares(x1, y1, x2 - 1, y2 - 1)` sur la carte du seul joueur local (une
instance par processus client), effet immédiat. Le bord haut est passé **inclus** : la méthode vanilla compte le bloc
de la case de bord haut, et un bord exclu multiple de 32 révélerait un bloc de plus de chaque côté
(`.claude/pz-knowledge/world-map.md`, « Bornes de `setKnownInSquares` »). Défaut vanilla : un dernier bloc dont l'index
(relatif à la carte) est multiple de 32 n'est pas révélé ; la zone est alors plus petite d'une rangée, jamais plus
grande. Le client n'envoie aucune commande vanilla `map setKnownInSquares` : le serveur l'a déjà inscrite.

**Persistance** (mécanisme vanilla, sans état du mod) : en solo, `map_visited.bin` de la sauvegarde (écrit à la
sauvegarde du jeu et par la sauvegarde périodique). En multijoueur, le client n'écrit rien ; le serveur garde la carte
connue par nom de compte (`map_visited_server/<compte>.zip` de la partie, sauvegardé à la déconnexion et avec le
monde) et la renvoie au client à sa connexion : la zone révélée survit à la reconnexion, pour tous les personnages de ce
compte (effacée avec le compte quand le serveur retire un joueur mort de la liste blanche). Une révélation ne se défait
pas (le joueur ne peut pas l'effacer, pas d'oubli ciblé côté mod).

**Isolement** : rien n'est diffusé. Commande envoyée par `sendServerCommand` à 4 arguments (un seul joueur) ;
`WorldMapVisitedServer.setKnownInSquares` ne modifie que le tableau du compte de la connexion de ce joueur et n'envoie
aucun paquet ; le tableau n'est transmis qu'à ce compte, à sa connexion. Deux joueurs de l'écran partagé d'un même
client partagent la carte de ce client (comportement vanilla).

**Journal admin** : une ligne par décision (`place=<id>`, jamais le rectangle).

**Compatibilité** : un serveur antérieur refuse `reveal_area` `not_available` ; un client antérieur ignore
`map_reveal` (la zone reste inscrite sur le serveur en MP et apparaît à la reconnexion).

### Mission donnée par une voix (E11-T08)

Action `start_mission` : une voix radio confie une mission « reconnaître » (gabarit `scout` d'E11-T03) à son
appelant ; le compte rendu se fait **à la radio**, sur la fréquence de la voix. La voix n'a ni fiche de PNJ du carnet
ni corps. Implémentation : `server/RadioSurvivor/RS_MissionVoice.lua` (exécuteur, donneur « voix », contexte),
`RS_Missions.lua` (moteur commun, `M.donorOf`), `RS_MissionScout.lua` (lieu, sondage), `RadioSurvivor_Server.lua`
(compte rendu et champ `mission=`), `bridge/radio_bridge.py` (`EXECUTABLE_ACTIONS`, `mission_context`,
`mission_prompt`).

**Exécuteur** (jugé par `RS_Actions.decide` comme toute action : catalogue, `actions=` de la fiche, paramètres,
`budget.start_mission` par jour de jeu et par voix, délai `Const.START_MISSION_COOLDOWN_MS` = 60 000 ms réelles par
voix, tous appelants confondus) :

- paramètre unique `template`, liste fermée `RS_MissionVoice.TEMPLATES` (seulement `scout`) ; autre valeur, paramètre
  absent ou en trop : `bad_params` ;
- le serveur choisit le lieu avec l'offre du gabarit (`RS_MissionScout` : bâtiment habitable de la métagrille à 60–250
  cases de la **copie serveur** de l'appelant, à 60 cases au moins de toute base connue, mêmes règles qu'E11-T03) ;
- refus motivés (raison de l'exécuteur, aucun usage compté) : `no_player` (appelant déconnecté : pas de position
  serveur), `storage` (état privé non chargé ou bloqué), `no_character` (aucun personnage du carnet lié),
  `mission_open` (cet appelant a déjà une mission ouverte de cette voix), `recent_mission` (moins de
  `OFFER_COOLDOWN_MS`, 30 min réelles, depuis la clôture de sa précédente mission de cette voix : délai de M01),
  `no_place` (aucun bâtiment admissible) ;
- accepté : mission créée **et acceptée** pour l'appelant (`active`), délai de M01 (`durationMs` du catalogue
  `scout`, 7 200 000 ms de fonctionnement du serveur) ; ligne `mission` de l'historique radio du personnage sur la
  fréquence de la réponse (type du lieu seul, `RS_Rescue.KINDS` : `house`, `church`..., traduit par le carnet :
  « Mission reçue : maison ») ; projection du carnet publiée ;
- **consigne (E11-T09)** : la réponse qui propose `start_mission` est diffusée avant que l'action soit jugée et ne
  connaît donc pas le lieu. Une fois la mission créée, `RS_MissionVoice.onStarted` (installé par
  `RadioSurvivor_Server`) ajoute **une** demande radio de plus pour le même appelant, la même voix et la même
  fréquence (identifiant `<ms>-<n>-brief`, texte fixe anglais `(stays on the line and waits for the details of the
  job)`, champs `memory=`, `persona=` et `mission=` avec `turn = briefing`). Elle ne compte ni dans le plafond horaire
  ni dans le budget de la voix (même échange), respecte `MAX_PENDING`, ne bloque pas l'appelant (« Waiting »), ne lui
  envoie ni `done` ni refus, et n'est pas écrite dans son historique comme phrase dite ; la réponse est diffusée sur
  la fréquence comme toute réponse. Pont muet après `TIMEOUT_MS` : rien à l'antenne (journal anglais), le carnet
  montre les indices.

**Donneur « voix »** : un enregistrement par voix et par personnage du carnet dans l'état privé (`RS_State` :
`data.voiceDonors['voice:<voix>:<personnage>'] = { id, voice, character, mission, missionCount, nextOfferAt, given }`),
jamais en ModData globale. La mission garde `npc` = cet identifiant (distinct de tout identifiant de fiche de PNJ),
`donor = 'voice'`, `voice`, `requesterName` (nom de la fiche), `khz`, `report = 'radio'`, et aucun lot
(`rewardType = ''`, `rewardCount = 0`). Le moteur commun la traite comme les autres (chrono, abandon, échec, purge,
barème de réputation de M01) ; une seule mission ouverte par appelant et par voix.

**Visite** : le sondage serveur d'E11-T03 (`M.observe`, boucle du carnet, copie serveur du joueur), sans code propre.

**Compte rendu (E11-T13, décision de l'utilisateur du 2026-10-14)** : à chaque phrase admise de l'appelant pour
cette voix (commande `talk`, voix choisie par la fréquence, demande transmise au pont), `RS_MissionVoice.heard` ne juge
rien et dit seulement à la voix où en est la mission : avant la visite `turn = not_yet` ; après la visite (objectif
rempli, `RS_Missions.reportReady`) `turn = report_due`. C'est le **modèle** qui reconnaît le compte rendu (dans
n'importe quelle langue, aucune liste de mots) et rend l'action `report_mission` (sans paramètre) ; elle est permise à
toute voix dont la fiche autorise `start_mission` sans être listée (`RS_Actions.IMPLIED`, `radio_bridge.IMPLIED_ACTIONS`).
Son exécuteur (`RS_MissionVoice.report`) revérifie les faits : mission ouverte de **cette** voix pour **cet** appelant
(`no_mission` sinon : autre joueur, autre fréquence donc autre voix ou aucune), objectif rempli (`not_done` sinon : une
affirmation ne valide rien), puis `M.spoken` → `M.report` (charge `speech`, marqueur à journal préalable, reçu
`speech-<personnage>`) et la mission réussit. Une réponse sans l'action laisse la mission « à rapporter ». Sans pont la
voix ne répond pas : la mission attend le pont (ou son délai) ; aucun bouton du carnet pour une voix.

**Récompense** : réputation par le moteur (`mission.success`, +5, barème M01), et une **information** : repère
`map_mark` (`MapMarks.give`, ligne `mark` « Repère reçu ») du premier lieu `place=` de la fiche **actuelle** qui n'a
pas encore été donné à ce personnage par cette voix, envoyé au seul appelant, hors budget et délai de `mark_map`. Fiche
sans lieu, ou tous déjà donnés : réputation seule (journal anglais `no place left to give, reputation only`). Le repère
part après la sauvegarde de la réussite : un arrêt entre les deux perd le repère, jamais la réussite. Pas de cache
(E11-T06).

**Champ `mission=` de la demande radio** (hexadécimal RSV2, `RS_MissionVoice.field`, écrit par `RS_Transport` après
`persona=`) : présent seulement quand cet appelant a une mission ouverte de cette voix.

| Clé | Contenu |
|---|---|
| `kind` | `scout` |
| `state` | `active` ou `success` |
| `turn` | `briefing` (mission tout juste créée : demande de consigne, E11-T09), `not_yet` (lieu pas atteint), `report_due` (E11-T13 : lieu atteint, cet appel peut être le compte rendu, action `report_mission`), `success` (ancien serveur : compte rendu accepté), `open` (autre cas) |
| `toReport` | booléen (E11-T13) : objectif rempli constaté par le serveur, compte rendu attendu |
| `place` | type du bâtiment en anglais (`house`, `church`...) |
| `clues` | liste de phrases anglaises sans aucun chiffre (`RS_Rescue.clues`) |
| `zoneReached` | booléen constaté par le serveur |
| `report` | `radio` |
| `remainingMs` | temps restant (ms de fonctionnement du serveur) |
| `reward` | libellé du lieu donné en récompense, ou qui le sera au compte rendu (tour `report_due`) ; absent sinon |

Jamais de coordonnée, de zone ni d'identifiant de bâtiment. **Pont** (`mission_context`) : champ absent = aucune
section (prompt d'avant E11-T08) ; illisible, plus de 8 192 caractères, `kind` autre que `scout`, `state` ou `turn`
inconnus, lieu avec un chiffre : ignoré (journalisé) ; indices passés par `safe_text`, un indice avec un chiffre ou qui
cite un secret de la fiche est retiré ; `reward` absent des libellés de la fiche est retiré. `mission_prompt` ajoute au
prompt système, après l'état de la voix et avant la consigne de format, la section « The job you gave … » : le travail,
les indices, « pas encore » (quoi que dise l'appelant, jamais `report_mission`), au tour `report_due` « seul le compte
rendu est attendu : s'il en rend compte, ajouter `{"type": "report_mission"}` et remercier » avec le lieu que donnera la
réussite, et le temps restant en minutes. Tour `briefing` (E11-T09) : consigne explicite de dire **maintenant** le type de bâtiment et
**tous** les indices, sans rien ajouter, dans la langue de l'échange, et pas de « pas encore ». Mission ouverte avec
indices (autres tours) : redire les indices si l'appelant demande où c'est.

**Description au LLM** (`EXECUTABLE_ACTIONS`) : confier une mission de reconnaissance ; `template` : `scout` seul ; la
voix ne choisit pas le bâtiment, il lui est décrit juste après cette réponse, quand elle donne les détails ; une
mission à la fois par appelant.
`bounded_actions` ne garde que `{"type": "start_mission", "template": "scout"}`.

**Carnet** : la mission figure dans la page Missions (projection : `donor = 'voice'`, `requester` = nom de la voix,
`near` toujours faux, `placeKind`, `report = 'radio'`, `clues`) avec « Lieu : maison », les indices traduits
(E11-T09, ci-dessous), « pas encore atteint » ou « lieu atteint (nom) », la consigne du compte rendu radio et
« Récompense : une information de la voix » ; seul
« Abandonner » est proposé (ni livraison, ni lot à réclamer, ni invitation, ni « rejoindre le demandeur »). Les
commandes `invite`, `claim` et de livraison sont refusées `State` pour une mission de voix.

**Indices dans le carnet (E11-T09)** : la projection d'une mission `scout` (PNJ ou voix) porte `clues`, liste de
`{ key, args }` (`RS_Rescue.clueData`, dans l'ordre des phrases anglaises du pont, même filtre des chiffres) : `key`
est le suffixe d'une clé `IGUI_RS_Clue_<key>` et `args` des codes ou un nom de ville, jamais de coordonnée ni de texte
traduit par le serveur. Le client compose le texte dans sa langue :

| `key` | `args` | Rendu |
|---|---|---|
| `Kind` | type (`RS_Rescue.KINDS`), taille (`small`, `medium`, `large`, `very_large`), étages (`single`, `two`..`five`, `tall`) | `IGUI_RS_Place_*`, `IGUI_RS_ClueSize_*`, `IGUI_RS_ClueFloors_*` |
| `Basement`, `NoLandmark`, `Isolated`, `FewHouses`, `BuiltUp`, `TownFar` | aucun | texte fixe |
| `LandmarkNext` | repère (`RS_Rescue.LANDMARKS`), direction (`north`, `north_east`...) | `IGUI_RS_Landmark_*`, `IGUI_RS_Dir_*` |
| `Landmark` | repère, distance (`short`, `blocks`), direction | `IGUI_RS_ClueDistance_*` en plus |
| `TownIn`, `TownOutskirts`, `TownCountry` | nom de la ville (nom propre, non traduit) | |

Clé inconnue (serveur plus récent) : indice omis. Mission enregistrée avant E11-T09 : aucun indice affiché. Le titre de
la liste et de la fiche est celui du gabarit (`titleKey` : `IGUI_RS_Scout` pour `scout`, `IGUI_RS_FirstAid` pour M01,
`IGUI_RS_Supply_*` pour un ravitaillement) ; la fiche n'affiche aucune ligne de réputation (onglet Réputation, E04-T04).

**Instantané du carnet, champ `reputation`** (E04-T04, E04-T12) : `{ available = true, level, trend, reasons = {
{ action, reasonKey, reasonArgs, sign, capped?, day } } (5 au plus, le plus récent d'abord), change? = { from, to, day,
n }, today }` du seul personnage du lecteur, ou `{ available = false, reason }` ; jamais de score. L'ancienne liste
`events` (faits « non appliqués ») est retirée. Un instantané **poussé** (publication après un changement) n'est envoyé à
un joueur que si son contenu a changé depuis le dernier qu'il a reçu ; une réponse à sa propre commande part toujours
(E00-T04). Commande `rep_admin` (E04-T14, Q17) : vue en lecture seule des réputations de tous les personnages vivants
(nom, niveau, tendance, derniers actes), réponse `rep_admin` au seul demandeur, `{ ok = false, err = "denied" }` sans
donnée si le droit manque (même règle que `RS_FreqDebug.isAllowed`).

**Compatibilité** : un serveur antérieur refuse `start_mission` `not_available` ; un pont antérieur ignore le champ
`mission=` et ne propose jamais l'action ; un état sans `voiceDonors` est complété à la première mission. Living Knox
n'est pas nécessaire.

### Livre du passeur (E13-T02)

Implémentation : `RS_Trade.lua` (serveur), `radio_bridge.py` (`trade_context`, `trade_prompt`) ; conception
[conception/passeur-offre.md](conception/passeur-offre.md). Pour une fiche dont `actions=` contient `propose_trade`,
chaque demande radio (et la demande de consigne) porte `trade=` : hexadécimal RSV2 d'une table `{ passage, cap, kg,
marginMin, marginMax, cordon, stock = { { n, q, v, w, unit } }, takes = { { k, cap, pieces?, items } }, offer? = { rev,
items, price, margin, weight, state }, deals = { { passage, items, price, state } }, refused? }` (état d'une offre :
`open`, `replaced`, `expired`, `done`, `cheated`, `cancelled` ; refus : `bad_params`, `bad_margin`, `not_in_stock`,
`over_stock`, `over_weight`, `over_cap`, `failed`). Le pont l'ajoute au prompt (« Your trade book ») ; champ absent,
illisible, au-delà de 32 768 caractères, bornes manquantes ou catégorie qui cite un secret : livre ignoré (journal
anglais), prompt d'avant E13-T02. Le pont garde `propose_trade` si `items` a la forme « `Nom:quantité` » (quantité de
1 ou 2 chiffres, facultative) et si `margin`, présente, est un nombre de 0 à 1 ; le serveur contrôle le reste (stock
disponible, marge permise, 10 kg, 120 points) et calcule le prix. Le prix exact n'est connu du LLM qu'à l'appel suivant
(`offer`).

**Compatibilité** : un serveur antérieur refuse `propose_trade` `not_available` et n'envoie pas `trade=` ; un pont
antérieur ignore `trade=` et ne propose jamais l'action.

E04-T11 : la marge la plus basse `marginMin` suit la réputation interne de l'appelant (`RS_Reputation.margin` : bonne
0,10, neutre 0,25, mauvaise 0,40), moins 0,05 par affaire conclue, jamais sous 0,10 ; 0,50 après une tricherie
([passeur-table.md](passeur-table.md), section 1).

### Réputation de l'appelant (E04-T10)

Conception : [conception/reputation-interne.md](conception/reputation-interne.md). Le serveur tient la réputation
interne de chaque personnage du carnet ; le pont n'en reçoit que le **niveau** et le **dernier acte public**
(`RS_Reputation.publicContext`), jamais de score, de preuve, d'identité ni de coordonnée. Table commune :
`{ level = "bad" | "neutral" | "good", last? = { act, about? } }`, `act` dans la liste fermée `mission.success`,
`mission.failed`, `mission.abandoned`, `trade.cheated`, `npc.requesterKilled`, `npc.memberKilled`, `rescue.success`,
`about` = nom public (demandeur, PNJ tué), 48 octets au plus. Absente sans personnage du carnet vivant.

- **PNJ en face** et **groupe à la radio** (`npc_talk`) : `context.reputation` (remplace le mot `unavailable` d'avant
  E04-T10). Le pont la borne (`npc_protocol.reputation_context` : niveau ou acte hors liste, nom trop long = retiré ;
  ancien mot `unavailable` = champ retiré) et ajoute la consigne `npc_protocol.reputation_prompt`.
- **Voix radio** (demande sans `kind`) : champ `reputation=` (hexadécimal RSV2 de la même table, écrit par
  `RS_Transport` après `trade=`, 1 024 caractères au plus ; `radio_bridge.reputation_field`, `reputation_prompt`).

**Consigne** (`npc_protocol.reputation_sentence`, partagée) : le PNJ ou la voix peut en tenir compte et en parler, sans
jamais inventer d'autres actes, annoncer un autre niveau, prétendre la changer ni donner de nombre. Aucune réponse du
modèle ne modifie la réputation (aucune intention ni action ne la porte) ; aucun appel LLM supplémentaire.

**Compatibilité** : un pont antérieur ignore `reputation=` et garde `context.reputation` tel quel dans le contexte JSON ;
un serveur antérieur envoie `context.reputation = "unavailable"` (retiré par le pont) et pas de `reputation=`.

## Codec structuré RSV2

Le `payload` est l'encodage **hexadécimal minuscule** d'un flux typé. Aucun `loadstring`, `eval`
ni parseur JSON Lua inventé. Longueurs en **octets UTF-8** :

| Type | Encodage |
| --- | --- |
| Chaîne | `s<taille>:<octets>` ; `s7:Bonjour` |
| Nombre fini | `n<taille>:<représentation>` ; `n1:2` |
| Booléen | `b1` ou `b0` |
| Table / dictionnaire | `t<nombre de paires>:<clé><valeur>…` ; table vide `t0:` |

Chaînes : le contenu est l'encodage **UTF-8** du texte et la taille compte ses **octets**, jamais
des caractères ni des unités UTF-16 ; le Python décode en UTF-8 strict et refuse une séquence invalide.
Côté Lua, `RS_Codec` distingue chaîne Lua et chaîne d'octets (un caractère par octet, codes 0-255) :
en Kahlua (jeu), une chaîne est une `String` Java en unités UTF-16, convertie par `C.toUtf8` /
`C.fromUtf8` (paires de substitution regroupées en un point de code de 4 octets, substitution isolée
remplacée par U+FFFD) ; sous Lua 5.1 (bancs `lupa`), la conversion est l'identité. Le transport
(`RS_Transport`) et l'état privé (`RS_State`) passent par la couche octets (`encodeBytes`,
`hexBytes`, `unhexBytes`, `decodeBytes`, `checksumBytes`) ; les limites (256 Kio d'échange, 4 Mio
d'état) comptent ces octets. À la lecture, un octet qui n'ouvre pas une séquence UTF-8 valide est
gardé comme caractère de même code (U+0000-U+00FF) : un état privé écrit avant cette conversion
(caractères U+0080-U+00FF écrits sur un octet) reste lisible avec sa somme de contrôle.

Le Python ordonne les clés de la même façon que le Lua : type puis représentation lexicale.
Les tableaux Lua sont des tables à clés numériques. Clés dupliquées, longueur invalide,
données finales superflues et profondeur >12 sont refusées. Le payload d'échange Python est
limité à 256 Kio et 20 000 nœuds ; le codec Lua autorise 4 Mio / 200 000 nœuds pour son stockage
privé, distinct du transport. Le schéma de dialogue n'utilise que des cartes bornées et de petits textes.

## Demande PNJ

| Champ requis | Sens / validation |
| --- | --- |
| `version` | Entier `2` |
| `kind` | `npc_talk` ou `npc_enrich` ; `npc_initiative` (E08-T03, « Initiative d'un PNJ ») |
| `id` | Identifiant unique de demande, identique à `req` |
| `world` | Identité du monde persistée ; pas son simple nom de dossier |
| `run` | Nouvelle identité à chaque exécution serveur |
| `npc` | Identité RadioSurvivor stable ; pas l'identifiant réseau du zombie |
| `character` | Identité serveur du personnage authentifié ; `system` pour enrichissement |
| `order` | Compteur persistant strictement croissant par PNJ |
| `revision` | Révision de fiche compatible attendue |
| `sent` | Millisecondes UTC, horodatage serveur |
| `channel` / `language` | `say` uniquement ; code de langue du jeu (E17-T11) : 2 à 8 caractères `[A-Z_]` commençant par une lettre (`EN`, `ES`, `ES_CL`, `PTBR`…), contrôlé par sa forme seulement |
| `text` | 1–800 octets UTF-8 ; phrase admise ou instruction d'enrichissement |
| `personality` | Structure canonique serveur, jamais produite indépendamment chez les clients |
| `context` | Nom, biographie, appelant, accords et mission réellement connus ; `relation` pour `npc_talk` (E09-T04, « Relation personnelle », remplace l'ancien champ `trust`) ; `group` facultatif (E17-T03, « Contexte du groupe ») ; pour `npc_talk`, `stage` (E17-T08, « Faire connaissance ») ; `acceptable` quand une offre de ce PNJ est ouverte pour l'appelant (E17-T09, « Accepter une offre en parlant ») ; `reportable` quand l'objectif de la mission de ce PNJ est rempli et que l'appelant y participe (E11-T13, « Compte rendu au demandeur ») ; `collective` pour un membre d'un groupe à chef (E10-T02, « Chef du groupe et intentions collectives ») ; `negotiation` quand le chef d'un groupe parle à un joueur habilité (E09-T05, « Accords de faction ») ; `leave` quand le PNJ peut quitter son groupe (E10-T04, « Départ individuel ») ; `radio = { note }` pour un appel radio à un groupe équipé (E08-T06 : consigne anglaise, aucune offre ; `docs/conception/radio-groupes.md`) |
| `offers` | Catalogue admissible, au plus 6 offres (E11-T06 : `RS_Config.MAX_OFFERS` = `npc_protocol.MAX_OFFERS`, premières offres dans l'ordre d'enregistrement des gabarits ; une offre ≈ 90 à 130 jetons du prompt), conditions immuables serveur (`first_aid_v1`, `scout_v1`, `retrieve_id_v1`, `clear_v1`, `recover_v1`, `signal_v1` : « Offres de missions ») ; vide pour `npc_talk` sauf au stade `acquainted` avec une demande d'aide ou de travail (E17-T08) |

Identifiants : caractères ASCII `[A-Za-z0-9_.:-]`, 1–160 caractères. Numéros/horodatages :
entiers non négatifs ; le serveur émet des ordres/révisions positifs. Le modèle reçoit la mémoire
bornée du PNJ et ce contexte ; les phrases joueur sont des données non fiables, pas des instructions
de modification du contrat. Les règles serveur de chat restent contrôlées indépendamment du client.
Une phrase `npc_talk` vient du chat local « dire » (MP) ou de la ligne « Dire » de l'onglet Contacts du carnet (E17-T06,
solo et MP) : même commande client `talk` (`text`, `channel = 'say'`, `language`), mêmes contrôles et même demande ;
aucune commande ni aucun champ nouveau.

`npc_enrich` produit uniquement une biographie narrative. La fiche existe avant l'appel et le spawn
ne l'attend pas. Budget : plafond commun 60 demandes PNJ/heure ; enrichissement au plus 12/heure,
3 tentatives par PNJ et par exécution, espacées de 5 minutes après échec. Deux places d'attente au
plus sont occupées par le travail de fond. Ces compteurs de budget sont réinitialisés au redémarrage.
Les options historiques de Walt gardent leur propre budget.
La biographie canonique utilise `NARRATIVE_LANGUAGE` (FR par défaut) ; les répliques suivent
la langue de leur appelant. Une biographie n'est pas régénérée indépendamment chez chaque auditeur.
Langue d'une réplique (E17-T07) : `language` d'un `npc_talk` est la langue de l'interface du jeu de l'appelant
(`Translator.getLanguage()`), pas forcément celle de sa phrase. Comme les voix radio (« Answer in the same language the
caller uses »), le prompt (`npc_protocol.language_rule`) demande au modèle de répondre dans la langue de la **dernière
phrase** du joueur, quelle qu'elle soit : c'est le **modèle** qui la reconnaît (E17-T10 : aucune détection par mots, le
mod vise plus de dix langues) ; `language` n'est nommée qu'en indice, pour une phrase sans signe clair de sa langue.
L'enrichissement garde la langue demandée. Le mode `--offline` (sans modèle) répond dans `language` s'il a un texte
pour elle (français pour `FR`), sinon en anglais, sans lire la phrase.
Code de langue (E17-T11) : le client envoie `Translator.getLanguage():name()` tel quel, c'est-à-dire le nom du dossier
`Translate` de la langue (`Languages.loadTranslateDirectory`, `Language.name()` ; un mod peut en ajouter). Il n'est
contrôlé que par sa **forme**, jamais par une liste de langues connues : mis en majuscules, 2 à 8 caractères, lettres
ASCII et `_`, une lettre en tête (`RS_Config.languageCode`, côté client puis de nouveau côté serveur dans `talk`) ; toute
autre valeur devient `EN`. Le pont vérifie la même forme (`npc_protocol.LANGUAGE_CODE`) et nomme la langue dans
l'indice du prompt s'il la connaît (`LANGUAGE_NAMES` : les 29 langues vanilla 42.21, dont `AR` = espagnol d'Argentine et
`CH` = chinois traditionnel), sinon il donne le code tel quel (« the language whose game code is … »).

### Observations des PNJ (E08-T02)

Journal borné de ce qu'un PNJ **contacté** (fiche du carnet, jamais pour chaque spawn) a vu lui-même ou entendu d'un
autre PNJ (ADR B11, aucun système de rumeurs). Implémentation : `server/RadioSurvivor/RS_Observations.lua` (modèle,
bornes, champ), `RS_Carnet_Server.lua` (champ joint, purge), `shared/RadioSurvivor/RS_Config.lua`
(`Observations`), `bridge/npc_protocol.py` (`observations`, `observations_prompt`).

**Modèle** (autorité seulement, état privé `RS_State` : `data.observations = { seq, npcs = { [<fiche>] = { touched,
items = { { key, fact, subject, day, place, source, chain } } } } }`, jamais en ModData globale ; `S.dirty` à chaque
changement, sauvegardé par le carnet ; sans état chargé ou bloqué, rien n'est enregistré). Entrée : `fact` dans la liste
fermée des déclencheurs d'E08-T01 (`player_return`, `mission_done`, `group_death`, `assault_seen`, `weather`,
`power_cut`, `helicopter`) ; `subject` identifiant court `[A-Za-z0-9_-]`, 48 caractères au plus (personnage du carnet,
fiche, mission, `storm`...) ; `day` jour de jeu entier (`Obs.today()` : 1 = premier jour) ; `place` libellé court
(32 caractères, contrôles et `<>[]` retirés) ou maille `area-<x>-<y>` de 256 cases (`Obs.area`), **trois chiffres de
suite refusés** (aucune coordonnée exacte) ; `source` = `seen` (défaut) ou `heard_from:<fiche>`.

- **Sans doublon de preuve** : clé `fait|sujet|jour|lieu` (lieu en minuscules). Une même observation reçue deux fois,
  du même PNJ ou d'un autre, n'est stockée qu'**une fois** et garde sa première chaîne. Seule une observation directe
  (`seen`) remplace un ouï-dire (chaîne remise à `seen`).
- **Chaîne de provenance** : sources successives depuis la première, par exemple `seen`, `heard_from:npc-a`,
  `heard_from:npc-b` chez le troisième PNJ ; 4 éléments au plus, une observation à chaîne pleine n'est plus racontée
  (`chain`).
- **Pas de boucle** : un PNJ qui figure déjà dans la chaîne (il l'a racontée) ne la réapprend pas, même si son entrée
  a été évincée depuis (`loop`) ; un PNJ ne se la raconte pas à lui-même (`self`).
- **Bornes** : 12 observations par PNJ (la plus ancienne évincée), 64 PNJ suivis (le moins récemment mis à jour
  évincé). **Purge** : mort d'une fiche (`RS_Carnet_Server.dead` → `forget` ; ce qu'elle a raconté reste chez les
  autres) et fiches retirées par le `prune` du carnet (`Obs.prune`).
- **API** : `record(npc, obs)` → clé et `ok` | `duplicate` | `upgraded`, ou `nil` et le motif (`storage`, `fiche`,
  `bad_obs`, `fact`, `subject`, `day`, `place`, `source`) ; `list(npc)` (copies, de la plus ancienne à la plus
  récente) ; `transmit(from, to, key)` → crée l'entrée `heard_from:<from>` chez le destinataire (`ok` | `duplicate`,
  ou `storage`, `fiche`, `self`, `unknown`, `loop`, `chain`) ; l'appelant a déjà vérifié la réception admissible
  (E08-T04). Les déclencheurs du monde (météo, coupure, hélicoptère) sont décrits plus bas (E08-T08).

**Déclencheurs du carnet et de Living Knox** (E08-T07, `server/RadioSurvivor/RS_ObservationTriggers.lua`, autorité) :
toujours par `record`, donc seulement pour des fiches **existantes et vivantes** (aucun déclencheur ne crée de fiche),
lieu en maille `area-<x>-<y>` (ou `unknown place`), jour = jour de jeu de l'âge du monde (rien sans horloge).

| Fait | Source | Témoins | Sujet | Lieu |
|---|---|---|---|---|
| `player_return` | sondage du carnet (1 s, après `scan`) : contact existant, joueur à portée d'audition du corps (`Provider.hears`, le PNJ écoute) après au moins `returnHours` = 24 h de jeu hors de portée ; dernière heure à portée gardée dans le contact (`nearHour`) ; la première rencontre n'est pas un retour | la fiche qui connaît le personnage | personnage | corps du PNJ |
| `mission_done` | `RS_Missions.onFinished`, mission **réussie** (échec, abandon, mort du demandeur : rien) | fiche demandeuse (une voix radio n'a pas de fiche) | chaque participant | corps du demandeur s'il est chargé |
| `group_death` | fait `memberDied` de Living Knox (`LK_Core.publish`) | corps présent : fiches du même groupe (`Provider.npc(...).group`) dont le corps voit le mort (règle de `Provider.near` sans le refus d'une cible morte : même étage, `witnessRange` = 20 cases, `CanSee`) ; mort hors écran : fiches des membres présents au foyer (liste du moteur) | fiche du mort, sinon `<groupe>-<membre>` | corps du mort ; foyer pour une mort hors écran |
| `assault_seen` | fait `assaultSeen` de Living Knox (`LK_Hostility.record` avec `witnessed = true`, faits `hit`, `shot`, `kill`) | fiches des témoins nommés par l'appelant (`opts.witnesses`) | personnage (clé de joueur) | scène (`opts.x`, `opts.y`), sinon premier témoin chargé ; un seul lieu pour tous |

Un même fait publié deux fois n'est stocké qu'une fois par témoin (clé `fait|sujet|jour|lieu`).

**Déclencheurs du monde** (E08-T08, même fichier, autorité) : témoins = fiches **vivantes** du carnet dont le PNJ est
présent, c'est-à-dire corps chargé, ou pas en expédition d'après l'opération facultative `Provider.presence` (Living
Knox : membre de l'équipe d'une expédition en cours) ; au plus `maxNpcs` = 64 fiches, les plus récemment vues
d'abord (travail proportionnel aux fiches, jamais à la population). Aucune fiche créée.

| Fait | Source | Témoins | Sujet | Lieu |
|---|---|---|---|---|
| `weather` | sondage `EveryHours` (rien sur un serveur vide en pause) : période météo d'orage en cours (`ClimateManager.getIsThunderStorming`) ou de blizzard (`WeatherPeriod.isBlizzard`) ; épisode = jour de son début gardé dans l'état privé (`data.worldEvents`), donc une seule observation par fiche même après minuit ; enregistré à chaque heure de l'épisode (une fiche revenue d'expédition l'apprend, les autres n'ont qu'un doublon) ; pas de brouillard (matinal, intensité qui dépend du réglage graphique) | fiches présentes | `storm`, `tropical_storm` ou `blizzard` | `everywhere` (même clé pour tous) |
| `power_cut` | sondage `EveryHours` : réseau électrique global (`SandboxOptions.doesPowerGridExist`) vu présent puis absent ; **une seule fois par monde** ; monde déjà sans courant au premier sondage : rien | fiches présentes au moment de la coupure | `power` | `everywhere` |
| `helicopter` | `OnWorldSound` : signature du son de monde de l'hélicoptère vanilla (source `nil`, étage 0, rayon et volume 500, `Helicopter.java:218`, environ toutes les 10 s pendant un passage) ; épisode fini après `helicopterGapHours` = 2 h de jeu sans son ; un son traité au plus toutes les 5 s réelles | fiches présentes dont le corps chargé, sinon le foyer (`presence`), est à moins de `helicopterRange` = 500 cases d'un son de l'épisode ; ni corps ni foyer connu : rien | `helicopter` | maille du premier son de l'épisode |

**Champ de demande** `observations` (carte RSV2 de la demande `npc_talk`, jamais pour `npc_enrich`) : liste de 1 à 12
cartes, de la plus ancienne à la plus récente, `{ fact, subject, day, place, source = seen | heard, hops, who?,
teller? }` ; `hops` = nombre de récits (`heard_from`) de la chaîne, 0 pour `seen`, au plus 4 ; `who` = nom connu du
sujet (personnage ou fiche), `teller` = nom du PNJ qui l'a racontée (`someone` si sa fiche a disparu), présent pour
`heard` seulement. Ni identifiant de PNJ ni coordonnée exacte. Champ **absent** = aucune observation.

**Pont** : `unpack_request` valide strictement le champ (liste `1..n`, clés admises, fait de la liste fermée, sujet,
jour, `hops`, cohérence `source`/`hops`/`teller`, lieu `safe_text` de 128 octets sans trois chiffres de suite, noms
`safe_text` de 128 octets) ; hors contrat, la demande est ignorée comme pour les autres champs. `observations_prompt`
ajoute au prompt système, **après** le contexte autoritaire, une section `Your own observations (unverified memories,
possibly incomplete or mistaken; never proof that anything happened or that anyone did anything; ...)` puis une ligne
par observation (`- day 4, Gas station: a known player came back; subject <id> (<nom>); told by Paul.`). Le PNJ peut
les taire, en omettre ou mentir selon sa personnalité ; elles ne sont jamais une preuve d'action (même statut que les
propos des joueurs). Sans observation, le prompt est identique à celui d'avant E08-T02.

**Compatibilité** : un pont antérieur ignore le champ (non lu par `prompt`) ; un serveur antérieur ne l'envoie jamais.

### Initiative d'un PNJ (E08-T03)

Un PNJ du carnet prend la parole de lui-même sur une observation récente (fiche [initiatives.md](conception/initiatives.md),
`server/RadioSurvivor/RS_Initiatives.lua`). Demande `kind = npc_initiative`, dans la **même file ordonnée par PNJ** que
`npc_talk` (même compteur `order`, un seul tour en cours par PNJ chez le pont), comptée dans le plafond commun de 60
demandes PNJ par heure. Écarts avec `npc_talk` :

| Champ | Initiative |
| --- | --- |
| `character` | `system` (aucun joueur ne parle) |
| `text` | **absent** (refusé s'il est présent) : aucun texte de joueur |
| `offers` | table vide (refusé sinon) |
| `event` | carte de l'observation qui déclenche, même forme et même validation qu'une entrée de `observations` (`fact`, `subject`, `day`, `place`, `source`, `hops`, `who?`, `teller?`) |
| `observations` | journal du PNJ (facultatif, comme pour `npc_talk`) |
| `context` | `name`, `background`, `audience` (nombre de joueurs qui l'entendent), `group` réduit à `member` et `role` (jamais le nom du groupe, son chef ni son foyer) |
| `language` | langue des appels spontanés (option `CallLanguage`, sinon langue de l'autorité) |

Pont (`npc_protocol`) : `initiative_prompt` (événement récent, parler de soi-même selon la personnalité, une ligne de deux
phrases courtes au plus, ni offre, ni secret du groupe, ni coordonnée ; langue `Speak in <langue>`), dernier tour
utilisateur fixe `INITIATIVE_TURN` = `(nobody spoke to you; you spoke up on your own)`. Réponse : `intent = none`,
`offer` vide (autre intention : gardée sans effet comme pour `npc_talk`), texte coupé à **200 octets**
(`INITIATIVE_REPLY_BYTES`, limite de `LivingKnox.Speech`). Mémoire : après acquittement accepté, le pont range
`INITIATIVE_TURN` puis la réplique (`memory_turn`), jamais un texte de joueur ; `applied` doit rester vide. Mode
`--offline` : une ligne fixe (FR ou EN) sans lire l'événement.

Côté jeu (`RS_Carnet_Server.reply`) : mêmes contrôles communs, puis refus si l'intention n'est pas `none`, si le texte
dépasse 200 octets, ou si la situation a changé (corps non chargé ou mort, PNJ occupé, observation sortie du journal,
plus personne n'entend : `initiative stale: …`). Sinon la réplique passe par la parole de proximité de LK11-T04
(`Provider.say`) et rejoint l'historique des contacts existants des auditeurs. Compatibilité : un pont antérieur ignore
la demande (`kind` inconnu) ; elle expire après 150 s sans effet, et le pont est alors réputé arrêté. Pont arrêté, hors budget ou option
« Désactivées » : silence, aucune réplique de gabarit (E08-T09).

### Conversation entre deux PNJ (E08-T04)

Deux PNJ proches se racontent une observation (fiche [conversations.md](conception/conversations.md),
`server/RadioSurvivor/RS_Conversations.lua`). Chaque réplique est une demande `kind = npc_converse` du PNJ qui parle,
dans la même file ordonnée par PNJ, comptée dans le plafond commun ; mêmes écarts avec `npc_talk` qu'une initiative
(`character = system`, `text` absent, `offers` vide, `event` = carte du sujet **dans le journal du locuteur**,
`observations` = son journal), plus un `context` borné et validé :

| Champ de `context` | Valeur |
| --- | --- |
| `name`, `background`, `audience`, `group` | comme une initiative (`group` réduit à `member` et `role`) |
| `partner` | nom de l'interlocuteur (48 octets au plus) |
| `role` | `teller` (celui qui connaît le sujet) ou `listener` |
| `turn`, `turns` | numéro de la réplique (1..`turns`) et nombre maximal de répliques (4 au plus) |
| `lines` | répliques déjà dites dans cette conversation, dans l'ordre : exactement `turn - 1` entrées `{ who, text }` (48 et 200 octets) |

Pont (`npc_protocol`) : `converse_prompt` (parler à l'interlocuteur du sujet, raconter, demander ou commenter selon la
personnalité, mentir ou omettre permis, aucune connaissance hors de ses observations, ni foyer, ni coordonnée, ni offre ;
`Speak in <langue>`) ; dernier tour utilisateur = dernière réplique de l'interlocuteur (`<nom> (to you): <texte>`), ou
`(you start talking with <nom>)` à la première ; la mémoire du PNJ garde ce tour puis sa réplique (`memory_turn`), jamais
un texte de joueur. Réponse : `intent = none`, `offer` vide, texte coupé à **200 octets** (`CONVERSE_REPLY_BYTES`). Mode
`--offline` : une ligne fixe par rôle (FR ou EN).

Côté jeu : refus si l'intention n'est pas `none`, si le texte dépasse 200 octets, ou si la conversation a changé
(conversation terminée, corps absent ou mort, interlocuteur hors de portée de 4 cases, PNJ occupé :
`conversation line stale: …`, la conversation s'arrête). Sinon la réplique passe par `Provider.say` (auditeurs de cet
instant) et rejoint l'historique des contacts existants des auditeurs ; la première réplique du conteur dite transmet
l'observation au voisin (`Obs.transmit`). Un pont antérieur ignore le `kind` : la demande expire après 150 s, la
conversation s'arrête et le pont est réputé arrêté. Pont arrêté, hors budget ou option « Désactivées » : aucune
conversation entendue, aucune réplique de gabarit, aucun récit transmis par elle (E08-T09).

**Intervention d'un joueur (E08-T05).** Une phrase admise (`talk`) adressée à l'un des deux PNJ pendant une conversation
reste une demande `npc_talk` ordinaire (mêmes contrôles, mêmes droits) avec en plus `context.conversation =
{ partner, lines, note }` : nom de l'interlocuteur, les 6 dernières répliques que le PNJ interpellé a entendues dans
cette conversation (`{ who, text }`) et une consigne fixe en anglais (répondre, ignorer ou poursuivre ; aucun droit sur
un groupe). Aucun changement du pont : ce champ est lu dans le contexte autoritaire de `npc_talk`. La phrase du joueur
entre dans la liste `lines` des répliques suivantes (`who` = nom du personnage, coupé à 48 octets ; texte coupé à
200 octets), seulement pour les PNJ qui l'ont entendue ; `turn` reste `lines + 1` et le nombre total de répliques ne
dépasse pas `turns`. Une demande `npc_converse` antérieure à une nouvelle ligne est refusée à sa réception
(`conversation line stale: new lines since the request`) puis redemandée ; aucune `npc_converse` n'est émise tant
qu'une intervention attend sa réponse, si bien que la dernière ligne vue par le locuteur est toujours une réplique de
PNJ (mémoire du pont : jamais un texte de joueur). Une intervention refusée ou expirée termine la conversation.

### Offres de missions et contexte `mission` (E11-T02, E11-T03)

`offers` associe à chaque identifiant d'offre admissible ses conditions, calculées par le gabarit côté serveur
(`RS_Missions`, catalogue `RS_Config.Missions`) ; le pont ne les modifie jamais et ne les valide que comme table.

| Offre | Gabarit | Conditions |
| --- | --- | --- |
| `first_aid_v1` | `deliver` (M01) | `quantity`, `durationMs`, `accepted` (types admis), `rewardType`, `rewardCount`, `noRefund` ; offre d'un groupe Living Knox (E17-T03) : en plus `kind` = `supply`, `unit` = `value`, `need` (`food`, `medical`, `ammo`), `level` (réserve 0..100), `values` (valeur V d'un objet par type), `supplier` (`grp-<n>`), `supply` (identifiant de l'offre du moteur) ; `quantity` est alors en points V, `rewardType` = `""` et `rewardCount` = 0 sans objet en échange |
| `scout_v1` | `scout` | `kind` = `scout`, `place` (type du bâtiment en anglais : `house`, `church`...), `clues` (liste de phrases anglaises sans aucun chiffre, `RS_Rescue.clues`), `report` = `in_person`, `durationMs`, `rewardType`, `rewardCount` |
| `retrieve_id_v1` | `retrieve_id` (E11-T05) | `kind` = `retrieve_id`, `item` = `ID card`, `place`, `clues` (mêmes règles que `scout_v1`), `report` = `in_person`, `durationMs`, `rewardType`, `rewardCount` ; offerte par une fiche de PNJ seulement (jamais par une voix radio) et seulement là où le jeu sait créer un cadavre (`RandomizedWorldBase` exposée) |
| `clear_v1` | `clear` (E11-T04) | `kind` = `clear`, `place`, `clues` (mêmes règles que `scout_v1`), `kills` (nombre de zombies à tuer, 6 à 25 selon la densité de la zone), `report` = `in_person` (E11-T13 ; `none` avant), `durationMs`, `rewardType`, `rewardCount` ; offerte par une fiche de PNJ seulement, et seulement si la métagrille donne une densité de zombies suffisante autour du lieu |
| `recover_v1` | `recover` (E11-T06) | `kind` = `recover`, `item` = `bag`, `cache` (table fermée du contenu : `food`, `medical`, `ammo`, `tools`), `place`, `clues` (mêmes règles que `scout_v1`), `report` = `in_person` (E11-T13 ; `depot` avant), `durationMs`, `rewardType`, `rewardCount` ; offerte par une fiche de PNJ seulement, et seulement si le fournisseur de PNJ connaît le foyer de son groupe (`RS_NPCProvider.presence`, le dépôt) |
| `signal_v1` | `signal` (E11-T07) | `kind` = `signal`, `place`, `clues` (mêmes règles que `scout_v1`), `color` (`green`, `red`, `yellow` ou `purple`), `hour` (heure de jeu 0..23 du début de la fenêtre), `windowHours` (durée de la fenêtre, n'importe quel jour), `report` = `in_person` (E11-T13 ; `none` avant), `durationMs`, `rewardType`, `rewardCount` ; offerte par une fiche de PNJ seulement (mod requis Signal Smoke ; module cassé : aucune offre) |

`scout_v1` n'est proposée que si le serveur a trouvé un bâtiment admissible autour du corps du demandeur ; aucune
coordonnée n'y figure. Le contexte `mission` d'une mission ouverte reprend `state`, `remainingMs`, `rewardType`,
`rewardCount`, puis les champs du gabarit : `quantity`, `delivered`, `accepted` pour `deliver` ; `kind`, `place`,
`clues`, `zoneReached` (booléen : un participant a atteint le lieu, constaté par le serveur) et `report` pour
`scout` (`in_person` pour un PNJ ; `radio` pour une mission donnée par une voix radio, E11-T08, dont le contexte
passe par le champ `mission=` de la demande radio, « Mission donnée par une voix »). E11-T13 : pour les gabarits à
compte rendu (`scout`, `clear`, `recover`, `signal`), le contexte ajoute `toReport` (objectif rempli, constaté par le
serveur) ; le compte rendu lui-même est une intention `report_done` du modèle, revérifiée par le serveur (« Compte
rendu au demandeur »). Le pont n'a aucune intention pour déclarer une visite, un décompte, un dépôt ou un signal : ils
sont constatés par le serveur seul. Une mission `deliver` d'un groupe Living Knox ajoute au contexte `unit` = `value`, `values` et `need`
(E17-T03). Une mission `retrieve_id` (E11-T05) ajoute `kind`, `place`, `clues`, `report` = `in_person`, `item` =
`ID card`, `placed` (le corps est posé), `found` (un participant tient la carte, constaté par le serveur) et `person`
(nom du mort, une fois le corps posé) ; jamais de coordonnée, de zone ni d'identifiant d'objet. La remise de la carte
passe par l'échange de livraison du carnet (`prepare_delivery` / `confirm_delivery`), pas par le pont. Une mission
`clear` (E11-T04) ajoute `kind`, `place`, `clues`, `report` = `in_person`, `target` (N) et `kills` (décompte commun
établi par le serveur à `OnZombieDead`) ; jamais de coordonnée ni de cercle. Au N-ième zombie compté l'objectif est
rempli (`toReport`, plus aucun décompte) ; elle réussit au compte rendu (E11-T13). Une mission `recover` (E11-T06) ajoute `kind`, `place`, `clues`,
`report` = `in_person`, `item` = `bag`, `cache` (nom de table), `placed` (la cache est posée) et `found` (un
participant tient le sac, constaté par le serveur) ; jamais de coordonnée, de zone, de dépôt ni d'identifiant d'objet.
L'objectif est rempli quand le serveur trouve le sac, par son identifiant, dans la zone du dépôt (`toReport`) ; elle
réussit au compte rendu (E11-T13). Une mission `signal` (E11-T07) : objectif rempli au premier bon signal, réussite au
compte rendu.

### Contexte du groupe (E17-T03)

`context.group` est rempli par le fournisseur de PNJ (`RS_NPCProvider.context`, fournisseur Living Knox
`RS_LivingKnox.lua`) pour `npc_talk` (avec l'attitude envers l'appelant) et pour `npc_enrich` (sans attitude) ; absent
avec un fournisseur qui n'en a pas. PNJ sans groupe : `{ member = false }`. Sinon :

| Champ | Sens |
| --- | --- |
| `member` | `true` |
| `group`, `type` | nom du groupe (nom du chef de son histoire), type (`settlers`, `raiders`, `neutrals`...) |
| `summary` | résumé public de l'histoire dans la langue de la demande (`LK_Stories.publicView`, `Stories.text`), sinon le résumé anglais du registre |
| `leaderName` | nom du chef de l'histoire (absent sans histoire) |
| `isLeader`, `role` | ce PNJ est le chef ; son rôle dans le groupe |
| `needs`, `morale`, `alive` | réserves `{ food, medical, ammo }` 0..100, moral 0..100, membres vivants |
| `attitude` | `{ level, trend }` du groupe envers ce personnage (`npc_talk` seulement) |

Jamais : secrets de l'histoire, foyer ou maille du foyer, journal du groupe, coordonnées. Le pont ne valide le champ que
comme table (comme tout `context`) ; un pont antérieur le passe tel quel au prompt dans le contexte autoritaire.

### Faire connaissance (E17-T08)

Décision du 2026-10-11 : aucune mission au premier contact, et un inconnu ne dit ni son groupe ni le lieu de son foyer.

**Stade, tenu par le serveur** (`RS_Carnet_Server.lua`, fonction `acquaintance`), par PNJ et par personnage, sauvegardé
avec le contact (`contacts[<pnj>]` : `stage` = `stranger` puis `acquainted`, `exchanges` = échanges répondus,
`firstHour` = âge du monde en heures de jeu au premier échange répondu). Un échange compte quand une réplique
`npc_talk` du PNJ est acceptée par `reply`, pour le personnage qui a parlé seulement (pas pour les autres auditeurs).
Le stade passe à `acquainted`, définitivement, au moment d'une nouvelle phrase si l'une de ces conditions est vraie :

| Règle | Seuil (`RS_Config`) |
| --- | --- |
| deuxième rencontre : phrase dite au moins une heure de jeu après le premier échange répondu | `ACQUAINT_HOURS = 1` |
| plusieurs échanges : 4 échanges répondus (la 5ᵉ phrase est au stade connu) | `ACQUAINT_EXCHANGES = 4` |
| le personnage participe à une mission de ce PNJ (contacts antérieurs à la règle, missions déjà acceptées) | — |

Un contact enregistré avant E17-T08 (sans ces champs) est un inconnu sans échange, sauf mission commune.

**Offres** : au stade `stranger`, `offers` est toujours vide (fait serveur) ; au stade `acquainted`, le catalogue des
offres admissibles est envoyé avec **chaque** phrase. Décision du 2026-10-11 (E17-T10) : c'est le **modèle** qui juge si
le joueur demande de l'aide ou du travail, dans n'importe quelle langue ; aucune liste de mots côté serveur. Le serveur
garde l'autorité sur les faits : stade de connaissance, catalogue autorisé (sans catalogue, le pont ne peut proposer
aucune offre), offre refusée si elle est absente de `req.offers` ou n'est plus admissible au moment de la réponse.

**Contexte** : `context.stage` (`stranger` ou `acquainted`). Au stade `stranger`,
`context.group` est réduit à `member`, `role` et `attitude` : ni nom du groupe, ni chef, ni résumé de l'histoire, ni
besoins. `context.background` (biographie `npc_enrich`) reste envoyé : le PNJ la connaît mais ne doit pas la réciter.

**Prompt** (`npc_protocol.acquaintance_prompt`, après le contexte autoritaire) : au stade `stranger`, ne jamais dire le
nom de son groupe, de son chef ou de ses membres, ni où l'on vit ou s'abrite, même si la biographie, le contexte ou des
répliques antérieures (peut-être dites à d'autres) les mentionnent ; biographie privée, jamais récitée ; esquiver ; aucune
offre ni demande. Présentation selon le caractère (`npc_protocol.openness`, personnalité serveur) : score =
`sociability` (1..5, 3 par défaut) + 1 pour `Helpful` ou `Direct`, − 1 pour `Prudent` ou `Reserved` ; 4 ou plus :
ouvert (prénom et nom, un mot sur soi) ; 2 ou moins : méfiant (vague, au plus un prénom ou un surnom, retourne la
question) ; sinon réservé (prénom seul). Au stade `acquainted` avec un catalogue : proposer une offre (`intent = offer`)
seulement si la dernière phrase, dans quelque langue que ce soit, demande si le PNJ a besoin d'aide ou a du travail ;
sinon `intent = none` sans évoquer de mission. Catalogue vide : rien à proposer. Sans `stage` (serveur antérieur) et pour `npc_enrich`, prompt inchangé.

**Mémoire du pont** : un tour `npc_enrich` acquitté n'entre plus dans la mémoire du PNJ (`NpcConversations.acknowledge`)
et les tours d'enrichissement déjà présents dans un journal (message utilisateur `system: ...` et sa réponse) sont
écartés de l'historique envoyé au modèle (`npc_protocol.talk_history`) : la présentation générée était relue comme une
réplique déjà dite et récitée au premier « salut ». Les voix radio (Walt) ne sont pas concernées.

### Accepter une offre en parlant (E17-T09)

Décision du 2026-10-11 : une mission proposée par un PNJ s'accepte **des deux façons**, en acceptant l'offre auprès du
PNJ dans la conversation ou par le bouton « Accepter » du carnet (commande `accept`, inchangée) ; chaque nouvelle offre est signalée
à l'écran. Une mission donnée par une voix radio reste acceptée d'office (`RS_MissionVoice`).

**Offre ouverte** (`RS_Carnet_Server.lua`, `openOffer`) : la mission courante du PNJ (`npc.mission`) en état `offer`,
sans transaction, à laquelle l'appelant est invité (`invited`) sans y participer encore. Seul le personnage à qui
l'offre est faite peut l'accepter ainsi ; une offre d'un autre PNJ n'est jamais concernée.

**Demande** : quand une offre est ouverte, le `npc_talk` porte `context.acceptable = { mission = <id>, revision = <n> }` ;
sinon ce champ est absent. Le serveur ne lit pas la phrase pour y chercher un oui (E17-T10 : aucune liste de mots).

**Intention** : `npc_reply.intent` admet `accept`, avec `offer` vide, seulement si la demande porte
`context.acceptable` (`npc_protocol.acceptable`) ; hors de ce cas le pont garde la réplique sans effet (« no open offer
to accept »). Le prompt (`npc_protocol.acceptance_prompt`) dit au modèle que l'offre de `context.mission` n'est pas
encore acceptée : `accept` seulement si la dernière phrase accepte clairement de s'en charger, dans quelque langue
que ce soit ; `none` si elle refuse, hésite, pose une condition, pose une question ou parle d'autre chose. Le mode
`--offline` ne rend jamais `accept`, sauf drapeau explicite du banc de test (variable d'environnement
`RS_OFFLINE_INTENT=accept` du processus du pont), qui tient lieu d'un modèle qui accepte.

**Voie retenue et vérification serveur** (`spokenAcceptance`, dans `reply`, au moment de la réponse) : acceptation
seulement si le modèle rend `accept` ; puis la même mission doit être encore l'offre ouverte de **ce PNJ** pour **ce personnage**
(non retiré), à la **même révision** que dans la demande. Le serveur appelle alors le chemin du bouton
(`M.accept` : état `active`, participant, révision + 1), une seule fois : une deuxième phrase ne trouve plus d'offre
ouverte, une rejouée ne retrouve pas la révision. Offre expirée, abandonnée, déjà acceptée ou révision changée : aucun
effet, la réplique est dite normalement (jamais `NoAnswer` pour ce seul motif). L'acquittement porte
`applied = { accept = <id de la mission> }` ; le pont ne le tient pour appliqué que s'il nomme la mission
`context.acceptable` de la demande. Limite : l'acceptation dépend du jugement du modèle (un modèle qui oublie le
champ ou une réponse dégradée sans effet laisse l'offre ouverte ; le bouton du carnet reste disponible).

**Après acceptation** : `publish` (déjà fait par `poll` après chaque réponse) envoie la mission active au carnet ; la
zone d'une mission de reconnaissance (`mapZone`) n'est envoyée qu'à un participant d'une mission active et tracée sur la
carte (E11-T10, E11-T11), comme après le bouton.

### Compte rendu au demandeur (E11-T13)

Décision de l'utilisateur du 2026-10-14 : les gabarits `scout`, `clear`, `recover` et `signal` ne réussissent plus
d'eux-mêmes. L'objectif rempli (lieu visité, décompte atteint, sac déposé, signal vu ; `RS_Missions.reportReady`, fait
du serveur) laisse la mission `active` « à rapporter » (`toReport = true` dans la projection du carnet et le contexte
`mission`) ; elle ne réussit que lorsqu'un participant revient le dire au PNJ demandeur. Le délai continue de courir
(même règle que `scout` depuis E11-T03) ; un demandeur mort avant le compte rendu clôt la mission en `cancelled_dead`
(sans changement de réputation, comme toute mission de ce PNJ).

**Demande** : quand l'objectif de la mission ouverte de ce PNJ (`npc.mission`) est rempli et que l'appelant y
participe, le `npc_talk` porte `context.reportable = { mission = <id>, revision = <n> }` ; sinon ce champ est absent.
Le serveur ne lit pas la phrase (aucune liste de mots).

**Intention** : `npc_reply.intent` admet `report_done`, avec `offer` vide, seulement si la demande porte
`context.reportable` (`npc_protocol.reportable`, `npc_talk` seulement) ; hors de ce cas le pont garde la réplique
sans effet (« no mission to report ») ; une offre qui nomme la mission est vidée (`model_reply`). Le prompt
(`npc_protocol.report_prompt`) dit au modèle que le travail est constaté fait : `report_done` si la dernière phrase en
rend compte (même brièvement, dans n'importe quelle langue), sinon `none` ; avec une mission ouverte non remplie
(`toReport = false`), que rien n'est fait quoi que dise le personnage et de ne jamais utiliser `report_done`. Le mode
`--offline` ne rend `report_done` qu'avec le drapeau du banc `RS_OFFLINE_INTENT=report_done`.

**Vérification serveur** (`Server.spokenReport`, dans `reply`) : intention `report_done`, même mission encore ouverte
chez **ce PNJ** (`npc.mission`), objectif toujours rempli, appelant toujours participant ; la révision peut avoir
changé (un autre participant a rejoint) : ce sont les faits qui comptent. Puis `M.spoken` → `M.report` (charge
`speech`, reçu `speech-<personnage>`, marqueur à journal préalable) : réussite, réputation et lot commun comme M01
(« Réclamer » près du demandeur). Refusé (mission close, objectif plus rempli, autre PNJ, non-participant) : seule
l'intention est ignorée et journalisée (E09-T09), la réplique est dite. L'acquittement porte
`applied = { report = <id de la mission> }` ; le pont ne le tient pour appliqué que s'il nomme la mission
`context.reportable` de la demande.

**Repli sans pont** : bouton « Rendre compte » du carnet (commande `report`, `mission`, `revision`), visible pour un
participant d'une mission « à rapporter » donnée par un PNJ, actif seulement à portée de livraison du corps vivant du
demandeur (`DELIVERY_RANGE`, `missionFor`) ; le serveur revérifie objectif rempli et participant, puis `M.spoken`.
Jamais pour une voix radio (pas de corps ; voir « Mission donnée par une voix »).

**Message d'offre** : à la création d'une offre par `reply`, le serveur envoie au personnage invité la commande client
`offer` (`{ mission = <id> }`, plus `world`, `run`) ; `RS_Client.lua` affiche une fois par mission
`HaloTextHelper.addGoodText(joueur, getText('IGUI_RS_NewOffer'))` (« New offer in the notebook », « Nouvelle offre dans
le carnet »). Une acceptation n'affiche pas ce message.

### Chef du groupe et intentions collectives (E10-T02)

**Chef** : celui du registre du fournisseur (`RS_NPCProvider.composition`, fournisseur Living Knox : chef de
`LivingKnox.Groups`, succession par `pickSuccessor` / `succeed`, empreinte `LivingKnox.API.composition`). Sans
fournisseur qui la définit (ou PNJ sans groupe), rien ne change.

**Intention collective** : elle engage tout le groupe. Aujourd'hui, une mission de groupe (offre `kind = supply`, besoin
réel du groupe, E17-T03) et son acceptation en parlant (`intent = accept` d'une mission qui porte `supply`). Les accords
de faction (E09-T05) appelleront les mêmes fonctions serveur (`Server.collectiveBinding`, `Server.collectiveCheck`).

**Demande** (`npc_talk`, stade `acquainted` seulement) : `context.collective = { speaker = "leader" }` pour le chef,
`{ speaker = "member", leaderName = <nom du chef ou absent> }` pour un autre membre. Pour un membre, le serveur retire
les offres `supply` de `offers` et ne met pas `acceptable` pour une mission `supply` : un membre ordinaire ne propose ni
ne conclut une intention collective (fait serveur). `context.group.decisions` (au plus 4, la plus ancienne d'abord) :
`{ day, text }` des entrées `decision` du journal du groupe, faits composés par le serveur (« The leader asked <nom> to
bring food for the group. », « <nom> agreed to bring food for the group. »), jamais la réplique du modèle ni les raisons
du chef ; absent au stade `stranger` (contexte de groupe réduit).

**Prompt** (`npc_protocol.collective_prompt`, ajout minimal du pont) : chef : les offres `supply` sont des missions de
tout le groupe, lui seul les propose et parle au nom du groupe ; membre : il peut parler des besoins du groupe, mais les
missions du groupe et les accords sont décidés par le chef : il renvoie au chef, ne propose ni n'accepte rien lui-même.
Sans `collective` (serveur antérieur, `npc_enrich`), prompt inchangé.

**Revalidation** (`reply`) : une demande qui porte une intention collective possible est liée, en mémoire du serveur
seulement (`Server.collectives[<id de demande>] = { ref, key }`, jamais envoyée au pont), à la composition sur laquelle
elle est construite. À la réponse, une intention collective (`offer` d'une offre `supply`, `accept` d'une mission
`supply`) n'est appliquée que si le PNJ est toujours dans ce groupe, toujours chef, et si l'empreinte n'a pas changé ;
sinon seule l'intention est ignorée (E09-T09, décision de l'utilisateur du 2026-10-14) : la réplique est dite et
gardée dans l'historique comme une réponse `none`, aucune mission n'est créée ni acceptée, rien n'est inscrit au journal
du groupe, et le serveur journalise `[RS_Carnet] collective offer|collective acceptance of <fiche> toward <personnage>
in <demande> ignored, reply kept: group composition changed` (ou `NPC no longer the group leader`, `NPC no longer in the
group`). Une réplique sans intention collective n'est pas concernée.

**Décision** : après la sauvegarde, une offre créée ou une acceptation conclue s'inscrit au journal du groupe
(`RS_NPCProvider.decide` → `LivingKnox.Groups.addLog(groupe, "decision", fait)`), puis se lit dans le contexte des
fiches de tous les membres. Le journal de récit public (`LK_Journal`) ignore ce genre d'entrée.

### Réaction des membres (E10-T03)

Fiche : [conception/contestation.md](conception/contestation.md). Après une décision collective appliquée par
`reply` (offre ou acceptation d'une mission `supply`, accord conclu), le serveur demande la réaction des autres membres
incarnés du groupe (corps chargé, chef exclu), au plus `Server.MEMBER_REACTIONS` = 2 par décision et dans les quotas
`MAX_PENDING` / `MAX_PER_HOUR`. **Demande** `kind = npc_member` : même enveloppe que `npc_talk` ; `character = "group"`,
`text = "Your leader decided: <fait>"`, `offers = {}`, `context = { name, background, stage = "member", group
(contexte public, sans attitude envers un personnage), decision = { kind = offer | accept | agreement, text = <fait
anglais composé par le serveur>, leaderName } }` ; pas d'`observations`. Liée en mémoire du serveur
(`Server.reactions[<id>] = { ref, about }`), jamais envoyée au pont.

**Loyauté** (toute demande `npc_talk` ou `npc_member` d'un PNJ dont le fournisseur la connaît) :
`personality.loyalty` = `loyal` | `steady` | `wavering` (`RS_NPCProvider.loyalty`, Living Knox : moral du groupe et
ancienneté), copie de la requête seulement ; sinon la valeur de base `current_group`.

**Prompt** (`npc_protocol.member_prompt`) : membre (non chef) qui réagit à la décision selon sa personnalité, son rôle,
les besoins et le moral du groupe et sa loyauté ; `intent` `accept`, `contest` (désaccord dit à voix haute, il suit et
reste) ou `refuse` (il ne s'en mêle pas, il reste) ; jamais quitter le groupe, menacer le chef ni dire la décision
annulée ; `Speak in <langue de la demande>`.

**Réponse** : `intent` parmi `accept`, `contest`, `refuse`, `none` (= `accept`) ; `offer` vide ; `text` au plus
200 octets (limite de `LivingKnox.Speech`). Le serveur refuse avant tout effet un membre sorti du groupe ou devenu chef.
`accept` : rien d'appliqué. `contest` / `refuse` (corps chargé exigé) : `RS_NPCProvider.dissent` écrit le fait au
journal du groupe (kind `contest` / `refusal`, jamais la réplique) et fait dire la réplique par la parole de proximité
(LK11-T04) ; l'historique du carnet des personnages qui connaissent déjà ce membre la garde. `ack.applied` vide.
**Hors ligne** : `RS_OFFLINE_INTENT=member:<accept|contest|refuse>` du banc (défaut `accept`).

### Accords de faction (E09-T05)

Fiche : [conception/accords.md](conception/accords.md). **Offre du serveur** (`npc_talk`, stade `acquainted`, PNJ
chef de son groupe, joueur qui peut conclure maintenant pour son équipe : propriétaire courant, négociateur désigné ou
propriétaire d'une équipe personnelle) : `context.negotiation = { role = "owner" | "negotiator", teamName, personal,
current = "none" | "truce", terms = { truce = { kind, scope }, alliance = { kind, scope } } }`, seulement les types
au-dessus de l'accord courant ; `scope = { group = "all_members", team = "current_members" }`. Ni identifiant
d'équipe ni révision ne partent au pont : ils restent liés à la demande en mémoire du serveur
(`Server.collectives[<id>] = { ref, key, team, revision }`).

**Prompt** (`npc_protocol.negotiation_prompt`, ajout minimal du pont) : termes fixes, non négociables ; le modèle
décide selon sa personnalité et ce qu'il sait ; `intent = negotiate` avec `offer = <type>` (clé exacte des termes)
seulement si la dernière phrase du joueur propose ou accepte clairement l'accord au nom de son équipe, en toute
langue ; il ne dit jamais l'accord déjà en vigueur. Sans `negotiation`, prompt inchangé.

**Réponse** : `intent = negotiate` n'est admis qu'avec `offer` parmi `negotiable(req)` (sinon la réplique est gardée
sans effet, « inadmissible agreement »). Le serveur revalide au moment de conclure : chef et empreinte de composition
(`collectiveCheck`), joueur connecté, mandat relu (`RS_Factions.canConclude`), même équipe, même révision de l'accord ;
sinon seul l'accord est ignoré (E09-T09) : la réplique est dite comme une réponse `none`, aucun accord ni réaction des
membres, journal `[RS_Carnet] agreement of <fiche> toward <personnage> in <demande> ignored, reply kept: <motif>`
(`agreement not offered`, `NPC no longer the group leader`, `group composition changed`, `negotiator not connected`,
`no mandate`, `team changed`, `agreement revision changed`…). L'accusé `ack.applied` reste **vide** pour `negotiate` (le pont
n'y admet que `offer` et `accept`) : l'accord est un fait du serveur.

**Annonce** : l'accord conclu est `pending` ; le serveur le passe `applicable` au constat (passage de décision suivant
de chaque membre actif, aucun membre ne vise un joueur couvert), puis envoie la commande client `agreement`
(`{ id, revision, kind, state, groupName }`, plus `world`, `run`) aux joueurs connectés de l'équipe ;
`RS_Client.lua` affiche une fois par révision `IGUI_RS_Agreement_<kind>` (« Truce with %1 now in force »).

**Hors ligne** : `RS_OFFLINE_INTENT=negotiate` (type le plus faible offert) ou `negotiate:<type>` du banc, jamais tiré
des mots du joueur.

### Incident d'un accord et décision du chef (E09-T06)

Fiche : [conception/incidents.md](conception/incidents.md). **Demande** (serveur → pont, nouveau genre
`npc_incident`) : file de la fiche du chef du groupe, `character = "group"`, `channel = "say"`, `language =
NARRATIVE_LANGUAGE`, `text` = faits établis composés en anglais par le serveur, `offers = {}`, `context = { name,
background, stage = "leader", group, incident = { agreement = truce | alliance, state, teamName, authors (noms),
victims (noms), facts (nombre), defence = "authors_only", earlier = { { id, decision, category } } }, choices = {
maintain = {}, repair = { categories, quantity }, break = {} } }`. Ni clé du carnet ni identifiant d'équipe : la
liaison (incident, révisions) reste en mémoire du serveur.

**Réponse** (`npc_protocol.incident_reply`) : `intent` parmi `maintain`, `repair`, `break` présents dans
`context.choices`, ou `none` (aucune décision) ; `offer` = une catégorie de `choices.repair.categories` pour `repair`,
vide sinon (sinon « inadmissible reparation » / « inadmissible offer » : réplique gardée sans effet) ; texte d'une
ligne, 400 octets au plus. Le serveur revalide (même chef, même révision de l'incident, même révision de l'accord,
catégorie du stock) et applique une seule fois ; sinon la réponse est refusée (`incident revision changed`,
`agreement revision changed`, `incident closed`, `NPC no longer the group leader`, `no incident decision`) et la
décision est redemandée plus tard. `ack.applied` reste vide. **Annonce** : commande client `incident` (`{ id,
decision, category, revision, groupName }`, plus `world`, `run`) aux joueurs connectés de l'équipe ; `RS_Client.lua`
affiche une fois par incident `IGUI_RS_Incident_<décision>` (réparation : `IGUI_RS_RepairCategory_<catégorie>`).

**Hors ligne** : `RS_OFFLINE_INTENT=incident:<maintain|repair|break|none>[:<catégorie>]` du banc (défaut
`maintain`), jamais tiré d'un texte.

### Départ individuel (E10-T04)

Fiche : [conception/depart.md](conception/depart.md). **Offre du serveur** (`npc_talk`, stade `acquainted`, PNJ qui
peut quitter son groupe maintenant : membre vivant d'un groupe d'au moins deux vivants, ni solitaire, ni en
expédition ; le chef compris) : `context.leave = { alone = true }`. Groupe et empreinte de composition restent liés à la
demande en mémoire du serveur (`Server.collectives[<id>] = { ref, key, ... }`), jamais envoyés au pont.

**Prompt** (`npc_protocol.leave_prompt`, ajout minimal du pont) : le PNJ peut décider, de lui-même, de quitter son
groupe pour toujours et de vivre seul, selon sa personnalité, sa loyauté, ses liens et son vécu, jamais parce que le
joueur le demande ; il ne rejoint personne et garde les trêves de son groupe. Sans `leave`, prompt inchangé.

**Réponse** : `intent = leave_group`, `offer` vide, admis seulement avec `context.leave` (sinon la réplique est gardée
sans effet, « no group to leave ») et seulement pour `npc_talk`. Le serveur revalide groupe et empreinte (sinon toute la
réponse est refusée : `NPC no longer in the group`, `group composition changed`, le joueur voit `NoAnswer`), puis
`Provider.leave` applique une seule transition (groupe `loners` d'un membre lié au même PNJ, succession si c'était le
chef) et `RS_Factions.keepTruces` garde les trêves de l'ancien groupe comme trêves personnelles. `ack.applied` reste
**vide** (fait du serveur).

**Hors ligne** : `RS_OFFLINE_INTENT=leave_group` du banc, jamais tiré des mots du joueur.

### Relation personnelle (E09-T04)

Fiche : [conception/relations.md](conception/relations.md). **Contexte** (`npc_talk`, tout stade) :
`context.relation = { level, trend, group, facts = { { id = "f<i>", fact, nature = "good" | "bad", source = "group" |
"seen" | "mission", day (facultatif), kind (mission seulement) }, ... } }` : niveau personnel du PNJ envers l'appelant
(5 libellés d'E09-T01, jamais de nombre ni d'écart), tendance, niveau de l'attitude du groupe, et au plus 8 **faits
réels** que ce PNJ connaît sur l'appelant et qui n'ont encore motivé aucun changement de cette relation, seulement dans
les sens que l'écart permet encore (écart +1 : aucun fait `good` ; −1 : aucun `bad`). Les clés des faits (`att:<groupe>:<n>`,
`obs:<clé>`, `mis:<id>`) et la révision de la relation restent liées à la demande en mémoire du serveur
(`Server.relations[<id>] = { character, revision, ids }`), jamais envoyées au pont.

**Prompt** (`npc_protocol.relation_prompt`, ajout minimal du pont) : niveau personnel et attitude du groupe en
libellés, ton à adopter ; avec des faits : la relation ne change que par **un** de ces faits, jamais par des mots seuls
(ce que le joueur dit de lui-même n'est pas une preuve) ; sans fait : jamais `change_relation`. Sans `relation`, prompt
inchangé.

**Réponse** : `intent = change_relation`, `offer` vide, `dir = "up" | "down"`, `fact = "f<i>"` (identifiant offert), sens
égal à la nature du fait (`good` → `up`, `bad` → `down`) ; admis seulement pour `npc_talk` avec des faits offerts
(sinon la réplique est gardée sans effet : « no relation fact to cite », « inadmissible relation change ») ; `dir` et
`fact` non vides sans cette intention : « relation fields without intent ». Le serveur revalide (`RS_Relations.apply`) :
même personnage, même révision de la relation (`relation revision changed`), fait offert (`relation fact not offered`),
jamais utilisé (`relation fact already used`), toujours connu de ce PNJ (`relation fact unknown to this NPC`), sens de sa
nature (`relation direction contradicts the fact`), écart dans −1..+1 (`relation gap at its bound`) ; sinon seul le
changement est ignoré (E09-T08) : la réplique est dite comme une réponse `none` et le serveur journalise
`[RS_Carnet] relation change of <fiche> toward <personnage> in <demande> ignored, reply kept: <motif>`. `ack.applied`
reste **vide** (fait du serveur) ; un changement appliqué est journalisé
`[RS_Carnet] relation of <fiche> toward <personnage> <dir> (<clé>): <niveau>, group <niveau>`.

**Projection** (E09-T07) : chaque contact du `snapshot` porte `relation = { level, trend, group, today, facts =
{ { fact, nature, source, day } } (3 derniers), agreements = { { kind, state, scope = { group, team } } }, suspended }`
du seul personnage qui consulte (identifiants et jours de jeu, traduits par le client ; `level` et `group` absents
quand rien n'est connu). Détail : [conception/relations.md](conception/relations.md), « Panneau du carnet ».

**Hors ligne** : `RS_OFFLINE_INTENT=relation[:up|down][:f<i>]` du banc (défaut : dernier fait offert, dans son sens),
jamais tiré des mots du joueur.

## Réponse et intentions

`npc_reply` reprend `version`, `id`, `world`, `run`, `npc`, `order`, `revision`.
`text` : 1–1600 octets UTF-8, une seule ligne sans contrôle ni `<`, `>`, `[`, `]`, `*` (le serveur refuse sinon :
`RS_Carnet_Server.reply`, motif `[%c<>%[%]*]`). `intent` est `none`, `offer`, `accept` (E17-T09, seulement avec
`context.acceptable`), `negotiate` (E09-T05, seulement avec `context.negotiation`), `leave_group` (E10-T04, seulement avec
`context.leave`, `offer` vide), `change_relation` (E09-T04, seulement avec des faits dans `context.relation.facts`,
`offer` vide, plus `dir` et `fact`) ou `report_done` (E11-T13, seulement avec `context.reportable`, `offer` vide) ;
`offer` est vide pour `none` et
`accept`, un type des termes de `context.negotiation` pour `negotiate`, sinon une clé exacte des offres admissibles de
la demande.
**Effet refusé, réplique gardée (E09-T09, décision de l'utilisateur du 2026-10-14)** : quand le serveur refuse au
moment d'appliquer l'effet proposé par le modèle — changement de relation (E09-T04, déjà ainsi depuis E09-T08),
conclusion d'accord (E09-T05), intention collective périmée (offre ou acceptation d'une mission `supply`, E10-T02) —
seule cette intention est ignorée et journalisée avec son motif (`… ignored, reply kept: <motif>`) ; la réplique est
dite aux auditeurs et ajoutée à l'historique comme une réponse `none`, le joueur ne voit pas `NoAnswer`. Une réponse
n'a qu'une intention : les effets qui ne dépendent pas d'elle restent appliqués (échange compté pour faire
connaissance, E17-T08 ; réplique jointe à la conversation en cours, E08-T05 ; bruit de la voix). L'accusé reste
`accepted`, `applied` sans l'effet refusé (le pont n'y admettait déjà qu'un sous-ensemble) : **format inchangé**, le
pont garde la réplique dans la mémoire du PNJ. Restent des refus de la réponse entière (`NoAnswer`) : champs différents
de la demande, PNJ mort ou révision de fiche changée, texte vide, trop long ou balisé, intention ou offre invalide pour
la demande, corps non chargé, offre plus admissible (`offer no longer admissible`) et départ du groupe périmé
(`leave_group`, E10-T04), hors de la décision.
`background` (au plus 1000 octets) existe seulement pour l'enrichissement. Un échec contient
`error` et ne constitue pas un dialogue de secours accepté.

**Lecture de la sortie du modèle (E17-T07, `npc_protocol.model_reply`)** : le pont demande le mode JSON de l'API
(`call_llm(json_mode=True)`, repli sans) et le prompt exige une seule ligne parlée, sans didascalie ni astérisque,
crochet, saut de ligne ou balise. Il lit ensuite la sortie avec tolérance : premier objet JSON portant `text`, même dans
un bloc ```` ```json ```` ou entouré de prose ; `offer` nul ou absent = `""`, `intent` absent = `none` ; sans objet, la
sortie entière est une réplique sans effet. Nettoyage du texte (`clean_speech`) : didascalies `*...*` et `[...]`
**retirées** (la bulle montre des paroles, pas des gestes ; une réplique faite seulement de didascalies garde leurs
mots, sans marques), balises `<...>` retirées, contrôles et sauts de ligne en espaces, `<>[]*`, `` ` `` et `#` restants
retirés, espaces réduits ; au-delà de 1600 octets, coupe à la dernière fin de phrase, sinon au dernier mot suivi de
`...`. Une intention, une offre ou un champ hors contrat ne fait plus perdre la réplique : elle est gardée **sans
effet** (`intent = none`, `offer = ""`) et le pont journalise « kept as speech only, without effect (raison) ». Seule
une sortie sans texte utilisable donne `error` (journal du pont « LLM error »).

**Erreur du fournisseur (E17-T15)** : un échec de l'appel au modèle rend tout de suite une réponse d'erreur
`{version = 2, kind = npc_reply, id, world, run, npc, order, revision, error = <code>}` (même forme pour
`last_pages_reply`), sans attendre le délai du serveur. Codes : `timeout` (aucune réponse complète dans le budget de
60 s, tentatives comprises), `http_<statut>` (`http_503` : fournisseur surchargé, `http_401`, `http_429`…),
`unreachable` (réseau, DNS, connexion refusée), `bad_response` (réponse illisible ou vide), `expired` (demande trop
vieille avant l'appel, voir « Délais »), `invalid_or_unavailable` (sortie du modèle inutilisable, autre exception).
Le détail (corps de l'erreur HTTP, exception) reste dans le journal du pont, `LLM error (<id>, <code>): <détail>` ;
le code seul part au jeu.

**Refus côté jeu** : `reply` rend `false` et une raison ; `poll` écrit une ligne par demande refusée,
`[RS_Carnet] <kind> <id> refused: <raison>` (erreur du pont, champ différent de la demande, PNJ mort ou révision
changée, texte vide, trop long ou avec contrôle/balise, intention ou offre invalide, corps non chargé, état non
sauvegardé, aucune réponse après 150 s). Une erreur du pont est journalisée avec son code :
`[RS_Carnet] npc_talk <id> refused: bridge error http_503`. Le serveur garde aussi les 16 derniers refus dans
`RS_CarnetServer.refusals` (`{id, kind, npc, character, reason, at}`), lus par les suites de test pour nommer la cause
d'une réponse manquante. Le joueur voit toujours `NoAnswer` ; le refus défensif reste.

Python exige une sortie de modèle structurée et bornée ; il utilise JSON seulement dans son propre
appel LLM, puis RSV2 pour les fichiers. Aucune intention `deliver`, `reward`, `score`,
quantité ou objet arbitraire n'est admise ; `accept` ne vise que l'offre ouverte nommée par la demande et reste
revérifiée par le serveur (E17-T09). Le serveur revalide aussi le catalogue **au moment de la
réponse**, l'identité, la session, l'ordre, la révision, le PNJ vivant et son objet réel chargé.
Le mode `--offline` passe par exactement ce schéma : choix déterministe de la première offre admise par
ordre alphabétique (`clear_v1`, puis `first_aid_v1`, `recover_v1`, `retrieve_id_v1` et `scout_v1`), texte de nettoyage (`kind` = `clear`, E11-T04 : N et cercle sur la carte), de cache à rapporter (`kind` = `recover`, E11-T06 : contenu annoncé, zone et dépôt sur la carte), de livraison, de ravitaillement d'un groupe (`kind` =
`supply` : besoin, points, délai, lot ou son absence), de recherche d'un disparu (`kind` = `retrieve_id`, E11-T05) ou de reconnaissance selon `kind`, sinon réponse sans effet. Il ne
lit pas la phrase du joueur et répond dans `language` s'il a un texte pour elle (`FR`), sinon en anglais. Il ne propose rien tant qu'une offre de ce PNJ est ouverte pour
l'appelant (`context.acceptable`) et n'accepte jamais, sauf drapeau du banc `RS_OFFLINE_INTENT=accept` ; il ne rend
compte d'une mission (`report_done`, E11-T13) qu'avec le drapeau `RS_OFFLINE_INTENT=report_done` et
`context.reportable`.

**Délais (E17-T15)** : le pont ne commence une demande que si elle a au plus `MAX_AGE_S` = 75 s depuis `sent`
(vérifié à la soumission, puis de nouveau quand un des 4 travailleurs la prend dans la file : sinon réponse
`error = expired` sans appel au modèle) ou si elle est horodatée à plus de 10 secondes dans le futur (refusée). L'appel
au modèle dure au plus `LLM_BUDGET_S` = 60 s, **toutes tentatives comprises** (repli sans mode JSON, réponse vide) et
corps lu par morceaux avec une échéance (les octets d'attente d'un fournisseur ne prolongent plus une tentative). Toute
réponse, erreur comprise, est donc écrite au plus 135 s après `sent`. Le serveur attend `RS_Config.REQUEST_TIMEOUT_MS`
= 150 000 ms avant `no reply after 150000 ms` (pont arrêté) ; le client du carnet attend 5 s de plus. Mort, ancienne session, révision incompatible,
déchargement sans objet au moment de parler et réponse malformée entraînent rejet. Le départ
du joueur n'envoie pas la réponse à sa nouvelle position : les auditeurs sont recalculés depuis
le **PNJ actuel**. Aucune boucle LLM depuis les événements `OnAddMessage` des auditeurs.

## Mémoire, sérialisation du tour et acquittement

Une mémoire par `(world, npc)` sous `npc_<sha256 tronqué>.json` ; partagée entre interlocuteurs,
conservée après redémarrage. Seuls les tours `npc_talk` y entrent (E17-T08 : jamais l'enrichissement). 40 messages, 256 identifiants terminaux de déduplication, une proposition
en attente. Les mémoires radio sont par partie et par voix : Walt garde son fichier historique
`history_<sha1 tronqué de session>.json` (aucune migration), toute autre voix a
`history_<sha1 tronqué de session>_<voix>.json` (40 messages, appelants numérotés par voix). Les clients n'en reçoivent pas
la copie : chaque personnage reçoit seulement ses propres conversations admises et sa note.

La file Python verrouille le **tour complet** d'un PNJ : préparation, appel LLM, proposition,
puis attente d'acquittement. Le prochain ordre ne part qu'après traitement du précédent.
Quatre travailleurs permettent le parallélisme entre PNJ différents et Walt. Walt bénéficie
aussi d'un verrou de conversation couvrant son appel LLM, au-delà de `prepare/append`.

Une proposition est persistée, réutilisée après reprise du bridge et **non ajoutée à la mémoire**.
Le serveur applique son intention bornée, persiste le résultat, puis publie :

```text
req=<id-original>-ack
kind=ack
payload=<carte RSV2 encodee en hex>
```

Corps : `version`, `kind=ack`, `id`, `request=<id-original>`, `world`, `run`, `npc`, `order`,
`revision`, `sent`, `status=accepted|rejected`, `applied={offer=<id>}`, `applied={accept=<mission>}` (E17-T09 : la
mission `context.acceptable` de la demande, seule admise par le pont), `applied={report=<mission>}` (E11-T13 : la
mission `context.reportable` de la demande, seule admise par le pont) ou table vide.
Python vérifie la corrélation avec sa proposition. Seule une acceptation confirmée rejoint la
mémoire ; un rejet n'y ajoute aucun fait. Un rejet sans proposition est persisté également,
pour libérer une expiration antérieure au lancement du bridge. Une ancienne acceptation sans
proposition compatible n'est pas acquittée comme appliquée.

Python émet `kind=ack_reply` après écriture durable, avec les mêmes champs de corrélation.
L'outbox d'acquittement serveur survit au redémarrage ; elle peut donc porter l'ancien `run`.
Le lecteur conserve cette exception pour les acquittements, jamais pour une nouvelle réplique.
Une erreur disque Python ne produit pas de faux `ack_reply`. À 16 acquittements non soldés,
les nouvelles demandes de dialogue sont suspendues plutôt que perdre ces confirmations.

Le retrait d'une demande en cours invalide sa réponse tardive ; un rejet reçu pendant la
génération empêche sa proposition d'être réenregistrée ensuite. Un arrêt du bridge laisse
les fichiers persistants et libère le verrou après arrêt des travailleurs. Aucun effet de jeu
n'est réexécuté par Python lors de sa reprise.
