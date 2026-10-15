# LK01 — Fondations du projet

**Objectif.** Poser ce dont toutes les étapes ont besoin : banc de tests hors jeu, squelette Lua, configuration, journal, règles d'écriture indépendante, et déclaration des incompatibilités.

**Dépend de.** LK00.

**Sources.** Banc `lupa` de RadioSurvivor (`RadioSurvivor/tests/test_protocol.py`, `test_carnet.py`) comme modèle de méthode ; base `logs-and-tools.md` (banc de tests Lua hors jeu, `next = nil`) ; skill `pz-workshop` (structure d'un projet).

## Décisions

- 2026-10-08 — **LK01-T04** : incompatibilité déclarée dans `mod.info` du mod `batman_RadioSurvivor` : `incompatible=\Bandits2,\ProjectALifeNPCs` (identifiants relevés dans `docs/bandits-analyse.md` et `docs/alife-analyse.md`).
- 2026-10-08 — `incompatible=` n'est appliqué que par le sélecteur de mods (base `mod-loading.md`) : **aucun contrôle à l'exécution** n'est ajouté (choix de l'utilisateur) ; un serveur qui charge Bandits! ou A-Life avec ce mod relève de la responsabilité de son administrateur.

## Tâches

- [x] **LK01-T01** — Banc de tests hors jeu : serveur et deux clients simulés
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `tests/harness.py`, `tests/test_harness.py`
  - Faire : machines Lua séparées (serveur, clients A et B) sous `lupa` avec `next = nil` ; faux objets du moteur : joueurs, zombies avec `isRemoteZombie`, propriétaire assignable et transférable, cases, cellule, événements (`OnTick`, `OnTickEvenPaused`, `OnZombieUpdate`, `OnClientCommand`, `OnServerCommand`, `OnCharacterDeath`, `EveryOneMinute`) ; `sendClientCommand` / `sendServerCommand` relayés avec copie des tables ; horloge réelle et horloge de jeu simulées ; fichiers `getFileReader` / `getFileWriter` dans un dossier temporaire.
  - Accepté si : un test peut changer le propriétaire d'un zombie et vérifier quel client exécute quoi ; aucune dépendance au jeu installé hors lecture de fichiers vanilla explicitement citée.
  - Tests : `tests/test_harness.py` (auto-tests du banc).
  - Preuve : `tests/test_harness.py` 24/24 (machines séparées, relais copié et non ordonné, propriétaire de zombie transférable, horloges, fichiers par machine, mode solo), `test_protocol.py`, `test_carnet.py` 19, `test_rst.py` 151, `test_rs_suites.py` 20, luacheck 21, `plan.py check` du 2026-10-08 ; LK01-T04 : commit `6d5ff74`
  - Reste : limites documentées en tête de `tests/harness.py` (Lua 5.1 et non Kahlua, transfert de propriété instantané, toutes les cases chargées, ModData non synchronisées) ; un client MP exécute aussi `media/lua/server` : garder le code serveur Living Knox par `isClient()`

- [x] **LK01-T02** — Squelette Lua, configuration et journal
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK01-T01
  - Fichiers : `media/lua/shared/LivingKnox/LK_Core.lua`, `LK_Config.lua`, `LK_Log.lua` ; `media/lua/server/LivingKnox/`, `media/lua/client/LivingKnox/` ; `media/sandbox-options.txt` (`LivingKnox.Enabled`, `LivingKnox.Debug`) ; traductions `Sandbox.json` FR/EN
  - Faire : espace de noms global unique `LivingKnox` (tables par module, appelées par la table pour rester enveloppables), modules chargés par `require` explicites, journal à niveaux (`[LivingKnox]`) désactivable, lecture des options sandbox (options Java d'abord, puis `SandboxVars`).
  - Accepté si : chargement sans erreur dans le banc côté serveur, client et solo ; luacheck sans avertissement.
  - Tests : banc ; luacheck.
  - Preuve : `tests/test_lk_core.py` 15/15 (serveur, client A, solo ; gardes de côté, journal, options Java → `SandboxVars` → défaut, relecture à chaud, pas de double inscription), luacheck 21 et 0 dans `LivingKnox/`, `test_harness.py` 24, `test_carnet.py` 19, `test_protocol.py`, `plan.py check` ; serveur dédié de test le 2026-10-08 : `[LivingKnox] INFO engine 0.1.0 started (side=server, enabled=true, debug=false)`, options présentes dans `SandboxVars.lua`, aucune erreur Lua ; LK01-T01 : commit `bd1de83`
  - Reste : défauts choisis `Enabled = true`, `Debug = false` (non fixés par le plan) ; à voir en jeu : ligne `client … ready` (client MP, solo) et page sandbox `LivingKnox` en FR et EN ; infobulle `Enabled` à revoir quand le moteur agira

- [x] **LK01-T03** — Règles et journal de conception indépendante
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/conception/README.md`
  - Faire : expliquer la règle d'écriture indépendante, les sources autorisées (vanilla 42.21, base de connaissances, nos mesures), ce que les analyses de Bandits! et A-Life peuvent apporter (liste de problèmes à prévoir, jamais de code), et le format d'une fiche de conception par sous-système (problème, contraintes moteur avec preuves, choix, alternatives, tests).
  - Accepté si : document relu par l'utilisateur.
  - Tests : —
  - Preuve : `docs/conception/README.md` rédigé le 2026-10-08 (règle d'écriture indépendante, sources autorisées, apport des analyses, format et gabarit de fiche, liens avec le plan et la base) ; `RadioSurvivor/CLAUDE.md` mis à jour (adaptateur `RS_Bandits.lua` retiré) ; LK01-T05 : commit `f810495` ; relu et validé par l'utilisateur le 2026-10-09, avec les trois propositions (rubrique « Idées reprises », statuts de fiche, interdiction étendue à la structure, aux noms internes et aux tables de données)
  - Reste : —

- [x] **LK01-T04** — Déclarer l'incompatibilité avec les autres mods de PNJ
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : E17-T02
  - Fichiers : `mod.info`
  - Faire : ajouter `incompatible=\Bandits2,\ProjectALifeNPCs` au `mod.info` 42.21, après le retrait de `loadModAfter=\Bandits2` par `E17-T02` (décision du 2026-10-08).
  - Accepté si : décision appliquée et testée au sélecteur de mods.
  - Tests : protocole : activer les deux mods dans le sélecteur.
  - Preuve : ligne `incompatible=\Bandits2,\ProjectALifeNPCs` ajoutée ; identifiants relevés dans les `mod.info` installés (seule variante `42.20` dans les deux mods, aucun alias) ; contrôle appliqué par le sélecteur de mods seulement (base `mod-loading.md`, 2026-10-08) ; `test_protocol.py`, `test_carnet.py` 19, `test_rs_suites.py` 20, luacheck 21, `plan.py check` ; E17-T02 : commit `ee0d8df` ; considéré validé par l'utilisateur le 2026-10-09 sans essai au sélecteur (contrôle appliqué par le sélecteur seulement, base `mod-loading.md`)
  - Reste : —

- [x] **LK01-T05** — Contrôles automatiques du dépôt
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK01-T02
  - Fichiers : `tests/run_all.py` ; `.github/workflows/checks.yml` (facultatif)
  - Faire : un seul script qui lance le banc, luacheck et `tools/plan.py check`, et échoue au premier écart ; nombre d'avertissements luacheck comparé à une référence.
  - Accepté si : `python RadioSurvivor/tests/run_all.py` donne un résultat clair.
  - Tests : exécution.
  - Preuve : `python RadioSurvivor/tests/run_all.py` le 2026-10-08 : 10 étapes PASS (protocole, carnet, banc, cœur LK, RST, suites RS, VM Kahlua, luacheck `Contents` ≤ 21 et `dev` = 0 selon `tests/luacheck_baseline.txt`, `plan.py check`), code 0 ; échec provoqué par `--luacheck-baseline 0` : arrêt à luacheck, code 1 ; `--keep-going`, `--only`, SKIP de la VM Kahlua sans ECJ vérifiés ; E01-T13 : commit `5190b8c`
  - Reste : pas de workflow GitHub (intégration continue distante hors périmètre)

- [x] **LK01-T06** — Banc : `isRemoteZombie()` fidèle au Java côté serveur et en solo
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK01-T01
  - Fichiers : `tests/harness.py`, `tests/test_harness.py` ; `tests/test_lk_essai.py` (retirer sa doublure de remplacement)
  - Faire : `isRemoteZombie()` = aucune connexion propriétaire (`NetworkZombieComponent.java:23`) : vrai sur le serveur pour un zombie que le serveur simule, faux pour un zombie possédé par un client, toujours vrai en solo ; `getOwner()` côté serveur ; adapter les auto-tests du banc qui supposaient l'inverse (base `multiplayer.md`, entrée corrigée le 2026-10-09).
  - Accepté si : les tests du banc décrivent la sémantique Java ; `test_lk_essai.py` n'a plus besoin de sa propre doublure.
  - Tests : `test_harness.py`, `test_lk_essai.py`, `tests/run_all.py`.
  - Preuve : `tests/harness.py` : `isRemoteZombie()` = aucune connexion propriétaire (client : faux pour le zombie qu'il simule ; serveur : vrai pour un zombie qu'il simule ; solo : toujours vrai), `getOwner()` et `getOwnerPlayer()` ajoutés ; 3 auto-tests de `test_harness.py` réécrits (24/24) ; doublure de remplacement retirée de `test_lk_essai.py` (19/19) ; mod principal sans usage de `isRemoteZombie` ; `tests/run_all.py` 11/11 le 2026-10-09 ; LK02 base B : commit `1450c13`
  - Reste : —

