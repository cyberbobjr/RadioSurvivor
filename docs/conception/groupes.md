# Registre des groupes

- Tâches : LK08-T01 (création), LK08-T02 (types de groupes et profils de membres en données), LK08-T05 (population initiale et réglages) ; servira LK08-T03/T04 (foyers), LK08-T06/T07 (stock et besoins), LK05-T09 (succession en jeu)
- Build : 42.21.0 — Date : 2026-10-10 — Statut : brouillon

Code : `media/lua/server/LivingKnox/LK_Groups.lua` (registre, API, persistance), mécanisme de fichiers partagé avec le registre des PNJ dans `LK_Store.lua` (`readSlotFile`, `writeSlotFile`, `worldFileBase`), rôles en liste fermée dans `media/lua/shared/LivingKnox/LK_Config.lua` (`GROUP_ROLES`), types de groupes dans le registre `media/lua/shared/LivingKnox/LK_GroupTypes.lua` rempli par les fichiers de données `media/lua/shared/LivingKnox/Data/LK_Type_<id>.lua` (LK08-T02, section « Types et profils »), relecture à `OnInitGlobalModData` dans `LK_Server.lua`.

## Problème

Chaque groupe de Living Knox (colons, pillards, neutres) a une identité stable tenue par l'autorité (serveur dédié ou solo) : type, nom, histoire courte, chef, membres et leurs rôles, foyer, besoins (nourriture, soins, munitions), moral et journal. Le registre doit survivre au redémarrage sans ModData globale, refuser proprement un fichier d'une autre version et ne perdre qu'un groupe abîmé, pas tous.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `OnInitGlobalModData(isNewGame)` part avant la cellule, avec `WorldDictionary.isIsNewGame()` : moment de relecture du registre et détection d'un monde neuf. | `J/world/moddata/GlobalModData.java:56` ; base `world-placement.md` ; [corps-registre.md](corps-registre.md) | confirmé statiquement |
| Aucune ModData globale pour un état privé (lisible par tout client). | base `multiplayer.md` | confirmé statiquement |
| Fichiers `getFileWriter` du serveur : extension `.txt` admise, nommés d'après la partie ; ils survivent à l'effacement du monde (d'où la règle « monde neuf »). | base `kahlua-lua.md` (extensions de `getFileWriter`), `multiplayer.md` (liste MP, point 8) | confirmé statiquement |
| Un client MP charge aussi `media/lua/server` : garde `isClient()` en tête de fichier. | base `mod-loading.md` | confirmé statiquement |
| Serveur dédié : sauvegarde du monde (`ServerMap.preupdate` → `QueuedSaveAll`) et arrêt (`quit` → `System.exit` à l'image suivante, sauvegarde par le crochet d'arrêt) en tête d'image, avant le Lua de l'image (`OnTickEvenPaused` … `EveryOneMinute`/`EveryHours` … `OnTick`) ; `OnSave` seulement depuis `GameWindow.save` (solo, client MP), jamais sur un serveur. | base `world-placement.md` (LK13-T06) ; `GameServer.java:958-1073`, `ServerMap.java:322-491`, `GameWindow.java:1025-1071` | confirmé statiquement |
| `getWorldAgeHours()` vaut 0 à 7 h le premier jour (flottant, d'après les nuits survécues) : le « jour de jeu » du journal change à 7 h, pas à minuit. | base `api-42-21.md` (calendrier de `GameTime`) | confirmé statiquement |
| Chaînes Kahlua en unités UTF-16 : les longueurs bornées (`#s`) comptent ces unités ; la coupe d'un texte trop long peut séparer une paire de substitution (U+FFFD à l'écriture RSV2). | base `kahlua-lua.md` ; `RS_Codec.lua` (en-tête) | confirmé statiquement |

## Choix

Retenu le 2026-10-10 (LK08-T01), dans le cadre de `docs/plan/README.md` (autorité serveur, aucun secret en ModData globale) et du contrat de la tâche.

**Schéma 1** (`LK_Groups.SCHEMA = 1`) :

```
{ schema = 1, nextId = <n>, groups = { ["grp-<n>"] = group } }
group = { id, type, name, story, founded, leader, nextMember, members, home, needs, morale, log }
member = { id = "m-<k>", role, alive, npc }
```

| Champ | Contenu et bornes |
|---|---|
| `id` | `grp-<n>`, tiré de `nextId`, qui ne recule jamais (numéro jamais réutilisé, même après `remove`) |
| `type` | identifiant d'un type enregistré dans `LivingKnox.GroupTypes` (livrés : `settlers`, `raiders`, `neutrals` ; section « Types et profils ») |
| `name` | 1 à 64 unités ; `story` : 0 à 600 |
| `founded` | jour de jeu de la création |
| `leader` | identifiant d'un membre **vivant**, ou absent |
| `nextMember` | prochain numéro de membre du groupe (jamais réutilisé) ; l'ancienneté d'un membre est son numéro |
| `members` | au plus 32 ; `role` dans `Config.GROUP_ROLES` (`deputy`, `fighter`, `scout`, `medic`, `worker`, puis `breaker` ajouté en fin de liste par LK08-T02 ; liste fermée), `alive` booléen (mort définitive), `npc` = identifiant `lk-<n>` du registre des corps ([corps-registre.md](corps-registre.md)), facultatif ; un PNJ appartient à un seul membre de tout le registre |
| `home` | `{ x, y, z }` entiers (x, y ≥ 0, z dans −32..31), ou absent ; aucune case n'est chargée |
| `needs` | `food`, `medical`, `ammo` : entiers 0..100 (défaut 50) |
| `morale` | entier 0..100 (défaut 50) |
| `log` | les 32 dernières entrées `{ day, kind, text }`, la plus ancienne d'abord ; `kind` = lettre puis lettres, chiffres, soulignés (24 au plus) ; `text` coupé à 200 |

Champs facultatifs ajoutés par la simulation hors écran (LK09-T01, [simulation.md](simulation.md)), sans changer de schéma : `simHour` (registre, dernière heure simulée ; invalide : oublié), `rest` 0..100 et `task` (groupe), `wound` 0..100 (membre, absent = 0) ; puis `expedition` (groupe, LK09-T02 : lieu, équipe, heures de départ et de retour ; section « Expéditions » de [simulation.md](simulation.md)) ; invalides, ils font écarter le groupe comme tout autre champ. Fonctions pures partagées : `applyDeath` (utilisée par `markDead` ; paramètre `quiet` : sans fait `memberDied`, pour la mort d'un membre incarné déjà publiée avec son corps, LK09-T03), `applyLeader` (par `setLeader`), `applyLeave` (par `removeMember` et l'événement `departure` de LK09-T05 : membre retiré, entrée `left`), et `update(fn)` (modification groupée, une seule sauvegarde). Les événements de groupe (LK09-T05, section « Événements » de [simulation.md](simulation.md)) n'ajoutent aucun champ : seulement des entrées de journal (`departure`, `recruit`, `conflict`, `illness`, `clash`, `remains`).

Champs facultatifs du cadre de décision (LK05-T02, [decisions.md](decisions.md)), sans changer de schéma : `objective` (groupe, dernier objectif choisi) et `duty` (membre, dernier poste attribué), contrôlés dans leur forme (celle d'un `kind` de journal) ; une valeur hors des listes fermées de `LK_Decisions` est remplacée à la notation suivante. Chaque changement d'objectif ou de poste ajoute une entrée `objective` au journal.

Champ facultatif du journal de récit (LK10-T02, [journal.md](journal.md)), sans changer de schéma : `journal` (groupe : `{ v, n, e }`, 40 entrées datées publiques), non contrôlé par `LK_Groups` : `LK_Journal` le contrôle et le remet à neuf s'il est malformé. Il est tiré de `log` au moment de l'écriture : chaque entrée technique passe par `Groups.onLog` (accroche de `appendLog`, erreur journalisée sans interrompre l'écriture) ; `Groups.hourContext` porte l'heure simulée posée par `LK_Simulation.advance`. `log` reste le journal technique privé.

Champ facultatif des besoins individuels (LK05-T06, [besoins.md](besoins.md)), sans changer de schéma : `vitals` (membre : `hunger`, `thirst`, `fatigue`, `fear` entiers 0..100 et `hour`, heure du dernier pas), non contrôlé par `LK_Groups` : `LK_Needs` le contrôle et le remet aux valeurs de départ s'il est malformé, sans écarter le groupe.

Bornes : point de départ propre au mod (3 à 5 groupes de 4 à 8 membres prévus par LK08-T05), avec une large marge ; au plus 64 groupes.

Le jour de jeu vaut `floor(getWorldAgeHours() / 24) + 1` (1 = premier jour) ; un appel peut aussi passer un jour explicite.

**API** (`LivingKnox.Groups`, autorité seulement ; chaque fonction rend son résultat, ou `nil` et une raison en anglais ; les lectures rendent des **copies**, sauf `peek`, voir « Lecture en place ») : `create(spec)`, `get(id)`, `peek(id)`, `list()` (identifiants triés), `remove(id)`, `addMember(id, { role, npc, day })`, `removeMember`, `markDead`, `setRole`, `setNpc`, `findNpc(npc)`, `setLeader(id, mid|nil)`, `successor(id)`, `succeed(id)`, `setNeed`/`addNeed`, `setMorale`/`addMorale` (arrondis puis bornés), `setHome(id, x, y, z)` (sans argument : effacé), `addLog(id, kind, text, day)`, `today()`. Les changements structurels s'inscrivent d'eux-mêmes au journal (`founded`, `joined`, `left`, `died`, `leader`).

**Succession (I6.6, API seulement)** : la mort ou le départ du chef laisse le groupe **sans chef** ; rien ne se passe seul. `successor` désigne, parmi les membres vivants autres que le chef, le rôle le plus prioritaire dans l'ordre de `Config.GROUP_ROLES` (`deputy` d'abord), puis le plus ancien (plus petit numéro). `succeed` l'installe et l'inscrit au journal. Le délai de « dispersion brève » et le repli collectif relèvent des comportements (LK05-T09).

**Persistance** : fichiers `Zomboid/Lua/batman_RadioSurvivor/livingknox/groups-<hex du mode/nom de partie>-<0|1>.txt`, même format que le registre des PNJ (`LKGRP1=<numéro>`, octets RSV2 en hex, somme de contrôle, `end`), deux emplacements en alternance. Relecture à `OnInitGlobalModData`, rattrapage paresseux au premier usage après une remise à zéro du Lua ; monde neuf : registre vide, numéros d'écriture poursuivis pour que le neuf gagne.

**Écriture regroupée (LK13-T06)** : un changement (API ou `Groups.update`) marque seulement le registre « à écrire » (`state.dirty`, registre gardé dans `state.pending`) ; l'écriture complète (encodage RSV2, hex, somme) a lieu **une fois par image** :
- à la fin de l'image : abonné `OnTick` `Groups.flush`, inscrit au chargement puis remis en fin de liste au premier `OnTickEvenPaused` (même fonction retirée puis rajoutée depuis un autre événement : aucun double appel, base `kahlua-lua.md`) ; il suit donc les autres abonnés du moteur, inscrits au chargement, et les pas `EveryOneMinute` / `EveryHours` (déclenchés par `GameTime.update` entre `OnTickEvenPaused` et `OnTick`) ;
- au début de l'image suivante (`OnTickEvenPaused` `Groups.flushPaused`), seulement pour des changements restés une image entière sans écriture : serveur en pause (`PauseEmpty` : `OnTick` n'est pas déclenché), abonné ajouté après le premier passage, commandes réseau traitées entre deux images ;
- à `OnSave` (`GameWindow.save` : solo, sortie au menu) ; **jamais** sur un serveur dédié, dont la sauvegarde (`ServerMap.QueuedSaveAll`) ne déclenche aucun événement Lua : la fin d'image suffit ;
- avant une relecture (`Groups.init`, rattrapage paresseux) : rien d'écrit n'est perdu par un rechargement ;
- **tout de suite** quand l'appelant l'exige, par `Groups.flush()` (rend vrai si le fichier est à jour) : marques idempotentes écrites avant de toucher au monde ou effacées seulement après l'écriture — `LK_Stock.applyPending` et `LK_Fortify.applyPending` (marques `LKStockOp` / `LKFortOp` effacées après un registre **écrit**, LK09-T06 / LK14-T05), marques « en cours » `LK_Homes` (aménagement), `LK_Stock` (remplissage), `LK_Traces` (carnet du foyer, notes du chef), échange `LK_Trade.apply` (objets déplacés après l'écriture). Les marques « fait » qui suivent restent différées : une marque « en cours » relue après un arrêt suffit à éviter une seconde pose.
- **Relecture de contrôle** : à la première écriture de la session, puis sur demande (`Groups.flush({ verify = true })`, `Groups.verifyFile()`, qui bloque le registre si le fichier ne porte pas la dernière écriture) ; plus à chaque écriture. Une écriture refusée (fichier non ouvert, sérialisation) bloque le registre comme avant ; l'appel qui avait fait le changement a déjà rendu son résultat, les suivants rendent `group registry not ready`.
- Hex et somme de contrôle par `LK_Store.hexOfBytes` (table de remplacement de `gsub`) et `LK_Store.checksumOfBytes` (modulo par blocs de 4 000 octets) : mêmes chiffres que `RS_Codec.hexBytes` / `checksumBytes` (bancs lupa et Kahlua), lus par le lecteur commun.
- **Garantie** : arrêt propre (`quit` : la commande est traitée après la sauvegarde de l'image, le Lua de cette image tourne encore, sortie à l'image suivante) : rien de perdu des changements faits avant le dernier `OnTick`. Arrêt brutal : au plus les changements de l'image en cours (100 ms sur un serveur dédié), contre aucun auparavant ; seules les commandes réseau arrivées après le dernier `OnTick` d'un arrêt propre restent exposées de la même façon (moins d'une image). Une sauvegarde complète du monde sur serveur (`SaveAll`, au plus toutes les `SaveWorldEveryMinutes`, ou à l'arrêt) a lieu en tête d'image, avant le Lua : le registre peut y avoir une image de retard, ce que les marques ci-dessus couvrent.
- Encodage plus rapide (LK13-T06, 2026-10-15 ; mêmes octets) : `RS_Codec.encodeBytes` remplit un seul tampon de
  sortie, calcule une fois par appel le texte de tri et la forme encodée de chaque clé et des chaînes courtes, trie
  par insertion les tables de 12 clés au plus ; somme de contrôle par seize octets d'un appel `string.byte` ;
  relecture par `LK_Store.unhexOfBytes` (table de remplacement) et la somme rapide. Écriture du registre du banc
  (21,6 Ko) dans la VM Kahlua : 7,7-8,6 → 5,3-5,6 ms.
- Mesure : [charge-groupes-2026-10-12.md](../validation/charge-groupes-2026-10-12.md),
  [charge-ecriture-etapes-2026-10-15.md](../validation/charge-ecriture-etapes-2026-10-15.md).

**Écriture retenue (LK13-T09)** : un travail étalé sur quelques images retient l'écriture de fin d'image pour n'écrire qu'une fois, à sa fin : `Groups.hold(clé, images)` puis `Groups.release(clé)` et `Groups.flush()` si plus aucune retenue n'est en cours (`Groups.isHeld()`). Deux clés aujourd'hui : `"hour"` (pas horaire de `LK_Simulation`, fiche [charge.md](charge.md), « Pas horaire étalé ») et `"stock"` (relecture de la minute, [stock.md](stock.md), « Relecture étalée »). Chaque retenue perd une image à chaque début d'image (`OnTickEvenPaused`) et tombe d'elle-même à zéro (12 images pour le pas horaire, nombre de groupes + 3 pour le stock) : jamais de changement gardé sans écriture au-delà, même si la fin du travail ne vient pas. `Groups.flush()` explicite (marques idempotentes, `OnSave`) écrit toujours tout de suite. Garantie : un arrêt pendant une retenue, propre (`quit`, aucun événement Lua sur un serveur dédié) ou brutal, peut laisser hors du fichier les changements de ces quelques images (1,2 s au plus sur un serveur dédié, contre une image auparavant). Ils sont refaits au redémarrage : simulation et besoins rattrapés à l'identique d'après `simHour` et l'heure de chaque membre, notation des objectifs et relecture du stock refaites au passage suivant ; les marques idempotentes (aménagement, remplissage, écarts appliqués, échanges) passent toujours par `Groups.flush()` et ne sont jamais retenues. Changement de la garantie de LK13-T06 : décision à confirmer.

**Lecture en place (LK13-T08)** : `Groups.get(id)` rend une copie profonde du groupe (journal, membres, plans compris), ce qui coûtait la moitié du module `LK_Obstacles` au banc (relevé des foyers, clé du foyer d'un PNJ, environ un appel par image). `Groups.peek(id)` rend le groupe **vivant** du registre, sans copie, ou `nil` et une raison. Règle (en tête de la fonction dans `LK_Groups.lua`) :
- **lecture seule** : aucune écriture dans la table rendue ni dans ses sous-tables (champ, `table.insert`/`remove`/`sort`, passage à une fonction qui écrit) ; toute écriture passe par l'API ou `Groups.update` ;
- **pas de conservation** au-delà de l'appel en cours (la vue suit les changements suivants et peut sortir du registre), pas de vue rendue à un appelant ; recopier les valeurs simples utiles ;
- réservée aux passages fréquents qui lisent quelques champs : `LK_Obstacles.refreshHomes`, `homeKeyOf`, `typeHostility`, et les contrôles d'entrée de `LK_Stock.check` (appelé à chaque minute de jeu par groupe ; la copie n'est faite qu'une fois la zone du foyer chargée et ses conteneurs trouvés). `LK_Decisions`, `LK_Routines` et `LK_Needs` lisaient déjà `Groups.state.data` en place (inchangés).
- **Protection** : (1) lecture du code par le banc (`tests/test_lk_groups.py`, `peek_writes`) : dans chaque fichier Lua du mod et du mod de développement, la variable qui reçoit une vue et ses alias (`local h = g.home`, `g and g.home`) ne sont jamais écrits jusqu'à la fin de la fonction, aucune vue n'est rendue ni laissée sans nom ; (2) contrôle à l'exécution facultatif `Groups.PEEK_CHECK = true` (tests, console debug ; coupé par défaut car il copie le groupe à chaque lecture) : chaque `peek` garde une copie du groupe par génération de changements (`Groups.stats.marks`) ; à la fin de l'image (`Groups.onTick`), au début de la suivante et sur demande (`Groups.checkPeeks()`), un groupe changé sans changement enregistré depuis la lecture est signalé (`ERROR groups: group grp-<n> changed through Groups.peek without a recorded change (read-only view) at <chemin>`, `Groups.stats.peekViolations`). Un changement en place volontairement sans écriture (peur montée par `LK_Needs.perceive`, [besoins.md](besoins.md)) le déclare par `Groups.touched(gid)`. Limite : une écriture par une vue suivie, dans la même image, d'un changement enregistré n'est pas vue à l'exécution (la lecture du code la couvre). Proxy en lecture seule écarté : `pairs` ne traverse pas un proxy en Lua 5.1 (pas de `__pairs` ; non vérifié dans Kahlua), les lecteurs qui parcourent `members` casseraient.
- Mesure : [lecture-en-place-2026-10-12.md](../validation/lecture-en-place-2026-10-12.md).

**Contrôle au chargement** :
- schéma différent de 1 (inconnu ou plus récent), structure générale fausse (`nextId`, `groups`) ou deux emplacements illisibles → registre **bloqué** : journal `ERROR`, aucune écriture, fichiers conservés, toute modification refusée (`group registry not ready`) ;
- sinon chaque groupe est vérifié (types, bornes, clé = `id`, numéros inférieurs à `nextId`/`nextMember`, chef membre vivant, rôles et types connus, journal en suite 1..n, PNJ unique) ; un groupe invalide est **écarté** et journalisé (`ERROR group grp-<n> dropped at load (file #<seq>): <raison>`), les autres sont gardés. Un PNJ cité par deux groupes : le groupe de plus grand numéro est écarté.
- Le chargement n'écrit rien : la prochaine écriture va dans l'autre emplacement, et le fichier d'origine (avec le groupe écarté) reste lisible jusqu'à l'écriture suivante.

## Types et profils

Retenu le 2026-10-10 (LK08-T02). Code : `media/lua/shared/LivingKnox/LK_GroupTypes.lua` (registre et validation) ; données : `media/lua/shared/LivingKnox/Data/LK_Type_settlers.lua`, `LK_Type_raiders.lua`, `LK_Type_neutrals.lua` ; noms affichés : `IGUI_LK_GroupType_<id>` dans `Translate/EN/IG_UI.json` et `Translate/FR/IG_UI.json`.

### Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Le jeu exécute d'office **tous** les `.lua` de `media/lua/shared` (sous-dossiers compris) de chaque mod actif : fichiers vanilla triés, puis, mod par mod dans l'ordre de `getModIDs()`, les fichiers de `common` et de la variante de version triés ensemble par chemin relatif en minuscules (`CASE_INSENSITIVE_ORDER`) ; un chemin relatif déjà exécuté n'est pas relancé. `shared` puis `client` au démarrage, `server` au chargement de la partie, donc avant `OnInitGlobalModData`. | `J/Lua/LuaManager.java:1142-1218, 1242-1259` ; `server` : base `mod-loading.md` (`GameLoadingState.java:153`) | confirmé statiquement |
| Dans notre mod, `livingknox/data/lk_type_*.lua` passe **avant** `livingknox/lk_grouptypes.lua` ; le fichier d'un autre mod passe avant ou après selon l'ordre des mods. Chaque fichier de données commence donc par `require "LivingKnox/LK_GroupTypes"`, qui exécute le registre une seule fois quel que soit l'appelant. | même source ; `require` et son ensemble `loaded` : base `mod-loading.md` (`LuaManager.java:1306-1340`) | confirmé statiquement ; ordre réel à voir dans `console.txt` |
| `getText("IGUI_…")` d'un mod renvoie la clé brute sur un serveur MP (traductions des mods non chargées) : le nom d'un type se traduit chez le client. | base `api-42-21.md` (traductions absentes sur un serveur MP) | confirmé statiquement |
| Clés `IGUI_` cherchées dans `IG_UI.json` seulement. | base `api-42-21.md` (`Translator.java:306-345`) | confirmé statiquement |
| Littéral non ASCII d'un `.lua` changé en U+FFFD par le lexeur Kahlua : données et code en ASCII, accents dans les traductions. | base `kahlua-lua.md` | confirmé statiquement ; contrôlé par le banc |

### Support retenu : fichiers Lua de données qui s'enregistrent (option A)

Un type = **un fichier Lua de données** placé n'importe où sous `media/lua/shared` d'un mod actif, qui appelle `LivingKnox.GroupTypes.register{ ... }`. Aucune ligne de code à toucher : le balayage du jeu exécute le fichier, `require` tire le registre. Un autre mod ajoute un type par un seul fichier, à un chemin **propre à ce mod** (un chemin identique au nôtre le remplacerait) :

```lua
-- media/lua/shared/<MonMod>/<MonMod>_LKType_nomads.lua
require "LivingKnox/LK_GroupTypes"
if LivingKnox and LivingKnox.GroupTypes then   -- RadioSurvivor absent : require échoue (WARN), rien n'est fait
    LivingKnox.GroupTypes.register({ format = 1, id = "nomads", nameKey = "IGUI_MonMod_Nomads", ... })
end
```

Pourquoi A plutôt que B (fichiers texte lus par `getModFileReader`) : A donne gratuitement la syntaxe Lua (tables imbriquées, listes, commentaires) et une erreur de syntaxe isolée au fichier fautif ; B demande un analyseur propre au mod (format à écrire, à tester, à documenter) et une découverte des fichiers : `getModFileReader(modId, chemin)` et `listFilesInModDirectory(modId, dossier)` exigent de connaître le mod et le dossier (base `mod-loading.md`), donc une convention de dossier à parcourir pour chaque mod actif. A est chargé sur toutes les machines au même moment (avant la partie), sans aucun appel au moteur.

### Format 1

Tout champ inconnu, à tout niveau, fait refuser la définition (faute de frappe visible).

| Champ | Contenu et bornes |
|---|---|
| `format` | `1` (une version future refusera un format qu'elle ne lit pas) |
| `id` | minuscule puis minuscules, chiffres, soulignés ; 24 au plus ; unique (doublon refusé, le premier enregistré reste) |
| `nameKey` | clé de traduction du nom affiché (lettre puis lettres, chiffres, soulignés ; 64 au plus), résolue côté client |
| `size` | `{ min, max }` entiers, 1 ≤ min ≤ max ≤ 32 (`SIZE_MAX` = `Groups.MAX_MEMBERS`, vérifié par le banc) |
| `hostility` | 0..100 : hostilité de départ envers les joueurs (0 amical, 100 hostile à vue) |
| `home` | `building` (vrai bâtiment) ou `forest` (camp en forêt), préférence lue par LK08-T03 |
| `morale` | 0..100 : moral de départ |
| `needs` | `food`, `medical`, `ammo` 0..100 : besoins de départ (mêmes clés que `Groups.NEEDS`) |
| `roles` | `{ [rôle] = { weight = 1..100, behaviours = { nom, ... } } }`, au moins un ; rôle de `Config.GROUP_ROLES` ; `weight` = part relative du rôle dans le groupe ; `behaviours` = comportements **permis** (I1.2), 1 à 16 noms distincts de `GroupTypes.BEHAVIOURS` |
| `profiles` | 1 à 32 profils de membres, identifiants distincts ; chaque rôle du type a au moins un profil ; si tous les profils ont un `max`, leur somme atteint `size.max` |

Profil : `id` (même forme que `id` du type), `role` (un rôle de ce type), `weight` 1..1000 (fréquence relative : petit = **rare**, I8.1), `max` 1..32 facultatif (au plus `max` membres de ce profil par groupe : un seul médecin, deux casseurs), `female` facultatif, `looks` facultatif (noms de `LK_Appearance.LOOKS`, du sexe de `female` s'il est donné ; absent : tous ceux du sexe), `outfits` facultatif (`Generic01`..`Generic05`, `LK_Appearance.OUTFITS` ; absent : toutes), `weapons` facultatif (absent : sans arme ; `<Module>.<Objet>` ; dans le module `Base`, seulement les armes de `GroupTypes.VANILLA_WEAPONS`), `traits` facultatif (`{ { id = <nom de GroupTypes.TRAITS>, chance = 1..100 } }`, chance en pour cent). Listes : 1 à 16 entrées distinctes (une liste vide est refusée : on omet le champ).

### Format 2 (E08-T06)

Format 1 plus deux champs facultatifs de **poste émetteur** (radio du groupe, voix du réseau radio : [radio-groupes.md](radio-groupes.md)) : `homeRadio = true` au niveau du type (un poste au foyer, utilisable par tout membre vivant présent au foyer) et `radio = true` dans un profil (chaque membre de ce profil porte un talkie, même en expédition). Booléens seulement. En format 1 ces champs restent inconnus, donc refusés. Les deux formats sont lus (`GroupTypes.FORMATS`) ; un autre format est refusé (`unknown format N (this version reads 1 to 2)`). Types livrés au format 2 : `settlers` et `raiders` (E08-T10, `homeRadio` : poste au camp).

**Références** : apparences et tenues sont celles que `LK_Appearance.normalize` comprend déjà ; les armes vanilla admises sont relevées dans `media/scripts/generated/items/weapon.txt` 42.21 avec un `AttachmentType` présent dans `LK_Equipment.LOCATIONS` (contrôle du banc sur les scripts installés) ; une arme d'un autre module (mod d'armes) n'est contrôlée ici que par sa forme, puis par `Equipment.spec` (`instanceItem`) quand un PNJ la reçoit.

**Noms réservés** (aucun effet codé ici) : comportements `guard`, `patrol`, `defend`, `fight`, `scout`, `expedition`, `scavenge`, `forage`, `fish`, `garden`, `cook`, `heal`, `maintain`, `chores`, `fortify`, `breach`, `raid`, `trade`, `talk` (LK05-T02 et suivantes les implémenteront et pourront en ajouter) ; besoins vitaux (dormir, manger, boire, fuir) hors rôles, permis à tous. Traits rares `smoker`, `drinker`, `tidy`, `nervous`, `keenHearing`, `strong` (effets avec LK05 et LK10).

**Rôles** : `breaker` (casseur de barricades, I6.9) ajouté **en fin** de `Config.GROUP_ROLES` : l'ordre des cinq rôles de LK08-T01, donc la succession des groupes déjà enregistrés, ne change pas ; le casseur passe après l'ouvrier dans la succession. Règle pour la suite : un rôle s'ajoute en fin de liste, jamais retiré (un groupe qui l'emploie deviendrait invalide).

**API** (`LivingKnox.GroupTypes`, toutes les machines) : `register(def)` (vrai, ou `nil` et la raison ; refus journalisé `ERROR group type <id> refused: <raison>` et gardé), `validate(def)` (copie normalisée, logique pure), `isKnown(id)`, `get(id)` (copie), `ids()` (triés, indépendants de l'ordre des mods), `refused()`, `weaponOk(type)`. `LK_Groups` valide `type` contre `isKnown` (création et relecture) ; `Config.GROUP_TYPES` est supprimé.

### Types livrés

Valeurs de départ propres au mod (décisions LK00 : colons amicaux et neutres méfiants en bâtiment, pillards hostiles en forêt, 4 à 8 membres), à recalibrer en jeu.

| Type | Taille | Hostilité | Foyer | Moral | Besoins (nourriture, soins, munitions) | Rôles (poids) | Profils (poids, max) |
|---|---|---|---|---|---|---|---|
| `settlers` (Colons) | 4-8 | 10 | bâtiment | 60 | 55, 50, 40 | deputy 1, fighter 3, scout 2, medic 1, worker 4 | `second` (10, 1), `guard` (30), `scout` (20, ouïe fine 40 %), `doctor` (10, 1), `farmer` (30, Generic01/03, fumeur 15 %), `handyman` (15) |
| `raiders` (Pillards) | 4-8 | 90 | forêt | 50 | 40, 30, 50 | deputy 1, fighter 5, scout 2, breaker 2, worker 1 | `lieutenant` (10, 1), `thug` (40, buveur 25 %), `gunman` (15, 2), `lookout` (20, ouïe fine 60 %), `breaker` (15, 2, fort 50 %), `camp_hand` (10, 1) |
| `neutrals` (Neutres) | 4-6 | 45 | bâtiment | 50 | 50, 45, 45 | deputy 1, fighter 2, scout 2, medic 1, worker 3 | `elder` (10, 1), `hunter` (25), `lookout` (20), `nurse` (10, 1, sans arme), `drifter` (35) |
| `loners` (Solitaire, E10-T04) | 1 | 50 | bâtiment | 50 | 50, 50, 50 | tous les rôles (1), mêmes comportements d'une vie seule | un profil par rôle (1) ; **jamais tiré** (aucune option de poids), aucune relève : groupe d'un PNJ parti de son groupe ([depart.md](depart.md)) |

Raisons : colons mieux nourris et soignés (potager, médecin), peu de munitions ; pillards bien armés et peu soignés, casseurs et guetteurs (I6.9) ; neutres plus petits (méfiance), chasseurs. Armes : fusils de chasse et outils chez les colons, armes de mêlée lourdes et quelques armes à feu chez les pillards, carabines de chasse chez les neutres.

### Alternatives écartées (types)

- **Option B, fichiers texte** : voir plus haut (analyseur et découverte à écrire, aucune vérification de syntaxe gratuite).
- **Types en dur dans `LK_Config`** (LK08-T01) : un type nouveau demandait du code.
- **Une table `GROUP_TYPES` recalculée dans `LK_Config`** : `LK_Config` devrait tirer le registre, qui tire déjà `LK_Config` (rôles) ; `LK_Groups` interroge directement le registre.
- **Comportements en texte libre** : une faute de frappe passerait sans bruit ; la liste fermée sera étendue par la tâche qui code un comportement.
- **Contrôle des armes par `instanceItem` à l'enregistrement** : appel au moteur pendant le chargement des fichiers `shared`, avant toute partie, sur toutes les machines ; contrôle reporté à l'usage pour les armes de mods, liste vanilla vérifiée hors jeu.
- **Tenues spécifiques (pillards en tenue de bandit)** : `LK_Appearance` ne comprend que `Generic01`..`Generic05` (présentes pour les deux sexes) ; une tenue de plus s'ajoutera à `Appearance.OUTFITS` avec sa vérification.

### Idées reprises (types)

- I1.2 (rôle = comportements permis) : chaque rôle d'un type porte la liste des noms de comportements permis ; registre trié par priorité et refus par rôle restent à coder (LK05-T02).
- I6.9 (éclaireur à l'ouïe fine, casseur) : rôle `scout` et trait `keenHearing`, rôle nouveau `breaker` avec le comportement `breach` et le trait `strong`.
- I8.1 (rôles et traits rares) : rareté par le poids et le maximum d'un profil (un médecin, un adjoint), traits rares tirés à leur chance ; leurs effets viendront avec LK05 et LK10.

### Tests (types)

- Banc lupa `tests/test_lk_group_types.py` (14 tests) : trois types enregistrés sur le serveur et les deux clients, sans erreur ; valeurs livrées ; lecture en copie ; `LK_Groups` n'accepte que les types enregistrés, `breaker` admis ; constantes égales à celles du registre des groupes, rôles de LK08-T01 dans le même ordre, `Config.GROUP_TYPES` absent ; **type supplémentaire ajouté sans code** par un fichier de données d'un autre mod (dossier `media/lua` temporaire), chargé après ou **avant** les nôtres, retrouvé dans le registre et utilisable par `Groups.create` ; redémarrage sans ce mod : son groupe écarté et journalisé, l'autre gardé ; 32 définitions invalides refusées avec leur raison exacte et journalisées, les types valides gardés ; fichier de données invalide sans effet sur les autres ; doublon refusé ; solo ; armes vanilla admises présentes dans `media/scripts` 42.21 installé, de type `base:weapon`, avec un `AttachmentType` de `LK_Equipment.LOCATIONS` ; clés de nom traduites en anglais et en français ; code et données ASCII.
- VM Kahlua (`tests/test_kahlua.py`, `test_group_types_in_kahlua`) : les trois types enregistrés par les fichiers de données, type supplémentaire, refus (motifs `%l`/`%a`, arme vanilla non admise), doublon refusé. Le banc passe désormais ses arguments par un fichier `@` du lanceur java (ligne de commande Windows de 32 767 caractères dépassée).
- En jeu : rien de propre à cette tâche (hors jeu) ; au premier démarrage, voir dans `console.txt` les trois lignes `group type … registered` sur le serveur et sur chaque client, et aucune ligne `refused`.

## Population

Retenu le 2026-10-10 (LK08-T05). Code : `media/lua/server/LivingKnox/LK_Population.lua` (`LivingKnox.Population`, autorité seulement), lecture des options dans `media/lua/shared/LivingKnox/LK_Config.lua` (`Config.population()`, `Config.readInt`), accroches dans `LK_Server.lua`, options dans `media/sandbox-options.txt`, libellés dans `Translate/EN|FR/Sandbox.json`, fonctions pures `Groups.applyCreate` / `Groups.applyMember` dans `LK_Groups.lua` (partagées avec `create` / `addMember`).

### Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Options `integer` : `min`, `max` et `default` obligatoires ; les options `enum` demandent `numValues` et un `default` entier (format piège) : la page Living Knox n'emploie que des entiers. | base `mod-loading.md` (`CustomSandboxOptions.java`), `load-warnings.md` (`CustomEnumSandboxOption.parse`) | confirmé statiquement |
| `getOptionByName("LivingKnox.X"):getValue()` est à jour sur l'autorité (solo compris, où `SandboxVars` reste périmé après l'éditeur en jeu) ; `nil` pour une option inconnue ; aucun événement ne signale un changement. | base `load-warnings.md` (option changée en cours de partie) | confirmé statiquement |
| Les options de la partie ne sont lues en solo qu'après la fusion du butin, avant `OnInitGlobalModData` ; lues ici au démarrage, donc à jour. | base `loot-distributions.md` (`IsoWorld.java:1791-1909`) | confirmé statiquement |
| `getCell()` vaut `nil` pendant `OnInitGlobalModData` ; `OnServerStarted` (serveur, après `IsoWorld.init`) et `OnGameStart` (solo) partent après la métagrille et la lecture des refuges (`map_meta.bin`). | base `world-placement.md`, `multiplayer.md` (refuges), `mod-loading.md` (`GameServer.java:1461`, `IngameState.java:849`) | confirmé statiquement |
| Clés `Sandbox_<translation>` et `Sandbox_<translation>_tooltip` dans `Sandbox.json`, chemin sensible à la casse sous Linux ; `getText` formate (pas de `%` seul). | base `mod-loading.md`, `file-path-case.md` | confirmé statiquement ; contrôlé par `check_case.py` et le banc |

### Options (page `LivingKnox`)

| Option | Défaut | Bornes | Rôle |
|---|---|---|---|
| `LivingKnox.GroupCount` | 4 | 3..5 | nombre de groupes de la population initiale (décision LK00) |
| `LivingKnox.WeightSettlers` | 40 | 0..100 | poids de tirage des colons ; 0 = exclus |
| `LivingKnox.WeightRaiders` | 35 | 0..100 | poids des pillards ; 0 = exclus |
| `LivingKnox.WeightNeutrals` | 25 | 0..100 | poids des neutres ; 0 = exclus |
| `LivingKnox.GroupSizeMin` / `GroupSizeMax` | 4 / 8 | 4..8 | taille d'un groupe, croisée avec `size` du type |
| `LivingKnox.ReliefDaysMin` / `ReliefDaysMax` | 2 / 5 | 2..5 | délai de relève en jours de jeu (`Config.population().reliefMin/Max`), tiré par groupe disparu (LK09-T04, section « Décimation et relève ») |

Poids par défaut : colons un peu plus nombreux (monde « vivant » plutôt qu'hostile), pillards présents dans presque chaque partie, neutres plus rares ; valeurs de départ à recalibrer en jeu.

**Lecture robuste** (`Config.readInt`) : valeur absente (ni option Java ni `SandboxVars`), non entière ou hors bornes → valeur par défaut et `WARN option LivingKnox.X …` en anglais ; `min > max` (taille ou relève) → les deux valeurs par défaut et `WARN options … defaults … used` ; tous les poids à 0 → poids par défaut et `WARN population: every group type weight is 0, default weights used`. Défauts et bornes de `LK_Config` = ceux de `sandbox-options.txt` (vérifié par le banc).

**Taille (règle d'intersection)** : bornes = `[max(GroupSizeMin, size.min), min(GroupSizeMax, size.max)]`, taille tirée uniformément dedans. Intersection vide (ex. 7..8 pour des neutres 4..6) : la borne du type la plus proche des options (6 ici), avec un `WARN`. Les options ne font donc jamais dépasser la taille d'un type.

**Types tirables** : types enregistrés ayant une option de poids (`Config.TYPE_WEIGHT_OPTIONS`) et un poids > 0, triés par identifiant. Un type ajouté par un autre mod n'a pas d'option : il n'est pas tiré par la population initiale (il reste utilisable par l'API). Un poids sur un type non enregistré : `WARN … never drawn`. Aucun type tirable : rien n'est créé (`ERROR`), le drapeau n'est pas posé, nouvelle tentative au démarrage suivant.

### Création initiale

- **Condition** : registre prêt, `populated ~= true` **et** `nextId == 1` (aucun groupe n'y a jamais été créé ; les numéros ne reculent jamais). Après la population, `populated = true` (champ facultatif du registre, schéma 1 inchangé ; une valeur non booléenne relue vaut vrai). Conséquences : jamais de seconde population après un redémarrage, ni après la disparition de tous les groupes (la relève est LK09) ; un registre d'une version antérieure qui a déjà eu un groupe n'est ni repeuplé ni réécrit ; un monde neuf (`OnInitGlobalModData(true)`, registre neuf) reçoit sa population.
- **Moment** : `OnServerStarted` (serveur) / `OnGameStart` (solo), inscrit avant la simulation (les groupes créés partent de l'heure courante) ; si le registre n'était pas relu (rechargement Lua) ou le moteur désactivé (`LivingKnox.Enabled`), au premier `EveryHours` qui suit le démarrage où le moteur est actif. Une seule tentative par session (`Population.state`, remis à zéro à `OnInitGlobalModData`). Jamais à `OnInitGlobalModData` (cellule absente). Jamais côté client : `LK_Population.lua` s'arrête sur `isClient()` comme les autres fichiers `server`.
- **Tirages** (graine = hachage de `"population/" .. Store.worldKey()`, Park-Miller sans opérateur binaire) : type selon les poids ; puis, sur un flux propre au groupe, taille ; membres un par un : rôle selon `roles[rôle].weight` parmi les rôles du type qui ont encore un profil disponible (ordre de `Config.GROUP_ROLES`, indépendant de `pairs`), profil selon `weight` parmi ceux du rôle sous leur `max`, sexe imposé par `female` du profil ou tiré à pile ou face, traits tirés à leur `chance` ; chef = `Groups.pickSuccessor` (règle de succession I6.6 : rôle puis ancienneté) ; graine d'histoire tirée, `Stories.compose(type, storySeed)` ; si le profil du chef impose un sexe différent de celui de l'histoire, nouvelle graine (8 essais, puis `WARN`) ; sinon le sexe du chef devient celui de l'histoire ; graine de site tirée.
- **Foyers** : `Sites.pick(type, { seed, homes = foyers déjà choisis, exclude = clés déjà prises })` pour chaque groupe dans l'ordre ; échec → groupe sans foyer et `WARN population: group <i> (<type>) has no home: <raison>`, la création continue. Aucun aménagement (LK08-T04), aucun corps.
- **Écriture** : tout est préparé avant d'écrire, puis inséré par `Groups.update` en **une seule sauvegarde** (un arrêt pendant la préparation ne laisse aucun groupe à moitié créé). Journal : une ligne `INFO population: grp-<n> <type>, <k> member(s), leader m-<j>, home x,y,z|none` par groupe, puis `INFO population: <N> group(s) created (requested <N>, seed <s>)`.

### Champs stockés

| Champ | Contenu |
|---|---|
| `name` | nom du chef tiré par l'histoire (`story.leader.name`) ; le nom affiché du groupe se composera côté client |
| `story` | `summary.en` (600 au plus, `Stories.SUMMARY_MAX = STORY_MAX`) : lisible dans le fichier et les journaux du serveur |
| `storySeed` | graine (0..2^31-1, facultative) : `Stories.compose(type, storySeed)` rend l'histoire complète, français et **secrets** compris, côté autorité ; les secrets ne sont jamais stockés (ni fichier ni ModData) |
| `needs`, `morale` | valeurs de départ du type (`needs`, `morale` de la définition) |
| membre `profile`, `female`, `traits` | profil tiré (identifiant du type), sexe, liste des traits tirés (absente si aucun) ; forme seulement contrôlée à la relecture : un profil ou un trait retiré des données ne fait rien écarter |

### Alternatives écartées (population)

- **Création à `OnInitGlobalModData`** : cellule absente, joueurs locaux pas encore placés.
- **Création au premier `EveryHours` seulement** : une heure de jeu sans groupes ; le démarrage suffit, `EveryHours` n'est qu'un rattrapage.
- **Un groupe par appel `Groups.create` / `addMember`** : une quarantaine d'écritures et, en cas d'arrêt, une population partielle que le drapeau ne saurait pas compléter.
- **Histoire stockée en entier** : secrets dans le fichier et risque de fuite par une lecture du registre ; la graine suffit.
- **Mélange garanti (au moins deux types)** : non demandé ; le tirage suit les poids, un poids à 0 exclut un type.
- **Option `enum` pour le mélange** : format piège en 42.21 et moins souple que trois poids.

### Tests (population)

- Banc lupa `tests/test_lk_population.py` : population par défaut (4 groupes, types, tailles dans l'intersection, rôles et profils du type, `max` respecté, traits du profil, chef = règle de succession, histoire recomposée depuis `storySeed`, nom du chef, sexe du chef, aucun secret dans le registre, besoins et moral du type, foyers distincts loin du joueur et entre eux) ; reproductible à graine égale, différente sinon ; graine dérivée de la partie ; `GroupCount` 3 et 5 ; poids (exclusion, proportions sur 1 200 groupes, tous nuls) ; tailles (plages atteintes, intersection, intersection vide) ; `max` des profils sur 600 groupes ; options absentes, non entières, hors bornes, `min > max`, repli `SandboxVars` ; relève lue et bornée, sans effet sur la population ; type non enregistré ; une seule population après redémarrage, même sans groupe restant ; registre ancien laissé intact ; drapeau invalide ; monde neuf repeuplé ; registre bloqué ; échec de site (groupe sans foyer) ; champs de membre contrôlés à la relecture ; client sans module. Banc `tests/harness.py` (serveur + 2 clients, et solo) : accroches de `LK_Server.lua` (`OnInitGlobalModData`, `OnServerStarted` / `OnGameStart`, `EveryHours`), rien avant le démarrage, rien sur les clients, redémarrage sans seconde population, moteur désactivé puis activé, registre relu paresseusement. Fichiers : options de `sandbox-options.txt` = défauts et bornes de `LK_Config`, traductions EN/FR, aucune `enum` ; contraintes Kahlua ; aucun autre code ne crée de groupe.
- En jeu (à faire) : nouvelle partie solo puis serveur dédié : lignes `population: …` dans `console.txt`, fichier `groups-…` avec `populated`, aucune ligne à la partie relancée.

## Décimation et relève (LK09-T04, 2026-10-12)

Code : `media/lua/server/LivingKnox/LK_Population.lua` (fin du fichier : `reliefStep`, `markGone`, `dueReliefs`,
`planRelief`, `reliefDelay`, `insert` partagé avec la population initiale), marque `gone` contrôlée par
`LK_Groups.lua` (`applyGone`, `isGone`, `livingCount`), foyer abandonné écarté de l'aménagement par
`LK_Homes.pending`. Accroche : `Population.onEveryHours` (déjà inscrite à `EveryHours` par `LK_Server.lua`), après la
tentative de population initiale ; `LK_Server.lua` n'est pas modifié.

### Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `EveryHours` part une fois par mise à jour, même si plusieurs heures passent ; l'heure de jeu entière vient de `getWorldAgeHours` ; aucun événement horaire sur un serveur vide en pause `PauseEmpty`. | base `api-42-21.md` (`EveryHours`, calendrier de `GameTime`) | confirmé statiquement |
| Aucun chargement pour choisir un site : `LK_Sites.pick` ne lit que la métagrille. | [sites.md](sites.md) | confirmé statiquement (suite `lk.sites`) |

Rien de nouveau sur le moteur : aucune entrée ajoutée à la base.

### Choix

**Constat** (à chaque heure de jeu, groupes dans l'ordre de leur numéro, une seule sauvegarde) :

- **décimé** (`wiped`) : plus aucun membre vivant (morts ou partis), dans un groupe qui a eu au moins un membre
  (`nextMember > 1`, même règle que l'événement public « groupe disparu ») ;
- **dispersé** (`dispersed`) : au plus `Population.RELIEF.DISPERSE_AT` = **1** vivant, dans un groupe qui a compté
  davantage de membres, **hors écran** (aucun membre incarné, aucune expédition en cours) : le survivant part
  (`Groups.applyLeave(..., "dispersed")`, fait `memberLeft` et événement public), puis le groupe est disparu. Un
  survivant incarné ou en expédition retarde le constat ; `DISPERSE_AT = 0` désactive la dispersion.

**Marque** (champ facultatif du groupe, schéma 1 inchangé) : `gone = { cause, day, hour, due, relief }` ; entrée de
journal `gone` (cause). Contrôle à la relecture : cause dans `Groups.GONE_CAUSES`, heures entières, `due >= hour`,
`relief` = identifiant de groupe de numéro `< nextId`, **aucun membre vivant** ; sinon le groupe est écarté comme pour
tout autre champ invalide. `addMember` refuse un groupe disparu (`group grp-<n> is gone`).

**Ce qui reste en place** : le groupe n'est **pas** retiré du registre. Son foyer reste un foyer connu
(`Sites.groupHomes` l'évite : aucun groupe neuf à moins de `GROUP_DISTANCE` = 400 cases), son aménagement
(`furnish`, objets marqués `LKHome`) et son stock (`stock`, conteneurs) restent tels quels : ni repris, ni nettoyés,
ni réaménagés (`Homes.pending` ignore un groupe disparu ; un foyer jamais aménagé le reste). La simulation, les
besoins, les offres et la matérialisation n'agissent déjà sur aucun groupe sans vivant.

**Délai** : `days` tiré uniformément dans `[ReliefDaysMin, ReliefDaysMax]` sur un flux Park-Miller de graine
(hachage de `"relief/" .. Store.worldKey()`, numéro du groupe) ; `due = hour + days × 24`, écrit dans la marque :
il survit au redémarrage et ne dépend pas d'un réglage changé ensuite.

**Relève** : à la première heure `>= due`, plan par le chemin de la population : type selon les poids des options
(`typeWeights`), `planGroup` (taille, membres, chef, histoire), `Sites.pick` ; contrôle supplémentaire de la distance
au centre de l'ancien foyer (`>= GROUP_DISTANCE`). Insertion (`Population.insert`), `gone.relief` = nouvel
identifiant, entrées `relieved` (ancien groupe, texte = nouveau) et `relief` (nouveau groupe, texte = ancien) dans
**la même sauvegarde** : une seule relève par groupe disparu, même après un redémarrage. Le groupe neuf publie
`groupCreated` (événement public `OnLivingKnoxGroupCreated`). Aucun site, aucun type tirable ou registre plein :
`WARN relief: no relief for grp-<n> (<raison>), next try at hour <h>`, `due` repoussé de `RETRY_HOURS` = 24 (nouvelle
graine, le tirage dépend de `due`). Moteur désactivé : rien, le constat et la relève attendent. E10-T04 : un groupe d'un type sans option de poids (solitaire `loners`) est marqué disparu mais n'appelle aucune relève (`dueReliefs`).

**Renforts sous la moitié de l'effectif (I8.4)** : non codés. La simulation a déjà des recrues (expéditions,
événement `recruit` de LK09-T05) ; un renfort demande un effectif de référence que le registre ne garde pas (taille de
fondation) et des règles de moment, de nombre et de rôles : reste.

### Alternatives écartées

- **Retirer le groupe (`Groups.remove`)** : perd le foyer abandonné, que `Sites` n'éviterait plus, et le journal ; le
  contrat demande des traces.
- **Constat au moment de la mort** (dans `applyDeath`) : la mort d'un membre incarné et celle d'un membre hors écran
  passent par des chemins différents ; le constat horaire couvre tous les cas (départs compris) en un seul point.
- **Même type que le groupe disparu** : non demandé ; la relève suit les poids de la population (un poids à 0 exclut
  un type).
- **Délai relu des options au moment de la relève** : un réglage changé déplacerait des relèves déjà annoncées.
- **Dispersion au-dessus d'un vivant** (par exemple « sous un quart de l'effectif ») : demande l'effectif de
  fondation, absent du registre ; à revoir avec les renforts.

### Tests

- Banc lupa `tests/test_lk_relief.py` (17 tests) : groupe décimé marqué une fois, foyer, aménagement et stock gardés,
  journal ; groupe sans membre jamais marqué ; tous partis = décimé ; dispersion du dernier survivant hors écran,
  retardée par une expédition ou un corps, désactivée par `DISPERSE_AT = 0` ; `addMember` refusé ; marque invalide
  écartée à la relecture (cause, heures, relève, vivant) ; délai selon les options, reproductible, toutes les valeurs
  atteintes ; moteur désactivé ; relève à l'heure due et pas avant, loin de l'ancien foyer et des autres, une seule
  fois, même après un redémarrage ; heure due relue après un redémarrage ; relève reproductible ; aucun site : nouvel
  essai 24 h plus tard ; deux relèves distinctes ; accroche horaire ; foyer abandonné absent de `Homes.pending` ;
  suite en jeu `lk.relief` exécutée par le vrai moteur RST (réussite et détection d'un foyer trop proche).
- En jeu : suite `lk.relief` (tags `world`, `server`), `RST.run({ suite = "lk.relief", tags = "world" })` sur une
  partie `rstest*` ; persistance après redémarrage : lignes `group grp-<n> gone` puis `relief: grp-<m> … replaces
  grp-<n>` de `console.txt`.

## Faits et événements publics (LK12-T02, 2026-10-12)

Le registre publie des faits internes (`LivingKnox.publish`) aux points uniques de ses transitions : `groupCreated`
(`applyCreate`), `memberLeft` (`applyLeave`, avec un argument facultatif `reason`), `groupRemoved` (`remove`), en plus
de `memberDied` (`applyDeath`). `LK_API.lua` les relaie en événements Lua publics ([api.md](../api.md), section
« Événements publics »). Choix pris par défaut (décisions à confirmer) :

- **File puis pas suivant** plutôt qu'un déclenchement immédiat : les faits naissent au milieu d'une transaction
  (`applyCreate` avant les membres de la population, `applyDeath` avant l'écriture) ; au pas suivant, la charge utile
  est relue dans un registre cohérent et un fait d'une transaction refusée (registre bloqué) est abandonné.
- **Membre mort** : seulement un membre de groupe (corps présent par `npcDied`, hors écran par `memberDied`) ; un PNJ
  hors groupe reste dans le fait interne `npcDied`.
- **Groupe disparu** : plus aucun vivant après une mort ou un départ (groupe qui a eu au moins un membre), ou retrait
  du registre d'un groupe encore vivant ; jamais deux fois par session.
- **Besoin critique** : réserves publiques `needs` (celles de l'API et des offres de LK12-T03) sous `NEED_LOW` (25,
  même seuil que `Stock.SUPPLY.CRITICAL`), sortie à `NEED_OK` (40) ; le stock réel de LK_Stock (eau, matériaux) n'est
  pas relayé : son statut dépend des conteneurs chargés et reste interne. Sondage `EveryTenMinutes` (aucun point
  d'écriture unique des réserves), relevé silencieux au premier passage d'une session.
- **Rencontre** : début d'une sommation (`start`), pas ses étapes ni ses reprises.
- **Membre parti** : membre vivant retiré par `applyLeave` ; `reason` nil pour LK09-T05 (aucun appelant modifié) ; E10-T04
  passe `"leave_group"` (RS_LivingKnox.leave, [depart.md](depart.md)).

## Alternatives écartées

- **Groupes dans le registre des PNJ (`registry-…`)** : un groupe abîmé bloquerait tous les PNJ, et le schéma des PNJ changerait pour une donnée sans rapport ; fichier distinct, mécanisme commun.
- **ModData globale** : lisible par tous les clients (règle du plan).
- **Bloquer tout le registre pour un seul groupe invalide** (règle du registre des PNJ) : le contrat demande de garder les autres ; un groupe se reconstruit plus facilement qu'un PNJ dont le corps existe dans le monde.
- **Réécrire le fichier dès le chargement sans le groupe écarté** : perdrait la seule copie du groupe avant toute récupération manuelle.
- **Succession automatique à la mort du chef** : c'est un comportement (délai, dispersion), hors périmètre ; l'API laisse l'appelant décider du moment.
- **Écriture toutes les minutes de jeu ou sur un minuteur** (proposition de LK13-T02) : une seule écriture par image suffit à sortir les pas horaires du point chaud, et une image (100 ms) est la plus courte attente qui garde l'ordre « registre écrit avant la sauvegarde suivante du monde » ; une minute de jeu (2,5 s réelles) élargirait la perte d'un arrêt brutal sans gain au banc.
- **Écriture immédiate des seuls changements venus du réseau ou hors d'image** : demande de savoir où l'on est dans l'image, et l'ordre des abonnés change pendant une mesure `LK_Load` ; le report à l'image suivante (au plus une image) est plus simple.
- **Membres en liste** : l'identifiant stable `m-<k>` et l'ancienneté par numéro suffisent ; une table par identifiant évite les décalages d'indices au retrait.

## Idées reprises

- I6.6 (succession du chef) : seule la règle de désignation du successeur est retenue (rôle puis ancienneté, règle propre au mod) ; repli collectif et dispersion reportés à LK05-T09.

## Tests

- Banc lupa (`tests/test_lk_groups.py`, 16 tests, 28 depuis LK13-T06) : création, membres, chef, besoins, moral, journal ; copies en lecture ; bornes et refus (type, rôle, nom, foyer, PNJ en double, besoin inconnu) ; journal borné et texte coupé ; jour de jeu d'après l'âge du monde ; règle de succession (rôle, ancienneté, chef mort, plus personne) ; numéro jamais réutilisé ; **redémarrage sans perte** (registre canonique RSV2 identique, serveur et solo) ; rattrapage paresseux ; neuf groupes invalides écartés, deux gardés, fichier d'origine intact ; schéma futur refusé sans écriture ; structure fausse ; emplacement corrompu (l'autre est relu) puis deux illisibles ; monde neuf ; aucune ModData globale lue ; client MP sans registre ni fichier. LK13-T06 (12 tests ajoutés, 28 en tout) : changements d'une image écrits une fois à sa fin, rien avant ; abonné `OnTick` inscrit après `LK_Groups` suivi par l'écriture (une par image, jamais deux) ; serveur en pause écrit à l'image suivante ; `flush` immédiat et idempotent ; relecture à la première écriture et sur demande seulement, fichier changé détecté (registre bloqué) ; écriture différée refusée : registre bloqué, fichiers gardés ; relecture après remise à zéro du Lua sans perte ; arrêt brutal : seule l'image inachevée perdue ; hex et somme rapides égaux au codec ; `OnSave` en solo ; abonné `OnTick` inchangé. LK13-T08 (4 tests, 32 en tout) : `peek` rend le groupe vivant (pas une copie, `get` en reste une), suit les changements ; contrôle `PEEK_CHECK` : lectures suivies de changements enregistrés (API, `update`) sans faute, écriture d'un champ, d'une sous-table et `table.insert` par la vue signalées une fois ; lecture du code : aucun appelant n'écrit dans une vue (et le contrôle repère quatre écritures d'exemple) ; banc de charge `tools/load_bench.py` 3 minutes de jeu avec `PEEK_CHECK` : plus de 20 lectures, aucune écriture par une vue, aucune erreur. Kahlua (`tests/test_kahlua.py`, `KR-GFLUSH`) : mêmes règles et mêmes chiffres de hex et de somme.
- VM Kahlua (`tests/test_kahlua.py`, `test_groups_logic_in_kahlua`) : API sur un registre en mémoire (écriture neutralisée), succession, bornes arrondies, journal coupé, aller-retour RSV2 validé, chef mort écarté, schéma futur refusé.
- En jeu : sans objet pour cette tâche (hors jeu) ; à vérifier au premier serveur dédié de test : ligne `groups: new world, empty group registry` et fichier `groups-…-1.txt` écrit par la VM réelle.

## Points ouverts

- ⚠ Un type qui n'est plus enregistré (mod qui le livrait retiré, fichier de données supprimé ou refusé) rend invalides les groupes de ce type à la relecture : ils sont écartés et journalisés (`unknown type …`), les autres gardés (banc LK08-T02). Aucune migration ni type de repli : à décider si le besoin apparaît (LK08-T05, LK09).
- ⚠ Profils, rôles pondérés, taille, besoins et moral des types sont lus par la population initiale (LK08-T05 : rôle, profil, sexe et traits de chaque membre) ; apparence et arme seront tirées à la création des corps ; hostilité, comportements et traits sans effet avant LK05 et LK10.
- ⚠ Population initiale : sur un serveur dédié, aucun joueur n'est connecté à `OnServerStarted` : seules les bases connues (refuges) sont évitées, pas les futurs points d'apparition ; forêts connues seulement pour les cellules déjà approchées (repli bâtiment isolé, voir [sites.md](sites.md)). Types d'autres mods jamais tirés (pas d'option de poids).
- ⚠ Un type enregistré après la relecture du registre des groupes (fichier hors de `media/lua/shared` ou `server`, appel tardif) n'existe pas encore quand les groupes sont validés : ses groupes seraient écartés. Les fichiers de données vont dans `media/lua/shared`.
- ⚠ Le lien `npc` n'est pas vérifié contre le registre des PNJ (un PNJ oublié laisse un lien orphelin) ; à rapprocher avec LK08-T05 et LK09.
- ⚠ Un groupe écarté au chargement est perdu après deux écritures ; aucune copie de récupération dédiée.
- ⚠ **Décisions à confirmer (LK13-T06)** : une écriture par image, à sa fin ; relecture de contrôle à la première écriture de la session et sur demande seulement ; écriture immédiate limitée aux marques « en cours » et aux marques effacées après l'écriture (Stock, Fortify, Homes, Traces, Trade), les marques « fait », repas et prises d'objets (`Stock.takeMeal`, `takeItem`) restant différés d'une image.
- ⚠ Arrêt brutal (plantage, `kill`) : les changements de l'image en cours sont perdus (avant LK13-T06 : aucun). Un corps créé dans cette image (`Bodies.spawn` écrit le registre des PNJ tout de suite, le lien `npc` du membre est différé) laisse un PNJ du registre sans membre de groupe (lien `npc` absent), comme un arrêt entre ces deux écritures avant LK13-T06, mais sur une fenêtre plus large (à traiter avec le point « lien `npc` non vérifié » ci-dessus) ; un objet pris du stock peut rester dans la référence (compté manquant au relevé suivant).
- ⚠ Le banc de charge reste au-dessus du budget de 25 ms Kahlua par image (47 ms lupa) : une écriture coûte encore environ 32 ms Kahlua (taille du registre, LK13-T07) et la création des corps écrit plusieurs fois le registre des PNJ dans la même image ([charge-groupes-2026-10-12.md](../validation/charge-groupes-2026-10-12.md)).
- ⚠ Les groupes disparus restent au registre (LK09-T04) et comptent dans `MAX_GROUPS` (64) : après de nombreuses relèves, la création échoue (`too many groups`, relève repoussée de 24 h en boucle). Aucun archivage des groupes disparus anciens : à décider si le cas se présente.
