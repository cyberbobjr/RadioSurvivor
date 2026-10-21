# Vérification du carnet 0.2 — 42.21.0

Date locale : 3 octobre 2026 (section datée du 2026-10-08 ajoutée ensuite). **Aucun parcours avec deux clients interactifs n'a été réalisé.**
Les API Java simulées ne valident ni le rendu ISUI, ni la synchronisation réelle des inventaires,
ni les comportements Bandits sous changement de propriétaire réseau.

Les sections « Contrôles réalisés » et « Démarrage du véritable serveur dédié » sont l'historique du
2026-10-03, quand le carnet utilisait Bandits! ; ce qui a changé depuis est décrit dans la section
datée du 2026-10-08 ci-dessous.

## 2026-10-08 — changements depuis cette validation

- **Bandits! retiré** (`E17-T01`, `E17-T02`) : adaptateur `RS_Bandits.lua` supprimé, `loadModAfter`
  ne cite plus que `\batman_CharacterReputation`, `mod.info` déclare `incompatible=\Bandits2,\ProjectALifeNPCs`.
  Le carnet passe par `RS_NPCProvider.lua` ; aucun fournisseur n'est inscrit, donc aucun PNJ. Le message
  de démarrage attendu est désormais
  `[RS_Carnet] authoritative state ready, NPC provider=none, available=false`.
- **Correctifs `E00-T01` à `E00-T04`** (testés hors jeu, commit `120033f`) : identité de personnage
  écrite par le serveur dans sa ModData du joueur, retrait à `OnCharacterDeath` au lieu de
  `OnPlayerDeath`, missions répétables (expiration des offres, délai entre deux offres, purge des
  missions closes), fiches créées à la sélection et purgées, envoi des instantanés sur changement
  et sauvegarde conditionnelle. Détails : [implémentation](../conception/carnet-implementation-04221.md).
- **Tests hors jeu au 2026-10-08** : `python RadioSurvivor/tests/run_all.py` passe (10 contrôles,
  dont `test_carnet.py` 20 tests rejoués avec un faux fournisseur conforme à l'interface,
  `test_protocol.py` 3 scénarios, luacheck à 21 avertissements de référence).
- **Serveur dédié de test** (`tests/run_dedicated_smoke.ps1`) : le script ne copie plus Bandits ;
  il charge `batman_CharacterReputation`, `batman_RadioSurvivor` et le mod de tests
  `batman_RadioSurvivorTests` (voir [tests en jeu](tests-en-jeu.md)). Essai du 2026-10-08 :
  `NPC provider=none, available=false`, 41 tests en jeu dont 38 réussis et 2 échecs connus
  (`E00-T08`, `E00-T10`).
- **En jeu solo le 2026-10-08** (retour de l'utilisateur) : le carnet s'ouvre depuis la barre latérale
  (`E00-T11`) avec « Aucun moteur de PNJ actif » et des onglets vides, Ctrl+G sans PNJ ne provoque
  pas d'erreur, la radio de Walt répond (pont non lancé : réponse de secours).
- **Correction d'un contrôle ci-dessous** : la « correspondance du codec UTF-8 » vérifiée sous `lupa`
  ne vaut pas dans la VM Kahlua du jeu ; `RS_Codec.hex` n'est pas réversible au-delà de U+00FF et le
  pont attend de l'UTF-8 (`E00-T08`, `E00-T09`, à corriger). Le retrait du lot utilise
  `InventoryItemFactory`, non exposé en 42.21 (`E00-T10`, à corriger).
- **Validations à rejouer** : tout le parcours avec PNJ ci-dessous attend le fournisseur Living Knox
  (`E17-T03`) puis les tâches de validation `E03` (solo `E03-T01`, rendu `E03-T02`, deux joueurs
  `E03-T03`, reconnexion/redémarrage/mort réels `E03-T04`, charge `E03-T05`, LLM réel `E03-T06`).

## 2026-10-14 — protocole visuel du carnet scripté (E03-T02)

**Lancement, une seule commande** (console Lua, mode debug, solo ou client MP, n'importe quelle partie) :
`RST.run({ suite = "rs.notebook.visual" })` — environ 30 s ; ne pas toucher à la souris ni au clavier pendant ce temps
(les dialogues de confirmation se centrent sur la souris). La suite fait aussi partie de `RST.campaign("solo-rs")`.
Rapport : `Zomboid/Lua/batman_RadioSurvivor/tests/<horodatage>-*.txt` ; captures : `Zomboid/Screenshots/rs_notebook_*.png`
(les copier dans `docs/annexes/tests/validation/E03-T02/` pour la preuve).

La suite (`dev/.../RST/suites/RS_NotebookVisual.lua`) remplit le **vrai** carnet avec un instantané client fixe (12
contacts dont un avec relation, trêve et faits, historiques longs ; une livraison engagée, une offre de soutien ; une
équipe de faction ; deux fréquences radio dont une de 12 lignes). Aucune donnée serveur n'est modifiée : les instantanés
et l'historique radio envoyés par le serveur sont ignorés pendant l'essai, puis redemandés. La fenêtre du joueur est
masquée puis rendue telle quelle.

Vérifié par script à chaque vue : contrôles visibles dans la fenêtre (géométrie Java) et fenêtre dans l'écran ; texte
de chaque bouton et de chaque signet dans son bouton ; en-tête de liste, pied « Interlocuteur », deuxième ligne de chaque
rangée et titre « Réputation » entiers ; statut au-dessus de la ligne « Dire » en deux lignes au plus ; aucune ligne de la
page plus large que la page ; page à l'encre sombre ; aucune clé `IGUI_` brute ; contrôles au-dessus de la bande de
redimensionnement et jamais superposés ; dialogue dans l'écran, lignes et boutons dedans.

| Test | Contenu | Captures |
| --- | --- | --- |
| 1. Tables de traduction | Tables **EN et FR** du mod lues dans les fichiers (`getModFileReader`) et données à `getText` pendant la mise en page d'un carnet hors écran à sa **taille minimale**, police **actuelle** et **plus grande** (Small mesurée en Medium, Medium en Large) : chaque page, fenêtre de livraison, les quatre confirmations ; puis chacune des ~430 chaînes du carnet contre la largeur de sa place (bouton, en-tête, rangée, statut sur deux lignes, dialogue, mot le plus long d'une page). | aucune |
| 2. Vues | Mode fenêtré (sans bordure désactivé) **1280×720** puis **1920×1080** (ou le plus grand mode inférieur) : Radio, Contacts (relation), Missions (livraison engagée), offre, Réputation, Équipe, fenêtre de livraison, confirmation d'abandon, confirmation de remise d'un devis, taille **minimale** et **grande** (contrôles qui suivent : texte jusqu'à la marge, signets au bord, dernière rangée sur la marge du bas). Mode d'affichage d'origine restauré à la fin. | 22 : `rs_notebook_<vue>_<l>x<h>_fs<n>.png` |
| 3. Comportements | Bouton latéral (dans l'écran, texte entier, ouvre le carnet) ; défilement de la page et de la liste puis retour ; « le détail ne saute pas » : contact 11 sélectionné, liste et page défilées, instantané forcé par le vrai `Client.receive` → sélection, rangée et deux positions de défilement inchangées ; repli (clavier rendu, onglet Radio non lu) et dépli ; fermeture (clavier rendu), réouverture et fermeture par le bouton latéral ; raccourci : fonction de la touche `RadioSurvivorSelect` (Ctrl+G) appelée, commande `select`/`deselect` capturée sans envoi. | `scrolled`, `collapsed` |

**Limites.** La taille de police ne change pas en partie (option « Taille de police » : redémarrage requis) : la grande
police est **simulée par la mesure** (test 1), sans capture ; pour la voir réellement, relancer le jeu avec une autre
taille et rejouer la commande (le nom des captures porte `fs<n>`). La langue ne change pas non plus en partie : EN et FR
sont mesurés à partir des fichiers, les captures sont dans la langue du jeu (rejouer après changement de langue pour
l'autre). Le dialogue suit la souris : sa position varie d'un essai à l'autre.

**Corrigé pendant la tâche** (banc `tests/test_notebook_visual.py`, polices réelles du jeu) : taille minimale du carnet
qui grandit avec la police (à 660×480 avec une police plus grande, « Parler » et « Effacer la cible » sortaient de la
fenêtre en Contacts) ; colonne de gauche assez large pour son en-tête, le pied « Interlocuteur » et la deuxième ligne de
chaque rangée (FR : « Interlocuteur → aucun interlocuteur » coupé à 660 px ; « personne » désormais) ; état d'une mission
en un mot dans la liste (`StateShort_*` : « Offre », « Échouée », « Annulée », « Expirée », « Fermée » ; la phrase entière
reste sur la page), ces phrases étaient coupées dans la rangée ; confirmations (`ConfirmAccept`, `ConfirmAbandon`,
`ConfirmDelivery`, `ConfirmSupply`, EN et FR) coupées en lignes par `\n` : le dialogue vanilla ne coupe jamais une ligne
et, en une seule ligne, `ConfirmSupply` FR mesurait 1 101 px en police 1x et environ 1 700 px une taille au-dessus,
plus large qu'un écran de 1280 px.

**À regarder sur les captures** (non scriptable) : lisibilité d'ensemble de l'encre sur le papier et des signets
colorés ; anneaux et reliure dessinés sans trou au redimensionnement ; points orange « non lu » (fréquence 96.6, signet
Radio) ; barre de défilement fine visible sur la page longue (`scrolled`) ; carnet replié réduit à sa barre de titre
(`collapsed`) ; fenêtre de livraison : lisible, posée sur le carnet, nom d'objet très long terminé par « ... » ; dialogues : texte
blanc lisible, boutons Oui/Non.

**Défauts relevés, corrigés par `E03-T07` (2026-10-14)** :
- La fenêtre de livraison s'ouvrait au coin haut gauche de l'écran (`Delivery:new(0, 0, …)`), sous la barre latérale
  vanilla. Elle s'ouvre désormais centrée sur le carnet (`Notebook.newDelivery(mission, carnet)`), ramenée entière dans
  l'écran quelle que soit la résolution ou la position du carnet.
- Les noms d'objets de la fenêtre de livraison n'étaient pas coupés à la largeur de la liste (`drawText` sans `fit`).
  Ils sont coupés par mesure (`MeasureStringX`) avec « ... », la place de la barre de défilement vanilla réservée.
- Suite étendue : un objet au nom très long (`V.LONG_ITEM`, pansement renommé par `setName`) est ajouté à l'inventaire
  pendant la passe puis retiré ; chaque rangée dessinée (cochée et non cochée) reste à gauche de la barre de
  défilement et un nom trop long finit par « ... » ; la fenêtre de livraison a son centre sur le carnet, ne recouvre
  pas la barre latérale, et reste dans l'écran pour un carnet poussé au-delà de chacun des quatre coins (test 2, aux
  deux résolutions). Banc `tests/test_notebook_visual.py` : 17 tests, dont 6 en échec sur l'ancien code.
- **Non fait** : passage en jeu de `RST.run({ suite = "rs.notebook.visual" })` après la correction (captures
  `rs_notebook_delivery_*` à regarder).

## 2026-10-09 — reconnexion, redémarrage et mort (E03-T04, volet code)

- **Suites serveur `rs.identity*`** (`dev/.../RST/suites/RS_Identity.lua`) : invariants de l'identité sur l'état
  réel (`rs.identity`, aussi dans `"rs"`), puis quatre étapes à la demande (tag `manual`) enchaînées entre les
  actions manuelles : `rs.identity.before` (relevé dans un fichier de test), `after-reconnect`, `after-restart`
  (temps d'arrêt exclu du chrono), `after-death`. Aucune écriture dans l'état du carnet.
- **Protocole à deux comptes** : [tests en jeu, § 11](tests-en-jeu.md). Le serveur de test se relance sur le même
  monde par `run_dedicated_smoke.ps1 -Manual -CacheDir <cache>`.
- **Hors jeu** : `test_carnet.py` exécute les suites sur le serveur simulé (reconnexion, redémarrage de 10 min,
  mort et nouveau personnage) et vérifie qu'elles détectent une identité serveur perdue, un chrono qui compte
  l'arrêt, un arrêt trop court et une mort sans retrait.
- **Serveur dédié de test** (`-Filters "rst,rs"`, 2026-10-09, 42.21.0) : `OK - 48 test(s): 45 pass, 0 fail,
  0 error, 3 skip` ; `rs.identity` passe sans joueur (2 tests `SKIP no online player`), les étapes `manual` ne
  sont pas sélectionnées ; aucune erreur Lua de nos mods.
- **Non fait** : le passage à deux clients (séance finale). Sans fournisseur de PNJ (`E17-T03`), il ne prouvera
  que l'identité ; notes, engagements et chrono seront à rejouer avec un PNJ.

## Contrôles réalisés (2026-10-03)

- Journal utilisateur : `console.txt:59`, `version=42.21.0 4a0e9546ec demo=false`.
- Sources Java décompilées 42.21.0, Lua installé, variante Bandits 42.20 et API locale
  CharacterReputation inspectés en lecture seule. Aucune source Steam/jeu modifiée.
- Syntaxe de tous les Lua du mod, syntaxe Python, JSON FR/EN et correspondance du codec UTF-8.
- `python RadioSurvivor/tests/test_protocol.py` : les 3 scénarios historiques Walt (solo,
  serveur + deux clients, bridge absent), vrais Lua et sous-processus Python `--offline`.
- `python RadioSurvivor/tests/test_carnet.py` : 13 tests. Lua du carnet exécuté dans des VM séparées,
  commandes authentifiées relayées par le banc de simulation, bridge offline réel. Le chemin
  `ISChat:onCommandEntered` utilisé est celui du fichier vanilla installé, pas une réécriture.

Couverture du carnet : offre et engagement individuel ; auditeur proche ; invitations non engageantes ;
remises partielles et équivalents ; quotes concurrentes, retrait unique concurrent et rejouements ;
notes privées et déduplication ; canaux exclus et restrictions chat ; surdité, étages, bâtiment et
distance selon la politique du mod ; départ de portée ; bridge absent, invalide et périmé ;
persistance, reconnexion, nouvelle session/personnage/monde ; pause/serveur vide et délai après
redémarrage ; acceptation après une première remise ; décès réel simulé sans malus, déchargement
sans faux décès ; restauration explicite de PNJ ; inventaire déplacé, capacité, erreur de paquet
avec transaction bloquée et slots de stockage corrompus. Python : mémoire par monde/PNJ, rejet
sans faux fait, proposition persistée réutilisée, mémoire bornée, sérialisation jusqu'à l'acquittement
et parallélisme entre PNJ différents ; un échec disque Python ne produit pas de faux acquittement.
Un même bridge est aussi testé avec une demande Walt historique et une demande PNJ concurrentes.

## Démarrage du véritable serveur dédié (2026-10-03)

À cette date, `tests/run_dedicated_smoke.ps1` créait un **nouveau cache temporaire**, copiait Bandits en lecture depuis
Steam et les projets locaux, puis lançait le Java fourni par le jeu en `-nosteam`, IP `127.0.0.1`,
ports 17381/17382, sans UPnP, avec `PauseEmpty=true`. Aucune sauvegarde utilisateur n'est chargée.

Premier essai : erreur Lua à `RS_Bandits.objects`, la cellule vaut `nil` lors de
`OnInitGlobalModData`. Garde ajoutée, puis démarrage complet recommencé.

Après correction : journal confirme `version=42.21.0`, chargement `Bandits2`,
`batman_CharacterReputation`, `batman_RadioSurvivor`, message
`[RS_Carnet] authoritative state ready, Bandits2=true`, puis `*** SERVER STARTED ****`.
Les générations des slots privés progressent pendant que le serveur reste vide et en pause :
l'événement de fonctionnement serveur est donc exercé réellement. Ce contrôle n'a créé aucun
PNJ corporel et n'a remis aucun objet en jeu.

Les premiers lancements, utilisant l'ordre natif du batch fourni, ont signalé à l'arrêt une
`UnsatisfiedLinkError` sur `ZombiePopulationManager.n_updateRealZombies`. Cette installation possède
deux copies différentes de `PZPopMan64.dll` : racine plus récente que `natives/win64`. Le script de
test privilégie désormais les DLL racine, sans modifier l'installation. D'autres messages vanilla
et Bandits (assets, scripts, dossiers d'animation absents) existent : ce n'est pas une certification
de démarrage entièrement sans erreurs de tous les mods.

Troisième essai avec cet ordre corrigé : démarrage, sauvegardes privées jusqu'à génération 78
sans joueurs, puis `quit` avec `Saving finish`, sans cette erreur native et sans pile Lua RadioSurvivor.

Journaux de test conservés dans les caches temporaires `rs-dedicated-*`, indépendants des journaux
utilisateur. Voir également `validation/dedicated-smoke-extrait.txt` pour les preuves ciblées.

## Parcours interactif restant : serveur dédié et deux clients

Consignes mises à jour le 2026-10-08 : ce parcours exige un fournisseur de PNJ actif et ne peut être
joué qu'après `E17-T03` (Living Knox) ; il sera repris par les tâches `E03`.

1. Créer une partie de test neuve 42.21.0 avec la même version de RadioSurvivor des deux côtés, sans
   autre moteur de PNJ. Pont unique `--offline`, bon `--exchange`, journaux séparés. Vérifier les
   variantes réellement chargées, le message `NPC provider=<nom>, available=true` et les premières
   erreurs `f:0`. Ne pas employer une sauvegarde importante.
2. Faire apparaître un PNJ non hostile du fournisseur actif. Deux joueurs proches : Ctrl+G pour A,
   nom confirmé, `/say` ; une seule réponse dans le chat normal de A et B, aucune seconde demande
   depuis B. Observer déplacement/combat natifs pendant le dialogue ; sortir de portée, changer
   d'étage, tester bâtiment/surdité et attendre une réponse pendant que le PNJ se déplace.
3. Carnet : vérifier rendu à 1280×720 et 1920×1080, petite/grande police, FR/EN, défilement,
   redimensionnement, réduction et fermeture. A écrit une note : B ne la voit pas. Conversations
   hors portée absentes. Tester général/faction/privé et joueur muté / `say` désactivé.
4. A accepte ; B voit l'offre, ne s'engage qu'après invitation + son propre bouton. Livrer une pièce
   avant l'acceptation de B et vérifier que les inscriptions restent ouvertes et le délai inchangé.
   Mélanger Bandage/RippedSheets dans des sacs ; voir le récapitulatif, annuler sans retrait,
   puis déplacer un objet ou quitter la portée avant confirmation : refus sans débit supplémentaire.
5. A et B confirment simultanément leurs remises : progression plafonnée, deuxième quote périmée
   refusée, inventaires cohérents après reconnexion. Après réussite, deux retraits simultanés :
   exactement 20 cartouches communes, un bénéficiaire affiché. Vérifier capacité insuffisante.
6. Arrêter proprement puis reprendre serveur/bridge, reconnecter A et B : monde/PNJ/notes inchangés,
   nouvelle session, temps d'arrêt exclu. Laisser serveur vide/pausé : chrono continue. Décharger
   puis recharger la zone et transférer le propriétaire réseau : noter l'incarnation réelle,
   l'identité retrouvée ou la limite de recréation décrite dans l'implémentation (événement
   `reincarnated`). Reconnecter A sans sa ModData client : même personnage, notes et engagements.
7. Dans une nouvelle mission de test, tuer le demandeur : annulation sans malus collectif ; sanction
   personnelle signalée comme non disponible. Tester expiration et abandon. Réputation toujours
   « non appliquée », aucun faux score. Couper/reprendre le bridge : pas d'effet accepté tardivement.
   Laisser une offre sans l'accepter : « Offre expirée » après 1 h de fonctionnement serveur, nouvelle
   offre possible 30 min réelles après la clôture. Faire mourir A : son identité est retirée, son
   nouveau personnage repart sans les missions de l'ancien, B poursuit la mission commune.
8. Walt : talkie valide sur 145,0 MHz, menu historique, réponse entendue par B. Continuer un dialogue
   PNJ en parallèle ; vérifier qu'une transmission Walt ne devient pas une phrase PNJ.

Une validation du parcours interactif doit conserver versions, logs serveur/clients, preuves
d'inventaires et résultats des cas concurrents. Aucun résultat de cette liste n'est annoncé acquis.
