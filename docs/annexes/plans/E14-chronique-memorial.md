# E14 — La chronique du serveur et le mémorial

**Objectif.** Chaque soir de jeu, le chroniqueur diffuse sur sa station pirate un bulletin fondé sur les faits confirmés du serveur, et termine par les noms des morts du jour (note de travail §06).

**Dépend de.** E05 (voix du chroniqueur).

**Sources.** Note de travail §06 ; spécification « Liens avec les fonctionnalités déjà retenues » (le chroniqueur ne raconte que les événements confirmés et autorisés, pas les conversations privées) ; base `multiplayer.md` (`OnCharacterDeath` côté serveur) ; base `power-and-lights.md` (coupures d'électricité et d'eau) ; base `radio-dynamic.md` (cadence d'antenne, diffusion).

## Décisions

- Acquises : un bulletin par soirée de jeu à une heure réglable dans le sandbox ; tout le monde peut être nommé ; sources : morts, sauvetages, missions, passages du passeur, coupures, météo ; jamais de position exacte d'une base, seulement quartier ou ville.
- 2026-10-18 — **E14-T04** (retour de l'utilisateur : « None None » lu au mémorial, voix qui annonce ne pas donner les noms puis les lit) : un animal n'est jamais une mort du mémorial ; la consigne de l'IA annonce le mémorial au lieu d'interdire les noms (correctifs directs, confirmé par défaut).
- 2026-10-14 — **E14-T01** : lieu arrondi à la ville (pas au quartier, faute de table lisible sans charger) ; sans bulletin, fait gardé jusqu'à la fin du jour suivant ; nouveaux groupes Living Knox inclus (3 par jour) (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E14-T02** : 20 h par défaut, diffusé même hors des heures d'écoute de la fiche (confirmé par l'utilisateur) ; langue du pont = `CallLanguage` ; chroniqueur `nightowl` fixé dans le code, hors plafond horaire et budget de la voix ; 60 s d'attente ; 12 faits (pont), 5 (secours) (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E14-T03** : noms dits une seule fois par le mémorial (le pont ne reçoit que leur nombre) ; noms seuls, sans lieu ni heure ; position après le texte du pont ou avant la clôture du secours ; personnages joueurs seulement (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **E14-T01** — Journal des faits du serveur
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Facts.lua`
  - Faire : collecte bornée des faits du jour : morts de joueurs (`OnCharacterDeath`), missions closes, secours, passages, coupures, météo ; lieux arrondis au quartier ou à la ville ; aucun contenu de conversation privée.
  - Accepté si : la journée est purgée après le bulletin ; aucune coordonnée précise dans le journal.
  - Tests : banc `lupa` ; suite serveur.
  - Preuve : banc `tests/test_facts.py` du 2026-10-12 (9 tests OK : morts de joueurs, missions closes, coupures d'électricité et d'eau sondées, météo marquante, faits publics Living Knox ; lieu arrondi à la ville sans coordonnée ; sortes et champs fermés ; bornes (80 faits, plafond par sorte et par jour) ; état privé `RS_State`, jamais en ModData globale ; `list`/`purge` pour le bulletin) ; suite `rs.facts` 6/6 sous lupa ; run_all 80/80 ; luacheck 16/0 ; conception `docs/annexes/conception/chronique.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.facts 7/7 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.facts 7/7 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : mort réelle d'un client consignée sur le serveur dédié (lieu en ville sans chiffres). Secours (E12-T04/05) et passages du passeur (E13) seulement réservés ; une coupure déjà en place au premier sondage n'est pas un fait.

- [x] **E14-T02** — Bulletin du soir
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E14-T01, E07-T01
  - Fichiers : `RS_Facts.lua` ; option sandbox `RadioSurvivor.ChronicleHour` ; pont
  - Faire : à l'heure réglée, demande au pont avec les faits du jour ; texte borné diffusé sur la fréquence du chroniqueur ; sans pont, bulletin de secours fixe construit à partir des faits.
  - Accepté si : un bulletin par soirée, même sans pont ; aucun fait inventé (le prompt l'interdit et le serveur ne fournit que des faits).
  - Tests : banc `lupa` ; suite en jeu (heure forcée).
  - Preuve : banc `tests/test_bulletin.py` du 2026-10-12 (12 tests OK : départ au sondage horaire de `RS_Facts` dès l'heure `RadioSurvivor.ChronicleHour` (0..23, défaut 20 h, jour des faits de 7 h à 7 h), un bulletin par soirée (`book.aired`, état privé), demande `kind=bulletin` (voix `nightowl`, au plus 12 faits en phrases construites par le serveur, jamais de coordonnée ni de secret), texte borné diffusé sur la fréquence du chroniqueur, secours traduit `IGUI_RS_Bulletin_*` après 60 s sans pont, faits purgés après diffusion, redémarrage avant diffusion redemandé, chroniqueur inactif ou parti) ; `RS_Facts.lua`, API `RS_RadioServer` de `RadioSurvivor_Server.lua`, `bridge/bulletin.py` ; `test_facts` 9 OK ; suite `rs.bulletin` ; run_all 97/97 ; luacheck 16/0 ; conception `chronique.md`, contrat `protocole-carnet-v2.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : RST.server rs.bulletin 2/2 (`20261013-112430-server.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.bulletin 2/2 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.bulletin 2/2 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : ⚠ bulletin de secours dans la langue du serveur ; noms des morts lus sans LLM : E14-T03.

- [x] **E14-T03** — Mémorial
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E14-T02
  - Fichiers : `RS_Facts.lua`
  - Faire : noms des personnages morts du jour lus à la fin du bulletin, sans texte du LLM pour cette partie.
  - Accepté si : chaque mort du jour apparaît une fois.
  - Tests : banc `lupa`.
  - Preuve : banc du 2026-10-13 : `tests/test_memorial.py` 6 OK (exécute aussi la suite `rs.facts` sous lupa), `tests/test_bulletin.py` 12 OK, `tests/test_facts.py` 9 OK : chaque personnage joueur mort depuis le bulletin précédent nommé une seule fois par le serveur, sans texte du LLM, à la fin du bulletin (ligne d'ouverture `IGUI_RS_Bulletin_Memorial` EN/FR, noms dans l'ordre des morts, lignes de 140 caractères au plus) ; le pont ne reçoit que le nombre de morts (`deathsText`), le secours ne raconte plus les morts ; morts lues purgées avec les faits ; `RS_Facts` : `split`, `deathsText`, `memorialLines` ; suite `rs.facts` (7 tests) ; luacheck 16/0 ; conception `chronique.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : RST.server rs.bulletin 2/2 (`20261013-112430-server.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.facts 7/7 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.facts 7/7 (test du mémorial), rs.bulletin 2/2 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : mort réelle d'un client puis bulletin : texte sans le nom, puis « One more thing… » et le nom une seule fois. Membres Living Knox non nommés ; lieu de la mort plus dit ; mémorial hors de la limite de 6 lignes.

- [ ] **E14-T04** — Mémorial : animaux exclus, consigne des noms sans contradiction
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : E14-T03
  - Fichiers : `RS_Facts.lua`, `tests/test_facts.py`, `tests/test_carnet.py`
  - Faire : `IsoAnimal` hérite d'`IsoPlayer` et déclenche `OnCharacterDeath` (descripteur « None None ») : `Facts.characterDeath` l'écarte par `isAnimal()`. `Facts.deathsText` ne dit plus « do not name them » (le modèle annonçait à l'antenne qu'il ne donnerait pas les noms, juste avant le mémorial) : il dit que la station lit les noms juste après, que la voix peut l'annoncer, sans jamais dire qu'elle ne les donnera pas ni nommer quiconque.
  - Accepté si : au banc, la mort d'un animal n'ajoute aucun fait ; en jeu, un animal tué n'apparaît pas au mémorial et le bulletin annonce les noms sans les refuser.
  - Tests : `tests/test_facts.py`, `tests/test_bulletin.py`, `tests/test_memorial.py`.
  - Preuve : `test_facts.py` 9 OK (animal `isAnimal` vrai : aucun fait), `test_bulletin.py` 14 OK, `test_memorial.py` 6 OK ; run_all 140/141 du 2026-10-18 (échec instable `mission_recover`, sans lien, vert seul 3 fois sur 3)
  - Reste : essai en jeu (animal tué, bulletin du soir suivant) ; le fait « None None » déjà enregistré dans la partie en cours a déjà été lu et ne revient pas
