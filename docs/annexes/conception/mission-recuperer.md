# Mission « récupérer » et caches (gabarit `recover`, action `place_cache`, E11-T06)

Brouillon du 2026-10-12. Code : `server/RadioSurvivor/RS_MissionRecover.lua`, `server/RadioSurvivor/RS_Caches.lua` ;
fonctionnement détaillé : [carnet-implementation-04221.md](carnet-implementation-04221.md), « Caches et gabarit
récupérer ».

## Choix non tranchés par le plan (à confirmer)

Le plan dit seulement : « cache tirée d'une table serveur fermée, posée au chargement de la case (placement différé) ;
la porter à un dépôt ; une cache par mission ; la cache n'apparaît qu'une fois, même après redémarrage ; le dépôt
vérifie l'objet marqué ». Les choix ci-dessous sont les plus simples et les plus proches du vanilla ; ils restent à
confirmer par l'utilisateur.

1. **La cache est un sac de sport vanilla** (`Base.Bag_DuffelBag`) posé au sol dans le bâtiment tiré, marqué par une
   ModData `RS_Cache = <mission>` et rempli d'une des quatre tables fermées de `RS_Config.Caches` (`food`, `medical`,
   `ammo`, `tools`, contenus fixes). Un sac se porte sans outil ; une caisse (meuble) demanderait le démontage.
   La table est tirée par le serveur (même graine que le lieu) et annoncée dans l'offre (`cache`).
2. **Dépôt = le foyer du groupe du demandeur**, lu par `RS_NPCProvider.presence(id)` (Living Knox : `home` du
   groupe), zone carrée de 7 × 7 cases autour du point (`depotRadius = 3`), même étage (0 si le moteur ne le dit
   pas). Le sac compte posé au sol dans la zone ou rangé dans un conteneur d'un objet de la zone (caisse, étagère,
   autre sac). Un PNJ sans foyer connu ne propose pas cette mission. **Conséquence** : le cercle « Dépôt » tracé sur
   la carte du participant révèle le foyer du groupe à un joueur déjà « connu » du PNJ (les offres ne partent qu'au
   stade `acquainted`) ; le pont, lui, ne reçoit jamais ce point.
3. **Vérification par identifiant d'objet** (`InventoryItem:getID()` du sac posé, gardé dans l'état privé) : un autre
   sac, même du même type, avec la même marque ModData et le même contenu, ne compte pas. Le **contenu n'est pas
   vérifié** : un joueur peut vider le sac avant de le déposer.
4. ~~**Réussite automatique** au sondage du serveur~~ : le sac trouvé au dépôt par le sondage (une fois par seconde,
   case du dépôt chargée, sans bouton « Livrer ») est retiré du monde (il revient au groupe) et remplit l'objectif.
   Remplacé le 2026-10-14 (décision de l'utilisateur, E11-T13) : l'objectif rempli met la mission « à rapporter » ; elle ne réussit que quand un participant le dit au PNJ demandeur (intention `report_done` du modèle revérifiée par le serveur, ou bouton « Rendre compte » près de lui) ; demandeur mort avant : `cancelled_dead`. Voir `docs/specifications-techniques/protocole-carnet-v2.md`, « Compte rendu au demandeur ». Lot commun réclamé ensuite près du demandeur, comme M01.
5. **Pose une seule fois** : `placing` sauvegardé avant de créer le sac, puis `placed` et l'identifiant aussitôt après ;
   un arrêt entre les deux fait chercher d'abord, dans l'emprise du bâtiment, un sac au sol portant la marque de la
   mission (repris), sinon reposer (le chunk n'avait pas été sauvegardé avec lui). Base : `world-placement.md`,
   « Créer ou retirer des objets d'après un registre en fichier ». Une mission échouée, expirée ou annulée ne pose plus
   rien ; la cache déjà posée reste dans le monde.
6. **Fiches de PNJ seulement** pour le gabarit (une voix radio n'a pas de dépôt ; `RS_MissionVoice.TEMPLATES` reste
   `scout`).
7. **Action de voix `place_cache { table }`** : cache de la dernière mission donnée par cette voix à l'appelant (ouverte,
   sinon sa dernière réussite : « cache sur place » de la décision E11-T08), au bâtiment de cette mission, une par
   mission. Refus : `no_mission`, `cache_exists`, `no_character`, `storage`, `no_place`, `bad_params` (table hors de la
   liste fermée). **Le pont ne la propose pas encore** au LLM (`bridge/radio_bridge.py`, `EXECUTABLE_ACTIONS`, hors du
   périmètre de cette tâche) : seul le serveur sait l'exécuter.
8. **Plafond d'offres porté à 6** (`RS_Config.MAX_OFFERS`, `bridge/npc_protocol.py` `MAX_OFFERS`) : cinq gabarits de
   PNJ existent, `signal` (E11-T07) fera le sixième. Le serveur garde les premières offres dans l'ordre
   d'enregistrement des gabarits et n'interroge pas les suivants. Une offre pèse 350 à 450 caractères de JSON dans le
   prompt, soit 90 à 130 jetons : environ 800 jetons de plus au plus par requête d'un PNJ connu.

## Limites

- Le sac au sol est soumis à `HoursForWorldItemRemoval` si son type figure dans la liste de retrait du bac à sable
  (pas par défaut) ; un sac retiré par le jeu rend la mission impossible jusqu'à son expiration.
- Un monde revenu à une sauvegarde plus ancienne que l'état privé peut perdre le sac (jamais le dédoubler).
- Une cache posée par `place_cache` n'apparaît pas dans le carnet (aucune ligne de page Missions ni d'historique).

## Sources

- Java 42.21 : `IsoGridSquare.java:5200-5265` (`AddWorldInventoryItem(item, x, y, z, true)` transmis aux clients),
  `IsoGridSquare.java:5072-5098` et `RemoveItemFromSquarePacket.java:101-142` (`transmitRemoveItemFromSquare` : retrait
  d'un objet au sol sur le serveur et chez les clients), `InventoryContainer.java:60-68` (contenu du sac sauvegardé
  et transmis avec lui), `InventoryItem.java:415-419` (`hasModData`, `getModData`).
- Base : `world-placement.md` (placement différé, objet préparé posé au sol, registre et marque ModData, suivi d'un
  objet par `getID()`).
