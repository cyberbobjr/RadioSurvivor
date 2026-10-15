# LK05 — Perception, décisions et routines

**Objectif.** Donner aux PNJ des sens simples et un cadre de décision à deux niveaux : objectifs du groupe à long terme (stock, sécurité, fortification) et réactions individuelles à court terme (menace proche, faim, soif, fatigue, peur, blessure). Le serveur décide ; le propriétaire exécute des routines déterministes (sommeil, garde, patrouille, corvées, repas, expédition, retour, défense).

**Dépend de.** LK03-T01, LK04-T02.

**Sources.** Décisions LK00 (groupes, foyers) ; Java vanilla (vue, ouïe, lumière, heure).

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-08 — Besoins à court et long terme (voir LK00) : modèle de décision tranché en `LK05-T02` (ci-dessous) ; besoins individuels (`LK05-T06`), repas réels (`LK05-T07`), alerte (`LK05-T08`) et défense coordonnée (`LK05-T09`) ajoutés.
- 2026-10-08 — **LK05-T02** : modèle **hybride**. Groupe, long terme : objectifs notés par score d'utilité à chaque heure de jeu (stock, besoins, menaces connues, fortification, personnalité du chef), rôles attribués aux membres. Membre, court terme : cascade de priorités fixe (menace, peur, blessure, faim, soif, fatigue, consigne du groupe, routine), comportements permis selon le rôle, états à échéance recalculés à l'échéance ou sur interruption, hasard déterministe tiré de l'identité.
- 2026-10-11 — Ordre de travail choisi par l'utilisateur : vie des groupes (LK05) puis combat (LK06) avant les autres chantiers.
- 2026-10-08 — **LK05-T06** : quatre jauges simples de 0 à 100 par membre (faim, soif, fatigue, peur), tenues par le serveur, même modèle à l'écran et hors écran.
- 2026-10-12 — **LK05-T14** (demande de l'utilisateur) : les seuils de distance qui déclenchent alerte, fuite, défense, engagement des zombies, retraite et renforts sont trop grands pour un serveur très peuplé en zombies (un groupe entier peut rester bloqué en alerte) ; ils doivent être réglables dans les options sandbox.
- 2026-10-14 — **LK05-T05** : `Expeditions.CFG` (équipe 2, charge 4/8, 6–45 cases, 7 h–16 h, 4 h de repos), table `ROOMS` (`bedroom` = munitions), butin abstrait (0,5 par membre et par manque), membre retiré seul qui quitte l'équipe (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK05-T07** : effet proportionnel à la ration (un repas rationné soulage moins, d'où plus d'objets par jour ; option : quota par jour) ; bouteille d'eau bue entière ; plancher de part 0,5 (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK05-T09** : seuls zombies et joueurs hostiles déclenchent la défense ; défense tant que le serveur recense une menace ; seuils 12 cases, rapports 3 et 2, hostile = 3 zombies, laisses 3 et 1 cases (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : un groupe en campement se bat sur place contre les zombies (au lieu de « camp sans défense ») : tâche LK05-T18.
- 2026-10-14 — **LK05-T10** : déchets = verre brisé seulement ; lumières de 19 h à 7 h ; plein sans arrêt, réparation à l'arrêt ; entretien = corvée prioritaire (pas de comportement de cascade) (confirmé par défaut, valeurs techniques) ; changement (décision de l'utilisateur) : seuls les générateurs du groupe sont entretenus, plus ceux d'un joueur dans la zone : tâche LK05-T19.
- 2026-10-14 — **LK05-T11** : cueillette si la nourriture est le premier manque, rendement ≥ 25 %, 40 cases ; 3 tirages par membre toutes les 15 min, cueilleur niveau 3 ; objets empoisonnés jetés, graines rangées non suivies ; eau croupie d'abord pour arroser (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK05-T14** : défauts plus courts (alerte zombie 10, portée 20, cri 10, fuite 4/8, engagement 4, défense 8, retraite 8, renforts 15) ; une seule option de rapport de défense (retour au rapport − 1) ; sommations inchangées ; limite zombie mesurée depuis le membre qui perçoit ; renforts de défense = `AlertReach` (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK05-T16** : une option règle toutes les règles qui utilisaient la constante (pas seulement l'inaptitude au combat) (confirmé par défaut, valeurs techniques).

- 2026-10-14 — **Correctifs MP de la campagne automatique confirmés** (utilisateur) : tolérance de position des rapports `REPORTS.MAX_GAP` = 22 cases (LK03, `rapports.md`) ; alerte levée aussi par le zombie qu'un membre combat, décidée par le serveur (LK05-T08, commit `778b940`) ; entretien qui garde la première tâche de chaque sorte sous le plafond `MAX_JOBS` (LK05-T10, `entretien.md`) ; zombie devant la vitre traité comme s'il la frappait jusqu'au rapport de la fenêtre frappée par le propriétaire (LK06-T11, décision 1).
- 2026-10-15 — **Blessé du campement au contact d'un zombie** : on garde le comportement actuel (un blessé à l'abri frappe au contact un zombie qui a franchi la couronne) ; confirmé par défaut (2026-10-15, l'utilisateur ne souhaite pas être interrogé sur le détail).
- 2026-10-15 — **Pêche (LK05-T11) reportée** (décision de l'utilisateur) : le code de la pêche reste en place mais sa preuve en jeu (décor avec de l'eau, test 5 de `lk.forage`) est mise de côté pour l'instant ; LK05-T11 se juge sur la cueillette, l'arrosage et la récolte du potager.

## Tâches

- [x] **LK05-T01** — Perception : vue, ouïe, lumière
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK03-T01
  - Fichiers : `LK_Senses.lua`
  - Faire : détection des joueurs et zombies selon distance, ligne de vue, lumière, bruit, posture ; résultats rapportés au serveur, pas de décision locale persistante.
  - Idées : I2.1 (lumière, allure, distance), I2.2 (vigilance selon l'activité) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : mêmes entrées → même résultat ; coût borné par tick.
  - Tests : banc ; suite en jeu.
  - Preuve : `LK_Senses.lua` (shared) : calcul chez l'exécutant (`Senses.scan`, lumière de case propre au joueur local `IsoGridSquare.java:8896-8908`), mémoire chez l'autorité (`Senses.accept`, `perceived`, `perceivedPlayer`) ; transport par le champ `sen` du rapport d'état (validé, filtré, rapport avancé sur changement) ; vue = 20 cases × lumière × météo × ligne de vue (`LosUtil.lineClear`, identique à `CanSee` ; vitre fermée transparente, facteur 0,8) ÷ étages × champ × posture × allure × vigilance (≤ 30), attention cumulée ; ouïe : bruit propre de la cible et `OnWorldSound` ÷ murs (pas vanilla aléatoires et locaux écartés) ; déterministe, coût borné (4 PNJ, 24 cibles, 32 `lineClear` par passage) ; `test_lk_senses.py` 22, `test_kahlua.py` KR-SENSES ; suite `lk.senses` ; `run_all.py` 45/45 le 2026-10-11, luacheck 16/0 et 0 ; `docs/conception/perception.md` ; base `perception.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo lk.senses 2/2 placé seul (`20261013-202155-solo.txt`)
  - Reste : en jeu solo : RST.run({suite="lk.senses",tags="world"}) 2/2 (vu à découvert, entendu derrière un mur sans être vu) ; seuils à recalibrer ; vigilance de l’autorité non transmise à l’exécutant en MP (LK05-T03) ; PNJ rivaux non perçus ; MP à la séance finale

- [x] **LK05-T02** — Cadre de décision serveur
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK05-T01
  - Fichiers : `LK_Decisions.lua` (server)
  - Faire : coder le cadre hybride décidé le 2026-10-08 (section Décisions) : notation des objectifs du groupe sur le serveur à chaque heure de jeu, cascade de priorités par membre, registre des comportements permis par rôle, états à échéance, raisons de chaque choix au journal du groupe. Actions en liste fermée ; produit des consignes LK03.
  - Idées : I1.1 à I1.6 ; synthèse recommandée : objectifs du groupe notés par utilité + cascade de priorités par membre (voir `docs/idees-bandits-alife.md`)
  - Accepté si : décisions reproductibles en test ; aucune décision prise par un client.
  - Tests : banc.
  - Preuve : `LK_Decisions.lua` (serveur) : objectifs du groupe notés chaque heure de jeu (`floor(getWorldAgeHours)`) parmi `settle`, `rest`, `guard`, `heal`, `supply`, `fortify` (réserves, repos, nuit, blessés, menaces vues 6 h, fortification neutre, hostilité du type, traits du chef, écart reproductible ±3), postes (`sentry`, `rest`, `keeper`, `carer`, `forager`, `builder`) selon les comportements du rôle, journal du groupe sur changement, champs facultatifs `objective` et `duty` ; cascade par membre (menace, peur, blessure, faim, soif, fatigue, poste, routine ; besoins neutres en attendant LK05-T06) ; états à échéance ; hasard déterministe ; comportements branchés `home`/`rest`/`sleep`, `guard`, `watch`, `flee` (non-combattants) en consignes LK03, vigilance de la perception réglée ; jamais côté client ; 1 passage/s, 4 membres au plus ; `test_lk_decisions.py` 20, `test_kahlua.py` KR-DECIDE ; `run_all.py` 46/46 le 2026-10-11, luacheck 16/0 et 0 ; `docs/conception/decisions.md` ; base `kahlua-lua.md` (`MathLib`)
  - Reste : en jeu solo (rstest) : ligne « group grp-N objective » au chargement d’un foyer ; LivingKnox.Decisions.get("lk-N") ; sentinelle tournée vers l’extérieur ; zombie proche : non-combattant fuit, combattant regarde ; retour au foyer ; valeurs à recalibrer ; vigilance non transmise en MP (LK05-T03) ; états non sauvegardés

- [ ] **LK05-T03** — Routines : sommeil, garde aux postes, patrouille
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK05-T02
  - Fichiers : `LK_Routines.lua`
  - Faire : postes et rondes définis par le foyer ; relèves selon l'heure ; sommeil sur couchage.
  - Idées : I2.2 (sentinelle), I3.1 (horaires décalés, veille de nuit), I3.2 (laisse autour du foyer), I3.3 (maison tenue la nuit, cour nettoyée à l'aube) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : routine observable sur une journée de jeu accélérée, identique pour deux observateurs.
  - Tests : suite `lk.routines` + protocole.
  - Preuve : `LK_Routines.lua` : relevé du foyer au premier passage (postes intérieurs contre portes puis fenêtres, regard vers l'extérieur, 6 au plus ; lits `IsoFlagType.bed`, qualité `BedType` ; ronde de coins et milieux à 2 cases dans la laisse de 10), sauvegardé dans le champ facultatif `posts` ; quarts de 4 h (guet de nuit, ronde à l'aube et première heure de jour), guetteur et poste tournants ; sommeil : geste assis au sol (`Bob_SitGround_Idle`, nœud `lkactor_sit`) près du lit, vigilance « endormi » (couché `Bob_Asleep` exige `onbed`, repli documenté) ; menace : relève et interrompt la routine ; vigilance transmise à l'exécutant MP (champ `vg` des consignes) ; repris d'un premier agent arrêté par la limite, corrigé (réveil, changement de plan, dormeur ramené dans le bâtiment, attribution des lits) ; `test_lk_routines.py` 18 (serveur + 2 clients : mêmes consignes, gestes, vigilance) ; suite `lk.routines` ; `run_all.py` 47/47 le 2026-10-11, luacheck 16/0 et 0 ; `docs/conception/routines.md` ; base `api-42-21.md` (`setTimeOfDay`), `world-placement.md` (lits) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : lk.routines 1/1 (`20261013-153514-solo.txt` : sentinelle au poste de nuit, deux dormeurs, menace, ronde à l'aube ; le test dépose eau, nourriture et munitions) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.routines 1/1 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`)
  - Reste : geste assis à voir (aucune étape client) ; relevé figé si les meubles changent ; lk.routines absente de la campagne solo du 2026-10-15

- [x] **LK05-T04** — Corvées au foyer
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK05-T03
  - Fichiers : `LK_Routines.lua`
  - Faire : petites activités visibles (feu, rangement, guet, soins) choisies dans une liste fermée, sans effet sur le monde au-delà du foyer.
  - Idées : I3.4 (gestes au repos reliés aux traits) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : aucune modification d'objet hors du foyer.
  - Tests : suite en jeu.
  - Preuve : liste fermée `Routines.CHORES` : `fire` (accroupi près d'un `IsoFireplace` ou d'une cuisinière), `warm` (mains au feu), `tidy` (fouille d'un meuble à conteneur), `lookout` (fenêtre), `repair` (marteau à une porte ou fenêtre), `smoke` (trait `smoker`), `care` (à genoux près du blessé), `rest` (assis) ; clips joueur vanilla `Bob_IdleLooting_Low/Mid`, `Bob_SitGround_WarmHands`, `Bob_IdleHammering`, `Bob_IdleSmoke`, `Bob_SitGround_Idle` en nœuds `lkactor_*` générés sans événement ; choix pondéré par poste, rôle et traits (I3.4), tirage déterministe par créneau de 30 min, places distinctes ; comportement `chore` de jour dans la cascade, interrompu par une menace puis repris ; aucune modification d'objet (lecture seule) ; `test_lk_chores.py` 12, `run_all.py` 48/48 le 2026-10-11, luacheck 16/0 et 0, `gen_animsets.py --check` 29 nœuds ; suite `lk.chores` ; `docs/conception/routines.md` ; base `custom-tiles-entities.md`, `zombies-as-npc-bodies.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo-retry lk.chores 1/1 (corvées réparties, menace qui interrompt, reprise, aucun objet modifié) (`20261013-205100-solo.txt`) ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.chores PASS (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : en jeu solo (rstest, maison meublée avec feu ou cuisinière) : RST.run({suite="lk.chores",tags="world"}) 2 à 4 min ; rendu des gestes sur un corps de PNJ à voir ; places relevées une fois ; soins sans effet ; rez-de-chaussée seulement ; la campagne MP automatique passe (2026-10-14) ; restent pour la séance finale les contrôles à deux joueurs actifs et à la main ci-dessus

- [ ] **LK05-T05** — Expéditions physiques et retour
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK05-T03
  - Fichiers : `LK_Routines.lua`, `LK_Directives.lua`
  - Faire : une équipe quitte le foyer vers un lieu choisi par le serveur selon ce qui manque au stock (`LK08-T07`), fouille brièvement, rapporte son butin au stock, revient ; si aucun joueur n'est proche, l'expédition passe en simulation abstraite (LK09).
  - Idées : I4.1 (bâtiment choisi par le chef, conteneurs réservés, charge bornée, retour au dépôt), I4.2 (objets cherchés selon les manques, par tags du jeu) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : départ et retour cohérents vus par deux clients ; bascule abstraite sans perte de membre.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_expeditions.py` du 2026-10-12 (13 tests OK : départ selon l'objectif `supply` et les manques du stock, équipe de fourrageurs, bâtiment choisi sans charger et reproductible, conteneurs réservés, charge bornée, retour au stock sans perte ni vol, bascule hors écran sans perte de membre et butin abstrait reproductible, suite `lk.expedition` sur doublures) ; run_all 64/64 ; luacheck 16/0 ; conception `docs/conception/expeditions.md` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.expedition 1/1 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; campagne solo-lk (`tools/autoclient/runs/20261015-135627-parallel-2-c6a500a78137`) : lk.expedition « foragers search a nearby building and bring real items home » PASS
  - Reste : MP : départ et retour vus par le client 2 (aucune étape client) ; éloignement à plus de 120 cases non automatisé ; fouille au seul niveau du foyer ; objets portés perdus si le serveur redémarre pendant une expédition

- [x] **LK05-T06** — Besoins individuels : faim, soif, fatigue, peur
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK05-T02, LK08-T01
  - Fichiers : `LK_Needs.lua` (server) ; registre des groupes
  - Faire : jauges faim, soif, fatigue et peur (0-100) par membre, tenues par le serveur, évoluant avec l'heure de jeu et l'activité ; seuils qui créent des envies (manger, boire, dormir, fuir) transmises à la cascade de priorités ; rattrapage après une absence par le même calcul.
  - Idées : aucune chez A ni B (faim et soif seulement animées) : modèle propre (voir `docs/idees-bandits-alife.md`)
  - Accepté si : évolution reproductible en test ; aucune jauge tenue par un client ; coût borné par heure de jeu.
  - Tests : banc.
  - Preuve : `LK_Needs.lua` (serveur) : jauges entières `hunger`, `thirst`, `fatigue`, `fear` (0-100) dans le champ facultatif `member.vitals`, pas horaire selon l'activité (sommeil, repos, attente, guet, travail, ronde, voyage, fuite), peur immédiate par menace perçue (zombie, joueur hostile ou méfiant ; trait `nervous`, combattant) ; repas abstrait en attendant LK05-T07 (−60 au point de repas si faim ou soif ≥ 70, réserve du groupe) ; même pas à l'écran (activité observée de la cascade) et hors écran (horaire abstrait, branché dans `LK_Simulation.step`), rattrapage borné à 24 h ; cascade : fatigue ≥ 80 → dormir, faim/soif ≥ 70 → rentrer, peur ≥ 70 → fuite plus longue d'un non-combattant ; aucune jauge côté client ; `test_lk_needs.py` 15, `run_all.py` 49/49 le 2026-10-11, luacheck 16/0 et 0 ; `docs/conception/besoins.md`
  - Reste : valeurs à recalibrer ; repas réels en LK05-T07 ; jauges sans effet sur santé, moral ou vigilance ; hors écran la peur ne fait que baisser

- [ ] **LK05-T07** — Repas et boisson réels pris dans le stock
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK05-T06, LK08-T06
  - Fichiers : `LK_Routines.lua`, `LK_Stock.lua`
  - Faire : un membre qui a faim ou soif va au point de repas du foyer, prend un aliment ou de l'eau réels dans les conteneurs, les consomme avec un geste visible ; à défaut, le besoin remonte au groupe (rationnement, expédition).
  - Accepté si : objet retiré une seule fois du conteneur, vu identique par deux clients ; aucun objet créé à partir de rien.
  - Tests : suite en jeu + protocole.
  - Preuve : banc `tests/test_lk_meals.py` du 2026-10-12 (14 tests OK : objet réel retiré une seule fois du conteneur et de la référence sans perte ni vol, aucun objet créé, besoin soulagé une fois selon la portion, stock vide → pénurie au journal et besoin mis de côté) ; run_all 55/55 ; luacheck 16/0 ; conception `besoins.md` (Repas réels), `routines.md`, `stock.md` ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.meals 1/1 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; campagne solo-lk (`tools/autoclient/runs/20261015-135627-parallel-2-c6a500a78137`) : lk.meals « hungry member eats one real item from the home stock » PASS
  - Reste : MP : objet disparu du meuble chez deux clients (aucune étape client) ; pas de clip de repas ; repas en cours perdu au redémarrage

- [ ] **LK05-T08** — Alerte de proximité : zombies et intrus
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK05-T01, LK05-T02
  - Fichiers : `LK_Decisions.lua`, `LK_Senses.lua`
  - Faire : une menace perçue près du foyer ou d'un membre (zombies, joueur hostile ou inconnu) déclenche une alerte de groupe : interruption des tâches, cri d'alerte audible, membres réveillés, portes refermées ; niveau d'alerte qui retombe avec le temps.
  - Idées : I2.3 (indices de présence humaine), I2.4 (dernière position partagée, recherche en spirale), I6.2 (annonces de position) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : alerte déclenchée une seule fois par menace, vue par deux clients ; retour à la routine après la menace.
  - Tests : banc ; suite en jeu.
  - Preuve : `LK_Alert.lua` (autorité) : alerte de groupe sur menace perçue près d'un membre ou du foyer (zombie ≤ 10/15 cases, niveau 45 ; joueur inconnu ou méfiant ≤ 8/12, niveau 50, `Hostility.isKnown` ; hostile ≤ 20/25, niveau 80), une seule fois par menace (clé gardée 60 min de jeu ; `raised`/`escalated` seuls crient), niveau −5 par minute, fermeture à 10 ; membres à 30 cases ou au foyer : tâches et sommeil interrompus, vigilance `guard`, regard vers la dernière position connue partagée, geste `guard`/`crouch`, non-combattant ramené au foyer ; cri : réplique `alert`, bruit `addSound` 15/20/30 (cri vanilla 30, `IsoGameCharacter.java:4810-4888`), voix `Voice*ShoutHey` chez les clients proches (`LK_AlertView.lua`, livraison unique) ; retour à la routine ; écouteurs `Alert.subscribe` (portes à brancher) ; `test_lk_alert.py` 16, `test_kahlua.py` KR-ALERT ; suite `lk.alert` ; luacheck des fichiers 0 ; `docs/conception/alerte.md` ; base `sounds-and-noise.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.alert", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-175002-solo.txt`) (après correctif de la suite `feb3aff`) ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.alert 2/2 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.alert 2/2 avec étapes lk.alert.view et lk.facing du client 2 vertes (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/client2/20261015-090729-steps.txt`)
  - Reste : campagne `mp-ambient` du 2026-10-15 (copie figée du commit `54087fb`, zombies vanilla, sans mode dieu) : lk.alert 2 FAIL : « alert raised once by a zombie near the home » (étape lk.facing : « lk-1 0 deg, lk-2 104 deg, lk-3 180 deg (max 60) ») et « a crowd of zombies beyond the alert distance leaves the group in its routine » (« alerts raised by zombies beyond the alert distance: expected 0, got 1 ») (`tools/autoclient/runs/20261015-120139-run-54087fb0f84f/run/server/20261015-100346-server.txt`) ; portes refermées à brancher (LK04) ; alerte non sauvegardée, aucune hors écran ; valeurs à recalibrer

- [ ] **LK05-T09** — Défense coordonnée du foyer
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK05-T08, LK06-T04
  - Fichiers : `LK_Defense.lua`
  - Faire : postes de défense du foyer occupés selon les rôles, tir ou mêlée depuis les postes, repli à l'intérieur si la menace est trop forte, renforts des membres proches, soins après l'attaque.
  - Idées : I6.1 (défense déclenchée par l'entrée dans le bâtiment), I6.3 (critères de repli), I6.4 (retrait tactique), I6.6 (repli collectif du chef) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : foyer défendu contre une petite horde sans comportement incohérent (sortie inutile, membres coincés) ; même déroulé pour deux observateurs.
  - Tests : suite en jeu + protocole.
  - Preuve : banc `tests/test_lk_defense.py` du 2026-10-12 (13 tests OK : postes pris selon les rôles et la menace, abris des non-combattants, repli au-delà de 3 × les combattants valides, renforts, laisse sans sortie inutile, même déroulé chez deux clients et sur deux mondes identiques, suite `lk.defense` sur doublures) ; run_all 58 étapes, luacheck 16/0 après correction d'une ligne longue de `LK_Config.lua` ; conception `docs/conception/defense.md` ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.defense PASS (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : lk.defense 2/2 (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.defense 2/2 avec étapes lk.positions du client 2 vertes (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`)
  - Reste : campagne `mp-ambient` du 2026-10-15 (copie figée du commit `54087fb`, zombies vanilla, sans mode dieu) : lk.defense 2 FAIL : petite horde « wounded member engaged a zombie beyond contact (went out to fight): expected 0, got 40 » ; camp « client rs_mp1 missed step 'lk.positions' within 15000 ms » (client 2 : « lk-11 no copy … ») (`tools/autoclient/runs/20261015-120139-run-54087fb0f84f/run/server/20261015-100346-server.txt`, `tools/autoclient/runs/20261015-120139-run-54087fb0f84f/run/client2/20261015-100347-steps.txt`). Abris au niveau du foyer seulement ; ni réparation ni barricade pendant l'attaque (LK14) ; soins = point d'appel `LivingKnox.Care.afterAttack` (LK07-T03).

- [ ] **LK05-T10** — Entretien du foyer : générateur, lumières, déchets, morts
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK05-T04, LK08-T06
  - Fichiers : `LK_Routines.lua`, `LK_Stock.lua`
  - Faire : corvées qui modifient le foyer : plein et réparation du générateur avec carburant et pièces du stock, lumière allumée en entrant dans une pièce alimentée, déchets ramassés et sang nettoyé, morts du groupe ou ennemis portés à une tombe et enterrés.
  - Idées : I3.5, I3.6 (voir `docs/idees-bandits-alife.md`)
  - Accepté si : chaque effet appliqué une seule fois et vu par deux clients ; matériaux consommés exactement ; rien hors du foyer.
  - Tests : suite en jeu + protocole.
  - Preuve : banc `tests/test_lk_upkeep.py` du 2026-10-12 (16 tests OK, solo et MP serveur + 2 clients : plein et réparation du générateur avec matériaux du stock retirés exactement, sang lavé avec dose de Javel, verre ramassé, lumière d'une pièce alimentée allumée la nuit, effet unique, interruption sans effet) ; `lk_meals`/`lk_routines`/`lk_chores` OK ; luacheck 16/0 ; conception `docs/conception/entretien.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.upkeep", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-175643-solo.txt`) ; campagne MP automatique du 2026-10-14 soir (serveur dédié + 2 clients, après les correctifs MP commits `826288c`, `ae252e5`, `7ff6143`, `778b940`, `862a942`) : lk.upkeep 2/2 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.upkeep 2/2 avec l'étape world.upkeep du client 2 verte (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`, `tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/client2/20261015-090723-steps.txt`)
  - Reste : campagne solo du 2026-10-15 : lk.upkeep « home upkeep from the stock » FAIL (« broken glass still there », `tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`) ; **morts portés à une tombe : non fait** (aucun chemin vanilla fiable avant LK07-T04 : `ISBuryCorpse` exige un cadavre saisi par un joueur). À vérifier en jeu : `IsoGenerator.new`, `sendItemStats` dans un meuble, `removeBlood` sur un serveur, `IsoRoom:getLightSwitches`. Lumières jamais éteintes ; générateur jamais démarré.

- [ ] **LK05-T11** — Production de nourriture : cueillette, pêche, potager
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK05-T05, LK08-T06
  - Fichiers : `LK_Routines.lua`, `LK_Stock.lua`
  - Faire : selon le foyer et la saison : cueillette en forêt ou en zone agricole avec les tables de cueillette vanilla (heure, météo, mois), pêche à l'aube et au crépuscule, potager arrosé avec l'eau et les outils du stock ; produits rangés au stock ; même production rattrapée hors écran.
  - Idées : I4.3, I4.4, I4.5 (voir `docs/idees-bandits-alife.md`)
  - Accepté si : aucun objet créé hors des tables vanilla ; produits retrouvés dans les conteneurs ; résultat cohérent à l'écran et hors écran.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_lk_food.py` du 2026-10-12 (18 tests OK, avec le vrai `forageSystem.lua` vanilla chargé : cueillette tirée des tables vanilla (mois, heure, météo) de façon reproductible, aucun objet hors des tables, dépôt au stock sans perte ni vol, même résultat à l'écran et hors écran, arrosage du potager avec l'eau du stock retirée exactement) ; run_all 65/65 ; luacheck 16/0 ; conception `docs/conception/nourriture.md` ; commit `54087fb` (récolte du potager mûr et pêche à l'aube et au crépuscule) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.forage 5/5, dont « a ripe plant of the home is harvested and its produce stored » et « fishers bring vanilla fish home at dawn » (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`) ; campagne solo-lk (`tools/autoclient/runs/20261015-135627-parallel-2-c6a500a78137`) : lk.forage tirages, cueillette, arrosage et récolte du potager PASS ; pêche mise de côté par l'utilisateur (SKIP)
  - Reste : MP : lk.forage à repasser après le correctif des suites (`fcb9657`) ; pêche reportée (décision du 2026-10-15) ; semis non fait

- [x] **LK05-T12** — Trajets qui contournent les potagers par points de passage
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK04-T06, LK02-T07
  - Fichiers : `LK_Directives.lua`
  - Faire : quand le trajet vers une destination traverse des plantes cultivées (ligne droite mesurée par `Directives.hazardsOnLine`), le serveur découpe la consigne en étapes intermédiaires qui contournent la zone dangereuse ; le chemin entre deux étapes reste celui du jeu (non exposé à Lua), le risque est réduit sans être supprimé.
  - Accepté si : un PNJ envoyé de l'autre côté d'un potager arrive sans détruire de plant dans la suite `lk.farm` étendue.
  - Tests : banc ; suite `lk.farm`.
  - Preuve : `LK_Directives.lua` : `Directives.planDetour` côté autorité (zone dangereuse mesurée par `hazardsOnLine` avec marge, boîte englobante des dangers proches de la ligne, coins élargis de 3 cases vérifiés chargés, libres et hors zone, 12 candidats déterministes, 3 étapes au plus, détour borné à +30 cases ; sinon trajet direct avec avertissement) ; consigne `move` avec champs facultatifs `w` (points) et `k` (étape), compatible avec l'ancien format ; `LK_Executor.lua` enchaîne les étapes et rapporte `k`, accepté une étape à la fois par l'autorité et republié (reprise par un nouveau propriétaire) ; `test_lk_directives.py` 29/29 ; suite `lk.farm` étendue (« trip across a garden row » : 5 plants alignés) ; `tests/run_all.py` vert le 2026-10-10 hors `plan-check` (deux tâches en cours en parallèle), luacheck 17/0, `check_case.py` PASS ; `docs/conception/consignes.md`, `neutralisation.md` ; LK08-T01 : commit `3cc21af` ; **en jeu solo le 2026-10-10** (`rstest-1010`) : `lk.farm` 4/5, fichier `20261010-165254-solo.txt` ; le test « trip across a garden row » échoue avant la traversée (`garden square 10606,9960 is not walkable` : rangée posée à un emplacement fixe occupé) : suite à corriger (LK05-T13) ; **en jeu solo le 2026-10-10** (`rstest-1010`) : `lk.farm` 5/5, fichier `20261010-172750-solo.txt` ; rangée de 5 plants posée à 5 cases à l’est, trajet découpé en 2 points de passage par le nord, arrivée sans aucun passage sur un plant ni à côté, plants vivants 5/5
  - Reste : risque réduit, pas supprimé (chemin vanilla entre deux points) ; départ ou destination dans le potager = trajet direct ; MP à la séance finale


- [x] **LK05-T13** — Suite `lk.farm` : rangée de potager posée sur un emplacement dégagé
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK05-T12
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/media/lua/shared/RST/suites/RST_LKFarm.lua`
  - Faire : constaté en jeu le 2026-10-10 (`20261010-165254-solo.txt`) : le test « trip across a garden row » pose ses 5 plants à un emplacement fixe (+5 cases à l'est) et échoue si une case est occupée (`garden square 10606,9960 is not walkable`). Chercher, autour du PNJ, une ligne dégagée (plusieurs directions et décalages, cases praticables et chargées pour la rangée, le départ et l'arrivée) avant de poser la rangée ; sinon SKIP motivé.
  - Accepté si : la suite trouve seule un emplacement sur un terrain ordinaire ; `lk.farm` 5/5 en jeu.
  - Tests : banc de la suite (`tests/test_rs_suites.py` ou équivalent) ; `lk.farm` en jeu.
  - Preuve : suite `lk.farm` : `gardenSite` cherche un emplacement dégagé (directions E, O, N, S ; rangée à 5, 4 puis 6 cases ; zone utile chargée, sans plante ni feu, départ, arrivée, rangée, coins et chemins de contournement praticables) avant toute modification du monde, sinon SKIP motivé ; journal `[LKF] garden row placed at …` ; `test_lk_directives.py` 34/34 (est bloqué → ouest, est non chargé et ouest bloqué → nord, aucun emplacement → `nil`) ; `tests/run_all.py` vert le 2026-10-10 hors `belt_radio` (dépôt BeltRadio), luacheck 17/0 et 0 ; LK11-T03 : commit `b0f59cf` ; **en jeu solo le 2026-10-10** (`rstest-1010`) : `lk.farm` 5/5, fichier `20261010-172750-solo.txt` ; rangée de 5 plants posée à 5 cases à l’est, trajet découpé en 2 points de passage par le nord, arrivée sans aucun passage sur un plant ni à côté, plants vivants 5/5
  - Reste : —
- [x] **LK05-T14** — Seuils de danger réglables dans les options sandbox
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK05-T08, LK05-T09, LK06-T04, LK06-T05
  - Fichiers : `media/sandbox-options.txt`, `Translate/*/Sandbox.json`, `LK_Config.lua`, `LK_Alert.lua`, `LK_Decisions.lua`, `LK_Defense.lua`, `LK_Zombies.lua`, `LK_Encounters.lua`
  - Faire : options sandbox `LivingKnox.*` pour les distances aujourd'hui figées dans le code : distance maximale d'un zombie qui déclenche l'alerte du groupe (nouveau seuil, aujourd'hui toute menace perçue), portée de l'alerte, rayon du cri pour un zombie, fuite d'un non-combattant (normale et apeurée), engagement d'un zombie par un combattant, rayon de défense du foyer et rapport de repli, danger de retraite, rayon des renforts, rayon des sommations ; valeurs par défaut plus courtes adaptées à un serveur chargé ; lecture par `getOptionByName` et sondage (base `load-warnings.md` : `SandboxVars` périmé en solo) ; option absente = valeur actuelle.
  - Accepté si : chaque seuil lu depuis les options (banc) ; un groupe face à une foule de zombies au-delà du seuil d'alerte reste dans sa routine.
  - Tests : banc ; suite en jeu `lk.alert` adaptée.
  - Preuve : banc `tests/test_lk_thresholds.py` du 2026-10-12 (17 tests OK : 12 options sandbox `LivingKnox.*` lues par `getOptionByName` à chaque appel, défaut et repli sur option absente ou invalide, zombie au-delà de `ZombieAlertDistance` ignoré par la cascade, l'alerte, la défense et l'engagement) ; `lk_alert` 22 OK (suite : foule de 50 zombies au-delà du seuil, aucune alerte ; contre-épreuve en échec sans le filtre) ; run_all 70/70 ; luacheck 16/0 ; simulateur `docs/simulateur-pnj.html` mis à jour ; conception `decisions.md` (Seuils de danger réglables) ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.alert", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-175002-solo.txt`) (après correctif de la suite `feb3aff`)
  - Reste : Solo validé le 2026-10-12. essai solo `RST.run({ suite = "lk.alert", tags = "world" })` dans une maison, endroit calme (ligne `[LKA] measure thresholds` avec les défauts, foule de 50 zombies sans alerte ; puis changer `ZombieAlertDistance` en cours de partie et relancer : effet immédiat). Seuils de besoin hors options.

- [x] **LK05-T15** — Un besoin élevé retient un membre au foyer, sauf si l'expédition y répond
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK05-T05
  - Fichiers : `LK_Expeditions.lua`
  - Faire : constaté en jeu le 2026-10-12 (`lk.meals`) : un membre à 95 de faim envoyé en expédition chercher des munitions. Écarter de l'équipe un membre dont un besoin atteint `NEED_HIGH`, sauf si l'expédition y répond.
  - Décisions (2026-10-12, utilisateur) : faim élevée admise seulement si la nourriture fait partie des manques cherchés, soif élevée seulement si l'eau en fait partie ; fatigue ou peur élevées écartent toujours ; le membre mange, boit ou dort au foyer à la place.
  - Accepté si : membre épuisé jamais dans l'équipe ; membre affamé parti seulement pour une expédition qui cherche de la nourriture.
  - Tests : banc.
  - Preuve : banc `tests/test_lk_expeditions.py` du 2026-10-12 (15 tests OK, dont `test_need_blocker_keeps_home_a_member_the_trip_does_not_help` (7 cas : faim/nourriture, faim/munitions, soif/eau, soif/nourriture, fatigue, peur, sous les seuils) et `test_tired_forager_stays_home_hungry_one_leaves_for_food` (équipe `m-4` seul)) ; `Ex.needBlocker`, `Ex.teamOf(g, gid, want)` ; conception `expeditions.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo lk.teamneeds 1/1 (fourrageur épuisé au foyer, affamé seulement pour la nourriture) (`20261013-202155-solo.txt`)
  - Reste : essai solo facultatif : panneau de debug (LK13-T14), fiche d'un fourrageur, fatigue 95 : il ne part plus ; faim 95 avec un stock sans nourriture manquante : il reste manger

- [x] **LK05-T16** — Seuils « blessé » et « apeuré » réglables dans les options sandbox
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK06-T07, LK05-T14
  - Fichiers : `LK_Config.lua`, `LK_Decisions.lua`, `sandbox-options.txt`, traductions `Sandbox`
  - Faire : les seuils qui rendent un membre inapte au combat (LK06-T07 : santé sous `WOUND_RATIO` = 0,5, peur >= `NEED_HIGH.fear` = 70) deviennent des options sandbox du mod, lues à chaque appel comme les seuils de danger de LK05-T14 (défaut = valeur actuelle, repli sur option absente ou invalide) ; simulateur `docs/simulateur-pnj.html` mis à jour.
  - Décisions (2026-10-12, utilisateur) : « Pour les seuils, il faut que ce soit des options de mod dans sandbox options ».
  - Accepté si : changer l'option change la décision au passage suivant ; défauts identiques au comportement actuel.
  - Tests : banc.
  - Preuve : banc `tests/test_lk_fitness.py` du 2026-10-12 (12 tests OK : options `LivingKnox.WoundedHealth` (10..90 %, défaut 50) et `LivingKnox.AfraidFear` (30..100, défaut 70) lues à chaque appel par `Config.danger` (`Config.FITNESS`), repli sur l'ancienne valeur avec avertissement ; défaut identique au comportement précédent ; changer l'option change la décision au passage suivant : combat ou retraite, fuite apeurée, repos du blessé, règle `fear`, départ en expédition) ; une option = une notion appliquée partout (`Decisions.woundRatio`, `fearHigh`, `needHigh` : inaptitude, règles `wound` et `fear`, défense du foyer (`VALID_HEALTH` retiré), expéditions, seuil affiché dans la fiche admin) ; traductions `Sandbox` EN/FR ; suite `lk.fitness` ; run_all 100/100 ; luacheck 16/0 ; conception `decisions.md` ; simulateur `docs/simulateur-pnj.html` ; base `load-warnings.md` (`option:setValue` en mémoire, hors bornes ignoré) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo lk.fitness 1/1 (`20261013-202155-solo.txt`)
  - Reste : essai solo : `RST.run({ suite = "lk.fitness" })` (1 PASS, lignes `[LKF] measure thresholds: WoundedHealth 50 -> ratio 0.5, AfraidFear 70 -> fear 70` puis `changed`) ; changer `AfraidFear` dans les options sandbox : un membre apeuré se remet à combattre. Restent fixes : retraite (0,35 et 85), reddition, faim, soif, fatigue (`WoundedHealth` sous 35 ou `AfraidFear` au-dessus de 85 : la retraite passe avant l'inaptitude).

- [x] **LK05-T17** — Joueur vu à travers un mur (suite `lk.senses`)
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK05-T01
  - Fichiers : `LK_Senses.lua`, `RST_LKSenses.lua`
  - Faire : constaté en jeu le 2026-10-12 (deux essais, joueur visible) : test « behind a wall » : case du PNJ choisie avec `LosUtil.lineClear` = `Blocked` depuis la case du joueur, mais la perception du PNJ donne `seen true` (`los 1`, `[LKS] measure behind a wall after 8000 ms: entry true, seen true, heard true`). Vérifier la symétrie de `lineClear` (sens PNJ -> joueur, positions flottantes, étage), la position réelle du corps au moment de la mesure, et la règle de vue de `Senses` ; corriger le mod ou la suite selon la cause.
  - Accepté si : derrière un vrai mur, le PNJ entend sans voir ; suite `lk.senses` 2/2 en jeu.
  - Tests : banc ; suite en jeu.
  - Preuve : diagnostic du 2026-10-12 : `LK_Senses` et la suite calculent la vue dans le même sens ; la suite (`siteFor`) retenait un couple `Blocked` seulement parce que le pas diagonal de `lineClear` frôlait l'angle d'un mur à côté d'une ouverture (`LosUtil.java:32-110`, `IsoGridSquare.java:5949-6044, 7606-7619` ; cuisine ouverte de la cellule 41_37 relevée dans les lotpacks) : un pas d'une case du joueur ou du PNJ suffit à rendre la ligne `Clear` ; suite `RST_LKSenses.lua` : site retenu seulement s'il est `Blocked` depuis toute sa marge vers toute celle du joueur, relecture des cases réelles et de la ligne au moment de la mesure (échec « moved » explicite) ; banc `tests/test_lk_senses.py` 26 OK (`WallCornerScanTests`, `SuiteWallSiteTests` : l'ancienne suite reproduit l'échec) ; luacheck 16/0 ; base `perception.md` (`lineClear` ni symétrique ni stable à une case près) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : lk.senses 2/2 dans une pièce close (`20261013-091108-solo.txt`)
  - Reste : essai solo : joueur visible, immobile, dans une pièce close (pas contre une ouverture) : `RST.run({ suite = "lk.senses", tags = "world" })` 2/2 (`[LKS] measure behind a wall … los Blocked`, `seen false`, puis entendu) ; sans pièce close à portée, le test du mur est ignoré. Hors périmètre : direction du corps 144° au lieu de 45° après `face` vers un joueur qui vient de bouger (banc)

- [ ] **LK05-T18** — Campement : le groupe se défend sur place contre les zombies
  - État : `testé solo`
  - Cible : `MP`
  - Dépend de : LK05-T09
  - Fichiers : `LK_Defense.lua`
  - Faire : décision de l'utilisateur du 2026-10-14 (LK05-T09) : un groupe en campement (foyer sans bâtiment) se bat sur place contre les zombies au lieu de rester sans défense : combattants en postes autour du camp, non-combattants regroupés au centre, mêlée et tir selon les portées `ZombieEngage*`, débordement et blessés comme la défense du foyer. Déclencheurs et seuils de LK05-T09 inchangés.
  - Accepté si : au banc : camp attaqué par 3 zombies = défense ouverte, combattants engagés dans leur portée puis retour aux places, défense close ; groupe logé dans un bâtiment inchangé.
  - Tests : banc (`tests/test_lk_defense.py`) ; suite `lk.defense` (cas campement) dans la campagne MP automatique.
  - Preuve : défense au camp en plein air : jusqu'à 8 postes en couronne à 3 cases du foyer, abris à 1 case pour blessés, apeurés, surnombre et repli ; déclencheurs, seuils, sorties et fin inchangés ; pas d'offensive à la fenêtre au camp ; banc `tests/test_lk_defense.py` 22 OK (`CampDefenseTests` 4, bancs de la maison inchangés) ; suite `lk.defense` second test « camp attacked by a small horde » (sur doublures) ; conception `defense.md` ; commit `66b5b10` ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : lk.defense 2/2, dont « camp attacked by a small horde: ring of posts, wounded at the centre, sortie and back, defense over » (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard2/20261015-094749-solo.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : lk.defense 2/2 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`)
  - Reste : campagne `mp-ambient` du 2026-10-15 (copie figée du commit `54087fb`, zombies vanilla, sans mode dieu) : lk.defense « camp attacked by a small horde » FAIL (« client rs_mp1 missed step 'lk.positions' within 15000 ms ») (`tools/autoclient/runs/20261015-120139-run-54087fb0f84f/run/server/20261015-100346-server.txt`)

- [x] **LK05-T19** — Entretien limité aux générateurs du groupe
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : LK05-T10
  - Fichiers : `LK_Routines.lua`
  - Faire : décision de l'utilisateur du 2026-10-14 (LK05-T10) : l'entretien (plein, réparation) ne touche plus que les générateurs du groupe (posés par le groupe ou situés dans le bâtiment de son foyer) ; un générateur d'un joueur dans la zone n'est plus rempli ni réparé.
  - Accepté si : au banc : générateur du groupe rempli et réparé ; générateur d'un joueur à proximité ni rempli ni réparé ; aucune autre corvée changée.
  - Tests : banc ; suite `lk.upkeep` dans la campagne MP automatique.
  - Preuve : générateur du groupe = marque ModData `LKGenerator` posée à l'aménagement du foyer (`Homes.adoptGenerators`), relue au relevé et à l'effet ; bancs `test_lk_upkeep.py` 20 OK et `test_lk_homes.py` 21 OK (générateurs d'un joueur dans la maison et au jardin intacts, générateur remplacé avant l'effet intact) ; suite `lk.upkeep` avec un générateur non marqué qui doit rester intact ; luacheck 15/0 ; base `power-and-lights.md` ; commit `83aefe5`; campagne MP complète du 2026-10-15 (client 2 actif, règle « les tests font foi ») : lk.upkeep 2/2 (générateur non marqué ni rempli ni réparé) (`tools/autoclient/runs/20261015-024734-mp-348bee78d4b7/server/20261015-004928-server.txt`)
  - Reste : foyer aménagé avant la tâche : aucun générateur marqué (entretien du générateur inactif)
