# Attitude des groupes envers les joueurs

- Tâches : LK11-T03 (création) ; servira LK11-T02 (sommations selon l'attitude), LK11-T05 (vengeance), LK11-T06 (demandes d'aide), LK11-T08 (troc), E09-T04 (relations du carnet), E04 (réputation)
- Build : 42.21.0 — Date : 2026-10-10 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Hostility.lua` (`LivingKnox.Hostility`, registre, persistance), réglages `Config.ATTITUDE` dans `media/lua/shared/LivingKnox/LK_Config.lua`, hostilité de départ par type dans `media/lua/shared/LivingKnox/Data/LK_Type_*.lua` (champ `hostility`), relecture à `OnInitGlobalModData` et déclin à `EveryHours` dans `LK_Server.lua`, projection par joueur dans `LK_API.lua` ([api-living-knox.md](../../specifications-techniques/api-living-knox.md)). Tests : `tests/test_lk_hostility.py`, `tests/test_lk_api.py` (`AttitudeTests`), `tests/test_kahlua.py` (`test_attitude_in_kahlua`).

## Problème

Chaque groupe de Living Knox doit savoir ce qu'il pense de **chaque personnage joueur**, d'après ce que ce personnage lui a fait : aide, agression, meurtre, vol, missions. Deux joueurs peuvent donc être accueillis différemment par le même groupe. L'attitude ne s'affiche jamais en chiffres (décision E09-T01) : seulement un niveau parmi cinq et une tendance. Elle doit survivre au redémarrage sans ModData globale et rester bornée.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Aucune ModData globale pour un état privé (lisible par tout client). | base `multiplayer.md` | confirmé statiquement |
| Clé de joueur côté serveur : `getUsername` (SteamID imprécis en Lua) ; une faction vanilla n'a pas d'identifiant stable. | base `multiplayer.md` | confirmé statiquement |
| Seule la ModData du joueur côté serveur est sauvegardée en MP : l'identité de personnage du carnet (`RS_CarnetCharacter`) y est écrite par le serveur, liée au compte et au slot, retirée à la mort (`OnCharacterDeath`). | `RS_Carnet_Server.lua` (`identity`, `characterDeath`), E00-T01, E00-T02 | confirmé statiquement (banc) |
| Un client MP charge aussi `media/lua/server` : garde `isClient()` en tête de fichier. | base `mod-loading.md` | confirmé statiquement |
| `OnInitGlobalModData(isNewGame)` part avant la cellule : moment de relecture et détection d'un monde neuf ; fichiers `getFileWriter` du serveur qui survivent à l'effacement du monde. | [groupes.md](groupes.md), base `world-placement.md`, `kahlua-lua.md` | confirmé statiquement |
| Le jour de jeu (`getWorldAgeHours() / 24`) change à 7 h, pas à minuit. | base `api-42-21.md` | confirmé statiquement |

## Choix

Retenu le 2026-10-10 (LK11-T03), dans le cadre des décisions E09-T01 (5 niveaux, tendance par les trois derniers faits, aucun score affiché) et des décisions acquises d'E09 (relations personnelles par personnage, accords de faction distincts).

### Clé : groupe + personnage

- Groupe : identifiant `grp-<n>` du registre des groupes ([groupes.md](groupes.md)) ; un fait sur un groupe inconnu est refusé.
- Joueur : **identité de personnage du carnet** (`RS_CarnetCharacter`, par exemple `character-<ms>-<n>-<tirage>`), retrouvée par `Hostility.keyOf(player)` dans `RS_CarnetServer.bound` (lié à la commande `hello` envoyée par le client à l'entrée en jeu). Elle est propre au compte en MP et **nouvelle pour chaque personnage** : deux personnages successifs d'un même compte ont deux attitudes distinctes ; un personnage mort ne garde rien (son identité est retirée, ses attitudes deviennent orphelines et sont oubliées avec le temps). Sans identité liée, `keyOf` rend `nil, "no notebook character bound"` et aucun fait n'est enregistré.
- Le module accepte toute clé bien formée (1 à 96 caractères de `[%w_.:-]`) pour rester utilisable par un autre fournisseur d'identité.
- Un **compte** seul (`getUsername`) n'a pas été retenu : il confondrait les personnages successifs d'un compte, contraire à la décision « relations personnelles par personnage ».

### Valeur, niveaux, tendance

| Élément | Règle |
|---|---|
| Valeur interne | entier −100..100, **jamais affiché ni rendu** par l'API |
| Départ | `arrondi((50 − hostilité du type) × START_SCALE)`, `START_SCALE = 1.25`, fixé à la création de la paire (`start`) ; colons (hostilité 10) = 50, neutres (45) = 6, pillards (90) = −50 ; type inconnu = 0 |
| Niveaux | `hostile` < −44 ≤ `wary` (méfiant) < −14 ≤ `cautious` (prudent) < 15 ≤ `favorable` < 60 ≤ `trusting` (confiant) ; seuils `Config.ATTITUDE.LEVEL_MIN`, strictement croissants (sinon seuils de repli) |
| Départ par type | colons : favorable ; neutres : prudent ; pillards : hostile |
| Tendance | signe de la somme des **sens** (+1, 0, −1) des trois derniers faits : `up`, `down`, `stable` ; aucun fait = `stable` ; le déclin n'est pas un fait |

Le sens d'un fait est celui de son effet nominal : un don à un groupe déjà au plafond reste un fait positif.

### Faits (liste fermée)

| Fait | Effet | Famille |
|---|---|---|
| `gift` | +8 | aide : don |
| `heal` | +12 | aide : soin |
| `delivery` | +10 | aide : livraison |
| `hit` | −15 | agression : coup |
| `shot` | −25 | agression : tir sur un membre |
| `kill` | −60 | mort d'un membre causée ; marque la paire « meurtre » ; enregistré depuis LK11-T05 (attribuable) par `LK_Relations.memberKilled` quand le serveur identifie le joueur tueur d'un membre (fait `npcDied`), voir [vengeance.md](vengeance.md) |
| `theft` | −20 | vol constaté (I5.2) |
| `mission_success` | +15 | mission réussie pour le groupe |
| `mission_failure` | −10 | mission ratée pour le groupe |

Effets dans `Config.ATTITUDE.EFFECTS`, bornés à ±`EFFECT_MAX` (60) ; valeur non numérique : effet de repli. La valeur résultante est bornée à −100..100.

**Témoins (I9.3)** : `record(groupId, playerKey, fact, opts)` refuse un fait qui n'est ni vu (`opts.witnessed = true` : un membre du groupe l'a vu) ni attribuable (`opts.attributable = true` : par exemple une mort que le serveur attribue au joueur). La détection dans le monde n'est pas faite ici : l'appelant (combat, interactions, missions) décide. **Seul le joueur désigné** est visé : jamais son équipe, ni les autres groupes.

### Amélioration et déclin (I9.4)

- Les actes positifs (aide, missions) améliorent l'attitude, y compris après un meurtre.
- **Retour lent vers le départ** : `decay(day)` rapproche chaque valeur de son départ de `DECAY_PER_DAY` (2) points par jour de jeu écoulé depuis le dernier déclin de la paire, au plus `DECAY_MAX_DAYS` (30) jours rattrapés par appel, sans dépasser la cible. Une rancune ou une faveur s'efface donc en quelques semaines de jeu.
- **Après un meurtre**, la cible devient `min(départ, MURDER_CAP)` avec `MURDER_CAP = −15` (haut de « méfiant ») : le temps seul ne ramène jamais au-dessus, et une amélioration obtenue par des actes redescend lentement vers ce plafond. Le marqueur de meurtre ne s'efface pas.
- Appel : à chaque `EveryHours`, appliqué quand le jour de jeu a changé (`Groups.today()`) ; sur un serveur vide en pause, l'heure n'avance pas et rien ne décline. Le même passage oublie les attitudes des groupes qui n'existent plus.

### API serveur (`LivingKnox.Hostility`, autorité seulement)

Chaque fonction rend son résultat, ou `nil` et une raison en anglais.

| Fonction | Rend |
|---|---|
| `record(groupId, playerKey, fact, opts)` | `{ level, trend }` après le fait ; raisons : `unknown fact <f>`, `bad player key`, `fact neither witnessed nor attributable`, `bad day`, `attitude registry not ready`, `group registry not ready`, `unknown group <id>`, `attitude registry write failed` |
| `get(groupId, playerKey)` | `{ level, trend }` ; sans fait connu : niveau de départ, `stable`, rien n'est créé |
| `forGroup(groupId)` | `{ { player, level, trend }, ... }` trié par clé, 64 au plus ; **serveur seulement** (clés de joueurs) |
| `decay(day)` | nombre de paires dont la valeur a changé (`day` facultatif : aujourd'hui) |
| `keyOf(player)` | identité de personnage du carnet liée au joueur |

`opts.day` (facultatif) fixe le jour du fait. `debugPair` rend une copie complète d'une paire (tests, diagnostic serveur) et ne doit jamais partir vers un client.

### Schéma et persistance

**Schéma 1** (`Hostility.SCHEMA = 1`) :

```
{ schema = 1, decayDay = <dernier jour de déclin>, groups = { ["grp-<n>"] = { [playerKey] = pair } } }
pair = { value, start, facts = { { fact, sign, day, n }, ... } (3 au plus, le plus ancien d'abord),
         murder = true ou absent, decayDay, seen = jour du dernier fait, count = faits enregistrés (E09-T04) }
```

Bornes : 64 groupes (= `Groups.MAX_GROUPS`), **64 joueurs par groupe**, **3 faits par paire**. Groupe plein : la paire la plus ancienne (dernier fait) **sans meurtre** est oubliée, sinon la plus ancienne ; journal `INFO`.

Fichiers : `Zomboid/Lua/batman_RadioSurvivor/livingknox/attitudes-<hex du mode/nom de partie>-<0|1>.txt`, mécanisme de `LK_Store` (entête `LKATT1=<numéro>`, octets RSV2 en hex, somme de contrôle, `end`), deux emplacements en alternance, relus après chaque écriture. Sauvegarde à chaque fait et à chaque déclin effectif (rares). Relecture à `OnInitGlobalModData` ; rattrapage paresseux (`ensure`) au premier usage ; monde neuf : registre vide, numéros d'écriture poursuivis.

Contrôle au chargement : schéma différent de 1, structure générale fausse, plus de 64 groupes ou deux emplacements illisibles → registre **bloqué** (`ERROR`, aucune écriture, fichiers conservés, faits refusés) ; sinon chaque groupe et chaque paire sont vérifiés (identifiant de groupe, clé, bornes, faits de la liste, sens, jours) et une entrée invalide est **écartée** et journalisée (`ERROR attitude <grp>/<clé> dropped at load (file #<n>): <raison>`).

### Lien avec la réputation et les relations du carnet

- **Réputation (E04, `RS_Reputation.lua`)** : réputation **globale et unique** d'un personnage, tenue par le serveur de RadioSurvivor (réputation interne, décision 8 du 2026-10-14, [reputation-interne.md](reputation-interne.md)). L'attitude de LK11-T03 est **locale à un groupe** : le même personnage peut être confiant pour des colons et hostile pour des pillards. Les deux ne se dupliquent pas : un fait de mission peut alimenter les deux (l'attitude du groupe concerné et la réputation globale). **Seul lien de calcul (E04-T11, Q14, confirmé par défaut le 2026-10-15)** : au **premier contact** d'un groupe qui ne connaît pas encore le personnage, le départ de la paire est décalé **d'un cran de niveau** selon la réputation (bonne : au moins le seuil du niveau au-dessus ; mauvaise : juste sous le seuil de son niveau ; neutre : inchangé ; `Hostility.startForPlayer`, crochet `LivingKnox.Hooks.reputation` posé par le carnet). Ce départ est fixé à la création de la paire (champ `start`, cible du déclin) ; ensuite seuls les faits envers ce groupe comptent, la réputation n'est plus relue pour lui. Rien ne va dans l'autre sens : l'attitude d'un groupe ne change jamais la réputation globale.
- **Relations du carnet (E09-T04)** : confiance personnelle d'**un PNJ** envers un personnage, motivée par le LLM. L'attitude d'un groupe en est le socle collectif (« base des relations de RadioSurvivor ») ; les mêmes cinq niveaux et la même règle de tendance s'appliquent. Décision du 2026-10-13 : écart personnel borné à un niveau au-dessus ou au-dessous de l'attitude du groupe, registre distinct du carnet qui ne recalcule jamais cette attitude ([relations.md](relations.md)). Les faits d'une paire portent depuis E09-T04 un numéro `n` (compteur `count` de la paire, champs facultatifs au chargement) lu par `API.attitudeFacts`.
- **Accords de faction (E09-T05)** : distincts, hors de cette tâche ; une trêve n'oblige pas un groupe à apprécier chaque joueur.

## Alternatives écartées

- Score affiché ou rendu par l'API : refusé par E09-T01 (niveaux qualitatifs seulement).
- Attitude par compte (`getUsername`) : confond les personnages d'un compte (voir plus haut).
- Attitude envers toute l'équipe ou tous les joueurs après une agression : défaut relevé chez Bandits! (I9.3) ; seul l'agresseur est visé.
- Réputation qui ne fait qu'empirer : défaut relevé chez A-Life (I9.4) ; ici les actes et le temps l'améliorent.
- Tendance sur une durée (sept jours) : écartée par E09-T01.
- Historique complet des faits : inutile pour la tendance (trois faits), coûteux ; seul le marqueur de meurtre est gardé en plus.
- Stockage dans le registre des groupes : schéma de `groups` alourdi, et un fichier abîmé ferait perdre les deux ; fichier distinct, même mécanisme.

## Idées reprises

- I5.2 (vol constaté) : fait `theft`, enregistré seulement s'il est vu ou attribuable ; la surveillance du stock relève de LK08-T06.
- I9.3 (témoins, agresseur seul) : paramètre `witnessed` / `attributable`, paire par joueur.
- I9.4 (réputation qui peut s'améliorer) : actes positifs et retour lent vers le départ, avec un plafond après un meurtre (choix propre au mod).

Valeurs chiffrées propres au mod, points de départ à recalibrer en jeu.

## Tests

- Banc lupa (`tests/test_lk_hostility.py`) : niveaux de départ par type, seuils, **deux joueurs aux attitudes différentes avec le même groupe**, agresseur seul visé, témoins requis, tendance sur trois faits, bornes de valeur et d'effet, refus, 64 joueurs par groupe (meurtre gardé), déclin (rattrapage borné, cible, plafond après meurtre, déclin horaire, groupes disparus), persistance à deux emplacements, monde neuf, schéma inconnu bloquant, paires invalides écartées, absence du module chez un client MP, clé de joueur par l'identité du carnet, solo.
- `tests/test_lk_api.py` (`AttitudeTests`) : `API.attitude`, vues par joueur, projection publique limitée au niveau et à la tendance.
- VM Kahlua (`tests/test_kahlua.py`, `test_attitude_in_kahlua`) : mêmes valeurs que sous lupa, aller-retour RSV2 validé.
- En jeu : aucun (pas encore de point d'entrée branché sur le jeu).

Choix de cible fondé sur cette attitude (LK06-T01) : [cibles.md](cibles.md).

## Points ouverts

- ⚠ Points d'entrée réels (coups, tirs, morts, vols, dons, missions) : tâches de combat et d'interaction (LK07, LK11-T02, LK11-T06, LK08-T06, E09-T04). L'attribution d'une mort au joueur repose sur E04-T06 (`getAttackedBy` à `OnZombieDead`).
- ⚠ Rejeu d'un même fait (aucun identifiant d'événement) : à l'appelant d'éviter le double enregistrement ; un identifiant idempotent pourra s'ajouter avec les points d'entrée.
- ⚠ Calibrage des effets, des seuils et du déclin en jeu.
- ⚠ Libellés traduits des niveaux et tendances pour le carnet (E09-T07) : les identifiants anglais sont internes.
