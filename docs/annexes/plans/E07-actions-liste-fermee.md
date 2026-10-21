# E07 — Actions en liste fermée pour les voix radio

**Objectif.** Les voix radio ne renvoient plus seulement du texte : le pont rend une réponse structurée (`say` + `actions`), le serveur vérifie chaque action contre la fiche du personnage et le catalogue, puis l'exécute ou la refuse, avec un journal admin (note de travail §02).

**Dépend de.** E05-T03 (fiches et routage par voix).

**Sources.** Note de travail §02 (règles, catalogue de départ) ; contrat v2 et `npc_protocol.bounded_reply` (modèle déjà appliqué aux PNJ Bandits!) ; base `world-map.md` (symboles persistants par `UIWorldMap` caché, `setKnownInSquares` par blocs de 32 en MP) ; base `quest-building-blocks.md`.

## Décisions

- 2026-10-18 — **E07-T10** (demande de l'utilisateur : « quelquefois un Radio Survivor peut donner des fréquences d'autres Radio Survivor, mais exceptionnel, sur négociation, confiance forte ou persuasion ») : confirmé par défaut : lien = 4 réponses sur 2 jours de jeu ou bonne réputation ; 7 jours par voix et personnage, 3 jours par personnage ; seulement une voix inconnue du carnet ; consigne « exceptionnel » au modèle ; Walt (Darlene, Night Owl) et Gus (Cody, Walt) s'ajoutent à Darlene et Cody ; Night Owl (chroniqueur) et les Whitaker ne partagent pas.

- Acquises : le LLM propose, le serveur décide ; liste d'actions autorisées par fiche ; aucun secret dans le prompt (le serveur complète les valeurs exactes) ; actions tracées ; sans pont, rien ne se passe.

## Hors périmètre

`place_cache`, `place_scene`, `start_mission` (E11, E12) ; `propose_trade` (E13) ; actions des PNJ Bandits! (E08 à E10).

## Tâches

- [x] **E07-T01** — Réponse structurée des voix et validation des actions
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/specifications-techniques/protocole-carnet-v2.md` (ou v3) ; `bridge/radio_bridge.py` ; `RadioSurvivor_Server.lua` ; `media/lua/server/RadioSurvivor/RS_Actions.lua`
  - Faire : la réponse radio devient `{say = {...}, actions = {...}}` encodée en RSV2 comme les PNJ ; validation côté pont (types, bornes) puis côté serveur (fiche, budgets par jour et par voix, distances, délai propre à chaque action) ; refus motivé ; compatibilité avec les anciennes réponses en lignes.
  - Accepté si : une action hors catalogue ou hors fiche est refusée et journalisée ; `say` seul fonctionne comme aujourd'hui.
  - Tests : `test_protocol.py` étendu (actions valides, invalides, budget épuisé, pont absent).
  - Preuve : `RS_Actions.lua` (registre `Actions.register`, `Actions.decide` : `unknown_action`, `not_allowed`, `not_available`, `bad_params`, `too_far`, `budget` par jour de jeu, `cooldown`, `too_many` au-delà de 3 ; une ligne console par décision ; compteurs dans l'état privé `RS_State`, en mémoire si l'état n'est pas chargé) ; `RadioSurvivor_Server.lua` lit `payload=` `radio_reply` en plus de `line=` ; pont : mode structuré seulement si la fiche autorise une action autre que `say` (`bounded_actions`, JSON invalide → `say` seul, secret dans un paramètre → parasites) ; `test_protocol.py` 12/12 dont `scenario_structured_bridge` et `scenario_structured_server` ; `tests/run_all.py` 27/27 le 2026-10-10, luacheck 18/0 (référence), `check_case.py` PASS ; `docs/specifications-techniques/protocole-carnet-v2.md` à jour ; E06-T06 et suivants : commit `05ad674`
  - Reste : aucun exécuteur réel (E07-T03..T06, E11, E12, E13) ; journal fichier admin (E07-T02) ; ⚠ non exécuté dans la VM Kahlua ; actions jugées même si la diffusion est abandonnée ensuite (à trancher par les tâches d'exécuteurs)

- [x] **E07-T02** — Journal admin des actions
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E07-T01
  - Fichiers : `RS_Actions.lua` ; fichier `batman_RadioSurvivor/actions-<partie>.log`
  - Faire : une ligne par action proposée : date réelle et de jeu, voix, appelant, action, paramètres, décision et raison ; rotation bornée.
  - Accepté si : le journal permet de reconstituer chaque décision ; aucune donnée secrète en clair au-delà de ce que l'admin possède déjà.
  - Tests : banc `lupa`.
  - Preuve : `RS_ActionLog.lua` : une ligne par action proposée (8 champs séparés par tabulation : date réelle UTC, date de jeu, voix, appelant, action, paramètres triés et encodés `%XX`, décision, raison ; `too_many` compris) dans `Zomboid/Lua/batman_RadioSurvivor/actions-<hex partie>.log`, en-tête versionné ; rotation à 2000 lignes ou 262 144 caractères vers `.1.log` (compteurs en mémoire, une seule relecture au premier usage) ; ni fiche, ni secret, ni texte `say` ; doublure `getFileWriter` fidèle au Java (extensions, troncature, ajout) ; `test_protocol.py` 12/12 (`check_action_log`) ; `tests/run_all.py` 27/27 le 2026-10-10, luacheck 18/0, `check_case.py` PASS ; format dans `docs/specifications-techniques/protocole-carnet-v2.md`, `README.md` ; E07-T01 : commit `09a6cb5`
  - Reste : ⚠ non exécuté dans la VM Kahlua (`gsub` à fonction et `%c`, `string.format("%%%02X")`, `os.date("!…")`) ; seuil de taille compté en unités UTF-16 en jeu

- [x] **E07-T03** — Action `remember` : mémoire bornée par appelant
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E07-T01
  - Fichiers : `bridge/` (mémoire), `RS_Actions.lua`
  - Faire : la voix retient un fait court sur l'appelant (nom de personnage, lieu déclaré, service rendu) ; taille bornée par voix et par appelant ; injecté dans les prompts suivants comme « souvenir », jamais comme preuve.
  - Accepté si : bornes respectées ; un fait ne crée aucun effet de jeu.
  - Tests : tests Python.
  - Preuve : `RS_Memory.lua` : exécuteur `remember` (paramètre `fact` seul, nettoyé, 64 caractères), mémoire dans l'état privé `RS_State` par voix + appelant + personnage, 5 faits par appelant (plus ancien évincé, doublon rafraîchi), 50 appelants par voix, purge à la mort (`characterDeath`) et personnages retirés filtrés ; champ de demande `memory=` (RSV2 hex) ; pont : section « souvenirs non vérifiés » injectée dès qu'il y en a, `safe_text`, fait citant un secret retiré, prompt inchangé sans souvenir ; `test_protocol.py` 14/14 (`scenario_memory_bridge`, `scenario_memory_server`) ; `tests/run_all.py` 27/27 le 2026-10-10, luacheck 18/0, `check_case.py` PASS ; `docs/specifications-techniques/protocole-carnet-v2.md`, `docs/specifications-techniques/persona-format.md` ; LK04-T01 : commit `7a34e3f`
  - Reste : ⚠ non exécuté dans la VM Kahlua (`string.lower` non ASCII, motif `[%c<>%[%]]`) ; sans carnet lié (`cid` absent) un nouveau personnage solo hérite des souvenirs ; budget `remember` par voix et non par appelant

- [ ] **E07-T04** — Action `mark_map` : repère sur la carte de l'appelant
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : E07-T01, E01-T05
  - Fichiers : `media/lua/client/RadioSurvivor/RS_MapActions.lua` ; `RS_Actions.lua`
  - Faire : la fiche liste les lieux connus du personnage (coordonnées côté serveur) ; le LLM choisit un lieu par son identifiant ; le serveur envoie le repère au seul appelant, qui l'ajoute par l'API de symboles de carte ; nombre par jour borné.
  - Accepté si : un lieu non listé est refusé ; le repère persiste après reconnexion.
  - Tests : suite en jeu `rs.actions.map`.
  - Preuve : fiches : clé répétable `place=<id> <x>,<y>,<z> <libellé>` (12 lieux, mêmes erreurs dans `persona_store.py` et `RS_Persona.lua`) ; pont : `mark_map` proposée seulement si la fiche a des lieux, prompt avec identifiants et libellés sans coordonnées, identifiant inconnu retiré ; serveur `RS_MapMarks.lua` : lieu de la fiche obligatoire, `budget.mark_map`, délai 30 s par voix, envoi au seul appelant (`Const.toClient`) ; client `RS_MapActions.lua` : symbole `Target` + libellé traduit sur la carte du monde par une `UIWorldMap` cachée, sans doublon ; persistance = symboles du joueur dans `map_symbols.bin` côté client (`WorldMapSymbols.java:240-259`, `MapItem.java:47-66`) ; `test_protocol.py` 22/22 (dont 4 `scenario_map_*`), `test_personas.py` 20/20, VM Kahlua 27/27 ; suites en jeu `rs.actions.map`, `.before`, `.after-reload` ; `tests/run_all.py` 37/37 le 2026-10-10, luacheck 17/0 et 0, `check_case.py` PASS ; base `world-map.md` ; E05/LK : commit `42c1eb6` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : repère de récompense reçu sur la carte ; `rs.actions.map` 3/3 (`20261011-135206-solo.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.actions.map 3/3 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`)
  - Reste : repère gardé après une reconnexion non prouvé en MP : les suites `rs.actions.map.before`/`.after-reload` ne sont pas dans la campagne `mp-persist`

- [x] **E07-T05** — Action `reveal_area` : révéler un quartier
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E07-T04
  - Fichiers : `RS_MapActions.lua`
  - Faire : `setKnownInSquares` sur une zone plafonnée, pour l'appelant seulement, en respectant les blocs de 32 cases.
  - Accepté si : surface plafonnée respectée ; seul l'appelant voit la zone révélée.
  - Tests : suite en jeu.
  - Preuve : `RS_MapMarks.lua` : exécuteur `reveal_area` (lieu `place=` de la fiche, `budget.reveal_area`, délai 60 s par voix, `off_map` refusé) ; carré de 5 blocs de 32 cases (160 cases de côté au plus, `Const.MAP_REVEAL_MAX_SIDE`) centré sur le bloc du lieu, rogné aux bornes de la carte ; en MP le serveur inscrit la zone dans la carte du compte de l'appelant (`WorldMapVisitedServer:setKnownInSquares`, non diffusé : `WorldMapVisitedServer.java:69-75`, sauvegardé par compte : `GameServer.java:2871`) puis `map_reveal` au seul appelant ; client `RS_MapActions.lua` : `WorldMapVisited:setKnownInSquares` (bord exclu passé moins 1 à cause de l'arrondi vanilla `coordToUnit`, vérifié au bytecode) ; ligne d'historique `reveal` « Quartier révélé : <libellé> » ; pont : `reveal_area` dans `EXECUTABLE_ACTIONS` ; `test_protocol.py` 27/27 (5 `scenario_reveal_*`), `test_radio_history.py` 30/30, VM Kahlua 28/28 ; suites en jeu `rs.actions.reveal`, `.before`, `.after-reload` ; `tests/run_all.py` 37/37 le 2026-10-10, luacheck 17/0 et 0 ; base `world-map.md` (bornes, persistance et diffusion) ; LK03-T01 : commit `be37e34` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : `rs.actions.reveal` 2/2 (`20261011-132656-solo.txt`) ; demande à Walt perdue par un JSON illisible du LLM (E07-T09) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.actions.reveal 2/2 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; étape map.known du client 2 (#26, #30 « 49 block(s) as expected » : zone révélée absente de la carte de l'autre client) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`)
  - Reste : Limite : JSON du LLM parfois illisible (E07-T09)

- [x] **E07-T06** — Action `persona_state` : moral, réserves, lieu
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E07-T01
  - Fichiers : `RS_Actions.lua` ; fiches (état dynamique séparé du fichier édité par l'admin)
  - Faire : champs bornés modifiables par la voix elle-même, stockés dans l'état privé, jamais dans la fiche éditée par l'admin.
  - Accepté si : bornes et pas maximal par appel respectés.
  - Tests : banc `lupa`.
  - Preuve : `RS_PersonaState.lua` : exécuteur `persona_state` (`morale` et `supplies` entiers 0..10, défaut 5, pas ramené à ±2 par appel puis aux bornes ; `place` texte nettoyé de 40 caractères, sans effet sur `coords` ; au moins un champ, aucun autre, sinon `bad_params`) ; état dans l'état privé `RS_State` (`S.data.personaState[voix]`), jamais dans la fiche ; champ de demande `persona=` dès le premier changement, injecté par le pont (« Your current state »), `place` citant un secret retiré ; `test_protocol.py` 16/16 (`scenario_persona_bridge`, `scenario_persona_server` : bornes, pas, budget, isolation, persistance, fiche inchangée sur disque) ; `tests/run_all.py` 27/27 le 2026-10-10, luacheck 18/0, `check_case.py` PASS ; `docs/specifications-techniques/protocole-carnet-v2.md`, `docs/specifications-techniques/persona-format.md` ; LK07-T01 : commit `9ddf0d9`
  - Reste : ⚠ non exécuté dans la VM Kahlua (nombres peut-être écrits `9.0` au journal) ; trois appels dans une réponse = ±6 au plus ; le prompt ne décrit pas encore les paramètres des actions (tâche E07-T07)

- [x] **E07-T07** — Paramètres des actions décrits dans le prompt
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E07-T03, E07-T06
  - Fichiers : `bridge/radio_bridge.py` ; `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : la consigne de format du mode structuré (`actions_prompt`) décrit, pour chaque action autorisée **et dotée d'un exécuteur**, ses paramètres et bornes (`remember` : `fact` ; `persona_state` : `morale`, `supplies`, `place`) ; les actions sans exécuteur ne sont plus proposées au LLM (elles seraient refusées `not_available`) ; si la fiche n'autorise alors que `say`, mode texte. Découverte d'E07-T06 : sans cette description, le LLM ignore les noms de paramètres.
  - Accepté si : le prompt d'une fiche `remember,persona_state` décrit leurs paramètres ; une fiche qui n'autorise que des actions sans exécuteur reste en mode texte ; aucune fiche `say` seule ne change.
  - Tests : `test_protocol.py` étendu.
  - Preuve : `radio_bridge.py` : table `EXECUTABLE_ACTIONS` (`remember` : `fact` ; `persona_state` : `morale`, `supplies`, `place`, bornes tirées des constantes) et `offered_actions` : seules les actions autorisées **et** dotées d'un exécuteur sont proposées au LLM, avec description et exemple JSON ; fiche sans action exécutable = mode texte, prompt identique à `say` seul ; `bounded_actions` retire une action sans exécuteur ; `test_protocol.py` 17/17 (`scenario_action_descriptions` : noms identiques aux exécuteurs enregistrés dans le banc, bornes = `RadioSurvivor_Const`) ; `tests/run_all.py` 27/27 le 2026-10-10, luacheck 18/0, `check_case.py` PASS ; `docs/specifications-techniques/protocole-carnet-v2.md` ; E07-T06 : commit `42993b4`
  - Reste : à essayer avec un vrai LLM (fiche `say,remember,persona_state`) : remplissage effectif des paramètres ; table du pont à tenir à jour à chaque nouvel exécuteur (le test détecte l’écart)

- [x] **E07-T08** — Repère reçu noté dans le carnet au lieu d'un texte flottant
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E07-T04
  - Fichiers : `media/lua/client/RadioSurvivor/RS_MapActions.lua` ; historique radio du carnet (`RS_RadioLog.lua`, onglet Radio)
  - Faire : décision de l'utilisateur du 2026-10-10 : retirer le texte flottant « Nouveau repère sur votre carte » ajouté hors contrat par E07-T04 et le remplacer par une ligne dans l'onglet Radio du carnet (« repère reçu : <libellé> »), dans l'historique de la fréquence de la voix, côté serveur comme le reste de l'historique (E06-T04).
  - Accepté si : plus aucun texte flottant ; la ligne apparaît dans l'historique de la bonne fréquence, pour le seul appelant.
  - Tests : banc `lupa` (`test_radio_history.py`, `test_protocol.py`) ; suite `rs.actions.map`.
  - Preuve : texte flottant retiré (clé `IGUI_RadioSurvivor_MapMarked` supprimée) ; nouveau type d'historique `mark` dans `RS_RadioLog` (mêmes bornes, `history_add` au seul joueur lié) écrit par `RS_MapMarks` à l'acceptation : ligne « Repère reçu : <libellé> » (`IGUI_RS_Radio_mark`, EN et FR) en rouge brique dans l'onglet Radio, sur la fréquence de la voix, sans coordonnée ; `tests/test_radio_history.py` 28/28 (`MapMarkTests` : autre joueur, autre fréquence, autre personnage ne la voient pas ; sans personnage lié, aucune ligne), `scenario_map_client` vérifie l'absence de texte flottant, suite `rs.actions.map` (3ᵉ test) ; luacheck sans nouvel avertissement de ces fichiers ; E07-T04 et E08-T02 : commit `06b8211` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : ligne « Repère reçu » dans l’onglet Radio, sur la seule fréquence de la voix ; `rs.actions.map` 3/3
  - Reste : —

- [x] **E07-T09** — Réponse structurée du LLM robuste
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E07-T01
  - Fichiers : `bridge/radio_bridge.py`, `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : constaté en jeu le 2026-10-11 : `structured reply unreadable (ValueError: no object)`, action `reveal_area` perdue (historique de 34 messages en texte) ; extraire le JSON entouré de texte, rappeler la consigne de format en fin de prompt, utiliser le mode JSON de l’API si le fournisseur le permet, journaliser la réponse brute en DEBUG.
  - Accepté si : une réponse JSON entourée de texte ou après un long historique donne ses actions ; aucune régression du mode texte
  - Tests : `test_protocol.py`
  - Preuve : `bridge/radio_bridge.py` : mode JSON de l'API en mode structuré (`response_format` `json_object`, repli sans lui sur refus HTTP 400, mémorisé par fournisseur et modèle), rappel de format en fin du message de l'appelant (`format_reminder`, historique non pollué), extraction tolérante du premier objet JSON avec `say` ou `actions` (entouré de texte, bloc de code, saut de ligne brut ; réparation des guillemets typographiques et de la virgule finale en dernier recours), réponse brute illisible journalisée en DEBUG (300 caractères, jamais un secret) ; mode texte inchangé ; `test_protocol.py` 31/31 (`scenario_structured_robust` : 10 formes lues, bout en bout après 34 messages d'historique) ; luacheck 17/0 ; `docs/specifications-techniques/protocole-carnet-v2.md` ; commit `19904bb` (fait par l'utilisateur, avec une partie d'E17-T06)
  - Reste : essai en jeu avec le vrai LLM : la demande à Walt de « montrer le coin autour de la clinique » doit produire `reveal_area` ; le constat du 2026-10-11 (aucune accolade dans la réponse) n’est couvert que par le rappel et le mode JSON

- [ ] **E07-T10** — Fréquence d'une autre voix donnée exceptionnellement
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E07-T01, E06-T07
  - Fichiers : `server/RadioSurvivor/RS_VoiceBonds.lua` (nouveau), `RS_MissionVoice.lua`, `RS_RadioLog.lua`, `RadioSurvivor_Server.lua`, `RS_Personas.lua`, `bridge/radio_bridge.py`, fiches `walt.txt` et `gus.txt`, `docs/specifications-techniques/persona-format.md`
  - Faire : décision du 2026-10-18. `share_frequency` n'aboutit que si le personnage a un lien avec la voix (réponses diffusées comptées par l'autorité, jours de jeu distincts, ou bonne réputation) et si le dernier partage est assez ancien ; la voix donnée est la première de `shares` active, servie et inconnue du carnet, inscrite avec sa voix (E06-T07). La consigne du modèle rend l'action exceptionnelle. Walt et Gus reçoivent l'action et leurs listes `shares` (empreintes des fiches livrées ajoutées).
  - Accepté si : au banc, refus sans lien, accord avec lien ou bonne réputation, délais de 7 et 3 jours, aucune voix déjà connue ; en jeu, une voix finit par présenter une autre voix après plusieurs échanges, et pas avant.
  - Tests : `tests/test_voice_bonds.py`, `tests/test_personas.py`, `tests/test_personas_server.py`.
  - Preuve : `test_voice_bonds.py` 5 OK, `test_personas.py` 20 OK, `test_personas_server.py` 106 OK ; `test_fake_llm.py`, `test_rs_trade_run.py` et `rs.env` ajustés (Walt et Gus en mode structuré) ; run_all du 2026-10-18 vert hors ces trois bancs, corrigés et relancés ; luacheck 15/0
  - Reste : essai en jeu par l'utilisateur ; ⚠ la fiche `walt.txt` installée de la partie de l'utilisateur est modifiée par l'admin : elle n'est pas remplacée (ajouter `share_frequency` et `shares=` à la main pour Walt)
