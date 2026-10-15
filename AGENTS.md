# Architecture validée et règles du projet

Les règles de `../AGENTS.md` et de `CLAUDE.md` s’appliquent.

Architecture existante validée par la décision utilisateur LK00-T02 du 2026-10-03 (docs/plan/LK00-cadrage.md), fusion confirmée le 2026-10-08 : serveur autoritaire, adaptateurs d’exécution, fournisseur de PNJ.

- Domaine et décisions serveur : missions, récompenses, groupes et état privé ; seules ces fonctions décident des effets persistants.
- Adaptateurs moteur : inventaire, monde, XP et réseau ; exécutent uniquement les décisions validées par le serveur.
- RS_NPCProvider : interface entre carnet et moteur Living Knox ; pas de dépendance aux détails des corps dans le carnet.
- Client : présentation, gestes du propriétaire et demandes ; aucune autorité sur récompenses, stocks ou objectifs.
- Pont Python : validation du protocole et proposition du modèle dans les listes fermées ; jamais autorité sur objets, fréquences, coordonnées ou récompenses.
- Dépendances : présentation/pont → contrat → décisions serveur → adaptateurs moteur ; état secret dans RS_State uniquement. Aucun changement de pattern ni migration dans cette tâche.
