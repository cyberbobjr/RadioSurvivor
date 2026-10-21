# E16 — Publication sur le Workshop

**Objectif.** Publier une version jouable de RadioSurvivor : contenu stabilisé, page Workshop, guide d'installation du pont, validation multijoueur complète.

**Dépend de.** Le périmètre de la première publication, décidé en E16-T01.

**Sources.** Skill `pz-workshop` (structure, `workshop.txt`, descriptions traduites, limite de 8 000 octets, captures) ; skill `pz-workshop-art` (poster, aperçu, icône) ; base `mod-loading.md` (structure B42, `versionMin`, suffixe Workshop ID / Mod ID) ; mémoire utilisateur : garder `batman_` dans l'identifiant d'un mod publié.

## Décisions

- 2026-10-10 — **E16-T01 (1)** : première publication **après les actions des voix** : radio de Walt, six voix (E05), carnet radio et « Émettre » (E06), BeltRadio requis, **plus** les actions des voix (E07 : souvenirs, état, repères de carte) et une première mission générée (E11) ; Living Knox désactivé par défaut tant qu'il n'est pas jouable ; après la séance MP finale de ces étapes.
- 2026-10-10 — **E16-T01 (2)** : visibilité **privée** pour la première mise en ligne (vérifier la page et le téléchargement avant tout partage).

## Tâches

- [x] **E16-T01** — Périmètre de la première publication
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : ce fichier
  - Faire : faire trancher ce qui part dans la première version.
  - Questions : (1) Contenu : options : Walt + carnet Bandits! (E00 à E03) [recommandé pour un premier retour] / attendre les six voix (E05, E06) / attendre la réputation réelle (E04). (2) Visibilité : options : non listée pour les amis d'abord [recommandé] / publique / privée.
  - Accepté si : décisions consignées.
  - Tests : —
  - Preuve : décisions du 2026-10-10 (section Décisions) : publication après les actions des voix (E07) et une mission générée (E11), Living Knox désactivé par défaut ; visibilité privée
  - Reste : —

- [ ] **E16-T02** — Nettoyage et métadonnées
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E16-T01
  - Fichiers : `mod.info` (nom sans « expérimental » si validé, version), `workshop.txt`, `preview.png`, `poster.png`, `icon.png`
  - Faire : suivre les skills `pz-workshop` et `pz-workshop-art` ; ne pas publier `dev/`, `docs/`, `tests/`, `bridge/` hors de l'archive prévue pour le pont.
  - Accepté si : structure validée par la skill ; aucun fichier de développement dans `Contents`.
  - Tests : contrôles de la skill.
  - Preuve : —
  - Reste : —

- [ ] **E16-T03** — Guide d'installation du pont pour un serveur
  - État : `codé`
  - Cible : `hors jeu`
  - Dépend de : E16-T01
  - Fichiers : `README.md` ; description Workshop FR et EN
  - Faire : le pont ne peut pas être fourni par le Workshop : expliquer l'installation sur la machine du serveur, le dossier d'échange (`-cachedir`), la clé, le coût, le mode `--offline`, un seul pont par dossier.
  - Accepté si : un admin tiers lance le pont en suivant le guide.
  - Tests : relecture.
  - Preuve : guides rédigés le 2026-10-12 : `docs/wiki/fr/07-installation-du-pont.md` (FR) et `docs/wiki/en/07-bridge-server-setup.md` (EN) — dossier d'échange par cas (`-cachedir`, partie hébergée vérifiée `CoopMaster.java:116`), clé `OPENAI_*` par `--env`, coût et options sandbox, `--offline`, `--debug`, verrou `bridge.lock`, démarrage automatique, vérification, 16 messages de dépannage relevés dans le code ; options vérifiées dans `main()` ; `radio_bridge.py --offline --test` exécuté avec succès
  - Reste : relecture et installation par un admin tiers (critère) ; renvoi à ajouter dans `README.md` (modifications non commitées de l'utilisateur) et dans les descriptions Workshop ; moyen de distribuer le pont à décider avec E16-T02 (dépôt privé : pas de lien GitHub) ; défaut `--env` relatif au dépôt à corriger dans le pont ; boucle `run()` sans pause si `requests.txt` reste illisible : corrigée le 2026-10-12 (pause avant la relecture, banc `scenario_unreadable_requests_wait`)

- [ ] **E16-T04** — Validation multijoueur finale
  - État : `à faire`
  - Cible : `MP`
  - Dépend de : E16-T02
  - Fichiers : `docs/annexes/tests/validation/`
  - Faire : toutes les suites en jeu du périmètre + protocole nominal sur le serveur dédié de test avec deux clients, mods exacts de la publication.
  - Accepté si : aucune erreur `f:0` liée au mod ; suites au vert.
  - Tests : `RST.server('rs')`, `RST.run('rs')`.
  - Preuve : —
  - Reste : —

- [ ] **E16-T05** — Publication
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E16-T04
  - Fichiers : `workshop.txt`, `CHANGELOG.md`
  - Faire : publier selon la skill `pz-workshop` **après accord explicite de l'utilisateur** ; consigner l'identifiant Workshop. Objets requis sur la page Steam : Belt Walkie-Talkie (`batman_BeltRadio`) et Signal Smoke (`batman_SignalSmoke`, Workshop 3811010882, prérequis depuis le 2026-10-15), cités aussi dans les descriptions et dans `WorkshopItems=` du guide serveur.
  - Accepté si : page en ligne avec la visibilité décidée ; identifiant consigné.
  - Tests : —
  - Preuve : —
  - Reste : —
