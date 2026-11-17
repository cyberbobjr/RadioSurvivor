# LK21 — Blessures localisées, infection, sang visible et soignant

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 0 / 12 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☐ | LK21-T01 | Modèle pur des plaies et registre des types | `testé hors jeu` | MP | — |
| ☐ | LK21-T02 | Les coups font des plaies ; la santé suit les plaies | `testé hors jeu` | MP | LK21-T01 |
| ☐ | LK21-T03 | La simulation hors écran utilise les mêmes plaies | `testé hors jeu` | MP | LK21-T02 |
| ☐ | LK21-T04 | Infection de plaie et virus de Knox | `à faire` | MP | LK21-T02 |
| ☐ | LK21-T12 | Retirer le verre brisé avant d'enjamber | `testé hors jeu` | MP | LK21-T02 |
| ☐ | LK21-T05 | Registre des soins, branchement par extension | `à faire` | MP | LK21-T02 |
| ☐ | LK21-T06 | Trousse de soins du soignant | `à faire` | MP | LK21-T05 |
| ☐ | LK21-T07 | Tâches du soignant : déchirer, laver, stériliser, attelle, remplir | `à faire` | MP | LK21-T06 |
| ☐ | LK21-T08 | Soins en expédition | `à faire` | MP | LK21-T06 |
| ☐ | LK21-T09 | Sang, trous et bandages visibles chez tous les joueurs | `à faire` | MP | LK21-T02 |
| ☐ | LK21-T10 | Gestes de pansement | `à faire` | MP | LK21-T05 |
| ☐ | LK21-T11 | Fiche du PNJ, documentation et changelog | `à faire` | MP | LK21-T09 |

<!-- fin du tableau de bord -->

**Mod.** Living Knox (`batman_LivingKnox`).

**Objectif.** Des blessures de PNJ comme celles du joueur : localisées, d'un type précis, qui s'infectent et dont le
sang se voit. Un soignant de groupe fabrique son matériel, porte une trousse et soigne, au foyer comme en expédition.

**ADR.** [Blessures localisées, infection, sang visible et soignant de groupe](../../architecture/decisions/adr-blessures-soins.md)
(accepté le 2026-11-17) ; ce plan en est l'ordre de livraison.

**Dépend de.** LK07 (santé de référence, saignement, soins), LK20 (façades et registres).

**Sources.** [Recherche moteur du 2026-11-17](../../annexes/conception/blessures-moteur.md) ;
[sante.md](../../annexes/conception/sante.md).

**Règles communes à toutes les tâches.**
- Test rouge d'abord.
- Un module par responsabilité. Les extensions passent par les registres : aucune liste fermée nouvelle, aucun `if kind == …` dans un moteur.
- Bancs verts, luacheck sans avertissement.
- Ligne joueur au CHANGELOG pour chaque changement visible.
- Fin de chaque phase : campagnes `solo-lk`, puis MP avec `--mods lk`.

## Phase 1 — Modèle des blessures

- [ ] **LK21-T01** — Modèle pur des plaies et registre des types
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : nouveaux `shared/LivingKnox/LK_Wounds.lua` et `shared/LivingKnox/Wounds/LK_Wound_<Kind>.lua` (griffure, coupure, profonde, morsure, balle, verre, fracture, brûlure) ; banc `tests/livingknox/test_lk_wounds.py`
  - Faire : D01 et D02 de l'ADR. `Wounds.registerKind`, `Wounds.add`, `Wounds.advance(list, minutes, ctx)` (guérison, saignement, usure du bandage, chance d'infection de plaie), `Wounds.bleeding(list)`, forme sauvegardée compacte et validée. Constantes du vanilla citées dans chaque fichier de type.
  - Accepté si : au banc, chaque règle du vanilla de la recherche est vérifiée (durées, saignement, bandage, points, attelle, infection) ; aucun appel au jeu dans le module.
  - Tests : `tests/livingknox/test_lk_wounds.py` (rouge d'abord) ; `tests/run_all.py --keep-going`.
  - Preuve : 2026-11-17, `python tests/run_all.py --keep-going` : `Summary: 213 passed, 0 failed, 0 skipped (684.2 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement). Rouge d'abord : `tests/livingknox/test_lk_wounds.py` `FAILED (errors=26)` (`module 'LivingKnox/LK_Wounds' not found`), puis `Ran 26 tests OK` ; `test_kahlua` `test_wounds_in_kahlua` : même ligne `KR-WOUNDS` dans la VM réelle. Modules `LK_Wounds.lua` (596 lignes : parties, registre des types, `add`, `advance`, transitions de soin), `LK_WoundsNeeds.lua` (besoins de soin, registre `registerNeed`), `LK_WoundsForm.lua` (`pack`, `unpack`, `valid`) ; 8 types dans `Wounds/` avec les constantes de `BodyPart.java` 42.22 citées. Non requis par `LK_Core` (cycle `LK_Core` → `LK_Wounds` → `LK_Registry` → `LK_Core`) : chaque consommateur requiert le module dont il a besoin. Écart assumé à l'ADR, corrigé dans l'ADR : une plaie infectée ne saigne pas plus (vanilla).
  - Reste : campagnes de fin de phase.

- [ ] **LK21-T02** — Les coups font des plaies ; la santé suit les plaies
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK21-T01
  - Fichiers : `server/LivingKnox/LK_Health.lua`, nouveaux `server/LivingKnox/Wounds/LK_WoundSource_<Id>.lua` (zombie, tranchant, contondant, arme à feu, feu, verre), registre des corps (`LK_Identity`, champ `wounds`)
  - Faire : D03 de l'ADR. `Wounds.registerSource`. `Health.applyHit` crée les plaies par la source du coup. La perte de santé par minute vient de `Wounds.bleeding`. `npc.bleed` est retiré. Les plaies sont sauvegardées avec le registre des corps.
  - Accepté si : au banc, une griffure de zombie, un coup de couteau, une balle et le feu donnent les plaies attendues, et la santé baisse selon le saignement des plaies ; `lk.health`, `lk.death` et `lk.killer` vertes.
  - Tests : bancs `test_lk_health`, `test_lk_death`, `test_lk_wounds` ; campagnes.
  - Preuve : 2026-11-17, `python tests/run_all.py --mod livingknox --keep-going` : `Summary: 115 passed, 0 failed, 0 skipped (430.0 s)`, `RESULT: PASS` (luacheck Contents et dev 0 avertissement ; `doubles_api` vert après rattachement des doublures `HandWeapon` et `IsoZombie` de `test_lk_wound_sources.py`). Rouge d'abord : `tests/livingknox/test_lk_wound_sources.py` (module `LivingKnox/LK_WoundSources` absent), puis vert. Registre `Wounds.registerSource` (`server/LivingKnox/LK_WoundSources.lua`), contexte jeu `LK_WoundContext.lua`, six sources `Wounds/LK_WoundSource_{Zombie,Blunt,Firearm,Blade,Fire,Glass}.lua` (chances du vanilla citées). `Health.applyHit` crée les plaies par la source du coup ; la santé suit le calcul vanilla (poids des parties, saignement, régénération passive `0,002` par tick) : écart mesuré au vanilla 1,5 point au plus (oracle `vanilla_loss` de `test_lk_health`). `npc.bleed` retiré ; plaies sauvegardées et validées dans le registre des corps (`LK_Identity`).
  - Reste : campagnes de fin de phase (`lk.health`, `lk.death`, `lk.killer`).

- [ ] **LK21-T03** — La simulation hors écran utilise les mêmes plaies
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK21-T02
  - Fichiers : `server/LivingKnox/LK_Simulation.lua`, `shared/LivingKnox/LK_Config.lua` (réglages `WOUND_*` abstraits retirés) ; nouveaux `shared/LivingKnox/LK_WoundsHealth.lua` (formule de santé commune, `Wounds.healthStep`) et `server/LivingKnox/LK_MemberHealth.lua` (plaies et santé d'un membre hors écran, critère « gravement blessé »)
  - Faire : D01 de l'ADR. La blessure abstraite `wound` 0..100 disparaît. Les événements hors écran créent des plaies par une source, et l'heure hors écran les fait évoluer par `Wounds.advance`. La consommation de soins hors écran est déduite des soins appliqués.
  - Accepté si : bancs de la simulation verts avec les nouveaux attendus justifiés ; un membre blessé hors écran revient avec ses plaies.
  - Tests : `test_lk_simulation`, `test_lk_wounds` ; campagnes.
  - Preuve : 2026-11-17. Rouge d'abord : nouveaux attendus de `tests/livingknox/test_lk_simulation.py` lancés sur une copie du code d'avant (`git archive HEAD`) : `Ran 56 tests` `FAILED (failures=7, errors=29)` (`attempt to index field 'MemberHealth' (a nil value)`) ; `test_lk_materialize.py WoundsRoundTripTests` : `FAILED (errors=1)`. Vert : `test_lk_simulation` `Ran 56 tests OK`, `test_lk_materialize` `Ran 17 tests OK`, tous les bancs `tests/livingknox/test_lk_*.py` lancés un par un (sauf `test_lk_obstacles`, LK21-T12 en cours) verts : 103 bancs, 1993 tests, 0 échec ; `tests/coreai/test_kahlua.py` `Ran 44 tests OK` (`KR-SIM`, `KR-EVT` : mêmes valeurs sous Kahlua et lupa), `test_doubles_api.py` `Ran 17 tests OK`, `test_mod_calls_api.py` `Ran 16 tests OK` ; `luacheck Contents dev --config .luacheckrc` : `0 warnings / 0 errors`. Membre hors écran : `member.wounds` (forme `Wounds.pack`, validée par `LK_Groups.validGroup` comme le registre des corps) et `member.health` (fraction, absente = pleine). Coups hors écran par `Wounds.fromHit` avec une source imposée par les données (`WOUND_SOURCE` « blunt », expéditions `SOURCE` « zombie », conflit « blunt », combat « blade » ; la maladie ne fait que perdre de la santé) ; l'heure applique `Wounds.healthStep`, la formule que `LK_Health` appelle aussi (une seule copie) ; mort à santé 0. Soins : bandage des plaies qui saignent (`Wounds.bandageBleeding`, commun avec `Health.stopBleeding`), `MEDICAL_PER_BANDAGE` par bandage posé. Critère unique `MemberHealth.seriouslyWounded` (santé sous l'option WoundedHealth, ou plaie qui saigne) pour la tâche `heal`, les équipes d'expédition, les raids, la vengeance et la force au combat ; seuil lu une fois (`Config.woundedRatio`, aussi pour `Decisions.woundRatio`). Passage incarné <-> hors écran : plaies passées telles quelles (`Health.setBirth(id, hp, wounds)`, `Health.handOver`). Vues : santé et nombre de plaies (fiche : champ réglable `offhealth`). Attendus changés et pourquoi : empreintes figées de `test_lk_simulation` (événements, rattrapage), `test_lk_raids`, `test_lk_revenge`, `test_lk_fortify_offscreen` et valeurs `KR-SIM`/`KR-EVT` (tirages des plaies dans le flux de l'heure, état des membres) ; empreintes de `test_lk_decision_context` (seul le champ de membre `wound` renommé `health` dans les tables relevées : relevés d'avant et d'après identiques champ ôté) ; `setup_world` : nourriture 30 (sous `NEED_TRIGGER`, l'expédition attendue part dans les 24 h : la blessure grave se soigne maintenant en une heure) ; équipe du test de départ : le blessé grave fait soigner le groupe au lieu de fouiller, exclusion vérifiée par `teamCandidates`.
  - Reste : campagnes de fin de phase.

- [ ] **LK21-T04** — Infection de plaie et virus de Knox
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK21-T02
  - Fichiers : `shared/LivingKnox/LK_Wounds.lua` (infection), nouveau `server/LivingKnox/LK_Infection.lua`, `LK_Health.lua`, `LK_Bodies.lua` (relevé en zombie ordinaire)
  - Faire : D04 de l'ADR. L'infection de plaie suit les chances du vanilla : une plaie infectée saigne plus et demande d'être désinfectée. Le virus est transmis par une morsure selon l'option sandbox de transmission ; le délai est tiré dans la table du vanilla. À la mort, le PNJ se relève en zombie ordinaire, il quitte le registre et la mort est observée par le groupe. Le journal note la morsure.
  - Accepté si : au banc, morsure, transmission, délai, mort et relevé ; option « pas de transmission » respectée ; en jeu, suite `lk.wounds` : un PNJ mordu, avec un délai réduit pour le test, se relève en zombie ordinaire.
  - Tests : `test_lk_infection` (rouge d'abord) ; suite `lk.wounds`.

- [ ] **LK21-T12** — Retirer le verre brisé avant d'enjamber
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : LK21-T02
  - Fichiers : `server/LivingKnox/Obstacles/LK_Obstacles_Windows.lua`, exécutant client (geste), source `Wounds/LK_WoundSource_Glass.lua`
  - Faire : D03 de l'ADR (verre brisé). Devant une fenêtre brisée dont le verre reste, un PNJ qui n'est ni en fuite ni en combat retire le verre (même effet et même synchronisation que l'action vanilla, fenêtre marquée verre retiré), puis enjambe. En fuite ou en urgence, il enjambe tout de suite et court le risque du vanilla (1 sur 2, main ou avant-bras, éclats 1 fois sur 7, sinon griffure).
  - Accepté si : au banc, retrait avant passage hors urgence, risque appliqué en fuite ; en jeu, `lk.traversal` « broken window » : verre retiré, aucune plaie, fenêtre vue sans verre par les deux clients en MP.
  - Tests : `test_lk_obstacles`, `test_lk_wounds` ; suite `lk.traversal`.
  - Preuve : 2026-11-17, rouge d'abord : nouveaux `GlassTests` et `MultiplayerGlassTests` de `tests/livingknox/test_lk_obstacles.py` `Ran 7 tests FAILED (failures=4, errors=8)`, puis `Ran 139 tests OK`. Règles pures `EdgeRules.glassLeft` et `EdgeRules.glassStep(window, hurry)` (« remove », « risk » ou rien) ; fait de bord `glassRemoved` (`IsoWindow.isGlassRemoved`, `IsoWindow.java:1280`). Nouveau `server/LivingKnox/Obstacles/LK_Obstacles_Glass.lua` : PNJ calme -> geste `removeglass` (clip `rummage`, celui de `ISRemoveBrokenGlass`), verre retiré par l'autorité à 2080 ms (durée vanilla 100 / 48 par seconde) par `removeBrokenGlass()` puis `sync()`, comme `ISRemoveBrokenGlass:complete` ; PNJ pressé (priorité de passage de son comportement >= 70 : alerte, défense, combat, fuite, soin...) -> enjambe, tirage 1 sur 2 au passage puis `Health.applyHit(..., 10, ..., { source = "glass", risk = false })`. Geste gardé par le relais (`Config.RELAY.KEEP_GESTURES.removeglass`). Suite `lk.traversal` : cas « broken window with glass ». Suite complète : voir le commit de LK21-T03.
  - Reste : suite `lk.traversal` en solo et en MP (fenêtre vue sans verre par les deux clients : confirmé statiquement, `IsoWindow.syncIsoObjectSend`, `IsoWindow.java:744`, et au banc) ; risque en MP lu sur l'état `climbwindow` de la copie serveur, à confirmer en jeu.

## Phase 2 — Soins et soignant

- [ ] **LK21-T05** — Registre des soins, branchement par extension
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK21-T02
  - Fichiers : `server/LivingKnox/LK_Care.lua` (choix du blessé, du soignant et du soin), nouveaux `server/LivingKnox/Care/LK_Treat_<Id>.lua` (désinfecter, bander, changer un bandage, recoudre, attelle, retirer éclats ou balle), `Decisions/LK_Decisions_Apply.lua`
  - Faire : D05 et D06 de l'ADR. `Care.registerTreatment` : plaies traitées, matériel par fonction vanilla, durée, geste, effet. Le soin le plus urgent passe d'abord. L'appel direct de `Care.apply` devient une extension inscrite.
  - Accepté si : au banc, chaque soin consomme son vrai matériel et produit son effet sur la plaie ; aucune règle de soin dans `LK_Care` ; `lk.care` verte et ajoutée aux campagnes.
  - Tests : `test_lk_care` (réécrit, rouge d'abord) ; suite `lk.care`.

- [ ] **LK21-T06** — Trousse de soins du soignant
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK21-T05
  - Fichiers : nouveau `server/LivingKnox/LK_MedKit.lua`, `LK_Care.lua` (ordre des sources de matériel), équipement du soignant
  - Faire : D08 de l'ADR. Le soignant porte un `FirstAidKit` réel, rempli au stock selon une liste cible déclarée. Le matériel est pris dans la trousse, puis sur le blessé, puis au stock du foyer.
  - Accepté si : au banc, remplissage et ordre de prise ; aucun objet créé ; trousse retrouvée sur le cadavre du soignant.
  - Tests : `test_lk_medkit` (rouge d'abord).

- [ ] **LK21-T07** — Tâches du soignant : déchirer, laver, stériliser, attelle, remplir
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK21-T06
  - Fichiers : nouveaux `server/LivingKnox/Jobs/LK_Job_RipCloth.lua`, `LK_Job_WashBandage.lua`, `LK_Job_Sterilize.lua`, `LK_Job_MakeSplint.lua`, `LK_Job_RefillKit.lua` ; `LK_Config.lua` (rôle affiché « soignant ») ; traductions
  - Faire : D07 de l'ADR. Chaque tâche est inscrite par `Upkeep.registerJob`. Déchirer suit le calcul de `RipClothing` du vanilla (types de tissu, ciseaux pour le jean et le cuir) sur des vêtements du stock ou d'un cadavre proche (retrait du conteneur du cadavre). Laver demande de l'eau ; stériliser, de l'eau bouillante ou de l'alcool. Une attelle est fabriquée (recette `MakeSplint` : tissu déchiré et planche, branche ou bâton) quand une fracture en demande une et qu'il n'y en a ni dans la trousse ni au stock. Les soins passent avant les tâches quand une plaie saigne.
  - Accepté si : au banc, chaque tâche consomme et produit de vrais objets selon les recettes vanilla ; en jeu, suite `lk.healer` : un soignant déchire un vêtement d'un cadavre et range le tissu dans sa trousse.
  - Tests : `test_lk_healer` (rouge d'abord) ; suite `lk.healer`.

- [ ] **LK21-T08** — Soins en expédition
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK21-T06
  - Fichiers : `server/LivingKnox/Expeditions/` (halte), `LK_Care.lua`
  - Faire : D08 (départ) et D09 de l'ADR. Au départ d'une expédition, le matériel médical du foyer est réservé d'abord à la trousse du soignant de l'équipe, avant les provisions des autres. Une plaie qui saigne fort arrête l'équipe dans un lieu sans menace perçue ; le soin puise dans la trousse ou sur le blessé, puis l'équipe reprend.
  - Accepté si : au banc, matériel médical réservé au soignant au départ, puis halte, soin et reprise ; en jeu, un membre blessé en expédition est soigné sur place (suite `lk.expedition` ou `lk.care`).
  - Tests : `test_lk_expeditions`, `test_lk_care` ; campagnes.

## Phase 3 — Ce qui se voit

- [ ] **LK21-T09** — Sang, trous et bandages visibles chez tous les joueurs
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK21-T02
  - Fichiers : nouveaux `server/LivingKnox/LK_WoundSync.lua` (état visible envoyé quand il change) et `client/LivingKnox/LK_WoundView.lua` (pose sur le corps vu, repose à la recréation)
  - Faire : D10 de l'ADR. Valeurs explicites par partie (`setBlood`, `addHole`, objets `Bandage_<Part>` et `_Blood`), jamais tirées au hasard.
  - Accepté si : au banc, même rendu calculé sur deux clients ; en jeu, suite `lk.woundvisuals` : capture du sang sur un PNJ blessé, identique sur les deux clients en MP.
  - Tests : `test_lk_wound_view` (rouge d'abord) ; suite `lk.woundvisuals` et capture.

- [ ] **LK21-T10** — Gestes de pansement
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK21-T05
  - Fichiers : `tools/anim_table.json`, `tools/gen_animsets.py`, AnimSets générés, `Care/LK_Treat_*.lua`
  - Faire : D11 de l'ADR. Essai des clips vanilla `Bob_Bandage*` sur un corps de zombie ; s'ils jouent, ils sont ajoutés et choisis par partie du corps, sinon le geste `kneel` est gardé et la tâche le consigne.
  - Accepté si : en jeu, capture du geste de pansement, ou preuve de son échec et repli consigné.
  - Tests : `test_gen_animsets` ; suite `lk.care`.

- [ ] **LK21-T11** — Fiche du PNJ, documentation et changelog
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : LK21-T09
  - Fichiers : `client/LivingKnox/LK_NpcSheet.lua` (plaies listées), `docs/annexes/conception/sante.md`, wiki fr/en, `CHANGELOG.md`
  - Faire : la fiche admin d'un PNJ liste ses plaies (partie, type, bandage, infection). Mettre à jour la fiche de conception (limites levées) et le wiki, et ajouter les lignes joueur au CHANGELOG.
  - Accepté si : `lk.npcsheet` verte ; documents à jour.
  - Tests : `tests/run_all.py --keep-going` ; campagnes.
