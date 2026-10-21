# E09 — Relations évolutives et accords de faction

**Objectif.** Les relations PNJ ↔ personnage évoluent dans les deux sens selon les faits vécus ; des trêves et alliances explicites se négocient avec une faction de joueurs par ses représentants ; une agression pendant une trêve entraîne une défense ciblée puis une décision du LLM validée par le serveur ; un panneau de relation l'explique au joueur.

**Dépend de.** E17-T03 ; E08-T02 (observations) recommandé ; LK11-T03 (attitude), LK06-T01 (choix de cible) pour T05 et T06.

**Sources.** Spécification : points 2 à 5 et 17 ; ADR B07 (évolution des relations), B08 (relations personnelles et accords de faction), B09 (mandats de négociation), B10 (défense ciblée et décision sur la trêve), B14 (panneau de relation) ; catalogue d'intentions `negotiate`, `change_relation` ; base `multiplayer.md` (faction vanilla sans identifiant stable : nom et propriétaire modifiables ; factions : propriétaire hors de `getPlayers`, noms en double, aucun événement serveur) ; `docs/annexes/conception/attitude.md`, `docs/specifications-techniques/api-living-knox.md` (`API.attitude`), `docs/annexes/conception/corps-registre.md` (tueur), LK06-T01, LK11-T05.

## Décisions

- 2026-10-08 — Bandits! abandonné le 2026-10-08 (`E17-T01`) : étape réécrite sur l'API Living Knox le 2026-10-10 (proposition `proposition-E08-E10-living-knox.md`, archivée). Le dialogue de proximité attendu en dépendance est validé par `E17-T03`.

- Acquises : relations personnelles par personnage et accords de faction distincts ; le propriétaire et ses négociateurs désignés concluent les accords ; défense immédiate ciblée puis décision LLM validée ; confiance en niveaux qualitatifs avec tendance, sans score affiché ; une trêve n'oblige pas chaque PNJ à apprécier chaque joueur.
- 2026-10-10 — **E09-T01 (1)** : échelle de confiance en **5 niveaux** : hostile, méfiant, prudent, favorable, confiant (sans score affiché).
- 2026-10-10 — **E09-T01 (2)** : tendance = **sens des trois derniers faits de relation** (monte, baisse, stable).
- 2026-10-10 — **Réécriture validée** par l'utilisateur (`proposition-E08-E10-living-knox.md`) : E09-T03 gardée (dépendance à E09-T02 abandonnée retirée), E09-T04 réécrite sur `LK_Hostility` et laissée `à décider` (articulation PNJ / groupe, question posée à son ouverture), E09-T05 et T06 réécrites sur le choix de cible de Living Knox (crochet `LivingKnox.Hooks.covered` consulté par LK06-T01, implémenté par `RS_Factions`), E09-T07 gardée et complétée. Q1 à Q3 ne concernent pas cette étape ; les trêves conservées par un PNJ parti (Q3, E10-T04) passent par le même crochet.
- 2026-10-10 — **E09-T03** : choix validés par l'utilisateur : mandats effacés au changement de propriétaire (le nouveau propriétaire redésigne) ; l'équipe personnelle d'un joueur sans faction ne transmet pas ses accords à une faction qu'il crée ; 5 négociateurs au plus par faction.
- 2026-10-14 — **E09-T04** : PNJ sans groupe à `cautious` (ou `hostile`) ; `player_return` non citable ; 8 faits au plus ; un fait motive un changement une fois par relation ; `context.trust` supprimé ; faits antérieurs à la tâche non citables (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : changement de relation refusé = réponse du PNJ gardée, sans le changement (aujourd'hui toute la réponse est refusée) : tâche E09-T09.
- 2026-10-14 — **E09-T05** : portée = membres actuels de l'équipe ; offre des types au-dessus de l'accord courant à tout joueur habilité parlant au chef ; annonce aux joueurs connectés de l'équipe (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : conclusion invalide = réponse du PNJ gardée, sans l'accord (aujourd'hui toute la réponse est refusée) : tâche E09-T09.
- 2026-10-14 — **E09-T06** : un incident par accord ; délais 5 s et 2 min ; toute décision monte la révision, rupture = `none`/`broken` ; réparation catégorie et quantité 5 ; riposte sans incident (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E09-T07** : 3 derniers faits ; date en mots ; « inconnu » pour un PNJ sans groupe ni changement ; accords rompus affichés ; anciens changements sans nature affichés « quelque chose pour / contre eux » ; anciennes clés de confiance supprimées (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **E09-T01** — Libellés, seuils et tendance de la confiance
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier ; spécification point 17
  - Faire : proposer une échelle et un calcul de tendance, faire trancher.
  - Questions : (1) Échelle : options : hostile, méfiant, prudent, favorable, confiant [recommandé] / trois niveaux seulement / sept niveaux. (2) Tendance : options : sens des trois derniers faits de relation [recommandé] / variation sur sept jours de jeu / pas de tendance.
  - Accepté si : décisions consignées.
  - Tests : —
  - Preuve : décisions du 2026-10-10 (section Décisions) : 5 niveaux, tendance par les trois derniers faits
  - Reste : —

- [ ] **E09-T02** — Investigation : hostilité Bandits! envers un joueur ou une faction
  - État : `abandonné`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/bandits-hostilite.md`
  - Faire : relever dans la copie installée (lecture seule) comment Bandits! décide qu'un PNJ attaque : `hostileP`, clans amicaux, cibles, propriétaire réseau, commandes ; ce qu'un mod tiers peut changer côté serveur et la façon dont les clients l'appliquent.
  - Accepté si : chaque point cite fichier et ligne ; la faisabilité d'une trêve ciblée (par joueur ou par faction) est établie ou réfutée.
  - Tests : —
  - Preuve : —
  - Reste : Bandits! abandonné le 2026-10-08 (`E17-T01`) : l'hostilité par joueur et par faction est conçue dans Living Knox (`LK06-T01`, `LK11-T03`).

- [x] **E09-T03** — Identifiant de faction propre au mod et mandats de négociation
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Factions.lua` ; `RS_Notebook.lua` (désignation des négociateurs)
  - Faire : identifiant stable par faction vanilla (retrouvé par le propriétaire ou la majorité des membres, renommage toléré) ; le propriétaire désigne des négociateurs dans le carnet ; revalidation des droits au moment de conclure. Les mandats et la faction sont indépendants du moteur de PNJ.
  - Accepté si : renommer la faction ne perd pas les accords ; un membre non désigné ne peut pas conclure.
  - Tests : banc `lupa` ; suite en jeu MP.
  - Preuve : `RS_Factions.lua` : identifiant d'équipe `fac-<n>` jamais réutilisé dans l'état privé, sondage borné (2 s) qui relie chaque faction vanilla par même objet Java dans la session, puis même propriétaire après un redémarrage, puis majorité des membres connus ; renommage, changement de membres ou de propriétaire sans perte d'identifiant ; faction dissoute marquée `dissolved`, homonymes distincts, joueur sans faction = équipe personnelle ; mandats : 5 négociateurs au plus désignés par le seul propriétaire courant (revalidé à chaque commande), perdus en quittant la faction ou au changement de propriétaire ; `canConclude` relit la faction à l'appel ; carnet : onglet « Équipe » (rôles, boutons de mandat pour le propriétaire), 18 clés EN/FR ; `tests/test_factions.py` 10/10, `test_carnet.py` 49/49, `test_rs_suites.py` 35/35 ; `tests/run_all.py` 39/39 le 2026-10-10, luacheck 17/0 et 0 ; `docs/specifications-techniques/factions.md` ; base `multiplayer.md` (factions vanilla) ; LK03-T04 : commit `6d1826d` ; suite en jeu écrite le 2026-10-15 (`rs.carnet.load`/`rs.worldradio`/`rs.radio`/`rs.observations`/`rs.factions.mandate` selon la tâche, étapes client `RST_PeerChecksRadio.lua`), banc `tests/test_rs_mp_suites.py` 29 OK (échoue sur les défauts injectés), commit `446a39d`; campagne MP complète du 2026-10-15 (client 2 actif, règle « les tests font foi ») : rs.factions.mandate 1 PASS + 1 SKIP solo seulement (faction renommée qui garde identifiant et accords, membre sans mandat refusé), étapes client 1 rs.faction #4/#6/#9 et carnet.mandate #7/#8, client 2 carnet.mandate #5 (`MandateOwner`) (`tools/autoclient/runs/20261015-024734-mp-348bee78d4b7/server/20261015-004928-server.txt`)
  - Reste : —

- [x] **E09-T04** — Relation personnelle d'un PNJ envers un personnage (`change_relation`)
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E09-T01, LK11-T03, E17-T03
  - Fichiers : `RS_Relations.lua` (server, état privé `RS_State`) ; `RS_Carnet_Server.lua` ; pont (intention `change_relation`) ; `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : relation par (fiche du PNJ, identité de personnage du carnet, même clé que `Hostility.keyOf`) ; niveau affiché = mêmes 5 niveaux et même tendance qu'E09-T01, calculés depuis l'attitude du groupe (`API.attitude`) et la relation personnelle selon la réponse à la question ; intention `change_relation` ajoutée à la liste fermée de la réponse (`intent` aujourd'hui `none` ou `offer`) avec un sens (`up`, `down`) et la référence d'un fait **réel** connu du PNJ (fait de `LK_Hostility` vu par son groupe, observation `seen` d'`RS_Observations`, mission close) ; le serveur vérifie la cible, la révision de la fiche, que le fait existe et n'a pas déjà motivé un changement ; une phrase seule ne prouve rien (ADR B11, B15). La relation personnelle est un registre carnet distinct qui ne recalcule pas l'attitude de `LK_Hostility`.
  - Questions : Articulation entre l'attitude du groupe et la relation d'un PNJ ? Options : écart personnel borné à un niveau au-dessus ou au-dessous de l'attitude du groupe [recommandé] / le LLM ne touche que l'attitude du groupe, par des faits de `LK_Hostility` / relation du PNJ entièrement indépendante du groupe.
  - Décisions (2026-10-13, utilisateur) : écart personnel borné à un niveau au-dessus ou au-dessous de l'attitude du groupe (option recommandée).
  - Accepté si : « une aide puis une trahison motivent deux changements » ; aucune transition sur une révision périmée ni sans fait réel ; deux PNJ d'un même groupe peuvent différer selon la réponse.
  - Tests : banc `lupa` ; `test_protocol.py` ; suite en jeu.
  - Preuve : banc `tests/test_relations.py` du 2026-10-13 (8 tests OK : aide puis trahison = deux changements de bout en bout, aucun changement sans fait réel, fait déjà utilisé ou de mauvais sens refusé, révision périmée refusée, deux PNJ d'un même groupe qui diffèrent, écart borné à ±1) ; `RS_Relations.lua` (état privé `RS_State`, clé fiche + personnage, écart -1..+1 sur `API.attitude`, tendance E09-T01, `LK_Hostility` jamais recalculée) ; faits citables : faits numérotés de `LK_Hostility` (`Hostility.facts`, `API.attitudeFacts`), observations `mission_done`/`assault_seen` du PNJ, missions closes ; au plus 8 faits en identifiants courts `f<i>`, clés gardées au serveur ; intention `change_relation` (`dir`, `fact`) au pont ; `context.relation` (libellés) remplace `trust` ; projection `relation = {level, trend, group}` par contact pour E09-T07 ; `test_protocol.py` (`scenario_relation_change`) ; run_all 122/122 ; luacheck 16/0 ; suite `rs.relation` (campagne `solo-rs`) ; conception `relations.md`, `attitude.md`, `protocole-carnet-v2.md`, `api.md` ; essai en jeu du 2026-10-14 : client automatique avec le pont et le vrai modèle (E01-T14) : rs.relation 2/2 (`tools/autoclient/runs/20261014-111501-57d2c373af5b/20261014-091544-solo.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.relation 3/3, dont « help then betrayal: two changes; two npcs of one group differ » (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; passages MP ciblés du 2026-10-15 (commit `66cfd42`) : rs.carnet.leader, rs.factions.accord et rs.relation 7/7 deux fois (`tools/autoclient/runs/20261015-124930-mp-6ae0aaac8167/server/20261015-105140-server.txt`, `tools/autoclient/runs/20261015-125353-mp-3e7e35ef077f/server/20261015-105602-server.txt`) ; solo rs.relation 3/3 deux fois (`tools/autoclient/runs/20261015-125758-446b976efdd7`, `tools/autoclient/runs/20261015-125931-19c7e1f84958`)
  - Reste : —

- [x] **E09-T05** — Accords de faction avec un groupe Living Knox : trêve et alliance (`negotiate`)
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E09-T03, E10-T02, LK06-T01
  - Fichiers : `RS_Factions.lua` (registre des accords, état privé) ; `RS_Carnet_Server.lua` ; pont ; contrat v2 ; crochet `LivingKnox.Hooks.covered` consulté par `LK06-T01`
  - Faire : accord entre un groupe (`grp-<n>`) et une faction de joueurs (identifiant stable d'E09-T03), de portée explicite ; offre issue du serveur, négociation par le LLM dans des conditions fixes, conclusion seulement par le chef du groupe (règle d'E10-T02) et un représentant habilité (mandat d'E09-T03), revalidée au moment de conclure (chef, composition, mandat, révision de l'accord) ; application : l'accord est inscrit dans le registre que le choix de cible consulte (crochet `LivingKnox.Hooks.covered(groupId, playerKey, npcId) -> boolean`, seule implémentation dans `RS_Factions`), puis le serveur vérifie au passage de décision suivant qu'aucun membre ne vise plus un joueur couvert ; l'annonce « applicable » n'est faite qu'après ce constat. Une trêve ne change pas l'attitude (`LK_Hostility`) : elle impose la non-agression dans son périmètre (ADR B08).
  - Accepté si : « trêve décidée pendant un combat : application confirmée avant annonce » ; un membre ordinaire ou un joueur sans mandat ne conclut pas ; deux conclusions incompatibles : une seule appliquée (révision).
  - Tests : banc `lupa` ; suite en jeu.
  - Preuve : banc `tests/test_agreements.py` du 2026-10-12 (7 tests OK : accord trêve/alliance au registre privé avec révision et portée, offre du serveur au seul chef pour un joueur habilité, conclusion revalidée (chef, composition, mandat, équipe, révision), deux conclusions concurrentes : une seule appliquée, crochet `LivingKnox.Hooks.covered` implémenté par `RS_Factions`, accord annoncé « applicable » seulement après constat qu'aucun membre ne vise un joueur couvert, attitude inchangée) ; `factions` 10, `carnet`, `rs_suites` 35, `kahlua` 36 OK ; luacheck 16/0 ; conception `docs/annexes/conception/accords.md` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.factions.accord 2 PASS (trêve conclue puis applicable, deux conclusions sur une révision : seule la première appliquée), rs.factions.mandate 1 PASS (membre sans mandat refusé) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; passages MP ciblés du 2026-10-15 (commit `66cfd42`) : rs.carnet.leader, rs.factions.accord et rs.relation 7/7 deux fois (`tools/autoclient/runs/20261015-124930-mp-6ae0aaac8167/server/20261015-105140-server.txt`, `tools/autoclient/runs/20261015-125353-mp-3e7e35ef077f/server/20261015-105602-server.txt`) ; solo rs.relation 3/3 deux fois (`tools/autoclient/runs/20261015-125758-446b976efdd7`, `tools/autoclient/runs/20261015-125931-19c7e1f84958`)
  - Reste : limites renvoyées à d'autres tâches : pas d'entrée au journal du groupe ni de panneau (E09-T07), pas de rupture (E09-T06) ; alliance = trêve pour l'instant ; raids et vengeances hors écran non couverts.

- [x] **E09-T06** — Défense ciblée et décision sur la trêve
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E09-T05, E04-T06, LK06-T01
  - Fichiers : `RS_Factions.lua` (incidents) ; `RS_Carnet_Server.lua` ; pont
  - Faire : un coup, un tir ou une mort d'un membre attribués à un joueur couvert (`Bodies.onHitZombie`, `Bodies.deathCause`, faits `hit`/`shot`/`kill` vus ou attribuables de `LK_Hostility`) ouvrent un **incident** (identifiant, auteur, victimes, accord, révision ; faits d'un même incident regroupés) ; l'auteur seul perd la protection envers ce groupe pendant l'incident (défense immédiate, sans attendre le LLM, par la règle du choix de cible) ; demande de décision au LLM via la fiche du chef (maintien, réparation dans les catégories du stock autorisées, rupture), validée par le serveur ; pont absent : défense maintenue, aucune rupture automatique ; une riposte d'un membre n'est jamais comptée comme agression initiale ; pas de vengeance de LK11-T05 contre les autres membres de la faction couverte.
  - Accepté si : critères de l'ADR B10 (agresseur et membre innocent présents ensemble, joueur tiers, deux agressions rapprochées, réponse tardive, pont indisponible) ; l'accord change une seule fois par décision valide.
  - Tests : suite en jeu avec deux joueurs ; banc `lupa`.
  - Preuve : banc `tests/test_incidents.py` du 2026-10-13 (6 tests OK), `agreements` 7, `lk_revenge` 27, `carnet` 84, `kahlua` 37 OK : incident ouvert par un coup, un tir ou une mort d'un membre attribué à un joueur couvert par un accord de son équipe (état privé, `inc-<n>`, auteurs, victimes, accord, révision, faits regroupés, doublon témoin/coup sous 2 s compté une fois) ; sources : nouveau fait `memberHit` (`LK_Bodies.onHitZombie`), `npcDied` avec tueur, `assaultSeen` ; défense immédiate : l'auteur seul perd la protection envers ce groupe (crochet `LivingKnox.Hooks.incident`), coéquipiers et tiers non concernés ; riposte d'un membre visé n'ouvre pas d'incident ; décision du chef par `npc_incident` (`RS_Incidents.lua`, 5 s après les faits) : maintien, réparation (catégorie de `LK_Stock`), rupture ; revalidation chef/révisions, application unique ; réponse tardive refusée et redemandée ; sans pont : incident ouvert, défense maintenue, aucune rupture ; décision annoncée à l'équipe (EN/FR) ; pont : genre `npc_incident` ; luacheck 16/0 ; conception `incidents.md`, `accords.md`, `protocole-carnet-v2.md`, `api.md` ; commit commun avec E08-T05 et E08-T06 ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.factions.incident 1/1 avec le pont (`20261013-112218-solo.txt` : décision du chef « repair medical ») ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.factions.incident 3/3, dont « B10 two players: defence against the author only, innocent member covered, third player apart » (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`)
  - Reste : Limites : réparation seulement enregistrée (quantité 5, sans livraison) ; défense sans durée maximale sans pont ; pas d'incident pour les trêves personnelles, un coup sans arme ou une mort sans tueur retenu ; réplique du chef non dite

- [x] **E09-T07** — Panneau de relation dans le carnet
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E09-T04
  - Fichiers : `RS_Notebook.lua` ; `Translate/EN|FR/IG_UI.json`
  - Faire : par contact : niveau et tendance (E09-T04, sinon attitude du groupe par `API.attitude`, projection propre au joueur qui consulte), libellés traduits côté client des identifiants `hostile`, `wary`, `cautious`, `favorable`, `trusting` et `up`, `down`, `stable` (réserve de LK11-T03), accords applicables avec leur portée, derniers faits expliquant l'attitude, sans secret ni conversation privée d'un autre joueur, sans valeur numérique.
  - Accepté si : « deux membres d'une faction, relations différentes » visible et correct.
  - Tests : protocole visuel + suite.
  - Preuve : banc `tests/test_relation_panel.py` du 2026-10-14 (6 tests OK : deux membres d'un même groupe aux relations différentes, projection propre au lecteur, aucun fait d'un autre joueur ni secret ni identifiant, trêve et portée, rendu par le vrai client avec la vraie table anglaise, « inconnu », identifiants inconnus, parité FR/EN) ; `RS_Relations.panel` (niveau, tendance, niveau du groupe, 3 derniers faits {fact, nature, source, day}, accords applicables avec leur portée, `suspended` après incident) remplace `trustKey`/`trendKey`/`agreements` ; section « Ce qu'on pense de vous » de la fiche du contact (`Notebook.relationLines`, dates en mots, aucun nombre) ; 56 clés `IGUI_RS_Rel*` EN/FR, 10 anciennes retirées ; run_all 123/123 ; luacheck 15/0 ; suite `rs.notebook.relation` (campagne `solo-rs`) ; conception `relations.md`, `protocole-carnet-v2.md`, `carnet-implementation-04221.md` ; essai en jeu automatique du 2026-10-14 (client piloté, E01-T14) : rs.notebook.relation 1/1 (`tools/autoclient/runs/20261014-103818-03b2c452d0bf/20261014-083901-solo.txt`, captures du carnet)
  - Reste : essai solo : `RST.run({ suite = "rs.notebook.relation", tags = "world" })` (1 PASS, deux notes qui recopient le panneau des deux PNJ) ; à l'œil : libellés traduits, niveau et tendance sur une ligne, ligne du groupe seulement si elle diffère, faits du jour, encre sombre, aucun débordement.

- [x] **E09-T08** — Réplique gardée quand un changement de relation est refusé
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E09-T04
  - Fichiers : `RS_Carnet_Server.lua` (`reply`), `RS_Relations.lua`, bancs `tests/test_relations.py`
  - Faire : aujourd'hui un `change_relation` refusé par le serveur (fait inventé ou non proposé, déjà utilisé, sens contraire à sa nature, écart déjà à ±1, révision périmée) fait refuser toute la réponse : le joueur voit « pas de réponse ». Garder la réplique du PNJ et ignorer seulement le changement, refus journalisé avec son motif.
  - Décisions (2026-10-14, utilisateur) : garder la réplique, ignorer seulement le changement refusé (option recommandée).
  - Accepté si : au banc, chaque motif de refus laisse la réplique affichée et la relation inchangée ; un changement valide reste appliqué.
  - Tests : banc ; `rs.relation`.
  - Preuve : banc `tests/test_relations.py` du 2026-10-14 (10 tests OK ; `test_refused_change_keeps_the_reply` et `test_stale_revision_refused` en échec sur l'ancien code) : `reply` ne refuse plus la réponse quand `Relations.apply` refuse le changement : réplique gardée (historique, parole, son, acquittement), changement ignoré et journalisé (`relation change of … ignored, reply kept: <motif>`) pour six motifs (aucune liaison, fait non offert, inconnu du PNJ, sens contraire, déjà utilisé, écart à la borne) et la révision de relation périmée ; révision de fiche périmée et réponses mal formées toujours refusées en entier ; run_all 124/124 ; luacheck 15/0 (référence abaissée à 15) ; `relations.md`, `protocole-carnet-v2.md` ; campagne solo automatique du 2026-10-15 (`tools/autoclient/runs/20261015-034525-e24ab0eb77eb/20261015-014609-solo.txt`, 195 tests : 167 PASS, 11 FAIL dont 8 dus à la panne du fournisseur LLM) : rs.relation 2/2 (cadeau réel offert comme fait, aide prétendue sans fait réel jamais acceptée)
  - Reste : —

- [x] **E09-T09** — Effet refusé par le serveur : la réponse du PNJ est gardée, sans l'effet
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E09-T04, E09-T05, E10-T02
  - Fichiers : `RS_Carnet_Server.lua` ; `RS_Relations.lua` ; `RS_Factions.lua` ; `docs/specifications-techniques/protocole-carnet-v2.md` si le contrat change
  - Faire : décision de l'utilisateur du 2026-10-14 (E09-T04, E09-T05, E10-T02) : quand le serveur refuse l'effet proposé par le modèle dans une réponse — changement de relation (E09-T04), conclusion d'accord de faction (E09-T05) ou intention collective périmée (E10-T02) — la réplique du PNJ est quand même dite et ajoutée à l'historique ; seul l'effet refusé n'est pas appliqué (aujourd'hui toute la réponse est refusée et le joueur voit « pas de réponse »). Le refus reste journalisé avec sa raison ; les autres règles de validation sont inchangées.
  - Accepté si : au banc, pour chacun des trois cas : réplique reçue par le joueur, relation, accord ou intention inchangés, ligne de refus au journal ; une réponse dont l'effet est valide est inchangée ; une réponse sans texte reste « pas de réponse ».
  - Tests : banc `lupa` (`tests/test_carnet.py`, `tests/test_protocol.py`) ; suites `rs.relation`, `rs.factions.accord` et `rs.carnet.lk` dans la campagne MP automatique.
  - Preuve : accord (`negotiate`) ou intention collective (offre ou acceptation `supply`) refusés par le serveur : réplique dite et gardée, aucun `NoAnswer`, rien d'appliqué (ni accord, ni mission, ni journal, ni réaction), ligne `ignored, reply kept: <motif>` ; relation déjà ainsi depuis E09-T08 ; format du protocole inchangé (`applied` sans l'effet refusé), `protocole-carnet-v2.md` ; bancs test_carnet 84, test_agreements 7, test_relations 10 OK ; luacheck 15/0 ; commit `2b92a7b`; campagne MP complète du 2026-10-15 (client 2 actif, règle « les tests font foi ») : rs.relation 2/2, rs.factions.accord 1/1, rs.carnet.lk 4/4 (`tools/autoclient/runs/20261015-024734-mp-348bee78d4b7/server/20261015-004928-server.txt`)
  - Reste : `leave_group` périmé et « offer no longer admissible » refusent encore toute la réponse (hors décision)
