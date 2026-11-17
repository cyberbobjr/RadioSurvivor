# ADR — Simplification de Living Knox : utilitaires communs, files partagées, moteurs découpés

| | |
|---|---|
| Date | 2026-11-17 |
| Statut | Accepté |
| Décideur | utilisateur (« lance la passe de simplification de Living Knox », 2026-11-17, après l'audit du 2026-11-16) ; options recommandées de l'audit retenues par défaut |
| Plan associé | [LK20 — Simplification de Living Knox](../../annexes/plans-termines/LK20-simplification.md) |
| Références | [Audit de complexité du 2026-11-16](../../annexes/audits/audit-complexite-livingknox-2026-11-16.md) (constats F01 à F10) ; [ADR remise en ordre SOLID](adr-remise-en-ordre-solid.md) (D04, ce qu'il ne faut pas faire) ; [ADR bords des cases](adr-bords-des-cases.md) |

## Contexte

L'utilisateur trouve Living Knox trop compliqué (« une usine à gaz »). L'audit du 2026-11-16 le confirme en partie. Le
problème ne vient pas du code mort (4 fonctions) ni des registres, qui servent tous plusieurs fois. Il vient de la
structure :
- **cinq moteurs géants** de 1 500 à 2 900 lignes, avec 8 à 11 rôles chacun : `LK_Fortify`, `LK_Decisions`,
  `LK_Obstacles`, `LK_Stock` et `LK_Expeditions` ;
- **de petites fonctions recopiées** : `cheb` 17 fois, `finite` 15 fois, `isInt` 16 fois, `now` 27 fois ;
- **166 accesseurs d'une ligne** ;
- **cinq files d'attente « une action par image »** réécrites ;
- **un transport réseau client** recopié dans trois vues ;
- **des valeurs par défaut écrites deux fois**.

LK17 est terminé : le chemin du jeu est en place et le déplacement peut être touché.

## Décisions

- **D01 — Une seule copie des petites fonctions pures.** `LivingKnox.Num` (`finite`, `isInt`, `clamp`) et
  `LivingKnox.Geo` (`cheb`, `angleGap`, `squaresAround`) dans `shared/`. Les copies locales identiques disparaissent.
  Une variante qui diffère, comme les `dist`, reste locale tant que sa différence n'est pas justifiée ou supprimée.
- **D02 — Pas d'accesseur qui ne fait que relire une table.** `local function Bodies() return LivingKnox.Bodies end`
  est remplacé par `LivingKnox.Bodies` au point d'appel. Exception : un module qui en a besoin au chargement garde un
  accès à l'exécution, sans capture au niveau du fichier.
- **D03 — Code mort supprimé avec ses tests.** Les 4 fonctions sans appelant de l'audit partent. Les points d'accès
  appelés par les seuls tests restent : ils servent aux campagnes en jeu.
- **D04 — Une seule table de vérité par option sandbox.** `{min, max, défaut}`, de la même forme que `DANGER`.
  `DEFAULTS` et `INT_BOUNDS` en dérivent. `LK_Initiatives` passe par `Config.readInt`.
- **D05 — Une file d'attente partagée.**
  - `LivingKnox.FrameQueue` gère l'enfilage, le budget par image ou par heure, la reprise et la fin.
  - Chaque module ne fournit que sa fonction de travail.
  - Les cinq files actuelles migrent une à une : Talk, API, Stock, Fortify, Decisions.
- **D06 — Un client de requêtes commun.** `LivingKnox.ClientRequest` prend en charge l'envoi, la réception par
  module et commande, et le relais solo. Il remplace la tuyauterie de `LK_AdminView`, `LK_NpcSheet` et
  `LK_TradeView`.
- **D07 — Les cinq moteurs sont découpés selon leurs sections, sans changement de comportement ni de format
  sauvegardé.**
  - Un dossier par moteur, comme `Fortify/` qui existe déjà : `Fortify/`, `Stock/`, `Expeditions/`, `Decisions/`,
    `Obstacles/`.
  - Le fichier d'origine reste la façade et la racine : il garde les mêmes noms publics, les mêmes événements, les
    mêmes clés de sauvegarde et les mêmes commandes réseau.
  - Ordre : `Fortify`, puis `Stock` et `Expeditions`, puis `Decisions` et `Obstacles`.
- **D08 — Déplacement : moins de façades.** Après LK17, `LK_Passage` (simple relais vers `PassageArbiter`) fusionne
  avec l'arbitre. `Edges` et `EdgeRules` restent tels quels.
  - *Mise à jour du 2026-11-17 :* décision retirée. `LK_Passage` n'est pas un relais : il porte le registre des priorités de passage et le nom de la commande réseau, alors que `LK_PassageArbiter` fait l'arbitrage pur. Les deux restent séparés (LK20-T10 abandonnée).
- **D09 — Fonctions longues et imbrication : au fil de l'eau.** Pas de chantier dédié (F07, F10). Toute fonction
  touchée par une tâche de ce plan qui dépasse 80 lignes est coupée en étapes nommées.

## Règles du chantier

- **Comportement inchangé.**
  - Les bancs hors jeu passent sans modifier aucun attendu.
  - Un test qui ne vérifie plus qu'un nom interne déplacé est adapté, jamais doublé d'un « garde-fou anti-retour ».
  - Les tests d'une fonction supprimée sont supprimés avec elle.
- **Lint :** luacheck Contents et dev ne gagne aucun avertissement.
- **Fin de chaque phase :** campagnes `solo-lk` puis MP avec `--mods lk` (les suites de RadioSurvivor ne sont pas
  lancées).
- **Préservation :** aucune clé sauvegardée, commande réseau, option sandbox ni API publique (`LivingKnox.API`) ne
  change de nom.
- **Ce qu'on ne fait pas (ADR remise en ordre SOLID, D04) :**
  - pas de registre pour les verbes de l'exécutant ;
  - pas de registre pour la nature d'obstacle ;
  - pas d'escalade de déplacement ;
  - pas de fusion des compteurs `count(...)` propres à chaque module.

## Conséquences

- **Effet attendu :** environ 600 lignes de moins. Les fichiers des moteurs passent de 1 500 à 2 900 lignes à 200 à
  500 lignes chacun.
- **Ajout de code :** ajouter un chantier, un genre d'expédition ou une règle de refus ne demande plus de relire un
  fichier de 2 000 lignes.
- **Risque :** le principal est l'ordre de chargement (`require`) et le format compact des fortifications (LK13-T07).
  Les bancs de sauvegarde et la campagne `mp-persist` le couvrent.
