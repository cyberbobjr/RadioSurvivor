*English: [The bridge on a dedicated server](../en/06-bridge-on-a-dedicated-server.md)*

# Le pont sur un serveur dédié

Sur un serveur dédié, le pont tourne **sur la machine du serveur** (ou dans un conteneur voisin), sous un compte qui
peut lire et écrire le dossier `Zomboid/Lua` du serveur. Les joueurs n'installent que les mods.

Cette page donne le chemin court. Toutes les options, le coût, le journal et les messages d'erreur sont dans le guide
complet : [Installer le pont sur un serveur](07-installation-du-pont.md).

## 1. Configuration du serveur

Dans `<Zomboid>/Server/<nom du serveur>.ini`, ajoutez les quatre objets Workshop et les quatre identifiants de mod :

```ini
WorkshopItems=<ID Workshop de Radio Survivor>;3817018338;3694097672;3811010882
Mods=TooltipLib;batman_BeltRadio;batman_SignalSmoke;batman_RadioSurvivor
```

Gardez vos autres entrées, séparées par `;`. L'ID Workshop de Radio Survivor figure en bas de sa page Workshop.
Retirez Bandits! et Project A-Life s'ils y sont (un seul moteur de PNJ par partie).

## 2. Le dossier d'échange

Le serveur écrit dans `<dossier Zomboid du serveur>/Lua/batman_RadioSurvivor/`. Le pont doit surveiller **exactement
ce dossier**.

| Cas | Dossier d'échange |
|---|---|
| Windows, sans `-cachedir` | `C:\Users\<compte>\Zomboid\Lua\batman_RadioSurvivor` |
| Linux, sans `-cachedir` | `/home/<compte>/Zomboid/Lua/batman_RadioSurvivor` |
| Serveur lancé avec `-cachedir=X` | `X/Lua/batman_RadioSurvivor` |

`<compte>` est le compte **qui lance le serveur**. Sans `--exchange`, le pont prend `~/Zomboid/Lua/batman_RadioSurvivor`
de **son propre** compte : passez `--exchange` dès que le serveur tourne sous un autre compte ou avec `-cachedir`.

- Le pont crée le dossier s'il manque : une faute de frappe ne donne aucune erreur. Vérification : après le premier
  chargement du monde par le serveur, le dossier contient un sous-dossier `personas` (`walt.txt`…) ; tant que le pont
  tourne, il contient aussi `bridge-alive.txt`.
- Deux serveurs lancés par le même compte sans `-cachedir` partagent le même dossier : donnez à chacun son
  `-cachedir` et son pont.
- **Un seul pont par dossier** : un second refuse de démarrer (`Another bridge is already running on …`).

## 3. Installer le pont

1. Python 3.10 ou plus récent (`python3 --version` sous Linux). Aucun paquet à installer.
2. Copiez les cinq fichiers (`radio_bridge.py`, `npc_protocol.py`, `persona_store.py`, `bulletin.py`,
   `last_pages.py`) dans un même dossier, par exemple `C:\RadioSurvivorBridge` ou `/opt/radiosurvivor-bridge`.
   Mettez-les à jour à chaque mise à jour du mod.
3. Placez le fichier de clé **hors** de ce dossier et hors des dossiers du jeu et d'échange, lisible par le seul compte
   du pont (Linux : `chmod 600`). Format : [Configurer le fournisseur d'IA](08-fournisseur-ia.md).
4. Testez d'abord à la main :

```sh
python3 /opt/radiosurvivor-bridge/radio_bridge.py --env /etc/radiosurvivor/bridge.env \
  --exchange /srv/pz/cache/Lua/batman_RadioSurvivor \
  --test "Allô ?" --personas /srv/pz/cache/Lua/batman_RadioSurvivor/personas
```

Puis la même commande sans `--test` ni `--personas`, et attendez `Bridge ready`.

## 4. Le lancer avec le serveur

### Windows : Planificateur de tâches

Dans une invite de commandes administrateur (une seule ligne) :

```bat
schtasks /Create /TN "RadioSurvivor bridge" /SC ONSTART /RU <compte> /RP * /TR "\"C:\Program Files\Python312\python.exe\" C:\RadioSurvivorBridge\radio_bridge.py --env C:\RadioSurvivorBridge-secret\bridge.env --exchange D:\PZServer\cache\Lua\batman_RadioSurvivor"
```

Dans les propriétés de la tâche, décochez « Arrêter la tâche si elle s'exécute plus de 3 jours » et activez le
redémarrage en cas d'échec. Ou lancez-le à la main dans une fenêtre à côté de la console du serveur.

### Linux : systemd

`/etc/systemd/system/radiosurvivor-bridge.service` :

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

`sudo systemctl daemon-reload`, `sudo systemctl enable --now radiosurvivor-bridge`, journal par
`journalctl -u radiosurvivor-bridge -f`.

### Docker

Lancez le pont sur l'hôte ou dans un second conteneur qui monte **le même volume** que les données du serveur :

```sh
docker run -d --name rs-bridge --restart unless-stopped \
  --user <uid>:<gid> \
  -v <volume ou dossier des données Zomboid du serveur>:/zomboid \
  -v /opt/radiosurvivor-bridge:/bridge:ro \
  -v /etc/radiosurvivor/bridge.env:/run/bridge.env:ro \
  python:3.12-slim \
  python /bridge/radio_bridge.py --env /run/bridge.env --exchange /zomboid/Lua/batman_RadioSurvivor
```

`--user` doit être le propriétaire des fichiers du serveur, pour que chaque processus lise et écrive les fichiers de
l'autre. Le chemin du dossier `Zomboid` dans le volume dépend de l'image du serveur (cherchez le dossier `Lua`). Un
seul conteneur de pont par serveur.

## 5. Droits et horloge

- Le compte du pont lit `requests.txt` et `bridge.lock`, et écrit `responses.txt`, `bridge-alive.txt`, les historiques
  et `token_usage.jsonl` dans le dossier d'échange ; le compte du serveur doit pouvoir lire ce que le pont écrit.
- Faites tourner le pont sur la **même machine** (ou le même hôte de conteneurs) que le serveur : l'âge des demandes
  (75 s) et le battement de vie (20 s) se comparent à l'horloge de la machine.

## 6. Notes pour l'admin

- Les fréquences sont tirées à chaque partie ; le journal du serveur affiche
  `[RadioSurvivor] personas: voice '<id>' drew … MHz` au premier chargement.
- Le caractère de chaque voix est dans `<exchange>/personas/<voix>.txt`, relu toutes les 30 s. Une fiche que vous avez
  modifiée n'est jamais écrasée par une mise à jour du mod (avertissement dans le journal).
- Les actions proposées par les voix (acceptées ou refusées, avec la raison) sont écrites dans
  `<exchange>/actions-<partie>.log`.
- Coût : [Configurer le fournisseur d'IA](08-fournisseur-ia.md) et l'option `MaxPerHour`
  ([Options sandbox](09-options-sandbox.md)).
