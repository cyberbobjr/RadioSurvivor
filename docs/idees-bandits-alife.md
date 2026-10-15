# Idées de comportement reprises de Bandits! et de Project A-Life

Relevé du 2026-10-08, à la demande de l'utilisateur (« reprends les meilleures idées »). Copies lues en lecture seule : Bandits! (Workshop `3268487204`, variante `42.20`) et Project A-Life (Workshop `3803984183`, `modversion=1.3.15`). Les sources servent seulement à vérifier une idée et se revérifient après une mise à jour de ces mods.

**Règle.** On reprend des **idées de jeu** (comportements, mécanismes, enchaînements visibles par le joueur), jamais du **code** : rien n'est copié, traduit ni paraphrasé, et les deux mods restent « tous droits réservés ». Les valeurs chiffrées citées sont des ordres de grandeur de départ, à recalibrer par nos propres essais. Chaque tâche qui met en œuvre une idée la conçoit à partir du Java et du Lua vanilla 42.21 (voir `docs/plan/README.md`, règles Living Knox).

Abréviations : **B** = Bandits!, **A** = A-Life. Chemins B relatifs à `mods/Bandits/42.20/media/lua/`, chemins A relatifs à `mods/ProjectALifeNPCs/42.20/media/lua/`. Lignes approximatives.

## I1 — Décision

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I1.1 | Cascade de priorités fixe par PNJ : réaction à une arme braquée, menace (combat ou repli), renfort demandé, comportements par priorité, recherche de la dernière position connue, enquête sur un bruit, programme de fond, attente | A `server/ProjectALife/Decisions/ALifeDecisionLoop.lua:482-842` | LK05-T02 |
| I1.2 | Comportements en registre trié par priorité, autorisés ou interdits par rôle : un rôle = une liste de comportements permis | A `shared/ProjectALife/Behaviours/ALifeModuleRegistry.lua:101-230` | LK05-T02, LK08-T02 |
| I1.3 | États courts à échéance : la décision n'est recalculée qu'à l'échéance ou sur interruption (bruit, menace) | A `ALifeDecisionLoop.lua:1009-1112` | LK05-T02 |
| I1.4 | Hasard déterministe tiré d'une empreinte stable du PNJ ou du groupe : même comportement quelle que soit la machine qui simule | A (panique, postes, routines) | LK05-T02 |
| I1.5 | Budget de réflexion selon la distance aux joueurs et le combat, mesuré par tick | A `ALifeDecisionLoop.lua:1312-1498` | LK05-T02, LK13-T02 |
| I1.6 | Choix de tâche d'un groupe hors écran par priorités : renfort, repos de nuit, fortifier si le ravitaillement suffit, piller s'il manque, patrouiller, voyager | A `server/ProjectALife/Offline/ALifeOfflineDirector.lua:629-740` | LK05-T02, LK09-T01 |

Synthèse retenue pour `LK05-T02` : **objectifs du groupe notés** (utilité, long terme, notre ajout : A et B n'ont aucun besoin réel) **+ cascade de priorités par membre** (court terme, I1.1 à I1.3).

## I2 — Perception et vigilance

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I2.1 | Repérage selon la lumière de la case de l'intrus, plus fort s'il court, plus faible s'il se faufile, plus fort de près | B `client/BanditUpdate.lua:64-85` | LK05-T01 |
| I2.2 | Vigilance selon l'activité (endormi ≪ occupé < repos < garde) ; un membre reste sentinelle à pleine vigilance | B `ZombiePrograms/ZPCamper.lua:24-90` ; A `shared/ProjectALife/Senses/ALifeAwareness.lua` | LK05-T01, LK05-T03 |
| I2.3 | Indices de présence humaine (moteur, générateur, barricades, constructions) qui s'accumulent par zone et déclenchent une fouille | A `server/ProjectALife/Senses/ALifeClues.lua:1-33, 308-401` | LK05-T08 |
| I2.4 | Dernière position connue partagée par le groupe, puis recherche en spirale ; points d'enquête sur bruit ou cri | A `ALifeDecisionLoop.lua:600-650`, `Senses/ALifeInvestigation.lua` | LK05-T08 |

## I3 — Routines et vie du foyer

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I3.1 | Journée type (sommeil, trois repas, garde), **horaires décalés** par membre pour qu'une veille de nuit existe (défaut de B) | B `ZPCamper.lua:20-70`, `ZPDefend.lua:38-75` ; A `Behaviours/ALifeModuleStances.lua:840-905` | LK05-T03 |
| I3.2 | Laisse autour du foyer : l'errance et les rondes restent dans un rayon du foyer | A `Decisions/ALifeRoutines.lua:14-60, 274-315` | LK05-T03 |
| I3.3 | Maison tenue la nuit : calme, réveil si un intrus approche des murs, nettoyage de la cour à l'aube | A `Behaviours/ALifeModuleNightHold.lua:14-22` | LK05-T03 |
| I3.4 | Gestes au repos (toux, cigarette, front essuyé…) reliés à la personnalité et aux traits | B `shared/BanditPrograms.lua:453-495` | LK05-T04 |
| I3.5 | Entretien : déchets ramassés puis vidés, sang nettoyé, morts portés à une tombe et enterrés, lumière allumée en entrant dans une pièce alimentée | B `BanditPrograms.lua:742-940`, `ZPBandit.lua:35-67` | LK05-T10 |
| I3.6 | Générateur : plein sous un seuil (éteindre, remplir, rallumer), réparation avec des pièces réelles, pas de second générateur sur une case déjà alimentée | B `BanditPrograms.lua:547-646` | LK05-T10 |
| I3.7 | Nourriture périssable rangée au congélateur puis au réfrigérateur | B `BanditPrograms.lua:944-981` | LK08-T06 |
| I3.8 | Conversations à plusieurs entre membres, à tours de parole, interrompues par le combat ; pause de patrouille assise en cercle | A `shared/ProjectALife/Audio/ALifeGossip.lua:257-900`, `Behaviours/ALifeModulePatrolRest.lua:12-23` | LK11-T04 |

## I4 — Nourriture et ravitaillement

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I4.1 | Pillage d'un bâtiment choisi par le chef, conteneurs **réservés** pour que deux membres ne fouillent pas le même, charge bornée, retour au dépôt, repos | A `Behaviours/ALifeModuleScavengeRun.lua:17-30, 115-200, 410-530` | LK05-T05 |
| I4.2 | Objets cherchés selon les manques du stock (catégories et tags du jeu, pas de mots-clés de texte) | A `Loot/ALifeScavenging.lua:85-155` (idée), écart volontaire | LK05-T05 |
| I4.3 | Cueillette en forêt ou en zone agricole, de jour, selon la météo, avec les tables de cueillette vanilla | B `ZPCompanion.lua:260-301` (inactif) | LK05-T11 |
| I4.4 | Pêche à l'aube et au crépuscule au point d'eau le plus proche | B `ZPCompanion.lua:205-258` (inactif) | LK05-T11 |
| I4.5 | Arrosage : arrosoir du stock rempli au point d'eau, rien sous la pluie | B `BanditPrograms.lua:648-737` (inactif) | LK05-T11 |
| I4.6 | Fouille des corps après un combat, puis des meubles de la pièce, pour se réarmer | B `BanditPrograms.lua:331-451` ; A `Behaviours/ALifeModuleSearch.lua:209` | LK06-T05 |

## I5 — Stock

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I5.1 | Index des objets par conteneur du foyer, rescanné progressivement ; conteneur le plus proche qui contient un objet voulu | B `client/BanditPlayerBase.lua:20-480` (inactif) | LK08-T06 |
| I5.2 | Stock surveillé : contenu attendu mémorisé, vol hors combat constaté et puni | A `server/ProjectALife/Outposts/ALifeOutpostTheft.lua` | LK08-T06, LK11-T03 |
| I5.3 | Dons sur demande tirés du stock, au plus une demande par groupe et par période, connue de tous les membres | A `Talk/ALifeTalkSupplies.lua` | LK11-T06 |

## I6 — Défense et combat

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I6.1 | Défenseurs déclenchés par l'entrée d'un intrus dans **leur** bâtiment, pas à distance | B `ZPDefend.lua:22-112` | LK05-T09 |
| I6.2 | Annonces de position de l'intrus (« dedans », « à l'étage », « dans la cuisine ») | B `shared/Bandit.lua:1336-1365` | LK05-T08 |
| I6.3 | Critères de repli : plus de munitions, peur d'une arme braquée ou d'un tir, santé basse, épuisement ; réengagement plus tard | A `Fear/ALifeSurvival.lua:9-16, 97-121` | LK05-T09, LK06-T05 |
| I6.4 | Retrait tactique sur encerclement ou rafale de coups : se cacher dans une pièce, revenir par un autre côté | A `Fear/ALifeModuleWithdraw.lua:11-40, 305-330` | LK05-T09 |
| I6.5 | Fuite pondérée par la proximité de chaque menace, avec déviation pour ne pas rester figé ; blessé qui fuit **vers le foyer** | B `BanditUpdate.lua:1352-1440`, `ZPBandit.lua:234-267` | LK06-T05 |
| I6.6 | Chef de section : repli collectif après des pertes ; à sa mort, dispersion brève puis succession | A `Behaviours/ALifeModuleLeader.lua:8-21, 145-230, 364-433` | LK05-T09, LK08-T01 |
| I6.7 | Tempérament qui règle l'agressivité ; un novice ne tire pas le premier ; agression contre un membre mémorisée par tout le groupe | A `Decisions/ALifeRisk.lua:60-160` | LK06-T01 |
| I6.8 | Fenêtres ouvertes par un amical, brisées par un hostile ; porte verrouillée détruite seulement par un hostile | B `BanditUpdate.lua:700-720, 800-850` | LK04-T03, LK04-T04 |
| I6.9 | Spécialités de combat : éclaireur à l'ouïe fine, casseur de barricades | B `ZPBandit.lua:69-129` | LK08-T02 |
| I6.10 | Morsure : chute, infection qui progresse, transformation ; drame pour le groupe | B `BanditUpdate.lua:1621-1680, 489-527` | LK06-T04, LK07-T03 |
| I6.11 | Reddition comme issue non violente | B `ZPBandit.lua:269-281` (inactif) | LK06-T05 |

## I7 — Santé

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I7.1 | Bandage après le combat qui consomme un bandage ou un drap ; le médecin soigne les autres | A `Behaviours/ALifeModuleHealing.lua`, `ALifeModuleConducts.lua:158-225` | LK07-T03 |
| I7.2 | Endurance : pauses d'épuisement après la course, halètement audible | B `BanditUpdate.lua:443-487` | LK07-T02 |
| I7.3 | Poches du mort qui racontent son métier et sa personnalité, avec ses **vrais** objets | B `Bandit.lua:940-1230` (idée) | LK07-T05 |

## I8 — Groupes, rôles et foyers

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I8.1 | Rôles (médecin, cuisinier, réparateur, éclaireur, radio…) qui ouvrent des comportements ; traits rares (fumeur, alcoolique, maniaque de la propreté) qui touchent gestes, besoins et répliques | B `Bandit.lua:49-65`, `BanditServerSpawner.lua:389-405` ; A `Talk/ALifeDialogueRoles.lua:7-31` | LK08-T02 |
| I8.2 | Pas d'installation dans un bâtiment visité récemment par un joueur | B `BanditServerSpawner.lua:858-870` | LK08-T03 |
| I8.3 | Foyer lisible de l'extérieur : rez-de-chaussée barricadé, rideaux tirés, lumière | B `BanditServerSpawner.lua:842-958` | LK08-T04 |
| I8.4 | Cycle de vie d'un foyer : renforts demandés sous la moitié de l'effectif, abandon après une garnison morte sans joueur proche | A `Outposts/ALifeOutpostDirector.lua:23-66, 1363-1368, 1640-1660` | LK09-T04 |
| I8.5 | Planches réparties sur les ouvertures pour en couvrir le plus possible, entrée laissée dégagée | A `Outposts/ALifePlanks.lua`, `Behaviours/ALifeModuleFortify.lua:13-19` | LK14-T03 |
| I8.6 | Foyers qui se racontent par leur décor (cabane de chasseur, tente de médecin…) | B `shared/BanditBases/Scenes/*` (inactif) | LK10-T04 |

## I9 — Hors écran et relations

| Id | Idée | Source | Tâche |
|---|---|---|---|
| I9.1 | Combat abstrait entre groupes (force selon santé, armes et moral, part d'aléa), jamais près d'un joueur ; groupe vaincu retrouvé en cadavres | A `Offline/ALifeOfflineCombat.lua:14-80, 229-260` ; B `server/BanditServerWanderers.lua:513-725` | LK09-T05 |
| I9.2 | Avertissements gradués à l'approche d'un foyer, réaction à une arme braquée avec délai de tolérance | A `Behaviours/ALifeModuleCareful.lua:12-21`, `Fear/ALifeThreatWatch.lua:6-30, 190-250` | LK11-T02 |
| I9.3 | Témoins d'une agression : l'attitude change envers **l'agresseur seul** (défaut de B : envers tous les joueurs) | B `client/BanditPlayer.lua:82-125` | LK11-T03 |
| I9.4 | Réputation qui peut aussi s'améliorer (défaut de A : elle ne fait qu'empirer) | A `Decisions/ALifeReputation.lua:278-315` (écart volontaire) | LK11-T03 |
| I9.5 | Voix fixe par individu, répliques par situation avec probabilité et délai, sous-titre coloré selon l'attitude | B `Bandit.lua:3-19, 1266-1334` | LK11-T04 |
| I9.6 | Vengeance différée et annoncée après la perte d'un membre, abandonnée après plusieurs échecs | A `server/ProjectALife/Offline/ALifeRevenge.lua:17-29, 100-236` | LK11-T05 |
| I9.7 | Raids d'un groupe pillard précédés d'éclaireurs qu'on peut éliminer ; cible choisie par les signes d'occupation de la base du joueur | A `World/ALifeRaidDirector.lua:11-30`, `World/ALifeBaseHeat.lua:4-16, 91-132` | LK11-T07 (à décider) |

## Écarté

- IA exécutée chez chaque client, effets confiés au joueur le plus proche (B) ; voix et portée calculées pour le seul joueur local (B).
- Objets, soins, renforts, vengeurs ou raids créés à partir de rien, ou surgissant près du joueur (A, B).
- Matérialisation qui tue tous les zombies alentour (B) ; saignement et infection liés à la fréquence d'images (B).
- Mêmes horaires pour tout le groupe, sans veille de nuit (B).
- Hostilité appliquée à tous les joueurs (B) ; réputation qui ne fait qu'empirer, rancunes effacées à la mort du joueur (A).
- Faim, soif et cigarette seulement animées (A) ; panique figée par l'identifiant (A) ; tir aveugle vers la dernière position (A) ; recherche d'objets par mots-clés (A).
- Nouvelles identités à chaque matérialisation (A) ; commandes client sans contrôle d'administrateur (B).
- Pression démographique et dizaines de groupes (A) : contraire au choix de 3 à 5 groupes (LK00).
