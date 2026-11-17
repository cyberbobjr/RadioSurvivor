# ADR — Lieux communs à toutes les voix, zones et lieux tirés autour du joueur

| | |
|---|---|
| Date | 2026-11-17 |
| Statut | Accepté |
| Décideur | utilisateur |
| Plan associé | [E25 — Lieux communs, zones et distances](../../annexes/plans/E25-lieux-communs.md) |
| Références | ADR [voix déclarées](adr-personas-declaratives.md) (sections `[place]`, `target=`) ; ADR [atelier des voix](adr-atelier-voix.md) (D12 : rien de technique à saisir) ; `docs/specifications-techniques/persona-format.md` (« Lieux connus ») ; `CA_Sites.lua`, `CA_MissionScout.lua` |

## Contexte

Constat du 2026-11-17 (lecture du code, confirmé statiquement) :

- Une mission à lieu fixe vise toujours la même case, pour tous les joueurs : « Nettoyer l'église » une troisième fois
  n'a plus d'intérêt.
- Sans `target=`, seuls quatre genres tirent un bâtiment au hasard autour de l'appelant (`scout`, `clear`, `retrieve`,
  `signal` : bâtiment habitable entre 60 et 250 cases, loin des bases connues, départ du tirage au hasard). Les autres
  (`barricade`, `relay`, `watch`, `item`, `route`) exigent un lieu fixe.
- Chaque voix déclare ses propres lieux (`[place]`, 12 au plus). Un même endroit utilisé par plusieurs voix se recopie
  dans chacune ; les 16 voix livrées portent 15 lieux (11 rendez-vous de marchand).

## Décisions (utilisateur, 2026-11-17, une question à la fois)

- **D01 — Trois façons de choisir l'objectif d'une mission, en plus du lieu fixe.** Un lieu peut être un **point** ou
  une **zone**. L'objectif d'une mission est au choix :
  - un **point** : ce bâtiment ou ce point, toujours ;
  - une **zone** : un bâtiment tiré dans la zone à chaque mission ;
  - **Près du joueur** (100 à 200 cases), **Plus loin** (200 à 500 cases), **Très loin** (500 à 1 500 cases) : un
    bâtiment tiré à cette distance de l'appelant à chaque mission.
  Valable pour tous les genres de mission qui ont un objectif.
- **D02 — Un seul fichier de lieux, commun à toutes les voix.** Les lieux (points et zones) vivent dans un fichier
  commun, édité par un onglet « Lieux » de l'atelier. Une voix choisit ses lieux dans une liste ; plus aucun lieu n'est
  écrit dans une voix. Les 16 voix livrées sont reprises, sans lecture de l'ancien format.

## Choix confirmés par défaut (2026-11-17)

- **D03 — Genre de bâtiment au choix** pour une zone et pour les trois distances : un des genres que le jeu reconnaît
  déjà (`CA_Sites.KINDS` : maison, maison avec garage, ferme, immeuble, motel, église, école, commissariat, caserne de
  pompiers, clinique, hôpital), ou « n'importe lequel ». Mêmes règles que le tirage d'aujourd'hui : bâtiment habitable
  de la carte, jamais construit par un joueur, loin des bases connues.
- **D04 — Un lieu sert là où il est nommé.** La clé `use=` disparaît : une voix nomme un lieu commun à l'endroit où elle
  s'en sert (repères qu'elle peut donner, planques d'une mission, objectif, points d'un trajet, rendez-vous du
  marchand, cache de récompense). Le modèle ne voit que les libellés des lieux que la voix nomme, jamais les autres ni
  une coordonnée.
- **D05 — Planque, rendez-vous, trajet et cache restent des points.** Le joueur doit trouver l'endroit exact : l'atelier
  ne propose que des points pour ces usages, le lecteur refuse une zone. Une zone donnée comme repère est marquée en son
  centre ; « révéler le quartier » couvre la zone, dans la limite actuelle de 160 cases.
- **D06 — Le fichier commun suit les règles des voix.** `_places.txt` livré dans le dossier `personas/` du mod, copié
  et mis à jour dans le dossier de travail comme une voix (empreintes), relu toutes les 30 s ; une voix qui nomme un lieu
  absent est refusée avec sa ligne, et le verdict s'affiche dans l'atelier. L'atelier refuse de supprimer un lieu
  qu'une voix utilise et dit lesquelles.
- **D07 — Une zone est un rectangle** donné par deux coins (chacun collé depuis la carte comme un point) et un étage.
- **D08 — Les relevés de lieux en jeu** (E22-T08) arrivent dans l'onglet « Lieux ». Dans une voix, la liste d'un
  choix de lieu propose aussi « Nouveau lieu… », qui ouvre la création sans quitter la voix.

## Conséquences

- Format : `_places.txt` (sections `[place <id>]` : `label`, et `at=` pour un point ou `area=` pour une zone) ; les
  sections `[place]` et la clé `use=` quittent les fiches de voix ; `target=` accepte un lieu, `near`, `far`,
  `very_far`, avec `building=` en option ; nouvelle clé de repères de la voix et lieu de cache nommé. Les deux lecteurs
  (serveur et pont) suivent.
- Jeu : un tirage commun (`CA_Sites`) avec distance mini et maxi, zone et genre ; tous les gabarits qui ont un objectif
  le reçoivent. « Très loin » lit les cellules de la métagrille jusqu'à 1 500 cases : coût à mesurer.
- Le libellé d'un lieu commun est unique, dans une seule langue, quelle que soit la langue de la voix.

## Hors périmètre

- Living Knox.
- Lieux propres à une seule voix.
