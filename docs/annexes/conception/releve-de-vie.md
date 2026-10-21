# Relevé de vie d'un personnage (E15-T01)

Matière première des « dernières pages » (étape E15) : ce que le serveur sait de la vie d'un personnage du carnet, relevé pendant sa vie puis figé à sa mort. Code : `media/lua/server/RadioSurvivor/RS_LifeLog.lua` ; banc : `tests/test_lifelog.py` ; suite en jeu : `rs.lifelog` (`dev/batman_RadioSurvivorTests/.../suites/RS_LifeLog.lua`).

## Règles

- **Identité obligatoire** : seul un personnage du carnet (identité E00-T01 : `RS_CarnetServer.bound[joueur]`, fiche de `S.data.characters` du même compte, non retirée) a un relevé. Un joueur sans identité, un personnage d'un autre compte ou retiré n'en a aucun. En solo, la clé de propriétaire est `solo` (comme `RS_Carnet_Server`).
- **Autorité serveur** : toutes les valeurs viennent de la copie serveur du joueur (`IsoPlayer`) ou de l'état privé. Rien n'est lu d'un client.
- **Stockage** : état privé du carnet (`RS_State`, `S.data.lifelogs = { seq, logs = { [id] = relevé } }`), sauvegardé avec lui. Jamais en ModData globale ni dans la ModData du joueur (lisibles par les clients).

## Contenu

| Champ | Source | Remarque |
|---|---|---|
| `kills` | `IsoPlayer:getZombieKills()` | Tenu par le serveur, sauvegardé avec le joueur. |
| `hours` | `IsoPlayer:getHoursSurvived()` | Avancé par `GameTime` sur le serveur pour chaque joueur connecté (`GameTime.java:495-500`). Arrondi au dixième. |
| `profession` | `getDescriptor():getCharacterProfession():getName()` | Chemin de l'identifiant du registre (`doctor`), comme la fenêtre vanilla `ISPlayerStatsUI.loadProfession`. Jamais un texte traduit (`getText` rend la clé brute sur un serveur MP). |
| `towns` | `RS_Rescue.TOWNS` | Ville dont le centre est à moins de la moitié de son rayon (même règle que l'indice « It is in … » des secours), carte vanilla chargée seulement (`getLotDirectories`). Première visite seulement, dans l'ordre, sans coordonnée. |
| `phrases` | `RS_RadioLog` (lignes `said`) | Les 8 dernières phrases dites par le personnage à la radio, texte et heure de jeu. **Jamais la fréquence** (les fréquences des voix sont secrètes et n'entrent pas dans un prompt). |
| `missions` | `S.data.missions` | Missions closes dont le personnage est participant : gabarit, issue, nom du demandeur, type de lieu. Notées une fois (ensemble `noted`, purgé des missions disparues). |
| `open` | `S.data.missions` | À la mort : missions encore actives, notées `open`, jamais comme accomplies (décision E15 : le LLM ne peut inventer ni une mort ni une mission accomplie). |
| `rescues` | `LifeLog.rescue(id, 'saved' \| 'missed', libellé)` | Appelé par E12-T04 / E12-T05 ; aucun secours n'a encore d'issue avant E12. |
| `totals` | — | Compteurs de missions réussies, échouées, annulées, secours faits ou manqués : conservés quand les listes bornées oublient leurs plus anciens éléments. |

## Sondage espacé

Toutes les 15 s réelles (`POLL_MS`, `OnTickEvenPaused`), pour chaque joueur lié et vivant. Un passage en voiture très rapide à travers une petite ville peut échapper au sondage : la liste des villes est un résumé, pas un trajet. Un sondage sans changement ne marque pas l'état à sauvegarder (les heures ne comptent qu'au changement d'heure entière).

## Mort : relevé figé

Abonné propre à `OnCharacterDeath` (joueurs seulement). Dernier sondage du corps, missions ouvertes notées, puis le relevé est **figé** (`dead = true`, heure de la mort, numéro d'ordre) et sauvegardé. Il est gardé pour E15-T03, qui le lit (`LifeLog.get`, `LifeLog.frozen`, écouteur facultatif `LifeLog.onFrozen(id, relevé, corps)`), écrit les dernières pages, puis appelle `LifeLog.release(id)`. Au plus 8 relevés figés (`MAX_FROZEN`), la plus ancienne mort oubliée.

L'ordre des abonnés n'a pas d'importance : `RS_Carnet_Server.characterDeath` efface la liaison, l'identité en ModData et l'historique radio du mort. Le relevé retrouve le personnage par la liaison, la ModData serveur ou la liaison vue au dernier sondage ; les phrases déjà copiées restent. En jeu, `server/RadioSurvivor/RS_LifeLog.lua` s'exécute avant `server/RS_Carnet_Server.lua` (chemins triés sans casse, base `mod-loading.md`) : son abonné passe le premier. Le banc couvre les deux ordres.

Un relevé vivant dont le personnage disparaît ou est retiré sans mort vue est retiré au sondage suivant.

## Bornes

12 villes, 8 phrases de 200 caractères, 12 missions closes, 4 missions ouvertes à la mort, 8 secours, libellés de 80 caractères : un relevé reste sous 12 Kio en RSV2 (`MAX_BYTES`, vérifié par le banc au pire cas).

## Décisions à confirmer

- Relevé **figé** à la mort plutôt que retiré, jusqu'à `release` par E15-T03 (8 au plus).
- Sondage toutes les 15 s réelles ; ville comptée à moins de la moitié de son rayon ; carte vanilla seulement.
- Métier gardé comme identifiant (`doctor`), traduit plus tard côté client ou par le pont.
- Seules les phrases dites par le personnage (pas les réponses des voix ni les lignes entendues).

## Reste

- E15-T04 (fait) : l'option sandbox `RadioSurvivor.LastPages` désactivée coupe le relevé et efface les relevés conservés (détail : `dernieres-pages.md`, section « Option sandbox »).
- E12-T04 / E12-T05 : appeler `LifeLog.rescue` pour chaque membre de l'équipe.
- Validation en jeu (suite `rs.lifelog`, MP).
