# Écriture regroupée du registre des groupes : mesure avant / après (LK13-T06)

- **Date** : 2026-10-12. **Statut** : mesure hors jeu (lupa et VM Kahlua de `projectzomboid.jar`), **aucune mesure en
  jeu**. Méthode, scénario et limites : [charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md) (LK13-T02) ;
  conception : [groupes.md](../../conception/groupes.md), section « Écriture regroupée ».
- **Avant** : branche `dev` au commit `9a871eb` plus les fichiers non commités des autres tâches en cours (aucun ne
  touche à l'écriture des registres). **Après** : même arbre plus LK13-T06 (`LK_Groups.lua`, `LK_Store.lua`, appels
  `Groups.flush()` de `LK_Stock`, `LK_Fortify`, `LK_Homes`, `LK_Traces`, `LK_Trade`).
- **Commandes** (mêmes options avant et après ; machine partagée avec un autre banc : quelques dixièmes de ms de bruit
  sur les moyennes) :

```powershell
python RadioSurvivor/tools/load_bench.py --minutes 60 --quiet --json after60.json
python RadioSurvivor/tools/load_bench.py --minutes 1440 --quiet --json after1440.json
python RadioSurvivor/tools/load_bench.py --kahlua
```

## 1. Serveur, temps lupa

| Mesure | Avant, 1re heure | Après, 1re heure | Avant, journée | Après, journée |
|---|---|---|---|---|
| Moteur par image, moyenne | 0,997 ms | 0,609 ms | 0,549 ms | 0,496 ms |
| **Image la plus lourde** | **105,4 ms** | **44,4 ms** | **114,0 ms** | **47,4 ms** |
| Écritures `LKGRP1` | 24, 27,0 ms chacune (max 35,9) | 15, 7,2 ms (max 9,3) | 75, 31,4 ms (max 41,0) | 38, 8,5 ms (max 14,5) |
| Temps total des écritures `LKGRP1` | — | — | 2 355 ms | 324 ms |
| Écritures `LKREG1` (registre des PNJ, inchangé) | 20, 9,2 ms | 20, 8,1 ms | 20, 8,6 ms | 20, 7,9 ms |

Par abonné sur la journée (ms par appel, plus lourd appel) :

| Abonné | Avant | Après |
|---|---|---|
| `Simulation.onEveryHours` | 33,0 (max 38,4) | 0,33 (max 1,1) |
| `Needs.onEveryHours` | 33,7 (max 41,1) | 0,10 (max 0,2) |
| `Decisions.onEveryHours` | 9,5 (max 38,9) | 0,94 (max 1,9) |
| `Decisions.tick` (plus lourde image) | max 78,1 | max 7,7 |
| `Bodies.tick` (création des corps, plus lourde image) | max 91,9 | max 38,9 |
| `Fortify.onEveryOneMinute` (plus lourde image) | max 38,4 | max 8,7 |
| `Groups.flush` (nouveau : écriture de fin d'image) | — | 0,009 en moyenne, max 14,5 |

L'heure de jeu, qui faisait trois écritures complètes dans la même image (`Simulation`, `Needs`, `Decisions` :
76 ms environ), n'en fait plus qu'une (environ 10 ms avec les passes elles-mêmes). Aucune erreur d'abonné sur les cinq
machines, avant comme après.

## 2. Chemin d'écriture dans Kahlua (`--kahlua`)

| Chemin (registre type de 64 Ko RSV2) | Kahlua | lupa | Rapport |
|---|---|---|---|
| Avant : encodage, hex (`Codec.hexBytes`), somme, relecture et décodage | 101,4-114,3 ms | 27,9-29,4 ms | 3,5-3,9 |
| Après : encodage, hex par table (`Store.hexOfBytes`), somme par blocs (`Store.checksumOfBytes`), sans relecture | 31,9-32,6 ms | 10,8-11,3 ms | 2,8-3,0 |
| dont encodage RSV2 seul (`Codec.encodeBytes`) | 21,0 ms | 8,5 ms | 2,5 |
| dont hex : `Codec.hexBytes` / table de `gsub` | 16,3 / 5,5 ms | 7,0 / 1,1 ms | |
| dont somme : `Codec.checksumBytes` / par blocs | 10,2 / 6,9 ms | 1,7 / 1,4 ms | |

## 3. Critère d'acceptation : **non atteint**

Budget proposé : 25 ms Kahlua estimés pour l'image la plus lourde. Après LK13-T06, l'image la plus lourde du banc est
de 47,4 ms lupa, soit environ 130 à 170 ms Kahlua estimés (rapport 2,8 à 3,6). Ce qui reste :

1. **Une écriture du registre des groupes coûte encore environ 32 ms Kahlua** (117 Ko en hex), à elle seule au-dessus
   du budget ; les deux tiers sont l'encodage RSV2. Le champ `fort` pèse 71 % du registre : LK13-T07 (registre divisé
   par deux au moins) ramènerait l'écriture vers 10-15 ms Kahlua. Piste mesurée sans être appliquée (fichier commun
   `RS_Codec.lua`, hors périmètre) : un tri des clés par chaînes calculées une fois (au lieu d'un comparateur qui
   construit deux chaînes par comparaison) donne les mêmes octets en 6,0 ms lupa au lieu de 8,4.
2. **Création des corps** (`Bodies.tick`, max 38,9 ms lupa) : plusieurs écritures du registre des PNJ (`LKREG1`,
   relues à chaque fois) dans la même image. Le même regroupement s'appliquerait à `LK_Store.save` (tâche à créer).
3. Pointes de `Obstacles.tick` (11-15 ms lupa), `Stock.onEveryOneMinute` (8,5-15 ms) : hors écriture (points 4 et 5
   des points chauds de LK13-T02).

## 4. Garanties vérifiées (bancs)

- Une écriture par image au plus, à la fin de l'image ; rien avant ; serveur en pause écrit à l'image suivante ;
  `OnSave` en solo ; relecture avant `Groups.init` ; arrêt propre sans perte (tous les bancs de redémarrage).
- Marques idempotentes inchangées : `tests/test_lk_stock.py` (`OffscreenTests`, marque `LKStockOp`),
  `tests/test_lk_fortify_offscreen.py` (marque `LKFortOp`), `tests/test_lk_homes.py`, `tests/test_lk_traces.py`,
  `tests/test_lk_trade.py` verts : l'écriture immédiate (`Groups.flush()`) les garde avant le monde ou avant d'effacer
  les marques.
- Hex et somme rapides égaux à `RS_Codec` sous lupa (30 chaînes aléatoires) et dans la VM Kahlua (`KR-GFLUSH`).
