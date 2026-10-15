# Architecture de l'IA en multijoueur : analyse comparative

Version 2 du 2026-10-03, pour la décision LK00-T02 : ajoute **Project A-Life** comme base possible et corrige le §1.4 (dégâts appliqués par le serveur). Lecture statique du Java décompilé 42.21 (**J/**), de Bandits! (Workshop `3268487204`, `Bandits2`, noté **B/** = `…\Bandits\42.20\media\lua`) et de Project A-Life (Workshop `3803984183`, `ProjectALifeNPCs` 1.3.15, téléchargé par steamcmd dans `C:\pzserver\…\3803984183`, noté **AL/** = `…\ProjectALifeNPCs\42.20\media\lua`). **Aucun essai en jeu.** Chaque fait est marqué **[C]** (lu dans le code) ou **[H]** (hypothèse déduite, à mesurer).

## 1. Contraintes du moteur, communes à toutes les options

1. **Un seul simulateur par zombie.** En MP, chaque zombie (donc chaque PNJ bâti sur un zombie, chez Bandits! comme chez A-Life) est simulé par son **propriétaire** : le client du joueur qui l'agrippe, sinon celui qu'il cible, sinon le plus proche ; un changement exige une distance 1,618 fois plus petite et 2 s depuis le précédent (J/popman/NetworkZombieManager.java:60-131) **[C]**. Le serveur ne simule que les zombies sans propriétaire, loin de tout joueur (J/characters/IsoZombie.java:1113, 2672) **[C]**. **Aucun mod Lua ne peut faire tourner sur le serveur l'IA d'un corps proche d'un joueur.**
2. **Les autres clients suivent par le réseau.** Chaque paquet réécrit destination, vitesse, type de marche et 14 drapeaux d'un zombie distant, et le téléporte au-delà de 3 cases d'écart (J/characters/NetworkZombieAI.java:235-276) **[C]** ; un zombie distant ne peut pas chercher de chemin (`bClient`, IsoZombie.java:595) **[C]**. Le client sait s'il est propriétaire : `zombie:isRemoteZombie()` (IsoZombie.java:441) **[C]**.
3. **Gestes non transmis.** Le paquet zombie ne porte ni `BumpType`, ni variables d'animation personnalisées, ni objets en main (J/network/packets/character/ZombiePacket.java:23-49, 204-246 ; IsoGameCharacter.java:12197-12208) **[C]** : tout client qui affiche un PNJ doit calculer ou recevoir ce qu'il montre.
4. **Dégâts.** Seul le propriétaire d'un zombie applique les dégâts qu'il subit (IsoZombie.java:3449) **[C]**. Pour un joueur : un client ne peut envoyer une commande qu'au nom de son joueur local (J/Lua/LuaManager.java:7231-7233) **[C]**, mais **le serveur peut appliquer lui-même des dégâts** par `BodyDamage:DamageFromWeapon` puis la globale `sendDamage(joueur)`, qui envoie un paquet `PlayerDamage` au client concerné (LuaManager.java:3743-3748) **[C]**.
5. **Licences.** Bandits! : copyright de Piotr Pawłowski, republication refusée sans permission écrite (description Workshop) **[C]**. A-Life : aucun texte de licence ni dans les fichiers ni sur la page ; par défaut tous droits réservés ; l'auteur invite les moddeurs à le contacter (Discord `xxvice`) **[C]**. Dans les deux cas : dépendre du mod et appeler ou envelopper ses globales, sans copier ni remplacer ses fichiers.
6. **Un seul mod de PNJ par partie.** Les deux mods construisent leurs PNJ sur des zombies et se prennent mutuellement pour des zombies ; A-Life classe Bandits! « non pris en charge » (AL/shared/ProjectALife/Compat/ALifeModCompat.lua:64-67) et Bandits! retire les objets en main de tout zombie près d'une fenêtre en MP (B/client/BanditUpdate.lua:2067-2090) **[C]**. Il faut choisir **une** base par serveur.

## 2. Ce que fait Bandits! en MP

- **IA chez chaque client** qui a le bandit chargé, sans test de propriétaire (aucun `isRemoteZombie` dans le mod) ; chaque copie décide avec son propre hasard (B/client/BanditUpdate.lua:2067-2071) **[C]**.
- **« Contrôleur » = joueur le plus proche** (B/shared/BanditUtils.lua:670-696), règle différente du moteur : arrêts ou à-coups quand elles divergent **[H]**.
- **Effets dupliqués** : sons relayés, dégâts de véhicule ajoutés par chaque client, portes et fenêtres manipulées par plusieurs clients, objets lâchés visibles localement seulement **[C]**.
- **Tirs fantômes** (les dégâts aux joueurs ne viennent que de la copie d'IA de la victime) ; **santé divergente** (relais des tirs cassé, B/shared/BanditUtils.lua:373) ; **mort locale → bandit redevenu zombie partout** (B/client/BanditUpdate.lua:2478-2494, 2143-2146) **[C/H]**.
- **Coût d'IA × N clients** proches, sans saut de ticks **[C]**.
- **Pas de canal serveur → corps chargés** : une modification serveur du cerveau n'atteint pas les copies déjà chargées (B/shared/BanditGMD.lua:52-67) **[C]**.
- Code lisible et commenté, événements personnalisés documentés, outil de test en jeu **[C]**.

## 3. Ce que fait A-Life en MP

- **Propriétaire unique.** Un PNJ n'est « adopté » que par le client qui possède son corps (`Sim.isOwner` = `isClient() and not shell:isRemoteZombie()`, AL/shared/ProjectALife/Shells/ALifeShellSimulation.lua:201-206) **[C]** ; ce client exécute perception, décisions, déplacement, combat, animations (`Executor.tick`, AL/shared/ProjectALife/Core/ALifeExecutor.lua:2624-2648) **[C]**. Sur un serveur dédié, le serveur **délègue** (`serverDelegates`, ALifeExecutor.lua:236-240) et saute déplacement, animations et décisions (AL/server/ProjectALife/Core/ALifeRuntime.lua:726-790) **[C]**.
- **Monde autoritaire côté serveur** : registre des PNJ, escouades, avant-postes, apparition et retrait des corps, persistance, munitions, dégâts aux joueurs et entre PNJ, mort définitive **[C]**. Le propriétaire envoie des rapports (position, activité, intention, santé) vérifiés : propriétaire réel, génération, cadence, révision (ALifeExecutor.lua:355-560) **[C]**.
- **Dégâts aux joueurs appliqués par le serveur** après contrôle (attaque payée, arme sélectionnée, politique de cible, hostilité, portée, ligne de tir, une victime par attaque) puis `DamageFromWeapon` + `sendDamage` (ALifeExecutor.lua:1326-1468) **[C]**. Munitions décomptées côté serveur (AL/shared/ProjectALife/Shells/ALifeNPCHitRelay.lua:278-372) **[C]**.
- **Gestes relayés** : le propriétaire publie sa pose ; le serveur la diffuse (`animationSync`, toutes les 500 ms pour 64 corps au plus, et à chaque changement) ; chaque client applique variables, arme affichée et animations ponctuelles (AL/shared/ProjectALife/Shells/ALifeAnimations.lua:1041-1178 ; AL/client/ProjectALife/Shells/ALifeAnimationClient.lua:223-498) **[C]** ; animations dédiées aux zombies distants (`walktoward-network`) **[C]**.
- **Changement de propriétaire géré** : libération après 3 audits (≈ 1,5 s), adoption par le nouveau, rancune et engagement conservés 10 s, santé et cible transmises par le serveur ; audit serveur qui reconstruit ou range un corps sans rapport depuis 15 s (ALifeExecutor.lua:1047-1102, 2152-2185, 2557-2562) **[C]**.
- **Hors écran** : escouades sur un graphe routier, ravitaillement et moral, combats abstraits, vengeance ; matérialisation près des joueurs, une recrue toutes les 1,25 s, et retrait au-delà du rayon (AL/server/ProjectALife/Offline/*) **[C]**.
- **Persistance** en ModData `ProjectALife.*.v1` avec numéro de schéma et refus de démarrer en cas d'écart ; corps jamais source de vérité (AL/server/ProjectALife/Core/ALifePersistence.lua) **[C]**.
- **Budgets** : décisions toutes les 150 ms près des joueurs, 1,5 s au loin, 12 ms par passe ; serveur par tranches (ALifeDecisionLoop.lua:1300-1495 ; ALifeRuntime.lua:461-633) **[C]**.
- **Faiblesses relevées** :
  - confiance au client propriétaire (position et santé rapportées acceptées) **[H]** ;
  - état de décision perdu au changement de propriétaire (à-coup probable à deux joueurs) **[H]** ;
  - corps possédés par le serveur inertes **[H]** ;
  - coups sur des zombies vanilla appliqués sans test de propriétaire (AL/server/ProjectALife/Combat/ALifeCombatStrike.lua:485-510) **[H]** ;
  - inventaires client et serveur qui peuvent diverger **[H]** ;
  - diffusion des gestes à tous les clients sans filtre de distance (coût PNJ × joueurs) **[C]** ;
  - nombres magiques pour la santé en MP (× 0,06, marge de +1 000) **[C]**.

## 4. Socle commun, identique quelle que soit l'option

La plus grande partie du sous-mod ne dépend pas du choix :

- registre serveur des groupes : histoire, chef, membres, foyer, besoins, moral, état ;
- choix des sites, simulation abstraite hors de portée, relève ;
- **décisions serveur** sous forme de consignes (dormir, garder, patrouiller, aller à, rentrer, fuir, hostilité) ;
- récits par gabarits et enrichissement par le LLM ;
- lien avec RadioSurvivor : besoins → missions, histoire → voix et fiches.

L'option choisie fixe la **couche d'exécution** : qui fait tourner l'IA des corps et le combat, comment les autres clients voient le résultat, et quel moteur de PNJ RadioSurvivor doit viser. À isoler derrière un **adaptateur d'exécution** (côté sous-mod) et un **fournisseur de PNJ** (côté RadioSurvivor, qui vise aujourd'hui Bandits! par `RS_Bandits.lua`).

## 5. Les options

### A — Bandits! tel quel, sous consignes serveur
Consignes serveur exécutées par le moteur de Bandits! chez tous les clients ; seulement `BanditUtils.IsController` aligné sur le propriétaire (≈ 30 lignes). Garde tous les défauts du §2, surtout en combat. Convient à un prototype solo, pas au MP.

### A+ — Bandits!, propriétaire unique
On arrête la boucle de Bandits! chez les non-propriétaires en enveloppant `BanditCompatibility.IsRagdoll` (globale appelée une seule fois en tête de boucle, B/client/BanditUpdate.lua:2091-2095) **[C]**, limité à nos bandits. À ajouter : boucle de présentation chez les autres clients (≈ 100 à 150 lignes) ; relais des gestes (≈ 150 à 300 lignes) ; dégâts aux joueurs : rapport du propriétaire, contrôle serveur, `DamageFromWeapon` + `sendDamage` (≈ 100 à 200 lignes) ; transfert de propriété. **Total ≈ 400 à 650 lignes** en plus du socle. C'est, en plus petit, ce qu'A-Life a déjà construit.

### B — Moteur propre sur les données de Bandits!
Couper `Bandit.Engine` (global : tous les bandits du serveur basculent) et réécrire, sans copier, l'équivalent de la boucle de Bandits! (≈ 2 100 à 2 300 lignes : combat, collisions, zombies contre bandits, tâches, santé…) plus les éléments de A+. ≈ 2 600 à 3 000 lignes.

### E — Addon d'A-Life (nouvelle option)
Dépendre d'A-Life comme moteur de PNJ : son exécution MP (§3) remplace A+ et B. Le sous-mod :
- **coupe le peuplement aléatoire** : options sandbox `Encounters_Enabled=false`, `Encounters_RollPercent=0`, `World_Mode=2` ou `Offline_SquadCap=0`, `Raid_Enabled=false`, `Realistic_Outbreak=false`, `Outposts_Chance=0`, `Population_PopulateOnStart=Off`, `Encounters_EarlyLooters=0` ; plus le directeur de factions, toujours actif, à couper en enveloppant `ProjectALife.Settings.runtimeOptions` (AL/server/ProjectALife/Core/ALifeSettings.lua:149, 423-430) **[C]** ;
- **fonde nos groupes** par les appels publics de construction d'avant-poste (`OutpostRegistry.create` → `OutpostBuilder.resolve` → `OutpostDirector.beginBuild`, comme l'outil admin ; ou `OutpostDirector.foundFixed(preset, x, y, heures, faction, durée)`) avec nos factions en données (`common\alife_runtime\catalog\*.alife` lus par `getModFileReader`, ou `CustomFactionAuthority.upsert`) **[C]** ;
- **pilote** par la mémoire du PNJ (`ActorRegistry.update` sur `memory.stance`/`stanceAnchor`, clés protégées et relayées au propriétaire) et par des modules de comportement (`ModuleRegistry.register`) (ALifeExecutor.lua:136-160 ; AL/shared/ProjectALife/Behaviours/ALifeModuleRegistry.lua:101-141) **[C]** ; `DecisionLoop.setOrder` côté serveur est sans effet en MP **[H]** ;
- **branche le LLM** en enveloppant `ProjectALife.Talk.respond` ou `ProjectALife.Speech.say` (AL/server/ProjectALife/Talk/ALifeTalk.lua:361-430 ; AL/shared/ProjectALife/Talk/ALifeSpeech.lua:411-448) ; réponse provisoire puis texte du LLM (la fenêtre de dialogue attend 5 s) **[C]** ;
- garde **ses propres données** (groupes, besoins, missions) dans sa ModData : la mémoire d'un PNJ est réécrite par le rapport du propriétaire, sauf clés protégées **[C/H]** ;
- place son code dans **son propre dossier** : A-Life signale comme incompatible tout mod qui livre du Lua sous `ProjectALife/` (ALifeModCompat.lua:158-215) **[C]**.

Ce qu'A-Life n'a pas et que le socle apporte de toute façon : groupes nommés permanents avec histoire, besoins détaillés (nourriture, soins, munitions ; A-Life n'a qu'un ravitaillement et un moral), missions, réputation qui remonte (la sienne ne fait qu'empirer), radio bidirectionnelle (sa radio du comté diffuse sur 99,6 MHz), relève sur un autre site. Points à vérifier : les avant-postes ont une durée de vie et un « regarnissage » par de nouvelles recrues à la reprise d'une session ; il faut des groupes **permanents** à identité stable.

### C — Moteur propre, indépendant de Bandits! et d'A-Life

Nos propres PNJ sur des corps de zombies, conçus d'emblée pour nos groupes et pour le MP. Évaluation détaillée ajoutée le 2026-10-03 à la demande de l'utilisateur.

**Mesures de référence** (lignes non vides) :
- **A-Life**, sans ses données de voix et de dialogue, son interface et son éditeur : enveloppes de corps ≈ 8 700, déplacement et obstacles ≈ 5 500, combat ≈ 9 300, décisions, perception et peur ≈ 6 000, comportements ≈ 9 300, noyau et exécution ≈ 7 300, monde hors écran ≈ 12 600. Soit **≈ 35 000 à 40 000 lignes** pour le moteur de PNJ.
- **Bandits!** : ≈ 12 000 à 15 000 lignes de Lua.
- **Animations** : uniquement des fichiers XML qui réutilisent les clips vanilla du joueur (`Bob_…`). A-Life : 225 fichiers, ≈ 6 000 lignes, 152 clips vanilla, aucun clip propre. Bandits! : 474 fichiers, ≈ 11 800 lignes, 14 clips propres. **Aucune animation 3D à créer.**

**Estimation pour notre périmètre** : 3 à 5 groupes, routines, combat de mêlée et à distance, MP correct, sans les 148 factions, les voix ni l'éditeur d'A-Life.

| Composant | Lignes estimées |
|---|---|
| Corps : création, apparence humaine, armes en main, identité | 1 500 à 2 500 |
| Neutralisation des comportements de zombie (attaque, morsure, voix, démarche) | 1 000 à 2 000 |
| Animations : XML d'états de zombie conditionnés par nos variables, en partie générés par script | 4 000 à 8 000 (XML) |
| Exécution MP : adoption par le propriétaire, rapports contrôlés, consignes, relais des gestes, transferts | 2 000 à 3 500 |
| Déplacement et obstacles (portes, fenêtres, clôtures, barricades, escaliers) | 2 000 à 4 000 |
| Perception (vue, ouïe, lumière) | 500 à 1 000 |
| Cadre de décision et routines (sommeil, garde, patrouille, expédition, retour) | 1 500 à 3 000 |
| Combat : cibles, mêlée, tir, munitions, rechargement, zombies contre PNJ dans les deux sens, dégâts serveur | 3 000 à 5 000 |
| Santé, saignement, mort, butin | 800 à 1 500 |
| Matérialisation et retrait, persistance des corps | 1 000 à 1 500 |
| Outils de debug et suites de tests | 1 000 à 2 000 |
| **Total moteur** | **≈ 15 000 à 25 000 lignes de Lua + 4 000 à 8 000 lignes de XML** |

Le socle commun (§4 : groupes, besoins, simulation, relève, récits, lien RadioSurvivor), ≈ 4 000 à 7 000 lignes, s'ajoute dans toutes les options.

**Durée avec un agent de codage** (hypothèses : Claude Code écrit et teste hors jeu ; l'utilisateur fait les essais en jeu ; méthode du plan, une tâche à la fois) :
- **Écriture** : ≈ 1 500 à 2 500 lignes testées hors jeu par journée de travail de l'agent, soit ≈ 10 à 15 journées d'agent pour le moteur. Ce n'est pas le facteur limitant.
- **Validation en jeu, facteur limitant** : chaque sous-système demande plusieurs aller-retours en jeu (rendu des animations, ressenti du combat, cas d'obstacles, MP à deux clients), soit ≈ 40 à 80 sessions d'essai.
- **Jalons réalistes** :
  1. **Corps et gestes prouvés** en solo et à deux clients (PNJ à l'air humain, arme en main, marche et visée vues par l'autre joueur) : 2 à 3 semaines. Point de décision : continuer ou abandonner.
  2. **Groupe vivant jouable** (routine, déplacements, mêlée, mort) : + 3 à 5 semaines.
  3. **Combat à distance, obstacles et interactions avec les zombies, solides en MP** : + 4 à 8 semaines.
  4. **Total : ≈ 2 à 4 mois** calendaires au rythme d'une à deux sessions d'essai par jour ; davantage si les essais à deux clients sont rares.

**Impact** :
- **Complexité** : la plus élevée de toutes les options. Il faut maîtriser des comportements non documentés du moteur, que les deux autres mods ont dû découvrir (santé en MP, transferts de propriétaire, états d'animation des zombies distants).
- **Maintenabilité** : bonne sur la durée. Code à nous, commenté et testé selon notre méthode, aucune dépendance qui change sous nos pieds ; en contrepartie, chaque mise à jour du jeu (42.22 et suivantes) est à suivre nous-mêmes.
- **Ouverture** : maximale. Décisions serveur, groupes, besoins, dialogue LLM, compagnons, troc et radio conçus dans le moteur, pas greffés dessus.
- **Fonctionnalités** : au départ, moins riches qu'A-Life (factions, voix, éditeur, escouades sur les routes) mais exactement ciblées ; elles s'ajoutent selon nos besoins.
- **Licence et publication** : aucune contrainte. Le code doit être écrit **indépendamment**, sans reprendre de code de Bandits! ni d'A-Life, que nous avons lus en détail : documenter nos propres choix de conception.
- **Compatibilité** : un seul mod de PNJ par serveur, comme toujours ; RadioSurvivor vise alors notre moteur par son fournisseur de PNJ.

### D — Contribution amont (en parallèle de A+ ou E)
Proposer aux auteurs les corrections ou les points d'extension utiles : propriétaire unique chez Bandits! ; API et événements chez A-Life, qui annonce une « Friendly Update » (compagnons, ordres). Résultat incertain, coût faible.

## 6. Comparaison

Échelle : ++ très favorable, + favorable, ~ neutre, − défavorable, −− très défavorable.

| Critère | A | A+ | B | **E (A-Life)** | **C (moteur propre)** |
|---|---|---|---|---|---|
| **Faisabilité** | ++ | + accroche vérifiée, relais à écrire | ~ gros volume | + exécution MP faite ; groupes permanents et coupure des directeurs à valider | ~ faisable (animations = XML sur clips vanilla), comportements du moteur à découvrir |
| **Ouverture** | − combat figé et divergent | + nos gestes, combat Bandits! | ++ | + registres de modules, dialogues, rencontres, avant-postes ; postures internes non extensibles ; pas d'événements | ++ tout est conçu pour nous |
| **Simplicité** (notre code) | ++ | ~ | −− | + aucune couche d'exécution à écrire ; mais 146 000 lignes non commentées à comprendre | −− le plus gros chantier |
| **Robustesse MP** | −− | + dépend de nos relais | + nos propres bugs | + mécanismes mûrs (propriétaire, contrôles serveur, dégâts serveur, transferts) ; faiblesses connues §3 | + conçue d'emblée (propriétaire unique, décisions serveur), mais tout est à éprouver |
| **Maintenabilité** | ~ | ~ deux globales enveloppées | − | − pas d'API, commentaires retirés, mod créé le 2026-09-18 et mis à jour très souvent ; nos enveloppes peuvent casser à chaque version | + code à nous, commenté, testé ; seules les mises à jour du jeu à suivre |
| **Coût** hors socle | ≈ 30 lignes | ≈ 400 à 650 | ≈ 2 600 à 3 000 | ≈ 300 à 600 lignes d'intégration **et** réécriture du fournisseur de PNJ de RadioSurvivor | ≈ 15 000 à 25 000 lignes de Lua + 4 000 à 8 000 de XML ; 2 à 4 mois calendaires |
| **Compatibilité** | ++ | + | −− | ~ un seul mod de PNJ par serveur : abandonner Bandits! (et le carnet 0.2 écrit pour lui) | ~ un seul mod de PNJ par serveur ; RadioSurvivor vise notre moteur |
| **Licence** | ++ | ++ | + réécriture indépendante | ++ dépendance seulement ; contacter l'auteur conseillé | ++ aucune contrainte (écriture indépendante) |
| **Charge** | − × N clients | ++ | ++ | + une IA par PNJ, budgets ; diffusion des gestes à tous les clients | ++ conçue pour quelques groupes |

### Lecture

- **Le problème que tu soulevais (IA chez les clients)** : A-Life le résout déjà correctement, dans les limites du moteur (propriétaire unique, serveur arbitre). Bandits! ne le résout pas ; A+ le résoudrait en reproduisant à petite échelle ce qu'A-Life fait.
- **Ouverture et adéquation** : A-Life est un monde vivant **ambiant** (148 factions, rencontres, avant-postes éphémères) qu'il faudra brider ; nos groupes permanents restent à écrire, comme avec Bandits!. Son outillage (éditeur, dialogues, radio, carte admin) est un plus.
- **Maintenabilité** : c'est le vrai risque d'A-Life. Le mod a deux semaines, change vite et n'expose aucune API. Les parades : vérification au démarrage (`Runtime.VERSION`, présence et type des fonctions visées), enveloppes défensives, contact avec l'auteur, et un adaptateur qui isole tout appel à A-Life.
- **RadioSurvivor** : le carnet 0.2 (sélection Ctrl+G, signature et fiches, mort, chat de proximité) vise Bandits!. Passer à A-Life impose un « fournisseur de PNJ » et la réécriture de l'adaptateur Bandits! ; A-Life a aussi son propre dialogue de proximité qui répondrait en double (à couper par enveloppe).

## 7. Recommandation et chemin

1. **Socle commun d'abord** (§4), avec un adaptateur d'exécution côté sous-mod et un fournisseur de PNJ côté RadioSurvivor. Il ne dépend pas du choix.
2. **Essai court et décisif sur A-Life (E)**, avant tout engagement, sur le serveur de test avec deux clients :
   1. couper tout peuplement aléatoire ;
   2. fonder un groupe permanent sur un site choisi, avec notre faction ;
   3. le faire garder ou patrouiller par la mémoire de posture ;
   4. remplacer une réplique par un texte externe ;
   5. vérifier l'identité des membres après sauvegarde et rechargement, et après un changement de propriétaire ;
   6. noter la version d'A-Life et ce qui a cassé entre deux mises à jour.

   En parallèle, contacter l'auteur d'A-Life.
3. **Si l'essai réussit** : E. Le sous-mod devient un addon d'A-Life (à renommer : il ne dépend plus de Bandits!), et RadioSurvivor vise A-Life par son fournisseur de PNJ.
4. **Si l'essai échoue** (groupes permanents impossibles, identité instable, enveloppes trop fragiles) : **A+** sur Bandits!, avec la même méthode par étapes mesurées.
5. **C (moteur propre)** est l'option à plus forte valeur à long terme (ouverture, maintenabilité, aucune dépendance) et au coût le plus élevé (2 à 4 mois). Elle se décide sur un jalon : corps et gestes prouvés en solo et à deux clients en 2 à 3 semaines, sinon repli sur E ou A+.
6. **A** reste réservé à un prototype solo ; **B** est dominée par C (même effort de réécriture, mais toujours liée à Bandits!).

## 8. Points à mesurer en premier

- A-Life : les six points de l'essai ci-dessus ; bande passante de `animationSync` avec 3 à 5 groupes et 4 joueurs ; à-coup au changement de propriétaire.
- Bandits! (si A+) : tirs fantômes, sons en double, portes, santé et zombification à deux clients ; latence d'un geste relayé ; dégâts appliqués par le serveur à un joueur non propriétaire.
