# LK11 — Interactions avec les joueurs

**Objectif.** Rendre les rencontres intéressantes : avertissements, attitude par groupe et par joueur, parole de proximité, et points d'entrée pour les missions de RadioSurvivor.

**Dépend de.** LK06-T01.

**Sources.** Spécifications RadioSurvivor (relations, réputation, chat de proximité ADR B17).

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-08 — **LK11-T01** : (1) avec un groupe ami : parler, échanger des nouvelles, demander de l'aide (`LK11-T06`), recevoir des missions du carnet **et troquer directement** contre des objets de son stock réel (`LK11-T08`) ; pas de recrutement. (2) Les pillards attaquent rarement les bases des joueurs, annoncés par des éclaireurs (`LK11-T07`).
- 2026-10-08 — **LK11-T07** : raids **rares et annoncés** : base repérée par ses signes d'occupation, éclaireurs qu'on peut éliminer pour annuler le raid, attaque par l'effectif réel parti du foyer pillard ; fréquence réglable et désactivable en sandbox.
- 2026-10-14 — **LK11-T02** : coup de semonce réservé aux types qui tirent le premier (un par rencontre) ; neutre jamais de tir ; engagement seulement par `targetRule` (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK11-T05** : serment et rancune liés au niveau `hostile` ; une vengeance par groupe ; nouvelle tentative 24 h, traque 12 h, 3 échecs, équipe 2 à 3, 300 cases/h ; apparition à 40 cases au moins de tout joueur et 75 de la zone (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : délai de la vengeance réglable par une option sandbox (défaut 72 h) : tâche LK11-T10.
- 2026-10-14 — **LK11-T06** : période de 24 h par groupe, refus compris ; menu sur tout PNJ, refus par le serveur ; règle de stock unique ; niveaux `favorable`/`trusting` ; portée 4 cases ; objet au pied du PNJ si le joueur est trop chargé (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK11-T07** : signes et points (refuge 3, générateur 2, barricades 1, constructions 1, seuil 2) ; 2 jours d'occupation, 3 000 cases, base ignorée à 60 cases d'un foyer ; un raid à la fois, `RaidDays` 14 ; raid seulement si un occupant est hostile ; valeurs des équipes et délais (confirmé par défaut, valeurs techniques) ; raid au plus tous les 14 jours confirmé par l'utilisateur.
- 2026-10-14 — **LK11-T08** : valeurs de repli (nourriture 2, eau 2, soins 1, matériaux 1, munitions en vrac 0) ; réserve visée complète gardée ; réserve visée = niveau 60 du barème ; groupe « prudent » troque avec marge 0,30 ; menu sur tout PNJ, refus par le serveur (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **LK11-T01** — Décisions d'interaction
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier
  - Faire : poser les questions, consigner.
  - Accepté si : décisions consignées.
  - Tests : —
  - Preuve : décisions du 2026-10-08 (section Décisions) ; `LK11-T07` tranchée, `LK11-T08` ajoutée
  - Reste : —

- [x] **LK11-T02** — Avertissements et sommations
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK11-T01, LK06-T01
  - Fichiers : `LK_Encounters.lua`
  - Faire : approche d'un foyer : sommation, distance de sécurité, escalade progressive selon le type et l'attitude.
  - Idées : I9.2 (avertissements gradués, arme braquée, délai de tolérance) (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : séquence identique pour deux observateurs ; jamais de tir sans sommation pour un groupe neutre.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_encounters.py` du 2026-10-12 (14 tests OK : séquence pure, place de `warn` dans la cascade, groupe neutre armé sans tir avec repli et reprise, un seul coup de semonce sans dégât pour un type qui tire le premier, sommation non entendue sans escalade, MP serveur + 2 clients identiques chez A et B, suite `lk.warn` sur doublures) ; luacheck 16/0 ; conception `docs/annexes/conception/sommations.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.warn", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-181233-solo.txt`) (après `31eb5ef` : joueur invisible du mode debug) ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.warn 2/2 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.warn 2/2 avec les étapes lk.speech.seen, lk.weapon.state (arme braquée) et lk.combat.view (coup de semonce) du client 2 vertes (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/client2/20261015-090729-steps.txt`)
  - Reste : Limites : joueur en véhicule traité à pied ; un joueur à la fois par guetteur ; faits d'attitude laissés par la suite

- [x] **LK11-T03** — Attitude par groupe et par joueur
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK11-T01
  - Fichiers : `LK_Hostility.lua`
  - Faire : attitude qui évolue avec les actes (aide, agression, vol) ; base des relations de RadioSurvivor.
  - Idées : I5.2 (vol constaté), I9.3 (témoins, agresseur seul), I9.4 (réputation qui peut s'améliorer) (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : deux joueurs peuvent avoir des attitudes différentes avec le même groupe.
  - Tests : banc.
  - Preuve : `LK_Hostility.lua` : attitude d'un groupe envers un personnage (clé = groupe + identité de personnage du carnet), valeur interne −100..100 jamais rendue, départ selon l'hostilité du type, 5 niveaux (décision E09-T01 : hostile, méfiant, prudent, favorable, confiant ; seuils en `Config.ATTITUDE`), tendance = sens des trois derniers faits ; faits en liste fermée bornés (don, soin, livraison, coup, tir, meurtre, vol, mission réussie ou ratée) comptés seulement s'ils sont vus ou attribuables (I9.3), agresseur seul visé ; déclin vers le départ de 2 points par jour, plafonné après un meurtre (I9.4) ; persistance privée à deux emplacements, schéma 1, bornes ; `LK_API.attitude` et champ `attitude` `{ level, trend }` quand un joueur est fourni ; `tests/test_lk_hostility.py` 20/20 (deux joueurs, attitudes différentes avec le même groupe), `test_lk_api.py` 21/21, VM Kahlua 26/26 ; `tests/run_all.py` vert le 2026-10-10 hors `belt_radio` (modifications en cours dans le dépôt BeltRadio), luacheck 17/0 et 0, `check_case.py` PASS ; `docs/annexes/conception/attitude.md`, `docs/specifications-techniques/api-living-knox.md` ; LK10-T05 : commit `2194dae`
  - Reste : aucun événement réel branché (coups, morts, vols, dons : tâches de combat et d’interaction) ; un fait enregistré deux fois compte deux fois ; valeurs à recalibrer ; libellés traduits avec le carnet (E09-T07)

- [x] **LK11-T04** — Parole de proximité et bulles
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK11-T01
  - Fichiers : `LK_Speech.lua`
  - Faire : répliques courtes générées par gabarit (barks), affichées aux joueurs à portée ; point d'entrée pour remplacer par le dialogue LLM de RadioSurvivor.
  - Idées : I3.8 (conversations entre membres, pause de patrouille), I9.5 (voix fixe, répliques par situation, délai) (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : texte vu une seule fois par chaque joueur à portée.
  - Tests : suite en jeu.
  - Preuve : `LK_Speech.lua` (autorité) : `Speech.say(npcId, texte | {key, params}, opts)` (point d'entrée d'E08-T03 et du dialogue du carnet) et `Speech.bark(npcId, situation, opts)` ; catalogue `Data/Speech.lua` de 44 répliques en 8 situations selon l'attitude, le type et le rôle, traduites côté client (`IGUI_LK_Speech_*`, EN/FR) ; délais par PNJ et par joueur ; auditeurs = destinataires du relais (`Directives.targets`) filtrés par la règle d'audition vanilla de la bulle (`ChatElement.java:204-237`), une commande `speech` par auditeur, doublons ignorés côté client (128 derniers) ; `LK_SpeechView.lua` : bulle par `addLineChatElement` sur la copie locale du corps (`IsoGameCharacter.java:6719-6725`, rien côté serveur `ChatElement.java:175`) et ligne de chat locale en MP ; `tests/test_lk_speech.py` 18/18 (A et B proches une bulle chacun, C hors portée rien, doublon ignoré, langues) ; suite en jeu `lk.speech` ; `docs/annexes/conception/parole.md` ; base `zombies-as-npc-bodies.md` ; LK09-T03 : commit `1c82290` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : réplique émise et entendue par le joueur (`speech … heard by 1 player(s)`) mais **aucune bulle affichée** au-dessus du PNJ ; dernière campagne MP complète du 2026-10-15 5 h 24 (client 2 actif, règle « les tests font foi ») : lk.speech 3/3, étapes lk.speech.bubble vertes chez les clients 1 et 2 (bulle dessinée une fois, livraison répétée refusée), lk.speech.seen verte chez les deux clients (`tools/autoclient/runs/20261015-052439-mp-4cf10c2eed18/server/20261015-032638-server.txt`)
  - Reste : texte du joueur à afficher au-dessus de son personnage (LK11-T09)

- [x] **LK11-T05** — Vengeance différée après la perte d'un membre
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK11-T03, LK09-T01
  - Fichiers : `LK_Relations.lua`, `LK_Offscreen.lua`
  - Faire : un groupe dont un membre est tué par un joueur identifié par le serveur peut jurer vengeance : délai de plusieurs jours de jeu, annonce perceptible (répliques, radio), équipe réelle partie du foyer (pas d'apparition à côté du joueur), abandon après plusieurs échecs ou si la rancune s'éteint.
  - Idées : I9.6 (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : équipe tirée de l'effectif réel ; aucune apparition près du joueur ; abandon vérifié.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_revenge.py` du 2026-10-12 (27 tests OK : meurtre noté dans l'attitude, serment déterministe selon type et attitude, délai, équipe de 2 à 3 combattants tirée de l'effectif vivant, zone = refuge vanilla ou lieu du meurtre, apparition à 40 cases au moins de tout joueur ou rien, engagement par le choix de cible, abandon après 3 échecs, rancune éteinte, persistance ; suite `lk.revenge` sur doublures) ; run_all 74/74 ; luacheck 16/0 ; conception `docs/annexes/conception/vengeance.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.revenge PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.revenge 1/1 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : vengeance qui cible A et pas B ; essai à la main (délai raccourci, vengeurs venus de loin) abandonné (règle du 2026-10-14 : couvert par `lk.revenge`). Radio sans fonction publique de diffusion (faits `revengeSworn/Started/Ended` en attendant une tâche E) ; base non déclarée en refuge inconnue ; petit écran = apparition parfois impossible ; module hors VM Kahlua du banc.

- [x] **LK11-T06** — Demandes d'aide : dons tirés du stock
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK11-T03, LK08-T06
  - Fichiers : `LK_Relations.lua`, `LK_Stock.lua`
  - Faire : un joueur peut demander nourriture, eau ou soins à un groupe ; acceptation selon l'attitude et le stock, au plus une demande par groupe et par période, connue de tous les membres ; l'objet donné sort réellement du stock. Point d'entrée pour le dialogue LLM du carnet.
  - Idées : I5.3 (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : don retiré une seule fois du stock ; refus si le stock manque ; limite par période respectée.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_aid.py` du 2026-10-12 (20 tests OK : `Relations.requestAid` refuse hors période (24 h par groupe), attitude non favorable ou stock sous la réserve visée ; don retiré une seule fois du stock dans la même écriture que la marque et le journal ; même objet remis au joueur ou posé au sol ; réplique traduite ; menu contextuel revérifié par le serveur en MP) ; run_all 71/71 ; luacheck 16/0 ; conception `docs/annexes/conception/aide.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.aid", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-175841-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.aid PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.aid 1/1 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : menu « Demander de l'aide » d'un client (objet reçu, un de moins dans la caisse, second refus « again »). Dialogue LLM du carnet non branché (le pont n'admet que `none`/`offer`/`accept` : à ajouter dans une tâche E) ; les colons démarrent en rationnement strict et ne donnent que des soins au départ ; aucun effet sur l'attitude ; arrêt brutal entre retrait et remise = objet perdu.

- [x] **LK11-T07** — Raids des groupes pillards
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK11-T03, LK05-T05
  - Fichiers : `LK_Raids.lua`
  - Faire : un groupe pillard repère une base de joueurs par ses signes d'occupation (barricades, constructions, véhicules, lumière, bruit), envoie des éclaireurs réels qu'on peut éliminer (raid annulé), puis attaque avec son effectif réel parti du foyer ; raids rares, réglage sandbox (fréquence, désactivation) ; jamais d'apparition près du joueur.
  - Idées : I9.7 (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : décision consignée ; si retenu, raid issu du foyer pillard, annulé si les éclaireurs sont éliminés.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_raids.py` du 2026-10-12 (20 tests OK : base repérée par signes lus par le serveur sur deux jours, éclaireurs réels qui annulent le raid s'ils meurent, annonce, attaque par l'effectif réel parti du foyer pillard avec apparition à 40 cases au moins des joueurs, fins `done`/`wiped`/`peace`/`disabled`/`forgotten`/`cancelled`, options `RaidsEnabled` et `RaidDays`, persistance, déterminisme) ; `lk_revenge` 27 OK ; run_all 76/76 ; luacheck 16/0 ; conception `docs/annexes/conception/raids.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.raid 2/2 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.raid 2/2 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : essai à la main (`RaidDays` à 3, générateur allumé deux jours) abandonné (règle du 2026-10-14 : déroulé couvert par `lk.raid`). À vérifier : `SafeHouse.getSafeHouse(case)` depuis Lua, générateurs et barricades sur serveur dédié, cases d'apparition sur un petit écran. Base repérée seulement en présence d'un joueur ; pas de pillage abstrait ; radio : point d'appel `raidAnnounced` seulement.

- [x] **LK11-T08** — Troc direct avec un groupe ami
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK11-T03, LK08-T07
  - Fichiers : `LK_Trade.lua` (server), fenêtre de troc côté client
  - Faire : un joueur propose des objets de son inventaire contre des objets du stock réel d'un groupe ami ; le serveur évalue l'échange selon une valeur par objet, ce dont le groupe a besoin (`LK08-T07`) et l'attitude, puis l'applique en une seule transaction (retrait chez l'un, ajout chez l'autre) ; refus motivé sinon. Barème commun avec le passeur de l'Ohio (`E13`) si possible.
  - Accepté si : aucun objet dupliqué ni perdu, même en cas de déconnexion pendant l'échange ; le groupe ne vend pas ce qui lui manque.
  - Tests : banc ; suite en jeu à deux clients.
  - Preuve : banc `tests/test_lk_trade.py` du 2026-10-12 (30 tests OK dont deux clients MP : évaluation par barème `docs/specifications-techniques/passeur-table.md` (`RS_TradeValues.lua`), besoins du stock et attitude ; le groupe ne cède pas ce qui lui manque ; refus motivés (9 raisons traduites) ; une seule transaction, présence revérifiée, un seul objet en transit, aucun vol compté à tort, aucun doublon si A et B demandent le même objet) ; luacheck 16/0 ; conception `docs/annexes/conception/troc.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.trade", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-175848-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.trade PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.trade 1/1 et lk.tradeview « two clients ask the same item through the Trade menu: one winner » PASS, étape lk.trade.window du client 2 verte (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/client2/20261015-090729-steps.txt`)
  - Reste : Limites : aucun effet sur l'attitude ; sacs du joueur non ouverts ; pas d'entrée LLM (pont) ; plafonds et papiers nominatifs laissés au passeur (E13) ; l'offre révèle la marge ; déconnexion pendant l'échange : abandonné (règle du 2026-10-14 : échange appliqué en un seul appel Lua serveur)

- [x] **LK11-T09** — Bulles visibles : PNJ et phrase du joueur
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK11-T04
  - Fichiers : `LK_SpeechView.lua`, `RS_Notebook.lua`, `RS_RadioTalk.lua`
  - Faire : constaté en jeu le 2026-10-11 : réplique entendue (`speech … heard by 1 player`) mais aucune bulle au-dessus du PNJ (`addLineChatElement` sur un corps de zombie ne se dessine pas) ; trouver une méthode d’affichage qui marche (Java) ; demande de l’utilisateur : la phrase que le joueur dit par le carnet (lignes « Dire » Radio et Contacts) s’affiche aussi au-dessus de son personnage.
  - Accepté si : bulle visible au-dessus du PNJ et au-dessus du joueur quand il parle, en solo
  - Tests : banc ; essai solo
  - Preuve : aucune cause Java trouvée à la bulle `addLineChatElement` absente (chemin `renderlast` identique au joueur : `IsoZombie.java:1202`, `IsoGameCharacter.java:6928-7010` ; hypothèse non prouvée : console debug ouverte ; `Say` sans effet sur un zombie) ; bulle dessinée par le mod dans `LK_SpeechView.lua` (`OnPreUIDraw`, `isoToScreenX/Y` à z + 2/3, `DrawStringCentre` police Dialogue avec ombre, 60 caractères par ligne, 5 s + 60 ms/caractère ≤ 15 s, fondu), aucun nouvel envoi réseau ; réponses LLM du carnet par `RS_LivingKnox.bubble` ; phrase du joueur déjà dite après acceptation (Radio `RS_RadioTalk.handle`, Contacts `speakAloud` d'E17-T06 : `Say` en solo, `processSayMessage` en MP, jamais sur refus) ; `test_lk_speech.py` 25 (`DrawTests`), `test_carnet.py` 59 (`PlayerSpeechTests`), `run_all.py` 44/44 le 2026-10-11, luacheck 17/0 et 0 ; suite `lk.speech` mesure la bulle dessinée ; `docs/annexes/conception/parole.md` ; base `ui-windows.md`, `zombies-as-npc-bodies.md` ; **en jeu solo le 2026-10-11 15:19** : `lk.speech` 3/3 PASS (`20261011-151946-solo.txt`), bulles du PNJ et phrase du joueur vues par l'utilisateur
  - Reste : en jeu solo (console fermée) : bulle au-dessus du PNJ (bark, réponse Contacts), stable au zoom ; phrase du joueur au-dessus de lui (Radio, Contacts) ; RST.run({suite="lk.speech",tags="world"}) ; écran partagé et pause non gérés ; MP à la séance finale

- [x] **LK11-T10** — Délai de la vengeance réglable par une option sandbox
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK11-T05
  - Fichiers : `LK_Relations.lua` (`DELAY_HOURS`) ; `media/sandbox-options.txt` ; `Translate/*/Sandbox.json`
  - Faire : décision de l'utilisateur du 2026-10-14 (LK11-T05) : le délai entre le serment et le premier départ de la vengeance devient une option sandbox `LivingKnox.RevengeDelayHours` (heures de jeu, défaut 72, de 12 à 336). Lue au serment ; une vengeance jurée garde son délai. Autres valeurs de LK11-T05 inchangées.
  - Accepté si : au banc : option à 24 = départ 24 h après le serment ; option absente ou hors bornes = 72 ; vengeance déjà jurée inchangée ; en jeu, option traduite visible dans les options sandbox.
  - Tests : banc ; suite `lk.revenge` dans la campagne solo.
  - Preuve : option sandbox `LivingKnox.RevengeDelayHours` (12-336, défaut 72) lue au serment (`Relations.revengeDelayHours`) ; banc `tests/test_lk_revenge.py` 35 OK (24 → départ +24 h, absente ou hors bornes → 72, vengeance jurée inchangée ; suite `lk.revenge` 2/2 sur doublures) ; luacheck 15/0 ; commit `de1bf89` ; campagne solo automatique du 2026-10-15 (`tools/autoclient/runs/20261015-034525-e24ab0eb77eb/20261015-014609-solo.txt`, 195 tests : 167 PASS, 11 FAIL dont 8 dus à la panne du fournisseur LLM) : lk.revenge 2/2 dont « the oath delay comes from the RevengeDelayHours option »
  - Reste : —
