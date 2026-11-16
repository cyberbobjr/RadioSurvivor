# Journal des décisions

Les décisions de conception sont datées dans la section « Décisions » de chaque fichier d'étape du plan
([annexes/plans/](../../annexes/plans/README.md)) : c'est leur source unique. Cette page relève celles qui fixent
l'architecture et range les ADR rédigés à part.

## Décisions d'architecture

| Date | Décision | Source |
|---|---|---|
| 2026-10-03 | Moteur de PNJ propre (option C de l'analyse) : décisions sur le serveur, corps exécutés par le seul client propriétaire, gestes relayés | [LK00-cadrage.md](../../annexes/plans-termines/LK00-cadrage.md), [ia-multijoueur.md](../ia-multijoueur.md) |
| 2026-10-03 | Écriture indépendante : aucun code de Bandits! ni de Project A-Life repris, traduit ou paraphrasé | [LK00-cadrage.md](../../annexes/plans-termines/LK00-cadrage.md), [conception/README.md](../../annexes/conception/README.md) |
| 2026-10-03 | Groupes de 3 à 5, simulation abstraite hors de portée des joueurs, relève après 2 à 5 jours | [LK00-cadrage.md](../../annexes/plans-termines/LK00-cadrage.md) |
| 2026-10-08 | Fusion de Living Knox dans `batman_RadioSurvivor` : un seul mod, un seul plan (préfixes `E` et `LK`) ; **remplacée le 2026-11-05** par la séparation en trois mods | [LK00-cadrage.md](../../annexes/plans-termines/LK00-cadrage.md), [E17](../../annexes/plans-termines/E17-fournisseur-pnj-living-knox.md) |
| 2026-10-08 | Carnet indépendant du moteur de PNJ par l'interface `RS_NPCProvider` ; adaptateur Bandits! retiré (`E17-T02`) | [E17-fournisseur-pnj-living-knox.md](../../annexes/plans-termines/E17-fournisseur-pnj-living-knox.md) |
| 2026-10-09 | Corps des PNJ : base B « joueur réanimé » retenue au jalon 1, base A (zombie ordinaire) abandonnée | [LK02-jalon-corps-gestes.md](../../annexes/plans-termines/LK02-jalon-corps-gestes.md) |
| 2026-10-09 | Six voix, fréquences tirées par partie et jamais envoyées aux clients, découvertes par des notes | [E05-voix-reseau-radio.md](../../annexes/plans-termines/E05-voix-reseau-radio.md) |
| 2026-11-05 | Séparation : `batman_RadioSurvivor` et `batman_LivingKnox` autonomes dans un article Workshop, sur un mod commun `batman_RadioSurvivorCore` (missions, pont LLM, identité, historique, outils) ; remplace la fusion du 2026-10-08. Révision du 2026-11-07 : pas de reprise des parties d'avant la séparation (D08 de l'ADR abandonnée) | [adr-separation-mods.md](adr-separation-mods.md), [E18](../../annexes/plans-termines/E18-separation-living-knox.md) |
| 2026-11-14 | Chaque mod paie ses missions : un PNJ Living Knox est payé par Living Knox (source de récompense déclarée au mod commun), RadioSurvivor ne paie que ses voix et ne lit plus Living Knox pour une récompense | [adr-separation-mods.md](adr-separation-mods.md) (D09), [E11](../../annexes/plans-termines/E11-missions-generees.md) |
| 2026-11-15 | Living Knox et RadioSurvivor s'ignorent : le mod commun devient `batman_CoreAI` et porte le carnet entier (interface `CA_NPCProvider`), les échanges entre les deux mods passent par ses registres, trois mods de test séparés ; remplace D03 et D06 de la séparation du 2026-11-05 | [adr-coreai-separation.md](adr-coreai-separation.md), [E21](../../annexes/plans-termines/E21-separation-coreai.md) |
| 2026-10-14 | « Les tests font foi » : une tâche MP est `testé MP` quand la campagne automatique (serveur dédié + 2 clients) passe | [E01-moteur-tests-en-jeu.md](../../annexes/plans-termines/E01-moteur-tests-en-jeu.md) |

Les autres étapes portent aussi leurs décisions (réputation E04, missions E11, troc E13, combat LK06,
fortification LK14…) : les lire dans leur fichier.

## ADR

| ADR | Statut |
|---|---|
| [adr-bords-des-cases.md](adr-bords-des-cases.md) — bords des cases : un seul lecteur du jeu (`LivingKnox.Edges`), des règles pures (`LivingKnox.EdgeRules`) pour l'arrivée, le déblocage, les places d'arrêt et le couloir d'un détour (2026-11-16), plan [LK17](../../annexes/plans/LK17-chemin-vanilla.md) | Accepté |
| [adr-atelier-voix.md](adr-atelier-voix.md) — atelier des voix servi par le pont, relevé des lieux en jeu, aide de l'IA, export et import, note et appel écrits dans la fiche (2026-11-15), plan [E22](../../annexes/plans/E22-atelier-voix.md) | Accepté |
| [adr-coreai-separation.md](adr-coreai-separation.md) — Living Knox et RadioSurvivor séparés autour de `batman_CoreAI` : carnet commun, registres neutres, tests séparés (2026-11-15), plan [E21](../../annexes/plans-termines/E21-separation-coreai.md) | Accepté |
| [adr-personas-declaratives.md](adr-personas-declaratives.md) — voix radio déclarées en un seul fichier : missions (registre de types), récompenses aléatoires par catégorie, planques multiples au choix du joueur, troc par marchand, remises hors de vue (2026-11-14), plan [E20](../../annexes/plans-termines/E20-voix-declaratives.md) | Accepté |
| [adr-remise-en-ordre-solid.md](adr-remise-en-ordre-solid.md) — remise en ordre SOLID du moteur Living Knox après l'audit du 2026-11-13, par chantiers vérifiés, sans changement de comportement, plan [LK16](../../annexes/plans-termines/LK16-remise-en-ordre-solid.md) | Accepté (par défaut) |
| [adr-banc-mimetique.md](adr-banc-mimetique.md) — banc hors jeu mimétique : doublures contrôlées contre l'API du jeu, Lua vanilla réel, horloge et réseau fidèles, site réel rejoué (2026-11-13), plan [E19](../../annexes/plans/E19-banc-mimetique.md) | Accepté |
| [adr-registre-routines.md](adr-registre-routines.md) — registres des routines et des tâches du foyer de Living Knox, une par fichier ; potager du jardinier (2026-11-13), plan [LK15](../../annexes/plans-termines/LK15-registre-routines.md) | Accepté |
| [adr-separation-mods.md](adr-separation-mods.md) — trois mods dans un article : RadioSurvivor, Living Knox et un mod commun (2026-11-05), plan [E18](../../annexes/plans-termines/E18-separation-living-knox.md) | Accepté |
| [adr-b17-chat-proximite-pnj.md](adr-b17-chat-proximite-pnj.md) — dialogue avec les PNJ dans le chat de proximité (2026-10-02) | Historique : écrit pour les PNJ Bandits! du carnet 0.2 ; le principe (chat « dire » + raccourci Ctrl+G) a été conservé avec Living Knox |

Un nouvel ADR se nomme `adr-<sujet>.md` dans ce dossier et s'ajoute au tableau ; il cite son plan d'étape associé, qui porte le suivi des tâches (et réciproquement).
