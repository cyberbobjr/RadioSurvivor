# Mission « nettoyer » (gabarit `clear`, E11-T04)

Brouillon du 2026-10-12. Code : `server/RadioSurvivor/RS_MissionClear.lua` ; fonctionnement détaillé :
[carnet-implementation-04221.md](carnet-implementation-04221.md), « Gabarit nettoyer ».

## Choix non tranchés par le plan (à confirmer)

Le plan dit seulement : « tuer N zombies autour d'un lieu ; décompte à `OnZombieDead` côté serveur avec attribution
établie en E04-T06 ; morts par le feu non comptées si non attribuées ». Les choix ci-dessous sont les plus simples et
les plus proches du vanilla ; ils restent à confirmer par l'utilisateur.

1. **Lieu tiré comme `scout`**, cercle de comptage **centré sur le bâtiment** (rayon 30 cases, plus grand pour un
   grand bâtiment : 5 cases de marge autour des coins). Contrairement à `scout` et `retrieve_id`, le cercle n'est pas
   décalé : c'est la zone où un zombie compte, le joueur doit la connaître exactement. Il est tracé sur la carte du
   participant dès l'acceptation (libellé « Zone à nettoyer (<demandeur>) ») et retiré à la fin.
2. **N d'après la densité des en-têtes de lot**, lue sans rien charger
   (`IsoMetaGrid:getChunkDataFromTile(x, y):getUnadjustedZombieIntensity()`, 0..255), moyenne des chunks dont le
   centre est dans le cercle, comme le jeu la traite : répartition uniforme (`Distribution` = 2) = 128, multipliée
   par `ZombieConfig.PopulationMultiplier` ; `Zombies` = 6 (aucun) ou multiplicateur 0 : pas d'offre.
   `densité = moyenne / 255 × multiplicateur` ; `N = 6 + 19 × min(1, densité / 0,5)`, arrondi, borné à **6..25** ;
   densité < 0,04 : pas d'offre (un lieu de campagne vide rendrait la mission impossible ; nouvel essai 1 min plus
   tard). Le nombre réel de zombies présents n'est pas lisible en Lua (population native) : N reste un ordre de
   grandeur, à ajuster en jeu (`RS_Config.Missions.clear` : `minKills`, `maxKills`, `fullDensity`, `minDensity`).
3. ~~**Réussite automatique au N-ième zombie compté**, sans compte rendu au demandeur~~. Remplacé le 2026-10-14 (décision de l'utilisateur, E11-T13) : l'objectif rempli met la mission « à rapporter » ; elle ne réussit que quand un participant le dit au PNJ demandeur (intention `report_done` du modèle revérifiée par le serveur, ou bouton « Rendre compte » près de lui) ; demandeur mort avant : `cancelled_dead`. Voir `docs/specifications-techniques/protocole-carnet-v2.md`, « Compte rendu au demandeur ». Le N-ième
   zombie compté arrête le décompte. Le lot commun se réclame ensuite près du demandeur (bouton « Réclamer », comme
   M01).
4. **Un zombie compte pour une seule mission** : la première mission ouverte (ordre des identifiants) dont le tueur
   est participant et dont le cercle contient le zombie à sa mort.
5. **Fiches de PNJ seulement.** Une voix radio n'a pas de corps près duquel réclamer le lot ; sa liste fermée
   (`RS_MissionVoice.TEMPLATES`, et celle du pont) reste `scout`.
6. **Règle d'attribution d'E04-T06 réécrite dans le gabarit** (même fenêtre de 5 s que
   `LivingKnox.Bodies.deathCause`), sans dépendre de Living Knox : le carnet doit fonctionner Living Knox désactivé.
   Dernier coup d'un joueur relevé à `OnHitZombie` (seulement tant qu'une mission `clear` est ouverte) ; à
   `OnZombieDead`, tueur = `getAttackedBy()` joueur (pas un animal) avec un coup relevé de lui depuis 5 s au plus, ou
   conducteur d'un véhicule à cet instant. Feu, Molotov, piège sans lanceur, chute, `Kill(nil)` : jamais comptés.
   Chaque brûlure remet l'attaquant à `nil` : un zombie qui meurt de ses brûlures ne compte pas, même frappé avant ;
   un zombie en feu achevé par un coup du participant compte.
7. **Jamais comptés** : corps d'un PNJ du fournisseur (`RS_NPCProvider.id`) ou étiqueté par Living Knox (ModData
   `lkNpcId`, toute génération), zombie déjà compté (ModData `RS_ClearCounted` : double `OnZombieDead` du feu,
   cadavre traîné puis lâché, ModData recopiées), zombie hors du cercle, tueur non participant ou sans fiche du
   carnet.

## Sources

- Java 42.21 : `IsoMetaChunk.java:66-136` (intensité brute, `Distribution`, option `Zombies`),
  `IsoMetaCell.java:95-103` (métachunk créé à la demande depuis l'en-tête de lot), `IsoMetaGrid.java:1183-1197`
  (`getChunkDataFromTile`), `ZombiePopulationManager.java:319` (`PopulationMultiplier` transmis à la population
  native), `SandboxOptions.java:67, 1961`.
- E04-T06 : `server/LivingKnox/LK_Bodies.lua` (« mort et tueur »), `docs/annexes/conception/corps-registre.md`.
- Base : `multiplayer.md` (« Qui a tué un zombie : connu du serveur à `OnZombieDead` », `OnZombieDead` sur chaque
  client), `quest-building-blocks.md` (piège du feu), `zombies-as-npc-bodies.md` (cadavre traîné, second
  `OnZombieDead`), `world-placement.md` (densité de zombies d'un point sans rien charger).
