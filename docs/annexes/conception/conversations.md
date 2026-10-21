# Conversations entre deux PNJ proches

- Tâches : E08-T04 (création) ; E08-T05 (intervention du joueur dans une conversation entendue, section dédiée)
- Build : 42.21.0 — Date : 2026-10-13 — Statut : brouillon (banc hors jeu seulement)

Code : `media/lua/server/RadioSurvivor/RS_Conversations.lua` (autorité), branché dans `RS_Carnet_Server.lua` (passage `tick`, réponse `reply`) ; aides partagées d'`RS_Initiatives.lua` (auditeurs, langue, carte d'observation, état du pont) ; transmission `RS_Observations.transmit` (inchangée) ; parole `Provider.say` / `Provider.bark` (LK11-T04) ; contrat `npc_converse` (`bridge/npc_protocol.py`, [protocole](../../specifications-techniques/protocole-carnet-v2.md) « Conversation entre deux PNJ »). Tests : `tests/test_conversations.py` ; suite en jeu `rs.conversations` (`dev/.../shared/RST/suites/RS_Conversations.lua`).

## Problème

ADR B11 : un PNJ raconte à un autre ce qu'il a observé par une vraie conversation de proximité ; le destinataire ne l'apprend qu'à la réception, avec la provenance ; seuls les joueurs qui entendent reçoivent les répliques ; les conversations finissent sans boucle et sans coût LLM quand personne n'écoute.

## Règle

1. **Paire** (un passage toutes les 5 s réelles, une ouverture au plus) : un conteur (fiche vivante, corps chargé) et un voisin (corps du fournisseur à **4 cases** au plus, `Provider.near` : même étage, distance, `CanSee`). Aucun des deux occupé (`Provider.engaged`), sans demande en file, ni déjà en conversation (une fiche en conversation ne prend pas d'initiative E08-T03).
2. **Sujet** : l'observation la plus récente du conteur que le voisin peut apprendre (absente de son journal, voisin absent de la chaîne de provenance, chaîne non pleine). Sujet = clé d'observation `fait|sujet|jour|lieu`.
3. **Fiche du voisin** : la sienne s'il en a une ; sinon elle est créée **seulement** si son groupe est déjà contacté (une fiche de ce groupe figure dans les contacts d'un personnage) et si le carnet compte moins de **64 fiches** ; sinon pas de conversation (sans fiche, rien ne peut être appris).
4. **Délai par paire** : 6 heures de jeu entre deux conversations des mêmes fiches (état privé `data.conversations.pairs`), transmission silencieuse comprise.
5. **Personne n'entend** le conteur (aucun joueur lié au carnet, `Provider.hears`) : **transmission silencieuse** (`Obs.transmit` sans texte), une par paire et par délai, aucun appel LLM.
6. **Conversation entendue** (mémoire du serveur : participants, sujet, tours, répliques dites ; perdue au redémarrage) : 4 répliques au plus, conteur puis voisin en alternance, 3 minutes réelles au plus, 6 s entre deux répliques. Avant chaque réplique : les deux corps chargés, vivants, à 4 cases, non occupés (sinon fin) ; auditeurs recalculés depuis le corps du **locuteur** ; personne n'entend : fin, avec transmission silencieuse si le récit n'est pas encore passé.
7. **Réplique LLM** : demande `npc_converse` du locuteur (file ordonnée par PNJ, `MAX_PER_HOUR` commun, plafond propre égal au plafond horaire du niveau de l'option `InitiativeFrequency`) avec sa carte du sujet, son journal et les répliques déjà dites. Réponse dite par `Provider.say` aux auditeurs de cet instant, ajoutée à l'historique de leurs contacts **existants** ; caduque (et fin) si la situation a changé.
8. **Réception** : le voisin apprend le récit (`Obs.transmit`, provenance `heard_from:<conteur>`, chaîne de 4, pas de boucle) quand la **première réplique du conteur est dite** alors qu'il est encore à portée ; jamais à la préparation de la demande. Une interruption avant (départ, coup reçu, réponse refusée) : rien appris.
9. **Sans pont** (pont réputé arrêté par E08-T03), hors budget ou option « Désactivées » : **silence** (E08-T09, décision de l'utilisateur du 2026-10-14, précisée le 2026-10-15) : aucune conversation entendue ne s'ouvre et une conversation en cours se termine au tour suivant (`no model line`), sans réplique de gabarit ni appel de `Provider.bark` ; sans conversation, aucun récit n'est transmis par elle. Rien n'est consommé (ni délai de paire, ni fiche créée) : la paire peut parler au retour du pont. La transmission silencieuse (personne n'entend, point 5) est inchangée.
10. **Fin sans boucle** : un récit ne revient jamais à un PNJ de sa chaîne ; une paire sans rien à apprendre n'ouvre plus rien ; chaque paire attend 6 heures de jeu.

## Intervention du joueur (E08-T05)

ADR B11 « Intervention du joueur » et ADR B04 « Ordre » : un joueur qui a sélectionné l'un des deux PNJ (Ctrl+G ou
« Parler », ADR B17) et lui parle (chat local ou ligne « Dire » du carnet, même commande `talk`) prend part à la
conversation.

1. **Même chemin que toute phrase** : `talk` du carnet (sélection à 8 cases, règles du chat, délai, budget) ; la phrase
   devient une demande `npc_talk` dans la file du PNJ interpellé, avec les droits ordinaires du personnage (stade,
   offres, mandat de négociation de sa propre équipe) : la conversation n'en confère **aucun** autre. Son contexte
   ajoute `conversation` : l'interlocuteur et les répliques que ce PNJ a entendues (6 dernières), plus une consigne : le
   modèle choisit de répondre au joueur, de l'ignorer ou de poursuivre avec son interlocuteur.
2. **Ordre canonique** : la phrase est ajoutée à la liste des répliques de la conversation au moment où le serveur
   l'admet, après les répliques déjà dites ; plusieurs joueurs s'insèrent dans l'ordre d'admission. Chaque ligne note
   les PNJ qui l'ont entendue : le PNJ interpellé toujours, son interlocuteur seulement s'il est à portée d'audition du
   joueur et le voit (`Provider.near`, 30 cases). Un locuteur ne reçoit que les lignes qu'il a entendues.
3. **Revalidation** : chaque ajout incrémente la révision de la conversation. Une réplique de conversation demandée
   avant (`npc_converse` en attente) est refusée à sa réception sans être dite (`stale`), puis redemandée avec les
   nouveaux tours. Elle n'écrase jamais l'intervention.
4. **Aucun double engagement** : tant qu'une intervention attend sa réponse, la conversation ne demande aucune réplique
   (elle reste en pause, délai de 3 minutes compris). La file par PNJ sérialise la réplique en attente et la phrase du
   joueur ; un PNJ n'est jamais dans deux conversations.
5. **Réponse** : la réponse admise au joueur est dite comme toute réponse `npc_talk` (auditeurs du PNJ, historique) puis
   devient une réplique de la conversation (le PNJ suivant est l'autre) ; dite par le conteur, elle transmet le récit
   si le voisin est encore à portée. Les PNJ ayant parlé ensuite, la conversation reprend à 6 s. Une intervention
   refusée ou expirée (90 s) met fin à la conversation ; une réponse qui arrive quand les deux PNJ ne sont plus
   ensemble est dite au joueur et termine la conversation.
6. **Ce que reçoit le joueur** : seulement ce qu'il entend au moment où c'est dit (`Provider.say`, réponse `speech` du
   carnet) ; l'historique de son carnet n'est jamais complété avec des répliques antérieures. Le client ne clôt
   l'attente de sa phrase que sur la réponse à **sa** demande (identifiant rendu par `queued`), pas sur la réponse du
   même PNJ à un autre joueur.

Limite des 4 répliques : elle compte toutes les lignes, joueurs compris (contrat du pont : `turn = lignes + 1 ≤ 4`) ;
une intervention raccourcit l'échange entre PNJ. Les réponses aux joueurs ne sont pas limitées par la conversation
(délai de 10 s par personnage, plafonds communs).

## Décisions prises sans l'utilisateur (à confirmer)

- E08-T05 : réplique en attente **refusée puis redemandée** dès qu'une ligne a été ajoutée (un appel LLM de plus) ;
  conversation **en pause** pendant qu'une intervention attend ; **4 lignes au total**, joueurs compris ; intervention
  sans réponse admise = **fin** de la conversation ; la réponse au joueur compte comme réplique du PNJ (et transmet le
  récit si c'est le conteur) ; l'interlocuteur entend le joueur à 30 cases avec ligne de vue ; aucun changement du pont
  (`context.conversation` lu dans le contexte autoritaire de `npc_talk`).

- Délai par paire : **6 heures de jeu** ; durée bornée **3 minutes réelles** ; **6 s** entre deux répliques (lecture de la bulle, délai `GAP_MS` de LK11-T04).
- Plafond LLM des conversations : celui du niveau de `InitiativeFrequency` (2, 6 ou 12 répliques par heure réelle), compté à part des initiatives, plus le plafond commun de 60 ; « Désactivées » = aucune conversation entendue (E08-T09), la transmission silencieuse restant active.
- ~~Gabarit sans pont : 2 répliques `smalltalk`~~ : remplacé par le silence (E08-T09).
- « Groupe déjà contacté » = au moins une fiche de ce groupe dans les contacts d'un personnage ; « borne de 64 fiches » = nombre de fiches du carnet (`RS_Config.Observations.maxNpcs`).
- Le récit transmis par une conversation est daté de sa réception : le destinataire peut ensuite en faire une initiative (E08-T03), dans les quotas de l'option.

## Limites

- Hors jeu seulement (banc lupa, doublures du Java) ; pas exécuté dans la VM Kahlua ni en jeu.
- Transmission entre PNJ non chargés exclue (aucune simulation de contact, ADR B11).
- Une conversation par paire ; une bande de trois ou plus parle par paires successives.
- Le contenu des répliques n'est pas vérifié contre la carte (le LLM peut mentir ou omettre, ADR B11) ; la transmission enregistrée est toujours la carte du serveur, jamais le texte.
