# Charge de Living Knox mesurée hors jeu (LK13-T02)

- **Date** : 2026-10-12. **Statut** : mesure hors jeu ; la mesure en jeu (5 groupes, 4 joueurs) reste à faire à la
  séance multijoueur finale ([charge-protocole.md](charge-protocole.md)). **Aucune mesure en jeu n'est présentée ici.**
- **Code mesuré** : branche `dev` du 2026-10-12 (commit `6ed7f68` ou `c7eb69d`, qui ne touche aucun fichier Living Knox,
  plus les fichiers non commités de LK13-T02).
- **Outil** : `tools/load_bench.py` (fiche [charge.md](../conception/charge.md)), mesure `shared/LivingKnox/LK_Load.lua`.

## 1. Méthode

```powershell
python RadioSurvivor/tools/load_bench.py --minutes 60 --json charge60.json      # première heure de jeu
python RadioSurvivor/tools/load_bench.py --minutes 1440 --json charge1440.json  # une journée de jeu (37 s)
python RadioSurvivor/tools/load_bench.py --kahlua                               # rapport de vitesse Kahlua / lupa
```

- **Banc** : `tests/harness.py`, une VM Lua 5.1 (lupa) par machine : serveur dédié et quatre clients `A`, `B`, `C`,
  `D`. Pile complète des corps des bancs existants (`test_lk_materialize.MatBase` et doublures de santé, perception,
  combat, tir, zombies, butin, mort), puis **tous** les fichiers Lua de Living Knox chargés par `require` (58 abonnés
  du moteur sur le serveur, 29 sur un client). Doublures ajoutées par le banc : cases sans eau ni buisson, aucune
  pièce ni bâtiment (`getBuilding`, `getBuildingAt` nil), `ZombRand` reproductible, `getText` qui rend la clé.
- **Scénario** : `Population.run` (graine 7, `GroupCount = 5`, poids par défaut) ; foyers fixés par le banc
  (`Sites.pick` remplacé) en (110, 110), (330, 110), (700, 110), (110, 700), (700, 700). Joueurs immobiles :
  `A` (100, 100) et `B` (106, 102) près du foyer 1, `C` (320, 100) près du foyer 2, `D` (1200, 1200) loin de tout ;
  les groupes 3 à 5 restent hors écran. 33 membres, 15 corps créés près des joueurs.
- **Cadence** : serveur à 10 images par seconde (100 ms, base `multiplayer.md`), une minute de jeu toutes les
  25 images (journée de 1 h réelle), `EveryHours` à chaque heure de jeu ; clients cadencés comme le serveur.
- **Réseau et corps** : file du banc livrée à chaque image. Toutes les 500 ms : copie d'un corps chez chaque client à
  64 cases ou moins de son joueur, propriétaire = client le plus proche à 48 cases ou moins (sinon le serveur),
  position du propriétaire recopiée ailleurs ; marche `STEP` du banc chez le propriétaire. Ici `B` possède les corps
  du groupe 1 (`A` observe), `C` ceux du groupe 2, `D` ne voit rien.
- **Mesure** : `LivingKnox.Load` sur chaque machine après une minute de mise en route, horloge fine
  (`time.perf_counter`) passée à `Load.clock`.

## 2. Limites (lupa ≠ Kahlua ≠ jeu)

- **lupa n'est pas Kahlua.** Sur le chemin d'écriture d'un registre (encodage RSV2 d'environ 64 Ko, hex, somme,
  relecture), Kahlua est **3,6 fois** plus lent (`--kahlua` : 99-100 ms contre 27-28 ms, deux essais). Le rapport
  dépend du code (chaînes et tables ici) : les ms ci-dessous sont des temps lupa, à multiplier par 3 à 4 pour une
  estimation Kahlua, qui reste une **estimation**.
- **Kahlua n'est pas le jeu.** Les doublures ne coûtent pas ce que coûte le Java (recherche de chemin, animation,
  cases, inventaires) ; le banc ne mesure ni le rendu ni le coût des corps eux-mêmes (zombies du moteur).
- **Pas couvert** : `LoadChunk` (aménagement des foyers, remplissage du stock : 0 entrée de stock), joueurs en
  mouvement, combats avec les joueurs, raids (`RaidDays` = 14 jours), commerce, parole demandée par un joueur,
  coupure et reconnexion, PauseEmpty.
- **Taille réseau approchée** (chaînes, 8 par nombre, 2 par table) ; le Java sérialise autrement.

## 3. Résultats : serveur

| Mesure (temps lupa) | 1re heure de jeu (1 500 images) | 1 journée de jeu (36 000 images) |
|---|---|---|
| Moteur par image, moyenne | 1,030 ms | 0,597 ms |
| Image la plus lourde | 99,7 ms | 110,6 ms |
| Images à 1 ms ou plus | 235 (16 %) | 5 660 (16 %) |
| Envoyés | 10,65 msg/s, 1 488 o/s | 10,03 msg/s, 1 383 o/s (36 077 à un joueur, 20 à tous) |
| Reçus | 6,11 msg/s, 949 o/s | 5,43 msg/s, 815 o/s |
| Écritures du registre des groupes `LKGRP1` | 24, 28,0 ms chacune (max 38,1) | 75, 31,5 ms chacune (max 46,5) |
| Écritures du registre des PNJ `LKREG1` | 20, 8,5 ms chacune (max 13,1) | 20, 8,3 ms chacune (max 13,9) |

Modules du serveur sur la journée (ms par image, temps lupa ; « max » = plus lourd total du module dans une image) :

| Module | ms/image | max | Abonné principal |
|---|---|---|---|
| Obstacles | 0,132 | 13,8 | `Obstacles.tick` (passage toutes les 5 images) |
| Stock | 0,126 | 15,7 | `Stock.onEveryOneMinute` : 3,15 ms par minute de jeu |
| Decisions | 0,124 | 82,5 | `Decisions.tick` 0,118 ms ; `Decisions.onEveryHours` 9,8 ms (max 41,4) |
| Directives | 0,026 | 1,0 | `Directives.tick`, `Directives.onClientCommand` |
| Relay | 0,026 | 0,9 | `Relay.tick` |
| Bodies | 0,025 | 95,0 | `Bodies.tick` (création des corps : écritures des deux registres) |
| Needs | 0,024 | 43,9 | `Needs.onEveryHours` : 36,1 ms par heure de jeu |
| Simulation | 0,024 | 48,5 | `Simulation.onEveryHours` : 36,0 ms par heure de jeu |
| Fortify | 0,014 | 39,1 | `Fortify.onEveryOneMinute` |
| Health, Upkeep, Zombies | 0,012-0,014 | 0,5-6,2 | |
| 17 autres | 0,025 ensemble | | |

Sur la première heure, `Bodies` (0,358 ms) et `Decisions` (0,266 ms) dominent : création des 15 corps et premières
décisions, chacune suivie d'écritures de registre.

**État sauvegardé** (fichiers en hex, après la journée) : registre des PNJ 23 846 o, registre des groupes 117 130 o,
attitudes 86 o. Champs de groupe les plus lourds : `fort` (plans de fortification) **83 240 o, 71 %** du registre des
groupes, `members` 11 542, `log` 10 806 (92 entrées), `story` 4 276, `journal` 1 860 (10 entrées), `furnish` 1 010.

## 4. Résultats : propriétaires et observateurs

| Client (journée) | Rôle | ms/image | max | Envoyés | Reçus |
|---|---|---|---|---|---|
| `B` | propriétaire des corps du groupe 1 | 0,049 | 2,3 | 2,82 msg/s, 462 o/s (`bodyReport`, `dirReport`) | 3,35 msg/s |
| `C` | propriétaire des corps du groupe 2 | 0,041 | 1,6 | 2,61 msg/s, 353 o/s | 3,34 msg/s |
| `A` | observateur du groupe 1 | 0,025 | 0,6 | 4 messages en tout (`dirAsk`) | 3,35 msg/s |
| `D` | loin de tout | 0,009 | 0,4 | 0 | 20 messages en tout (`guardRoster`, `equipState`, envoyés à tous) |

Chez un propriétaire, `Executor` est le premier module (0,02-0,03 ms/image) ; les autres (`Anim`, `Equipment`,
`ZombieGuard`, `CombatView`…) restent sous 0,005 ms/image. Envois du serveur sur la journée : `dirState` 25 945
(7,2/s, 85 o en moyenne), `animState` 10 099 (2,8/s, 275 o en moyenne) ; reçus : `bodyReport` 10 862 (3,0/s, 201 o),
`dirReport` 8 672 (2,4/s).

## 5. Budgets proposés (à confirmer en jeu)

Valeurs de `LivingKnox.Load.BUDGET`, vérifiées à chaque rapport (`budget: ok` ou `budget: OVER …`).

| Budget | Autorité | Client | Fondement |
|---|---|---|---|
| Moteur par image, moyenne | 2 ms | 1 ms | 2 % d'une image de 100 ms du serveur dédié ; ~3-6 % d'une image client de 16-33 ms. Banc : 0,6 ms lupa ≈ 2,1 ms Kahlua estimés : **à la limite** |
| Image la plus lourde | 25 ms | 8 ms | un quart d'image serveur ; une demi-image client à 60 images/s. Banc : **dépassé** (110 ms lupa) |
| Un module, moyenne | 0,5 ms | 0,5 ms | aucun module ne doit prendre le quart du budget total. Banc : 0,13 ms lupa au plus ≈ 0,5 ms Kahlua |
| Envoyés | 40 msg/s, 8 Ko/s | 5 msg/s, 1 Ko/s | 4 joueurs et 15 corps : 10 msg/s et 1,4 Ko/s au banc, marge × 4 pour plus de corps |
| Fichier de registre | 1 Mo | — | 117 Ko au banc pour 5 groupes ; la limite RSV2 est 4 Mo (`RS_Codec.MAX_BYTES`) |

## 6. Points chauds (nouvelles tâches proposées, non corrigés ici)

1. **Écriture complète du registre des groupes à chaque changement.** Chaque `Groups.update` qui change quelque chose
   réencode tout le registre (117 Ko en hex), l'écrit, le relit et le décode pour le vérifier : 31,5 ms lupa
   (≈ 110 ms Kahlua estimés) par écriture, 75 par journée de jeu, et plusieurs dans la même image (création de corps,
   heure de jeu). C'est l'essentiel des images lourdes (95-110 ms) ; les écritures des registres font 54 % du temps du serveur
   sur la première heure de jeu (842 ms sur 1 545) et 12 % sur la journée (2 530 ms sur 21 490).
   *Proposition* : regrouper les écritures (registre marqué « à écrire », une écriture par image ou par minute et à
   `OnSave`), vérification de relecture seulement à la première écriture de la session ou sur demande.
2. **Plans de fortification dans le registre persistant.** `fort` pèse 71 % du registre des groupes (16 Ko par
   groupe) et alourdit chaque écriture du point 1 et chaque copie de groupe. *Proposition* : ne garder que l'état
   utile (chantiers faits, rang), recalculer le plan, ou le ranger dans un fichier à part écrit rarement.
3. **Pas horaires dans la même image.** `Simulation`, `Needs`, `Decisions`, `Population`, `Raids`, `Hostility`
   partent tous sur `EveryHours`, chacun avec sa propre écriture du registre : 36 + 36 + 10-41 ms lupa dans une seule
   image. *Proposition* : une seule écriture pour l'ensemble du pas horaire, et étaler les passes sur plusieurs images
   (une par image).
4. **Copies complètes de groupe par image.** `Groups.get` rend une copie profonde du groupe (plans `fort` compris) ;
   `LK_Obstacles` l'appelle environ une fois par image avec 15 corps en marche (240 appels en 250 images, 0,07 ms
   chacun), soit environ la moitié du coût d'`Obstacles`, premier module en continu. *Proposition* : lecture sans copie
   (accesseur en lecture seule ou champ demandé) pour les passages fréquents.
5. **`Stock.onEveryOneMinute` à chaque minute de jeu** : 3,15 ms lupa par minute (contrôle de chaque groupe candidat
   dans la même image), sans stock rempli au banc. *Proposition* : un groupe par passage, mesurer avec un vrai stock
   (protocole en jeu).
6. **`dirState` à 7 msg/s pour 15 corps** (0,5 msg/s par corps, envoyé au propriétaire et aux observateurs) et
   `animState` lourd (275 o en moyenne) : premier poste réseau, acceptable à 4 joueurs. *À surveiller* avec plus de
   corps visibles. Messages envoyés à tous (`guardRoster`, `equipState`) reçus aussi par un joueur sans aucun corps
   à portée (`D`) : volume faible, à adresser aux seuls clients concernés si le nombre de corps grandit.
7. **Budget de réflexion selon la distance (I1.5)** : pas nécessaire au vu de ces chiffres (le coût des décisions des
   membres incarnés reste sous 0,13 ms lupa par image) ; à reconsidérer si la mesure en jeu le contredit.

## 7. Ce qui reste à mesurer en jeu

Le protocole [charge-protocole.md](charge-protocole.md) : temps réels du serveur dédié (Kahlua, API Java), coût chez
un propriétaire et un observateur avec le rendu, avec stock rempli, aménagement des foyers et combat, sur au moins
30 minutes réelles.
