# Perception des PNJ : vue, ouïe, lumière

- Tâches : LK05-T01 (création, 2026-10-11) ; suite : LK05-T02 (cadre de décision, lecteur), LK05-T03 (vigilance selon la routine), LK05-T08 (alerte)
- Build : 42.21.0 (Java décompilé `<decompiled>\42.21.0\java`, noté **J/** = `…\java\zombie\`) — Date : 2026-10-11 — Statut : brouillon

Code : `media/lua/shared/LivingKnox/LK_Senses.lua` (`LivingKnox.Senses`). Calcul appelé par `client/LivingKnox/LK_Executor.lua` (`Executor.pass` → `Senses.scan`), transport par le rapport d'état de `server/LivingKnox/LK_Reports.lua` (champ `sen`, [rapports.md](rapports.md)).

## Problème

Un PNJ doit savoir quels joueurs et quels zombies il voit ou entend, selon la distance, les murs et les portes, la lumière, le bruit, la posture et l'allure de la cible, et sa propre vigilance. Le résultat sert au cadre de décision du serveur (LK05-T02) : la perception **mesure**, elle ne décide rien. Elle doit être reproductible (mêmes entrées, même résultat), de coût borné, et rapportée à l'autorité sans faire confiance aveugle au client.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `LosUtil` est exposé à Lua ; `LosUtil.lineClear(cell, x0, y0, z0, x1, y1, z1, bIgnoreDoors)` parcourt les cases de l'axe principal et rend `TestResults` : `Clear`, `ClearThroughOpenDoor`, `ClearThroughWindow`, `ClearThroughClosedDoor`, `Blocked`. `IsoGameCharacter.CanSee` est exactement `lineClear(...) != Blocked` (coordonnées entières, `false`). | `J/Lua/LuaManager.java:2160` ; `J/iso/LosUtil.java:28-152, 648-653` ; `J/characters/IsoGameCharacter.java:4733-4735` | confirmé statiquement |
| Murs (matrice de vision de la case), porte fermée opaque, rideau fermé, barricade et fenêtre construite fermée : `Blocked`. Vitre d'une `IsoWindow` : **transparente, même fermée** (`ClearThroughWindow`). Porte vitrée fermée (`DOOR_TRANS`) : `ClearThroughClosedDoor`. | `J/iso/IsoGridSquare.java:6423-6539` ; `J/iso/objects/IsoDoor.java:914-940` ; `J/iso/objects/IsoWindow.java:381-401` | confirmé statiquement |
| Lumière d'une case : `getLightLevel(i)` = max(r, g, b) de l'éclairage calculé **pour le joueur local d'index i** ; seul un client (ou le solo) a un joueur local. Le repérage vanilla d'un zombie multiplie sa chance par la lumière de la case de la cible et, sans joueur, retombe sur `min(getDayLightStrength(), getAmbient())`. | `J/iso/IsoGridSquare.java:8896-8908` ; `J/characters/IsoZombie.java:1727-1732, 4638-4646` | confirmé statiquement ; ⚠ valeur sur une case hors de la vue du joueur local à mesurer |
| Repérage vanilla d'un zombie (`spottedNew`) : vision 10..20 cases (20 moins la nuit, la pluie ×2,5 et le brouillard ×7), chance ÷ (5 × écart d'étages + 1), demi-cercle avant favorisé (0 dans le dos, cosinus < −0,4), allure 0,8 / 1 / 1,5 / 2, joueur accroupi × `getSneakSpotMod`, tirage `Rand`. | `J/characters/IsoZombie.java:1662-1840, 4638-4652` | confirmé statiquement (valeurs de départ seulement) |
| Bruit du monde : `WorldSound.init` déclenche `OnWorldSound(x, y, z, rayon, volume, source)` sur toute machine qui l'ajoute ; un client MP l'ajoute aussi pour un bruit relayé par le serveur (source = personnage de l'émetteur). Les champs d'un `WorldSound` ne sont pas lisibles en Lua. | `J/WorldSoundManager.java:107-155, 464-481` ; `J/network/packets/sound/WorldSoundPacket.java:109-121` ; `J/network/GameServer.java:3042-3053` | confirmé statiquement |
| Ouïe vanilla d'un zombie : distance avec l'étage ×3, ×1,2 si autre pièce, encore ×1,4 si l'un est dehors (sur le rapport distance²/rayon²). | `J/WorldSoundManager.java:214-249` | confirmé statiquement |
| Pas d'un personnage : bruit du monde de rayon `ceil(volume × 10)`, moitié dans une pièce, émis **une fois sur 2** (accroupi : 1 sur 4 + Discrétion) et **jamais envoyé** (`doSend` faux) : aléatoire et local. | `J/characters/IsoGameCharacter.java:5312-5358` | confirmé statiquement |
| Posture et allure lisibles : `isSneaking`, `isRunning` (faux à partir de 3 niveaux d'épuisement), `isSprinting`, `isPlayerMoving`, `getTorchStrength` (copie distante : valeur réseau `mpTorchStrength`), `isGhostMode`, `isInvisible`, `isCrawling`. | `J/characters/IsoGameCharacter.java:3761, 10985, 12312-12330, 12396` ; `J/characters/IsoPlayer.java:1063, 1683-1695, 7628` ; `J/characters/IsoZombie.java:3998` | confirmé statiquement ; ⚠ drapeaux d'allure d'un joueur distant sur un client à mesurer |
| Regard d'un personnage : `getDirectionAngle()` en degrés, vecteur (cos a, sin a). | `J/characters/IsoGameCharacter.java:2622-2635` | confirmé statiquement |

## Choix (2026-10-11)

### Où tourne le calcul

Sur la machine qui **simule** le corps (client MP propriétaire, ou le solo), à chaque passage de l'exécutant : la lumière n'existe que là (éclairage par joueur local), la position et le regard du corps y sont à jour, et le résultat suit le chemin déjà contrôlé des rapports d'état (propriétaire, bail, ordre, cadence). Un serveur dédié ne calcule rien (aucun joueur local, aucune lumière) ; un corps simulé par le serveur n'a pas de perception (aucun joueur proche, cf. rapports.md, points ouverts).

Le fichier est **partagé** (`shared`) : le calcul tourne chez l'exécutant, la mémoire chez l'autorité, sans `require` de module serveur au chargement (lectures paresseuses de `LivingKnox.Reports`, `Executor`, `ZombieGuard`).

### Modèle (valeurs de `Senses.MODEL`, propres au mod, à recalibrer en jeu)

**Vue.** Portée = `SIGHT` 20 cases × lumière × météo × ligne de vue ÷ (1 + écart d'étages) × champ de vision × posture × allure × vigilance (× 0,5 si le PNJ est au sol), plafonnée à 30 :

| Facteur | Valeurs |
|---|---|
| Lumière L (case de la cible, 0..1 ; lampe tenue : au moins 0,9) | 0,25 + 0,75 × L → nuit noire 5 cases, plein jour 20 |
| Météo | max(0,3 ; 1 − 0,35 × brouillard − 0,125 × pluie) |
| Ligne de vue | `Clear` et `ClearThroughOpenDoor` 1 ; `ClearThroughWindow` et `ClearThroughClosedDoor` 0,8 ; `Blocked` 0 |
| Champ de vision (cosinus regard → cible) | ≥ 0,5 : 1 ; ≥ 0 : 0,6 ; ≥ −0,5 : 0,25 ; dos : 0 ; à 1,5 case ou moins : au moins 0,6 |
| Posture de la cible | joueur accroupi 0,5 ; zombie rampant 0,6 |
| Allure de la cible | immobile 0,7 ; marche 1 ; course 1,3 ; sprint 1,5 |
| Vigilance du PNJ (I2.2) | endormi 0 ; occupé 0,75 ; repos 1 ; garde 1,3 |

Exemples : joueur debout qui marche, de jour, en face d'un PNJ au repos : 20 cases ; immobile : 14 ; accroupi qui marche : 10 ; de nuit sans lumière : 5 (immobile : 3,5) ; avec une lampe : 18,5.

**Attention.** Par cible, une attention `a` de 0 à 1 : dans la portée, elle monte de `0,25 + 2 × (1 − d / portée)` par seconde ; hors de portée ou hors de vue, elle baisse de 0,25 par seconde (souvenir de 4 s). La cible est **vue** (`s`) quand elle est dans la portée avec `a = 1`. Une cible accroupie, à portée réduite, monte donc moins vite et n'est vue que plus tard ; au-delà de sa portée, jamais. Pas d'une durée `dt` bornée à 1 s.

**Ouïe.** Sans ligne de vue. Rayon = max(bruit propre selon l'allure, plus grand bruit du monde émis par la cible depuis 2 s) × vigilance ÷ murs ; distance = √(d² + (3 × écart d'étages)²). Bruit propre : joueur immobile 0, marche 5, course 10, sprint 15 (accroupi × 0,3) ; zombie immobile 2, en marche 5, plus vite 8. Murs : même pièce 1, autre pièce 1,2, l'un dehors 1,68 (facteurs vanilla appliqués au rayon). Ouïe selon la vigilance : endormi 0,35, occupé 0,8, repos 1, garde 1,25. Une cible entendue le reste 3 s (`h`). Les bruits du monde **sans** cible connue (ou d'une source non candidate) forment la liste `n` (3 plus forts, hors bruits des corps de PNJ) : base des enquêtes de LK05-T08.

**Allure** : drapeaux du joueur (`isSprinting`, `isRunning`, `isPlayerMoving`), et pour toute cible le déplacement mesuré depuis le passage précédent du même PNJ (≥ 0,5 case/s marche, 3,5 course, 5,5 sprint) ; la plus vive des deux. Les pas vanilla (aléatoires, locaux) ne servent pas de mesure : le bruit propre les remplace de façon déterministe.

**Vigilance** (`Senses.vigilanceOf`) : valeur posée par l'autorité (`Senses.setVigilance(id, kind)`), sinon déduite de l'exécution en cours (marche : occupé ; sinon : repos). En MP, la valeur décidée par le serveur est portée par la consigne courante (champ `vg`, LK05-T03, [routines.md](routines.md)) et lue par l'exécutant ; sans consigne reçue, vigilance déduite.

**Déterminisme.** Aucun tirage : mêmes mesures du moteur, même horloge passée en argument (`t`, `dt`) → même résultat ; candidats triés par distance puis clé, résumé trié (vu, attention, distance, clé).

### Coût par passage (`Senses.BUDGET`)

| Borne | Valeur |
|---|---|
| PNJ examinés par passage de l'exécutant (tous les 10 images), tour à tour | 4 |
| Cibles examinées par PNJ (les plus proches, rayon 30 cases, 2 étages) | 24 |
| Appels `LosUtil.lineClear` par passage (seulement si la cible est dans la portée sans ligne de vue) | 32 ; au-delà, la cible garde son état (compteur `losSkipped`) |
| Zombies de la cellule parcourus par passage (curseur au-delà) | 1000 |
| Bruits du monde retenus | 32 sur 2 s |

Compteurs : `Senses.stats` (`passes`, `npcs`, `targets`, `los`, `losSkipped`, `zombies`, maxima par passage, `last` du dernier passage).

### Transport et mémoire de l'autorité

- **Résumé** `sen` = `{ v = 1, nz, p = { { u, x, y, z, a, s, h } } (4 au plus), z = { { o, x, y, z, a, s, h } } (6 au plus), n = { { x, y, z, r } } (3 au plus) }` ; `nz` = zombies perçus en tout ; positions en cases entières. Porté par **chaque** rapport d'état `bodyReport` quand le module est chargé (jamais vide sur le réseau : `v` et `nz` toujours présents).
- **Cadence** : celle des rapports d'état (au plus 1 par seconde en marche, 1 toutes les 5 s au repos) ; un changement de la **signature** (cible apparue, vue, entendue, perdue ou déplacée de 2 cases) compte comme un changement d'activité : rapport au plus `MIN_MS` = 250 ms plus tard. Mesuré sur le banc : joueur entré dans le champ, vu par le serveur en moins de 3 s au lieu d'attendre les 5 s du repos.
- **Contrôles** : avec le rapport (LK03-T02 : propriétaire, bail, ordre, seau à jetons) ; forme et bornes du résumé (`Senses.validate`, refus du rapport entier : `bad report`, `out of bounds`) ; puis, rapport accepté, filtre par entrée (`Senses.accept`) : joueur inconnu de l'autorité, cible vue à plus de 30 + 6 cases ou à plus de 2 étages de la copie du serveur, cible entendue à plus de 150 + 6 cases, bruit plus loin que son rayon × 1,25 + 6 : entrée retirée (`stats.dropped`, ligne DEBUG). Distance recalculée par le serveur.
- **Lecture** : `Senses.perceived(npcId)` → `{ ms, age, stale, by, nz, seen, heard, p, z, n }` (copie ; `stale` au-delà de 15 s sans rapport) ; `Senses.perceivedPlayer(npcId, compte)`. Oubli avec l'état des rapports (`Reports.forget`, PNJ disparu).

### Fenêtres frappées (LK06-T11)

Décision de l'utilisateur du 2026-10-14 : le client propriétaire rapporte la fenêtre que frappe son zombie (le serveur ne
la connaît pas : paquet `Thump` seulement relayé, J/network/packets/character/ThumpPacket.java:54-63). Lecteur :
`Defense.thumpTargetOf` ([defense.md](defense.md)).

- **Transport (écart à confirmer)** : prévu dans le rapport d'état des corps (`bodyReport`, champ `sen`), il a dû en
  sortir : la campagne MP du 2026-10-15 (`tools/autoclient/runs/20261015-003218-mp-408e7729765d`) a montré le zombie
  passé au client 2 au moment où il frappait, alors que les trois corps restaient simulés par le client 1 ; seul le
  propriétaire d'un **corps** envoie un rapport d'état, rien n'arrivait. D'où une commande propre au propriétaire du
  **zombie** : `zombieThumps { n, w }` (client → serveur), envoyée par l'exécutant (`Executor.pass`,
  `Senses.thumpReport`) même s'il ne simule aucun corps.
- **Collecte** (client MP) : zombies de la cellule à 30 cases (x et y, 2 étages) d'un corps de PNJ présent sur ce
  client, que **ce client simule** (`ZombieGuard.simulatedHere` : la copie distante d'un autre client reçoit la cible
  du paquet `Thump`, sans paquet de fin) et dont `getThumpTarget()` est une `IsoWindow`. Entrée `{ o (onlineId), x, y,
  z (case de la fenêtre), k = "N" | "W" (bord nord ou ouest de cette case) }`, triées par `o`, 4 au plus ; envoi quand
  la liste change, puis toutes les 2 s tant qu'elle n'est pas vide (`THUMP_REFRESH_MS`) ; liste vidée : `{ n }` seul.
  Ligne `INFO thumped windows reported: …` à chaque changement.
- **Contrôles du serveur** (`Senses.onThumps`) : forme (`Senses.validateThumps` : `o` entier ≥ 0, cases entières,
  niveau −32..31, `k` N ou W, 4 au plus) et numéro `n` croissant, rapports plus rapprochés que 150 ms ignorés
  (`stats.thumpsRefused`) ; par entrée : zombie vivant connu du serveur **et simulé par l'expéditeur**
  (`getOwnerPlayer`), fenêtre réelle à cette case et sur ce bord (`Senses.windowAt` : `getWindowTo` des deux cases du
  bord), copie du serveur du zombie au même niveau et à 4 cases au plus du milieu du bord (le propriétaire lâche sa
  cible au-delà de 3 cases, J/characters/IsoZombie.java:738-746, + 1 case de retard) ; sinon entrée retirée
  (`stats.thumpsDropped`, gardées : `stats.thumps`). Mémoire : dernier rapport par compte.
- **Lecture** : `Senses.thumpOf(onlineId)` → `{ x, y, z, k, ms, by }` du rapport le plus récent de moins de 5 s
  (`THUMP_MS`) ; un rapport suivant sans cette fenêtre l'efface. Le foyer est contrôlé à l'usage (`Defense`).

## Alternatives écartées

- **Calcul sur le serveur** : pas de lumière sur un serveur dédié, corps parfois en retard ; ajouterait un calcul par PNJ sur la machine la plus chargée.
- **Réutiliser `spotted` du moteur** : réservé aux zombies non `useless`, aléatoire (`Rand`), pose une cible et déclenche l'attaque ; contraire à la neutralisation des corps et au déterminisme.
- **Commande réseau propre** (`senseReport`) : dupliquerait propriétaire, bail, ordre et cadence déjà contrôlés pour `bodyReport`.
- **Écouter les pas vanilla** : aléatoires (1 fois sur 2 à 12) et jamais envoyés ; remplacés par le bruit propre déterministe.
- **Hasard reproductible** (graine identité × temps) : inutile pour ce modèle ; un seuil d'attention donne déjà un délai qui dépend de la distance et de la posture.

## Idées reprises

- I2.1 (lumière de la case de l'intrus, allure, distance) : retenue telle quelle, chiffres propres (points de départ vanilla de `spottedNew`, pas ceux de la source).
- I2.2 (vigilance selon l'activité, sentinelle) : quatre niveaux ; le niveau garde dépend de LK05-T03.

## Tests

- Banc lupa `tests/test_lk_senses.py` (22 tests) : chiffres du modèle ; déterminisme (même scénario rejoué dans deux bancs : résumés identiques ; modèle pur appelé deux fois) ; vu à découvert en moins de 5 passages ; mur et porte fermée : jamais vu ; porte ouverte et fenêtre : vu ; nuit sans lumière : pas vu à 6 cases, vu à 3, vu avec une lampe ou sous un lampadaire ; bruit de course entendu à travers un mur (sans être vu), oublié 3 s après, bruit du monde de la cible et liste `n` ; accroupi vu plus tard, jamais au-delà de sa portée ; vigilance (repos, garde, endormi) ; dos et contact ; fantôme et mort ignorés ; zombies perçus, corps de PNJ exclus, résumé borné ; coût : 20 PNJ et 300 zombies, 4 PNJ et au plus 32 `lineClear` par passage, tous les PNJ vus en 5 passages ; transport : solo (autorité directe), MP (A propriétaire calcule, B rien, serveur garde la dernière valeur), résumé mal formé = rapport refusé, entrées implausibles retirées, rapport avancé quand le PNJ commence à voir ; suite `lk.senses` déroulée sur les doublures ; sources compatibles Kahlua, sans tirage ni effet sur le monde.
- VM Kahlua (`tests/test_kahlua.py`, `KR-SENSES`) : mêmes valeurs du modèle que sous lupa.
- En jeu : suite `lk.senses` (solo, partie `rstest…`, joueur immobile) : `RST.run({ suite = "lk.senses", tags = "world" })` ; lignes `[LKS] measure …`. Non encore lancée.

## Points ouverts

- ⚠ Lumière `getLightLevel` d'une case que le joueur local ne voit pas, et en MP pour la case d'un autre joueur : à mesurer (ligne `light` de la suite).
- ⚠ Drapeaux d'allure et d'accroupissement d'un joueur distant sur le client propriétaire : à mesurer à deux clients (le déplacement mesuré sert de repli pour l'allure, pas pour l'accroupissement).
- Vigilance posée par l'autorité transmise en MP par la consigne (`vg`, LK05-T03) : à valider en jeu à la séance MP.
- ⚠ Seuils (portée, gain, bruits propres) à recalibrer par des essais : un PNJ ne doit ni voir à travers la nuit noire ni rater un joueur debout en plein jour.
- Autres PNJ comme cibles (groupes rivaux) : hors périmètre de LK05-T01.
