# Écarts entre le banc hors jeu et le jeu

Registre des défauts découverts **seulement en jeu** alors que les bancs hors jeu étaient verts. Il sert à mesurer ce
que le banc ne reproduit pas encore et à choisir quoi lui apprendre
([ADR du banc mimétique](../../architecture/decisions/adr-banc-mimetique.md), décisions D07 et D08 ;
plan [E19](../plans/E19-banc-mimetique.md)).

**Règle.** Tout échec d'une campagne en jeu reçoit une ligne ici, avec sa catégorie. Quand la catégorie le permet, il
est d'abord reproduit au banc par un test rouge, puis corrigé ; la colonne « Couvert par » nomme alors le test ou le
mécanisme du banc. Sinon elle dit « non reproductible » et pourquoi.

## Catégories

| | Écart | Mécanisme du banc qui le couvre |
|---|---|---|
| A | API Java absente, renommée ou de signature différente | doublures et appels contrôlés contre l'API du jeu (`E19-T01` à `E19-T03`) |
| B | API Java au comportement différent de la doublure | doublure corrigée d'après le Java, test qui prouve le refus (`E19-T03`) |
| C | Lua ou IA vanilla | vrai Lua vanilla chargé au banc (`E19-T04`) ; l'IA écrite en Java n'est pas simulée |
| D | Temps et ordre des événements | horloge fidèle et balayage des phases (`E19-T05`) |
| E | Monde réel (murs, ouvertures verrouillées, cases déchargées, zombies de la partie) | site réel rejoué (`E19-T08`) |
| F | Réseau (propriétaire du corps, ordre et zone d'envoi) | réseau en désordre, zone d'envoi (`E19-T06`) |
| G | Particularité de la VM Kahlua | banc Kahlua réel (`tests/test_kahlua.py`) |
| H | Rendu, animation, son, interface | non reproductible : validé en jeu |
| I | Défaut du test en jeu lui-même | suite jouée au banc sous balayage (`E19-T05`) |

## Registre

Inventaire du 2026-11-13, tiré des plans, des commentaires des suites en jeu et des commits ; les journaux de campagne
cités par ces sources n'ont pas été relus un par un. Les plus récents d'abord.

| Date | Suite ou tâche | Ce qui a cassé en jeu | Cat. | Couvert par |
|---|---|---|---|---|
| 2026-11-13 | `lk.meals` | heure de jeu changée entre la faim posée par la suite et la première décision du membre : repas abstrait du pas horaire, aucun objet pris | D | `test_lk_meals.py` `test_suite_lk_meals_passes_under_the_phase_sweep` (monde peuplé, phases `hour-3` et `hour-4`, `E19-T05`) |
| 2026-11-13 | `rs.observations` (témoins) | compte passé de 47 à 48 pendant une attente ; contrôle unique après un sommeil fixe, avant la passe | D | à couvrir (`E19-T05`) |
| 2026-11-13 | `rs.observations` (témoins) | témoin placé à 3 cases, placement par défaut qui suit le joueur | E | à couvrir (`E19-T08`) |
| 2026-11-13 | `lk.upkeep` | un garde en ronde tire sur un zombie pendant les tâches | E | à couvrir (`E19-T08`) |
| 2026-11-13 | `lk.windowsally` | un garde sort en ronde à l'aube et au crépuscule | E | à couvrir (`E19-T05`, heure du jour) |
| 2026-11-13 | `lk.forage` | le gardien du groupe de test part chercher l'eau | I | à couvrir (`E19-T05`) |
| 2026-11-12 | `lk.expedition` | un zombie à l'étage de la cuisine fouillée retient l'équipe | E | à couvrir (`E19-T08`) |
| 2026-11-12 | `rs.conversations` | lien du joueur lu une seule fois, trop tôt | I | à couvrir (`E19-T05`) |
| 2026-11-10 | chargement en 42.22 | `getGameMode()` rend un objet : concaténation refusée (état, journal d'actions, clé de session du pont) | A | à couvrir (`E19-T01`, `E19-T02`) |
| 2026-11-08 | `lk.windowsally` | fenêtre ouverte refermée en 7 s par le geste vanilla | C | non reproductible (geste vanilla) |
| 2026-11-08 | `lk.windowsally` | un membre sort avec une expédition et ne rentre jamais | E | à couvrir (`E19-T08`) |
| 2026-11-07 | `lk.talk.alone` | sur serveur dédié, `isFree` refuse toutes les cases autour du joueur | B | à couvrir (`E19-T03`) |
| 2026-11-07 | `lk.talk.alone` | PNJ apparu derrière le mur du foyer | E | à couvrir (`E19-T08`) |
| 2026-11-07 | `lk.chatter` | aucune discussion en 30 s : budget horaire déjà épuisé | D | à couvrir (`E19-T05`) |
| 2026-11-07 | `lk.traversal` | trajet par les portes de la maison coupé | E | à couvrir (`E19-T08`) |
| 2026-11-07 | `E18-T17` | identifiant d'objet tiré au hasard qui déborde du `short` vers les négatifs | B | à couvrir (`E19-T03`) |
| 2026-11-05 | `rs.mission.retrieve` | cadavre jamais reçu par un client téléporté (zone d'envoi) | F | à couvrir (`E19-T06`) |
| 2026-11-05 | `rs.npctalk` | commande et réponse livrées sans ordre | F | à couvrir (`E19-T06`) |
| 2026-11-05 | `lk.windowkill` | le zombie reste dehors, une seule frappe (IA vanilla) | C | non reproductible (IA vanilla) |
| 2026-11-05 | `lk.barricade` | les joueurs de test, solides, bouchent un couloir d'une case | I | à couvrir (`E19-T08`) |
| 2026-11-04 | `lk.guard` | zombie recyclé resté `useless` : corps inoffensif | B | à couvrir (`E19-T03`) |
| 2026-11-04 | `rs.voicedelivery` | à 65 cases, la case du dépôt est déchargée avant le ramassage | E | à couvrir (`E19-T08`) |
| 2026-11-04 | `rs.carnet.load`, `rs.npctalk` | PNJ posé derrière une cloison vitrée : sélection refusée | E | à couvrir (`E19-T08`) |
| 2026-11-04 | `rs.missionrewards` | 6,25 points reçus pour 25 accordés (multiplicateur vanilla ×0,25) | C | à couvrir (`E19-T03`, doublure d'`addXp`) |
| 2026-11-04 | `rs.missions.solo` | le test lisait un ancien champ de délai en temps réel | D | à couvrir (`E19-T05`) |
| 2026-11-04 | `lk.routines` | cueilleur debout toute la nuit | D | à couvrir (`E19-T05`) |
| 2026-11-04 | `lk.meals`, `lk.expedition` | zombies de la partie autour du foyer : alerte et défense pendant la scène | E | à couvrir (`E19-T08`) |
| 2026-11-04 | `lk.melee` | case du joueur impraticable pour un déplacement | E | à couvrir (`E19-T08`) |
| 2026-10-15 | `lk.handover` | écart de 3 s autour d'un changement de propriétaire pendant une escalade | F | à couvrir (`E19-T06`) |
| 2026-10-15 | `lk.traversal` | clé non retirée : le corps porte une autre clé du même bâtiment | B | à couvrir (`E19-T03`) |
| 2026-10-15 | `rs.relation` | corps posé derrière un mur de la maison | E | à couvrir (`E19-T08`) |
| 2026-10-15 | `lk.milestone` | case du PNJ encore chargée après 60 s sur le serveur | E | à couvrir (`E19-T08`) |
| 2026-10-14 | `lk.executor` | copie arrivée 4,3 cases derrière la cible | F | à couvrir (`E19-T06`) |
| 2026-10-12 | `LK06` | PNJ resté 7 s dans l'état vanilla « turnalerted » | C | non reproductible (états vanilla) |
| 2026-10-12 | `LK05` | ligne de vue « Blocked » alors que la perception dit « vu » | B | à couvrir (`E19-T03`) |
| 2026-10-11 | `LK04` | fenêtre ouverte : « expected 1 argument, got 2 » | A | à couvrir (`E19-T03`, nombre d'arguments) |
| 2026-10-11 | `LK04` | PNJ qui enjambe la fenêtre au lieu du portail (chemin vanilla) | C | non reproductible (chemins vanilla) |
| 2026-10-11 | `LK04` | aucune animation d'ouverture quand l'autorité ouvre une fenêtre | H | non reproductible |
| 2026-10-11 | `LK11` | réplique entendue, bulle non dessinée au-dessus du corps | H | non reproductible |
| 2026-10-11 | `LK03` | rapport d'état refusé en boucle après la sortie de zone | F | à couvrir (`E19-T06`) |
| 2026-10-11 | `E17` | « pont absent » affiché alors que le pont tourne | F | à couvrir (`E19-T06`) |

## Mesure

Au 2026-11-13 : 41 lignes, 1 couverte par un test du banc, 6 non reproductibles (catégories C et H), 34 à couvrir.
Mettre ce compte à jour à chaque tâche de `E19` terminée.
