# API publique de Living Knox

- Tâches : LK12-T01 ; LK10-T03 (histoires enrichies, ajout compatible dans la version 1, 2026-10-12) ; LK11-T03 (attitude par joueur, ajout compatible dans la version 1) ; LK12-T03 (offres de ressources et livraisons, ajout compatible dans la version 1) ; LK12-T02 (événements publics, ajout compatible dans la version 1, 2026-10-12) ; servira E17-T03 (fournisseur du carnet)
- Build : 42.21.0 — Date : 2026-10-10 (événements : 2026-10-12) — Statut : testé hors jeu (banc lupa et VM Kahlua)

Code : `Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/LivingKnox/LK_API.lua` (`LivingKnox.API`). Tests : `tests/test_lk_api.py`, `tests/test_kahlua.py` (`test_api_in_kahlua`, `test_attitude_in_kahlua`, `test_events_in_kahlua`).

## Portée

- **Autorité seulement** (serveur dédié ou hébergé, solo). Le fichier est sous `media/lua/server`, qu'un client MP charge aussi : il s'y arrête dès la première ligne (`if isClient() then return end`), donc `LivingKnox.API` vaut `nil` chez un client MP. Un consommateur teste `LivingKnox and LivingKnox.API` avant usage (aucune dépendance dure).
- **Lecture**, sauf deux fonctions (LK12-T03) : `missionOffers` (ouvre ou ferme paresseusement les offres d'un groupe) et `deliver` (remonte une réserve). Elles écrivent seulement le registre des groupes, par `LivingKnox.Groups.update` (une sauvegarde, réserve et reçu dans la même écriture) ; aucune fonction n'écrit une ModData ni un inventaire. Événements Lua publics : section [Événements publics (LK12-T02)](#événements-publics-lk12-t02).
- **Copies** : chaque appel rend des tables neuves, composées uniquement de chaînes, nombres, booléens et tables simples ; aucune référence au registre, aucun objet Java. Modifier un résultat ne change rien au moteur.
- **Envoi à un client** : ces résultats ne sont pas faits pour être transmis tels quels. Tout envoi (`sendServerCommand`, ModData, journal, pont LLM pour un texte public) passe par une projection explicite : `API.publicGroup(g)` pour un groupe, ou une projection du consommateur qui ne rajoute rien de privé. Rappel (base `multiplayer.md`) : aucune ModData globale pour ces données, lisibles par tout client.

## Version et compatibilité

- `API.VERSION` = **1** ; `API.version()` rend le même entier.
- Dans une même version, on n'**ajoute** que des fonctions ou des champs. Tout **retrait**, renommage ou **changement de sens** (unité, maille du foyer, bornes, signification d'une valeur, ordre de tri) impose `VERSION + 1`, consigné ici.
- Un consommateur vérifie `API.version() >= N` (N = la version qu'il connaît) et ignore les champs qu'il ne connaît pas.
- Ajouts dans la version 1 : LK11-T03 (2026-10-10) — fonction `API.attitude`, argument facultatif `playerKey` de `listGroups` et `getGroup`, champ `attitude` rempli seulement quand un joueur est fourni (sans lui, toujours nil comme avant), `attitude` admise par `publicGroup`. Un consommateur qui teste la présence de la fonction (`API.attitude ~= nil`) sait si l'ajout est là.
- Ajouts dans la version 1 : LK12-T03 (2026-10-10) — fonctions `API.missionOffers`, `API.deliver`, `API.currentHour`, constantes `API.SUPPLY`, `API.SUPPLY_ITEMS`, `API.REWARD_ITEMS` ; champ facultatif `supply` du groupe dans le registre (schéma 1 inchangé). Test de présence : `API.deliver ~= nil`.
- Ajouts dans la version 1 : LK10-T02 (2026-10-12) — fonction `API.journal` (journal de récit public, section [Journal de récit (LK10-T02)](#journal-de-récit-lk10-t02)). Test de présence : `API.journal ~= nil`.
- Ajouts dans la version 1 : LK12-T02 (2026-10-12) — six événements Lua (`API.EVENTS`), fonctions `API.flushEvents`, `API.checkNeeds`, constante `API.EVENT_QUEUE_MAX` ; argument facultatif `reason` de `LivingKnox.Groups.applyLeave` et `removeMember`. Test de présence : `API.EVENTS ~= nil`. Un abonné tiers n'a besoin d'aucun test : il déclare les noms lui-même (voir l'exemple).
- Ajouts dans la version 1 : LK10-T03 (2026-10-12) — fonctions `API.story` et `API.enrichStory`, constante `API.STORY` ; champ facultatif `enrich` du groupe dans le registre (schéma 1 inchangé). `summary` de `listGroups`/`getGroup` garde son sens (résumé du registre, jamais le texte fourni). Test de présence : `API.enrichStory ~= nil`.
- Ajouts dans la version 1 : E01-T10 (2026-10-12) — fonctions de test `API.testAllowed`, `API.testSpawnNpc`, `API.testRemoveNpc`, `API.testNpcs`, constante `API.TEST_SAVE_PREFIX` (fichier `LK_APITest.lua`), réservées aux parties de test, section [Fonctions de test (E01-T10)](#fonctions-de-test-e01-t10). Test de présence : `API.testSpawnNpc ~= nil`.
- Ajouts dans la version 1 : E10-T02 (2026-10-12) — fonction `API.composition` (chef vivant et empreinte calculée des membres vivants, aucun champ stocké, schéma inchangé), section [`API.composition`](#apicompositiongroupid---composition--nil-reason). Test de présence : `API.composition ~= nil`.

## Constantes

| Nom | Valeur | Sens |
|---|---|---|
| `API.AREA_SIZE` | 100 | maille du foyer approximatif, en cases |
| `API.NEAR_DEFAULT` | 20 | rayon par défaut de `npcsNear` |
| `API.NEAR_MAX` | 50 | rayon plafonné de `npcsNear` (un rayon plus grand est ramené à 50) |
| `API.NEEDS` | `{ "food", "medical", "ammo" }` | besoins rendus |

## Fonctions

### `API.isReady() -> boolean`

Vrai si le registre des groupes est relu et non bloqué (rattrapage paresseux comme `LivingKnox.Groups.ensure`).

### `API.listGroups([playerKey]) -> { view, ... }`

Groupes triés par numéro (`grp-1`, `grp-2`, …). Table vide si le registre n'est pas prêt (voir `isReady`). `playerKey` facultatif (ajout LK11-T03) : la vue devient une **projection pour ce joueur** et porte l'attitude de chaque groupe envers lui. Chaque vue :

| Champ | Type | Sens |
|---|---|---|
| `id` | chaîne | identifiant stable `grp-<n>`, jamais réattribué |
| `type` | chaîne | type de groupe (`settlers`, `raiders`, `neutrals` ou type ajouté par données) |
| `typeNameKey` | chaîne ou nil | clé de traduction du nom du type, **à traduire chez le client** (`getText` rend la clé sur un serveur MP) |
| `name` | chaîne | nom du groupe (1 à 64) |
| `summary` | chaîne | résumé public de l'histoire (champ `story` du registre, 0 à 600) ; il ne contient que `Stories.summary`, jamais les secrets ([recits.md](conception/recits.md)) |
| `founded` | entier | jour de fondation (1 = premier jour) |
| `alive` / `total` | entiers | membres vivants / membres connus (morts compris) |
| `leader` | table ou nil | `{ id = "m-<k>", npc = "lk-<n>" ou nil, name = nil }` ; `name` toujours nil en version 1 : le registre ne tient aucun nom de membre |
| `area` | table ou nil | foyer approximatif `{ x, y, size = 100 }` : **centre** de la maille de 100 × 100 cases qui contient le foyer ; ni case exacte ni étage ; nil sans foyer |
| `needs` | table | `{ food, medical, ammo }`, entiers 0..100 |
| `morale` | entier | 0..100 |
| `task` | chaîne ou nil | dernière tâche hors écran (`heal`, `rest`, `scavenge`… , [simulation.md](conception/simulation.md)) |
| `attitude` | table ou nil | attitude du groupe envers le joueur `playerKey` : `{ level, trend }` (voir `API.attitude`) ; **nil sans `playerKey`** (comportement d'origine de la version 1), avec une clé invalide ou un registre d'attitudes non prêt |

Exemple :

```lua
local API = LivingKnox and LivingKnox.API
if API and API.version() >= 1 then
    for _, g in ipairs(API.listGroups()) do
        print(string.format("%s %s alive=%d food=%d", g.id, g.name, g.alive, g.needs.food))
    end
end
-- grp-1 Mill Folk alive=2 food=20
```

### `API.getGroup(id[, playerKey]) -> view | nil, reason`

La vue de `listGroups` (avec l'attitude envers `playerKey` s'il est fourni) plus `members`, triés par numéro (ancienneté) : `{ { id = "m-<k>", role, alive = booléen, npc = "lk-<n>" ou nil }, ... }`. Raisons (anglais) : `group registry not ready`, `unknown group <id>`.

```lua
local g = LivingKnox.API.getGroup("grp-1")
-- g.members = { { id = "m-1", role = "worker", alive = true, npc = "lk-1" },
--               { id = "m-3", role = "medic", alive = false } }
```

### `API.composition(groupId) -> composition | nil, reason`

Ajout E10-T02. Composition **calculée** à chaque appel (aucun champ stocké) pour revalider une décision collective :

| Champ | Sens |
|---|---|
| `group` | identifiant du groupe |
| `leader`, `leaderNpc` | membre chef (`m-<k>`) s'il est vivant, et son PNJ (`lk-<n>`), sinon nil |
| `alive`, `members` | nombre et liste des membres vivants (`m-<k>`, triés par numéro) |
| `key` | empreinte `"<chef ou ->|<m-a>,<m-b>,..."` |

Deux appels rendent la même `key` tant que ni le chef ni l'ensemble des membres vivants n'ont changé ; une mort, un départ, une arrivée ou une succession la changent. Un consommateur garde `key` avec une intention collective et la compare au moment de l'appliquer : une réponse fondée sur une ancienne composition est rejetée (carnet : `RS_Carnet_Server.collectiveCheck`). Raisons : `group registry not ready`, `unknown group <id>`. Serveur seulement ; l'empreinte nomme des membres, elle ne s'envoie pas à un client.

### `API.attitude(groupId, playerKey) -> { level, trend } | nil, reason`

Ajout LK11-T03 ([attitude.md](conception/attitude.md)). Attitude d'un groupe envers **un** personnage joueur, sans valeur numérique (décision E09-T01) :

| Champ | Valeurs |
|---|---|
| `level` | `hostile`, `wary` (méfiant), `cautious` (prudent), `favorable`, `trusting` (confiant) — identifiants internes, libellés à traduire chez le client |
| `trend` | `up`, `down`, `stable` : sens des trois derniers faits de relation |

`playerKey` = identité de personnage du carnet (`LivingKnox.Hostility.keyOf(player)` côté serveur) : deux personnages d'un même compte sont distincts. Sans fait connu : niveau de départ du type de groupe, `stable`. Raisons : `bad player key`, `attitude registry not ready`, `group registry not ready`, `unknown group <id>`. Lecture seule ; les faits s'enregistrent par `LivingKnox.Hostility.record` (serveur, hors de cette API en lecture).

```lua
local key = LivingKnox.Hostility.keyOf(player)
local a = key and LivingKnox.API.attitude("grp-1", key)
-- a = { level = "wary", trend = "down" }
```

Cette projection est propre au joueur concerné : l'attitude d'un groupe envers un joueur ne s'envoie qu'à ce joueur.

### `API.attitudeFacts(groupId, playerKey) -> { { n, fact, sign, day }, ... } | nil, reason`

Ajout E09-T04 ([relations.md](conception/relations.md)), compatible avec la version 1. Derniers faits de relation du groupe envers ce personnage (les trois de la tendance au plus, le plus ancien d'abord), chacun vu par un membre ou attribuable : `n` = numéro du fait dans la paire (stable, jamais réutilisé : `LK_Hostility` le pose à l'enregistrement, champ `count` de la paire), `fact` (liste fermée de `LivingKnox.Hostility.FACTS`), `sign` (−1, 0, 1), `day`. Les faits enregistrés avant cet ajout n'ont pas de numéro et ne sont pas rendus. Liste vide sans fait ; mêmes raisons qu'`API.attitude`. Jamais la valeur interne ; lecture seule ; serveur seulement (la liste est propre à un joueur).

### `API.npcsNear(player, radius)` ou `API.npcsNear(x, y, z, radius)` -> `{ near, ... } | nil, reason`

PNJ **incarnés** (état `embodied` du registre des corps) à portée horizontale d'un joueur (tout objet à `getX/getY/getZ`) ou d'un point. `radius` facultatif (20), plafonné à 50. Position : celle du corps lié s'il est dans le monde, sinon la dernière position vue du registre (`last`, rafraîchie au balayage et écrite à `OnSave`) ; un PNJ virtuel, mort ou sans position connue est exclu. Coût : un passage sur le registre des PNJ et un sur celui des groupes ; aucune case, aucun chunk, aucun parcours de carte.

| Champ | Sens |
|---|---|
| `id` | identifiant stable du PNJ `lk-<n>` |
| `group`, `member`, `role` | groupe, membre et rôle s'il appartient à un groupe, sinon nil (aussi nil si le registre des groupes n'est pas prêt) |
| `distance` | distance horizontale arrondie à la case |
| `floor` | étage du PNJ moins étage du point (0 = même étage) |
| `inWorld` | vrai si la position vient du corps présent dans le monde, faux si elle vient du registre |

Tri : distance croissante, puis numéro. Raisons : `bad position`, `bad radius`, `npc registry not ready`.

```lua
local near = LivingKnox.API.npcsNear(player, 30)
-- { { id = "lk-2", group = "grp-1", member = "m-2", role = "fighter", distance = 5, floor = 0, inWorld = true } }
```

### `API.publicGroup(g) -> table | nil`

Projection sûre pour un client : **liste blanche** des champs de la vue (`id`, `type`, `typeNameKey`, `name`, `summary`, `founded`, `alive`, `total`, `leader`, `area`, `needs`, `morale`, `task`, `members`, et depuis LK11-T03 `attitude` réduite à `{ level, trend }` aux valeurs connues), valeurs simples seulement ; tout autre champ, fonction ou objet est retiré et `area` est remise sur la maille. Accepte une vue (`listGroups`, `getGroup`) ou un groupe **brut** du registre (converti : foyer en maille, journal et champs internes jamais repris). nil si `g` n'est pas une table.

### `API.area(x, y) -> { x, y, size } | nil`

Centre de la maille `AREA_SIZE` qui contient `(x, y)` ; sert à `area` et à `publicGroup`.

### `API.engaged(npcId) -> true, reason | false`

Ajout compatible de la version 1 (E08-T03). Vrai si le PNJ est **occupé** à l'instant, et la première raison dans cet
ordre : `hit` (coup d'un joueur reçu depuis moins de `API.ENGAGED_MS` = 30 s, `LivingKnox.Bodies.lastHits`), `combat`
(ordre de combat de `LK_Combat` en cours : couvre les coups portés pendant l'engagement ; un ordre clos est oublié),
`warning` (sommation de LK11-T02 en cours menée par ce PNJ : rencontre de `LK_Encounters` à une étape ≥ 1), `alert`
(alerte de LK05-T08 active pour son groupe, `LK_Alert.isActive` à la minute de `LK_Decisions.currentMinute`). Un
module absent ne compte pas. Mémoire seulement (rien de sauvegardé), autorité seulement. Prédicat **provisoire**
jusqu'à LK05-T08 et LK06-T01 ; sert aux initiatives du carnet (`RS_NPCProvider.engaged`, fournisseur
`RS_LivingKnox.lua`).

```lua
local busy, why = LivingKnox.API.engaged("lk-3")   -- true, "warning" | false
```

## Journal de récit (LK10-T02)

### `API.journal(groupId[, since]) -> { group, next, entries } | nil, reason`

Faits marquants du groupe (installation, expéditions, morts, rencontres, départs, recrues, combats hors écran, disparition, relève), la plus ancienne d'abord, au plus 40 (`LivingKnox.Journal.SIZE`). Conception : [journal.md](conception/journal.md).

- `since` (facultatif, entier >= 0) : seules les entrées de numéro `> since` ; `next` = numéro de la prochaine entrée (un consommateur qui garde `next - 1` ne relit que les nouvelles).
- `entries[i] = { n, day, hour, kind, key, args, member, npc, text }` :
  - `n` : numéro croissant, jamais réutilisé dans le groupe ; `day` : jour de jeu ; `hour` : heure du jour 0..23 du début de l'heure de jeu du fait (ou nil sans horloge) ;
  - `kind` : `founded`, `settled`, `moved`, `leader`, `leaderless`, `died`, `killed` (tué par un joueur, sans dire lequel), `left`, `deserted`, `recruit`, `expedition`, `trip`, `returned`, `noneBack`, `encounter` (une par jour, compte en argument), `attackWon`, `attackLost`, `defenseWon`, `defenseLost`, `wiped`, `dispersed`, `relief`, `relieved` (liste fermée ; une sorte ajoutée plus tard est un ajout compatible) ;
  - `key` : clé de traduction `IGUI_LK_Journal_<kind>` ; `args` : `{ { text, key }, ... }` dans l'ordre de `%1`, `%2` : `key` d'un rôle (`IGUI_LK_Journal_Role_<rôle>`) ou d'un lieu (`IGUI_LK_Journal_Place_<lieu>`) à résoudre d'abord, repli sur `text` ; sinon `key` = nil ;
  - `member`, `npc` : membre et PNJ concernés (identifiants publics de `getGroup`) ou nil ;
  - `text` : texte composé sur cette machine (langue du processus) quand les traductions du mod y sont chargées (solo, hôte) ; **nil sur un serveur dédié** : `key` et `args` font foi (composer côté client par `getText`, ou les donner au LLM).
- Aucune coordonnée, aucun compte de joueur, aucun secret d'histoire. Le journal technique `log` reste privé.
- Erreurs : `group registry not ready`, `unknown group <id>`.


Les missions de ravitaillement (M01 du carnet, E17-T03) partent des **besoins réels** d'un groupe : ses réserves
abstraites `food`, `medical`, `ammo` (0..100, [simulation.md](conception/simulation.md)). Barème commun :
[passeur-table.md](passeur-table.md), section 5 (même valeur V que le passeur, objets reliés aux réserves, « le groupe
ne cède pas ce qui lui manque »). Seuils lus dans `LivingKnox.Config.SIMULATION` (`NEED_LOW` = 25, `NEED_OK` = 40,
`NEED_TARGET` = 60), repli sur `API.SUPPLY`.

### Règles

| Règle | Valeur |
|---|---|
| Offre ouverte | une par réserve **sous `NEED_OK`** (40), groupe avec au moins un vivant ; aucune si aucun besoin |
| Joueur hostile | `playerKey` fourni et attitude `hostile` : aucune offre, livraison refusée (`group is hostile`) |
| Valeur demandée | `(NEED_TARGET − réserve) × 4` V, bornée à `VALUE_MIN` = 8 .. `VALUE_MAX` = 40 (10 points), ou `VALUE_LOW` = 60 (15 points) si la réserve est sous `NEED_LOW` |
| Délai | `HOURS` = 48 heures de jeu depuis l'ouverture (2 h réelles au réglage par défaut, comme M01) |
| Identifiant | `<groupe>-<réserve>-<n>` (`grp-1-food-3`), `n` compté par groupe, jamais réutilisé ; stable jusqu'à l'expiration ou la complétion |
| Conversion | **1 point de réserve = 4 V**, arrondi au plus proche **sur le cumul** de l'offre : gain d'une livraison = `round(cumul / 4) − round(cumul précédent / 4)` (trois bandages de 1 V : 0, 1, 0 = round(3/4)) ; réserve bornée à 100 |
| Dépassement | seul le dernier objet peut dépasser le reste ; une livraison qui contient un objet de plus que nécessaire est refusée (`too many items`) ; V comptée = min(total, reste) |
| Récompense | fait d'attitude `delivery` (à enregistrer par l'appelant, `LivingKnox.Hostility.record`) et, si possible, un objet tiré d'une **réserve non manquante** (la plus haute autre que le besoin, à `NEED_TARGET` au moins à l'ouverture) : prix de vente `⌈V × q × 1,30⌉` (marge d'un groupe neutre) ≤ moitié de la valeur demandée ; à la complétion, la réserve cède `round(V × q / 4)` points, sinon (elle passerait sous `NEED_OK`) l'objet est retiré |
| Journal | une entrée `supply` par livraison : `food +5 (grp-1-food-1, 20 V)`, à la complétion `…, gives 1 Base.ShotgunShellsBox, done` ou `…, reward withdrawn, done` |
| Reçus | `RECEIPTS_MAX` = 16 derniers par groupe, persistants avec le registre ; clé `[%w_.:-]`, 1 à 64 caractères |

Objets acceptés (`API.SUPPLY_ITEMS`, liste fermée, module `Base`, identifiants vérifiés dans
`media/scripts/generated/items/` de 42.21) :

| Réserve | Objets (V) | Récompense prise dans cette réserve |
|---|---|---|
| `food` | `TinnedBeans`, `TinnedSoup`, `CannedChili`, `CannedCornedBeef`, `CannedCorn`, `CannedPeas`, `CannedPotato2`, `CannedTomato2`, `CannedBolognese`, `CannedFruitCocktail`, `Rice`, `Pasta`, `DriedBlackBeans`, `PeanutButter` (2) | `TinnedBeans` (7 pour 40 V, 11 pour 60 V) |
| `medical` | `Antibiotics` (8), `Bandage` (1), `AlcoholWipes` (1), `Disinfectant` (3), `Pills` (3), `SutureNeedle` (3) ; `AntibioticsBox` (90) écartée, plus grosse qu'une offre | `Antibiotics` (1 pour 40 V, 2 pour 60 V) |
| `ammo` | `ShotgunShellsBox` (12), `308Box` (14), `3030Box` (12), `556Box` (8), `Bullets9mmBox` (10) | `ShotgunShellsBox` (1) |

### `API.missionOffers(groupId[, playerKey]) -> { offer, ... } | nil, reason`

Offres ouvertes, dans l'ordre `food`, `medical`, `ammo`. Ferme d'abord les offres expirées ou remplies, puis ouvre
celles qui manquent ; le registre n'est écrit que si une offre s'ouvre ou se ferme (un second appel identique n'écrit
rien). Raisons : `group registry not ready`, `unknown group <id>`, `bad player key`, `attitude registry not ready`,
`no game clock`.

| Champ | Sens |
|---|---|
| `id`, `group`, `need` | identifiant de l'offre, groupe, réserve visée |
| `level` | réserve actuelle (0..100) |
| `items` | `{ { type = "Base.X", value = V, count = exemplaires de ce seul objet pour le reste }, ... }` |
| `value`, `delivered`, `remaining` | V demandée, V déjà livrée, reste ; `points` = gain de réserve du reste |
| `opened`, `expires`, `hours` | heure de jeu d'ouverture, d'expiration, heures restantes |
| `reward` | `{ attitudeFact = "delivery", item = { type, count } ou nil }` |

```lua
local API = LivingKnox and LivingKnox.API
if API and API.deliver then
    local offers = API.missionOffers("grp-1", LivingKnox.Hostility.keyOf(player))
    -- offers[1] = { id = "grp-1-food-1", need = "food", level = 20, value = 60, remaining = 60, points = 15,
    --               hours = 48, items = { { type = "Base.TinnedBeans", value = 2, count = 30 }, ... },
    --               reward = { attitudeFact = "delivery", item = { type = "Base.ShotgunShellsBox", count = 1 } } }
end
```

### `API.deliver(groupId, offerId, delivered, receiptKey[, playerKey]) -> result | nil, reason`

`delivered` = `{ ["Base.X"] = nombre, ... }` (1 à `COUNT_MAX` = 60 par type). L'appelant a déjà vérifié les objets dans
l'inventaire du joueur ; il ne les retire qu'après un résultat `applied` (ou les place en séquestre avant, avec la même
clé de reçu pour rejouer après une coupure). **Idempotent par `receiptKey`** : une clé déjà reçue rend le résultat
d'origine (`duplicate = true`, `applied = false`) sans rien changer, même si l'offre est close depuis ; une clé reprise
pour une autre offre est refusée. Un refus ne consomme pas la clé.

| Champ | Sens |
|---|---|
| `applied`, `duplicate` | livraison appliquée maintenant / rejeu d'un reçu connu |
| `receipt`, `offer`, `need` | clé, offre, réserve |
| `value`, `points`, `level` | V comptée, points ajoutés (après borne 100), réserve après la livraison |
| `completed` | offre remplie (alors fermée) |
| `reward` | à la complétion seulement : `{ attitudeFact = "delivery", item = { type, count } ou nil }` ; l'appelant remet l'objet et enregistre le fait |

Raisons : `bad receipt key`, `group registry not ready`, `unknown group <id>`, `unknown offer <id>`, `receipt key
already used`, `group is hostile`, `bad player key`, `offer closed` (remplie, remplacée ou groupe sans vivant),
`offer expired`, `bad delivery`, `nothing delivered`, `item not accepted: <type>`, `bad count for <type>`,
`too many items`, `no game clock`, `group registry write failed`.

```lua
local r = API.deliver("grp-1", "grp-1-food-1", { ["Base.TinnedBeans"] = 6, ["Base.Rice"] = 4 }, "lk-2-delivery3-1")
-- r = { applied = true, duplicate = false, offer = "grp-1-food-1", need = "food", value = 20, points = 5, level = 25,
--       completed = false }
API.deliver("grp-1", "grp-1-food-1", { ["Base.TinnedBeans"] = 6, ["Base.Rice"] = 4 }, "lk-2-delivery3-1")
-- rejeu : { applied = false, duplicate = true, ..., points = 5, level = 25 } ; la réserve reste à 25
```

Confidentialité : une offre et un résultat ne contiennent ni foyer, ni journal, ni secret ; ils peuvent être projetés
vers le joueur concerné (les réserves sont déjà publiques dans `needs`). Le champ `supply` du registre (reçus, clés)
reste privé.

## Demandes d'aide (LK11-T06)

Point d'entrée serveur, hors de `LivingKnox.API` (autorité seulement) : `LivingKnox.Relations.requestAid(groupId,
playerKey, kind[, opts])`, `kind` ∈ `food`, `water`, `care`, `opts = { player, npc }`. Le groupe décide selon
l'attitude envers ce joueur et son stock réel, une demande au plus par groupe et par période ; un don sort du stock une
seule fois et arrive dans l'inventaire du joueur (ou au sol au pied du PNJ). Rend `{ accepted, reason, decided, item,
where, line, said, wait }` ou `nil, raison`. Règles, réplique et menu : [aide.md](conception/aide.md). Prévu pour une
intention fermée d'aide du LLM du carnet, revérifiée par le serveur (non branchée : le pont ne l'admet pas encore).

## Histoires enrichies (LK10-T03)

Point d'enrichissement de l'histoire d'un groupe par un autre mod (prévu : le LLM du carnet de RadioSurvivor). Le
moteur **n'appelle jamais** ce mod : sans lui, rien n'est écrit et `API.story` rend le gabarit composé par
`LK_Stories` ([recits.md](conception/recits.md)). Seul le **résumé public** se remplace ou se complète ; les secrets
de l'histoire ne sont ni lus, ni rendus, ni remplacés.

| Constante `API.STORY` | Valeur | Sens |
|---|---|---|
| `TEXT_MAX` | 600 | longueur du texte fourni, blancs de tête et de fin retirés (octets sous Lua 5.1, unités UTF-16 en Kahlua ; = `STORY_MAX`) |
| `LINES_MAX` | 8 | lignes au plus (séparées par `
`) |
| `LANGS` | `{ "en", "fr" }` | langues (celles des gabarits) |
| `MODES` | `{ "replace", "append" }` | le texte remplace le texte de base, ou s'y ajoute après un saut de ligne |
| `GROUP` | `"group"` | cible du groupe entier (sinon un membre `m-<k>`) |

Caractères refusés : contrôles autres que `
` (dont `	`, `
`), DEL, `<` et `>` (balises des panneaux de texte
riche du jeu). Lettres accentuées et ponctuation admises.

### `API.story(groupId[, lang[, memberId]]) -> { group, member, lang, text, source, mode, version, template } | nil, reason`

- `lang` : `en` ou `fr` (casse indifférente) ; toute autre valeur ou nil = anglais (comme `Stories.text`).
- `text` : texte à afficher ou à donner au LLM. `source` : `member` (texte du membre), `group` (texte du groupe) ou
  `template` (aucun texte fourni, ou texte invalide ou **périmé**) ; `mode` du texte retenu, nil pour le gabarit.
- Membre : son texte s'il en a un, sinon celui du groupe (texte fourni, sinon gabarit) ; un texte `append` d'un membre
  complète celui du groupe.
- `template` : résumé composé dans la langue (`summary.fr`/`.en` de `Stories.compose(type, storySeed)` ; sans graine,
  le résumé anglais du registre pour les deux langues).
- `version` : version du gabarit (`t1-<graine>-<empreinte>` du type, de la graine et des deux résumés composés),
  chaîne opaque à rendre telle quelle à `enrichStory`. Elle change si la graine, le type ou les données des gabarits
  changent : tout texte enregistré pour l'ancienne version est alors ignoré (repli sur le gabarit).
- Raisons : `group registry not ready`, `unknown group <id>`, `unknown member <id>`.

### `API.enrichStory(groupId, lang, text[, opts]) -> { group, member, lang, mode, version, cleared } | nil, reason`

- `lang` : `en` ou `fr` (obligatoire). `text` : texte borné, ou **nil pour retirer** le texte (retour au gabarit).
- `opts = { member = "m-<k>" (membre du groupe, mort compris ; sinon le groupe), mode = "replace" (défaut) | "append",
  version = version lue par API.story }`. Avec `version`, refus `stale version` si le gabarit a changé entre la lecture
  et la réponse du LLM ; sans elle, la version courante.
- Une seule écriture du registre (`LivingKnox.Groups.update`), qui retire aussi les entrées invalides, périmées ou d'un
  membre retiré. Le texte n'est jamais journalisé (console : `stories: en text of grp-1 set for group (replace)`).
- Raisons : `bad options`, `bad language`, `bad mode`, `bad version`, `bad text`, `empty text`, `text too long`,
  `too many lines`, `bad character in text`, `group registry not ready`, `unknown group <id>`, `unknown member <id>`,
  `stale version`, `group registry write failed`. Un refus n'écrit rien.
- Registre (privé, comme tout le registre des groupes) : `group.enrich = { ["<cible>:<langue>"] = { text, mode,
  version, day } }`, au plus (32 + 1) × 2 entrées.

```lua
local API = LivingKnox and LivingKnox.API
if API and API.enrichStory then
    local s = API.story("grp-1", "fr")                 -- s.text = gabarit, s.version = "t1-1234-…"
    -- … le LLM reçoit s.text (public) et rend une version enrichie …
    local r, why = API.enrichStory("grp-1", "fr", "Ils gardent la roue du moulin.",
        { mode = "append", version = s.version })
    -- r = { group = "grp-1", lang = "fr", mode = "append", version = s.version, cleared = false }
end
```

### Chemin prévu côté carnet (non branché)

1. Serveur, `RS_LivingKnox.context` (autorité) : lire `API.story(gid, langue de la requête, membre)` au lieu du seul
   `Stories.publicView` ; transmettre au pont `text` (public) et garder `version` côté serveur avec la requête.
2. Pont et LLM (`bridge/`, contrat RSV2) : un champ fermé facultatif de la réponse porte le texte proposé (une
   histoire du groupe ou du membre interrogé), sans autre effet.
3. Serveur, à la réponse : `API.enrichStory(gid, langue, texte, { member, mode, version })` ; un refus (bornes,
   version périmée) est journalisé et ignoré : le gabarit reste. Aucun secret n'est jamais donné au LLM
   (`publicView`, `API.story`), il ne peut donc pas en réécrire.
4. Client : rien de nouveau ; le texte arrive par les réponses du carnet comme aujourd'hui.

Rien de cela n'est fait par LK10-T03 : le moteur expose seulement le point d'entrée, et le carnet continue de lire le
gabarit.

## Faits publiés (E08-T07)

Crochets internes du moteur, relayés depuis LK12-T02 par les [événements publics](#événements-publics-lk12-t02) (un
mod tiers préfère ces derniers : charge utile publique, une fois par fait) : le moteur **publie**, un consommateur
**s'abonne** ; aucune dépendance du moteur vers le consommateur. Autorité seulement.

- `LivingKnox.listen(name, key, fn)` : abonné `fn(info)`, idempotent par `key` (un rechargement remplace l'abonné).
- `LivingKnox.publish(name, info)` : appelle les abonnés dans l'ordre d'inscription, chacun sous `pcall` (erreur
  journalisée `ERROR listener <clé> of <nom> failed`), rend le nombre d'abonnés réussis.
- `info` est propre à l'autorité (peut contenir un objet du moteur) : **jamais à envoyer tel quel à un client** ; le
  foyer exact (`x`, `y`) n'en sort qu'en maille (le carnet le réduit à `area-<x>-<y>`).

| Nom | Publié par | `info` |
|---|---|---|
| `memberDied` | `LK_Bodies.onZombieDead` (corps courant d'un PNJ membre d'un groupe, après `Bodies.onDied`) | `{ group, member, npc = "lk-<n>", day, offscreen = false, body = zombie mort, cause, killer, weapon }` (`cause`, `killer`, `weapon` : LK07-T04, comme `npc.death`) |
| `npcDied` | `LK_Bodies.onZombieDead` (LK07-T04 : mort du corps courant de **tout** PNJ, une fois, après le registre des groupes) ; point d'appel de l'événement public de LK12-T02 | `{ npc = "lk-<n>", generation, cause = melee \| firearm \| fire \| vehicle \| zombie \| bleeding \| other \| unknown, killer = compte ou nil, weapon = type ou nil, burning = true ou nil, group, member (nil hors groupe), x, y, z = case du corps, body = zombie mort (le cadavre n'existe pas encore) }` |
| `memberDied` | `LK_Groups.applyDeath` (simulation hors écran et `markDead`) | `{ group, member, npc ou nil, day, offscreen = true, witnesses = { "lk-<n>", ... } (PNJ des membres vivants au foyer, hors équipe d'expédition, triés), x, y = foyer ou nil }` |
| `memberHit` | `LK_Bodies.onHitZombie` (E09-T06 : coup d'un joueur avec une arme sur le corps courant d'un membre de groupe, avant les dégâts) | `{ group, member, npc = "lk-<n>", player = IsoPlayer, u = compte, category = melee \| firearm \| fire, weapon = type, ms }` |
| `assaultSeen` | `LK_Hostility.record` réussi, `witnessed = true`, fait `hit`, `shot` ou `kill` | `{ group, player = clé de joueur, fact, day, witnesses = opts.witnesses (chaînes seules), x, y = opts.x, opts.y ou nil }` |
| `groupCreated` | `LK_Groups.applyCreate` (LK12-T02 : `create` et population initiale, avant l'écriture du registre) | `{ group, type, day }` |
| `memberLeft` | `LK_Groups.applyLeave` (LK12-T02 : `removeMember`, départ hors écran de LK09-T05, futur départ d'E10-T04) | `{ group, member, npc ou nil, role, alive = vivant au départ, day, reason = argument facultatif ou nil }` |
| `groupRemoved` | `LK_Groups.remove` (LK12-T02) | `{ group, alive = vivants au retrait, day }` |
| `encounterStarted` | `LK_Encounters` (LK12-T02 : nouvelle rencontre, étape `start` ; pas une reprise) | `{ group, npc = guetteur, player = compte, level = hostile \| wary, n = numéro de rencontre }` |
| `aidDecided` | `LK_Relations.requestAid` (LK11-T06 : don accepté ou refus pour l'attitude ou le stock ; pas les refus « again », « away » ni les entrées invalides) | `{ group, player = clé de joueur, kind = food \| water \| care, accepted, reason = given \| attitude \| short, item = type donné ou nil, where = inventory \| ground \| nil, npc ou nil, day }` |
| `tradeDone` | `LK_Trade.propose` (LK11-T08 : troc accepté et appliqué ; pas les refus) | `{ group, player = clé de joueur, got = types reçus par le groupe (texte), gave = types cédés (texte), given = valeur donnée, asked = prix demandé, npc ou nil, day }` |
| `revengeSworn` | `LK_Relations.memberKilled` (LK11-T05 : serment après le meurtre d'un membre par un joueur identifié) ; point d'appel prévu de la radio du carnet | `{ group, player = clé de joueur, victim = "m-<k>", n = 0, fails = 0, day, due = heure de jeu du départ, x, y = lieu de la mort }` |
| `revengeStarted` | `LK_Relations.offscreenHour` (LK11-T05 : départ d'une équipe, dans le pas de la simulation) | `{ group, player, victim, n = numéro de tentative, fails, day, team = { "m-<k>" }, x, y = dernière zone connue, src = kill \| safehouse }` |
| `revengeEnded` | `LK_Relations` (LK11-T05 : fin de la vengeance) | `{ group, player, victim, n, fails, day, ending = avenged \| target_dead \| faded \| given_up \| wiped }` |
| `raidScouting`, `raidAnnounced`, `raidLaunched`, `raidEnded` | `LK_Raids` (LK11-T07 : départ des éclaireurs, annonce à la fin du guet, départ de l'attaque, fin du raid) ; `raidAnnounced` est le point d'appel prévu de la radio du carnet | `{ group, base = "b:<id>" \| "sh:x,y", x, y = centre de la base, src = building \| safehouse, players = clés du carnet (ou comptes) des occupants, day }` ; plus `team` (départs, annonce), `hours` (annonce : heures avant l'attaque), `ending = cancelled \| done \| wiped \| peace \| disabled \| forgotten` (fin) |

`Hostility.record` accepte donc deux champs facultatifs de plus dans `opts` (ajout compatible) : `witnesses` (PNJ qui
ont vu l'agression, connus de l'appelant seul : le combat de LK06) et `x`, `y` (lieu de la scène).

## Événements publics (LK12-T02)

Six événements Lua **déclarés par `LuaEventManager.AddEvent`** sur l'autorité (serveur dédié ou hébergé, solo), au
chargement de `LK_API.lua`. `AddEvent` est idempotent : il rend l'événement déjà déclaré sans recréer
`Events[nom]` (`zombie/Lua/LuaEventManager.java:615-631`, 42.21 ; base `multiplayer.md`, « Événements Lua partagés entre
mods »). Noms dans `API.EVENTS` :

| Clé | Nom de l'événement | Fait source |
|---|---|---|
| `groupCreated` | `OnLivingKnoxGroupCreated` | `groupCreated` (création, population initiale et relève d'un groupe disparu comprises, LK09-T04) |
| `memberDied` | `OnLivingKnoxMemberDied` | `npcDied` d'un membre (corps présent) ; `memberDied` hors écran (`offscreen = true`) |
| `groupGone` | `OnLivingKnoxGroupGone` | dernier vivant mort ou parti ; `groupRemoved` d'un groupe encore vivant |
| `needCritical` | `OnLivingKnoxNeedCritical` | sondage `EveryTenMinutes` des réserves publiques `needs` |
| `encounter` | `OnLivingKnoxEncounter` | `encounterStarted` (sommation LK11-T02 commencée) |
| `memberLeft` | `OnLivingKnoxMemberLeft` | `memberLeft` d'un membre vivant (LK09-T05, `removeMember`, E10-T04) |

### Déclenchement

- **Une seule fois par fait** : clé de fait gardée pour la session (`died|<groupe>|<membre>`, `left|…`, `created|…`,
  `gone|<groupe>`, `enc|<groupe>|<compte>|<n>`). Une double publication interne (mort d'un corps présent, puis
  `markDead` hors écran pour le même membre) ne donne qu'un événement. Un fait n'existe qu'une fois (une mort, un
  départ, une création) : un redémarrage ne rejoue rien.
- **Après la transaction** : les faits sont mis en file (au plus `EVENT_QUEUE_MAX` = 256, le plus ancien abandonné)
  et déclenchés au pas suivant (`OnTickEvenPaused`, aussi sur un serveur dédié en pause `PauseEmpty`) par
  `API.flushEvents()`. La charge utile est **relue dans le registre** à ce moment : un groupe peuplé dans la même
  transaction annonce ses membres (`alive`), un fait sur un groupe ou un membre absent est écarté. Registre non prêt
  ou bloqué (écriture refusée) : faits abandonnés, `ERROR events: group registry not ready, <n> fact(s) dropped`.
- Un fait produit par un abonné pendant un déclenchement part au pas suivant. Une erreur d'abonné est journalisée
  par le jeu (`Event.trigger` appelle chaque abonné sous protection, `zombie/Lua/Event.java:29-64`, `protectedCallVoid` et `ExceptionLogger`) et n'arrête ni
  les suivants ni le moteur.
- **Groupe disparu** : jugé après tous les faits d'un pas, avec la raison du dernier fait du groupe (`dead` ou
  `left`) ; seulement pour un groupe qui a eu au moins un membre. `removed` : groupe retiré du registre alors qu'il
  avait encore un vivant (un groupe vidé puis retiré a déjà été annoncé).
- **Besoin critique** : réserve publique (`needs.food`, `medical`, `ammo`, comme `listGroups`) sous `NEED_LOW`
  (25, `Config.SIMULATION`), groupe avec au moins un vivant ; l'état critique ne cesse qu'à `NEED_OK` (40) ou plus
  (hystérésis : une oscillation autour de 25 ne répète pas l'événement) ; une nouvelle chute après une remontée à 40
  est un nouveau fait. Le premier sondage d'une session relève les besoins déjà critiques **sans** événement (aucune
  répétition après un redémarrage) ; un groupe apparu ensuite est jugé normalement.
- **Rencontre** : début d'une sommation d'un groupe envers un joueur (LK11-T02), pas une reprise dans les
  `RESUME_MS` ; une rencontre oubliée puis recommencée est un nouveau fait.

### Charges utiles

Un seul argument : table neuve de chaînes, nombres, booléens et tables simples, **partagée** par les abonnés d'un
même déclenchement (ne pas la modifier). Ni foyer exact (maille `area` de 100 cases seulement), ni journal, ni
secret, ni objet Java, ni tueur, ni arme, ni témoins.

| Événement | Champs |
|---|---|
| `OnLivingKnoxGroupCreated` | `group`, `type`, `typeNameKey` (à traduire chez le client), `name`, `day` (fondation), `alive` (au déclenchement), `area` ou nil |
| `OnLivingKnoxMemberDied` | `group`, `member`, `npc` ou nil, `role`, `offscreen` (vrai : simulation hors écran), `cause` (corps présent : `melee`, `firearm`, `fire`, `vehicle`, `zombie`, `bleeding`, `other`, `unknown` ; nil hors écran), `byPlayer` (tueur connu, sans son nom), `area` (maille du corps, sinon du foyer, ou nil), `groupAlive`, `day` |
| `OnLivingKnoxGroupGone` | `group`, `reason` = `dead` \| `left` \| `removed`, `total` (membres encore connus, morts compris ; nil pour `removed`), `day` |
| `OnLivingKnoxNeedCritical` | `group`, `need` (`food`, `medical`, `ammo`), `level`, `threshold` (25), `alive`, `day` |
| `OnLivingKnoxEncounter` | `group`, `npc` (guetteur), `player` (nom de compte), `level` (`hostile` \| `wary`), `day` |
| `OnLivingKnoxMemberLeft` | `group`, `member`, `npc` ou nil, `role`, `reason` (nil = non précisée, par exemple départ hors écran de LK09-T05 ; E10-T04 passera `"leave_group"` à `Groups.applyLeave` ; `"dispersed"` = dernier survivant d'un groupe dispersé, LK09-T04), `groupAlive`, `day` |

`day` = jour du fait (1 = premier jour). `player` et le niveau d'une rencontre concernent un seul joueur : comme
l'attitude, ils ne s'envoient qu'à lui.

### S'abonner sans dépendance

```lua
-- Fichier serveur d'un mod tiers (media/lua/server) : marche avant, après ou sans Living Knox.
if isClient() then return end
local MY = "OnLivingKnoxMemberDied"
LuaEventManager.AddEvent(MY)          -- idempotent : déclare le nom si Living Knox n'est pas (encore) chargé
Events[MY].Add(function(e)
    print(string.format("[MyMod] %s lost %s (%s)", e.group, e.member, tostring(e.cause)))
end)
```

Sans Living Knox, l'événement existe mais ne part jamais. Lire plus de détails : `LivingKnox.API.getGroup(e.group)`
(tester `LivingKnox and LivingKnox.API`).

**Côté client** : rien n'est déclaré ni déclenché chez un client MP (`LK_API.lua` s'y arrête). Un abonné client
(`Events.OnLivingKnoxX.Add` sans `AddEvent`) planterait sur `Events.OnLivingKnoxX` nil ; avec `AddEvent`, il ne reçoit
jamais rien. Pour informer un joueur, l'abonné serveur envoie sa propre commande (`sendServerCommand`) avec une
projection qui ne rajoute rien de privé.

## Fonctions de test (E01-T10)

Code : `server/LivingKnox/LK_APITest.lua` (même table `LivingKnox.API`, chargé après `LK_API.lua`). Tests : `tests/test_lk_apitest.py`. Consommateur : la fixture `RST.Fixtures.spawnNpc` du mod de développement (suite en jeu `rst.fixtures.npc`).

Ces fonctions **écrivent** (registre des PNJ et corps, par `LivingKnox.Bodies.spawn` et `despawn`) et ne servent qu'aux tests en jeu. Elles refusent d'agir hors de l'autorité, hors du **mode debug** de la machine qui les exécute (E01-T18 : `isDebugEnabled()` = `Core.debug` ; client ou solo lancé avec `-debug`, serveur dédié lancé avec la propriété Java `-Ddebug`, car `GameServer` ignore un argument `-debug` ; le serveur de test de `tools/autoclient` la reçoit) et hors d'une **partie de test** : nom de partie (`getWorld():getWorld()`) commençant par `API.TEST_SAVE_PREFIX` = `"rstest"`, sans tenir compte de la casse (même règle que la garde `world` du moteur de tests). Sur un serveur dédié, ce nom est celui du serveur (`-servername`). Chaque refus de `testSpawnNpc` ou `testRemoveNpc` est écrit dans la console : `[LivingKnox] test API <fonction> refused: <raison>` (raison hors debug : `debug mode off (isDebugEnabled() is false on this machine)`).

| Fonction | Rend | Sens |
|---|---|---|
| `API.testAllowed()` | `true`, ou `false` et une raison | les fonctions de test peuvent agir ici (autorité, mode debug, partie `rstest*`) |
| `API.testSpawnNpc(x, y, z[, profile])` | `"lk-<n>"`, ou `nil` et une raison | nouveau PNJ **sans groupe** et son corps sur la case chargée et libre la plus proche (règle de `Bodies.spawn`) ; `profile` = entrée de `LivingKnox.Appearance.normalize` (`{}` par défaut). Refus : partie normale, mode debug coupé, client MP, moteur coupé, case non chargée, aucune case libre, plafond de corps |
| `API.testRemoveNpc(id)` | `true` et le nombre de corps retirés, ou `false` et une raison | retire le corps et oublie le PNJ (`Bodies.despawn(id, true)`, consignes du PNJ effacées) ; **seulement un PNJ créé par `testSpawnNpc` dans cette session Lua** ; un corps hors zone chargée (0 retiré) est retiré comme orphelin à son retour |
| `API.testNpcs()` | liste triée (copie) | PNJ de test encore présents |

Aucun objet Java n'est rendu : le corps se retrouve par le fournisseur du carnet (`RS_NPCProvider.objects()`, identifiant = id du PNJ) ou par `LivingKnox.Bodies.find(id)` côté autorité. La liste des PNJ de test n'est pas sauvegardée : après un rechargement du Lua, un PNJ de test oublié reste un PNJ ordinaire du registre (`LivingKnox.Bodies.despawn(id, true)` pour le retirer).

## Volontairement absent

| Donnée | Pourquoi |
|---|---|
| Secrets d'histoire | privés au serveur ([recits.md](conception/recits.md)) ; seul le résumé public est rendu, et seul lui peut être enrichi (`API.enrichStory`). Une histoire complète, si elle est exposée plus tard, passera par `LivingKnox.Stories.publicView`. |
| Coordonnées exactes du foyer, étage | elles désigneraient la base d'un groupe à tout client ; la maille de 100 cases suffit pour situer un groupe dans une ville ou un quartier. Aucun nom de lieu n'est disponible en version 1. |
| Journal technique du groupe (`log`) | privé (textes libres, coordonnées, comptes de joueurs) ; le récit public passe par `API.journal` (LK10-T02). |
| Blessures (`wound`), repos (`rest`), heure simulée, compteurs internes (`nextMember`, `nextId`) | état interne de la simulation, sans sens stable pour un consommateur ; leur forme peut changer sans nouvelle version de l'API. |
| Noms des membres et du chef | non tenus par le registre en version 1 (`leader.name` = nil) ; un ajout futur sera un champ nouveau, compatible. |
| Profil d'apparence, vêtements, arme, cause de mort d'un PNJ | relèvent du registre des corps et du carnet (`RS_NPCProvider`) ; hors de cette tâche. |
| Objets Java (corps, joueurs, cases) | jamais rendus : un consommateur retrouve un corps par son identifiant côté autorité, par le fournisseur du carnet (E17-T03). |
| Valeur numérique de l'attitude, faits, marqueur de meurtre, liste des joueurs d'un groupe | internes (E09-T01 : aucun score affiché) ; seuls `level` et `trend` sortent, pour un joueur donné. `LivingKnox.Hostility.forGroup` (clés de joueurs) reste réservé au serveur. |
| Tueur, arme, témoins, case exacte d'une mort | dans les faits internes seulement (`LivingKnox.listen`) ; l'événement public dit `cause`, `byPlayer` et la maille. |
| Événements côté client | aucun (autorité seulement) : l'abonné serveur relaie lui-même ce qu'un joueur doit savoir. |
| Retrait des objets d'un inventaire, remise de la récompense | à l'appelant (transaction du carnet) : l'API ne touche aucun inventaire. |

## Limites

- Histoires enrichies (LK10-T03) : banc lupa seulement (pas encore dans la VM Kahlua : longueurs en unités UTF-16 et empreinte à vérifier) ; aucun consommateur branché ; l'empreinte de version est calculée par la VM qui l'écrit (lupa et Kahlua donnent des empreintes différentes pour un texte accentué, sans effet en jeu).
- Hors jeu seulement : banc lupa (doublures du moteur) et VM Kahlua réelle pour la logique. Aucun test en jeu propre à cette tâche ; à observer avec E17-T03.
- Événements (LK12-T02) : mémoire de session (clés de fait, état critique) ; un besoin devenu critique pendant un arrêt du serveur n'est pas annoncé ; la mort d'un PNJ hors groupe n'est pas un « membre mort » (fait interne `npcDied` seulement) ; un groupe créé puis retiré avant le pas suivant n'annonce que sa disparition (`removed`) ; `alive` et `groupAlive` sont lus au déclenchement (pas suivant), pas à l'instant exact du fait.
- `npcsNear` s'appuie sur la dernière position vue pour un corps non lié (hors zone chargée, ou pas encore relié après un redémarrage) : elle date du dernier balayage qui l'a vu et peut être ancienne ; un corps lié donne sa position courante (`inWorld` distingue les deux).
- Le rayon est comparé en distance horizontale ; l'étage n'est pas filtré (`floor` le rend au consommateur, qui applique sa propre règle, par exemple `RS_NPCProvider.near`).
- Offres (LK12-T03) : aucun stock réel d'objets (LK08-T07, LK09-T06 à venir) ; la récompense est prise sur une réserve abstraite, l'objet est créé par l'appelant. Le multiplicateur de besoin du barème (× 1,5 sous 25…) ne s'applique qu'au troc (LK11-T08), pas à la conversion en réserve. Un état `supply` malformé (édition manuelle du fichier) est remis à neuf : offres ouvertes et reçus perdus, numérotation gardée si lisible. Seuils et valeurs à recalibrer en jeu avec E17-T03.
