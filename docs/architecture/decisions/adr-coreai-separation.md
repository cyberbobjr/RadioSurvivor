# ADR — Living Knox et RadioSurvivor séparés autour de `batman_CoreAI`

| | |
|---|---|
| Date | 2026-11-15 |
| Statut | Accepté |
| Décideur | utilisateur |
| Complète | [Trois mods dans un article](adr-separation-mods.md) (2026-11-05) : D01, D02, D04, D05 y restent valables ; D03 et D06 sont remplacées ici |
| Plan associé | [E21 — Séparer Living Knox et RadioSurvivor autour de batman_CoreAI](../../annexes/plans-termines/E21-separation-coreai.md) (suivi des tâches dans le plan) |
| Références | relevé des liens du 2026-11-15 (résumé dans le plan E21, section Sources) ; [API Living Knox](../../specifications-techniques/api-living-knox.md) ; [protocole du carnet v2](../../specifications-techniques/protocole-carnet-v2.md) |

## Contexte

Consignes de l'utilisateur du 2026-11-15 :

- « Il faut bien séparer LivingKnox et RadioSurvivors, la seule chose qu'ils ont en commun c'est le bridge, et des
  méthodes factorisées pour le même comportement. Les tests LivingKnox ne devraient pas toucher à RadioSurvivors. Le
  module de partage commun « RadioSurvivors Core » devrait s'appeler « batman_CoreAI ». »
- Transmise par la session E20 le même jour : « le point commun entre RS et LK c'est le carnet, donc le carnet doit
  être dans batman_CoreAI ».

Le relevé du 2026-11-15 montre que la séparation de E18 reste incomplète :

- **Living Knox connaît RadioSurvivor.** L'adaptateur `shared/RadioSurvivor/RS_LivingKnox.lua` vit dans Living Knox.
  Il charge `RadioSurvivor/RS_NPCProvider` et définit le global `RS_LivingKnox`, que lit `LK_Admin`.
  `LivingKnox.radioSurvivorActive()` règle la parole (`LK_TalkView`, `LK_TalkAlone`) et les contacts (`LK_Contacts`).
  Onze journaux portent `[RS_Conversations]`, `[RS_Incidents]` et `[RS_Initiatives]`.
- **RadioSurvivor connaît Living Knox.** `RS_Carnet_Server`, `RS_Facts` et `RS_Relations` appellent
  `LivingKnox.Agreements`, `Relations`, `Hostility`, `Talk`, `Observations`, `PersonalRelation` et `API`, et
  s'abonnent à trois événements `OnLivingKnox…`. Le mod commun lui-même lit `LivingKnox.Identity`
  (`RC_MissionClear`).
- **Le carnet appartient à RadioSurvivor**, alors que les PNJ s'y inscrivent. Il comprend `RS_Notebook`,
  `RS_MissionViews` et `MissionViews/`, `RS_MapActions`, `RS_DeadDropLines`, `RS_Carnet_Server` et l'interface
  `RS_NPCProvider`.
- **Le mod commun porte le nom de RadioSurvivor.** On le retrouve dans l'identifiant, le dossier Lua, le global
  `RadioSurvivorCore`, le module réseau, le dossier d'échange du pont, les clés `RS_CarnetCharacter`, `RS_Cache`,
  `RS_ClearCounted` et `RS_RetrieveMission`, et le verrou `RadioSurvivor`.
- **Les tests de Living Knox touchent RadioSurvivor.** 44 bancs `test_lk_*.py` chargent du code RadioSurvivor, ou un
  dossier qui porte son nom. Les suites en jeu `lk.*` vivent dans `batman_RadioSurvivorTests`.

## Décisions

- **D01 — Deux mods qui s'ignorent.** Ni `batman_LivingKnox` ni `batman_RadioSurvivor` ne nomment l'autre :
  - aucun `require` ;
  - aucun global ni événement de l'autre ;
  - aucun test de son identifiant de mod ;
  - aucun journal à son préfixe.

  Ce qu'ils partagent passe par `batman_CoreAI`.
- **D02 — `batman_CoreAI`, mod commun.** Il contient le lien avec le pont, le carnet (D04) et les méthodes factorisées
  pour un même comportement :
  - moteur et gabarits de missions ;
  - identité ;
  - historique ;
  - réputation ;
  - contacts ;
  - équipes ;
  - lieux ;
  - faits du monde ;
  - petits outils.

  Un module qui ne sert qu'à un mod va dans ce mod. Les gabarits de mission restent communs : les deux donneurs de
  missions s'en servent (D04 de l'ADR de 2026-11-05).
  - *Mise à jour du 2026-11-17 (utilisateur) :* les cinq gabarits que seules les voix de RadioSurvivor donnent
    aujourd'hui (barricade, objet, relais, itinéraire, surveillance) restent eux aussi dans `batman_CoreAI` : les PNJ
    de Living Knox pourront les donner plus tard. Un gabarit de mission n'est jamais rangé selon son seul donneur
    actuel.
- **D03 — Nommage du mod commun (confirmé par défaut).** Mod pas encore publié : aucune reprise de données.

  | Élément | Nouvelle valeur |
  |---|---|
  | Dossier et `id=` | `batman_CoreAI` |
  | `name=` | `batman_Core AI` |
  | Dossier Lua | `CoreAI/` |
  | Global | `CoreAI` |
  | Préfixe des fichiers et globaux | `CA_` (`CA_Identity`…) |
  | Clés de traduction | `IGUI_CA_` |
  | Module réseau | `CoreAI` |
  | Dossier d'échange | `Zomboid/Lua/batman_CoreAI/` |
  | Journaux | `[CoreAI]` |
  | Clés de ModData et verrou | `CA_Character`, `CA_Cache`, `CA_ClearCounted`, `CA_RetrieveMission`, verrou `CoreAI` |
- **D04 — Le carnet dans `batman_CoreAI`.** Le carnet entier passe dans le mod commun :
  - fenêtre et pages ;
  - vues par type de mission ;
  - zones sur la carte ;
  - lignes des planques ;
  - partie serveur ;
  - interface des fournisseurs de personnages (`RS_NPCProvider` → `CA_NPCProvider`).

  Les voix de RadioSurvivor et les PNJ de Living Knox s'y inscrivent par des registres (fournisseurs, pages, vues,
  actions). Le carnet ne connaît ni l'un ni l'autre.
- **D05 — Échanges entre les deux mods, par le commun seulement (confirmé par défaut).** Une information de Living Knox
  utile aux voix passe par un registre ou un événement neutre de `batman_CoreAI`. C'est le cas des faits de groupe, des
  accords et des relations. Le mod qui la lit ne sait pas qui l'a écrite. Un comportement qui ne peut pas passer par un
  registre neutre est retiré, nommé dans la tâche et signalé à l'utilisateur.
- **D06 — Tests séparés (confirmé par défaut).** Trois mods de test :

  | Mod de test | Contenu |
  |---|---|
  | `batman_CoreAITests` | outil de suites `RST`, aides communes, suites `rc.*` |
  | `batman_LivingKnoxTests` | suites `lk.*` et leurs aides |
  | `batman_RadioSurvivorTests` | suites `rs.*` et leurs aides |

  Un banc hors jeu de Living Knox ne charge que des fichiers de `batman_CoreAI` et de `batman_LivingKnox`. La campagne
  `solo-lk` charge CoreAI, Living Knox et leurs mods de test, sans RadioSurvivor ni Belt Walkie-Talkie. Les tests des
  deux mods ensemble vérifient les registres du commun, avec des doublures neutres.
- **D07 — Même dépôt, même article Workshop (confirmé par défaut).** Le joueur coche RadioSurvivor et/ou Living Knox ;
  `batman_CoreAI` est activé par leur `require=`.
- **D08 — Le pont reste commun.** Il change seulement de dossier d'échange (D03).

## Conséquences

- L'architecture validée est conservée : serveur autoritaire, adaptateurs d'exécution, registres. Les dépendances
  changent de sens : chaque mod dépend du commun, jamais de l'autre.
- RadioSurvivor perd le carnet et devient un fournisseur du carnet commun (voix, vues de ses missions, troc,
  réputation). Living Knox en devient un autre (PNJ, missions de foyer).
- Tous les chemins, globaux et clés `RC_`/`RadioSurvivorCore` changent. Cela touche environ 210 fichiers hors
  `Contents/` : tests, outils, pont, docs et mod de test.
- La page Workshop et les README décrivent le nouveau mod commun.

## Mise à jour du 2026-11-17 — D09 : tests hors jeu rangés par mod

Constat : D06 a séparé les mods de test en jeu (`dev/`), pas les tests hors jeu. Les 230 fichiers de `tests/`
(RadioSurvivor, Living Knox, mod commun, doublures partagées) sont à plat dans un seul dossier, et la suite complète
lançait les tests de Living Knox pendant un travail sur RadioSurvivor.

- **D09 — Un dossier de tests hors jeu par mod (utilisateur, 2026-11-17).** `tests/coreai/`, `tests/radiosurvivor/`,
  `tests/livingknox/`, plus un dossier commun pour les doublures, le banc et les aides partagées. Un travail sur
  RadioSurvivor lance ses tests et ceux du mod commun, jamais ceux de Living Knox, et inversement
  (`tests/run_all.py --mod radiosurvivor|livingknox`). Les tests qui vérifient les deux mods ensemble ont leur propre
  dossier et ne tournent que pour un travail qui touche les deux. Le rangement attend que la session Living Knox ait
  commité, pour ne rien écraser. Plan : [E26](../../annexes/plans/E26-tests-par-mod.md).
