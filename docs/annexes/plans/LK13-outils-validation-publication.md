# LK13 — Outils, performance, validation et publication

**Objectif.** Outils d'administration, mesures de charge, validation multijoueur complète et publication.

**Dépend de.** Étapes LK03 à LK12 selon le périmètre de publication.

**Sources.** Skills `pz-workshop` et `pz-workshop-art`.

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-14 — **LK13-T01** : droit `PopmanManage` (modérateurs et admins) ; relève forcée seulement pour un groupe disparu ou sans vivant ; 25 cases minimum entre foyers, ancien aménagement laissé (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T02** : budgets proposés (autorité 2 ms en moyenne, 25 ms au pire, 0,5 ms par module, 40 msg/s ; client 1 ms, 8 ms) ; mesure ouverte au droit `PopmanManage` (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T06** : une écriture par image ; relecture à la première écriture seulement ; marques « fait », repas et prises différés d'une image (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T07** : empreinte de la clé du plan (collision = réécriture retardée) ; migration au premier examen plutôt qu'au chargement (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T08** : `Groups.touched` pour l'écriture en place de la peur dans `LK_Needs.perceive` ; `PEEK_CHECK` coupé par défaut (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T09** : simulation, besoins et population restent dans l'image de l'heure ; arrêt pendant une retenue (≤ 1,2 s) = changements refaits au redémarrage ; stock un groupe par image sans budget en ms (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T10** : registre des attitudes laissé en écriture immédiate ; mort en écriture immédiate (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T11** : `GroupTypes.peek` ajouté et utilisé hors des fichiers prévus (`LK_GroupTypes`, `LK_Hostility`) (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T13** : debug exigé en solo pour la fiche seulement (fenêtre d'admin LK13-T01 inchangée) ; option sans limite de distance au joueur ; santé 1..100 % (un réglage ne tue pas) ; saignement et blessure hors écran ajoutés aux champs ; valeur hors bornes ramenée à la borne (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T14** : liste des groupes renvoyée à chaque rafraîchissement (une seule opération) ; ligne écrite aussi sur changement de règle ou de cible ; coup reçu noté `combat` ; bouton visible seulement avec le droit (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T15** : fenêtres non redimensionnables, taille fixée à l'ouverture (panneau au plus 1760 × 980, fiche au plus 1000 px) (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK13-T16** : hors zone chargée, arrivée sur la case même du foyer (meuble ou mur possible) ; chaque « Aller au foyer » écrit une entrée admin au journal du groupe (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **LK13-T01** — Outils d'administration
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK08-T01
  - Fichiers : `LK_Admin.lua`
  - Faire : carte des groupes, état et journal d'un groupe, forcer une relève, déplacer un foyer, commandes réservées aux administrateurs.
  - Accepté si : commandes refusées aux non-administrateurs.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_admin.py` du 2026-10-12 (22 tests OK : chaque opération refusée à un non-admin sans donnée ni écriture, droit `PopmanManage` vérifié par `checkPermissions` et le rôle, MP deux clients (admin A reçoit liste et détail, B 4 refus), relève forcée, contrôles du déplacement de foyer, solo direct ; suite `lk.admin` jouée sur le vrai moteur RST) ; run_all 70/70 ; luacheck 16/0 ; conception `docs/annexes/conception/administration.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.admin", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-181425-solo.txt`) ; fenêtre `LivingKnox.AdminView.open()` ouverte et vue par l'utilisateur ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.admin 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.admin 3/3 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : bouton du panneau d'admin pour l'admin, refus d'un client `user` ; fenêtre (liste, détail, déplacer le foyer, forcer la relève) abandonné (règle du 2026-10-14 : jugée à l'œil, opérations couvertes par `lk.admin`). Carte = liste de coordonnées (pas de symboles) ; nouvelle case non vérifiée contre l'eau ; `LK_Admin.lua` hors VM Kahlua du banc ; identifiants internes non traduits.

- [ ] **LK13-T02** — Mesures de charge
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK09-T03
  - Fichiers : `docs/annexes/tests/validation/charge-*.md`
  - Faire : 5 groupes, 4 joueurs : coût serveur par tick, coût chez le propriétaire et les observateurs, trafic réseau, taille de l'état.
  - Idées : I1.5 (budget de réflexion selon la distance) (voir `docs/annexes/recherches/idees-bandits-alife.md`)
  - Accepté si : budgets respectés ; points chauds traités en nouvelles tâches.
  - Tests : suites + compteurs.
  - Preuve : outil de mesure `LK_Load.lua` (coût par image, module et abonné ; commandes réseau par type ; écritures des registres ; taille de l'état ; verdict de budget ; opération admin `load`) et banc `tools/load_bench.py` (serveur dédié + 4 clients, 5 groupes, 15 corps, une journée de jeu ; facteur Kahlua mesuré ≈ 3,6) le 2026-10-12 ; résultats `docs/annexes/tests/validation/charge-hors-jeu-2026-10-12.md` (serveur 0,60 ms/image lupa ≈ 2,1 ms Kahlua, pire image 110 ms, 10 msg/s envoyés, registre des groupes 117 Ko) ; `tests/test_lk_load.py` 24 OK, `kahlua` 34 OK ; suite `lk.load` 3 PASS sur le banc ; protocole `docs/annexes/tests/validation/charge-protocole.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.load", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-180221-solo.txt`) ; mesure solo : moteur 0,12 ms par image, pire image 2 ms (résolution 1 ms), registre des groupes 20 Ko, « budget: ok » ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.load 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.load 3/3 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; campagne `mp-ambient` du 2026-10-15 (copie figée du commit `54087fb`, zombies vanilla, sans mode dieu) : lk.load 3/3 (`tools/autoclient/runs/20261015-120139-run-54087fb0f84f/run/server/20261015-100346-server.txt`)
  - Reste : campagnes à 2 clients seulement : mesure de charge en MP à 4 joueurs et 5 groupes à automatiser (campagne à 4 clients, `docs/annexes/tests/validation/charge-protocole.md`) ; critère « budgets respectés » non atteint hors jeu (pire image) ; points chauds reportés en tâches LK13-T06 à LK13-T09

- [ ] **LK13-T03** — Périmètre de la première publication
  - État : `abandonné`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier
  - Faire : poser la question, consigner.
  - Accepté si : décision consignée.
  - Tests : —
  - Preuve : —
  - Reste : doublon de `E16-T01` depuis la fusion du 2026-10-08 : un seul mod, une seule publication ; le périmètre (radio, carnet, Living Knox) se décide en `E16-T01`.

- [ ] **LK13-T04** — Validation multijoueur finale et publication
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E16-T01
  - Fichiers : `workshop.txt`, `preview.png`, `CHANGELOG.md`
  - Faire : toutes les suites du périmètre sur serveur dédié avec deux clients, puis publication selon la skill `pz-workshop` après accord explicite.
  - Accepté si : aucune erreur au démarrage liée au mod ; page publiée avec la visibilité décidée.
  - Tests : suites ; skill.
  - Preuve : —
  - Reste : —

- [ ] **LK13-T05** — Essai sur serveur dédié Linux (N5)
  - État : `codé`
  - Cible : `MP`
  - Dépend de : LK02-T05
  - Fichiers : `tools/gen_animsets.py` (contrôle de casse) ; protocole dans `docs/annexes/tests/tests-en-jeu.md`
  - Faire : le serveur de l'utilisateur tourne sous Linux, sensible à la casse ; vérifier statiquement la casse de tous les chemins du mod (AnimSets, scripts, textures, `require`) contre les dossiers vanilla, puis essayer le mod sur un serveur Linux (animations des PNJ et des zombies ordinaires intactes).
  - Accepté si : contrôle statique vert ; en jeu sur Linux, PNJ et zombies ordinaires animés normalement.
  - Tests : contrôle statique ; séance sur serveur Linux.
  - Preuve : volet statique : `tools/check_case.py` (dossiers, états d'AnimSets, collisions, remplacements vanilla, `require`, chemins `media/`, `mod.info`, traductions, options sandbox) vert sur le mod publié et le mod de dev, aucune erreur à corriger ; étape `case` dans `tests/run_all.py` (21/21 le 2026-10-09), `tests/test_check_case.py` 14/14 ; protocole Linux dans `docs/annexes/tests/tests-en-jeu.md` § 10 (non exécuté) ; base `file-path-case.md` complétée ; LK03-T06 : commit `79baeb2`
  - Reste : essai sur serveur Linux reporté à la toute fin : l'utilisateur le fera lui-même (décision du 2026-10-09), protocole `docs/annexes/tests/tests-en-jeu.md` § 10
- [x] **LK13-T06** — Écriture incrémentale du registre des groupes
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK13-T02
  - Fichiers : `LK_Groups.lua, LK_Store.lua`
  - Faire : point chaud de LK13-T02 : chaque changement réencode, écrit et relit tout le registre des groupes (31,5 ms lupa, environ 110 ms Kahlua, 75 fois par jour, plusieurs par image ; 54 % du temps serveur la première heure) ; regrouper les écritures d'une même image (écriture différée et unique), et éviter la relecture de contrôle à chaque écriture.
  - Accepté si : image la plus lourde du banc `tools/load_bench.py` sous le budget proposé (25 ms Kahlua estimés) ; aucune perte après redémarrage.
  - Tests : banc ; `tools/load_bench.py`.
  - Preuve : banc du 2026-10-12 : écriture du registre des groupes regroupée une fois par image (fin d'image, `OnSave` en solo, avant relecture), relecture de contrôle à la première écriture seulement, écriture immédiate gardée pour les marques idempotentes (LK09-T06, LK14-T05, foyers, traces, troc) ; `tests/test_lk_groups.py` 28 OK, `kahlua` 35 OK (`KR-GFLUSH`), run_all 88/88 ; `tools/load_bench.py` : pire image 114,0 → 47,4 ms lupa, écritures 75 × 31,4 ms → 38 × 8,5 ms, chemin d'écriture Kahlua 101-114 → 32 ms (`docs/annexes/tests/validation/charge-groupes-2026-10-12.md`) ; 2026-10-15 : encodage RSV2 à tampon unique et mémo de clés (mêmes octets, `cmp` sur 3 passages), somme par 16 octets : écriture du registre 7,7-8,6 → 5,3-5,6 ms dans la VM Kahlua réelle ; pire image du banc désormais l'image de l'heure (`Decisions` + `Simulation`), plus l'écriture (`docs/annexes/tests/validation/charge-ecriture-etapes-2026-10-15.md`) ; run_all 127/127 ; commit `c32b702` ; phase 2 (2026-10-15) : pire image de la journée de banc mesurée sans les pauses du ramasse-miettes de lupa 4,8 → 3,8 ms lupa (0 image ≥ 4 ms, sous le budget de 7 ms lupa ≈ 25 ms Kahlua), écriture `LKGRP1` 2,58 → 1,91 ms ; aucune perte (bancs de redémarrage inchangés) ; commit `697dd69`
  - Reste : pointes isolées de 8 à 40 ms d'un seul module dues au ramasse-miettes de lupa, absentes sans lui : à confirmer en jeu avec `LivingKnox.Load` (LK13-T02)
- [x] **LK13-T07** — Alléger les plans de fortification gardés au registre
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK13-T02
  - Fichiers : `LK_Fortify.lua`
  - Faire : point chaud de LK13-T02 : le relevé `fort` fait 71 % du registre des groupes (117 Ko) ; garder une forme compacte (chantiers restants seulement, champs courts) ou le recalculer.
  - Accepté si : registre des groupes divisé par deux au moins sur le banc de charge ; rattrapage hors écran (LK14-T05) inchangé.
  - Tests : banc ; `tools/load_bench.py`.
  - Preuve : banc du 2026-10-12 : relevé `fort` en forme compacte (chantiers restants seulement, coordonnées relatives au foyer, empreinte de clé), migration de l'ancienne forme au premier examen sans perte ni double pose ; registre des groupes 117 130 → 43 122 o (÷ 2,72), champ `fort` ÷ 9, écriture Kahlua 35,6 → 12,9 ms (`docs/annexes/tests/validation/charge-fortification-2026-10-12.md`) ; `test_lk_fortify_offscreen` 17 OK (dont `CompactFormTests` 5), `kahlua` 36 OK (`KR-FORT`), run_all 89/89 ; luacheck 16/0
  - Reste : essai facultatif : `RST.run({ suite = "lk.fortify_offscreen", tags = "world" })` ; sur une sauvegarde à ancien relevé, ligne `fortify: N offscreen survey(s) rewritten in the compact form` puis aucune double barricade. Pire image du banc toujours au-dessus de 25 ms (création des corps, LK13-T10).
- [x] **LK13-T08** — Lecture sans copie profonde pour les modules chauds
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK13-T02
  - Fichiers : `LK_Groups.lua, LK_Obstacles.lua`
  - Faire : point chaud de LK13-T02 : `Groups.get` fait une copie profonde, appelée environ une fois par image par `LK_Obstacles` (la moitié de son coût) ; fournir une lecture en place documentée (lecture seule) ou un cache par image.
  - Accepté si : coût de `LK_Obstacles` divisé par deux sur le banc ; aucune écriture possible par la lecture en place.
  - Tests : banc ; `tools/load_bench.py`.
  - Preuve : banc du 2026-10-12 : `Groups.peek(gid)` lecture en place en lecture seule (règle documentée, contrôle du code par `tests/test_lk_groups.py` et contrôle facultatif `Groups.PEEK_CHECK` : 5 346 lectures, 0 écriture), utilisée par `LK_Obstacles` et `Stock.check` ; `LK_Obstacles` 0,065 → 0,011 ms/image et pire image 9,5 → 1,6 ms sur `tools/load_bench.py`, réseau identique à l'octet (`docs/annexes/tests/validation/lecture-en-place-2026-10-12.md`) ; `test_lk_groups` 32 OK ; luacheck 16/0
  - Reste : contrôle facultatif en jeu : `LivingKnox.Groups.PEEK_CHECK = true`, 10 min près d'un foyer, aucun `changed through Groups.peek`. Temps lupa seulement ; une vue passée à une fonction qui écrit n'est pas vue par le contrôle du code ; `Stock.onEveryOneMinute` reste un point chaud (LK13-T09).
- [x] **LK13-T09** — Étaler les pas horaires et le relevé du stock
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK13-T02
  - Fichiers : `LK_Simulation.lua, LK_Needs.lua, LK_Decisions.lua, LK_Stock.lua`
  - Faire : points chauds de LK13-T02 : tous les pas horaires tombent dans la même image avec chacun son écriture ; `Stock.onEveryOneMinute` coûte 3,2 ms par minute de jeu ; étaler sur plusieurs images (file de travail) et regrouper les écritures ; surveiller `dirState` (7 msg/s) et la taille d'`animState`.
  - Accepté si : aucune image du banc au-dessus du budget ; résultats identiques (déterminisme) avant et après.
  - Tests : banc ; `tools/load_bench.py`.
  - Preuve : banc du 2026-10-12 : notation horaire et déclin des attitudes passés en file (une passe par image), relecture du stock un groupe par image, écriture des groupes retenue puis unique ; images ≥ 7 ms 194-249 → 90-106, image de l'heure 14-21 → 4-9 ms, `Stock.onEveryOneMinute` 4 ms → 0,15 ms par image ; registre identique à l'octet avant/après (déterminisme) (`docs/annexes/tests/validation/etalement-2026-10-12.md`) ; `tests/test_lk_spread.py` 13 OK, `kahlua` 37 OK, run_all 91/91 ; luacheck 16/0 ; phase 2 (2026-10-15) : notation de l'heure étalée, un groupe incarné par image (`Decisions.hourQueue`), écriture retenue jusqu'à la fin, plus de notation à l'arrivée en double ; images 1 à 5 après l'heure 7,3-12,5 → 3,1-5,2 ms lupa (sans ramasse-miettes : au plus 3,2) ; registres identiques d'un passage à l'autre (`DecisionSpreadTests`) ; commit `697dd69`
  - Reste : mesure en jeu (LK13-T02)
- [x] **LK13-T10** — Écriture regroupée du registre des PNJ et encodage plus rapide
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK13-T06
  - Fichiers : `LK_Store.lua`, `LK_Bodies.lua`, `RS_Codec.lua`
  - Faire : point chaud de LK13-T06 : `Bodies.tick` fait plusieurs écritures relues du registre des PNJ (`LKREG1`) dans la même image (38,9 ms lupa) ; appliquer le même regroupement par image que le registre des groupes ; tri des clés plus rapide dans `RS_Codec.lua` (mêmes octets, 6,0 au lieu de 8,4 ms mesurés).
  - Accepté si : mêmes octets écrits qu'avant ; pire image du banc de charge abaissée ; aucun banc existant cassé.
  - Tests : banc ; `tools/load_bench.py`.
  - Preuve : banc du 2026-10-12 : registre des PNJ écrit une fois par image (`Store.flush`, relecture à la première écriture, écriture immédiate gardée pour la mort), `setWeapon` différé, tri des clés de `RS_Codec` plus rapide avec octets identiques (registres comparés au `cmp`, `KR-RFLUSH` dans la VM Kahlua) ; pire image du banc 42-53 → 13-24 ms lupa, `Bodies.tick` 38-49 → 1,0-1,4 ms (`docs/annexes/tests/validation/charge-registre-pnj-2026-10-12.md`) ; `lk_store` 11 OK, `lk_bodies` 55 OK, `kahlua` 37 OK, run_all 90/90 ; luacheck 16/0
  - Reste : essai : monde solo, groupe matérialisé, quitter et recharger (corps reliés, sans orphelin ni doublon), `RST.run({ suite = "lk.bodies", tags = "world" })` ; serveur dédié : `quit` juste après une matérialisation (`registry loaded: N npc(s)`). Pire image encore ≈ 35-85 ms Kahlua estimés, venant de `Fortify.onEveryOneMinute` et `Stock.onEveryOneMinute` (LK13-T09).
- [x] **LK13-T11** — Pointes de `Decisions.tick` et de `Fortify.onEveryOneMinute`
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK13-T09
  - Fichiers : `LK_Decisions.lua`, `LK_Fortify.lua`
  - Faire : points chauds restants de LK13-T09 : `Decisions.tick` (7-13 ms lupa, passage des membres incarnés) et `Fortify.onEveryOneMinute` (10-23 ms à des minutes isolées) ; borner le travail par image (budget en ms ou nombre d'éléments) sans changer les résultats.
  - Accepté si : aucune image du banc `tools/load_bench.py` au-dessus du budget proposé ; registre identique à l'octet avant/après.
  - Tests : banc ; `tools/load_bench.py`.
  - Preuve : banc du 2026-10-12 : `GroupTypes.peek` (lecture en place) dans la cascade et l'attitude, relevés de fortification de la minute mis en file (un par image, `settle` avant toute lecture du plan, écriture retenue) ; images ≥ 7 ms lupa 29-75 → 5-11 par journée, pire image 15-19 → 10-12 ms, `Decisions.tick` max 10 → 4-5 ms ; registres, consignes et décisions identiques à l'octet (`docs/annexes/tests/validation/etalement-pointes-2026-10-12.md`) ; `tests/test_lk_peaks.py` 10 OK, run_all 92/92 ; luacheck 16/0 ; 2026-10-15 : relevé de fortification en trois images (`planNeed`, `planSurvey`, `planFinish`), stock relu après le relevé de son groupe : `Fortify` 0 image ≥ 7 ms (6-12 avant), pointe 2,9-4,2 ms ; images ≥ 7 ms par journée 11-16 → 4-10 ; registre identique à l'octet ; bancs `test_lk_peaks.py`, `test_lk_store.py` ; commit `c32b702` ; phase 2 (2026-10-15) : membres d'un passage évalués un par image (`MEMBERS_PER_FRAME` = 1, débit et fréquence par membre inchangés) ; `Decisions` max 2,6 → 1,1 ms, `Fortify` 2,4 → 0,7 ms, pire image 3,8 ms lupa sans ramasse-miettes ; déterminisme du nouveau code (`test_lk_peaks` 13 OK) ; `animState` 2,8 → 6,3 msg/s, total 13,5 msg/s pour un budget de 40 ; commit `697dd69`
  - Reste : mesure en jeu avec `LivingKnox.Load` (LK13-T02)
- [x] **LK13-T12** — L'outil de mesure ne doit pas réordonner les abonnés
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK13-T02
  - Fichiers : `LK_Load.lua`
  - Faire : constaté en LK13-T09 : `LK_Load` remet les abonnés qu'il enveloppe en ordre alphabétique, ce qui change l'ordre des traitements pendant une mesure (objectifs notés avant la simulation, 3 écritures de plus) ; garder l'ordre d'inscription.
  - Accepté si : mêmes registres et même nombre d'écritures avec et sans mesure sur le banc.
  - Tests : banc.
  - Preuve : banc du 2026-10-12 : `LK_Load` garde l'ordre d'inscription des abonnés (rang noté par `LivingKnox.subscribe`, `LivingKnox.requeue` pour les remises en fin de liste de `Groups.flush` et `Store.flush`) ; `tools/load_bench.py` `run_compare` : 62 et 180 min avec et sans mesure, mêmes écritures et 3 registres identiques (divergents avant) ; `tests/test_lk_load.py` 29 OK (`OrderTests`, `BenchOrderTests`, 3 échouent sur l'ancien code) ; run_all 91/91
  - Reste : contrôle facultatif en jeu : `LivingKnox.Load.start()` puis `print()` après une heure (même nombre de `LKGRP1` par heure qu'en l'absence de mesure). Abonnés posés directement par `Events.X.Add` (autres mods, vanilla, fichiers RadioSurvivor) non suivis

- [x] **LK13-T13** — Fiche d'un PNJ par clic droit, besoins et santé modifiables
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK13-T01
  - Fichiers : `LK_Admin.lua`, `LK_NpcSheet.lua` (client, nouveau)
  - Faire : clic droit sur un corps de PNJ Living Knox → « Détails » : fenêtre avec tout l'état connu de l'autorité (groupe, membre, rôle, profil, chef, besoins faim/soif/fatigue/peur, santé et blessure, comportement en cours et règle de la cascade, tâche et geste, vigilance, perception résumée, arme, munitions chargées et en poche, position, foyer) ; besoins et santé modifiables (bornés par l'autorité, notés dans le journal du groupe « modifié par l'admin ») ; rafraîchie toutes les 2 s tant qu'elle est ouverte.
  - Décisions (2026-10-12, utilisateur) : accès en solo quand le mode debug est actif (`isDebugEnabled()`) et en MP aux rôles ayant la capacité de la fenêtre d'admin (`PopmanManage`), revérifiée par le serveur à chaque requête et modification ; modifiables : besoins et santé seulement ; rafraîchissement toutes les 2 s, fenêtre ouverte seulement (rien envoyé fenêtre fermée).
  - Accepté si : option absente pour un joueur sans droit ; toute requête ou modification d'un non-autorisé refusée sans donnée ni écriture ; valeur modifiée visible au passage de décision suivant et bornée.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_npcsheet.py` du 2026-10-12 (11 tests OK : option du clic droit seulement avec le droit, refus `denied` sans donnée ni écriture (solo sans `-debug`, client MP sans `PopmanManage` : 3 refus), fiche complète reçue par le réseau, bornes (besoins 0..100, santé 1..100 % de la naissance, saignement 0..60 %/h, blessure hors écran 0..99, hors bornes ramené à la borne), note au journal du groupe `... set by admin`, faim lue au passage de décision suivant (règle `hunger`), relecture toutes les 2 s, aucune requête fenêtre fermée) ; opérations `npc`/`npcSet` sur le canal de `LK_Admin.lua`, `Health.setByAdmin`, client `LK_NpcSheet.lua`, clés `IGUI_LK_Sheet_*` EN/FR ; suite `lk.npcsheet` ; run_all 93/93 ; luacheck 16/0 ; `docs/annexes/conception/administration.md`, `docs/annexes/tests/tests-en-jeu.md` § 15 ; base `ui-windows.md` (`setOnlyNumbers` ne filtre que la frappe) ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.npcsheet", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-193804-solo.txt`) ; fiche ouverte par clic droit et vue par l'utilisateur (lisibilité à reprendre : LK13-T15) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.npcsheet 4/4 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.npcsheet 4/4 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : client `user` sans option « Détails (Living Knox) » ni donnée. Journal du groupe limité à 32 entrées (réglages répétés chassent les anciennes).

- [x] **LK13-T14** — Panneau de debug des PNJ : groupes, activité en direct, journal d'activité
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK13-T13
  - Fichiers : `LK_Admin.lua`, `LK_Activity.lua` (autorité, nouveau), `LK_DebugView.lua` (client, nouveau)
  - Faire : bouton « Living Knox – PNJ » dans le panneau debug vanilla (et accès depuis la fenêtre d'admin) ouvrant un panneau : liste de tous les groupes, pour le groupe choisi l'activité en direct de chaque PNJ (comportement, règle, tâche, geste, cible, position, besoins, incarné ou hors écran) et le journal d'activité du groupe ; ouverture de la fiche LK13-T13 d'un membre. Journal d'activité fin tenu par l'autorité : chaque changement de comportement d'un PNJ avec sa raison, objectif du groupe, alerte, repas, soin, combat, avec l'heure de jeu ; en mémoire seulement, 200 lignes par groupe, non sauvegardé ; le journal sauvegardé existant reste affiché à côté.
  - Décisions (2026-10-12, utilisateur) : mêmes droits que LK13-T13 ; rafraîchissement du groupe choisi toutes les 2 s tant que le panneau est ouvert ; journal fin en mémoire (200 lignes par groupe), non sauvegardé.
  - Accepté si : aucun message réseau panneau fermé ; refus sans donnée pour un non-autorisé ; journal borné à 200 lignes ; coût du journal négligeable sur le banc de charge.
  - Tests : banc ; banc de charge ; suite en jeu.
  - Preuve : banc `tests/test_lk_debugview.py` du 2026-10-12 (14 tests OK : refus sans donnée d'un non-autorisé (solo sans `-debug`, client MP sans `PopmanManage`), journal borné à 200 lignes de 160 caractères, envoi incrémental après `after`, aucune requête panneau fermé, activité en direct de chaque membre, ouverture de la fiche LK13-T13, bouton du panneau debug vanilla sans retirer les autres) ; `LK_Activity.lua` (autorité, mémoire seulement : comportement/règle/cible avec raison, objectif et relève, alerte, repas, soin, combat), opération `activity` de `LK_Admin.lua`, client `LK_DebugView.lua` (bouton « Living Knox - PNJ » de `ISDebugMenu`, bouton de la fenêtre des groupes, `LivingKnox.DebugView.open()`) ; coût sur `tools/load_bench.py` 60 min : 0,0003 ms par image lupa, écritures et registres identiques avec et sans journal (`docs/annexes/tests/validation/charge-journal-activite-2026-10-12.md`) ; suite `lk.debugview` ; run_all 94/94 ; luacheck 16/0 ; `docs/annexes/conception/administration.md`, `docs/annexes/tests/tests-en-jeu.md` § 15 ; base `ui-windows.md` (bouton ajouté à `ISDebugMenu`) ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.debugview", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-193817-solo.txt`) ; panneau ouvert depuis le panneau debug et vu par l'utilisateur (lisibilité à reprendre : LK13-T15) ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.debugview 4/4 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : refus d'un client `user`, aucun `adminRequest` panneau fermé. Membre hors écran : poste, état et dernière position seulement ; journal vide après un redémarrage ; doublure `ISDebugMenu` du banc.

- [x] **LK13-T15** — Panneaux de debug en tableaux, actions : rôle, téléportation, nom
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK13-T14
  - Fichiers : `LK_DebugView.lua`, `LK_NpcSheet.lua`, `LK_Admin.lua`
  - Faire : constaté en jeu le 2026-10-12 : panneau des groupes et fiche peu lisibles (texte en lignes). Présenter les groupes, les membres et le journal d'activité en tableaux à colonnes (en-têtes, colonnes alignées, texte coupé proprement), la fiche en sections étiquetées ; actions d'admin : changer le rôle d'un membre, se téléporter vers un PNJ, changer son prénom et son nom.
  - Décisions (2026-10-12, utilisateur, après un essai en jeu) : « il faudrait des tableaux pour que ce soit plus clair, en plus il faudrait pouvoir faire des trucs : changer le rôle, se téléporter vers, changer son prénom/nom ». Mêmes droits que LK13-T13 (revérifiés par l'autorité à chaque action, chaque action notée au journal du groupe).
  - Accepté si : colonnes lisibles à 1920 px et plus ; trois actions faites par l'autorité et refusées à un non-autorisé.
  - Tests : banc ; suite en jeu.
  - Preuve : bancs du 2026-10-12 : `tests/test_lk_npcsheet.py` 18 OK et `tests/test_lk_debugview.py` 19 OK (refus d'un non-autorisé pour chaque action, rôle hors liste ou identique refusé, prénom/nom nettoyés et bornés (lettres ASCII, espace, `'`, `.`, `-`, 1 à 24), téléportation vers une case libre voisine du corps ou la dernière position connue, refus sans position) ; tableaux à colonnes (`LK_Table.lua` : tri par clic sur l'en-tête, texte coupé par « ... », infobulle par ligne, fond opaque, petite police) pour groupes, membres, journal d'activité et journal sauvegardé ; fiche en sections, nombres arrondis, santé en %, champs préremplis ; actions dans `LK_Admin.lua` notées au journal du groupe ; nom repris par le carnet (`Admin.hookNames`) ; suites `lk.npcsheet` (4) et `lk.debugview` (3) ; run_all 97/97 ; luacheck 16/0 ; `docs/annexes/conception/administration.md`, `docs/annexes/tests/tests-en-jeu.md` § 15 ; base `ui-windows.md` (tableau à colonnes `ISScrollingListBox`), `multiplayer.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.npcsheet 4/4 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.npcsheet 4/4, lk.debugview 4/4 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : les trois actions refusées à un client `user` ; lisibilité à 1920 px, tri et infobulles abandonné (règle du 2026-10-14 : jugement à l'œil). MP : `/teleportto` exige `TeleportToCoordinates` (moderator non vérifié). Résumé d'histoire déjà composé garde l'ancien nom ; noms accentués refusés ; pas de retour au nom d'origine ; le rôle ne change ni profil ni arme.
- [x] **LK13-T16** — Coordonnées des PNJ dans le panneau de debug, téléportation hors écran
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK13-T15
  - Fichiers : `LK_DebugView.lua`, `LK_Admin.lua`
  - Faire : demandé en jeu le 2026-10-13 : le panneau de debug des PNJ n'affiche pas où se trouve chaque PNJ, et la téléportation vers un PNJ hors écran échoue (`npcGoto` ne connaît que le corps incarné ou la dernière position du registre, sinon refus « no known position »). Ajouter une colonne de coordonnées (corps, sinon dernière position connue, sinon foyer du groupe, avec la source indiquée) et faire de la téléportation vers un PNJ non incarné un saut vers cette position (foyer du groupe en dernier recours).
  - Accepté si : au banc, chaque membre vivant a des coordonnées et une source ; `npcGoto` d'un membre jamais incarné mène au foyer de son groupe ; en jeu, téléportation vers un PNJ hors écran.
  - Tests : banc ; essai solo dans le panneau.
  - Preuve : bancs du 2026-10-13 : `tests/test_lk_debugview.py` 23 OK (`PositionTests`, `PositionSoloTests` : chaque membre vivant a des coordonnées et une source body / last / home, membre jamais incarné mené au foyer par `/teleportto`, `homeGoto` refusé sans donnée à un client sans la capacité, groupe inconnu ou sans foyer refusé, solo déplacé par l'autorité), `tests/test_lk_npcsheet.py` 18 OK, `tests/test_lk_admin.py` 22 OK ; `Admin.positionOf`, op `homeGoto` (`LK_Admin.lua`), colonnes Foyer et Position, bouton « Aller au foyer du groupe » (`LK_DebugView.lua`, `LK_NpcSheet.lua`), traductions EN/FR, suite `lk.debugview` 4 tests ; conception `administration.md`, protocole § 15 de `tests-en-jeu.md` ; luacheck 16/0 (commit LK13-T16) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : lk.debugview 4/4 (`20261013-112148-solo.txt`)
  - Reste : essai solo `-debug` : `RST.run({ suite = "lk.debugview", tags = "world" })` (4 PASS) ; panneau « Living Knox - PNJ » : colonnes Foyer et Position, « Aller au foyer du groupe » vers un groupe lointain, « Se téléporter » vers un membre hors écran ; MP séance finale (`homeGoto` refusé à un client `user`). Limites : membre sans PNJ joignable seulement par le foyer ; position voulue d'un PNJ virtuel non utilisée ; clés `IGUI_LK_*_LastPos` devenues inutiles
