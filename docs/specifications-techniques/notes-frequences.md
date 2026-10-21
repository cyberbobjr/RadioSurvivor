# Notes de fréquences (E05-T09)

Les fréquences des voix sont tirées au hasard à chaque partie (E05-T07) et ne sont jamais envoyées aux clients
(E05-T08). Les joueurs les découvrent par des **notes** : des documents lisibles trouvés dans le butin, qui portent la
fréquence de la partie en cours. Build 42.21 ; décision de l'utilisateur du 2026-10-09
(`docs/annexes/plans/E05-voix-reseau-radio.md`, Décisions).

## Les cinq notes

Une note par voix qui parle. **Pas de note pour Whitaker** : la voix est livrée silencieuse (`state=silent`) jusqu'aux
secours (E12) ; sa note sera à créer avec E12.

| Voix | Objet (`RadioSurvivor.`) | Aspect (icône et modèle vanilla) | Texte (résumé) | Horaires cités |
|---|---|---|---|---|
| Walt | `NoteWalt` « Page de journal radio » | page de journal de station radioamateur : papier réglé, en-tête imprimé, écriture manuscrite bleue (`Paperwork1`) | une voix de l'autre côté du fleuve, Walt, dit être sorti ; répond à toute heure ; talkie ou poste amateur ; « il ne peut venir chercher personne, mais il parle » | à toute heure |
| Darlene | `NoteDarlene` « Fiche de consignes au patient » | fiche cartonnée imprimée « Consignes au patient », annotée à la main (`IndexCard`) | infirmière à la radio, Darlene ; plaies, fièvre, médicaments ; « elle ne dit pas où elle est » | 7 h-10 h et 16 h-19 h |
| Cody | `NoteCody` « Avis de recherche de la Garde nationale » | avis dactylographié de la Garde nationale du Kentucky, note manuscrite dans la marge (`PaperReport1`, modèle `SheetOfPaper`) | Spc. Haskins absent sans permission du barrage du pont Esther Kinsella, armé, radio de campagne ; émettrait en ondes courtes ; « écouter et signaler, ne pas répondre » ; en marge : « Il dit des choses sensées. Écoute la nuit. » | 22 h-3 h |
| Gus | `NoteGus` « Note griffonnée » | bout de papier au crayon (`Note2`) | quelque chose à vendre ? demander Gus sur la bande marine ; argent, bijoux, papiers ; « parle franc, pas de suppliques » | 3 h-6 h |
| Night Owl | `NoteNightOwl` « Prospectus du Night Owl » | prospectus photocopié : bandeau sombre, gros titre, fréquence en rouge (`Flier`, modèle `Flier1`) | « Le comté de Knox est toujours à l'antenne » ; nouvelles confirmées, noms qui nous parviennent, un peu de musique ; toute radio peut écouter, appeler avec un talkie | 19 h-22 h |

- Textes FR et EN, ton de chaque voix, 1993, comté de Knox. Aucun secret de fiche (`secret=`), aucune invitation de
  Darlene à la clinique (ni la clinique ni West Point ne sont nommées). Vérifié par `tests/test_notes.py`.
- Fichiers : script `media/scripts/RadioSurvivor_notes.txt` ; traductions `Translate/{EN,FR}/ItemName.json`,
  `Print_Media.json` (titre et mise en page, `%1` = fréquence), `Print_Text.json` (transcription, bouton du bas).
- Lecture : clic droit → **« Inspecter »** (libellé vanilla des documents `printMedia`, comme les prospectus ; grisé
  dans le noir ou endormi), fenêtre vanilla des documents. Tags `base:fastread` (lecture en une seconde) et
  `base:picture` (⚠ lisible aussi par un personnage Illettré : choix d'accessibilité, comme Opération Artemis).
- Mise en page : rectangles de couleur et polices SDF vanilla (`SdfOldBold`, `SdfOldRegular`, `SdfCaveat` pour
  l'écriture manuscrite), aucune texture du mod. Largeurs mesurées hors jeu avec les fichiers `.fnt` (aucune ligne ne
  dépasse la page) ; rendu réel à vérifier en jeu.
- Le titre (« lu ») diffère par voix : la marque « lu » de l'inventaire (`isPrintMediaRead(title)`) les distingue.

## Transport de la fréquence (autorité, puis objet)

Choix : **écrite par l'autorité dans la ModData de l'objet à sa création** (option « à défaut » d'une commande serveur
à la première lecture écartée : un aller-retour réseau, une fenêtre de lecture asynchrone, un contrôle de possession à
écrire, et rien de plus à protéger, voir ci-dessous).

1. **Création** (`RS_Notes.onCreate`, `OnCreate = RadioSurvivorNotes.onCreate`) : `Item.InstanceItem` appelle `OnCreate`
   quand le butin remplit un conteneur, sur l'autorité (solo, ou serveur MP : `RequestItemsForContainerPacket`). La
   note reçoit :
   - `modData.printMedia = { id, title, info, text }` : **des clés** de traduction, jamais un texte composé (un
     serveur MP ne connaît pas les traductions des mods ; un texte composé serait figé dans sa langue) ;
   - `modData.RadioSurvivorNote = { voice = "<id>", khz = <kHz> }` : la voix et la **première fréquence servie** de la
     voix (`RS_Personas.served(id)[1]`, ordre des plages de la fiche : le Night Owl cite sa fréquence FM), fournie par
     `server/RadioSurvivor/RS_NotesServer.lua` (`NotesServer.frequencyOf`). Les fiches et le tirage sont prêts avant
     le premier conteneur : `OnLoadRadioScripts` (`IsoWorld.java:1905`) précède le chargement du monde
     (`WorldStreamer`, l. 2067) ; vu au journal du serveur dédié de test (tirages, puis `notes: 20 loot entries
     added`).
2. **Arrivée chez un client** : la ModData d'un objet n'est envoyée qu'avec l'objet lui-même (contenu d'un conteneur
   que le joueur ouvre, objet au sol près de lui, son inventaire). Sur le client, `OnCreate` est rejoué à la réception
   **sans fournisseur** (les fichiers `server` rendent tout de suite sur un client) : il ne pose que les clés et une
   note sans fréquence, puis la ModData du serveur remplace la sienne (`InventoryItem.load`, base
   `loot-distributions.md`). Aucune commande réseau ne porte de fréquence (`tests/test_notes.py` vérifie qu'aucun
   module des notes n'appelle `sendServerCommand`, `sendClientCommand` ou une ModData globale ; seule exception,
   E06-T07 : à l'ouverture d'une note lisible, le lecteur envoie `note_read { itemId }`, sans fréquence ; le serveur
   vérifie l'objet dans l'inventaire et sa ModData, puis inscrit la voix et ses heures dans le carnet).
3. **Lecture** (`client/RadioSurvivor/RS_NotesReader.lua`) : l'enveloppe de `ISReadABook:displayPrintMedia` place, le
   temps de l'appel, le texte composé par `getText(clé, fréquence)` dans la **langue du lecteur**, puis remet les
   clés ; celle de `startLoadingPrintMediaTextures` évite l'avertissement « Missing arguments » (aucune image à
   précharger). Mécanisme de la base `api-42-21.md` (« un serveur MP ne connaît pas celles des mods », cas `printMedia`).

Conséquence MP : seul un client qui a reçu la note (il a ouvert le conteneur, la voit au sol ou la porte) connaît la
fréquence ; le joueur qui ouvre le conteneur peut la prendre. Les autres limites de E05-T08 restent (paquet
`WaveSignal` vanilla, `docs/specifications-techniques/persona-format.md`, « Ce qui pourrait révéler une fréquence »).

### Cas particuliers

- **Voix sans fréquence à la création** (fiche absente, état `silent`, `gone` ou `dead`, aucune fréquence servie à
  cause d'un conflit) : note sans fréquence ; le texte affiche `???.?` (encre délavée). Choix le plus simple :
  l'objet reste dans le butin, sa table ne dépend pas de l'état des voix.
- ⚠ **Fréquence changée après la création** (fiche modifiée par l'admin, plage changée) : une note déjà créée garde
  l'ancienne fréquence (la plus simple ; aucun suivi). Un nouveau tirage n'a lieu qu'avec un **monde neuf**, où aucune
  ancienne note n'existe.
- ⚠ **Horaires** : écrits dans les traductions (valeurs livrées des fiches), pas lus dans `listen=` : si l'admin
  change les heures d'écoute, les notes citent encore les anciennes.
- Mod désactivé (`Enabled`) au chargement du monde : aucune note dans le butin ; une note déjà créée reste lisible.

## Butin

Ajout à `OnInitGlobalModData` (options sandbox de la partie connues, y compris en solo, base `loot-distributions.md`),
sans doublon, puis `ItemPickerJava.Parse()`. Serveur MP ou solo (`server/RadioSurvivor/RS_NotesServer.lua`). Un
changement de l'option en cours de partie n'est repris qu'au prochain chargement du monde ; un conteneur déjà rempli ne
change pas.

Listes vanilla 42.21 retenues, **citées par des salles** (relevé `.claude/tools/distmatrix.py`, `salle.conteneur
(weightChance de la liste / somme du conteneur)`) ou par des véhicules. Poids de base ≈ chance en % par tirage, avant
le facteur de rareté, les réglages de butin du sandbox (catégorie littérature) et la densité de zombies.

| Voix | Liste (tirages) | Poids | Salles qui la tirent (distmatrix) |
|---|---|---|---|
| Walt | `OfficeDeskHome` (4) | 4 | `bedroom.desk` (100/101) |
| Walt | `GarageTools` (4) | 4 | `garagestorage.locker` (100/121), `.counter` (20/320), `.metal_shelves` (20/325), `shed.metal_shelves` et `shed.shelves` (100/400) |
| Walt | `CrateElectronics` (4) | 4 | 18 conteneurs : `closet.crate` (100/800), `closet.other` (100/2665), `garagestorage.crate` (80/1475), `shed.other` (100/1060), greniers, chambres, `pawnshop`… |
| Walt | `ElectronicStoreHAMRadio` (1) | 15 | `electronicstore.shelves` (10/341) |
| Walt | `OfficeDeskHomeClassy` (4) | 4 | bureaux de chambre en zone riche |
| Walt | `OfficeDesk`, `OfficeDeskSecretary`, `OfficeDeskStressed` (4 chacun) | 4 | bureaux généraux et variantes de secrétariat |
| Darlene | `MedicalClinicDrugs` (4) | 3 | `medical.counter` (100/220), `pharmacy.counter` (100/111), `pharmacystorage.other` (100/140), `medicalstorage`, `dentist.counter`, `kennels` |
| Darlene | `MedicalOfficeDesk` (4) | 4 | `medicaloffice.desk`, `medical.desk`, `hospitalroom.desk`, `hospitalhallway.desk`, `pharmacystorage.desk`, `morgue.desk`… (1/1) |
| Darlene | `HospitalRoomCounter` (4) | 2 | `hospitalroom.counter` (100/101) |
| Darlene | `StoreShelfMedical` (4) | 1 | `pharmacy.shelves` (100/381), supérettes et stations-service `.shelves` (20/224 à 20/344), `generalstore.shelves` (20/1003) |
| Cody | `PoliceDesk` (2) | 5 | `policeoffice.desk`, `detectiveoffice.desk` (1/1), `office.desk` (1/133) |
| Cody | `PoliceFilingCabinet` (4) | 3 | `filingcabinet` de 10 salles de police et `security` (1/1) |
| Cody | `SecurityDesk` (2) | 3 | `security.desk`, `security.counter` (100/100) |
| Cody | `ArmyStorageElectronics` (4) | 3 | `armystorage` (100/215 à 100/250), `pawnshopoffice` (100/600, 100/1000), `pawnshop` (20/…) |
| Cody | `ArmySurplusMisc` (4) | 2 | `armysurplus.metal_shelves` (100/800), `.shelves` (100/901), `.other` (100/280), `.counter` (20/121) |
| Gus | `FishingStoreGear` (4) | 4 | `fishingstorage` (100/140 à 100/401), `hunting` (20/…), `camping` (5/…), `outdoorsupply`, `toolstore.shelves` (10/452) |
| Gus | `CrateFishing` (4) | 1,5 | `closet.crate` (100/800), `closet.other` (100/2665), `garagestorage.crate` (80/1475), `shed.other` (100/1060), `storageunit.other` (10/515) |
| Gus | `VehicleDistributions.FishermanGloveBox` (1) | 10 | boîte à gants des pick-up de pêcheur (variante `Fisherman`) |
| Night Owl | `LivingRoomSideTable` (4) | 1 | `livingroom.sidetable` et `.dresser` (100/103) |
| Night Owl | `MagazineRackMixed` (4) | 2 | présentoirs `shelvesmag` des supérettes, stations-service, épiceries (100/180, 100/220), pharmacie (40/220) |
| Night Owl | `ElectronicStoreMusic` (4) | 4 | `electronicstore.shelves` (20/341), `.counter` (10/321), `pawnshop.counter` (40/311) |
| Night Owl | `VehicleDistributions.GloveBox` (1) | 1,5 | boîte à gants des voitures ordinaires (liste vide en vanilla : seule la note y est tirée) |

Écartées : `DoctorTools`, `FishermanTools` (citées par aucune salle), `ArmyHangar*` (base `loot-distributions.md`).
Contrôle automatique : `tests/test_notes.py` vérifie que chaque liste existe et qu'elle est citée par
`Distributions.lua` (ou par un véhicule pour une boîte à gants).

### Option sandbox `RadioSurvivor.NoteRarity`

| Valeur | Facteur des poids |
|---|---|
| Aucune | 0 (aucune note ajoutée) |
| Rares | 0,4 |
| **Normales** (défaut) | 1 |
| Fréquentes | 2,5 |

Ordre de grandeur en **Normales** (sans les réglages de butin du sandbox) : environ 15 % par bureau de chambre ou bureau général (variantes comprises), casier
de garage ou caisse utilisant `CrateElectronics`, et 15 % sur la liste radioamateur pour Walt, 12 à 16 % par comptoir ou bureau médical pour Darlene, 10 à 12 % par bureau ou classeur de police
pour Cody, 16 % par meuble de magasin de pêche pour Gus, 4 % par table de salon et 8 % par présentoir de magazines pour
le Night Owl. Une fouille de quelques heures dans une ville (maisons, commissariat, pharmacie, supérette) devrait donner
plusieurs notes ; le magasin de pêche (Gus) est plus rare : ⚠ à régler en jeu.

## Tests

- `tests/test_notes.py` (banc lupa, dans `tests/run_all.py`) : fréquence écrite égale au tirage de la partie pour les
  cinq voix, deux mondes neufs, Whitaker sans note, voix `silent`/`gone` (note sans fréquence), OnCreate rejoué sur un
  client MP (aucune fréquence, aucun fournisseur), aucune commande réseau, texte FR/EN composé avec les vraies
  traductions, ouverture du document (clés remises, autres documents intacts, pas d'enveloppe empilée), butin selon
  `NoteRarity` (facteurs, idempotence, mod désactivé, liste absente journalisée), scripts, icônes et modèles vanilla,
  traductions complètes, mise en page lisible par le parseur vanilla, listes citées.
- Suite en jeu `rs.notes` (tags `world`, `server` : `RST.run({ suite = "rs.notes", tags = { "world", "server" } })` en solo sur une partie
  `rstest*`, `RST.server({ suite = "rs.notes", tags = { "world", "server" } })` sur un serveur dédié ; un filtre
  chaîne seul lance 0 test, exclusions par défaut) : scripts chargés, fréquence écrite par l'autorité, entrées de butin
  selon l'option, texte composé (solo).
- Protocole solo : `docs/annexes/tests/tests-en-jeu.md` § 13, « Notes de fréquences (E05-T09) ».

## Notes sur les cadavres équipés d’un talkie-walkie

Sur l’autorité, `OnFillContainer` examine le butin déjà généré : si un objet `Radio`
possède un appareil émetteur (`getIsTwoWay`), une note supplémentaire a 35 % de
chance d’apparaître (14 % en rare, 87,5 % en fréquent, aucune si désactivé).
Une seule note est tirée parmi les cinq voix actives ayant une fréquence. Les
poids des meubles et véhicules restent ceux définis plus haut.

Le résultat est mémorisé dans les ModData du cadavre : un nouveau remplissage
ne relance pas le tirage et ne duplique pas la note ; si le moteur reconstruit
l’inventaire, la même note est rétablie. Le bonus concerne les cadavres dont le
butin est rempli après activation. Validation automatisée sur doublures Lua ; contrôle du butin réel en solo
et sur serveur après redémarrage restant à effectuer.
