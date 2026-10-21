# Journal des décisions

Les décisions de conception sont datées dans la section « Décisions » de chaque fichier d'étape du plan
([annexes/plans/](../../annexes/plans/README.md)) : c'est leur source unique. Cette page relève celles qui fixent
l'architecture et range les ADR rédigés à part.

## Décisions d'architecture

| Date | Décision | Source |
|---|---|---|
| 2026-10-03 | Moteur de PNJ propre (option C de l'analyse) : décisions sur le serveur, corps exécutés par le seul client propriétaire, gestes relayés | [LK00-cadrage.md](../../annexes/plans/LK00-cadrage.md), [ia-multijoueur.md](../ia-multijoueur.md) |
| 2026-10-03 | Écriture indépendante : aucun code de Bandits! ni de Project A-Life repris, traduit ou paraphrasé | [LK00-cadrage.md](../../annexes/plans/LK00-cadrage.md), [conception/README.md](../../annexes/conception/README.md) |
| 2026-10-03 | Groupes de 3 à 5, simulation abstraite hors de portée des joueurs, relève après 2 à 5 jours | [LK00-cadrage.md](../../annexes/plans/LK00-cadrage.md) |
| 2026-10-08 | Fusion de Living Knox dans `batman_RadioSurvivor` : un seul mod, un seul plan (préfixes `E` et `LK`) | [LK00-cadrage.md](../../annexes/plans/LK00-cadrage.md), [E17](../../annexes/plans/E17-fournisseur-pnj-living-knox.md) |
| 2026-10-08 | Carnet indépendant du moteur de PNJ par l'interface `RS_NPCProvider` ; adaptateur Bandits! retiré (`E17-T02`) | [E17-fournisseur-pnj-living-knox.md](../../annexes/plans/E17-fournisseur-pnj-living-knox.md) |
| 2026-10-09 | Corps des PNJ : base B « joueur réanimé » retenue au jalon 1, base A (zombie ordinaire) abandonnée | [LK02-jalon-corps-gestes.md](../../annexes/plans/LK02-jalon-corps-gestes.md) |
| 2026-10-09 | Six voix, fréquences tirées par partie et jamais envoyées aux clients, découvertes par des notes | [E05-voix-reseau-radio.md](../../annexes/plans/E05-voix-reseau-radio.md) |
| 2026-10-14 | « Les tests font foi » : une tâche MP est `testé MP` quand la campagne automatique (serveur dédié + 2 clients) passe | [E01-moteur-tests-en-jeu.md](../../annexes/plans/E01-moteur-tests-en-jeu.md) |

Les autres étapes portent aussi leurs décisions (réputation E04, missions E11, troc E13, combat LK06,
fortification LK14…) : les lire dans leur fichier.

## ADR

| ADR | Statut |
|---|---|
| [adr-b17-chat-proximite-pnj.md](adr-b17-chat-proximite-pnj.md) — dialogue avec les PNJ dans le chat de proximité (2026-10-02) | Historique : écrit pour les PNJ Bandits! du carnet 0.2 ; le principe (chat « dire » + raccourci Ctrl+G) a été conservé avec Living Knox |

Un nouvel ADR se nomme `adr-<sujet>.md` dans ce dossier et s'ajoute au tableau.
