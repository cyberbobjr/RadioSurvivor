# LK08 — Socle des groupes

**Objectif.** Registre serveur des groupes : type, histoire, chef, membres, foyer, besoins, moral ; création de 3 à 5 groupes ; choix et aménagement des foyers.

**Dépend de.** LK01-T02 (peut avancer en parallèle du jalon pour la partie hors jeu).

**Sources.** Décisions LK00 ; base `world-placement.md` (point lointain sans charger, métagrille, bâtiments), `knox-geography.md`.

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-10 — **LK08-T03** : pillards sans forêt connue (biomemap non exposée, zones de forêt connues seulement pour les cellules approchées) : **garder le repli sur un bâtiment isolé** ; pas de table de forêts précalculée.
- 2026-10-14 — **LK08-T04** : lampe sur pile (environ 2,8 jours), sacs de couchage, caisse vide pour réserve, quantités (2 fenêtres à 2 planches, 4 couchages, 3 tentes) (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK08-T06** : kits et quantités ; kit des colons par défaut (confirmé par défaut, valeurs techniques) ; conteneurs du bâtiment = stock du groupe, un vol rapporté au plus une fois par heure par joueur (confirmé par l'utilisateur).
- 2026-10-14 — **LK08-T07** : 1 objet = la journée d'un membre, visée 3 jours, seuils 2 et 1 jour, marge 0,5 jour, visées soins 1 / munitions 0,5 / matériaux 1 par membre, critique sous 25 % ; eau dans `supply` ; avec les kits actuels les colons démarrent en rationnement strict (0,7 jour d'eau) (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **LK08-T01** — Registre des groupes et persistance
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK01-T02
  - Fichiers : `LK_Groups.lua` (server), état privé
  - Faire : groupes, membres, rôles, foyer, besoins (nourriture, soins, munitions), moral, journal ; persistance serveur privée avec schéma versionné.
  - Idées : I6.6 (succession du chef) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : redémarrage sans perte ; schéma vérifié au chargement.
  - Tests : banc.
  - Preuve : `LK_Groups.lua` : registre serveur (schéma 1 : groupes `grp-<n>` et membres `m-<k>` à identifiants jamais réutilisés, type, nom, histoire, chef, rôles en liste fermée `LK_Config.GROUP_ROLES`, lien facultatif `npc` vers le registre des corps, foyer, besoins `food`/`medical`/`ammo` et moral 0..100, journal borné à 32 entrées), API (création, membres, mort, succession I6.6 par rôle puis ancienneté, besoins, foyer, journal ; lectures en copies) ; persistance privée à deux emplacements extraite de `LK_Store` (`readSlotFile`, `writeSlotFile`), sauvegarde à chaque changement ; contrôle au chargement (groupe invalide écarté et journalisé, schéma inconnu bloqué sans écraser) ; `tests/test_lk_groups.py` 16/16, VM Kahlua 21/21 (`test_groups_logic_in_kahlua`) ; `tests/run_all.py` 28/28 le 2026-10-10, luacheck 17/0, `check_case.py` PASS ; fiche `docs/conception/groupes.md` ; E11-T02 : commit `cd21e36`
  - Reste : à voir au premier serveur de test : ligne `groups: new world, empty group registry` et fichier `groups-…` écrit par le jeu ; retrait d’un type de `GROUP_TYPES` = groupes invalides (migration à prévoir avec LK08-T02) ; lien `npc` non recoupé avec le registre des corps

- [x] **LK08-T02** — Profils et types de groupes en données
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK08-T01
  - Fichiers : `media/lua/shared/LivingKnox/Data/*.lua` ou fichiers texte
  - Faire : types (colons, pillards, neutres), profils de membres (apparence, armes, rôle), réglages par type ; format propre au mod.
  - Idées : I1.2 (rôle = comportements permis), I6.9 (éclaireur, casseur), I8.1 (rôles et traits rares) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : un nouveau type s'ajoute sans code.
  - Tests : banc.
  - Preuve : `LK_GroupTypes.lua` : registre validé (format 1, champs inconnus refusés, rôles, tailles, réglages, profils de membres avec apparence comprise par `LK_Appearance`, armes `Base` vérifiées, rareté `weight`/`max`, traits par `chance`, comportements permis par rôle en noms seulement) ; définition invalide ou doublon refusée et journalisée sans faire tomber les autres ; types livrés en fichiers de données qui s'enregistrent (`Data/LK_Type_settlers.lua`, `raiders`, `neutrals`), un nouveau type = un seul fichier, même depuis un autre mod (ordre de chargement confirmé statiquement, `LuaManager.java:1142-1218`) ; `LK_Groups` valide le type contre le registre ; rôle `breaker` ajouté en fin de `GROUP_ROLES` ; noms traduits côté client (`IGUI_LK_GroupType_*`) ; `tests/test_lk_group_types.py` 14/14, `test_lk_groups.py` 16/16, VM Kahlua 22/22 ; `tests/run_all.py` 31/31 le 2026-10-10, luacheck 17/0, `check_case.py` PASS ; `docs/conception/groupes.md` ; base `mod-loading.md` ; E12-T01 : commit `6df2e2a` ; **en jeu solo le 2026-10-10** (partie `rstest-1010`, retour de l’utilisateur) : trois lignes `group type … registered`, aucun refus
  - Reste : profils et réglages pas encore consommés (tirage des membres : LK08-T05) ; type retiré = groupes écartés au chargement, sans migration ; au premier démarrage : trois lignes `group type … registered` et aucune `refused` dans `console.txt`

- [x] **LK08-T03** — Choix des sites sans charger la zone
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK08-T01
  - Fichiers : `LK_Sites.lua`
  - Faire : bâtiment habitable pour colons et neutres, clairière forestière pour pillards ; loin des bases des joueurs et des autres groupes ; terre ferme.
  - Idées : I8.2 (pas de bâtiment visité récemment par un joueur) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : aucun chargement de chunk pendant le choix ; sites variés sur plusieurs tirages.
  - Tests : suite en jeu `lk.sites`.
  - Preuve : `LK_Sites.lua` : `Sites.pick(type, opts)` sans lecture de case ni écriture ; style de foyer lu dans le type (`building`/`forest`) ; bâtiment habitable par `RS_Rescue.check` (types admis par type de groupe, aucune pièce explorée pour I8.2), clairière de 17 × 17 cases dans les zones de forêt déjà inscrites de la métagrille (`getZonesIntersecting`, sans `Water`, à 40 cases d'une route `Nav` et 60 d'un bâtiment) ; à 600 cases des bases des joueurs et 400 des autres foyers ; 300 tirages au plus, graine Park-Miller ; repli sur bâtiment isolé si aucune forêt connue (`fallback`, ligne `WARN`, désactivable) ; `tests/test_lk_sites.py` 24/24 ; suite en jeu `lk.sites` (6 tests, sondes de non-chargement) ; `tests/run_all.py` 33/33 le 2026-10-10, luacheck 17/0 et 0, `check_case.py` PASS ; `docs/conception/sites.md` ; base `world-placement.md` (forêt d'une case non chargée, pièce explorée) ; LK09-T01 : commit `757d7db` ; **en jeu solo le 2026-10-10** (`rstest-1010`) : `RST.server("lk.sites")` 6/6, fichier `20261010-165227-server.txt` (après LK08-T08)
  - Reste : I8.2 = « déjà vu », jamais « récemment » ; forêt connue seulement pour les cellules approchées (repli validé par l’utilisateur)

- [ ] **LK08-T04** — Aménagement des foyers
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK08-T03
  - Fichiers : `LK_Homes.lua`
  - Faire : au premier chargement : barricades, lumière, couchages, réserves (bâtiment) ou tentes et feu (camp), avec objets vanilla ; une seule fois, synchronisé.
  - Idées : I8.3 (foyer lisible de l'extérieur) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : aucun doublon après redémarrage ; deux clients voient le même foyer.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_homes.py` du 2026-10-12 (18 tests OK : plans bâtiment et camp, pose unique, marque relue après redémarrage, marque perdue rétablie par les objets marqués, suite `lk.homes` exécutée au banc) ; run_all 52/52 ; luacheck 16/0 ; conception `docs/conception/foyers.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.homes", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-181143-solo.txt`) (après correctifs `feb3aff` et `e322fdc` : sols et tapis ramassables, feu de camp marqué) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.homes 2/2 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; phases réelles du 2026-10-15 6 h 07 (reconnexion des clients puis `quit` et relance du serveur sur la même partie, `tools/autoclient/runs/20261015-060712-mp-1a0abb0c888e`) : lk.homes.after-restart « same furnishing after the restart, nothing placed twice » PASS (marque des barricades portée par la fenêtre, `1bc001a`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.homes 2/2 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : lk.homes.before et lk.homes.after-restart PASS (aucun doublon après redémarrage) (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093457-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`)
  - Reste : même foyer vu par les deux clients : aucune étape client dans lk.homes ; rideaux (I8.3) non faits

- [x] **LK08-T05** — Population : 3 à 5 groupes et réglages
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK08-T03
  - Fichiers : `media/sandbox-options.txt`, `LK_Groups.lua`
  - Faire : nombre cible (défaut 4), mélange des types, tailles 4 à 8, délai de relève 2 à 5 jours ; création initiale au démarrage du monde.
  - Accepté si : options respectées ; aucune apparition aléatoire hors de ce cadre.
  - Tests : banc.
  - Preuve : `LK_Population.lua` (autorité seulement) : population initiale une seule fois par monde (registre jamais peuplé : `populated ~= true` et `nextId == 1`), à `OnServerStarted` / `OnGameStart` ou au premier `EveryHours` ; type tiré selon les poids, taille dans l'intersection des options et du type, membres (rôle, profil dans sa limite `max`, sexe, traits), chef par `pickSuccessor`, histoire `Stories.compose` (champ `story` = `summary.en`, `storySeed` pour recomposer ; secrets jamais stockés), foyer par `Sites.pick` sans doublon (échec = groupe sans foyer et `WARN`) ; préparation complète puis une seule sauvegarde ; graine dérivée de la partie ; 8 options sandbox `integer` (`GroupCount` 4 [3..5], poids `WeightSettlers`/`Raiders`/`Neutrals` 40/35/25, `GroupSizeMin/Max` 4/8, `ReliefDaysMin/Max` 2/5 stockés pour LK09) avec traductions EN/FR, lecture robuste (défaut + avertissement) ; `tests/test_lk_population.py` 30/30 ; `tests/run_all.py` 35/35 le 2026-10-10, luacheck 17/0 et 0, `check_case.py` PASS ; `docs/conception/groupes.md` (Population) ; LK12-T01 : commit `f3a6d3d` ; **en jeu solo le 2026-10-10** (partie `rstest-1010`, retour de l’utilisateur) : 4 groupes créés au premier démarrage (`population: 4 group(s) created`), relance sans nouvelle création (`group registry already populated`) ; 3 pillards sans foyer : LK08-T08
  - Reste : en jeu : nouvelle partie solo puis serveur dédié (lignes `population: …`, fichier `groups-…` avec `populated`, aucune création au relancement) ; non exécuté dans la VM Kahlua ; serveur dédié : seuls les refuges sont évités à `OnServerStarted` ; types d’autres mods jamais tirés (pas d’option de poids) ; ⚠ variété des origines à vérifier (3 groupes sur 4 avec la même origine dans un échantillon)

- [x] **LK08-T06** — Stock réel dans les conteneurs du foyer
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK08-T04
  - Fichiers : `LK_Stock.lua` (server)
  - Faire : les réserves du groupe sont de vrais objets rangés dans les conteneurs du foyer (garde-manger, eau, soins, munitions, matériaux) ; le serveur tient un inventaire de référence par catégorie, relu quand la zone est chargée ; un pillage par un joueur est constaté et fait réagir le groupe (`LK11-T03`).
  - Idées : I3.7 (périssables au froid), I5.1 (index par conteneur), I5.2 (stock surveillé) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : inventaire de référence égal au contenu réel après chargement, retrait par un joueur détecté ; aucune duplication.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_stock.py` du 2026-10-12 (22 tests OK : catégories par données de script, remplissage unique, référence rétablie sans duplication, relecture = contenu réel, vol retrouvé chez un joueur rapporté à `LK_Hostility`) ; run_all 54/54 ; luacheck 16/0 ; conception `docs/conception/stock.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.stock", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-174949-solo.txt`) (après `feb3aff`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.stock PASS (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.stock 1/1 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : second client voit la caisse, vol par transfert attribué. Niveau du foyer seul ; objet posé au sol ou donné = perte sans coupable ; prélèvements du groupe à faire passer par `LK_Stock` (LK05-T07, LK11-T06, LK11-T08) ; I3.7 non faite.

- [x] **LK08-T07** — Gestion du stock : seuils, rationnement, besoins du groupe
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK08-T06
  - Fichiers : `LK_Stock.lua`
  - Faire : seuils par catégorie selon la taille du groupe, jours d'autonomie calculés, rationnement quand le stock baisse, besoins du groupe dérivés du stock et transmis au cadre de décision (expéditions, fortification, missions RadioSurvivor).
  - Accepté si : besoins reproductibles pour un stock donné ; rationnement visible dans le journal.
  - Tests : banc.
  - Preuve : banc `tests/test_lk_stock.py` du 2026-10-12 (31 tests OK : seuils par membre vivant, jours d'autonomie, rationnement à 4 niveaux avec marge, besoins ordonnés reproductibles, entrée au journal) ; `tests/test_lk_decisions.py` 20 OK (objectif `supply` lu sur le stock réel) ; luacheck 16/0 ; conception `docs/conception/stock.md`
  - Reste : aucun consommateur ne lit encore `Stock.portion` (LK05-T07, LK09-T06) ni `Stock.needs` (LK05-T05, LK14, missions) ; référence relue seulement zone chargée.

- [x] **LK08-T08** — Repli des pillards trop strict : groupes sans foyer
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK08-T03
  - Fichiers : `LK_Sites.lua`, `tests/test_lk_sites.py`, suite `lk.sites`
  - Faire : constaté en jeu le 2026-10-10 (`rstest-1010`, `console.txt`) : sans forêt connue, le repli « bâtiment isolé habitable sans voisin à 100 cases » échoue après 300 tirages (refus `not habitable` ≈ 130, `not isolated` ≈ 135) ; 3 groupes de pillards sur 3 sans foyer, suite `lk.sites` 3/6. Assouplir le repli de façon bornée et déterministe (isolement dégressif, bâtiments non habitables admis pour les pillards) sans charger la zone.
  - Accepté si : sur la carte vanilla, un pillard reçoit un foyer pour toutes les graines de la suite ; `lk.sites` 6/6 en jeu.
  - Tests : `test_lk_sites.py` ; suite `lk.sites`.
  - Preuve : `LK_Sites.lua` : repli sans forêt connue sur tout bâtiment habitable ou, pour les pillards (`LAIR_TYPES`), un repaire en liste fermée (`LAIR_KINDS` : entrepôt, grange, garage, station-service, atelier ; pièce au sol d'au moins 25 cases) ; isolement mesuré (≤ 100 cases) avec paliers dégressifs 100/60/30 par tiers des 300 tirages, meilleur candidat rendu au besoin, échec seulement si aucune distance ne passe ; colons et neutres inchangés ; `RS_Rescue.check` accepte `opts.rules` (défaut inchangé) ; `tests/test_lk_sites.py` 40/40 (carte de test dense d'après le constat du 2026-10-10 : un foyer pour toutes les graines), `test_rescue.py` 21/21 ; suite `lk.sites` adaptée ; `tests/run_all.py` 35/35 le 2026-10-10, luacheck 17/0 et 0, `check_case.py` PASS ; `docs/conception/sites.md`, `docs/rescue.md` ; LK10-T01 : commit `a1f4cde` ; **en jeu solo le 2026-10-10** (`rstest-1010`) : `RST.server("lk.sites")` 6/6, fichier `20261010-165227-server.txt` ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : 4 groupes avec foyer dont les pillards (maison isolée, palier 100)
  - Reste : paliers, surface et repaires à recalibrer ; vérifier sur un monde neuf qu’aucun pillard n’est `home none`
