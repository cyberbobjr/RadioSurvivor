# E20 — Voix déclarées en un seul fichier : missions, récompenses, planques et troc

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 2 / 15 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E20-T01 | Registre des types de mission, sans changement de comportement | `testé hors jeu` | hors jeu | — |
| ☑ | E20-T02 | Analyseur unique des fiches et pont sans liste de types | `testé hors jeu` | hors jeu | E20-T01 |
| ☐ | E20-T03 | Fiche à sections : lieux, missions, récompenses, catégories | `à faire` | hors jeu | E20-T02 |
| ☐ | E20-T04 | Récompenses tirées au hasard par catégorie | `à faire` | MP | E20-T03 |
| ☐ | E20-T05 | Planques multiples au choix du joueur, ramassées hors de vue | `à faire` | MP | E20-T03 |
| ☐ | E20-T06 | Objets demandés par une voix toujours déposés à une planque | `à faire` | MP | E20-T05 |
| ☐ | E20-T07 | Troc déclaré dans la fiche, un état par marchand | `à faire` | MP | E20-T03, E20-T05 |
| ☐ | E20-T08 | Missions enchaînées et état de fiche | `à faire` | hors jeu | E20-T03 |
| ☐ | E20-T09 | Type de mission `barricade` | `à faire` | MP | E20-T01, E20-T03 |
| ☐ | E20-T10 | Darlene veut rentrer à sa clinique | `à faire` | MP | E20-T04, E20-T05, E20-T08, E20-T09 |
| ☐ | E20-T11 | Un marchand par ville vanilla | `à faire` | MP | E20-T07 |
| ☐ | E20-T12 | Type de mission `relay` (relais radio) | `à faire` | MP | E20-T01, E20-T03 |
| ☐ | E20-T13 | Type de mission `route` (itinéraire) | `à faire` | MP | E20-T01, E20-T03 |
| ☐ | E20-T14 | Type de mission `watch` (guet) | `à faire` | MP | E20-T01, E20-T03 |
| ☐ | E20-T15 | Type de mission `item` (objet personnel) | `à faire` | MP | E20-T01, E20-T03, E20-T05 |

<!-- fin du tableau de bord -->

**Mod.** RadioSurvivor (`batman_RadioSurvivor`), le pont, et `batman_RadioSurvivorCore` pour les gabarits de mission
qu'il héberge. Living Knox hors périmètre.

**Objectif.** Une voix radio se définit entièrement dans sa fiche `personas/<id>.txt` : missions proposées et leurs
paramètres, récompenses tirées au hasard par catégorie, planques de dépôt (plusieurs par mission, au choix du joueur),
troc. Le moteur gère tout le reste. Ajouter un type de mission, une nature de récompense ou un mode d'arrivée du
marchand = un fichier inscrit à un registre, sans modifier le moteur. Aucune remise ne fait disparaître un objet sous
les yeux du joueur.

**ADR.** [Voix radio déclarées en un seul fichier](../../architecture/decisions/adr-personas-declaratives.md)
(accepté le 2026-11-14) ; ce plan en est l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** E11 (missions des voix, planque `RS_VoiceDelivery`), E13 (passeur), E07 (actions et lieux des fiches).

**Sources.** Relevé du code du 2026-11-14 (ADR, section Contexte) ; `docs/specifications-techniques/persona-format.md` ;
`docs/specifications-techniques/protocole-carnet-v2.md` ; sources vanilla 42.22 (`E:\pz-source-42.22`) relevées par
chaque tâche avant son code.

## Décisions

- 2026-11-14 — **E20** (utilisateur) : ADR accepté. Tout est dans la fiche de la voix (option A de l'ADR) ; comportement
  d'un type de mission en code, un fichier par type, inscrit à un registre ; catalogue de catégories d'objets partagé
  livré par le mod, catégories propres possibles dans la fiche. SOLID non négociable.
- 2026-11-14 — **E20** (utilisateur) : une mission propose **plusieurs planques à la fois** ; le joueur dépose à celle
  de son choix (ADR D06, précision).
- 2026-11-14 — **E20** (utilisateur) : Darlene a quitté sa clinique et veut y revenir une fois les lieux sûrs ; ses
  missions préparent ce retour, point d'accroche pour Living Knox (ADR D09).
- 2026-11-14 — **E20** (utilisateur) : le wiki suit le code. Toute tâche qui change ce qu'on écrit dans une fiche
  (sections, récompenses, planques, troc, enchaînements, nouveau type) ou ce que vit le joueur (remise, ramassage,
  marchands) met à jour dans le même commit les pages concernées de `docs/wiki/fr/` et `docs/wiki/en/`
  (`10-creer-une-voix-radio.md` / `10-creating-radio-voices.md`, `03-utilisation.md` / `03-usage.md`, FAQ), et le
  dit dans sa preuve.

## Hors périmètre

- Missions des PNJ de Living Knox, dépôt au foyer d'un groupe (`recover`), remise en main propre à un PNJ.
- Incarnation de Darlene par Living Knox à son retour (seul l'état « rentrée » de sa fiche est livré ici).

## Tâches

- [x] **E20-T01** — Registre des types de mission, sans changement de comportement
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `batman_RadioSurvivorCore/.../RC_Missions.lua` (déclarations des gabarits) ; gabarits `RC_MissionScout.lua`, `RC_MissionClear.lua`, `RC_MissionRetrieve.lua`, `RC_MissionSignal.lua`, gabarit `deliver` ; `batman_RadioSurvivor/.../server/RadioSurvivor/RS_MissionVoice.lua` ; `client/RadioSurvivor/RS_Notebook.lua` ; `client/RadioSurvivor/RS_MapActions.lua` ; bancs `tests/`
  - Faire : ADR D02. Chaque gabarit déclare ce que lisent les autres modules : permis à une voix (`voice`), mode de remise (`report = radio | drop | in_person`), lignes du carnet, style de carte, chargement paresseux éventuel. Supprimer `V.TEMPLATES`, `TEMPLATE_NAMES`, les cas `template == "deliver"` et `name == "signal"` de `RS_MissionVoice.lua`, les booléens par type de `RS_Notebook.lua:484-488` et `RS_MapActions.lua:203`. Le cas planque de `deliver` passe dans la déclaration du gabarit.
  - Accepté si : `grep -E "template ?== ?['\"]"` vide dans `RS_MissionVoice.lua`, `RS_Notebook.lua`, `RS_MapActions.lua` ; banc avec un faux gabarit inscrit par le test, donné par une voix, affiché au carnet et sur la carte sans autre modification ; bancs actuels des missions verts sans changement d'attendu ; luacheck sans hausse.
  - Tests : `tests/run_all.py` ; nouveau banc du registre.
  - Preuve : 2026-11-14 : déclarations `handover`, `voiceName`, `mapStyle` sur les gabarits ; `M.voiceTemplate`, `M.voiceNames`, projection de `handover` et `mapStyle` (`RC_Missions.lua`) ; `Journal.HANDOVER` retiré ; `V.TEMPLATES`, `TEMPLATE_NAMES` et les cas `deliver`/`signal` retirés de `RS_MissionVoice.lua` (`V.allowed`, `V.registerSetup`, planque inscrite par `RS_VoiceDelivery.lua`) ; registre `RS_MissionViews.lua` et six vues `client/RadioSurvivor/MissionViews/RS_View_*.lua` ; carte : clé `IGUI_RS_MapZone` + `mapStyle`. Banc `tests/test_mission_registry.py` (faux gabarit donné par une voix, projeté, affiché par une fausse vue, libellé de carte) : 3 tests OK (écrit après le code, jamais vu rouge : il appelle des fonctions absentes de l'ancien code). `python tests/run_all.py --keep-going` : 184 passés, 1 échec (`rs_suites`, références `file:line` de `RS_Env.lua` décalées), corrigé, puis `--only rs_suites --only rst --only rs_mp_suites --only persist_suites --only mission_registry` : 5 passés, `RESULT: PASS` ; `test_voice_templates.py` et bancs touchés : `Ran 132 tests … OK`. luacheck `Contents` 8 avertissements (inchangé), `dev` 0. Greps d'acceptation vides dans `RS_MissionVoice.lua`, `RS_Notebook.lua`, `RS_MapActions.lua`, `RC_MissionJournal.lua`.
  - Reste : liste `MISSION_TEMPLATES` de `RS_Persona.lua` reportée à `E20-T02` (le cas « bad missions » de `tests/test_personas.py:79` compare les deux analyseurs). Chargement du dossier `MissionViews/` à confirmer en jeu avec la première tâche `solo` ou `MP` du plan.
- [x] **E20-T02** — Analyseur unique des fiches et pont sans liste de types
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E20-T01
  - Fichiers : `RS_Persona.lua` ; `RadioSurvivor_Server.lua` (contexte des demandes) ; `bridge/persona_store.py` ; `bridge/radio_bridge.py` ; `docs/specifications-techniques/protocole-carnet-v2.md` ; bancs Python et Lua
  - Faire : ADR D03. Le serveur envoie, dans chaque demande d'une voix, les missions permises avec la description déclarée par leur gabarit et le contexte de la mission ouverte sous une forme générique (champs nommés par le gabarit). Le pont ne lit plus dans la fiche que l'identité et le prompt ; supprimer `MISSION_TEMPLATES`, `CACHE_TABLES` et les branches `elif kind ==` (`radio_bridge.py:1153, 1204-1242, 1553, 1602` ; `persona_store.py:37, 330-333`). Retirer aussi `MISSION_TEMPLATES` de `RS_Persona.lua` (reporté de E20-T01) : la ligne `missions=` accepte tout nom syntaxiquement valide, `V.start` refuse et journalise un nom sans gabarit ; revoir avec le pont le cas « bad missions » de `tests/test_personas.py:79`.
  - Accepté si : un faux gabarit du banc E20-T01 est décrit au modèle sans aucune modification du pont ; aucune liste de noms de gabarits dans `bridge/` (`grep`) ; contrat mis à jour des deux côtés dans le même commit ; bancs Python et Lua verts.
  - Tests : `tests/test_protocol.py`, `tests/test_bridge_*.py`, `tests/run_all.py`.
  - Preuve : 2026-11-15 : chaque gabarit déclare `voiceText` et `voiceBrief(m)` (objectif et faits en anglais composés par le serveur) ; `mission=` générique (`kind`, `state`, `turn`, `place`, `clues`, `remainingMs`, `toReport`, `reward`, `job`, `facts`) ; nouveau champ `jobs=` (`V.jobs` : types permis par la fiche et inscrits, tables de cache de `RC_Caches.tableNames`) ; pont sans liste de types ni de tables (registre `ACTION_CHOICES`, `voice_jobs`) ; `missions=` et `cache_table=` contrôlés par leur syntaxe seule dans les deux analyseurs ; défaut `scout` porté par `RS_MissionVoice` seul. Rouge d'abord : `test_mission_registry.py` `Ran 4 tests … FAILED (errors=1)` (fiche `missions=fake` refusée), puis `Ran 4 tests … OK` ; `test_personas.py` 20 OK ; `test_voice_templates.py` OK ; `test_fake_llm.py` 27 OK ; `test_protocol.py` code 0 ; `test_carnet.py` OK ; `run_all.py --keep-going` : 184 passés, 1 échec `doubles_api` (`test_peer_checks2.py`, commit LK `9162e24` arrivé pendant le passage, sans lien). luacheck `Contents` 8 avertissements (inchangé), `dev` 0. `grep MISSION_TEMPLATES\|CACHE_TABLES` vide dans `bridge/` et `Contents/`. Contrat (`protocole-carnet-v2.md`), `persona-format.md` et pages 10 du wiki FR/EN mis à jour.
  - Reste : `bridge/npc_protocol.py:1191-1220` (réponses hors ligne des offres de PNJ, Living Knox) garde une chaîne par type : hors périmètre E20 (Living Knox exclu), à reprendre par une tâche LK.
- [ ] **E20-T03** — Fiche à sections : lieux, missions, récompenses, catégories
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E20-T02
  - Fichiers : `RS_Persona.lua` (sections) ; `RS_Personas.lua` (empreintes `KNOWN_DELIVERED`) ; `personas/*.txt` (six fiches réécrites) ; `personas/_categories.txt` (catalogue livré) ; `docs/specifications-techniques/persona-format.md` ; `docs/wiki/fr/10-creer-une-voix-radio.md` et `docs/wiki/en/10-creating-radio-voices.md` (exemples de fiche réécrits)
  - Faire : ADR D01, D04, D11. Sections `[place <id>]` (`at`, `label`, `use` parmi `mark`, `target`, `drop`, `landing`), `[mission <id>]` (`type`, paramètres validés par le schéma déclaré du gabarit, `weight`, `after`, `story`, `drops`), `[rewards]` (`pool` pondéré), `[category <id>]` (objets et fourchettes de quantités). Une fiche ne cite que des types inscrits et des lieux qu'elle déclare ; erreur de fiche = ligne et raison journalisées, fiche refusée. Les six fiches passent au format sans changer ce que propose chaque voix aujourd'hui. Pas de lecture de l'ancien format.
  - Accepté si : bancs d'analyse (sections valides, type inconnu, lieu absent, `drops` vers un lieu sans `use=drop`, catégorie inconnue, poids invalides) ; un faux type inscrit par le test accepte ses propres paramètres sans modifier l'analyseur ; les six fiches livrées se chargent ; `persona-format.md` réécrit ; pages 10 du wiki FR et EN réécrites, leurs exemples de fiche se chargent tels quels.
  - Tests : `tests/test_persona*.py`, `tests/run_all.py`.
  - Preuve : —
  - Reste : —
- [ ] **E20-T04** — Récompenses tirées au hasard par catégorie
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T03
  - Fichiers : `RS_Rewards.lua` (moteur du tirage) ; `server/RadioSurvivor/Rewards/` (une nature par fichier : `cache`, `frequency`, `stashmap`, `lesson`) ; `RC_MissionConfig.lua` (tables figées `Caches.tables` remplacées par le catalogue pour les voix) ; bancs ; suite en jeu
  - Faire : ADR D05. Tirage pondéré dans `pool` parmi les récompenses réalisables, puis contenu tiré dans la catégorie (objets et quantités du catalogue ou de la fiche). Fin du cycle fixe `cursor`. Une nature de récompense s'inscrit à un registre.
  - Accepté si : banc à graine fixe (répartition des tirages conforme aux poids sur 1 000 tirages, nature irréalisable écartée, contenu dans les fourchettes) ; faux type de récompense inscrit par le test ; suite MP : une mission réussie donne une cache dont le contenu appartient à la catégorie tirée.
  - Tests : banc des récompenses ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T05** — Planques multiples au choix du joueur, ramassées hors de vue
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T03
  - Fichiers : `RS_VoiceDelivery.lua` ; `RS_MissionVoice.lua` ; `RS_Config.lua` (`VoiceDelivery`) ; `client/RadioSurvivor/RS_MapActions.lua` (une marque par planque) ; bancs ; suite en jeu
  - Faire : ADR D06 et sa précision. Une mission de voix porte toutes ses planques (`drops`) ; chacune est préparée (relevé de l'existant), marquée sur la carte du participant et surveillée ; les dépôts de plusieurs planques se cumulent jusqu'à la quantité. Ramassage d'une planque seulement si aucun joueur ne la voit (case déchargée, ou tous les joueurs au-delà de la distance d'affichage) **et** après un délai en heures de jeu (défaut : 6 h de jeu, éditable par la fiche et `RS_Config`), décompté par l'horloge de jeu (`RC_GameClock`), plus en temps réel. Un retour du joueur avant le délai remet le délai à zéro. Valeur de la distance relevée dans le Java 42.22 avant le code.
  - Accepté si : bancs : deux planques, dépôt partiel dans chacune, total crédité une fois ; joueur à portée de vue = rien ramassé ; délai compté en temps de jeu (pause arrêtée, vitesse x3 accélère) ; reprise après redémarrage sans double crédit ; suite MP : dépôt, départ, retour avant le délai (objets présents), départ, retour après le délai (objets partis, mission avancée).
  - Tests : banc `RS_VoiceDelivery` ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T06** — Objets demandés par une voix toujours déposés à une planque
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T05
  - Fichiers : `RC_MissionRetrieve.lua` (remise d'une voix) ; déclaration du gabarit `retrieve_id` ; `RS_MissionVoice.lua` ; bancs ; suite en jeu
  - Faire : ADR D06. Pour une voix, la carte d'identité se dépose à une planque de la mission (règle de E20-T05, objet reconnu par son identifiant `m.cardId`) ; le compte rendu radio ne retire plus rien de l'inventaire (`RC_MissionRetrieve.lua:220-238`). La remise en main propre aux PNJ ne change pas.
  - Accepté si : banc : compte rendu radio sans dépôt = refus, carte toujours dans l'inventaire ; carte déposée puis ramassée hors de vue = objectif atteint ; une autre carte d'identité déposée n'est pas prise ; suite MP du parcours complet.
  - Tests : banc `RS_MissionRetrieve` ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T07** — Troc déclaré dans la fiche, un état par marchand
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T03, E20-T05
  - Fichiers : `RS_Trade.lua`, `RS_TradeRun.lua`, `RS_TradeExchange.lua` ; `server/RadioSurvivor/TradeArrivals/` (un mode d'arrivée par fichier, `boat` d'abord) ; `personas/gus.txt` ; bancs ; suite en jeu
  - Faire : ADR D07. Section `[trade]` : lieux `use=landing`, cadence, heures, stock (catégories et fourchettes), mode d'arrivée. État par marchand (fin de `S.data.trade` unique et de `Trade.PIER`). Le mode d'arrivée fournit son signal attendu, son bruit d'approche et de départ (son vanilla relevé dans 42.22) et ses causes d'annulation. Échange seulement hors de vue de tout joueur et après un délai de jeu (règle de E20-T05). Gus passe au format, même ponton, même stock.
  - Accepté si : bancs : deux marchands réservés la même semaine sans interférence ; un faux mode d'arrivée inscrit par le test ; joueur à portée de vue = aucun échange ; bancs actuels du troc verts une fois adaptés au nouvel état ; suite MP du passage de Gus.
  - Tests : bancs `RS_Trade*` ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T08** — Missions enchaînées et état de fiche
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E20-T03
  - Fichiers : `RS_MissionVoice.lua` (choix de la mission) ; `RS_PersonaState.lua` ; bancs
  - Faire : ADR D04, D09. Une mission `after=<id>` n'est proposée qu'après la réussite de la mission citée (par personnage, ou par équipe si la mission l'indique) ; tirage pondéré (`weight`) parmi les missions disponibles. Une mission peut déclarer `sets_state=<valeur>` à sa réussite (état de la voix, lu par le prompt et exposé par une API publique du mod pour un usage futur, sans dépendance vers Living Knox).
  - Accepté si : bancs : chaîne de trois missions proposée dans l'ordre ; mission échouée = chaîne bloquée jusqu'à une nouvelle réussite ; état posé une fois, sauvegardé et relu.
  - Tests : banc des voix ; `tests/run_all.py`.
  - Preuve : —
  - Reste : —
- [ ] **E20-T09** — Type de mission `barricade`
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T01, E20-T03
  - Fichiers : `server/.../Missions/` (fichier du gabarit, emplacement fixé par E20-T01) ; traductions EN/FR ; bancs ; suite en jeu
  - Faire : ADR D10. Barricader `count` fenêtres et portes d'un lieu `target` (bâtiment entier) ; vérification par les barricades vanilla relevées dans 42.22 (objet de barricade et ses planches ou tôles) ; compte rendu à la radio.
  - Accepté si : banc avec doublures fidèles ; suite MP : barricades posées par le joueur comptées, objectif atteint, compte rendu accepté.
  - Tests : banc du gabarit ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T10** — Darlene veut rentrer à sa clinique
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T04, E20-T05, E20-T08, E20-T09
  - Fichiers : `personas/darlene.txt` ; `RS_Personas.lua` (empreinte) ; traductions de son appel ; suite en jeu
  - Faire : ADR D09. Prompt : elle a quitté la clinique après la nuit de la porte fermée et se cache ailleurs ; elle veut y revenir une fois les lieux sûrs. Chaîne : reconnaître la clinique → nettoyer les abords → barricader → déposer des médicaments à une planque proche ; la dernière réussite pose l'état `returned`. Planques et lieux relevés sur la carte 42.22.
  - Accepté si : fiche chargée ; banc de la chaîne avec la vraie fiche ; suite MP : la chaîne entière jusqu'à l'état `returned`.
  - Tests : campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T11** — Un marchand par ville vanilla
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T07
  - Fichiers : `personas/*.txt` (nouvelles fiches) ; `server/RadioSurvivor/TradeArrivals/` (`road`, `cache`) ; traductions ; notes de découverte des fréquences (`RS_Notes.lua`, si la liste reste dans le code : la passer en déclaration de fiche) ; suite en jeu
  - Faire : ADR D08. Passeurs en barque pour Riverside (Gus), West Point, Brandenburg et Louisville ; arrivée par la route ou planque pour Muldraugh, Rosewood, March Ridge, Ekron, Irvington et Echo Creek. Chaque marchand : une fiche, un personnage, une histoire, ses lieux relevés sur la carte 42.22. Noms, histoires et liste des villes confirmés par défaut, montrés à l'utilisateur dans le compte rendu.
  - Accepté si : chaque fiche se charge ; aucun code de marchand nommé (`grep` des identifiants hors `personas/`) ; suite MP : un passage par la route complet.
  - Tests : banc de chargement des fiches ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T12** — Type de mission `relay` (relais radio)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T01, E20-T03
  - Fichiers : fichier du gabarit ; traductions ; bancs ; suite en jeu
  - Faire : ADR D10. Poser une radio (talkie ou HAM) dans un lieu `target` en hauteur, alimentée et allumée ; vérification par les objets radio vanilla relevés dans 42.22 ; compte rendu à la radio.
  - Accepté si : banc ; suite MP : radio posée et allumée comptée, éteinte refusée.
  - Tests : banc du gabarit ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T13** — Type de mission `route` (itinéraire)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T01, E20-T03
  - Fichiers : fichier du gabarit ; traductions ; bancs ; suite en jeu
  - Faire : ADR D10. Traverser dans l'ordre plusieurs lieux `target` de la fiche (à pied ou en véhicule) ; points marqués un à un sur la carte ; compte rendu à la radio.
  - Accepté si : banc (ordre respecté, point sauté refusé) ; suite MP du parcours.
  - Tests : banc du gabarit ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T14** — Type de mission `watch` (guet)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T01, E20-T03
  - Fichiers : fichier du gabarit ; traductions ; bancs ; suite en jeu
  - Faire : ADR D10. Rester à un point d'observation une durée en heures de jeu (absence tolérée courte), puis compte rendu ; le contexte du modèle reçoit les faits vus pendant le guet (hélicoptère vanilla entendu, horde proche) pour en parler.
  - Accepté si : banc (durée en temps de jeu, absence longue = remise à zéro) ; suite MP.
  - Tests : banc du gabarit ; campagne MP.
  - Preuve : —
  - Reste : —
- [ ] **E20-T15** — Type de mission `item` (objet personnel)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E20-T01, E20-T03, E20-T05
  - Fichiers : fichier du gabarit ; traductions ; bancs ; suite en jeu
  - Faire : ADR D10. Un objet vanilla nommé (photo, bijou ; types relevés dans les scripts 42.22) placé dans un lieu `target`, marqué par son identifiant ; à trouver puis déposer à une planque de la mission (règle de E20-T05).
  - Accepté si : banc ; suite MP : objet trouvé, déposé, ramassé hors de vue ; un objet du même type non marqué refusé.
  - Tests : banc du gabarit ; campagne MP.
  - Preuve : —
  - Reste : —
