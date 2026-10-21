# LK02 — Jalon 1 : corps et gestes prouvés (décision de continuer)

**Objectif.** Démontrer, en solo puis sur serveur dédié avec deux clients, qu'un PNJ de Living Knox **a l'air humain** (vêtements, cheveux, peau, arme en main), **ne se comporte pas en zombie**, **marche vers une destination décidée par le serveur** et **montre ses gestes** (viser, frapper, s'accroupir) à l'autre joueur. Durée visée : 2 à 3 semaines. Se termine par une décision explicite (LK02-T09).

**Dépend de.** LK01-T01, LK01-T02 ; moteur de tests en jeu `E01-T04` (lancement console) et `E01-T05` (suites serveur).

**Contraintes moteur connues** (base `multiplayer.md`, entrée « Zombies en MP : un seul simulateur ») : un seul simulateur par corps ; un zombie distant suit le réseau et ne cherche pas de chemin ; `BumpType`, variables d'animation et objets en main ne sont pas transmis ; seul le propriétaire applique les dégâts subis par le corps ; le serveur peut blesser un joueur (`DamageFromWeapon` + `sendDamage`).

**Hors périmètre.** Obstacles (LK04), combat réel (LK06), groupes (LK08). Le jalon ne vise qu'un ou deux PNJ de test.

## Décisions

- 2026-10-09 — **Base du corps** (après LK02-T01) : ni zombie ordinaire (A) ni joueur réanimé (B) n'est choisi d'emblée ; un **essai comparatif court** (`LK02-T10`) crée en jeu un PNJ de chaque sorte et mesure apparence chez deux clients, persistance, neutralisation et marche, avant le choix (choix de l'utilisateur).
- 2026-10-09 — **Voix** : l'essai comparatif teste un moyen de couper les gémissements de zombie ; le jalon n'exige le silence que si un moyen fiable est trouvé, sinon une tâche dédiée viendra plus tard (choix de l'utilisateur).
- 2026-10-09 — **Base retenue : B, joueur réanimé** (choix de l'utilisateur après l'essai solo `LK02-T10`) : identité conservée hors zone (A la perd), peau humaine `clean` la plus crédible ; corps créé par `addZombiesInOutfit` → `DoZombieInventory` → `createCorpse(zombie)` → `reanimate()`, apparence posée avant la réanimation ; identité portée par les ModData du corps. Conséquences mesurées : marche en mode `pathfind` avec `useless` (6,5 cases en 8 s), `useless` posé hors trajets (sinon le corps erre), voix coupées par un préfixe de voix inexistant (le jalon exige donc le silence, décision « voix » ci-dessus), vêtements déchirés de la tenue zombie à remplacer (LK02-T03). Validation MP regroupée à la fin (`docs/annexes/plans/README.md`).
- 2026-10-09 — **Arme du PNJ (LK02-T06)** (choix de l'utilisateur) : arme **accrochée** (dos ou hanche, `sendAttachedItem`, sans événement) au repos et en marche ; **mise en main** par chaque client seulement pour viser, garder ou frapper (poses justes grâce à la variable `Weapon`), avec neutralisation des abonnés `OnEquipPrimary` qui supposent un joueur (base `zombies-as-npc-bodies.md`).
- 2026-10-09 — **Décision de jalon (LK02-T09) : continuer le moteur propre** (choix de l'utilisateur), sur la preuve solo (`docs/annexes/tests/validation/jalon1-2026-10-09.md`, `lk.milestone1` 3/3) ; la preuve à deux clients reste due à la séance MP finale, et la décision pourra être revue si elle échoue.
- 2026-10-15 — **`lk.essai` en MP** : la base A est retirée de la campagne MP (caduque depuis le 2026-10-09), seule la base B y reste ; confirmé par défaut (2026-10-15, l'utilisateur ne souhaite pas être interrogé sur le détail).

## Tâches

- [x] **LK02-T01** — Investigation vanilla : corps, apparence, états et animations des zombies
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/annexes/conception/corps-et-animations.md` ; entrées de la base `.claude/pz-knowledge`
  - Faire : dans le Java et les fichiers vanilla 42.21 **uniquement** :
    - comment le serveur crée un zombie à une case précise et le rend persistant (identifiant de tenue, retour après déchargement) ;
    - comment lui donner une apparence humaine (`HumanVisual`, vêtements, cheveux, barbe, peau) et la transmettre aux clients ;
    - quels drapeaux et états neutralisent les comportements de zombie (attaque, morsure, cris, poursuite, réveil) ;
    - comment les `AnimSets` et `actiongroups` des zombies choisissent un nœud selon une variable, quels clips du joueur (`Bob_…`) sont utilisables, et quels états servent aux zombies distants (`walktoward-network`) ;
    - comment afficher un objet en main d'un zombie chez tous les clients.
  - Accepté si : chaque point est prouvé par `fichier:ligne` vanilla ou marqué hypothèse à mesurer ; faits génériques journalisés dans la base.
  - Tests : —
  - Preuve : fiche `docs/annexes/conception/corps-et-animations.md` (brouillon, 2026-10-09 ; Java 42.21.0 et `media/` vanilla seulement, aucun code de Bandits! ni d'A-Life lu) ; base : nouveau `zombies-as-npc-bodies.md` (7 entrées : `OnZombieCreate` avant identifiant et habillage, apparence rejouée depuis la tenue persistante, peau humaine, joueur réanimé, effet réel de `useless`/`noTeeth`/voix, choix des nœuds d'animation et états `-network`, objet en main), compléments `multiplayer.md` et `character-textures.md` ; `tests/run_all.py` 10/10 ; E17-T05 : commit `a3d03a0`
  - Reste : 7 hypothèses à mesurer en jeu (fiche, section Tests) ; questions de conception pour LK02-T02 à T07 posées à l'utilisateur (base du corps, neutralisation pendant la marche, voix, arme, animations, clé d'identité)

- [x] **LK02-T02** — Création d'un corps de PNJ côté serveur avec identité
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK02-T01, LK01-T02, LK02-T10
  - Fichiers : `media/lua/server/LivingKnox/LK_Bodies.lua` ; `media/lua/shared/LivingKnox/LK_Identity.lua`
  - Faire : registre serveur des PNJ (identifiant stable, génération, profil d'apparence) ; création du corps sur une case chargée ; liaison corps ↔ PNJ retrouvée après déchargement, rechargement et redémarrage ; corps orphelins retirés.
  - Accepté si : le même PNJ est retrouvé après sortie de zone et redémarrage ; aucun doublon.
  - Tests : banc ; suite en jeu `lk.bodies`.
  - Preuve : `LK_Identity.lua`, `LK_Store.lua` (registre schéma 1 dans un fichier serveur, deux emplacements alternés, refus bloquant d'un schéma inconnu), `LK_Bodies.lua` (chemin B, étiquette `lkNpcId`/`lkNpcGen` en ModData, `useless`, sondage de 64 zombies toutes les 15 images, doublons et orphelins retirés) ; `tests/test_lk_bodies.py` 27/27 (aller-retour hors zone, redémarrage simulé, doublons, orphelins, garde `Enabled`, client MP inactif), `test_kahlua.py` 11/11, `tests/run_all.py` 12/12 le 2026-10-09 ; serveur dédié de test : `registry: new world, empty registry`, fichier de registre écrit, aucune erreur Lua ; fiche `docs/annexes/conception/corps-registre.md` ; LK01-T06 : commit `20d5ab8` ; **en jeu solo le 2026-10-09** (`rstest-solo`, `console.txt` 11:58) : `lk.bodies` 5/5 PASS (aller-retour : `same object true`) ; `LKB.spawn` → `lk-6 gen=1 embodied inWorld=true` ; après rechargement de la partie : `registry loaded: 1 npc(s)` puis `npc lk-6 bound to its body (generation 1)` au 15e tick, un seul corps ; `LKB.clear` → corps retiré
  - Reste : ⚠ arrêt brutal entre une création et la sauvegarde du monde (corps relu jugé périmé) : parade à décider avec LK09 ; zombie temporaire visible jusqu'à 5 s chez les clients MP (LK02-T07) ; `useless` écrasé par le client propriétaire (LK02-T04) ; contrôles MP à la séance finale

- [x] **LK02-T03** — Apparence humaine visible par tous les clients
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK02-T02, LK02-T10
  - Fichiers : `LK_Appearance.lua` (shared) ; profils d'apparence en données
  - Faire : vêtements, cheveux, barbe, couleur de peau tirés d'un profil ; appliqués côté serveur et repris par chaque client à l'apparition du corps.
  - Accepté si : deux clients voient le même PNJ habillé de la même façon, sans peau de zombie ni sang de zombie.
  - Tests : suite `lk.appearance` + captures des deux clients.
  - Preuve : `LK_Appearance.lua` : 10 profils en données (peaux humaines 1-5, coupes et barbes vanilla, couleurs de `MainCreationMethods.lua`), tirage déterministe par numéro de PNJ, application avant la réanimation (tenue rejouée par sa variante, arme d'habillage retirée, peau/cheveux/barbe, sang, saleté, plaies, trous et pièces des vêtements retirés) ; registre en schéma 2 avec migration du schéma 1 ; `tests/test_lk_appearance.py` 15/15, `test_lk_bodies.py` 27/27, `test_kahlua.py` 12/12, `tests/run_all.py` 13/13 le 2026-10-09 ; serveur dédié de test : 6/6 sans erreur Lua ; fiche `docs/annexes/conception/apparence.md` ; LK02-T02 : commit `04fd056` ; **en jeu solo le 2026-10-09** (`rstest-solo`, `console.txt` 12:24) : migration `schema 1 to 2` au chargement, `lk.appearance` 4/4 (peaux `MaleBody01`/`FemaleBody01`/`MaleBody04`/`FemaleBody05`, coupes et barbes conformes, 6 à 9 vêtements sans trou, sang, saleté ni pièce, ré-incarnation identique) ; rendu des 4 profils validé à l'œil par l'utilisateur ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.appearance 5 PASS + 1 SKIP (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.appearance 5 PASS + 1 SKIP (phase 1 du redémarrage avec une autre liste de mods) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`), lk.look vert chez le client 2 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`) ; campagne avec un mod de vêtements en plus du 2026-10-15 (copie figée `54087fb`, 7/7) : lk.appearance 6/6, dont « an npc embodied again after a restart with another mod list keeps its clothes (two runs) », lk.look du client 2 vert (`tools/autoclient/runs/20261015-121241-run-54087fb0f84f/run/server/20261015-101651-server.txt`)
  - Reste : Limite : objets accrochés hors du descripteur partagé (LK02-T06/T07)

- [x] **LK02-T04** — Neutralisation des comportements de zombie
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK02-T02, LK02-T10
  - Fichiers : `LK_ZombieGuard.lua` (shared)
  - Faire : le corps n'attaque pas, ne mord pas, ne crie pas, ne poursuit pas les joueurs, ne réagit pas aux bruits comme un zombie ; appliqué chez le propriétaire et, pour l'affichage, chez les autres clients.
  - Accepté si : un joueur peut rester une minute au contact du PNJ sans être attaqué, sur les deux clients ; les zombies vanilla voisins gardent leur comportement normal.
  - Tests : suite `lk.guard` + protocole.
  - Preuve : `LK_ZombieGuard.lua` : `useless` (sauf trajet autorisé), `noTeeth` partout, cible, repas et cible de coups effacés par le simulateur, voix coupée par le préfixe `LKSilentZombie` chez chaque client ; corps reconnus par le registre côté autorité et par une liste d'`onlineId` envoyée par le serveur côté client (`guardRoster` versionné, `guardHello`) ; zombies sans étiquette jamais touchés ; `tests/test_lk_guard.py` 12/12, `tests/run_all.py` 14/14 le 2026-10-09 ; serveur dédié de test 6/6 sans erreur Lua ; fiche `docs/annexes/conception/neutralisation.md` ; LK02-T03 : commit `c72f713` ; **en jeu solo le 2026-10-09** (`rstest-solo`, `console.txt` 12:43) : `lk.guard` 3/3 (voisin vanilla avec sa voix `MaleZombie`, PNJ `LKSilentZombie` ; 60 s au contact : 3 594 relevés, 0 cible, 0 attaque, 0 repas, santé 100 ; aller-retour : même objet, voix coupée) ; observations de l'utilisateur : PNJ silencieux, aucune réaction à un cri du joueur, zombie vanilla voisin normal (cible nulle dans la suite car le joueur était invisible) ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.guard 3/3 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.guard 4/4, dont « 60 s at contact on the second client: no target, no attack, no eating, unhurt » (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; lk.spawnclean 2/2 avec lk.appear.check des clients (voix coupée) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`)
  - Reste : Limites : plantes et feux de camp non protégeables, marche vers un cadavre derrière un obstacle possible, son de blessure non coupé

- [x] **LK02-T05** — Animations de base générées
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK02-T01
  - Fichiers : `tools/gen_animsets.py` ; `common/media/AnimSets/zombie/…` (XML générés) ; `docs/annexes/conception/corps-et-animations.md`
  - Faire : table source (geste → clip vanilla, conditions sur nos variables) et générateur d'XML pour les états de zombie utilisés (repos, marche locale et réseau, course, accroupi, visée arme à feu, garde de mêlée, frappe) ; ne jamais modifier les nœuds vanilla des zombies ordinaires (conditions exclusives sur notre variable d'acteur).
  - Accepté si : en solo, chaque geste se joue sur commande de console ; un zombie ordinaire garde ses animations.
  - Tests : suite `lk.anims` (bascule des gestes) + protocole visuel.
  - Preuve : `tools/anim_table.json` (13 nœuds : repos, accroupi, visée pistolet et arme longue, garde 1 et 2 mains, frappe 1 et 2 mains, marche, course, marche accroupie, attente de chemin ; clips `Bob_` prouvés dans les AnimSets du joueur) ; `tools/gen_animsets.py` (19 fichiers sous `common/media/AnimSets/zombie/{idle,walktoward,walktoward-network,pathfind}/lkactor_*.xml`, priorité 5, condition exclusive `LKActor=true`, `--check` vert) ; `LK_Anim.lua` (`setGesture` sur l'autorité, variables posées par chaque machine qui affiche le corps) ; `tests/test_gen_animsets.py` 10/10 (exclusivité vérifiée par mutation), `tests/test_lk_anim.py` 9/9, `tests/run_all.py` 16/16 le 2026-10-09 ; serveur dédié de test : AnimSets lus sans erreur ; LK02-T04 : commit `ce04eaf` ; **en jeu solo le 2026-10-09** (`rstest-solo`) : gestes `aim`/`guard`/`strike`/`crouch`/`idle` jugés parfaits à l'œil par l'utilisateur, nœuds `LKActor…` et clips `Bob_…` lus par `lk.anims`, zombie ordinaire voisin sur `defaultIdle` ; `lk.anims` verte après déplacement du joueur (premier passage en échec par le défaut `LK02-T11`)
  - Reste : ⚠ serveur Linux non essayé (casse) ; MP à la séance finale (variables posées par chaque client, propagation `animState`) ; à mesurer plus tard : vitesse de `Bob_Walk`/`Bob_Run`, frappe en boucle

- [ ] **LK02-T06** — Arme en main visible par tous
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK02-T03, LK02-T05
  - Fichiers : `LK_Equipment.lua` (shared), commande serveur → clients
  - Faire : le serveur décide de l'arme du PNJ (identifiant d'objet vanilla) ; chaque client affiche le modèle et la posture correspondants.
  - Accepté si : fusil, pistolet et arme de mêlée visibles et tenus correctement chez les deux clients.
  - Tests : suite `lk.equipment` + captures.
  - Preuve : `LK_Equipment.lua` : arme décidée par le serveur (champ optionnel `npc.weapon`, schéma 2 inchangé), accrochée selon son `AttachmentType` (table de `ISHotbarAttachDefinition.lua` recopiée), mise en main par chaque client pour `aim`/`guard`/`strike` (deux mains pour les armes longues), raccrochée ensuite ; `Fishing.Handler.handleFishing` enveloppée pour ignorer un non-joueur ; table `equipState` versionnée pour les clients arrivés après ; `tests/test_lk_equipment.py` 16/16, `tests/run_all.py` 17/17 le 2026-10-09 ; serveur dédié de test 6/6 sans erreur Lua ; fiche `docs/annexes/conception/equipement.md` ; LK02-T11 : commit `4f5f831` ; **en jeu solo le 2026-10-09** (`rstest-solo`, `console.txt` 13:52) : fusil, batte et hachette accrochés puis en main (`aim`, `guard`, `strike`) jugés corrects par l'utilisateur ; `lk.equipment` 2/2 (armes à feu et de mêlée : accrochées au repos, en main pour le geste, raccrochées) ; aucune erreur `handleFishing` dans la session ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.equipment 3/3, dont l'arme à feu d'un mod d'armes (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; étapes lk.weapon.state et lk.weapon.count vertes chez le client 2 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`)
  - Reste : client arrivé après la pose de l'arme non automatisé ; campagne solo du 2026-10-15 : lk.equipment 3 FAIL « npc spawn refused: square … is not loaded » (régression du harnais : le test n'a pas tourné) (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`) ; ⚠ abonnés `OnEquipPrimary` d'autres mods non neutralisés ; arme accrochée sur la copie serveur (pillage du cadavre : LK07)

- [ ] **LK02-T07** — Exécution par le propriétaire : consigne « aller à » et relais de pose
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK02-T04, LK02-T05
  - Fichiers : `media/lua/server/LivingKnox/LK_Directives.lua` ; `media/lua/client/LivingKnox/LK_Executor.lua` ; `media/lua/client/LivingKnox/LK_Presentation.lua`
  - Faire : le serveur fixe une consigne versionnée (aller à une case, s'arrêter, viser une direction) et l'envoie aux clients proches ; seul le client propriétaire (`not isRemoteZombie()`) l'exécute (recherche de chemin, geste) et rapporte position et pose ; le serveur contrôle et relaie la pose ; les autres clients appliquent la pose reçue ; au changement de propriétaire, le nouveau reprend la consigne courante.
  - Accepté si : avec deux joueurs, le PNJ marche jusqu'à la case choisie quel que soit le propriétaire ; l'autre client voit la marche et la visée ; un transfert de propriété en cours de route ne fait ni demi-tour ni arrêt durable.
  - Tests : banc (transfert simulé) ; suite `lk.executor` + protocole à deux clients.
  - Preuve : `LK_Directives.lua` (consigne versionnée `move`/`stop`/`face` côté serveur, table `dirState`, rapports `dirReport` acceptés du seul `getOwnerPlayer()` avec contrôles de cohérence, relais `poseState`), `LK_Executor.lua` (exécution par le simulateur en `pathfind` en gardant `useless`, reprise au changement de propriétaire), `LK_Presentation.lua` (orientation relayée, position jamais touchée) ; corps simulé par le serveur : ligne droite si dégagée, sinon attente d'un client, sans téléportation ; `tests/test_lk_directives.py` 16/16 (transfert à mi-chemin sans demi-tour, livraison non ordonnée, rapports refusés), `tests/run_all.py` 18/18 le 2026-10-09 ; serveur dédié de test 6/6 ; fiche `docs/annexes/conception/consignes.md` ; LK02-T06 : commit `1735f76` ; **en jeu solo le 2026-10-09** (`rstest-solo`, `console.txt` 15:36) : commandes `moveTo`/`stop`/`face` validées par l'utilisateur ; `lk.executor` 3/3 (9 cases en 4,9 s puis repos et `useless` rétabli ; arrêt net : 0,26 case après l'ordre ; orientation sud à 90°) ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.executor 3 PASS + 2 SKIP (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.executor 4 PASS + 1 SKIP (solo seulement), dont « body reappearance: open move resumed, stale directive ignored » sur serveur dédié (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : lk.executor 5/5 (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : lk.rejoin PASS (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093552-server.txt`)
  - Reste : transfert de propriété en cours de route : lk.handover FAIL « resumed 3357 ms after the owner change » (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; délai de relais par `LKB.pose` non mesuré ; ⚠ consignes non persistées (trajet abandonné au redémarrage, LK05 réémettra) ; écran partagé non traité ; seuils (arrivée 1 case, 8 cases/s) à recalibrer

- [ ] **LK02-T08** — Suite de jalon et mesures
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK02-T06, LK02-T07
  - Fichiers : suite `lk.milestone1` ; `docs/annexes/tests/validation/jalon1-<date>.md`
  - Faire : enchaîner apparition, apparence, arme, neutralisation, marche, gestes et transfert ; mesurer trafic réseau par PNJ, délai de pose, coût par tick chez le propriétaire et chez un observateur ; captures des deux clients.
  - Accepté si : rapport complet avec mesures et captures ; défauts listés en nouvelles tâches.
  - Tests : `RST.run('lk.milestone1')`, `RST.server('lk.milestone1')`.
  - Preuve : suite `lk.milestone1` (mod de dev : un PNJ enchaîné de l'apparition à l'aller-retour hors zone, deux PNJ ensemble, contrôle du nettoyage et coût à vide), sonde `RST_LKProbe.lua` (coût des abonnés `OnTick`, corps sondés, trafic `LivingKnox`, `LKM.start/stop` pour un observateur) sans modification du mod principal ; rapport `docs/annexes/tests/validation/jalon1-2026-10-09.md` (résultats solo T02-T07/T10/T11, défauts reliés aux tâches, propositions N1-N7) ; `tests/test_lk_milestone.py` 12/12, `tests/run_all.py` 19/19 le 2026-10-09 ; LK02-T07 : commit `7d33352` ; **en jeu solo le 2026-10-09** : `lk.milestone1` 3/3 (`20261009-140249-solo.txt`), mesures reportées au § 5 du rapport (relève 2,9 s, marche 2,3 cases/s, course 4,8 cases/s, coût 0,043 ms/image avec 1 PNJ, 0,055 avec 2, 0,017 sans PNJ, aller-retour sans perte) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.milestone1 3/3 avec l'étape lk.probe du client 2 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/client2/20261015-090729-steps.txt`)
  - Reste : mesures § 6 (trafic par PNJ, délai de relais, coût chez l'observateur, captures des deux clients) non relevées par la campagne ; temps réellement passé à renseigner ; propositions N1-N7 à valider avant création

- [x] **LK02-T09** — Décision de jalon : continuer ou se replier
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK02-T08
  - Fichiers : ce fichier ; `LK00-cadrage.md`
  - Faire : présenter le rapport du jalon et le temps réellement passé, puis poser la question.
  - Questions : Options : continuer le moteur propre (LK03 et suivantes) [si le jalon est concluant] / repli sur un addon de Project A-Life (essai décrit dans l'analyse, §7) / repli sur Bandits! en « propriétaire unique » (option A+).
  - Accepté si : décision consignée ; étapes suivantes ajustées ou remplacées.
  - Tests : —
  - Preuve : décision du 2026-10-09 (section Décisions), rapport `docs/annexes/tests/validation/jalon1-2026-10-09.md`
  - Reste : décision à revoir si la séance MP finale échoue

- [ ] **LK02-T10** — Essai comparatif : zombie ordinaire (A) ou joueur réanimé (B)
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK02-T01, E01-T05
  - Fichiers : mod de dev `dev/batman_RadioSurvivorTests/42.21/media/lua/{shared,server,client}/RST/…` (code d'essai jamais publié) ; `docs/annexes/conception/corps-et-animations.md` (résultats)
  - Faire : commandes de console et suite `lk.essai` (suites `world`, partie `rstest*`) qui créent côté serveur un PNJ de chaque sorte près du joueur, puis mesurent : apparence (peau, cheveux, vêtements, sang) chez deux clients et après une reconnexion ; persistance après sortie de zone, déchargement et redémarrage (identité retrouvée, doublons) ; neutralisation (`useless`, `noTeeth`, cible effacée : un joueur au contact une minute) ; marche vers une case (sans `useless`, avec `useless` + `pathfind`, cible effacée) ; moyen de couper les voix ; objet en main posé côté client et `sendAttachedItem`. Nettoyage complet en `after`.
  - Accepté si : rapport comparatif A/B consigné dans la fiche, chaque mesure prouvée par un fichier de résultat RST ou une capture ; recommandation argumentée pour LK02-T02 à T07 présentée à l'utilisateur.
  - Tests : banc `lupa` des commandes et du nettoyage ; suite `lk.essai` en solo puis sur le serveur dédié de test avec deux clients.
  - Preuve : code d'essai dans le mod de dev (`RST_LKEssai.lua`, `RST_LKEssaiServer.lua`, `RST_LKEssaiClient.lua`, suite `lk.essai`) : commandes `LKE.spawn/list/here/set/walk/clear` ; chemin B réel `addZombiesInOutfit` → `DoZombieInventory` → `createCorpse(zombie)` → `reanimate()` ; `tests/test_lk_essai.py` 19/19 (routage, refus hors debug, hors `rstest*` et sans capacité, autorité, nettoyage), `tests/run_all.py` 11/11 le 2026-10-09 ; serveur dédié de test `-Filters "rst"` : 6/6, mod de dev chargé sans erreur Lua ; protocole et tableau A/B dans `docs/annexes/conception/corps-et-animations.md` ; LK02-T01 : commit `cb9aa64` ; **solo le 2026-10-09** (`rstest-solo`) : suite `lk.essai` 11/12 (`20261009-090207-solo.txt` ; l'échec est la mesure « A perdu après sortie de zone », B retrouvé), observations manuelles dans le tableau A/B de la fiche (B `clean` le plus humain, voix coupées par préfixe, marteau en main et pistolet accroché visibles, `clear` complet) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.essai 7/7 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`)
  - Reste : volet MP : changement de propriétaire non prouvé (lk.handover FAIL, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) et `sendAttachedItem` pour un client arrivé après non automatisé ; apparence chez l'autre client couverte par lk.look (LK02-T03), reconnexion et redémarrage par `mp-persist` ; recommandation présentée et base B retenue le 2026-10-09

- [x] **LK02-T11** — Corps créé sur une case libre (sinon il ne se relève jamais)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK02-T02
  - Fichiers : `media/lua/server/LivingKnox/LK_Bodies.lua` ; suites `lk.bodies`, `lk.appearance`, `lk.guard`, `lk.anims` du mod de dev ; `tests/test_lk_bodies.py`
  - Faire : un corps réanimé reste couché tant qu'un personnage debout se tient sur sa case ou une voisine (`isBeingSteppedOn`, base `zombies-as-npc-bodies.md`) ; choisir pour la création une case chargée dont les 8 voisines sont libres de tout personnage debout (recherche bornée autour de la case voulue), refuser proprement sinon ; les suites placent leurs PNJ à l'écart des PNJ existants.
  - Accepté si : deux PNJ demandés sur la même case se relèvent tous les deux ; la suite `lk.anims` passe avec un PNJ déjà présent près du joueur.
  - Tests : banc ; suites en jeu.
  - Preuve : `LK_Bodies.lua` : `findFreeSquare` (case chargée, `isFree(false)`, aucun personnage debout ni corps de PNJ sur la case et ses 8 voisines, anneaux jusqu'au rayon 4, refus sans consommer de numéro), `want`/`last` dans le registre ; suites du mod de dev espacées ; `tests/test_lk_bodies.py` 32/32 (`FreeSquareTests`), `tests/run_all.py` 16/16 le 2026-10-09 ; LK02-T05 : commit `0c97afd` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo lk.bodies « two npcs wanted on the square of an npc already there: all on distinct free squares, all standing » PASS ; lk.anims « a new npc is standing from its creation » PASS (`20261013-202155-solo.txt`)
  - Reste : en jeu solo : `lk.anims` avec un PNJ créé à la main près du joueur, `LKB.spawn` qui annonce `(wanted …)` ; ⚠ règle plus stricte (intérieurs meublés écartés), voisinage 3 × 3 exclu en entier au lieu du contact exact

- [x] **LK02-T12** — Apparence stable si la liste des tenues change (N2)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK02-T03
  - Fichiers : `LK_Appearance.lua`, `LK_Identity.lua`, `LK_Store.lua`
  - Faire : l'identifiant de tenue persistante dépend de l'index de la tenue dans la liste chargée ; un mod de vêtements ajouté ou retiré peut rhabiller un PNJ autrement à sa ré-incarnation. Enregistrer une description indépendante de l'index (nom de tenue et variante, ou liste des vêtements et teintes) ou détecter le changement.
  - Accepté si : un PNJ ré-incarné après ajout d'un mod de tenues garde les mêmes vêtements.
  - Tests : banc ; essai solo avec un mod de vêtements activé puis retiré.
  - Preuve : `LK_Appearance.lua` : relevé des visuels portés à la première incarnation (`describe`, champ optionnel `npc.clothes`, schéma inchangé) et rejeu à l'identique aux incarnations suivantes avant `DoZombieInventory`, objet inconnu sauté avec `WARN` ; PNJ existants relevés à la liaison sans changer d'apparence ; `tests/test_lk_appearance.py` (`ClothesTests` 7 : décalage d'index simulé, témoin sans relevé), `test_kahlua.py`, `tests/run_all.py` 19/19 le 2026-10-09 ; serveur dédié de test 6/6 ; fiche `docs/annexes/conception/apparence.md` ; LK02-T09 : commit `7ff0d12` ; **en jeu solo le 2026-10-09** : `lk.appearance` 5/5 dont « même vêtements quand la variante donnerait d'autres vêtements » (changement simulé) ; essai réel avec un mod de vêtements ajouté reste à faire ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : lk.appearance en deux passes après le correctif `1b302b9` : passe 1 sans les mods Frockin (`20261013-211444-solo.txt`), passe 2 avec 6 mods Frockin ajoutés : npc lk-261 corps identique, 9 vêtements, 0 différence, 0 laissé de côté (`20261013-211727-solo.txt`) ; le premier échec venait de la comparaison dans l'ordre (Frockin réordonne les emplacements du corps)
  - Reste : en jeu solo : `LKB.spawn` puis rechargement avec un mod de vêtements ajouté, `LKB.embody` identique ; ⚠ `ItemVisual.new` depuis Lua confirmé statiquement seulement ; premier habillage dépendant des mods chargés à ce moment

- [x] **LK02-T13** — Abonnés `OnEquipPrimary` des autres mods (N6)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK02-T06
  - Fichiers : `LK_Equipment.lua` ; relevé dans `docs/annexes/conception/equipement.md`
  - Faire : relever, dans les mods actifs de l'utilisateur (Workshop en lecture seule), les abonnés `OnEquipPrimary`/`OnEquipSecondary` qui supposent un joueur ; les protéger (garde générique ou liste) sans modifier ces mods.
  - Accepté si : aucune erreur d'un autre mod quand un PNJ prend une arme en main, avec la liste de mods de l'utilisateur.
  - Tests : banc ; essai solo avec la liste de mods habituelle.
  - Preuve : relevé statique des abonnés `OnEquipPrimary`/`OnEquipSecondary`/`OnClothingUpdated` dans le vanilla et les 26 mods de la liste de l'utilisateur (tableau dans `docs/annexes/conception/equipement.md`) : seul l'abonné vanilla de la pêche suppose un joueur (déjà enveloppé) ; les abonnés trouvés dans un mod d'armes ne touchent que l'arme ; aucune protection supplémentaire nécessaire, garde générique impossible (abonnés non exposés) ; `tests/test_lk_equipment.py` 19/19 (doublures des abonnés relevés, abonné fautif inventé isolé), `tests/run_all.py` 19/19 le 2026-10-09 ; LK02-T12 : commit `812e477` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo lk.equipment 3/3 (arme d'un mod d'armes, aucune erreur Lua) (`20261013-202155-solo.txt`)
  - Reste : en jeu solo avec la liste de mods habituelle : arme vanilla et arme d'un mod d'armes en main sans nouvelle erreur ; refaire le relevé si la liste de mods change

- [x] **LK02-T14** — PNJ qui apparaît déjà debout
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK02-T10, LK04-T12
  - Fichiers : `LK_Bodies.lua`, AnimSets (`tools/anim_table.json`)
  - Faire : constaté en jeu le 2026-10-11 : chaque PNJ qui apparaît est allongé puis se relève (voie B : cadavre réanimé, état de relevé du joueur réanimé) ; le faire apparaître debout sans changer de voie : remettre le corps debout dès la réanimation (état Java vérifié) ou nœud de relevé quasi instantané réservé à `LKActor` ; sûr en MP (aucun glissement ni corps figé chez les autres clients).
  - Accepté si : un PNJ créé près du joueur est debout dès qu'il apparaît, chez tous les clients
  - Tests : banc ; essai solo
  - Preuve : cause : `IsoDeadBody.reanimate` met le corps au sol et lance l'état `onground` (`IsoDeadBody.java:1875-1880, 1930-1937`, `to_onground.xml`), qui ne sort que par le relevé à la fin d'un minuteur de 1 à 3 s (`ZombieOnGroundState.java:37-67`) ; les `actiongroups` d'un mod ne sont jamais chargés (`ActionGroup.java:32-47`) ; en MP le client force l'état au sol d'un cadavre réanimé (`NetworkZombieSimulator.java:226-233`) ; voie retenue : `LK_Stand.lua` remet l'état Java debout dans l'appel de création (`setOnFloor(false)`, état d'action `idle` imposé par `playbackSetCurrentStateSnapshot` relevé sur un zombie neuf, `changeState(ZombieIdleState)`, fondu `setAlpha(0)`) ; côté client, copie redressée à son adoption (5 s au plus) ; corps renversé plus tard jamais touché ; échec → WARN unique et relevé vanilla ; `test_lk_stand.py` 12, `test_lk_bodies.py` 55 ; suite `lk.anims` (+2 tests) ; luacheck des fichiers 0 ; `docs/annexes/conception/corps-et-animations.md` ; base `zombies-as-npc-bodies.md`, `mod-loading.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : lk.anims 3 pass, 1 SKIP marche faute de place (`20261013-111126-solo.txt` : PNJ debout dès sa création, relevé vanilla ensuite)
  - Reste : en jeu solo (jeu redémarré) : LKB.spawn(2, 0) → PNJ debout en fondu ; RST.run({suite="lk.anims",tags="world"}) ; WARN « vanilla get-up instead » si Kahlua refuse ActionStateSnapshot ; MP : copie couchée le temps d’un paquet possible ; écran partagé non traité

- [x] **LK02-T15** — Apparence humaine des PNJ non répliquée aux clients MP
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK02-T03, E01-T16
  - Fichiers : `LK_Appearance.lua` et voisins (à établir)
  - Faire : constaté par le client 2 le 2026-10-15 (`tools/autoclient/runs/20261015-010646-mp-e8fba085accd`, relances `…011037…`, `…011504…`, `…012242…`) : sur les deux clients, la copie d'un corps de PNJ retrouvée par son identifiant de tenue persistante ou réseau a une peau de zombie (`F_ZedBody03_level1`…), aucun vêtement, et diffère d'un client à l'autre, alors que le serveur a une peau humaine et des vêtements. Établir la cause (descripteur partagé `SharedDescriptors`/`useDescriptor` non appliqué ? étape `lk.look` qui lit la mauvaise copie ?) par le Java 42.21 et les journaux, puis corriger.
  - Accepté si : étape `lk.look` verte sur les deux clients dans la campagne MP (même peau, mêmes vêtements que le serveur).
  - Tests : banc ; suite `lk.appearance` en campagne MP.
  - Preuve : cause : défaut de l'étape de contrôle, pas du mod : une copie cliente de zombie n'est habillée qu'à son premier affichage (`ModelManager.Add`, descripteur partagé appliqué alors) ; `lk.look` habille la copie non affichée comme le moteur (même indice de tenue serveur et client, « same look true ») ; MP `lk.appearance` vert deux fois avec le client 2 (`tools/autoclient/runs/20261015-022944-mp-7a478eb4107e`, `tools/autoclient/runs/20261015-023625-mp-7716162db52f` : serveur 10 PASS 0 FAIL, client 2 OK 8 étapes) ; solo `tools/autoclient/runs/20261015-023854-3ea991ed08a6` ; banc `test_rst_steps` ; base `zombies-as-npc-bodies.md` ; commit `e85f964`
  - Reste : rendu réellement affiché non observé à l'œil (abandonné, règle du 2026-10-14 : jugement visuel)
