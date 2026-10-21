# Parole de proximité des PNJ

- Tâches : LK11-T04 (création), LK11-T09 (bulle dessinée par le mod, phrase du joueur) ; servira E08-T03 (initiatives de parole et réplique de secours sans pont), E08-T04 (conversations entre PNJ), LK11-T02 (sommations), LK05 (routines : repos, faim, alerte), LK07 (blessure)
- Build : 42.21.0 — Date : 2026-10-11 — Statut : brouillon

Code : choix et envoi `media/lua/server/LivingKnox/LK_Speech.lua` (`LivingKnox.Speech`, autorité seulement), affichage `media/lua/client/LivingKnox/LK_SpeechView.lua` (`LivingKnox.SpeechView`, client MP et solo), catalogue `media/lua/shared/LivingKnox/Data/Speech.lua` (`LivingKnox.SpeechData`, données seules), textes `Translate/EN|FR/IG_UI.json` (clés `IGUI_LK_Speech_<id>`). Tests : `tests/test_lk_speech.py` ; suite en jeu `lk.speech` (`dev/.../shared/RST/suites/RST_LKSpeech.lua`).

## Problème

Un PNJ de Living Knox doit pouvoir dire quelque chose à voix haute : des répliques courtes par situation (salut, avertissement, alerte…), et plus tard les répliques rédigées par le LLM du carnet. Chaque joueur qui l'entend doit lire la phrase **une seule fois**, au-dessus du corps du PNJ ; un joueur trop loin ne reçoit rien. Le serveur décide ; le texte est affiché dans la langue de chaque client.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Le chat « dire » natif exige un auteur `IsoPlayer` (portée et bulle) : un PNJ ne peut pas y parler. | ADR B17 (`J/chat/defaultChats/RangeBasedChat.java:75`, `114`) | confirmé statiquement |
| `addLineChatElement(texte, r, g, b, police, portée, étiquette, 6 booléens)` existe sur tout `IsoGameCharacter` ; chaque personnage (zombie compris) a un `ChatElement` créé par le constructeur. | `J/characters/IsoGameCharacter.java:817`, `6719-6725` | confirmé statiquement |
| La ligne n'est posée que hors serveur, pour chaque joueur local qui la lirait au moins en partie (brouillage < 1) ; un sourd la lit (seuls TV, radio et pièce de véhicule lui sont cachés). | `J/chat/ChatElement.java:174-201` | confirmé statiquement |
| Règle d'audition de la bulle : même pièce = portée × 2 et lecture forcée ; même bâtiment et même étage = × 2 ; un seul des deux dans un bâtiment = × 0,5 et brouillé ; −25 % par étage d'écart et brouillé ; distance euclidienne ; lecture complète sous 0,6 × portée. | `J/chat/ChatElement.java:204-237`, `121-136` (`useEuclidean = true`, :31) | confirmé statiquement |
| La ligne est mise à jour par `updateTextObjects` (`IsoGameCharacter.update`) et dessinée par `renderlast` pour tout personnage qui a une ligne à afficher ; `IsoCell.renderLast` appelle `renderlast` de tous les objets mobiles. Un zombie distant d'un client MP passe aussi par `super.update()`. | `J/characters/IsoGameCharacter.java:6862-6891`, `8390`, `6916-7011` ; `J/iso/IsoCell.java:3114-3121` ; `J/characters/IsoZombie.java:2703-2773` | confirmé statiquement |
| Un `IsoZombie` n'a qu'une ligne de bulle (`new ChatElement(this, 1, …)`) : une nouvelle réplique remplace la précédente. | `J/characters/IsoGameCharacter.java:817` | confirmé statiquement |
| `getSayLine()` rend la dernière ligne posée. | `J/characters/IsoGameCharacter.java:6605-6608`, `J/chat/ChatElement.java:98-100` | confirmé statiquement |
| Essai solo du 2026-10-11 : réplique livrée (`speech … heard by 1 player`) mais **aucune bulle vue** au-dessus du PNJ avec `addLineChatElement`. Relecture du Java : aucun obstacle propre à un zombie (même `ChatElement.addChatLine` que la bulle du joueur, `RangeBasedChat.java:114-140` ; `renderlast` dessine dès `getHasChatToDisplay()`, `IsoGameCharacter.java:6928-7010` ; zombies de `getObjectList()` parcourus par `FBORenderCell.java:300-303` et `IsoCell.java:3114-3121` ; lot dessiné par `IngameState.java:1214`). Cause non établie. | console du 2026-10-11, Java cité | constaté en jeu ; cause inconnue |
| Durée d'une ligne de `ChatElement` : 314 « tics » décomptés de 1,25 × `GameTime.getMultiplier()` à chaque mise à jour du personnage (vitesse de jeu comprise) ; un zombie n'a qu'une ligne. | `J/chat/ChatElement.java:249-252, 371` ; `J/ui/TextDrawObject.java:285-293` | confirmé statiquement |
| `OnPreUIDraw` est déclenché à chaque image d'interface ; `isoToScreenX/Y(joueur, x, y, z)` rend la position à l'écran (caméra, zoom, coin de l'écran du joueur) ; un étage vaut 96 × `tileScale` px et les noms et bulles vanilla sont posés 64 × `tileScale` px au-dessus des pieds, soit z + 2/3. `getTextManager():DrawStringCentre(UIFont, x, y, texte, r, g, b, a)` dessine depuis Lua (procédé du Lua vanilla `client/erosion/debug/DebugDemoTime.lua:194-196`, ombre noire décalée). | `J/ui/UIManager.java:303` ; `J/Lua/LuaManager.java:3355-3370, 3428-3431, 6938` ; `J/iso/IsoUtils.java:76-79, 104-108` ; `J/characters/IsoGameCharacter.java:6934-6935` ; `J/ui/TextManager.java:80` | confirmé statiquement |
| `player:Say(texte)` (solo) passe par `ChatManager.showInfoMessage` → canal « dire » solo → bulle du joueur (`RangeBasedChat.showInSpeechBubble`) ; `Say` d'un zombie ne fait rien (`isZombie`). En MP, `processSayMessage` affiche la bulle localement avant l'envoi. | `J/characters/IsoGameCharacter.java:6655-6660, 6686-6688` ; `J/chat/ChatManager.java:115-123, 306-313` ; `J/chat/defaultChats/RangeBasedChat.java:91-95` ; base `ui-windows.md` | confirmé statiquement |
| Ligne de chat locale sans paquet : `ChatBase:createMessage`, `setLocal(true)`, `showMessage` ; canal « dire » découvert par `OnAddMessage` et reconnu par `tostring(chat:getType()) == "say"` (`ChatType` non exposé : `getType():getValue()` lève une erreur en jeu, E17-T14). Pas de chat en solo. | base `ui-windows.md` (« Chat dire ») ; `radio-dynamic.md` | confirmé statiquement |
| Le serveur MP ne traduit pas les textes des mods (`getText` rend la clé) ; `getText`/`getTextOrNull` acceptent des paramètres variables. | base `api-42-21.md` ; `J/Lua/LuaManager.java:6949-6957` | confirmé statiquement |
| Commandes serveur livrées en RELIABLE non ordonné ; table vide reçue en `nil`. | base `multiplayer.md` | confirmé statiquement |

## Choix (2026-10-11)

### Langue : clés de traduction, rendues par chaque client

Contrairement aux récits ([recits.md](recits.md)), une réplique n'est **jamais** lue par le serveur, le journal ou le LLM : elle ne sert qu'à l'affichage. Le serveur envoie donc la **clé** (`IGUI_LK_Speech_<id>`) et chaque client la traduit dans sa langue (`getTextOrNull`). Les textes sont dans `IG_UI.json` (UTF-8 en clair, sans échappements d'octets ; une troisième langue n'est qu'un fichier de plus). Deux joueurs de langues différentes voient la même réplique, chacun dans sa langue (banc). Le texte déjà rédigé (LLM) passe tel quel.

### Catalogue (liste fermée, 44 répliques)

Situations : `greet` (salut), `warn` (avertissement : trop près), `alert` (danger), `hurt` (blessure du PNJ), `hungry` (faim), `rest` (repos), `farewell` (au revoir), `smalltalk` (propos sans engagement : réplique de secours sans pont, E08-T03). Attitude envers le joueur visé, en trois bandes : `friendly` (confiant, favorable), `neutral` (prudent), `hostile` (méfiant, hostile). Une réplique peut être réservée à des types de groupe (`types`) ou des rôles (`roles`, dont `leader`) ; elle pèse alors plus lourd (+2 type, +3 rôle, base 1). `alert`, `hurt`, `hungry`, `rest` ne dépendent pas de l'attitude (adressées au groupe ou au PNJ lui-même), sauf une réplique de faim réservée aux amis. Chaque situation a, pour chaque bande, au moins une réplique sans type ni rôle (`Speech.checkData`). Aucune réplique ne révèle l'état réel du groupe (stock, foyer, effectif). Textes français au tutoiement, sans accord au genre du PNJ ni du joueur ; jeu de caractères Latin-1 seulement (police des bulles).

### Contexte d'un PNJ

`Speech.context(npcId, joueur)` : type du groupe et rôle du membre (`leader` pour le chef) par `LK_Groups`, attitude du groupe envers l'identité de personnage du joueur par `LK_Hostility.get` ; sans joueur ou sans identité liée : niveau de départ du type ; sans groupe : neutre. La bande colore la bulle (vert pâle, blanc cassé, rouge pâle : I9.5).

### API (autorité)

- `Speech.say(npcId, texte | { key, params }, opts)` → `{ id, heard, names }` ou `nil, raison`. Point d'entrée d'E08-T03 et du dialogue du carnet : `opts.id` (identifiant de la demande, pour l'absence de doublon), `opts.name` (auteur de la ligne de chat, fourni par la fiche serveur), `opts.range` (1..60, défaut 25), `opts.chat` (défaut vrai), `opts.band`. `heard` rend les joueurs auditeurs (pour l'historique du carnet). Texte : 1..200 octets sans caractère de contrôle ; clé `IGUI_[%w_]+`, 4 paramètres au plus (64 octets chacun). Raisons : `bad text`, `bad key`, `bad params`, `bad id`, `npc not embodied (<état>)`, `nobody hears`, `not the authority`.
- `Speech.bark(npcId, situation, opts)` → résultat de `say` + `line`. `opts.player` (joueur visé), `opts.band` (force l'attitude), `opts.range`, `opts.chat` (défaut **faux** : bulle seule, pour ne pas remplir le chat). Délais (I9.5) : `GAP_MS` = 6 s entre deux répliques du même PNJ ; `SAME_MS` = 90 s avant de redire la même situation au même joueur ; la dernière réplique du PNJ est évitée quand une autre convient. Raisons en plus : `unknown situation`, `cooldown`, `said recently`, `no line for …`.
- La probabilité de parler (I9.5) reste à l'appelant (routines, sommations, initiatives) : `bark` parle toujours si rien ne l'en empêche.

### Auditeurs et livraison

- Auditeurs calculés **à l'instant de la réplique depuis le corps du PNJ** (`Bodies.find`) : candidats du relais des consignes en MP (`Directives.targets` : joueurs à 100 cases et propriétaire, comme le relais des gestes LK03-T05), joueurs locaux en solo ; retenus seulement s'ils liraient la phrase **en entier** selon la règle de la bulle vanilla (`Speech.hears` ; pas de texte brouillé ; mort ou endormi exclus). Personne n'entend : rien n'est envoyé et le délai n'est pas consommé.
- MP : une commande `speech` (module `LivingKnox`) **par auditeur**, `{ u = { id, npc, o, r, b, k, p | t, n, chat } }` ; aucune pour les autres. Identifiant `sp-<départ du serveur>-<n>` ou celui de l'appelant ; le client garde les 128 derniers et ignore un identifiant déjà vu (livraison répétée). Solo : appel direct de `SpeechView.receive`, aucune commande.
- Client : ligne de chat (si `chat`, nom fourni et canal « dire » connu ; MP seulement), puis bulle sur la copie locale du corps (corps connu de `LK_Anim.knownBodies`, sinon joueur réanimé de même `onlineId`). Corps pas encore chargé : bulle retentée 3 s, puis abandonnée (le chat l'a déjà montrée s'il y en avait une).

### Bulle dessinée par le mod (LK11-T09)

- `SpeechView.show(corps, texte, couleur, npc)` pose la bulle (une par corps ; morceaux successifs et file d'attente : voir ci-dessous) ; `SpeechView.draw`, abonné à `OnPreUIDraw`, la dessine à chaque image d'interface pour chaque joueur local : point `isoToScreenX/Y(joueur, x, y, z + 2/3)` (hauteur des noms et bulles vanilla), lignes de 60 caractères au plus empilées vers le haut (bas de la dernière ligne à ce point), police `UIFont.Dialogue`, ombre noire (décalages −1 et +1) puis texte à la couleur de l'attitude.
- Durée en **temps réel** : 5 s + 60 ms par caractère, 15 s au plus ; fondu sur le dernier quart (comme `ChatElement`). Bulle oubliée à l'échéance, ou quand le corps meurt ou quitte le monde (plus de case). Aucune règle d'audition refaite : le serveur a choisi les auditeurs.
- Une erreur de dessin vide les bulles et n'écrit qu'un avertissement (pas une erreur par image).
- Morceaux (E17-T13, 2026-10-14) : un texte de plus de `PIECE` (180) caractères est découpé par
  `RS_TextCut.pieces` (fin de phrase, sinon virgule, point-virgule ou deux-points, sinon entre deux mots, jamais dans un
  mot ; même règle que la radio, `radio-groupes.md`, « Découpe des répliques ») et ses morceaux s'affichent l'un après
  l'autre sur le même corps, chacun pendant sa propre durée (5 s + 60 ms par caractère, 15 s au plus). Avant E17-T13,
  une réponse au joueur (jusqu'à 1600 octets) tenait dans une seule bulle de 15 s au plus, quelle que soit sa longueur.
- File d'attente : un texte reçu pour un corps dont la bulle n'a pas fini sa durée passe à la suite de ses morceaux
  (`MAX_PIECES` 16 en attente au plus ; au-delà, la fin du texte reçu est oubliée, `stats.dropped`) ; une bulle
  échue est remplacée. Une bulle n'est jamais remplacée avant d'avoir eu le temps d'être lue (avant E17-T13, une
  réplique suivante du même corps l'effaçait aussitôt). Décision à confirmer : une réplique urgente (bark d'alerte)
  attend donc la fin de la bulle en cours du même corps.
- Longueur des répliques dites par un corps (E17-T13) : conversation entre PNJ, initiative et réaction d'un membre
  restent bornées à 200 octets (`LivingKnox.Speech.MAX_TEXT`) ; la consigne au modèle les demande en caractères
  (« at most two short sentences, under 150 characters in all », `npc_protocol.spoken_limit`), et le pont
  (`clean_speech`) coupe une réplique trop longue à sa dernière fin de phrase qui tient, même courte (avant : coupe au
  dernier mot avec « ... » dès que cette fin de phrase tombait dans le premier tiers), sinon à une virgule, sinon entre
  deux mots, suivie de « ... ». La fin d'une réplique trop longue est perdue, jamais affichée au milieu d'une phrase.
- Réponse du carnet à une phrase du joueur (E17-T14, 2026-10-15, `RS_Client.lua` `inject`) : la bulle est posée dès
  la réception de l'événement `speech`, en solo comme en MP. Seule la ligne de chat locale attend que le canal « dire »
  soit connu (découvert par le premier `OnAddMessage` de ce canal, qui peut ne jamais venir si personne ne parle) ;
  l'événement reste alors dans la boîte de réception pour la ligne de chat seulement, sans redessiner la bulle. Avant
  E17-T14, en MP, la bulle attendait elle aussi le canal, et le canal n'était **jamais** reconnu :
  `chat:getType():getValue()` levait « attempted index: getValue of non-table: say » à chaque message (`ChatType`
  n'est pas exposé à Lua ; journal client de l'essai MP du 2026-10-15, `rs.npctalk`) ; ni bulle ni ligne de chat
  n'étaient affichées. Reconnaissance par `tostring(chat:getType()) == "say"` dans `RS_Client.isSayChat` et
  `LK_SpeechView.observeMessage`.
- Contexte d'une conversation (E08-T05) : une ligne jointe (phrase du joueur, réponse au joueur) est bornée à 200 octets
  par la même découpe (`RS_Conversations` `cut`, avant : coupe à l'octet, au milieu d'un mot).
- Trace lisible depuis Lua : `stats.drawn` (dessins), `stats.pieces`, `lastDraw = { npc, text, x, y, player }`,
  `bubbles` (`rest` : morceaux en attente), `lastPieces = { npc, text, pieces }`, `pieceLog` (32 derniers morceaux
  affichés : `{ npc, text, at, ms }`).
- Les réponses du carnet (`RS_CarnetClient` → `RS_NPCProvider.bubble`) passent par `RS_LivingKnox.bubble` → même bulle (couleur de l'ancienne bulle du carnet) ; sans la vue (machine qui ne la charge pas), repli `addLineChatElement`.
- Pourquoi abandonner `addLineChatElement` sans cause prouvée : la bulle n'a pas été vue en jeu ; le dessin par le mod ne dépend plus de l'état du `ChatElement` du zombie (une ligne, durée liée à la vitesse du jeu), et la suite en jeu peut constater le dessin (coordonnées à l'écran).

### Phrase du joueur (LK11-T09)

- Ligne « Dire » de l'onglet Radio (`RS_RadioTalk.send`) : la phrase n'est prononcée qu'à l'acceptation du serveur (`accepted`) : `player:Say` en solo, `processSayMessage` sur un client MP (bulle locale du chat « dire », jamais `Say` en plus). Refus : seulement le motif en rouge.
- Ligne « Dire » de l'onglet Contacts (`RS_CarnetClient.talk`, E17-T06) : même règle à l'accusé `queued` (`speakAloud`), une seule fois (texte effacé après usage) ; une phrase venue du chat n'est pas redite. Refus (`error`) : rien.
- Aucun code ajouté : les deux chemins existaient (E06-T02, E17-T06) ; le banc le vérifie (`tests/test_carnet.py`, `PlayerSpeechTests`). L'essai du 2026-10-11 précédait la publication d'E17-T06 (Contacts).
- Aucun bruit pour les zombies (effet distinct, à l'appelant : ADR B17).

### Conversation entre membres pendant une pause (I3.8)

**Non faite ici** : elle demande de savoir quand un groupe est en pause et quels membres sont ensemble (routines LK05), et d'alterner les tours ; ce n'est pas trivial avec le seul catalogue. Laissée à E08-T04 (répliques `smalltalk` du catalogue comme repli sans pont).

## Alternatives écartées

- **Chat « dire » natif avec un auteur PNJ** : exige un `IsoPlayer` (ADR B17).
- **`IsoGameCharacter:Say`** sur le corps : sans effet sur un zombie (`IsoGameCharacter.java:6655-6658`).
- **`addLineChatElement` sur le corps** (choix de LK11-T04) : pas de bulle vue en jeu le 2026-10-11, cause non établie ; remplacé par le dessin du mod (LK11-T09).
- **`SayDebug`** : même `ChatElement`, police `Medium` blanche imposée (`ChatElement.java:138-159`).
- **Textes FR/EN dans les données Lua** (comme les récits) : utile quand le serveur ou le LLM lit le texte, inutile ici ; impose des échappements d'octets.
- **Même texte calculé par chaque client** (tirage local) : divergences entre observateurs ; le serveur choisit une seule réplique, chacun la lit dans sa langue.
- **Réplique adaptée à l'attitude de CHAQUE auditeur** : deux joueurs verraient des phrases différentes dans la même bulle. L'attitude retenue est celle du joueur visé (`opts.player`).
- **Diffusion à tous les joueurs proches (100 cases) avec filtrage par le client** : envoie le texte à des joueurs qui ne doivent pas l'entendre.

## Idées reprises

- I9.5 : répliques par situation, délai entre deux répliques par PNJ, couleur selon l'attitude. Écart : pas de « voix fixe » sonore (les corps sont réduits au silence, [neutralisation.md](neutralisation.md)) ; la probabilité de parler reste à l'appelant.
- I3.8 : non reprise ici (voir ci-dessus), renvoyée à E08-T04.

## Tests

- Banc lupa (`tests/test_lk_speech.py`, 25 tests ; LK11-T09 : `DrawTests` — dessin à chaque `OnPreUIDraw` au point de la tête, ombre, couleur, caméra et zoom, lignes coupées et empilées, fondu et échéance en temps réel, remplacement, corps retiré, erreur de dessin, réponse du carnet par la même bulle ; dessin chez A et B, rien chez C) : serveur + A et B proches + C dans le rayon du relais mais à 23 cases : A et B reçoivent une commande chacun, C aucune ; livraison répétée de chaque commande ignorée (une seule bulle par client) ; A en anglais, B en français pour la même clé ; rien sur le serveur ; joueur qui entre dans la portée : seulement la réplique suivante ; personne n'entend : rien envoyé, délai non consommé ; client MP sans partie serveur ; texte rédigé avec nom → ligne de chat locale (auteur du serveur, sans bulle de joueur ni bruit) sur le seul client qui connaît le canal « dire », bulle chez les deux ; bark sans ligne de chat, coloré ; corps chargé après la réplique (bulle en attente puis affichée) ou jamais (abandon après 3 s) ; clé paramétrée, clé inconnue ; entrées refusées ; délais par PNJ et par (situation, joueur), dernière réplique évitée ; catalogue (contrôle, traduit en EN et FR, Latin-1, longueurs), choix par bande, type et rôle, poids ; contexte (type, chef, attitude du joueur, départ du type, sans groupe) ; règle d'audition (dehors, même pièce, même étage, dehors/dedans, deux bâtiments, étage, mort, endormi) ; solo par appel direct, sans réseau ; suite `lk.speech` listée ; sources sans caractère non ASCII dans le code.
- Morceaux de bulle (E17-T13) : `tests/test_lk_speech_pieces.py` (réponse longue lue en phrases entières l'une après
  l'autre, chacune pendant sa durée ; réponse du carnet par la même découpe ; texte suivant mis en file ; phrase unique
  coupée aux virgules ; file bornée ; corps retiré ; pont : `clean_speech` garde une fin de phrase même courte, coupe
  dans la limite d'octets, consigne en caractères) et `tests/test_conversations.py`
  (`test_long_line_joined_in_whole_sentences`). En jeu : `RST.run({ suite = "rs.npctalk", tags = "world" })`, test
  E17-T13 (réponse longue demandée au modèle, morceaux mesurés et ordre vérifié par `pieceLog`).
- VM Kahlua : non couvert (aucune chaîne non ASCII dans le Lua de la tâche ; `RS_TextCut` est vérifié en Kahlua réelle
  par `tests/test_kahlua.py`).
- En jeu, solo : `RST.run({ suite = "lk.speech", tags = "world" })` (bulle posée sur un PNJ créé et **dessinée** au moins une fois à un point de l'écran, doublon ignoré, délai, texte rédigé, PNJ à 30 cases inaudible). MP à la séance finale.
- Phrase du joueur : `tests/test_carnet.py`, `PlayerSpeechTests` (Radio : solo `Say`, MP `processSayMessage`, jamais sur refus ; Contacts : une fois à `queued`, jamais sur `error`, pas de redite d'une phrase du chat).

### Protocole en jeu

1. Solo (`rstest-solo`, mod de dev, option Living Knox activée) : `RST.run({ suite = "lk.speech", tags = "world" })` ; puis `LKB.spawn(2, 0)` et, dans la console, `LivingKnox.Speech.bark("lk-1", "greet", { player = getPlayer() })` puis **fermer la console** : une bulle au-dessus de la tête du PNJ, lisible, de la couleur de l'attitude, pendant 5 à 8 s (`LivingKnox.SpeechView.stats.drawn` augmente) ; `LivingKnox.Speech.say("lk-1", "Testing.")` : la bulle est remplacée ; zoomer et dézoomer : elle reste au-dessus de la tête ; carnet, onglet Contacts, ligne « Dire » vers ce PNJ : la phrase du joueur au-dessus de son personnage, puis la réponse au-dessus du PNJ ; onglet Radio, ligne « Dire » sur une fréquence : la phrase au-dessus du joueur, rien sur un refus ; s'éloigner à 20 cases : `say` rend `nil, "nobody hears"`.
2. MP (séance finale, serveur dédié + 2 clients) : A et B à moins de 10 cases du PNJ, un troisième joueur à 20 cases (ou B s'éloigne) ; sur le serveur `LivingKnox.Speech.bark("lk-1", "greet")` : A et B voient la bulle une fois (B en français si son jeu l'est), le joueur éloigné rien ; journal serveur en Debug : `speech sp-… by lk-1 heard by 2 player(s)` ; `LivingKnox.Speech.say("lk-1", "Hello.", { name = "Kate" })` après qu'un joueur a parlé dans le chat : ligne « Kate » dans son chat.

## Points ouverts

- ⚠ Rendu réel de la bulle dessinée (position au-dessus de la tête, lisibilité de l'ombre sans fond, durée) à voir en jeu ; écran partagé non découpé (bulle d'un joueur visible hors de sa moitié d'écran) ; ligne de chat MP non vérifiée en jeu.
- ⚠ Cause de l'absence de bulle `addLineChatElement` sur un zombie non établie (aucun obstacle trouvé dans le Java 42.21.0).
- ⚠ Aucun appelant automatique encore : sommations (LK11-T02), routines (LK05), blessures (LK07), initiatives (E08-T03) appelleront `bark` ou `say`.
- ⚠ Le carnet (ADR B17) envoie toujours ses propres répliques LLM (`RS_Carnet_Server` commande `speech` du module RadioSurvivor) ; son passage par `Speech.say` relève d'E08-T03 (ne pas afficher les deux).
- ⚠ Délais en mémoire seulement (remis à zéro au redémarrage) ; valeurs (portée 25, 6 s, 90 s) à recalibrer.
- ⚠ Textes à relire par l'utilisateur.
