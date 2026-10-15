# Contrat RadioSurvivor ↔ CharacterReputation

Version du contrat : **RSREP-1** (brouillon du 2026-10-13, tâche `E04-T02`). Cible : Project Zomboid 42.21, serveur
dédié, hôte et solo. Statut : **à relire par l'utilisateur** ; aucun code n'est livré par ce document.

Ce document fixe le **sous-ensemble** de l'API de CharacterReputation dont RadioSurvivor a besoin, et ce que fait
RadioSurvivor quand un appel manque ou échoue. Il ne conçoit pas le service de réputation : celui-ci suit son propre
plan dans `Zomboid\Workshop\CharacterReputation` (proposition `docs/proposition-api-reputation.md`). Les noms de
fonctions ci-dessous sont ceux que l'adaptateur `RS_Reputation.lua` (`E04-T03`) appellera ; si CharacterReputation
retient d'autres noms, seul cet adaptateur change.

Sources : décisions `E04-T01` ([plan E04](plan/E04-reputation.md)) ; ADR B15 de la
[spécification](bandits-llm-specifications.md) ; identité du carnet `E00-T01` et mort `E00-T02`
([carnet-implementation-04221.md](carnet-implementation-04221.md), « Identité de personnage », « Mort d'un joueur ») ;
missions `RS_Missions.lua` (`M.finish`) ; état actuel `RS_Reputation.lua` ; coquille installée
`CharacterReputation.lua` 0.1.0 (`getDescriptor()`, capacités toutes fausses).

## 1. Principes

- **Une seule réputation globale par personnage**, détenue par CharacterReputation. RadioSurvivor n'en tient
  **aucune copie** et ne calcule **aucun score de substitution** (décision B15, `E04-T03`).
- **Autorité serveur.** Tous les appels de ce contrat sont faits par le serveur (ou en solo par la machine unique),
  depuis `media/lua/server`. Aucune commande client ne choisit un personnage, un montant ni un motif. Le client reçoit
  seulement la projection du carnet (section 6).
- **RadioSurvivor fixe les montants** (`RS_Config.Reputation` : réussite +5, échec et abandon −5, demandeur tué −50,
  provisoires) ; CharacterReputation borne, historise et déduplique.
- **Faits antérieurs ignorés** (décision `E04-T01` (2)) : un fait clos quand l'API n'était pas disponible n'est
  **jamais** envoyé plus tard.
- **Pas de secret transmis** : ni texte du LLM, ni code de mission, ni position de foyer, ni fréquence secrète dans un
  motif ou une preuve.
- La confiance personnelle d'un PNJ (carnet) et l'attitude d'un groupe Living Knox (`LK11-T03`) restent **séparées** :
  un même fait de mission peut alimenter les deux, aucune ne se calcule à partir de l'autre
  ([attitude.md](conception/attitude.md)).

## 2. Détection de version et de capacités

**Accès.** Par la globale `CharacterReputation` (le `mod.info` de RadioSurvivor déclare
`loadModAfter=\batman_CharacterReputation`). Jamais par `require "CharacterReputation/..."` : un `require` d'un
fichier absent écrit un avertissement `require(...) failed` à chaque chargement.

**Appel.** `CharacterReputation.getDescriptor()` → table neuve :

| Champ | Exigence RSREP-1 |
| --- | --- |
| `modId` | `"batman_CharacterReputation"` |
| `apiVersion` | chaîne `"M.m.p"` ; **majeure = 1** (une majeure différente = incompatible ; mineure quelconque) |
| `status` | informatif (`"scaffold"`, `"ready"`…) ; n'accorde rien seul |
| `capabilities.characterIdentity` | requis |
| `capabilities.recordEvent` | requis |
| `capabilities.reputationRead` | requis (niveau) |
| `capabilities.persistence` | requis (sans persistance, la déduplication ne survit pas au redémarrage) |
| `capabilities.history` | facultatif (derniers motifs) ; **capacité à ajouter** au descripteur de CharacterReputation |

**Moment.** Évaluée une fois à l'initialisation du carnet (`init` sur `OnServerStarted` en MP, `OnGameStart` en solo,
après le chargement de tous les Lua), puis gardée pour la session. Une erreur levée par un appel ultérieur fait passer l'état à `error` pour la
session (section 7).

**États de l'adaptateur** : `ready` (tout requis présent), `missing` (globale ou `getDescriptor` absents),
`incompatible` (majeure ≠ 1 ou capacité requise fausse : cas de la coquille 0.1.0 actuelle), `error` (appel en erreur).
Seul `ready` envoie des faits.

**Repli** : tout état autre que `ready` = comportement actuel inchangé (onglet « service indisponible »,
`context.reputation = 'unavailable'`, faits gardés `applied=false`, `status='api_unavailable'`). Un message console
en anglais, **une seule fois** par session, nomme l'état et la version lue.

## 3. Identité de personnage côté serveur

**Lien avec le carnet (`E00-T01`).** Le carnet a sa propre identité `character-…` (ModData serveur
`RS_CarnetCharacter`, contrôles compte + slot, retirée à la mort `E00-T02`). CharacterReputation a **la sienne**,
opaque pour RadioSurvivor. RadioSurvivor ne fabrique jamais l'identité de réputation et n'utilise ni compte, ni
SteamID, ni `onlineId`.

| Appel | Contrat attendu |
| --- | --- |
| `R.characterOf(player)` | `player` = `IsoPlayer` présent sur le serveur. Rend `subjectId` (chaîne non vide, stable pour ce personnage : reconnexion, redémarrage, changement de nom ; nouvelle après la mort et un nouveau personnage ; distincte entre deux personnages homonymes et entre slots d'écran partagé), ou `nil, code`. Sans effet de bord visible du joueur. |

`R` est le module rendu par `CharacterReputation.forMod("batman_RadioSurvivor")` (provenance des écritures, côté
serveur seulement).

**Quand.** À chaque liaison du carnet (`identity()` dans `RS_Carnet_Server.lua`, au `hello` ou à la reconnexion),
quand l'état est `ready`. RadioSurvivor mémorise le résultat dans **son état privé** :
`characters[<id carnet>].reputationId = subjectId`. Les faits d'un participant **hors ligne** (mission close sans
lui) utilisent cette valeur mémorisée : le service n'a pas besoin du joueur connecté pour écrire.

**Cas particuliers.**
- `characterOf` rend un `subjectId` différent de celui mémorisé : CharacterReputation fait foi ; la nouvelle valeur
  remplace l'ancienne, avertissement console (anglais).
- `characterOf` rend `nil, code` : aucune valeur mémorisée ; repli ci-dessous.
- Personnage mort (`retired` dans le carnet) : sa valeur mémorisée reste valable pour ses faits déjà clos ;
  RadioSurvivor ne signale pas la mort au service (le nouveau personnage reçoit une nouvelle identité des deux côtés).

**Repli.** Un fait d'un personnage sans `reputationId` mémorisé prend `status='identity_pending'` ; il est envoyé à
la prochaine liaison réussie de ce personnage, avec le même identifiant d'événement. Un personnage mort sans jamais
s'être relié garde ses faits en attente, sans effet (choix C2, section 9).

## 4. `recordEvent` idempotent

| Appel | Contrat attendu |
| --- | --- |
| `R.recordEvent(event)` | Applique `delta` à la réputation globale de `event.subject`, une seule fois par `eventId`. Rend `result` ou `nil, code`. |

Champs de `event` envoyés par RadioSurvivor :

| Champ | Type | Contenu |
| --- | --- | --- |
| `subject` | chaîne | `reputationId` mémorisé (section 3) |
| `eventId` | chaîne ≤ 128 octets ASCII | `rs:` + identifiant du fait déjà utilisé par le carnet : `rs:<mission>-<carnet>-result` pour un résultat de mission, `rs:<npc>-killed-<carnet>` pour le demandeur tué (`E04-T07`). Unique dans le monde : `<mission>` et `<carnet>` viennent de `S.uid` (horodatage, compteur, aléa). |
| `action` | chaîne | code stable : `mission.` + résultat de `M.finish` (`mission.success`, `mission.failed`, `mission.abandoned`, actuels dans `outcomes`), `npc.requesterKilled` |
| `delta` | entier | montant de `RS_Config.Reputation` ; jamais 0 (un fait sans effet n'est pas envoyé) |
| `reasonKey` | chaîne | clé de traduction du motif affiché, livrée par RadioSurvivor en EN et FR (`IGUI_RS_RepReason_<Action>`) |
| `reasonArgs` | table de chaînes, facultative | arguments publics du motif (nom affiché du PNJ demandeur) |
| `proof` | table plate, petite | `{mission=<id>, template=<gabarit>, npc=<id carnet du PNJ>, result=<résultat>}` ; serveur seulement, jamais montrée à un autre joueur |

`result` attendu : `{status = 'applied' | 'duplicate', before, after, appliedDelta, entryId}`. `duplicate` = même
`eventId` déjà appliqué avec le même contenu (aucun nouvel effet).

**Garanties exigées du service** : déduplication durable par `(provenance, subject, eventId)`, y compris après
redémarrage ; même `eventId` avec un autre contenu refusé (`event_conflict`) ; aucun effet partiel sur erreur ;
appel synchrone sur le fil Lua du serveur.

**Ordre d'écriture côté RadioSurvivor** (pour qu'un fait ne soit jamais appliqué deux fois) :
1. le fait est écrit dans `outcomes[eventId]` avec `status='sending'`, et l'état privé sauvegardé ;
2. appel `recordEvent` ;
3. `applied` ou `duplicate` → `applied=true`, `status='applied'` ; sauvegarde.

Un arrêt entre 1 et 3 laisse `sending` : au démarrage suivant (état `ready`), le fait est renvoyé avec le même
`eventId` ; le service répond `duplicate` s'il l'avait déjà appliqué.

**Missions de groupe.** Un appel par participant inscrit, même `action` et même `delta` pour tous (décision B15) ; la
capacité `groupResults` du service n'est pas utilisée. Les annulations (`cancelled_*` : demandeur mort, offre close)
n'envoient rien.

**Replis.**

| Réponse | Traitement RadioSurvivor |
| --- | --- |
| état ≠ `ready` au moment du fait | `applied=false`, `status='api_unavailable'`, jamais renvoyé (décision `E04-T01` (2)) |
| pas de `reputationId` | `status='identity_pending'` (section 3) |
| `nil, 'unknown_subject'` ou `nil, 'storage_unavailable'` | `status='sending'` conservé, renvoyé à la prochaine liaison du personnage ou au prochain démarrage |
| `nil, 'event_conflict'`, `nil, 'invalid_argument'` ou autre code | `status='rejected'`, `applied=false`, jamais renvoyé, avertissement console avec le code |
| erreur levée (exception Lua ou Java) | même traitement que `storage_unavailable` pour ce fait, puis état `error` pour la session (section 7) |

## 5. Lecture du niveau et des derniers motifs

| Appel | Contrat attendu |
| --- | --- |
| `R.getLevel(subject)` | Rend `{level = 'bad' \| 'neutral' \| 'good', revision = <entier>}` ou `nil, code`. Un personnage sans fait rend `neutral`, `revision = 0`, sans rien créer. |
| `R.getHistory(subject, {limit = n, order = 'desc'})` | Si `capabilities.history` : `{entries = {…}}`, au plus `n` entrées récentes, **toutes provenances**, chacune `{action, appliedDelta, reasonKey, reasonArgs, sourceModId, worldAgeHours}` ; copies indépendantes. Sinon absent. |

- Les **seuils** entre les trois niveaux appartiennent à CharacterReputation (profil global commun à tous les mods),
  pas à RadioSurvivor. RadioSurvivor ne lit **jamais** la valeur brute : le LLM et le carnet ne reçoivent que
  `level` (`E04-T05`).
- Le carnet lit au plus `n = 5` motifs ; un motif d'un autre mod s'affiche par sa `reasonKey` (traduite par le client
  si la clé existe chez lui, sinon par le code `action`).

**Replis.**
- `getLevel` absent, en erreur ou `nil, code` → `level = 'unavailable'` ; le carnet garde « service indisponible »
  et le contexte du LLM `reputation = 'unavailable'` (comportement actuel).
- `getHistory` absent (capacité fausse) → le carnet montre les faits **de RadioSurvivor seulement**
  (`outcomes` du personnage avec `applied=true`), déjà tenus par le serveur.
- `getHistory` en erreur → liste vide, niveau conservé.

## 6. Projection vers le client

RadioSurvivor n'utilise pas la projection client de CharacterReputation (`clientProjection`). Le serveur ajoute à
l'instantané du carnet (`snapshot`, déjà envoyé au seul joueur concerné) : `reputation = {available, level, reasons}`
où `reasons` = au plus 5 `{reasonKey, reasonArgs, sign}` (`sign` = `+`, `-`). Ni valeur brute, ni preuve, ni données
d'un autre personnage. Le bouton propre au mod de réputation (décision `E04-T01` (3)) relève de CharacterReputation.

## 7. Erreurs et isolement

- Chaque appel au service passe par une seule fonction de l'adaptateur, protégée par `pcall` **à la frontière** du
  mod optionnel : une erreur du service ne doit pas interrompre `M.finish`, la liaison du carnet ni l'instantané.
  L'erreur est écrite en console (anglais, première occurrence de la session) et l'état passe à `error` : plus aucun
  appel au service jusqu'au prochain démarrage.
- Les arguments invalides construits par RadioSurvivor sont des bogues du mod : ils sont testés dans le banc de
  l'adaptateur avec une fausse API conforme à ce contrat (`E04-T03`), pas masqués.

## 8. Comportement sans le mod

CharacterReputation reste **facultatif** (`loadModAfter`, pas `require=`). Absent, désactivé, coquille ou version
incompatible : RadioSurvivor fonctionne comme aujourd'hui — missions, récompenses en objets, confiance personnelle
qualitative des PNJ, onglet Réputation en « service indisponible », faits gardés comme preuves `applied=false`, aucun
score local. L'ajout ou le retrait du mod en cours de partie ne reprend aucun fait ancien (section 2).

## 9. Choix pris sans l'utilisateur (à confirmer)

- **C1 — identité mémorisée** : le `subjectId` de CharacterReputation est relevé à la liaison du carnet et gardé dans
  l'état privé de RadioSurvivor, pour écrire les faits d'un participant hors ligne.
- **C2 — fait en attente d'identité** : un fait clos pendant que le service est `ready` mais avant toute liaison du
  personnage attend sa prochaine liaison (jamais pour un personnage mort entre-temps). Ce n'est pas un « fait
  antérieur à l'API » au sens de `E04-T01` (2), qui reste ignoré.
- **C3 — niveaux calculés par le service** : les trois niveaux et leurs seuils sont fournis par CharacterReputation
  (`getLevel`), pour que tous les mods voient le même niveau.
- **C4 — majeure 1** : RSREP-1 exige `apiVersion` 1.x ; la coquille actuelle (0.1.0) est donc `incompatible`.
- **C5 — capacité `history`** à ajouter au descripteur, facultative ; repli sur les faits de RadioSurvivor.
- **C6 — motifs traduits par clé** : `reasonKey` + `reasonArgs` plutôt qu'un texte composé, pour que chaque joueur
  lise le motif dans sa langue.

## 10. Hors périmètre et renvois

- Incidents de langage envers un PNJ (ADR R03, proposé seulement), PvP, vols : aucune action réservée par RSREP-1.
- Réputation de faction, cibles multiples, import ou migration : non utilisés.
- **Renvoi à ajouter** dans `CharacterReputation/docs/proposition-api-reputation.md` (autre dépôt, non modifié par
  cette tâche) : une ligne « Consommateur RadioSurvivor : contrat RSREP-1, `RadioSurvivor/docs/reputation-contract.md` »
  dans la section « Contrat API proposé », et la capacité `history` au descripteur.
- Le lien `reputation-api-specifications.md` cité par la spécification et par la proposition n'existe pas dans le
  dépôt.
