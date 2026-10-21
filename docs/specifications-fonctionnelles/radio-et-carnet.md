# Radio, carnet et missions (F01 à F15)

Vue joueur des fonctionnalités de la partie « radio » du mod. Contrats techniques :
[specifications-techniques/](../specifications-techniques/README.md) ; guide joueur : [Utilisation](../wiki/fr/03-utilisation.md).

## F01 — Réseau de six voix radio

- Walt (le confident, hors carte), Darlene (infirmière, clinique de West Point), Cody (déserteur de la Garde nationale),
  Whitaker (famille assiégée, le premier secours), le Night Owl (station pirate, la chronique) et Gus (passeur de
  l'Ohio, le troc).
- Chaque voix a sa fréquence **tirée pour chaque partie** dans une plage qui lui est propre, ses horaires d'écoute, la
  radio requise et ses appels spontanés (une voix au plus par heure, option `RadioSurvivor.SpontaneousCalls`).
- Une voix se souvient de chaque personnage ; un joueur qui parle sans pause est invité à reprendre son souffle
  (`PlayerCooldown`, `MaxPerHour`).
- MP : les fréquences ne sont jamais envoyées aux clients. Détails : [persona-format.md](../specifications-techniques/persona-format.md).

## F02 — Notes de fréquences dans le butin

- Cinq notes (journal radio, fiche de patient, avis de la Garde nationale, note griffonnée, prospectus du Night Owl)
  portent la fréquence de la partie ; chacune se trouve là où sa voix l'aurait laissée. Clic droit → **Inspecter**.
- Rareté réglable (`NoteRarity` : aucune, rare, normale, fréquente). Détails : [notes-frequences.md](../specifications-techniques/notes-frequences.md).

## F03 — Émettre depuis la fenêtre radio

- Section **Émettre** ajoutée à la fenêtre radio vanilla : talkie-walkie ou radio HAM en main, radio militaire portée
  sur le dos, radio posée, autoradio. Le micro doit être ouvert. Le champ est grisé pendant la réponse.
- Un talkie-walkie à la ceinture reçoit mais n'émet pas.
- Conception : [E06](../annexes/plans/E06-carnet-radio-emettre.md).

## F04 — Carnet de terrain

- Bouton **Carnet** de la barre de gauche. Onglets **Radio** (historique par fréquence, voyant de réception ; 40 lignes
  par fréquence, 8 fréquences au plus, gardé côté serveur), **Contacts** (personnes rencontrées, note privée, « Ce qu'on
  pense de vous »), **Missions**, **Réputation**, **Équipe** (faction et négociateurs, multijoueur).
- Maquette : [carnet-unique.html](../annexes/maquettes/carnet-unique.html) ; historique : [carnet-implementation-04221.md](../annexes/conception/carnet-implementation-04221.md).

## F05 — Dialogue de proximité avec un PNJ (Ctrl+G)

- **Ctrl+G** (touche réglable) sélectionne le PNJ visible le plus proche ; on écrit sur la ligne **Dire** du carnet ou,
  en MP, dans le chat local. Réponse dans une bulle, en plusieurs bulles si elle est longue.
- Un inconnu ne dit pas tout : nom, histoire et demandes viennent après quelques échanges. Origine :
  [ADR B17](../architecture/decisions/adr-b17-chat-proximite-pnj.md) ; conception : [parole.md](../annexes/conception/parole.md).

## F06 — Actions des voix en liste fermée

- Une voix peut : diffuser des lignes, poser un repère sur la carte, révéler un quartier, lancer une fumée ou une fusée
  (Signal Smoke), déposer une cache tirée d'une table serveur, mettre en scène un lieu, ouvrir une mission, mettre à jour
  son état, retenir un fait, proposer un échange. Le serveur vérifie chaque action.
- Contrat : [protocole-carnet-v2.md](../specifications-techniques/protocole-carnet-v2.md), section « Réponse radio structurée ».

## F07 — Missions générées

- Gabarits vérifiés par le serveur : **Livrer** (N objets d'une catégorie), **Signaler** (fumée d'une couleur ou fusée à
  un lieu et une heure), **Retrouver** (un corps et sa carte d'identité nominative), **Reconnaître** (atteindre un lieu
  puis en rendre compte), **Nettoyer** (N zombies autour d'un lieu), **Récupérer** (une cache à porter à un dépôt).
- Carnet : accepter, inviter sans engager, abandonner (coûte de la réputation) ; zone approximative sur la carte ;
  l'objectif rempli passe à **À rapporter** et la mission ne réussit qu'au compte rendu.
- Récompenses : réputation, puis **une** cache de matériel, une fréquence, une carte-cachette vanilla ou une leçon
  (`LessonMultiplier`, 0 = sans expérience). Livraisons radio par boîte de dépôt ou sac caché.
- Conception : [mission-nettoyer.md](../annexes/conception/mission-nettoyer.md), [mission-recuperer.md](../annexes/conception/mission-recuperer.md),
  [mission-retrouver.md](../annexes/conception/mission-retrouver.md), [mission-signaler.md](../annexes/conception/mission-signaler.md).

## F08 — Survivants à secourir

- Une famille assiégée dans un vrai bâtiment appelle à l'aide avec des indices ; secourue à temps, elle laisse une
  cache ; trop tard, on trouve la scène. Un secours par équipe ; les réserves ne baissent que si un joueur est connecté.
- Délai réglable (`RescueDays`). Détails : [rescue.md](../specifications-techniques/rescue.md), [secours.md](../annexes/conception/secours.md).

## F09 — Le passeur de l'Ohio (troc)

- Troc négocié à la radio avec Gus, une traversée par semaine de jeu, échange sans contact sur une berge, quatre
  catégories de marchandises. Il apporte le « journal du dehors ».
- La même table de valeurs sert au troc direct avec un groupe Living Knox ami (F29). Table :
  [passeur-table.md](../specifications-techniques/passeur-table.md).

## F10 — Chronique du soir et mémorial

- Chaque soir (`ChronicleHour`), le Night Owl raconte les faits du serveur et lit les noms des morts du jour ; tout le
  monde peut être nommé. Conception : [chronique.md](../annexes/conception/chronique.md).

## F11 — Dernières pages

- À la mort d'un personnage, son journal manuscrit, écrit d'après son relevé de vie, est laissé sur le corps. Toujours
  écrites ; seul l'admin peut les couper (`LastPages`). Conception : [dernieres-pages.md](../annexes/conception/dernieres-pages.md),
  [releve-de-vie.md](../annexes/conception/releve-de-vie.md).

## F12 — Réputation

- Missions tenues, personnes secourues, marchand floué, demandeur tué : niveau (mauvaise, neutre, bonne), tendance et
  derniers actes dans l'onglet **Réputation**. Distincte de l'attitude de chaque PNJ. Interne au mod ;
  CharacterReputation est utilisé s'il est présent ([reputation-contract.md](../specifications-techniques/reputation-contract.md),
  [reputation-interne.md](../annexes/conception/reputation-interne.md)).

## F13 — Parler fait du bien

- Une réponse d'un survivant à votre personnage par radio apaise un peu l'ennui et la tristesse ; entendre deux
  survivants discuter apaise un peu l'ennui. Plafond par heure de jeu (`ComfortBoredom`, `ComfortSadness`,
  `ComfortListen`, `ComfortPerHour`).

## F14 — Initiatives et échanges entre PNJ

- Les PNJ prennent la parole sur des événements et se transmettent ce qu'ils ont vu (`InitiativeFrequency`).
  Conception : [initiatives.md](../annexes/conception/initiatives.md), [conversations.md](../annexes/conception/conversations.md).

## F15 — Relations, accords de faction, chef et départ

- Relations qui évoluent dans les deux sens ; trêves et alliances négociées par le chef d'un groupe avec une faction de
  joueurs (mandats de négociation). Le chef décide pour la bande ; un membre peut contester, refuser ou partir en gardant
  sa mémoire. Détails : [factions.md](../specifications-techniques/factions.md), [accords.md](../annexes/conception/accords.md),
  [contestation.md](../annexes/conception/contestation.md), [depart.md](../annexes/conception/depart.md).
