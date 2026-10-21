# E00 — Correctifs de la revue du carnet 0.2

**Objectif.** Corriger les défauts trouvés à la relecture du carnet 0.2 (2026-10-03) avant de construire la suite : identité perdue à la reconnexion, mort de joueur ignorée sur serveur dédié, une seule mission par PNJ, charge proportionnelle à la population Bandits.

**Dépend de.** Rien. La validation en jeu de ces corrections est regroupée dans E03.

**Sources.** Revue du code 0.2 ; base de connaissances `multiplayer.md` (ModData d'un joueur sauvegardée sur le serveur seulement ; `OnPlayerDeath` côté client seulement) ; `IsoPlayer.java:6096-6110` ; spécification ADR B06.

## Décisions

- 2026-10-03 — L'utilisateur demande de tout corriger.
- 2026-10-03 — Fiches persistées **au premier contact** (sélection), personnalité **déterministe** dérivée de l'identité Bandits pour respecter « personnalité dès l'apparition » sans stocker toute la population. Écart à confirmer formellement : E00-T06.
- 2026-10-08 — Bandits! abandonné (`E17-T01`) : les correctifs déjà codés restent ; leur validation en jeu se fera avec les PNJ Living Knox (`E17-T03`). `E00-T06` abandonnée ; `E00-T07` attend `E17-T02`.

## Hors périmètre

Plafond de population Bandits (E02), validation en jeu (E03).

## Tâches

- [x] **E00-T01** — Identité de personnage écrite dans la ModData du joueur côté serveur
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `media/lua/server/RS_Carnet_Server.lua` (`identity`, `usable`, `ownerOf`) ; `tests/test_carnet.py` (`Simulation.saved_players`, `player_data`)
  - Faire : le serveur lit et écrit `RS_CarnetCharacter` dans sa copie de la ModData du joueur (seule sauvegardée en MP) ; la valeur du client n'est qu'un repli vérifié (même compte, même slot, non retirée).
  - Accepté si : reconnexion sans ModData client = même personnage, notes et engagements ; revendication d'un autre compte refusée ; redémarrage serveur conservé.
  - Tests : `test_reconnect_without_client_modData_keeps_identity`, `test_persistence_clock_reconnect_and_new_character` (banc corrigé : ModData serveur persistée, ModData client perdue) ; en jeu : E03-T04.
  - Preuve : tests `lupa` du 2026-10-03 (17/17 `test_carnet.py`, 3/3 `test_protocol.py`), commit `120033f` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.identity 6/6 (2 joueurs en ligne, 2 liés) (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; phases réelles du 2026-10-15 6 h 07 (reconnexion des clients puis `quit` et relance du serveur sur la même partie, `tools/autoclient/runs/20261015-060712-mp-1a0abb0c888e`) : rs.identity.after-reconnect 3 PASS (même monde, même identité, notes et engagements) et rs.identity.after-restart PASS (même monde, mêmes identités) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.claim 1/1 (revendication de l'identité d'un autre compte par un vrai client refusée), rs.identity 6/6 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : rs.identity.after-reconnect 3 PASS + 1 SKIP (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093730-server.txt`), rs.identity.after-restart 3 PASS + 1 SKIP (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`) ; chrono de mission d'un vrai PNJ Living Knox (commit `76f4692`) : solo rs.identity 7/7 (`tools/autoclient/runs/20261015-133255-2f6bf7bfcb20/20261015-113348-solo.txt`) ; MP `--phases reconnect,restart --server-suite rs.identity --restart-pause 120` sans SKIP : après reconnexion 4/4, après redémarrage 4/4 (chrono arrêté pendant 150 s d'arrêt), `tools/autoclient/runs/20261015-134033-mp-c6559a321d3e` (`server/20261015-114241-server.txt`, `server/20261015-114834-server.txt`, preuve de la reconnexion dans `server/Logs-2026-10-15_13-40_DebugLog-server.txt`)
  - Reste : —

- [x] **E00-T02** — Retrait de l'identité à la mort par `OnCharacterDeath`
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E00-T01
  - Fichiers : `RS_Carnet_Server.lua` (`Server.characterDeath`) ; `tests/test_carnet.py` (`instanceof` IsoPlayer)
  - Faire : remplacer `OnPlayerDeath` (jamais déclenché sur serveur dédié) par `OnCharacterDeath`, filtré par `instanceof(…, 'IsoPlayer')`, propriétaire vérifié, clé de ModData effacée.
  - Accepté si : un zombie ou un autre compte ne retire rien ; le personnage mort ne peut plus être revendiqué ; un nouveau personnage reçoit une nouvelle identité.
  - Tests : `test_persistence_clock_reconnect_and_new_character` ; en jeu : E03-T04.
  - Preuve : tests `lupa` du 2026-10-03, commit `120033f` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.death 2/2, vraie mort du client 2 sur le serveur dédié (`OnCharacterDeath`, identité retirée, nouveau personnage, ancienne identité jamais revendiquée, missions de l'ancienne identité non reprises) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; rs.death 2/2 en MP : mission partagée d'un vrai PNJ toujours `active` pour le demandeur après la mort de rs_mp2 puis après son nouveau personnage (`tools/autoclient/runs/20261015-134912-mp-6a36ce8817b0/server/20261015-115114-server.txt`, commit `76f4692`)
  - Reste : —

- [x] **E00-T03** — Plusieurs missions par PNJ, expiration des offres et délai entre deux offres
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `RS_Missions.lua` (`create`, `release`, `advance`, `prune`) ; `RS_Config.lua` (`OFFER_TTL_MS`, `OFFER_COOLDOWN_MS`, `MISSION_RETENTION_MS`, `UNCLAIMED_RETENTION_MS`) ; `RS_Carnet_Server.lua` (`offerCatalog`) ; traductions `IGUI_RS_State_expired`
  - Faire : identifiant de mission unique par PNJ (`-deliveryN`), libération du PNJ à la clôture, offre non acceptée expirée après 1 h de fonctionnement serveur, nouvelle offre après 30 min réelles, missions closes purgées après 24 h (7 jours si lot non retiré).
  - Accepté si : un PNJ propose à nouveau après le délai ; une offre ignorée ne bloque plus le PNJ ; les missions closes disparaissent des carnets après rétention.
  - Tests : `test_offer_expiry_cooldown_and_second_mission`.
  - Preuve : tests `lupa` du 2026-10-03, commit `120033f` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.missions.solo « unanswered offer expires and the notebook shows it expired » PASS (`20261013-202155-solo.txt`)
  - Reste : affichage de l'état « expirée » dans le carnet en jeu (E03-T01).

- [x] **E00-T04** — Charge bornée : fiches au contact, purge, publication sur changement, sauvegarde conditionnelle
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `RS_Carnet_Server.lua` (`find`, `ensure`, `scan`, `prune`, `tick`, `clockRunning`) ; `RS_State.lua` (`dirty`) ; `RS_Client.lua` (cadence `SNAPSHOT_OPEN_MS` / `SNAPSHOT_CLOSED_MS`) ; `RS_Config.lua`
  - Faire : plus de fiche pour chaque spawn ni de crochets `TransmitBanditCluster` / `Virtual` ; enrichissement LLM seulement après contact ; purge des fiches sans contact et sans corps chargé depuis 1 h ; plus d'envoi de l'état complet chaque seconde à tous ; sauvegarde seulement si l'état a changé ou si un chrono tourne.
  - Accepté si : 30 bandits chargés sans contact = 0 fiche et 0 appel LLM ; serveur inactif = aucun envoi d'état ; fiche contactée jamais purgée.
  - Tests : `test_lazy_fiches_enrichment_and_pruning`, `test_no_periodic_snapshot_broadcast`.
  - Preuve : tests `lupa` du 2026-10-03, commit `120033f` ; suite en jeu écrite le 2026-10-15 (`rs.carnet.load`/`rs.worldradio`/`rs.radio`/`rs.observations`/`rs.factions.mandate` selon la tâche, étapes client `RST_PeerChecksRadio.lua`), banc `tests/test_rs_mp_suites.py` 29 OK (échoue sur les défauts injectés), commit `446a39d` ; suite corrigée (`0d1b6fa` : surcharges de `sendServerCommand` respectées, seules les sauvegardes d'un état inchangé comptent) ; campagne MP complète du 2026-10-15 4 h 08 (client 2 actif) : rs.carnet.load 3/3 (`tools/autoclient/runs/20261015-040851-mp-5c884ff76aeb/server/20261015-021039-server.txt`)
  - Reste : —

- [x] **E00-T05** — Personnalité déterministe dès l'apparition
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E00-T04
  - Fichiers : `media/lua/shared/RadioSurvivor/RS_Bandits.lua` (`B.personality`) ; `RS_Carnet_Server.lua` (`ensure`)
  - Faire : personnalité tirée par Park-Miller d'un hachage de la signature Bandits (identifiant, naissance, coordonnées, nom, `bid`) ; identique quel que soit le moment du premier contact.
  - Accepté si : deux calculs donnent la même personnalité ; la fiche créée au contact la reprend.
  - Tests : `test_lazy_fiches_enrichment_and_pruning` (comparaison).
  - Preuve : tests `lupa` du 2026-10-03, commit `120033f`
  - Reste : —

- [ ] **E00-T06** — Confirmer l'écart à ADR B06 (fiche persistée au contact, enrichissement au contact)
  - État : `abandonné`
  - Cible : `hors jeu`
  - Dépend de : E00-T05
  - Fichiers : `docs/annexes/recherches/bandits-llm-specifications.md` (ADR B06, critères de validation), ce fichier
  - Faire : poser les questions, puis amender la spécification selon la réponse.
  - Questions : (1) La personnalité déterministe sans fiche stockée satisfait-elle « personnalité dès l'apparition » ? Options : oui, garder [recommandé] / non, stocker une fiche à chaque spawn malgré la charge / stocker seulement pour les PNJ amicaux. (2) Quand enrichir par le LLM ? Options : au premier contact [recommandé] / dès l'apparition dans la limite de 12 par heure / jamais automatiquement, seulement à la demande d'un dialogue.
  - Accepté si : décision consignée ici et dans la spécification ; si elle diffère de l'implémentation, une tâche de correction est ajoutée.
  - Tests : —
  - Preuve : —
  - Reste : Bandits! abandonné le 2026-10-08 (`E17-T01`) : les PNJ Living Knox ont une identité et une fiche persistantes par construction (`LK08-T01`) ; le moment de l'enrichissement LLM se décidera avec `E17-T03` et `LK10-T03`.

- [x] **E00-T07** — Documentation du carnet à jour après les correctifs
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E17-T02
  - Fichiers : `README.md`, `docs/annexes/conception/carnet-implementation-04221.md`, `docs/annexes/tests/carnet-validation-04221.md`
  - Faire : après le retrait de Bandits! (`E17-T02`) : décrire identité serveur, mort, missions répétables, purge, cadence d'envoi et fournisseur de PNJ ; retirer les phrases devenues fausses (Bandits!, Ctrl+G sur un bandit, fiche créée avant transmission).
  - Accepté si : aucune phrase des documents ne contredit le code ; les limites restantes sont listées.
  - Tests : relecture croisée avec le code.
  - Preuve : `README.md`, `docs/annexes/conception/carnet-implementation-04221.md`, `docs/annexes/tests/carnet-validation-04221.md` relus contre le code le 2026-10-08 (identité serveur, mort par `OnCharacterDeath`, missions répétables, purge, sauvegarde conditionnelle, cadence 3 s / 30 s, interface `RS_NPCProvider`) ; phrases fausses retirées avec leur preuve ; limites listées ; occurrences « Bandit » restantes historiques et datées ; `tests/run_all.py` 10/10 ; E00-T12 : commit `cb5c461`
  - Reste : —

- [x] **E00-T08** — `RS_Codec.hex` réversible pour tout texte (unités UTF-16 au-delà de U+00FF)
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `media/lua/shared/RadioSurvivor/RS_Codec.lua` ; `tests/test_carnet.py` ou `tests/test_protocol.py` ; suite `rs.codec` (mod de dev)
  - Faire : en Kahlua, une chaîne est en unités UTF-16 ; `string.format('%02x', string.byte(c))` donne 3 ou 4 chiffres au-delà de U+00FF (« ’ », « € », « œ ») et `unhex` refuse ou corrompt le texte : l'état privé relu échoue au contrôle de somme (`RS_State.lua:19-20`). Encoder les caractères en UTF-8 avant l'hexadécimal (et décoder au retour), sans opérateurs binaires, en gardant le comportement octet à octet de `lupa`.
  - Accepté si : aller-retour exact d'un texte contenant « é ’ € œ » dans la VM Kahlua du jeu (suite `rs.codec`) et sous `lupa` ; ancien état sauvegardé sans caractère non ASCII toujours relu.
  - Tests : `rs.codec` (Kahlua) ; banc `lupa`.
  - Preuve : `RS_Codec.lua` : conversions `toUtf8`/`fromUtf8` sans opérateurs binaires, détection du runtime par `#"\195\169" == 1`, couche octets (`encodeBytes`, `hexBytes`, `checksumBytes`) utilisée par `RS_State` et `RS_Transport`, tolérance Latin-1 des anciens états, chemin du fichier d'état inchangé ; `test_carnet.py` 24/24 (ancien code recopié : état ASCII identique octet pour octet, ancien état Latin-1 relu), `test_kahlua.py` 10/10 dans la VM Kahlua du jeu (`rs.codec` 15/15, U+00FF et hors BMP), serveur dédié de test le 2026-10-08 `-Filters "rs.codec"` : `RST-RESULT ok=true total=15 pass=15` ; `tests/run_all.py` 10/10 ; E00-T07 : commit `a76b0a2`
  - Reste : un ancien état contenant un caractère au-delà de U+00FF était déjà illisible et le reste

- [x] **E00-T09** — Texte accentué envoyé au pont Python en UTF-8
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E00-T08
  - Fichiers : `RS_Codec.lua` ; `bridge/npc_protocol.py` ; `docs/specifications-techniques/protocole-carnet-v2.md` si le contrat change
  - Faire : `hex` produit du Latin-1 entre U+0080 et U+00FF (« é » → `e9`) alors que le pont décode en UTF-8 strict (`bridge/npc_protocol.py:77`) : une requête accentuée serait refusée. Aligner les deux côtés sur UTF-8 (dépend du choix d'`E00-T08`).
  - Accepté si : un message accentué fait l'aller-retour Lua → pont → Lua ; `test_protocol.py` couvre le cas.
  - Tests : `test_protocol.py`.
  - Preuve : `test_protocol.py` 4/4 dont `scenario_accented_npc_exchange` (vrai `RS_Transport`, pont `--offline`, « ’ € œ » et U+1F4FB, branche lupa et branche UTF-16 forcée ; contre-test : l'ancien comportement fait lever `UnicodeDecodeError` au pont) ; VM Kahlua du jeu : charge accentuée encodée par Kahlua décodée par `npc_protocol.decode`, réponse Python relue exactement ; borne de 800 octets comptée en UTF-8 (`RS_Carnet_Server.lua:252`) ; `docs/specifications-techniques/protocole-carnet-v2.md` à jour ; pont Python inchangé ; E00-T08 : commit `2952715`
  - Reste : borne de 800 octets confirmée statiquement seulement ; écart préexistant du contrat sur les identifiants (`.` et `:` refusés par `npc_protocol.ID`)

- [x] **E00-T10** — Récompense de mission créée par `instanceItem` (`InventoryItemFactory` non exposé)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Missions.lua:158` ; `tests/test_carnet.py`
  - Faire : `InventoryItemFactory` n'est pas exposé à Lua en 42.21 (aucune exposition dans `LuaManager`, seule mention vanilla en commentaire `server/Traps/STrapGlobalObject.lua:247`) : `M.claim` lèverait une erreur. Utiliser la globale `instanceItem(type)` (`LuaManager.java:4669-4676`).
  - Accepté si : la récompense est créée et ajoutée à l'inventaire en solo ; la suite `rs.env` ne signale plus `InventoryItemFactory`.
  - Tests : banc `lupa` ; suite `rs.env` ; protocole solo de livraison.
  - Preuve : `RS_Missions.lua:158` : `instanceItem(m.rewardType)` (renvoie `nil` pour un type inconnu, `LuaManager.java:4674-4677`, `InventoryItemFactory.java:104-107`) ; doublure `InventoryItemFactory` retirée du banc : l'ancien appel fait échouer 2 tests comme en jeu ; `tests/run_all.py` 10/10 ; serveur dédié de test le 2026-10-08 `-Filters "rs.env"` : `RST-RESULT ok=true total=7 pass=6 skip=1` ; E00-T09 : commit `d4e560b` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.missions.solo « reward lot claimed into the real inventory » PASS (`20261013-202155-solo.txt`)
  - Reste : réclamer une vraie récompense en jeu (lot créé dans l'inventaire) : impossible tant qu'aucun fournisseur de PNJ ne propose de mission (`E17-T03`)

- [x] **E00-T11** — Carnet qui ne s'ouvre pas : `setMaxTextLength` appelé avant `addChild`
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `media/lua/client/RadioSurvivor/RS_Notebook.lua:73` ; doublure `ISTextEntryBox` de `tests/test_carnet.py` (échouer sans `javaObject`, comme le jeu)
  - Faire : appeler `setMaxTextLength(2000)` après `self:addChild(self.note)` ; rendre la doublure fidèle (base `ui-windows.md`, réglages d'un `ISTextEntryBox`).
  - Accepté si : le carnet s'ouvre en solo sans erreur (bouton de la barre latérale) ; le banc échoue avec l'ancien ordre et passe avec le nouveau.
  - Tests : `test_carnet.py` ; protocole solo : ouvrir le carnet.
  - Preuve : `RS_Notebook.lua:73` : `addChild` avant `setMaxTextLength` ; doublures ISUI fidèles au vanilla 42.21 dans `test_carnet.py` (`javaObject` créé par `instantiate`, déclenché par `addChild`/`addToUIManager`/`setVisible`) ; nouveau test `test_notebook_window_opens_with_vanilla_instantiation_order` : échoue avec l'ancien ordre (`attempted index: setMaxTextLength of non-table: null`), passe avec le nouveau ; audit des autres fichiers client sans autre cas ; `tests/run_all.py` 10/10 le 2026-10-08 ; LK01-T03 : commit `743327a` ; **en jeu solo le 2026-10-08** après redémarrage : le bouton de la barre latérale ouvre le carnet sans erreur, onglets affichés (retour de l'utilisateur)
  - Reste : texte du panneau blanc : `E00-T12`

- [x] **E00-T12** — Texte du carnet blanc et illisible (`ISRichTextPanel` ignore `textR/G/B`)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E00-T11
  - Fichiers : `media/lua/client/RadioSurvivor/RS_Notebook.lua` (panneau `detail`, ligne 196) ; `tests/test_carnet.py`
  - Faire : préfixer le texte riche du panneau de détail par une balise `<RGB:0.16,0.17,0.14>` (couleur encre déjà choisie dans le code) ; vérifier les autres textes du carnet dessinés en blanc sur le fond clair.
  - Accepté si : texte du carnet lisible (encre sombre) en solo ; le banc vérifie la présence de la balise en tête du texte.
  - Tests : `test_carnet.py` ; protocole solo : ouvrir le carnet.
  - Preuve : `RS_Notebook.lua:196` : texte du panneau de détail préfixé par `<RGB:0.16,0.17,0.14>` (aucune autre balise ne rétablit le blanc, `clean()` retire les balises des contenus) ; `test_carnet.py` vérifie la balise à l'ouverture et sur chaque onglet ; autres textes du carnet vérifiés lisibles ; `tests/run_all.py` 10/10 le 2026-10-08 ; E00-T11 : commit `75cdf89` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.notebook.ink 1/1 (encre sombre sur les 5 onglets, contrôlée par script) (`20261013-202155-solo.txt`)
  - Reste : en jeu solo après redémarrage : texte sombre sur les trois onglets ; champ de note : texte blanc sur fond gris (fond vanilla noir à 50 %), lisible mais peu contrasté, à juger en jeu

- [x] **E00-T13** — État du mod effacé à chaque redémarrage d'un serveur dédié
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E01-T17
  - Fichiers : `RS_WorldStart.lua` (nouveau), `LK_Server.lua`, `RS_Carnet_Server.lua`
  - Faire : constaté le 2026-10-15 par le premier passage réel des phases E01-T17 (`tools/autoclient/runs/20261015-043927-mp-e129a29e832d`) : après `quit` (sauvegarde complète) et relance du serveur sur la même partie, Living Knox (groupes, attitudes, registre) et le carnet repartaient d'un « monde neuf ». Cause (Java 42.21.0) : l'argument d'`OnInitGlobalModData` vient de `WorldDictionary.isIsNewGame()` (`GlobalModData.java:56`), vrai au départ (`WorldDictionary.java:526`) et remis à faux seulement par `GameLoadingState.java:253` (solo et client) : toujours vrai sur un serveur dédié. Le signal de monde neuf vient désormais du second argument d'`OnLoadRadioScripts` (`ZomboidRadio.java:246`, levé juste avant `GlobalModData.init`, `IsoWorld.java:1905-1907`), avec repli journalisé.
  - Accepté si : au banc, un redémarrage de serveur dédié garde registre et état du carnet ; en campagne, phases `restart` vertes (`rs.identity.after-restart`, `lk.homes.after-restart`, `lk.leave.after-restart`, `lk.walls.after-restart`).
  - Tests : `test_lk_groups.py` (`test_dedicated_server_restart_keeps_the_registry`), `test_carnet.py` (`test_dedicated_server_restart_keeps_the_world`) ; phases E01-T17.
  - Preuve : bancs du 2026-10-15 (les deux tests échouent sans le correctif) ; run_all 130/130 ; luacheck 15/0 ; base `multiplayer.md` (liste de contrôle MP, point 8, corrigé) ; commit `d0ca2b8` ; passage réel des phases le 2026-10-15 5 h 16 (`tools/autoclient/runs/20261015-051633-mp-f2739c903f59`) : après `quit` et relance, plus aucune ligne « new world, empty » (registres relus), lk.leave.after-restart et lk.walls.after-restart PASS, rs.mission.recover.after-restart PASS ; phases réelles du 2026-10-15 6 h 07 (reconnexion des clients puis `quit` et relance du serveur sur la même partie, `tools/autoclient/runs/20261015-060712-mp-1a0abb0c888e`) : rs.identity.after-restart « new session of the same world » et « same identity for each account » PASS, lk.homes, lk.leave, lk.walls, rs.mission.recover et rs.rescue.missed .after-restart PASS
  - Reste : —
