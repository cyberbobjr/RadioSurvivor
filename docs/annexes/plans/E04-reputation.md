# E04 — Réputation interne (CharacterReputation facultatif)

**Objectif.** Donner à chaque personnage une **réputation tenue par le serveur de RadioSurvivor**, bâtie sur les faits déjà confirmés par le serveur (fins de mission, tricherie au passeur, mort d'un PNJ attribuée ; mêmes points de capture que la chronique `rs.facts`), lue par le carnet, les PNJ et les voix (niveau seulement), et qui a des effets en jeu (offres de missions, missions de rachat, marge du passeur, accueil des groupes, sanction du tueur d'un demandeur). Si l'API de CharacterReputation arrive, un adaptateur facultatif lui transmet les mêmes faits (contrat RSREP-1).

**Dépend de.** Rien d'extérieur : l'étape ne dépend plus de l'API métier de CharacterReputation (`Zomboid\Workshop\CharacterReputation`, toujours une coquille : `getDescriptor()`, capacités toutes fausses), sauf l'adaptateur `E04-T13`.

**Sources.** Conception proposée [reputation-interne.md](../conception/reputation-interne.md) ; spécification ADR B15 et points 18 à 30 ; contrat [RSREP-1](../../specifications-techniques/reputation-contract.md) ; chronique [chronique.md](../conception/chronique.md) (`RS_Facts.lua`) ; attribution du tueur `E04-T06` ([corps-registre.md](../conception/corps-registre.md), `Bodies.deathCause`) ; attitude des groupes [attitude.md](../conception/attitude.md) (`LK11-T03`) ; barème du passeur [passeur-table.md](../../specifications-techniques/passeur-table.md) ; `RS_Reputation.lua` (preuves `applied=false`) ; base `multiplayer.md` (« tueur d'un zombie connu du serveur », aucun secret en ModData globale).

## Décisions

- Acquises (spécification) : réputation par personnage, globale et unique, trois niveaux visibles (mauvaise, neutre, bonne) avec les derniers actes, départ neutre, amélioration par les actes seulement (aucune amélioration automatique par le temps), missions simples toujours possibles pour se racheter, même résultat pour tous les participants, même malus pour l'échec et l'abandon, très forte baisse pour le seul tueur du demandeur, aucune pénalité sur une parole seule.
- 2026-10-08 — **E04-T01 (1)** : API métier de CharacterReputation développée **plus tard**, quand les PNJ Living Knox donneront de vraies missions (`E17-T03`) ; elle s'articulera alors avec l'attitude par groupe de Living Knox (`LK11-T03`). D'ici là, les faits restent enregistrés comme non appliqués. **Remplacée** par la décision 8 du 2026-10-14 pour RadioSurvivor.
- 2026-10-08 — **E04-T01 (2)** : les faits enregistrés avant l'arrivée de l'API sont **ignorés** (aucun effet, pas de reprise). Conservée pour l'adaptateur `E04-T13` ; pour la réputation interne, voir la question Q1 (`E04-T08`).
- 2026-10-08 — **E04-T01 (3)** : accès par un onglet « Réputation » du carnet et par un bouton propre au mod CharacterReputation.
- 2026-10-14 — **Décision 8 (utilisateur)** : « Réputation (E04, bloquée par l'API CharacterReputation) : réputation interne de RadioSurvivor côté serveur, bâtie sur les faits déjà journalisés (`rs.facts`), avec un adaptateur optionnel vers CharacterReputation si son API arrive ; réécrire les tâches E04 en conséquence (décisions de détail à me poser une par une). » Conséquences : `E04-T03` abandonnée ; principes « aucune copie, aucun score de substitution » de RSREP-1 (§1, §8) à réviser par `E04-T13` ; nouvelles tâches `E04-T08` à `E04-T14`. Constat de conception : le carnet des faits `rs.facts` ne garde que des noms et se vide en deux jours (bulletin, expiration) : la réputation se capte aux mêmes points et s'inscrit dans le registre durable par personnage `state.outcomes` ([reputation-interne.md](../conception/reputation-interne.md), section 2).
- 2026-10-15 — **Q1 à Q17 : réponse recommandée (a), confirmé par défaut (2026-10-15, l'utilisateur ne souhaite pas être interrogé sur le détail)** : Q1 tout le monde repart neutre, faits antérieurs ignorés ; Q2 une seule réputation globale connue de tous les PNJ et voix du serveur ; Q3 4 réussites de neutre à bonne, 4 échecs ou abandons de neutre à mauvaise ; Q4 aucune usure avec le temps ; Q5 tuer un membre d'un groupe (attribution serveur) = baisse moyenne (−10) ; Q6 gains plafonnés à deux missions par jour de jeu (+10) ; Q7 tueur du demandeur ramené à « mauvaise » (−50) ; Q8 niveau en mots + tendance (en hausse, stable, en baisse) + 5 derniers actes ; Q9 avertissement seulement au changement de niveau (texte au-dessus du personnage + ligne de l'onglet) ; Q10 PNJ et voix connaissent le niveau et le dernier acte public, peuvent en parler sans l'inventer ni le changer ; Q11 mauvaise réputation = missions simples seulement ; Q12 neutre garde l'accès aux missions sensibles, seule la mauvaise les ferme ; Q13 marge du passeur bonne 0,10 / neutre 0,25 / mauvaise 0,40, tricherie 0,50, rabais d'historique en plus ; Q14 un cran de mieux ou de moins au premier contact d'un groupe inconnu, ensuite seuls les actes envers lui ; Q15 réputation visible du seul joueur concerné ; Q16 CharacterReputation reçoit en plus les actes, rien ne change dans RadioSurvivor ; Q17 administrateurs : lecture seule (niveau et derniers actes). Valeurs techniques de la section 9 de la conception confirmées par défaut.
- 2026-10-15 — **E04-T02** : contrat RSREP-1 accepté par défaut (confirmé par défaut, 2026-10-15) ; sa révision RSREP-2 (§1, §5, §8) reste dans `E04-T13`.
- Questions de détail : posées **une par une**, numérotées Q1 à Q17 dans le champ « Reste » des tâches, chacune avec trois réponses (la recommandée en premier). Les valeurs techniques proposées (section 9 de la conception) sont **confirmées par défaut** sauf réponse contraire.
- 2026-10-15 — **E04-T13 sortie du périmètre** : l'adaptateur vers CharacterReputation dépend d'une API externe absente ; tâche abandonnée pour l'instant, à rouvrir quand l'API existera (priorité de l'utilisateur : finir le solo de la radio et du carnet).

## Tâches

- [x] **E04-T01** — Décisions d'intégration de la réputation
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier ; spécification (point 26)
  - Faire : poser les questions une à une, consigner les réponses.
  - Accepté si : décisions consignées et reportées dans la spécification.
  - Tests : —
  - Preuve : décisions du 2026-10-08 (section Décisions) ; renvoi ajouté dans la spécification, ADR B15
  - Reste : —

- [x] **E04-T02** — Contrat RadioSurvivor ↔ CharacterReputation versionné
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E04-T01, E17-T03
  - Fichiers : `docs/specifications-techniques/reputation-contract.md` ; renvoi depuis la proposition d'API de CharacterReputation
  - Faire : sous-ensemble utilisé par RadioSurvivor : identité de personnage côté serveur (lien avec l'identité du carnet E00-T01), `recordEvent` idempotent (identifiant d'événement, motif, delta, preuve), lecture du niveau et des derniers motifs, détection de version et de capacités, comportement sans le mod. Depuis la décision 8 : **cible de l'adaptateur facultatif** `E04-T13`, plus la source de la réputation.
  - Accepté si : contrat relu par l'utilisateur ; chaque appel a un comportement de repli.
  - Tests : —
  - Preuve : contrat `docs/specifications-techniques/reputation-contract.md` RSREP-1 du 2026-10-13 : détection par `CharacterReputation.getDescriptor()` (jamais par `require`), API 1.x et capacités `characterIdentity`, `recordEvent`, `reputationRead`, `persistence` (`history` facultative), états `ready`/`missing`/`incompatible`/`error` (coquille 0.1.0 = `incompatible`) ; identité serveur `R.characterOf` relevée à la liaison du carnet (état privé `reputationId`) ; `recordEvent` idempotent (`eventId` = `rs:` + identifiant du fait, ordre `sending` -> appel -> `applied`, replis par code d'erreur, un appel par participant) ; lecture `getLevel` (`bad`/`neutral`/`good`) et `getHistory` (5 motifs) ; projection par l'instantané du carnet ; sans le mod, comportement inchangé ; run_all 107/108 (plan-check : tâches parallèles) ; documentation seulement ; contrat accepté par défaut le 2026-10-15 (section Décisions)
  - Reste : — (contrat accepté par défaut le 2026-10-15 ; révision RSREP-2, renvoi dans le dépôt CharacterReputation et lien cassé de la spécification repris par `E04-T13`)

- [ ] **E04-T03** — Adaptateur `RS_Reputation` sur l'API réelle
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : E04-T02
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Reputation.lua` ; `RS_Missions.lua` (`finish`)
  - Faire : détecter les capacités ; envoyer les faits terminaux (réussite, échec, abandon) avec identifiant stable ; ignorer les preuves enregistrées avant l'API (décision E04-T01) ; aucun score local de substitution.
  - Accepté si : un fait n'est jamais appliqué deux fois (redémarrage, rejeu) ; sans le mod, comportement actuel inchangé.
  - Tests : banc `lupa` avec une fausse API conforme au contrat ; suite en jeu `rs.reputation`.
  - Preuve : décision 8 de l'utilisateur du 2026-10-14 (section Décisions)
  - Reste : abandonnée le 2026-10-14 (décision 8) : bloquée par l'API métier absente de CharacterReputation et fondée sur « aucun score local », désormais contraire à la décision ; remplacée par la réputation interne (`E04-T08`, `E04-T09`) et par l'adaptateur facultatif `E04-T13`.

- [x] **E04-T04** — Onglet Réputation du carnet avec niveau et motifs
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E04-T09
  - Fichiers : `RS_Notebook.lua` (onglet, lignes 616-620) ; `RS_Carnet_Server.lua` (instantané, lignes 226-231) ; `RS_Reputation.lua` (`projection`) ; traductions (`IGUI_RS_RepReason_*`, niveaux, tendance)
  - Faire : la projection serveur rend `{available = true, level, trend, reasons}` (5 motifs au plus, `reasonKey` + arguments publics + signe) depuis la réputation interne ; l'onglet affiche le niveau en mots, la tendance selon Q8, les derniers actes avec leur motif, la confiance personnelle de chaque PNJ à part ; les lignes « non appliqué » disparaissent ; avertissement au joueur selon Q9.
  - Accepté si : affichage conforme en FR et EN ; aucune donnée d'un autre personnage ; aucun chiffre affiché.
  - Tests : banc `lupa` de la projection ; suite en jeu + protocole visuel.
  - Preuve : commit `6d21937` (onglet Réputation, avertissement de changement de niveau, projection) ; banc `tests/test_reputation.py` 25 OK le 2026-10-15 (dont `test_notebook_tab_and_warning_on_level_change`, `test_projection_has_no_number_and_one_character`) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : rs.reputation 5/5, étapes rep.read et rep.admin PASS, captures `rs_notebook_reputation_*.png` du carnet (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.reputation 5/5, rep.read chez les deux clients (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`)
  - Reste : —

- [x] **E04-T05** — Offres selon la réputation et missions de rachat
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E04-T09
  - Fichiers : `RS_Missions.lua` (`M.offers`, lignes 75-85) ; `RS_Carnet_Server.lua` (`offerCatalog`) ; `RS_MissionVoice.lua` ; `RS_Config.lua` (classe de chaque gabarit)
  - Faire : le serveur filtre les offres admissibles selon le niveau de l'appelant (missions simples toujours possibles, missions sensibles selon Q11 et Q12) ; le LLM reçoit le niveau, jamais un score brut. Classement proposé (confirmé par défaut) : simples = `deliver`, `signal`, `scout`, `clear` ; sensibles = `retrieve`, `recover`, missions de groupe `supply`.
  - Accepté si : une mauvaise réputation reçoit encore une offre simple ; aucune offre sensible refusée par Q11/Q12 n'est proposée ; un nouveau personnage (neutre) garde les offres d'aujourd'hui sauf réponse contraire à Q12.
  - Tests : banc `lupa`.
  - Preuve : commit `6d21937` ; banc `tests/test_reputation.py` 25 OK le 2026-10-15 (`test_offers_and_margin_by_level`, `test_bad_reputation_keeps_simple_offers_only`) ; en jeu : rs.reputation « a bad reputation keeps the simple offers only » PASS en solo (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`) et en MP (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`)
  - Reste : —

- [x] **E04-T06** — Preuve serveur du tueur du demandeur
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E01-T05
  - Fichiers : `docs/annexes/conception/carnet-implementation-04221.md` (section décès) ; `RS_Carnet_Server.lua` (`Server.dead`)
  - Faire : réexaminer la conclusion « bloquée » avec l'entrée de la base (`getAttackedBy` lu à `OnZombieDead` côté serveur) et le code décompilé 42.21 ; mesurer en jeu qui est rapporté pour un coup de mêlée, une arme à feu, un feu, un véhicule.
  - Accepté si : soit une règle d'attribution fiable est démontrée (cas couverts listés), soit le blocage est confirmé avec preuves.
  - Tests : suite `rs.killer` en jeu (PNJ Living Knox créé par `LKB.spawn` + coups ; adaptation du 2026-10-09 après le retrait de Bandits!).
  - Preuve : blocage levé : le serveur décide de la mort d'un zombie et connaît l'attaquant (mêlée, tir, explosif avec lanceur, conducteur) ; règle `Bodies.deathCause` (dernier coup d'un joueur relevé par `OnHitZombie`, attribué s'il date de 5 s au plus ; véhicule par le conducteur ; feu jamais attribué) enregistrée dans `npc.death` et passée à l'écouteur `Bodies.onDied` préparé pour E17-T03 ; tableau des preuves dans `docs/annexes/conception/corps-registre.md` ; `tests/test_lk_bodies.py` 54/54 (`KillerTests`, `KillerSoloTests`), `tests/run_all.py` 21/21 le 2026-10-09 ; serveur dédié de test 6/6 ; suite `rs.killer` ; E03-T04 : commit `0325c28` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.killer 5/5 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.killer 5/5 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : cas bombe, Molotov et voiture à ajouter à `rs.killer` (couverts par le Java et le banc seulement) ; ⚠ tueur « probable » (coup récent suivi d'une mort envoyée par le propriétaire), véhicule sans événement de choc, nom de personnage non stable en solo ; commentaire « attribution bloquée » de `RS_Carnet_Server.lua` à réécrire avec E04-T07

- [x] **E04-T07** — Sanction personnelle du tueur du demandeur
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E04-T06, E04-T09
  - Fichiers : `RS_Carnet_Server.lua` (`Server.dead`, lignes 963-977) ; `RS_Config.lua` (`Reputation.requesterKilled`) ; `RS_Reputation.lua`
  - Faire : à l'événement fournisseur `'death' (id, object, cause)`, si `cause.killer` (compte) se résout en personnage du carnet (même chemin que `LK_Relations.onNpcDied` : `playerByName` puis `Hostility.keyOf`) **et** que ce personnage participe à une mission ouverte de ce PNJ, appliquer la sanction de Q7 à ce seul personnage, une fois par mort (`eventId` `<npc>-killed-<personnage>`) ; aucune accusation venant d'un client ; cas non attribués (feu, piège, mort non relevée) sans sanction ; réécrire le commentaire « attribution bloquée » et `deathAttribution`.
  - Accepté si : coéquipiers épargnés ; double événement de mort sans double sanction ; tueur non participant traité par la règle `npc.memberKilled` d'`E04-T09`, pas par celle-ci.
  - Tests : banc `lupa` + suite en jeu (`rs.reputation`, deux clients).
  - Preuve : commit `a5c6808` ; banc `tests/test_reputation.py` 25 OK le 2026-10-15 (`test_requester_killer_alone_once_team_mates_spared`, `test_non_participant_killer_is_a_member_kill`, `test_unattributed_death_no_sanction`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.reputation « the killer of a requester drops to bad, the team mate is spared » PASS, rep.read du client 2 inchangée (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; solo : même test PASS (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`)
  - Reste : —

- [x] **E04-T08** — Modèle de réputation interne côté serveur
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E04-T01, E04-T06
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Reputation.lua` (réécrit) ; `RS_State.lua` (champ `reputation`) ; `RS_Missions.lua` (ligne 140) ; `RS_TradeExchange.lua` (ligne 297) ; `docs/annexes/conception/reputation-interne.md`
  - Faire : registre par personnage du carnet (E00-T01) dans l'état privé : `reputation[<personnage>] = {score, revision, trend, reasons, gainDay, gainSum}` ; `Rep.record` garde son rôle d'écriture unique dans `outcomes[eventId]` et applique le montant dans le même appel (règles d'`E04-T09`) ; lecture `Rep.level(personnage)`, `Rep.trend`, `Rep.reasons(n)` ; sources en liste fermée captées aux mêmes points que `rs.facts` (fins de mission, tricherie au passeur, mort attribuée d'un PNJ, secours `E12` réservé) ; jamais déduite du carnet `rs.facts` (noms seulement, vidé en deux jours) ; nouveau personnage neutre ; personnage mort (`retired`) plus lu ; faits antérieurs selon Q1 ; portée selon Q2.
  - Accepté si : un fait n'est jamais compté deux fois (rejeu, redémarrage, double événement) ; une mission de groupe donne le même montant à chaque participant ; aucun client ne peut écrire ; la réputation d'un personnage ne dépend pas de sa connexion.
  - Tests : banc `lupa` `tests/test_reputation.py`.
  - Preuve : commit `a5c6808` (modèle interne côté serveur) ; banc `tests/test_reputation.py` 25 OK le 2026-10-15 ; en jeu : rs.reputation « a mission success raises its participant only » PASS en solo (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`) et en MP (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`)
  - Reste : —

- [x] **E04-T09** — Règles de calcul : barème, plafond, usure
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E04-T08
  - Fichiers : `RS_Reputation.lua` ; `RS_Config.lua` (`Reputation`) ; `docs/annexes/conception/reputation-interne.md` (sections 3, 4, 9)
  - Faire : score borné, seuils des trois niveaux, tendance sur les trois derniers faits, montants par action (`mission.success`, `mission.failed`, `mission.abandoned`, `trade.cheated`, `npc.requesterKilled`, `npc.memberKilled`, `rescue.success` réservé), plafond de gain par jour de jeu, usure selon Q4 ; valeurs techniques proposées (confirmées par défaut) : score −100..+100, départ 0, `bad` ≤ −20 < `neutral` < +20 ≤ `good`, +5 / −5 / −5 / −5 / −50, −10 pour un membre de groupe tué (Q5), gains plafonnés à +10 par jour de jeu (Q6), pertes jamais plafonnées.
  - Accepté si : quatre réussites mènent de neutre à bonne (selon Q3) ; un gain au-delà du plafond est noté sans effet ; une série de petites missions n'efface pas un acte grave le même jour ; bornes respectées.
  - Tests : banc `lupa`.
  - Preuve : commit `a5c6808` (barème, plafond, usure) ; banc `tests/test_reputation.py` 25 OK le 2026-10-15 (`test_four_successes_lead_from_neutral_to_good_over_two_days`, `test_four_failures_lead_to_bad_and_losses_are_never_capped`, `test_bounds`, `test_serious_act_not_erased_the_same_day`, `test_trend_on_the_last_three_acts_and_five_reasons`)
  - Reste : —

- [x] **E04-T10** — Réputation lue par les PNJ et les voix (contexte LLM)
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E04-T09
  - Fichiers : `RS_Carnet_Server.lua` (contexte, ligne 356) ; `RS_GroupRadio.lua` (ligne 144) ; `RadioSurvivor_Server.lua` (requête de voix, lignes 445-463) ; pont (`bridge/npc_protocol.py`, prompts) ; `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : remplacer `reputation = 'unavailable'` par le niveau (`bad`, `neutral`, `good`) et, selon Q10, le dernier motif public ; ajouter le champ à la requête des voix radio ; consigne du prompt : le PNJ peut en tenir compte et en parler, sans jamais l'inventer ni la changer ; jamais de score, de preuve, d'identité ni de coordonnée ; contrat Lua ↔ Python mis à jour des deux côtés dans le même commit.
  - Accepté si : le niveau arrive au pont pour un PNJ en face, un groupe à la radio et une voix ; une réponse du LLM ne modifie jamais la réputation ; aucun appel LLM supplémentaire.
  - Tests : banc `lupa` ; `tests/test_protocol.py`.
  - Preuve : commit `6d21937` (contexte LLM) ; banc `tests/test_reputation.py` 25 OK le 2026-10-15 (`test_public_context_level_and_last_act_only`, `test_npc_talk_carries_level_and_last_public_act`, `test_reputation_field_of_a_voice_request`) ; `tests/test_protocol.py` OK le 2026-10-15
  - Reste : —

- [x] **E04-T11** — Effets en jeu : marge du passeur et accueil des groupes
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E04-T09, E13-T04, LK11-T03
  - Fichiers : `RS_Trade.lua` (`marginFloor`, `marginRange`, lignes 340-356) ; `docs/specifications-techniques/passeur-table.md` (section 1) ; `LK_Hostility.lua` (départ d'une paire) ; `docs/annexes/conception/attitude.md`
  - Faire : plancher de marge du passeur selon le niveau (Q13 ; remplace « faute d'API de réputation » de la décision E13-T02), tricherie toujours au maximum ; départ de l'attitude d'un groupe envers un inconnu selon Q14 (le contrat RSREP-1 §1 et `attitude.md` disent aujourd'hui qu'aucune ne se calcule à partir de l'autre : à réviser selon la réponse).
  - Accepté si : deux appelants de niveaux différents reçoivent des fourchettes de marge différentes ; un groupe déjà rencontré n'est pas modifié par la réputation (selon Q14).
  - Tests : banc `lupa` (`rs_trade`, `lk_hostility`) ; suite en jeu.
  - Preuve : commit `6d21937` ; bancs `tests/test_rs_trade.py` 24 OK, `tests/test_lk_hostility.py` 41 OK (1 ignoré), banc `tests/test_reputation.py` 25 OK le 2026-10-15 ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.reputation « the smuggler margin follows the level » PASS (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; solo : même test PASS (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`)
  - Reste : Limite : l'accueil d'un groupe selon la réputation (Q14) n'est prouvé qu'au banc (`test_one_step_better_or_worse_at_first_contact_only`), aucun test en jeu ne le provoque

- [x] **E04-T12** — Persistance et multijoueur de la réputation
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E04-T08
  - Fichiers : `RS_State.lua` ; `RS_Reputation.lua` ; `RS_Carnet_Server.lua` (instantané, `prune`, `characterDeath`)
  - Faire : autorité serveur (garde `isClient()`, aucune commande client qui fixe personnage, montant ou motif) ; stockage dans l'état privé `RS_State` (fichier serveur), **aucune ModData globale** ; projection envoyée au seul joueur concerné (et à d'autres selon Q15) ; purge proposée (confirmée par défaut) : `outcomes` gardés 30 jours de jeu, personnage retiré purgé après 7 jours ; écriture sur changement seulement.
  - Accepté si : après redémarrage du serveur, scores et motifs identiques, aucun doublon ; un client ne lit pas la réputation d'un autre (sauf Q15) ; un joueur hors ligne reçoit les faits de sa mission de groupe.
  - Tests : banc `lupa` ; suite en jeu MP (campagne automatique).
  - Preuve : commit `a5c6808` ; banc `tests/test_reputation.py` 25 OK le 2026-10-15 (`test_group_mission_same_amount_offline_participant_and_restart`, `test_no_client_can_write_and_projection_is_private`, `test_purge_outcomes_and_dead_characters`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.reputation 5/5, rep.read du client 2 sans les actes du client 1 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : rs.reputation.before (fait d'identifiant fixe enregistré) et rs.reputation.after-restart (même score, fait compté une fois) PASS (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093457-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`)
  - Reste : Limite : joueur hors ligne qui reçoit les faits de sa mission de groupe prouvé au banc seulement

- [ ] **E04-T13** — Adaptateur facultatif vers CharacterReputation (RSREP-2)
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : E04-T02, E04-T09
  - Fichiers : `RS_Reputation.lua` (frontière `pcall`) ; `docs/specifications-techniques/reputation-contract.md` (révision RSREP-2) ; `mod.info` (`loadModAfter` déjà prévu)
  - Faire : garder RSREP-1 comme cible (détection §2, identité §3, `recordEvent` idempotent §4, lecture §5, isolement §7) ; réviser §1, §5 et §8 pour la décision 8 ; selon Q16, envoyer au service chaque fait appliqué en interne (même `eventId` préfixé `rs:`, même montant) quand il est `ready` ; faits antérieurs jamais renvoyés (décision E04-T01 (2)) ; sans le mod ou API incompatible, rien ne change pour le joueur.
  - Accepté si : avec une fausse API conforme, chaque fait part une fois (redémarrage, rejeu) ; avec la coquille 0.1.0 (`incompatible`), comportement identique à l'absence du mod.
  - Tests : banc `lupa` avec une fausse API ; suite en jeu le jour où l'API existe.
  - Preuve : décision de l'utilisateur du 2026-10-15 (finir le solo de la radio et du carnet ; section Décisions)
  - Reste : abandonnée le 2026-10-15 : dépend d'une API métier que CharacterReputation n'expose pas (capacités toutes fausses), hors de notre contrôle ; à rouvrir comme nouvelle tâche le jour où cette API existera (Q16 (a) reste la réponse retenue ; révision RSREP-2 §1, §5, §8 ; renvoi dans `CharacterReputation/docs/proposition-api-reputation.md`).

- [x] **E04-T14** — Suites en jeu de la réputation et outil d'administration
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E04-T04, E04-T05, E04-T07, E04-T10, E04-T11, E04-T12
  - Fichiers : `dev/batman_RadioSurvivorTests/.../suites/RS_Reputation.lua` (suite `rs.reputation`) ; `RS_Carnet_Server.lua` ou panneau d'admin selon Q17
  - Faire : suite `rs.reputation` dans les campagnes solo et MP automatiques : mission réussie → niveau, tendance et motif chez le seul participant ; deux clients : l'un tue le demandeur, l'autre garde sa réputation ; redémarrage : score conservé, aucun doublon ; offre simple encore proposée à une mauvaise réputation ; marge du passeur selon le niveau. Réglage de la réputation pour les essais réservé aux parties `rstest` ; outil d'administration selon Q17.
  - Accepté si : suite verte dans la campagne solo et dans la campagne MP automatique (règle « les tests font foi ») ; rapports en preuve.
  - Tests : `autoclient.py --campaign solo --bridge on` ; `autoclient.py --mp --clients 2 --server-campaign mp --bridge on`.
  - Preuve : commit `6d21937` (suite `rs.reputation`, vue d'administration) ; campagne solo automatique du 2026-10-15 (copie figée du commit `54087fb`, pont avec faux modèle) : rs.reputation 5/5 (`tools/autoclient/runs/20261015-114001-parallel-2-54087fb0f84f/shard1/20261015-094053-solo.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.reputation 5/5 avec rep.read des deux clients et rep.admin (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; campagne `mp-persist` du 2026-10-15 (copie figée du commit `54087fb`, reconnexions et redémarrage réels, toutes étapes vertes) : rs.reputation.before et .after-restart PASS (`tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093457-server.txt`, `tools/autoclient/runs/20261015-113252-run-54087fb0f84f/run/server/20261015-093940-server.txt`)
  - Reste : —
