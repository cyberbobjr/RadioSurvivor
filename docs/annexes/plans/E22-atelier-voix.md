# E22 — Atelier des voix

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** en cours — 11 / 17 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E22-T01 | Catalogue de l'atelier généré depuis le mod | `testé hors jeu` | hors jeu | — |
| ☑ | E22-T02 | Serveur de l'atelier et lanceurs | `testé hors jeu` | hors jeu | E22-T01 |
| ☑ | E22-T03 | Interface : voix, assistant en cinq étapes, aperçu | `testé hors jeu` | hors jeu | E22-T02 |
| ☐ | E22-T04 | Verdict du jeu affiché dans l'atelier | `testé hors jeu` | solo | E22-T03 |
| ☑ | E22-T05 | Exporter et importer une voix | `testé hors jeu` | hors jeu | E22-T03 |
| ☑ | E22-T06 | L'IA du pont aide à écrire et fait essayer la voix | `testé hors jeu` | hors jeu | E22-T03 |
| ☐ | E22-T07 | Note de fréquence et appel spontané écrits dans la fiche | `testé hors jeu` | MP | — |
| ☐ | E22-T08 | Relevé de lieux en jeu | `testé hors jeu` | MP | E22-T03 |
| ☐ | E22-T10 | Journal en direct dans l'atelier | `testé hors jeu` | solo | E22-T03 |
| ☑ | E22-T11 | Aide détaillée sur chaque réglage | `testé hors jeu` | hors jeu | E22-T03 |
| ☐ | E22-T12 | Stock du marchand sans poids à saisir | `testé hors jeu` | MP | E22-T07 |
| ☐ | E22-T13 | Toutes les voix se souviennent des appelants, sans oubli, morts compris | `testé hors jeu` | MP | E22-T12 |
| ☑ | E22-T14 | Fiches sans connaissances, ignorances ni secrets figés | `testé hors jeu` | hors jeu | E22-T13 |
| ☑ | E22-T15 | Atelier ouvert sur le réseau, protégé par un mot de passe | `testé hors jeu` | hors jeu | E22-T14 |
| ☑ | E22-T09 | Wiki et README de l'atelier | `testé hors jeu` | hors jeu | E22-T04, E22-T05, E22-T06, E22-T08, E22-T10, E22-T11, E22-T12, E22-T13 |
| ☑ | E22-T16 | Wiki de référence de l'atelier et exemples de voix | `testé hors jeu` | hors jeu | E22-T09 |
| ☑ | E22-T17 | Stock vendable, libellés neutres, ancienne version, lieux vérifiés | `testé hors jeu` | hors jeu | E22-T16 |

<!-- fin du tableau de bord -->

**Mod.** Le pont (`bridge/`) pour l'atelier ; RadioSurvivor (`batman_RadioSurvivor`) pour la note générique, l'appel
écrit dans la fiche et le relevé de lieux. Living Knox hors périmètre.

**Objectif.** Un adolescent crée, corrige, exporte, importe et supprime des voix radio (personnalité, missions,
récompenses, lieux, note de fréquence) dans un atelier simple ouvert dans son navigateur, sur Windows, Linux ou macOS,
sans jamais écrire une fiche à la main. Les lieux se relèvent en marchant dans le jeu.

**ADR.** [Atelier des voix](../../architecture/decisions/adr-atelier-voix.md) (accepté le 2026-11-15) ; ce plan en est
l'ordre de livraison et porte le suivi des tâches.

**Dépend de.** E20 (fiches à sections, registres des types de mission et des récompenses).

**Sources.** `docs/specifications-techniques/persona-format.md` ; `bridge/radio_bridge.py`, `bridge/persona_store.py` ;
maquettes de l'ADR.

## Décisions

- 2026-11-15 — **E22** (utilisateur) : solution D (atelier du pont et relevé en jeu), rester simple, l'IA du pont aide à
  rédiger, interface française et anglaise selon le navigateur (anglais à défaut), boutons Exporter et Importer ; une
  voix créée a sa note de fréquence et son texte d'appel écrits dans sa fiche.
- 2026-11-15 — **E22** (confirmé par défaut) : bibliothèque standard Python et JavaScript sans framework ; écoute sur
  `127.0.0.1` ; le jeu reste le seul juge d'une fiche, l'interface lit un catalogue généré depuis le mod (ADR D03) ;
  exporter = la fiche `.txt` elle-même.
- 2026-11-15 — **E22** (utilisateur) : le pont se lance comme avant, l'atelier
  est facultatif : `--atelier` l'ouvre en plus, dans le même programme ; lire
  les journaux en direct dans l'atelier, qui sert aussi d'administration en direct des voix (ADR D09, E22-T10).
- 2026-11-15 — **E22** : le wiki suit le code, comme en E20 ; chaque tâche visible du joueur met à jour `CHANGELOG.md`
  (Unreleased) dans son commit.

- 2026-11-16 — **E22-T15** (utilisateur) : l'atelier peut écouter sur le réseau (`--atelier-host`), protégé par
  `ATELIER_PASSWORD` ; chaque client se connecte, freins contre les essais en rafale, pas de HTTPS ni de comptes
  (ADR D11).
- 2026-11-16 — **E22-T16** (utilisateur) : une page du wiki dédiée à l'atelier, où chaque écran et chaque onglet est
  documenté pour un adolescent, et des exemples concrets de nouvelles voix (page 14).
- 2026-11-16 — **E22-T17** (utilisateur) : le stock d'un marchand ne propose que des objets vendables, libellés
  neutres, nom de la voix dans les confirmations, pastille « Ancienne version », captures isolées, lieux des exemples
  vérifiés sur la carte du jeu, règles de dépôt expliquées dans le wiki.

## Hors périmètre

- Hébergement en ligne, partage par un service, fiches de Living Knox.

## Tâches

- [x] **E22-T01** — Catalogue de l'atelier généré depuis le mod
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `tools/gen_atelier_catalog.py`, `bridge/atelier/catalog.json`, nouveau banc.
  - Faire : ADR D03. Lire les déclarations du mod (types de mission et leurs paramètres, natures de récompense,
    catégories de `_categories.txt`, actions des voix, clés d'en-tête, plages de fréquence des fiches livrées) et écrire
    un catalogue JSON que l'interface lit. Aucune règle recopiée à la main.
  - Accepté si : un banc échoue quand le catalogue n'est plus à jour du mod ; un type de mission ajouté au mod apparaît au
    catalogue sans autre changement.
  - Tests : `tests/run_all.py`.
  - Preuve : 2026-11-15 : `tools/gen_atelier_catalog.py` charge le lecteur réel par lupa (chargeur des bancs
    `tests/radiosurvivor/test_personas.LuaPersona`) et chaque `CoreAI/CA_Mission*.lua`, écrit `bridge/atelier/catalog.json`
    (missionTypes, setups, paramKinds, rewardKinds, skills, categories, header, sections, sheet, voices) ;
    `Persona.grammar(rules)` expose les tables des lecteurs de `RS_Persona.lua` (constantes sorties, sans changement de
    comportement), `Params.kinds()` dans `RS_PersonaParams.lua`. `python tests/radiosurvivor/test_atelier_catalog.py` : `Ran 3 tests`
    `OK` (catalogue à jour, rendu stable, faux gabarit repris sans changer le générateur) ; `test_persona_sections` 12,
    `test_personas` 20, `test_personas_server` 107, `test_mission_route` 15, `test_mission_item` 14, `test_kahlua` 40 :
    `OK` ; luacheck des deux fichiers : 0 avertissement. Suite complète non lancée (autre session en cours).
  - Reste : set-ups lus dans les sources (`registerDeclaredSetup('<champ>'`), faute d'accesseur de `RS_MissionVoice` ;
    le générateur dépend d'un banc pour son chargeur Lua.
- [x] **E22-T02** — Serveur de l'atelier et lanceurs
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T01
  - Fichiers : `bridge/atelier_server.py`, option `--atelier` de `bridge/radio_bridge.py`, `bridge/atelier.bat`,
    `bridge/atelier.sh`, `bridge/atelier.command`.
  - Faire : ADR D01, D02. Serveur HTTP local (`127.0.0.1`) : lister, lire, écrire, dupliquer, supprimer une fiche,
    revenir à la version livrée, vider une voix livrée ; dossier de travail trouvé comme le pont le trouve ; ouvre le
    navigateur.
  - Accepté si : bancs de chaque opération sur un dossier temporaire ; aucune écriture hors du dossier de travail ; refus
    d'un identifiant qui sortirait du dossier.
  - Preuve : 2026-11-15 : `bridge/atelier_server.py` (bibliothèque standard ; `VoiceStore` pour les fiches, écriture
    par fichier temporaire, adaptateur HTTP à table de routes ; 127.0.0.1, port 8765 puis les 9 suivants ; Host et
    Origin étrangers refusés), option `--atelier` et `--atelier-port` de `radio_bridge.py` (dossier de travail par
    `personas_folder`, fiches livrées par `BUNDLED_PERSONAS` ; le pont tourne aussi, et sans configuration de l'IA
    l'atelier reste ouvert seul), lanceurs
    `bridge/atelier.bat`, `atelier.sh`, `atelier.command` (LF imposé par `.gitattributes`). Réponses
    `{ok, code, message}` traduisibles. `python tests/radiosurvivor/test_atelier_server.py` : `Ran 21 tests` `OK` (15 passages de suite) ;
    `test_bridge_guards` 11 `OK` ; `test_protocol` sans échec ; lancement réel sur un dossier temporaire : 16 voix listées.
- [x] **E22-T03** — Interface : voix, assistant en cinq étapes, aperçu
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T02
  - Fichiers : `bridge/atelier/index.html`, `bridge/atelier/app.js`, `bridge/atelier/i18n/fr.json`,
    `bridge/atelier/i18n/en.json`.
  - Faire : ADR D05, maquettes B et D. Liste des voix ; nouvelle voix vide ou copiée d'une voix livrée ; étapes Qui,
    Où et quand, Ce qu'elle sait, Missions, Récompenses ; mots de joueur, listes tirées du catalogue ; aperçu de la fiche ;
    langue du navigateur, anglais à défaut.
  - Accepté si : une voix créée de bout en bout par l'interface est acceptée par le lecteur du jeu (banc lupa) ; capture
    de l'atelier en français et en anglais.
  - Preuve : 2026-11-15 : `bridge/atelier/` en modules ES sans framework ni CDN : `sheet.js` (lecture et écriture de la
    syntaxe, commentaires et clés inconnues gardés), `values.js`, `voice.js`, `catalog.js`, `checks.js` (contrôles légers
    tirés du catalogue, registre par genre de paramètre, jamais bloquants), `i18n.js` et `i18n/{fr,en}.json`, une étape
    par fichier dans `steps/`, `app.js`. `python tests/radiosurvivor/test_atelier_ui.py` : `Ran 7 tests` `OK` (16 fiches livrées
    relues et réécrites à l'identique ; voix construite de zéro acceptée par le vrai `RS_Persona.readFile` et par
    `persona_store` ; clés de traduction complètes dans les deux langues). Navigateur (Playwright, `tools/atelier_smoke.py`,
    code 0) : voix créée par les cinq étapes en français puis en anglais, enregistrée, acceptée par le lecteur du jeu,
    `summary: OK (2 locales, 0 failure(s))`, sans défilement horizontal à 800 px.
  - Reste : bandes des voix du joueur non prises en compte par « Trouver une bande libre » ; champs bruts pour `[trade]`
    et `[note]` ; identifiants de lieux et de missions non renommables.
- [ ] **E22-T04** — Verdict du jeu affiché dans l'atelier
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : E22-T03
  - Faire : ADR D03. Lire les refus `personas: ERROR: ... refused, line N` de `console.txt` (et du journal du serveur
    dédié) et les montrer à la voix et à la section fautives, avec un bouton qui y mène.
  - Accepté si : en jeu solo, une fiche fautive écrite par l'atelier est signalée dans l'atelier avec sa ligne, puis
    disparaît de la liste des erreurs une fois corrigée.
  - Preuve : 2026-11-15 (hors jeu) : `bridge/game_console.py` (`ConsoleTail` suit `console.txt`, fichier absent ou
    réécrit toléré ; verdict par fiche tiré d'une table d'événements), route `GET /api/verdicts`, option `--game-log` ;
    `atelier/verdict.js` (bandeau en mots simples et message brut, bouton vers l'étape fautive par `sheet.js locate`),
    pastille rouge dans la liste. `python tests/radiosurvivor/test_atelier_log.py` : `Ran 19 tests` `OK` ; navigateur
    (`tools/atelier_smoke.py`, code 0) : refus ligne 6 affiché, saut à l'étape « Où et quand ».
  - Reste : validation en jeu solo (jeu pris par une autre session le 2026-11-15).
- [x] **E22-T05** — Exporter et importer une voix
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T03
  - Faire : ADR D06. Exporter télécharge la fiche ; importer l'accepte par glisser-déposer ou sélection, propose un
    nouvel identifiant si la voix existe.
  - Accepté si : bancs export puis import identiques ; conflit d'identifiant résolu sans écraser.
  - Preuve : 2026-11-15 : routes `export` et `import` de `atelier_server.py` (bancs de `test_atelier_server.py`) ;
    boutons Exporter et Importer (sélection ou glisser-déposer, nouvel identifiant demandé dans la page sur
    `voice_exists`) ; navigateur : export identique et réimport sous un nouvel identifiant en français et en anglais.
- [x] **E22-T06** — L'IA du pont aide à écrire et fait essayer la voix
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T03
  - Faire : ADR D04. Rédiger la personnalité en anglais depuis quelques phrases, proposer l'histoire d'une mission,
    conversation d'essai avec le prompt construit comme le pont le construit ; plafonds de coût du pont ; boutons grisés
    sans fournisseur.
  - Accepté si : bancs avec le faux LLM du pont ; aucun appel sans fournisseur configuré.
  - Preuve : 2026-11-15 : `bridge/atelier_ai.py` (requêtes de l'atelier, LLM injecté) et `atelier_ai_templates.json`
    (consignes en données) ; `radio_bridge.voice_turn` construit le prompt et appelle le LLM à l'identique pour le jeu et
    pour l'essai ; `WorkshopLLM` passe par `call_llm` (mêmes plafonds), journal des jetons `source=workshop` ; route
    `POST /api/ai/<kind>` (personality, story, try ; 503 `ai_unavailable` sans IA) ; interface `atelier/ai.js` (panneau
    de personnalité, bouton Proposer des missions, tiroir « Essayer la voix » sur le texte non enregistré).
    `test_atelier_ai` `Ran 9 tests` `OK` (faux LLM, plafond 413, dossier de travail inchangé) ; `test_fake_llm` 27,
    `test_bridge_guards` 11, bancs de l'atelier `OK`, `test_protocol` sans échec ; navigateur : `summary: OK`.
  - Reste : jamais essayé avec un vrai fournisseur (aucun appel payant).
- [ ] **E22-T07** — Note de fréquence et appel spontané écrits dans la fiche
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : —
  - Faire : ADR D07. Note manuscrite générique du mod dont le texte et les lieux de butin viennent de la fiche ; texte
    d'appel écrit dans la fiche ; voix livrées inchangées. Format et wiki mis à jour.
  - Accepté si : en multijoueur, une voix créée sans objet propre a sa note trouvée dans le butin, lisible chez le
    joueur, et son appel spontané diffusé.
  - Preuve : 2026-11-15 (hors jeu) : `[note]` accepte `text=` (une ligne par ligne, `%1` = fréquence, 8 lignes de 40
    octets, sans `<`, `>`, `^`, `%` seul) à la place de `item=` et `key=` : objet générique `RadioSurvivor.NoteVoice`,
    texte et fréquence posés en ModData par l'autorité, page composée chez le client (`RS_Notes.lua`) ; en-tête `call=`
    (texte écrit, exclusif de `call_text`) ; lecteur du pont aligné ; format, notes de fréquence, wiki et CHANGELOG à
    jour ; atelier : bloc « appel spontané » et `text` dans le panneau Note. `test_notes` 33, `test_personas` 20,
    `test_persona_sections` 12, `test_personas_server` 107, `test_kahlua` 40, `test_translations_split` 7, bancs de
    l'atelier `OK` ; `protocol`, `rs_suites`, luacheck et `check_case` `PASS`. Suite en jeu `rs.notes.written` écrite.
  - Reste : campagne MP `rs.notes.written` (pont arrêté) ; rendu réel de la page ; note trouvée dans un vrai conteneur.
- [ ] **E22-T08** — Relevé de lieux en jeu
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E22-T03
  - Faire : ADR D08. Clic droit « Atelier des voix : relever ce lieu » (case, conteneur, bâtiment) en solo ou par un
    admin ; fichier de relevés dans le dossier de travail ; liste « Lieux relevés » dans l'atelier, ajout à une voix.
  - Accepté si : en multijoueur, un admin relève une benne, l'atelier sur la machine du serveur la propose comme
    planque ; un joueur non admin n'a pas le menu.
  - Preuve : 2026-11-15 (hors jeu) : `RS_PlaceSurveyMenu.lua` (clic droit « Atelier des voix : relever ce lieu », solo ou
    admin `CA_AdminAccess`), `RS_PlaceSurvey.lua` (le serveur revérifie les droits, lit case, pièce, bâtiment et 4
    conteneurs au plus lui-même, écrit `workshop-places.txt`, 200 relevés gardés) ; `bridge/place_surveys.py`, route
    `GET /api/surveys`, bloc « Relevés en jeu » de l'atelier (nom et usages proposés, « Ajouter à cette voix »).
    `test_rs_place_survey` 15, `test_atelier_surveys` 12, bancs de l'atelier, `test_translations_split` 7,
    `test_mod_calls_api` 16, `test_kahlua` 41 `OK` ; `rs_suites`, `rs_mp_suites` `PASS` ; luacheck 0 ; `check_case`
    `PASS` ; navigateur : relevé ajouté comme planque, voix acceptée par le lecteur du jeu. Suite `rs.placesurvey` écrite.
  - Reste : campagne MP (admin près d'une benne, non-admin refusé) ; atelier lancé sur le dossier du serveur.
- [ ] **E22-T10** — Journal en direct dans l'atelier
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : E22-T03
  - Fichiers : `bridge/atelier_server.py`, `bridge/radio_bridge.py` (fonction `log`), `bridge/atelier/`.
  - Faire : ADR D09. Le pont garde en mémoire ses dernières lignes de journal (taille bornée) et l'atelier les lit
    (`GET /api/log?since=`), avec les lignes `[RadioSurvivor] personas:` de `console.txt` ; onglet « Journal » : filtre par
    voix, par gravité, pause du défilement ; journal du pont présent dès que le pont tourne.
  - Accepté si : bancs du tampon et de la route ; en jeu solo, une phrase dite à une voix apparaît dans l'onglet avec sa
    réponse.
  - Preuve : 2026-11-15 (hors jeu) : `bridge/log_buffer.py` (tampon de 2000 lignes, `since`), `log()` du pont y écrit,
    identifiant de voix tiré des formats fixes des lignes du pont, jamais du texte du joueur ; nouvelle ligne
    `reply of voice '<id>': ...` ; lignes `personas:` du jeu dans le même journal ; route `GET /api/log?since=` ;
    `atelier/journal.js` (filtres voix, gravité, origine ; pause ; interrogation arrêtée quand la vue est cachée).
    `test_atelier_log` 19 `OK`, `test_atelier_server` 21, `test_atelier_ui` 7, `test_atelier_catalog` 3,
    `test_bridge_guards` 11 `OK`, `test_protocol` sans échec ; navigateur : ligne du pont et ligne du jeu affichées et
    filtrées.
  - Reste : validation en jeu solo ; une ligne du jeu porte l'heure de lecture par l'atelier.
- [x] **E22-T11** — Aide détaillée sur chaque réglage
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T03
  - Fichiers : `bridge/atelier/` (aide, traductions), banc.
  - Faire : demande de l'utilisateur du 2026-11-15. Chaque réglage et chaque choix possible (actions, radio, état,
    emplacement, usages d'un lieu, types de mission et leurs paramètres, récompenses, portée, troc, note) a une aide :
    à quoi il sert, ce que vit le joueur, les choix possibles, un exemple ; en français et en anglais ; aide ouverte au
    survol et au clavier. Format actuel des fiches seulement, aucune ancienne écriture (utilisateur, 2026-11-15).
  - Accepté si : un banc échoue quand un élément du catalogue n'a pas d'aide dans les deux langues ; capture.
  - Preuve : 2026-11-15 : `bridge/atelier/help.js` (bouton « ? » au survol, au clavier et au clic, bulle gardée dans
    l'écran ; parties à quoi ça sert, dans le jeu, choix, exemple, bon à savoir), branché dans les étapes et les
    formulaires ; 126 sujets `help.*` en français et en anglais tirés du wiki et du format des fiches ; avis déplacés en
    bas à droite. `python tests/radiosurvivor/test_atelier_help.py` : `Ran 5 tests` `OK` (chaque élément du catalogue a son aide dans
    les deux langues) ; autres bancs de l'atelier `OK` ; navigateur : bulle de « Livrer des affaires » et de « Confier
    des missions » visibles dans l'écran, `summary: OK (2 locales, 0 failure(s))`.
- [ ] **E22-T12** — Stock du marchand sans poids à saisir
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E22-T07
  - Fichiers : `RS_Persona.lua` (lecteur de `[trade]`), `RS_Trade*.lua`, les 11 fiches de marchands, `passeur-table.md`,
    `persona-format.md`, wiki, atelier (formulaire du stock).
  - Faire : demande de l'utilisateur du 2026-11-15. `item=Module.Type:quantité` sans poids : le serveur lit le poids dans
    le script de l'objet (liquide d'un récipient plein compris), aucune ancienne écriture gardée. Dans l'atelier, le
    stock est un formulaire (objet cherché par son nom, quantité de… à…, poids affiché pour information).
  - Accepté si : bancs du lecteur et du plafond de 20 kg avec les poids lus dans les scripts ; en multijoueur, un troc
    trop lourd est refusé et un troc normal livré.
  - Preuve : 2026-11-15 (hors jeu) : `RS_ItemWeights.lua` lit le poids dans le script de l'objet sans le créer
    (`ScriptManager.FindItem`, `Item.getActualWeight`, liquide initial d'un `FluidContainer` à 1 kg par litre ; sources
    42.22 citées dans le module), cache par type ; `item=Module.Type:quantité`, 3 parties et type inconnu refusés ; 11
    fiches de marchands sans poids, 57 types relus : écart nul avec les anciennes valeurs. Atelier : stock en formulaire
    (objet, de… à…). `test_rs_trade` 27, `test_rs_trade_run` 23, `test_rs_trade_traders` 14, `test_rs_trade_exchange`
    18, `test_rs_town_traders` 14, `test_personas` 20, `test_personas_server` 107, `test_persona_sections` 12,
    `test_kahlua` 41 `OK` ; `rs_suites` `PASS` ; luacheck 0 ; `check_case` `PASS`.
  - Reste : MP sur serveur dédié Linux : fiches chargées, contrepartie de plus de 10 kg refusée, troc normal livré.
- [ ] **E22-T13** — Toutes les voix se souviennent des appelants, sans oubli, morts compris
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : E22-T12
  - Fichiers : `RS_Persona.lua` (liste des actions), `RS_Memory.lua`, `RadioSurvivor_Const.lua`,
    `CA_NotebookServer` (mort d'un personnage), `bridge/persona_store.py`, `bridge/radio_bridge.py`, atelier (case
    « Se souvenir des appelants » retirée), format, protocole, wiki.
  - Faire : demandes de l'utilisateur du 2026-11-15 : « toutes les voix doivent se souvenir des appelants, et ce de façon
    permanente » ; « garder le souvenir de ceux qui sont morts pour donner plus de richesse au récit si quelqu'un parle
    d'un mort » ; « ouvrir la mémoire à 2000 caractères par joueur ». `remember` n'est plus une action à cocher : toute
    voix retient des faits sur un appelant. Mémoire de 2000 caractères par voix et par personnage, sans éviction de fait
    ni d'appelant ; une fois pleine, un nouveau fait est refusé et journalisé. La mort d'un personnage n'efface plus ses
    souvenirs : ils restent, marqués « mort », et la voix reçoit de quoi reconnaître un mort dont on lui parle (noms et
    faits des personnages morts qu'elle a connus, dans une part bornée du prompt, sous le plafond du pont). Format
    actuel seulement.
  - Accepté si : bancs : une voix sans `remember` dans sa fiche retient un fait, aucun fait ni appelant évincé, refus
    au-delà de 2000 caractères, souvenirs gardés après la mort et transmis comme morts ; en multijoueur, un fait retenu
    revient au prompt après un redémarrage du serveur.
  - Preuve : 2026-11-15 (hors jeu) : `remember` retiré du catalogue des fiches (les deux lecteurs) et donné à toute voix
    (`Actions.UNIVERSAL`, `UNIVERSAL_ACTIONS` du pont ; toute voix répond en mode structuré) ; mémoire de 2000 caractères
    par voix et par personnage, fait de 200 caractères, 50 faits au plus, refus `memory_full` journalisé, aucune
    éviction ; la mort marque les souvenirs (`RS_Memory.markDead`, nom et jour) au lieu de les effacer ; champ `dead=`
    (10 morts les plus récents, 300 caractères chacun) et section « People you knew who died » du prompt ; protocole,
    format, wiki et CHANGELOG à jour ; case retirée de l'atelier. `run_all --keep-going` sur 31 étapes (protocol,
    personas, fake_llm, kahlua, rs_trade*, atelier_*, persist_suites, rs_suites...) : `31 passed, 0 failed` ; luacheck 0 ;
    `check_case` `PASS`. Suite en jeu `rs.memory.before` / `rs.memory.after-restart` (campagne `mp-persist`) écrite.
  - Reste : campagne `mp-persist` ; mort marquée sur serveur dédié ; naturel des réponses en mode structuré avec le vrai
    modèle. Aucune limite globale de l'état : environ 750 mémoires pleines tiennent sous le plafond du codec.
- [x] **E22-T14** — Fiches sans connaissances, ignorances ni secrets figés
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T13
  - Fichiers : `RS_Persona.lua`, `RS_Personas.lua` (empreintes des fiches livrées), les 15 fiches concernées,
    `bridge/persona_store.py`, `bridge/radio_bridge.py`, `bridge/bulletin.py`, `bridge/atelier_ai.py`,
    `bridge/atelier_ai_templates.json`, atelier (étape 3, traductions, aides), `tools/gen_atelier_catalog.py`, bancs,
    format, protocole, wiki, README, ADR, CHANGELOG.
  - Faire : décision de l'utilisateur du 2026-11-16 ([ADR D10](../../architecture/decisions/adr-atelier-voix.md)).
    `knows=`, `ignores=` et `secret=` sont retirés des fiches et des deux lecteurs (refusés comme toute clé inconnue,
    aucune reprise). Le texte libre est le seul lieu de la personnalité : métier, savoir-faire, passé et ce que la voix
    tait (« You never tell anyone that …, even if asked; deny it. »), sans état actuel de la carte. Le pont ne filtre plus
    rien d'après des secrets de fiche (`leaks_secret` retiré, avec ses appels : souvenirs, morts, lieu dit, mission,
    missions permises, troc, faits du bulletin, réponses, appels, actions, essai de l'atelier). Atelier : l'étape 3
    devient « Personnalité » ; l'IA qui écrit la personnalité y met passé et secrets.
  - Accepté si : bancs des deux lecteurs, du pont, de l'atelier et des fiches livrées au vert ; luacheck sans
    avertissement de plus ; fumée de l'atelier et captures du wiki refaites.
  - Preuve : 2026-11-16 (hors jeu) : 15 fiches réécrites (affirmations sur l'état de la carte retirées : clinique de West
    Point encerclée, pont de Brandenburg coupé, patrouilles du fleuve, horaires des postes, pont Clark Memorial…) ;
    empreintes des 6 fiches d'avant E05-T11 ajoutées. `test_personas` 20, `test_personas_server` 107,
    `test_persona_sections` 12, `test_kahlua` 41, `test_atelier_*` (ai 9, catalog 7, help 5, log 20, server 24, surveys
    12, ui 11), `test_bulletin` 14, `test_voice_templates` 12, `test_mission_*` (chain, barricade, item, relay, route,
    watch), `test_rs_trade*`, `test_notes` 33, `test_outside_news` 25, `test_carnet` 98 `OK` ; `test_protocol` 39
    scénarios `OK` ; luacheck 0 avertissement ; `atelier_smoke.py` `summary: OK (2 locales, 0 failure(s))` ;
    `atelier_doc_shots.py` `summary: OK` (étape 3 : `atelier-*-03-personality.png`). `run_all --keep-going` : `204 passed, 1 failed` (rs_suites : repères de ligne de `RS_Personas.lua` décalés d'une ligne dans `RS_Env.lua`, corrigés), puis `--only rs_suites luacheck-* plan-check` : `4 passed, 0 failed`.
- [x] **E22-T15** — Atelier ouvert sur le réseau, protégé par un mot de passe
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T14
  - Fichiers : `bridge/atelier_auth.py` (nouveau), `bridge/atelier_server.py`, `bridge/radio_bridge.py`,
    `bridge/.env.example`, atelier (`login.html`, `login.js`, `api.js`, `app.js`, `theme.css`, traductions),
    `tests/radiosurvivor/test_atelier_auth.py` (nouveau), `tests/radiosurvivor/test_atelier_server.py`, `tests/run_all.py`,
    `tools/atelier_smoke.py`, `tools/atelier_doc_shots.py`, wiki 13 (fr, en) et captures `atelier-*-11-login.png`,
    README, ADR, CHANGELOG.
  - Faire : décision de l'utilisateur du 2026-11-16 ([ADR D11](../../architecture/decisions/adr-atelier-voix.md)).
    `--atelier-host ADRESSE` (défaut `127.0.0.1` : rien ne change, sans mot de passe) ; toute adresse hors boucle
    locale demande `ATELIER_PASSWORD` de `bridge/.env` (10 caractères au moins, lu par le lecteur du `.env` du pont),
    sinon l'atelier ne démarre pas et le pont continue. En mode réseau, chaque client se connecte (boucle locale
    comprise) : page de connexion française ou anglaise, `POST /api/login`, jeton `secrets.token_urlsafe(32)` en cookie
    `HttpOnly`, `SameSite=Strict`, `Path=/`, 7 jours, sessions en mémoire ; bouton de déconnexion (`POST /api/logout`) ;
    comparaison `hmac.compare_digest`. Sans session : 401 pour `/api/*`, renvoi vers la page de connexion sinon.
    Freins : par adresse réelle du client, 5 échecs bloquent 60 s, puis doublement jusqu'à 15 min, remise à zéro par une
    réussite, table bornée ; 30 échecs par minute toutes adresses confondues bloquent toute connexion 60 s ; 429 avec
    les secondes restantes. Journal et console : connexion, échec, blocage, déconnexion, avec l'adresse, jamais le mot
    de passe. Origine égale à `http://<Host>` exigée pour toute demande qui modifie ; mode local inchangé. Une seule
    porte dans la répartition des demandes (`LocalGate` ou `NetworkGate`, choisie au démarrage).
  - Accepté si : bancs de l'atelier au vert (horloge simulée pour les freins et l'expiration) ; fumée de l'atelier avec
    un passage de connexion dans les deux langues ; capture de la page de connexion dans le wiki.
  - Preuve : 2026-11-16 (hors jeu) : `test_atelier_auth` 17 (refus du réglage absent ou court, comparaison, sessions et
    expiration à 7 jours, blocage 60 s puis 120, 240, 480, 900, 900 s, remise à zéro, limiteur global, table bornée,
    journal sans mot de passe), `test_atelier_server` 33 (mode réseau : 401 sans cookie, 303 vers la page de connexion,
    cookie strict, mauvais mot de passe 401 puis 429 après 5, cookie falsifié, déconnexion, origine étrangère refusée,
    hôte quelconque avec sa propre origine ; mode local sans route de connexion ; démarrage refusé sans mot de passe ou
    trop court ; porte selon l'adresse), `test_atelier_ui` 11, `test_atelier_log` 20, `test_atelier_ai` 9,
    `test_atelier_catalog` 7, `test_atelier_help` 5, `test_atelier_surveys` 12, `test_bridge_guards` 11 `OK` ;
    `atelier_smoke.py` `summary: OK (2 locales, 0 failure(s))` (connexion, mauvais mot de passe, déconnexion et
    blocage en français et en anglais) ; `atelier_doc_shots.py` `summary: OK` (`atelier-*-11-login.png`) ;
    `run_all --keep-going` : `206 passed, 0 failed, 0 skipped`.
- [x] **E22-T09** — Wiki et README de l'atelier
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T04, E22-T05, E22-T06, E22-T08, E22-T10, E22-T11, E22-T12, E22-T13
  - Faire : page wiki « Atelier des voix » (français et anglais) avec captures, renvoi depuis « Créer une voix radio »,
    README et CHANGELOG.
  - Preuve : 2026-11-15 : pages `docs/wiki/fr/13-atelier-des-voix.md` et `docs/wiki/en/13-voice-workshop.md` (menu,
    accueil, renvoi depuis les pages 10), 22 captures `docs/images/screenshots/atelier/` produites par
    `tools/atelier_doc_shots.py` sur une copie temporaire (voix d'exemple Rosie acceptée par le lecteur du jeu) ;
    README et descriptions Steam (7403 et 7974 octets) ; groupe « Voice workshop » du CHANGELOG ; le pont décrit comme un
    dossier entier dans le wiki et les README. `wiki_sync.py RadioSurvivor --out` : code 0 ; liens relatifs : 0 problème.
- [x] **E22-T16** — Wiki de référence de l'atelier et exemples de voix
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T09
  - Fichiers : wiki 13 réécrit (`docs/wiki/fr/13-atelier-des-voix.md`, `docs/wiki/en/13-voice-workshop.md`), nouvelle
    page 14 (`docs/wiki/fr/14-exemples-de-voix.md`, `docs/wiki/en/14-voice-examples.md`), menus, accueils, renvoi des
    pages 10 ; `tests/radiosurvivor/test_wiki_voice_examples.py` (nouveau), `tests/run_all.py` ; `tools/atelier_doc_shots.py` et
    captures `docs/images/screenshots/atelier/` (12 à 17, `exemples/` 21 à 25).
  - Faire : demande de l'utilisateur du 2026-11-16 : une page du wiki dédiée à l'atelier, chaque écran, onglet, case et
    choix documenté pour un adolescent, et des exemples concrets de nouvelles voix. Page 13 : sommaire, ouverture (local,
    réseau), écran, pastilles et boutons de la liste, nouvelle voix, chaque étape avec un exemple de jeu et le tableau de
    tous ses réglages et choix, portée des radios du jeu, dix genres de mission, quatre récompenses, troc (déroulé,
    signal, hors de vue, plafonds 10 kg apportés et 20 kg pris lus dans `RS_Trade.lua` et `RS_TradeExchange.lua`, objets
    vendables du barème), note, catégories propres, aides de l'IA, verdict et raisons de refus, journal, partage,
    retrait, mémoire, propriétaire de serveur, limites. Page 14 : quatre voix originales (bavarde, donneur de missions,
    marchand de la route, dépôt caché), fiche complète dans des blocs ```persona. Aucune modification du mod ni de
    l'atelier.
  - Accepté si : chaque fiche des deux pages 14 acceptée par le lecteur du jeu (`RS_Persona.lua` dans lupa, poids des
    scripts du jeu) et par celui du pont, réécrite telle quelle par l'atelier sans point signalé, bandes libres, stock
    vendable ; captures refaites et regardées ; liens et ancres du wiki valides.
  - Preuve : 2026-11-16 (hors jeu) : `test_wiki_voice_examples` 5 `OK` (8 fiches : opal, vernon, marisol, wendell en
    français et en anglais) ; `test_atelier_server` 33, `test_atelier_auth` 17, `test_atelier_catalog` 7,
    `test_atelier_ui` 11, `test_atelier_log` 20, `test_atelier_ai` 9, `test_atelier_help` 5, `test_atelier_surveys` 12
    `OK` ; `run_all.py --only wiki_voice_examples` : `1 passed, 0 failed` ; `atelier_doc_shots.py` `summary: OK` (23
    captures par langue relues, dont 12-new, 13-restore, 14-import, 15-browser, 16-ai-personality, 17-saved et
    `exemples/` 21 à 25) ; `atelier_smoke.py` `summary: OK (2 locales, 0 failure(s))` ; `wiki_sync.py RadioSurvivor
    --out` : code 0 ; ancres des liens du wiki et des README : 0 problème. Pages : fr 13 = 45 Ko, fr 14 = 27 Ko.
  - Reste : coordonnées des lieux des exemples approximatives (à relever en jeu, dit dans la page 14).
- [x] **E22-T17** — Stock vendable, libellés neutres, ancienne version, lieux vérifiés
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E22-T16
  - Fichiers : `tools/gen_atelier_catalog.py` et `bridge/atelier/catalog.json` (liste `sellable`),
    `bridge/atelier/catalog.js`, `checks.js`, `tradekeys.js`, `itempicker.js`, `itembrowser.js`, `voicelist.js`,
    `app.js`, `theme.css`, `i18n/fr.json`, `i18n/en.json` ; `tests/radiosurvivor/test_atelier_catalog.py`, `tests/radiosurvivor/test_atelier_ui.py` ;
    `tools/atelier_smoke.py`, `tools/atelier_doc_shots.py` et captures ; wiki 10, 13 et 14 (fr, en) ; CHANGELOG.
  - Faire : demande de l'utilisateur du 2026-11-16. (1) Le catalogue liste les objets vendables (`sellable` :
    `CA_TradeValues.sellValue` > 0 dans lupa, comme `RS_Trade`, après chargement des fichiers qui appellent
    `registerSellOnly`) ; le stock d'un marchand ne cherche et ne parcourt qu'eux (les catégories propres gardent tous
    les objets) ; une ligne de stock invendable est signalée (`check.not_sellable`). (2) Les confirmations nomment la
    voix par son nom. (3) Libellés et aides neutres (« Arrive par », « Cette voix… »). (4) Copie écrite par le jeu
    d'après une ancienne version du mod : état « Ancienne version » avec info-bulle. (5) Captures : Walt n'est modifié
    que pour la capture 13. (6) Lieux des exemples vérifiés sur la carte installée (lotheader, lotpack, définitions de
    tuiles), corrigés, lien vers zomboidmap.com. (7) Wiki : où poser paiement, livraisons et sacs de récompense.
  - Accepté si : objets invendables absents du stock et signalés ; stock des voix livrées entièrement vendable ;
    captures sans Walt modifié hors capture 13, regardées ; chaque lieu des exemples sur la bonne case.
  - Preuve : 2026-11-16 (hors jeu) : `test_atelier_catalog` 10, `test_atelier_ui` 14, `test_atelier_server` 33,
    `test_atelier_ai` 9, `test_atelier_auth` 17, `test_atelier_help` 5, `test_atelier_log` 20, `test_atelier_surveys`
    12, `test_wiki_voice_examples` 5 `OK` (rouges avant le code : `KeyError: 'sellable'`, `check.not_sellable` et
    état `outdated` absents) ; `atelier_smoke.py` `summary: OK (2 locales, 0 failure(s))` (« hache » introuvable au
    stock, note du navigateur, ancienne version de Walt, confirmation « Walt Hensley ») ; `atelier_doc_shots.py`
    `summary: OK` (46 captures relues) ; ancres du wiki : 0 problème ; `run_all --keep-going` : `208 passed, 0 failed, 0 skipped` (luacheck 0 avertissement).
