Validée le 2026-10-10 et reportée dans les fichiers d'étape ; ce document est archivé.

# Proposition — E08, E09 et E10 réécrites sur Living Knox

- Date : 2026-10-10 — Statut : **proposition à valider** par l'utilisateur. Aucun fichier d'étape n'est modifié ; après validation, les textes ci-dessous seront reportés dans `E08-initiatives-echanges-pnj.md`, `E09-relations-accords-factions.md`, `E10-chef-contestation-depart.md` (et les remarques sur les tâches LK dans leurs fichiers), puis `plan.py check` et `plan.py suivi`.
- Origine : décision du 2026-10-08 (`E17-T01`, Bandits! abandonné) consignée dans les trois étapes : « étape à réécrire sur l'API Living Knox (`LK12`) avant de commencer ».
- Sources lues : `docs/annexes/plans/README.md`, E08, E09, E10, E17, LK08 à LK12 (et LK05, LK06, LK07 pour les dépendances), `docs/specifications-techniques/api-living-knox.md`, `docs/annexes/conception/groupes.md`, `attitude.md`, `simulation.md`, `recits.md`, `consignes.md`, `rapports.md`, `docs/specifications-techniques/protocole-carnet-v2.md` (observations E08-T02, actions E07, demande et réponse PNJ), `RS_NPCProvider.lua`, `LK_Bodies.lua` (relevé du tueur), ADR B04, B09 à B13 de `docs/annexes/recherches/bandits-llm-specifications.md`. Aucun code de Bandits! ; les fichiers `docs/bandits-*.md` ne servent que de retour d'expérience.

## 1. Ce qui change avec Living Knox

| Besoin d'E08-E10 (formulé pour Bandits!) | Ce qui existe désormais | Conséquence |
|---|---|---|
| « En combat » lu dans le cerveau Bandits! (E08-T03) | Aucun combat Living Knox encore (LK06 à faire) ; `Bodies.onHitZombie` relève déjà le dernier coup d'un joueur sur un corps (`Bodies.lastHits`, heure comprise) ; alerte prévue par LK05-T08 | Prédicat « occupé » à définir dans le moteur, provisoire jusqu'à LK05-T08 / LK06 |
| Équipement radio Bandits! (E08-T06) | `LK_Equipment` ne gère aucune radio ; les groupes vivent hors écran (`LK_Simulation`) | Question Q1 |
| Hostilité Bandits! par joueur ou par faction (E09-T02, abandonnée) | `LK_Hostility` : attitude groupe × personnage, 5 niveaux de la décision E09-T01, tendance par les trois derniers faits, faits vus ou attribuables (I9.3), agresseur seul visé ; `API.attitude` | E09-T04 se construit au-dessus ; E09-T05/T06 s'appliquent au choix de cible de LK06-T01 |
| Clan Bandits!, chef inexistant (E10-T01, abandonnée) | `LK_Groups` : chef, rôles en liste fermée, succession I6.6 (rôle puis ancienneté), `applyLeave`, journal ; `API.getGroup` rend chef et membres (`npc = lk-<n>`) | E10-T02 ne « désigne » plus rien : il lit le chef du registre |
| Contestation et départ « à adapter à Bandits! » (E10-T03, T04) | LK09-T05 : événement `conflict` (chef contesté, journal seul) et `departure` (moral bas, jamais le chef, jamais un membre lié à un PNJ) hors écran | Le LLM ne traite que les PNJ incarnés et contactés ; la simulation garde les membres abstraits |
| Événement de mort Bandits! | `Bodies.onDied` (écouteur prévu pour E17-T03) avec la cause d'E04-T06 ; LK12-T02 publiera « membre mort », « groupe disparu » | Déclencheur `group_death` d'E08-T01 branchable |
| Parole de proximité | `RS_NPCProvider.hears/near/bubble` ; LK11-T04 prévoit `LK_Speech.lua` (répliques par gabarit, « point d'entrée pour remplacer par le dialogue LLM ») ; LK11-T02 les sommations | Un seul canal de parole : celui de LK11-T04 (voir 2.2) |

Constat secondaire : `LK06-T01` (« hostilité par groupe et par joueur ») recouvre en partie `LK11-T03`, déjà fait. Proposition : réduire LK06-T01 au **choix de cible** (à reporter dans LK06 après validation), qui consultera l'attitude de LK11-T03 et les accords d'E09 (voir 4.3).

## 2. Répartition du code entre tâches E et LK (doublons évités)

1. **Canal de parole** : `LK11-T04` porte le canal (bulle, auditeurs calculés depuis le PNJ, une seule fois par joueur à portée, délai par PNJ, répliques de gabarit sans pont). `E08-T03` et `E08-T04` ne codent que la **demande LLM** et passent le texte reçu par ce canal ; le gabarit de LK11-T04 est le secours sans pont (règle « coût LLM borné »).
2. **Sommations** : `LK11-T02` garde l'approche du foyer. Une initiative d'E08-T03 est suspendue pour un PNJ engagé dans une sommation (pas deux paroles concurrentes).
3. **Contestation hors écran** : `LK09-T05` (`conflict`) reste le seul code abstrait ; `E10-T03` traite les PNJ incarnés et n'en duplique pas les règles.
4. **Départ hors écran** : `LK09-T05` (`departure`) ; `E10-T04` traite le départ décidé par le LLM d'un PNJ incarné et réutilise `Groups.applyLeave`.
5. **Succession** : `LK_Groups.pickSuccessor` / `succeed` (déjà codés) ; aucune règle de succession nouvelle dans E10.
6. **Attitude** : `LK_Hostility` reste l'unique registre groupe × personnage ; la relation personnelle d'un PNJ (E09-T04) est un registre carnet distinct qui ne recalcule pas l'attitude.
7. **Application des trêves au combat** : le registre des accords est dans `RS_Factions` (E09-T05) ; sa **consultation** par le choix de cible appartient à `LK06-T01` (crochet décrit en 4.3). Aucune autre tâche ne touche au ciblage.
8. **Lectures nouvelles du moteur** (chef et composition, prédicat « occupé ») : ajouts compatibles à `LK_API` version 1 (règle de `docs/specifications-techniques/api-living-knox.md` : ajouts seuls dans une version), portés par la première tâche E qui en a besoin, avec mise à jour de `docs/specifications-techniques/api-living-knox.md`.

## 3. Questions à l'utilisateur

Trois décisions acquises deviennent ambiguës parce qu'elles supposaient des corps Bandits! sans groupes simulés hors écran. Une question à la fois, dans l'ordre ; les tâches concernées restent `à décider` jusqu'à la réponse.

### Q1 — Radio des PNJ équipés (E08-T06 ; décision acquise B04 « radio pour les PNJ équipés »)

Avec Bandits!, un PNJ n'existait que s'il était chargé. Living Knox fait vivre les groupes hors écran, et une émission depuis une radio posée révèle sa position à tous les clients en MP (base `radio-dynamic.md`), donc le foyer d'un groupe.

- **A [recommandé]** — Radio **du groupe** : un groupe dont un profil ou le foyer porte un poste émetteur devient une voix du réseau radio (même mécanisme que les voix d'E05 : chaîne sans source physique, fréquence tirée par partie sans conflit, mémoire par voix), joignable même hors écran ; l'opérateur parle au nom du groupe avec son état simulé ; aucune position exacte révélée.
- **B** — Radio **portée par un corps** seulement : joignable quand le PNJ équipé est incarné, sa radio allumée et réglée ; muet hors écran (lecture littérale ; en solo, presque toujours hors d'atteinte puisque le joueur est déjà à moins de 80 cases).
- **C** — **Reporter** : E08-T06 abandonnée pour cette version (raison consignée), radio des PNJ reprise après LK13.

### Q2 — Portée de la contestation (E10-T03 ; décision acquise « un chef décide, les membres peuvent contester ou refuser »)

Living Knox prend lui-même les décisions collectives courantes (cadre LK05-T02 : objectifs du groupe notés chaque heure, « personnalité du chef » comprise). L'ADR B12 supposait un LLM pour chaque réaction.

- **A [recommandé]** — **Deux voies** : contestation et refus décidés par le LLM pour les seules intentions collectives nées d'un dialogue (accord, mission de groupe) ; pour les ordres du moteur (garde, expédition, défense), refus **déterministe** par des règles de LK05-T02 (blessure, peur, moral, traits), avec une réplique de gabarit. Coût LLM borné.
- **B** — LLM seulement pour les intentions nées d'un dialogue ; les ordres du moteur ne sont **jamais** contestés (seul `conflict` de LK09-T05 hors écran).
- **C** — LLM pour **chaque** ordre suivi par un membre incarné (fidèle à B12 mais un appel par membre et par ordre : quotas vite atteints).

### Q3 — Sort d'un PNJ incarné qui quitte son groupe (E10-T04 ; décision acquise « départ décidé par le LLM, identité, souvenirs, relations et trêves conservés, pas de ralliement automatique »)

Hors d'un groupe, un PNJ Living Knox n'a ni foyer ni simulation.

- **A [recommandé]** — **Solitaire durable** : il forme un groupe d'un seul membre d'un type `loners` livré en données (taille 1, hostilité de départ neutre, aucune option de poids : jamais tiré par la population), foyer choisi par `Sites.pick` loin de l'ancien, vie hors écran par `LK_Simulation` ; il peut plus tard être recruté par une décision distincte, jamais au départ.
- **B** — **Départ du secteur** : il s'éloigne puis le PNJ est oublié une fois hors de vue ; fiche, souvenirs, relations et trêves archivés côté carnet (aucun retour prévu).
- **C** — **Errant sans groupe** : il reste dans le registre des corps sans groupe ni simulation, incarné près des joueurs, figé (virtuel) à sa dernière position sinon.

## 4. Tâches, une par une

### 4.1 E08 — Initiatives des PNJ et échanges entre PNJ

En-tête proposé :

- **Objectif.** Les PNJ de Living Knox prennent la parole sur des événements pertinents, se transmettent leurs observations par de vraies conversations de proximité (ou par radio selon Q1), et le joueur peut intervenir dans une conversation qu'il entend.
- **Dépend de.** E17-T03 (fournisseur Living Knox), LK11-T04 (canal de parole), LK12-T02 (événements publics).
- **Sources.** Ajouter : `docs/specifications-techniques/api-living-knox.md`, `docs/annexes/conception/groupes.md`, `simulation.md`, `attitude.md` ; LK11-T02, LK11-T04, LK12-T02 ; base `api-42-21.md` (météo côté serveur), `power-and-lights.md` (`hasGridPower`), `staging-effects.md` (hélicoptère), `load-warnings.md` / `mod-loading.md` (options `enum`).

| Tâche | Sort proposé |
|---|---|
| E08-T01, E08-T02 | inchangées (faites) |
| E08-T03 | **réécrire** (Living Knox, canal LK11-T04, prédicat « occupé », quotas `enum`) |
| E08-T04 | **réécrire** (paires de PNJ Living Knox, `Obs.transmit`, secours de gabarit) |
| E08-T05 | **garder**, dépendances et fichiers précisés |
| E08-T06 | **réécrire selon Q1** (texte pour A ; B ou C donnés en note) |
| E08-T07 (nouvelle) | déclencheurs du carnet et de Living Knox branchés sur les observations |
| E08-T08 (nouvelle) | déclencheurs du monde (météo, courant, hélicoptère) |

La réserve d'E08-T02 (« aucun déclencheur du monde branché (E08-T03, T04) ») est en réalité un travail distinct d'E08-T03 : il devient E08-T07 et E08-T08 (numéros suivants libres).

- [ ] **E08-T07** — Déclencheurs du carnet et de Living Knox vers les observations
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E08-T02, E17-T03, LK12-T02
  - Fichiers : `RS_Carnet_Server.lua` (abonnements) ; `RS_Observations.lua` (aucun changement de modèle) ; `RS_LivingKnox.lua` (fournisseur) ; `tests/test_observations.py`
  - Faire : enregistrer par `Obs.record` les faits `player_return` (personnage déjà connu d'une fiche qui revient à portée d'audition après au moins un jour de jeu d'absence), `mission_done` (clôture d'une mission par `RS_Missions`, chez le PNJ demandeur), `group_death` (événement « membre mort » de LK12-T02 : fiches des membres incarnés qui voient la scène par `Provider.near`, et, pour une mort hors écran, fiches des membres présents au foyer, la simulation abstraite n'ayant pas de perception plus fine), `assault_seen` (fait `hit`, `shot` ou `kill` enregistré par `LK_Hostility.record` avec `witnessed = true`, chez les fiches des témoins). Seulement des fiches existantes (règle « fiches créées au contact ») ; sujet = identité de personnage du carnet ou fiche, lieu en maille `Obs.area`.
  - Accepté si : chaque fait apparaît une fois par témoin admissible, jamais chez un PNJ qui n'a pu le voir ; aucune coordonnée exacte ; aucune fiche créée par un déclencheur.
  - Tests : banc `lupa` (fausse API Living Knox conforme, deux clients) ; suite en jeu solo (retour d'un joueur, mort d'un membre devant un autre).
  - Preuve : —
  - Reste : ⚠ témoins d'une mort hors écran = membres au foyer (choix à confirmer par la relecture) ; `assault_seen` réel attend les coups de LK06.

- [ ] **E08-T08** — Déclencheurs du monde : météo, coupure de courant, hélicoptère
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E08-T07
  - Fichiers : `RS_Carnet_Server.lua` (ou `RS_WorldEvents.lua`, server) ; `tests/test_observations.py`
  - Faire : sondage à `EveryHours` sur l'autorité : orage (`getIsThunderStorming`, base `api-42-21.md`), fin du réseau électrique (passage de `hasGridPower` à faux, base `power-and-lights.md`), passage d'hélicoptère ; un fait par épisode (clé `fait|sujet|jour|lieu` existante, sujet `storm`, `power`, `helicopter`), enregistré pour les fiches suivies de PNJ dont le groupe n'est pas en expédition ; aucun travail proportionnel à la population (64 fiches au plus).
  - Accepté si : un orage donne une seule observation par fiche ; aucune observation sur un serveur vide en pause (`EveryHours` ne part pas).
  - Tests : banc `lupa` ; protocole solo (orage forcé par la console, courant coupé par `ElecShutModifier`).
  - Preuve : —
  - Reste : ⚠ détection de l'hélicoptère vanilla douteuse (`getWorld().helicopter`, hypothèse de la base `staging-effects.md`) : si elle est réfutée, la tâche passe à `à décider` pour retirer `helicopter` de la liste fermée d'E08-T01.

- [ ] **E08-T03** — Initiative de parole d'un PNJ Living Knox à proximité
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E08-T07, LK11-T04
  - Fichiers : `RS_Carnet_Server.lua` (demande `npc_initiative`) ; `bridge/npc_protocol.py` ; `docs/specifications-techniques/protocole-carnet-v2.md` ; `media/sandbox-options.txt` et `Translate/EN|FR/Sandbox.json` (option `enum`) ; `LK_API.lua` et `docs/specifications-techniques/api-living-knox.md` (ajout compatible `API.engaged(npcId)`)
  - Faire : une observation récente (moins d'une heure de jeu) d'une fiche dont le corps est incarné, et au moins un joueur qui l'entend (`Provider.hears`), ouvrent une demande sans texte joueur, dans la même file ordonnée par PNJ que les sollicitations (ADR B04 : identifiant d'événement, regroupement des répétitions, caduque si la situation change) ; la réplique passe par le canal de LK11-T04 ; sans pont, réplique de gabarit de LK11-T04 ou silence. Aucune initiative si `API.engaged` est vrai : coup reçu ou porté depuis moins de 30 s (`Bodies.lastHits`), sommation de LK11-T02 en cours, puis alerte de LK05-T08 quand elle existera. Option `enum` (format piège : `numValues`, `default` par index) « Fréquence des initiatives » : Désactivées / Rares (1 par PNJ et par jour de jeu, 2 par heure réelle pour le serveur) / Normales (1 par PNJ et par heure de jeu, 6 par heure réelle) / Fréquentes (1 par PNJ et par demi-heure de jeu, 12 par heure réelle) ; chaque libellé affiche son coût approximatif (appels par heure réelle) ; toutes les initiatives comptent dans le plafond commun `MAX_PER_HOUR` des demandes PNJ. Valeurs à faire confirmer à l'ouverture de la tâche (décision E08-T01 (2) : « plafonds à proposer dans la tâche qui l'implémente »).
  - Accepté si : quotas de chaque niveau respectés ; un PNJ occupé ne parle pas ; une seule initiative par événement admissible, sans répétition après une sortie puis un retour dans la portée ni après une reconnexion ; pont arrêté : aucune nouvelle demande LLM.
  - Tests : banc `lupa` (deux clients, pont factice) ; `test_protocol.py` ; suite en jeu.
  - Preuve : —
  - Reste : prédicat « occupé » provisoire jusqu'à LK05-T08 et LK06-T01.

- [ ] **E08-T04** — Conversation entre deux PNJ Living Knox proches
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E08-T03
  - Fichiers : `RS_Carnet_Server.lua` ; `RS_Observations.lua` (`transmit`, inchangé) ; pont ; contrat v2
  - Faire : deux PNJ incarnés à portée l'un de l'autre (`Provider.near`, 4 cases), non occupés, dont l'un a une observation que l'autre n'a pas : conversation identifiée (participants, sujet = clé d'observation, 4 tours au plus, durée bornée) ; un appel LLM par tour seulement si au moins un joueur entend (sinon transmission silencieuse : `Obs.transmit` sans texte, une par paire et par délai) ; auditeurs recalculés à chaque réplique depuis le PNJ ; le destinataire n'apprend qu'à la réception admissible, par `Obs.transmit` (provenance, pas de boucle, chaîne de 4) ; délai avant une nouvelle conversation entre les mêmes PNJ ; fiche créée pour le destinataire seulement s'il est d'un groupe déjà contacté, dans la borne de 64 fiches. Sans pont : répliques de gabarit de LK11-T04 (idée I3.8 de cette tâche).
  - Accepté si : critères de l'ADR B11 (récit transmis, retour au premier sans duplication, seuls les auditeurs admissibles l'entendent, fin sans boucle).
  - Tests : banc `lupa` ; suite en jeu avec deux PNJ `LKB.spawn` et un joueur, puis deux joueurs dont un hors portée.
  - Preuve : —
  - Reste : transmission entre PNJ non chargés exclue (aucune simulation de contact, ADR B11).

- [ ] **E08-T05** — Intervention du joueur dans une conversation entendue (**gardée**)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E08-T04
  - Fichiers : `RS_Carnet_Server.lua` ; `RS_Client.lua`
  - Faire : inchangé : un joueur qui a sélectionné l'un des interlocuteurs (Ctrl+G ou bouton « Parler » de la fiche, ADR B17) et parle dans le chat local s'insère dans l'ordre des échanges (ADR B04) ; une réponse en attente est revalidée avec les nouveaux tours ; les PNJ choisissent leur réaction ; aucun mandat de faction conféré.
  - Accepté si : ordre canonique conservé ; aucun double engagement ; le joueur ne reçoit pas les tours qu'il n'a pas entendus.
  - Tests : banc `lupa` deux clients.
  - Preuve : —
  - Reste : —

- [ ] **E08-T06** — Radio des groupes équipés (texte pour Q1 = A)
  - État : `à décider` (Q1), puis `à faire`
  - Cible : `MP`
  - Dépend de : E08-T03, E06-T03, E05-T03
  - Fichiers : `RS_LivingKnox.lua` ; `RadioSurvivor_Server.lua` ; voix du réseau E05 (fiche générée par groupe) ; `media/lua/shared/LivingKnox/Data/LK_Type_*.lua` (poste émetteur par profil ou foyer, format 1 si le champ existe, sinon format 2)
  - Faire : un groupe équipé reçoit une fréquence tirée par partie sans conflit (même règle qu'E05-T07) et une voix générée (nom du groupe, résumé public `story`, état simulé : besoins, moral, chef) ; un joueur l'appelle par le module « Émettre » validé côté serveur (E06-T03) ; mêmes quotas et même file que la proximité (une décision sur un canal ne crée pas un second état sur l'autre) ; jamais de coordonnée, foyer seulement en maille (`API.area`) ; une émission ne révèle pas la position d'une base de joueur.
  - Accepté si : seul un groupe équipé est joignable ; un groupe décimé ou disparu ne répond plus ; aucune position exacte dans les répliques ni dans la chaîne.
  - Tests : banc `lupa` ; suite en jeu solo puis MP.
  - Preuve : —
  - Reste : Q1 = B : « radio portée par un corps » (lecture de l'inventaire du corps sur l'autorité, joignable seulement incarné). Q1 = C : `abandonné`, raison « reportée après LK13 ».

### 4.2 E09 — Relations évolutives et accords de faction

En-tête proposé :

- **Dépend de.** E17-T03 ; E08-T02 (observations) recommandé ; LK11-T03 (attitude), LK06-T01 (choix de cible) pour T05 et T06.
- **Sources.** Ajouter : `docs/annexes/conception/attitude.md`, `docs/specifications-techniques/api-living-knox.md` (`API.attitude`), `docs/annexes/conception/corps-registre.md` (tueur), LK06-T01, LK11-T05.

| Tâche | Sort proposé |
|---|---|
| E09-T01, E09-T02 | inchangées (faite / abandonnée) |
| E09-T03 | **garder**, dépendance corrigée (E09-T02 abandonnée) |
| E09-T04 | **réécrire** sur `LK_Hostility` ; repasse `à décider` (articulation PNJ / groupe, question propre à la tâche, posée à son ouverture) |
| E09-T05 | **réécrire** : application au choix de cible de Living Knox, conclusion par le chef (E10-T02) |
| E09-T06 | **réécrire** : attribution par `Bodies.onHitZombie` / `deathCause`, défense par LK06-T01 |
| E09-T07 | **garder**, contenu complété (attitude du groupe, libellés traduits) |

- [ ] **E09-T03** — Identifiant de faction propre au mod et mandats de négociation (**gardée**)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : inchangés (`RS_Factions.lua`, `RS_Notebook.lua`)
  - Faire, Accepté si, Tests, Reste : inchangés. Seule la dépendance change (E09-T02 abandonnée ; la tâche ne dépendait d'elle que pour l'application Bandits!, sans objet ici). Les mandats et la faction sont indépendants du moteur de PNJ.
  - Preuve : —

- [ ] **E09-T04** — Relation personnelle d'un PNJ envers un personnage (`change_relation`)
  - État : `à décider`
  - Cible : `MP`
  - Dépend de : E09-T01, LK11-T03, E17-T03
  - Fichiers : `RS_Relations.lua` (server, état privé `RS_State`) ; `RS_Carnet_Server.lua` ; pont (intention `change_relation`) ; `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : relation par (fiche du PNJ, identité de personnage du carnet, même clé que `Hostility.keyOf`) ; niveau affiché = mêmes 5 niveaux et même tendance qu'E09-T01, calculés depuis l'attitude du groupe (`API.attitude`) et la relation personnelle selon la réponse à la question ; intention `change_relation` ajoutée à la liste fermée de la réponse (`intent` aujourd'hui `none` ou `offer`) avec un sens (`up`, `down`) et la référence d'un fait **réel** connu du PNJ (fait de `LK_Hostility` vu par son groupe, observation `seen` d'`RS_Observations`, mission close) ; le serveur vérifie la cible, la révision de la fiche, que le fait existe et n'a pas déjà motivé un changement ; une phrase seule ne prouve rien (ADR B11, B15).
  - Questions : Articulation entre l'attitude du groupe et la relation d'un PNJ ? Options : écart personnel borné à un niveau au-dessus ou au-dessous de l'attitude du groupe [recommandé] / le LLM ne touche que l'attitude du groupe, par des faits de `LK_Hostility` / relation du PNJ entièrement indépendante du groupe.
  - Accepté si : « une aide puis une trahison motivent deux changements » ; aucune transition sur une révision périmée ni sans fait réel ; deux PNJ d'un même groupe peuvent différer selon la réponse.
  - Tests : banc `lupa` ; `test_protocol.py` ; suite en jeu.
  - Preuve : —
  - Reste : —

- [ ] **E09-T05** — Accords de faction avec un groupe Living Knox : trêve et alliance (`negotiate`)
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E09-T03, E10-T02, LK06-T01
  - Fichiers : `RS_Factions.lua` (registre des accords, état privé) ; `RS_Carnet_Server.lua` ; pont ; contrat v2 ; crochet consulté par `LK06-T01` (voir 4.3)
  - Faire : accord entre un groupe (`grp-<n>`) et une faction de joueurs (identifiant stable d'E09-T03), de portée explicite ; offre issue du serveur, négociation par le LLM dans des conditions fixes, conclusion seulement par le chef du groupe (règle d'E10-T02) et un représentant habilité (mandat d'E09-T03), revalidée au moment de conclure (chef, composition, mandat, révision de l'accord) ; application : l'accord est inscrit dans le registre que le choix de cible consulte, puis le serveur vérifie au passage de décision suivant qu'aucun membre ne vise plus un joueur couvert ; l'annonce « applicable » n'est faite qu'après ce constat. Une trêve ne change pas l'attitude (`LK_Hostility`) : elle impose la non-agression dans son périmètre (ADR B08).
  - Accepté si : « trêve décidée pendant un combat : application confirmée avant annonce » ; un membre ordinaire ou un joueur sans mandat ne conclut pas ; deux conclusions incompatibles : une seule appliquée (révision).
  - Tests : banc `lupa` ; suite en jeu.
  - Preuve : —
  - Reste : membres de la faction relus par sondage (aucun événement serveur, base `multiplayer.md`).

- [ ] **E09-T06** — Défense ciblée et décision sur la trêve
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E09-T05, E04-T06, LK06-T01
  - Fichiers : `RS_Factions.lua` (incidents) ; `RS_Carnet_Server.lua` ; pont
  - Faire : un coup, un tir ou une mort d'un membre attribués à un joueur couvert (`Bodies.onHitZombie`, `Bodies.deathCause`, faits `hit`/`shot`/`kill` vus ou attribuables de `LK_Hostility`) ouvrent un **incident** (identifiant, auteur, victimes, accord, révision ; faits d'un même incident regroupés) ; l'auteur seul perd la protection envers ce groupe pendant l'incident (défense immédiate, sans attendre le LLM, par la règle du choix de cible) ; demande de décision au LLM via la fiche du chef (maintien, réparation dans les catégories du stock autorisées, rupture), validée par le serveur ; pont absent : défense maintenue, aucune rupture automatique ; une riposte d'un membre n'est jamais comptée comme agression initiale ; pas de vengeance de LK11-T05 contre les autres membres de la faction couverte.
  - Accepté si : critères de l'ADR B10 (agresseur et membre innocent présents ensemble, joueur tiers, deux agressions rapprochées, réponse tardive, pont indisponible) ; l'accord change une seule fois par décision valide.
  - Tests : suite en jeu avec deux joueurs ; banc `lupa`.
  - Preuve : —
  - Reste : ⚠ tueur « probable » d'E04-T06 (coup récent puis mort envoyée par le propriétaire).

- [ ] **E09-T07** — Panneau de relation dans le carnet (**gardée**, contenu complété)
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E09-T04
  - Fichiers : `RS_Notebook.lua` ; `Translate/EN|FR/IG_UI.json`
  - Faire : par contact : niveau et tendance (E09-T04, sinon attitude du groupe par `API.attitude`, projection propre au joueur qui consulte), libellés traduits côté client des identifiants `hostile`, `wary`, `cautious`, `favorable`, `trusting` et `up`, `down`, `stable` (réserve de LK11-T03), accords applicables avec leur portée, derniers faits expliquant l'attitude, sans secret ni conversation privée d'un autre joueur, sans valeur numérique.
  - Accepté si : « deux membres d'une faction, relations différentes » visible et correct.
  - Tests : protocole visuel + suite.
  - Preuve : —
  - Reste : —

### 4.3 Remarque pour LK06-T01 (à reporter dans LK06 après validation)

`LK06-T01` devient « Choix de cible » (l'hostilité par joueur existe : LK11-T03). Ajouter à son « Faire » : avant de viser un joueur, interroger un crochet facultatif `LivingKnox.Hooks.covered(groupId, playerKey, npcId) -> boolean` que RadioSurvivor remplit (trêves de groupe d'E09-T05, trêves conservées par un PNJ parti d'E10-T04) ; un joueur couvert n'est pas une cible, sauf l'auteur d'un incident ouvert (E09-T06). Crochet absent = aucun joueur couvert. Une seule implémentation : celle de `RS_Factions`.

### 4.4 E10 — Chef de bande, contestation et départ individuel

En-tête proposé :

- **Objectif.** Les décisions collectives d'un groupe Living Knox viennent de son chef (registre `LK_Groups`) ; chaque membre incarné peut contester ou refuser selon sa personnalité et sa loyauté ; un PNJ peut quitter son groupe sur décision du LLM en gardant identité, souvenirs, relations et trêves.
- **Dépend de.** E17-T03 ; E09-T05 pour T04 (trêves conservées).
- **Sources.** Ajouter : `docs/annexes/conception/groupes.md` (chef, succession, `applyLeave`), `simulation.md` (événements `conflict`, `departure`), LK05-T02.

| Tâche | Sort proposé |
|---|---|
| E10-T01 | inchangée (abandonnée) |
| E10-T02 | **réécrire** : chef lu dans `LK_Groups`, empreinte de composition ; passe avant E09-T05 |
| E10-T03 | **réécrire selon Q2** (texte pour A) ; règles abstraites laissées à LK09-T05 |
| E10-T04 | **réécrire selon Q3** (texte pour A) |

- [ ] **E10-T02** — Chef du groupe et intentions collectives
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E17-T03
  - Fichiers : `RS_Carnet_Server.lua` ; `RS_LivingKnox.lua` ; `LK_API.lua` et `docs/specifications-techniques/api-living-knox.md` (ajout compatible `API.composition(groupId)`)
  - Faire : le chef est celui du registre (`API.getGroup(...).leader`, succession I6.6 déjà codée) ; les intentions collectives (accord d'E09-T05, mission de groupe issue des offres de LK12-T03) ne sont proposées au LLM que si le PNJ qui parle est le chef ; un autre membre peut en parler mais renvoie au chef ; à la réponse, le serveur revalide chef et composition par `API.composition` (empreinte calculée des membres vivants et du chef, sans champ stocké ni changement de schéma) et rejette une réponse fondée sur une ancienne composition ; la décision est inscrite au journal du groupe (`addLog`, kind `decision`) et jointe au contexte des fiches des membres, sans les raisons privées du chef.
  - Accepté si : un membre ordinaire ne conclut pas un accord collectif ; une réponse arrivée après une mort ou une succession est rejetée.
  - Tests : banc `lupa` ; suite en jeu.
  - Preuve : —
  - Reste : —

- [ ] **E10-T03** — Contestation et refus d'un membre incarné (texte pour Q2 = A)
  - État : `à décider` (Q2), puis `à faire`
  - Cible : `MP`
  - Dépend de : E10-T02, LK05-T02
  - Fichiers : pont (prompt membre) ; `RS_Carnet_Server.lua` ; `LK_Decisions.lua` (règle de refus déterministe, si Q2 = A)
  - Faire : intention collective née d'un dialogue : chaque membre incarné concerné reçoit son contexte et le LLM choisit accepter, contester (réplique par le canal de LK11-T04) ou refuser ; quota d'évaluations par décision. Ordre du moteur (LK05-T02) : refus déterministe selon blessure, peur, moral du groupe et traits, avec réplique de gabarit. Conséquence bornée : le membre qui refuse n'exécute pas l'ordre, garde sa mémoire et son appartenance ; aucun changement de groupe implicite (le départ est E10-T04). Loyauté : aujourd'hui constante dans `Provider.personality` (`loyalty = 'current_group'`) ; elle se dérive du moral du groupe et de l'ancienneté du membre (aucun nouveau champ persistant).
  - Accepté si : refus tracé (journal du groupe) et audible pour les auditeurs ; aucune incohérence d'état collectif ; contestation hors écran laissée à `conflict` de LK09-T05, sans double règle.
  - Tests : banc `lupa`.
  - Preuve : —
  - Reste : Q2 = B : sans la partie « ordre du moteur » et sans dépendance à LK05-T02. Q2 = C : LLM pour chaque ordre, quota par membre et par heure à fixer.

- [ ] **E10-T04** — Départ individuel (`leave_group`) d'un PNJ incarné (texte pour Q3 = A)
  - État : `à décider` (Q3), puis `à faire`
  - Cible : `MP`
  - Dépend de : E10-T03, E09-T05
  - Fichiers : `RS_Carnet_Server.lua` ; `RS_LivingKnox.lua` ; `RS_Factions.lua` (trêves conservées par PNJ) ; `media/lua/shared/LivingKnox/Data/LK_Type_loners.lua` ; pont ; contrat v2
  - Faire : intention `leave_group` liée au PNJ, à son groupe et à l'empreinte de composition (E10-T02) ; le serveur revalide puis applique une transition unique : `Groups.applyLeave` (entrée `left`), succession immédiate si c'était le chef (`succeed`), nouveau groupe `loners` d'un membre lié au même PNJ (`npc`), foyer par `Sites.pick` loin de l'ancien ; fiche, souvenirs, observations et relations inchangés (clés par fiche) ; trêves applicables au PNJ copiées dans ses trêves personnelles, que le crochet de 4.3 consulte ; départ physique par une consigne LK03 hors de vue, qui peut échouer sans annuler le départ social ; les anciens compagnons ne l'apprennent que par observation ou transmission.
  - Accepté si : « départ sans renégociation » ; une seule transition persistée, conservée après redémarrage ; les clients voient le même état ; réponse tardive sur une ancienne composition rejetée.
  - Tests : banc `lupa` ; suite en jeu MP.
  - Preuve : —
  - Reste : Q3 = B : oubli du PNJ hors de vue, fiche archivée. Q3 = C : PNJ sans groupe ni simulation (`npcsNear` rend déjà `group = nil`).

### 4.5 Remarque pour LK12-T02 (à reporter après validation)

Ajouter à la liste des événements publics « membre parti » (départ hors écran de LK09-T05 et départ d'E10-T04) : E08-T07 et E10-T04 en ont besoin, et un abonné tiers ne doit pas lire le journal privé.

## 5. Ordre de réalisation proposé

Prérequis existants, hors de ces étapes : **E17-T03** (fournisseur Living Knox, après LK12-T03), **LK12-T02** (événements), **LK11-T04** (canal de parole).

1. Q1, Q2, Q3 posées à l'utilisateur (une à la fois), décisions reportées dans les étapes.
2. `E09-T03` (identifiant de faction, sans dépendance au moteur : peut avancer tout de suite, en parallèle).
3. `E08-T07` puis `E08-T08` (déclencheurs).
4. `E08-T03` → `E08-T04` → `E08-T05` (parole, conversations, intervention).
5. `E10-T02` (chef et composition), puis `E09-T04` (après sa question propre) → `E09-T07` (panneau, solo).
6. `LK06-T01` réduit au choix de cible (avec le crochet de 4.3) → `E09-T05` → `E09-T06`.
7. `E10-T03` (après LK05-T02 si Q2 = A) → `E10-T04`.
8. `E08-T06` en dernier (après E06-T03, E05-T03 et selon Q1).

```
E17-T03 ─┬─ E08-T07 ─ E08-T08
LK12-T02 ┘     └─ E08-T03 (+LK11-T04) ─ E08-T04 ─ E08-T05
                      └─ E08-T06 (+E06-T03, Q1)
E17-T03 ─ E10-T02 ─┬─ E09-T05 (+E09-T03, LK06-T01) ─ E09-T06 (+E04-T06)
                   ├─ E10-T03 (+LK05-T02 si Q2=A) ─ E10-T04 (+E09-T05, Q3)
LK11-T03 ─ E09-T04 ─ E09-T07
```

Les tâches de cible `MP` suivent la règle du 2026-10-09 : essais solo au fil de l'eau, validation multijoueur en une seule séance finale.

## 6. Récapitulatif

| Tâche | Sort | Porte le code |
|---|---|---|
| E08-T03 | réécrire | demande LLM ; canal = LK11-T04 |
| E08-T04 | réécrire | conversations ; gabarits = LK11-T04 |
| E08-T05 | garder | — |
| E08-T06 | réécrire selon Q1 (ou abandonner si C) | — |
| E08-T07, E08-T08 | nouvelles | déclencheurs |
| E09-T03 | garder (dépendance corrigée) | — |
| E09-T04 | réécrire, `à décider` | relation PNJ ; attitude = LK11-T03 |
| E09-T05 | réécrire | registre des accords ; ciblage = LK06-T01 |
| E09-T06 | réécrire | incidents ; défense = LK06-T01 |
| E09-T07 | garder (complétée) | — |
| E10-T02 | réécrire | chef et composition (`API.composition`) |
| E10-T03 | réécrire selon Q2 | hors écran = LK09-T05 |
| E10-T04 | réécrire selon Q3 | hors écran = LK09-T05 ; `applyLeave` réutilisé |

Aucune tâche ouverte n'est abandonnée ni fusionnée purement dans une tâche LK : chaque recouvrement (LK11-T04, LK09-T05, LK06-T01, LK11-T03) est traité par un partage explicite (la tâche LK porte le mécanisme du moteur, la tâche E la partie LLM et carnet).
