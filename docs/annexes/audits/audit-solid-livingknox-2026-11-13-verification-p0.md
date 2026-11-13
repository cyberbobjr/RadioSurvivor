# Vérification contradictoire des 34 P0 de l'audit SOLID Living Knox (2026-11-13)

Lecture seule. Aucun git écrit, aucun test lancé, aucun fichier du dépôt modifié.
Audit vérifié : `RadioSurvivor/docs/annexes/audits/audit-solid-livingknox-2026-11-13.md` (section « P0 critique (34) »).
Code lu : `RadioSurvivor/Contents/mods/batman_LivingKnox/42.21/media/lua/` (chemins ci-dessous relatifs à `lua/`, avec `server/LivingKnox/`, `client/LivingKnox/`, `shared/LivingKnox/` implicites quand le nom suffit).

Toutes les lignes citées ont été relues. Les numéros de l'audit sont corrects à quelques lignes près pour la grande majorité des constats.

## 1. Tableau des verdicts

Légende : CONFIRMÉ = fait et gravité juste ; RÉDUIT = fait réel mais gravité, périmètre ou chiffre à corriger ; RÉFUTÉ = le constat ne tient pas comme « genre ouvert » ou comme défaut.

| # | Constat | Verdict | Motif court |
|---|---|---|---|
| 1 | A01 `workOf` (Fortify) | CONFIRMÉ | 4 sortes, chaînes sur `site.kind` ; genre plausible à étendre |
| 2 | A02 `site.target` / `site.kind` | CONFIRMÉ | Même chantier que A01 |
| 3 | A03 tables de codes parallèles | CONFIRMÉ | Risque réel : décodage et validation de la forme compacte |
| 4 | B-C01 `Decisions.apply` | CONFIRMÉ | Huit comportements en chaîne ; `registerExtension` existe déjà |
| 5 | B-C02 `Decisions.context` | CONFIRMÉ (chiffre corrigé) | Environ 13 modules nommés, pas 14 |
| 6 | B-C03 angle de visée `decide` | CONFIRMÉ | Cinq cas sur `b` (lignes 884-899) |
| 7 | B-C04 geste d'alerte | CONFIRMÉ | Six comportements listés (1821-1827) ; même chantier que B-C01 |
| 8 | B-C05 postes et objectifs | RÉDUIT | `OBJECTIVES`, `DUTIES`, `DUTY_NEEDS` sont déjà des tables ; objectifs = vocabulaire de design fermé |
| 9 | B-C06 `RULES.threat` | RÉDUIT | Pipeline ordonné à retours anticipés ; `registerExtension` accepte déjà `before` |
| 10 | C-X01 `spotFor` (Expéditions) | CONFIRMÉ | Trois genres (bâtiment, cueillette, pêche), une dizaine de sites |
| 11 | C-X02 `tryDepart` | RÉDUIT | Deux blocs parallèles, mais portes d'entrée différentes (pêche à l'heure, cueillette au jour) |
| 12 | C-X05 `deliver` | RÉDUIT | Trois origines codées par deux drapeaux ; origines fermées par le mécanisme |
| 13 | D-OBS-01 modèles d'itinéraire | CONFIRMÉ | Sept modes en chaîne dans `edgeCost` et six autres sites |
| 14 | D-OBS-02 nature d'obstacle | RÉDUIT | Énumération fermée par le moteur PZ (porte, fenêtre, clôture, mur, rien) ; le problème est la duplication, pas l'absence de registre |
| 15 | D-OBS-03 politique de passage | RÉDUIT | Trois politiques fermées par conception (force, wait, detour), sélection par seuils |
| 16 | E-F01 aménagements (Homes) | CONFIRMÉ | Six sortes, sept endroits, liste littérale dupliquée en 700 |
| 17 | E-F02 signes de raid (Raids) | RÉDUIT | `Raids.SIGNS` est une table morte ; le score est une somme pondérée, pas un dispatch |
| 18 | F-R01 `Routines.plan` | RÉDUIT | Un registre d'activités existe déjà (`registerActivity`) ; le plan peut y migrer |
| 19 | F-R02 `plan.kind` | RÉFUTÉ | Quatre primitives d'exécution (face, sit, round, point) : énumération fermée par nature |
| 20 | F-R03 corvées | CONFIRMÉ | Huit corvées, six tables à éditer par corvée |
| 21 | F-R04 `leave` / `forget` | RÉDUIT | Deux modules (Upkeep, Fortify), sous le seuil des trois cas ; correction bon marché |
| 22 | F-R05 événements de groupe | CONFIRMÉ | Cinq événements, `applyEvent` en chaîne |
| 23 | F-R06 retours d'expédition | CONFIRMÉ | Chaîne à trois branches, cycle Simulation <-> Relations réel |
| 24 | F-R07 ordre horaire | CONFIRMÉ | Quatre modules nommés dans la boucle du moteur ; ordre significatif |
| 25 | F-R08 faits publics (API) | CONFIRMÉ | Cinq genres de faits en chaîne `f.kind ==` |
| 26 | F-R09 opérations admin | CONFIRMÉ (correction) | Douze opérations en chaîne ; la branche `else` n'avale PAS les inconnues (rejet ligne 901), mais une opération ajoutée à `Admin.OPS` sans branche tombe silencieusement dans `moveHome` |
| 27 | G-Z01 genres de requête (Talk) | CONFIRMÉ | Six genres de requête, ordre significatif |
| 28 | G-Z02 intents (Talk) | RÉDUIT | Vocabulaire du protocole LLM (contrat avec le pont), fermé par nature |
| 29 | G-Z09 corvées (`chorePlan`) | CONFIRMÉ, doublon | Même code que F-R03 ; à compter une fois |
| 30 | H-D01 opérations de l'exécutant | RÉDUIT | Trois verbes de protocole (move, stop, face) ; registre spéculatif tant qu'il n'y a pas de quatrième verbe |
| 31 | H-D02 escalade de blocage | RÉFUTÉ | Séquence ordonnée repath -> unblock -> fail : algorithme à trois états, pas un genre ouvert |
| 32 | H-D03 tris de tableaux (debug) | RÉDUIT | Vrai, mais vue de débogage ; trois clés au plus par tri |
| 33 | H-D04 `Sheet.fieldValue` | RÉDUIT | Trois cas spéciaux plus repli générique ; outil admin |
| 34 | H-D05 réponses admin (client) | RÉDUIT | Cinq opérations, UI admin ; coût faible, gravité moyenne |

Compte : CONFIRMÉ 18 (dont un doublon : G-Z09 = F-R03, et A02 fait partie du chantier A01) ; RÉDUIT 14 ; RÉFUTÉ 2 (F-R02, H-D02). Total 34.

Effet réel sur le plan : 18 constats CONFIRMÉ se regroupent en 9 à 11 chantiers distincts (voir section 3). Le chiffre « 34 P0 » est gonflé de deux manières : (a) des doublons (G-Z09 = F-R03, A01/A02/A03 = un même chantier), (b) des énumérations fermées classées en P0 sous la règle « au troisième cas ».

## 2. Preuves par constat

### Zone A, Fortify

**A01 à A03 : CONFIRMÉ, un seul chantier.**
- `LK_Fortify.lua:1570-1577` (`workOf`) : `if site.kind == "barricade"`, `if site.kind == "repair"`, puis défaut `RING_GESTURES`. Trois branches confirmées.
- Quatre tables parallèles réelles : `Fortify.KINDS` (ligne 88), `Fortify.OFF_KINDS` (1731), `KIND_CODE` / `CODE_KIND` (1784-1785), `SITE_PATTERN` / `OP_PATTERN` (1788-1789) avec `[bwp]` en dur, plus `Fortify.STAGES` (1114) et `RING_GESTURES` (119).
- Risque réel (A03) : la forme compacte est décodée par `string.match(txt, SITE_PATTERN)` puis `if k == nil then return nil end` (1841-1842). La validation d'écriture rejette par `not Fortify.OFF_KINDS[e.k]` (1762, 1769) : un genre ajouté à `KINDS` sans passer par `OFF_KINDS` et les motifs est perdu au rechargement, sans erreur Lua. Non vérifié à l'exécution, c'est une déduction de lecture ; le banc `test_lk_fortify_offscreen.py` devrait le montrer s'il est écrit pour.
- Nuance : quatre genres, dont deux (barricade, réparation) sont des mécaniques vanilla distinctes. Un nouveau genre (porte blindée, tranchée) exige de toute façon un travail de design et de ressources vanilla ; le registre gagne surtout sur la cohérence des tables.
- Effort : `LK_Fortify.lua` seul (2726 lignes), plus son découpage prévu. Bancs : `test_lk_fortify.py`, `test_lk_fortify_offscreen.py`, `test_lk_barricade.py`, `test_lk_walls.py`, `test_lk_repair.py` (existent, 8 fichiers Fortify au total).
- Risque : moyen. Le format compact est persistant ; le projet n'est pas publié, donc pas de migration à écrire (règle « no legacy before release »), mais le banc de forme compacte doit rester vert.

### Zone B, Decisions

**B-C01 : CONFIRMÉ.** `LK_Decisions.lua:1816-1909` (`Decisions.apply`) : chaîne `if b == "fight"` (1841), `"defend"` (1847), `"surrender"/"retreat"` (1870), `"watch"/"alert"` (1876), `"flee"` (1899), `"guard"/"patrol"` (1901), huit comportements. `Decisions.registerExtension` existe (ligne 809) avec `behaviour { vigil, apply }`, mais n'a qu'un utilisateur : `LK_ProvisionMeal.lua:248`. Le patron est donc là, sous-utilisé.

**B-C02 : CONFIRMÉ, chiffre corrigé.** `Decisions.context` (1573) nomme environ 13 modules du mod (Routines, Expeditions, Relations, Senses, Combat, Zombies, Alert, Defense, Encounters, Needs, Bodies, etc.), pas 14. Le fait structurant (dépendances `LivingKnox.X ~= nil`) est réel.

**B-C03 : CONFIRMÉ.** `Decisions.decide` (fonction d'angle, 878-899) : `if b == "watch" and t`, `elseif b == "alert"`, `elseif (b == "flee" or b == "retreat")`, `elseif b == "surrender"`, `elseif b == "guard"`. Cinq cas.

**B-C04 : CONFIRMÉ.** `LK_Decisions.lua:1821-1827` : `if st.b == "alert" or ...` puis `elseif st.b == "surrender" or st.b == "retreat" or st.b == "defend" or st.b == "warn"`. Même chantier que B-C01 (le geste doit être porté par l'applicateur, pas listé ici).

**B-C05 : RÉDUIT.** La liste n'est pas « codée en dur » au sens strict : `Decisions.OBJECTIVES` (utilisée ligne 353), `Decisions.DUTIES` (ligne 96), `Decisions.DUTY_NEEDS` (98-103) sont déjà des tables. Restent des branches `if objective == "guard"` (458-462) et des bonus en dur (`add("fortify", ...)` ligne 392). Les objectifs sont le vocabulaire de design du groupe (repos, garde, soin, ravitaillement, fortification), fermé. Gain réel mais faible ; à traiter avec les tables existantes.

**B-C06 : RÉDUIT.** `RULES.threat` (`LK_Decisions.lua:639`) : une suite de retours anticipés (reddition, retraite, défense, sommation, combat), dont l'ordre est l'invariant. Ce n'est pas un « genre » à registre. Le défaut signalé (impossible de s'insérer entre `warn` et `defend`) existe, mais `registerExtension` accepte déjà des règles `{ name, before, rule }` (ligne 811) : l'insertion avant une règle nommée est possible. Un `THREAT_STEPS` serait une abstraction spéculative.

### Zone C, Expéditions et stock

**C-X01 : CONFIRMÉ.** `LK_Expeditions.lua:1062-1078` (`spotFor`) : `if t.kind == Ex.FISH` (1065), `if t.kind == Ex.FORAGE` (1073), défaut bâtiment. Trois genres. Sites de genre supplémentaires : 632/636 (`tryDepart`), 988 (`drawRound`), 1016-1017 (texte), 1051 (durée), 1248 (`seen`). Une dizaine de lieux, cohérent avec le constat. Les genres pêche et cueillette sont liés à `LivingKnox.Food` (dépendance `Ex` -> `Food` lue à l'exécution, réelle).
- Effort : `LK_Expeditions.lua` (1506 lignes) plus un registre `Ex.registerKind`. Bancs : `test_lk_expeditions.py`, `test_lk_food.py`, `test_lk_garden.py`, `test_lk_loot.py`.
- Risque : moyen (mécanique de sortie, phases, persistance `Ex.FORMAT`).

**C-X02 : RÉDUIT.** `LK_Expeditions.lua:582-595` (pêche : `fishHour(hod)` ; `pcall(F.fishTarget)`) et `602-612` (cueillette : `pcall(F.pickTarget)`). Les deux blocs ont la même forme (pcall, journal, cible, `want`), mais la porte d'entrée est différente (heure de pêche contre « hors jour ») et la pêche remplace `want`. « Quasi identiques » est exagéré. Une boucle sur des genres est possible, mais le gain est petit tant que C-X01 n'a pas le registre.

**C-X05 : RÉDUIT.** `LK_Expeditions.lua:1191-1212` (`deliver`) : `if e.a and e.f` (cueillette ou pêche, objet créé par `F.make`), `elseif e.a` (abstrait), `elseif e.i ~= nil` (objet porté). Trois origines réelles, codées par deux drapeaux, mais l'ensemble est fermé par le mécanisme (objet vanilla créé, objet abstrait, objet déjà porté). Un registre `registerCarrySource` serait spéculatif.

### Zone D, Obstacles

**D-OBS-01 : CONFIRMÉ.** `LK_Obstacles.lua:1532-1598` (`edgeCost`) : chaînes `mode == "exit-loose"`, `"zombie"`/`"zombie-door"`, `"trapped"`, `"exit"`, défaut `detour`/`npc`. Sept modes, réutilisés à 2065-2131 (`planDoorRoute`). Le genre « modèle d'itinéraire » est un choix de conception qui peut s'enrichir (foule, véhicule). Chantier lourd (2849 lignes) ; à faire avec D-OBS-05 (découpage), pas seul.

**D-OBS-02 : RÉDUIT.** `LK_Obstacles.lua:1487-1495` (`edgeElement`) : `door`, `window`, `fence`, `wall`, `plain`. Ces cinq genres sont les arêtes de tuile que le moteur PZ expose (portes, fenêtres, clôtures franchissables, murs bloquants). Ils sont fermés par le moteur, donc un registre est spéculatif. Le vrai défaut est la duplication des paires `decide`/`decideWindow`, `setDoor`/`setWindow`, `check`/`checkWindows`, `closePass`/`closeWindowsPass`. Le remède est un dédoublonnage local, pas un registre.

**D-OBS-03 : RÉDUIT.** Chaînes `"force"` / `"wait"` / `"detour"` en trois endroits : `LK_Obstacles.lua:1147-1152` (`blockedPolicy`, sélection par seuils de `hostility`), `1277-1294` (`blockedPass`), `1416-1438` (suivi). Trois politiques, documentées (en-tête, lignes 1098-1103) comme vocabulaire de conception fermé. Le seuil est un choix de hostilité, pas un dispatch sur un genre. Gain modeste.

### Zone E, Combat, Défense, Raids, Foyers, Hostilité, Alerte

**E-F01 : CONFIRMÉ.** `LK_Homes.lua:71` (`Homes.KINDS`, six sortes) ; dispatch par `a.k == "barricade"` (501), `"fire"` (504), `"lamp"` (520-522) ; liste littérale `{ "barricade", "lamp", "bed", "crate", "fire", "tent" }` en 700 (dupliquée, déjà présente dans `KINDS`) ; traitement de retrait en 751-753 ; plan en 278-350. Sept endroits, sept sortes d'aménagement plausibles (table, établi). Bancs : `test_lk_homes.py` (13 fichiers de test touchent `Homes` ou ses dépendances).

**E-F02 : RÉDUIT.** `LK_Raids.lua:87` : `Raids.SIGNS = { "safehouse", "generator", "barricades", "constructions" }`. Grep sur le fichier : la table n'est jamais lue ailleurs. Le score (`LK_Raids.lua` vers 317-332) est une somme de quatre termes avec seuils, pas un dispatch sur un genre. Correction utile : supprimer la table morte (ou la brancher) ; un registre de signes est inutile.

### Zone F, Noyau et registres

**F-R01 : RÉDUIT.** `LK_Routines.lua:442-466` (`Routines.plan`) : `if b == "guard"`, `"patrol"`, `"sleep"`. Un registre d'activités existe déjà (`Routines.registerActivity`, ligne 486) et les trois activités l'utilisent : `Routines/LK_Routine_Watch.lua:12-13` (guard, patrol), `Routines/LK_Routine_Sleep.lua:9` (sleep), toutes via `Routines.runPlanned`. Le plan peut migrer dans la spec de chaque activité (`plan = ...`). Gain réel, petit, sans nouveau registre.

**F-R02 : RÉFUTÉ.** `LK_RoutineExec.lua:212-241` : `plan.kind` vaut `face`, `sit`, `round`, ou le repli « aller au point ». Ce sont quatre primitives d'exécution du mouvement (regarder, s'asseoir, tourner en rond, rejoindre un point). Aucun nouveau genre n'est attendu : un registre `Routines.registerPlanKind` serait une abstraction spéculative.

**F-R03 : CONFIRMÉ.** `LK_Routines.lua:31` (`Routines.CHORES`, huit corvées, liste « fermée » par commentaire), `32-33` (`CHORE_GESTURE`), `63` (`CHORE_DUTY`), `70` (`CHORE_ROLE`), `73` (`CHORE_TRAIT`), plus `avail` construit dans `Routines/LK_Routine_Chores.lua:208` et `chorePlan` (222-243, `if chore == "fire"`, `"warm"`, `"tidy"`, `"lookout"`, `"repair"`, `"smoke"`, `"care"`). Une corvée = six tables et une branche. Une corvée plausible (cuisiner au feu, réparer une fenêtre) : oui. L'activité `chore.visible` est déjà inscrite (`Routine_Chores.lua:245`) : le registre des corvées se greffe dessus.
- Bancs : `test_lk_chores.py`, `test_lk_routines.py`.

**F-R04 : RÉDUIT.** `LK_RoutineExec.lua:258-262` (`leave`) : `if m.kind == "upkeep" and U ~= nil and U.release ~= nil` puis `"fortify"` avec `F.release`. `forget` (vers 271-275) répète le même patron. Deux modules, donc sous le seuil des trois cas. Correction simple : la mémoire de routine porte sa fonction `release` (ou `Routines` appelle un hook enregistré). Réel, à faire comme nettoyage avec A-A20.

**F-R05 : CONFIRMÉ.** `LK_Simulation.lua:1061-1071` (`Simulation.applyEvent`) : `departure`, `recruit`, `conflict`, `illness`, `clash` (avec condition sur `targets`). Cinq événements de groupe, fermés pour l'instant ; un sixième (vol, deuil) est plausible. Bancs : `test_lk_simulation.py` (13 fichiers touchent Simulation).

**F-R06 : CONFIRMÉ.** `LK_Simulation.lua:534-551` : `if g.expedition.trip ~= nil and Ex ... resolveAbstract` ; `elseif g.expedition.place == "revenge"` (Relations) ; `elseif g.expedition.place == "raid"` (Raids) ; `else` (résolution simple). Trois chemins. Cycle réel : `Simulation` lit `LivingKnox.Relations` (local en 1146) et `Relations` lit `LivingKnox.Simulation` (`LK_Relations.lua:501`, `memberEmbodied`). Le cycle est à l'exécution, avec garde `nil`, donc invisible à `require`.

**F-R07 : CONFIRMÉ.** `LK_Simulation.lua:1146-1163` : boucle `for hour`, dans l'ordre : `Relations.offscreenHour`, `Raids.offscreenHour`, `simulateHour`, `Stock.offscreenHour`, `Fortify.offscreenHour`. Quatre modules nommés dans le moteur, avec un ordre significatif (vengeance avant raid, raid avant stock). C'est exactement le motif « liste de noms dans un moteur » que la règle du projet interdit. Le registre `Simulation.registerHourly{ id, order, run }` est justifié par la règle, pas par une nécessité immédiate ; le coût est faible.

**F-R08 : CONFIRMÉ.** `LK_API.lua:966-1003` (`handle`) : `if f.kind == "created"` (`groupCreated`), `"died"` (`memberDied`), `"left"` (`memberLeft`), `"removed"` (`groupGone`), `"encounter"`. Cinq genres de faits, chacun avec sa clé de déduplication. Une table `FACT_HANDLERS` est directe. Bancs : `test_lk_api.py`, `test_lk_apitest.py`.

**F-R09 : CONFIRMÉ, avec correction.** `LK_Admin.lua:66-67` (`Admin.OPS`, douze opérations) et `73-74` (`Admin.DEBUG_OPS`). Rejet en amont : `LK_Admin.lua:901` (`if op == nil or not Admin.OPS[op]` -> « unknown request »). La chaîne `elseif op ==` (906-929) couvre onze opérations, et sa branche `else` appelle `Admin.moveHome` : c'est l'opération `home`. Donc le constat « la branche `else` avale les opérations inconnues » est FAUX (les inconnues sont rejetées avant), mais le risque équivalent existe : une opération ajoutée à `Admin.OPS` sans branche dans la chaîne tombe silencieusement dans `moveHome`. Correction : table `Admin.OPS[op] = { debug, run }`. Bancs : `test_lk_admin.py`.

### Zone G, Social et besoins

**G-Z01 : CONFIRMÉ.** `LK_Talk.lua:540-569` (`reply`) : `if req.kind == "npc_member"` (E10), `"npc_incident"`, `"npc_enrich"` (bloc propre), `"npc_initiative"`, `"npc_converse"`, puis `talkReply` par défaut. Six genres de requête, ordre significatif (le claim de radio passe avant tout). Bancs : `test_lk_talk.py`, `test_lk_talk_alone.py`.

**G-Z02 : RÉDUIT.** `LK_Talk.lua:547-552` : liste blanche d'intents (`none`, `offer`, `accept`, `negotiate`, `leave_group` et `change_relation` et `report_done` restreints à `npc_talk`). `LK_Talk.lua:478-499` : `negotiate`, `leave_group`, `change_relation`. Les intents sont le vocabulaire du protocole entre le mod et le pont LLM (le modèle produit ces valeurs). Fermé par contrat ; un registre d'intents serait spéculatif tant que le pont ne change pas. Le vrai point : la liste est dupliquée à deux endroits, à centraliser en une constante.

**G-Z09 : doublon de F-R03.** `Routine_Chores.lua:222-243`, même code.

### Zone H, Shared et client

**H-D01 : RÉDUIT.** `client/LivingKnox/LK_Executor.lua:131-136` (`validEntry`) et `350-368` (`start`) : `if e.op == "move"`, `elseif "stop"`, `elseif "face"`. Trois verbes du protocole serveur->client (`move`, `stop`, `face`). Ils sont l'interface de l'exécutant, stable. Un registre d'opérations vaut quand un quatrième verbe apparaît ; aujourd'hui, c'est le troisième cas du texte de la règle, mais la règle vise les genres ouverts.

**H-D02 : RÉFUTÉ.** `LK_Executor.lua:398-415` (`act == "repath"`, `"unblock"`, sinon `fail`) et `shared/LivingKnox/LK_Movement.lua:243-268` (`Movement.respond` renvoie `"repath"`, `"unblock"` ou `"fail"`). C'est une séquence ordonnée à trois états (une nouvelle requête de chemin, puis un point de déblocage, puis l'échec), dont l'ordre est l'algorithme. Pas un genre ouvert : un `Movement.registerEscalation` serait de l'abstraction spéculative.

**H-D03 : RÉDUIT.** `client/LivingKnox/LK_DebugView.lua:266-271` (`groupSort` : trois clés), `308-313` (`memberSort` : trois clés), `324-327` (`entrySort`), `334-337` (`logSort`). Vrai, mais c'est une vue de débogage (`DebugView`), et chaque tri a au plus trois clés. Un champ `sort` dans le descripteur de colonne serait plus propre, sans urgence.

**H-D04 : RÉDUIT.** `client/LivingKnox/LK_NpcSheet.lua:377-391` (`Sheet.fieldValue`) : cas spéciaux `health`, `bleed`, `wound`, puis repli `d.needs[field]`. Trois cas plus un repli générique. Outil admin ; `Admin.SHEET_FIELDS` (`LK_Admin.lua:76`) liste déjà les champs côté serveur. Gain faible.

**H-D05 : RÉDUIT.** `client/LivingKnox/LK_AdminView.lua:105-134` (`View.receive`) : `reply.op` vaut `list`, `group`, `relief`, `load`, `home` (cinq branches). C'est l'UI admin ; le serveur en compte douze (F-R09). Un `AdminClient.onReply(op, handler)` est propre ; la gravité est moyenne, pas critique.

## 3. Chantiers confirmés, regroupés

Chaque ligne est une tâche possible d'un plan. Dépendances indiquées.

**C1. Forme compacte et tables de genres de chantier Fortify.** Constats A01, A02, A03, A04 (P1), A05 (P1), A06 (P1). Un registre `Fortify.registerKind` dont dérivent `KINDS`, `OFF_KINDS`, `KIND_CODE`, `CODE_KIND`, les motifs et `STAGES`. Fichiers : `LK_Fortify.lua` (+ éventuellement `Fortify/Kinds/*.lua`). Bancs : `test_lk_fortify.py`, `test_lk_fortify_offscreen.py`, `test_lk_barricade.py`, `test_lk_walls.py`, `test_lk_repair.py`. Dépendance : aucune. Effort : moyen. Risque : moyen (format persistant ; banc de forme compacte à garder vert).

**C2. Registre des comportements de décision (absorbe B-C01, B-C03, B-C04).** Migrer `fight`, `defend`, `expedition`, `revenge`, `warn`, puis `surrender`, `retreat`, `watch`, `alert`, `flee`, `guard`, `patrol` vers `registerExtension` (contrat `behaviour { vigil, apply }`, plus `aim` et `gesture` portés par chaque comportement). Dépendance : B-C02 (les champs de contexte doivent être inscrits avant) ; à faire après C5 si les cycles de C5 touchent les mêmes lignes. Bancs : `test_lk_decisions.py`, `test_lk_defense.py`, `test_lk_encounters.py`, `test_lk_surrender.py`, `test_lk_contest.py`, `test_lk_revenge.py`, `test_lk_leave.py`. Effort : fort (2366 lignes). Risque : élevé (cascade de décisions, ordre des priorités).

**C3. Contexte de décision par inscription (B-C02, B-C12, B-C13).** Chaque module s'inscrit en fournisseur de contexte (`input`) au lieu d'être nommé dans `Decisions.context` ; casse les cycles Decisions <-> Defense / Encounters / Expeditions / Care. Dépendance : précède C2. Bancs : les mêmes, plus `test_lk_directives.py`. Effort : moyen. Risque : moyen (ordre des champs de contexte, à figer par un banc).

**C4. Expéditions : registre des genres (C-X01, C-X02, C-X03, C-X04, C-X07).** `Ex.registerKind` (bâtiment, cueillette, pêche), `tryDepart` en boucle sur les genres, Food s'inscrit lui-même. Dépendance : aucune. Bancs : `test_lk_expeditions.py`, `test_lk_food.py`, `test_lk_garden.py`, `test_lk_loot.py`. Effort : moyen. Risque : moyen.

**C5. Casser les cycles par événements (F-R04, F-R06, B-C12, A-A20, A-A21, F-R11).** `Simulation` ne lit plus `Relations` / `Raids` (événement de retour d'expédition), `Relations` ne lit plus `Simulation`, `Fortify` reçoit ses ports, `Routines` appelle le `release` mémorisé. Dépendance : précède C2 et C6. Bancs : `test_lk_simulation.py`, `test_lk_revenge.py`, `test_lk_raids.py`, `test_lk_fortify.py`, `test_lk_routines.py`. Effort : moyen. Risque : moyen (ordre des événements).

**C6. Simulation : ordre horaire et événements de groupe (F-R05, F-R07).** `Simulation.registerHourly{ id, order, run }` et `Simulation.registerEvent`. Dépendance : après C5. Bancs : `test_lk_simulation.py`. Effort : faible à moyen. Risque : faible à moyen.

**C7. Dispatch des opérations et des faits (F-R08, F-R09, G-Z01, H-D05).** Tables `FACT_HANDLERS` (API), `Admin.OPS[op].run` (Admin, avec suppression du repli implicite `moveHome`), `Talk.kinds` (requêtes), `AdminClient.onReply`. Indépendants entre eux. Bancs : `test_lk_api.py`, `test_lk_admin.py`, `test_lk_talk.py`, `test_lk_talk_alone.py`, `test_lk_admin.py` côté client via `test_lk_npcsheet.py` et `test_lk_debugview.py`. Effort : faible par item. Risque : faible.

**C8. Corvées (F-R03 = G-Z09).** Une table ou un fichier par corvée, `Routines.registerChore`. Dépendance : aucune, mais se greffe sur `chore.visible`. Bancs : `test_lk_chores.py`, `test_lk_routines.py`. Effort : moyen. Risque : faible.

**C9. Routines : plan dans les activités (F-R01).** Déplacer `Routines.plan` dans les specs `watch.guard`, `watch.patrol`, `sleep`. Dépendance : aucune. Bancs : `test_lk_routines.py`, `test_lk_stand.py` (aucun banc dédié au couchage). Effort : faible. Risque : faible.

**C10. Obstacles : découpage et dédoublonnage (D-OBS-01, D-OBS-02, D-OBS-03, D-OBS-05, D-OBS-06).** D-OBS-01 (modèles d'itinéraire) à traiter avec le découpage ; D-OBS-02 et D-OBS-03 en dédoublonnage local. Dépendance : aucune. Bancs : `test_lk_obstacles.py`, `test_lk_window_lure.py`, `test_lk_floor_strike.py`. Effort : fort. Risque : élevé (2849 lignes, chemins de routage).

**C11. Aménagements Homes (E-F01).** `Homes.registerFurnishing`, un fichier par sorte ; supprimer la liste littérale en 700. Dépendance : aucune. Bancs : `test_lk_homes.py`. Effort : moyen. Risque : moyen.

**Hors chantier (nettoyages sans registre) :** E-F02 (supprimer `Raids.SIGNS`), F-R04 (release mémorisé, avec C5), G-Z02 (une seule constante pour la liste d'intents), H-D03 et H-D04 (descripteurs de colonnes et de champs, quand la vue est touchée), B-C05 (utiliser les tables existantes), C-X02 (boucle locale).

**Ne pas faire (abstraction spéculative) :** F-R02 (primitives d'exécution), H-D02 (escalade), D-OBS-02 comme registre (arêtes PZ fermées), C-X05 (origines fermées), H-D01 tant qu'il n'y a pas de quatrième verbe, B-C06 (`THREAT_STEPS`).

## 4. Les trois chantiers à faire en premier

Critères : gain réel (dérive observée ou extension plausible), risque de régression couvert par des bancs lupa existants, coût proportionné, et prise en compte du fait que le mod n'est pas publié (pas de migration) et que les campagnes en jeu sont rares (pas de validation en jeu qui serve de filet).

1. **C1, tables de genres Fortify (A01 à A03).** C'est le seul P0 avec un mécanisme de perte silencieuse vérifié à la lecture (validation par `OFF_KINDS` et motifs, rejet de la forme compacte). Huit bancs Fortify couvrent la zone, le fichier est isolé, et le format n'est pas publié. Gain élevé sur la cohérence, risque moyen maîtrisé par le banc de forme compacte. Premier.

2. **C7, dispatch des opérations et des faits (F-R08, F-R09, G-Z01, H-D05).** Coût faible par item, chacun dans un fichier, chacun couvert par un banc existant. F-R09 corrige un piège réel (une opération ajoutée à `Admin.OPS` tombe dans `moveHome`). Gain modeste mais le meilleur ratio gain/risque du lot. Deuxième. Il peut être fait en parallèle de C1 (fichiers disjoints).

3. **C5 puis C3, casser les cycles et inscrire le contexte de décision.** Ce sont les prérequis de la migration des comportements (C2), le chantier le plus coûteux et le plus risqué. Les cycles (Decisions <-> Defense / Encounters / Expeditions / Care ; Simulation <-> Relations) sont à l'exécution et invisibles à `require`. C5 réduit le risque de C2 avant qu'il ne commence. Troisième, à découper en deux tâches. Si l'on veut un gain plus tôt, C8 (corvées, risque faible) peut prendre cette place.

Ordre recommandé : C1 et C7 en parallèle, puis C5, C3, C2 ; C4, C6, C8, C9, C10, C11 selon le besoin réel de nouveaux contenus.

## 5. Limites

- Lecture seule : aucun banc `tests/test_lk_*.py` n'a été exécuté (pas de lancement, pas d'écriture de caches). Les « bancs couvrent la zone » sont des constats de présence de fichiers, pas de couverture mesurée. Un passage `pytest` par le propriétaire donnerait la couverture réelle.
- Le constat de perte silencieuse de C1 (A03) est une déduction de lecture ; il faut un test de forme compacte avec un genre absent de `OFF_KINDS` pour le confirmer.
- Les jugements « genre ouvert / fermé » sont des appréciations de design, à valider par le propriétaire du projet (en particulier F-R05 événements, F-R01 plans, D-OBS-01 modèles, G-Z02 intents).
- Le rapport d'audit cite un commit « non relevé » ; les lignes lues correspondent au code présent dans le dépôt au moment de la vérification (2026-11-13).
