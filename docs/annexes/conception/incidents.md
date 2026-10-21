# Défense ciblée et décision sur la trêve (E09-T06)

Brouillon du 2026-10-13. Code : `server/RadioSurvivor/RS_Factions.lua` (fin du fichier : registre des incidents,
crochets, `decideIncident`), `server/RadioSurvivor/RS_Incidents.lua` (demande au modèle et réponse),
`server/RS_Carnet_Server.lua` (passage du `tick`, aiguillage de `reply`, annonce), `server/LivingKnox/LK_Bodies.lua`
(fait `memberHit`), `client/RadioSurvivor/RS_Client.lua` (annonce), `bridge/npc_protocol.py` (genre `npc_incident`).
Accords : [accords.md](accords.md). Choix de cible : [cibles.md](cibles.md). ADR B08 et B10 de
[bandits-llm-specifications.md](../recherches/bandits-llm-specifications.md).

## Problème

Un joueur couvert par un accord de son équipe avec un groupe (trêve ou alliance, E09-T05) frappe, tire sur ou tue un
membre du groupe. Le groupe se défend aussitôt contre l'auteur seul, sans attendre le modèle ; les autres membres de
l'équipe restent couverts ; puis le chef décide du sort de l'accord (maintien, réparation, rupture), décision vérifiée
par le serveur et appliquée une seule fois.

## Choix (le plus simple, à confirmer)

1. **Faits** (abonnés `LivingKnox.listen`, posés par `RS_Factions.installHook`) :
   - `memberHit` (nouveau fait publié par `LK_Bodies.onHitZombie`, coup d'un joueur avec une arme sur le corps courant
     d'un membre) : fait `shot` pour une arme à feu (`Bodies.weaponCategory` = `firearm`), sinon `hit` ;
   - `npcDied` avec `killer` (tueur retenu par `Bodies.deathCause`, règle d'E04-T06) : fait `kill` ;
   - `assaultSeen` (`LK_Hostility.record` d'un `hit`, `shot` ou `kill` vu) : même fait.
   Le joueur est retrouvé par sa clé du carnet (`Hostility.keyOf`). Seul compte un joueur dont l'équipe a avec ce
   groupe un accord de rang > 0 (en attente ou applicable) ; un joueur tiers n'ouvre rien (règles ordinaires).
2. **Incident** : un seul ouvert par accord (clé `<groupe>|<équipe>`), dans l'état privé du carnet
   (`S.data.factions.incidents = { counter, open = { [clé] = incident }, closed = { … 32 derniers } }`) :
   `{ id = "inc-<n>", group, team, agreement, state, revision, count, authors = { [clé] = compte }, accounts,
   victims = { [lk-<n>] = true }, facts = { { fact, author, npc, ms } } (16 derniers), openedAt, lastAt }`. Chaque fait
   nouveau incrémente `revision`. Plusieurs auteurs d'une même équipe vont dans le même incident (une seule décision
   sur l'accord). Le même fait du même auteur reçu une fois sans victime (témoin) et une fois avec (coup), à moins de
   2 s, compte une fois.
3. **Défense immédiate ciblée** : un auteur d'un incident ouvert n'est plus couvert pour ce groupe (`F.covered` rend
   faux) et le crochet `LivingKnox.Hooks.incident` (`F.isIncidentAuthor`) le désigne à la règle 1 du choix de cible
   (`Hostility.targetRule` : « incident » → attaque, avant « couvert »). Les renforts (`Decisions.helpTarget`) le
   visent aussi. Les autres membres de l'équipe restent couverts ; l'accord garde son état jusqu'à une décision. Un
   membre qui vise un auteur ne retient pas l'application d'un accord en attente (`confirmed`).
4. **Riposte** : une attaque d'un membre n'écrit aucun fait ici ; le coup d'un joueur couvert sur un membre qui le
   vise à cet instant (`Decisions.aims` : engagement de combat ou comportement `fight` / `warn`) n'ouvre rien
   (journal : raison `riposte`) ; un auteur déjà inscrit voit ses coups suivants ajoutés au même incident.
5. **Demande au modèle** (`RS_Incidents.tick`, une par passage, dans les quotas du pont, pas quand le pont est
   considéré arrêté) : quand aucun fait n'est arrivé depuis `SETTLE_MS` (5 s), requête `npc_incident` dans la file de
   la fiche du **chef** (`LivingKnox.API.composition(groupe).leaderNpc`), personnage `group`, langue
   `NARRATIVE_LANGUAGE`, texte = faits établis composés en anglais par le serveur (noms des personnages du carnet et
   des PNJ, nombres de coups, tirs, morts), `context.incident = { agreement, state, teamName, authors (noms), victims
   (noms), facts, defence = "authors_only", earlier = décisions précédentes sur cet accord }`, `context.choices =
   { maintain, repair = { categories, quantity }, break }`. Aucune clé du carnet ni identifiant d'équipe n'est envoyé ;
   la liaison (incident, révision de l'incident, révision de l'accord) reste en mémoire (`RS_Incidents.bindings`).
6. **Décision** (`npc_incident`) : `intent = maintain | repair | break` (ou `none`, aucune décision), `offer` = la
   catégorie de réparation pour `repair`, vide sinon. Revalidée par le serveur : chef toujours le même PNJ, même
   révision de l'incident (aucun fait nouveau), même révision de l'accord, catégorie parmi celles du stock
   (`LK_Stock.CATEGORIES`). Effet, une seule fois : révision de l'accord + 1, `a.decision = { incident, choice, at,
   npc }` ; `repair` : `a.repair = { category, quantity = 5, incident, at }` (demande enregistrée) ; `break` :
   `kind = "none"`, `state = "broken"` (plus personne n'est couvert ; un nouvel accord peut être négocié). L'incident
   est fermé : l'auteur redevient couvert si l'accord tient. Annonce aux joueurs connectés de l'équipe (commande
   `incident`, texte traduit côté client).
7. **Réponse tardive** : une réponse construite avant un fait nouveau est refusée (`incident revision changed`) ;
   l'incident est redemandé avec les faits nouveaux. Deux réponses valides sur le même incident : la seconde est
   refusée (`incident closed`).
8. **Pont indisponible** : la requête expire (`REQUEST_TIMEOUT_MS`), l'incident reste ouvert, la défense reste ciblée
   sur l'auteur, l'accord ne change pas ; nouvelle demande après `RETRY_MS` (2 min), sans limite de durée.
9. **Vengeance** (LK11-T05) : le serment ne vise que le tueur (`Relations.memberKilled`, clé du tueur) ; la règle
   « couvert » passe avant « vengeance » dans le choix de cible : les autres membres de l'équipe ne sont jamais visés.

## Alternatives écartées

- Un incident par auteur : deux décisions contradictoires possibles sur le même accord (ADR B10 : regrouper).
- Défense par le seul fait d'attitude (`provoked`) : la règle « couvert » passe avant, l'auteur ne serait jamais
  visé ; d'où le crochet `incident` en tête.
- Rupture automatique sans pont ou au-delà d'un délai : contraire à « pont absent : défense maintenue, aucune rupture
  automatique ».
- Réparation livrée par une mission de groupe : extension hors périmètre (voir Limites).

## Limites

- La réparation est **enregistrée** (catégorie, quantité fixe 5) et annoncée, mais rien ne la fait livrer ni ne la
  contrôle (à décider : mission de groupe, troc, délai, effet d'un refus).
- Pas de fin de défense sans décision : sans pont, l'auteur reste une cible du groupe tant que l'incident est ouvert.
- Les trêves personnelles d'un PNJ parti (E10-T04) n'ouvrent pas d'incident ; un coup sans arme (`weapon == nil`) ou
  une mort sans tueur retenu (feu, véhicule non attribué, tueur « probable » d'E04-T06) non plus.
- Les faits d'attitude `hit`/`shot` ne sont toujours pas écrits par un coup (seul `kill` l'est, par LK11-T05) : hors
  périmètre.
- Pas d'entrée au journal du groupe pour la décision, réplique du chef non dite à voix haute (mémoire du pont
  seulement).
- Non prouvé en jeu ni dans la VM Kahlua pour le chemin complet : banc lupa `tests/test_incidents.py`, suite
  `rs.factions.incident` à jouer.

## Idées reprises

Aucune.
