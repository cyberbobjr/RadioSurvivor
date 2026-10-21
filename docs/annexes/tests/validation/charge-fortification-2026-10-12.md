# Relevé de fortification compact au registre des groupes : mesure avant / après (LK13-T07)

- **Date** : 2026-10-12. **Statut** : mesure hors jeu (lupa et VM Kahlua de `projectzomboid.jar`), **aucune mesure en
  jeu**. Méthode, scénario et limites : [charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md) (LK13-T02) ;
  étape précédente : [charge-groupes-2026-10-12.md](charge-groupes-2026-10-12.md) (LK13-T06) ; conception :
  [fortification.md](../../conception/fortification.md) §10.3.
- **Avant** : arbre du commit `28402b4` (export `git archive`, sans les fichiers non commités d'autres tâches).
  **Après** : même arbre plus `LK_Fortify.lua` de LK13-T07. Les deux avec le même `tools/load_bench.py` (options
  `--dump-groups` et `--registry` ajoutées par cette tâche). Machine partagée : quelques ms de bruit sur les pointes.
- **Commandes** (mêmes options avant et après) :

```powershell
python RadioSurvivor/tools/load_bench.py --minutes 60 --quiet --dump-groups g60.hex
python RadioSurvivor/tools/load_bench.py --minutes 1440 --quiet --dump-groups g1440.hex
python RadioSurvivor/tools/load_bench.py --kahlua --registry g1440.hex
```

## 1. Taille du registre des groupes (hex, comme le fichier écrit)

| Mesure | Avant | Après | Rapport |
|---|---|---|---|
| Registre des groupes, 1re heure | 113 404 o | 39 396 o | ÷ 2,88 |
| **Registre des groupes, journée** | **117 130 o** | **43 122 o** | **÷ 2,72** |
| dont champ `fort` (5 groupes) | 83 240 o (71 %) | 9 232 o (21 %) | ÷ 9,0 |

Champ par groupe au banc (camp, 57 segments de palissade à faire) : 16,6 Ko → 1,8 Ko. Les champs les plus lourds du
registre sont désormais `members` (11,5 Ko) et `log` (10,8 Ko). **Critère « registre divisé par deux au moins » :
atteint** (÷ 2,72).

## 2. Coût d'une écriture

| Mesure (journée) | Avant | Après |
|---|---|---|
| Écritures `LKGRP1`, lupa | 38, 8,5 ms (max 15,8) | 38, 3,3 ms (max 6,9) |
| Écritures `LKGRP1`, 1re heure, lupa | 15, 7,7 ms (max 11,6) | 15, 2,6 ms (max 3,7) |
| Écriture du registre réel de fin de journée, **Kahlua** (`--kahlua --registry` : encodage RSV2, hex par table, somme par blocs, sans relecture) | **35,6 ms** (7,3 ms lupa) | **12,9 ms** (2,2 ms lupa) |
| Registre type de référence (`--kahlua`, inchangé, contrôle de la machine) | 31,5 ms | 34,4 ms |

Deux relances supplémentaires de la journée : écritures 3,1 et 3,3 ms après, 9,0 et 9,3 ms avant.

## 3. Image la plus lourde et modules

| Mesure | Avant | Après |
|---|---|---|
| Moteur par image, journée (3 passages) | 0,525 / 0,594 / 0,662 ms | 0,503 / 0,447 / 0,524 ms |
| Image la plus lourde, journée (3 passages) | 55,2 / 47,9 / 46,0 ms | 41,0 / 48,0 / 39,6 ms |
| Image la plus lourde, 1re heure | 51,7 ms | 42,2 ms |
| `Fortify.onEveryOneMinute`, moyenne (journée, 3 passages) | 0,33 / 0,38 / 0,41 ms | 0,27 / 0,23 / 0,28 ms |
| `Fortify.onEveryOneMinute`, plus lourd appel | 9,4 / 15,0 / 12,6 ms | 19,5 / 14,2 / 16,5 ms |

La pointe d'un appel de `Fortify` reste dans le bruit du banc (9 à 20 ms dans les deux cas : relevé du monde du plan
expiré) ; la vue de travail est relue en mémoire tant que le relevé n'a pas changé. L'image la plus lourde baisse
d'environ 10 ms lupa mais **reste au-dessus du budget proposé de 25 ms Kahlua** : elle vient de la création des corps
(`Bodies.tick`, écritures du registre des PNJ, tâche LK13-T10), pas du registre des groupes.

## 4. Garanties vérifiées (bancs)

- `tests/test_lk_fortify_offscreen.py` (17 tests, dont 5 nouveaux `CompactFormTests`) : forme compacte au registre ;
  ancienne forme avec écarts en attente convertie puis posée une fois ; application interrompue avant la conversion
  reprise sans double pose (marques `LKFortOp` inchangées) ; heure hors écran sur l'ancienne forme. Rattrapage hors
  écran et pose à l'arrivée : les 12 tests de LK14-T05 inchangés et verts.
- `tests/test_lk_fortify.py`, `test_lk_walls.py`, `test_lk_repair.py`, `test_lk_barricade.py` verts sans changement.
- VM Kahlua (`tests/test_kahlua.py`, `KR-FORT`) : mêmes chaînes que sous lupa, nombres entiers concaténés sans `.0`,
  identifiant de boîte négatif sur 31 bits, chaîne mal formée refusée.
