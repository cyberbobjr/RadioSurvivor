# Journal du dehors (E13-T05)

Document du mod que le passeur de l'Ohio apporte à chaque passage : « journaux récents » du catalogue d'apport
(`docs/passeur-table.md`, section 3 ; décision E13-T01 (7) du 2026-10-10). Brouillon du 2026-10-12, cible solo.

## Objet

- `RadioSurvivor.OutsideNews` (`media/scripts/RadioSurvivor_outsidenews.txt`) : `literature` sans `CanBeWrite`, icône
  et modèles du journal vanilla (`Newspaper`, `Newspaper_Ground`), tag `base:fastread` (lecture en une seconde), pas
  de `base:newspaper` (recettes vanilla). « Inspecter » ouvre la fenêtre vanilla des documents (`ISReadABook`,
  base `quest-building-blocks.md`, « Document de mod au rendu des journaux »).
- Nom : « Journal du dehors » / « News From Outside ». Un personnage illettré ne le lit pas (pas de `base:picture`) :
  c'est un texte.

## Contenu

- Feuille ronéotypée de la rive de l'Indiana : titre, numéro d'édition, **date du jour de jeu de sa création** (donc
  après l'épidémie), un article de une, trois brèves, les prix de la semaine à Evansville (essence, pain).
- Gabarits fixes FR/EN dans `Print_Text.json` (`Print_Text_RadioSurvivor_OutsideNews_*`) : 10 unes, 12 brèves. Ils
  ne parlent que du dehors (clôture, réfugiés, couvre-feu, rationnement, Congrès, télévision, marchés…) : aucune
  fréquence, aucune voix du mod, aucun lieu de rendez-vous, aucun secret de fiche, aucune promesse de secours
  (contrôlé par `tests/test_outside_news.py`). Les textes évitent les faits qui se contrediraient d'une édition à
  l'autre (aucun état qui « finit »).
- Choix reproductible d'après le seul numéro d'édition `n` (`RS_OutsideNews.select`) : une `((n - 1) × 7 mod 10) + 1`
  (deux éditions qui se suivent n'ont jamais la même une ; dix éditions de suite, dix unes différentes), trois brèves
  distinctes tirées par Park-Miller sans opérateur binaire, prix `base + pas × (n - 1) + tirage 0..9` en cents (ils
  montent chaque semaine, plafond 99,99 $).

## Transport et langue (règle MP des traductions)

- L'autorité n'écrit dans la ModData que des clés et des nombres :
  `printMedia = { id = "RadioSurvivor_OutsideNews_<n>", title = id, info = <clé>, text = <clé> }` et
  `RadioSurvivorOutsideNews = { format, edition, y, m, d, lead, briefs, gas, bread }`.
- Le client compose mise en page, transcription et titre dans la langue du lecteur juste avant l'ouverture : même
  enveloppe d'`ISReadABook:displayPrintMedia` que les notes de fréquences (`client/RadioSurvivor/RS_NotesReader.lua`,
  clés remises après l'appel ; `startLoadingPrintMediaTextures` court-circuité, aucune image). Mise en page bâtie en
  Lua élément par élément (`RS_OutsideNews.LAYOUT`), vérifiée hors jeu avec les métriques des polices SDF vanilla et
  la règle de retour à la ligne d'`AtomUIText`.
- **Marque « lu » par édition** : `ISReadABook:complete` marque l'identifiant (`addReadPrintMedia(id)`) et
  l'inventaire teste le titre (`isPrintMediaRead(title)`, `ISInventoryPane.lua:2605`). Le titre stocké vaut donc
  l'identifiant de l'édition ; le titre affiché est composé (« Nouvelles du dehors - n° 4 »).

## Création et point d'appel

- `server/RadioSurvivor/RS_OutsideNewsServer.lua`, autorité seulement :
  `OutsideNewsServer.create(passage)` rend un objet neuf (`instanceItem`), hors de tout conteneur, portant l'édition
  du passage ; **l'échange sur la berge (E13-T04) l'appellera** avec le numéro du passage et posera l'objet avec la
  contrepartie (envoi aux clients compris). Sans numéro : édition de la semaine en cours
  (`floor(âge du monde / 168 h) + 1`). Numéro invalide (non entier, < 1, > 9999) : `nil` et une ligne `WARNING`.
- `OnCreate` (objet donné par un admin, apparu autrement) pose l'édition de la semaine en cours : tout journal est
  lisible. Sur un client MP, l'`OnCreate` rejoué est remplacé par la ModData du serveur.
- Commande de test (console Lua de debug, solo) : `RadioSurvivorOutsideNews.give()` (semaine en cours),
  `RadioSurvivorOutsideNews.give(3)` (passage 3), `RadioSurvivorOutsideNews.give(3, joueur)` ; sur un serveur, l'objet
  est envoyé au client (`sendAddItemToContainer`).

## Barème

- Valeur de vente **2** (`RS_TradeValues.SELL_ONLY`, `RS_TradeValues.sellValue`), une édition par passage
  (`cap = 1`).
- **Jamais repris** : hors module `Base`, `RS_TradeValues.value` le laisse à 0 (passeur comme groupes Living Knox,
  `docs/passeur-table.md`, « Ce qui est toujours refusé »).

## Décisions à confirmer

Prises par défaut (option la plus simple, la plus proche du vanilla), signalées dans le compte rendu de la tâche :

1. Gabarits fixes (10 unes, 12 brèves) plutôt qu'un texte écrit par le LLM : aucun pont requis, aucune langue figée
   sur le serveur, contenu contrôlable.
2. Numéro d'édition = numéro du passage fourni par l'échange ; à défaut, semaine du monde.
3. Date = jour de jeu de la création (aucune date fictive décalée).
4. Commande de test = fonction globale de la console Lua de debug (solo), pas de commande réseau d'admin.

## Reste

- Appel par l'échange (E13-T04) et numéro de passage (E13-T03).
- Les nouvelles du journal ne sont pas transmises au contexte du passeur (fiche `gus.txt` : « Never invent facts …
  about the outside world ») : à décider avec E13-T02 si le LLM doit pouvoir les citer.
- Rendu réel de la page à vérifier en jeu (polices, retours à la ligne).
