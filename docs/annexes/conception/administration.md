# Administration

- Tâches : LK13-T01 (création), LK13-T13 (fiche d'un PNJ), LK13-T14 (panneau de debug des PNJ), LK13-T15 (tableaux et
  actions), LK13-T16 (coordonnées et téléportation hors écran)
- Build : 42.21.0 — Date : 2026-10-12 — Statut : brouillon

## Problème

Donner aux administrateurs d'un serveur (et au joueur solo) une vue et quelques leviers sur les groupes Living Knox :
état des groupes, détail et journal d'un groupe, carte des groupes, relève forcée d'un groupe disparu (LK09-T04),
foyer déplacé vers une case choisie. Aucune donnée privée (foyer exact, journal, membres) ne doit atteindre un joueur
qui n'en a pas le droit, et toute commande d'un non-administrateur est refusée côté serveur.

Code : `server/LivingKnox/LK_Admin.lua` (autorité), `client/LivingKnox/LK_AdminView.lua` (fenêtre). Traductions :
`IGUI_LK_Admin_*` de `IG_UI.json` (EN, FR).

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| `checkPermissions(joueur, capacité)` ne vérifie que sur un serveur MP (rôle de la connexion, `AntiCheatCapability.validate`) et rend vrai si la connexion du joueur est introuvable ; ailleurs, y compris sur un client MP, il rend vrai : le serveur relit aussi `getRole():hasCapability` (rôle copié de la connexion) | `J/Lua/LuaManager.java:2913-2919`, `J/network/anticheats/AntiCheatCapability.java:12-14` ; base `multiplayer.md` | confirmé statiquement |
| `Role.hasCapability` est vrai pour toute capacité en solo avec `-debug` (`isUsingDebugMode`) | `J/characters/Role.java:187-193` | confirmé statiquement |
| Rôles par défaut : `admin` a toutes les capacités ; `moderator` toutes sauf huit (dont `ChangeAndReloadServerOptions`, `RolesWrite`) ; `gm` n'a pas `PopmanManage` | `J/characters/Roles.java:373-437` (42.21.0) | confirmé statiquement |
| `PopmanManage` garde la population de zombies côté client vanilla | `J/popman/ZombiePopulationManager.java:778, 793, 808` | confirmé statiquement |
| Le panneau d'admin vanilla n'existe qu'en MP ; ses boutons sont triés par `title` après leur création, un bouton ajouté avant l'original entre dans la grille | `M/client/ISUI/AdminPanel/ISAdminPanelUI.lua:23-24, 157-182` ; base `ui-windows.md` | confirmé statiquement |
| En solo, `sendServerCommand` ne fait rien : la fenêtre appelle l'autorité directement, la réponse arrive pendant l'appel | base `quest-building-blocks.md`, `multiplayer.md` | confirmé statiquement |
| `getText` formate un nombre entier sans décimale (`fixupArgs`) | `J/core/Translator.java:421-433` | confirmé statiquement |

## Choix

- **Droit exigé : `Capability.PopmanManage`** (rôles `moderator` et `admin` par défaut ; un rôle personnalisé peut le
  recevoir). Choix du 2026-10-12, à confirmer par l'utilisateur : capacité vanilla la plus proche (gestion de la
  population du monde) qui exclut le rôle `gm`. Vérifiée à **chaque** requête sur l'autorité (`Admin.isAllowed`) ;
  côté client, `getRole():hasCapability` ne sert qu'à activer le bouton. Solo : le joueur local administre sa partie.
  Un client MP ne décide jamais (le module s'arrête à sa garde avant toute donnée).
- **Requêtes** : une seule commande `adminRequest { op, n, gid, x, y, z }`, réponse `adminReply` au seul demandeur.
  Refus : `{ n, op, ok = false, err = "denied" }` sans aucun autre champ ; ligne WARN `admin: request <op> refused for
  <compte> (<raison>)`, au plus une par joueur et par opération et par minute réelle, avec le compte des refus tus.
- **État des groupes** (`list`) : vivants / total, incarnés, chef, objectif, tâche hors écran, besoins, moral, foyer
  exact, marque « disparu » (cause, heure, relève due, relève posée), expédition en cours. **Détail** (`group`) :
  membres (rôle, vivant, PNJ, poste, blessure, incarné), histoire publique, groupe relevé, journal complet (32
  entrées) et, depuis LK10-T02, journal de récit (`journal` : vues publiques de `LK_Journal`, composées par la fenêtre
  dans la langue du client, section « Récit du groupe », [journal.md](journal.md)). Copies simples, jamais le registre.
- **Relève forcée** (`relief`) : seulement un groupe disparu, ou sans plus aucun vivant (le pas de relève le marque
  d'abord, cause `wiped`) ; l'heure due est ramenée à l'heure courante, puis `Population.reliefStep` (même chemin que
  le pas horaire : type, plan, site, insertion). Pas de relève possible (aucun site) : la marque reste, nouvel essai
  24 h plus tard comme le pas horaire. Un groupe vivant n'est jamais forcé à disparaître (hors périmètre).
- **Foyer déplacé** (`home`) : entiers, `x, y >= 0`, `z` dans -32..31 ; case de la carte (`isValidSquare` et cellule
  de la métagrille) ; hors refuge de joueur ; à `HOME_GAP` = 25 cases au moins du foyer d'un autre groupe (deux
  aménagements de rayon 10 ne se chevauchent pas) ; groupe non disparu. Une sauvegarde ; aménagement, stock et relevé
  des postes suivent le nouveau foyer d'eux-mêmes (marques périmées, LK_Homes, LK_Stock, LK_Routines) ; l'ancien
  aménagement reste en place. Case saisie dans la fenêtre, préremplie avec la position du joueur.
- **Mesure de charge** (`load`, LK13-T02) : départ, rapport et arrêt d'une mesure `LivingKnox.Load` sur l'autorité,
  même contrôle d'accès ; voir [charge.md](charge.md).
- **Traçabilité** : entrée de journal `admin` dans le groupe touché (`relief forced by <compte>`, `home a -> b by
  <compte>`) et ligne INFO.
- **Carte des groupes : liste de coordonnées.** Le foyer exact de chaque groupe s'affiche dans la liste (et la
  position du joueur dans les champs de saisie). Aucun symbole sur la carte du monde : un symbole posé par script est
  sauvegardé dans `map_symbols.bin` du client et reste après la fermeture (base `world-map.md`), il faudrait le
  reconnaître et le retirer à chaque ouverture ; une couche dessinée par-dessus `ISWorldMap` demande d'envelopper son
  rendu (coût et fragilité hors périmètre). Reste possible plus tard (nouvelle tâche).
- **Ouverture** : MP, bouton « Groupes Living Knox » du panneau d'admin ; solo, console Lua du mode debug
  `LivingKnox.AdminView.open()`.

## Fiche d'un PNJ (LK13-T13)

Code : opérations `npc` et `npcSet` de `LK_Admin.lua` (même commande `adminRequest` / `adminReply`, même contrôle à
chaque requête), `Health.setByAdmin` (`LK_Health.lua`), fenêtre `client/LivingKnox/LK_NpcSheet.lua`. Traductions :
`IGUI_LK_Sheet_*` (EN, FR).

- **Accès** (décision du 2026-10-12) : solo = mode debug (`isDebugEnabled`) pour ces deux opérations seulement (les
  autres opérations de l'outil restent ouvertes au joueur solo, choix de LK13-T01) ; MP = capacité `PopmanManage`,
  revérifiée par le serveur à chaque relecture et chaque réglage. Refus : `{ n, op, ok = false, err = "denied" }`,
  rien écrit. L'option du clic droit n'est ajoutée que si `NpcSheet.canUse()` (affichage seulement).
- **Ouverture** : clic droit sur une case à 1,5 case au plus d'un corps de PNJ connu ici (`LivingKnox.Anim.knownBodies`
  : corps relié en solo, roster de la garde sur un client MP), au niveau du joueur ; option « Détails (Living
  Knox) ». Aucune distance au joueur exigée (outil d'administration).
- **Lecture** (`npc`) : copie de valeurs simples : groupe, type, membre, rôle, profil, chef, poste, objectif, tâche hors
  écran, foyer, état du registre des corps, incarné, besoins (`Needs.get`) et seuils d'envie, santé (% de la santé de
  naissance, valeurs brutes, saignement en % par heure, nombre de blessures, dernière blessure), blessure abstraite du
  membre, état de décision (`Decisions.get` : comportement, règle, raison, échéance), routine (clé, phase), engagement
  de combat, geste affiché, vigilance, perception (`Senses.perceived` : vus, entendus, zombies, 8 joueurs au plus),
  arme (`Equipment.wantedOf`) et munitions (`Ammo` : chargées, capacité, cartouches libres, en chargeurs), position du
  corps (ou dernière position vue), minute de jeu.
- **Réglages** (`npcSet { npc, field, value }`, membre vivant, valeur numérique finie, sinon refus motivé) :
  faim, soif, fatigue, peur : entier 0..100 (jauges `member.vitals`, créées à l'heure courante si absentes) ;
  santé : 1..100 % de la santé de naissance, PNJ incarné seulement (jamais une mort : une mort ne passe que par
  `Health.kill`) ; saignement : 0..60 % par heure (`BLEEDING.MAX`), 0 l'arrête ; blessure abstraite : 0..99
  (`WOUND_DEATH - 1`, relue à la matérialisation suivante ; un membre incarné la recalcule à son retrait). Valeur
  hors bornes ramenée à la borne (réponse `value` = valeur retenue, `old` = ancienne).
- **Traçabilité** : entrée `admin` du journal du groupe `<champ> m-<k> (lk-<n>) <ancienne> -> <nouvelle> set by admin
  <compte>`, écrite avec la valeur (une écriture du registre des groupes ; santé et saignement : registre des corps
  puis journal) ; ligne INFO.
- **Effet** : aucune décision forcée. `Decisions.needsOf` et `healthOf` lisent le registre à chaque évaluation : la
  valeur réglée est lue au passage de décision suivant du membre (au plus une seconde, quatre membres par passage).
  La révision de santé est envoyée aux clients proches comme pour un coup.
- **Rafraîchissement** : toutes les 2 s (`REFRESH_MS`) tant que la fenêtre est ouverte (`NpcSheet.poll`, appelé par
  l'`update` de la fenêtre), jamais si une relecture attend encore sa réponse ; fenêtre fermée : plus aucune requête.
- **Limites** : le journal du groupe garde 32 entrées : une série de réglages peut chasser des entrées anciennes ; la
  fiche ne montre pas le chemin calculé ni la liste complète des menaces (outil LK13-T14).

Tests : `tests/test_lk_npcsheet.py` (MP : refus sans donnée ni écriture d'un client sans la capacité, fiche complète
par le réseau, bornes, journal, faim lue par la décision suivante, relecture toutes les 2 s et rien fenêtre fermée ;
solo : refus sans mode debug, appel direct, option du clic droit ; suite RST sur les doublures) ; suite en jeu
`lk.npcsheet` ; protocole `docs/annexes/tests/tests-en-jeu.md` § 15, « Fiche d'un PNJ par clic droit ».

## Panneau de debug des PNJ (LK13-T14)

Code : journal d'activité `server/LivingKnox/LK_Activity.lua` (autorité), opération `activity` de `LK_Admin.lua`
(même commande `adminRequest` / `adminReply`), panneau `client/LivingKnox/LK_DebugView.lua`. Traductions :
`IGUI_LK_Debug_*`, `IGUI_LK_Admin_DebugView` (EN, FR).

- **Accès** (décision du 2026-10-12) : ceux de la fiche d'un PNJ : `activity` est dans `Admin.DEBUG_OPS` (solo = mode
  debug ; MP = capacité `PopmanManage`, revérifiée à chaque requête). Refus : `{ n, op, ok = false, err = "denied" }`,
  aucune donnée.
- **Ouverture** : bouton « Living Knox - PNJ » de l'onglet MAIN du panneau debug vanilla (`ISDebugMenu`, ouvert en mode
  `-debug`) : enveloppe de `ISDebugMenu:setupButtons` qui ajoute le bouton (si `DebugView.canUse()`) AVANT d'appeler
  la fonction précédente, qui trie tous ses boutons puis ajoute « Fermer » (`ISDebugMenu.lua:16-58`) : aucun bouton
  vanilla ou d'un autre mod retiré, enveloppe gardée au rechargement ; bouton « Debug des PNJ » de la fenêtre des
  groupes (ouvre le panneau sur le groupe choisi) ; console : `LivingKnox.DebugView.open()` (ou `open("grp-<n>")`).
- **Contenu** : liste de tous les groupes (lignes de `list`) ; pour le groupe choisi, une ligne par membre :
  rôle, chef, présent / en expédition / hors écran (état du registre des corps), comportement, règle et raison de la
  cascade, cible (clé de la décision), échéance, routine (clé, phase), geste affiché, engagement de combat, position
  du corps (ou dernière position vue), besoins, santé en %, blessure abstraite ; puis le journal d'activité (plus
  récent d'abord, heure de jeu « jour J hh:mm ») et le journal sauvegardé du groupe (32 entrées, inchangé). Clic sur un
  membre puis « Ouvrir la fiche », ou double clic : fiche LK13-T13 (`NpcSheet.open`).
- **Journal d'activité** (décision du 2026-10-12) : tenu par l'autorité, EN MÉMOIRE seulement (aucune écriture de
  registre, perdu au redémarrage), anneau de 200 lignes par groupe, texte anglais de 160 caractères au plus, minute de
  jeu de chaque ligne. Sortes : `behaviour` (décision renouvelée dont le comportement, la règle ou la cible change :
  `chore -> meal (rule hunger: hunger 95, target hunger)`, « interrupted » si la cascade a interrompu l'état),
  `objective` (objectif ou postes changés, relève de quart comprise), `alert` (écouteurs `raised` / `calm` de
  `LK_Alert`), `meal` (`Stock.takeMeal`), `care` (`Care.finish`), `combat` (`Combat.engage` / `disengage`, coup reçu
  accepté par `Decisions.noteHit`). Points d'écoute : une ligne gardée par `LivingKnox.Activity ~= nil` dans chacun de
  ces endroits ; aucune décision changée (banc de charge : mêmes écritures et mêmes registres avec et sans journal).
- **Rafraîchissement** : une requête toutes les 2 s (`REFRESH_MS`) tant que le panneau est ouvert (`DebugView.poll`,
  appelé par l'`update` de la fenêtre), jamais si une réponse est attendue ; panneau fermé : aucune requête, réponse en
  route ignorée. Envoi incrémental : la requête porte `after` (dernier numéro de ligne reçu pour ce groupe), la
  réponse ne contient que les lignes suivantes (le panneau garde les 200 dernières) ; numéros repartis de zéro
  (autorité redémarrée) : liste vidée puis relue en entier.
- **Coût** : banc de charge (`tools/load_bench.py`, 60 min de jeu, 5 groupes) : 0,0003 ms par image serveur en lupa
  pour 366 appels (0,08 % du moteur), plus lourd appel 0,04 ms ; détail
  [charge-journal-activite-2026-10-12.md](../tests/validation/charge-journal-activite-2026-10-12.md).
- **Limites** : la cible affichée est la clé de la décision (un joueur `p<compte>`, une menace, ou le nom de la règle
  pour une envie) ; un membre hors écran n'a ni comportement ni geste (la simulation hors écran n'a pas d'état par
  PNJ) : poste, état du registre et dernière position seulement ; journal vide après un redémarrage du serveur ;
  aucune ligne pour les actions des routines elles-mêmes (corvée en cours, sommeil) au-delà du changement de
  comportement.

Tests : `tests/test_lk_debugview.py` (MP : refus sans donnée d'un client sans la capacité, liste et activité par le
réseau, faim réglée par `npcSet` notée comme changement de comportement, envoi incrémental, 200 lignes au plus des deux
côtés, aucune écriture de registre, relecture toutes les 2 s et rien panneau fermé, fiche d'un membre ; solo : refus
sans mode debug, bouton du panneau debug, écouteur de l'alerte ; suite RST sur les doublures) ; suite en jeu
`lk.debugview` ; protocole `docs/annexes/tests/tests-en-jeu.md` § 15, « Panneau de debug des PNJ ».

## Tableaux et actions d'administration (LK13-T15)

Constat de l'utilisateur en jeu (2026-10-12, écran 2560 px) : listes en lignes de texte qui débordent, journal serré,
très grand titre, fond transparent, santé en flottants bruts, champs de réglage vides. Demande : des tableaux, et
pouvoir changer le rôle, se téléporter vers un PNJ, changer son prénom et son nom.

Code : tableau `client/LivingKnox/LK_Table.lua` (nouveau), panneau `LK_DebugView.lua`, fiche `LK_NpcSheet.lua`,
opérations `npcRole`, `npcName`, `npcGoto` de `LK_Admin.lua`. Traductions `IGUI_LK_Debug_*`, `IGUI_LK_Sheet_*`.

- **Tableaux** (`LK_Table.lua`) : rangée d'en-têtes `ISButton` (clic : tri par la colonne, second clic : ordre inverse,
  comme `ISUsersList`) au-dessus d'un `ISScrollingListBox` dont `doDrawItem` dessine des cellules alignées, texte coupé
  avec « ... » à la largeur de la colonne (mesure `MeasureStringX`), infobulle de la ligne entière (champ `tooltip`
  de l'item, rendu par `ISToolTip`). Largeurs : minimum par colonne + reste au prorata d'un poids. Police
  `UIFont.Small` partout (plus de titre `<H2>`). Panneau : groupes (id, nom, type, chef, vivants / présents, objectif,
  alerte / défense), membres du groupe choisi (membre et nom, PNJ et état, rôle, poste, comportement + engagement,
  routine, geste, règle et raison, cible et échéance, besoins faim/soif/fatigue/peur, santé %, position), journal
  d'activité (heure, membre, sorte, texte ; plus récent d'abord) et journal sauvegardé (jour, sorte, entrée) côte à
  côte. Fond opaque.
- **Taille** (choix le plus simple, à confirmer) : fenêtre non redimensionnable, taille fixée à l'ouverture d'après
  l'écran (panneau au plus 1760 × 980, fiche au plus 1000 px de large). Raison : la barre de défilement vanilla d'un
  `ISScrollingListBox` reste à sa place de création et les lignes sont coupées à l'ancienne largeur (base
  `ui-windows.md`) ; un redimensionnement exigerait de recréer les tableaux. À 1920 px, le panneau fait 1760 px :
  chaque colonne a au moins sa largeur minimale.
- **Fiche** : sections étiquetées (identité, besoins, santé, comportement, perception, équipement) en deux colonnes,
  libellé et valeur alignés ; nombres arrondis au dixième, santé en %, saignement en % par heure. Champs de réglage
  préremplis avec la valeur actuelle, mis à jour à chaque relecture tant que l'administrateur n'a pas changé leur
  texte ni ne les a en main ; repris sur la valeur retenue après un réglage.
- **Changer le rôle** (`npcRole`) : liste fermée `Admin.rolesOf(type)` = rôles du type de groupe (`LK_GroupTypes`,
  `roles`) dans l'ordre de `Config.GROUP_ROLES`, proposée dans une liste déroulante ; tout autre rôle refusé
  (« role X is not a role of type T »), rôle identique refusé. Le profil (apparence, arme) ne change pas ; le moteur lit
  le rôle au passage de décision suivant.
- **Prénom et nom** (`npcName`) : deux champs ; `Admin.cleanNamePart` (défini avant la garde du client, utilisé aussi par
  la fiche avant l'envoi) : espaces de tête et de fin retirés, espaces répétés réduits, lettres ASCII, espace,
  apostrophe, point et tiret, commençant par une lettre, 1 à 24 caractères ; sinon « bad name ». Rangés dans le
  membre du registre des groupes (`firstName`, `lastName`, champs facultatifs, schéma inchangé, lus par
  `Admin.ownName` qui ignore une valeur mal formée). Jamais interprétés : affichés par `drawText`, infobulle avec « < »
  remplacé. Propagation : enveloppes posées une fois par `Admin.hookNames` sur `RS_LivingKnox.npc` (nom du carnet,
  des dernières pages, des missions, du chef de `LK.composition`) et `RS_LivingKnox.context` (nom du chef pour le LLM).
  Limites : le résumé d'histoire déjà composé (et donc le récit du chef) garde le nom d'origine ; les accents sont
  refusés ; aucun retour au nom d'origine par la fiche.
- **Se téléporter** (`npcGoto`) : destination choisie par l'autorité : première case voisine libre du corps
  (`isFree(false)`), sinon sa case ; PNJ hors écran : dernière position connue (registre des corps, `last`), notée
  comme telle ; aucune : refus « no known position » (LK13-T16 : foyer du groupe avant le refus, section suivante). Solo : le joueur est déplacé par l'autorité (`teleportTo`, qui
  sort du véhicule). Serveur : aucun appel Lua ne déplace un joueur (base `multiplayer.md`) ; la réponse porte la
  destination, le client envoie `/teleportto x,y,z` (comme `ISAdminMessage`), commande qui exige
  `TeleportToCoordinates` (revérifiée par le serveur ; la fiche ne demande rien sans elle et l'affiche). Bouton
  « Se téléporter » dans la fiche et dans le panneau (membre choisi).
- **Droits** : les trois opérations sont dans `Admin.DEBUG_OPS` (solo = mode debug ; serveur = `PopmanManage`,
  revérifiée à chaque requête) ; refus `{ n, op, ok = false, err = "denied" }` sans donnée ni écriture. Chaque action
  faite : entrée « admin » au journal du groupe (« role m-2 (lk-40) worker -> fighter set by admin <compte> »,
  « name ... », « teleport of admin <compte> to ... ») et ligne INFO de la console.

Tests : `tests/test_lk_npcsheet.py` (refus de chaque action pour un client sans la capacité, sans écriture ; rôle dans
la liste du type, hors liste et inchangé refusés ; bornes du nom côté client et autorité ; téléportation par
`/teleportto` près du corps, dernière position connue, refus sans position ; solo : déplacement par l'autorité, refus
sans mode debug ; nom repris par le fournisseur du carnet ; sections et préremplissage), `tests/test_lk_debugview.py`
(cellules, mise en page, coupure et tri du tableau, bouton de téléportation du panneau) ; suites `lk.npcsheet` (actions)
et `lk.debugview` (noms et cellules).

## Coordonnées des PNJ et téléportation hors écran (LK13-T16)

Constat de l'utilisateur en jeu (2026-10-13) : le panneau ne montrait pas où se trouve un PNJ hors écran, et
« Se téléporter » refusait un PNJ jamais vu (« no known position ») ; il a fallu lire les foyers à la console.

- **Position et source** (`Admin.positionOf(g, m)`, autorité) : corps chargé (`src = "body"`, au dixième de case), sinon
  dernière position vue du registre des corps (`"last"`), sinon foyer du groupe (`"home"`) ; rien pour un membre mort.
  Portée par chaque membre de la vue `activity` (panneau) et par la fiche (`npc`). Aucune donnée nouvelle : les foyers
  exacts étaient déjà dans la réponse `list` ; même canal, mêmes droits, rien envoyé panneau fermé. La position voulue
  d'un PNJ virtuel (`want`) n'est pas utilisée (trois sources demandées).
- **Panneau** : colonne « Position » de chaque membre « x,y,z (corps | vu en dernier | foyer du groupe) », colonne
  « Foyer » de la liste des groupes. Fiche : même texte (`Sheet.posText`).
- **Se téléporter** (`npcGoto`) : corps -> case libre voisine (inchangé) ; sinon dernière position connue ; sinon case
  libre voisine du foyer de son groupe (la case du foyer elle-même hors zone chargée, `getGridSquare` rendant nil) ;
  refus « no known position » seulement sans aucune des trois. Réponse `dest.src`, message « Téléporté près du foyer
  du groupe x,y,z », entrée de journal suffixée « (group home) ».
- **Aller au foyer du groupe** (`homeGoto`, nouveau, `DEBUG_OPS`) : bouton du panneau pour le groupe choisi, même
  destination (case libre voisine du foyer), même chemin (solo : `teleportTo` par l'autorité ; MP : `/teleportto`
  demandé par le client, `TeleportToCoordinates`), entrée « teleport of admin <compte> to the group home at x,y,z ».
  Envoyé par la fiche (`NpcSheet.teleportHome`), qui lit déjà les réponses de téléportation.
- Limite : un membre sans PNJ (jamais matérialisé, `npc` absent) a une position (foyer) mais « Se téléporter » reste
  grisé (l'opération vise un PNJ) : utiliser « Aller au foyer du groupe ».

Tests : `tests/test_lk_debugview.py` (`PositionTests` : chaque membre vivant a des coordonnées et une source, membre
jamais incarné mené au foyer par `/teleportto`, `homeGoto` et refus sans donnée ni écriture pour un client sans la
capacité, groupe ou foyer inconnu ; `PositionSoloTests` : déplacement par l'autorité, refus sans mode debug),
`tests/test_lk_npcsheet.py` (dernière position, puis foyer, puis refus sans foyer) ; suite `lk.debugview` (4e test :
groupe lointain jamais incarné, sources « home », `homeGoto` avec un joueur de substitution).

## Alternatives écartées

- Capacité `SandboxOptions` ou `ChangeAndReloadServerOptions` : la première a le même périmètre de rôles mais vise les
  options ; la seconde exclut les modérateurs.
- Commandes de chat (`/lk ...`) : analyse de texte de joueur et aucune interface ; le panneau d'admin vanilla est le
  geste naturel d'un administrateur.
- Vue publique de LK_API (`publicGroup`) envoyée à tous : elle cache justement foyer et journal, inutile à un admin,
  et l'outil ne doit rien envoyer aux autres.

## Idées reprises

- Aucune.

## Tests

- Banc lupa direct (`tests/test_lk_admin.py`, carte de test de `test_lk_relief.py`) : refus de chaque opération à un
  non-admin sans donnée ni écriture, journal borné, client MP et capacité absente refusés, routage de la commande au
  seul demandeur, liste et détail, relève forcée (une seule, groupe sans site, moteur désactivé, groupe vivant),
  foyer (contrôles, une sauvegarde, entrée `admin`) ; suite `lk.admin` par le vrai moteur RST.
- Banc `harness.py` : MP (client A admin : liste et détail par le réseau ; client B sans la capacité : quatre refus
  sans donnée, rien de modifié ; réponse périmée ignorée), solo (appel direct, aucune commande réseau).
- VM Kahlua (`tests/test_kahlua.py`) : compilation de tous les fichiers du mod.
- En jeu : suite `lk.admin` (tag `world`) ; fenêtre et refus d'un vrai client non admin : `docs/annexes/tests/tests-en-jeu.md` § 15.

## Statut

Brouillon. ⚠ À confirmer : capacité exigée (`PopmanManage`). ⚠ Non vu en jeu : rendu de la fenêtre, bouton du
panneau d'admin, refus d'un vrai client `user`.
