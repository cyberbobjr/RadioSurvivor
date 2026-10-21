# Secours : issue « trop tard » (E12-T05, zombies : E12-T07)

Code : `media/lua/server/RadioSurvivor/RS_RescueLost.lua` (dernières pages, survivants en tenue, pose unique)
et `RS_Rescue.lua` (survivants et tenues décrites au départ : `Rescue.SURVIVORS`, `Rescue.OUTFITS`,
`Rescue.drawSurvivors`, `Rescue.looks`). Traductions `IGUI_RS_RescueLast_*` (EN, FR). Banc :
`tests/test_rescue_lost.py` ; suite en jeu : `rs.rescue.missed`. Décisions acquises : celles d'E12, d'E12-T02
([secours.md](secours.md)), d'E12-T04 ([secours-issue.md](secours-issue.md)) et d'E15-T03/T04
([dernieres-pages.md](dernieres-pages.md)) ; note de travail §05 (« Trop tard : cadavres ou zombies portant les
vêtements qu'ils avaient décrits (le jeu sait reconnaître une tenue), et leurs dernières pages »).

## Choix pris pour E12-T05 (à confirmer)

1. **Les survivants et leurs tenues sont tirés au départ du secours** (le plan ne disait pas d'où venait la
   description) : 2 ou 3 survivants, tenues distinctes d'une liste fermée de 10 tenues vanilla, le premier est le
   demandeur (la voix). Tirage reproductible par l'identifiant du secours et la clé du site ; gardé dans le secours
   (`rec.survivors = { { outfit, look, requester } }`), avec les phrases anglaises que la voix dira
   (`rec.looks` : « I am wearing a long white doctor's coat. », « One of the others is wearing hospital scrubs. »),
   sans chiffre, données du prompt comme les indices. Un secours commencé avant E12-T05 reçoit le même tirage à son
   issue.
2. **Liste fermée des tenues** : `Doctor`, `Nurse`, `HospitalPatient`, `Fireman`, `Police`, `Ranger`, `Chef`,
   `Fossoil`, `Sanitation`, `Ski`. Chacune existe pour les deux sexes dans `media/clothing/clothing.xml` 42.21
   (`PersistentOutfits.pickOutfit` rend 0 pour un sexe absent : cadavre sans tenue) ; ni `Bandit*` ni
   `Survivalist*` (remplacées selon le stade par `ZombiesStageDefinitions.getAdvancedOutfitName`). La description
   ne nomme qu'une pièce de probabilité 1 dans la tenue (blouse du médecin, tenue de bloc, chemise d'hôpital,
   pantalon de pompier, uniforme de police ou de garde forestier, pantalon de cuisinier, t-shirt Fossoil,
   combinaison bleue et rouge, pantalon de ski), donc toujours visible sur le cadavre ; le sexe reste au hasard du
   jeu et n'est pas décrit.
3. **Zombies, pas de cadavres** (E12-T07, décision de l'utilisateur du 2026-10-14, qui remplace le choix
   « cadavres » d'E12-T05) : un zombie par survivant dans la tenue décrite. Il est fait comme un **joueur réanimé**
   (base `zombies-as-npc-bodies.md`), en un seul appel Lua : `addZombiesInOutfit(x, y, z, 1, tenue, 50)`, marque
   `RS_RescueBody = "<secours>#<rang>"` en ModData, `DoZombieInventory()`, `case:createCorpse(zombie)`,
   `cadavre:reanimate()`. Raisons : un zombie ordinaire perdrait son inventaire (et le cahier) à la virtualisation
   (joueur éloigné) et à la mort (`DoZombieInventory` vide l'inventaire d'un zombie ordinaire) ; un joueur réanimé
   n'est jamais virtualisé, il est sauvegardé en entier avec son inventaire et ses ModData (`reanimated.bin`), son
   apparence part chez chaque client (descripteur partagé), et le zombie temporaire n'atteint jamais un client
   (chaîne dans le même appel). Il naît couché et se relève seul (1 à 3 s). Aucun cadavre n'est posé. Il erre et
   peut être tué loin du lieu : la scène ne le suit pas.
4. **Dernières pages** : un `Base.Notebook` vanilla écrit (`addPage`, mise en page de `RS_LastPages.layout`) puis
   verrouillé (`setLockedBy`, mêmes réglages qu'E15-T03), nommé « Dernières pages de <demandeur> », dans
   l'**inventaire** du zombie du demandeur (`getInventory():AddItem`, sur l'autorité, après la réanimation) : à sa
   mort, `DoZombieInventory` ne fait rien pour un joueur réanimé, le cadavre reprend l'inventaire et part chez les
   clients MP avec son contenu. Un objet seulement accroché serait perdu sur un serveur (base, « Contenu du cadavre
   d'un zombie »). Rien n'est envoyé tant que le zombie vit (aucune synchronisation d'inventaire d'un zombie). Sans
   zombie du demandeur : dans son cadavre marqué s'il a déjà été tué (reprise après un arrêt), sinon au sol de la
   première case. Texte fixe traduit (`IGUI_RS_RescueLast_*`), composé à l'issue dans la
   langue de l'autorité avec les seuls faits du secours : jours attendus (réserves consommées, bornées aux réserves
   reçues), nombre de survivants, une approche de l'équipe sans dépôt, un dépôt insuffisant, signature. Pas de
   demande au pont (comme la note d'E12-T04) : les survivants n'ont pas de relevé de vie.
5. **Option `RadioSurvivor.LastPages`** (E15-T04) coupée, à l'issue ou à la pose : zombies posés, aucun cahier.
6. **Pose** au chargement de la zone : quand la case du point du site est chargée et que le bâtiment a passé ses
   histoires vanilla (même règle que les caches), sur des cases libres distinctes du bâtiment autour du point (sans
   escalier ; cases réutilisées s'il en manque). Une seule fois, même après un redémarrage : `rec.lost.placing`
   sauvegardé avant toute création ; un secours repris avec `placing` sans `placed` adopte d'abord ce qui porte sa
   marque — zombies vivants de la liste des zombies (où qu'ils soient : ils marchent), cadavres marqués du site à
   cet étage (tués entre-temps) — avec le cahier, et ne crée que les survivants manquants. Après `placed`, plus rien
   n'est jamais posé.
7. **Relevé de vie** : `RS_LifeLog.rescue(cid, 'missed', demandeur)` pour chaque aidant lié au carnet (des aidants
   n'existent qu'après un dépôt), hors magasin de travail.
8. **Fichier** : nouveau `RS_RescueLost.lua` (la tâche citait `RS_Rescue.lua`), qui enveloppe `Rescue.sceneHook`
   pour l'issue `missed` et laisse l'issue `saved` à `RS_RescueScene` (dont le banc interdit toute lecture de case).

## Limites

- La description n'est pas encore dite par une voix : aucun secours n'est lancé par le pont ; `rec.looks` attend le
  branchement du prompt (reste d'E12, comme les indices).
- La voix des survivants morts n'est pas changée (état de la voix, silence) : hors périmètre.
- Les zombies des survivants restent dans le monde (joueurs réanimés, `reanimated.bin`) jusqu'à leur mort ; rien ne
  les retire. Un cadavre de zombie peut redevenir faux mort en pourrissant si `DisableFakeDead` = 2 (base) : le
  cahier reste dans son inventaire.
- Pas de remise debout immédiate (naissance couchée, relevé vanilla en 1 à 3 s).
- Sexe, coiffure et variante de la tenue au hasard du jeu ; un mod qui remplace une tenue vanilla change le cadavre.
- Cadavre (après la mort du zombie) soumis à `HoursForCorpseRemoval`.
- Un monde restauré à une sauvegarde plus ancienne que l'état privé peut perdre la scène (jamais la doubler).
- Pose, tenues et cahier vus par un client MP non vérifiés en jeu ; la suite `rs.rescue.missed` tue le zombie du
  demandeur sur l'autorité et lit son cadavre côté serveur seulement (vérification côté client : à ajouter aux
  contrôles des pairs de la campagne MP).
