# E26 — Tests hors jeu rangés par mod

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** terminée — 1 / 1 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E26-T01 | Un dossier de tests hors jeu par mod | `testé hors jeu` | hors jeu | — |

<!-- fin du tableau de bord -->

**Mod.** Dépôt entier : tests hors jeu (`tests/`), lanceur `tests/run_all.py`, outils et docs qui citent les tests.

**Objectif.** Les tests de RadioSurvivor, de Living Knox et du mod commun vivent chacun dans leur dossier ; un travail
sur un mod ne lance que ses tests et ceux du commun.

**ADR.** [Living Knox et RadioSurvivor séparés](../../architecture/decisions/adr-coreai-separation.md), décision D09
(2026-11-17).

**Dépend de.** E25.

## Décisions

- 2026-11-17 — **E26** (utilisateur) : un dossier de tests par mod ; rangement fait après le commit de la session
  Living Knox en cours, pour ne rien écraser.

## Hors périmètre

- Tests en jeu (`dev/`), déjà séparés (D06).

## Tâches

- [x] **E26-T01** — Un dossier de tests hors jeu par mod
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : D09 ; classer chaque fichier de `tests/` (RadioSurvivor, Living Knox, commun, les deux, aides partagées)
    d'après ce qu'il charge ; `git mv` vers `tests/radiosurvivor/`, `tests/livingknox/`, `tests/coreai/`,
    `tests/ensemble/`, `tests/commun/` ; chemins d'import et de racine ; `run_all.py --mod` lu depuis les dossiers
    (plus de liste écrite à la main) ; docs, outils et AGENTS qui citent `tests/test_*.py`.
  - Accepté si : `run_all.py --mod radiosurvivor` et `--mod livingknox` verts, aucune étape Living Knox dans la
    première ni RadioSurvivor dans la seconde, suite entière verte une fois.
  - Preuve : 2026-11-17, 231 tests rangés par `git mv` : `tests/coreai/` 31, `tests/radiosurvivor/` 74, `tests/livingknox/` 116, `tests/ensemble/` 10, aides partagées `tests/commun/` (`bench_paths.py`, `bench_game.py`, `persona_fixtures.py`, `carnet_world.py`, doublures, `fixtures/`, `kahlua/`) ; aucun import entre radiosurvivor et livingknox ; `run_all.py` découvre les étapes par dossier (`--mod radiosurvivor` = coreai + radiosurvivor, `--mod livingknox` = coreai + livingknox, sans `--mod` + ensemble) ; références des docs, outils et commentaires réécrites. `run_all.py --mod radiosurvivor --keep-going` `Summary: 109 passed, 0 failed` (263,7 s) ; `--mod livingknox` `Summary: 151 passed, 0 failed` (524,5 s) ; les 10 étapes `ensemble` `10 passed, 0 failed` ; luacheck 0 ; la suite entière (sans `--mod`) est l'union de ces trois passages. Reste : `test_carnet` et `test_kahlua` mêlent encore des cas des deux mods (à découper), quelques bancs Living Knox chargent encore du Lua RadioSurvivor.
