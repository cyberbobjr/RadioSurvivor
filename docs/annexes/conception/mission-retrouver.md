# Mission « retrouver » (gabarit `retrieve_id`, E11-T05)

Brouillon du 2026-10-12. Code : `server/RadioSurvivor/RS_MissionRetrieve.lua` ; fonctionnement détaillé :
[carnet-implementation-04221.md](carnet-implementation-04221.md), « Gabarit retrouver ».

## Choix non tranchés par le plan (à confirmer)

Le plan dit seulement : « un cadavre ou un zombie porteur d'une carte d'identité nominative ; rapporter la carte au
donneur ; vérification par identifiant d'objet côté serveur ». Les choix ci-dessous sont les plus simples et les plus
proches du vanilla ; ils restent à confirmer par l'utilisateur.

1. **Cadavre, pas de zombie porteur.** Un cadavre vanilla (`RandomizedWorldBase.createRandomDeadBody`) reste où il est
   posé, garde son conteneur et sa ModData avec le chunk, et le jeu l'envoie lui-même aux clients
   (`GameServer.sendCorpse`, `RandomizedWorldBase.java:504-506`). Un zombie porteur se déplace, peut être
   virtualisé et perdre son inventaire, et demande de poser la carte à sa mort (`OnZombieDead`, piège du feu) : écarté
   pour l'instant (variante possible plus tard).
2. **Remise par le bouton « Livrer » du carnet**, pas par une phrase. L'échange de livraison de M01
   (`prepare_delivery` / `confirm_delivery`, à `DELIVERY_RANGE` du corps du demandeur) liste toutes les cartes
   d'identité du joueur ; le serveur n'admet que l'objet dont l'identifiant est celui de la carte posée. Le joueur
   choisit explicitement l'objet et reçoit un refus motivé (`WrongCard`) pour une autre carte, critère d'acceptation
   de la tâche.
3. **Fiches de PNJ seulement.** Une voix radio n'a pas de corps : on ne peut rien lui « rapporter ». Sa liste fermée
   (`RS_MissionVoice.TEMPLATES`, et celle du pont) reste `scout`.
4. **Offert seulement si `RandomizedWorldBase` est exposée** (toujours vrai en jeu 42.21, `LuaManager.java:2474`) :
   un environnement qui ne sait pas créer de cadavre n'offre pas une mission impossible.
5. **Carte `Base.IDcard` nommée d'après le mort** par la méthode vanilla `InventoryItem.nameAfterDescriptor`
   (`InventoryItem.java:4768-4775`, celle qu'applique le jeu aux papiers d'un mort) ; le nom n'est qu'un affichage,
   jamais une preuve (deux cartes peuvent porter le même nom).
6. **Pose différée** au sondage du carnet (une seconde, au plus une tentative toutes les 5 s par mission) quand la case
   du point est chargée et que le bâtiment a passé ses histoires vanilla (base `world-placement.md`, « Quand poser »
   et « Placement différé »). Une pose réussie est enregistrée dans l'état privé aussitôt (pas de second corps après
   un redémarrage) ; un arrêt brutal entre la pose et la sauvegarde peut en poser un second (carte différente,
   l'ancienne refusée).

## Sources

- Java 42.21 : `RandomizedWorldBase.java:444-507` (cadavre, faux mort une fois sur 20, `sendCorpse`),
  `BuildingDef.java:389-399` (`isFullyStreamedIn`, serveur compris), `GameServer.java:2239-2247` et
  `network/fields/ContainerID.java:170` (ajout d'un objet au conteneur d'un cadavre transmis aux clients),
  `InventoryItem.java:4768` (nom d'après le descripteur).
- Base : `world-placement.md` (faux cadavres, placement différé, suivi d'un objet par `getID()`), `api-42-21.md`
  (pièces d'identité nominatives), `quest-building-blocks.md` (objet dans un cadavre).
