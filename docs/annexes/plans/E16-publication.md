# E16 — Publication sur le Workshop

**Objectif.** Publier une version jouable de RadioSurvivor : contenu stabilisé, page Workshop, guide d'installation du pont, validation multijoueur complète.

**Dépend de.** Le périmètre de la première publication, décidé en E16-T01.

**Sources.** Skill `pz-workshop` (structure, `workshop.txt`, descriptions traduites, limite de 8 000 octets, captures) ; skill `pz-workshop-art` (poster, aperçu, icône) ; base `mod-loading.md` (structure B42, `versionMin`, suffixe Workshop ID / Mod ID) ; mémoire utilisateur : garder `batman_` dans l'identifiant d'un mod publié.

## Décisions

- 2026-10-10 — **E16-T01 (1)** : première publication **après les actions des voix** : radio de Walt, six voix (E05), carnet radio et « Émettre » (E06), BeltRadio requis, **plus** les actions des voix (E07 : souvenirs, état, repères de carte) et une première mission générée (E11) ; Living Knox désactivé par défaut tant qu'il n'est pas jouable ; après la séance MP finale de ces étapes.
- 2026-10-10 — **E16-T01 (2)** : visibilité **privée** pour la première mise en ligne (vérifier la page et le téléchargement avant tout partage).
- 2026-10-21 — **Durcissement avant publication** (confirmé par l'utilisateur 2026-10-21) : les corrections de la revue `docs/ameliorations-et-idees.md` déjà faites sont suivies ici, une tâche par chantier (E16-T06 à E16-T10). Plafonds du pont (jetons 16 000, prompt 128 000 caractères) réglables dans sa configuration, mêmes défauts ; lot non réclamé gardé 7 jours **de jeu** (168 h d'âge du monde), avec conversion des lots déjà enregistrés en temps réel.

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

- [ ] **E16-T06** — Pont LLM : injections et coût des appels (C01, C02, C03, C10)
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `bridge/radio_bridge.py`, `tests/test_bridge_guards.py`, wiki `08-*` EN/FR
  - Faire : nom du personnage, nom de la radio, date et jours bornés et cités comme données dans le prompt (C01) ; crochets d'un appelant neutralisés dans l'historique partagé (C02) ; plafond de jetons à chaque tentative, sans nouvelle tentative après une réponse vidée par le plafond (C03) ; prompt de plus de 128 000 caractères refusé `prompt_too_large` (C10).
  - Accepté si : bancs verts ; en jeu, une voix répond normalement avec un nom de personnage piégé.
  - Tests : `tests/test_bridge_guards.py`
  - Preuve : commits `4215bd3`, `ea265bc` ; `tests/test_bridge_guards.py` vert (2026-10-21)
  - Reste : vérification en jeu (échange radio réel avec le pont et un fournisseur).

- [x] **E16-T07** — Plafonds du pont réglables
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E16-T06
  - Fichiers : `bridge/radio_bridge.py`, `bridge/.env.example`, `tests/test_bridge_guards.py`, wiki `08-*` EN/FR
  - Faire : `LLM_MAX_TOKENS` (défaut 16 000, 256 à 131 072) et `LLM_MAX_PROMPT_CHARS` (défaut 128 000, 16 000 à 2 000 000) lus comme les autres réglages (variable d'environnement, puis `.env`) ; valeur non entière ou hors bornes : défaut gardé et avertissement ; plafonds appliqués affichés au démarrage.
  - Accepté si : valeurs valides appliquées aux deux essais et au refus du prompt, valeurs invalides remplacées par le défaut ; wiki admin EN/FR à jour.
  - Tests : `tests/test_bridge_guards.py` (`LimitSettingTests`)
  - Preuve : commit `69e550c` ; `tests/test_bridge_guards.py` vert (11 tests, 2026-10-21)
  - Reste : —

- [ ] **E16-T08** — Carnet : état privé borné et écritures fiables (C17 à C20)
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `server/RadioSurvivor/RS_State.lua`, `server/RadioSurvivor/RS_StatePurge.lua`, `tests/test_rs_state.py`
  - Faire : l'encodeur refuse ce que le décodeur refuserait (aucun fichier illisible), écriture échouée réessayée sans bloquer le carnet, purge des personnages morts par une passe quotidienne depuis la sauvegarde, hexadécimal et somme de contrôle rapides.
  - Accepté si : bancs verts ; serveur de longue durée qui sauvegarde et recharge son état sans perte.
  - Tests : `tests/test_rs_state.py`
  - Preuve : commits `3760771`, `5fd79b3`, `99dc0bc` ; `tests/test_rs_state.py` vert (2026-10-21)
  - Reste : vérification sur un serveur dédié (sauvegarde, redémarrage, purge après quelques semaines de jeu).

- [ ] **E16-T09** — Limites de débit et coût côté serveur (C21, C22, C30, C31)
  - État : `testé hors jeu`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `shared/RadioSurvivor/RS_RateLimit.lua`, `shared/RadioSurvivor/RadioSurvivor_Const.lua`, `tests/test_server_guards.py`, `tests/test_lk_bodies.py`
  - Faire : seaux de jetons par compte pour les commandes client, coupe linéaire des espaces (`oneLine`), cache par image de `Bodies.find`.
  - Accepté si : bancs verts ; jeu normal et reconnexions non limités sur un serveur dédié.
  - Tests : `tests/test_server_guards.py`, `FindCacheTests` (`tests/test_lk_bodies.py`)
  - Preuve : commits `2d8cae5`, `ed4353f` ; `tests/test_server_guards.py` et `FindCacheTests` verts (2026-10-21)
  - Reste : vérification MP (jeu normal à deux clients, aucune commande légitime refusée).

- [ ] **E16-T10** — Lot non réclamé gardé 7 jours de jeu
  - État : `testé hors jeu`
  - Cible : `solo`
  - Dépend de : —
  - Fichiers : `server/RadioSurvivor/RS_Missions.lua`, `shared/RadioSurvivor/RS_Config.lua`, `tests/test_carnet.py`, `docs/specifications-techniques/protocole-carnet-v2.md`
  - Faire : échéance `unclaimedUntilHour` = âge du monde à la réussite + `UNCLAIMED_RETENTION_HOURS` (168 h de jeu, `RS_GameClock`), arrêtée en pause et sur un serveur vide ; plafonnée à 168 h au-delà de l'âge actuel ; lot enregistré avant la décision converti une fois (temps réel restant en heures de jeu à vitesse normale, plafonné à 7 jours de jeu) ; gardé sans horloge de jeu.
  - Accepté si : bancs verts ; en jeu, un lot réussi non réclamé reste réclamable après une longue pause.
  - Tests : `tests/test_carnet.py` (`GameClockTests.test_unclaimed_lot_kept_seven_game_days`, `test_unclaimed_lot_saved_in_real_time_is_converted`)
  - Preuve : commits `a2a81b3`, `ff8fc39` (suite en jeu `rs.missions` alignée) ; `tests/test_carnet.py`, `tests/test_rs_suites.py`, `tests/test_kahlua.py` verts (2026-10-21)
  - Reste : vérification en jeu (lot laissé, pause longue, puis réclamation).
