# Écriture du registre plus rapide et relevé de fortification en trois images : mesure avant / après (LK13-T06, LK13-T11)

- **Date** : 2026-10-15. **Statut** : mesure hors jeu (lupa et VM Kahlua de `projectzomboid.jar`), **aucune mesure en
  jeu**. Méthode, scénario et limites : [charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md) (LK13-T02) ;
  étapes précédentes : [charge-groupes-2026-10-12.md](charge-groupes-2026-10-12.md) (LK13-T06),
  [charge-registre-pnj-2026-10-12.md](charge-registre-pnj-2026-10-12.md) (LK13-T10),
  [etalement-pointes-2026-10-12.md](etalement-pointes-2026-10-12.md) (LK13-T11) ; conception :
  [groupes.md](../conception/groupes.md) « Écriture regroupée », [fortification.md](../conception/fortification.md)
  § 10.4, [stock.md](../conception/stock.md) « Relecture étalée ».
- **Avant** : copie de l'arbre de travail du 2026-10-15 (branche `dev`, commit `802d72d`, plus les fichiers non
  commités d'autres tâches en cours, sans rapport avec ces chemins) où les quatre fichiers ci-dessous sont remis à
  leur version `HEAD`. **Après** : même arbre avec `RS_Codec.lua`, `LK_Store.lua`, `LK_Fortify.lua`, `LK_Stock.lua`.
  Même `tools/load_bench.py`. Machine partagée avec d'autres agents : plusieurs ms de bruit sur les pointes lupa.
- **Commandes** :

```powershell
python <arbre>/tools/load_bench.py --minutes 1440 --quiet --heavy 7     # trois passages de chaque côté
python <arbre>/tools/load_bench.py --minutes 60 --quiet --heavy 7
python RadioSurvivor/tools/load_bench.py --minutes 1440 --quiet --dump-groups g.hex   # comparé (cmp) à l'avant
python RadioSurvivor/tools/load_bench.py --kahlua --registry g.hex
```

Mesure par étape dans la VM Kahlua : banc `KRun` de `tests/kahlua` copié hors dépôt avec une fonction Java
`nanoClock` (`System.nanoTime`, Kahlua n'a pas `os.clock`) ; registre réel du banc en fin de journée (21 561 octets,
43 122 en hex), 40 tours après 8 tours de chauffe, ancien `RS_Codec` chargé à côté du nouveau. Script de travail
hors dépôt.

## 1. Écriture du registre des groupes (LK13-T06)

| Chemin d'écriture (registre réel, 21,6 Ko) | Kahlua avant | Kahlua après | lupa avant | lupa après |
|---|---|---|---|---|
| Encodage RSV2 (`Codec.encodeBytes`) | 4,4-4,7 ms | **2,3-2,4 ms** | 1,1 ms | 0,6 ms |
| Somme de contrôle (`Store.checksumOfBytes`) | 1,7 ms | **1,0 ms** | 0,30 ms | 0,14 ms |
| Hex (`Store.hexOfBytes`, inchangé) | 1,6-2,0 ms | 1,6-2,0 ms | 0,22 ms | 0,22 ms |
| **Écriture complète** (minimum de 40 tours) | **7,7-8,6 ms** | **5,3-5,6 ms** | 1,8 ms | 1,9 ms |
| `--kahlua --registry` (différence de deux JVM, JIT compris) | 14,2 ms | 9,0 / 11,5 ms | 2,1 ms | 1,4 ms |
| Écriture `LKGRP1` au banc de charge (moyenne lupa, fichier compris) | 3,2-3,3 ms | 2,5-2,7 ms | | |

- **Encodage** (`RS_Codec`, mêmes octets) : un seul tampon de sortie joint une fois (les `table.concat` imbriqués
  recopiaient chaque octet une fois par niveau) ; pendant un appel, texte de tri et forme encodée de chaque clé, et
  forme encodée des chaînes de 64 caractères au plus, calculés une fois (les mêmes clés et mots reviennent dans chaque
  membre et chaque groupe) ; tables de 12 clés au plus triées par insertion (aucun appel par comparaison). Rien n'est
  gardé d'un appel à l'autre.
- **Somme** : seize octets lus par un seul `string.byte(s, k, k + 15)`, mêmes entiers que seize pas d'un octet.
- **Relecture** (chargement, contrôle de la première écriture) : hex inverse par table de remplacement
  (`Store.unhexOfBytes`, mêmes refus que `Codec.unhexBytes`) et la somme rapide.
- Hex par `string.format` de seize octets : 1,1 ms au lieu de 1,6 en Kahlua mais **cinq fois plus lent sous lupa**
  (1,1 contre 0,22 ms) : non retenu (gain faible, banc faussé).
- **Mêmes octets** : registre des groupes de fin de journée identique octet pour octet avant / après (`cmp`, trois
  passages) ; `tests/test_lk_store.py` `CodecSortTests` (comparateur historique : 200 tables tirées, 60 grandes
  tables à clés et chaînes répétées jusqu'à 45 × 30 clés, branche UTF-16 forcée, limite de profondeur, repli à textes
  égaux) ; VM Kahlua : `KR-RFLUSH` (300 tables) et `KR-GFLUSH` (somme, hex inverse) dans `tests/test_kahlua.py`.

**Pointes `LKGRP1` de 8 à 11 ms lupa à l'heure** : ce n'est pas l'écriture. Les écritures 5 images après l'heure
mesurées seules : encodage 5,5-6,2 ms au lieu de 1,2 ms ; avec un `collectgarbage("collect")` juste avant, 1,1-1,2 ms
et l'écriture entière 3,1-3,2 ms. Le pas de ramasse-miettes incrémental de Lua 5.1, dû aux déchets du pas horaire,
tombe dans la première fonction qui alloue beaucoup : artefact du banc lupa (la JVM ramasse autrement).

## 2. Relevé de fortification de la minute en trois images (LK13-T11, suite)

Relevé d'un plan expiré au banc (sans la mesure LK_Load) : relevé du monde 1,2-1,4 ms, plan (`build`, pur)
2,1 ms, faisabilité et relevé hors écran 1,0-1,5 ms lupa, soit 4,4-5 ms dans une image, plus la relecture du stock
du groupe suivant (2 ms) dans la même image.

- Le relevé en file se fait en **trois étapes, une par image**, toutes avec l'heure de sa minute ; l'entrée reste en
  file jusqu'à la dernière : toute lecture du plan d'ici là fait les étapes restantes d'un coup (`settle`), comme
  avant. Le plan des deux premières étapes est rendu au premier `Fortify.plan` de la faisabilité (aucun second relevé,
  même quand la zone n'est pas chargée).
- La relecture du stock d'un groupe dont le relevé est encore en file **attend** sa fin (file du stock arrêtée,
  écriture retenue d'autant) : le stock est toujours relu après le relevé de son groupe, comme quand le relevé tenait
  dans une image, et sans faire ses étapes dans l'image de la relecture (premier essai : `settle` depuis la
  relecture, pointes `Stock` 8-11 ms).

## 3. Banc de charge, serveur, une journée (36 000 images, temps lupa, trois passages de chaque côté)

| Mesure | Avant | Après |
|---|---|---|
| Moteur par image, moyenne | 0,505 / 0,500 / 0,502 ms | 0,529 / 0,504 / 0,453 ms |
| **Images de 7 ms ou plus** | **11 / 15 / 16** | **10 / 7 / 4** |
| dont module principal `Fortify` | 6 / 12 / 7 (max 9,9) | **0** |
| `Fortify`, plus lourde image | 6,4 / 6,4 / 6,1 ms | 4,2 / 3,1 / 2,9 ms |
| Image la plus lourde | 11,7 / 12,9 / 24,3 ms | 12,4 / 12,3 / 12,5 ms |
| Écritures `LKGRP1` | 42, 3,2-3,3 ms chacune | 41, 2,5-2,7 ms chacune |

Première heure : images de 7 ms ou plus 0 → 0, image la plus lourde 6,6 → 5,0 ms, écriture `LKGRP1` 2,3 → 1,6 ms.
Une écriture de moins par journée : la retenue de la file des relevés dure trois images par groupe. Aucune erreur
d'abonné sur les cinq machines, avant comme après.

**Images restantes au-dessus de 7 ms lupa** (après) : toutes dans les 10 images qui suivent l'heure : `Decisions`
(notation horaire et passage des membres, 5-6 ms) avec `Simulation` (pas horaire, 4 ms) dans la même image, et
l'écriture de fin de file à l'heure (pas de ramasse-miettes lupa, § 1). Hors de l'heure : aucune sur deux passages,
une (`Decisions`) sur le troisième.

## 4. Déterminisme

| Banc | Comparaison | Résultat |
|---|---|---|
| Banc de charge, une journée (`--dump-groups`) | avant / après (trois passages) | registre des groupes **identique à l'octet** |
| `tests/test_lk_peaks.py`, banc de charge 3 h | relevé dans l'image de la minute / file à trois étapes | registre des groupes, attitudes, registre des PNJ, lignes `fortify:` dans le même ordre, nombre de relevés : identiques |

## 5. Critères

- **LK13-T06** (image la plus lourde sous 25 ms Kahlua estimés ; aucune perte après redémarrage) : **l'écriture n'est
  plus en cause** : 5,3-5,6 ms Kahlua mesurés dans la VM (8-9 auparavant, 32 ms au début de la tâche), la moitié de
  l'encodage en moins ; règle d'écriture et relecture inchangées (aucun banc de redémarrage changé). L'image la plus
  lourde du banc reste de 12-12,5 ms lupa, soit **environ 30 à 45 ms Kahlua estimés** (rapport 2,5 à 3,6) : elle
  vient de l'image de l'heure (`Decisions` + `Simulation`), pas de l'écriture. Critère du banc **non atteint**.
- **LK13-T11** (aucune image au-dessus du budget ; registre identique) : `Fortify` ne fait plus aucune image lourde ;
  restent celles de l'heure (`Decisions`, fichier hors de ce lot). Critère **partiellement atteint**.
- **LK13-T09** : rien de changé dans ses fichiers (`LK_Simulation`, `LK_Needs`) ; l'image de l'heure (simulation,
  besoins, population, décisions) garde le choix vérifié de LK13-T09.

## 6. Phase 2 : passage des membres et notation de l'heure étalés (LK13-T11, LK13-T09)

Fichiers : `LK_Decisions.lua` (membres d'un passage un par image, notation de l'heure en file), `LK_Simulation.lua`
(`finishHour` vide aussi la file de notation) ; conception : [charge.md](../conception/charge.md). Décision : l'ordre
des écritures en place change ; exigence remplacée par le déterminisme du nouveau code.

**Mesure sans ramasse-miettes dans les images** : les pointes isolées restantes du banc (un seul module, 8 à 40 ms,
à des images différentes d'un passage à l'autre : `Stock`, `Relay`, `ZombieGuard`, `Directives`, `Decisions`) sont
des pas du ramasse-miettes de Lua 5.1 et le bruit de la machine partagée. Pour les séparer, le même banc est lancé
avec le ramasse-miettes du serveur arrêté pendant les images et fait entre deux images, hors mesure
(`collectgarbage("stop")`, `collectgarbage("collect")` toutes les 5 images ; script de travail hors dépôt qui
enveloppe `LoadBench.frame`). Deux arbres lancés l'un après l'autre :

| Mesure (journée, sans ramasse-miettes dans les images) | Avant (commit `802d72d`) | Après (phases 1 et 2) |
|---|---|---|
| Moteur par image, moyenne | 0,322 ms | 0,346 ms |
| **Image la plus lourde** | **4,8 ms** | **3,8 ms** |
| Images de 4 ms ou plus | 11 | **0** |
| `Decisions`, plus lourde image | 2,6 ms | 1,1 ms |
| `Fortify`, plus lourde image | 2,4 ms | 0,7 ms |
| `Stock`, plus lourde image (écriture de fin de file) | 4,6 ms | 3,3 ms |
| Écriture `LKGRP1`, moyenne (max) | 2,58 (4,6) ms | 1,91 (3,3) ms |
| Plus lourde image de l'heure, places 0 à 10 | 2,4 3,2 2,0 1,5 1,2 1,0 4,8 … | 2,7 3,2 1,9 1,7 1,6 1,8 3,8 … |

Banc standard (ramasse-miettes compris, deux passages) : places 1 à 5 après l'heure au plus 3,1-5,2 ms (7,3-12,5
avant la phase 2) ; `Decisions` au plus 2,7 ms hors pointes isolées. Réseau : `animState` 2,8 → 6,3 msg/s (mêmes
octets, 2,82 Mo contre 2,76 : gestes envoyés dans plus d'images), total 10 → 13,5 msg/s pour un budget de 40.

**Déterminisme du nouveau code** : deux journées de banc, registre des groupes identique à l'octet (`cmp`) ;
`tests/test_lk_peaks.py` `DecisionSpreadTests` : deux bancs de 3 h, registres des groupes, attitudes et PNJ
identiques, un membre évalué par image au plus, même nombre de notations.

**Critères** : image la plus lourde du code sous 7 ms lupa (3,8 ms, soit 10 à 25 ms Kahlua selon le rapport 2,5 à
6,5) : **atteint hors ramasse-miettes** pour LK13-T06, T09 et T11. Avec le ramasse-miettes de lupa compté dans les
images, des pointes isolées restent au-dessus de 7 ms (artefact du banc, à confirmer en jeu avec
`LivingKnox.Load`, où la JVM ramasse autrement).
