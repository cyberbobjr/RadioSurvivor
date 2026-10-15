# Secours : issue « à temps » (E12-T04)

Code : `media/lua/server/RadioSurvivor/RS_RescueScene.lua` (nouveau : scène, cache, note, nouvel endroit de la voix,
mémoire) ; points d'appel ajoutés à `RS_Rescue.lua` (`noteHelpers`, `helpedActive`, `isWorkStore`, `sceneHook`,
participants par défaut) et à `RS_RescueVisit.lua` (aidants, départ) ; note de cache générique dans `RS_Caches.lua`
(`makeNote`) ; fiche `personas/whitaker.txt` (règle du secours réussi). Banc : `tests/test_rescue_scene.py` ; suite
en jeu : `rs.rescue.saved`. Décisions acquises : celles d'E12, d'E12-T02 ([secours.md](secours.md)) et d'E12-T03
([secours-livraison.md](secours-livraison.md)) ; note de travail §05 (« À temps : les survivants laissent une cache
et une note, puis partent. Ils restent une voix du réseau, depuis un nouvel endroit, et se souviennent de qui les a
aidés »).

## Choix pris pour E12-T04 (à confirmer)

1. **Ce qui fait « à temps »** (le plan ne le disait pas) : un **dépôt réel** compté par E12-T03 pendant que le
   secours est actif, **puis** le départ de tous les membres de l'équipe (aucun membre vivant et connecté à moins de
   40 cases du bâtiment au sondage suivant). Les survivants, ravitaillés, partent après l'équipe. Une visite sans
   dépôt ne sauve personne ; un dépôt garde aussi son effet d'E12-T03 (réserves) tant que l'équipe reste sur place.
   Raisons : garder un sens au dépôt d'E12-T03 (une arrivée seule rendrait le dépôt inutile) et poser la scène hors
   de la vue des joueurs, « quand la zone se charge ».
2. **Aidants** : les membres près du bâtiment au moment du dépôt et à chaque sondage suivant tant qu'ils restent
   près (nom du personnage, clé d'appelant de la radio : compte sur un serveur, `solo` en solo, personnage du carnet
   s'il est lié), 8 au plus, gardés dans le secours (état privé). Ils sont les participants du fait du jour.
3. **Cache** : le sac marqué d'E11-T06 (`RS_Caches`, pose différée, une seule fois même après redémarrage), table
   tirée dans la liste fermée `RS_Config.Caches.order` par l'identifiant du secours, posée au point du site dès que
   sa case est chargée et que le bâtiment a passé ses histoires vanilla. Aucun choix de contenu propre au secours.
4. **Note** : une feuille de papier vanilla (`Base.SheetPaper2`) écrite (`addPage`) et verrouillée (`setLockedBy`),
   rangée dans le sac : remerciements aux aidants par leur nom, départ vers un lieu plus sûr, écoute radio maintenue,
   signature du demandeur. Texte composé à l'issue dans la langue de l'autorité (`IGUI_RS_RescueNote_*`, anglais
   intégré si les traductions sont illisibles), sans chiffre, lieu ni fréquence ; texte fixe, pas de demande au pont.
5. **Nouvel endroit de la voix** : un vrai bâtiment habitable tiré par `RS_Rescue.pick` (métagrille seule, à
   600 cases au moins des bases connues, ni l'ancien site ni un site de secours en cours), gardé dans le secours
   (`moved` : clé, type) ; ses mots (« a farmhouse outside Rosewood », niveau ville, 40 caractères au plus, anglais)
   deviennent le **lieu dit** de l'état de la voix (`RS_PersonaState`, `place`) que le pont met déjà dans le prompt ;
   moral +2. La fiche, éditée par l'admin, n'est pas réécrite : `location=rescue` reste, l'état dynamique porte le
   lieu. Sans bâtiment trouvé : « somewhere safer, far from the old place ».
6. **Mémoire de l'équipe** : deux souvenirs au plus par aidant (`RS_Memory`, voix + appelant + personnage) :
   « Came in time with supplies; we got out thanks to them » et « Came with <autres aidants> ». La voix les reçoit
   aux appels suivants de cet appelant (champ `memory=` existant). Aucun changement du pont ni du protocole.
7. **Relevé de vie** : `RS_LifeLog.rescue(cid, 'saved', demandeur)` pour chaque aidant lié au carnet (pour ses
   dernières pages), sauf dans le magasin de travail des suites.

## Limites

- Les membres de l'équipe qui ne sont pas venus ne sont pas mémorisés (identité de carnet inconnue hors ligne).
- Un membre qui s'éloigne à plus de 40 cases juste après le dépôt (même un instant) déclenche le départ.
- Aucun secours n'est encore lancé par le pont ni rattaché à une voix active : la voix `whitaker` reste
  `state=silent` ; le lieu et les souvenirs sont rangés, et ne s'entendent qu'une fois la voix active.
- Issue « trop tard » (scène de cadavres) : E12-T05 ; un secours `missed` garde sa scène en attente sans cache.
- Pose et contenu vus par un client MP non vérifiés en jeu (sac envoyé complet par `AddWorldInventoryItem(…, true)`).
