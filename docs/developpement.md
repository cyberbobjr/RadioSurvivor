# RadioSurvivor — contraintes de développement

Contraintes propres à ce projet. Les règles communes à tous les mods de l'utilisateur (règle immuable du Workshop
Steam, méthode de diagnostic, Kahlua, multijoueur, traductions, base de connaissances du moteur, tests en jeu
automatisés) vivent dans le fichier d'instructions unique du dossier de développement parent, hors de ce dépôt.

## Périmètre du projet

Un projet, un article Workshop, **trois mods** sous `Contents/mods/` (décision :
[ADR de séparation](architecture/decisions/adr-separation-mods.md), plan
[`E18`](annexes/plans/E18-separation-living-knox.md)). Le dossier et l'`id=` sont identiques :

| Mod | Rôle | `require=` |
|---|---|---|
| `batman_RadioSurvivorCore` | mod commun : moteur et journal des missions, lien avec le pont Python LLM, identité des personnages, historique des échanges, réputation, outils, carnet (cadre et onglets Contacts, Missions, Réputation) | `batman_SignalSmoke` |
| `batman_RadioSurvivor` | radio, voix, onglet Radio du carnet, factions ; fiches de voix | Core, `batman_BeltRadio`, `batman_SignalSmoke` |
| `batman_LivingKnox` | moteur de PNJ : groupes, foyers, besoins, routines, parole de proximité ; `incompatible=` Bandits2, ProjectALifeNPCs | Core |

Montages valides : RadioSurvivor seul, Living Knox seul, ou les deux, toujours avec le Core. Chacun vit sans l'autre ;
le Core activé seul n'apporte rien de jouable. Le code commun n'existe qu'une fois, dans le Core. Aucun `require` ni
appel de Living Knox vers RadioSurvivor : les liens passent par le Core, l'API publique de Living Knox ou
`RS_NPCProvider`. Le pont est un seul programme, sans option selon le montage ; son dossier d'échange est
`Zomboid/Lua/batman_RadioSurvivorCore/`, les fiches de voix restent dans `Zomboid/Lua/batman_RadioSurvivor/personas`
(RadioSurvivor actif seulement). Le mod de tests `dev/batman_RadioSurvivorTests` n'est jamais publié.

Pas de reprise des anciennes sauvegardes : les mods ne sont pas publiés avec une sauvegarde à reprendre, et aucune
migration n'est écrite ni documentée.

Les observations des PNJ, leurs déclencheurs et l'option de fréquence des initiatives appartiennent à Living Knox
(`E18-T27`) : seul ou avec RadioSurvivor, un PNJ prend la parole de lui-même et deux PNJ se racontent ce qu'ils ont vu.

## Architecture validée — à préserver

Architecture validée par la décision utilisateur LK00-T02 du 2026-10-03
([`annexes/plans-termines/LK00-cadrage.md`](annexes/plans-termines/LK00-cadrage.md)), fusion confirmée le 2026-10-08 : serveur
autoritaire, adaptateurs d'exécution, fournisseur de PNJ. Vue détaillée :
[`architecture/README.md`](architecture/README.md). **Aucun changement de pattern ni migration** sans décision.

- Domaine et décisions serveur : missions, récompenses, groupes et état privé ; seules ces fonctions décident des
  effets persistants.
- Adaptateurs moteur : inventaire, monde, XP et réseau ; exécutent uniquement les décisions validées par le serveur.
- `RS_NPCProvider` : interface entre le carnet de RadioSurvivor et le moteur Living Knox ; pas de dépendance aux détails des corps dans le
  carnet. L'ancien adaptateur Bandits! (`RS_Bandits.lua`) a été retiré le 2026-10-08 (`E17-T02`).
- Client : présentation, gestes du propriétaire et demandes ; aucune autorité sur récompenses, stocks ou objectifs.
- Pont Python : validation du protocole et proposition du modèle dans les listes fermées ; jamais autorité sur objets,
  fréquences, coordonnées ou récompenses.
- Dépendances : présentation/pont → contrat → décisions serveur → adaptateurs moteur ; état secret dans `RS_State`
  uniquement.

## Méthode du plan

- Le développement suit le plan de [`annexes/plans/`](annexes/plans/) : méthode dans
  [`annexes/plans/README.md`](annexes/plans/README.md), état généré dans
  [`annexes/plans/SUIVI.md`](annexes/plans/SUIVI.md), prochaine tâche par `python tools/plan.py next`
  (skill `radiosurvivor-plan`). Préfixes : `E` (radio, carnet, missions) et `LK` (moteur de PNJ).
- **Une tâche à la fois.** Les décisions marquées `à décider` se posent à l'utilisateur avant tout code : une question
  à la fois, trois réponses fermées et une réponse libre.
- Avant de déclarer une tâche testée : `tests/test_protocol.py`, `tests/test_carnet.py`, luacheck (sans nouvel
  avertissement) et `python tools/plan.py check`. La suite complète est `python tests/run_all.py`.

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
