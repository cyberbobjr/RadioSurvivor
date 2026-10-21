# Mission « signaler » (gabarit `signal`, E11-T07)

Brouillon du 2026-10-13. Code : `server/RadioSurvivor/RS_MissionSignal.lua` ; catalogue `RS_Config.Missions.signal`
(offre `signal_v1`) ; carnet `client/RadioSurvivor/RS_Notebook.lua` ; carte `client/RadioSurvivor/RS_MapActions.lua` ;
banc `tests/test_mission_signal.py` ; suite en jeu `rs.mission.signal`.

Le plan dit : « lancer la couleur demandée à un lieu et une heure ; RadioSurvivor écoute l'événement si Signal Smoke
est actif ; sans le mod, le gabarit n'est pas proposé ». Décision acquise d'E11 : Signal Smoke facultatif (détection du
mod actif puis `require` protégé, sans dépendance dans `mod.info`). **Remplacée le 2026-10-15 : Signal Smoke est un
mod requis** (`require=\batman_SignalSmoke`, objet requis sur Steam) ; le point 2 ci-dessous est mis à jour.

## Choix non tranchés par le plan (à confirmer)

1. **API d'événements existante de Signal Smoke, aucun ajout dans son dépôt.** Le plan prévoyait un événement
   `batman_OnSignalLit(joueur, x, y, z, couleur, type)` à ajouter dans le dépôt de Signal Smoke. Signal Smoke 0.2.3
   publie déjà un abonnement serveur équivalent : `SignalSmoke.onSignal(fn)`, événement `started` avec l'entrée du
   registre (position, couleur `{ r, g, b }`, `kind`, `source`) et `player` (IsoPlayer à l'origine) ou `username`.
   RadioSurvivor s'y abonne ; Signal Smoke n'est pas modifié (et ne pouvait pas l'être cette nuit : dépôt hors du
   projet). La couleur nommée est retrouvée en comparant l'entrée à `SignalSmoke.COLORS`.
2. **Module** (2026-10-15 : mod requis) : `require 'SignalSmoke/SignalSmoke'` doit rendre une table avec `onSignal`
   et `COLORS`. Le module est dans `shared` de Signal Smoke : exécuté au démarrage, avant tout fichier `server`, donc
   résolu quel que soit l'ordre des mods (base `mod-loading.md`). Module inutilisable (installation cassée) : une
   ligne `ERROR` au journal, aucune offre, aucun abonné.
3. **Lieu tiré comme `scout`** (bâtiment habitable à 60–250 cases du demandeur, loin des bases), **cercle centré sur
   le bâtiment** de 20 cases (plus grand pour un grand bâtiment), comme `clear` : c'est la zone où le signal compte,
   le joueur doit la connaître exactement. Tracé sur la carte du participant dès l'acceptation (« Zone du signal
   (<demandeur>) »), retiré à la fin.
4. **Couleur** tirée parmi vert, rouge, jaune et violet (couleurs des fumigènes de Signal Smoke) que le module connaît.
   **Tout signal de la couleur compte** : fumigène lancé, fusée de détresse (toujours rouge), bâton lumineux posé.
5. **Heure** : début d'une fenêtre de 2 heures de jeu, tiré 2 à 4 heures de jeu après l'heure du tirage, **valable
   n'importe quel jour** tant que la mission est active (le délai reste la règle M01 en temps réel, 2 h). Heure lue
   par `GameTime:getHour()` au moment de l'événement.
6. ~~**Réussite automatique**~~ : le premier signal valable (participant, couleur, cercle, fenêtre) remplit
   l'objectif ; les suivants ne sont plus jugés. Remplacé le 2026-10-14 (décision de l'utilisateur, E11-T13) : l'objectif rempli met la mission « à rapporter » ; elle ne réussit que quand un participant le dit au PNJ demandeur (intention `report_done` du modèle revérifiée par le serveur, ou bouton « Rendre compte » près de lui) ; demandeur mort avant : `cancelled_dead`. Voir `docs/specifications-techniques/protocole-carnet-v2.md`, « Compte rendu au demandeur ». Le lot commun se réclame près du demandeur (comme
   `clear`).
7. **Attribution** : `event.player` (IsoPlayer), sinon `event.username` parmi les joueurs liés à une fiche du carnet
   sur le serveur ; le joueur doit être participant de la mission. Un signal posé par un script sans joueur ne compte
   jamais.
8. **Fiches de PNJ seulement.** Une voix radio n'a pas de corps près duquel réclamer le lot ; sa liste fermée
   (`RS_MissionVoice.TEMPLATES`) reste `scout`.

## Limites

- Signal Smoke 0.2.3 : fusées des joueurs toujours rouges ; un bâton lumineux est attribué au joueur près duquel il
  est trouvé posé (balayage serveur), pas forcément à celui qui l'a lâché ; une grenade est attribuée par
  `IsoTrap:getAttacker()` (inconnu dans certains cas : le signal ne compte pas).
- Journée très longue (réglage du sandbox) : la fenêtre horaire peut ne pas revenir avant l'échéance réelle de 2 h.
- Plafond de 6 offres du pont : `signal_v1` est le sixième gabarit enregistré, toujours envoyé quand il est offert.

## Sources

- Signal Smoke (`Workshop\SignalSmoke`, `shared/SignalSmoke/SignalSmoke.lua` : en-tête « Événements »,
  `onSignal`, `notify`, `start` ; `server/SignalSmoke/SignalSmoke_Server.lua` : grenade et bâton lumineux ;
  `TimedActions/SignalSmoke_LightFlareAction.lua` : fusée rouge).
- Base : `mod-loading.md` (« Savoir en Lua si un autre mod est actif », `require` et ordre de chargement),
  `kahlua-lua.md` (`%` tronqué vers zéro).
- Gabarits voisins : `mission-nettoyer.md` (cercle centré, compte rendu au demandeur depuis E11-T13, PNJ seulement).
