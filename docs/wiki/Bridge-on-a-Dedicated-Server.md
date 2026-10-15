*Français : [[Le pont sur un serveur dédié|Bridge-on-a-Dedicated-Server-FR]]*

# The bridge on a dedicated server

On a dedicated server, the bridge runs **on the server machine** (or in a container next to it), under an account
that can read and write the server's `Zomboid/Lua` folder. Players install the mods only.

## 1. Server configuration

In `<Zomboid>/Server/<server name>.ini`, add the four Workshop items and the four mod IDs:

```ini
WorkshopItems=<Radio Survivor Workshop ID>;3817018338;3694097672;3811010882
Mods=TooltipLib;batman_BeltRadio;batman_SignalSmoke;batman_RadioSurvivor
```

Keep your other entries; separate them with `;`. The Radio Survivor Workshop ID is shown at the bottom of its
Workshop page. Remove Bandits! and Project A-Life if they are listed (one NPC engine per game).

## 2. The exchange folder

The server writes to `<server Zomboid folder>/Lua/batman_RadioSurvivor/`. The bridge must watch **exactly that
folder**.

| Case | Exchange folder |
|---|---|
| Windows, no `-cachedir` | `C:\Users\<account>\Zomboid\Lua\batman_RadioSurvivor` |
| Linux, no `-cachedir` | `/home/<account>/Zomboid/Lua/batman_RadioSurvivor` |
| Server started with `-cachedir=X` | `X/Lua/batman_RadioSurvivor` |

`<account>` is the account **that runs the server**. Without `--exchange`, the bridge uses
`~/Zomboid/Lua/batman_RadioSurvivor` of **its own** account: pass `--exchange` as soon as the server runs under
another account or with `-cachedir`.

- The bridge creates the folder if it is missing, so a typo gives no error. Check: after the server's first world
  load, the folder holds a `personas` subfolder (`walt.txt`…); while the bridge runs, it also holds `bridge-alive.txt`.
- Two servers started by the same account without `-cachedir` share the same folder: give each one its own
  `-cachedir` and its own bridge.
- **Only one bridge per folder**: a second one refuses to start (`Another bridge is already running on …`).

## 3. Install the bridge

1. Python 3.10 or newer (`python3 --version` on Linux). No package to install.
2. Copy the five files (`radio_bridge.py`, `npc_protocol.py`, `persona_store.py`, `bulletin.py`, `last_pages.py`)
   into one folder, for example `C:\RadioSurvivorBridge` or `/opt/radiosurvivor-bridge`. Update them with every mod
   update.
3. Put the key file **outside** that folder and outside the game and exchange folders, readable by the bridge
   account only (Linux: `chmod 600`). Format: [[AI provider configuration|AI-Provider-Configuration]].
4. Test by hand first:

```sh
python3 /opt/radiosurvivor-bridge/radio_bridge.py --env /etc/radiosurvivor/bridge.env \
  --exchange /srv/pz/cache/Lua/batman_RadioSurvivor \
  --test "Hello?" --personas /srv/pz/cache/Lua/batman_RadioSurvivor/personas
```

Then the same command without `--test` and `--personas`, and wait for `Bridge ready`.

## 4. Start it with the server

### Windows: Task Scheduler

In an administrator command prompt (one line):

```bat
schtasks /Create /TN "RadioSurvivor bridge" /SC ONSTART /RU <account> /RP * /TR "\"C:\Program Files\Python312\python.exe\" C:\RadioSurvivorBridge\radio_bridge.py --env C:\RadioSurvivorBridge-secret\bridge.env --exchange D:\PZServer\cache\Lua\batman_RadioSurvivor"
```

In the task properties, untick "Stop the task if it runs longer than 3 days" and enable restart on failure. Or start
it by hand in a window next to the server console.

### Linux: systemd

`/etc/systemd/system/radiosurvivor-bridge.service`:

```ini
[Unit]
Description=Radio Survivor bridge (Project Zomboid)
After=network-online.target
Wants=network-online.target

[Service]
User=<PZ server account>
ExecStart=/usr/bin/python3 /opt/radiosurvivor-bridge/radio_bridge.py --env /etc/radiosurvivor/bridge.env --exchange /srv/pz/cache/Lua/batman_RadioSurvivor
Restart=on-failure
RestartSec=10
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
```

`sudo systemctl daemon-reload`, `sudo systemctl enable --now radiosurvivor-bridge`, log with
`journalctl -u radiosurvivor-bridge -f`.

### Docker

Run the bridge on the host or in a second container that mounts **the same volume** as the server data:

```sh
docker run -d --name rs-bridge --restart unless-stopped \
  --user <uid>:<gid> \
  -v <server Zomboid data volume or folder>:/zomboid \
  -v /opt/radiosurvivor-bridge:/bridge:ro \
  -v /etc/radiosurvivor/bridge.env:/run/bridge.env:ro \
  python:3.12-slim \
  python /bridge/radio_bridge.py --env /run/bridge.env --exchange /zomboid/Lua/batman_RadioSurvivor
```

`--user` must be the owner of the server files so both processes can read and write each other's files. The path of
the `Zomboid` folder inside the volume depends on the server image (look for the `Lua` folder). One bridge container
per server.

## 5. Rights and clock

- The bridge account reads `requests.txt` and `bridge.lock`, and writes `responses.txt`, `bridge-alive.txt`,
  histories and `token_usage.jsonl` in the exchange folder; the server account must be able to read what the bridge
  writes.
- Run the bridge on the **same machine** (or container host) as the server: the request age (75 s) and the heartbeat
  (20 s) are compared with the machine clock.

## 6. Admin notes

- Frequencies are drawn per game; the server log shows `[RadioSurvivor] personas: voice '<id>' drew … MHz` at the
  first load.
- The character of each voice is in `<exchange>/personas/<voice>.txt`, reread every 30 s. A sheet you edited is
  never overwritten by a mod update (a warning goes to the log).
- Actions proposed by the voices (accepted or refused, with the reason) are written to
  `<exchange>/actions-<game>.log`.
- Cost: [[AI provider configuration|AI-Provider-Configuration]] and the `MaxPerHour` option
  ([[Sandbox options|Sandbox-Options]]).
