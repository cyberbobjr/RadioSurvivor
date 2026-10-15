# E05 — Les voix du réseau radio

**Objectif.** Passer d'une seule voix (Walt, 145,0 MHz) à un réseau de personnages radio hors carte, chacun avec sa fiche, sa fréquence, ses horaires et ses actions autorisées, éditables par l'admin sans redémarrage (note de travail §04).

**Dépend de.** E01 pour la validation en jeu. Indépendant des étapes Bandits!.

**Sources.** Note de travail §01 (décisions), §04 (fiche, édition par fichiers, distribution de départ), §02 (actions par personnage) ; `RadioSurvivor_Server.lua` (chaîne dynamique, file de diffusion, appel spontané) ; `bridge/radio_bridge.py`, `bridge/persona.txt` ; base `radio-dynamic.md` (chaîne de mod `OnLoadRadioScripts` + `AddChannel`, fréquence libre, chaîne secrète `removeChannelName`, plages des radios vanilla dont ondes courtes 10-25 MHz réservées aux postes haut de gamme, `getIsHighTier`, en solo seule la radio en main ou sur le dos reçoit une chaîne, une émission révèle la position de sa source aux clients en MP).

## Décisions

- 2026-10-11 — **E05-T12** : la langue des appels spontanés des voix est fixée par une **option sandbox** du serveur (liste de langues livrées par le mod), pour tous les joueurs.
- Acquises : fiches en fichiers côté serveur sous `Zomboid\Lua\batman_RadioSurvivor\personas\`, relues à chaud ; jamais en ModData globale ; six voix de départ (Walt, une infirmière, un déserteur, une famille assiégée, le chroniqueur, le passeur) ; panneau admin en jeu plus tard.
- 2026-10-09 — **Fréquence de Walt** (choix de l'utilisateur) : la **fiche** fait foi pour toutes les voix, Walt compris (fiche autoporteuse) ; l'option sandbox `RadioSurvivor.Frequency` est retirée ; migration unique : à la première copie de la fiche de Walt sur un serveur, une valeur sandbox différente de 145,0 y est recopiée.
- 2026-10-09 — ~~Fréquences des voix publiques~~ : **remplacée** le même jour par la décision « Fréquences tirées au hasard et découvertes par des notes » ci-dessous.
- 2026-10-09 — **E05-T04, les cinq voix** (choix de l'utilisateur, une voix à la fois, propositions documentées) : **infirmière** Darlene Pruitt (`darlene`), 115,6 MHz, écoute 07:00-10:00 et 16:00-19:00, lieu fixe clinique de West Point (11880,6878,0) ; **déserteur** Spc. Cody Haskins (`cody`), 17,4 MHz (ondes courtes), 22:00-03:00, mobile ; **famille assiégée** les Whitaker, voix de Jolene (`whitaker`), 81,4 MHz, 06:00-21:00, lieu `rescue`, livrée **silencieuse** (`state=silent`) jusqu'aux secours E12 ; **chroniqueur** « Night Owl » Lyle Ferrand (`nightowl`), 106,2 (FM) et 112,4 MHz, 19:00-22:00, hors carte (risque accepté : l'alerte d'urgence vanilla peut prendre 106,2) ; **passeur** Gus Lacombe (`gus`), 156,6 MHz (canal marine), 03:00-06:00, hors carte (risque accepté de collision avec Military Drop, à vérifier en E05-T06). Détails (connaissances, ignorances, secrets, ton) : propositions principales du document de travail reprises dans les fiches.
- 2026-10-09 — **Fréquences tirées au hasard et découvertes par des notes** (choix de l'utilisateur, après la collision du Night Owl avec l'alerte d'urgence vanilla) : **toutes les voix, Walt compris** (« Walt est un persona comme un autre, il n'a plus rien de spécial »), tirent leur fréquence au hasard à chaque **nouvelle partie**, dans une plage propre à chaque voix qui garde les mêmes radios capables de la joindre, en évitant toute fréquence déjà prise (chaînes vanilla dont l'alerte d'urgence, autres voix, autres mods) ; le tirage est mémorisé pour la partie (inchangé au redémarrage). **Plus aucune liste de fréquences n'est envoyée aux clients** et le menu « Réglez la radio sur … » disparaît : toute phrase dite dans une radio émettrice part au serveur avec la fréquence de la radio, et le serveur décide si une voix répond (quotas existants). Les joueurs découvrent les fréquences par des **notes** : des **documents lisibles** (moteur `printMedia` de 42.21 : papier manuscrit, carnet de radioamateur, prospectus… selon la voix), traduits FR/EN, portant la fréquence de la partie en cours, placés dans les **tables de butin** vanilla de lieux cohérents avec chaque voix, avec une rareté réglable en sandbox. Les fréquences fixes des fiches (décision E05-T04) deviennent les valeurs de repli ou des exemples ; les plages exactes sont fixées par la tâche `E05-T07`.
- 2026-10-09 — **Source unique des fiches** (remarque de l'utilisateur) : les fiches livrées n'existent qu'une fois, dans le mod (`Contents/mods/batman_RadioSurvivor/42.21/personas/`) ; `bridge/personas/` est supprimé ; le pont lit en jeu le dossier d'échange (inchangé) et, pour ses tests et son mode `--test`, le dossier du mod par chemin relatif ou option.
- 2026-10-09 — **Mise à jour des fiches installées** (choix de l'utilisateur) : le serveur mémorise l'empreinte de chaque fiche qu'il copie ; une fiche installée **non modifiée** par l'admin est remplacée par la nouvelle version livrée ; une fiche modifiée est gardée, avec un avertissement dans le journal.
- 2026-10-14 — **E05-T14** : canal séparé et règle de droits recopiée ; ni bouton ni contenu sans droit ; pas de rafraîchissement automatique, bouton « Actualiser » (confirmé par l'utilisateur).

## Hors périmètre

Carnet radio et module « Émettre » (E06), actions autres que `say` (E07), secours (E12), passeur (E13), chronique (E14).

## Tâches

- [x] **E05-T01** — Format de fiche personnage lisible par le pont et le serveur
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/persona-format.md` ; `bridge/personas/walt.txt` (exemple livré) ; `bridge/persona_store.py`
  - Faire : un fichier par voix, format ligne `clé=valeur` plus un bloc de texte libre pour le prompt (lisible par `getFileReader` en Lua, sans JSON) : identifiant, nom, langue, fréquences, radio requise (`any`, `high_tier`), horaires d'écoute, lieu (`none`, `fixed`, `rescue`), connaissances, secrets (jamais envoyés au client), actions autorisées et budgets, état (`active`, `silent`, `gone`, `dead`). Validation stricte avec messages d'erreur.
  - Accepté si : une fiche invalide est refusée avec la ligne fautive ; Walt actuel est entièrement décrit par sa fiche.
  - Tests : `tests/test_personas.py` (Python) et lecture Lua dans `lupa`.
  - Preuve : `docs/persona-format.md` (en-tête `clé=valeur` + bloc `[prompt]`, champs, valeurs admises, défauts, secrets jamais envoyés au client) ; `bridge/persona_store.py` et `server/RadioSurvivor/RS_Persona.lua` (validation stricte, même message et même ligne des deux côtés) ; `bridge/personas/walt.txt` décrit exactement le Walt actuel ; `tests/test_personas.py` (52 cas lus par Python et par le Lua du mod), 7 cas dans la VM Kahlua, `tests/run_all.py` 22/22 le 2026-10-09 ; E04-T06 : commit `51d8b21`
  - Reste : —

- [x] **E05-T02** — Chargement et rechargement à chaud des fiches côté serveur
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E05-T01
  - Fichiers : `media/lua/server/RadioSurvivor/RS_Personas.lua` ; `RadioSurvivor_Server.lua`
  - Faire : au démarrage, copier les fiches livrées dans le dossier d'échange si absentes (sans écraser celles de l'admin) ; relire toutes les N secondes réelles ; une chaîne dynamique par voix active ; voix `silent` ou `gone` sans réponse ; fréquences en conflit refusées et journalisées.
  - Accepté si : modifier une fiche change le comportement sans redémarrer ; une fréquence prise est signalée.
  - Tests : banc `lupa` (lecture, conflit, rechargement) ; suite en jeu `rs.personas`.
  - Preuve : `RS_Personas.lua` (fiches livrées hors de `media/` et copiées une fois dans `Zomboid/Lua/batman_RadioSurvivor/personas/`, relecture toutes les 30 s, une chaîne par fréquence servie, changement de fréquence par `RemoveChannel` + `AddChannel`, états `silent`/`gone`/`dead`, conflits et fiches invalides journalisés), Walt piloté par sa fiche, option sandbox `Frequency` retirée (migration impossible : valeur illisible une fois l'option retirée, note à l'admin dans le journal) ; `tests/test_personas_server.py` 40/40, `test_kahlua.py` 15/15, `tests/run_all.py` 23/23 le 2026-10-09 ; serveur dédié de test rejoué par moi après correction : 48 tests, 45 PASS, 3 SKIP, aucune erreur Lua, fiche de Walt copiée et chaîne créée sur 145,0 ; E05-T01 : commit `b8eef54` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo-retry rs.personas 6/6 dont la chaîne créée après le chargement reçue par un talkie en main (`20261013-205100-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.personas 5 PASS + 1 SKIP, rs.personas.update 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`)
  - Reste : en jeu solo : protocole `docs/tests-en-jeu.md` § 13 (changement de fréquence à chaud, `silent`, `gone`, fiche invalide) et suite `rs.personas` ; ⚠ réception d'une chaîne créée après le chargement à vérifier ; un serveur qui avait changé la fréquence de Walt doit la reporter dans la fiche ; liste des fréquences annoncée aux clients : à décider avec E05-T03 ; la campagne MP automatique passe (2026-10-14) ; restent pour la séance finale les contrôles à deux joueurs actifs et à la main ci-dessus

- [x] **E05-T03** — Routage par voix, mémoire par voix et quotas
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E05-T02
  - Fichiers : `RadioSurvivor_Server.lua` ; `RadioSurvivor_Const.lua` ; `bridge/radio_bridge.py` ; `docs/protocole-carnet-v2.md`
  - Faire : la fréquence de la radio de l'appelant désigne la voix ; la demande porte l'identifiant de voix ; historique par partie et par voix ; prompt construit depuis la fiche (secrets exclus des réponses) ; budget par voix en plus du plafond global ; radio haut de gamme exigée si la fiche le dit ; horaires d'écoute respectés (hors horaire : silence ou parasites).
  - Accepté si : deux voix répondent sur leurs fréquences sans mélanger leurs historiques ; Walt fonctionne comme avant.
  - Tests : `test_protocol.py` étendu (deux voix, horaire, radio basse gamme refusée).
  - Preuve : routage décidé par le serveur (fréquence de la radio de l'appelant, contrôlée par les bornes de réglage de la radio, voix qui tient la chaîne), champ `voice=` ajouté au contrat Lua ↔ Python (`docs/protocole-carnet-v2.md`, compatible avec un pont antérieur), pont : fiches lues dans le dossier d'échange, historique par voix (celui de Walt conservé sans migration), prompt construit depuis la fiche avec secrets à ne jamais révéler et garde-fou sur une citation mot pour mot, budget par voix en plus du plafond global, radio haut de gamme et horaires respectés par le silence ; fréquences de toutes les voix publiques (décision) ; `tests/test_protocol.py` (deux voix en MP simulé, pont seul), `test_personas_server.py` 47/47, `tests/run_all.py` 23/23 le 2026-10-09 ; serveur dédié de test 45 PASS / 3 SKIP ; E05-T02 : commit `09d7474`
  - Reste : en jeu (protocole `docs/tests-en-jeu.md` § 13 avec une fiche d'essai) à faire avec E05-T06 ; ⚠ une paraphrase d'un secret n'est pas détectée ; fiche déjà invalide au démarrage du pont : seule la version du serveur reste valide

- [x] **E05-T04** — Noms, lieux et fréquences des cinq nouvelles voix
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E05-T01
  - Fichiers : ce fichier ; `bridge/personas/*.txt`
  - Faire : proposer pour chaque voix un nom, une fréquence (dont au moins une en ondes courtes pour le déserteur), des horaires et un lieu de la carte vanilla (base `knox-geography.md`) ; faire valider, puis écrire les fiches.
  - Questions : pour chaque voix, une proposition principale et deux variantes, plus une réponse libre (une voix à la fois).
  - Accepté si : six fiches valides ; aucune fréquence en conflit avec une chaîne vanilla.
  - Tests : validation des fiches (E05-T01).
  - Preuve : décision de l'utilisateur du 2026-10-09 (section Décisions) ; cinq fiches `darlene`, `cody`, `whitaker` (silencieuse), `nightowl`, `gus` dans `bridge/personas/` et copiées à l'identique dans le mod ; validées par le pont et le lecteur Lua, ids et fréquences distincts, aucune fréquence vanilla (`tests/test_personas.py` `DeliveredVoicesTests`, `test_personas_server.py` `DeliveredVoicesServerTests`), `tests/run_all.py` 23/23 le 2026-10-09 ; serveur dédié de test : six voix chargées, chaînes sur 17,4, 115,6, 156,6, 112,4, 145,0 et 81,4, aucune erreur Lua ; E05-T03 : commit `4c17fc0`
  - Reste : 106,2 du Night Owl prise par l'alerte d'urgence vanilla dès le premier monde de test (risque accepté, repli sur 112,4 vérifié) ; phrase d'exemple de Gus ajustée (pas de passagers) à valider ; réponses réelles du LLM et collision avec Military Drop en E05-T06

- [x] **E05-T05** — Appels spontanés par voix
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E05-T03
  - Fichiers : `RadioSurvivor_Server.lua` ; fiches (fréquence d'appel)
  - Faire : généraliser l'appel général de Walt (une chance sur trois par heure de jeu si personne ne parle) à chaque voix, avec sa propre fréquence et ses horaires ; textes générés par le LLM avec secours fixe ; plafond commun.
  - Accepté si : aucun appel hors horaire ; le plafond horaire global n'est jamais dépassé.
  - Tests : banc `lupa` ; suite en jeu.
  - Preuve : 2026-10-09 : appel spontané par voix active (`call_one_in`, horaires `listen`, une voix au plus par heure), plafond `MaxPerHour` commun aux réponses et aux appels, texte LLM (`kind=radio_call`) avec secours fixe `call_text` après 30 s, composé côté serveur (`Translator.loadFiles` si clé absente) ; darlene/cody 6, gus 8 ; banc : simulation 30 jours six voix, plafond jamais dépassé, pont absent ou antérieur ; `tests/run_all.py` 23/23 ; serveur dédié de test 45 PASS / 3 SKIP ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.calls 2/2 (appel forcé à l'heure pleine, silence hors des heures d'écoute) (`20261013-202155-solo.txt`)
  - Reste : essai solo (`docs/tests-en-jeu.md` § 13, appels spontanés) ; langue de l'appel = celle du serveur en MP (à valider à la séance MP).

- [x] **E05-T06** — Validation du réseau en solo puis en multijoueur
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E05-T04, E05-T05
  - Fichiers : protocole dans `docs/validation/`
  - Faire : chaque voix sur sa fréquence, radio basse et haut de gamme, horaires, rechargement d'une fiche pendant la partie, deux joueurs sur deux voix différentes.
  - Accepté si : suites et protocole passés.
  - Tests : `RST.run('rs.voices')`, `RST.server('rs.voices')`.
  - Preuve : 2026-10-09 : suites `rs.voices` (serveur, lecture seule, 5 tests) et `rs.voices.world` (partie `rstest*` : routage par voix, `high_tier`, rechargement à chaud) ; protocole `docs/validation/E05-reseau-voix.md` (solo 8 étapes, MP 8 étapes) ; `tests/test_rs_suites.py` 31/31 (défauts injectés détectés) ; `tests/run_all.py` 24/24 ; serveur dédié de test 50 PASS / 3 SKIP, `rs.voices` 5/5 sur l'API réelle ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.voices 5/5, rs.voices.world 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.voices 5/5, rs.voices.world 3/3 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : deux joueurs sur deux voix différentes, chacun reçoit la réponse de sa voix

- [x] **E05-T07** — Fréquence de chaque voix tirée au hasard par partie, sans conflit
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E05-T04
  - Fichiers : `docs/persona-format.md` ; `bridge/persona_store.py`, `RS_Persona.lua`, `RS_Personas.lua` ; les six fiches ; état de partie côté serveur
  - Faire : champ de fiche pour une **plage** de tirage (au pas de 0,2 MHz) à la place ou en plus d'une fréquence fixe ; tirage à la première installation d'une nouvelle partie, mémorisé dans un fichier serveur propre à la partie (monde neuf détecté, base `multiplayer.md`) ; refus des fréquences déjà prises (chaînes vanilla dont l'alerte d'urgence, autres voix, autres chaînes de mods) avec nouveau tirage ; plages des six voix choisies pour garder les mêmes radios capables de les joindre ; le pont reçoit la fréquence tirée.
  - Accepté si : deux nouvelles parties donnent des fréquences différentes ; un redémarrage les conserve ; aucune collision avec l'alerte d'urgence ni entre voix.
  - Tests : banc ; serveur dédié de test (deux mondes) ; essai solo.
  - Preuve : champ `frequency_range` (Python et Lua, mêmes messages), plages des six voix gardant les mêmes radios (Walt 130,0-149,8 ; Darlene 115,0-129,8 ; Whitaker 75,0-87,8 ; Cody 10,0-24,8 ; Night Owl 88,0-107,8 et 109,0-114,8 ; Gus 150,2-199,8), tirage au monde neuf (`OnLoadRadioScripts` second argument), fréquences prises exclues (AEBS comprise) et 1,0 MHz entre voix, mémoire dans un fichier serveur propre à la partie ; `test_personas.py` 19/19, `test_personas_server.py` 65/65, `test_kahlua.py` 16/16, `tests/run_all.py` 23/23 le 2026-10-09 ; serveur dédié de test : deux mondes neufs aux fréquences toutes différentes, relance du premier aux mêmes fréquences, aucune collision avec l'AEBS (95,2 et 94,4) ; E05-T04 : commit `24832ea` ; **en jeu solo le 2026-10-10** (partie `rstest-1010`, retour de l’utilisateur) : fréquences tirées par partie (fichier `frequencies-…`), appel réussi sur 142,6 MHz
  - Reste : essai solo ; ⚠ une installation existante garde ses anciennes fiches copiées (fréquences fixes) : à remplacer à la main ou par une mise à jour automatique à décider ; collision avec Military Drop à vérifier en E05-T06 ; fréquences encore envoyées aux clients jusqu'à E05-T08

- [x] **E05-T08** — Plus de liste de fréquences chez les clients : le serveur trie
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E05-T03
  - Fichiers : `RadioSurvivor_Client.lua`, `RadioSurvivor_Server.lua`, `RadioSurvivor_Const.lua`, traductions
  - Faire : retirer l'envoi de la liste des fréquences aux clients et le menu « Réglez la radio sur … » ; toute phrase dite dans une radio émettrice part au serveur avec la fréquence de la radio ; le serveur répond seulement si une voix tient cette fréquence, sans révéler les autres ; quotas existants.
  - Accepté si : aucun client ne reçoit de fréquence de voix ; une phrase sur une fréquence de voix obtient sa réponse, ailleurs rien ; aucune charge excessive.
  - Tests : `test_protocol.py` ; essai solo.
  - Preuve : 2026-10-09 : liste des fréquences et menu « Réglez la radio sur … » retirés ; toute phrase sur une radio émettrice part avec sa fréquence (5 s minimum côté client, 15 phrases/minute par joueur côté serveur) ; refus visibles jugés avant la fréquence, silence sinon (sans demande au pont ni plafond) ; noms de chaînes retirés (`removeChannelName`) ; `test_protocol.py` scénario `scenario_server_sorts` (deux clients, aucune fréquence reçue) ; `tests/run_all.py` 23/23 ; serveur dédié de test 45 PASS / 3 SKIP. Limite vanilla : le paquet `WaveSignal` porte la fréquence à toutes les connexions (client modifié). ; **en jeu solo le 2026-10-10** (partie `rstest-1010`, retour de l’utilisateur) : talkie en main réglé sur la fréquence d’une voix, la voix répond (le serveur trie)
  - Reste : essai solo (`docs/tests-en-jeu.md`, « Le serveur trie (E05-T08) ») ; test `rs.personas` « frequencies never published » à lancer en jeu (suite `world`).

- [x] **E05-T09** — Notes de fréquences : documents lisibles dans le butin
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E05-T07
  - Fichiers : scripts d'objets et traductions (`Print_Media.json` ou équivalent 42.21), distributions de butin, `sandbox-options.txt`
  - Faire : un ou plusieurs documents lisibles par voix (moteur `printMedia` : papier manuscrit, carnet de radioamateur, prospectus…), texte FR/EN avec la fréquence de la partie en cours (composée à la lecture côté client, base `api-42-21.md` et `quest-building-blocks.md`), placés dans les tables de butin vanilla de lieux cohérents avec chaque voix ; rareté réglable en sandbox.
  - Accepté si : en solo, on trouve en fouillant des notes de chaque voix, qui s'ouvrent par « Lire » et donnent la bonne fréquence de la partie ; texte traduit.
  - Tests : banc ; essai solo (lecture, langue, butin).
  - Preuve : 2026-10-09 : cinq documents `printMedia` (Walt, Darlene, Cody, Gus, Night Owl ; pas Whitaker, silencieuse), fréquence écrite par l'autorité dans la ModData de l'objet à l'`OnCreate`, texte composé côté client dans sa langue (FR/EN) ; 20 entrées de butin vérifiées par `distmatrix` ; option `NoteRarity` (Aucune/Rares/Normales/Fréquentes) ; `tests/test_notes.py` 23/23 ; `tests/run_all.py` 24/24 ; serveur dédié de test 45 PASS / 3 SKIP, `notes: 20 loot entries added` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.notes 6/6 (lecteur, fouille de conteneurs de ville) (`20261013-202155-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.notes 4 PASS + 2 SKIP solo (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`)
  - Reste : essai solo (`docs/tests-en-jeu.md` § 13, « Notes de fréquences ») dont `RST.run("rs.notes")`, rendu des documents et fouille réelle ; poids à régler en jeu (Gus peut-être rare) ; la campagne MP automatique passe (2026-10-14) ; restent pour la séance finale les contrôles à deux joueurs actifs et à la main ci-dessus

- [x] **E05-T10** — Fiches livrées en un seul exemplaire (dans le mod)
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E05-T07
  - Fichiers : `bridge/personas/` (supprimé), `bridge/persona.txt`, `bridge/radio_bridge.py`, `bridge/persona_store.py`, tests, docs
  - Faire : supprimer `bridge/personas/` ; le pont lit les fiches du dossier d'échange en jeu et, pour ses tests et `--test`, le dossier du mod par chemin relatif à son fichier ou option `--personas` ; retirer `bridge/persona.txt` (secours devenu inutile, la fiche de Walt étant toujours installée) ; corriger les annotations de type signalées par Pylance dans `persona_store.py`.
  - Accepté si : une seule copie de chaque fiche dans le dépôt ; tests au vert ; aucun avertissement Pylance dans `persona_store.py`.
  - Tests : `tests/run_all.py`.
  - Preuve : 2026-10-09 : `bridge/personas/` et `bridge/persona.txt` supprimés ; pont : dossier du mod par chemin relatif ou `--personas` ; pyright 0 erreur sur `persona_store.py` ; test « fiches livrées valides » ; `tests/run_all.py` 23/23.
  - Reste : —

- [x] **E05-T11** — Mise à jour des fiches installées non modifiées
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E05-T10
  - Fichiers : `RS_Personas.lua` ; fichier d'empreintes côté serveur ; docs
  - Faire : mémoriser l'empreinte de chaque fiche copiée ; au démarrage, remplacer une fiche installée dont le contenu correspond encore à l'empreinte mémorisée par la nouvelle version livrée ; garder une fiche modifiée par l'admin avec un avertissement ; installations antérieures sans empreinte : comparer aux versions livrées connues (au minimum la version précédente de chaque fiche) pour reconnaître une fiche non modifiée.
  - Accepté si : une installation antérieure à E05-T07 reçoit les fiches à plages ; une fiche modifiée par l'admin n'est jamais écrasée.
  - Tests : banc ; essai solo sur une partie existante.
  - Preuve : 2026-10-09 : empreintes Adler-32 dans `personas-fingerprints.txt` (`RSFP1`), versions livrées connues `KNOWN_DELIVERED` (24832ea, 09d7474, actuelles) ; banc : copie initiale, mise à jour, fiche modifiée gardée, installation antérieure reconnue, fiche inconnue intacte, fichier abîmé ignoré ; serveur dédié de test : mise à jour et conservation vérifiées au journal ; `tests/run_all.py` 23/23 ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : campagne solo rs.personas.update 3/3 (`20261013-202155-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.personas 5 PASS + 1 SKIP, rs.personas.update 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`)
  - Reste : essai solo sur une partie existante (fiches à fréquences fixes remplacées par les fiches à plages). Rappel : toute modification d'une fiche livrée impose d'ajouter son empreinte à `KNOWN_DELIVERED` ; la campagne MP automatique passe (2026-10-14) ; restent pour la séance finale les contrôles à deux joueurs actifs et à la main ci-dessus

- [x] **E05-T12** — Langue des appels spontanés d’une voix
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E05-T05
  - Fichiers : `RadioSurvivor_Server.lua` (`callText`, `authorityLanguage`), pont
  - Faire : constaté en jeu le 2026-10-11 : les appels spontanés partent dans la langue du serveur (jeu en anglais) alors que le joueur parle français à la voix ; décider la langue d’un appel spontané puis l’appliquer.
  - Accepté si : décision consignée puis langue appliquée
  - Tests : banc
  - Preuve : décision du 2026-10-11 appliquée : option sandbox `RadioSurvivor.CallLanguage` (`enum`, défaut « langue du serveur », anglais, français ; langues livrées par le mod), libellés EN/FR ; `Const.callLanguage()` lue à chaque appel (`getOptionByName`, repli `SandboxVars`), demande `radio_call` en `language=` choisie, réponses aux joueurs inchangées ; pont inchangé (`call_situation` lit déjà `language`) ; `test_personas_server.py` 106 (`test_call_language_option`, `test_call_language_leaves_player_answers_alone`) ; `run_all.py` 44/44 le 2026-10-11, luacheck 17/0 et 0 ; `README.md`
  - Reste : en jeu solo : option « French » sur un jeu en anglais → appel spontané de Walt en français (requests.txt language=FR) ; sans pont, texte de repli dans la langue du serveur (getText sans autre langue en 42.21)

- [x] **E05-T13** — Journal complet du pont en mode debug
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E05-T12
  - Fichiers : `bridge/radio_bridge.py`, `README.md`
  - Faire : demande de l'utilisateur le 2026-10-11 : en mode `--debug`, journaliser en entier ce que le pont reçoit et envoie (demandes du jeu lues, messages envoyés au LLM, réponse brute du LLM, réponse écrite pour le jeu, acquittements) ; jamais la clé d'API ; sans `--debug`, journal inchangé.
  - Accepté si : avec `--debug`, chaque échange est lisible de bout en bout dans le terminal ; aucune clé d'API ; journal normal inchangé
  - Tests : banc
  - Preuve : `bridge/radio_bridge.py` avec `--debug` : demandes et acquittements lus (champs RSV2 décodés, `readable_record`), messages complets envoyés au LLM (en ligne et hors ligne), réponse brute complète de l'API, corps complet d'une erreur HTTP, réponses écrites pour le jeu (`debug_dump`) ; jamais la clé ni les en-têtes ; sans `--debug` rien ne change ; `README.md` (avertissement : prompts et dialogues dans le journal) ; `test_protocol.py` `scenario_debug_journal` (en processus et pont réel `--offline --debug` : tout présent, aucune clé, sortie vide sans `--debug`) ; `run_all.py` 44/44 le 2026-10-11
  - Reste : —

- [x] **E05-T14** — Bouton de debug : fréquences de toutes les voix de la partie
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E05-T07
  - Fichiers : `RS_Personas.lua` (lecture), vue client nouvelle
  - Faire : un bouton dans le panneau debug vanilla (comme « Living Knox - PNJ », LK13-T14) ouvre une fenêtre qui liste chaque voix de RadioSurvivor (nom, état actif ou silencieux, fréquence(s) tirée(s) pour cette partie, plages, radio requise, horaires) et les autres fréquences du mod (chroniqueur, chaînes propres) ; lecture seule.
  - Décisions (2026-10-12, utilisateur) : « rajoute un bouton debug dans le panneau debug pour afficher toutes les fréquences de RadioSurvivor car les fréquences sont aléatoires et je n'ai pas envie de chercher un document donnant les fréquences » ; mêmes droits que les outils de debug LK13-T13 (mode debug en solo, capacité `PopmanManage` en MP, revérifiés par l'autorité) : les fréquences sont un secret de partie, jamais envoyées à un non-autorisé.
  - Accepté si : fenêtre fidèle aux fréquences en usage ; refus sans donnée d'un non-autorisé ; aucun envoi fenêtre fermée.
  - Tests : banc ; suite en jeu.
  - Preuve : banc `tests/test_rs_freqdebug.py` du 2026-10-12 (23 tests OK : bouton « Radio Survivor - Fréquences » ajouté au panneau debug vanilla sans retirer les autres ; fenêtre en lecture seule (tableaux `LK_Table.lua`) : voix (id, nom, état, fréquences de la partie, plages ou « fixe », radio requise, heures d'écoute, rôle, « pas à l'antenne »), bulletin du soir (voix, fréquence, `ChronicleHour`) ; canal `RadioSurvivorDebug` `freqRequest`/`freqReply` au seul demandeur, appel direct en solo ; droits recopiés de `LK_Admin.isAllowed` (comparés sur 96 cas), revérifiés à chaque requête ; refus `denied` sans donnée ; aucun envoi fenêtre fermée) ; `RS_FreqDebug.lua`, `RS_FreqDebugView.lua`, clés `IGUI_RS_FreqDebug_*` EN/FR ; suite `rs.freqdebug` ; run_all 100/100 ; luacheck 16/0 ; `docs/persona-format.md`, `docs/tests-en-jeu.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.freqdebug 3/3 (`20261013-092308-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.freqdebug 3/3 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.freqdebug 3/3 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : client `user` sans bouton ni donnée, ligne `frequency debug: WARNING: request refused` ; contenu de la fenêtre (6 voix, Whitaker silencieuse, Night Owl chroniqueur, bulletin, Walt sur la fréquence affichée) abandonné (règle du 2026-10-14 : jugé à l'œil, fidélité vérifiée par `rs.freqdebug`). Rechargement seul de `LK_DebugView.lua` en jeu : bouton perdu jusqu'au redémarrage ; `RS_Env` non mis à jour.
