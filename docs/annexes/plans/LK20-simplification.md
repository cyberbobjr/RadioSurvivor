# LK20 — Simplification de Living Knox

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** à faire — 0 / 10 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | LK20-T01 | Une seule copie des petites fonctions pures (`Num`, `Geo`) | `à faire` | MP | — |
| ☐ | LK20-T02 | Code mort supprimé | `à faire` | MP | — |
| ☐ | LK20-T03 | Accesseurs d'une ligne remplacés par l'accès direct | `à faire` | MP | LK20-T01 |
| ☐ | LK20-T04 | Une seule table de vérité par option sandbox | `à faire` | MP | — |
| ☐ | LK20-T05 | Une file d'attente partagée (`FrameQueue`) | `à faire` | MP | LK20-T03 |
| ☐ | LK20-T06 | Un client de requêtes commun (`ClientRequest`) | `à faire` | MP | LK20-T03 |
| ☐ | LK20-T07 | `LK_Fortify` découpé dans `Fortify/` | `à faire` | MP | LK20-T05 |
| ☐ | LK20-T08 | `LK_Stock` et `LK_Expeditions` découpés | `à faire` | MP | LK20-T05 |
| ☐ | LK20-T09 | `LK_Decisions` et `LK_Obstacles` découpés | `à faire` | MP | LK20-T05 |
| ☐ | LK20-T10 | Façades du déplacement fusionnées | `à faire` | MP | LK20-T09 |

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

- [ ] **LK20-T01** — Une seule copie des petites fonctions pures (`Num`, `Geo`)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : nouveaux `shared/LivingKnox/LK_Num.lua` et `LK_Geo.lua`, chargés par `LK_Core` ; tous les fichiers runtime qui recopient `cheb`, `finite`, `isInt`, `clamp`, `angleGap` ; bancs `tests/`
  - Faire : D01 de l'ADR. Comparer chaque copie avant de la remplacer. Seules les copies au corps identique disparaissent ; une variante différente reste locale et est signalée. `squaresAround(cx, cy, r)` sert d'itérateur aux boucles de balayage qui parcourent un carré plein.
  - Accepté si : plus aucune copie locale identique de ces fonctions ; bancs verts sans attendu changé ; luacheck 0 avertissement ; campagnes de fin de phase vertes sur les suites de Living Knox.
  - Tests : banc `tests/test_lk_num_geo.py` (rouge d'abord) ; `tests/run_all.py --keep-going`.

- [ ] **LK20-T02** — Code mort supprimé
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `LK_Homes.lua` (`furnishingOf`), `LK_Relations.lua` (`huntMemory`), `client/.../LK_NotebookPages.lua` (`relationTitle`), `shared/.../LK_NotebookProvider.lua` (`supplyDeliver`)
  - Faire : D03 de l'ADR. Vérifier de nouveau chaque fonction, sans aucun appelant dans `Contents`, `dev`, `tests` ni CoreAI. Puis la supprimer avec ses éventuels tests.
  - Accepté si : les fonctions sans appelant sont retirées ; bancs verts.
  - Tests : `tests/run_all.py --keep-going`.

- [ ] **LK20-T03** — Accesseurs d'une ligne remplacés par l'accès direct
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK20-T01
  - Fichiers : fichiers runtime de Living Knox qui déclarent `local function X() return LivingKnox.Y end`
  - Faire : D02 de l'ADR. Remplacer `X()` par `LivingKnox.Y` au point d'appel. Pas de capture `local Y = LivingKnox.Y` au niveau du fichier. Exception : un module dont le `LivingKnox.Y` n'existe pas encore au chargement garde l'accès à l'exécution.
  - Accepté si : plus aucun accesseur pur ; bancs verts ; luacheck 0 avertissement.
  - Tests : `tests/run_all.py --keep-going`.

- [ ] **LK20-T04** — Une seule table de vérité par option sandbox
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `shared/LivingKnox/LK_Config.lua`, `server/LivingKnox/LK_Initiatives.lua`, bancs de cohérence
  - Faire : D04 de l'ADR. `DEFAULTS` et `INT_BOUNDS` dérivent d'une table `{min, max, défaut}` par option, de même forme que `DANGER`. `LK_Initiatives` lit sa fréquence par `Config.readInt`. Les valeurs ne changent pas.
  - Accepté si : chaque défaut et chaque borne écrits une seule fois dans le Lua ; le banc de cohérence avec `sandbox-options.txt` passe.
  - Tests : `tests/run_all.py --keep-going`.

## Phase 2 — Mécanique commune

- [ ] **LK20-T05** — Une file d'attente partagée (`FrameQueue`)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK20-T03
  - Fichiers : nouveau `shared/LivingKnox/LK_FrameQueue.lua` ; `LK_Talk.lua`, `LK_API.lua`, `LK_Stock.lua`, `LK_Fortify.lua`, `LK_Decisions.lua`
  - Faire : D05 de l'ADR. La file gère enfilage, budget par image ou par heure, reprise et fin. Les cinq modules migrent un par un, sans changer budget, ordre ni seuils.
  - Accepté si : une seule implémentation de file ; bancs verts sans attendu changé.
  - Tests : banc `tests/test_lk_frame_queue.py` (rouge d'abord) ; `tests/run_all.py --keep-going` ; campagnes de fin de phase.

- [ ] **LK20-T06** — Un client de requêtes commun (`ClientRequest`)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK20-T03
  - Fichiers : nouveau `client/LivingKnox/LK_ClientRequest.lua` ; `LK_AdminView.lua`, `LK_NpcSheet.lua`, `LK_TradeView.lua`
  - Faire : D06 de l'ADR. Envoi, réception par module et commande, relais solo dans un seul fichier. Les vues ne gardent que la présentation. Les commandes réseau gardent leurs noms.
  - Accepté si : plus de `sendClientCommand` ni d'abonnement `OnServerCommand` recopiés dans les trois vues ; bancs verts ; en jeu, `lk.admin`, `lk.npcsheet` et l'échange vertes en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes de fin de phase.

## Phase 3 — Découpage des moteurs

- [ ] **LK20-T07** — `LK_Fortify` découpé dans `Fortify/`
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK20-T05
  - Fichiers : `server/LivingKnox/LK_Fortify.lua`, `server/LivingKnox/Fortify/`
  - Faire : D07 de l'ADR. Un fichier par section : sortes de chantier, lecture du monde, plan pur, stock, persistance (`parseFort`, `packFort`, forme compacte), hors écran. `LK_Fortify.lua` reste la façade, avec les mêmes noms publics et le même format sauvegardé.
  - Accepté si : aucun fichier de `Fortify/` ni la façade au-delà de 600 lignes ; bancs verts sans attendu changé (forme compacte LK13-T07 comprise) ; `lk.fortify` vertes en `solo-lk` et en MP ; `mp-persist` verte.
  - Tests : `tests/run_all.py --keep-going` ; campagnes `solo-lk`, MP et `mp-persist`.

- [ ] **LK20-T08** — `LK_Stock` et `LK_Expeditions` découpés
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK20-T05
  - Fichiers : `server/LivingKnox/LK_Stock.lua`, nouveau `Stock/` ; `LK_Expeditions.lua`, `Expeditions/`
  - Faire : D07 de l'ADR, même méthode que LK20-T07. Le hors écran sort dans son propre fichier.
  - Accepté si : aucun fichier au-delà de 600 lignes ; bancs verts sans attendu changé ; suites du stock et des expéditions vertes en `solo-lk` et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes.

- [ ] **LK20-T09** — `LK_Decisions` et `LK_Obstacles` découpés
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK20-T05
  - Fichiers : `server/LivingKnox/LK_Decisions.lua`, `Decisions/` ; `LK_Obstacles.lua`, nouveau `Obstacles/`
  - Faire : D07 de l'ADR. Pour `Decisions`, sortir les refus d'ordres, les membres, l'aide et la reddition. Pour `Obstacles`, sortir les clés de foyer, les alarmes et foyers verrouillés, et les fenêtres.
  - Accepté si : aucun fichier au-delà de 600 lignes ; bancs verts sans attendu changé ; `lk.traversal`, `lk.doors` et `lk.windowsally` vertes en `solo-lk` et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes.

- [ ] **LK20-T10** — Façades du déplacement fusionnées
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK20-T09
  - Fichiers : `shared/LivingKnox/LK_Passage.lua`, `LK_PassageArbiter.lua`
  - Faire : D08 de l'ADR. Le relais `LK_Passage` est absorbé par l'arbitre. `Edges` et `EdgeRules` ne changent pas.
  - Accepté si : une façade de moins ; bancs verts ; `lk.passage` verte en `solo-lk` et en MP.
  - Tests : `tests/run_all.py --keep-going` ; campagnes.
