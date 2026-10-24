# Plan d'implémentation RadioSurvivor — méthode

Ce dossier découpe le projet en **étapes** successives. Chaque étape a son fichier et contient des **tâches** numérotées, chacune avec un état vérifiable. Claude Code suit ces fichiers dans l'ordre pour mener le projet à bien, une tâche à la fois.

Deux familles d'étapes cohabitent dans ce plan unique depuis la fusion du 2026-10-08 (un seul mod `batman_RadioSurvivor`) :

- `E00` à `E17` : radio, carnet, missions, voix, publication ;
- `LK00` à `LK14` : moteur de PNJ **Living Knox** (ancien projet séparé `LivingKnox`, identifiants conservés). Ses règles propres sont plus bas, section « Règles propres à Living Knox ».

- Vue d'ensemble générée : [SUIVI.md](SUIVI.md)
- Outil : `python RadioSurvivor/tools/plan.py check | suivi | next | show E01-T02` (depuis `%USERPROFILE%\Zomboid\Workshop`)
- Sources de conception Living Knox : [analyse d'architecture](../../architecture/ia-multijoueur.md), études [Bandits!](../recherches/bandits-analyse.md) et [Project A-Life](../recherches/alife-analyse.md), décisions [LK00](LK00-cadrage.md).
- Sources de conception : [spécifications Bandits/LLM](../recherches/bandits-llm-specifications.md), [note de travail du carnet radio](../maquettes/note-de-travail.html), [contrat Lua ↔ Python v2](../../specifications-techniques/protocole-carnet-v2.md), [ADR B17](../../architecture/decisions/adr-b17-chat-proximite-pnj.md), [implémentation 0.2](../conception/carnet-implementation-04221.md), [validation 0.2](../tests/carnet-validation-04221.md).

## Format d'une tâche

```markdown
- [ ] **E01-T02** — Titre court et cherchable
  - État : `à faire`
  - Cible : `hors jeu`
  - Dépend de : E01-T01
  - Fichiers : chemins créés ou modifiés
  - Faire : ce qu'il faut coder, précisément
  - Accepté si : critères vérifiables
  - Tests : tests hors jeu à écrire ou lancer ; suites en jeu concernées
  - Preuve : —
  - Reste : —
```

- **Identifiant** `E<étape>-T<numéro>` ou `LK<étape>-T<numéro>` : stable, jamais réutilisé ni renuméroté. Une tâche ajoutée prend le numéro suivant libre de son étape, même si elle s'insère logiquement plus haut.
- **Case** `[x]` : cochée seulement quand l'état atteint la cible. `plan.py check` refuse toute incohérence.
- **Cible** : le niveau de preuve exigé pour terminer la tâche.
  - `hors jeu` : banc `lupa` et luacheck suffisent (logique pure, protocole, pont Python).
  - `solo` : la tâche touche une API Java, l'interface ou un comportement que la simulation ne prouve pas.
  - `MP` : autorité serveur, synchronisation, inventaires partagés ou plusieurs clients.
- **Preuve** : hachage court du commit entre accents graves (vérifié par `plan.py check`), nom du test, suite en jeu et fichier de résultat. Un état sans preuve est refusé.
- **Reste** : ce qui manque pour l'état suivant ; obligatoire pour `bloqué` et `abandonné`. `⚠` signale un point technique à vérifier.

### États

| État | Sens |
|---|---|
| `à décider` | Une question de conception est ouverte : **demander à l'utilisateur avant de coder** |
| `à faire` | Prête, conception suffisante |
| `en cours` | Une seule à la fois dans tout le plan |
| `codé` | Code écrit, tests pas encore au vert |
| `testé hors jeu` | Tests `lupa`, luacheck et `plan.py check` au vert |
| `testé solo` | Suite de la tâche verte dans la campagne solo automatique (`autoclient.py --campaign solo --bridge on`) |
| `testé MP` | Suite de la tâche verte dans la campagne MP automatique (serveur dédié + deux clients pilotés, `autoclient.py --mp`) ; rapport de la campagne en preuve |
| `bloqué` | Impossible pour l'instant ; raison dans « Reste » |
| `abandonné` | Retiré par décision ; raison dans « Reste » |

Une dépendance est **utilisable** dès qu'elle est `testé hors jeu`. Les validations en jeu se font par lots (une session de jeu valide plusieurs tâches), sans bloquer le code des étapes suivantes. Le parcours d'une étape n'est **terminé** que lorsque toutes ses tâches ont atteint leur cible.

## Boucle de travail de Claude Code

À chaque demande du type « continue le plan RadioSurvivor » (skill `radiosurvivor-plan`) :

1. `python RadioSurvivor/tools/plan.py next` : lire la tâche proposée, puis le fichier d'étape entier (objectif, décisions, hors périmètre).
2. **Décision requise** (`à décider`) : poser les questions listées dans la tâche, **une à la fois, avec trois options fermées et une réponse libre**, en recommandant l'une d'elles. Ne rien coder. Après la réponse : écrire la décision dans le fichier d'étape (section Décisions, avec la date), passer la tâche à `à faire`, puis continuer.
3. Passer la tâche à `en cours`. Relire `.claude/pz-knowledge/README.md` puis chercher les mots-clés de la tâche dans la base. Lire les fichiers cités et le code vanilla ou Bandits concerné (lecture seule du Workshop Steam).
4. Coder **uniquement** le périmètre de la tâche. Une découverte qui demande plus de travail devient une nouvelle tâche (numéro suivant), pas une extension silencieuse.
5. Tests : écrire ou mettre à jour les tests `lupa` (`tests/test_carnet.py`, `tests/test_protocol.py`, ou un nouveau fichier), puis lancer :
   ```powershell
   python RadioSurvivor/tests/test_protocol.py
   python RadioSurvivor/tests/test_carnet.py
   luacheck RadioSurvivor/Contents --config RadioSurvivor/.luacheckrc
   python RadioSurvivor/tools/plan.py check
   ```
   Le nombre d'avertissements luacheck ne doit pas augmenter. Si la tâche a des suites en jeu, les écrire aussi (moteur E01) et les lancer dans le banc `lupa` quand elles le permettent.
6. Mettre à jour la tâche : état, preuve (tests, puis commit), reste. Régénérer `SUIVI.md` (`plan.py suivi`). Mettre à jour la documentation touchée (README du mod, `docs/annexes/conception/carnet-implementation-04221.md` ou son successeur).
7. Commit **par tâche** sur une branche de travail, message `E01-T02: titre` suivi des lignes d'attribution. Pousser seulement si l'utilisateur l'a demandé.
8. Base de connaissances : journaliser toute découverte générique sur le moteur (`AGENTS.md` du dossier de développement parent, section obligatoire), sans nom de mod.
9. Si la cible est `solo` ou `MP` : écrire la suite en jeu, lancer la campagne automatique correspondante et consigner le rapport comme preuve. Ne **jamais** annoncer un test en jeu non effectué ; un échec se rapporte avec sa sortie.
10. S'arrêter après une tâche, ou enchaîner si l'utilisateur l'a demandé. Le compte rendu cite les identifiants traités, les tests lancés et ce qui reste à valider en jeu.

## Règles permanentes

- Cible **Project Zomboid 42.21**, priorité serveur dédié. `AGENTS.md` du dossier Workshop s'applique : jamais de modification du Workshop Steam `108600`, correctifs de mods tiers par wrappers dans ce mod ou mod local `batman_…`.
- **Autorité serveur** : un client ne décide jamais d'un effet (inventaire, relation, réputation, mission). Le LLM propose dans une liste fermée, le serveur valide.
- **Aucun secret** dans une ModData globale ni dans un prompt ; état privé dans les fichiers serveur (`RS_State`).
- **Coût LLM borné** : toute nouvelle source d'appel passe par les quotas existants (`MAX_PER_HOUR`, budget d'enrichissement) et dispose d'un secours sans pont.
- **Charge bornée** : pas de travail proportionnel à toute la population Bandits ; fiches créées au contact, purge des données mortes, sauvegarde sur changement.
- Une tâche qui change le contrat Lua ↔ Python met à jour `docs/specifications-techniques/protocole-carnet-v2.md` et les deux côtés dans le même commit.
- Les décisions déjà tranchées dans les spécifications ne se rediscutent pas ; un écart nécessaire devient une tâche `à décider`.

## Règles propres à Living Knox (étapes `LK`)

- **Écriture indépendante.** Bandits! (copyright de son auteur, republication refusée) et Project A-Life (tous droits réservés) ont été lus pour comprendre les contraintes du moteur. Aucun extrait de leur code n'est repris, traduit ni paraphrasé. Leurs **idées de jeu** peuvent l'être : elles sont relevées avec leur source dans [`docs/annexes/recherches/idees-bandits-alife.md`](../recherches/idees-bandits-alife.md) et citées par le champ « Idées » des tâches ; leurs valeurs chiffrées ne sont que des points de départ. Chaque choix de conception du moteur s'appuie sur le Java et le Lua vanilla 42.21, la base de connaissances ou nos propres mesures, et se documente dans `docs/annexes/conception/`.
- **Autorité serveur** pour toute décision persistante (groupes, consignes, besoins, combat, morts, relève). Exécution des corps par le seul client propriétaire. Aucune donnée secrète dans une ModData globale.
- **Jalon de décision** : l'étape LK02 (corps et gestes prouvés en solo et à deux clients) se termine par un choix explicite de continuer ou de se replier (A-Life ou Bandits!, voir l'analyse d'architecture).
- **Un seul moteur de PNJ actif par partie** : le moteur Living Knox ne tourne pas en même temps que Bandits! ou Project A-Life. Depuis la fusion, la façon de l'imposer dépend du sort de l'adaptateur Bandits! du carnet (`E17-T01`, `LK01-T04`).
- Code sous `media/lua/{shared,server,client}/LivingKnox/`, fichiers préfixés `LK_`, dans le mod `batman_RadioSurvivor`.

## Méthode de validation en jeu

- Moteur de tests en jeu (étape E01) : suites Lua lancées depuis la console Lua du mode debug (`RST.run(...)`), résultats écrits dans un fichier sous `Zomboid\Lua\batman_RadioSurvivor\tests\`. Ce fichier sert de preuve.
- Les suites qui modifient le monde (spawn, inventaire) refusent de tourner hors d'une partie de test dont le nom commence par `rstest`.
- **Les tests font foi (décision de l'utilisateur, 2026-10-14 ; remplace la « séance finale » MP du 2026-10-09)** : il n'y a plus de séance multijoueur manuelle à la fin. Une tâche de cible `MP` passe à `testé MP` dès que sa suite passe dans la campagne MP automatique :
  ```powershell
  python RadioSurvivor/tools/autoclient/autoclient.py --mp --clients 2 --server-campaign mp --bridge on --timeout 7200 --wait-idle 3600
  ```
  le rapport serveur de la campagne (`tools/autoclient/runs/<run>/server/*-server.txt`) servant de preuve. Une tâche de cible `solo` passe à `testé solo` quand sa suite passe dans la campagne solo automatique (`autoclient.py --campaign solo --bridge on`).
- Chaque tâche de cible `MP` a au moins une suite automatique verte. Les contrôles « à la main » d'un champ « Reste » sont soit automatisés (suite en jeu, au besoin exécutée par le client 2), soit abandonnés avec leur raison dans « Reste ».
- Bancs : campagne solo (partie `rstest-…` pilotée), campagne MP (serveur dédié sans zombies ambiants, mode dieu, point d'apparition fixe, 4 Go par client, 3 Go pour le serveur) et petite campagne `mp-ambient` (zombies vanilla, sans mode dieu) pour la robustesse. Un seul jeu à la fois sur le PC (`--wait-idle`).
