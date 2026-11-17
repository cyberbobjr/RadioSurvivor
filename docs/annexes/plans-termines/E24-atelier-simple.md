# E24 — Atelier simple pour les adolescents

<!-- tableau de bord : généré par tools/plan.py suivi, ne pas modifier à la main -->

**Avancement.** terminée — 5 / 5 tâche(s) terminée(s).

| | Tâche | Titre | État | Cible | Dépend de |
|---|---|---|---|---|---|
| ☑ | E24-T01 | Fréquence choisie par la radio nécessaire | `testé hors jeu` | hors jeu | — |
| ☑ | E24-T02 | Passe de simplicité sur tous les écrans de l'atelier | `testé hors jeu` | hors jeu | E24-T01 |
| ☑ | E24-T03 | Socle commun des notes de fréquence | `testé hors jeu` | hors jeu | E24-T02 |
| ☑ | E24-T04 | « Proposer » par l'IA sur chaque champ texte, coller une position de la carte | `testé hors jeu` | hors jeu | E24-T03 |
| ☑ | E24-T05 | Tableau de bord des voix (option A) | `testé hors jeu` | hors jeu | E24-T04 |

<!-- fin du tableau de bord -->

**Mod.** RadioSurvivor (`batman_RadioSurvivor`) pour le format des fiches et le tirage des fréquences ; le pont
(`bridge/`) et son atelier.

**Objectif.** Un adolescent crée une voix sans jamais taper un identifiant, un nom technique, une syntaxe ni une plage
de nombres : il choisit dans des listes, des cases et des curseurs, avec des mots simples.

**ADR.** [Atelier des voix](../../architecture/decisions/adr-atelier-voix.md), décision D12 (2026-11-16).

**Dépend de.** E22, E23.

## Décisions

- 2026-11-16 — **E24-T01** (utilisateur) : la fréquence d'une voix se choisit par la radio nécessaire (cinq niveaux, du
  talkie le plus simple au matériel militaire) ; le jeu tire à chaque partie une fréquence libre que cette radio capte
  et pas les radios plus faibles. En option, une fréquence fixe unique, avec une pastille qui montre la radio
  nécessaire. Bande de fréquences, fréquences multiples et « gros poste » (`radio=high_tier`) disparaissent, sans
  reprise de l'ancien format.
- 2026-11-16 — **E24-T02** (utilisateur) : les lots du stock se choisissent dans une liste, sans nom à saisir ; une
  passe sur tous les écrans de l'atelier supprime toute saisie technique, une fois pour toutes, avec une charte écrite
  pour les écrans futurs.
- 2026-11-16 — **E24-T02** (utilisateur, après l'audit de 111 constats, une question à la fois) : langue de la
  personnalité au choix (anglais par défaut, français possible : le modèle comprend les deux) ; onglet Journal gardé tel
  quel ; coordonnées saisies comme aujourd'hui (champs, lien de carte, relevés) ; réglages chiffrés en crans nommés avec
  un panneau « Valeur exacte » replié ; marge du marchand en trois crans (Généreux, Correct, Rapace) ; catégories
  propres repliées sous « Options avancées », identifiant fabriqué depuis le nom ; état de l'histoire écrit en phrase
  libre, mot technique fabriqué et caché ; à la création, une carte de type de voix (survivant qui parle, donneur de
  missions, marchand) coche les actions qui vont avec.
- 2026-11-16 — **E24-T02** (confirmé par défaut) : « paquet » à l'écran au lieu de « lot » (le format garde `group=`) ;
  les 95 corrections de présentation de l'audit sont appliquées ; la charte de l'atelier (8 règles) entre dans la doc.
- 2026-11-16 — **E24-T03** (utilisateur) : les notes de fréquence de toutes les voix doivent se trouver en jeu ; socle
  commun pour toute voix qui a une note (lieux à papiers, boîtes à gants, zombies même sans talkie, chance faible), plus
  ses listes à thème par-dessus ; l'atelier applique ce socle d'office.

## Hors périmètre

- Living Knox.

## Tâches

- [x] **E24-T01** — Fréquence choisie par la radio nécessaire
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Faire : décision E24-T01 ; format, lecteur du jeu, tirage d'une fréquence libre, pont, atelier, 16 voix livrées, doc.
  - Accepté si : bancs du tirage (niveau, pas de collision, fréquence fixe), fiches livrées acceptées, atelier.
  - Preuve : 2026-11-16, `RS_RadioLevels.lua` (cinq niveaux tirés de `media/scripts/generated/items/radio.txt` 42.22, pas de 0,2 MHz) sert au jeu, au tirage et au catalogue ; fiches `radio=` ou `frequency=` (exactement l'un des deux) ; tirage d'une fréquence libre dans la zone du niveau à chaque partie (`RSFREQ2`), jamais sur une autre voix ni une chaîne prise ; bandes, `frequencies=` et `high_tier` retirés ; atelier : cinq cartes et fréquence fixe avec pastille ; 16 voix livrées, wiki 10, 13, 14, `persona-format.md`, CHANGELOG. Bancs : `test_radio_levels` 9, `test_personas` 17, `test_personas_server` 106, `test_kahlua` 41, `test_protocol` OK, `test_wiki_voice_examples` 5, `test_atelier_ui` 20 ; `atelier_smoke` `summary: OK (2 locales, 0 failure(s))` ; luacheck 0 avertissement. Reste en jeu : suites `rs.voices.world`, `rs.personas`.

- [x] **E24-T02** — Passe de simplicité sur tous les écrans de l'atelier
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E24-T01
  - Faire : décision E24-T02 ; audit de tous les écrans, lots par liste, corrections de présentation, charte.
  - Accepté si : tests de l'atelier, essai automatique, captures refaites et regardées.
  - Preuve : 2026-11-16, audit `docs/annexes/audits/audit-ux-atelier-2026-11-16.md` appliqué (corrections de présentation, Journal gardé) ; identifiants fabriqués et cachés (voix, lieux, missions, paquets, listes propres, état de l'histoire) ; crans nommés avec « Valeur exacte » (`scales.js`) ; marge en trois cartes ; langue de la personnalité par `language=` ; état de l'histoire en phrase (`story.js`) ; cartes de genre de voix (`presets.js`) ; paquets (`paquets.js`) ; charte `docs/annexes/conception/charte-atelier.md` ; wiki 13 et 14, CHANGELOG. Bancs : `test_atelier_simple` 7, `test_atelier_ui` 20, autres `test_atelier_*` OK, `test_wiki_voice_examples` 5 ; `atelier_smoke` `summary: OK (2 locales, 0 failure(s))` ; captures refaites. Restes : aide de l'IA en anglais seulement, noms de butin non traduits, noms de paquets sans accents, `app.js` à découper.

- [x] **E24-T03** — Socle commun des notes de fréquence
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E24-T02
  - Faire : décision E24-T03 ; socle de listes de butin à papiers, boîtes à gants et zombies appliqué par le jeu à
    toute note déclarée ; listes à thème de la fiche en plus ; atelier, wiki, CHANGELOG.
  - Accepté si : bancs du socle (toute note dans le socle, thème ajouté, zombie sans talkie), atelier.
  - Preuve : 2026-11-16, socle `server/RadioSurvivor/RS_NotesBase.lua` (12 listes à papiers vanilla 42.22 à 0,1, `GloveBox` 0,5, zombies 2 %, porteur de talkie 35 %, × NoteRarity) appliqué à toute note déclarée ; `loot=`/`glovebox=` = lieux à thème en plus ; `corpse=` retiré ; fiches allégées, empreintes `KNOWN_DELIVERED` ; atelier : socle dit en clair, « Aussi dans… » choisi dans une liste filtrable par genre (`lootindex.js`), sans saisie ; `notes-frequences.md` (calcul : environ 5,4 % par meuble à papiers à 4 tirages), wiki 01, 03, 10, 12, 13, 14, CHANGELOG. Bancs : `test_notes` 35, `test_persona_sections` 12, `test_personas` 17, `test_personas_server` 106, `test_wiki_voice_examples` 5, `test_atelier_*` OK ; `atelier_smoke` `summary: OK (2 locales, 0 failure(s))` ; luacheck 0 avertissement. Reste en jeu : suite `rs.notes`, butin réel.

- [x] **E24-T04** — « Proposer » par l'IA sur chaque champ texte, coller une position de la carte
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E24-T03
  - Faire : décision D13 de l'ADR atelier-voix ; requête `suggest` (contexte : fiche entière + cible du champ), bouton
    sur les 10 champs texte, collage `x, y` dans les coordonnées ; wiki 13, captures, CHANGELOG.
  - Accepté si : bancs `test_atelier_ai`, `test_atelier_ui` ; `atelier_smoke` (Proposer et collage, fr et en).
  - Preuve : 2026-11-17, requête `POST /api/ai/suggest` (`atelier_ai.py`, champs déclarés dans `atelier_ai_templates.json` : 10 champs, langue de la voix ou de la page, limite en caractères ou en octets, marque de fréquence `{frequency}` → `%1`, sinon `ai_no_frequency`) ; contexte = fiche entière non enregistrée + détails de la cible + texte actuel ; « Suggérer » de l'histoire remplacé ; bouton « ✨ Proposer » sur les 10 champs (`ai.js` `proposeButton`) ; collage `x, y[, z]` (`values.js` `parseSquare`, `maplink.js` `squareEditor`) ; wiki 13 fr/en, CHANGELOG. Bancs : `test_atelier_ai` 18, `test_fake_llm` 27, `test_atelier_server` 33, `test_atelier_ui` OK ; `atelier_smoke` `summary: OK (2 locales, 0 failure(s))` ; suite complète `Summary: 209 passed, 0 failed` (585 s). Reste : propositions variées seulement avec un vrai LLM (le faux LLM répond toujours pareil).

- [x] **E24-T05** — Tableau de bord des voix (option A)
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E24-T04
  - Faire : décision utilisateur 2026-11-17 (maquette, option A) : vue « Tableau de bord » de l'atelier, chiffres clés,
    filtres par interaction et par radio, une ligne par voix (radio nécessaire, heures d'écoute sur 24 h, ce qu'on peut
    faire), tri d'un clic, clic sur une voix = sa fiche ; wiki 13, captures, CHANGELOG.
  - Accepté si : `test_atelier_ui`, `atelier_smoke` (fr et en), captures regardées.
  - Preuve : 2026-11-17, onglet « Tableau de bord » ouvert au démarrage (`bridge/atelier/dashboard.js`, lecteurs de la page `sheet.js`/`voice.js`, niveaux de radio du catalogue, `catalog.frequencyLevel` partagé avec le badge de `where.js`) : six chiffres, filtres par interaction et par radio, une ligne par voix (radio, barre de 24 h, interactions), tri, clic = fiche, point rouge redessiné au changement de verdict ; wiki 13 fr/en, captures `atelier-*-00-dashboard.png` regardées, CHANGELOG. Bancs : `test_atelier_ui` 27, autres `test_atelier_*` OK ; `atelier_smoke` `summary: OK (2 locales, 0 failure(s))` ; suite complète `Summary: 209 passed, 0 failed` (581 s).
