# Livre du passeur : stock, offre figée et action `propose_trade`

- Tâche : E13-T02 (table serveur et action `propose_trade`) ; s'appuie sur E13-T01 (table validée [passeur-table.md](../../specifications-techniques/passeur-table.md), décisions du 2026-10-08 et du 2026-10-10), E07-T01 (actions en liste fermée), E13-T05 (journal du dehors, numéro de passage)
- Code : `media/lua/server/RadioSurvivor/RS_Trade.lua` (autorité) ; barème `media/lua/shared/RadioSurvivor/RS_TradeValues.lua` (inchangé) ; contexte joint par `RadioSurvivor_Server.lua` (champ `trade=`, écrit par `RS_Transport.lua`) ; pont `bridge/radio_bridge.py` (`trade_context`, `trade_prompt`, `EXECUTABLE_ACTIONS["propose_trade"]`, contrôle de forme dans `bounded_actions`) ; banc `tests/test_rs_trade.py`
- Build : 42.21.0 (Java décompilé **J/** = `<decompiled>\42.21.0\java\zombie\`) — Date : 2026-10-13 — Statut : brouillon, testé hors jeu seulement

## Problème

Le passeur (voix radio jouée par le LLM) négocie à la radio. Il ne doit proposer que ce qu'il a à bord ce passage, à un prix tiré de la table validée, dans une marge permise ; le serveur doit figer l'offre pour que l'échange sur la berge (E13-T04) la vérifie, se souvenir des affaires passées et laisser le passeur refuser. Acceptation : aucune offre hors table acceptée ; stocks jamais négatifs.

## Contraintes

| Fait | Preuve | Statut |
|---|---|---|
| Une action proposée par le LLM n'a que des paramètres scalaires : au plus 8, chaînes de 64 caractères au plus. | `RS_Actions.lua` (`paramsOf`), `radio_bridge.py` (`bounded_actions`, `MAX_PARAM_BYTES`) | confirmé (banc) |
| Le serveur joint du contexte à la demande suivante en hexadécimal RSV2 (comme `memory=`, `persona=`, `mission=`). | `RS_Transport.lua`, `radio_bridge.py` (`HEX_FIELDS`) | confirmé (banc) |
| Poids d'un objet à fluide = poids du script + litres de fluide (`getUnequippedWeight = getActualWeight + getContentsWeight`, `getContentsWeight` = `getFluidContainer():getAmount()`). Une bouteille de whiskey pleine pèse 0,7 + 1,0 kg. | `J/inventory/InventoryItem.java:3135-3147, 3160-3162` | confirmé statiquement |
| Kahlua : pas d'opérateurs binaires ; Park-Miller (48271, 2^31 − 1) exact en `double`. | base `kahlua-lua.md` | confirmé statiquement |

## Choix (2026-10-13)

### Passage et stock

- **Passage** = semaine de jeu, `RS_OutsideNews.currentEdition()` (même numéro que l'édition du journal du dehors). E13-T03 pourra le remplacer par la réservation réelle.
- **Stock tiré** par passage (section 3 de la table) : fourchettes par objet ; graines 3 à 8 sachets, 4 sortes au plus ; alcools 1 à 4 bouteilles au total ; une édition du journal du dehors. Tirage **reproductible** : Park-Miller sur une graine tirée une fois et gardée dans l'état privé du serveur ; même graine et même passage = même stock (rien d'autre à sauvegarder).
- **Disponible** pour un appelant = stock tiré − échanges faits du passage (`sold`) − offres ouvertes des autres appelants. Son offre ouverte n'est pas déduite : une nouvelle offre la remplace. Jamais négatif ; une proposition qui dépasse est refusée `over_stock`.
- Poids par objet : `Weight` du script vanilla 42.21, plus la capacité du fluide pour les bouteilles pleines (contrainte ci-dessus) ; vérifié par le banc contre les scripts installés.

### Offre (`propose_trade`)

- Paramètres : `items` = « `Nom:quantité` » séparés par des virgules (64 caractères au plus ; quantité 1 si omise, 1 à 99 ; nom du stock sans module, casse indifférente ; 8 lignes au plus ; pas de doublon) ; `margin` facultative (la plus basse permise si absente).
- Contrôles, dans l'ordre : forme (`bad_params`), marge arrondie au centième dans la fourchette (`bad_margin`), chaque objet au stock disponible (`not_in_stock`, `over_stock`), poids total ≤ 10 kg (`over_weight`), prix total ≤ 120 points (`over_cap` : le passeur ne prend pas plus en un passage, une offre plus chère serait impayable).
- **Prix calculé par le serveur**, jamais par le LLM : par ligne ⌈V × quantité × (1 + marge) × M⌉, M = cordon × rareté (1,25 si le stock tiré de l'objet est d'un seul exemplaire), borné à 1,75. Les exemples 1, 2 et 4 de la table sont rejoués par le banc.
- **Offre figée** : numéro de révision global croissant, passage, lignes (objet, quantité, V, M, prix), marge, prix, poids, état `open`. Une nouvelle offre du même appelant remplace la précédente (`replaced`) et rend sa réserve. Une offre ouverte d'un passage passé devient `expired`.
- **Refus possible** : le LLM ne propose rien (consigne du prompt) ; le serveur refuse ce qui sort de la table et garde le dernier refus, dit au LLM à l'appel suivant.

### Mémoire des affaires et marge

- Par appelant (compte, plus le personnage du carnet comme `RS_Memory`) : les 8 dernières offres (passage, objets, prix, issue : `open`, `replaced`, `expired`, `done`, `cheated`, `cancelled`) ; 50 appelants au plus, le moins récent sans offre ouverte évincé.
- **Marge la plus basse permise** (décision à confirmer) : 0,25, moins 0,05 par affaire conclue (`done`), jamais sous 0,10 ; 0,50 dès qu'une tricherie figure dans la mémoire. La plus haute : 0,50. La réputation E04 n'a pas d'API exploitable (`RS_Reputation.lua` : `available = false`) ; la mémoire du passeur en tient lieu.
- `Trade.close(appelant, personnage, rev, issue)` (point d'appel de E13-T04) : `done` garde les quantités prises pour le passage (`sold`), `cheated` et `cancelled` rendent la réserve.

### Contexte du LLM (`trade=`)

Joint à chaque demande d'une voix dont la fiche autorise `propose_trade` (et à sa demande de consigne) : passage, plafonds (120 points, 10 kg), fourchette de marge, cordon, stock disponible pour cet appelant (V, poids, prix unitaire à la marge la plus basse), ce que le passeur prend (barème des quatre catégories, plafonds par catégorie, papiers nominatifs), offre en cours, 5 dernières affaires, dernier refus. Rien de secret : ni lieu, ni heure, ni fréquence, ni secret de fiche (le pont ignore un livre qui en cite un). Le pont l'écrit en anglais (« Your trade book ») et demande de ne pas annoncer de total avant l'appel suivant, où l'offre figée et son prix exact figurent.

### État

`S.data.trade` (état privé `RS_State`, sauvegardé par la boucle du carnet) : `seed`, `rev`, `books[clé] = { offer, deals, lastRev, refused }`, `sold = { passage, items }`, `cordons[passage]`. Sans état chargé : table en mémoire, perdue au redémarrage (comme les compteurs de `RS_Actions`). Jamais en ModData globale.

## Alternatives écartées

- **Prix annoncé par le LLM** et contrôlé ensuite : le LLM calcule mal ; le serveur calcule, le LLM choisit la marge.
- **Une ligne par paramètre** (`antibiotics = 2`) : les noms d'objets ne respectent pas la forme des noms de paramètres (`308Box`), et 8 paramètres au plus.
- **Codes courts par objet** : moins lisibles pour le LLM ; les noms vanilla tiennent dans 64 caractères pour 3 ou 4 lignes.
- **Stock gardé tel quel en sauvegarde** : le tirage reproductible suffit ; seuls les échanges faits et les offres sont écrits.
- **Ce que le joueur donne dans l'offre** : le passeur fixe un prix en points ; ce que le joueur dépose est compté au barème sur la berge (E13-T04), avec les plafonds par catégorie.

## Décisions à confirmer

1. Passage = semaine de jeu (comme le journal du dehors), en attendant la réservation d'E13-T03.
2. Livre tenu **par appelant** (compte + personnage), pas encore par équipe (E13-T03 : une réservation par équipe).
3. Marge la plus basse tirée de la mémoire du passeur (0,25 − 0,05 par affaire conclue, plancher 0,10 ; 0,50 après tricherie), faute d'API de réputation.
4. Offre au-dessus de 120 points refusée (`over_cap`) ; 8 lignes au plus, 99 par ligne.
5. `propose_trade` **pas encore activée sur la fiche de Gus** (`actions=say`) : sans réservation ni échange (E13-T03, E13-T04), une offre figée ne mènerait à rien en jeu, et la fiche interdit encore de citer un prix. À activer avec E13-T03, en revoyant sa « Business rule ».
6. Les nouvelles du journal du dehors ne sont pas mises dans le contexte du passeur (question laissée ouverte par E13-T05).

## Tests

- Banc `tests/test_rs_trade.py` (23 tests) : catalogue conforme à la table (noms, fourchettes, plafonds, marges) et poids relus dans les scripts vanilla 42.21 ; tirage reproductible et dans les fourchettes sur 400 passages ; exemples de prix de la table ; multiplicateur borné ; offre figée, révision, réserve, remplacement ; refus `not_in_stock`, `over_stock`, `over_weight`, `over_cap`, `bad_margin`, `bad_params` ; tirage aléatoire de 3 000 propositions sur deux passages (aucune offre hors table, prix recalculé, disponible = tiré − pris, jamais négatif) ; marge selon la mémoire, tricherie, `close`, expiration ; livre par personnage et borné ; persistance (encodage RSV2 puis relecture) ; exécuteur jugé par `RS_Actions` ; champ `trade=` relu par le pont, prompt, livre cassé ignoré ; forme de l'action dans le pont ; chaîne complète dans le serveur radio solo (demande avec `trade=`, réponse `propose_trade`, offre figée, demande suivante portant l'offre et le refus).
- En jeu : rien avant E13-T03 (cible hors jeu).

## Limites et restes

- E13-T03 ([passeur-rendezvous.md](passeur-rendezvous.md)) : cordon tiré par passage et monté par l'hélicoptère ; la première offre figée réserve le passage pour l'équipe de l'appelant ; `propose_trade` activée sur la fiche de Gus (décision 5).
- Aucun contrôle de ce que le joueur apporte (E13-T04) ; la réputation n'est pas modifiée ici.
- Comportement réel du LLM (respect des noms, marge, refus) non mesuré : à observer dès l'activation sur Gus.
