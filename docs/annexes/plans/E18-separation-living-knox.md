# E18 — Séparer Living Knox et RadioSurvivor en deux mods autonomes

**Objectif.** Livrer deux mods qui fonctionnent chacun sans l'autre et mieux ensemble : `batman_RadioSurvivor` (radio,
voix, carnet, missions, factions, troc des voix) et `batman_LivingKnox` (moteur de PNJ : corps, gestes, groupes,
routines, combat, parole de proximité). Le pont Python LLM sert l'un, l'autre ou les deux.

**Dépend de.** `E17` (interface `RS_NPCProvider`, déjà neutre vis-à-vis du moteur) ; `LK12` (API publique de Living Knox).

**Sources.** Relevé des liens entre les deux moteurs du 2026-11-05 (résumé ci-dessous) ; `docs/architecture/README.md` ;
`docs/specifications-techniques/protocole-carnet-v2.md` ; `docs/specifications-techniques/api-living-knox.md` ;
`shared/RadioSurvivor/RS_NPCProvider.lua` (contrat).

## Décisions

- 2026-11-05 — **Séparation** (utilisateur) : RadioSurvivor et Living Knox deviennent deux mods qui fonctionnent chacun
  sans l'autre ; revient sur la fusion du 2026-10-08 (`E17`, `docs/architecture/decisions/README.md`).
- 2026-11-05 — **Forme** (utilisateur) : **un seul article Workshop, deux mods** à cocher séparément dans la liste des
  mods ; même projet `Workshop\RadioSurvivor` et même dépôt, deux dossiers frères sous `Contents/mods`.
- 2026-11-05 — **Pont** (utilisateur) : le pont Python LLM doit servir les deux mods ensemble ou l'un des deux seul.
  Conséquence : avec Living Knox seul, un joueur parle aux PNJ et reçoit une réponse du LLM ; la parole des PNJ
  (demandes `npc_talk`, `npc_converse`, `npc_initiative`, `npc_enrich`) est émise par Living Knox ; RadioSurvivor,
  s'il est présent, y ajoute son contexte (missions, relations, réputation, offres, accords) et applique ses actions
  dans la réponse.
- 2026-11-05 — Confirmé par défaut (valeurs techniques, modifiables) :
  - identifiant du nouveau mod `batman_LivingKnox`, nom affiché « Living Knox » ; `batman_RadioSurvivor` garde son
    identifiant (sauvegardes, dossier d'échange du pont et dossiers de données inchangés) ;
  - aucun troisième mod de bibliothèque : les petits modules communs (codec, limite de débit, découpe des bulles,
    valeurs de troc, début du monde) sont copiés dans Living Knox sous des noms `LK_` ; chaque mod garde sa copie ;
  - données de Living Knox sous `Zomboid\Lua\batman_LivingKnox\`, reprises une fois de l'ancien dossier
    `batman_RadioSurvivor\livingknox\` au premier lancement (aucune partie existante perdue) ;
  - clé de joueur propre à Living Knox (compte et personnage) pour les attitudes ; RadioSurvivor y relie son
    personnage du carnet quand il est présent ;
  - un seul processus de pont lit les dossiers d'échange des mods présents ; signal de vie écrit dans chacun ;
  - un seul mod de test de développement pour les deux, qui accepte trois montages (RadioSurvivor seul, Living Knox
    seul, les deux) ; campagnes solo et MP dans les trois montages.

## Relevé des liens (2026-11-05, lecture du code, confirmé statiquement)

- RadioSurvivor → Living Knox : un seul lien dur, l'adaptateur `shared/RadioSurvivor/RS_LivingKnox.lua` (requiert
  `LK_Core` et `LK_Config`) ; tout le reste passe par `RS_NPCProvider` ou par des gardes `nil`.
- Living Knox → RadioSurvivor : `LK_ZombieGuard` (`RS_RateLimit`), `LK_Store` (`RS_Codec`, format des registres),
  `LK_Server` (`RS_WorldStart`), `LK_Sites` et `LK_Simulation` (`RS_Rescue`, qui tire `RS_State` et `RS_Factions`),
  `LK_Trade` et `LK_TradeView` (`RS_TradeValues`), `LK_SpeechView` (`RS_TextCut`) ; clé de joueur des attitudes lue
  dans le carnet (`LK_Hostility`, `RS_CarnetServer`).
- Ressources communes : `sandbox-options.txt` (pages `RadioSurvivor` et `LivingKnox`), `IG_UI.json` et `Sandbox.json`
  (préfixes déjà disjoints : `IGUI_LK_`, `Sandbox_LivingKnox_` contre `IGUI_RS_`, `IGUI_RadioSurvivor_`,
  `Sandbox_RadioSurvivor_`) ; AnimSets `lkactor_*` (Living Knox seul).
- Pont : toutes les demandes LLM sont émises aujourd'hui par RadioSurvivor ; dossier d'échange, signal de vie et
  personnages fixés sur `batman_RadioSurvivor`.

## Hors périmètre

Deuxième article Workshop, dépôt séparé, mod de bibliothèque commun, changement des règles de jeu des deux moteurs.

## Tâches

- [ ] **E18-T01** — Mod `batman_LivingKnox` : dossier, métadonnées et code déplacé
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `Contents/mods/batman_LivingKnox/` (`common/`, `42.21/mod.info`) ; code `media/lua/*/LivingKnox/`, AnimSets `lkactor_*`, page `LivingKnox` des options sandbox, clés `IGUI_LK_` et `Sandbox_LivingKnox_` (EN, FR et autres langues) déplacés depuis `batman_RadioSurvivor` ; `tools/gen_animsets.py`
  - Faire : déplacer le moteur dans le nouveau mod, avec ses ressources ; `incompatible=` Bandits! et Project A-Life repris par Living Knox ; RadioSurvivor ne cite plus Living Knox dans `require=`.
  - Accepté si : chaque mod se charge seul sans erreur Lua ; les deux ensemble se chargent comme aujourd'hui ; aucun fichier du moteur n'est resté dans `batman_RadioSurvivor`.
  - Tests : `run_all.py` (bancs adaptés aux deux dossiers) ; démarrage solo de chaque montage.
  - Preuve : —
  - Reste : —

- [ ] **E18-T02** — Modules communs copiés dans Living Knox
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E18-T01
  - Fichiers : `LK_Codec`, `LK_RateLimit`, `LK_TextCut`, `LK_TradeValues`, `LK_WorldStart` (nouveaux) ; `LK_Store`, `LK_ZombieGuard`, `LK_Server`, `LK_Trade`, `LK_TradeView`, `LK_SpeechView`
  - Faire : plus aucun `require "RadioSurvivor/..."` dans Living Knox ; format des registres (RSV2) identique, relu tel quel.
  - Accepté si : recherche `RadioSurvivor/` vide dans le code de Living Knox ; anciens registres relus octet pour octet.
  - Tests : bancs `test_lk_*` ; banc de relecture d'un registre écrit par l'ancien code.
  - Preuve : —
  - Reste : —

- [ ] **E18-T03** — Bases connues et sites sans RadioSurvivor
  - État : `à faire`
  - Cible : `solo`
  - Dépend de : E18-T02
  - Fichiers : `LK_Sites`, `LK_Simulation` (`knownBases`), `RS_Rescue`
  - Faire : Living Knox ne requiert plus `RS_Rescue` ; les bases des joueurs connues de RadioSurvivor lui parviennent par un crochet optionnel de l'API ; seul, Living Knox repère les bases par ses propres moyens ou s'en passe.
  - Accepté si : sites et raids tournent sans RadioSurvivor ; avec lui, mêmes bases qu'aujourd'hui.
  - Tests : bancs `test_lk_sites*`, `test_lk_raids` ; suites lk.sites et lk.raids dans les deux montages.
  - Preuve : —
  - Reste : —

- [ ] **E18-T04** — Adaptateur fournisseur porté par Living Knox
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T01
  - Fichiers : `RS_LivingKnox.lua` (déplacé dans `batman_LivingKnox`, chargé seulement si RadioSurvivor est présent) ; `RS_NPCProvider.lua` (reste dans RadioSurvivor)
  - Faire : le fournisseur s'enregistre auprès de `RS_NPCProvider` quand les deux mods sont actifs ; sans Living Knox, RadioSurvivor tourne avec « aucun moteur de PNJ » (cas déjà prévu par E17).
  - Accepté si : RadioSurvivor seul démarre sans erreur et sans fiche de PNJ ; les deux ensemble se comportent comme aujourd'hui.
  - Tests : bancs `test_carnet.py`, `test_lk_api*` ; campagnes des trois montages.
  - Preuve : —
  - Reste : —

- [ ] **E18-T05** — Clé de joueur propre à Living Knox
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T02
  - Fichiers : `LK_Hostility`, `LK_Alert`, `LK_Decisions`, `RS_LivingKnox.lua`
  - Faire : attitudes, faits et alertes de Living Knox clés par une identité qu'il possède (compte et personnage) ; RadioSurvivor relie son personnage du carnet à cette clé ; attitudes déjà enregistrées reprises.
  - Accepté si : Living Knox seul garde les relations avec chaque joueur après reconnexion et redémarrage ; avec RadioSurvivor, mêmes attitudes qu'avant la séparation.
  - Tests : bancs `test_lk_hostility*` ; phases MP reconnexion et redémarrage.
  - Preuve : —
  - Reste : —

- [ ] **E18-T06** — Dossier de données de Living Knox et reprise des parties existantes
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T02
  - Fichiers : `LK_Store` (`DIR`), `LK_Groups`, `LK_Hostility`
  - Faire : registres sous `Zomboid\Lua\batman_LivingKnox\` ; au premier lancement, reprise une seule fois de `batman_RadioSurvivor\livingknox\` (copie, ancien dossier laissé en place, ligne de journal en anglais).
  - Accepté si : une partie créée avant la séparation garde ses groupes, foyers et attitudes ; une reprise ne se refait pas.
  - Tests : banc de reprise ; phase `after-restart` sur une partie d'avant la séparation.
  - Preuve : —
  - Reste : —

- [ ] **E18-T07** — Parole des PNJ émise par Living Knox, enrichie par RadioSurvivor
  - État : `à décider`
  - Cible : `MP`
  - Dépend de : E18-T04, E18-T05
  - Fichiers : nouveau transport de Living Knox (`LK_Transport`, `LK_Talk`) ; `RS_Carnet_Server.lua` (talk), `RS_Conversations`, `RS_Initiatives`, `RS_Incidents` ; `docs/specifications-techniques/protocole-carnet-v2.md` ; `bridge/npc_protocol.py`
  - Faire : Living Knox émet `npc_talk`, `npc_converse`, `npc_initiative` et `npc_enrich` par son propre dossier d'échange, avec ses quotas et un secours sans pont ; RadioSurvivor ajoute au contexte ses éléments (missions, offres, réputation, relation, accords) et traite ses actions de la réponse par des crochets de l'API ; le carnet reste un affichage de RadioSurvivor.
  - Questions : Quand les deux mods sont actifs, qui garde l'historique des échanges avec un PNJ ? Options : Living Knox, RadioSurvivor le lit pour le carnet [recommandé] / RadioSurvivor, comme aujourd'hui / chacun le sien.
  - Accepté si : Living Knox seul : une phrase dite près d'un PNJ reçoit une réponse du LLM en bulle ; les deux ensemble : mêmes offres, acceptations et relations qu'aujourd'hui (suites rs.npctalk, rs.conversations, rs.initiatives).
  - Tests : `test_protocol.py`, bancs du transport ; suites de parole dans les trois montages.
  - Preuve : —
  - Reste : —

- [ ] **E18-T08** — Pont commun aux deux mods
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T07
  - Fichiers : `bridge/radio_bridge.py`, `bridge/npc_protocol.py`, `bridge/README*`, `RadioSurvivor_Const.lua` (signal de vie), équivalent Living Knox
  - Faire : un processus lit les dossiers d'échange `batman_RadioSurvivor` et `batman_LivingKnox` présents (option `--exchange` répétable, valeur par défaut : ceux qui existent) ; signal de vie dans chacun ; verrou d'instance unique par dossier ; personnages des voix lus seulement chez RadioSurvivor ; limites de texte de Living Knox lues dans un seul endroit.
  - Accepté si : le même pont, sans option, sert RadioSurvivor seul, Living Knox seul et les deux ; aucun dossier inexistant créé.
  - Tests : bancs du pont (`tests/test_bridge*`, `test_protocol.py`) dans les trois montages ; campagnes avec `--bridge on`.
  - Preuve : —
  - Reste : —

- [ ] **E18-T09** — Traductions et options sandbox séparées
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E18-T01
  - Fichiers : `media/lua/shared/Translate/*/IG_UI.json`, `Sandbox.json` des deux mods ; `media/sandbox-options.txt` des deux mods
  - Faire : chaque mod porte ses clés et sa page d'options ; aucune clé ni option perdue, dans toutes les langues livrées.
  - Accepté si : union des clés des deux mods égale aux clés d'avant ; aucune clé `IGUI_LK_` dans RadioSurvivor ni `IGUI_RS_` dans Living Knox.
  - Tests : banc de comparaison des clés ; `check_case`.
  - Preuve : —
  - Reste : —

- [ ] **E18-T10** — Outillage des tests pour trois montages
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E18-T01
  - Fichiers : `dev/batman_RadioSurvivorTests/42.21/mod.info` (plus de `require=` dur, détection des mods actifs) ; `tests/harness.py`, `tests/run_all.py` ; `tools/autoclient/autoclient.py` (`--mods rs|lk|both`, dossiers de résultats et d'échange) ; `tests/run_dedicated_smoke.ps1` ; listes des campagnes
  - Faire : chaque suite déclare les mods qu'elle exige (SKIP sinon) ; les suites mixtes (carnet et PNJ) ne tournent qu'avec les deux ; campagnes `solo` et `mp` lançables dans chaque montage.
  - Accepté si : `run_all.py` vert ; un passage de chaque montage démarre et rend un rapport.
  - Tests : bancs `test_autoclient.py`, `test_rst.py`.
  - Preuve : —
  - Reste : —

- [ ] **E18-T11** — Validation des trois montages
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E18-T03, E18-T06, E18-T08, E18-T09, E18-T10
  - Fichiers : ce fichier
  - Faire : campagnes solo et MP automatiques avec RadioSurvivor seul, Living Knox seul et les deux, pont avec faux modèle ; reconnexion et redémarrage pour les deux ensemble.
  - Accepté si : six campagnes vertes (hors instabilités suivies par leur propre tâche, citées dans la preuve).
  - Tests : campagnes automatiques.
  - Preuve : —
  - Reste : —

- [ ] **E18-T12** — Documentation et page Workshop des deux mods
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E18-T11
  - Fichiers : `README.md`, `README_fr.md`, `README.steam*`, `docs/developpement.md`, `docs/architecture/README.md`, `docs/architecture/decisions/README.md`, wiki (`docs/wiki/*`), `docs/annexes/plans/README.md`
  - Faire : expliquer les trois montages au joueur (quoi cocher, ce que chacun apporte, le pont) ; architecture et décisions à jour ; page Steam qui présente les deux mods de l'article.
  - Accepté si : aucune page ne décrit encore un mod unique ; descriptions Steam dans toutes les langues sous la limite de 8 000 octets.
  - Tests : `plan.py check` ; contrôle de taille des descriptions.
  - Preuve : —
  - Reste : —
