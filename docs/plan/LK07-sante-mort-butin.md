# LK07 — Santé, mort et butin

**Objectif.** Santé des PNJ cohérente en MP, blessures, soins, mort unique et butin réel.

**Dépend de.** LK06-T02.

**Sources.** Base `multiplayer.md` (seul le propriétaire applique les dégâts d'un zombie-corps) ; `clothing-and-character-state.md`.

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-11 — **LK07-T02** : un coup qui dépasse le maximum honnête de l'arme est **laissé passer** (le serveur croit la valeur du client ; anti-triche peu prioritaire sur un serveur entre amis) ; seuls restent les contrôles de portée, d'étage, de cadence et d'attaquant vivant. Changement de code : `LK07-T06`.
- 2026-10-14 — **LK07-T03** : arrêt naturel (moitié toutes les 3 h) ; soin = 0,03 × BandagePower × santé de naissance (× 1,5 médecin) ; point d'appel dans `Decisions.apply` sans comportement `heal` (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK07-T04** : mort par saignement sans tueur ; étiquette gardée sur le cadavre ; cadavre traîné jamais touché, cadavre relevé remis à terre ; corps mis de côté jamais tué, saignement suspendu (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK07-T05** : arme gardée dans le cadavre ; munitions de départ (fraction de `needs.ammo`, 2 chargeurs ou 12 cartouches au niveau 100) ; liste `LOOT.POCKETS` (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK07-T08** : munitions converties une pour une (nombre gardé, calibre changé) (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **LK07-T01** — Investigation : dégâts subis par un corps et synchronisation de la santé
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/conception/sante.md`
  - Faire : comment un coup de joueur sur un corps de PNJ est appliqué, où vit la santé de référence, comment la transmettre.
  - Accepté si : faits prouvés ou marqués à mesurer.
  - Tests : —
  - Preuve : `docs/conception/sante.md` (Java 42.21.0 et Lua vanilla, chaque fait avec `fichier:ligne` ou « à mesurer ») : dégâts calculés par le client attaquant (`PlayerHitZombie`, plafond anti-triche 100), appliqués par le serveur et le propriétaire (`IsoZombie.java:3449`, `HitCharacter.java:37-50`), santé de référence vanilla = propriétaire (`NetworkZombiePacker.java:97-99`), santé remontée au changement de propriétaire, santé > 32,767 qui tue en MP (`short` × 1000, `NetworkZombieAI.java:180`, vérifié), seul `setInvulnerable(true)` bloque toutes les sources (à poser sur chaque machine), événements déclenchés sur plusieurs machines, véhicule, feu, explosion et chute sans événement Lua, cadavre faux mort qui se relève, inventaire refait avant `OnZombieDead` ; choix proposés pour LK07-T02 (non tranchés) ; base : `multiplayer.md`, `combat-and-xp.md` (dont correction `Hook.Attack`), `zombies-as-npc-bodies.md` ; E07-T03 : commit `c221262`
  - Reste : points « à mesurer » listés dans le document (solo : réaction d’un corps invulnérable, vêtements ; MP : santé au changement de propriétaire, valeur reçue par `OnWeaponHitCharacter` côté serveur, chocs de véhicule et explosions)

- [x] **LK07-T02** — Santé de référence sur le serveur
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK07-T01
  - Fichiers : `LK_Health.lua`
  - Faire : points de vie et blessures du PNJ tenus par le serveur ; coups des joueurs contrôlés puis appliqués ; corps mis à jour chez le propriétaire.
  - Idées : I7.2 (endurance, halètement) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : même santé vue par deux clients ; aucune remontée sans soin.
  - Tests : banc ; suite `lk.health`.
  - Preuve : `LK_Health.lua` : santé de référence `npc.hp` (et `wounds`) dans le registre, santé vanilla inerte par `setInvulnerable(true)` sur chaque copie (serveur et clients reconnus), seule hausse par `noteHeal` ; coups contrôlés à `OnWeaponHitCharacter` (attaquant vivant, portée de l'arme, même niveau, cadence, mêlée hors véhicule) et ramenés au plafond honnête de l'arme (multiplicateurs vanilla, ≤ 100) ; explosion appliquée (plafond 20) ; feu et chute neutralisés ; mort décidée une seule fois à 0 puis chemin vanilla (`die()` serveur, `Kill` en solo) ; retransmission `npcHealth` versionnée aux seuls destinataires des consignes, lecture client `HealthView.get` ; `LK_Bodies` (retrait d'un corps invulnérable), `LK_Materialize` (`setBirth`) ; `tests/test_lk_health.py` 15/15 (suites `lk.health` et `rs.killer` sur doublures) ; `tests/run_all.py` 44/44 le 2026-10-11, luacheck 17/0 et 0 ; `docs/conception/sante.md` ; base `combat-and-xp.md` ; LK11-T04 : commit précédent ; **en jeu solo le 2026-10-11** (partie `rstest-1011`, jeu en anglais) : santé de référence en baisse à chaque coup sans remontée, mort unique décidée par le serveur (cause, tueur, arme), cadavre resté au sol, membre marqué mort ; `lk.health` 2/2 (`20261011-134737-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.health 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; dernière campagne MP complète du 2026-10-15 5 h 24 (client 2 actif, règle « les tests font foi ») : lk.health 3/3, étape lk.health.view verte chez les clients 1 et 2 (même santé que l'autorité) (`tools/autoclient/runs/20261015-052439-mp-4cf10c2eed18/server/20261015-032638-server.txt`)
  - Reste : plafond à retirer (LK07-T06) ; véhicule non couvert

- [x] **LK07-T03** — Saignement et soins
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK07-T02
  - Fichiers : `LK_Health.lua`
  - Faire : saignement après blessure, soin par un membre (consomme une ressource du groupe, LK08), mort par perte de sang possible.
  - Idées : I6.10, I7.1 (bandage pris au stock, médecin qui soigne les autres) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : ressource décomptée côté serveur.
  - Tests : banc.
  - Preuve : banc `tests/test_lk_care.py` du 2026-10-12 (15 tests OK : saignement après blessure sauvegardé et arrêt naturel, mort par perte de sang par `Health.kill`, médecin puis blessé seul, objet de pansement réel retiré une seule fois par `Stock.takeItem` sans vol, effet unique même interrompu, pénurie `medical`, `Care.afterAttack` branché ; suite `lk.care` sur doublures) ; run_all 60/60 ; luacheck 16/0 ; conception `sante.md` (Saignement et soins) ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.care", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-175415-solo.txt`)
  - Reste : Solo validé le 2026-10-12. essai solo `RST.run({ suite = "lk.care", tags = "world" })` dans une maison avec un meuble à conteneur (médecin qui fouille puis s'agenouille près du blessé). Toute blessure saigne sans partie du corps ; saignement invisible et non envoyé aux clients ; suspendu hors écran ; mort par saignement de cause « other » ; infection et transformation (I6.10) non faites.

- [x] **LK07-T04** — Mort unique et cadavre
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK07-T02
  - Fichiers : `LK_Health.lua`, `LK_Bodies.lua`
  - Faire : mort décidée par le serveur, une seule fois ; cadavre avec vêtements ; PNJ retiré du groupe ; événement publié (LK12).
  - Accepté si : aucune double mort, aucun PNJ qui redevient un zombie par erreur.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_death.py` du 2026-10-12 (11 tests OK : `Health.kill` chemin unique pour coup, zombie, saignement et API, second appel refusé, corps hors du monde refusé, causes `zombie`/`bleeding`, cadavre unique avec vêtements et inventaire, cadavre traîné jamais retiré, cadavre relevé remis à terre, fait `npcDied`) ; `lk_bodies` 55, `lk_health` 16, `lk_materialize` 16 OK ; luacheck 16/0 ; conception `sante.md` (Mort unique et cadavre) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.death 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : lk.death 3/3 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : même cadavre chez A et B, cadavre fouillé, traîné et lâché (même contenu, une seule ligne `died`). Prise et faux mort de pourriture non reproduits en jeu ; cadavre relevé actif quelques secondes avant le balayage ; arme en main posée au sol par `die()` sur un serveur (LK07-T05) ; aucune API d'événements (fait `npcDied` en attendant LK12-T02).

- [x] **LK07-T05** — Butin réel du cadavre
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK07-T04
  - Fichiers : `LK_Loot.lua`
  - Faire : inventaire construit par le serveur à partir de l'équipement réel et de l'état du groupe (munitions restantes, objets de mission).
  - Idées : I7.3 (poches qui racontent le métier, avec les vrais objets) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : butin identique pour tous les joueurs ; pas de duplication.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_loot.py` du 2026-10-12 (14 tests OK : inventaire construit une seule fois par corps (marque `LKLoot` sauvegardée), munitions réelles selon le niveau du groupe, poches selon le rôle, arme gardée dans le cadavre accrochée et rangée en solo comme en MP, cartouches du chargeur rendues en objets, aucune duplication) ; run_all 64/64 ; luacheck 16/0 ; conception `sante.md` (Butin réel du cadavre) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.loot 2 PASS + 1 SKIP (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.loot 3/3 avec les étapes world.keys (même cadavre, même contenu) et corpse.drag du client 2 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`) ; lk.death 4/4 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`)
  - Reste : Limites : munitions non rendues au niveau abstrait au retrait d'un corps ; traits (I7.3) non repris ; PNJ hors groupe sans poches ; objets de mission : point d'appel `Loot.missionItems` ; campagne solo du 2026-10-15 : lk.loot 3 FAIL « npc spawn refused: square … is not loaded » (régression du harnais : le test n'a pas tourné) (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`)

- [x] **LK07-T06** — Coups au-delà du plafond de l'arme laissés passer
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK07-T02
  - Fichiers : `LK_Health.lua`, `tests/test_lk_health.py`
  - Faire : décision du 2026-10-11 : ne plus ramener un coup au plafond de l'arme ; la valeur du client est appliquée telle quelle (bornée seulement par la santé restante et le format réseau) ; garder portée, étage, cadence et attaquant vivant.
  - Accepté si : un coup de grâce au couteau tue d'un coup ; un coup hors portée reste refusé.
  - Tests : banc ; suite `lk.health`.
  - Preuve : `LK_Health.lua` : plafond de l'arme supprimé (`Health.cap` et réglages associés, plafond des explosions compris) ; valeur du client appliquée, bornée par la santé restante (blessure notée à cette valeur) ; refusées : non numérique, NaN, infinie ou ≥ 10⁹, négative ; portée, étage, cadence, attaquant vivant, mêlée depuis un véhicule, explosif en inventaire inchangés ; `test_lk_health.py` 16 (coup de grâce au couteau de 900 : refusé hors de portée, tue d'un coup à portée ; valeurs invalides) ; suite `lk.health` : coup mortel en un seul coup ; `run_all.py` 44/44 le 2026-10-11, luacheck 17/0 et 0 ; `docs/conception/sante.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo lk.health « finishing blow with a knife on an npc on the floor: one hit kills » PASS (`20261013-202155-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : lk.health 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`)
  - Reste : en jeu solo : RST.run({suite="lk.health"}) (coup mortel en 1 coup) ; coup de grâce au couteau sur un PNJ à terre ; MP : AntiCheatHitDamage vanilla peut refuser un coup > 100 en amont, à mesurer à la séance finale ; la campagne MP automatique passe (2026-10-14) ; restent pour la séance finale les contrôles à deux joueurs actifs et à la main ci-dessus

- [x] **LK07-T07** — Butin de mort absent du cadavre en jeu
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK07-T05
  - Fichiers : `LK_Loot.lua`, `LK_Health.lua`, `LK_Bodies.lua`
  - Faire : constaté en jeu le 2026-10-12 (`RST.run({ suite = "lk.loot", tags = "world" })`, test « death keeps the weapon in the corpse ») : à la mort décidée par l'autorité (`reference health 0, death decided by the authority (nobody, no weapon)`), le journal annonce `death loot: weapon Base.Pistol (created), 8 round(s) of the weapon turned into items, 15 item(s) in the corpse`, mais le cadavre trouvé ne contient que les objets de poche déjà dans l'inventaire (2 pansements) : ni arme, ni chargeur, ni cartouches, rien au sol. Trouver où se perdent les objets ajoutés à la mort (chemin de mort solo, moment de création du cadavre, copie de l'inventaire) et corriger ; le banc doit reproduire le défaut.
  - Accepté si : en jeu solo, le cadavre contient l'arme, les cartouches et les chargeurs annoncés, une seule fois.
  - Tests : banc ; suite en jeu.
  - Preuve : diagnostic du 2026-10-12 : chemin de mort réel `Health.kill` -> `die()` -> `Kill` -> `OnZombieDead` (butin ajouté) -> `becomeCorpse` -> `new IsoDeadBody(this)` qui reprend le même conteneur (`IsoGameCharacter.java:13463-13541`, `IsoZombie.java:4599-4610`, `IsoDeadBody.java:327-332`) : aucune perte dans le moteur ni dans le mod ; cause : mod actif dans la partie (Guns of Marz + SWMG, présents dans la liste des mods de la console) dont l'option de remplacement vanilla, vraie par défaut, pose un `OnCreate` sur armes, chargeurs et munitions vanilla et remplace l'objet dès qu'il est dans un autre conteneur (cadavre), plus un abonné `OnZombieDead` ; suite `lk.loot` : mesure des crochets de création (`getLuaCreate`) et du contenu du cadavre, test de mort en SKIP nommé si un crochet est actif ; banc `tests/test_lk_loot.py` 16 OK (doublure `OnCreate` fidèle au Java, reproduction du remplacement) ; run_all 101/101 ; conception `sante.md` ; base `loot-distributions.md` (objet posé par script qui change de type après coup : chercher un `OnCreate` d'un autre mod) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo lk.loot 3/3 (remplacement de Guns of Marz actif : une seule arme à feu dans le cadavre) (`20261013-202155-solo.txt`)
  - Reste : essai solo : avec l'option de remplacement du mod d'armes active, `RST.run({ suite = "lk.loot", tags = "world" })` : test de mort en SKIP, mesure qui nomme `MarzGuns_OnCreate.VanillaReplace` et objets `MarzGuns.*` dans le cadavre ; option décochée : `OK`, pistolet et 2 chargeurs (23 cartouches). À vérifier : le même mod remplace aussi l'arme vanilla d'un zombie à sa première mise à jour (`OnZombieUpdate`), donc peut-être l'arme d'un PNJ vivant (`LK_Equipment`). Décision de l'utilisateur (2026-10-12) : laisser faire, le butin des PNJ suit le mod d'armes installé comme pour les zombies (vérification du PNJ vivant : LK07-T08)

- [x] **LK07-T08** — Arme d'un PNJ vivant remplacée par un mod d'armes : rien de perdu
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK07-T07
  - Fichiers : `LK_Equipment.lua`, `LK_Ammo.lua`
  - Faire : un mod d'armes actif (constaté avec Guns of Marz le 2026-10-12, option de remplacement vanilla vraie par défaut) remplace l'arme vanilla accrochée d'un zombie à sa première mise à jour (`OnZombieUpdate`) et les armes, chargeurs et munitions vanilla dès qu'ils changent de conteneur. Vérifier qu'un PNJ vivant garde une arme utilisable et des munitions comptées justes (registre `weapon`, état des munitions de LK_Ammo) quand son arme est remplacée ; s'adapter à l'arme remplaçante (relire l'arme réellement portée) sans contourner le mod.
  - Décisions (2026-10-12, utilisateur) : laisser le mod d'armes remplacer le butin des PNJ comme celui des zombies ; seulement garantir qu'un PNJ vivant ne perd ni son arme ni ses munitions.
  - Accepté si : PNJ armé d'une arme vanilla, mod de remplacement actif : il tire avec l'arme remplaçante, munitions cohérentes, aucune arme fantôme au registre.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_weapon_swap.py` du 2026-10-12 (26 tests OK, MP et solo) : arme créée par `LK_Equipment` marquée `LKWeapon` ; arme d'un autre type sans marque à l'emplacement voulu adoptée par `Equipment.adoptForeign` (registre `weapon`, même objet à son emplacement, ancien vidé et envoyé, `equipState` republiée) ; munitions converties par `Ammo.convert` (nombre gardé : chargées jusqu'à la capacité, libres échangées une pour une, chargeurs échangés ou vidés) ; ordre de combat renouvelé avec l'arme portée (`LK_Combat`, `stats.rearmed`) ; adoption avant le butin de mort (`LK_Loot.onDeath`) ; arme inutilisable : arme du registre reposée ; objet marqué d'un ancien type jamais adopté ; aucun code du mod tiers lu par le moteur ; `lk_equipment` 19, `lk_combat` 32, `lk_loot` 16 OK ; suite `lk.weaponswap` ; luacheck 16/0 ; conception `equipement.md` ; base `loot-distributions.md` (objet accroché remplacé par un autre mod : marque ModData) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : lk.weaponswap 1/1 (`20261013-111154-solo.txt`, arme de Guns of Marz adoptée)
  - Reste : essai solo : `RST.run({ suite = "lk.weaponswap", tags = "world" })` (pistolet accroché remplacé par un fusil par la suite : adoption, cartouches gardées, au moins deux tirs au fusil, lignes `[LKW] measure adopted`) ; avec le mod d'armes actif, `lk.ranged` et lignes `replaced by ... by another mod, adopted` ; MP séance finale. Calibre changé à la conversion ; remplacement posé à un autre emplacement non vu ; le mod tiers peut ne rien remplacer selon le moment de la pose.

- [x] **LK07-T09** — Cadavre d'un PNJ absent chez les clients MP
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK07-T04, E01-T16
  - Fichiers : `LK_Death.lua` et voisins (à établir)
  - Faire : constaté par le client 2 le 2026-10-15 (`tools/autoclient/runs/20261015-010646-mp-e8fba085accd` et relances) : le serveur voit le cadavre marqué d'un PNJ tué (vêtements, contenu), les deux clients ne voient aucun cadavre à 10 cases 20 s après la mort. Établir la cause (cadavre jamais envoyé : `DeadZombiePacket`/`sendCorpse`, mort d'un joueur réanimé simulé par le serveur, base `zombies-as-npc-bodies.md`) et corriger, ou corriger l'étape `world.keys` si c'est elle qui lit mal.
  - Accepté si : étape `world.keys` verte sur les deux clients pour `lk.death` et `lk.loot` (même cadavre, mêmes vêtements, même contenu).
  - Tests : banc ; suites `lk.death`, `lk.loot` en campagne MP.
  - Preuve : causes : (1) corps tué avant que les clients aient sa copie (`DeadZombiePacket` ignoré sans copie : artefact du test, étape `lk.present` qui attend les copies) ; (2) défaut du mod : `IsoDeadBody:reanimate()` retire le cadavre côté serveur sans paquet, et `Bodies.layDown` remettait aussitôt le zombie relevé à terre : cadavre fantôme chez les clients, qui bloquait les cadavres suivants de la case (`isNextServerSquareIndex`) ; correctif : sur un serveur MP, remise à terre après `Bodies.RISEN_DELAY_MS` = 2000 ; MP `lk.death`, `lk.loot` verts deux fois (`world.keys` #3/#6/#8 PASS chez les deux clients, `tools/autoclient/runs/20261015-023625-mp-7716162db52f`) ; solo inchangé (`tools/autoclient/runs/20261015-023854-3ea991ed08a6`) ; banc `test_lk_death` ; base `zombies-as-npc-bodies.md` ; commit `e85f964`
  - Reste : PNJ tué alors qu'un client n'a pas sa copie (retirée « stale » après 5 s) : pas de cadavre chez ce client (LK07-T10)

- [x] **LK07-T10** — Cadavre d'un PNJ tué loin d'un client sans copie
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK07-T09
  - Fichiers : `LK_Death.lua`, `LK_Bodies.lua`
  - Faire : relevé le 2026-10-15 (LK07-T09) : un PNJ tué alors qu'un client n'a pas sa copie (copie retirée « stale » après 5 s sans paquet, client arrivé juste avant) ne laisse pas de cadavre chez ce client, et un cadavre fantôme d'une case bloque les cadavres suivants (écart d'objets statiques). Renvoyer le cadavre aux clients concernés (`sendCorpse` ou équivalent) sans doublon chez ceux qui l'ont déjà.
  - Accepté si : au banc et en campagne MP, un client sans copie au moment de la mort voit le cadavre (étape `world.keys`), aucun doublon chez l'autre.
  - Tests : banc ; suite `lk.death` (cas « client sans copie ») en campagne MP.
  - Preuve : cause (Java 42.21.0) : `DeadZombiePacket` ignoré par un client sans la copie, `sendCorpse` envoyé à toutes les connexions proches (doublon chez qui l'a déjà) ; correctif sur l'autorité MP : vérification 7 s après la mort (`corpseCheck` aux joueurs à 100 cases, identifiant `DeadBody-<n>`), réponse `corpseMissing` contrôlée (fenêtre 5 s, joueur proche), retrait chez tous puis `addCorpse` + `sendCorpse` 1 s plus tard, au plus 2 renvois ; banc `test_lk_death.py` 26 OK (`CorpseResendTests` 8 : un seul cadavre chez A et B) ; suite `lk.death` 4e test « killed before any client copy » ; base `zombies-as-npc-bodies.md` ; commit `81c1142` ; 2026-10-15 : `setCharacterOnlineID(-1)` refusé par Kahlua (paramètre `short` primitif, base `kahlua-lua.md`) : retrait sans masquer l'identifiant (`74bb68c`) ; MP ciblé (client 2 actif) : lk.death « killed before any client copy: corpse resent, one corpse on every client » PASS (`tools/autoclient/runs/20261015-045824-mp-c116c39f7cb9`)
  - Reste : identifiant réseau recyclé entre la mort et le renvoi : limite documentée ; fenêtre de fouille ouverte fermée au renvoi
