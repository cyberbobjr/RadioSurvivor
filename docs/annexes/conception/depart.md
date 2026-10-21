# Départ individuel d'un PNJ incarné (E10-T04, E10-T05)

Brouillon du 2026-10-13. Code : `shared/RadioSurvivor/RS_LivingKnox.lua` (section « individual departure » :
`LK.canLeave`, `LK.leave`, marche de départ ; `LK.composition` donne `canLeave` ; `LK.npc` nomme un solitaire d'après
son groupe), `shared/RadioSurvivor/RS_NPCProvider.lua` (opération facultative `Provider.leave`),
`server/RS_Carnet_Server.lua` (`context.leave` dans `talk`, intention `leave_group` dans `reply`),
`server/RadioSurvivor/RS_Factions.lua` (`keepTruces`, `trucesOf`, `dropTruces`, `covered` avec `npcId`),
`shared/LivingKnox/Data/LK_Type_loners.lua` (type `loners`), `server/LivingKnox/LK_Population.lua` (`dueReliefs` : aucune
relève d'un type jamais tiré), `bridge/npc_protocol.py` (`leavable`, `leave_prompt`, mode hors ligne). Contrat :
[protocole-carnet-v2.md](../../specifications-techniques/protocole-carnet-v2.md), « Départ individuel (E10-T04) ». Banc : `tests/test_lk_leave.py` ;
suite en jeu `lk.leave`.

## Décisions appliquées

- ADR B13 (spécification) : départ décidé par le LLM selon personnalité, loyauté, liens et vécu ; trêves existantes
  conservées sans renégociation ; départ social et déplacement physique séparés ; les anciens compagnons ne l'apprennent
  que par observation ou transmission.
- Q3 du 2026-10-10, option A : **solitaire durable**, groupe d'un seul membre de type `loners` livré en données, avec son
  abri, simulé hors écran, qui se souvient des joueurs.

## Parcours

1. **Offre** (`talk`) : `context.leave = { alone = true }` quand le personnage qui parle est connu du PNJ (stade
   `acquainted`) et que le PNJ peut partir maintenant (`canLeave` : membre vivant d'un groupe d'au moins deux vivants,
   qui n'est pas un groupe `loners` ni disparu, hors de l'équipe d'une expédition abstraite ou physique). La demande est
   liée au groupe et à l'empreinte de composition (`Server.collectives[id] = { ref, key, ... }`, mémoire du serveur,
   jamais envoyée au pont), comme une intention collective d'E10-T02. Le chef peut partir aussi.
2. **Décision** : le modèle qui joue le PNJ rend `intent = leave_group`, `offer` vide, selon sa personnalité et sa
   loyauté dérivée (E10-T03) ; jamais parce que le joueur le demande. Le pont refuse l'intention sans `context.leave`
   (réplique gardée sans effet, « no group to leave »). Aucune liste de mots.
3. **Revalidation** (`reply`) : même groupe, même empreinte, sinon toute la réponse est refusée avant tout effet
   (`NoAnswer` ; « NPC no longer in the group », « group composition changed »). Puis `Provider.leave` relit tout.
4. **Transition unique** (`LK.leave`) : foyer d'abord (`Sites.pick("loners", LK.homeOptions(id, groupe))` : graine
   `leave/<id>`, **anneau autour de l'ancien foyer** (E10-T05, section « Foyer du solitaire »), loin de tout foyer
   connu, l'ancien compris, à 400 cases au moins, et des bases des joueurs ; aucun site : rien ne change). Puis une
   seule transaction du registre (`Groups.update`, écrite tout de suite par `Groups.flush`) : groupe `loners` nommé
   d'après le PNJ, avec ce foyer ; membre lié au même PNJ (même rôle, profil, sexe, traits, blessure et besoins), chef
   de son groupe ; entrée `separated` (ancien groupe) ; départ de l'ancien membre (`Groups.applyLeave`, entrée `left`,
   fait `memberLeft` de raison `leave_group`) ; succession immédiate si c'était le chef (`Groups.pickSuccessor`, comme
   `Groups.succeed`, entrée `leader`).
5. **Trêves** : `RS_Factions.keepTruces(npcId, ancien groupe)` copie chaque accord de l'ancien groupe (trêve ou
   alliance, `pending` ou `applicable` : la portée couvre tous les membres) dans `S.data.factions.truces[npcId][équipe]`
   (le plus fort par équipe). Le crochet `LivingKnox.Hooks.covered(gid, playerKey, npcId)` (`RS_Factions.covered`)
   les lit pour ce PNJ, quel que soit son groupe. Un accord conclu avec l'ancien groupe après le départ ne le couvre
   pas ; un accord retiré ensuite à l'ancien groupe ne lui retire pas sa trêve personnelle.
6. **Départ physique** : mémoire du moteur oubliée pour ce PNJ (`Decisions.forget` : décision, combat, défense,
   routines), puis une consigne LK03 « marche » vers le nouveau foyer (`Directives.moveTo`, 40, 28, 16 puis 8 cases
   essayées) ; consigne d'un autre module, jamais remplacée par le cadre de décision. Elle peut échouer (corps non
   chargé, case non chargée ou bloquée) sans annuler le départ social. Le corps est rendu à la simulation abstraite
   comme tout autre quand aucun joueur n'est proche (`Bodies.releasePass`), puis vit à son nouveau foyer
   (`LK_Simulation`, `LK_Homes` l'aménage à la première visite).
7. **Carnet** : la fiche, les souvenirs (historique des contacts, observations) et les relations sont tenus par fiche,
   jamais par groupe : inchangés. `npc.clan` et `npc.groupName` suivent le nouveau groupe ; l'instantané publié montre
   le même état à tous les clients. La réplique du modèle est dite comme toute réponse (annonce ou départ discret, au
   choix du modèle).

## Foyer du solitaire (E10-T05)

Constat en jeu du 2026-10-13 (`lk.leave`) : foyer tiré n'importe où sur la carte, à 7 013 cases de l'ancien. Décision
de l'utilisateur (2026-10-13) : « un membre qui a quitté le foyer ne devrait pas être trop loin de son foyer quitté, il
faut que ce soit cohérent ».

- `LK.homeOptions(id, g)` passe `near = { x, y, min, max }` à `Sites.pick` quand l'ancien groupe a un foyer
  (`min`, `max` = `LivingKnox.Config.LEAVE.HOME_MIN`, `HOME_MAX`, lus à chaque départ) ; sans foyer, tirage habituel.
- `Sites.pick` (fiche [sites.md](sites.md), « Anneau autour d'un centre ») examine seulement les bâtiments des
  cellules qui croisent le carré de rayon `max` (métagrille, rien n'est chargé), dans un ordre mélangé par la graine,
  au plus `MAX_ATTEMPTS` par palier. Le point du site doit être à une distance euclidienne de l'ancien foyer comprise
  entre `min` et `max` ; le bâtiment qui contient l'ancien foyer est toujours exclu ; toutes les autres règles des
  foyers restent (bases des joueurs à 600 cases, autres foyers à 400, pièce explorée, eau…).
- Aucun bâtiment ne convient : `max` élargi par paliers (`Sites.CONFIG.NEAR_WIDEN` : x 2 = 2 400, puis x 4 = 4 800
  cases), chaque palier refusé journalisé (`WARN sites: no building for loners in ring 1 (400-1200 squares from
  x,y): … ; widening`), puis la carte entière (`WARN … whole map: b<id> <d> squares from x,y`), où le minimum et
  l'exclusion du bâtiment restent. Le site rend `nearDistance`, `nearTier` (1 = anneau, 2-3 = paliers, 0 = carte
  entière), `nearMin`, `nearMax`.
- **Valeurs retenues** (décision à confirmer) : `HOME_MIN = 400`, `HOME_MAX = 1200` au lieu des 150 / 600 proposés.
  Raison : le joueur qui parle au PNJ est tout près de l'ancien foyer (corps matérialisés à 80 cases du foyer au
  plus, `MATERIALIZE.RADIUS`) et compte comme une base (`Rescue.knownBases`, joueurs connectés) à `BASE_DISTANCE` =
  600 cases : tout site à moins de 520 cases environ de l'ancien foyer est refusé de toute façon. Un anneau
  150-600 serait presque toujours vide et passerait au palier x 2 à chaque départ. Le minimum 400 reprend
  `GROUP_DISTANCE`, que l'ancien foyer impose déjà comme tout foyer ; le maximum 1 200 (2 x `BASE_DISTANCE`) laisse
  un anneau d'au moins 600 cases de large au-delà de la distance au joueur, à l'échelle d'une ville vanilla (rayons
  600 à 900 dans `Rescue.TOWNS`). Abaisser le minimum sous 600 demanderait de réduire la distance aux bases pour ce
  seul tirage (refuges compris) : écarté.
- Preuves : banc `tests/test_lk_sites_near.py` (anneau, paliers, carte entière, exclusions, graine, aucune lecture de
  case) et `tests/test_lk_leave.py` (options passées par `leave`) ; suite en jeu `lk.leave` (distance mesurée,
  palier affiché).

## Choix pris sans l'utilisateur (à confirmer)

1. Intention offerte seulement à un personnage **connu** du PNJ (stade `acquainted`), dans une conversation `npc_talk`
   (pas dans une réaction `npc_member` d'E10-T03, dont le prompt interdit toujours de partir).
2. Départ refusé au dernier vivant d'un groupe et à un membre en expédition (la dispersion hors écran, LK09-T04, couvre
   le premier cas).
3. Type `loners` : hostilité de départ 50 (attitude de départ 0, « cautious »), foyer `building`, moral et besoins 50 ;
   tous les rôles déclarés avec les mêmes comportements d'une vie seule (garde, défense, combat, fouille, cueillette,
   pêche, cuisine, corvées, entretien, fortification, parole, troc ; ni rondes, ni expédition, ni pillage) : le PNJ garde
   son rôle. L'attitude de son ancien groupe envers les joueurs n'est pas reprise (relations de groupe, clés par
   groupe) ; ses souvenirs de joueurs (carnet) le sont.
4. Groupe nommé d'après le PNJ (`LK.npc` rend ce nom pour un solitaire : un ancien chef garde le nom de son histoire).
5. Un solitaire disparu n'appelle **aucune relève** (`Population.dueReliefs` ignore un type sans option de poids) : un
   départ ne fait jamais grossir la population.
6. Aucun site pour le solitaire : départ refusé, rien ne change (réponse refusée, `NoAnswer`).
7. Trêves copiées = accords `pending` et `applicable` de l'ancien groupe (même règle que `covered` pour un groupe).
8. Foyer du solitaire dans l'anneau 400-1 200 cases de l'ancien foyer, paliers x 2 et x 4, puis carte entière
   (E10-T05, section « Foyer du solitaire »).

## Hors périmètre (restes)

- Recrutement ultérieur d'un solitaire par un autre groupe : décision distincte, non codée.
- Missions de groupe (`supply`) offertes ou acceptées par le PNJ avant son départ : elles restent attachées à l'ancien
  groupe (livraisons comptées pour lui) ; le bouton « Accepter » du carnet ne revalide toujours pas le chef (reste
  d'E10-T02).
- Trêves personnelles jamais purgées (mort du PNJ, équipe dissoute) : volume borné par les départs.
- Le nombre de vivants de l'ancien groupe (contexte public `alive`) change aussitôt ; aucune autre information n'est
  donnée aux anciens compagnons.
- Arme et apparence : celles du PNJ (registre des corps), même hors profil du type `loners`.

## Idées reprises

Aucune.
