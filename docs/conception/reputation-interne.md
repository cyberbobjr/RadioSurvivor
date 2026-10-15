# Réputation interne de RadioSurvivor

- Tâches : E04-T08 à E04-T14 (et E04-T04, T05, T07 adaptées) — plan [E04](../plan/E04-reputation.md)
- Build : 42.21.0 — Date : 2026-10-14, mise à jour 2026-10-15 — Statut : **cœur serveur codé** (E04-T07, T08, T09,
  T12 ; Q1 à Q17 réponse (a), confirmées par défaut le 2026-10-15 ; section 10) ; onglet, offres, contexte LLM, marge et
  suite en jeu à venir (E04-T04, T05, T10, T11, T14)
- Décision d'origine : décision 8 de l'utilisateur, 2026-10-14 : « réputation interne de RadioSurvivor côté serveur,
  bâtie sur les faits déjà journalisés (`rs.facts`), avec un adaptateur optionnel vers CharacterReputation si son API
  arrive ».

Les numéros de ligne ci-dessous sont ceux de la branche `dev` au 2026-10-14 (chemins relatifs à
`Contents/mods/batman_RadioSurvivor/42.21/media/lua/`).

## 1. Point de départ

| Élément | État actuel | Preuve |
|---|---|---|
| Adaptateur | `RS_Reputation.lua` n'a que `descriptor`, `projection` (toujours « indisponible ») et `record`, qui écrit un fait `applied=false`, `status='api_unavailable'` dans `state.outcomes[eventId]`, une seule fois par `eventId` | `server/RadioSurvivor/RS_Reputation.lua:4-22` |
| Montants | `Reputation = {success = 5, failure = -5, requesterKilled = -50}`, « provisoires » | `shared/RadioSurvivor/RS_Config.lua:59-60` |
| Résultats de mission | `M.finish` : un `Rep.record` par participant, identifiant `<mission>-<personnage>-result`, actions `mission.success`/`mission.failed`/`mission.abandoned` ; annulations (`cancelled_*`) sans effet | `server/RadioSurvivor/RS_Missions.lua:120-145` (appel ligne 140, filtre 130-131) |
| Tricherie au passeur | `Rep.record(..., "trade-<rév>-cheated", who, "trade.cheated", failure)` | `server/RadioSurvivor/RS_TradeExchange.lua:291-302` (appel ligne 297) |
| Mort du demandeur | `Server.dead` annule les missions (`cancelled_dead`) et pose `deathAttribution = 'unavailable_server_evidence'` ; commentaire « attribution bloquée » devenu faux depuis E04-T06 | `server/RS_Carnet_Server.lua:963-977` (commentaire 972-974) |
| Cause de la mort d'un PNJ | `Bodies.deathCause` (dernier coup d'un joueur ≤ 5 s, conducteur, feu jamais attribué) passée à `Bodies.onDied`, relayée en événement fournisseur `'death' (id, object, cause)` | `server/LivingKnox/LK_Bodies.lua:941-974`, `1013-1014` ; `shared/RadioSurvivor/RS_LivingKnox.lua:618` ; `shared/RadioSurvivor/RS_NPCProvider.lua:88` |
| Compte → personnage | `cause.killer` est un **compte** ; le personnage du carnet s'obtient comme le fait la vengeance : `Relations.playerByName` puis `Hostility.keyOf(player)` (`RS_CarnetServer.bound`) | `server/LivingKnox/LK_Relations.lua:603-625` ; `server/LivingKnox/LK_Hostility.lua:545-550` |
| Lecture | carnet : instantané `reputation = Rep.projection()` + liste `events` du personnage ; contexte LLM `reputation = 'unavailable'` (carnet, radio de groupe) ; voix radio : aucun champ | `server/RS_Carnet_Server.lua:226-231`, `356` ; `server/RadioSurvivor/RS_GroupRadio.lua:144` ; `server/RadioSurvivor_Server.lua:445-463` |
| Onglet | « réputation globale », « indisponible », confiance séparée, faits « non appliqués » | `client/RadioSurvivor/RS_Notebook.lua:616-620` |
| Marge du passeur | plancher 0,25 − 0,05 par affaire conclue (0,10 au mieux), 0,50 après tricherie, « faute d'API de réputation » (décision E13-T02) | `server/RadioSurvivor/RS_Trade.lua:62-65`, `340-356` |

## 2. Pourquoi pas le carnet des faits `rs.facts` tel quel

Le journal de la chronique (`RS_Facts`, [chronique.md](chronique.md)) ne peut pas porter seul une réputation durable :

- il ne connaît **pas le personnage** : les faits `mission` gardent des **noms** de participants
  (`RS_Facts.lua:75-76`, `353-366`), `group_death` seulement `byPlayer = true/false` (`RS_Facts.lua:83`, `394-397`) ;
- il est **vidé** : purge par le bulletin (`Facts.purge`, `RS_Facts.lua:322`) et expiration à la veille sans
  bulletin (`Facts.expireBook`, `RS_Facts.lua:225`, `330`) ; au plus 80 faits (`RS_Facts.lua:63`).

Proposition : la réputation est bâtie sur **les mêmes faits confirmés par le serveur**, captés **aux mêmes points**
que la chronique (fin de mission, tricherie, mort d'un PNJ attribuée), mais enregistrés dans un **registre
durable par personnage** : le registre `state.outcomes` qui existe déjà (identifiant d'événement unique, personnage
du carnet, action, montant, preuve). La chronique reste le récit public ; la réputation, le compte privé.

## 3. Sources proposées (liste fermée)

| Action | Quand | Qui | Montant proposé | Source |
|---|---|---|---|---|
| `mission.success` | `M.finish(..., 'success')` | chaque participant inscrit | +5 | `RS_Missions.lua:140` (existant) |
| `mission.failed` / `mission.abandoned` | `M.finish` | chaque participant inscrit | −5 | idem (existant) |
| `trade.cheated` | sac insuffisant au ponton | l'appelant du passage | −5 | `RS_TradeExchange.lua:297` (existant) |
| `npc.requesterKilled` | mort d'un PNJ dont une mission est ouverte, `cause.killer` attribué **et** participant de cette mission | ce seul personnage | −50 | `RS_Carnet_Server.lua:963` + cause de `'death'` (E04-T07) |
| `npc.memberKilled` | mort d'un membre de groupe attribuée à un joueur (fait `npcDied` avec `killer`), hors cas précédent | ce seul personnage | −10 (question Q5, E04-T09) | `LK_Relations.lua:614-625` (même résolution) |
| `rescue.success` | survivant secouru (E12-T04/T05) | participants | +5 | réservé, comme `Facts.record('rescue', …)` |

Rien ne vient d'une parole (ADR B11/B15 : une phrase ne crée aucun fait) ni d'un client. Feu, piège sans lanceur,
mort non attribuée : aucun effet (règle d'E04-T06).

## 4. Formule proposée (valeurs « confirmées par défaut »)

- **Score** entier borné **−100..+100**, départ **0** (neutre) pour chaque nouveau personnage du carnet ; jamais
  affiché, jamais envoyé au client ni au LLM.
- **Niveaux** (3, décidés) : `bad` ≤ −20 < `neutral` < +20 ≤ `good`. Une réussite seule ne change pas de niveau ;
  quatre réussites mènent à « bonne », quatre échecs à « mauvaise ».
- **Tendance** (`up`, `down`, `stable`) = signe de la somme des sens des trois derniers faits, comme les relations
  (décision E09-T01) : le joueur voit qu'il progresse sans voir de chiffre.
- **Plafond de gain** : au plus **+10 par jour de jeu** et par personnage (jour de 7 h à 7 h, `Facts.now`) ; le
  surplus est noté `appliedDelta = 0` (« plafond atteint ») ; les pertes ne sont jamais plafonnées. Après la mort
  d'un demandeur (−50), revenir à neutre demande au moins 7 réussites sur 4 jours de jeu : une série de petites
  missions n'efface pas un acte grave d'un coup (ADR B15).
- **Pas d'usure avec le temps** (décision acquise de la spécification : aucune amélioration automatique) ; la
  question Q4 (E04-T09) propose seulement une usure de la **bonne** réputation.
- **Idempotence** : `outcomes[eventId]` écrit une fois ; l'application du montant se fait dans le même appel Lua que
  l'écriture (`applied = true`, `appliedDelta`, `status = 'applied'`), puis `S.save()`. Rejouer un événement (double
  mort, redémarrage) trouve l'entrée et ne fait rien.
- **Motifs** : les 5 derniers faits appliqués par personnage, `{action, sign, reasonKey, reasonArgs}` avec
  `reasonKey = IGUI_RS_RepReason_<Action>` (clés à créer, EN + FR) et `reasonArgs` publics (nom affiché du PNJ).

## 5. Où elle est lue

| Lecteur | Ce qu'il reçoit | Point d'entrée |
|---|---|---|
| Carnet, onglet Réputation | niveau, tendance, 5 motifs ; confiance des PNJ toujours à part | instantané `RS_Carnet_Server.lua:226-231` → `RS_Notebook.lua:616-620` |
| PNJ en face (carnet, proximité) | `reputation = 'bad' / 'neutral' / 'good'` (+ dernier motif public si décidé) | `RS_Carnet_Server.lua:356` |
| Radio de groupe | idem | `RS_GroupRadio.lua:144` |
| Voix radio (Walt…) | idem, nouveau champ de la requête | `RadioSurvivor_Server.lua:445-463` ; contrat `docs/protocole-carnet-v2.md` à mettre à jour |
| Offres de missions | filtre serveur par niveau (simples / sensibles) | `M.offers`, `RS_Missions.lua:75-85` (E04-T05) |
| Passeur | plancher de marge par niveau | `RS_Trade.lua:340-356` (E04-T11) |
| Groupes Living Knox | éventuel décalage du départ de l'attitude (question Q14, E04-T11) | `LK_Hostility` (départ, [attitude.md](attitude.md)) |

Le prompt ne reçoit jamais le score, ni preuve, ni identité, ni coordonnée. L'instruction du pont « ne jamais changer
la réputation » (`bridge/npc_protocol.py:979`) reste vraie : seul le serveur l'écrit.

## 6. Persistance et multijoueur

- **Autorité** : tout le module est sous `media/lua/server` avec `if isClient() then return end` (garde existante,
  `RS_Reputation.lua:1`) ; aucune commande client ne fixe un personnage, un montant ni un motif.
- **Stockage** : état privé `RS_State` (fichier serveur `getFileWriter`, `RS_State.lua:29`, `49-59`), nouveau champ
  `reputation[<personnage du carnet>] = {score, revision, trend, reasons, gainDay, gainSum}` à côté de `outcomes`
  (`RS_State.lua:41`). **Aucune ModData globale** (lisible par tout client, base `multiplayer.md`).
- **Identité** : personnage du carnet (E00-T01) ; nouveau personnage = réputation neutre ; personnage mort (`retired`,
  `RS_Carnet_Server.lua:1169-1175`) : sa réputation n'est plus lue, purgée avec ses `outcomes` après 7 jours de jeu.
- **Purge proposée** : `outcomes` aujourd'hui jamais purgé (aucun appel hors `RS_Reputation`) : garder 30 jours de
  jeu, ou jusqu'à la purge du personnage retiré ; le score suffit ensuite (les doublons possibles viennent d'événements
  proches dans le temps).
- **Diffusion** : l'instantané est envoyé au seul joueur concerné (existant) ; aucun autre joueur ne lit la
  réputation d'autrui (question Q15, E04-T12).
- **Joueur hors ligne** : le fait est appliqué à sa clé de personnage, sans le joueur (le registre ne dépend pas de
  la connexion).

## 7. Adaptateur optionnel CharacterReputation

- Le contrat **RSREP-1** ([reputation-contract.md](../reputation-contract.md)) reste la cible : détection par
  `getDescriptor()` (§2), identité opaque (§3), `recordEvent` idempotent avec `eventId = rs:` + identifiant de
  `outcomes` (§4), lecture (§5), isolement par `pcall` à la frontière (§7).
- Changement de principe à reporter dans RSREP-1 (§1 et §8) : RadioSurvivor **tient désormais sa propre réputation**
  (décision 8). Proposition recommandée (question Q16, E04-T13) : la réputation interne reste celle qui pilote les effets de
  RadioSurvivor ; quand le service est `ready`, chaque fait appliqué en interne est **aussi** envoyé au service
  (même `eventId`, mêmes montants) ; le service partage ainsi les actes avec les autres mods sans que le comportement
  du jeu change à l'installation ou au retrait du mod.
- Faits antérieurs à l'arrivée du service : jamais renvoyés (décision E04-T01 (2) conservée pour l'adaptateur).

## 8. Validation prévue

- Banc `lupa` (`tests/test_reputation.py`) : barème, bornes, plafond de gain, niveaux, tendance, idempotence
  (double événement, rejeu après rechargement d'état), tueur non participant, cas non attribué, purge.
- Suite en jeu `rs.reputation` (solo puis campagne MP automatique) : mission réussie → niveau et motif visibles chez le
  seul participant ; deux clients : l'un tue le demandeur, l'autre garde sa réputation ; redémarrage serveur : score
  conservé, aucun doublon.

## 9. Valeurs techniques proposées (confirmées par défaut, sauf réponse contraire)

Score −100..+100, départ 0 ; seuils ±20 ; +5 / −5 / −5 / −50 (montants existants) ; −10 pour un membre de groupe tué ;
plafond de gain +10 par jour de jeu ; 5 motifs ; tendance sur 3 faits ; `outcomes` gardés 30 jours de jeu ; personnage
retiré purgé après 7 jours ; aucun appel au pont ni coût LLM supplémentaire (la réputation voyage dans le contexte
existant).

## 10. Mise en œuvre (2026-10-15)

Code : `server/RadioSurvivor/RS_Reputation.lua` (en-tête : API publique), `shared/RadioSurvivor/RS_Config.lua`
(`Reputation`, valeurs de la section 9), points de capture `RS_Missions.finish`, `RS_TradeExchange` (`finish`),
`RS_Carnet_Server.lua` (`Server.dead`, `Server.npcDied`, `killerCharacter`, instantané, `prune`, `characterDeath`).
Banc : `tests/test_reputation.py`.

- **Registre** : `S.data.reputation[<personnage>] = {score, revision, trend, signs, reasons, gainDay, gainSum,
  retiredDay}` ; `signs` = sens des trois derniers actes (tendance) ; `reasons` = cinq derniers actes, du plus récent
  au plus ancien, `{action, reasonKey, reasonArgs, sign, capped, day}`.
- **Entrée de `outcomes`** (écrite une fois par `eventId`, montant appliqué dans le même appel) : `rep` = `applied`,
  `capped` (plafond du jour : surplus sans effet), `no_character` (appelant sans personnage du carnet) ou `retired`
  (personnage mort) ; `appliedDelta`, `before`, `after` ; `proposedDelta` = montant de l'action ; `day` = jour de jeu.
  **Choix** : les champs `applied = false` et `status = 'api_unavailable'` restent ceux du service facultatif
  CharacterReputation (RSREP-1 §4, adaptateur E04-T13) et ne disent rien de l'application interne : l'adaptateur
  gardera ses propres états (`sending`, `applied`…) sans toucher à `rep`.
- **Montant** : toujours celui de la liste fermée (`R.ACTIONS` → clé de `RS_Config.Reputation`) ; l'argument `delta`
  de `R.record` est gardé pour la compatibilité des appels et ignoré ; une action hors liste est refusée.
- **Missions** : un fait par participant inscrit (connecté ou non), même action et même montant ; motif public = nom
  du demandeur (fiche ou voix radio).
- **Demandeur tué (E04-T07)** : `Server.dead(id, object, cause)` ; `cause.killer` (compte) → joueur vivant
  (`LivingKnox.Relations.playerByName`, sinon joueurs connectés) → personnage (`LivingKnox.Hostility.keyOf`, sinon
  `Server.bound`) ; si ce personnage participe à une mission **active** de ce PNJ (relevé avant l'annulation
  `cancelled_dead`) : `npc.requesterKilled`, `eventId` `<npc>-killed-<personnage>`, motif = nom du PNJ.
  `deathAttribution` = `player` (personnage du carnet), `unbound` (compte sans personnage) ou
  `unavailable_server_evidence` (aucun tueur établi : feu, piège, mort non relevée).
- **Membre de groupe tué** : fait Living Knox `npcDied` (abonné à clé `RS_Reputation.memberKilled`, branché par le
  passage du carnet) avec `group` et `killer` ; `eventId` `lk-<npc>-g<génération>-memberKilled-<personnage>` ; ignoré
  si la règle du demandeur a déjà frappé ce personnage pour cette mort. **Ordre requis** : `LK_Bodies.onZombieDead`
  appelle `Bodies.onDied` (événement `'death'` du fournisseur) avant de publier `npcDied` (même appel Lua).
- **Purge** : à chaque passage `prune` du carnet ; une entrée `outcomes` antérieure à ce code reçoit le jour courant
  (son délai de 30 jours part de là) ; la mort d'un personnage (`characterDeath` → `R.retire`) date sa réputation,
  supprimée avec ses `outcomes` 7 jours de jeu plus tard. Le score survit à la purge de ses `outcomes`.
- **Diffusion** : l'instantané du carnet porte `reputation = {available, level, trend, reasons, change, today}` du
  seul personnage du joueur (jours de jeu des actes et du dernier changement de niveau, traduits en mots par le
  client) ; aucune valeur brute.

### Effets (E04 seconde partie, 2026-10-15)

- **Onglet Réputation (E04-T04, Q8, Q9)** : `RS_Notebook.reputationLines` : niveau en mots et tendance, ligne du
  dernier changement de niveau, 5 derniers actes avec leur motif et leur moment en mots (aujourd'hui, hier...), puis,
  à part, l'avis personnel de chaque PNJ connu (`relation.level`). Aucun chiffre. Avertissement au changement de niveau
  seulement : `R.change` garde `{from, to, day, n}` ; le client (enveloppe de `RS_CarnetClient.receive` dans
  `RS_Notebook.lua`) affiche « Réputation : bonne » au-dessus du personnage une fois par `n` ; le premier instantané
  après le chargement ne fait que noter la référence. L'ancienne liste `events` « non appliqués » est retirée.
- **Offres (E04-T05, Q11, Q12)** : `RS_Missions.offers` filtre par `R.offerAllowed(level, template, offer)` :
  mauvaise réputation = `deliver`, `signal`, `scout`, `clear` seulement ; `retrieve_id`, `recover` et les missions de
  groupe (offre `kind = supply`) fermées (`RS_Config.Reputation.sensitive`) ; neutre et bonne gardent tout. Même
  garde dans `RS_MissionVoice.start` (refus `reputation`). L'acceptation revalide le même catalogue.
- **Contexte LLM (E04-T10, Q10)** : `R.publicContext` = `{level, last = {act, about}}` dans `context.reputation` du
  PNJ en face (`RS_Carnet_Server.talk`) et des groupes à la radio (`RS_GroupRadio.talk`), et champ `reputation=` des
  voix (`RadioSurvivor_Server`, écrit par `RS_Transport`) ; consigne `npc_protocol.reputation_sentence` (peut en
  parler, ne l'invente ni ne la change). Protocole : [protocole-carnet-v2.md](../protocole-carnet-v2.md).
- **Marge du passeur (E04-T11, Q13)** : `RS_Trade` (`marginFloor`) : base du niveau (0,10 / 0,25 / 0,40), rabais
  d'historique, tricherie 0,50 ([passeur-table.md](../passeur-table.md)).
- **Accueil d'un groupe inconnu (E04-T11, Q14)** : `LK_Hostility.startForPlayer` (crochet
  `LivingKnox.Hooks.reputation` posé par `RS_Carnet_Server`), un cran au premier contact seulement
  ([attitude.md](attitude.md)).
- **Essais et administration (E04-T14, Q17)** : `R.testSetLevel` (parties `rstest*` en mode debug seulement,
  `LivingKnox.API.testAllowed`) ; commande `rep_admin` du carnet : vue en lecture seule (nom, niveau, tendance,
  derniers actes) pour un administrateur (`RS_FreqDebug.isAllowed` : `checkPermissions` + capacité `PopmanManage` du
  rôle sur un serveur, mode debug en solo), bouton « Toutes les réputations (admin) » de l'onglet. Suite en jeu
  `rs.reputation` (+ base `mp-persist`).
