# Relation personnelle d'un PNJ envers un personnage (E09-T04)

- Tâche : E09-T04 ; panneau de relation du carnet : E09-T07 ; réplique gardée quand le changement est refusé : E09-T08
- Build : 42.21.0 — Date : 2026-10-13 — Statut : brouillon

Code (depuis E18-T21) : `server/LivingKnox/LK_PersonalRelation.lua` du mod `batman_LivingKnox` (registre, faits du
groupe, vérification, panneau, purge ; état privé de Living Knox), `server/LivingKnox/LK_API.lua` (`API.relation`,
`API.relationPanel`, `API.relationOffer`, `API.relationApply`, `API.attitudeFacts`), `server/LivingKnox/LK_Hostility.lua`
(numéro `n` des faits, `Hostility.facts`) ; côté RadioSurvivor, `server/RadioSurvivor/RS_Relations.lua` (lecture par
l'API de Living Knox, faits citables propres au carnet, accords du panneau) et `server/RS_Carnet_Server.lua` (`talk` :
contexte `relation` et liaison `Server.relations` ; `reply` : intention `change_relation` ; `projection`),
`bridge/npc_protocol.py` (`relation_facts`, `relation_prompt`, `bounded_reply`). Contrat :
[protocole-carnet-v2.md](../../specifications-techniques/protocole-carnet-v2.md), « Relation personnelle (E09-T04) ». Socle collectif :
[attitude.md](attitude.md). ADR B07, B08, B11, B15 de [bandits-llm-specifications.md](../recherches/bandits-llm-specifications.md).

## Problème

Deux membres d'un même groupe doivent pouvoir voir différemment un même personnage, selon ce qu'ils ont vécu et ce
que le modèle qui les joue en a conclu, sans que des mots seuls (« je vous ai sauvé la vie ») changent quoi que ce
soit, et sans désaccorder l'attitude collective du groupe (`LK_Hostility`), qui commande déjà le choix de cible.

## Contraintes du moteur

| Fait | Preuve | Statut |
|---|---|---|
| Aucune ModData globale pour un état privé (lisible par tout client). | base `multiplayer.md` | confirmé statiquement |
| L'état privé (Living Knox depuis E18-T21) est un fichier du serveur, sauvegardé à deux emplacements. | `RC_SlotFile.lua` | confirmé (bancs) |
| Clé de personnage : identité du carnet, la même que `LK_Hostility.keyOf`. | [attitude.md](attitude.md) | confirmé (bancs) |
| Un client MP charge `media/lua/server` : garde `isClient()` en tête. | base `mod-loading.md` | confirmé statiquement |

## Choix

Décision de l'utilisateur du 2026-10-13 : **écart personnel borné à un niveau au-dessus ou au-dessous de l'attitude
du groupe** (option recommandée).

### Registre

État privé de **Living Knox** (E18-T21, décision confirmée par défaut le 2026-11-06 : la relation appartient au moteur
des PNJ, règle d'or « RadioSurvivor et Living Knox vivent l'un sans l'autre ») :
`Zomboid/Lua/batman_LivingKnox/personal-relations-<partie>-<0|1>.txt` (deux emplacements `RC_SlotFile`, en-tête
`LKPREL1`), `relations[<PNJ Living Knox lk-n>][<personnage>] = { gap = -1..1, revision, changes = { { sign, day, fact,
what } } (3 derniers), used = { clé de fait, ... } (64 derniers) }` ; créé au premier changement seulement, écrit à
chaque changement. Purgé au démarrage, chaque jour de jeu et à la mort d'un personnage (identité retirée du mod
commun) : PNJ disparu du registre de Living Knox, personnage retiré. Aucune reprise d'une partie d'avant la séparation
(décision de l'utilisateur du 2026-11-06 : mod jamais publié, toute partie repart de zéro).

Faits citables : ceux du groupe viennent de Living Knox ; l'appelant ajoute les siens dans `extra`, la même liste à
l'offre et à la réponse. Le carnet de RadioSurvivor y met les observations vues par ce PNJ (`obs:`) et les missions
closes de ce PNJ avec le personnage (`mis:`) ; avec Living Knox seul, seuls les faits du groupe sont citables tant que
la parole des PNJ sans RadioSurvivor (E18-T18) n'existe pas.

### Niveau et tendance affichés

- Niveau = niveau de l'attitude du groupe (`API.attitude`) décalé de l'écart, borné à `hostile`..`trusting`
  (5 niveaux d'E09-T01). Sans attitude de groupe : `hostile` si le type du groupe part hostile, sinon `cautious`.
- Tendance (règle d'E09-T01) : signe de la somme des sens des trois derniers faits, faits du groupe et changements
  personnels mêlés par jour de jeu (faits du groupe d'abord le même jour) ; sans changement personnel, tendance du
  groupe.
- Le registre ne recalcule jamais l'attitude du groupe : `LK_Hostility` reste seul maître de la valeur collective.

### Faits citables (réels, connus de CE PNJ, de nature connue)

| Source | Clé (serveur seulement) | Sens |
|---|---|---|
| `group` : faits de `LK_Hostility` du groupe du PNJ envers le personnage (vus ou attribuables, les 3 gardés) | `att:<groupe>:<n>` | signe du fait |
| `seen` : observation du PNJ vue par lui (`RS_Observations`, source `seen`, sujet = le personnage) | `obs:<clé>` | `mission_done` +1, `assault_seen` −1 |
| `mission` : mission close de ce PNJ à laquelle le personnage a participé | `mis:<id>` | `success` +1, `failed` et `abandoned` −1 |

Écartés : ouï-dire (`heard_from`), `player_return` (nature inconnue), missions annulées ou expirées, faits déjà utilisés
pour cette relation, faits dans un sens que l'écart ne permet plus. Au plus 8 faits par demande.

### Changement

1. `talk` joint `context.relation = { level, trend, group, facts }` (identifiants courts `f<i>`, nature, source, jour) et
   garde la liaison `Server.relations[<demande>] = { character, revision, ids }` en mémoire.
2. Le modèle rend `intent = change_relation`, `dir`, `fact` ; le pont refuse un fait non offert ou un sens contraire à
   sa nature (réplique gardée sans effet).
3. `reply` → `RS_Relations.apply` revérifie : personnage, révision de la relation (révision de la fiche déjà vérifiée),
   fait offert, jamais utilisé, toujours connu du PNJ, sens, borne ±1. Appliqué : écart ±1, révision +1, fait marqué
   utilisé. Refusé (E09-T08) : seul le changement est ignoré, la réplique est dite comme une réponse `none` et le
   motif est journalisé (`[RS_Carnet] relation change of <fiche> toward <personnage> in <demande> ignored, reply
   kept: <motif>`, anglais).

**Décision E09-T08 (2026-10-14, utilisateur)** : un `change_relation` refusé par le serveur (fait inventé ou non
proposé, déjà utilisé, sens contraire à sa nature, écart déjà à ±1, révision de la relation périmée) ne fait plus
perdre la réplique ; il est seulement ignoré. Raison : la phrase du PNJ reste vraie sans le changement, aucun autre
effet n'en dépend, et le joueur voyait « pas de réponse » pour un détail interne. Une **révision de fiche** périmée
(`NPC revision changed`, vérifiée avant toute intention) refuse toujours toute la réponse : la fiche a changé
pendant que le modèle répondait (mort puis retour, autre incarnation), donc la réplique elle-même a été écrite pour
un PNJ qui n'est plus le même, pas seulement le changement de relation ; tous les autres contrôles de la demande sont
périmés aussi. Les autres refus de forme (`relation fields without intent`, intention invalide) restent des refus
de la réponse entière : réponse mal formée, pas un changement refusé.

Un même fait peut motiver un changement chez **chaque** PNJ qui le connaît (relations distinctes), une seule fois par
relation.

## Panneau du carnet (E09-T07)

Code : `RS_Relations.panel` (serveur), `RS_Carnet_Server` (`projection` : `contacts[i].relation`) ; depuis `E18-T26`,
le panneau est dessiné par Living Knox (`client/LivingKnox/LK_NotebookPages.lua` : `Notebook.relationLines`, fiche de
l'onglet Contacts du carnet commun, section « Ce qu'on pense de vous »), clés `IGUI_LK_Rel*` (EN, FR) ; avec Living Knox
seul, ses PNJ connus arrivent par la source `lk` du commun (`LK_Contacts`, `LK_PersonalRelation.panel`).

- **Projection par personnage** : chaque instantané n'est construit que pour le personnage lié au joueur qui le
  reçoit (`Server.bound[player]`) ; la relation lue est la paire (fiche du PNJ, ce personnage) et les accords sont
  ceux du groupe du PNJ avec l'équipe de ce joueur (`RS_Factions.projection`). Rien d'un autre personnage n'est lu.
- **Contenu envoyé** (identifiants et jours de jeu seulement, aucune clé de traduction, aucun texte serveur) :
  `{ level, trend, group, today, facts, agreements, suspended }`.
  - `level`, `trend` : niveau et tendance de la relation (5 niveaux, `up`/`down`/`stable`) ; `group` : niveau du
    groupe (le client ne l'affiche que s'il diffère).
  - `facts` : les **3 derniers** faits qui expliquent l'attitude, fusionnés par jour comme la tendance : faits
    d'attitude du groupe envers CE personnage (`LK_Hostility`, vus ou attribuables) et changements personnels de ce
    PNJ (`changes[i].what` = nature du fait cité, enregistrée depuis E09-T07). Chacun : `{ fact, nature, source =
    group | personal, day }`.
  - `agreements` : accord du groupe avec l'équipe du lecteur (`truce`, `alliance`, ou `none` rompu ; état `pending`,
    `applicable`, `broken`) et trêve personnelle gardée par un PNJ parti (`kept`, E10-T04), avec leur portée
    explicite : `group` = `all_members` (ou `this_npc` pour une trêve gardée), `team` = `current_members` (faction
    vanilla) ou `you` (équipe personnelle).
  - `suspended` : le lecteur est l'auteur d'un incident ouvert avec ce groupe (E09-T06, protection perdue).
- **Jamais envoyés** : écart personnel, valeur d'attitude, clés de faits (`att:`, `obs:`, `mis:`), révisions,
  identifiants de groupe, d'équipe ou d'accord, faits d'un autre personnage.
- **Rendu client** : libellés traduits par `getText` côté client ; date en mots (aujourd'hui, hier, cette semaine,
  il y a un moment), donc **aucun nombre** dans le panneau ; identifiant inconnu (serveur plus récent) : mot générique
  (`RelKind_other`, `RelFact_good`...), jamais de clé brute. Sans relation ou sans niveau : « Attitude envers vous :
  inconnue ».
- **« Inconnu »** : un PNJ sans base de groupe (`Provider.relation` nil) et sans changement personnel n'envoie ni
  `level` ni `group` (le niveau par défaut `cautious` du contexte du modèle n'est pas montré comme un fait).
- Anciennes lignes « Confiance personnelle » / « Tendance » (`trustKey`, `trendKey`, `IGUI_RS_Trust*`,
  `IGUI_RS_Trend*`, `TrustScope`, `NoAgreements`) et accords textuels `npc.agreements` du carnet 0.2 retirés de la
  fiche ; `known.trust` reste lu par la radio de groupe.

Tests : `tests/test_relation_panel.py` (6 tests : deux membres d'un même groupe aux relations différentes pour alice,
projection propre de bob de la même faction, aucun fait de l'un chez l'autre, accord et portée, rendu anglais réel
sans clé ni nombre, page du carnet, équipe personnelle et suspension, « inconnu », identifiants inconnus, clés FR) ;
en jeu : `RST.run({ suite = "rs.notebook.relation", tags = "world" })` (campagne `solo-rs`).

## Alternatives écartées

- Le LLM ne touche que l'attitude du groupe par des faits de `LK_Hostility` : deux membres ne pourraient plus différer.
- Relation entièrement indépendante du groupe : contredirait le choix de cible, fondé sur l'attitude collective.
- Changement sur la seule foi des paroles : refusé par les ADR B11 et B15 (une phrase ne prouve rien).
- Clés de faits envoyées au pont : inutiles au modèle, identifiants internes ; identifiants courts par demande.

## Tests

- Banc lupa `tests/test_relations.py` (10 tests) : une aide puis une trahison motivent deux changements (bout en bout,
  pont hors ligne `RS_OFFLINE_INTENT=relation`), aucun fait offert ni changement sans fait réel, fait déjà utilisé et
  sens contraire refusés, révision de relation périmée (changement ignoré, réplique dite) ou de fiche périmée (réponse
  refusée), deux PNJ d'un même groupe qui diffèrent, écart borné à ±1, observation vue et mission close citables
  (ouï-dire et retour neutre exclus), purge ; E09-T08 : bout en bout par `reply`, chaque motif de refus (aucune
  liaison, fait non offert, fait inconnu, sens contraire, déjà utilisé, écart à la borne) garde la réplique, laisse la
  relation inchangée et journalise le motif ; un changement valide reste appliqué avec sa réplique.
- `tests/test_protocol.py` : `scenario_relation_change` (RSV2, prompt, `bounded_reply`, `model_reply`, pont hors ligne).
- En jeu : suite `rs.relation` (`RST.run({ suite = "rs.relation", tags = "world" })`, solo, pont et vrai modèle).

## Points ouverts

- ⚠ Décisions à confirmer : sans groupe, départ `cautious` (ou `hostile`) ; `player_return` non citable ; 8 faits par
  demande ; un même fait utilisable par chaque PNJ qui le connaît. (Réponse `change_relation` refusée : tranché par
  E09-T08, réplique gardée.)
- ⚠ Faits enregistrés avant E09-T04 sans numéro : non citables.
- ⚠ Panneau du carnet : fait (E09-T07, section ci-dessus). Décisions à confirmer : 3 faits affichés ; date en mots
  sans nombre ; « inconnu » pour un PNJ sans groupe ni changement personnel ; accords rompus affichés ; changements
  personnels antérieurs à E09-T07 affichés en « quelque chose que vous avez fait pour / contre eux ».
- ⚠ MP non essayé (séance finale) ; essai solo avec le vrai modèle à faire.
