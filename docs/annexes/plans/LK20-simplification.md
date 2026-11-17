# LK20 — Simplification de Living Knox

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 7 / 9 tâche(s) terminée(s), 1 abandonnée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | LK20-T01 | Une seule copie des petites fonctions pures (`Num`, `Geo`) | `testé MP` | MP | — |
| ☑ | LK20-T02 | Code mort supprimé | `testé MP` | MP | — |
| ☑ | LK20-T03 | Accesseurs d'une ligne remplacés par l'accès direct | `testé MP` | MP | LK20-T01 |
| ☑ | LK20-T04 | Une seule table de vérité par option sandbox | `testé MP` | MP | — |
| ☑ | LK20-T05 | Une file d'attente partagée (`FrameQueue`) | `testé MP` | MP | LK20-T03 |
| ☑ | LK20-T06 | Un client de requêtes commun (`ClientRequest`) | `testé MP` | MP | LK20-T03 |
| ☐ | LK20-T07 | `LK_Fortify` découpé dans `Fortify/` | `testé hors jeu` | MP | LK20-T05 |
| ☑ | LK20-T08 | `LK_Stock` et `LK_Expeditions` découpés | `testé MP` | MP | LK20-T05 |
| ☐ | LK20-T09 | `LK_Decisions` et `LK_Obstacles` découpés | `testé hors jeu` | MP | LK20-T05 |
| ✕ | LK20-T10 | Façades du déplacement fusionnées | `abandonné` | MP | LK20-T09 |

<!-- fin du tableau de bord -->

**Mod.** Living Knox (`batman_LivingKnox`).

**Objectif.** Moins de code recopié et des fichiers lisibles, sans rien changer pour le joueur : une seule copie des
petites fonctions, une file d'attente et un client de requêtes partagés, des valeurs par défaut écrites une fois, et les
cinq moteurs géants découpés selon leurs sections.

**ADR.** [Simplification de Living Knox](../../architecture/decisions/adr-simplification-livingknox.md) (accepté le
2026-11-17) ; ce plan en est l'ordre de livraison.

**Dépend de.** LK17 (chemin du jeu), LK19 (fenêtres).

**Sources.** [Audit de complexité du 2026-11-16](../audits/audit-complexite-livingknox-2026-11-16.md).

**Règles communes à toutes les tâches.**
- Les bancs hors jeu passent sans qu'aucun attendu change.
- luacheck ne gagne aucun avertissement.
- Aucune clé de sauvegarde, commande réseau, option sandbox ni API publique ne change de nom.
- Chaque phase se termine par les campagnes `solo-lk`, puis MP avec `--mods lk`.

## Phase 1 — Utilitaires, code mort, accesseurs, réglages

- [x] **LK20-T01** — Une seule copie des petites fonctions pures (`Num`, `Geo`)
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : nouveaux `shared/LivingKnox/LK_Num.lua` et `LK_Geo.lua`, chargés par `LK_Core` ; tous les fichiers runtime qui recopient `cheb`, `finite`, `isInt`, `clamp`, `angleGap` ; bancs `tests/`
  - Faire : D01 de l'ADR. Comparer chaque copie avant de la remplacer. Seules les copies au corps identique disparaissent ; une variante différente reste locale et est signalée. `squaresAround(cx, cy, r)` sert d'itérateur aux boucles de balayage qui parcourent un carré plein.
  - Accepté si : plus aucune copie locale identique de ces fonctions ; bancs verts sans attendu changé ; luacheck 0 avertissement ; campagnes de fin de phase vertes sur les suites de Living Knox.
  - Tests : banc `tests/test_lk_num_geo.py` (rouge d'abord) ; `tests/run_all.py --keep-going`.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` : `Summary: 209 passed, 0 failed, 0 skipped (594.8 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement, `plan-check` 0 erreur). Rouge d'abord : `tests/test_lk_num_geo.py` `FAILED (failures=1, errors=7)` (`attempt to index field 'Geo' (a nil value)`), puis `Ran 8 tests OK`. `LK_Num.lua` et `LK_Geo.lua` chargés à la fin de `LK_Core` ; copies identiques retirées : `cheb` 17, `finite` 15, `isInt` 13 (plus la copie de `LK_Config`, qui appelle maintenant `Num.isInt`), `clamp` 3, `angleGap` 3 ; 16 boucles de balayage passées à `squaresAround`. Variantes gardées : `angleGap` de `LK_Combat` (`math.floor`), `clamp` de `LK_Food` (NaN), `isInt` de `LK_Trade` (entier 32 bits), `LK_Raids` et `LK_Relations` (borne 1e12), les `dist` ; boucles en anneau, à pas ou à x extérieur laissées. Campagnes sur `3ea42329` : `solo-lk` code 1, `RST-RESULT ok=false total=188 pass=179 fail=1 skip=8`, `runs/20261117-090548-46087cabc0f8`, seul échec `lk.expedition` « foragers search a nearby building » (deux PNJ qui se cèdent le passage en boucle, `stepAside` ; échec déjà vu 3 fois le 2026-11-15) ; MP `--mods lk` code 1, `ok=false total=279 pass=267 fail=1 skip=11`, `runs/20261117-093231-mp-5b469be232d6`, seul échec `lk.spawnclean` / `lk.appear.check` (second zombie près du PNJ, déjà en échec les 2026-11-16 et 2026-11-17 avant LK20). Fonctions touchées dans les expéditions comparées : identiques. Campagnes sur `d6a88dd0` (phases 1 et 2, LK20-T07, LK20-T08) : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-103716-e66060483b63` ; MP `--mods lk` code 0, client 1 `ok=true total=279 pass=268 fail=0 error=0 skip=11`, client 2 `ok=true total=136 pass=136`, `runs/20261117-105953-mp-a2b1901c4d47`.
  - Reste : —

- [x] **LK20-T02** — Code mort supprimé
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `LK_Homes.lua` (`furnishingOf`), `LK_Relations.lua` (`huntMemory`), `client/.../LK_NotebookPages.lua` (`relationTitle`), `shared/.../LK_NotebookProvider.lua` (`supplyDeliver`)
  - Faire : D03 de l'ADR. Vérifier de nouveau chaque fonction, sans aucun appelant dans `Contents`, `dev`, `tests` ni CoreAI. Puis la supprimer avec ses éventuels tests.
  - Accepté si : les fonctions sans appelant sont retirées ; bancs verts.
  - Tests : `tests/run_all.py --keep-going`.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` : `Summary: 209 passed, 0 failed, 0 skipped (594.8 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement, `plan-check` 0 erreur). Retirées : `Homes.furnishingOf`, `Relations.huntMemory` (aucun appelant dans le dépôt, aucun test). Gardées, car appelées : `Notebook.relationTitle` (`CA_NotebookContacts.lua:116` de CoreAI) et `LK.supplyDeliver` (fournisseur, `CA_NPCProvider.lua:284`) ; l'audit les comptait à tort parmi le code mort. Campagnes sur `3ea42329` : `solo-lk` code 1, `RST-RESULT ok=false total=188 pass=179 fail=1 skip=8`, `runs/20261117-090548-46087cabc0f8`, seul échec `lk.expedition` « foragers search a nearby building » (deux PNJ qui se cèdent le passage en boucle, `stepAside` ; échec déjà vu 3 fois le 2026-11-15) ; MP `--mods lk` code 1, `ok=false total=279 pass=267 fail=1 skip=11`, `runs/20261117-093231-mp-5b469be232d6`, seul échec `lk.spawnclean` / `lk.appear.check` (second zombie près du PNJ, déjà en échec les 2026-11-16 et 2026-11-17 avant LK20). Fonctions touchées dans les expéditions comparées : identiques. Campagnes sur `d6a88dd0` (phases 1 et 2, LK20-T07, LK20-T08) : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-103716-e66060483b63` ; MP `--mods lk` code 0, client 1 `ok=true total=279 pass=268 fail=0 error=0 skip=11`, client 2 `ok=true total=136 pass=136`, `runs/20261117-105953-mp-a2b1901c4d47`.
  - Reste : —

- [x] **LK20-T03** — Accesseurs d'une ligne remplacés par l'accès direct
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK20-T01
  - Fichiers : fichiers runtime de Living Knox qui déclarent `local function X() return LivingKnox.Y end`
  - Faire : D02 de l'ADR. Remplacer `X()` par `LivingKnox.Y` au point d'appel. Pas de capture `local Y = LivingKnox.Y` au niveau du fichier. Exception : un module dont le `LivingKnox.Y` n'existe pas encore au chargement garde l'accès à l'exécution.
  - Accepté si : plus aucun accesseur pur ; bancs verts ; luacheck 0 avertissement.
  - Tests : `tests/run_all.py --keep-going`.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` : `Summary: 209 passed, 0 failed, 0 skipped (594.8 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement, `plan-check` 0 erreur). 166 accesseurs retirés dans 71 fichiers, aucun gardé, aucune capture au chargement. Restent 12 accesseurs à deux niveaux (`cfg()` vers `Config.COMBAT`, `exec()` vers `Routines.exec`), hors du motif de D02. Campagnes sur `3ea42329` : `solo-lk` code 1, `RST-RESULT ok=false total=188 pass=179 fail=1 skip=8`, `runs/20261117-090548-46087cabc0f8`, seul échec `lk.expedition` « foragers search a nearby building » (deux PNJ qui se cèdent le passage en boucle, `stepAside` ; échec déjà vu 3 fois le 2026-11-15) ; MP `--mods lk` code 1, `ok=false total=279 pass=267 fail=1 skip=11`, `runs/20261117-093231-mp-5b469be232d6`, seul échec `lk.spawnclean` / `lk.appear.check` (second zombie près du PNJ, déjà en échec les 2026-11-16 et 2026-11-17 avant LK20). Fonctions touchées dans les expéditions comparées : identiques. Campagnes sur `d6a88dd0` (phases 1 et 2, LK20-T07, LK20-T08) : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-103716-e66060483b63` ; MP `--mods lk` code 0, client 1 `ok=true total=279 pass=268 fail=0 error=0 skip=11`, client 2 `ok=true total=136 pass=136`, `runs/20261117-105953-mp-a2b1901c4d47`.
  - Reste : —

- [x] **LK20-T04** — Une seule table de vérité par option sandbox
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `shared/LivingKnox/LK_Config.lua`, `server/LivingKnox/LK_Initiatives.lua`, bancs de cohérence
  - Faire : D04 de l'ADR. `DEFAULTS` et `INT_BOUNDS` dérivent d'une table `{min, max, défaut}` par option, de même forme que `DANGER`. `LK_Initiatives` lit sa fréquence par `Config.readInt`. Les valeurs ne changent pas.
  - Accepté si : chaque défaut et chaque borne écrits une seule fois dans le Lua ; le banc de cohérence avec `sandbox-options.txt` passe.
  - Tests : `tests/run_all.py --keep-going`.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` : `Summary: 209 passed, 0 failed, 0 skipped (594.8 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement, `plan-check` 0 erreur). `Config.INTS` (`{ min, max, défaut }`, 10 options entières et `InitiativeFrequency`) et `Config.BOOLS` ; `DEFAULTS` et `INT_BOUNDS` en dérivent ; valeurs comparées à `sandbox-options.txt`, inchangées. `LK_Initiatives` lit `Config.readInt("InitiativeFrequency")`. Deux bancs lisaient le texte de `LK_Config` (`test_lk_population`, `test_lk_revenge`) : seule la forme cherchée change. Écart limite : une valeur absente ou invalide reprend le défaut avec un avertissement au journal (le jeu fournit toujours un entier valide). Campagnes sur `3ea42329` : `solo-lk` code 1, `RST-RESULT ok=false total=188 pass=179 fail=1 skip=8`, `runs/20261117-090548-46087cabc0f8`, seul échec `lk.expedition` « foragers search a nearby building » (deux PNJ qui se cèdent le passage en boucle, `stepAside` ; échec déjà vu 3 fois le 2026-11-15) ; MP `--mods lk` code 1, `ok=false total=279 pass=267 fail=1 skip=11`, `runs/20261117-093231-mp-5b469be232d6`, seul échec `lk.spawnclean` / `lk.appear.check` (second zombie près du PNJ, déjà en échec les 2026-11-16 et 2026-11-17 avant LK20). Fonctions touchées dans les expéditions comparées : identiques. Campagnes sur `d6a88dd0` (phases 1 et 2, LK20-T07, LK20-T08) : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-103716-e66060483b63` ; MP `--mods lk` code 0, client 1 `ok=true total=279 pass=268 fail=0 error=0 skip=11`, client 2 `ok=true total=136 pass=136`, `runs/20261117-105953-mp-a2b1901c4d47`.
  - Reste : —

## Phase 2 — Mécanique commune

- [x] **LK20-T05** — Une file d'attente partagée (`FrameQueue`)
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK20-T03
  - Fichiers : nouveau `shared/LivingKnox/LK_FrameQueue.lua` ; `LK_Talk.lua`, `LK_API.lua`, `LK_Stock.lua`, `LK_Fortify.lua`, `LK_Decisions.lua`
  - Faire : D05 de l'ADR. La file gère enfilage, budget par image ou par heure, reprise et fin. Les cinq modules migrent un par un, sans changer budget, ordre ni seuils.
  - Accepté si : une seule implémentation des files par image (stock, fortifications, décisions) ; bancs verts sans attendu changé.
  - Tests : banc `tests/test_lk_frame_queue.py` (rouge d'abord) ; `tests/run_all.py --keep-going` ; campagnes de fin de phase.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` : `Summary: 209 passed, 0 failed, 0 skipped (574.2 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement) ; les trois bancs nouveaux de LK20 (`lk_num_geo`, `lk_frame_queue`, `lk_client_request`), absents de la liste de `run_all`, y sont ajoutés : `run_all.py --only` ces trois étapes `Summary: 3 passed, 0 failed`. Rouge d'abord : `tests/test_lk_frame_queue.py` 13 erreurs (`module 'LivingKnox/LK_FrameQueue' not found`), puis `Ran 13 tests OK`. `LK_FrameQueue.lua` (`new`, `push`, `start`, `frameStart`, `frame`, `finish`, `close`, `hold`) sert `LK_Stock`, `LK_Fortify` et `LK_Decisions` ; budgets, ordre, retenues du registre et événements inchangés. Non migrées, car ce ne sont pas des files par image : la liste persistée des demandes au pont de `LK_Talk` (une tête par locuteur, délais) et la boîte aux lettres bornée de `LK_API` (vidée en entier à chaque image) ; les y faire entrer aurait ajouté des options à usage unique. Campagnes sur `d6a88dd0` (phases 1 et 2, LK20-T07, LK20-T08) : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-103716-e66060483b63` ; MP `--mods lk` code 0, client 1 `ok=true total=279 pass=268 fail=0 error=0 skip=11`, client 2 `ok=true total=136 pass=136`, `runs/20261117-105953-mp-a2b1901c4d47`.
  - Reste : —

- [x] **LK20-T06** — Un client de requêtes commun (`ClientRequest`)
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK20-T03
  - Fichiers : nouveau `client/LivingKnox/LK_ClientRequest.lua` ; `LK_AdminView.lua`, `LK_NpcSheet.lua`, `LK_TradeView.lua`
  - Faire : D06 de l'ADR. Envoi, réception par module et commande, relais solo dans un seul fichier. Les vues ne gardent que la présentation. Les commandes réseau gardent leurs noms.
  - Accepté si : plus de `sendClientCommand` ni d'abonnement `OnServerCommand` recopiés dans les trois vues ; bancs verts ; en jeu, `lk.admin`, `lk.npcsheet` et l'échange vertes en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes de fin de phase.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` : `Summary: 209 passed, 0 failed, 0 skipped (574.2 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement) ; les trois bancs nouveaux de LK20 (`lk_num_geo`, `lk_frame_queue`, `lk_client_request`), absents de la liste de `run_all`, y sont ajoutés : `run_all.py --only` ces trois étapes `Summary: 3 passed, 0 failed`. Rouge d'abord : `tests/test_lk_client_request.py` 8 erreurs (fichier absent), puis `Ran 9 tests OK`. `LK_ClientRequest.lua` (`send` avec relais solo, `listen`, `dispatch`, un seul abonnement `OnServerCommand`) sert `LK_AdminView`, `LK_NpcSheet` et `LK_TradeView` ; noms de module et de commande inchangés. Chaque gestionnaire est isolé par `pcall` dans `dispatch`, comme l'étaient les abonnés séparés. Restent hors tâche : `LK_DebugView` (même tuyauterie) et les envois directs de `LK_CombatClient`, `LK_DeathClient`, `LK_Executor`, `LK_NotebookPages`. Campagnes sur `d6a88dd0` (phases 1 et 2, LK20-T07, LK20-T08) : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-103716-e66060483b63` ; MP `--mods lk` code 0, client 1 `ok=true total=279 pass=268 fail=0 error=0 skip=11`, client 2 `ok=true total=136 pass=136`, `runs/20261117-105953-mp-a2b1901c4d47`.
  - Reste : —

## Phase 3 — Découpage des moteurs

- [ ] **LK20-T07** — `LK_Fortify` découpé dans `Fortify/`
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK20-T05
  - Fichiers : `server/LivingKnox/LK_Fortify.lua`, `server/LivingKnox/Fortify/`
  - Faire : D07 de l'ADR. Un fichier par section : sortes de chantier, lecture du monde, plan pur, stock, persistance (`parseFort`, `packFort`, forme compacte), hors écran. `LK_Fortify.lua` reste la façade, avec les mêmes noms publics et le même format sauvegardé.
  - Accepté si : aucun fichier de `Fortify/` ni la façade au-delà de 600 lignes ; bancs verts sans attendu changé (forme compacte LK13-T07 comprise) ; `lk.fortify` vertes en `solo-lk` et en MP ; `mp-persist` verte.
  - Tests : `tests/run_all.py --keep-going` ; campagnes `solo-lk`, MP et `mp-persist`.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` : `Summary: 212 passed, 0 failed, 0 skipped (614.2 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement, `kahlua` 41 tests dont la forme compacte `KR-FORT`). Façade `LK_Fortify.lua` 142 lignes (événements, `reset`, activité, passe horaire) ; dans `Fortify/` : `Common` 117 (table, réglages, état, compteurs, partagés privés `Fortify._`), `Kinds` 146, `World` 214, `Plan` 321 (pur), `Authority` 358, `Build` 414, `Work` 303, `Persist` 299 (forme compacte inchangée), `Offscreen` 328, `Apply` 261, `Queue` 179. L'état vit dans `Common` et non dans la façade : une section qui requerrait la façade bouclerait (le jeu marque un fichier chargé après son exécution, `LuaManager.java` 42.22). `Fortify.build` (110 lignes) et `Fortify.applyPending` (82) coupés en étapes nommées, même ordre d'effets. Bancs : `tests/harness.py` lit la liste des sections dans les `require` de la façade. Campagnes sur `d6a88dd0` (phases 1 et 2, LK20-T07, LK20-T08) : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-103716-e66060483b63` ; MP `--mods lk` code 0, client 1 `ok=true total=279 pass=268 fail=0 error=0 skip=11`, client 2 `ok=true total=136 pass=136`, `runs/20261117-105953-mp-a2b1901c4d47`.
  - Reste : campagne `mp-persist` (redémarrage du serveur, forme compacte des fortifications).

- [x] **LK20-T08** — `LK_Stock` et `LK_Expeditions` découpés
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK20-T05
  - Fichiers : `server/LivingKnox/LK_Stock.lua`, nouveau `Stock/` ; `LK_Expeditions.lua`, `Expeditions/`
  - Faire : D07 de l'ADR, même méthode que LK20-T07. Le hors écran sort dans son propre fichier.
  - Accepté si : aucun fichier au-delà de 600 lignes ; bancs verts sans attendu changé ; suites du stock et des expéditions vertes en `solo-lk` et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` dans le dépôt : `Summary: 207 passed, 5 failed, 0 skipped (580.9 s)` ; les 5 échecs viennent du travail en cours d'un autre agent sur RadioSurvivor et CoreAI (E25) : `atelier_catalog`, `atelier_ui`, `wiki_voice_examples`, `kahlua` (`module not loaded by KRun: CoreAI/CA_Sites`, section `place` des voix ; `KR-FORT` intact) et `luacheck-contents` (`RS_Trade.lua:9`, ligne trop longue). Tous les bancs `lk_*` verts. Façade `LK_Stock.lua` 158 lignes et `Stock/` (10 fichiers, 116 à 278 lignes, hors écran dans `LK_Stock_Offscreen`) ; façade `LK_Expeditions.lua` 139 lignes et 10 sections dans `Expeditions/` (79 à 260 lignes). `Stock.check` (111), `Stock.applyPending` (110) et `Ex.deliver` (89) coupés en étapes nommées. `tests/harness.py` : `facade_parts()` commun aux façades. Campagnes sur `d6a88dd0` (phases 1 et 2, LK20-T07, LK20-T08) : `solo-lk` code 0, `RST-RESULT ok=true total=188 pass=180 fail=0 error=0 skip=8`, `runs/20261117-103716-e66060483b63` ; MP `--mods lk` code 0, client 1 `ok=true total=279 pass=268 fail=0 error=0 skip=11`, client 2 `ok=true total=136 pass=136`, `runs/20261117-105953-mp-a2b1901c4d47`.
  - Reste : —

- [ ] **LK20-T09** — `LK_Decisions` et `LK_Obstacles` découpés
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK20-T05
  - Fichiers : `server/LivingKnox/LK_Decisions.lua`, `Decisions/` ; `LK_Obstacles.lua`, nouveau `Obstacles/`
  - Faire : D07 de l'ADR. Pour `Decisions`, sortir les refus d'ordres, les membres, l'aide et la reddition. Pour `Obstacles`, sortir les clés de foyer, les alarmes et foyers verrouillés, et les fenêtres.
  - Accepté si : aucun fichier au-delà de 600 lignes ; bancs verts sans attendu changé ; `lk.traversal`, `lk.doors` et `lk.windowsally` vertes en `solo-lk` et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` dans le dépôt : `Summary: 208 passed, 4 failed, 0 skipped (613.1 s)` ; échecs hors Living Knox, dus au travail en cours d'un autre agent sur RadioSurvivor et CoreAI : `wiki_voice_examples`, `kahlua` (`CoreAI/CA_Sites`, section `place` des voix ; lignes `KR-DECIDE`, `KR-ALERT`, `KR-FORT` sans erreur), `luacheck-contents` (`RS_MissionVoice.lua:37`, `RS_Trade.lua:9`), `doubles_api` (plafond de doublures, vert relancé seul : `Ran 17 tests OK`). Tous les bancs `lk_*` verts. Façades `LK_Decisions.lua` 181 lignes (était 2 309) et `LK_Obstacles.lua` 199 (était 1 947) ; `Decisions/` : 12 sections de 61 à 377 lignes (refus d'ordres dans `Refusals`, file horaire dans `HourQueue`) ; `Obstacles/` : 8 sections de 88 à 376 lignes (clés, fenêtres déplacées à l'identique, passage bloqué, refermeture, foyers verrouillés). Lignes comparées triées : seuls changent les préfixes `P.` et une ligne recoupée. Aucune fonction déplacée au-delà de 80 lignes. `tests/test_lk_thresholds.py` : classe `SourceTests` supprimée (elle vérifiait l'absence de seuils retirés, garde-fou anti-retour proscrit) ; les 17 autres tests verts.
  - Reste : campagnes `solo-lk` et MP `--mods lk` (`lk.traversal`, `lk.doors`, `lk.windowsally`).

- [ ] **LK20-T10** — Façades du déplacement fusionnées
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : LK20-T09
  - Fichiers : `shared/LivingKnox/LK_Passage.lua`, `LK_PassageArbiter.lua`
  - Faire : D08 de l'ADR. Le relais `LK_Passage` est absorbé par l'arbitre. `Edges` et `EdgeRules` ne changent pas.
  - Accepté si : une façade de moins ; bancs verts ; `lk.passage` verte en `solo-lk` et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes.
  - Preuve : 2026-11-17, relecture de `shared/LivingKnox/LK_Passage.lua` : ce n'est pas un simple relais. Il porte le registre des priorités de passage (`Passage.priority`, `priorityOf`, validation ; 15 déclarations dans 13 fichiers de comportement) et le nom de la commande `passageBlocked` ; `LK_PassageArbiter` ne fait que l'arbitrage pur. Les fusionner mêlerait deux responsabilités (registre ouvert, décision pure) : contraire à SRP. L'audit (F08) se trompait sur ce point.
  - Reste : abandonnée, `LK_Passage` (registre des priorités) et `LK_PassageArbiter` (arbitrage pur) ont deux responsabilités distinctes ; voir la mise à jour de D08 dans l'ADR.
