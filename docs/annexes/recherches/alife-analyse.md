# Project A-Life : analyse pour un « monde vivant » de groupes persistants

Copie lue **en lecture seule** le 2026-10-03 : Workshop `3803984183`, « Project A-Life [ALIFE NPCS] », `id=ProjectALifeNPCs`, auteur Vice, `modversion=1.3.15` (la page annonce 1.3.16), `versionMin=42.21.0`, variante `42.20` + `common/`. Téléchargée par steamcmd anonyme dans `C:\pzserver\steamapps\workshop\content\108600\3803984183` (hors du dossier du jeu). 248 fichiers Lua, ≈ 146 000 lignes, **sans aucun commentaire**. Chemins relatifs à `mods/ProjectALifeNPCs/42.20/media/lua/` (préfixes `server/`, `shared/`, `client/` + `ProjectALife/`). Lignes à revérifier après chaque mise à jour.

## Résumé

| Besoin du monde vivant | Ce qu'A-Life fournit | Écart |
|---|---|---|
| IA correcte en MP | Propriétaire unique + monde autoritaire serveur + relais des gestes + dégâts appliqués par le serveur | Faiblesses limitées (§1) |
| Couper le peuplement aléatoire | Options sandbox + directeur de factions à couper par enveloppe | Faisable (§2) |
| Quelques groupes permanents avec foyer | Avant-postes (9 modèles) et garnisons, construits par appels publics | Durée de vie, regarnissage à la reprise, identités : à valider |
| Histoire, chef, membres | Factions et profils en données ; rôles (chef, garde, éclaireur, médecin) | Pas de groupe nommé ni d'histoire |
| Besoins | Escouades hors écran : `supplies` et `morale` seulement | Nourriture, soins, munitions à écrire |
| Vie hors écran | Escouades sur graphe routier, combats abstraits, vengeance | Pas d'expéditions liées à un foyer |
| Relève après décimation | Nouvelles escouades aléatoires | Règle propre à écrire |
| Dialogue LLM, missions, réputation positive | Dialogue par mots-clés et répliques prévues, barks, radio de diffusion | Pas de missions, réputation qui ne fait qu'empirer, pas d'API |

## 1. Exécution multijoueur

- Adoption par le seul propriétaire du corps (`shared/…/Shells/ALifeShellSimulation.lua:201-206`) ; serveur dédié en délégation (`shared/…/Core/ALifeExecutor.lua:236-240`, `server/…/Core/ALifeRuntime.lua:726-790`).
- Rapports du propriétaire vérifiés (propriétaire réel, génération, cadence, révision) : `ALifeExecutor.lua:355-560`. Dégâts aux joueurs par le serveur (`ALifeExecutor.lua:1326-1468`, `DamageFromWeapon` + `sendDamage`). Munitions comptées côté serveur (`shared/…/Shells/ALifeNPCHitRelay.lua:278-372`).
- Gestes : pose du propriétaire → serveur → `animationSync` diffusé à tous (`shared/…/Shells/ALifeAnimations.lua:1041-1178`, `client/…/Shells/ALifeAnimationClient.lua:223-498`) ; animations conditionnées par `ALifeActor`, `ALifePace`… (`common/media/AnimSets/zombie/…`).
- Changement de propriétaire : libération après 3 audits, adoption, rancune conservée 10 s, audit serveur à 15 s (`ALifeExecutor.lua:1047-1102, 2152-2185, 2557-2562`).
- Couche `ALifeAIFence` (3 390 lignes) qui neutralise les comportements de zombie des corps de PNJ (`shared/…/Shells/ALifeAIFence.lua`).
- Faiblesses : confiance au propriétaire, perte d'état au transfert, corps possédés par le serveur inertes, coups sur zombies vanilla sans test de propriétaire (`server/…/Combat/ALifeCombatStrike.lua:485-510`), inventaires divergents, diffusion des gestes sans filtre de distance, santé MP × 0,06 et marge +1 000.

## 2. Peuplement et réglages

- Six générateurs : directeur de factions, directeur de rencontres, escouades hors écran, avant-postes, peuplement de bâtiments, raids et renforts.
- Coupure : `Encounters_Enabled=false`, `Encounters_RollPercent=0`, `World_Mode=2` (ou `Offline_SquadCap=0`), `Raid_Enabled=false`, `Realistic_Outbreak=false`, `Outposts_Chance=0`, `Population_PopulateOnStart=Off`, `Encounters_EarlyLooters=0` ; le directeur de factions est toujours actif (`server/…/Core/ALifeSettings.lua:149, 423-430`) : envelopper `ProjectALife.Settings.runtimeOptions`. Fuite possible : repaires générés par les rumeurs (`server/…/Talk/ALifeRumors.lua:136-173`).
- 118 options sandbox ; détail dans `42.20/media/sandbox-options.txt`.

## 3. Monde

- 148 factions et 780 profils en texte (`common/alife_runtime/catalog/faction_registry.alife`, `npc_profiles.alife`, format `@alife-records 1`), lus par `getModFileReader` (`shared/…/Records/ALifeCatalog.lua:106-125`).
- Avant-postes : 9 modèles (`shared/…/Outposts/ALifeOutpostPresets.lua:63-421`), états proposé → construit → garni → expiré ; les avant-postes automatiques sont toujours hostiles ; ceux d'un admin expirent aussi (durée du modèle) sauf directeur coupé.
- Escouades hors écran : `ProjectALife.Squads.v1`, 8 membres au plus, `supplies`, `morale`, tâches (renfort, repos, fortification, récupération, patrouille, voyage) (`server/…/Offline/ALifeSquadLedger.lua`, `ALifeOfflineDirector.lua:629-870`).
- Persistance : ModData `ProjectALife.*.v1` avec schéma ; identités `palife:<ms>:<seq>` ; les membres d'escouade hors écran reçoivent de **nouveaux** enregistrements à chaque matérialisation, l'identité stable étant `memory.identitySeed` (`server/…/Offline/ALifeRenderProtocol.lua:132-152`).
- Dialogue : saisie capturée par enveloppe de `processSayMessage`, intentions par mots-clés, répliques prévues ; seuls effets : petits dons, tolérance, méfiance, rumeurs (`server/…/Talk/ALifeTalk.lua`). Radio : chaîne de diffusion « Knox County Radio » sur 99,6 MHz (`server/…/Talk/ALifeKnoxCountyRadio.lua`), radio d'avant-poste par menu.
- Éditeur de factions et de PNJ complet, partage par code texte (`client/…/Interface/Creator/ALifeCreatorCore.lua`).

## 4. Extension

- **Aucune API ni événement** (`triggerEvent`, `LuaEventManager`, `AddEvent` absents). Tous les modules sont des tables globales `ProjectALife.<Module>` appelées par la table : enveloppables.
- Registres : `ModuleRegistry.register` (comportements, autorisés par profil), `DialogueData.*`, `TalkIntents.choices`, `Encounters.definitions`, `OutpostPresets`, `BehaviorProfiles.definitions`.
- Flux d'événements de fait : `ProjectALife.Telemetry.emit(catégorie, champs)` (`server/…/Core/ALifeTelemetry.lua:55`).
- Pilotage MP : mémoire du PNJ par `ActorRegistry.update` (clés protégées relayées au propriétaire). Éviter de stocker nos données dans `actor.memory` (réécrite par les rapports).
- Contrainte : code de l'addon hors de tout dossier `ProjectALife/`, sinon A-Life le déclare incompatible (`shared/…/Compat/ALifeModCompat.lua:158-215`).

## 5. Licence et projet

- Aucun texte de licence ; tous droits réservés par défaut. La page invite les moddeurs à contacter l'équipe (Discord `discord.gg/alife`, `xxvice`) et déconseille un second mod de PNJ sur la même partie.
- Créé le 2026-09-18, mis à jour le 2026-09-30, ≈ 117 000 abonnés ; « Friendly Update » annoncée (compagnons, ordres). API interne instable à prévoir.
- Aucune dépendance déclarée, aucun binaire, aucun processus externe.
