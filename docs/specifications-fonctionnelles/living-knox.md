# Groupes de survivants Living Knox (F20 à F31)

Vue joueur du moteur de PNJ Living Knox intégré au mod. Fiches de conception par sous-système :
[annexes/conception/](../annexes/conception/README.md) ; guide joueur : [Utilisation](../wiki/fr/03-utilisation.md), section 3.

## F20 — Groupes et foyers

- 3 à 5 groupes par serveur (`GroupCount`, défaut 4) de 4 à 8 membres (`GroupSizeMin`, `GroupSizeMax`) : colons
  amicaux, neutres méfiants, pillards hostiles (poids `WeightSettlers`, `WeightNeutrals`, `WeightRaiders`).
- Chaque groupe a un type, une histoire, un chef, des rôles (combattants, ouvriers, médecin, éclaireur…), un foyer et
  un moral. Colons et neutres vivent dans un vrai bâtiment aménagé (couchages, lampe, barricades) ; pillards dans un
  camp. Les réserves sont de vrais objets dans les conteneurs du foyer, avec rationnement.
- Conception : [groupes.md](../annexes/conception/groupes.md), [foyers.md](../annexes/conception/foyers.md), [stock.md](../annexes/conception/stock.md).

## F21 — Corps et gestes humains

- Vêtements, peau, cheveux et arme d'humain ; aucun comportement de zombie ; les PNJ apparaissent debout et montrent
  leurs gestes. Corps de « joueur réanimé » (décision du 2026-10-09).
- Conception : [corps-et-animations.md](../annexes/conception/corps-et-animations.md), [apparence.md](../annexes/conception/apparence.md),
  [neutralisation.md](../annexes/conception/neutralisation.md).

## F22 — Exécution multijoueur

- Le serveur donne les consignes ; le corps est exécuté par le client propriétaire, transféré entre joueurs, et ses
  gestes sont relayés aux joueurs proches. Conception : [consignes.md](../annexes/conception/consignes.md).

## F23 — Déplacement et obstacles

- Portes avec de vraies clés, fenêtres ouvertes avec le geste du joueur, clôtures enjambées, escaliers, sortie d'une
  maison par une porte, détour autour d'une porte refusée ; les pillards forcent barricades et portes ; blocages
  détectés ; potagers évités. Conception : [deplacement.md](../annexes/conception/deplacement.md).

## F24 — Perception, besoins, décisions et routines

- Vue, ouïe et lumière ; besoins (faim, soif, fatigue, peur) ; objectifs du groupe notés chaque heure et cascade de
  priorités par membre ; sommeil, garde, ronde, corvées, repas pris dans le stock réel ; alerte et défense du foyer ;
  entretien du générateur ; expéditions de fouille et de cueillette.
- Seuils réglables : `ZombieAlertDistance`, `AlertReach`, `AlertShoutZombie`, `FleeDistance`, `FleeDistanceAfraid`,
  `DefenseRadius`, `DefenseWithdrawRatio`, `RetreatDangerDistance`, `ReinforcementRadius`, `WarnHomeRadius`,
  `WarnGroupRadius`, `WoundedHealth`, `AfraidFear`.
- Conception : [perception.md](../annexes/conception/perception.md), [besoins.md](../annexes/conception/besoins.md),
  [decisions.md](../annexes/conception/decisions.md), [routines.md](../annexes/conception/routines.md),
  [alerte.md](../annexes/conception/alerte.md), [defense.md](../annexes/conception/defense.md),
  [expeditions.md](../annexes/conception/expeditions.md). Simulateur des seuils : [simulateur-pnj.html](../annexes/maquettes/simulateur-pnj.html).

## F25 — Combat

- Cible choisie selon l'attitude (un groupe neutre ne tire jamais le premier), mêlée, tir avec de vraies munitions,
  PNJ contre zombies dans les deux sens (`ZombieEngage*` par rôle), retraite, reddition et appel à l'aide.
- Conception : [combat.md](../annexes/conception/combat.md), [cibles.md](../annexes/conception/cibles.md),
  [fuite-reddition.md](../annexes/conception/fuite-reddition.md), [zombies.md](../annexes/conception/zombies.md).

## F26 — Santé, mort et butin

- Blessures et saignement, soins par le médecin avec un vrai pansement, une seule mort, un cadavre qui ne se relève
  jamais, le vrai butin du PNJ sur le corps. Conception : [sante.md](../annexes/conception/sante.md).

## F27 — Vie hors écran et relève

- Les groupes vivent loin des joueurs ; stock et fortification rattrapent le temps passé à l'arrivée d'un joueur ; un
  groupe décimé laisse ses traces et un autre s'installe ailleurs après 2 à 5 jours (`ReliefDaysMin`, `ReliefDaysMax`).
- Conception : [simulation.md](../annexes/conception/simulation.md), [traces.md](../annexes/conception/traces.md).

## F28 — Récits

- Une histoire et un journal de récit par groupe ; un carnet laissé au foyer abandonné, une note sur le chef mort ;
  enrichissement par le LLM quand le pont tourne. Conception : [recits.md](../annexes/conception/recits.md),
  [journal.md](../annexes/conception/journal.md).

## F29 — Interactions avec les joueurs

- Attitude par groupe et par joueur, sommations avant tout tir, demandes d'aide, troc direct, vengeance après un
  meurtre (`RevengeDelayHours`), raids annoncés des pillards (`RaidsEnabled`, `RaidDays`), parole de proximité (F05) et
  missions (F07).
- Conception : [attitude.md](../annexes/conception/attitude.md), [sommations.md](../annexes/conception/sommations.md),
  [aide.md](../annexes/conception/aide.md), [troc.md](../annexes/conception/troc.md), [vengeance.md](../annexes/conception/vengeance.md),
  [raids.md](../annexes/conception/raids.md).

## F30 — API pour RadioSurvivor

- Lecture des groupes, événements publics, demandes de ressources pour les missions, journal de récit lisible par la
  radio. Contrat : [api-living-knox.md](../specifications-techniques/api-living-knox.md).

## F31 — Fortification progressive

- Plan de fortification par foyer ; les bâtisseurs barricadent portes et fenêtres puis montent murs et palissades avec
  les vrais matériaux du stock, et réparent après une attaque. Conception : [fortification.md](../annexes/conception/fortification.md),
  [entretien.md](../annexes/conception/entretien.md).
