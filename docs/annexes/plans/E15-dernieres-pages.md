# E15 — Les dernières pages

**Objectif.** À la mort d'un personnage, le LLM écrit son journal à partir de sa vie enregistrée, et un document manuscrit en lecture seule est placé sur le corps ou à côté (note de travail §07).

**Dépend de.** E00-T02 (mort sur serveur dédié), E05-T03 (pont).

**Sources.** Note de travail §07 et §10 (« à quel moment le conteneur du cadavre existe côté serveur ») ; base `quest-building-blocks.md` (document en lecture seule `addPage` + `setLockedBy`, 15 lignes par page ; écriture manuscrite ; document au rendu des journaux) ; base `world-placement.md` (objet au sol `AddWorldInventoryItem`) ; base `kahlua-lua.md` (`getFileWriter` en UTF-8).

## Décisions

- Acquises : toujours écrites, un joueur ne peut pas refuser ; l'admin peut couper la fonction par une option sandbox ; matière : heures de survie, zombies tués, villes traversées (relevé périodique), métier, dernières phrases radio, sauvetages faits ou manqués ; le LLM ne peut inventer ni une mort ni une mission accomplie.
- 2026-10-14 — **E15-T01** : relevé figé à la mort jusqu'à E15-T03 (8 au plus) ; sondage 15 s, ville à moins de la moitié de son rayon, carte vanilla ; métier en identifiant ; seules les phrases du personnage (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E15-T02** : (pour E15-T03) jeton en ModData du joueur recopié sur le cadavre, case et état « en feu » notés à la mort ; document ajouté au cadavre portant le jeton, sinon posé au sol (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E15-T03** : `Base.Notebook` vanilla sans police manuscrite `printMedia` (confirmé par l'utilisateur) ; 90 s, pose à 3 s, cadavre à 2 cases ; demande perdue au redémarrage = secours immédiat ; langue `CallLanguage` ; verrou `RadioSurvivor`, nom traduit côté serveur (confirmé par défaut, valeurs techniques).
- 2026-10-14 — **E15-T04** : option désactivée = relevés effacés (pas mis en pause) ; morts en attente abandonnées ; option indépendante de `RadioSurvivor.Enabled` (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **E15-T01** — Relevé de vie du personnage
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `media/lua/server/RadioSurvivor/RS_LifeLog.lua`
  - Faire : relevé borné par identité de personnage (E00-T01) : villes traversées (sondage espacé), zombies tués, métier, heures de survie, dernières phrases radio, missions et secours ; stocké dans l'état privé.
  - Accepté si : taille bornée ; aucun relevé pour un personnage sans identité.
  - Tests : banc `lupa`.
  - Preuve : banc `tests/test_lifelog.py` du 2026-10-12 (19 tests OK : relevé seulement pour une identité E00-T01 utilisable, sondage espacé (zombies tués, heures de survie, métier, villes traversées sans coordonnée, 8 dernières phrases radio, missions closes), bornes sous 12 Kio, relevé figé à la mort quel que soit l'ordre des abonnés, intégration avec le vrai `RS_Carnet_Server`, suite `rs.lifelog` sur le banc) ; run_all 81/81 ; luacheck 16/0 ; conception `docs/annexes/conception/releve-de-vie.md` ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.lifelog 5/5 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.lifelog 5/5 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : relevé figé à la mort réelle d'un client. Petite ville traversée vite parfois manquée ; l'option de E15-T04 devra couper aussi le relevé ; E12-T04/T05 appelleront `LifeLog.rescue`.

- [x] **E15-T02** — Investigation : conteneur du cadavre côté serveur
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : —
  - Fichiers : `docs/annexes/recherches/derniers-pages-cadavre.md`
  - Faire : établir dans le Java 42.21 et en jeu quand l'inventaire du corps d'un joueur existe côté serveur après `OnCharacterDeath`, et comment y ajouter un objet visible des clients ; sinon, poser le document au sol à côté du corps.
  - Accepté si : méthode retenue démontrée sur serveur dédié.
  - Tests : suite en jeu `rs.lastpages.corpse`.
  - Preuve : investigation statique du Java 42.21.0 du 2026-10-12 (`docs/annexes/recherches/derniers-pages-cadavre.md`, preuves `IsoGameCharacter.java:13480-13542`, `IsoDeadBody.java:327-333`, `IsoPlayer.java:7756-7765`, `GameServer.java:2934-2942`) : `OnCharacterDeath` part sur le serveur avant la création du cadavre, qui reprend l'inventaire du mort ; méthode retenue = ajout à l'inventaire dans `OnCharacterDeath`, ajout tardif au conteneur du cadavre + `sendAddItemToContainer`, repli au sol ; suite `rs.lastpages.corpse` (+ `.arm`/`.check` manuelles) ; banc `tests/test_lastpages_corpse.py` 9 OK ; run_all 82/82 ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.lastpages.corpse 3/3 sur serveur dédié (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-15 (copie figée du commit `54087fb`, serveur dédié + 2 clients, pont avec faux modèle) : rs.lastpages.corpse 3/3 (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard2/server/20261015-090708-server.txt`) ; rs.death « client 2 dies on the server: OnCharacterDeath, identity retired, last-pages paper in its corpse seen by the requester (E00-T02, E15-T02) » PASS (vraie mort d'un client, feuille vue par l'autre client) (`tools/autoclient/runs/20261015-110446-parallel-2-54087fb0f84f/shard1/server/20261015-090647-server.txt`)
  - Reste : Limites : hôte supposé identique au dédié ; ajout tardif désigné par le rang du cadavre sur la case

- [x] **E15-T03** — Génération et document manuscrit verrouillé
  - État : `testé MP`
  - Cible : `MP`
  - Dépend de : E15-T01, E15-T02
  - Fichiers : `RS_LifeLog.lua` ; pont (type de demande `last_pages`) ; contrat
  - Faire : demande au pont à la mort ; texte borné ; document en lecture seule (`addPage` + `setLockedBy`), écriture manuscrite ; sans pont, journal de secours construit à partir des faits.
  - Accepté si : un document par mort, posé une fois ; contenu fidèle aux faits.
  - Tests : banc `lupa` ; suite en jeu.
  - Preuve : banc `tests/test_last_pages.py` du 2026-10-12 (18 tests OK : à la mort d'un personnage du carnet (`LifeLog.onFrozen`), jeton en ModData recopié sur le cadavre, une demande `kind=last_pages` (charge RSV2 de faits seuls : heures, tués, métier, villes, dernières phrases radio, missions closes et ouvertes, secours ; jamais coordonnée, fréquence, compte ni jeton), texte du pont nettoyé et borné à 2 400 caractères sinon journal de secours composé des faits (erreur, 90 s sans réponse, demande perdue au redémarrage), `Base.Notebook` écrit par `addPage` puis `setLockedBy`, nommé « Dernières pages de <nom> », posé dans le cadavre au jeton à 2 cases (sinon au sol, toujours au sol mort en feu), un seul document par mort) ; `RS_LastPages.lua`, `bridge/last_pages.py`, liste `T.lastPages` de `RS_Transport.lua` ; `lifelog` 19 OK, `lastpages_corpse` 9 OK ; suite `rs.lastpages` ; run_all 97/97 ; luacheck 16/0 ; conception `dernieres-pages.md` ; base `api-42-21.md` (`getUIName` du métier lisible par l'autorité) ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.lastpages 8/8 (`20261013-093732-solo.txt`) ; campagne MP automatique du 2026-10-14 (E01-T15, serveur dédié + 2 clients, client 2 seulement présent) : rs.lastpages 5/5 (`tools/autoclient/runs/20261014-144930-mp-045a8627ec16/server/20261014-125125-server.txt`) ; campagne MP automatique du 2026-10-14 soir (règle « les tests font foi ») : rs.lastpages 5/5 (`tools/autoclient/runs/20261014-184508-mp-1b6224aba9e1/server/20261014-164709-server.txt`)
  - Reste : à automatiser par le client 2 (E01-T16) : vraie mort d'un client lié au carnet, l'autre client ouvre le cadavre (« Last pages of A », seulement « Lire », un seul exemplaire) ; largeur de ligne de 40 caractères abandonné (règle du 2026-10-14 : jugée à l'œil dans la fenêtre) ; reconnexion abandonné (règle du 2026-10-14 : non exigée par le critère). Joueur relevé en zombie : document au sol ; métier d'un autre mod en clé brute en MP ; coupure par option : E15-T04.

- [x] **E15-T04** — Option sandbox pour couper la fonction
  - État : `testé solo`
  - Cible : `solo`
  - Dépend de : E15-T03
  - Fichiers : `media/sandbox-options.txt` ; traductions `Sandbox.json`
  - Faire : `RadioSurvivor.LastPages` (activé par défaut).
  - Accepté si : désactivée = aucun relevé ni document.
  - Tests : banc `lupa`.
  - Preuve : banc du 2026-10-12 : `tests/test_last_pages.py` 24 OK (`OptionTests` 6 : option désactivée = aucun relevé, relevés effacés, mort sans `onFrozen` ni jeton ni demande, demandes en attente retirées, relevés figés libérés sans document, `LifeLog.rescue` refusé ; coupure prise au passage suivant), `tests/test_lifelog.py` 19 OK ; option booléenne `RadioSurvivor.LastPages` (activée par défaut, page Radio Survivor, traductions EN/FR), `Const.lastPages()` lue à chaque passage ; suite `rs.lastpages` (5e test : option enregistrée, booléenne, défaut vrai) ; luacheck dev 0 ; conception `dernieres-pages.md`, `releve-de-vie.md` ; essai en jeu du 2026-10-13 (Lua/batman_RadioSurvivor/tests/) : rs.lastpages 8/8, option sandbox comprise (`20261013-093732-solo.txt`)
  - Reste : essai solo : `RST.run({ suite = "rs.lastpages", tags = "world" })` (5 PASS, note `RadioSurvivor.LastPages = true`) ; option désactivée puis mort d'un personnage lié au carnet : `lifelog: option LastPages off, n log(s) dropped`, aucun document ; option réactivée : document posé.
