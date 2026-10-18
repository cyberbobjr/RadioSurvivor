# Radio Survivor

[English](README.md)

**Des voix à la radio et des survivants bien vivants dans le comté de Knox.**
Mod pour Project Zomboid **Build 42.21**, solo et multijoueur (serveur dédié compris).
Identifiant `batman_RadioSurvivor`, version **0.3.0 (version de test)**.

Knox County, juillet 1993. La zone est bouclée, les survivants sont seuls. Radio Survivor leur donne ce que le jeu de
base n'a pas : **des voix de l'autre côté de la radio**, jouées par une intelligence artificielle, et **d'autres
survivants en chair et en os**, des groupes de PNJ qui vivent leur vie dans le comté. Un carnet de terrain sert à les
rencontrer, à gagner leur confiance et à accepter leurs missions.

> **Le pont d'IA.** Les dialogues sont écrits par un modèle de langage (LLM). Le jeu ne peut pas l'appeler lui-même :
> un petit programme Python, **le pont**, fait l'intermédiaire et doit tourner sur la machine qui exécute la partie
> (votre PC en solo, la machine du serveur en multijoueur). Sans pont, le jeu reste jouable mais les voix et les PNJ se
> taisent. Tout est expliqué dans [Le pont d'IA](#le-pont-dia).

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Installation du mod](#installation-du-mod)
- [Le pont d'IA](#le-pont-dia)
- [Configuration](#configuration)
- [Jouer](#jouer)
- [Dépannage](#dépannage)
- [État du projet](#état-du-projet)
- [Développement](#développement)

## Fonctionnalités

### La radio

- **Six voix**, chacune sur sa propre fréquence, tirée au hasard à chaque partie : Walt, le confident sorti de la zone ;
  Darlene, infirmière à West Point ; Cody, déserteur de la Garde nationale ; les Whitaker, famille assiégée ; le Night
  Owl, station pirate ; Gus, passeur de l'Ohio. Chacune a son caractère, ses horaires et la radio qu'il faut pour la
  joindre.
- **On les trouve en fouillant** : des notes du butin (page de journal, fiche de patient, avis de recherche, prospectus…)
  donnent les fréquences de la partie. Aucune liste n'est envoyée aux joueurs.
- **On leur parle avec n'importe quelle radio émettrice** : talkie en main ou sur le dos, radio de radioamateur posée,
  autoradio d'un véhicule. Une section **Émettre** s'ajoute à la fenêtre radio du jeu.
- **Elles agissent**, mais seul le serveur décide : repère sur votre carte, quartier révélé, mission de
  reconnaissance (Darlene, Cody), troc avec le passeur. L'IA propose dans une liste fermée, le serveur vérifie.
- **Parler fait du bien** : chaque réponse d'un survivant à votre personnage par radio apaise un peu l'ennui et la
  tristesse ; entendre deux survivants discuter apaise un peu l'ennui (quelques fois par heure de jeu au plus).
- **Appels spontanés**, **bulletin du soir** de la station pirate (faits du serveur, mémorial des morts du jour) et
  **dernières pages** : à la mort d'un personnage, son journal manuscrit est écrit et laissé sur le corps.
- **Survivants à secourir** : une famille appelle à l'aide depuis un vrai bâtiment, avec des indices ; secourue à temps
  elle laisse une cache, sinon on trouve la scène.
- **Le passeur de l'Ohio** : troc négocié à la radio, une traversée par semaine de jeu, échange sans contact de nuit sur
  une berge.

### Le carnet et les PNJ

- **Carnet de terrain** (bouton **Carnet** de la barre latérale) : contacts, onglet Radio (historique par fréquence, avec qui y parle et ses heures d'écoute dès le premier contact ou la note lue),
  missions, réputation, notes.
- **Parler à un PNJ** : s'en approcher, **Ctrl+G** pour le sélectionner, puis parler dans le chat local (`/say`). Il
  répond en bulles et se souvient de vous.
- **Missions** : livrer, reconnaître, retrouver les papiers d'un disparu, nettoyer un lieu, récupérer une cache, faire un
  signal (fumigène ou fusée, mod Signal Smoke). L'objectif rempli, il faut **revenir le dire** au demandeur (ou à la
  radio pour une mission donnée par une voix), puis **Récupérer le lot commun** (la récompense).
- **Relations** : chaque PNJ a son avis sur vous, qui change sur des faits réels (aide, vol, mission réussie ou ratée),
  jamais sur de simples paroles. Trêves et alliances se négocient avec le chef d'un groupe.
- **Réputation** (mauvaise, neutre, bonne), tenue par le serveur : elle monte avec les missions réussies, baisse avec les
  échecs, les abandons, la tricherie envers le passeur, et chute si vous tuez celui qui vous a confié une mission. Une
  mauvaise réputation ne laisse que les missions simples, le passeur fait payer plus cher, les PNJ en parlent.

### Living Knox, le moteur de PNJ

- **Trois à cinq groupes de survivants** (colons, neutres, pillards), chacun avec un chef, des membres, une histoire et un
  foyer aménagé dans un vrai bâtiment, dont le stock est fait d'objets réels.
- **Une vie** : sommeil, gardes et rondes, corvées, repas pris dans le stock, entretien du générateur, expéditions de
  fouille, cueillette, arrosage et récolte du potager.
- **Une défense** : alerte, défense du foyer depuis des postes, campement qui se défend sur place, fortification
  progressive (barricades, murs, palissades) et réparation après une attaque.
- **Face aux joueurs** : sommations avant tout tir, demandes d'aide, troc, vengeance après un meurtre, raids annoncés des
  pillards sur les bases des joueurs.
- **Hors écran** : les groupes continuent de vivre loin des joueurs ; un groupe décimé laisse ses traces et un autre
  s'installe ailleurs.
- Les PNJ sont des corps humains (vêtements, armes, gestes de joueur) pilotés par le serveur, conçus pour le
  multijoueur.

## Prérequis

| Élément | Où | Remarque |
|---|---|---|
| Project Zomboid **42.21** | — | Build 41 non prise en charge. |
| **Belt Walkie-Talkie** (`batman_BeltRadio`) | Workshop 3817018338 | Mod requis (talkie à la ceinture, règle d'émission commune). |
| **TooltipLib** (`TooltipLib`) | Workshop 3694097672 | Requis par Belt Walkie-Talkie. |
| **Signal Smoke** (`batman_SignalSmoke`) | Workshop 3811010882 | Mod requis (fumigènes et fusées des missions, du passeur et des secours). |
| **Python 3.10 ou plus récent** | sur la machine de la partie | Pour le pont d'IA. Aucun paquet à installer. |
| **Une clé d'API d'IA** | chez un fournisseur | Compatible avec l'API OpenAI (voir [Fournisseur d'IA](#3-la-clé-et-le-fournisseur-dia)). |

**Incompatible** avec Bandits! et Project A-Life : un seul moteur de PNJ par partie (le sélecteur de mods le signale).
`batman_CharacterReputation` est facultatif.

## Installation du mod

### En solo

1. Abonnez-vous aux mods requis et à Radio Survivor sur le Workshop, **ou** copiez les dossiers de mods dans
   `%USERPROFILE%\Zomboid\mods\` (installation sans Workshop, par exemple à partir du zip de test : voir son
   `LISEZMOI.md`).
2. Dans **Mods**, activez dans cet ordre : TooltipLib, Belt Walkie-Talkie, Signal Smoke, Radio Survivor.
3. Redémarrez complètement le jeu après une installation ou une mise à jour.
4. **Créez une nouvelle partie** : les groupes de survivants s'installent au démarrage du monde.
5. Installez et lancez le [pont d'IA](#le-pont-dia).

### Sur un serveur dédié

Dans `<Zomboid>/Server/<nom du serveur>.ini`, ajoutez les quatre objets Workshop et les quatre identifiants de mod
(en gardant vos autres entrées, séparées par `;`) :

```ini
WorkshopItems=<ID Workshop de Radio Survivor>;3817018338;3694097672;3811010882
Mods=TooltipLib;batman_BeltRadio;batman_SignalSmoke;batman_RadioSurvivor
```

Les joueurs n'ont rien d'autre à installer que les mods. Le pont tourne **sur la machine du serveur** : voir
[Pont sur un serveur dédié](#pont-sur-un-serveur-dédié).

## Le pont d'IA

### Comment ça marche

Le Lua de Project Zomboid n'a aucun accès réseau. Le jeu (le serveur en multijoueur, votre jeu en solo) échange donc
avec le pont par deux fichiers texte, dans un **dossier d'échange** ; le pont appelle l'API de l'IA :

```text
jeu ──requests.txt──▶ pont ──HTTPS──▶ API de l'IA
jeu ◀─responses.txt── pont ◀─────────
```

- Dossier d'échange : `<dossier Zomboid>/Lua/batman_RadioSurvivor/` (en solo sous Windows :
  `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor`).
- Le pont signale qu'il est vivant en réécrivant `bridge-alive.txt` toutes les 5 s. Tant qu'il est vivant, le jeu attend
  une réponse lente jusqu'à 150 s ; sans pont, il passe au secours après 90 s.
- Le serveur ne transmet jamais de secret à l'IA (position exacte des bases, fréquences cachées…) et vérifie chaque
  action qu'elle propose.
- **Un mod Workshop ne peut ni fournir ni lancer un programme** : le pont s'installe et se lance à la main.

| Partie | Où tourne le pont |
|---|---|
| Solo | Sur votre PC |
| Partie hébergée depuis le menu (« Héberger ») | Sur le PC de l'hôte |
| Serveur dédié | Sur la machine du serveur (ou un conteneur voisin) |
| Joueurs qui se connectent | **Rien à installer** |

### 1. Les fichiers

Le pont tient en cinq fichiers Python, à garder **ensemble dans un même dossier** et à mettre à jour avec le mod :

| Fichier | Rôle |
|---|---|
| `radio_bridge.py` | Programme principal : surveillance des fichiers, appels à l'IA, réponses |
| `npc_protocol.py` | Dialogues des PNJ du carnet |
| `persona_store.py` | Lecture des fiches de caractère des voix |
| `bulletin.py` | Bulletin du soir de la station pirate |
| `last_pages.py` | Dernières pages d'un personnage mort |

S'y ajoute `.env.example`, le modèle du fichier de réglages. Dans ce dépôt : dossier [`bridge/`](bridge/).

### 2. Python

Python 3.10 ou plus récent (`python --version`, ou `python3 --version` sous Linux). Le pont n'utilise que la
bibliothèque standard : rien à installer avec `pip`.

### 3. La clé et le fournisseur d'IA

Le pont parle à tout fournisseur compatible avec l'**API Chat Completions d'OpenAI** (`POST <adresse>/chat/completions`) :
OpenAI, DeepSeek, OpenRouter, Mistral, ou un serveur local comme Ollama ou LM Studio. Copiez `.env.example` en `.env`
dans le dossier du pont et remplissez les trois réglages :

```ini
OPENAI_KEY=<votre clé>
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=<nom du modèle chez ce fournisseur>
```

- `OPENAI_BASE_URL` s'écrit **sans** `/chat/completions`. Prenez l'adresse et le nom de modèle exacts dans la
  documentation de votre fournisseur. Un serveur local n'exige en général pas de clé : mettez une valeur quelconque.
- Une **variable d'environnement** du même nom l'emporte sur le fichier ; un autre fichier se désigne par
  `--env CHEMIN`.
- **Ne partagez jamais `.env`** ni un journal `--debug` (il contient les prompts). Le bandeau du pont n'affiche que
  `API key: configured (hidden)`. En cas de fuite, révoquez la clé chez le fournisseur.

### 4. Vérifier sans le jeu

Dans un terminal ouvert dans le dossier du pont :

```powershell
python radio_bridge.py --test "Allô ?"
```

Quelques lignes de Walt s'affichent : la clé, l'adresse et le modèle sont bons. `--voice darlene` essaie une autre voix ;
`--offline` vérifie l'installation sans clé ni coût (la voix répète votre phrase).

### Pont en solo

```powershell
python radio_bridge.py
```

Le bandeau affiche la configuration effective, puis `Bridge ready, model …, directory …`. **Laissez la fenêtre ouverte**
pendant la partie ; l'ordre (jeu ou pont d'abord) est indifférent. Arrêt par **Ctrl+C**.

- Dossier d'échange par défaut : `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` (créé au besoin).
- Jeu lancé avec `-cachedir=X` : ajoutez `--exchange "X\Lua\batman_RadioSurvivor"`.
- Pour garder le journal dans un fichier : `python radio_bridge.py > bridge.log 2>&1`.

### Pont en partie hébergée

Comme en solo, sur le PC de l'hôte : le serveur lancé par le jeu utilise le même dossier `Zomboid` que le jeu de l'hôte.

### Pont sur un serveur dédié

1. **Le bon dossier d'échange.** Le pont doit surveiller exactement le dossier où écrit le serveur :

   | Cas | Dossier d'échange |
   |---|---|
   | Windows, sans `-cachedir` | `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` |
   | Linux, sans `-cachedir` | `/home/<compte du serveur>/Zomboid/Lua/batman_RadioSurvivor` |
   | Serveur lancé avec `-cachedir=X` | `X/Lua/batman_RadioSurvivor` |

   Sans `--exchange`, le pont prend le dossier `Zomboid` de **son propre** compte : passez `--exchange` dès que le
   serveur tourne sous un autre compte ou avec `-cachedir`. Le pont crée le dossier s'il manque, donc une faute de
   frappe ne donne aucune erreur : après le premier chargement du monde, le bon dossier contient `personas/`.
2. **Installer** les cinq fichiers dans un dossier (par exemple `C:\RadioSurvivorBridge` ou
   `/opt/radiosurvivor-bridge`) et le fichier de clé **hors** de ce dossier et des dossiers du jeu, lisible par le seul
   compte du pont (`chmod 600` sous Linux).
3. **Tester à la main** :

   ```sh
   python3 /opt/radiosurvivor-bridge/radio_bridge.py --env /etc/radiosurvivor/bridge.env \
     --exchange /srv/pz/cache/Lua/batman_RadioSurvivor
   ```

   et attendre `Bridge ready`.
4. **Le lancer avec le serveur.** Sous Linux, un service systemd :

   ```ini
   # /etc/systemd/system/radiosurvivor-bridge.service
   [Unit]
   Description=Radio Survivor bridge (Project Zomboid)
   After=network-online.target
   Wants=network-online.target

   [Service]
   User=<compte du serveur PZ>
   ExecStart=/usr/bin/python3 /opt/radiosurvivor-bridge/radio_bridge.py --env /etc/radiosurvivor/bridge.env --exchange /srv/pz/cache/Lua/batman_RadioSurvivor
   Restart=on-failure
   RestartSec=10
   KillSignal=SIGINT

   [Install]
   WantedBy=multi-user.target
   ```

   puis `sudo systemctl daemon-reload && sudo systemctl enable --now radiosurvivor-bridge` (journal :
   `journalctl -u radiosurvivor-bridge -f`). Sous Windows : une tâche planifiée « Au démarrage » qui lance
   `python radio_bridge.py --env … --exchange …`. Avec Docker : un second conteneur `python:3.12-slim` qui monte **le
   même volume** que les données du serveur, sous le même utilisateur. Détails, Windows et Docker :
   [docs/installation-pont.md](docs/installation-pont.md) ([English](docs/bridge-setup.md)).
5. **Règles** :
   - **un seul pont par dossier d'échange** : un second refuse de démarrer (`bridge.lock`) ; deux serveurs sur la même
     machine ont chacun leur `-cachedir` et leur pont ;
   - le pont tourne sur **la même machine** (ou le même hôte de conteneurs) que le serveur : l'âge des demandes (75 s)
     et le battement de vie se comparent à l'horloge locale ;
   - le compte du pont lit et écrit le dossier d'échange, le compte du serveur lit ce que le pont écrit.

### Options du pont

| Option | Rôle |
|---|---|
| `--offline` | Sans IA, sans clé, sans coût : les voix répètent votre phrase (pour tester l'installation). |
| `--test "TEXTE"` | Un échange en console, sans le jeu ; `--voice ID` pour une autre voix que `walt`. |
| `--env CHEMIN` | Autre fichier de réglages que `.env` à côté du pont. |
| `--exchange CHEMIN` | Autre dossier d'échange. |
| `--personas CHEMIN` | Dossier des fiches de voix pour `--test` (défaut : les fiches livrées avec le mod). |
| `--usage-log CHEMIN` | Journal de consommation (défaut `<échange>/token_usage.jsonl`). |
| `--debug` | Journal complet dans le terminal, prompts et dialogues compris. |
| `--poll SECONDES` | Intervalle de lecture de `requests.txt` (défaut 0,3). |
| `--help` | Aide complète. |

### Coût

- Chaque message radio, chaque réplique de PNJ, chaque appel spontané, bulletin ou dernière page est **un appel à
  l'IA** (jusqu'à deux ou trois si le fournisseur refuse un paramètre ou rend une réponse vide).
- Garde-fous en jeu : option **`MaxPerHour`** (60 messages radio par heure réelle pour tout le serveur, `0` = illimité,
  à éviter sur un serveur public), `PlayerCooldown`, `InitiativeFrequency` pour les paroles spontanées des PNJ, plafonds
  fixes de 60 dialogues de PNJ et 12 biographies par heure.
- La consommation (tokens par appel, cumuls) est écrite dans `token_usage.jsonl` ; le pont n'estime aucun prix.
- **Fixez une limite de dépense mensuelle chez votre fournisseur** : c'est la seule limite qui tient même si une option
  est mal réglée.

### Sans le pont

Le jeu reste jouable : la radio répond « Rien que des parasites… », le bulletin du soir et les dernières pages prennent
de courts textes fixes, et les PNJ se taisent. Tout le reste (groupes, combats, foyers, missions par le carnet, troc)
continue.

## Configuration

### Options sandbox

Deux pages dans les réglages sandbox (sur un serveur dédié : `<Zomboid>/Server/<nom>_SandboxVars.lua`).

**Radio Survivor** : `Enabled` (voix radio), `PlayerCooldown` (10 s entre deux messages d'un joueur), `MaxPerHour`
(60), `SpontaneousCalls`, `CallLanguage` (langue des appels spontanés), `NoteRarity` (notes de fréquences dans le
butin), `ChronicleHour` (heure du bulletin, 20 h), `LastPages`, `InitiativeFrequency` (paroles spontanées des PNJ),
`RescueDays` (temps pour secourir une famille), `ComfortBoredom` / `ComfortSadness` (3 / 1 retirés par une réponse radio),
`ComfortListen` (1 d'ennui retiré par une conversation entendue), `ComfortPerHour` (5 réconforts par heure de jeu ; 0
désactive une valeur).

**Living Knox** : `Enabled` (groupes de survivants), `Debug`, `GroupCount` (3 à 5, **à régler avant de créer le monde**),
proportions colons / pillards / neutres, taille des groupes, délai de relève d'un groupe décimé, `RaidsEnabled` et
`RaidDays` (raids des pillards), `RevengeDelayHours`, et les distances d'alerte, de fuite, de défense et de sommation.

Liste complète avec les valeurs par défaut : [docs/wiki/Sandbox-Options-FR.md](docs/wiki/Sandbox-Options-FR.md).

### Caractère des voix

Chaque voix a une fiche texte dans `<dossier d'échange>/personas/<voix>.txt` (fréquences, horaires, radio exigée,
actions permises, ce qu'elle sait, ignore ou cache, et son prompt après `[prompt]`). Le serveur l'installe au premier
chargement du monde et la relit toutes les 30 s : la modifier change la voix sans redémarrer. Une fiche modifiée par
l'admin n'est jamais écrasée par une mise à jour du mod. Guide : [docs/wiki/Creating-Radio-Voices-FR.md](docs/wiki/Creating-Radio-Voices-FR.md).

## Jouer

1. **Trouver une fréquence** : fouillez, lisez les notes (« Inspecter »).
2. **Parler à une voix** : talkie allumé **en main ou sur le dos** (jamais depuis la ceinture), micro ouvert, réglé sur
   la fréquence ; dans la fenêtre de la radio, section **Émettre** : tapez votre phrase, Entrée. La radio de
   radioamateur posée (à moins de 5 cases) et l'autoradio émettrice d'un véhicule marchent aussi.
3. **Rencontrer un groupe** : approchez sans arme pointée, **Ctrl+G** pour sélectionner le PNJ, parlez dans le chat
   local. Faites connaissance avant de demander du travail.
4. **Mission** : acceptez-la dans le carnet (**Missions**), remplissez l'objectif (cercle sur la carte), revenez le
   dire au demandeur, puis **Récupérer le lot commun**.
5. **Carnet** : onglet Radio pour relire les conversations, Contacts pour ce que chaque PNJ pense de vous, Réputation
   pour votre niveau et vos derniers actes.

Admins et mode debug : fenêtre d'administration des groupes, fiche d'un PNJ par clic droit et panneau de debug des PNJ
(panneau debug du jeu en solo, panneau d'admin en multijoueur).

## Dépannage

| Symptôme | Cause probable |
|---|---|
| Toujours « Rien que des parasites… » | Pont arrêté, mauvais dossier d'échange (`--exchange`), clé ou modèle invalide (`--test`), fournisseur trop lent (plus de 60 s par appel). |
| Le pont refuse de démarrer | Un autre pont surveille déjà ce dossier (`bridge.lock`). |
| Aucune voix sur une fréquence | Personne ne la tient cette partie, hors de ses horaires, ou radio pas assez puissante (ondes courtes). |
| `Expired request ignored` | Demande de plus de 75 s : pont lancé en retard ou horloges différentes (pont sur une autre machine). |
| Radio Survivor absent du jeu | Un mod requis manque (Belt Walkie-Talkie, TooltipLib, Signal Smoke) ou n'est pas dans `WorkshopItems=`. |

Journaux : sortie du pont (`bridge.log` si redirigée), `token_usage.jsonl`, `%USERPROFILE%\Zomboid\console.txt` (solo),
`server-console.txt` du serveur. Plus de cas : [docs/wiki/Troubleshooting-FR.md](docs/wiki/Troubleshooting-FR.md).

## État du projet

Version de test, non publiée sur le Workshop.

- Toutes les fonctions de la radio, du carnet et de Living Knox sont vérifiées **en jeu solo** par des campagnes de
  tests automatiques (vrai jeu 42.21 piloté par script), et une grande partie l'est aussi **en multijoueur** (serveur
  dédié et deux clients pilotés). État détaillé et journal de développement :
  [docs/fonctionnalites.html](docs/fonctionnalites.html) ; plan : [docs/plan/SUIVI.md](docs/plan/SUIVI.md).
- Les tests tournent dans une partie de test calme ; une longue partie avec la densité de zombies normale reste à
  éprouver.
- Limites connues : offensive des PNJ par une fenêtre encore irrégulière en multijoueur ; pêche des PNJ non vérifiée ;
  les voix ne donnent que des missions de reconnaissance ; texte au-delà du Latin-1 (« ’ », « € ») mal transmis.

## Développement

```text
Contents/mods/batman_RadioSurvivor/42.21/   le mod (Lua client, server, shared ; personas ; traductions EN/FR)
bridge/                                     le pont Python
dev/batman_RadioSurvivorTests/              mod de tests en jeu (RST), jamais publié
tests/                                      bancs hors jeu (lupa, VM Kahlua)
tools/                                      plan, campagnes en jeu (autoclient), zip de test
docs/                                       conception, protocole, plan, wiki, guides
workshop/                                   descriptions Workshop (EN, FR)
```

- Tous les tests hors jeu : `python tests/run_all.py` (nécessite `lupa` ; aucun appel d'IA payant).
- Campagnes en jeu automatiques : `tools/autoclient/autoclient.py` (solo, serveur dédié avec deux clients, tranches
  parallèles, faux modèle d'IA) ; méthode : [docs/tests-en-jeu.md](docs/tests-en-jeu.md).
- Contrat Lua ↔ Python : [docs/protocole-carnet-v2.md](docs/protocole-carnet-v2.md) ; API de Living Knox :
  [docs/api.md](docs/api.md) ; conception : [docs/conception/README.md](docs/conception/README.md).
- Zip de test local sans le Workshop : `python tools/make_test_zip.py` (écrit `dist/`).
- Pages wiki prêtes à publier : [docs/wiki/](docs/wiki/Home-FR.md).
- Living Knox est écrit indépendamment : aucun code de Bandits! ni de Project A-Life n'est repris.

## Licence

MIT — voir [LICENSE](LICENSE).
