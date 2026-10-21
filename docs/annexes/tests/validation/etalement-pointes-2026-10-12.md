# Pointes du passage des membres et du relevé de la minute : mesure avant / après (LK13-T11)

- **Date** : 2026-10-12. **Statut** : mesure hors jeu (lupa), **aucune mesure en jeu**. Méthode, scénario et limites :
  [charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md) (LK13-T02) ; mesure précédente :
  [etalement-2026-10-12.md](etalement-2026-10-12.md) (LK13-T09) ; conception : [charge.md](../../conception/charge.md)
  « Pointes du passage des membres et du relevé de la minute », [fortification.md](../../conception/fortification.md)
  § 10.4.
- **Avant** : arbre du commit `aa4f478` (export `git archive`), sans les fichiers non commités de la tâche menée en
  parallèle (`LK_Load.lua`, `LK_Groups.lua`, `LK_Store.lua`, `LK_Core.lua`, `tools/load_bench.py`). **Après** : même
  arbre plus LK13-T11 (`LK_Fortify.lua`, `LK_Decisions.lua`, `LK_Hostility.lua`, `LK_GroupTypes.lua`). Même
  `tools/load_bench.py` des deux côtés. Machine partagée avec un autre banc : 10 à 50 % de bruit sur les pointes.
- **Commandes** :

```powershell
python RadioSurvivor/tools/load_bench.py --minutes 1440 --quiet --heavy 7    # deux essais avant, deux après
python RadioSurvivor/tools/load_bench.py --minutes 60 --quiet --heavy 7
python -m unittest RadioSurvivor/tests/test_lk_peaks.py                     # file, déterminisme, lecture en place
```

`--heavy 7` : images du serveur de 7 ms lupa ou plus (≈ 25 ms Kahlua, le budget proposé, au rapport 3 à 3,6).

## 1. Profil (ce qui coûtait)

Chaque fonction des tables `LivingKnox.<Module>` enveloppée d'une horloge (temps inclusif par image, surcoût de
l'enveloppe compris ; script de travail hors dépôt), banc de charge, 6 h de jeu :

| Pointe | Coût | Dont |
|---|---|---|
| `Decisions.tick` (passage de 4 membres), 9 à 13 ms | 2,5 ms par membre | `GroupTypes.get` 5 à 6 ms (30 à 40 copies profondes d'un type de groupe : `Hostility.startFor` par joueur et par groupe, `Decisions.allowedOf`, `Hostility.firstStrike`) ; `Hostility.startFor` 3 à 4 ms (copie comprise) |
| `Fortify.onEveryOneMinute`, 16 à 20 ms | 5 relevés (`Fortify.feasible`) dans l'image | `plan` 9 à 13 ms (relevé du monde 4 ms, `build` 5 à 8 ms), `snapshot` 4,8 ms (relevé gardé décodé à chaque appel), faisabilité 1,2 ms |

Les cinq plans expiraient dans la même minute : relevés dans la même image, `PLAN_MS` (60 s réelles) les fait expirer
ensemble 24 minutes de jeu plus tard.

## 2. Changements

| Travail | Avant | Après |
|---|---|---|
| Type de groupe lu par le passage des membres | `GroupTypes.get` (copie profonde) | `GroupTypes.peek` (lecture en place, lecture seule) |
| Relevés des plans expirés de la minute | tous dans l'image de la minute | un groupe par image à partir de l'image suivante, avec l'heure de la minute ; écriture du registre retenue jusqu'à la fin de la file |
| Relevé hors écran inchangé (`snapshot`) | relevé gardé décodé | vue mémorisée `readView` |

## 3. Serveur, une journée de jeu (36 000 images, temps lupa, deux essais de chaque côté)

| Mesure | Avant | Après |
|---|---|---|
| Moteur par image, moyenne | 0,479 / 0,400 ms | 0,378 / 0,364 ms |
| **Images de 7 ms ou plus** | **75 / 29** | **5 / 11** |
| dont module principal `Decisions` | 56 / 20 (max 17,5 / 12,1) | 1 / 2 (max 8,2 / 7,8) |
| dont module principal `Fortify` | 13 / 8 (max 18,7 / 15,2) | 1 / 6 (max 10,5 / 8,1) |
| `Decisions.tick` par image, moyenne (max) | 0,151 / 0,126 ms (9,5 / 10,3) | 0,063 / 0,062 ms (3,8 / 4,9) |
| `Fortify` : image de la minute (max) | 18 / 14,9 ms | 2,5 / 2,8 ms (mise en file) |
| `Fortify` : un relevé de la file (max) | — | 7,7 / 6,0 ms |
| **Image la plus lourde** | 18,7 / 15,2 ms | 11,9 / 10,4 ms |
| Écritures `LKGRP1` | 41 / 41 | 41 / 41 |

Première heure de jeu : images de 7 ms ou plus 4 → 0, image la plus lourde 13,2 → 6,4 ms, `Fortify` 12,9 → 2,7 ms.

**Critère « aucune image du banc au-dessus du budget » : non atteint** (5 à 11 images par journée au-dessus de 7 ms
lupa, contre 29 à 75). Restent :

1. **Relevé de la file et relecture du stock dans la même image** (`Fortify` 4,8 à 6 ms + `Stock` 1,2 à 2 ms, 7,2 à
   8,1 ms) : un relevé de camp (57 chantiers, plan reconstruit) coûte 5 à 6 ms à lui seul. Le relevé doit partir avant
   la relecture du stock de son groupe (même résultat qu'à la minute) ; le découper (monde dans une image, plan dans
   la suivante) ou alléger `Fortify.build` est hors de cette tâche.
2. **Image d'écriture du registre des groupes** (`Stock` 8,5 à 11,4 ms : fin de la file de relecture, une écriture
   `LKGRP1` de 3,3 ms en moyenne, au plus 11,4) : coût de l'écriture (LK13-T06/T07), non touché ici.
3. **Image de l'heure et la suivante** (`Simulation` 6,8 ms + autres, 10,4 ms ; `Decisions` 4,9 + `Simulation` 1,1,
   7,8 ms) : simulation, besoins et population restent dans l'image de l'heure (choix vérifié de LK13-T09).
4. **Première image mesurée** (`Groups` + `Store` + `Bodies`, 8,3 ms) : mise en route.

## 4. Déterminisme

| Banc | Comparaison | Résultat |
|---|---|---|
| Banc de charge complet, **une journée** (1 441 minutes), sans la mesure, files vidées en fin de banc | arbre avant / arbre après | registre des groupes (journal, mémoire, plans, relevés compris), attitudes, registre des PNJ, consignes (`Directives` : état, détenteurs, derniers rapports, consignes émises) et état des décisions des membres **identiques à l'octet** ; même nombre de relevés (305) et d'écritures du registre (51) ; lignes `fortify:` du journal identiques et dans le même ordre ; journal console : mêmes lignes (même multiensemble, 17 623), entrelacées autrement (un relevé « plan » écrit une ou plusieurs images plus tard, entre les lignes de la relecture du stock) |
| Banc de charge complet, 4 heures | arbre avant / arbre après | idem |
| `tests/test_lk_peaks.py`, banc de charge complet, 3 heures | relevé dans l'image de la minute (file vidée aussitôt) / file | registre des groupes, attitudes, registre des PNJ, lignes `fortify:` et nombre de relevés identiques |

## 5. Garanties vérifiées (bancs)

`tests/test_lk_peaks.py` (10 tests) : rien dans l'image de la minute, relevé à l'image suivante avec l'heure de la
minute (`plan.ms`), horloge rendue ; un seul relevé pour deux minutes sans image, plan frais jamais mis en file ;
lecture du plan (`levelOf`) et `invalidate` qui font d'abord le relevé en file (entrée sautée ensuite) ; une seule
écriture du registre après la file, dans une image à elle ; `OnSave` qui vide la file ; relevé en erreur journalisé,
file qui continue ; heure hors écran : relevé en file fait d'abord de jour, laissé en file la nuit ; `GroupTypes.peek`
rend la table vivante (`get` une copie) ; banc de charge : un groupe par image après la minute (trois minutes à
plusieurs groupes vues) et déterminisme (§ 4). Lecture du code des vues `peek` (aucune écriture par la vue) :
`tests/test_lk_groups.py`, qui couvre tous les appels `.peek(` hors de `LK_Groups.lua`, donc `GroupTypes.peek`.
