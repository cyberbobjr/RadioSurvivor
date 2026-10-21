# Protocole de la mesure de charge en jeu (LK13-T02)

- **But** : mesurer le moteur Living Knox avec **5 groupes et 4 joueurs** sur le serveur dédié (Kahlua, API Java
  réelles), chez un propriétaire de corps et chez un observateur ; comparer aux budgets proposés
  ([charge-hors-jeu-2026-10-12.md](charge-hors-jeu-2026-10-12.md), § 5) ; confirmer ou écarter les points chauds (§ 6).
- **Quand** : séance multijoueur finale (décision du 2026-10-09 : MP en une seule séance à la fin). Avant : un essai
  solo court pour vérifier l'outil.
- **Outil** : `LivingKnox.Load` ([charge.md](../../conception/charge.md)). Messages au journal : lignes
  `[LivingKnox] INFO load: …` du `console.txt` de chaque machine.

## Campagne automatique (outil, 2026-10-15)

`tools/autoclient/autoclient.py --mp --load` prépare la séance sans personne devant le PC (`docs/annexes/tests/tests-en-jeu.md`,
§ 6 ter) :

```powershell
python RadioSurvivor/tools/autoclient/autoclient.py --mp --load --bridge off --timeout 3600 --wait-idle 3600
```

- serveur dédié de test, **monde neuf**, `LivingKnox.GroupCount = 5` écrit dans `Server\rstest_mp_SandboxVars.lua`
  (sans zombie ambiant, comme les autres campagnes MP ; `--ambient-zombies` pour la population vanilla) ;
- **4 clients** `rs_mp1`..`rs_mp4` (tous admin, mode dieu), lancés l'un après l'autre ; le client 1 demande la passe
  serveur, les clients 2 à 4 sont « peer » (ils répondent aux étapes des suites et rendent leur résultat) ;
- passe serveur : campagne `mp-load` si `RST_Campaign.lua` la déclare, sinon `lk.load` seule (étiquette `server`,
  mesure de 20 s) ; `--clients`, `--group-count`, `--server-suite` explicites priment ;
- mémoire : 4 × 4096 Mo + 3072 Mo = 19 Go de `-Xmx`, environ 26 Go avec la part native (affiché au départ, alerte si la
  mémoire libre est plus faible ; `--client-xmx 3072m` ramène l'estimation à environ 22 Go).

Ce que l'outil ne fait pas encore (suites à écrire, hors de l'outil) : le placement P1-P4 du § 2 autour des foyers
(étapes `RST.Steps` vers chaque client, ou déplacement par le serveur), la mesure longue (`windowMs = 60000`, 30
minutes) sur le serveur et la mesure locale chez P1 et P2 (`LivingKnox.Load.start` côté client), et la campagne
`mp-load` qui les enchaîne. Sans elles, `--load` donne la mesure courte de `lk.load` avec 4 joueurs et 5 groupes.

## 0. Essai solo de l'outil (5 minutes)

1. Partie solo avec le mod et le mod de développement, `-debug`.
2. Console Lua : `RST.run({ suite = "lk.load", tags = "server" })` → 3 PASS (exports, refus sans joueur autorisé,
   mesure de 20 s) ; les lignes du rapport sont dans les notes du test et dans `console.txt` (`load: load on solo …`).
3. Facultatif : `LivingKnox.Load.start({ windowMs = 10000, log = true })`, jouer une minute près d'un foyer, puis
   `LivingKnox.Load.print()` et `LivingKnox.Load.stop()`.

## 1. Préparation MP

1. Serveur dédié de test (`tests/run_dedicated_smoke.ps1` ou serveur de la séance) avec `batman_RadioSurvivor` et
   `batman_RadioSurvivorTests`, **monde neuf**, option sandbox `LivingKnox.GroupCount = 5` (poids par défaut).
2. Quatre clients connectés ; un client a le rôle `admin` ou `moderator` (droit `PopmanManage`). Les clients du
   propriétaire et de l'observateur sont lancés avec `-debug` (console Lua).
3. `console.txt` du serveur : `[LivingKnox] INFO engine … started`, puis `population: 5 group(s) created`.
4. Client admin : panneau d'admin → « Groupes Living Knox » : relever les foyers des cinq groupes.

## 2. Placement (5 minutes)

| Joueur | Place | Rôle attendu |
|---|---|---|
| P1 | à 5-10 cases du foyer du groupe 1 | propriétaire des corps du groupe 1 (le plus proche) |
| P2 | à 15-25 cases du même foyer | observateur du groupe 1 |
| P3 | près du foyer du groupe 2 | propriétaire des corps du groupe 2 |
| P4 | loin de tous les foyers (plus de 150 cases) | sans corps à portée |

Attendre que les corps soient visibles chez P1, P2 et P3 (créés deux par passage, quelques secondes).

## 3. Mesure (30 minutes réelles au moins)

1. Client admin, console Lua : `LivingKnox.Load.ask("start", { windowMs = 60000, log = true })` → la console du
   client affiche `load: server measure started on server (window 60000 ms, log true), from the next tick on`.
   Sans console : `RST.server({ suite = "lk.load" })` donne un rapport de 20 s seulement.
2. Clients P1 et P2 (console Lua) : `LivingKnox.Load.start({ windowMs = 60000 })` (mesure locale).
3. Laisser jouer : 10 minutes immobiles, puis 10 minutes à tourner autour du foyer 1 (P1, P2), entrer et sortir de la
   portée (P2 s'éloigne à 100 cases puis revient), parler à un PNJ et ouvrir le troc (P3), puis 10 minutes libres.
   Noter l'heure réelle de chaque phase. Facultatif en fin de séance : un combat contre un groupe hostile.
4. À mi-parcours : `LivingKnox.Load.ask("report")` (client admin).
5. Fin : `LivingKnox.Load.ask("stop")` (client admin) ; P1 et P2 : `LivingKnox.Load.print()` puis
   `LivingKnox.Load.stop()`.

## 4. Relevés

- Serveur : lignes `load:` de `console.txt` (rapports et une ligne `window …` par minute), heure de jeu au début et à
  la fin, taille des fichiers `Zomboid/Lua/batman_RadioSurvivor/livingknox/groups-*.txt` et `registry-*.txt`.
- P1, P2 : lignes `load:` de leur `console.txt` ; ressenti (saccades, corps figés, gestes en retard).
- Tous : erreurs Lua de nos mods (aucune attendue).

## 5. Critères

| Mesure | Budget | Si dépassé |
|---|---|---|
| Serveur, moteur par image | 2 ms en moyenne | nouvelle tâche ; comparer au banc (× 3-4 attendu) |
| Serveur, image la plus lourde | 25 ms | attendu dépassé (écritures du registre, point chaud 1) : relever le module et l'heure |
| Serveur, un module | 0,5 ms en moyenne | nouvelle tâche pour ce module |
| Serveur, envoyés | 40 msg/s, 8 Ko/s | nouvelle tâche réseau |
| Client propriétaire ou observateur | 1 ms en moyenne, 8 ms au plus | nouvelle tâche côté client |
| Registre des groupes | 1 Mo | nouvelle tâche (point chaud 2) |

Résultat à consigner dans `docs/annexes/tests/validation/charge-jeu-<date>.md` (version du jeu lue au journal, lignes `load:`,
écarts avec le banc, points chauds confirmés ou écartés), puis preuve de LK13-T02.
