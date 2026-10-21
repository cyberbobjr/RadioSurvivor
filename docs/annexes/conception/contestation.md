# Contestation et refus d'un membre incarné (E10-T03)

Brouillon du 2026-10-13. Code : `server/LivingKnox/LK_Decisions.lua` (bloc « E10-T03 » : `loyaltyOf`,
`loyaltyOfMember`, `refusalOf`, `judgeOrder`, `refuseDuties`, `judgeDefense`, `flushRefusals`),
`server/LivingKnox/LK_Expeditions.lua` (`teamOf`), `server/RS_Carnet_Server.lua` (`Server.memberReactions`,
`memberReply`), `shared/RadioSurvivor/RS_LivingKnox.lua` (`loyalty`, `dissent`), `shared/RadioSurvivor/RS_NPCProvider.lua`
(opérations facultatives `loyalty`, `dissent`), `bridge/npc_protocol.py` (genre `npc_member`). Contrat :
[protocole-carnet-v2.md](../../specifications-techniques/protocole-carnet-v2.md), « Réaction des membres (E10-T03) ». Banc : `tests/test_lk_contest.py` ;
suite en jeu `lk.contest`.

## Deux chemins (décision Q2 du 2026-10-10, option A « mixte »)

1. **Ordre du moteur** (LK05-T02) : refus **déterministe, sans LLM**, par des règles simples. Ordres jugés :
   - `guard` : poste `sentry` donné par la notation horaire (`scoreGroup`) ;
   - `expedition` : départ dans l'équipe d'une expédition physique (`LK_Expeditions.teamOf`, avec `gid`) ;
   - `defend` : place de combat (rôle `post`) dans la défense du foyer (`LK_Defense`), jugée à chaque évaluation.
   Règles, dans l'ordre : chef (ne refuse jamais) ; **blessure** (santé de référence < 60 %) ; **moral** (loyauté
   `wavering`) ; **attitude** (défense contre un joueur que le groupe apprécie : `trusting`, `favorable`) ; **rôle**
   (ordre que les comportements du rôle ne permettent pas : guet sans `guard`/`patrol`/`defend`, expédition sans
   comportement de fouille ; tout rôle défend depuis LK06-T07).
2. **Intention collective née d'une conversation** (E10-T02 : mission de groupe offerte ou acceptée, accord de faction
   conclu) : chaque membre incarné du groupe (corps chargé sur le serveur, chef exclu), au plus
   `Server.MEMBER_REACTIONS` = 2 par décision et dans les quotas du pont (`MAX_PENDING`, `MAX_PER_HOUR`), reçoit une
   demande `npc_member` ; le modèle qui joue le membre choisit `accept` (silencieux), `contest` ou `refuse`.

## Loyauté (sans champ persistant)

`loyauté = moral du groupe + 20 x ancienneté` (ancienneté = 1 pour le plus ancien vivant, 0 pour le dernier arrivé,
rang = numéro de membre, `Groups` : « plus petit = plus ancien ») ; `>= 60` : `loyal`, `< 30` : `wavering`, sinon
`steady`. Calculée à chaque demande : `personality.loyalty` de la requête (copie) vaut cette valeur pour un PNJ de
Living Knox (`Provider.loyalty`) ; la fiche garde la valeur de base `current_group` (aucun champ nouveau).

## Conséquence bornée

- Ordre du moteur refusé : le membre n'exécute pas l'ordre (un autre prend le guet, l'équipe part sans lui, il quitte
  sa place de combat et ne combat aucun joueur ; un zombie à portée reste combattu, LK06-T07). Il garde mémoire et
  appartenance. Le refus vaut 240 minutes de jeu pour la même instance d'ordre (mémoire seulement, oublié au
  redémarrage), puis il est rejugé.
- Réaction `contest` / `refuse` : la décision n'est pas annulée (un membre n'a rien à exécuter dans une mission de
  groupe, menée par les joueurs, ni dans un accord, appliqué par le moteur) ; le membre reste dans le groupe ; aucun
  changement de groupe (le départ est E10-T04).

## Traces

- Journal du groupe : `refusal` (ordre du moteur : « m-3 refused the guard order: morale (loyalty 27 < 30) ») ;
  `contest` / `refusal` (réaction : « <nom> contested a group decision: <fait> »). Faits anglais composés par le
  serveur, jamais la réplique du modèle. Le journal de récit public (`LK_Journal`, liste fermée) les ignore.
- Audible : réplique de gabarit `IGUI_LK_Refuse_<ordre>_<raison>` (EN, FR) par `LivingKnox.Speech.say` (LK11-T04),
  traduite par chaque client ; réplique du modèle (200 octets au plus, limite de `LK_Speech`) par le même canal pour
  une réaction. Les personnages qui connaissent déjà ce membre gardent sa réplique dans l'historique du carnet.

## Choix pris sans l'utilisateur (à confirmer)

1. Seuils : santé 60 %, loyauté 30 / 60, bonus d'ancienneté 20, maintien 240 minutes, 2 réactions par décision.
2. « Attitude » lue comme l'attitude du groupe envers le joueur visé par une défense (aucune attitude propre à un
   membre n'existe) ; la règle ne joue donc que pour `defend`.
3. Réaction `accept` silencieuse (ni réplique ni journal) ; `none` du modèle compte comme `accept`.
4. Les accords de faction (E09-T05) déclenchent aussi les réactions (fait : « The leader concluded a truce with ... »).
5. Membres concernés = membres du groupe dont le corps est chargé sur le serveur (fiche du carnet créée au besoin,
   sans enrichissement).

## Hors périmètre

- Contestation hors écran : événement `conflict` de LK09-T05 (aucune règle ajoutée ici : un membre non incarné n'est
  jamais jugé).
- Départ du groupe : E10-T04.
- La place de défense refusée reste affectée dans le plan de `LK_Defense` (mémoire) : la défense compte ce membre
  absent jusqu'à la fin de l'alerte.

## Idées reprises

Aucune.
