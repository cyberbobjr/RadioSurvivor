# Journal de récit des groupes

- Tâches : LK10-T02 (journal daté et borné des faits marquants) ; servira LK10-T04 (traces lisibles en jeu), LK10-T03 et E17-T03 (contexte du LLM par RadioSurvivor)
- Build : 42.21.0 — Date : 2026-10-12 — Statut : brouillon (testé hors jeu)

Code : `media/lua/server/LivingKnox/LK_Journal.lua` (`LivingKnox.Journal`, autorité seulement) ; accroche dans `LK_Groups.appendLog` (`Groups.onLog`) et heure simulée posée par `LK_Simulation.advance` (`Groups.hourContext`). Lecture : `LivingKnox.API.journal` ([api.md](../api.md)), détail admin (`LK_Admin`, champ `journal` ; fenêtre `LK_AdminView`, section « Récit du groupe »). Banc : `tests/test_lk_journal.py` ; chargement vérifié dans la VM Kahlua (`tests/test_kahlua.py`, liste des modules). Chargement : le jeu exécute tout `media/lua/server` ; `LK_API` et `LK_Admin` le requièrent (pas `LK_Server`, pour ne pas ajouter d'abonné aux bancs qui ne chargent que lui).

## Problème

Chaque groupe a déjà un journal (`g.log`, LK08-T01) où de nombreux modules écrivent : objectifs, rations, alertes, troc, défense, raids… Ce journal technique est privé : il contient des coordonnées (base d'un joueur repérée, alerte près d'une case, foyer déplacé), des comptes de joueurs, des détails de calcul, et ses 32 entrées sont vite remplacées par les entrées courantes. Il faut en plus un journal **de récit** : les faits marquants du groupe (installation, expéditions, morts, rencontres, départs, recrues, relève), datés au jour et à l'heure, bornés, lisibles par un administrateur et par RadioSurvivor, sans secret.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Sur un serveur MP, les traductions des mods ne sont pas chargées : `getText` rend la clé, `getTextOrNull` rend `nil`. | base `api-42-21.md` (`Translator.loadFiles` avant `loadMods`) | confirmé statiquement |
| `getText(clé, a1, …)` : arguments `nil` remplacés par une chaîne vide, arguments en trop ignorés. | `zombie/core/Translator.java:386-392, 421-433` (42.21.0) | confirmé statiquement |
| `getTextOrNull(clé)` sans arguments sur un texte à `%1` écrit « Missing arguments » dans le journal du jeu. | base `load-warnings.md` | confirmé statiquement |
| Aucune ModData globale pour un état privé. | base `multiplayer.md` | confirmé statiquement |
| Le jour de jeu change à 7 h ; heure simulée k = âge du monde [k-1, k[, début à (k + 6) % 24 h. | base `api-42-21.md` (calendrier de `GameTime`) ; en-tête de `LK_Simulation.lua` | confirmé statiquement |

## Choix (2026-10-12)

### Frontière entre les deux journaux

- **`g.log` reste le journal technique**, inchangé, privé, jamais rendu par l'API.
- **`g.journal` est le journal de récit**, champ facultatif du groupe (schéma 1 du registre inchangé, contrôlé par `LK_Journal` et remis à neuf s'il est malformé, comme `supply` ou `trips`).
- Le récit est **tiré du journal technique au moment de l'écriture** : `LK_Groups.appendLog` appelle `Groups.onLog(g, kind, text, day)` sur le groupe vivant, dans la même transaction. Une entrée de récit est donc sauvegardée avec le fait technique qui la porte ; une transaction non écrite (registre bloqué) n'en laisse aucune ; aucun module ne doit écrire deux fois. Une erreur du journal est journalisée et n'interrompt pas l'écriture du groupe.
- Raisons : un seul point d'entrée couvre tous les écrivains présents et futurs (simulation hors écran, expéditions physiques, population, relève, admin) sans modifier leurs fichiers ; l'ordre et les jours sont ceux du registre ; le rattrapage hors écran donne le même récit qu'un pas horaire (banc). Écarté : un second appel dans chaque module (oublis, doublons, fichiers d'un autre chantier) ; un récit recalculé à la lecture depuis `g.log` (32 entrées noyées par les entrées courantes, aucune heure, textes libres).
- Deux faits internes complètent ce que le journal technique ne porte pas : `encounterStarted` (rencontres : mises en file, écrites au pas suivant `OnTickEvenPaused` hors de toute transaction, comme les événements de LK12-T02) et `memberDied` d'un corps présent tué par un joueur (publié par `LK_Bodies` juste avant la mort au registre : la mort qui suit devient `killed`). `memberLeft` (publié juste après l'entrée `left`, avant l'écriture) donne le rôle d'un membre déjà retiré.

### Correspondance

| Entrée technique | Récit | Arguments |
|---|---|---|
| `founded` | `settled` (foyer connu) ou `founded` | — |
| `admin` « home a -> b » | `moved` | — |
| `leader` | `leader` ou `leaderless` (aucun chef) | rôle |
| `died` | `died`, ou `killed` après un `memberDied` avec tueur | rôle |
| `left` | `left` (rôle par `memberLeft`) ; rien après `departure` ; supprimée si raison `dispersed` | rôle |
| `departure` (LK09-T05) | `deserted` | rôle |
| `recruit` | `recruit` | rôle |
| `expedition` abstraite (LK09-T02) | `expedition`, à l'heure exacte du départ | taille de l'équipe, lieu |
| `expedition` « trip n to … » (LK05-T05) | `trip` | taille de l'équipe |
| `return` (abstraite, physique, équipe perdue, expédition perdue) | `returned` ou `noneBack` | revenus |
| `clash` (LK09-T05) | `attackWon`, `attackLost`, `defenseWon`, `defenseLost` | nom de l'autre groupe |
| `gone` | `wiped` ou `dispersed` | — |
| `relief` / `relieved` (LK09-T04) | `relief` / `relieved` | nom de l'autre groupe |
| fait `encounterStarted` | `encounter`, une par groupe et par jour (compte augmenté) | nombre |

Restent au seul journal technique : `joined` (doublon de `recruit` ou de la création), `loss` et `remains` (chaque mort a son entrée), `trip` (bascule hors écran d'une expédition physique, même expédition), `wounded`, `task`, `objective`, `ration`, `shortage`, `upkeep`, `alert`, `defense`, `care`, `supply`, `aid`, `trade`, `conflict`, `illness`, `raid`, `revenge`, `admin` hors foyer.

Le texte technique n'est lu que pour des formes stables écrites par le moteur (« `<membre> <rôle>` » d'une recrue ou d'un départ, « `: <n> back` » ou « `, <n> back` » d'un retour, « `no one came back` », « `attack|defend grp-<n> won|lost:` », « `home ` ») ; le banc vérifie que ces formes sont toujours présentes dans le code qui les écrit. Le reste vient de l'état vivant du groupe (`g.expedition`, `g.trips.cur`, membres, noms des groupes).

### Format (version 1)

`g.journal = { v = 1, n = <prochain numéro>, e = { entry, ... } }`, au plus `Journal.SIZE` = 40 entrées (les plus anciennes oubliées), numéros croissants jamais réutilisés dans le groupe (un journal remis à neuf garde sa numérotation si elle est lisible).

`entry = { n, day, hour, kind, args, member, npc }` : `day` = jour de jeu du fait technique (celui de `g.log`) ; `hour` = heure du jour (0..23) du début de l'heure de jeu du fait : heure simulée en cours pendant la simulation hors écran (`Groups.hourContext`), heure de départ exacte d'une expédition abstraite, sinon heure courante de l'horloge ; `kind` dans la liste fermée `Journal.KINDS` ; `args` : au plus 4 valeurs (chaînes de 64 octets au plus, entiers) ; `member`, `npc` : identifiants publics (ceux que `API.getGroup` rend déjà).

Aucune coordonnée, aucun compte de joueur, aucun secret d'histoire n'est écrit dans une entrée : le journal entier est public par construction.

### Texte composable EN/FR

Une entrée ne stocke pas de texte : clé `IGUI_LK_Journal_<kind>` et arguments positionnels `%1`, `%2`. Un argument de type rôle ou lieu porte sa propre clé (`IGUI_LK_Journal_Role_<rôle>`, `IGUI_LK_Journal_Place_<lieu>`), résolue d'abord, repli sur l'identifiant brut. La fenêtre admin compose sur le client (langue du joueur) ; `API.journal` ajoute `text` composé sur l'autorité quand ses traductions sont chargées (solo, hôte), `nil` sur un serveur dédié où la clé et les arguments font foi (le consommateur compose côté client, ou transmet clé et arguments au LLM). Écarté : textes EN/FR dans des données Lua comme `LK_Stories` : un récit de faits répétitifs se compose très bien par clés, et le texte reste traduisible par les fichiers `.json` habituels.

### Bornes et coût

40 entrées par groupe et 64 groupes au plus : environ 2 560 petites entrées dans le registre (moins de 300 Kio en RSV2, sous la borne de 4 Mio de `RS_Codec`). Une entrée par fait ; aucune lecture du monde. File des rencontres bornée à 64 faits.

## Limites et reste

- Hors jeu seulement (banc lupa) ; non exécuté dans la VM Kahlua.
- Monde existant : aucun récit rétroactif (le journal commence à la mise à jour).
- Les heures d'un fait écrit hors simulation viennent de l'horloge au moment de l'écriture. Une erreur Lua au milieu d'un pas de simulation laisserait `Groups.hourContext` posé jusqu'au pas suivant (heure d'entrée fausse d'au plus quelques heures).
- Raids et vengeances (LK11-T05, LK11-T07), troc, aide et soins ne sont pas au récit (formats en cours d'évolution, autre chantier) : à ajouter par une ligne de `TECH` quand ils seront stables. Le lieu d'une expédition physique n'est pas nommé.
- `day` suit la convention de la simulation (jour de l'heure simulée k = floor(k / 24) + 1) : l'heure 6 h – 7 h est comptée au jour suivant.
- Les traces lisibles en jeu (carnet du foyer, notes sur le chef) : LK10-T04, [traces.md](traces.md).
