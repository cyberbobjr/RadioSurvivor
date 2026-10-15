# Traces lisibles en jeu : carnet du foyer, notes sur le chef

- Tâche : LK10-T04 (idée I8.6, « foyer qui se raconte par son décor ») ; s'appuie sur LK10-T02 ([journal.md](journal.md)), LK10-T01 ([recits.md](recits.md)), LK08-T04 ([foyers.md](foyers.md)), LK09-T04 (groupe disparu) et LK07-T05 (butin du cadavre, [sante.md](sante.md))
- Code : `Contents/mods/batman_RadioSurvivor/42.21/media/lua/server/LivingKnox/LK_Traces.lua` (`LivingKnox.Traces`, autorité seulement) ; banc `tests/test_lk_traces.py` ; suite en jeu `lk.traces` (`dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKTraces.lua`, tags `world`, `server`)
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\` ; Lua vanilla **M/** = `ProjectZomboid\media\lua\`) — Date : 2026-10-12 — Statut : brouillon, testé hors jeu seulement

Base de connaissances : [quest-building-blocks.md](../../../.claude/pz-knowledge/quest-building-blocks.md) (document en lecture seule `addPage` + `setLockedBy`, 15 lignes par page), [api-42-21.md](../../../.claude/pz-knowledge/api-42-21.md) (note écrite vide si non remplie, traductions absentes sur un serveur MP), [multiplayer.md](../../../.claude/pz-knowledge/multiplayer.md) (objet ajouté à un conteneur par le serveur), [world-placement.md](../../../.claude/pz-knowledge/world-placement.md) (quand poser). Aucune ligne de Bandits! ni de Project A-Life n'a été lue.

## Problème

Le journal de récit (`g.journal`) n'est lisible que par un administrateur ou par RadioSurvivor. Un joueur qui fouille le foyer d'un groupe disparu, ou le corps d'un chef qu'il a tué, doit pouvoir lire l'histoire du groupe dans un objet du jeu, une seule fois, sans y apprendre de secret.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Un objet `CanBeWrite` reçoit son texte par `addPage(i, texte)` ; `setLockedBy(nom)` ne laisse que « Lire » à tout autre nom (admin MP excepté), et « Lire » est grisé si `isEmptyPages()`. | J/inventory/types/Literature.java:446-482 ; M/client/ISUI/ISInventoryPaneContextMenu.lua:566-585 ; ISUIWriteJournal.lua:318-325 | confirmé statiquement |
| Page de 15 lignes (`setMaxLines(15)`), 1 200 caractères au plus (`15 × 80`) ; un lecteur d'un document verrouillé voit autant de pages qu'il y en a d'écrites. | M/client/ISUI/ISUIWriteJournal.lua:22-28, 310, 318-325 | confirmé statiquement |
| Pages et verrou sauvegardés avec l'objet (`save`/`load`), donc envoyés avec lui (`sendAddItemToContainer`, contenu d'un cadavre). | J/inventory/types/Literature.java:280-334 ; base multiplayer.md | confirmé statiquement |
| `Base.Notebook` : `CanBeWrite`, 10 pages ; `Base.SheetPaper2` : `CanBeWrite`, 1 page ; aucun `OnCreate`. | `media/scripts/generated/items/literature.txt:1819-1840` | confirmé statiquement (banc `test_document_items_are_writable_vanilla_items`) |
| `OnZombieDead` part avant la création du cadavre ; ce qui est mis dans l'inventaire du corps part dans le cadavre, reçu par chaque client. | en-tête de `LK_Loot.lua` (J/characters/IsoZombie.java:4599-4609, IsoDeadBody.java:327-332, 2345-2376) | confirmé statiquement |
| Un serveur MP (dédié ou hébergé) n'a pas les traductions des mods ; `Translator.loadFiles()` les recharge dans la langue du processus serveur. | base api-42-21.md | confirmé statiquement |

## Choix (2026-10-12)

### Carnet du foyer : déposé quand le groupe a disparu (décision à confirmer)

Le contrat laissait le choix entre « foyer abandonné ou disparu » et « mis à jour au plus une fois par jour tant que le groupe vit ». Retenu : **le plus simple, une seule pose, à la disparition** (marque `gone` de LK09-T04, groupe décimé ou dispersé). Raisons : un document figé n'est jamais réécrit (aucun objet à retrouver et à remplacer pendant qu'un joueur le lit ou l'emporte), le récit est complet (il finit par « Plus personne » ou « dispersés »), et c'est le moment où le foyer devient une ruine que le joueur fouille. Écarté : mise à jour quotidienne (objet à suivre, à réécrire et à resynchroniser, lecture des affaires d'un groupe vivant) ; foyer déplacé (l'ancien foyer n'est pas gardé au registre).

- Quand : à chaque `LoadChunk` (au plus une fois par seconde) et à chaque minute de jeu, pour chaque groupe disparu sans marque ; rien tant que `LivingKnox.Homes.ready(home)` est faux (case du foyer et coins du carré de 10 cases lisibles, bâtiment complet ou exploré : même règle que l'aménagement).
- Où : la caisse ou la tente posée par l'aménagement (`ModData.LKHome` du groupe) ; sinon le conteneur le plus proche du foyer dans le même bâtiment (hors de tout bâtiment pour un camp) ; sinon au sol sur la case du foyer (`AddWorldInventoryItem`, transmis). Dans un conteneur sur un serveur : `AddItem` puis `sendAddItemToContainer`.
- Contenu : « Carnet : <nom> », le résumé public de l'histoire (`Stories.compose(type, storySeed)` puis `publicView`, ou le résumé anglais du registre sans graine), puis le journal de récit, une ligne « Jour <j>, <hh> h - <fait> » par entrée, le plus ancien d'abord. Si tout ne tient pas en 10 pages, les entrées les plus anciennes sont omises.

### Notes sur le chef : à la mort de son corps

- Fait `memberDied` publié par `LK_Bodies.onZombieDead` (corps présent, `offscreen = false`, champ `body`) : publié **avant** la mort au registre (`Materialize.onBodyDied`), donc `g.leader` désigne encore le mort, et avant le cadavre, donc la feuille part avec lui comme le butin de LK07-T05.
- Feuille `Base.SheetPaper2` (une page) : « Notes : <nom> », la motivation publique du groupe, puis les entrées les plus récentes qui tiennent dans la page.
- Un chef mort hors écran (simulation abstraite, sans corps) n'en a pas. Un membre qui n'est pas chef n'en a pas.

### Mise en page

Texte coupé aux espaces à 40 caractères par ligne (« \n » explicites), 15 lignes par page ; une entrée n'est jamais coupée entre deux pages si elle tient dans une page ; page bornée à 1 200 caractères. La largeur réelle de la fenêtre (350 px, police Small) n'est pas mesurée : 40 est une estimation prudente, à vérifier en jeu.

### Une seule fois

- Marque dans le registre privé des groupes, champ facultatif `traces` (schéma 1 inchangé, contrôlé par `LK_Traces`, remis à neuf s'il est malformé) :
  `traces = { v = 1, home = { hx, hy, hz, day, state = "placing" | "done", where = "container" | "floor" | "found" }, chiefs = { "m-<k>", ... } }` (16 chefs au plus).
- Carnet : marque `placing` écrite **avant** le dépôt, `done` après ; une marque `placing` relue vaut « fait » (avertissement), jamais un second carnet. Registre plus ancien que le monde : sans marque, un carnet du groupe trouvé autour du foyer (`ModData.LKTrace` = groupe, `LKTraceKind = "home"`) rétablit la marque (`where = "found"`) sans rien déposer.
- Notes : marque `LKTraceChief` dans les ModData du corps et identifiant du chef ajouté à `traces.chiefs` avant la création de la feuille.

### Langue et multijoueur

- Le texte d'une page est **figé dans l'objet** au moment du dépôt, dans la langue de la machine qui le compose : celle du joueur en solo, celle du processus serveur en MP (dédié ou hébergé). Un serveur MP n'a pas les traductions des mods : `Translator.loadFiles()` est appelé une fois s'il le faut (même parade que les appels radio de RadioSurvivor) ; sans traductions malgré cela, rien n'est déposé (une ligne au journal) et le groupe reste en attente jusqu'au redémarrage.
- Les histoires n'existent qu'en anglais et en français (`Stories.text`) : toute autre langue du serveur reçoit l'histoire en anglais.
- Suivre la langue de chaque lecteur demanderait de recomposer la page côté client à l'ouverture (envelopper `ISUIWriteJournal`, ou un document `printMedia` de mod à paramètres injectés côté client) : hors du périmètre (contrat : « dans la langue du joueur qui lit si possible »), noté comme reste.
- Tout est fait sur l'autorité ; un client MP ne charge pas le module (`if isClient() then return end`).

### Aucun secret

Le journal de récit n'a ni coordonnée, ni compte de joueur, ni secret ([journal.md](journal.md)) ; seuls le résumé et la motivation **publics** de l'histoire sont lus (`publicView`), jamais `secrets` ; la marque et ses coordonnées restent dans le registre privé. Le nom d'un autre groupe (attaque, relève) apparaît, jamais la position de son foyer. Vérifié par le banc (`test_no_secret_and_no_coordinates_in_the_notebook`).

## Limites et restes

- ⚠ Hors jeu seulement (banc lupa) ; non chargé dans la VM Kahlua (`LK_Homes`, requis, s'abonne à des événements absents du banc Kahlua). Rendu réel à vérifier : retour à la ligne et nombre de lignes visibles, « Lire » proposé et non grisé, contenu reçu par un client MP (conteneur et cadavre).
- Langue figée à la création (voir ci-dessus).
- Groupes disparus avant cette version : leur carnet est déposé au prochain chargement de leur foyer ; chefs morts avant : aucune note.
- Un foyer déplacé n'a pas de carnet ; un groupe vivant n'en a pas (pas de mise à jour quotidienne).
- Un dépôt interrompu par une erreur Java (marque `placing`) n'est jamais refait : le foyer reste sans carnet (journalisé).
- Les suites en jeu qui créent un groupe puis le marquent disparu (`lk.relief`, `lk.admin`…) peuvent faire déposer un carnet à leur foyer de test s'il est chargé ; `LivingKnox.Traces.clear(gid)` le retire.

## Essai en jeu

`RST.run({ suite = "lk.traces", tags = "world" })` en solo, debout dans une maison (un conteneur proche montre le cas « caisse ou meuble »), ou `RST.server({ suite = "lk.traces", tags = "world" })` depuis un client admin. La suite imprime la première page de chaque document.
