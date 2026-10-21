# Lecture des groupes sans copie : mesure avant / après (LK13-T08)

- **Date** : 2026-10-12. **Statut** : mesure hors jeu (lupa), **aucune mesure en jeu**. Méthode, scénario et limites :
  [charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md) (LK13-T02) ; conception :
  [groupes.md](../../conception/groupes.md), « Lecture en place ».
- **Avant** : branche `dev` au commit `b9cb096` (LK13-T07 compris : plans `fort` compacts, d'où un `Obstacles` déjà
  plus léger que dans la mesure LK13-T02). **Après** : même arbre plus LK13-T08 (`Groups.peek` dans `LK_Groups.lua`,
  appels dans `LK_Obstacles.lua` et `LK_Stock.lua`, `Groups.touched` dans `LK_Needs.lua`).
- **Bruit** : machine partagée avec un autre agent qui modifiait en même temps `LK_Bodies.lua` / `LK_Store.lua` (second
  essai « après » : 63 abonnés mesurés au lieu de 61, écritures `LKREG1` différentes) ; les autres modules varient de
  10 à 15 % d'un essai à l'autre sans changement de leur code.

```powershell
python RadioSurvivor/tools/load_bench.py --minutes 1440 --quiet --json before1440.json   # avant
python RadioSurvivor/tools/load_bench.py --minutes 1440 --quiet --json after1440.json    # après (deux essais)
```

## 1. Module `Obstacles` (serveur, une journée de jeu, 36 000 images, temps lupa)

| Mesure | Avant | Après, essai 1 | Après, essai 2 |
|---|---|---|---|
| `Obstacles.tick`, ms par image | 0,065 | **0,011** | **0,010** |
| Plus lourde image du module | 9,5 ms | 1,6 ms | 1,7 ms |

Coût divisé par **6** (critère : par 2). Réseau identique au message près (36 097 envoyés, 4 981 299 o ; 19 546 reçus) :
même comportement.

## 2. Appels de `Groups.get` (serveur, 4 h de jeu, 6 000 images, enveloppe de mesure par ligne d'appel)

| Appelant | Appels | ms par image avant | Après |
|---|---|---|---|
| `LK_Obstacles` `homeKeyOf` (clés des corps, toutes les 2 s par corps) | 4 474 | 0,037 | lecture en place, aucune copie |
| `LK_Obstacles` `refreshHomes` (relevé des foyers) | 1 500 | 0,012 | lecture en place, aucune copie |
| `LK_Stock.check` (chaque minute de jeu et par groupe) | 1 200 | 0,011 | inchangé au banc : la copie n'est plus faite qu'une fois la zone du foyer chargée et ses conteneurs trouvés ; au banc tout est chargé. En jeu, un foyer hors zone chargée ne coûte plus de copie. |
| `LK_Stock`, `LK_Fortify`, `LK_Loot` (autres) | 165 | 0,0015 | inchangés (rares) |

Une copie de groupe coûte 0,05 ms lupa au banc (5 groupes, plans `fort` compacts) ; `Groups.peek` ne copie rien.

## 3. Contrôle de non-écriture

- Lecture du code (`tests/test_lk_groups.py`, `test_no_caller_writes_through_a_view`) : aucun appelant n'écrit dans une
  vue ni ne la rend.
- Contrôle à l'exécution `Groups.PEEK_CHECK = true` sur le banc de charge : 180 minutes de jeu, 5 346 lectures, **0**
  écriture par une vue (après déclaration de la peur montée en place par `LK_Needs.perceive`, `Groups.touched`) ;
  3 minutes de jeu dans le banc automatique `test_load_bench_never_writes_through_a_view`.

## 4. Reste

- Mesure en jeu (Kahlua, serveur dédié) : protocole [charge-protocole.md](charge-protocole.md), séance finale.
- `Stock.onEveryOneMinute` (4 ms lupa par minute de jeu) reste le premier poste par minute (point chaud 5 de LK13-T02,
  hors de cette tâche).
