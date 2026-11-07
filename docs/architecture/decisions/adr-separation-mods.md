# ADR — Trois mods dans un article : RadioSurvivor, Living Knox et un mod commun

| | |
|---|---|
| Date | 2026-11-05 |
| Statut | Accepté |
| Décideur | utilisateur |
| Remplace | la fusion du 2026-10-08 (Living Knox intégré à `batman_RadioSurvivor`) |
| Plan associé | [E18 — Séparer RadioSurvivor et Living Knox autour d'un mod commun](../../annexes/plans/E18-separation-living-knox.md) (suivi des tâches dans le plan) |
| Références | relevé des liens du 2026-11-05 (résumé dans le plan E18) ; [`RS_NPCProvider`](../README.md) ; [protocole du carnet v2](../../specifications-techniques/protocole-carnet-v2.md) ; [API Living Knox](../../specifications-techniques/api-living-knox.md) |

## Contexte

Depuis le 2026-10-08, la radio, le carnet et le moteur de PNJ Living Knox forment un seul mod. L'utilisateur veut
que chacun puisse servir sans l'autre : un serveur peut vouloir les PNJ sans la radio, ou la radio sans les PNJ. Les
deux donnent des missions et s'appuient sur le pont Python LLM. Le relevé du code du 2026-11-05 montre un seul lien dur
de RadioSurvivor vers Living Knox (l'adaptateur du fournisseur de PNJ), et une dizaine d'emprunts de Living Knox à
RadioSurvivor (outils, état des secours, identité des joueurs).

## Décisions

- **D01 — Deux mods autonomes.** `batman_RadioSurvivor` (radio, voix, carnet, factions, troc des voix) et
  `batman_LivingKnox` (moteur de PNJ et parole de proximité) fonctionnent chacun seul ; ensemble, RadioSurvivor
  enrichit les PNJ (relations, réputation, accords).
- **D02 — Un seul article Workshop.** Même projet, même dépôt, dossiers frères sous `Contents/mods` ; le joueur coche
  RadioSurvivor et/ou Living Knox.
- **D03 — Un mod commun.** Le code partagé n'existe qu'une fois, dans `batman_RadioSurvivorCore`, exigé (`require=`) par
  les deux mods et activé par le jeu sans que le joueur le coche : moteur de missions, lien avec le pont LLM (file,
  quotas, signal de vie, dossier d'échange unique), identité des personnages, historique des échanges, petits outils
  (codec, découpe des bulles, limite de débit, valeurs de troc, horloge de jeu, début du monde).
- **D04 — Deux donneurs de missions.** Les voix radio (RadioSurvivor) et les PNJ (Living Knox) proposent des missions
  par le même moteur commun.
- **D05 — Le pont, base de l'intelligence.** Le pont Python LLM sert RadioSurvivor seul, Living Knox seul ou les deux.
  Living Knox émet lui-même la parole de ses PNJ (`npc_talk`, `npc_converse`, `npc_initiative`, `npc_enrich`).
- **D06 — Journal commun des missions.** Le mod commun apporte un journal des missions ; avec RadioSurvivor, le carnet
  l'intègre à son onglet missions (une seule liste).
- **D07 — Historique dans le commun.** L'historique des échanges avec un PNJ (et avec une voix radio) est gardé par le
  mod commun, lu par le carnet.
- **D08 — Parties existantes reprises. Abandonnée le 2026-11-07** (consigne de l'utilisateur : les mods ne sont pas
  publiés avec une sauvegarde à reprendre). Texte d'origine : missions, identités, historiques, groupes et attitudes
  d'une partie d'avant la séparation sont repris une fois au premier lancement, sans perte. Aucune reprise n'est écrite.

Valeurs techniques confirmées par défaut (identifiants, dossiers de données, outillage des tests) : voir la section
« Décisions » du plan E18.

## Conséquences

- L'architecture validée (serveur autoritaire, adaptateurs d'exécution, fournisseur de PNJ `RS_NPCProvider`) est
  conservée ; seule la répartition en mods change.
- Living Knox ne requiert plus aucun module de RadioSurvivor ; les liens restants passent par le mod commun, l'API
  publique de Living Knox et `RS_NPCProvider`.
- Le dossier d'échange du pont change (mod commun : `Zomboid/Lua/batman_RadioSurvivorCore/`). L'ancien n'est pas lu
  (révision du 2026-11-07, voir D08) ; les fiches de voix restent dans `Zomboid/Lua/batman_RadioSurvivor/personas`.
- Les tests tournent dans trois montages (RadioSurvivor seul, Living Knox seul, les deux), en solo et en MP.
- La page Workshop présente les mods de l'article et ce que chacun apporte.
