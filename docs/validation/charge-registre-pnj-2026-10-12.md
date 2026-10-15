# Écriture regroupée du registre des PNJ et tri des clés RSV2 : mesure avant / après (LK13-T10)

- **Date** : 2026-10-12. **Statut** : mesure hors jeu (lupa et VM Kahlua de `projectzomboid.jar`), **aucune mesure en
  jeu**. Méthode, scénario et limites : [charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md) (LK13-T02) ;
  étapes précédentes : [charge-groupes-2026-10-12.md](charge-groupes-2026-10-12.md) (LK13-T06),
  [charge-fortification-2026-10-12.md](charge-fortification-2026-10-12.md) (LK13-T07) ; conception :
  [corps-registre.md](../conception/corps-registre.md), « Écriture regroupée (LK13-T10) ».
- **Avant** : arbre du commit `b9cb096` (export `git archive`, sans les fichiers non commités d'autres tâches).
  **Après** : même arbre plus les quatre fichiers de LK13-T10 (`LK_Store.lua`, `LK_Bodies.lua`, `LK_Equipment.lua`,
  `RS_Codec.lua`). Même `tools/load_bench.py`. Machine partagée avec un autre banc : quelques ms de bruit sur les
  pointes.
- **Commandes** (mêmes options avant et après, depuis chaque arbre) :

```powershell
python <arbre>/tools/load_bench.py --minutes 60 --quiet --json r60.json
python <arbre>/tools/load_bench.py --minutes 1440 --quiet --json r1440.json --dump-groups g1440.hex   # 3 passages
python <arbre>/tools/load_bench.py --kahlua --registry <avant>/g1440.hex                             # 2 passages
```

Encodage seul (`C.encodeBytes`, 80 tours, VM Kahlua et lupa) : petit script de mesure appelant
`load_bench.kahlua_factor(loop=...)` de chaque arbre, non gardé dans le dépôt.

## 1. Serveur, temps lupa

| Mesure | Avant, 1re heure | Après, 1re heure | Avant, journée (3 passages) | Après, journée (3 passages) |
|---|---|---|---|---|
| Moteur par image, moyenne | 0,578 ms | 0,461 ms | 0,615 / 0,352 / 0,395 ms | 0,415 / 0,346 / 0,425 ms |
| **Image la plus lourde** | **42 ms** | **13,3 ms** | **52,8 / 45,0 / 41,5 ms** | **18,2 / 13,6 / 23,8 ms** |
| `Bodies.tick`, plus lourd appel | 38,6 ms | 1,0 ms | 49,4 / 42,2 / 38,4 ms | 1,4 / 1,2 / 1,1 ms |
| Écritures `LKREG1` (registre des PNJ) | 20, 8,51 ms chacune (max 11,9) | 7, 1,57 ms (max 2,5) | 20, 7,7-8,6 ms (max 12,6-14,1) | 7, 1,4-1,65 ms (max 1,7-2,1) |
| `Store.flush` (nouveau : écriture de fin d'image) | — | 0,008 ms en moyenne, max 2,5 | — | sous les 12 premiers modules |
| Écritures `LKGRP1` (registre des groupes, inchangé) | 15, 2,74 ms | 15, 2,61 ms | 38, 3,2-3,7 ms | 38, 2,9-3,4 ms |

Les créations de corps d'une même tranche de matérialisation (plusieurs membres, chacun avec une écriture à la
création et une à l'arme, relue à chaque fois) ne font plus qu'une écriture, sans relecture, à la fin de l'image.
Écritures du registre des attitudes (`LKATT1`) : aucune au banc, avant comme après (inchangé, voir § 5). Aucune
erreur d'abonné sur les cinq machines, avant comme après.

Pointes restantes (après, journée) : `Fortify.onEveryOneMinute` (14,3 à 18 ms, relevé du monde du plan expiré),
`Stock.onEveryOneMinute` (10,6-10,8 ms), `Decisions.tick` (9,6 ms) ; la pire image (23,8 ms) cumule `Fortify` et
`Stock` à la même minute de jeu. Aucune ne vient plus de l'écriture d'un registre.

## 2. Encodage RSV2 (`RS_Codec`)

| Mesure (encodage seul, `C.encodeBytes`) | Avant | Après |
|---|---|---|
| Registre type de 64 Ko (`FACTOR_BUILD`), lupa | 8,3 / 8,4 ms | 6,4 / 6,3 ms |
| Registre type de 64 Ko, **Kahlua** | 20,7 / 20,6 ms | 17,1 / 17,2 ms |
| Registre réel des groupes en fin de journée (43 Ko en hex), lupa | 1,4 / 1,5 ms | 1,2 / 1,2 ms |
| Registre réel des groupes, Kahlua | 6,8 / 7,7 ms | 7,2 / 6,0 ms (dans le bruit) |
| Écriture complète du registre réel (`--kahlua --registry`), Kahlua | 13,3 / 12,5 ms | 13,1 / 13,4 ms |

Le gain vient des grandes tables (le registre type a 120 entrées de fortification par groupe) : environ 20 % sous
lupa et 17 % sous Kahlua. Le registre réel, fait de nombreuses petites tables depuis LK13-T07, n'y gagne presque
rien : son écriture reste dominée par l'hex et la somme de contrôle.

## 3. Mêmes octets

- Registre des groupes écrit en fin de journée (`--dump-groups`, encodé par le `RS_Codec` de chaque arbre) :
  **fichiers identiques octet pour octet** avant et après (`cmp`, 43 122 o). Tailles du registre des PNJ identiques
  (23 846 o), sur l'heure comme sur la journée.
- `tests/test_lk_store.py`, `CodecSortTests` : 200 tables tirées (clés chaînes, entières, flottantes, négatives, non
  ASCII, tables imbriquées) et le registre des PNJ du banc, octet pour octet contre le comparateur historique ;
  repli sur ce comparateur quand deux clés s'écrivent pareil (deux nombres égaux sur 14 chiffres sous Lua 5.1 ;
  jamais en Kahlua, dont `Double.toString` est exact ; cas simulé au banc).
- VM Kahlua (`tests/test_kahlua.py`, `KR-RFLUSH`) : 300 tables tirées, mêmes octets dans la VM réelle
  (`table.sort` de `stdlib.lua`).
- Bancs du carnet et de l'échange (`test_protocol`, `test_carnet`, `test_personas*`, `test_notes`…) verts sans
  changement.

## 4. Critère d'acceptation : **atteint**

Mêmes octets écrits ; pire image du banc abaissée (journée : 41,5-52,8 ms → 13,6-23,8 ms lupa ; première heure :
42 → 13,3 ms) ; aucun banc existant cassé (`tests/run_all.py`). Le rapport du banc affiche `budget: ok` (seuil de
25 ms comparé au temps lupa) ; en temps Kahlua estimé (rapport 2,5 à 3,6), la pire image reste d'environ 35 à 85 ms,
**au-dessus du budget proposé de 25 ms Kahlua** : elle vient désormais de `Fortify` et `Stock` (points chauds 4 et 5
de LK13-T02), hors du périmètre de cette tâche.

## 5. Garanties vérifiées (bancs) et limites

- `tests/test_lk_store.py` (11 tests) : créations et retraits d'une image écrits une fois à sa fin, rien avant ;
  arme posée à la création écrite avec elle ; écriture de fin d'image placée derrière les abonnés inscrits au
  chargement, une par image au plus ; serveur en pause écrit au début de l'image suivante ; `OnSave` et relecture
  (`Store.init`) écrivent ce qui attend ; `flush` idempotent, refusé registre bloqué ; **mort écrite tout de suite**
  (avec le changement en attente) ; relecture de contrôle à la première écriture de la session et sur demande, fichier
  abîmé détecté par `Store.verifyFile` (registre bloqué) ; redémarrage qui relit tout.
- `tests/test_lk_bodies.py` (55 tests) : inchangé sauf l'aide `spawn` du banc, qui termine l'image après chaque
  création (une création par image, comme une commande de console).
- Registre des attitudes (`LK_Hostility`) laissé en écriture immédiate : aucune écriture au banc, une par fait de
  joueur et une par jour de déclin ; le même schéma s'y appliquerait, sans gain mesurable aujourd'hui.
- Arrêt brutal : au plus les changements de l'image en cours (100 ms sur un serveur dédié), contre aucun auparavant ;
  le monde de cette image (corps neufs compris, sauvegardés seulement dans `reanimated.bin`) est perdu aussi.
