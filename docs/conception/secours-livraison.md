# Secours : livraison sur place et approche (E12-T03)

Code : `media/lua/server/RadioSurvivor/RS_RescueVisit.lua` (lectures de cases et d'inventaires, séparées de
`RS_Rescue.lua` dont le choix du bâtiment ne doit rien lire ni charger) ; points d'appel ajoutés à `RS_Rescue.lua` :
`noteApproach`, `startForTeam(team, { site = ... })`. Banc : `tests/test_rescue_visit.py` ; suite en jeu :
`rs.rescue.visit`. Décisions acquises : celles d'E12 et d'E12-T02 ([secours.md](secours.md)).

## Choix pris pour E12-T03 (à confirmer)

1. **« Dépôt réel » = objet apporté de l'extérieur.** Un membre de l'équipe (`RS_Factions.idOf`) à moins de
   40 cases du bâtiment mais hors de son emprise voit les identifiants de ses vivres et soins (sacs compris, deux
   niveaux) retenus en mémoire par le serveur. Un membre dans l'emprise fait examiner par le serveur les conteneurs
   des meubles du bâtiment à 8 cases autour de lui, à son étage : un objet compte si son identifiant a été retenu
   (l'identifiant d'objet survit aux transferts MP) et s'il est utilisable tel quel. Le butin du bâtiment, jamais vu
   dans un inventaire dehors, ne compte jamais ; ni le sol, ni un véhicule, ni un conteneur hors de l'emprise.
   Option la plus simple qui exclut le butin sans relevé initial des conteneurs (remplis au chargement).
2. **Les survivants prennent l'objet** : retiré du meuble (`DoRemoveItem` + `sendRemoveItemFromContainer`), ce qui
   empêche de compter deux fois la même boîte.
3. **Valeurs** : 8 h de réserves par aliment (ni pourri, ni gelé, ni cru dangereux), 4 h par récipient d'eau propre
   non vide, 6 h par objet de soins (`DisplayCategory` `FirstAid` ou `Bandage`) ; plafond existant de 10 jours.
   Constantes de `RS_RescueVisit.HOURS`, sans option sandbox. Autres boissons (fluide autre que l'eau) exclues.
4. **Approche** : un membre à moins de 40 cases alors qu'aucun ne l'était au sondage précédent, au plus une fois par
   12 h de jeu et par secours (dernière approche sauvegardée dans le secours). Fumée verte de Signal Smoke (mod
   requis) de 30 minutes de jeu à 2 cases hors de l'emprise, du côté du membre le plus proche, et la voix l'annonce ;
   si la fumée est refusée (ou module cassé : erreur au journal) : la voix décrit ce qu'elle voit (côté où se tiennent les membres, un ou
   plusieurs, véhicule).
5. **Texte fixe traduit**, composé par l'autorité (`IGUI_RS_RescueSee*`, `IGUI_RS_RescueSmoke_<couleur>`,
   directions `IGUI_RS_Dir_*` des indices ; anglais intégré si les traductions sont illisibles) et diffusé sur la
   première fréquence servie de la voix du secours (`RS_RadioServer.air`), comme le texte fixe d'un appel spontané.
   Pas de demande au pont (le branchement du secours au pont reste hors périmètre) ; l'approche est gardée dans le
   secours (`approach`, `approaches`) pour le contexte futur de la voix.

## Limites

- Un membre qui apparaît déjà dans le bâtiment (connexion, téléportation) doit ressortir avec ses vivres pour qu'ils
  comptent ; la mémoire des objets apportés est perdue au redémarrage du serveur.
- Un objet ramassé dans le bâtiment, emporté dehors puis rapporté compte.
- Sans fréquence de voix (secours démarré sans `voice`), rien n'est diffusé ; la fumée est posée quand même.
- Contenu vu par le serveur en MP (transactions d'inventaire) non vérifié en jeu.
