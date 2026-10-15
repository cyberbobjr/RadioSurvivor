# LK10 — Récits

**Objectif.** Donner à chaque groupe une histoire et un journal, à partir de gabarits écrits, enrichis par le LLM quand RadioSurvivor est présent.

**Dépend de.** LK08-T01.

**Sources.** Décision LK00 (gabarits + LLM optionnel) ; RadioSurvivor (pont, contrat RSV2).

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-10 — **LK10-T05** : origines répétées dans une population (47 % des populations de 4 groupes en partagent une, tirage uniforme sans biais mesuré sur 1 000 mondes) : **ajouter des gabarits** sans changer le tirage (pas de tirage sans remise).
- 2026-10-14 — **LK10-T02** : récit tiré de `appendLog` ; texte par clés `.json` (et non dans les données Lua comme `LK_Stories`) ; sortes retenues (joined, loss, remains, conflict, illness restées techniques) ; 40 entrées par groupe (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK10-T03** : bornes 600 caractères / 8 lignes ; refus de `<` et `>` ; héritage du texte du groupe par un membre, `append` après saut de ligne ; un texte par langue (en, fr) (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **LK10-T04** : carnet déposé à la disparition du groupe plutôt que mis à jour chaque jour ; `Base.Notebook` et `Base.SheetPaper2` ; texte dans la langue de l'autorité (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **LK10-T01** — Gabarits d'histoire FR/EN
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK08-T01
  - Fichiers : `media/lua/shared/LivingKnox/Data/Stories*.lua`, traductions
  - Faire : origine, motivation, chef, ton, secrets, combinés par le serveur ; textes FR et EN.
  - Accepté si : cent tirages sans incohérence grossière ; textes relus.
  - Tests : banc.
  - Preuve : `Data/Stories.lua` (12 origines, 12 motivations, 9 tons, 14 passés de chef, 17 secrets, noms du Kentucky ; français en échappements d'octets UTF-8, formes féminines) et `LK_Stories.lua` côté serveur : `compose(type, graine)` déterministe (Park-Miller, sans opérateurs binaires), anglais et français composés par le serveur (`getText` inutilisable sur un serveur MP), résumé ≤ 600 octets, règles de compatibilité `types`/`tags`/`excludes`/`requires`, secrets marqués privés et retirés par `publicView` ; `tests/test_lk_stories.py` 13/13 (cent tirages par type sans incohérence, contre-épreuve, ≥ 95 résumés distincts) ; échantillon de 3 histoires par type fourni à l'utilisateur ; `tests/run_all.py` 31/31 le 2026-10-10, luacheck 17/0, `check_case.py` PASS ; `docs/conception/recits.md` ; LK08-T02 : commit `c2bb795` ; relecture de l’utilisateur le 2026-10-10 : 61 OK et 4 à corriger, corrigés (commit `a1f4cde`), seconde lecture 65 OK sur 65
  - Reste : non exécuté dans la VM Kahlua (longueurs en unités UTF-16) ; graine numérique ou ASCII seulement

- [x] **LK10-T02** — Journal de groupe
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK10-T01, LK09-T02
  - Fichiers : `LK_Journal.lua`
  - Faire : faits datés du groupe (installation, expéditions, morts, rencontres), bornés, consultables par l'admin et par RadioSurvivor.
  - Accepté si : journal cohérent avec les faits simulés.
  - Tests : banc.
  - Preuve : banc `tests/test_lk_journal.py` du 2026-10-12 (18 tests OK : journal de récit `g.journal` tiré du journal technique dans la même écriture, borné à 40 entrées, daté à l'heure simulée ; sur 6 jours simulés, un départ et un retour par expédition tirée et une entrée par mort ; rattrapage hors écran = pas horaire ; persistance ; aucune coordonnée ni compte de joueur ; `API.journal` ; traductions EN/FR de toutes les sortes) ; `kahlua` 33 OK ; run_all 77/77 ; luacheck 16/0 ; conception `docs/conception/journal.md`
  - Reste : dans la VM Kahlua seul le chargement est vérifié ; pas de récit rétroactif ; raids, vengeance, troc, aide et soins pas encore au récit ; lieu d'une expédition physique non nommé.

- [x] **LK10-T03** — Point d'enrichissement par un LLM
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK10-T01
  - Fichiers : `LK_API.lua`
  - Faire : fonction publique pour qu'un autre mod (RadioSurvivor) remplace ou complète l'histoire générée, avec bornes et repli sur le gabarit.
  - Accepté si : sans RadioSurvivor, aucun appel ni erreur.
  - Tests : banc.
  - Preuve : banc `tests/test_lk_api.py` du 2026-10-12 (48 tests OK dont `StoryEnrichTests` 6 : `API.enrichStory` borné et contrôlé par le serveur (600 caractères, 8 lignes, sans balises), gardé au registre privé avec la version du gabarit, réponse périmée refusée, `API.story` avec repli sur le gabarit, secrets jamais lus ni remplacés, sans RadioSurvivor aucun appel ni écriture) ; run_all 79/79 ; luacheck 16/0 ; `docs/api.md` (Histoires enrichies), `recits.md`
  - Reste : non vérifié dans la VM Kahlua (longueurs UTF-16, empreinte) ; aucun consommateur branché (`RS_LivingKnox.context`, `LK_Traces` lisent encore le gabarit ; branchement LLM côté carnet et pont à faire dans une tâche E) ; pas de contrôle de recopie d'un secret.

- [x] **LK10-T04** — Traces lisibles en jeu
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : LK10-T02
  - Fichiers : `LK_Homes.lua`
  - Faire : carnet ou notes dans le foyer, et sur le chef à sa mort, issus du journal.
  - Idées : I8.6 (foyer qui se raconte par son décor) (voir `docs/idees-bandits-alife.md`)
  - Accepté si : document lisible, une seule fois.
  - Tests : suite en jeu.
  - Preuve : banc `tests/test_lk_traces.py` du 2026-10-12 (23 tests OK : carnet `Base.Notebook` en lecture seule déposé une seule fois au foyer d'un groupe disparu (caisse, conteneur proche ou sol), feuille sur le chef à sa mort qui part avec le cadavre, contenu = résumé public de l'histoire et journal de récit, aucun secret ni coordonnée, marque persistante et rétablie, pages de 15 lignes) ; run_all 79/79 ; luacheck 16/0 ; conception `docs/conception/traces.md` ; **en jeu solo le 2026-10-12** : `RST.run({ suite = "lk.traces", tags = "world" })` OK (`Lua/batman_RadioSurvivor/tests/20261012-175834-solo.txt`)
  - Reste : Solo validé le 2026-10-12. essai solo `RST.run({ suite = "lk.traces", tags = "world" })` dans une maison avec meuble de rangement (2 PASS), puis lire le carnet (« Lire » proposé, pas de débordement) ; MP `RST.server(...)`. Largeur de 40 caractères à vérifier ; langue de l'autorité, pas de chaque lecteur ; les suites `lk.relief`/`lk.admin` peuvent laisser un carnet (`Traces.clear`) ; chef mort hors écran sans note ; dépôt interrompu jamais refait ; module hors VM Kahlua.

- [x] **LK10-T05** — Plus d'origines d'histoire
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK10-T01
  - Fichiers : `media/lua/shared/LivingKnox/Data/Stories.lua`, `tests/test_lk_stories.py`
  - Faire : enrichir les origines (au moins 6 de plus, réparties par type, FR et EN, Knox 1993) et, si besoin, les motivations compatibles, sans changer le tirage ; décision du 2026-10-10.
  - Accepté si : part des populations de 4 groupes qui partagent une origine nettement réduite (mesure `measure_origins.py` sur 1 000 mondes) ; cent tirages sans incohérence ; textes relus par l'utilisateur.
  - Tests : `test_lk_stories.py`, mesure de répartition.
  - Preuve : 12 origines et 3 motivations ajoutées sans changer le tirage (commit `2194dae`) ; populations de 4 groupes qui partagent une origine : 46,8 % → 25,8 % sur 1 000 mondes (25,5 % sur 4 000, `measure_origins.py`) ; `test_lk_stories.py` 14/14, `test_lk_population.py` 30/30 ; relecture de l’utilisateur le 2026-10-10 : 80 OK sur 80
  - Reste : non exécuté dans la VM Kahlua
