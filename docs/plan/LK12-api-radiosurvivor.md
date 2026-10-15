# LK12 — API publique et intégration RadioSurvivor

**Objectif.** Exposer une API stable et des événements pour que RadioSurvivor (et d'autres mods) lisent les groupes et PNJ, réagissent aux faits et proposent des missions.

**Dépend de.** LK08-T01, LK07-T04.

**Sources.** Plan RadioSurvivor (étape `E17`) ; analyse d'A-Life (absence d'API = problème à éviter).

**Précision.** Tâches à affiner après la décision de jalon `LK02-T09` ; découper toute tâche qui dépasse une session de travail.

## Décisions

- 2026-10-14 — **LK12-T02** : déclenchement différé au pas suivant ; besoin critique fondé sur les réserves publiques (sous 25, sortie à 40) ; « membre mort » limité aux membres d'un groupe ; « groupe disparu » = plus aucun vivant ou retrait ; « rencontre » = début d'une sommation ; `reason` vide pour les départs hors écran (LK09-T05), `"leave_group"` pour E10-T04 (confirmé par défaut, valeurs techniques).

## Tâches

- [x] **LK12-T01** — API versionnée en lecture
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK08-T01
  - Fichiers : `LK_API.lua`, `docs/api.md`
  - Faire : version d'API, liste des groupes et membres (identifiants stables, noms, rôles, foyer approximatif, besoins, attitude), PNJ à portée d'un joueur.
  - Accepté si : documentée ; aucune donnée secrète exposée aux clients.
  - Tests : banc.
  - Preuve : `LK_API.lua` (serveur seulement) : `API.VERSION = 1` et règle de compatibilité (ajouts seuls dans une version), `isReady`, `listGroups`, `getGroup` (membres), `npcsNear` (PNJ incarnés, rayon plafonné à 50, un passage par registre, sans accès à la carte), `publicGroup` (projection client par liste blanche), `area` ; foyer rendu seulement par maille de 100 cases, résumé public seul (`story`), ni journal, ni secrets, ni blessures ; `attitude` réservée à `nil` (LK11-T03, en attente d'E09-T01) ; copies détachées ; `tests/test_lk_api.py` 18/18 (aucun secret ni coordonnée exacte dans les résultats, contre-épreuve sur le groupe brut), VM Kahlua 24/24 ; `tests/run_all.py` 34/34 le 2026-10-10, luacheck 17/0 et 0, `check_case.py` PASS ; `docs/api.md` ; LK08-T03 : commit `9beb6c6`
  - Reste : nom du chef et nom de lieu absents (non tenus par le registre) ; position d’un corps non lié = dernière vue, peut-être ancienne ; à observer en jeu avec E17-T03

- [x] **LK12-T02** — Événements publics
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK12-T01
  - Fichiers : `LK_API.lua`
  - Faire : événements Lua déclarés (`LuaEventManager.AddEvent`) : groupe créé, membre mort, groupe disparu, besoin critique, rencontre, membre parti (ajout du 2026-10-10 : départ hors écran de LK09-T05 et départ d'E10-T04, utile à E08-T07 et E10-T04 sans lecture du journal privé) ; idempotents.
  - Accepté si : un mod tiers s'abonne sans dépendance dure.
  - Tests : banc.
  - Preuve : banc `tests/test_lk_api.py` du 2026-10-12 (41 tests OK, `EventTests` et `ThirdPartyEventTests` : six événements `OnLivingKnox*` déclarés par `AddEvent` sur l'autorité, un seul déclenchement par fait, contenu public sans secret (foyer en maille de 100 cases), abonnement d'un mod tiers avant, après ou sans Living Knox) ; `test_kahlua.py` 33 OK (`KR-EVENTS`) ; run_all 64/64 ; luacheck 16/0 ; `docs/api.md` (Événements publics)
  - Reste : `LuaEventManager` réel vérifié statiquement seulement ; mémoire des événements limitée à la session ; mort d'un PNJ hors groupe sans événement public.

- [x] **LK12-T03** — Demandes de ressources pour les missions
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK12-T01, LK09-T01
  - Fichiers : `LK_API.lua`
  - Faire : le serveur expose les besoins d'un groupe sous forme d'offres admissibles (objets, quantités, délai, récompense), et accepte une livraison validée pour remonter les réserves.
  - Accepté si : une livraison remonte les réserves une seule fois.
  - Tests : banc.
  - Preuve : `LK_API.lua` (ajouts compatibles, version 1) : `API.missionOffers(gid[, playerKey])` : une offre par réserve sous 40 (identifiant `<groupe>-<réserve>-<n>` stable), valeur demandée en points du barème (40 V, 60 V sous 25), délai 48 h de jeu, objets vanilla acceptés vérifiés dans les scripts (`food` : conserves et vivres secs ; `medical` : antibiotiques, bandages, désinfectant, comprimés, aiguille ; `ammo` : boîtes de munitions), récompense : fait d'attitude `delivery` et objet d'une réserve haute (jamais si elle passerait sous 40), aucune offre si hostile ; `API.deliver(gid, offerId, items, receiptKey)` : 1 point de réserve = 4 V arrondi sur le cumul, réserve bornée à 100, idempotent par `receiptKey` (rejeu sans effet, même après relecture), une seule sauvegarde, journal `supply` ; inventaires laissés à l'appelant ; `tests/test_lk_api.py` 31/31 (`SupplyTests` : rejeu, double appel, expiration, mauvais objets, dépassement), VM Kahlua 29/29 ; `tests/run_all.py` 40/40 le 2026-10-10, luacheck 17/0 et 0 ; `docs/api.md` ; LK03-T05 : commit `b7f88b4`
  - Reste : valeurs à recalibrer avec E17-T03 (seuil 40, 40/60 V, 48 h, marge 0,30) ; pas encore de stock réel d’objets (LK08-T07, LK09-T06) : récompense prise sur une réserve abstraite ; réputation et fait `delivery` à enregistrer par l’appelant (E17-T03)

- [ ] **LK12-T04** — Fournisseur Living Knox côté RadioSurvivor
  - État : `abandonné`
  - Cible : `MP`
  - Dépend de : LK12-T03, E17-T02
  - Fichiers : RadioSurvivor (étape E17)
  - Faire : voir `E17` : le carnet sélectionne, parle et donne des missions aux PNJ de Living Knox.
  - Accepté si : parcours du carnet 0.2 rejoué avec un PNJ Living Knox.
  - Tests : suites des deux projets.
  - Preuve : —
  - Reste : doublon de `E17-T03` depuis la fusion du 2026-10-08 (même mod, même plan) ; le travail est suivi dans `E17-T03`.
