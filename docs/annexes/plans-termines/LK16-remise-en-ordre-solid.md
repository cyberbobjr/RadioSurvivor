# LK16 — Remise en ordre SOLID

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** terminée — 12 / 12 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | LK16-T01 | Socle `LivingKnox.Registry` | `testé hors jeu` | hors jeu | — |
| ☑ | LK16-T02 | C1 : genres de chantier de la fortification | `testé hors jeu` | hors jeu | — |
| ☑ | LK16-T03 | C7 : tables d'aiguillage (faits publics, administration, parole) | `testé hors jeu` | hors jeu | — |
| ☑ | LK16-T04 | C5 : cycles cassés par événements | `testé hors jeu` | hors jeu | LK16-T01 |
| ☑ | LK16-T05 | C3 : contexte de décision par inscription | `testé hors jeu` | hors jeu | LK16-T04 |
| ☑ | LK16-T06 | C2 : comportements de décision par extension | `testé hors jeu` | hors jeu | LK16-T05 |
| ☑ | LK16-T07 | C8 et C9 : corvées et plans des routines | `testé hors jeu` | hors jeu | LK16-T01 |
| ☑ | LK16-T08 | C4 : genres d'expédition | `testé hors jeu` | hors jeu | LK16-T01 |
| ☑ | LK16-T09 | C6 : simulation hors écran | `testé hors jeu` | hors jeu | LK16-T04 |
| ☑ | LK16-T10 | C11 : aménagements des foyers ; nettoyages | `testé hors jeu` | hors jeu | LK16-T01 |
| ☑ | LK16-T11 | C10 : obstacles | `testé hors jeu` | hors jeu | LK16-T01 |
| ☑ | LK16-T12 | Remise en ordre vérifiée en jeu | `testé MP` | MP | LK16-T02, LK16-T03, LK16-T06, LK16-T07, LK16-T08, LK16-T09, LK16-T10, LK16-T11 |

<!-- fin du tableau de bord -->

**Mod (après la séparation).** Living Knox (`batman_LivingKnox`).

**Objectif.** Que chaque « genre » du moteur (sorte de chantier, comportement, expédition, corvée, événement, opération)
s'ajoute par un fichier inscrit à un registre, sans toucher aux moteurs, et que les modules ne se lient plus par des
cycles cachés. Aucun changement de comportement pour un joueur.

**ADR.** [Remise en ordre SOLID du moteur Living Knox](../../architecture/decisions/adr-remise-en-ordre-solid.md)
(accepté par défaut le 2026-11-13) ; ce plan en est l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** LK15 (registres des routines et des tâches du foyer), E19 (banc hors jeu mimétique, filet de sécurité).

**Sources.** [Audit SOLID](../audits/audit-solid-livingknox-2026-11-13.md) ;
[vérification des P0](../audits/audit-solid-livingknox-2026-11-13-verification-p0.md) (chantiers C1 à C11).

## Décisions

- 2026-11-13 — **LK16** : ADR confirmé par défaut (règle de l'utilisateur : option recommandée, veto possible) ; ordre
  C1 et C7, puis C5, C3, C2, puis les autres ; corrections spéculatives écartées (ADR D04).

## Hors périmètre

Constats P2 et P3 de l'audit hors des chantiers ; tout changement visible par un joueur ; RadioSurvivor.

## Tâches

- [x] **LK16-T01** — Socle `LivingKnox.Registry`
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `shared/LivingKnox/LK_Registry.lua` ; `LK_Upkeep.lua`, `LK_Routines.lua`, `LK_Decisions.lua`, `LK_Loot.lua`, `LK_GroupTypes.lua` ; bancs
  - Faire : ADR D02 : inscription, liste triée (`order` puis identifiant, sans `next`), lecture, remplacement au rechargement ; les cinq registres existants s'appuient dessus sans changer leur API.
  - Accepté si : banc du socle ; bancs des cinq registres verts sans changement d'attendu.
  - Tests : banc nouveau ; suite complète.
  - Preuve : 2026-11-13 : `shared/LivingKnox/LK_Registry.lua` : `LivingKnox.Registry.new(name, { key, validate, sort, items, byKey })` rend `register` (erreur « <registre>: <raison> » au niveau de l'appelant), `try`, `list` (tri par `order` puis clé, sans `next`), `get` ; une seule politique de doublon (remplacement par clé) ; `Upkeep.registerJob`, `Routines.registerActivity`, `Decisions.registerExtension`, `Loot.registerContent`, types de groupes et `Fortify.registerKind` s'appuient dessus en gardant leur API, leurs tables publiques et leurs messages ; les règles propres restent dans leur `validate` (code de chantier déjà pris, comportement de la liste fermée, identifiant de type déjà enregistré) ; banc `tests/test_lk_registry.py` 11 tests (rouge avant : `errors=11`) ; bancs des six registres verts sans attendu changé ; `python tests/run_all.py` : `170 passed, 0 failed, 0 skipped` (482 s) ; luacheck `Contents` 8, `dev` 0
  - Reste : le registre des types de groupes garde son index `state.types` (lu directement par un banc) ; non vérifié en jeu (`LK16-T12`)
- [x] **LK16-T02** — C1 : genres de chantier de la fortification
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `LK_Fortify.lua` (+ `Fortify/Kinds/*.lua`) ; bancs `test_lk_fortify*.py`, `test_lk_barricade.py`, `test_lk_walls.py`, `test_lk_repair.py`
  - Faire : constats A01 à A06 : `Fortify.registerKind` dont dérivent `KINDS`, `OFF_KINDS`, `KIND_CODE`, `CODE_KIND`, les motifs de la forme compacte et `STAGES` ; un fichier par sorte (barricade, mur, palissade, réparation).
  - Accepté si : une sorte de chantier ajoutée par un seul fichier de banc est planifiée, sauvegardée en forme compacte, relue et appliquée hors écran (test qui échoue aujourd'hui) ; bancs existants verts sans changement d'attendu.
  - Tests : bancs de la fortification ; suite complète.
  - Preuve : 2026-11-13 : `Fortify.registerKind(spec)` (`id`, `order`, `unit`, `work` ; facultatifs `stages`, `names`, `ring`, `repair`, `need`, `plan` ; `code` et `offscreen` ensemble) dans `LK_Fortify.lua` ; `KINDS`, `OFF_KINDS`, codes de la forme compacte, motifs de lecture, `STAGES`, `STRUCTURES`, `REPAIRS`, noms d'ouvrages et types hors écran dérivés du registre ; code dupliqué refusé avant toute modification ; une sorte par fichier sous `server/LivingKnox/Fortify/` (barricade `b`, mur `w`, palissade `p`, réparation sans hors écran) ; sonde sur le code d'avant : une lettre absente du motif `[bwp]` perdait le chantier hors écran sans erreur (8 planches prises, rien posé), une sorte sans lettre échouait par une erreur Lua ; banc `tests/test_lk_fortify_kinds.py` : une sorte factice inscrite par le banc seul est planifiée, gardée en forme compacte, relue, avancée hors écran et posée une fois (rouge avant : `attempt to call field 'registerKind' (a nil value)`, `Ran 3 tests … OK` après) ; `test_lk_fortify` 15, `test_lk_fortify_offscreen` 17, `test_lk_barricade` 12, `test_lk_walls` 10, `test_lk_repair` 14, `test_lk_peaks` 13, `test_kahlua` 40 (forme compacte comprise) verts sans attendu changé ; `test_doubles_api`, `test_mod_calls_api` verts ; luacheck `Contents` 8
  - Reste : suite complète à repasser avec les autres tâches du jour ; le planificateur nomme encore `barricade` et `repair` pour ses deux sources (ouvertures, pourtour) ; primitives de pose dans le moteur (découpage A24 non fait) ; réglages propres à une sorte encore dans `CFG` ; registre local à remplacer par `LivingKnox.Registry` (LK16-T01) ; chargement du dossier `Fortify/` vérifié statiquement, pas en jeu
- [x] **LK16-T03** — C7 : tables d'aiguillage (faits publics, administration, parole)
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `LK_API.lua`, `LK_Admin.lua`, `LK_Talk.lua`, `client/LivingKnox/LK_AdminView.lua` (et `LK_NpcSheet.lua` pour ses réponses) ; bancs correspondants
  - Faire : constats F-R08, F-R09, G-Z01, H-D05 : table de gestionnaires des faits publics, `Admin.OPS[op] = { debug, onNpc, run }` (fin du repli implicite vers `moveHome`), table des genres de requête de parole (ordre gardé), `onReply(op, handler)` côté client ; constante unique de la liste d'intents (G-Z02).
  - Accepté si : une opération ajoutée à `Admin.OPS` sans gestionnaire est refusée (test qui échoue aujourd'hui) ; bancs existants verts.
  - Tests : bancs de l'API, de l'administration et de la parole ; suite complète.
  - Preuve : 2026-11-13 : `API.FACT_HANDLERS` (faits publics ; genre sans gestionnaire abandonné et journalisé) ; `Admin.HANDLERS[op] = { run, onNpc, logFailure }` à côté du contrat de noms `Admin.OPS` / `DEBUG_OPS` (gardé : lu par le client et la suite `lk.load`), opération sans gestionnaire refusée « unknown request » au lieu de retomber sur `moveHome` (rouge avant : `(True, None, 3, 'wipeAll') != (False, 'unknown request', 3, 'wipeAll')`), banc de concordance `OPS`/`HANDLERS` ; `Talk.REPLY_KINDS[kind] = { beforeClaim, reply }` et constante unique `REPLY_INTENTS` (pas de registre : contrat du pont) ; `View.onReply` (`LK_AdminView.lua`) et `Sheet.onReply` (`LK_NpcSheet.lua`) ; droits d'administration inchangés ; `test_lk_admin.py` 26 OK, `test_lk_api.py` 49 OK, `test_lk_talk.py` 9 OK, `test_lk_npcsheet.py` 19 OK, `test_lk_debugview.py` 23 OK, et 19 autres bancs qui chargent ces fichiers verts sans attendu changé ; `test_mod_calls_api.py` 16 OK ; luacheck `Contents` 8
  - Reste : suite complète à repasser avec les autres tâches du jour ; `LK_AdminView` et `LK_NpcSheet` dupliquent encore l'envoi, la réception et les compteurs (un client d'administration commun : constat P1 de l'audit) ; deux tables `OPS` et `HANDLERS` tenues d'accord par un banc
- [x] **LK16-T04** — C5 : cycles cassés par événements
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Simulation.lua`, `LK_Relations.lua`, `LK_Raids.lua`, `LK_Fortify.lua`, `LK_RoutineExec.lua`, `LK_Bodies.lua`, `LK_Materialize.lua`
  - Faire : constats F-R04, F-R06, A-A20, A-A21, F-R11, C-X25 : retours d'expédition par événement, `release` mémorisé par la routine, ports injectés dans la fortification, événements de corps.
  - Accepté si : plus aucun appel d'un module bas vers un module haut cité par l'audit ; bancs verts. (2026-11-13 : le contrôle statique des couches envisagé au brief n'est pas écrit : ce serait un test « nom interdit qui ne doit pas revenir », que la règle de l'utilisateur interdit ; chaque coupure est prouvée par un banc de comportement.)
  - Tests : suite complète.
  - Preuve : 2026-11-13 : bus `LivingKnox.listen(name, key, fn, order)` à ordre explicite (stable à ordre égal) ; retour d'expédition publié par la simulation (`expeditionReturn`, écouté par Expeditions 10, Relations 20, Raids 30, retour abstrait sinon) ; fin de routine par la libération portée par la mémoire (`release`, posée par l'entretien et la fortification) ; `LK_Bodies` publie `bodyDying` (santé puis butin), `bodyDied`, `bodyReleasing` (consignes puis rapports), `bodyReleased`, `bodyTick` au lieu d'appeler sept modules (trois `pcall` en moins) ; `LK_Materialize` publie `memberReleased` (écouté par les expéditions) ; `Fortify.ports` (stock, nuit, incarnation, minute, angle, marque d'attaque) ; 8 bancs nouveaux rouges sur une copie de HEAD (5 échecs, 3 erreurs) puis verts ; une cinquantaine de bancs des modules touchés verts ; seul attendu changé : une sonde de source de `test_lk_traces.py` qui cherche maintenant `LivingKnox.publish("bodyDied"` (même invariant : `memberDied` avant la mort au registre) ; `test_doubles_api`, `test_mod_calls_api`, `test_kahlua` verts ; luacheck `Contents` 8
  - Reste : suite complète à repasser ; sur un chemin d'erreur seulement, une erreur d'un écouteur est journalisée par le bus au lieu de se propager ; lectures avec valeur de retour encore directes dans `LK_Bodies` (santé, rapports, consignes, gestes) ; arêtes inverses hors périmètre : `LK_Stock` lit la fortification, la boucle horaire de la simulation nomme Relations, Raids, Stock et Fortify (`LK16-T09`), `Decisions` lit la fortification (`LK16-T05`)
- [x] **LK16-T05** — C3 : contexte de décision par inscription
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK16-T04
  - Fichiers : `LK_Decisions.lua` et les modules fournisseurs de contexte
  - Faire : constats B-C02, B-C12, B-C13 : chaque module fournit son champ de contexte par `registerExtension` (`input`), ordre des champs figé par un banc ; `Decisions.context` ne nomme plus de module.
  - Accepté si : banc de l'ordre des champs ; bancs des décisions verts sans changement d'attendu.
  - Tests : suite complète.
  - Preuve : 2026-11-13 : registre dédié `Decisions.registerContext{ id, order, fill(ctx, src) }` sur `LivingKnox.Registry` (le hook `input` des extensions ne reçoit ni le groupe, ni le membre, ni les joueurs, ni la perception) ; `Decisions.context` de 62 à 16 lignes, sans nom de module ; fournisseurs inscrits par leur module : Routines 10, Expeditions 20, Relations 30, Alert 90, Defense 100, Encounters 110, Needs 120 ; fournisseurs du moteur : foyer 40, perception 50, menaces 60, cible 70, défense 80, besoins 130, débordement 140 ; dépendances entre champs relevées et ordre d'avant gardé ; cycle Decisions ↔ Defense, Encounters, Expeditions cassé ; banc `tests/test_lk_decision_context.py` (10 tests) : gel de trois grilles de 1 500 situations (solo complet, serveur dédié, modules de `LK_Server` seuls ; contexte, décision et appels aux modules), empreintes relevées sur l'ancien code et identiques après ; acceptation : un fournisseur inscrit par le banc seul nourrit une règle d'extension (rouge avant : `attempt to call field 'registerContext' (a nil value)`) ; banc de l'ordre ; une soixantaine de bancs verts sans attendu changé, balayage des phases vert sur onze suites ; `test_doubles_api`, `test_mod_calls_api`, `test_kahlua` verts ; luacheck `Contents` 8
  - Reste : lectures directes gardées hors du contexte pour les modules bas sans dépendance vers les décisions (perception, zombies, combat, hostilité, santé, corps) ; `target`, `defence` et `overwhelmed` à rapprocher de leurs comportements en `LK16-T06` ; `Decisions.groupInput` lit encore le stock et la fortification ; suite complète à repasser
- [x] **LK16-T06** — C2 : comportements de décision par extension
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK16-T05
  - Fichiers : `LK_Decisions.lua` ; fichiers d'extension par comportement
  - Faire : constats B-C01, B-C03, B-C04 : `fight`, `defend`, `expedition`, `revenge`, `warn`, puis la défense (`surrender`, `retreat`, `watch`, `alert`) inscrits par `registerExtension`, avec `aim` et le geste portés par chaque comportement.
  - Accepté si : `Decisions.apply` sans chaîne sur le comportement ; bancs verts sans changement d'attendu.
  - Tests : suite complète, balayage des phases.
  - Preuve : 2026-11-13 : comportements menés par l'extension qui porte leur nom (`registerExtension`, propriétaire inscrit sans `behaviour`, la liste fermée `BEHAVIOURS` et les règles restant dans le moteur, ADR D04) : `fight` (Combat), `defend` (Defense), `warn` (Encounters), `expedition` (Expeditions), `revenge` (Relations), `surrender`, `retreat`, `watch`, `alert`, `flee` (`server/LivingKnox/Decisions/LK_Decide_Defence.lua`), `guard`, `patrol` (`LK_Decide_Post.lua`) ; contrat étendu de façon générique : `aim`, `gesture`, `overlay`, `keeps`, `forget` ; `Decisions.apply` de 95 (+ 28) à 38 lignes sans nom de comportement, `Decisions.decide` de 31 à 9 lignes ; gel de l'application ajouté à `tests/test_lk_decision_context.py` (2 × 1 500 séquences de trois passages : consignes, gestes, vigilance, appels aux modules, état gardé), empreintes relevées sur l'ancien code et identiques après chaque étape, empreintes du contexte de `LK16-T05` identiques ; acceptation : un comportement inscrit par le banc seul est décidé, visé, appliqué, garde son geste et est quitté (rouge avant : `None != 342`) ; une vingtaine de bancs des décisions verts sans attendu changé, balayage des phases et désordre réseau verts ; `python tests/run_all.py` : `172 passed, 0 failed` (534 s) ; luacheck `Contents` 8
  - Reste : deux nettoyages de mémoires indépendantes changent d'ordre (routine puis provision) ; le moteur nomme encore des comportements dans les règles et leurs suites (`noteThreat`, réveil, `afterDecision`, `defenceContext`, fournisseur `overwhelmed`), gardés par l'ADR D04 ; le soin et les routines restent des activités superposées appelées par `apply` ; non vérifié en jeu (`LK16-T12`)
- [x] **LK16-T07** — C8 et C9 : corvées et plans des routines
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Routines.lua`, `Routines/LK_Routine_*.lua`
  - Faire : constats F-R03, G-Z09, F-R01 : `Routines.registerChore` (une corvée par fichier) ; le plan de guet, de ronde et de sommeil porté par son activité.
  - Accepté si : une corvée ajoutée par un seul fichier de banc est choisie et exécutée ; bancs verts.
  - Tests : bancs des routines et corvées.
  - Preuve : 2026-11-13 : `Routines.registerChore(spec)` sur `LivingKnox.Registry` (`id`, `order`, `gesture`, poids `duty`/`role`/`trait`, `avail(c)`, `plan(c)`) ; une corvée par fichier sous `server/LivingKnox/Chores/` (feu, se réchauffer, ranger, guetter, réparer, fumer, soigner, se reposer, ordres 10 à 80 = ordre d'avant) ; six tables parallèles et six branches de `chorePlan` supprimées ; tirage inchangé, figé avant la refonte par deux bancs à empreinte (`test_draw_is_frozen_on_a_grid` : 900 combinaisons × 36 tirages ; `test_chore_plans_are_frozen` : 3 membres × 6 postes × 3 jeux de traits × 24 créneaux), verts après ; plans du guet, de la ronde et du sommeil portés par leurs activités (`registerActivity` accepte `plan`), `Routines.plan` sans nom de comportement ; acceptation `test_a_chore_added_by_one_registration_is_drawn_and_done` (rouge avant : `attempt to call field 'registerChore' (a nil value)`) ; `test_lk_chores.py` et `test_lk_routines.py` 39 OK, `test_lk_meals` 16, `test_lk_upkeep` 28, `test_lk_provisions` 19, `test_lk_decisions` 27, `test_lk_care` 16, `test_lk_alert` 25, `test_lk_contest` 18, `test_lk_needs` 16, `test_lk_defense` 23, `test_lk_expeditions` 16, `test_lk_stand` 12, `test_kahlua` 40, `test_doubles_api` 17, `test_mod_calls_api` 16, sans attendu changé
  - Reste : suite complète à repasser avec LK16-T04 ; le relevé des places ne connaît que deux genres (feu, meuble) : une corvée qui demanderait un autre genre de place toucherait encore `surveySpots` ; non vérifié en jeu (`LK16-T12`)
- [x] **LK16-T08** — C4 : genres d'expédition
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Expeditions.lua`, `LK_Food.lua`
  - Faire : constats C-X01, C-X02, C-X03, C-X04, C-X07 : `Expeditions.registerKind` (bâtiment, cueillette, pêche), départ par boucle sur les genres, la nourriture s'inscrit elle-même.
  - Accepté si : un genre d'expédition ajouté par un seul fichier de banc part et revient ; bancs verts.
  - Tests : bancs des expéditions et de la nourriture.
  - Preuve : 2026-11-13 : `Expeditions.registerKind(spec)` sur `LivingKnox.Registry` (`fallback`, `hours`, `wanted`, `pickTarget`, `wants`, `start`, `valid`, `spot`, `round`, `offscreen`, `gesture`, `seen`, `make` ; pour les genres à tirages `draw`, `conditions`, `minutes`, `verb`, `detail`) ; trois genres sous `server/LivingKnox/Expeditions/` : bâtiment (repli, 100), cueillette (20), pêche (10), les deux derniers inscrits par la nourriture (plus de dépendance `Expeditions → LK_Food`) ; `tryDepart` en boucle sur les genres par priorité ; 30 lignes de chaînes sur le genre supprimées ; banc `tests/test_lk_expedition_kinds.py` : gel des départs (9 heures × bâtiments, eau, forêt × 5 profils de manques × 5 équipes), d'un déroulé complet de chaque genre et des retours hors écran, empreintes relevées sur l'ancien code et identiques après ; acceptation : un genre factice inscrit par le banc seul part, tire, rentre et se résout hors écran (rouge avant : `attempt to call field 'registerKind' (a nil value)`) ; `test_lk_expeditions` 16, `test_lk_food` 33, `test_lk_garden` 29, `test_lk_loot` 18, `test_lk_decisions` 27, `test_lk_decision_context` 14, `test_lk_stock` 44, `test_doubles_api`, `test_mod_calls_api`, `test_kahlua` verts sans attendu changé ; balayage des phases de `lk.expedition` et `lk.forage` vert
  - Reste : phases de l'expédition (C-X07) non faites ; code propre au bâtiment encore dans le moteur (C-X06) ; une expédition à genre inconnu (enregistrement malformé) ne lance plus la fouille de bâtiment pendant le passage ; suite complète à repasser ; chargement du dossier `Expeditions/` non vérifié en jeu
- [x] **LK16-T09** — C6 : simulation hors écran
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK16-T04
  - Fichiers : `LK_Simulation.lua` et modules horaires
  - Faire : constats F-R05, F-R07 : `Simulation.registerHourly{ id, order, run }`, `Simulation.registerEvent`.
  - Accepté si : un événement de groupe ajouté par un seul fichier de banc est tiré ; bancs verts.
  - Tests : bancs de la simulation.
  - Preuve : 2026-11-13 : `Simulation.registerHourly{ id, order, run }` (passes : vengeance 10 par Relations, raids 20 par Raids, règles 30 et besoins 40 par le moteur, repas 50 par Stock, chantiers 60 par Fortify ; `advance` ne nomme plus de module) et `Simulation.registerEvent{ id, order, config, bounds, prepare, chance, apply }` (départ, recrue, conflit, maladie, affrontement, un par fichier sous `server/LivingKnox/SimEvents/`, ordre et sel du tirage inchangés) ; table morte `Raids.SIGNS` retirée ; gel sha256 de cinq mondes (simulation sur 26 jours avec les cinq événements, raid complet, vengeance, chantiers et repas sur 48 h ; entrée et sortie de chaque passe, événements tirés, journal, registre), identique avant et après chaque étape ; acceptation : un événement et une passe factices inscrits par le banc seul s'exécutent à leur rang (rouge avant : `attempt to call field 'registerEvent' (a nil value)`) ; banc de l'ordre ; 104 bancs `test_lk_*` verts ; seul attendu changé : la sonde de source de `test_lk_journal.py` lit aussi les fichiers `SimEvents/` (même invariant, code déménagé) ; luacheck `Contents` 8
  - Reste : un banc qui charge `LK_Server.lua` sans les fichiers d'événements simule sans événement de groupe ; chargement du dossier `SimEvents/` non vérifié en jeu ; suite complète à repasser
- [x] **LK16-T10** — C11 : aménagements des foyers ; nettoyages
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Homes.lua`, `LK_Raids.lua`
  - Faire : constat E-F01 : `Homes.registerFurnishing`, un fichier par sorte ; table morte `Raids.SIGNS` retirée (E-F02).
  - Accepté si : un aménagement ajouté par un seul fichier de banc est posé ; bancs verts.
  - Tests : bancs des foyers et des raids.
  - Preuve : 2026-11-13 : `Homes.registerFurnishing(kind, spec)` sur `LivingKnox.Registry` (`order`, `style`, `plan(ctx, out)` ; facultatifs `furniture`, `prep`, `place`, `clear`) ; six aménagements, un par fichier sous `server/LivingKnox/Furnishings/` (barricade, lampe, lit, caisse, feu, tente) ; `KINDS` et `FURNITURE` dérivés, blocs par sorte de `planBuilding`/`planCamp`, cas particuliers de `applyAction` et de `clear` et liste du journal supprimés (`LK_Homes.lua` 813 → 744 lignes) ; banc de gel `FrozenTests` (6 foyers : maisons, camps, réaménagement, pose refusée ; plan, marque, objets posés, feux, journal, retraits), empreinte identique avant et après ; acceptation `RegistryTests` : un aménagement factice inscrit par le banc seul est planifié, posé, journalisé, validé et retiré (rouge avant : `attempt to call field 'registerFurnishing' (a nil value)`) ; `test_lk_homes.py` 25 OK ; une vingtaine de bancs qui chargent les foyers verts sans attendu changé ; `test_doubles_api`, `test_mod_calls_api`, `test_kahlua` verts ; luacheck `Contents` 8
  - Reste : retrait de la table morte `Raids.SIGNS` reporté (fichier voisin d'une autre tâche en cours) ; repli `crate` de `findTagged` encore écrit dans le moteur ; le retrait choisit son traitement par la sorte notée sur l'objet et non plus par sa classe (aucun cas différent aujourd'hui) ; suite complète à repasser ; chargement du dossier `Furnishings/` non vérifié en jeu
- [x] **LK16-T11** — C10 : obstacles
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Obstacles.lua` (découpage)
  - Faire : constats D-OBS-01, D-OBS-03, D-OBS-05, D-OBS-06 : modèles d'itinéraire inscrits, un fichier par modèle ; paires `decide`/`decideWindow` et voisines dédoublonnées localement (D-OBS-02 sans registre).
  - Accepté si : bancs des obstacles verts sans changement d'attendu.
  - Tests : bancs des obstacles ; suite complète.
  - Preuve : 2026-11-13 : `LivingKnox.Obstacles.Routing.registerModel(name, spec)` sur `LivingKnox.Registry` (`edgeCost`, `maxNodes`, `vanilla`, `refusedCost`) ; moteur d'itinéraires sorti dans `LK_Routing.lua` (relevé des bords, recherche de chemin, détours, choix d'itinéraire) ; sept modèles, un par fichier sous `server/LivingKnox/Routing/` ; plus aucune comparaison de mode dans le moteur ; `LK_Obstacles.lua` de 2 850 à 1 947 lignes, appels publics `LivingKnox.Obstacles.*` inchangés ; dédoublonnages locaux (fin commune des refermetures, contrôle « objet disparu ») ; paires porte/fenêtre et politique force/attente/détour gardées (règles différentes, ADR D04) ; banc de gel `tests/test_lk_routing.py` (9 cartes, 7 modèles : coûts de chaque bord dans les deux sens, itinéraires, lignes dégagées, `planDoorRoute`), empreintes identiques avant et après ; acceptation : un modèle factice inscrit par le banc seul est suivi par la recherche (rouge avant : `attempt to index field 'Routing' (a nil value)`) ; `test_lk_obstacles.py` 176 OK, `test_lk_alert` 25, `test_lk_window_lure` 12, `test_lk_floor_strike` 6, `test_lk_movement` 15, `test_lk_guard` 27, `test_lk_milestone` 13, `test_lk_directives` 43, `test_doubles_api`, `test_mod_calls_api`, `test_kahlua` verts sans attendu changé ; luacheck `Contents` 8
  - Reste : suite complète à repasser ; portes, clés, fenêtres, passage bloqué et refermetures restent dans `LK_Obstacles.lua` (aides privées partagées) ; passes codées en dur (D-OBS-04), lectures directes de l'état des consignes et des décisions (D-OBS-08) ; les nouveaux fichiers ne sont pas compilés par le banc Kahlua réel (le moteur des obstacles n'y est pas chargé) ; chargement du dossier `Routing/` vérifié statiquement, pas en jeu
- [x] **LK16-T12** — Remise en ordre vérifiée en jeu
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK16-T02, LK16-T03, LK16-T06, LK16-T07, LK16-T08, LK16-T09, LK16-T10, LK16-T11
  - Fichiers : —
  - Faire : campagnes solo (deux mods, Living Knox seul), MP et `mp-ambient` sur le commit de fin.
  - Accepté si : mêmes résultats que la dernière campagne verte de référence.
  - Tests : campagnes en jeu.
  - Preuve : campagnes du 2026-11-13 au soir et du 2026-11-14 (dossier de travail, commits `8b439ee` à `a7ddc94`) : MP 3 tranches `tools/autoclient/runs/20261113-233636-parallel-3` 510/534, 3 FAIL (`lk.alert` garde, `lk.forage` arrosage, `rs.npctalk` délai : corrigés par `19ac890`, `44b200a`, `f9c8d8f`) ; solo deux mods `20261113-235754-parallel-2` 245/257, 3 FAIL (`lk.forage` : lancé avant `44b200a` ; `lk.upkeep` : corrigé par `a7ddc94` ; `lk.debugview` : ouvert, registre des écarts) ; Living Knox seul `20261114-001702-parallel-2` 105/114, 0 FAIL ; `mp-ambient` `20261114-003116-mp-cf36126965e3` 23/24, 0 FAIL ; campagne MP de contrôle sur `a7ddc94` arrêtée par Claude Code (mémoire de la machine basse), non relancée ; campagne MP du 2026-11-15 sur `962ee34` (serveur dédié + 2 clients, pont avec faux modèle) : code 0, `RST-RESULT ok=true total=398 pass=378 fail=0 error=0 skip=20` (`tools/autoclient/runs/20261115-004728-mp-63ed80f68139`) ; campagne `mp-ambient` du 2026-11-15 sur `d52f5f2` (zombies du jeu, sans mode dieu) : code 0, `RST-RESULT ok=true total=24 pass=23 fail=0 error=0 skip=1` chez rs_mp1 et 6/6 chez rs_mp2 (`tools/autoclient/runs/20261115-022131-mp-aad4e251e079`) ; campagne solo des deux mods du 2026-11-15 sur le commit `d52f5f2` (copie figée, `--campaign solo --bridge on --llm fake --wait-idle 3600`) : code 1, `RST-RESULT ok=false total=274 pass=256 fail=1 error=0 skip=17` (`tools/autoclient/runs/20261115-022616-966db38d6a28`), seul échec étranger à Living Knox : rs.personas.update (fiche de voix, travail E20 en cours) ; campagne `solo-lk` (Living Knox seul) du 2026-11-15 sur `962ee34` : code 0, `TOTAL total=114 pass=105 fail=0 error=0 skip=9` (`tools/autoclient/runs/20261115-002325-run-962ee349cab6`) : aucune suite de Living Knox en échec, lk.garden joué et vert en solo et en MP
  - Reste : `lk.debugview` reste au registre des écarts (`E19-T08`)
