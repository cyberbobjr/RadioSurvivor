# RadioSurvivor — contraintes de développement

Contraintes propres à ce projet. Les règles communes à tous les mods de l'utilisateur (règle immuable du Workshop
Steam, méthode de diagnostic, Kahlua, multijoueur, traductions, base de connaissances du moteur, tests en jeu
automatisés) vivent dans le fichier d'instructions unique du dossier de développement parent, hors de ce dépôt.

## Périmètre du projet

Un projet, un article Workshop, **trois mods** sous `Contents/mods/` (décisions :
[ADR de séparation](architecture/decisions/adr-separation-mods.md), plan
[`E18`](annexes/plans-termines/E18-separation-living-knox.md) ; [ADR batman_CoreAI](architecture/decisions/adr-coreai-separation.md),
plan [`E21`](annexes/plans-termines/E21-separation-coreai.md)). Le dossier et l'`id=` sont identiques :

| Mod | Rôle | `require=` |
|---|---|---|
| `batman_CoreAI` | mod commun : lien avec le pont Python LLM, carnet entier (fenêtre, onglets Contacts, Missions, Réputation, vues des missions, zones sur la carte, serveur et stock du carnet, interface `CA_NPCProvider`), moteur et gabarits des missions, identité, historique, réputation, contacts, équipes, lieux, faits du monde, faits de groupe, accès administrateur, petits outils | `batman_SignalSmoke` |
| `batman_RadioSurvivor` | voix radio, onglet Radio du carnet, missions des voix, troc, factions ; fiches de voix | `batman_CoreAI`, `batman_BeltRadio`, `batman_SignalSmoke` |
| `batman_LivingKnox` | moteur de PNJ : groupes, foyers, besoins, routines, parole, relations, accords ; fournisseur du carnet (`LK_NotebookProvider`) ; `incompatible=` Bandits2, ProjectALifeNPCs | `batman_CoreAI` |

Montages valides : RadioSurvivor seul, Living Knox seul (avec le carnet complet), ou les deux, toujours avec CoreAI ;
CoreAI activé seul n'apporte rien de jouable. **Living Knox et RadioSurvivor ne se nomment jamais** : aucun `require`,
global, événement, test d'identifiant de mod ni préfixe de journal de l'autre. Ce qu'ils partagent passe par les
registres de CoreAI (`CA_NPCProvider` et ses opérations, `CA_MissionViews.registerGiver`,
`CA_NotebookServer.registerCommand` / `addPoll` / `hooks`, registre des commandes client de `CA_NotebookClient`,
`CA_GroupFacts`, `CA_TradeValues.registerSellOnly`) ; un module qui ne sert qu'à un mod vit dans ce mod. Le pont est un
seul programme, sans option selon le montage ; son dossier d'échange est `Zomboid/Lua/batman_CoreAI/`, les fiches de
voix restent dans `Zomboid/Lua/batman_RadioSurvivor/personas` (RadioSurvivor actif seulement). Module réseau du
carnet : `CoreAI` ; stock du carnet : `Zomboid/Lua/batman_CoreAI/notebook-<monde>-<0|1>.txt` ; `RS_State` ne garde que
les données des voix.

Mods de test, jamais publiés : `dev/batman_CoreAITests` (moteur RST, aides communes, suites `ca.*`),
`dev/batman_LivingKnoxTests` (suites `lk.*`), `dev/batman_RadioSurvivorTests` (suites `rs.*`). Un banc hors jeu de
Living Knox ne charge que des fichiers de CoreAI et de Living Knox.

Pas de reprise des anciennes sauvegardes : les mods ne sont pas publiés avec une sauvegarde à reprendre, et aucune
migration n'est écrite ni documentée.

Les observations des PNJ, leurs déclencheurs et l'option de fréquence des initiatives appartiennent à Living Knox
(`E18-T27`) : seul ou avec RadioSurvivor, un PNJ prend la parole de lui-même et deux PNJ se racontent ce qu'ils ont vu ;
deux membres d'un groupe bavardent à leur foyer devant un joueur (`E18-T32`).

## Architecture validée — à préserver

Architecture validée par la décision utilisateur LK00-T02 du 2026-10-03
([`annexes/plans-termines/LK00-cadrage.md`](annexes/plans-termines/LK00-cadrage.md)), fusion confirmée le 2026-10-08 : serveur
autoritaire, adaptateurs d'exécution, fournisseur de PNJ. Vue détaillée :
[`architecture/README.md`](architecture/README.md). **Aucun changement de pattern ni migration** sans décision.

- Domaine et décisions serveur : missions, récompenses, groupes et état privé ; seules ces fonctions décident des
  effets persistants.
- Adaptateurs moteur : inventaire, monde, XP et réseau ; exécutent uniquement les décisions validées par le serveur.
- `CA_NPCProvider` : interface entre le carnet de CoreAI et un moteur de PNJ (Living Knox : `LK_NotebookProvider`) ;
  le carnet ne dépend ni des détails des corps ni d'un mod nommé.
- Client : présentation, gestes du propriétaire et demandes ; aucune autorité sur récompenses, stocks ou objectifs.
- Pont Python : validation du protocole et proposition du modèle dans les listes fermées ; jamais autorité sur objets,
  fréquences, coordonnées ou récompenses.
- Dépendances : présentation/pont → contrat → décisions serveur → adaptateurs moteur ; chaque mod dépend de CoreAI,
  jamais de l'autre ; état secret dans les fichiers privés (CoreAI, `RS_State`, registres de Living Knox) uniquement.
- **Principes SOLID dès la conception** (demande de l'utilisateur du 2026-11-13). Une nouvelle routine, tâche du foyer,
  activité, variante ou nature d'effet passe par un registre et vit dans son propre fichier (modèle : registre des
  tâches `LivingKnox.Upkeep.registerJob`, dossier `server/LivingKnox/Jobs/`, ADR
  [`registre des routines`](architecture/decisions/adr-registre-routines.md)). Interdit : ajouter un cas à une chaîne
  `if kind == "…"` ou à une liste de noms dans un moteur ; au plus tard au troisième cas du même genre, extraire un
  registre avant d'ajouter le suivant. À la clôture d'une tâche, relire le module touché (une responsabilité par
  fichier, ajout sans modification du moteur) et signaler tout écart dans le compte rendu.
- **Atelier des voix** (`bridge/atelier/`, décision `E24-T02` du 2026-11-16) : tout nouvel écran de l'atelier suit la
  [charte de l'atelier](annexes/conception/charte-atelier.md) (rien de technique à l'écran, nombres en crans nommés,
  identifiants fabriqués).

## Méthode du plan

- Le développement suit le plan de [`annexes/plans/`](annexes/plans/) : méthode dans
  [`annexes/plans/README.md`](annexes/plans/README.md), état généré dans
  [`annexes/plans/SUIVI.md`](annexes/plans/SUIVI.md), prochaine tâche par `python tools/plan.py next`
  (skill `radiosurvivor-plan`). Préfixes : `E` (radio, carnet, missions) et `LK` (moteur de PNJ).
- **Une tâche à la fois.** Les décisions marquées `à décider` se posent à l'utilisateur avant tout code : une question
  à la fois, trois réponses fermées et une réponse libre.
- **Le banc hors jeu fait l'essentiel, le jeu confirme** (demande de l'utilisateur du 2026-11-13,
  [ADR du banc mimétique](architecture/decisions/adr-banc-mimetique.md)). Une doublure d'API Java ne définit que des
  méthodes qui existent dans le jeu, avec leurs refus ; un système écrit en Lua par le jeu se charge pour de vrai au
  banc plutôt que d'être réécrit. **Un défaut vu en jeu se reproduit d'abord au banc** : il reçoit une ligne dans
  [`annexes/tests/ecarts-banc-jeu.md`](annexes/tests/ecarts-banc-jeu.md) avec sa catégorie, puis un test rouge au banc
  quand la catégorie le permet, puis la correction.
- Avant de déclarer une tâche testée : `tests/test_protocol.py`, `tests/test_carnet.py`, luacheck (sans nouvel
  avertissement) et `python tools/plan.py check`. La suite complète se lance **pour le mod sur lequel on travaille** (ADR `adr-coreai-separation` D06) : `python tests/run_all.py --mod radiosurvivor` pour RadioSurvivor, `--mod livingknox` pour Living Knox ; chacune garde les tests du mod commun. Sans `--mod`, tout le dépôt, seulement si le travail touche les deux.
- Tests en jeu ([méthode](annexes/tests/tests-en-jeu.md)) : `python tools/autoclient/autoclient.py --campaign
  solo-lk|solo-rs|solo --bridge on --llm fake --wait-idle 3600` (`solo-lk` : Living Knox seul, sans RadioSurvivor ;
  `solo-rs` : RadioSurvivor seul ; `solo` : les deux) et la campagne `mp` (serveur dédié et deux clients). Rapports
  dans `Zomboid/Lua/batman_CoreAITests/tests/`.

## Écriture indépendante (Living Knox)

Ne jamais copier, traduire ligne à ligne ni paraphraser du code de Bandits! (`3268487204`) ou de Project A-Life
(`3803984183`). Sources de conception autorisées : Java et Lua vanilla 42.21, la base de connaissances du moteur de
l'utilisateur, nos propres essais. Les analyses
[`annexes/recherches/bandits-analyse.md`](annexes/recherches/bandits-analyse.md) et
[`annexes/recherches/alife-analyse.md`](annexes/recherches/alife-analyse.md) servent de retour d'expérience (problèmes
à prévoir), **pas de modèle de code**.

## Dépôt

Dépôt GitHub **public** (MIT, créé le 2026-10-15 sans historique) : une seule branche, **`main`**, qui porte
toujours le dernier état du mod (décision du 2026-10-24, alignée sur les autres dépôts de mods de l'utilisateur :
l'ancienne branche de travail `dev` a été fusionnée par avance rapide puis supprimée, ici et sur `origin`). N'y
mettre aucune donnée personnelle : chemins absolus du poste de l'utilisateur, adresses, noms de dépôts privés, clés —
les clés du pont restent dans `bridge/.env`, jamais versionné. Un remote local `archive` pointe vers l'archive privée
de l'ancien dépôt (branches locales `archive-dev` et `archive-main`) : **ne jamais pousser une branche `archive-*`
vers `origin`.**
