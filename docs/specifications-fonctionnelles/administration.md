# Administration, pont et compatibilité (F40 à F45)

Vue administrateur. Guides pas à pas : [wiki](../wiki/fr/Home.md).

## F40 — Pont LLM et fournisseur d'IA

- Le Lua du jeu n'a pas de réseau : un programme Python (`bridge/radio_bridge.py`, bibliothèque standard seulement)
  tourne sur la machine qui exécute le Lua serveur (le PC du joueur en solo, le serveur dédié en MP) et échange des
  fichiers avec lui. Fournisseur compatible OpenAI configuré par `OPENAI_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`.
- Modes `--offline` et `--debug`, verrou `bridge.lock` (un pont par dossier), démarrage automatique (planificateur
  Windows, systemd, Docker).
- Guides : [Le pont en solo](../wiki/fr/05-pont-en-solo.md), [Le pont sur un serveur dédié](../wiki/fr/06-pont-sur-serveur-dedie.md),
  [guide complet](../wiki/fr/07-installation-du-pont.md), [Fournisseur d'IA](../wiki/fr/08-fournisseur-ia.md).

## F41 — Options sandbox

- Deux pages d'options : **RadioSurvivor** (activation, cadence et coût des appels, langue, rareté des notes, heure de
  la chronique, dernières pages, initiatives, délai des secours, réconfort, multiplicateur de leçon) et **LivingKnox**
  (activation, debug, nombre, types et taille des groupes, relève, seuils de danger, combat contre les zombies,
  défense, blessure, peur, raids, vengeance).
- Effet de chaque option : [Options sandbox](../wiki/fr/09-options-sandbox.md) ; noms, types, défauts et bornes :
  [spécifications techniques](../specifications-techniques/README.md#options-sandbox).

## F42 — Fenêtre d'administration et fiche d'un PNJ

- Solo en mode debug, ou rôle `admin`/`moderator` sur un serveur : menu debug → **Living Knox - Admin** (groupes,
  foyers, membres, histoire, journal ; déplacer un foyer, forcer une relève) ; clic droit sur un survivant →
  **Détails (Living Knox)** (besoins, santé, décision, arme ; réglages bornés, rôle, nom, téléportation) ; onglet
  **Réputation** → **Toutes les réputations (admin)** ; panneau de debug des fréquences.
- Conception : [administration.md](../annexes/conception/administration.md).

## F43 — Fiches de voix éditables

- Chaque voix est une fiche texte installée côté serveur et relue à chaud ; une fiche que l'admin n'a pas modifiée suit
  les mises à jour du mod, une fiche modifiée n'est jamais écrasée. Guide : [Créer une voix radio](../wiki/fr/10-creer-une-voix-radio.md) ;
  format : [persona-format.md](../specifications-techniques/persona-format.md).

## F44 — Compatibilité et prérequis

- Prérequis : Belt Walkie-Talkie (`batman_BeltRadio`, lui-même dépendant de TooltipLib) et Signal Smoke
  (`batman_SignalSmoke`). Facultatif : CharacterReputation (`batman_CharacterReputation`, chargé avant).
- Incompatibles : Bandits! (`Bandits2`) et Project A-Life (`ProjectALifeNPCs`).
- Installation : [Installation](../wiki/fr/04-installation.md).

## F45 — Tests en jeu automatiques (développement)

- Moteur RST (mod de développement jamais publié) lancé depuis la console (`RST.run`, `RST.server`) et campagnes
  automatiques solo et serveur dédié avec deux clients. Méthode : [tests-en-jeu.md](../annexes/tests/tests-en-jeu.md).
