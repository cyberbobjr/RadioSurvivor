# PNJ de test (E01-T10)

- Tâche : E01-T10 (fixture PNJ du moteur de tests en jeu) — Date : 2026-10-12 — Statut : testé hors jeu (banc lupa), **décision à confirmer**.

## Besoin

La fixture `RST.Fixtures.spawnNpc` du mod de développement doit faire apparaître un PNJ près du joueur **par l'API publique de Living Knox**, le retrouver par l'interface du carnet `RS_NPCProvider`, puis le retirer. L'API publique (`LK_API.lua`, [api-living-knox.md](../../specifications-techniques/api-living-knox.md)) n'avait aucune fonction de création : les suites `lk.*` appellent directement `LivingKnox.Bodies.spawn`.

## Choix retenu (le plus simple, proche du moteur existant)

- **Fichier séparé** `server/LivingKnox/LK_APITest.lua` dans le mod publié, qui ajoute à `LivingKnox.API` quatre fonctions (`testAllowed`, `testSpawnNpc`, `testRemoveNpc`, `testNpcs`) : `LK_API.lua` garde sa règle « écritures par `LivingKnox.Groups.update` seulement » et ses contrôles de source inchangés.
- **Garde** : autorité seulement et partie dont le nom commence par `rstest` (même règle que la garde `world` du moteur RST). Aucun mode debug exigé (un serveur dédié de test n'est pas forcément lancé en `-debug`).
- **PNJ sans groupe**, créé par `LivingKnox.Bodies.spawn` (case libre la plus proche, mêmes refus) ; retrait par `Bodies.despawn(id, true)` après effacement de ses consignes.
- **Retrait limité** aux PNJ créés par `testSpawnNpc` dans la session Lua : la fonction ne peut pas servir à retirer un PNJ de la partie.
- Rien d'autre que des chaînes et des nombres n'est rendu (règle de l'API) : le corps se retrouve par le fournisseur.

## Côté fixture

- `F.npcReady()` dit pourquoi la fixture ne peut pas agir : client MP, `RS_NPCProvider` absent, fournisseur vide (`none`), autre fournisseur que Living Knox, API de test absente.
- `F.spawnNpc(t, player[, suite])` exige une suite `world` autorisée (`RST.worldGuard()`), crée le PNJ à 2 cases à l'est du joueur, enregistre le retrait (`t:defer`) aussitôt, puis attend (`t:waitQuiet`, 10 s) que le fournisseur voie le corps sous cet identifiant.
- La suite `rst.fixtures.npc` est SKIP avec la raison de `F.npcReady()` quand Living Knox n'est pas le fournisseur actif.

## Limites

- La liste des PNJ de test vit en mémoire : un rechargement du Lua pendant un test laisse un PNJ ordinaire au registre.
- PNJ sans groupe : le moteur peut lui donner des consignes ou le rendre à la vie hors écran s'il s'éloigne des joueurs ; la suite dure quelques ticks.
