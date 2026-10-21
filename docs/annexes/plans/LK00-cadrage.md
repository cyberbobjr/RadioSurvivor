# LK00 — Cadrage : décisions de conception et architecture

**Objectif.** Fixer la conception de Living Knox et choisir, sur une analyse complète, la base des PNJ et l'architecture d'exécution en multijoueur, avant d'écrire du code de jeu.

**Sources.** [Analyse d'architecture](../../architecture/ia-multijoueur.md) (version 2 et estimation du moteur propre) ; [Bandits!](../recherches/bandits-analyse.md) ; [Project A-Life](../recherches/alife-analyse.md) ; méthode : [README](README.md).

## Décisions

- 2026-10-03 — **But** : un monde vivant fait de quelques groupes isolés, organisés, avec une histoire et des besoins, au lieu d'apparitions périodiques en masse. Un groupe décimé est remplacé par un autre qui fait sa vie.
- 2026-10-03 — **Forme** : mod séparé avec son dépôt GitHub privé et son plan ; RadioSurvivor s'y branche s'il est présent (besoins → missions, histoires → voix et fiches PNJ).
- 2026-10-03 — **Groupes** : 3 à 5 en même temps (sandbox, défaut 4), types mêlés : colons amicaux, pillards hostiles, groupe neutre méfiant ; 4 à 8 membres et un chef.
- 2026-10-03 — **Foyers selon le type** : colons et neutres dans un vrai bâtiment (barricades, lumière, couchages) ; pillards et nomades dans un camp en forêt ; site choisi par le serveur sans charger la zone, loin des bases des joueurs.
- 2026-10-03 — **Hors de portée** : simulation abstraite par heure de jeu (réserves, expéditions, moral, événements) ; à l'arrivée d'un joueur, les corps reflètent l'état simulé.
- 2026-10-03 — **Récits** : gabarits écrits combinés par le serveur ; enrichissement par le LLM seulement si RadioSurvivor et son pont sont actifs.
- 2026-10-03 — **Relève** : après 2 à 5 jours de jeu (sandbox), un nouveau groupe s'installe sur un autre site, loin de l'ancien ; les traces du groupe disparu restent.
- 2026-10-03 — **Exigence multijoueur** (remarque de l'utilisateur) : l'IA gérée par chaque client, comme dans Bandits!, ne convient pas. Analyse demandée sur faisabilité, ouverture, simplicité, robustesse et maintenabilité de chaque option, puis étude de Project A-Life et estimation d'un moteur propre.
- 2026-10-03 — **Base des PNJ : moteur propre avec jalon** (option C de l'analyse). Décisions sur le serveur, exécution des corps par le seul client propriétaire, gestes relayés, dégâts aux joueurs appliqués par le serveur. Jalon LK02 (corps et gestes prouvés en solo et à deux clients, 2 à 3 semaines) suivi d'une décision explicite : continuer, ou repli sur un addon de Project A-Life ou sur Bandits! en « propriétaire unique ».
- 2026-10-03 — **Nom** : « Living Knox », `id=batman_LivingKnox`, dossier `Zomboid\Workshop\LivingKnox`, dépôt `cyberbobjr/LivingKnox`, préfixe de plan `LK`. Le projet ne dépend plus de Bandits!.
- 2026-10-03 — **Écriture indépendante** : aucun code de Bandits! ni de Project A-Life repris, traduit ou paraphrasé.
- 2026-10-08 — **Fusion dans RadioSurvivor** (décision de l'utilisateur, remplace les décisions « Forme » et « Nom » ci-dessus pour l'emballage) : un seul mod `batman_RadioSurvivor`, un seul dépôt (`cyberbobjr/RadioSurvivor`, historique de `cyberbobjr/LivingKnox` fusionné), un seul plan. Living Knox reste le nom du moteur de PNJ, préfixe `LK` conservé ; l'identifiant `batman_LivingKnox` n'est plus utilisé. La relation RadioSurvivor ↔ Living Knox devient interne au mod : l'API de LK12 sert le carnet et les mods tiers.
- 2026-10-08 — **Comportements autonomes** (demande de l'utilisateur) : les PNJ vivent comme des humains, guidés par des besoins à court terme (zombies ou intrus à proximité, faim, soif, fatigue, peur, blessure) et à long terme (stock, sécurité du foyer, fortification). Ils protègent leur base, cherchent de la nourriture, boivent et mangent réellement, fortifient progressivement et gèrent un stock réel. Ajouts : modèle de décision à deux niveaux (`LK05-T02`), `LK05-T06` à `LK05-T09`, `LK08-T06` et `LK08-T07`, `LK09-T06`, étape `LK14`.
- 2026-10-08 — **Idées reprises de Bandits! et A-Life** (demande de l'utilisateur) : les meilleures idées de comportement des deux mods sont relevées dans `docs/annexes/recherches/idees-bandits-alife.md` (idées seulement, avec leur source pour vérification, jamais de code) et rattachées aux tâches par un champ « Idées ». Nouvelles tâches : `LK05-T10`, `LK05-T11`, `LK11-T05` à `LK11-T07`.
- 2026-10-08 — **Véhicules hors du plan** : la récupération et l'usage de véhicules par les PNJ sont reportés à beaucoup plus tard, sans étape ni tâche pour l'instant.

## Tâches

- [x] **LK00-T01** — Analyse comparative des architectures d'exécution de l'IA en multijoueur
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : —
  - Fichiers : `docs/architecture/ia-multijoueur.md`, `docs/annexes/recherches/bandits-analyse.md`, `docs/annexes/recherches/alife-analyse.md`
  - Faire : comparer chaque option (faisabilité, ouverture, simplicité, robustesse, maintenabilité, coût, risques, licence) avec preuves dans le Java 42.21, Bandits! et Project A-Life ; estimer un moteur propre.
  - Accepté si : l'utilisateur dispose de tout ce qu'il faut pour trancher ; chaque affirmation est sourcée ou marquée comme hypothèse.
  - Tests : —
  - Preuve : analyse v2 et estimation, commits `9441d40` et `534803f` ; faits porteurs revérifiés à la main (accroche `IsRagdoll`, `sendClientCommand` réservé au joueur local, `NetworkZombieAI.parse`, `isRemote`, `isOwner` d'A-Life, `sendDamage`)
  - Reste : mesures en jeu listées au §8 du document.

- [x] **LK00-T02** — Choisir la base des PNJ et l'architecture d'exécution
  - État : `testé hors jeu`
  - Cible : `hors jeu`
  - Dépend de : LK00-T01
  - Fichiers : ce fichier ; `docs/annexes/plans/LK01-*.md` à `LK13-*.md`
  - Faire : présenter l'analyse, poser la question, consigner la décision, écrire les étapes suivantes.
  - Accepté si : décision consignée ; plan des étapes suivantes écrit.
  - Tests : —
  - Preuve : décision « moteur propre avec jalon » et nom « Living Knox » du 2026-10-03 (section Décisions) ; étapes LK01 à LK13 écrites
  - Reste : —
