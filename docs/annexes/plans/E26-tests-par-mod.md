# E26 — Tests hors jeu rangés par mod

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** à faire — 0 / 1 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | E26-T01 | Un dossier de tests hors jeu par mod | `à faire` | hors jeu | — |

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

- [ ] **E26-T01** — Un dossier de tests hors jeu par mod
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : D09 ; classer chaque fichier de `tests/` (RadioSurvivor, Living Knox, commun, les deux, aides partagées)
    d'après ce qu'il charge ; `git mv` vers `tests/radiosurvivor/`, `tests/livingknox/`, `tests/coreai/`,
    `tests/ensemble/`, `tests/commun/` ; chemins d'import et de racine ; `run_all.py --mod` lu depuis les dossiers
    (plus de liste écrite à la main) ; docs, outils et AGENTS qui citent `tests/test_*.py`.
  - Accepté si : `run_all.py --mod radiosurvivor` et `--mod livingknox` verts, aucune étape Living Knox dans la
    première ni RadioSurvivor dans la seconde, suite entière verte une fois.
