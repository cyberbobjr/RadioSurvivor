# Initiatives de parole des PNJ

- Tâche : E08-T03 (création) ; servira E08-T04 (conversations entre PNJ) et E08-T06 (radio des groupes équipés, même file et mêmes quotas)
- Build : 42.21.0 — Date : 2026-10-13 — Statut : brouillon (banc hors jeu seulement)

Code : `media/lua/server/RadioSurvivor/RS_Initiatives.lua` (autorité), branché dans `RS_Carnet_Server.lua` (passage `tick`, réponse `reply`, délai `poll`) ; opérations du fournisseur `Provider.engaged`, `Provider.say`, `Provider.bark` (`RS_NPCProvider.lua`, implémentées par `RS_LivingKnox.lua` sur `LivingKnox.API.engaged` et `LivingKnox.Speech`) ; heure de rangement `hour` des observations (`RS_Observations.lua`) ; contrat `npc_initiative` (`bridge/npc_protocol.py`, [protocole](../protocole-carnet-v2.md) « Initiative d'un PNJ ») ; option sandbox `RadioSurvivor.InitiativeFrequency`. Tests : `tests/test_initiatives.py` ; suite en jeu `rs.initiatives` (`dev/.../shared/RST/suites/RS_Initiatives.lua`).

## Problème

Un PNJ du carnet doit pouvoir parler de lui-même d'un événement récent qu'il a remarqué (ADR B04 « Initiative acceptée ») : une seule fois par événement, seulement si quelqu'un l'entend, jamais en plein combat, dans la même file que les sollicitations des joueurs, avec un coût LLM borné et réglable (E08-T01 (2)).

## Règle

1. **Déclencheur** : une observation de `RS_Observations` (faits fermés d'E08-T01, enregistrés par E08-T07 et E08-T08) rangée chez la fiche depuis moins d'**une heure de jeu** (champ `hour` posé au rangement, ou quand un ouï-dire devient une observation directe). Les entrées d'avant E08-T03 n'ont pas d'heure : elles n'ouvrent rien.
2. **Événement** = fiche + clé d'observation (`fait|sujet|jour|lieu`) ; gardé dans l'état privé (`data.initiatives.done`), donc **une seule initiative par événement** même après une sortie puis un retour dans la portée, une reconnexion ou un redémarrage. Il est consommé dès l'ouverture, même si la réplique échoue ensuite (caduque, pont muet).
3. **Conditions au passage** (toutes les 5 s réelles, une initiative au plus par passage) : fiche vivante, corps chargé (`Server.objects`), aucune demande de ce PNJ dans la file, pas de conversation en cours avec un autre PNJ (E08-T04, [conversations.md](conversations.md)), délai par PNJ écoulé, PNJ non occupé, au moins un joueur lié au carnet qui l'entend (`Provider.hears`, portée `HEARING_RANGE`).
4. **Occupé** (`LivingKnox.API.engaged`, provisoire jusqu'à LK05-T08 et LK06-T01) : coup d'un joueur reçu depuis moins de 30 s (`Bodies.lastHits`), ordre de combat en cours (`LK_Combat.orders`), sommation en cours menée par ce PNJ (`LK_Encounters`, étape ≥ 1), alerte active de son groupe (`LK_Alert.isActive`).
5. **Demande** `npc_initiative` dans la même file ordonnée par PNJ (`Server.pending`, `npc.order`) : `character = system`, aucun texte, aucune offre, `event` = carte de l'observation, `observations` = son journal, contexte réduit (nom, biographie, nombre d'auditeurs, membre et rôle seulement : règle de l'inconnu d'E17-T08 pour tous, plusieurs auditeurs pouvant être inconnus).
6. **Réponse** : intention `none`, 200 octets au plus (limite de `LivingKnox.Speech`). **Caduque** si, à l'arrivée, le corps n'est plus chargé, le PNJ est occupé, l'observation a quitté son journal ou plus personne ne l'entend. Sinon dite par `Provider.say` (bulle et ligne de chat de LK11-T04 chez les auditeurs de cet instant) et ajoutée à l'historique des contacts **existants** de ces auditeurs (aucun contact ni fiche créé par une initiative). Le pont garde dans la mémoire du PNJ un tour utilisateur fixe `(nobody spoke to you; you spoke up on your own)`, jamais un texte de joueur.
7. **Sans pont** : pont réputé arrêté quand une demande `npc_talk` ou `npc_initiative` reste sans réponse 90 s ; réputé revenu à la première réponse reçue. Pendant l'arrêt : aucune demande, sauf un essai toutes les 10 min ; l'initiative reste **silencieuse** (E08-T09, décision de l'utilisateur du 2026-10-14 : sans l'IA, le PNJ ne dit rien de lui-même) : aucune réplique de gabarit, aucun appel de `Provider.bark` ; l'événement est consommé comme une initiative ouverte (compteur `silent`). Même silence quand le plafond du niveau, le plafond serveur ou le plafond commun est atteint ; option « Désactivées » : aucune initiative.

## Quotas (option enum `RadioSurvivor.InitiativeFrequency`)

| Niveau (index) | Par PNJ (heures de jeu) | Demandes LLM d'initiative par heure réelle (serveur) |
|---|---|---|
| Désactivées (1) | — | 0 |
| Rares (2) | 1 par jour (24 h) | 2 |
| Normales (3, défaut) | 1 par heure | 6 |
| Fréquentes (4) | 1 par demi-heure | 12 |

Le délai par PNJ est gardé dans l'état privé (`data.initiatives.last`, en heures de jeu) ; le plafond par heure réelle est en mémoire, remis à zéro au redémarrage comme les autres budgets du carnet. Chaque demande compte aussi dans le plafond commun `MAX_PER_HOUR` (60) des demandes PNJ (`Server.times`, partagé avec `talk` et l'enrichissement), avec `MAX_PENDING` et les 16 acquittements non soldés. Le libellé de chaque niveau affiche son plafond d'appels par heure réelle. Option relue à chaque passage : un changement en cours de partie est pris aussitôt.

## Décisions prises sans l'utilisateur (à confirmer)

- Valeurs des quotas : celles proposées par le plan (Rares 1/jour et 2/h, Normales 1/h et 6/h, Fréquentes 1/30 min et 12/h), défaut **Normales** (option recommandée d'E08-T01 (2)).
- Pont arrêté détecté par une demande restée sans réponse 90 s (aucun signal de vie du pont n'existe), essai toutes les 10 min.
- ~~Repli sans pont : `greet` pour `player_return`~~ : remplacé par le silence (E08-T09, décision de l'utilisateur du 2026-10-14, précisée le 2026-10-15 : sans pont, hors budget et option « Désactivées »).
- Langue de l'initiative : celle des appels spontanés (option `CallLanguage`, sinon langue de l'autorité), aucun joueur ne parlant.
- « Occupé » inclut un ordre de combat en cours et l'alerte du groupe (LK05-T08 existe déjà) ; un coup porté n'est vu que pendant l'ordre de combat (aucune mémoire après sa fin).
- Le LLM parle toujours une fois l'initiative ouverte (pas d'intention « se taire ») ; la décision de parler reste au serveur.

## Limites

- Hors jeu seulement (banc lupa, doublures du Java) ; pas exécuté dans la VM Kahlua ni en jeu.
- Une observation rangée quand aucun joueur n'écoute n'ouvre une initiative que si un joueur arrive dans l'heure de jeu qui suit.
- Plusieurs membres d'un même groupe peuvent parler du même orage l'un après l'autre (une initiative par fiche) ; la coordination d'une bande reste à définir (ADR B04).
