# Accords de faction avec un groupe Living Knox : trêve et alliance (E09-T05)

Brouillon du 2026-10-12. Code : `server/RadioSurvivor/RS_Factions.lua` (registre des accords, `negotiation`,
`conclude`, `covered`, `pollApplications`), `server/RS_Carnet_Server.lua` (`talk`, `reply`, `tick`),
`client/RadioSurvivor/RS_Client.lua` (annonce), `server/LivingKnox/LK_Decisions.lua` (point de lecture
`Decisions.markEvaluated`, `Decisions.aims`), `bridge/npc_protocol.py` (intention `negotiate`). Contrat :
[protocole-carnet-v2.md](../../specifications-techniques/protocole-carnet-v2.md), « Accords de faction (E09-T05) ». Équipes et mandats :
[factions.md](../../specifications-techniques/factions.md). Choix de cible : [cibles.md](cibles.md). ADR B07 à B09 de
[bandits-llm-specifications.md](../recherches/bandits-llm-specifications.md).

## Problème

Un groupe Living Knox (`grp-<n>`) et une équipe de joueurs (`fac-<n>`, E09-T03) concluent une trêve ou une alliance.
L'offre vient du serveur, le modèle juge s'il l'accepte, le serveur vérifie qui conclut ; l'accord n'est annoncé
qu'une fois appliqué : aucun membre du groupe ne vise plus un joueur couvert, même si la trêve est décidée pendant un
combat. Une trêve ne change pas l'attitude du groupe (ADR B08).

## Choix (le plus simple, à confirmer)

1. **Registre privé** : `S.data.factions.agreements["<groupe>|<équipe>"] = { id = "agr-<n>", group, team, kind,
   state = "pending" | "applicable", revision, scope, signed = { account, role, character, npc }, concludedAt,
   appliedAt }` dans l'état du carnet (`RS_State`), jamais en ModData globale ni envoyé au client. Un seul accord par
   paire ; son identifiant reste le même d'une révision à l'autre ; la révision part de 1 à la première conclusion
   (0 = aucun accord). Les accords d'une équipe dont l'enregistrement est purgé (au-delà de 64 dissoutes) sont
   retirés.
2. **Types** : `truce` puis `alliance` (du plus faible au plus fort). L'offre ne propose que les types au-dessus de
   l'accord courant : aucun accord → trêve et alliance ; trêve → alliance ; alliance → rien. Les deux imposent la
   même non-agression ; l'alliance n'a pas d'autre effet dans cette tâche (aide, partage : à décider plus tard).
   Aucune rupture ici (E09-T06).
3. **Portée explicite** (`F.SCOPE`, identique pour tout accord, écrite dans l'accord et envoyée au modèle) : tous les
   membres du groupe (`group = "all_members"`) ; les membres **actuels** de l'équipe (`team = "current_members"`),
   relus par le sondage borné des factions vanilla (2 s, aucun événement serveur, base `multiplayer.md`) : un joueur
   qui rejoint la faction est couvert, un joueur qui la quitte ne l'est plus ; pour une équipe personnelle (joueur
   sans faction, solo), son propriétaire. **Décision à confirmer** : la règle ADR B08 laisse ouvert « membres
   actuels, présents à la signature ou liste explicite » ; « membres actuels » est le plus simple et suit le reste de
   la tâche (sondage).
4. **Offre du serveur** (`Factions.negotiation(player, gid)`) : seulement dans une phrase dite au **chef** du groupe
   (stade `acquainted`, `Server.collectiveBinding`), et seulement si le joueur peut conclure maintenant
   (`Factions.canConclude` : propriétaire courant ou négociateur désigné ; équipe personnelle : son propriétaire).
   Termes fixes, sans durée ni condition. `context.negotiation = { role, teamName, personal, current, terms }` ; la
   demande est liée en mémoire du serveur à l'équipe et à la révision (`Server.collectives[<id>] = { ref, key, team,
   revision }`, jamais envoyée au pont).
5. **Négociation par le modèle** : il décide selon sa personnalité, l'attitude du groupe et ce qu'il sait ; il ne
   change pas les termes. Il rend `intent = "negotiate"` et `offer = <type>` seulement si la dernière phrase du joueur
   propose ou accepte clairement l'accord au nom de son équipe ; aucune liste de mots, toute langue. Le prompt lui
   interdit de dire l'accord déjà en vigueur.
6. **Conclusion** (`reply`, puis `Factions.conclude`) : revalidée au moment de conclure : chef et composition du
   groupe (`Server.collectiveCheck`), joueur connecté, mandat relu sur la faction vanilla (`canConclude`), même
   équipe, même révision de l'accord, type encore au-dessus de l'accord courant. Sinon, depuis E09-T09 (décision de
   l'utilisateur du 2026-10-14), **seul l'accord est ignoré** : la réplique du chef est dite et gardée dans
   l'historique, aucun accord ni réaction des membres ; journal `[RS_Carnet] agreement of <fiche> toward <personnage>
   in <demande> ignored, reply kept: <motif>` (`no mandate`, `team changed`, `agreement revision changed`, `NPC no
   longer the group leader`, `group composition changed`, `negotiator not connected`, `agreement not offered`), comme
   les intentions collectives d'E10-T02. Deux conclusions bâties sur la même révision : la première passe, la seconde
   est ignorée (`agreement revision changed`), sa réplique dite.
7. **Application** : l'accord conclu est inscrit aussitôt ; le crochet `LivingKnox.Hooks.covered(groupId,
   playerKey, npcId)` est `Factions.covered` (seule implémentation, posée au chargement et avant chaque sondage
   d'application) : vrai quand la clé de joueur (identité de personnage du carnet) appartient à un compte dont
   l'équipe actuelle a une trêve ou une alliance avec ce groupe, en attente ou applicable. Le choix de cible
   (`Hostility.chooseTarget`) et les renforts (`Decisions.helpTarget`) le consultent : le joueur couvert n'est plus
   une cible dès le passage de décision suivant.
8. **Constat** (`Factions.pollApplications`, chaque seconde dans le `tick` du carnet) : l'accord reste `pending`
   tant qu'un membre vivant du groupe vise un joueur de l'équipe ou qu'un membre actif (état de décision ou
   engagement de `LK_Combat`) n'a pas été évalué depuis la conclusion. Ensuite il devient `applicable`, est
   sauvegardé, puis **annoncé** : commande serveur `agreement` aux joueurs connectés de l'équipe, texte traduit côté
   client (« Truce with <groupe> now in force », « Trêve avec <groupe> désormais en vigueur »), une fois par
   révision. Après un redémarrage, un accord resté en attente repart de l'évaluation courante.
9. **Point de lecture côté Living Knox** (minimal, `LK_Decisions`) : chaque `Decisions.evaluate` reçoit un numéro
   croissant (`Decisions.markEvaluated`, mémoire seulement) ; `Decisions.aims(gid)` rend, pour chaque membre vivant,
   ce numéro, s'il est actif et le compte du joueur visé (engagement de `LK_Combat` contre un joueur, sinon
   comportement `fight` ou `warn` de clé `p<compte>`). Lecture seule.
10. **Attitude** : aucun fait d'attitude n'est écrit par un accord ; la paire `LK_Hostility` reste identique, et une
   provocation passée reste une provocation (elle ne fait plus tirer tant que le joueur est couvert).
11. **Accusé de réception au pont** : `applied` reste vide pour `negotiate` (le pont n'admet que `offer` et `accept`
   dans `applied`, et `radio_bridge.py` n'est pas modifié) : la mémoire du PNJ garde l'échange, l'accord est un fait
   du serveur.

## Alternatives écartées

- Annoncer à la conclusion : contraire au critère « trêve décidée pendant un combat : application confirmée avant
  annonce » (un membre peut encore frapper).
- Constat par l'arrêt du seul engagement de `LK_Combat` : une sommation (`warn`) ou un état de décision non encore
  revu viserait encore le joueur ; d'où le numéro d'évaluation.
- Couverture des seuls signataires ou des membres présents à la signature : demande une liste figée contraire au
  « membres relus par sondage » de la tâche.
- Accord inscrit dans la fiche du PNJ (`npc.agreements`) : l'accord engage tout le groupe, pas un PNJ.

## Limites

- Pas de journal du groupe pour un accord (`RS_NPCProvider.decide` ne connaît que les missions de groupe) ; pas de
  panneau des accords dans le carnet (E09-T07) ; incidents et rupture : [incidents.md](incidents.md) (E09-T06).
- Le constat exige un passage de décision de chaque membre actif : un membre engagé par l'API (suite de test) contre
  un joueur couvert garde l'accord en attente jusqu'à la fin de cet engagement.
- Un membre qui n'est pas incarné n'est pas compté (rien ne vise depuis la simulation abstraite) ; un raid ou une
  vengeance hors écran contre un joueur couvert n'est pas traité ici (E10-T04, LK11-T05 : `covered` passe avant
  `revenge` dans la règle de cible).
- Non prouvé en jeu ni dans la VM Kahlua : bancs lupa seulement (`tests/test_agreements.py`), suite
  `rs.factions.accord` à jouer.

## Idées reprises

Aucune.
