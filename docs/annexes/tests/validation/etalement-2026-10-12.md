# Pas horaire et relecture du stock étalés : mesure avant / après (LK13-T09)

- **Date** : 2026-10-12. **Statut** : mesure hors jeu (lupa), **aucune mesure en jeu**. Méthode, scénario et limites :
  [charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md) (LK13-T02) ; conception :
  [charge.md](../../conception/charge.md) « Pas horaire étalé », [stock.md](../../conception/stock.md) « Relecture étalée »,
  [groupes.md](../../conception/groupes.md) « Écriture retenue ».
- **Avant** : arbre du commit `77f774a` (LK13-T08), export `git archive`, sans les fichiers non commités de la tâche
  LK13-T10 menée en parallèle (`LK_Bodies.lua`, `LK_Store.lua`). **Après** : même arbre plus LK13-T09
  (`LK_Simulation.lua`, `LK_Server.lua`, `LK_Groups.lua`, `LK_Stock.lua`, `LK_Needs.lua`, `LK_Decisions.lua`). Les deux
  avec le même `tools/load_bench.py` (options `--heavy` et plus gros message ajoutées par cette tâche). Machine
  partagée avec un autre banc : 10 à 50 % de bruit sur les pointes d'un essai à l'autre (deux essais de chaque côté).
- **Commandes** :

```powershell
python RadioSurvivor/tools/load_bench.py --minutes 1440 --quiet --heavy 7    # deux essais avant, deux après
python RadioSurvivor/tools/load_bench.py --minutes 60 --quiet --heavy 7
python -m unittest RadioSurvivor/tests/test_lk_spread.py                    # déterminisme et mécanisme
```

`--heavy 7` : images du serveur de 7 ms lupa ou plus (≈ 25 ms Kahlua, le budget proposé, au rapport 3 à 3,6), module
principal, place de l'image après l'heure et après la minute.

## 1. Ce qui a changé

| Travail | Avant | Après |
|---|---|---|
| Relecture du stock de la minute (5 groupes) | tous les groupes dans l'image de l'`EveryOneMinute` | un groupe par image, de l'image suivante à la 5e, puis une image d'écriture |
| Population, simulation, besoins (`EveryHours`) | image de l'heure | image de l'heure (inchangé, voir § 4) |
| Notation des objectifs, déclin des attitudes | image de l'heure | une passe par image, images 1 et 2 après l'heure |
| Écriture du registre des groupes du pas horaire | une, fin de l'image de l'heure | une, dans une image à elle (retenue jusqu'à la fin des deux files) |

## 2. Serveur, une journée de jeu (36 000 images, temps lupa, deux essais de chaque côté)

| Mesure | Avant | Après |
|---|---|---|
| Moteur par image, moyenne | 0,498 / 0,538 ms | 0,547 / 0,485 ms |
| **Images de 7 ms ou plus** | **194 / 249** | **106 / 90** |
| dont module principal `Stock` | 81 / 122 (max 17,8 / 21,4) | 2 / 2 (max 11,7 / 13,6 : image d'écriture) |
| dont dans les 10 images qui suivent l'heure | 25 / 22 | 7 / 3 |
| Image de l'heure (la plus lourde de la journée à cette place) | 20,8 / 14,4 ms | 8,8 / 4,3 ms |
| Image suivante | 18,8 / 17,7 ms | 14,7 / 16,9 ms (notation + passage `Decisions.tick`) |
| `Stock.onEveryOneMinute` (image de la minute) | 3,79 / 3,96 ms par minute (max 10,7 / 12,1) | 0,02 ms (mise en file) |
| Relecture étalée `Stock.minuteQueue` | — | 0,15-0,17 ms par image en moyenne (max 11 / 13,4, image d'écriture) |
| `Decisions.onEveryHours` dans l'image de l'heure | 1,57 / 1,29 ms (max 8,6 / 2,0) | 0,005 ms (mise en file) |
| **Image la plus lourde** | 43,3 / 46,7 ms | 41,2 / 44,6 ms |
| Écritures `LKGRP1` (avec la mesure en place, voir § 5) | 38 / 38 | 41 / 41 |

Première heure de jeu : images de 7 ms ou plus 7 → 10 (toutes `Bodies` et 3 `Decisions.tick` au bruit près), image de
l'heure 6,2 → 1,9 ms, `Stock` 2,6 ms par minute → 0,12 ms par image.

**Critère « aucune image du banc au-dessus du budget » : non atteint.** Les images restantes au-dessus de 7 ms lupa ne
viennent plus ni du pas horaire ni du relevé du stock :

1. **Création des corps** (`Bodies.tick`, 7 images de 23 à 46 ms dans les 100 premières images) : tâche LK13-T10
   (écritures relues du registre des PNJ), en cours en parallèle.
2. **`Decisions.tick`** (images de 7 à 13 ms : 28 à 77 par journée avant, 6 à 82 après selon l'essai, soit le bruit
   de la machine partagée) : passage des membres incarnés, hors du pas horaire. Proposition : borner le travail d'un passage (membres par passage, ou passage étalé) — tâche à créer.
3. **`Fortify.onEveryOneMinute`** (10 à 39 images de 7 à 23 ms par journée, à des minutes isolées) : relevé du monde
   d'un plan expiré dans l'image de la minute. Proposition : même file que le stock (un groupe par image) — tâche à
   créer (`LK_Fortify.lua`, hors des fichiers de LK13-T09).

## 3. Déterminisme

| Banc | Comparaison | Résultat |
|---|---|---|
| `tests/test_lk_spread.py`, banc léger (2 groupes, 30 heures) | ancien chemin (tout dans l'image de l'heure) / nouveau | registre des groupes et attitudes identiques à l'octet, mêmes lignes `simulation:` et `objective` |
| `tests/test_lk_spread.py`, banc de charge complet (5 groupes, 4 joueurs, 3 heures) | ancien chemin / nouveau | registre et attitudes identiques à l'octet |
| Banc de charge complet, **une journée**, sans la mesure | arbre avant / arbre après | registre des groupes identique à l'octet (journal, mémoire et plans compris) |

## 4. Choix vérifié : simulation et besoins restent dans l'image de l'heure

Essai sur le banc de charge (3 heures) en décalant aussi population, simulation et besoins d'une image chacun : les
jauges des membres d'un groupe incarné divergent (faim 32 → 35, soif 35 → 41 ; sur une journée, faim 100 contre 49) et
l'ordre de deux entrées du journal change. Cause : entre l'heure et la passe, les membres incarnés montent la peur
(`Needs.perceive`) et prennent des repas réels (`Needs.relieve`) en place, avec des bornes 0..100 : l'ordre des
écritures change le résultat. Décaler seulement la notation et les attitudes (essai « partiel ») donne le registre
identique sur la journée. Les groupes hors écran, eux, n'avaient pas divergé.

## 5. Constat sur l'outil de mesure (non corrigé ici)

`LivingKnox.Load` remet en fin de liste chaque abonné qu'il enveloppe, dans l'ordre alphabétique des clés
(`charge.md`, « Choix ») : pendant une mesure, les abonnés `EveryHours` passent dans l'ordre `Decisions`, `Hostility`,
`Needs`, `Population`, `Raids`, `Simulation`, au lieu de l'ordre d'inscription. Avant LK13-T09, la notation partait
donc **avant** la simulation pendant une mesure (journal du groupe dans un autre ordre, nombre d'écritures différent) ;
avec la file, elle part toujours après. La comparaison de déterminisme se fait donc sans la mesure (§ 3) ; le nombre
d'écritures `LKGRP1` sans la mesure est le même avant et après (28 et 28 sur la première heure). À corriger dans
`LK_Load.lua` (garder l'ordre d'inscription) : tâche à créer.
Corrigé par LK13-T12 (ordre réel gardé, `charge.md`, « Choix »).

## 6. Réseau (inchangé, à surveiller)

| Commande (serveur, journée) | Débit | Taille moyenne | Plus gros message |
|---|---|---|---|
| `dirState` | 7,21 msg/s (25 945) | 85 o | 152 o |
| `animState` | 2,81 msg/s (10 099) | 275 o | 634 o |
| `guardRoster` (à tous) | 13 messages | 347 o | 567 o |

Mêmes nombres avant et après (protocole réseau non modifié). Au banc, 15 corps et 4 joueurs : 10 msg/s et 1,4 Ko/s
envoyés, sous le budget proposé (40 msg/s, 8 Ko/s). `dirState` croît avec le nombre de corps vus (0,5 msg/s par
corps) ; `animState` reste sous 1 Ko par message. À revoir si la mesure en jeu montre plus de corps à portée.

## 7. Garanties vérifiées (bancs)

- `tests/test_lk_spread.py` (13 tests) : notation et attitudes hors de l'image de l'heure, une passe par image, heure
  lue à l'`EveryHours` ; ordre du jeu (`EveryHours` avant `OnTick` dans la même image) ; heure nouvelle avec une file
  non vide (heure précédente finie d'abord) ; passe en erreur journalisée sans arrêter la suivante ; `OnSave` qui vide
  la file et écrit ; une seule écriture pour le pas horaire et pour la relecture du stock ; retenue bornée ;
  `Groups.flush()` jamais retenu ; relecture du stock un groupe par image, sans doublon, même résultat qu'un `scan`.
- Bancs existants adaptés (file vidée après l'événement, `Simulation.finishHour()` / `Stock.finishQueue()`) :
  `test_lk_simulation`, `test_lk_needs`, `test_lk_decisions`, `test_lk_population`, `test_lk_hostility`,
  `test_lk_journal`, `test_lk_stock`.
