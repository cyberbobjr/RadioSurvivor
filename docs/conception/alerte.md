# Alerte de proximité d'un groupe : zombies et intrus

- Tâches : LK05-T08 (création) ; suite : LK05-T09 (défense coordonnée, après le combat LK06), portes refermées (point d'entrée `Alert.subscribe`, côté `LK_Obstacles`)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-11 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Alert.lua` (`LivingKnox.Alert`, autorité seulement), appelé par `LK_Decisions.lua` (comportement `alert`), cri joué par `media/lua/client/LivingKnox/LK_AlertView.lua` (`LivingKnox.AlertView`). Entrées : [perception.md](perception.md) (`Senses.perceived`), [attitude.md](attitude.md) (`Hostility`). Sorties : [decisions.md](decisions.md) (cascade), [parole.md](parole.md) (`Speech.bark(…, "alert")`), [consignes.md](consignes.md) (`face`, `moveTo`), gestes (`LivingKnox.Anim`).

## Problème

Quand un membre voit ou entend une menace près du foyer ou de lui (zombie, joueur hostile ou inconnu du groupe), tout le groupe doit réagir : les tâches et le sommeil s'arrêtent, chacun se tourne vers l'endroit où la menace a été vue, quelqu'un crie. L'alerte ne doit partir qu'**une fois par menace**, retomber avec le temps et rendre le groupe à sa routine. Le serveur décide ; deux joueurs proches voient et entendent la même chose.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Cri du joueur : `WorldSoundManager.addSound(personnage, x, y, z, 30, 30, …)` ; accroupi 6, mégaphone 90 ; voix `VoiceMaleShoutHey`/`VoiceFemaleShoutHey` (`distanceMax = 150`) par `transmitPlayerVoiceSound`. | `J/characters/IsoGameCharacter.java:4810-4888` ; `J/characters/IsoPlayer.java:6644-6653` ; `media/scripts/generated/sounds/player/sounds_player_voice_male.txt:153-161`, `…_female.txt:133-141` ; base `sounds-and-noise.md` | confirmé statiquement |
| `addSound(source, x, y, z, rayon, volume)` sur le serveur : bruit relayé aux connexions concernées (`GameServer.sendWorldSound`, `RelevantTo`), donc aussi aux zombies simulés par un client. | `J/Lua/LuaManager.java:9239-9241` ; `J/WorldSoundManager.java:107-150` ; `J/network/GameServer.java:3042-3053` | confirmé statiquement |
| Un bruit de rayon < 50 n'atteint pas les zombies virtuels ; l'étage compte ×3. | base `staging-effects.md` (« Attirer des zombies avec un bruit ») | confirmé statiquement |
| Aucun son n'est joué par un serveur (`playVocals`, émetteur factice) : la voix doit être jouée par chaque client. | `J/characters/CharacterSoundEmitter.java:65-68` ; `J/characters/IsoGameCharacter.java:786` | confirmé statiquement |
| Émetteur d'un personnage : `playSoundImpl(String, IsoObject)` seule surcharge à deux arguments, sans paquet ; émetteur libre : `(String, nil)` choisit la surcharge `IsoGridSquare` (NPE), utiliser `(String, false, nil)`. | `J/characters/CharacterSoundEmitter.java:190-201` ; `fmod/fmod/FMODSoundEmitter.java:431-490` ; base `kahlua-lua.md` | confirmé statiquement |
| Une consigne `face` ou `stop` remet le geste au repos (`LK_Directives.issue`) : le geste d'alerte se pose après la consigne. | `LK_Directives.lua` (fonction `issue`) | confirmé par le banc |
| Zombie en solo : `onlineId` = −1 ; la perception ne transporte que cet identifiant. | `LK_Senses.lua` (`zombieKey`) ; [perception.md](perception.md) | confirmé statiquement |

## Choix (2026-10-11)

### Menaces qui donnent l'alerte (`Alert.threatsOf`)

| Genre | Qui | Près du membre (distance perçue) | Près du foyer (écart x et y, ±1 étage) | Niveau | Bruit du cri |
|---|---|---|---|---|---|
| `zombie` | zombie vu ou entendu ; clé `z:<onlineId>`, sans identifiant (solo) clé commune `z?` | ≤ 10 | ≤ 15 | 45 | 15 |
| `intruder` | joueur **inconnu** du groupe (aucune paire d'attitude : aucun fait vu ni attribuable, ou aucune identité de personnage du carnet) ou envers qui le groupe est méfiant (`wary`) ; clé `p:<compte>` | ≤ 8 | ≤ 12 | 50 | 20 |
| `hostile` | joueur dont le niveau d'attitude est `hostile` (paire, ou niveau de départ du type : un inconnu pour des pillards) | ≤ 20 | ≤ 25 | 80 | 30 |

Appel à l'aide (LK06-T05, [fuite-reddition.md](fuite-reddition.md)) : un coup accepté sur un membre note l'agresseur par `Alert.raise` (même traitement qu'une menace observée, extrait d'`Alert.observe`), clé `help:<clé>`, genre `hostile` (joueur) ou `zombie`, journal du groupe « called by m-<k> ».

Un joueur connu prudent, favorable ou confiant ne donne pas l'alerte. « Connu » = `Hostility.isKnown(gid, clé)` (ajout de lecture seule à `LK_Hostility`). PNJ rivaux : non perçus (perception), donc jamais menace.

### Une seule fois par menace, niveau qui retombe (`Alert.note`, `Alert.update`)

- Chaque clé de menace est gardée **60 minutes de jeu** (`FORGET_MIN`) après sa dernière observation (32 au plus par groupe).
- Groupe calme + menace **nouvelle** → alerte **déclenchée** (`raised`) : cri, entrée `alert` au journal du groupe, journal du moteur, écouteurs `raised`. Menace **déjà connue** revue après le calme → alerte rallumée **sans** cri ni écouteur (`resumed`).
- Pendant une alerte : même menace → niveau rafraîchi (`seen`) ; autre menace nouvelle → `joined` (niveau + 10, `EXTRA`), sans cri ; menace plus grave que celle de l'alerte (zombie < intrus < hostile) → `escalated` : nouveau cri, écouteurs `raised`.
- Niveau : porté au niveau du genre (au plus 100), il perd **5 par minute de jeu** (`DECAY`) depuis la dernière observation ; à **10** ou moins (`CALM`) l'alerte retombe (`Alert.update`, à chaque passage du cadre de décision : journal, écouteurs `calm`). Un zombie vu puis disparu : 7 minutes de jeu ; deux zombies : 9 ; un hostile : 14 (à 1 h de jeu par jour réel, une minute de jeu ≈ 2,5 s).
- Dernière position connue (I2.4) : position de la menace la plus grave observée en dernier, partagée par tout le groupe.
- Mémoire seulement (alertes, menaces connues) : un redémarrage les oublie.

### Effets (cascade de [decisions.md](decisions.md))

- LK05-T14 ([decisions.md](decisions.md), « Seuils de danger réglables ») : un zombie perçu à plus de `LivingKnox.ZombieAlertDistance` cases (défaut 10) du membre n'est jamais une menace d'alerte, même près du foyer ; `REACH` (option `AlertReach`, défaut 20) et `SHOUT.zombie` (option `AlertShoutZombie`, défaut 10) sont réglables ; sans les options, valeurs ci-dessous.
- Membres concernés : incarnés, à 30 cases au plus (`REACH`, un étage = 3 cases) de l'endroit d'où la menace a été vue ou de sa dernière position, ou au foyer.
- Un membre qui perçoit lui-même la menace garde la règle `threat` existante (`watch`, ou `flee` pour un membre aux constantes mauvaises trop proche, LK06-T07). Les autres prennent le comportement **`alert`** (règle `threat`, rang 1) : tâches, corvées et sommeil **interrompus** (`Routines.leave` remet debout, compteur `Alert.stats.woken`), vigilance `guard` (portée par la consigne `vg` en MP), consigne `face` vers la dernière position connue (renouvelée si elle tourne de 30° ou plus), geste **`guard`** (membre valide) ou **`crouch`** (constantes mauvaises : blessé, apeuré ; LK06-T07, avant : selon le rôle) ; un tel membre loin du foyer y **court** d'abord. Le même geste accompagne `watch` pendant une alerte ; il est retiré quand le membre quitte `alert`/`watch`. Durée d'un état `alert` : 2 minutes, recalculé ensuite.
- Alerte retombée : `ctx.alert` vide, la cascade reprend la routine (sommeil, corvée, poste).
- Besoins : `alert` compte comme activité « guet » (`LK_Needs`).

### Cri (`Alert.cry`, au déclenchement seulement)

Par le membre qui a vu la menace : réplique `alert` du catalogue (`Speech.bark`, portée 30, bulle aux seuls auditeurs) ; bruit `addSound(nil, x, y, z, r, r)` avec r = 15 (zombie), 20 (intrus), 30 (hostile) ; voix `VoiceMaleShoutHey` ou `VoiceFemaleShoutHey` selon le sexe du membre, envoyée en MP par une commande `alertCry` (module `LivingKnox`, `{ c = { id, gid, npc, o, x, y, z, s, k } }`) aux destinataires du relais des consignes (`Directives.targets` : joueurs à 100 cases et propriétaire), en solo par appel direct de `AlertView.receive`. Le client ignore un identifiant déjà reçu et ne joue que les deux voix connues, sur l'émetteur du corps s'il le connaît, sinon sur un émetteur libre à la position du cri.

Rayon : le cri vanilla d'un joueur vaut 30. Pour un zombie, crier aussi fort attirerait au foyer tous les zombies réels à 30 cases pour chaque zombie aperçu ; on retient 15 (avertissement à voix forte, assez pour le foyer), 20 pour un intrus, 30 (comme un joueur) pour un hostile. Tous restent sous 50 : aucun zombie virtuel n'est attiré.

### Portes refermées et autres sous-systèmes

`LivingKnox.Alert.subscribe(nom, { raised = function(gid, info, event) … end, calm = function(gid, info) … end })` (un même nom remplace l'écouteur ; `Alert.unsubscribe(nom)`). `raised` part au déclenchement et à l'aggravation (`event` = `"raised"` ou `"escalated"`), `calm` à la retombée. `info` = `{ id, gid, kind, key, label, x, y, z (dernière position connue), level, since, threats, spotter, origin = { x, y, z }, home }`. Une erreur d'écouteur est isolée (`pcall`), journalisée et comptée (`stats.listenerErrors`). Lecture : `Alert.get(gid)`, `Alert.isActive(gid, minute)`.

Portes refermées (branché le 2026-10-11, `LK_Obstacles.lua`, section « alerte ») : écouteur `"doors"` (`Obstacles.hookAlert`, appelé au chargement et à chaque passage des obstacles : l'ordre de chargement de `LK_Alert` et `LK_Obstacles` est indifférent). À `raised` ou `escalated`, `Obstacles.onAlert` note une demande par foyer (bâtiment du foyer du groupe ; foyer hors bâtiment : rien) sans toucher aucune porte ; le passage suivant des obstacles la traite par `shutHome`, le code de la fermeture à l'arrivée (LK04-T10) : portes extérieures **ouvertes** du foyer au niveau du foyer, liste figée au premier essai, hors portes ouvertes par le module pour un PNJ en route (refermées derrière lui) ; fermée seulement si ses deux cases sont libres, qu'elle n'est sur le trajet d'aucun PNJ à ce passage et qu'elle n'est pas obstruée ; verrouillée si un membre porteur de la clé est au foyer (LK04-T12), sinon fermée seulement (et verrouillée plus tard par `securePass`) ; nouvel essai toutes les `SHUT_RETRY_MS`, abandon (WARN) après `SHUT_GIVE_UP_MS` ; jamais barricadée, détruite, double, de garage ni cadenassée. Journal : `group grp-N: alert al-… raised: open exterior doors of its home to be closed`, puis `… closed and locked (alert al-… raised)`. Une demande en cours par foyer au plus ; une porte rouverte ensuite reste ouverte jusqu'à la prochaine alerte déclenchée ou aggravée (pas de bataille avec un joueur). Compteur `Obstacles.stats.alertShuts`.

### MP

Aucune décision côté client (le fichier serveur s'arrête sur un client MP ; `AlertView` ne fait que jouer la voix reçue). Deux clients proches reçoivent la même commande `alertCry` (même identifiant, une fois chacun), la même bulle (`Speech`, une commande par auditeur), les mêmes consignes et la même vigilance (relais des consignes), le même geste (relais des gestes, `LK_Relay`).

## Alternatives écartées

- **Alerte par menace sans fenêtre** : un zombie qui entre et sort du champ de vision crierait à chaque fois ; la clé gardée 60 minutes l'empêche.
- **Un cri par menace nouvelle pendant l'alerte** : une petite horde ferait crier sans arrêt ; seul le passage à une menace plus grave relance le cri.
- **Niveau en temps réel** : les autres sous-systèmes (décisions, besoins) comptent en minutes de jeu ; une vitesse de jeu accélérée raccourcit l'alerte comme le reste.
- **Cri de rayon 30 pour tout** : attire trop de zombies au foyer pour un seul zombie aperçu (voir plus haut).
- **Voix jouée par le serveur** ou `transmitPlayerVoiceSound` : aucun son sur un serveur, méthode réservée à `IsoPlayer`.
- **Comportement `alert` avec un rang de priorité propre** : la cascade fixe (décision du 2026-10-08) ne change pas ; l'alerte est une menace partagée, rangée dans la règle `threat`.
- **Écrire les portes ici** : `LK_Obstacles` a son propre propriétaire ; point d'entrée `subscribe` à la place.

## Idées reprises

- I2.4 (dernière position partagée) : retenue (position de la menace la plus grave observée en dernier, regard de tous les membres) ; **recherche en spirale non faite** (à revoir avec LK05-T09/LK06).
- I2.3 (indices de présence humaine qui s'accumulent) : non reprise ici (l'alerte part de la perception directe) ; à revoir avec les sites et la fortification.
- I6.2 (annonces de position de l'intrus) : non reprise (le catalogue `alert` n'a pas de réplique paramétrée par la pièce ou l'étage) ; candidate pour LK05-T09.

## Tests

- Banc lupa (`tests/test_lk_alert.py`, 16 tests) : menaces près du membre ou du foyer seulement (gravité, zombie anonyme, joueur connu écarté, étage) ; inconnu = intrus, ami connu rien, méfiant = intrus, inconnu pour des pillards = hostile ; une alerte par menace (`raised`, `seen`, `joined`, `escalated`, `resumed` sans cri, nouvelle alerte après 60 min, groupes distincts) ; niveau qui retombe et `EXTRA` ; écouteurs appelés une fois (déclenchement, calme), erreur isolée ; cascade (`alert` au rang 1, regard vers la dernière position, réveil d'un dormeur, propre menace d'abord, interruption puis état gardé jusqu'à l'échéance) ; portée `REACH` et foyer ; pile solo : dormeurs assis réveillés (debout, `guard`, regard, geste `guard`/`crouch`), une réplique, un bruit de 15, une voix, une entrée de journal, un appel d'écouteur ; aucun nouveau cri tant que la menace reste vue ; niveau retombé → retour au sommeil et geste assis ; même zombie revu → rallumée sans cri ; autre zombie plus tard → nouvelle alerte ; corvée de jour interrompue puis reprise ; joueur inconnu près du foyer = intrus, connu favorable rien ; pile MP (serveur + deux clients) : une commande `alertCry` par client, même identifiant, livraison répétée ignorée, mêmes consignes, gestes et vigilance chez A et B, aucune alerte côté client, retour au sommeil identique ; vue client : émetteur libre en `(nom, false, nil)`, doublons et voix inconnues refusés, doublure qui refuse `(nom, nil)` ; sources sans `next`, `goto`, coroutines ni caractère non ASCII dans le code ; suite `lk.alert` déroulée sur les doublures. Tests mis à jour pour l'alerte : `test_lk_decisions.py`, `test_lk_routines.py`, `test_lk_chores.py` (retour à la routine après la retombée) ; suite `lk.chores` (alerte du groupe de test close après la fausse menace).
- VM Kahlua (`tests/test_kahlua.py`, `KR-ALERT`) : clés, une fois par menace, niveau et distance identiques à lupa.
- En jeu : suite `lk.alert` (solo, tags `world`) ; MP à la séance finale. LK05-T14 : second test de la suite (foule fictive de 50 zombies perçus au-delà de `ZombieAlertDistance`, aucune alerte ni règle `threat` pendant 20 s) ; banc `tests/test_lk_thresholds.py`.

### Protocole en jeu (solo, rstest, maison)

1. Se placer dans une maison, option Living Knox activée, mode Debug : `RST.run({ suite = "lk.alert", tags = "world" })` (2 à 4 min). Attendu : lignes `[LKA] measure alert raised`, `cry`, `members alerted`, `calm`, test PASS ; à l'écran, la bulle « alert » au-dessus d'un PNJ, la voix « Hey! » entendue une fois, les PNJ tournés vers le zombie (garde ou accroupis), puis retour à leur activité.
   Second test (LK05-T14, 1 à 2 min, endroit calme sans zombie à moins de 10 cases) : ligne `[LKA] measure thresholds: zombie alert 10, reach 20, shout 10, ...` (défauts des options), puis `[LKA] measure crowd: 20 s with 50 zombies 12 to 26 squares away: alerts raised 0, ...`, test PASS ; à l'écran, les PNJ poursuivent leur activité.
2. Cas limites (ensuite) : la nuit, PNJ assis qui se relèvent ; un deuxième zombie pendant l'alerte (aucun nouveau cri) ; joueur qui s'approche du foyer d'un groupe qui ne le connaît pas (alerte « intruder »).

## Points ouverts

- ⚠ Voix `Voice*ShoutHey` jouée sur l'émetteur d'un corps de zombie (événement FMOD de voix de joueur) : rendu à vérifier en jeu ; repli émetteur libre si le corps n'est pas connu.
- ⚠ Valeurs (rayons, niveaux, baisse de 5 par minute, fenêtre de 60 min, portée 30) à recalibrer en jeu.
- ⚠ En solo tous les zombies partagent la clé `z?` : après un premier zombie, un autre zombie dans l'heure rallume l'alerte sans cri.
- ⚠ Portes refermées à l'alerte (écouteur `doors` de `LK_Obstacles`) : vérifiées sur le banc seulement (`tests/test_lk_alert.py`, `AlertDoorTests`, `MultiplayerAlertDoorTests`) ; à voir en jeu (suite `lk.alert` dans une maison dont une porte extérieure est ouverte). Seules les portes du niveau du foyer ; fenêtres non refermées.
- ⚠ Alerte non sauvegardée ; hors écran (simulation abstraite), aucune alerte.
- ⚠ Recherche en spirale (I2.4), indices de présence (I2.3) et annonces de position (I6.2) non faits ; défense coordonnée en LK05-T09.
