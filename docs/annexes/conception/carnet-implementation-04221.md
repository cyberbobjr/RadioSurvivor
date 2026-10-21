# Carnet RadioSurvivor 0.2 : implémentation et limites

Cible : **42.21.0**. Le parcours serveur est implémenté ; ses effets sont vérifiés en simulation
(`tests/test_carnet.py`), pas encore par deux joueurs dans le jeu. Lire [la validation](../tests/carnet-validation-04221.md)
et [le contrat v2](../../specifications-techniques/protocole-carnet-v2.md). Cette version ne publie aucun contenu, ne modifie aucun
mod Steam ni source vanilla, ne migre pas MilitaryDrop et n'implémente pas rumeurs, négociation,
campagnes, autonomie de factions ou radio des PNJ. Mise à jour du 2026-10-08 : correctifs `E00-T01`
à `E00-T04` et interface de fournisseur `E17-T02` décrits ci-dessous.

## Fournisseur de PNJ

Le carnet ne parle à aucun moteur de PNJ directement : il n'appelle que
`shared/RadioSurvivor/RS_NPCProvider.lua`, dont l'en-tête documente le contrat.

| Opération | Côté | Rôle pour le carnet |
| --- | --- | --- |
| `register(impl)` | tous | Inscrit le moteur. Un seul fournisseur : un second est refusé avec un message console, le premier reste actif. |
| `active()` | tous | Implémentation inscrite, ou fournisseur vide par défaut. |
| `available()` | tous | Faux : le carnet affiche « Aucun moteur de PNJ actif ». |
| `objects()` | tous | Corps chargés sur cette machine, par identifiant du fournisseur (jamais `nil`). |
| `id(objet)` | tous | Identifiant du fournisseur pour un corps ; il ne nomme que l'incarnation courante. |
| `npc(id)` | autorité | `signature` (identité stable de l'incarnation, obligatoire), `name`, `group`, `groupName` facultatif (nom lisible du groupe, `E17-T06`), `hostile` (`true`, `false` ou inconnu), `traits` facultatifs. |
| `bubble(objet, texte, portée)` | client | Bulle de parole ; à défaut, `addLineChatElement` vanilla. |
| `on` / `emit` | autorité | Événements émis par le fournisseur, écoutés par le serveur du carnet. |
| `near`, `hears`, `personality` | tous | Règles communes indépendantes du moteur : portée sur le même étage avec `CanSee`, parole intelligible (politique ci-dessous), personnalité de base dérivée de la signature. |
| `context(id, personnage, langue)` | autorité | Facultatif (`E17-T03`) : contexte public du PNJ pour le LLM (`context.group` des demandes, contrat v2 « Contexte du groupe »). |
| `hasSupplies()`, `supplies(id, personnage)` | autorité | Facultatif (`E17-T03`) : offres de ravitaillement réelles du moteur ; un fournisseur qui les définit remplace le catalogue statique de M01 pour ses PNJ. |
| `supplyOpen(ref, offre)`, `supplyDeliver(ref, offre, objets, reçu, personnage)` | autorité | Facultatif (`E17-T03`) : offre encore ouverte ; livraison idempotente par reçu (voir « Missions »). |
| `presence(id)` | autorité | Facultatif (`E08-T08`) : `{ away, x, y }` : PNJ parti en expédition, foyer de son groupe ; mémoire serveur des déclencheurs d'observations du monde, jamais envoyé ni mis dans une demande ; `nil` = inconnu. |

Une opération absente de l'implémentation se comporte comme vide ; tant que `available()` est faux,
`objects`, `id` et `npc` ne sont même pas appelés. Un fournisseur du même nom inscrit une seconde fois (fichier
rechargé) remplace le précédent ; un fournisseur d'un autre nom reste refusé.

Événements (`RS_Carnet_Server.lua`, abonnés en fin de fichier) :

- `death (id, objet)` → `Server.dead` : seule l'incarnation courante d'une fiche vivante est prise en
  compte, et seulement si `objet:isDead()`. La fiche passe morte, sa révision augmente (les réponses
  en attente sont refusées), ses missions actives sont closes `cancelled_dead` sans malus collectif.
  Le déchargement d'une zone n'est jamais une mort.
- `reincarnated (ancienneSignature, nouvelId, nouvelleSignature)` → `Server.reincarnated` : la fiche
  canonique (mémoires, accords, missions) passe sur la nouvelle incarnation ; une fiche temporaire
  créée entre-temps pour la nouvelle signature est supprimée. **Sans cet événement, rien n'est
  migré** : une nouvelle signature donne une nouvelle fiche, sans rapprochement par nom ou proximité.

**Fournisseur vide (Living Knox désactivé).** Aucun moteur ne s'inscrit : `available()` faux, aucun corps,
aucune fiche, Ctrl+G ne trouve personne (`IGUI_RS_Error_Range`). L'instantané envoyé au client porte
`npcProvider = false` ; le carnet affiche `IGUI_RS_NoNPCProvider` et des onglets vides. La radio de
Walt n'en dépend pas. Le journal serveur indique au démarrage
`[RS_Carnet] authoritative state ready, NPC provider=none, available=false`.

**Fournisseur Living Knox (`E17-T03`, `shared/RadioSurvivor/RS_LivingKnox.lua`).** Inscrit quand l'option sandbox
`LivingKnox.Enabled` est vraie, à `OnInitGlobalModData` (avant l'initialisation du carnet : les fichiers `shared` se
chargent avant `server`), `OnGameStart` et `OnServerStarted` (idempotent) ; journal
`NPC provider=livingknox, available=true`. Correspondance avec le moteur :

| Interface | Living Knox |
| --- | --- |
| `available()` | option `LivingKnox.Enabled` ; sur l'autorité, partie serveur chargée (`LivingKnox.Bodies`, `LivingKnox.API`) |
| `objects()` | autorité : `LivingKnox.Bodies.bound` présents dans la liste des zombies de la cellule ; client MP : copies locales `LivingKnox.ZombieGuard.cache` conformes à la liste du serveur (même `onlineId`, joueur réanimé), car les ModData d'un zombie ne parviennent pas aux clients |
| `id(objet)` | identifiant du PNJ `lk-<n>` (jamais réattribué, identique sur le serveur et les clients, conservé d'une incarnation à l'autre : aucun événement `reincarnated`) |
| `npc(id)` | `signature` = `lk:<id>` ; `group` = `grp-<n>` (`LivingKnox.Groups.findNpc`, vide sans groupe) ; `name` = nom du chef de l'histoire pour le chef actuel d'un groupe qui en a une, sinon nom tiré des listes de noms des histoires avec le numéro du PNJ pour graine (le registre ne tient aucun nom de membre en version 1) ; `hostile` = niveau de départ `hostile` du type de groupe (pillards), `nil` sans groupe (aucune offre) ; `traits` du membre (`smoker`, `drinker` → `alcoholic`, `tidy` → `compulsiveCleaner`) |
| événement `death` | `LivingKnox.Bodies.onDied` (mort du corps courant, cause relevée par `LK_Bodies`) |
| `context` | `API.getGroup` + `API.publicGroup` (attitude envers le personnage) et `LK_Stories.publicView` de l'histoire recomposée côté serveur (résumé dans la langue de la demande, nom du chef) ; ni secret, ni foyer, ni maille, ni journal |
| `supplies`, `supplyOpen`, `supplyDeliver` | `API.missionOffers(groupe, personnage)`, `API.deliver(groupe, offre, objets, reçu, personnage)` ; à la complétion, fait d'attitude `delivery` enregistré pour le personnage qui livre (`LK_Hostility.record`, attribuable) |
| `presence` | `away` = membre de l'équipe d'une expédition en cours (`group.expedition.team`), `x`, `y` = `group.home` ; PNJ sans groupe : `{ away = false }` |

Sélection Ctrl+G : le client prend la copie la plus proche parmi `objects()` et envoie `lk-<n>` ; le serveur crée la
fiche (`Server.ensure`) et revérifie la portée sur son propre corps. **Un seul moteur de PNJ par serveur** : si un
autre fournisseur occupe déjà `RS_NPCProvider` (autre mod de PNJ qui s'y inscrirait), Living Knox ne s'inscrit pas et
écrit une fois `[RS_LivingKnox] another NPC provider (<nom>) is active: Living Knox is not registered in the notebook
(one NPC engine per server)` ; le moteur lui-même continue de tourner (cohabitation : `LK01-T04`).

**Historique.** Jusqu'au 2026-10-08, le seul fournisseur était un adaptateur Bandits!
(`RS_Bandits.lua`, chargé après `\Bandits2`), retiré par `E17-T02` (commit `ee0d8df` ; dernière version
dans `120033f`). Les sources inspectées et les limites d'identité de ce moteur sont analysées dans
[bandits-analyse.md](../recherches/bandits-analyse.md) ; les validations faites avec lui restent décrites dans
[la validation](../tests/carnet-validation-04221.md).

## Autorité, personnages et projections

Les commandes `RS_Carnet` utilisent le `IsoPlayer` authentifié de `OnClientCommand`. Le serveur
ignore toute identité d'appelant prétendue dans les arguments, vérifie monde/session et lit lui-même
PNJ, portée, révision, inventaire, échéance, engagement et lot. Les commandes sont traitées
séquentiellement sur le fil Lua du serveur. Chaque sélection appartient à un personnage ; plusieurs
joueurs peuvent sélectionner le même PNJ. Une sélection devenue impossible (PNJ mort, hors de portée
ou de vue) est retirée au contrôle suivant (chaque seconde) ou dès qu'une action la revalide.

**Identité de personnage (`E00-T01`).** Fonction `identity` : le serveur lit puis écrit
`RS_CarnetCharacter` dans **sa** copie de la ModData du joueur, seule sauvegardée en multijoueur ;
une valeur écrite par le client y serait perdue à la reconnexion. L'identifiant n'est retenu que s'il
existe dans l'état privé, appartient au même propriétaire (`getUsername()` en MP, `solo` sinon) et au
même slot (`getPlayerNum()`) et n'est pas retiré (`usable`). La valeur que le client envoie dans
`hello` n'est qu'un repli soumis aux mêmes contrôles ; sinon un nouvel identifiant est créé. La
reconnexion retrouve donc personnage, notes et engagements, y compris après un redémarrage du
serveur. Ce mécanisme appartient au carnet, pas à CharacterReputation.

**Mort d'un joueur (`E00-T02`).** `OnPlayerDeath` n'est déclenché que côté client
(`IsoPlayer.java:6096-6110`) : le serveur écoute `OnCharacterDeath`, déclenché aussi sur serveur dédié
pour tout personnage, et ne garde que les `instanceof(…, 'IsoPlayer')` (`Server.characterDeath`). Si
l'identité liée appartient bien à ce propriétaire, elle est marquée `retired`, effacée de la ModData,
et sélection et devis en cours sont abandonnés. Un zombie ou un autre compte ne retire rien ; le mort
ne peut plus être revendiqué ; le personnage suivant reçoit une nouvelle identité et ne reprend pas
les missions de l'ancien. Les missions où le mort était engagé continuent pour les autres
participants.

Le carnet reçoit uniquement les contacts connus, les missions entendues/invitées/engagées,
les interlocuteurs proches invitables et les faits de réputation de son personnage. Notes privées,
reçus d'objets et mémoires internes des autres personnages ne sont jamais projetés. Une mission
entendue est consultable mais ne devient ni invitation ni engagement automatique.

## Fiches de PNJ et purge (`E00-T04`)

Une fiche n'est créée qu'à la **sélection** d'un PNJ (`Server.ensure`, commande `select`), jamais à
son apparition : l'état privé ne grandit pas avec la population et aucun appel LLM n'a lieu sans
contact. `Server.find` lit une fiche existante sans en créer. La fiche contient un identifiant `npc-*`
persistant, l'incarnation et la signature du fournisseur, le nom, le groupe, la personnalité de base
(`personality(signature)` : Park-Miller sur un hachage de la signature, donc identique quel que soit
le moment du premier contact) complétée des `traits` fournis, la biographie, la révision, les accords
(vides) et la dernière vue d'un corps chargé (`seenAt`, rafraîchie au plus une fois par minute).
Un changement de groupe ne supprime ni accords, ni contacts, ni personnalité.

La biographie (enrichissement LLM) n'est demandée qu'après le premier contact d'un personnage, au plus
12 par heure, 3 tentatives par fiche et par démarrage, nouvel essai 5 minutes après un échec.

Purge (`prune`, chaque minute) : les missions closes d'abord (section suivante), puis les fiches qui
n'ont ni contact, ni mission, ni demande en attente, ni corps chargé, et qui sont mortes ou sans corps
vu depuis 1 heure (`NPC_UNSEEN_MS`). Une fiche contactée par un personnage n'est jamais purgée.

## Chat B17

`ISChat:onCommandEntered` et la globale `processSayMessage` sont enveloppés en conservant leurs
arguments, retours, valeurs `nil` et erreurs. Seule une entrée utilisateur effectivement passée
par le chemin vanilla `say`, affichée au joueur et autorisée par le canal, donne une commande
supplémentaire. Le chat radio de Walt, appelé programmatiquement, est exclu de cette capture.
`OnAddMessage` découvre le `ChatBase` local et confirme cet affichage pendant la saisie ; cet
événement ne lance jamais de demande chez un auditeur.

Côté serveur : vivant/éveillé, non muté, `ChatStreams` contient `s`, filtre natif `detectBadWords`,
portée, étage/ligne de vue, texte et budgets. Un mot détecté est refusé de façon conservatrice,
sans chercher à contourner les politiques vanilla de remplacement/ban/kick. Limite propre de
10 secondes ou slow mode serveur plus élevé. La commande du mod reste un canal distinct du paquet
de chat vanilla : **aucun hook Lua serveur confirmé ne permet de prouver qu'un client modifié a
envoyé le paquet vanilla correspondant**. Elle ne peut cependant contourner ces restrictions
revalidées côté serveur ni appliquer des intentions arbitraires.

Réponse : serveur choisit une fois les auditeurs depuis le corps du PNJ au moment de parler.
Client utilise `ChatBase:createMessage` puis `showMessage`, auteur issu de la fiche serveur,
message local sans paquet de faux joueur. `ChatManager` n'est pas appelé depuis Lua. Le canal
`say` exposé est obtenu via `ChatMessage:getChat()` ; une réponse attend dans une petite inbox
jusqu'au premier événement `say` local. Pas de publication dans général/faction/privé.
Déduplication par ID, monde et session. Bulle par `Provider.bubble` sur le corps local de la même
incarnation, s'il est chargé.

L'audition (`Provider.hears`) est une **politique conservatrice de parole intelligible**, pas une
reproduction exacte du chat vanilla : distance, même pièce/bâtiment, étages, exclusion surdité/sommeil/mort
et exclusion des passages qui seraient brouillés. Le réglage serveur `HEARING_RANGE=30` est explicite ; il ne
prétend pas suivre tous les réglages de SayChat. Le bruit du monde est un `addSound` serveur séparé,
une seule fois, portée 15 ; l'injection locale n'attire pas à nouveau les zombies. La vérification
sonore réelle, les cloisons, l'écho et les réglages personnalisés restent à tester en jeu.

**Ligne « Dire » de l'onglet Contacts (`E17-T06`).** Le chat n'existe pas en solo : la fiche d'un contact porte une
ligne de saisie (même présentation que la ligne « Dire » de l'onglet Radio) qui envoie la phrase par
`RS_CarnetClient.talk`, le même chemin que la capture du chat ci-dessus : commande client `talk`
(`text`, `channel = 'say'`, `language`), donc mêmes contrôles serveur (PNJ sélectionné et à portée, règles de chat,
filtre, délai de 10 s ou slow mode, budget) et même demande `npc_talk` au pont. Une fois la phrase admise (réponse
`queued`), le personnage la prononce : `processSayMessage` en MP (entendue par les autres joueurs ; l'enveloppe ne
capture que la saisie d'`ISChat`, donc aucune seconde demande), `IsoPlayer:Say` en solo. La ligne est grisée avec la
raison tant que la fiche n'est pas la cible (`Parler` ou Ctrl+G), que le PNJ est hors de portée ou mort, qu'une
réponse est attendue (jusqu'à la réponse de ce PNJ, un refus du serveur ou 95 s) ou pendant le délai entre deux
phrases ; le serveur reste seul juge. En solo, la réponse s'affiche en bulle au-dessus du PNJ et dans l'historique de
la fiche (pas de ligne de chat). Un refus `Range` renvoie aussitôt la projection (cible retirée, ligne grisée).

## Missions, livraison et persistance

Catalogue inspecté dans `media/scripts/items/normal.txt` installé : `Bandage`, `RippedSheets`,
`Bullets9mm`. Quantités figées dans `RS_Config.lua` (`Missions.deliver`, alias historique `Delivery`), recopiées à création de mission ;
une modification du catalogue ne réécrit pas une mission existante. Offre admissible seulement si le
fournisseur déclare le PNJ non hostile (`hostile == false` ; inconnu = pas d'offre), si le PNJ n'a
aucune mission ouverte et si son délai entre deux offres est écoulé (`offerCatalog`). Le LLM choisit
une offre admissible, le serveur la revérifie, le carnet l'accepte par bouton.

**Moteur de gabarits (`E11-T02`, `RS_Missions.lua`).** Le moteur porte ce qui est commun à toute
mission : offres admissibles (`M.offers`, appelé par `offerCatalog`), création, acceptation, chrono et
expiration des offres, résultat collectif et réputation, transaction de progression à journal
préalable (`M.report`), lot de récompense commun (`M.claim`), purge et projection. Chaque gabarit est
enregistré par `M.register(nom, gabarit)` et fournit `offer`, `create`, `check`, `prepare`, `apply`,
`progress`, `complete`, `project` et `context` (signatures en tête du fichier) ; son catalogue est
`RS_Config.Missions[nom]`, dont `id` est l'identifiant d'offre vu par le pont. M01 est le gabarit
`deliver` ; `M.deliver`, `M.checkItems` et `M.eligible` restent des façades. Une mission sauvegardée
sans champ `template` (avant `E11-T02`) est lue comme `deliver`. Le contrat Lua ↔ Python
(`offers`, contexte `mission`, projection) est inchangé.

**M01 alimentée par les besoins réels (`E17-T03`).** Pour un PNJ d'un fournisseur qui définit `supplies` (Living
Knox), l'offre `first_aid_v1` du gabarit `deliver` n'est plus le catalogue statique : c'est l'offre ouverte de son
groupe dont la réserve est la plus basse (`API.missionOffers(groupe, personnage)` : une offre par réserve sous 40, aucune
envers un personnage que le groupe tient pour hostile, aucune sans besoin). Sans offre du moteur, aucune mission
`deliver` pour ce PNJ (`M.create` refuse). Le catalogue est calculé pour le personnage qui parle (`offerCatalog`) et
revalidé à la réponse ; les conditions revalidées (`terms`) sont passées à `M.create`.
- *Adaptation V ↔ objets* : la mission compte en points de valeur V du barème (`m.unit = 'value'`) : `quantity` = V
  restant à l'acceptation, `values` = V d'un objet par type (liste fermée `API.SUPPLY_ITEMS`), `delivered` = V comptée
  par le moteur. La fenêtre de livraison borne le nombre d'objets au reste en V (chaque objet vaut au moins 1 V) ; le
  serveur refuse avant tout effet une livraison qui contient un objet de plus que nécessaire (`TooMany` : seul le
  dernier objet peut dépasser, règle du moteur) ou une offre déjà close (`SupplyClosed`).
- *Livraison* : marqueur d'écriture préalable sauvegardé, puis `Provider.supplyDeliver` avec la **clé de reçu = jeton
  de transaction du carnet** (la réserve du groupe remonte de `round(cumul / 4) − round(cumul précédent / 4)`, une seule
  fois : un rejeu de la même clé rend `duplicate` sans rien changer), puis retrait des objets. Un refus du moteur à cet
  instant retire le marqueur sans effet (`SupplyRefused`) ; un échec de retrait d'objet garde le blocage `Recovery`.
- *Fin* : l'offre remplie ferme la mission en `success` (réputation du carnet et confiance comme M01) ; le fournisseur
  enregistre le fait d'attitude `delivery` pour le personnage qui complète ; le lot commun est l'objet de récompense du
  moteur (`reward.item`, par exemple 2 `Base.Antibiotics` pris sur une réserve haute), retiré par `M.claim` ; sans objet
  (aucune réserve assez haute, ou retiré par le moteur), aucun lot (`RewardGoodwill`). Une offre close par le moteur
  avant la fin (expirée en heures de jeu, remplie par une autre mission, groupe disparu), relevée au plus toutes les
  10 s, ferme la mission en `cancelled_closed` sans réputation (comme `cancelled_dead`) ; une offre non acceptée expire.
- *Délai* : celui de M01 (7 200 000 ms de fonctionnement) ; l'offre du moteur a son propre délai de 48 heures de jeu,
  qui peut tomber avant (pause, vitesse de jeu) : la mission se ferme alors comme ci-dessus.

**Gabarit reconnaître (`E11-T03`, `RS_MissionScout.lua`, offre `scout_v1`).** Atteindre un lieu choisi par le
serveur, puis en rendre compte au demandeur **de vive voix**. Mêmes délai (7 200 000 ms de fonctionnement du
serveur), barème de réputation, résultat collectif et lot commun (20 cartouches de 9 mm) que M01 ; le moteur commun
gère acceptation, chrono, abandon, mort du demandeur, purge et récompense.
- *Lieu* : bâtiment habitable de la métagrille (`RS_Rescue.check` : ni construction de joueur, ni sous-sol seul,
  ni eau, dans la carte), entre `minDistance` (60) et `maxDistance` (250) cases du corps du demandeur et à 60 cases
  au moins de toute base connue (refuges vanilla, joueurs connectés : `RS_Rescue.knownBases`). Seules les cellules
  autour du demandeur sont lues (`IsoMetaCell:getBuildingsIntersecting`), aucune case n'est lue ni chargée ; départ
  au hasard (tirage Park-Miller de `RS_Rescue.drawer`), puis 40 bâtiments consécutifs au plus. Le lieu est tiré au
  calcul de l'offre et gardé en mémoire 10 min pour ce demandeur (une minute sans lieu avant un nouvel essai), pour
  que l'offre racontée par le pont et la mission créée désignent le même bâtiment ; après un redémarrage, un nouveau lieu est tiré. Sans
  métagrille ou sans bâtiment admissible, `scout_v1` n'est pas offerte et une création est refusée.
- *Zone* : emprise du bâtiment (`BuildingDef`, fins exclusives) élargie de `margin` (2) cases, tous étages. Elle est
  rangée dans la mission (`m.zone`, état privé `RS_State`), jamais dans une ModData globale, ni dans le contexte du
  pont, ni dans la projection du carnet.
- *Présence* : `M.observe`, appelé par la boucle du carnet une fois par seconde (avec la vérification des
  sélections) sur la **copie serveur** de chaque joueur connecté et identifié (`Server.bound`, `getX`/`getY` du
  `IsoPlayer` serveur). Aucune commande du client ne porte une position prise en compte : une commande forgée
  (`report`, `scout_reached`, `talk` avec `x`/`y`) est ignorée. Le premier participant vivant dans la zone marque
  `zoneReached` (avec `reachedBy`, `reachedAt`), la révision monte, l'état est sauvegardé et la projection publiée.
  Une offre non acceptée n'est pas surveillée ; liste vide : rien n'est décidé.
- *Compte rendu* (`E11-T13`, commun à `scout`, `clear`, `recover`, `signal`) : de proximité pour un PNJ (à la radio
  pour une voix, ci-dessous). L'objectif rempli (`RS_Missions.reportReady` ; ici la visite) laisse la mission
  `active` « à rapporter » (`toReport`). Une phrase d'un participant admise par `talk` (demandeur sélectionné à
  `SELECT_RANGE`, chat local autorisé, délai respecté) porte alors `context.reportable` ; le modèle rend
  `report_done` s'il y voit le compte rendu (aucune liste de mots) et `Server.spokenReport` revérifie (même mission
  ouverte chez ce PNJ, objectif rempli, participant) avant `M.spoken` puis `M.report` (charge `speech`, marqueur à
  journal préalable, reçu `speech-<personnage>`) : réussite. Sans pont : bouton « Rendre compte » près du corps du
  demandeur (`DELIVERY_RANGE`, commande `report`). Avant l'objectif : pas de `reportable`, `report_done` ignoré,
  bouton refusé (`State`). Un objectif sans compte rendu laisse la mission en cours jusqu'à l'expiration (`failed`) ;
  demandeur mort : `cancelled_dead`. Détails : `docs/specifications-techniques/protocole-carnet-v2.md`, « Compte rendu au demandeur ».
- *Donnée par une voix radio (`E11-T08`, `RS_MissionVoice.lua`)* : action `start_mission { template = "scout" }`
  jugée par `RS_Actions` (fiche, `budget.start_mission`, 60 s par voix). Le donneur est un enregistrement « voix » de
  l'état privé (`data.voiceDonors['voice:<voix>:<personnage>']`), sans fiche de PNJ ni corps ; le moteur le retrouve
  par `M.donorOf` (libération, délai de 30 min, purge). Lieu tiré par la même offre `scout`, autour de la **copie
  serveur** de l'appelant (refus `no_player` sans elle) ; mission créée et acceptée aussitôt pour l'appelant, une seule
  ouverte par appelant et par voix (`mission_open`), ligne « Mission reçue : <type de lieu> » sur la fréquence de la
  voix. Visite : même sondage `M.observe`. Compte rendu **à la radio** (`E11-T13`) : après la visite, la demande de
  l'appelant à cette voix porte `turn = report_due` ; le modèle rend l'action `report_mission` (permise avec
  `start_mission`) s'il y voit le compte rendu, et son exécuteur (`RS_MissionVoice.report`) revérifie puis passe par
  `M.spoken` ; avant la visite, `turn = not_yet` et `report_mission` est refusée `not_done`. Récompense : réputation du moteur (barème M01) et repère `mark_map` du premier lieu `place=`
  de la fiche pas encore donné à ce personnage (réputation seule sinon) ; aucun lot (`rewardCount = 0`), pas de cache
  avant `E11-T06`. Contexte de la mission joint aux demandes de l'appelant à cette voix (`mission=`), sans
  coordonnée. Fonctionne sans moteur de PNJ (Living Knox désactivé). Détails : `docs/specifications-techniques/protocole-carnet-v2.md`,
  « Mission donnée par une voix ».
- *Carnet* : la projection ajoute `template = 'scout'`, `zoneReached`, `reachedBy`, `placeKind`, `report`
  (`donor = 'voice'` pour une voix) ; la page Missions affiche le type de lieu traduit, « lieu atteint » ou « pas
  encore atteint » et la consigne du compte rendu (de vive voix, ou à la radio pour une voix), sans bouton de
  livraison ; pour une voix, ni lot, ni invitation, ni « rejoindre le demandeur », seulement « Abandonner ». Depuis
  `E11-T09`, la projection ajoute `clues` (`RS_Rescue.clueData` : clés et codes, jamais de texte traduit par le serveur
  ni de coordonnée) et la page affiche « Indices donnés sur le lieu : » suivi des indices composés par le client
  (`IGUI_RS_Clue_*`, EN/FR) ; titre du gabarit dans la liste et la fiche (`titleKey`), plus de ligne
  `ReputationUnavailable` dans la fiche. Une voix dit aussi les indices juste après la création (demande de consigne
  `turn = briefing`, `docs/specifications-techniques/protocole-carnet-v2.md`).
- *Zone sur la carte* (`E11-T10`, décision du 2026-10-11) : à la création (PNJ ou voix), `Scout.mapZone` tire un
  cercle d'environ un pâté de maisons (`RS_Config.Missions.scout.mapZoneRadius` = 30 cases de rayon, agrandi si la
  demi-diagonale du bâtiment laisse moins de 40 % du rayon) qui contient toute l'emprise du bâtiment, centre décalé du
  centre du bâtiment d'une distance tirée entre la moitié et la totalité de la marge restante (rayon − demi-diagonale
  − 1 case), direction et distance tirées par `RS_Rescue.drawer` sur `<id de mission>:<clé du lieu>` (même tirage pour
  la même mission). Gardée dans `m.mapZone = { x, y, r }` (état privé, jamais en ModData globale) ; distance des cibles
  inchangée. La projection ne la donne (`p.mapZone`) qu'à un participant d'une mission **active** ; ni le contexte du
  pont ni l'offre ne la portent. Le client (`RS_MapActions.zones`, appelé à chaque instantané du carnet) pose un
  symbole vanilla « Circle » agrandi (anneau de rayon `r`) et le libellé `IGUI_RS_MapZone` (« Zone de reconnaissance
  (<demandeur>) ») ; il retire les zones qui ne correspondent plus à une mission active (réussite, abandon,
  expiration, purge, autre personnage), y compris au premier instantané après une reconnexion (`hello` d'`OnGameStart`)
  quand la fin a eu lieu hors connexion. Symboles reconnus par leur couleur orange et leur alpha 0,8 ; persistance
  comme les notes du joueur (`map_symbols.bin` côté client), zone manquante reposée une fois par session. La page
  Missions ajoute « Une zone approximative est entourée sur votre carte » tant que le lieu n'est pas atteint. Missions
  créées avant `E11-T10` : pas de zone.

**Gabarit retrouver (`E11-T05`, `RS_MissionRetrieve.lua`, offre `retrieve_id_v1`).** Retrouver le corps d'un
disparu dans un bâtiment choisi par le serveur et rapporter sa carte d'identité au demandeur. Mêmes délai, barème,
résultat collectif et lot commun que M01 et `scout` (moteur commun). Choix de conception : `docs/annexes/conception/mission-retrouver.md`.
- *Offre* : fiche de PNJ du carnet seulement (une voix radio ne la propose pas : `RS_MissionVoice.TEMPLATES` et la
  liste fermée du pont restent `scout`) ; seulement si la classe vanilla `RandomizedWorldBase` est exposée (un banc
  sans elle n'offre rien). Lieu tiré comme `scout` (`RS_MissionScout.pick` : 60 à 250 cases du corps du demandeur, 60
  cases au moins des bases connues, rien de chargé), gardé 10 min par demandeur dans la mémoire du gabarit ; offre au
  pont : `kind = retrieve_id`, `item = ID card`, type de lieu, indices sans chiffre.
- *Création* : point du site (centre de la pièce principale, `m.spot`) et emprise (`m.bounds`) dans l'état privé ;
  zone approximative sur la carte comme `scout` (`Scout.mapZone`, `m.mapZone`, projetée au seul participant d'une
  mission active ; libellé `IGUI_RS_MapZoneSearch`, « Zone de recherche (<demandeur>) ») ; champs de livraison
  `quantity = 1`, `delivered`, `accepted` = cartes d'identité vanilla (`IDcard`, `_Male`, `_Female`, `_Stolen`).
- *Pose différée* : par le sondage d'une seconde du carnet (`M.observe` → `Retrieve.observe`), au plus toutes les 5 s
  par mission, quand la case du point est chargée (`getCell():getGridSquare` du point lui-même) et que le bâtiment a
  passé ses histoires vanilla (`BuildingDef:isFullyStreamedIn` ou une pièce explorée) : cadavre
  `RandomizedWorldBase.createRandomDeadBody` (tenue au hasard, ni rampant ni faux mort) sur la case libre la plus
  proche du point dans le même bâtiment (sans escalier), sinon dans l'emprise ; une carte `Base.IDcard` nommée d'après
  le mort (`nameAfterDescriptor`) dans son conteneur (`sendAddItemToContainer`). La mission garde `m.cardId`
  (`getID()` de la carte), `m.person`, `m.bodyAt` ; le corps porte la ModData `RS_RetrieveMission`. Sauvegarde
  aussitôt après la pose ; une pose réussie n'est jamais refaite (redémarrage compris).
- *Trouvée* : le sondage marque `found` (et `foundBy`) dès qu'un participant tient la carte (inventaire serveur, sacs
  compris, `getItemWithIDRecursiv`).
- *Remise* : bouton « Livrer » du carnet près du demandeur (`DELIVERY_RANGE`), fenêtre de livraison qui liste les
  cartes d'identité du joueur ; `confirm_delivery` → `M.report` → `Retrieve.check` : seule la carte dont l'identifiant
  vaut `m.cardId` et qui est dans l'inventaire serveur du joueur est admise (jamais d'après le nom affiché) ; toute
  autre carte, même homonyme, est refusée avant tout effet (`WrongCard`, « Ce n'est pas la carte d'identité prise
  sur le corps »). La carte est retirée (transaction à journal préalable du moteur), puis réussite, réputation et lot
  commun.
- *Carnet* : projection `template = 'retrieve_id'`, `placeKind`, `clues`, `person`, `found`, `foundBy`, `quantity`,
  `delivered`, `accepted`, `mapZone` ; page Missions : lieu, indices, zone entourée, nom sur la carte, carte trouvée
  ou non, consigne de remise ; bouton « Livrer » visible.
- *Limites* : un arrêt brutal entre la pose et la sauvegarde peut poser un second corps (l'ancienne carte serait
  refusée) ; un corps retiré par `HoursForCorpseRemoval` ou détruit perd la carte (la mission expire) ; corps
  seulement (pas de zombie porteur) ; aucune vérification en jeu ni en MP à ce jour.

**Gabarit nettoyer (`E11-T04`, `RS_MissionClear.lua`, offre `clear_v1`).** Tuer N zombies dans un cercle tracé autour
d'un lieu choisi par le serveur. Mêmes délai, barème, résultat collectif et lot commun que M01 et `scout` (moteur
commun). Choix de conception : `docs/annexes/conception/mission-nettoyer.md`.
- *Offre* : fiche de PNJ du carnet seulement (`RS_MissionVoice.TEMPLATES` reste `scout`). Lieu tiré comme `scout`
  (`RS_MissionScout.pick`), gardé 10 min par demandeur. Cercle de comptage centré sur le bâtiment (30 cases, plus pour
  un grand bâtiment). N d'après la densité des en-têtes de lot dans le cercle (`getChunkDataFromTile` →
  `getUnadjustedZombieIntensity`, `Distribution` uniforme = 128, × `ZombieConfig.PopulationMultiplier`) :
  `N = 6 + 19 × min(1, densité / 0,5)`, borné à 6..25 ; densité < 0,04, `Zombies` = 6 ou métagrille sans densité :
  pas d'offre. Offre au pont : `kind = clear`, type de lieu, indices sans chiffre, `kills` = N, `report = in_person`.
- *Création* : `m.mapZone` (cercle exact, projeté au seul participant d'une mission active ; libellé
  `IGUI_RS_MapZoneClear`, « Zone à nettoyer (<demandeur>) »), `m.target`, `m.kills = 0`, `m.tally` (par personnage) ;
  `quantity = 0`, `accepted = {}` : l'échange de livraison du carnet n'admet rien.
- *Décompte* (serveur ou solo seulement) : `OnHitZombie` relève le dernier coup d'un joueur sur chaque zombie, tant
  qu'une mission `clear` est ouverte ; à `OnZombieDead`, règle d'E04-T06 : tueur = `getAttackedBy()` joueur avec un
  coup relevé de lui depuis 5 s au plus, ou conducteur d'un véhicule ; feu, piège sans lanceur, chute, `Kill(nil)` :
  rien. Corps de PNJ (fournisseur, étiquette Living Knox), zombie déjà compté (ModData `RS_ClearCounted`), hors du
  cercle (position serveur du zombie à sa mort) ou tueur non participant : rien. Un zombie compte pour une seule
  mission (première par identifiant). Chaque compte relève la révision, marque l'état à sauvegarder et publie
  l'instantané ; au N-ième, objectif rempli (`E11-T13` : « à rapporter », plus aucun décompte, sauvegarde) ; la
  réussite (réputation, lot commun réclamé près du demandeur) vient du compte rendu au demandeur (voir `scout`).
- *Carnet* : projection `template = 'clear'`, `placeKind`, `clues`, `kills`, `target`, `tally` (liste
  `{ name, count }` triée), `mapZone` ; page Missions : lieu, indices, cercle, décompte commun et part de chaque
  participant, règle de comptage, compte rendu au demandeur une fois le décompte atteint ; ni bouton « Livrer » ni
  ligne « sans remboursement ».
- *Limites* : N est un ordre de grandeur (population native illisible en Lua) ; décompte sauvegardé avec l'état
  (intervalle de sauvegarde) : un arrêt brutal peut perdre les derniers comptes ; relevé des coups en mémoire (un
  redémarrage entre le coup et la mort la laisse non attribuée) ; aucune vérification en jeu ni en MP à ce jour.

**Caches et gabarit récupérer (`E11-T06`, `RS_Caches.lua`, `RS_MissionRecover.lua`, offre `recover_v1`).** Ramasser
une cache (sac marqué) posée dans un lieu choisi par le serveur et la porter au dépôt du groupe du demandeur. Mêmes
délai, barème, résultat collectif et lot commun que M01 et `scout` (moteur commun). Choix de conception :
`docs/annexes/conception/mission-recuperer.md`.
- *Cache* (`RS_Caches`) : champ `m.cache` de la mission (une par mission, état privé) = `{ key, table, spot, bounds,
  placing, placed, itemId, at }` ; tables fermées `RS_Config.Caches` (`food`, `medical`, `ammo`, `tools`) ; sac
  `Base.Bag_DuffelBag`, ModData `RS_Cache = <mission>`, rempli avant d'être posé au sol par
  `AddWorldInventoryItem(sac, 0.5, 0.5, 0, true)` sur la case libre la plus proche du point dans le même bâtiment.
  Pose différée (au plus toutes les 5 s) quand la case du point est chargée et que le bâtiment a passé ses histoires
  vanilla ; `placing` sauvegardé avant, `placed` et `itemId` aussitôt après ; un arrêt entre les deux fait reprendre
  le sac marqué trouvé au sol de l'emprise plutôt qu'en poser un second. Seules les missions `active` (ou `success`
  pour la cache d'une voix) posent leur cache ; sondage `Caches.poll` par la boucle du carnet, une fois par seconde
  quand un joueur est connecté.
- *Offre* : fiche de PNJ dont le fournisseur connaît le foyer du groupe (`RS_NPCProvider.presence` : `x`, `y`, `z`
  facultatif), sinon rien. Lieu tiré comme `scout` et table de la cache tirée avec la même graine, gardés 10 min par
  demandeur. Offre au pont : `kind = recover`, `item = bag`, `cache` (nom de table), type de lieu, indices sans
  chiffre, `report = in_person` (`depot` avant E11-T13).
- *Création* : `m.spot`/`m.bounds` du bâtiment, `m.cache`, `m.depot = { x, y, z, r = 3 }` (foyer relu à la
  création), `m.mapZone` (zone approximative de `scout`) ; `quantity = 0`, `accepted = {}` : l'échange de livraison du
  carnet n'admet rien (`check` refuse toute contribution).
- *Sondage* (`observe`, copie serveur des participants) : pose de la cache ; `m.found` quand un participant tient le
  sac (`getItemWithIDRecursiv(itemId)`) ; une fois par seconde au plus, si la case du dépôt est chargée, recherche du
  sac par son identifiant au sol des cases de la zone (`getWorldObjects`) ou dans un conteneur d'un objet de la zone
  (`getContainerByIndex(i):getItemWithIDRecursiv`). Trouvé : retiré du monde (`transmitRemoveItemFromSquare`, ou
  `Remove` + `sendRemoveItemFromContainer`), `m.deposited` : objectif rempli (`E11-T13` : « à rapporter », plus de
  recherche) ; réussite (réputation, lot commun) au compte rendu au demandeur (voir `scout`).
- *Carnet* : projection `template = 'recover'`, `placeKind`, `clues`, `cache`, `placed`, `found`, `foundBy`,
  `deposited`, et pour un participant d'une mission active `mapZone` et `depotZone` ; carte : cercles « Zone de la
  cache (<demandeur>) » et « Dépôt (<demandeur>) », retirés à la fin ; page Missions : lieu, indices, contenu annoncé,
  sac trouvé ou non, dépôt, règle de remise ; ni bouton « Livrer » ni ligne « sans remboursement ».
- *Action de voix `place_cache { table }`* : cache de la dernière mission de la voix pour l'appelant (ouverte, sinon
  sa dernière réussite), au bâtiment de cette mission (`m.zone` moins la marge de `scout`), une par mission ; refus
  `no_mission`, `cache_exists`, `no_character`, `storage`, `no_place`, `bad_params` ; délai 60 s par voix, plafond
  `budget.place_cache`. Le pont la propose avec ses quatre tables (`EXECUTABLE_ACTIONS`, `CACHE_TABLES`).
- *Plafond d'offres* : 6 (`RS_Config.MAX_OFFERS` = `npc_protocol.MAX_OFFERS`), premières offres dans l'ordre
  d'enregistrement des gabarits.
- *Limites* : contenu du sac non vérifié au dépôt ; sac au sol soumis à `HoursForWorldItemRemoval` s'il figure dans la
  liste de retrait ; foyer révélé au participant par le cercle du dépôt ; cache d'une voix absente du carnet ; aucune
  vérification en jeu ni en MP à ce jour.

**Gabarit signaler (`E11-T07`, `RS_MissionSignal.lua`, offre `signal_v1`).** Allumer un signal de la couleur demandée
dans un cercle tracé autour d'un bâtiment tiré par le serveur, pendant une fenêtre d'heures de jeu. Mod requis
Signal Smoke (`batman_SignalSmoke`, `require=` du `mod.info` depuis le 2026-10-15). Mêmes délai, barème, résultat collectif et lot
commun que M01. Choix de conception : `docs/annexes/conception/mission-signaler.md`.
- *Module* : `require 'SignalSmoke/SignalSmoke'` rend une table avec `onSignal` et `COLORS` ; sinon (installation
  cassée) une ligne `ERROR` au journal et aucune offre. Abonnement unique `SignalSmoke.onSignal(Signal.onSignal)` sur l'autorité, au chargement du fichier.
- *Offre* : fiche de PNJ seulement ; lieu tiré comme `scout`, cercle centré de 20 cases (`Clear.zone`), couleur parmi
  `green`, `red`, `yellow`, `purple`, heure de début 2 à 4 heures de jeu après le tirage, fenêtre de 2 heures, gardés
  10 min par demandeur. Offre au pont : `kind = signal`, type de lieu, indices sans chiffre, `color`, `hour`,
  `windowHours`, `report = in_person` (`none` avant E11-T13).
- *Objectif* : premier événement `started` dont le joueur (`event.player`, sinon `event.username` parmi les joueurs
  liés) est participant d'une mission `signal` active, dont la couleur (comparée à `SignalSmoke.COLORS`) est celle
  demandée, la position dans le cercle et l'heure de jeu (`GameTime:getHour`) dans la fenêtre (n'importe quel jour) :
  `m.lit`, « à rapporter » (`E11-T13`), état sauvegardé et publié ; autres signaux, dont les suivants : rien. Réussite
  au compte rendu au demandeur (voir `scout`).
- *Projection* : `template = signal`, type de lieu, indices, `color`, `hour`, `windowHours`, `lit`, `litBy`, cercle
  `mapZone` pour un participant d'une mission active (libellé `IGUI_RS_MapZoneSignal`). Pas de bouton « Livrer ».
- *Limites* : fusées de Signal Smoke toujours rouges ; bâton lumineux attribué au joueur près duquel il est trouvé ;
  grenade sans lanceur connu non comptée ; journée de jeu très longue : fenêtre peut-être hors délai ; aucun essai en
  jeu ni MP à ce jour.

**Missions répétables (`E00-T03`, `RS_Missions.lua`).** Un PNJ n'a qu'une mission ouverte (offre ou
active) à la fois ; chaque mission a un identifiant unique `<fiche>-deliveryN`. À la clôture
(réussite, échec, abandon, mort du demandeur, expiration), `release` libère le PNJ et fixe la
prochaine offre possible 30 minutes **de jeu à vitesse normale** plus tard (`OFFER_COOLDOWN_MS`, âge du monde
`nextOfferHour` depuis `E11-T20` ; un ancien `nextOfferAt` en ms réelles est converti à la lecture par
`M.offerWait`). Une offre que personne n'accepte expire après 1 heure de jeu à vitesse normale
(`OFFER_TTL_MS`, décomptée comme le chrono ci-dessous) et passe à l'état `expired`
(« Offre expirée : personne ne l'a acceptée »). Une offre d'un PNJ mort n'est plus acceptable et
expire de même.

Première acceptation : activation du chrono commun de 7 200 000 ms **de jeu à vitesse normale**
(`E11-T20`, décision de l'utilisateur du 2026-10-21, point C27 ; remplace le décompte en temps réel de
fonctionnement du serveur). `OnTickEvenPaused`, les commandes et `OnSave` font avancer un même compteur
(`RS_GameClock.meter`) : écart d'âge du monde (`getWorldAgeHours`) × durée réelle d'une heure de jeu
(`getMinutesPerDay() × 60000 / 24`). Le chrono s'arrête donc en pause (Échap en solo, serveur vide en
`PauseEmpty`), va trois fois plus vite en vitesse x3 ou pendant le sommeil, et dure 2 h réelles à x1
quelle que soit la durée du jour du sandbox. Au démarrage, le compteur repart de l'âge du monde chargé :
redémarrer n'ajoute pas la durée d'arrêt. Un âge du monde qui recule (`setTimeOfDay`) ne compte rien.
Les missions sauvegardées gardent leur `remainingMs` (même unité à vitesse normale). Les rétentions
(`MISSION_RETENTION_MS`, `UNCLAIMED_RETENTION_MS`, `closedAt`) restent en temps réel. Les joueurs tardifs confirment individuellement sans remettre le chrono
à zéro, même après une remise partielle. L'abandon confirmé clôt la mission commune pour tous ; le
libellé l'annonce.

Remise : choix natif des IDs réels dans l'inventaire et les sacs, devis personnel de 30 secondes,
récapitulatif, confirmation. Revalidation complète puis marqueur d'écriture préalable dans le
stockage privé, retrait `ItemContainer:Remove`, paquet natif `sendRemoveItemFromContainer`,
progression/reçu/séquestre, sauvegarde appliquée, suppression du marqueur. Deux devis de même
révision ne peuvent débiter deux fois la même progression : le second doit être refait. Objets admis :
type du catalogue, état supérieur à zéro, ni favori ni équipé. Les fournitures sont définitivement
remises sous forme de reçus serveur ; elles ne sont pas injectées dans l'inventaire du moteur de PNJ,
dont l'IA pourrait rematérialiser ou écraser le contenu.

Lot : le serveur crée le lot fixe, vérifie la capacité, écrit le marqueur, réserve le bénéficiaire
**avant** tout ajout, puis ajoute les objets et transmet les paquets natifs. Deux retraits de même
révision ne produisent qu'un lot. Répartition libre après retrait. **Défaut connu (`E00-T10`)** :
`M.claim` crée les objets par `InventoryItemFactory.CreateItem`, classe non exposée à Lua en 42.21 ;
le retrait du lot lèverait une erreur en jeu tant qu'il n'utilise pas `instanceItem`.

**Purge des missions.** Une mission close reste dans les carnets 24 heures réelles après sa clôture
(`MISSION_RETENTION_MS`), 7 jours si elle a réussi et que son lot n'a pas été retiré
(`UNCLAIMED_RETENTION_MS`) ; une mission bloquée par une transaction n'est jamais purgée.

Stockage : deux fichiers `state-<hex(mode/nom)>-{0,1}.txt`, génération, corps RSV2, somme de contrôle,
`end` et relecture après écriture. Dernier slot valide sélectionné ; deux slots existants invalides
bloquent le carnet au lieu de remplacer le monde. Plafond 4 Mio ; dépassement bloquant explicite.
Ces fichiers sont dans le cache serveur, pas dans le Workshop.

**Sauvegarde conditionnelle.** Les commandes qui modifient l'état le sauvegardent aussitôt. En plus,
toutes les 5 secondes (`SAVE_INTERVAL_MS`), `tick` ne réécrit l'état que s'il est marqué modifié
(`S.dirty`) ou si une mission est en offre ou active (`clockRunning`) ; `OnSave` sauvegarde toujours.
Un crash peut perdre au plus 5 secondes de chrono. Un serveur sans mission ouverte ni changement
n'écrit plus rien.

**Défaut connu (`E00-T08`).** `RS_Codec.hex` traite chaque unité UTF-16 de la chaîne Kahlua comme un
octet : au-delà de U+00FF (« ’ », « € », « œ ») il produit plus de deux chiffres et `unhex` ne relit plus
le texte ; un état contenant un tel caractère (note, nom, réponse) échouerait au contrôle de somme et
bloquerait le stockage. Le pont attend par ailleurs de l'UTF-8 alors que le mod envoie du Latin-1
entre U+0080 et U+00FF (`E00-T09`).

**Limite de crash inventaire :** le fichier du mod et la persistance Java des personnages ne sont
pas une transaction de base commune. Les erreurs natives capturées pendant le transfert conservent
le marqueur et bloquent la mission avec « vérification administrateur nécessaire ». Aucun rejeu,
remboursement ou effacement automatique d'un état incertain. Même après une confirmation du mod,
un crash avant sauvegarde Java de l'inventaire n'offre pas une garantie d'atomicité durable.
Avant récupération manuelle, conserver les deux slots, journaux et inventaires du cache de test ;
comparer IDs du marqueur, reçu, progression et objets réellement persistés. Ne pas effacer un
marqueur ni attribuer un second lot sans cette réconciliation. Aucune migration automatique
ou intervention dans les sauvegardes utilisateur n'est livrée.

## Cadence d'envoi (`E00-T04`)

- Le serveur n'envoie plus l'état complet chaque seconde à tous. Il pousse l'instantané de chaque
  joueur connecté (`publish`) après un changement : réponse ou acquittement du pont, commande de
  mission, mort d'un PNJ, avancée ou purge de mission. Sélection, note et sortie de portée ne
  renvoient l'instantané qu'au joueur concerné.
- Chaque client redemande son instantané (`snapshot`) toutes les 3 s carnet ouvert
  (`SNAPSHOT_OPEN_MS`, portées et minuteurs) et toutes les 30 s carnet fermé (`SNAPSHOT_CLOSED_MS`,
  maintien de l'identité et de la session) ; sans identité, il renvoie `hello` à la même cadence.
- Le serveur relit le fichier de réponses du pont et contrôle les sélections une fois par seconde ;
  le carnet ne réécrit le fichier de demandes que lorsque sa file d'attente change.

## Réputation, relations et décès : capacités réelles

`CharacterReputation` installé expose `getDescriptor()` ; les capacités métier sont toutes fausses.
Il n'expose ni `recordEvent`, ni lecture de score, ni identité persistante commune exploitable.
`RS_Reputation.lua` appelle ce descripteur réel, affiche l'indisponibilité et conserve des preuves
terminales `applied=false`, sans score local de substitution et sans replay automatique ultérieur.
La proposition d'API dans `CharacterReputation/docs/proposition-api-reputation.md` n'est pas une API
livrée. Son intégration exigera un contrat serveur de personnage, événement idempotent, score/projection
et règles de barème ; elle devra faire l'objet d'une modification séparée de ce service.

Barème **provisoire configurable**, sans effet tant que l'API manque : réussite +5, échec/abandon -5
pour chacun des participants, aucun gain intermédiaire. Une preuve de réussite est créée une seule
fois par participant. Le carnet affiche une confiance personnelle qualitative : à la rencontre,
hostile si le fournisseur déclare le PNJ hostile, prudente s'il le déclare non hostile, non évaluée
sinon ; favorable et tendance montante après réussite, prudente et tendance descendante après
échec/abandon. Ces catégories n'inventent pas une réputation globale, un accord ni une modification
de combat. Les accords actuels sont vides ; aucune trêve fictive. **Remplacé par E09-T07** : la fiche du contact montre
le panneau de relation (niveau et tendance de la relation personnelle d'E09-T04, niveau du groupe s'il diffère,
accords de faction et leur portée, trois derniers faits), traduit côté client à partir d'identifiants ; voir
[conception/relations.md](relations.md), « Panneau du carnet ». Les lignes de confiance ci-dessus ne sont
plus affichées.

La mort d'un PNJ n'est connue que par l'événement `death` du fournisseur (section « Fournisseur de
PNJ »). Le carnet marque encore `deathAttribution = 'unavailable_server_evidence'` et n'applique aucune
sanction : le fournisseur Living Knox émet `death` avec la cause depuis `E17-T03`, mais la sanction relève de
`E04-T07`. Le réglage `requesterKilled=-50` est une proposition très forte, pas un montant
définitif ni un effet appliqué.

**Réexamen du 2026-10-09 (`E04-T06`) : une règle d'attribution serveur existe.** L'ancienne conclusion
(« bloquée ») partait de `DeadCharacterPacket`, qui est un paquet **serveur → client** (traité seulement
par `processClient`, `java/zombie/network/packets/character/DeadCharacterPacket.java:90-122`) : la mort
d'un zombie est décidée sur le serveur, jamais rapportée par un client. Ce qui fait foi (Java 42.21.0,
`J/` = `java/zombie/`) :

- coup de mêlée ou tir d'un joueur en MP : paquet `PlayerHitZombie`, joueur pris de la **connexion**
  (`J/network/fields/character/PlayerID.java:43`), arme relue dans son inventaire serveur
  (`J/network/fields/hit/Weapon.java:30-49`), puis `target.Hit` (`J/network/fields/hit/WeaponHit.java:79`) ;
  `IsoZombie.Hit` déclenche `OnHitZombie(zombie, attaquant, partie, arme)` avant les dégâts
  (`J/characters/IsoZombie.java:1109-1112`), `setAttackedBy(attaquant)` (`J/characters/IsoGameCharacter.java:5739`),
  et un coup mortel appelle `die()` → `Kill(getAttackedBy())` → `OnZombieDead` dans le même appel
  (`IsoGameCharacter.java:5836-5844, 13478-13486, 13463-13474` ; `IsoZombie.java:4599-4609`) ;
- explosion d'un piège ou d'une bombe : `Hit(arme du piège, lanceur)` (`J/iso/objects/IsoTrap.java:783-790`) ;
- feu : `setAttackedBy(null)` à chaque brûlure et double `OnZombieDead` (`IsoGameCharacter.java:5562-5577,
  6044-6066`) ; cocktail Molotov = feu seul, aucun `Hit` (`IsoTrap.java:754-755`) ;
- véhicule : `setAttackedBy(conducteur de la connexion)` sans `OnHitZombie` (`J/network/fields/hit/Hit.java:63`,
  `VehicleHitField.java:60-70`) ; chute : `setAttackedBy(null)` (`IsoZombie.java:2579`) ;
- **piège** : le client propriétaire d'un zombie envoie sa santé et le serveur appelle `die()` si elle est nulle
  (`J/popman/NetworkZombiePacker.java:100-101, 230`) : `getAttackedBy()` peut alors être un ancien attaquant.

Règle retenue, appliquée par `LivingKnox.Bodies` sur l'autorité (fiche `conception/corps-registre.md`,
« Mort et tueur ») : tueur retenu seulement si le dernier `OnHitZombie` sur ce corps vient du même joueur
depuis 5 s au plus (catégorie `melee`, `firearm`, ou `fire` pour un explosif, avec l'arme), ou si ce joueur
conduit un véhicule à la mort (`vehicle`) ; corps en feu sans coup récent : `fire` sans tueur ; autre cas :
`other` ou `unknown`, sans tueur. La cause est gardée dans le registre Living Knox (`npc.death`) et sera le
troisième argument de `death` (`RS_NPCProvider`). Couvert par le banc et la suite en jeu `rs.killer` (code) ;
tirs, Molotov, bombe et véhicule réels restent au protocole manuel (`tests-en-jeu.md` § 12). Aucune accusation
client ni proximité n'est utilisée. Limites : un tueur « probable » (coup récent puis mort rapportée par le
propriétaire), véhicule sans relevé du choc (conducteur au moment de la mort), compte solo = nom du personnage.

## ISUI et ressources

Bouton latéral Carnet ajouté à `ISEquippedItem`, raccourci configurable (Ctrl+G par défaut : PNJ
visible le plus proche à 8 cases au plus), fenêtre réductible/redimensionnable,
Contacts/Missions/Réputation, liste gauche et détail défilant droite, textes mesurés avec la police
native. Sélection depuis Contacts, ligne « Dire » vers le PNJ sélectionné (`E17-T06`), note privée sur plusieurs lignes
(`setMultipleLine(true)` et `setMaxLines(4)` après `addChild` : mots renvoyés à la ligne par `UITextBox2`, Entrée
ajoute une ligne ; le serveur garde les sauts de ligne et remplace les autres caractères de contrôle), choix de
fournitures, récapitulatif et confirmations sont des contrôles ISUI. La fiche nomme le groupe par son nom lisible
(`groupName` du fournisseur, nom du registre Living Knox), jamais par son identifiant `grp-<n>` (plus projeté),
et n'affiche aucune ligne de groupe pour un PNJ sans groupe. Textes FR/EN dynamiques ; aucun texte incrusté dans les fonds. Le détail est
écrit à l'encre sombre (balise `<RGB:0.16,0.17,0.14>`, `E00-T12`). Cache `getTexture` et repli par
couleurs si texture absente. Namespace `RS_UI_*`, `RS_Carnet`, `RS_*`.

Les textures du carnet papier (`RS_Notebook_*.png`) sont générées par `tools/gen_notebook_textures.py` ;
les anciennes copies papier et couverture de cette première version ont été retirées. Aucune capture d'un autre mod, icône vanilla ni donnée fictive de la maquette n'est copiée dans
l'interface de jeu. Cette provenance locale n'annonce aucune publication de ressources. Ouverture du
carnet vérifiée en solo le 2026-10-08 (sans PNJ) ; rendu avec contenu, grandes polices, petites
résolutions et interactions clavier restent à vérifier (`E03-T02`). Premier joueur local uniquement ;
pas de prise en charge écran partagé annoncée.

## Limites restantes (2026-10-08)

- Fournisseur Living Knox (`E17-T03`) vérifié hors jeu seulement (banc avec le vrai moteur et le pont hors ligne,
  `test_carnet.py` `LivingKnoxCarnetTests`) ; parcours en jeu solo et à deux clients à faire (suite `rs.carnet.lk` et
  protocole manuel). Nom du chef : après une succession, le nouveau chef prend le nom du chef de l'histoire ; noms des
  autres membres tirés (aucun nom tenu par le moteur).
- `E00-T08`, `E00-T09` : texte non ASCII dans l'état privé et vers le pont (section « Missions,
  livraison et persistance »).
- `E00-T10` : retrait du lot par `InventoryItemFactory`, non exposé en 42.21.
- `E17-T05` : le prompt du pont (`bridge/npc_protocol.py`) et le contrat v2 nomment encore l'ancien
  moteur ; aucun champ échangé n'en dépend.
- Identité de PNJ : seule la migration signalée par `reincarnated` est prise en charge.
- Sanction du tueur du demandeur et réputation : non appliquées.
- Missions d'un joueur mort poursuivies par les autres participants ; identités retirées et contacts
  conservés dans l'état privé sans purge (croissance bornée par le plafond de 4 Mio, qui bloque).
- Crash pendant une remise ou un retrait : transaction bloquée, réconciliation manuelle.
- Ligne « Dire » des Contacts, nom du groupe et note multiligne (`E17-T06`) : banc seulement (`test_carnet.py`
  `ContactsTalkTests`, solo et MP simulés, doublures ISUI) ; rendu, focus clavier et retour à la ligne réels de la
  note à vérifier en jeu solo, puis à la séance MP finale.
- Rien n'est validé en jeu avec des PNJ ni à deux joueurs : reconnexion, redémarrage et mort réels
  (`E03-T04`), charge réelle (`E03-T05`), rendu (`E03-T02`), parcours à deux (`E03-T03`).
