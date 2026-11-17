# Charte de l'atelier des voix

Règles de conception de chaque écran de l'atelier des voix (`bridge/atelier/`). Le public est un adolescent qui invente
une voix pour la radio : il choisit, il ne programme pas. La charte vient de l'audit
[audit-ux-atelier-2026-11-16.md](../audits/audit-ux-atelier-2026-11-16.md) (section 10) et des décisions de l'utilisateur
de la tâche `E24-T02` ([plan E24](../plans-termines/E24-atelier-simple.md)). **Tout écran nouveau de l'atelier la suit** ; une
exception se décide avec l'utilisateur et s'écrit ici.

## Les huit règles

1. **Rien de technique par défaut.** Aucun identifiant, code, chemin, clé de traduction, nom interne du jeu ni poids à
   l'écran. Un nom technique tient au plus dans une info-bulle (`title`) ou dans un panneau « Détails » fermé. Seules
   exceptions décidées : les coordonnées d'une case (champs x, y, étage, lien de carte, relevés en jeu) et la fréquence
   fixe facultative d'une voix (pastille de la radio nécessaire).
2. **Un nombre du jeu = un choix en mots.** Crans nommés (« Rarement », « Chaque semaine », « Rapace »), cartes ou
   pastilles ; le nombre se lit dans l'info-bulle du cran et se règle dans le panneau replié « Valeur exacte ». Une
   valeur écrite à la main allume le cran le plus proche et dit « réglage sur mesure ». Jamais « une chance sur N ».
3. **Remplir, pas taper.** Ce que l'atelier peut fabriquer l'est : identifiant d'une voix (depuis son prénom), d'un lieu,
   d'une mission, d'un paquet, d'une liste d'objets, nom d'état de l'histoire, valeur par défaut. L'ado tape seulement
   ce qu'il invente : un nom, une phrase, le texte de la voix.
4. **Une question, une réponse, une aide.** Chaque réglage est une question posée au-dessus de sa réponse, regroupée
   par sujet sous un titre ; une ligne d'aide courte (douze mots environ) ; le détail derrière « ? », dont la bulle
   montre « ce que c'est », les choix et un exemple, le reste sous « En savoir plus ». Un réglage à remplir porte une
   étoile, expliquée une fois en haut du formulaire.
5. **Le texte de la voix dans la langue de l'ado.** La personnalité s'écrit en anglais (par défaut) ou en français :
   l'IA qui joue la voix comprend les deux, rien n'est traduit et le texte reste tel qu'il est écrit (`language=` de la
   fiche dit laquelle). L'IA de l'atelier aide à l'écrire à partir de quelques phrases.
6. **Le vocabulaire de l'ado.** Dire voix, lieu, mission, récompense, troc, paquet, note, radio, liste d'objets.
   Interdits à l'écran : identifiant, slug, MHz à taper, poids, kg, lot (dire « paquet »), sorte, paramètre, pont,
   octets, clé, format, fiche (dire « voix »). Tutoiement, phrases courtes, verbes d'action.
7. **Choisir dans une liste, jamais recopier.** Choix fermé : cartes avec icône (`widgets.cards`) ; choix multiple :
   cases en cartes ou pastilles ; quantité : bouton « − » / « + » (`widgets.stepper`, `rangeStepper` pour « entre n et
   m ») ; réglage chiffré : crans (`stepchoice.js`) ; objet : la liste filtrable des objets du jeu ; lieu, voix : une
   liste. Un seul style de contrôle par sorte de donnée dans tout l'atelier.
8. **Erreur = phrase + bouton.** Un message dit quoi faire en une phrase et propose le bouton qui le fait
   (« Corriger », « Créer le lieu de rendez-vous », « Importer comme une nouvelle voix »). Le message brut du jeu reste
   dans « Détails pour un adulte », sans numéro de ligne.

## Où vivent les données

Une règle de présentation qui dépend du jeu est une **donnée**, à un seul endroit, jamais une suite de `if` :

| Donnée | Module | Contenu |
|---|---|---|
| Crans des réglages chiffrés | `scales.js` (`SCALES`) | Cran → valeur écrite dans la fiche, pour l'appel spontané, le passage et le calme du marchand, sa marge (trois cartes), l'attente de ramassage et la durée de guet ; valeurs tirées des bornes et défauts du lecteur `RS_Persona.lua` et des modèles de mission |
| Heures d'écoute toutes faites | `steps/where.js` (`HOUR_PRESETS`) | Toujours, la nuit, le jour ; « Sur mesure » garde les plages |
| Types de voix à la création | `presets.js` (`VOICE_TYPES`, `STEP_WANTS`) | Actions cochées et sections ajoutées par carte ; étapes repliées tant que la voix ne les utilise pas |
| Groupes de questions d'une section | `stock.js` (`KEY_GROUPS`) | Les trois sous-titres du troc |
| Langues de la personnalité | `voice.js` (`STARTERS`) | Texte de départ par langue |
| Genres des lieux de la note | `lootindex.js` (`LOOT_KINDS`) | Motif du nom de liste du jeu → genre (maison, bureaux, magasins, caisses, véhicules, autres) du sélecteur « Aussi dans… » (E24-T03) |

Les textes, icônes et aides vivent dans `i18n/fr.json` et `i18n/en.json` (mêmes clés).

## Identifiants fabriqués

- **Voix** : premier mot du nom, en minuscules sans accent, suivi de `_2`, `_3`… s'il est pris (`voice.voiceId`).
- **Lieu, mission** : depuis le nom du lieu ou le genre de mission (`places.addPlace` : lieu commun de l'onglet « Lieux »,
  jamais `near`, `far` ni `very_far` ; `voice.addMission`).
- **Paquet** (`group=` du troc) : depuis le nom tapé ; l'écran le montre en clair depuis l'identifiant
  (`voice.labelOf`, sans accent) ; renommer un paquet garde ses objets (`paquets.js`).
- **Liste d'objets propre** (`[category]`) : depuis le nom tapé, jamais le nom d'une liste du mod.
- **État de l'histoire** (`sets_state=`) : l'ado écrit une phrase courte ; `story.js` en fait un nom (32 caractères au
  plus, `_2` si une autre phrase donne le même nom, la même phrase partage le même état) et écrit la phrase à la fin de
  la personnalité : `Story state: when your story state is <nom>, <phrase>`. Le pont ne donne à l'IA que le nom de
  l'état (`radio_bridge.story_prompt`, « ta fiche dit ce qu'il veut dire ») : la ligne de la personnalité lui en donne
  le sens. Un texte de personnalité réécrit par l'IA de l'atelier garde ces lignes (`story.carry`).

## Vérifier un écran

- Tests hors jeu : `tests/test_atelier_ui.py` (modules purs, clés de traduction) et `tests/test_atelier_simple.py`
  (identifiants fabriqués, crans, marge, état de l'histoire, types de voix, paquets).
- Essai automatique : `tools/atelier_smoke.py` crée une voix sans rien taper de technique.
- Captures du wiki : `tools/atelier_doc_shots.py`, regardées une à une en se mettant à la place d'un adolescent.
