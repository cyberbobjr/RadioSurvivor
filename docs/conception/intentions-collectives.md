# Chef du groupe et intentions collectives du carnet (E10-T02)

Brouillon du 2026-10-12. Code : `server/RS_Carnet_Server.lua` (`talk`, `reply`, `Server.collectiveBinding`,
`Server.collectiveCheck`), `shared/RadioSurvivor/RS_LivingKnox.lua` (`composition`, `decide`, décisions du contexte),
`shared/RadioSurvivor/RS_NPCProvider.lua` (opérations facultatives), `server/LivingKnox/LK_API.lua`
(`API.composition`), `bridge/npc_protocol.py` (`collective_prompt`). Contrat : [protocole-carnet-v2.md](../protocole-carnet-v2.md),
« Chef du groupe et intentions collectives (E10-T02) » ; API : [api.md](../api.md), `API.composition`.

## Problème

Une décision qui engage tout un groupe Living Knox vient de son chef (registre `LK_Groups`, succession I6.6 déjà
codée) ; un membre ordinaire peut en parler mais renvoie au chef ; une réponse du modèle arrivée après une mort ou une
succession ne doit rien appliquer (E10-T02 ; points d'appel pour E09-T05 et E10-T04).

## Choix (le plus simple, à confirmer)

1. **Intention collective = mission de groupe** : une offre `kind = supply` (besoin réel du groupe, E17-T03 /
   LK12-T03) et son acceptation en parlant (`accept` d'une mission qui porte `supply`). Les autres gabarits (scout,
   clear, retrieve, recover) restent des missions personnelles du PNJ, offertes par tout membre connu. L'accord de
   faction d'E09-T05 n'est pas fait : il appellera `Server.collectiveBinding` à la demande et `Server.collectiveCheck`
   à la réponse.
2. **Membre ordinaire** : le serveur retire les offres `supply` de son catalogue et ne met pas `acceptable` pour une
   mission `supply` (une telle mission appartient de toute façon à la fiche du chef) ; `context.collective` lui dit
   qu'il n'est pas chef et donne le nom du chef. Aucun mot du joueur n'est lu (le modèle juge, le serveur vérifie).
3. **Empreinte calculée** : `API.composition(gid).key` = chef vivant puis membres vivants triés
   (`"m-1|m-1,m-2"`), recalculée à chaque appel, aucun champ ni changement de schéma. Gardée en mémoire du serveur
   avec la demande (`Server.collectives[<id>]`), jamais envoyée au pont ni au client.
4. **Revalidation** : à la réponse, une intention collective exige le même groupe, le PNJ toujours chef et la même
   empreinte ; sinon, depuis E09-T09 (décision de l'utilisateur du 2026-10-14), **seule l'intention est ignorée** :
   la réplique est dite et gardée dans l'historique, aucune mission n'est créée ni acceptée, rien n'est inscrit au
   journal du groupe ni demandé aux membres ; journal console en anglais `[RS_Carnet] collective offer|collective
   acceptance of <fiche> toward <personnage> in <demande> ignored, reply kept: <motif>`. (Avant E09-T09 la réponse
   entière était refusée et le joueur voyait `NoAnswer`.) Une réplique sans intention collective passe.
5. **Journal** : une offre créée ou une acceptation conclue écrit une entrée `decision` au journal technique du groupe
   (`Groups.addLog`), texte anglais composé par le fournisseur à partir de champs bornés (« The leader asked <nom> to
   bring food for the group. », « <nom> agreed to bring food for the group. »), jamais la réplique du modèle ni les
   raisons du chef. Les 4 dernières entrées `decision` sont jointes au contexte de groupe de chaque membre
   (`context.group.decisions`, stade `acquainted` seulement). Le journal de récit public (LK_Journal) les ignore.

## Alternatives écartées

- Filtrer les offres dans `offerCatalog` (donc aussi dans `Server.offerCatalogFor`) : la revalidation par empreinte
  reste nécessaire pour le chef, et la fonction sert aussi aux bancs et aux gabarits ; le filtre est fait dans `talk`.
- Champ `composition` stocké dans le groupe : interdit par la tâche (aucun changement de schéma).
- Refuser la réponse entière (choix initial d'E10-T02) : remplacé par E09-T09, le joueur ne voyait que « pas de
  réponse ». Limite acceptée par l'utilisateur : la réplique peut annoncer une mission qui n'a pas été créée.

## Limites

- Le bouton « Accepter » du carnet ne revalide pas le chef (pas d'intention du modèle) : une offre faite avant une
  succession reste acceptable par le bouton tant qu'elle est ouverte. À revoir avec E10-T04 (départ du chef).
- Le nom du chef de `context.collective.leaderName` est celui de la fiche du PNJ chef (nom de l'histoire pour le chef
  d'origine, nom tiré sinon).

## Idées reprises

Aucune.
