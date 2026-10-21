# Installer le pont de Radio Survivor sur un serveur

Guide pour l'administrateur d'un serveur Project Zomboid 42.21 (dédié ou hébergé depuis le jeu, Windows ou Linux).
English version: [07-bridge-server-setup.md](../en/07-bridge-server-setup.md).

Les voix radio (Walt et les autres) et les dialogues du carnet sont écrits par un modèle de langage (LLM). Le jeu ne
peut pas l'appeler lui-même : le Lua de Project Zomboid n'a aucun accès réseau. Un petit programme Python, **le
pont** (`bridge/radio_bridge.py`), fait l'intermédiaire. Le serveur du jeu et le pont s'échangent deux fichiers texte
dans un dossier commun ; le pont appelle l'API du LLM.

```
joueur → serveur PZ → requests.txt → pont → API du LLM
joueur ← serveur PZ ← responses.txt ← pont
```

## 1. Pourquoi le Workshop ne suffit pas

Le Workshop installe les fichiers du mod chez le serveur et chez chaque joueur, mais un mod ne peut ni fournir ni
lancer un programme : le pont s'installe et se lance **à la main, sur la machine qui exécute le serveur**.

- **Serveur dédié** : sur la machine (ou le conteneur voisin) du serveur.
- **Partie hébergée depuis le jeu** (« Héberger ») : sur le PC de l'hôte. Le serveur lancé par le jeu utilise le même
  dossier `Zomboid` que le jeu de l'hôte.
- **Solo** : sur le PC du joueur.
- Les **joueurs** qui se connectent n'ont **rien** à installer à part le mod.

Sans pont, le mod fonctionne : les voix ne répondent que par des parasites, le bulletin du soir et les dernières pages
passent à de courts textes de secours écrits par le serveur, et les PNJ du carnet restent muets.

Le pont tient en cinq fichiers : `radio_bridge.py` (le programme), `npc_protocol.py` (dialogues du carnet),
`persona_store.py` (fiches des voix), `bulletin.py` (bulletin du soir) et `last_pages.py` (dernières pages). Copiez-les
ensemble dans un même dossier, avec `.env.example`, à la même version que le mod installé sur le serveur : un pont plus
ancien que le mod ne comprend pas toutes les demandes, et un fichier manquant l'empêche de démarrer
(`ModuleNotFoundError`). Mettez-le à jour à chaque mise à jour du mod.

## 2. Prérequis

- **Python 3.10 ou plus récent** (3.12 recommandé), sur Windows ou Linux. Vérifier avec `python --version` (Windows) ou
  `python3 --version` (Linux).
- **Aucun paquet à installer** : le pont n'utilise que la bibliothèque standard de Python (pas de `pip install`).
- Un accès Internet sortant vers le fournisseur du LLM (HTTPS), sauf en mode `--offline`.
- Une **clé d'API** d'un fournisseur compatible avec l'API OpenAI (`/chat/completions`), sauf en mode `--offline`.
- Le compte système qui lance le pont doit pouvoir lire et écrire dans le dossier d'échange (section 3).

## 3. Le dossier d'échange

Le serveur écrit dans `<dossier Zomboid du serveur>/Lua/batman_RadioSurvivor/`. Le pont doit surveiller **exactement
ce dossier**.

| Cas | Dossier `Zomboid` du serveur | Dossier d'échange |
|---|---|---|
| Windows, sans `-cachedir` | `%USERPROFILE%\Zomboid` | `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` |
| Linux, sans `-cachedir` | `/home/<compte>/Zomboid` (`~/Zomboid`) | `~/Zomboid/Lua/batman_RadioSurvivor` |
| Serveur lancé avec `-cachedir=X` | `X` | `X/Lua/batman_RadioSurvivor` |
| Partie hébergée depuis le jeu | celui du jeu de l'hôte | comme ci-dessus pour le compte de l'hôte |

`<compte>` est le compte système **qui lance le serveur**, pas forcément le vôtre.

- Sans option, le pont prend `~/Zomboid/Lua/batman_RadioSurvivor` **du compte qui lance le pont**. Si le serveur
  tourne sous un autre compte ou avec `-cachedir`, passez le chemin par `--exchange`.
- Le pont crée le dossier s'il n'existe pas : une faute de frappe ne donne aucune erreur, le pont attend dans un
  dossier vide. Pour vérifier le chemin : après le premier chargement du monde par le serveur, le dossier contient un
  sous-dossier `personas` avec les fiches des voix (`walt.txt`…). S'il n'y est pas, ce n'est pas le bon dossier.
- **Deux serveurs lancés par le même compte sans `-cachedir` partagent le même dossier `Zomboid/Lua`**, donc le même
  dossier d'échange : ils s'écraseraient leurs demandes. Donnez à chaque serveur son propre `-cachedir`, puis un pont
  par serveur.

## 4. La clé d'API

Le pont lit trois réglages : `OPENAI_KEY` (la clé), `OPENAI_BASE_URL` (adresse de l'API, par exemple
`https://api.openai.com/v1` ; le pont y ajoute `/chat/completions`) et `OPENAI_MODEL` (nom du modèle chez ce
fournisseur). Les trois sont obligatoires hors `--offline`.

Ils viennent des **variables d'environnement**, sinon d'un **fichier `.env`** désigné par `--env` ; une variable
d'environnement l'emporte sur le fichier. Format du fichier, une ligne par réglage (`#` pour un commentaire,
`export ` accepté) :

```
OPENAI_KEY=<votre clé>
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=<nom du modèle>
```

Règles :

- Sans `--env`, le pont lit le `.env` placé à côté de `radio_bridge.py` (copiez `.env.example` en `.env` puis
  remplissez-le ; ce fichier est ignoré par Git). Sur un serveur, préférez `--env` vers un fichier hors du dossier du pont.
- Placez le fichier **hors de tout dépôt Git** et hors du dossier d'échange, du dossier du jeu et des dossiers du
  mod. Restreignez sa lecture au compte du pont (Linux : `chmod 600`, propriétaire = compte du pont ; Windows :
  dossier de ce compte seulement).
- **Ne l'affichez jamais**, ne le collez pas dans un ticket ni sur Discord. Le pont n'affiche jamais la clé : son
  bandeau de démarrage indique seulement `API key: configured (hidden)`.
- En cas de fuite, révoquez la clé chez le fournisseur et créez-en une autre.

## 5. Coût et budget

Chaque message accepté par le serveur coûte **un appel au LLM** (jusqu'à deux, trois pour une voix qui peut agir,
quand le fournisseur refuse un paramètre ou rend une réponse vide). Le pont n'estime aucun prix : il enregistre la
consommation.

**Limites côté jeu** (options sandbox, page « Radio Survivor ») :

| Option | Défaut | Effet sur le coût |
|---|---|---|
| `MaxPerHour` | 60 | Messages radio par heure réelle, **tous joueurs confondus**. `0` = **illimité** : à éviter sur un serveur public. |
| `PlayerCooldown` | 10 s | Délai réel entre deux messages d'un même joueur. |
| `SpontaneousCalls` | oui | Appels généraux des voix ; ils comptent dans `MaxPerHour`. |
| `Enabled` | oui | Coupe toutes les voix. |

S'y ajoutent, sans option sandbox :

- 8 demandes radio en attente au plus ; au-delà, ou plafond atteint, le joueur lit « Trop de monde sur la fréquence,
  réessayez plus tard. ». Une phrase sur une fréquence sans voix ne coûte rien.
- Un budget par voix possible dans sa fiche (`budget=` dans `<dossier d'échange>/personas/<voix>.txt`, demandes par
  heure réelle, `0` = seul `MaxPerHour`).
- Une demande de consigne de mission juste après l'attribution d'une mission par une voix, hors plafond horaire.
- Les dialogues du carnet avec les PNJ (seulement si un moteur de PNJ est actif) : plafond fixe de 60 dialogues et
  12 biographies par heure réelle (`RS_Config.lua`).

**Mesurer** : chaque appel est ajouté à `<dossier d'échange>/token_usage.jsonl` (ou au fichier de `--usage-log`) :
date UTC, modèle, tokens d'entrée, de sortie et total, cumuls de la session du pont. Un compteur absent vaut `null`
(inconnu, pas zéro). Multipliez par le tarif de votre fournisseur.

**Recommandé** : fixez aussi une limite de dépense mensuelle **chez le fournisseur** de la clé ; c'est la seule
limite qui tient même si une option est mal réglée.

## 6. Lancer le pont

Exemples de commande (adaptez les chemins) :

```powershell
# Windows
python C:\RadioSurvivorBridge\radio_bridge.py --env C:\RadioSurvivorBridge-secret\bridge.env --exchange "D:\PZServer\cache\Lua\batman_RadioSurvivor"
```

```sh
# Linux
python3 /opt/radiosurvivor-bridge/radio_bridge.py --env /etc/radiosurvivor/bridge.env --exchange /srv/pz/cache/Lua/batman_RadioSurvivor
```

Au démarrage, le pont affiche un bandeau : mode, modèle, adresse de l'API (sans identifiants), `API key: configured
(hidden)`, fichier `.env`, `Exchange directory: …`, journal des tokens, dossier des fiches, puis l'intervalle de lecture, le nombre d'appels simultanés (4),
l'âge maximal d'une demande (75 s) et le budget d'un appel au LLM (60 s). Puis `Bridge ready, model …, directory …`
et `Waiting for game requests (Ctrl+C to stop)`. Laissez-le tourner tant que le serveur tourne ; l'ordre de démarrage
(serveur ou pont d'abord) est indifférent.

### Délais et battement de vie

- **Battement de vie** : tant qu'il tourne, le pont réécrit toutes les 5 s le fichier `bridge-alive.txt` du dossier
  d'échange (`alive=<heure en millisecondes>`) et le supprime à l'arrêt. Le serveur le relit : un battement de moins de
  20 s signifie « pont vivant ».
- **Pont vivant** : le serveur attend chaque réponse jusqu'à 150 s. Le pont, lui, démarre une demande au plus 75 s
  après son envoi et borne l'appel au LLM à 60 s, tentatives comprises : toute réponse, erreur comprise, est écrite
  avant 135 s.
- **Pont absent ou arrêté** (pas de battement) : les secours partent après le délai court de chaque demande, par
  exemple 90 s pour la radio (« Rien que des parasites… »).
- Une demande plus vieille que 75 s quand le pont la prend (file pleine, pont lancé trop tard, serveur redémarré) est
  abandonnée avec `Expired request ignored` ; c'est normal après une panne. Le battement et l'âge des demandes
  utilisent l'horloge de la machine : serveur et pont doivent tourner sur la même machine (ou des horloges
  synchronisées).

### Journal du pont

Le pont écrit son journal dans le terminal seulement (aucun fichier). Pour le garder, redirigez la sortie, par exemple
`python radio_bridge.py > bridge.log 2>&1` ; sous systemd, `journalctl` le conserve. Lignes utiles : le bandeau
(`Exchange directory`, `Model`), `Bridge ready`, `<appelant> -> <voix ou PNJ> : <phrase>` pour chaque demande, et les
`LLM error (…)` (section 9).

Options vérifiées dans `radio_bridge.py` :

| Option | Rôle |
|---|---|
| `--exchange CHEMIN` | Dossier d'échange (section 3). Défaut : `~/Zomboid/Lua/batman_RadioSurvivor` du compte du pont. |
| `--env CHEMIN` | Fichier des réglages (section 4). Ignoré avec `--offline`. |
| `--offline` | Aucun appel au LLM, aucune clé lue, aucun coût : la voix répond en écho (« Walt, hors ligne. Je reçois … »). |
| `--debug` | Journal complet dans le terminal (voir ci-dessous). |
| `--usage-log CHEMIN` | Autre fichier pour le journal des tokens. Défaut : `<exchange>/token_usage.jsonl`. |
| `--poll SECONDES` | Intervalle de lecture de `requests.txt` (défaut 0,3 s, minimum 0,02 s). |
| `--test "TEXTE"` | Un échange en console, sans le jeu (section 8). |
| `--voice ID` | Voix utilisée par `--test` (défaut `walt`). |
| `--personas CHEMIN` | Dossier des fiches lu par `--test`. Défaut : `../Contents/mods/batman_RadioSurvivor/42.21/personas` relatif au pont (dépôt de développement) ; ailleurs, donner `<dossier d'échange>/personas` (rempli au premier chargement du monde) ou le dossier `42.21/personas` du mod installé. |
| `--help` | Aide complète. |

### Mode `--offline`

Pour vérifier l'installation sans clé ni dépense : la voix répète la phrase reçue. Le serveur, les fichiers d'échange
et l'antenne fonctionnent comme en vrai. Ce mode ne lit pas le fichier `.env`.

### Mode `--debug`

Affiche dans le terminal chaque demande et chaque acquittement lus dans `requests.txt` (champs décodés), les messages
complets envoyés au LLM, la réponse brute de l'API, les réponses écrites dans `responses.txt` et les durées. La clé et
les en-têtes HTTP ne sont jamais affichés, mais **ce journal contient les prompts et les dialogues des joueurs** : ne
le partagez pas tel quel. À utiliser pour un diagnostic, pas en continu.

### Un seul pont par dossier

Un second pont sur le même dossier refuse de démarrer (`Another bridge is already running on …`), grâce au verrou
`bridge.lock` du dossier. Deux ponts répondraient deux fois à chaque message : coût doublé, historique en double,
réponses qui s'écrasent. Le verrou est libéré par le système à l'arrêt du pont, même après un plantage ; le fichier
`bridge.lock` lui-même reste et ne doit pas être supprimé à la main pendant que le pont tourne.

## 7. Démarrage automatique

Le pont doit tourner **sous le compte qui a les droits sur le dossier d'échange**, avec les mêmes options qu'en
lancement manuel. Testez toujours d'abord à la main.

### Windows : Planificateur de tâches

Dans une invite de commandes **administrateur** (une seule ligne) :

```bat
schtasks /Create /TN "RadioSurvivor bridge" /SC ONSTART /RU <compte> /RP * /TR "\"C:\Program Files\Python312\python.exe\" C:\RadioSurvivorBridge\radio_bridge.py --env C:\RadioSurvivorBridge-secret\bridge.env --exchange D:\PZServer\cache\Lua\batman_RadioSurvivor"
```

`/RP *` demande le mot de passe du compte. Dans les propriétés de la tâche, décochez « Arrêter la tâche si elle
s'exécute plus de 3 jours » et, dans « Paramètres », activez le redémarrage en cas d'échec. Le terminal n'est pas
visible : pour suivre le pont, regardez `token_usage.jsonl` et les fichiers d'échange, ou lancez-le à la main.

Partie hébergée depuis le jeu : lancez simplement le pont à la main avant ou après « Héberger » ; la fenêtre reste
ouverte pendant la partie.

### Linux : service systemd

Fichier `/etc/systemd/system/radiosurvivor-bridge.service` :

```ini
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

Puis `sudo systemctl daemon-reload`, `sudo systemctl enable --now radiosurvivor-bridge`, et le journal par
`journalctl -u radiosurvivor-bridge -f`. `KillSignal=SIGINT` arrête le pont comme Ctrl+C (`Bridge stopped`).

### Docker

Si le serveur tourne dans un conteneur, le plus simple est de lancer le pont sur l'hôte, ou dans un second conteneur
Python, en montant **le même volume** que les données du serveur :

```sh
docker run -d --name rs-bridge --restart unless-stopped \
  --user <uid>:<gid> \
  -v <volume ou dossier des données Zomboid du serveur>:/zomboid \
  -v /opt/radiosurvivor-bridge:/bridge:ro \
  -v /etc/radiosurvivor/bridge.env:/run/bridge.env:ro \
  python:3.12-slim \
  python /bridge/radio_bridge.py --env /run/bridge.env --exchange /zomboid/Lua/batman_RadioSurvivor
```

- Le chemin du dossier `Zomboid` dans le conteneur du serveur dépend de l'image utilisée (lisez sa documentation ou
  cherchez le dossier `Lua` dans le volume).
- `--user` : l'identifiant du compte propriétaire des fichiers du serveur, pour que les deux processus puissent lire
  et écrire les fichiers de l'autre.
- Ne lancez qu'**un** conteneur de pont par serveur.
- Les deux conteneurs partagent l'horloge de l'hôte : l'âge des demandes et le battement `bridge-alive.txt` (section 6) ne sont pas affectés.

## 8. Vérifier que tout marche

1. **Le pont seul, sans le jeu** : `python radio_bridge.py --env <fichier> --exchange <dossier> --test "Allô ?"
   --personas <dossier d'échange>/personas`. Une ou plusieurs lignes de Walt s'affichent : clé, adresse et modèle sont
   bons. Ajoutez `--offline` pour tester sans clé. (Sans `--personas`, `--test` cherche les fiches dans le dépôt de
   développement du mod, absent d'un serveur.) Ce test ajoute un historique dans `<dossier d'échange>/console-test`,
   sans effet sur les parties.
2. **Le dossier** : après le chargement du monde par le serveur, `<dossier d'échange>/personas/` contient les fiches
   des voix. Le bandeau du pont affiche ce même dossier (`Exchange directory`).
3. **En jeu** : réglez un talkie, tenu en main, allumé et micro ouvert, sur la fréquence d'une voix (les fréquences
   sont tirées à chaque partie ; l'admin les lit dans le journal du serveur au premier chargement de la partie, ligne
   `[RadioSurvivor] personas: voice '<id>' drew … MHz`), et
   parlez dans la section **Émettre** de la fenêtre de la radio.
   - le serveur crée ou réécrit `requests.txt` ;
   - le terminal du pont affiche `<appelant> -> walt : <phrase>` ;
   - le pont écrit `responses.txt` et la réponse passe à l'antenne quelques secondes plus tard ;
   - `token_usage.jsonl` reçoit une ligne (sauf `--offline`).
4. **Option, pour les testeurs du mod** : avec le mod de développement `batman_RadioSurvivorTests` et le jeu en mode
   `-debug` (il n'est pas publié), `RST.server("rs.voices")` vérifie les fiches installées et
   `RST.server({ suite = "rs.personas", tags = { "world", "server" } })` leur installation et leur relecture dans le
   dossier d'échange (voir [tests-en-jeu.md](../../annexes/tests/tests-en-jeu.md)).

## 9. Dépannage

| Message | Où | Cause probable et remède |
|---|---|---|
| « Rien que des parasites… » après environ 90 s, et `[RadioSurvivor] no answer from the bridge for <id> (is bridge\radio_bridge.py running?)` | joueur ; journal du serveur | Pont arrêté, ou lancé sur un **autre dossier** que celui du serveur (section 3) : le serveur n'y lit aucun `bridge-alive.txt` récent. Vérifier `Exchange directory` dans le bandeau du pont et la présence de `bridge-alive.txt` dans le dossier d'échange du serveur. |
| « Rien que des parasites… » après environ 150 s, pont en marche | joueur | Le LLM n'a pas répondu dans son budget de 60 s, ou la demande a attendu plus de 75 s (file saturée) : voir `LLM error` ou `Expired request ignored` dans le terminal du pont. |
| « Rien que des parasites… » immédiatement | joueur | Le serveur n'a pas pu écrire `requests.txt` (droits du dossier `Zomboid/Lua`, disque plein). |
| « Bridge absent, réponse invalide ou périmée. Aucune décision appliquée. » (EN : « Bridge missing, invalid or expired reply… »), et `[RS_Carnet] npc_talk <id> refused: …` | carnet ; journal du serveur | Même chose pour un dialogue avec un PNJ : pont absent (`no reply after 150000 ms`), erreur du fournisseur nommée (`bridge error timeout`, `bridge error http_503`, `unreachable`, `bad_response`), réponse du LLM inutilisable (`bridge error invalid_or_unavailable`) ou demande trop vieille (`bridge error expired`). |
| « Impossible de transmettre au bridge. » | carnet | Écriture de `requests.txt` impossible, comme ci-dessus. |
| « Trop de monde sur la fréquence, réessayez plus tard. » | joueur | `MaxPerHour` atteint ou 8 demandes en attente. Normal en cas d'affluence ; sinon augmenter `MaxPerHour`. |
| `Missing configuration: OPENAI_KEY, … (file … or environment variables)` | pont | Réglage absent : chemin `--env` faux ou variable vide (section 4). |
| `Another bridge is already running on …` | pont | Un pont tourne déjà sur ce dossier (tâche planifiée, service, autre terminal). L'arrêter, ou garder celui-là. |
| `LLM error (<id>): no valid sheet for voice 'walt' in …/personas` | pont | Mauvais dossier d'échange, ou monde pas encore chargé par le serveur : les fiches n'y sont pas. |
| `LLM error (<id>): HTTP 401 …` / `HTTP 403` | pont | Clé refusée ou révoquée. |
| `LLM error (<id>): HTTP 404 …` | pont | Nom de modèle ou adresse `OPENAI_BASE_URL` incorrects. |
| `LLM error (<id>): HTTP 429 …` | pont | Quota ou limite de débit du fournisseur atteints. |
| `LLM error (<id>): URLError …` / `TimeoutError` | pont | Pas d'accès réseau vers l'API, pare-feu, proxy, ou réponse de plus de 60 s. |
| `Expired request ignored (<id>, <n>s)` | pont | Demande de plus de 75 s quand le pont la prend (pont lancé après coup, serveur redémarré) : normal. Fréquent sans raison : file saturée (beaucoup de joueurs, LLM lent) ou horloges différentes entre serveur et pont (machines distinctes), à éviter. |
| `reply of voice '<id>' withheld: it quotes one of its secrets` | pont | Normal : la voix allait révéler un secret de sa fiche, remplacé par des parasites. |
| `Token usage journal write failed: …` | pont | Fichier de `--usage-log` non inscriptible ; le pont continue. |

Pour un diagnostic plus fin, relancez le pont à la main avec `--debug` (journal complet, à ne pas partager tel quel).
