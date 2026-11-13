# LK16 — Remise en ordre SOLID

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 4 / 12 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | LK16-T01 | Socle `LivingKnox.Registry` | `testé hors jeu` | hors jeu | — |
| ☑ | LK16-T02 | C1 : genres de chantier de la fortification | `testé hors jeu` | hors jeu | — |
| ☑ | LK16-T03 | C7 : tables d'aiguillage (faits publics, administration, parole) | `testé hors jeu` | hors jeu | — |
| ☐ | LK16-T04 | C5 : cycles cassés par événements | `à faire` | hors jeu | LK16-T01 |
| ☐ | LK16-T05 | C3 : contexte de décision par inscription | `à faire` | hors jeu | LK16-T04 |
| ☐ | LK16-T06 | C2 : comportements de décision par extension | `à faire` | hors jeu | LK16-T05 |
| ☑ | LK16-T07 | C8 et C9 : corvées et plans des routines | `testé hors jeu` | hors jeu | LK16-T01 |
| ☐ | LK16-T08 | C4 : genres d'expédition | `à faire` | hors jeu | LK16-T01 |
| ☐ | LK16-T09 | C6 : simulation hors écran | `à faire` | hors jeu | LK16-T04 |
| ☐ | LK16-T10 | C11 : aménagements des foyers ; nettoyages | `à faire` | hors jeu | LK16-T01 |
| ☐ | LK16-T11 | C10 : obstacles | `à faire` | hors jeu | LK16-T01 |
| ☐ | LK16-T12 | Remise en ordre vérifiée en jeu | `à faire` | MP | LK16-T02, LK16-T03, LK16-T06, LK16-T07, LK16-T08, LK16-T09, LK16-T10, LK16-T11 |

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
- [ ] **LK16-T04** — C5 : cycles cassés par événements
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Simulation.lua`, `LK_Relations.lua`, `LK_Raids.lua`, `LK_Fortify.lua`, `LK_RoutineExec.lua`, `LK_Bodies.lua`, `LK_Materialize.lua`
  - Faire : constats F-R04, F-R06, A-A20, A-A21, F-R11, C-X25 : retours d'expédition par événement, `release` mémorisé par la routine, ports injectés dans la fortification, événements de corps.
  - Accepté si : plus aucun appel d'un module bas vers un module haut cité par l'audit ; bancs verts.
  - Tests : suite complète.
  - Preuve : —
  - Reste : —
- [ ] **LK16-T05** — C3 : contexte de décision par inscription
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK16-T04
  - Fichiers : `LK_Decisions.lua` et les modules fournisseurs de contexte
  - Faire : constats B-C02, B-C12, B-C13 : chaque module fournit son champ de contexte par `registerExtension` (`input`), ordre des champs figé par un banc ; `Decisions.context` ne nomme plus de module.
  - Accepté si : banc de l'ordre des champs ; bancs des décisions verts sans changement d'attendu.
  - Tests : suite complète.
  - Preuve : —
  - Reste : —
- [ ] **LK16-T06** — C2 : comportements de décision par extension
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK16-T05
  - Fichiers : `LK_Decisions.lua` ; fichiers d'extension par comportement
  - Faire : constats B-C01, B-C03, B-C04 : `fight`, `defend`, `expedition`, `revenge`, `warn`, puis la défense (`surrender`, `retreat`, `watch`, `alert`) inscrits par `registerExtension`, avec `aim` et le geste portés par chaque comportement.
  - Accepté si : `Decisions.apply` sans chaîne sur le comportement ; bancs verts sans changement d'attendu.
  - Tests : suite complète, balayage des phases.
  - Preuve : —
  - Reste : —
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
- [ ] **LK16-T08** — C4 : genres d'expédition
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Expeditions.lua`, `LK_Food.lua`
  - Faire : constats C-X01, C-X02, C-X03, C-X04, C-X07 : `Expeditions.registerKind` (bâtiment, cueillette, pêche), départ par boucle sur les genres, la nourriture s'inscrit elle-même.
  - Accepté si : un genre d'expédition ajouté par un seul fichier de banc part et revient ; bancs verts.
  - Tests : bancs des expéditions et de la nourriture.
  - Preuve : —
  - Reste : —
- [ ] **LK16-T09** — C6 : simulation hors écran
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK16-T04
  - Fichiers : `LK_Simulation.lua` et modules horaires
  - Faire : constats F-R05, F-R07 : `Simulation.registerHourly{ id, order, run }`, `Simulation.registerEvent`.
  - Accepté si : un événement de groupe ajouté par un seul fichier de banc est tiré ; bancs verts.
  - Tests : bancs de la simulation.
  - Preuve : —
  - Reste : —
- [ ] **LK16-T10** — C11 : aménagements des foyers ; nettoyages
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Homes.lua`, `LK_Raids.lua`
  - Faire : constat E-F01 : `Homes.registerFurnishing`, un fichier par sorte ; table morte `Raids.SIGNS` retirée (E-F02).
  - Accepté si : un aménagement ajouté par un seul fichier de banc est posé ; bancs verts.
  - Tests : bancs des foyers et des raids.
  - Preuve : —
  - Reste : —
- [ ] **LK16-T11** — C10 : obstacles
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : LK16-T01
  - Fichiers : `LK_Obstacles.lua` (découpage)
  - Faire : constats D-OBS-01, D-OBS-03, D-OBS-05, D-OBS-06 : modèles d'itinéraire inscrits, un fichier par modèle ; paires `decide`/`decideWindow` et voisines dédoublonnées localement (D-OBS-02 sans registre).
  - Accepté si : bancs des obstacles verts sans changement d'attendu.
  - Tests : bancs des obstacles ; suite complète.
  - Preuve : —
  - Reste : —
- [ ] **LK16-T12** — Remise en ordre vérifiée en jeu
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK16-T02, LK16-T03, LK16-T06, LK16-T07, LK16-T08, LK16-T09, LK16-T10, LK16-T11
  - Fichiers : —
  - Faire : campagnes solo (deux mods, Living Knox seul), MP et `mp-ambient` sur le commit de fin.
  - Accepté si : mêmes résultats que la dernière campagne verte de référence.
  - Tests : campagnes en jeu.
  - Preuve : —
  - Reste : —
