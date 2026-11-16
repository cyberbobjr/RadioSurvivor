# ADR — Troc par liste d'objets et cas limites des missions et récompenses

| | |
|---|---|
| Date | 2026-11-16 |
| Statut | Accepté |
| Décideur | utilisateur |
| Plan associé | [E23 — Troc simple et cas limites](../../annexes/plans-termines/E23-troc-simple-et-cas-limites.md) |
| Références | ADR [voix déclarées](adr-personas-declaratives.md) (D07, D08 : troc déclaré dans la fiche, modes d'arrivée) ; ADR [atelier des voix](adr-atelier-voix.md) ; `docs/specifications-techniques/passeur-table.md` |

## Contexte

Une revue des cas limites (2026-11-16, lecture du code) a trouvé des trous dans le troc, les missions et les
récompenses. Le plus grave vient du troc lui-même : la voix fixe un **prix en points**, et le joueur doit payer avec des
objets dont il ne voit jamais la valeur. Le moteur doit alors deviner le paiement (sac le plus riche, prise dans
l'ordre jusqu'au prix, aucune monnaie rendue) ; il se paie sur le butin déjà présent dans une benne, sur le sac d'un
autre joueur, et traite de tricheur un joueur qui a réparti son paiement dans deux sacs. Depuis l'atelier (E22), toute
voix peut faire du troc, pas seulement Gus.

Autres trous : sac de récompense jamais posé quand le joueur arrive plus de 24 h réelles après la réussite (dossier de
mission purgé) ; mort du participant avant son rapport ; mission qui expire pendant une panne du pont ; livraison perdue
par un arrêt brutal pendant le ramassage ; carte de planque perdue quand l'inventaire est plein.

## Décisions (utilisateur, 2026-11-16, une question à la fois)

- **D01 — Le prix est une liste d'objets.** La voix et le joueur conviennent à la radio des deux listes : ce que le
  joueur apporte, ce que le marchand laisse (« tu m'apportes 1 boîte de cartouches, je te laisse 2 conserves »). Le
  joueur ne voit jamais de points. Le serveur garde le barème (valeurs, marge, cordon, rareté) pour refuser un accord
  inéquitable. La liste convenue s'affiche dans le carnet.
- **D02 — Seul ce qui a été déposé après la réservation compte.** Le marchand cherche les objets convenus dans tous les
  sacs au sol (modes route et bateau) ou tous les contenants du lieu (mode cache), à 3 cases, mais seulement parmi ce
  qui a été ajouté après la réservation : le contenu présent est noté la première fois que le serveur voit le lieu
  chargé après la réservation. Plusieurs sacs ou contenants s'additionnent. Un sac déjà là, du butin d'origine ou la
  planque d'un autre joueur ne comptent pas. Un véhicule n'est jamais lu, et la consigne de la voix le dit.
- **D03 — Tout ou rien, avec compensation.** Tout est déposé : le marchand prend exactement la liste convenue (le reste
  reste en place) et laisse sa marchandise au même endroit. Dépôt incomplet : promesse non tenue, le marchand garde tout
  ce qui a été déposé en compensation, ne laisse rien, et le joueur perd de la réputation auprès de cette voix. Rien
  déposé : il perd un peu de réputation, moins qu'un dépôt incomplet.
- **D04 — Accord figé à l'arrivée.** Une fois le marchand arrivé au rendez-vous, la voix refuse toute nouvelle offre
  pour ce passage.
- **D05 — Annulations rares et annoncées.** Patrouille de soldats : 1 chance sur 75 par rendez-vous. Hélicoptère : 1
  chance sur 100. Météo : selon la météo réelle du jeu (orage). Valable pour toute voix qui fait du troc, selon son mode
  d'arrivée. La voix annonce l'annulation sur sa fréquence et la répète chaque heure jusqu'à l'heure du rendez-vous.
  Une annulation par le marchand ne touche à aucun dépôt et ne coûte rien au joueur.
- **D06 — Sac de récompense gardé jusqu'à sa pose.** Une mission dont le sac de récompense n'est pas encore posé n'est
  jamais purgée.
- **D07 — Mission perdue avec le mort.** La mort d'un participant efface ce qu'il savait : sa participation finit
  aussitôt, avec un message dans le carnet de son nouveau personnage. Si un autre participant de l'équipe est vivant, la
  mission continue pour lui (confirmé par défaut).
- **D08 — Délai suspendu sans pont.** Tant que le pont ne répond pas, le délai des missions qui attendent un rapport à
  une voix est arrêté ; il reprend au retour du pont. Le carnet dit que la voix ne répond pas et que la mission attend.
- **D09 — Livraison comptée après un arrêt brutal.** Au redémarrage, les objets que le serveur ramassait et qui ont
  disparu sont comptés comme livrés.
- **D10 — Carte de planque remise d'abord.** La planque n'est réservée qu'une fois la carte entrée dans l'inventaire ;
  sinon rien n'est consommé et la récompense reste à réclamer.

- **D11 — Ce que la voix propose et accepte est déclaré d'avance** (utilisateur, 2026-11-16, ajout). La section
  `[trade]` porte, en plus du stock, la liste de ce que la voix accepte en paiement (`accept=` : objets qui ont un prix
  au troc, ou catégories). La négociation reste dans ces deux listes ; le serveur refuse un objet non accepté.
  L'atelier édite les deux listes ; aucun objet ne s'y saisit à la main (liste filtrable à cocher).

## Conséquences

- Les points 5 et 5 bis de la revue (sacs additionnés, monnaie) disparaissent avec D01-D03.
- L'action `propose_trade` du LLM change de forme (deux listes) : consignes du pont, fiche des marchands, atelier, wiki
  et exemples suivent. Aucune reprise de l'ancien format d'offre (mod non publié).
- Pénalités (confirmé par défaut) : dépôt incomplet = la sanction actuelle de tricherie ; rien déposé = la moitié.
