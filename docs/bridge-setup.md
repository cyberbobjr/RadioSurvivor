# Setting up the Radio Survivor bridge on a server

Guide for the administrator of a Project Zomboid 42.21 server (dedicated or hosted from the game, Windows or Linux).
Version française : [installation-pont.md](installation-pont.md).

The radio voices (Walt and the others) and the notebook dialogues are written by a language model (LLM). The game
cannot call it itself: Project Zomboid's Lua has no network access. A small Python program, **the bridge**
(`bridge/radio_bridge.py`), sits in between. The game server and the bridge exchange two text files in a shared
folder; the bridge calls the LLM API.

```
player → PZ server → requests.txt → bridge → LLM API
player ← PZ server ← responses.txt ← bridge
```

## 1. Why the Workshop is not enough

The Workshop installs the mod files on the server and on every player's machine, but a mod can neither ship nor start
a program: the bridge is installed and started **by hand, on the machine that runs the server**.

- **Dedicated server**: on the server's machine (or a container next to it).
- **Game hosted from the game menu** ("Host"): on the host's PC. The server started by the game uses the same
  `Zomboid` folder as the host's game.
- **Single player**: on the player's PC.
- **Players** who join have **nothing** to install besides the mod.

Without the bridge, the mod still works: the voices only answer with static, the evening bulletin and the last pages
fall back to short texts written by the server, and the notebook NPCs stay silent.

The bridge is five files: `radio_bridge.py` (the program), `npc_protocol.py` (notebook dialogues), `persona_store.py`
(voice sheets), `bulletin.py` (evening bulletin) and `last_pages.py` (last pages). Copy them together into one folder,
with `.env.example`, at the same version as the mod installed on the server: a bridge older than the mod does not
understand every request, and a missing file stops it from starting (`ModuleNotFoundError`). Update it with every mod
update.

## 2. Requirements

- **Python 3.10 or newer** (3.12 recommended), on Windows or Linux. Check with `python --version` (Windows) or
  `python3 --version` (Linux).
- **No package to install**: the bridge only uses the Python standard library (no `pip install`).
- Outgoing Internet access (HTTPS) to the LLM provider, except in `--offline` mode.
- An **API key** from a provider compatible with the OpenAI API (`/chat/completions`), except in `--offline` mode.
- The system account that runs the bridge must be able to read and write the exchange folder (section 3).

## 3. The exchange folder

The server writes into `<server Zomboid folder>/Lua/batman_RadioSurvivor/`. The bridge must watch **exactly that
folder**.

| Case | Server `Zomboid` folder | Exchange folder |
|---|---|---|
| Windows, no `-cachedir` | `%USERPROFILE%\Zomboid` | `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` |
| Linux, no `-cachedir` | `/home/<account>/Zomboid` (`~/Zomboid`) | `~/Zomboid/Lua/batman_RadioSurvivor` |
| Server started with `-cachedir=X` | `X` | `X/Lua/batman_RadioSurvivor` |
| Game hosted from the game menu | the host's game folder | as above, for the host's account |

`<account>` is the system account **that runs the server**, not necessarily yours.

- Without options, the bridge uses `~/Zomboid/Lua/batman_RadioSurvivor` **of the account that runs the bridge**. If the
  server runs under another account or with `-cachedir`, pass the path with `--exchange`.
- The bridge creates the folder if it does not exist: a typo gives no error, the bridge just waits in an empty folder.
  To check the path: once the server has loaded the world, the folder holds a `personas` subfolder with the voice
  sheets (`walt.txt`…). If it is not there, it is the wrong folder.
- **Two servers started by the same account without `-cachedir` share the same `Zomboid/Lua` folder**, hence the same
  exchange folder: they would overwrite each other's requests. Give each server its own `-cachedir`, then run one
  bridge per server.

## 4. The API key

The bridge reads three settings: `OPENAI_KEY` (the key), `OPENAI_BASE_URL` (API address, for example
`https://api.openai.com/v1`; the bridge appends `/chat/completions`) and `OPENAI_MODEL` (model name at that provider).
All three are required unless `--offline`.

They come from **environment variables**, otherwise from a **`.env` file** given by `--env`; an environment variable
wins over the file. File format, one setting per line (`#` for a comment, `export ` accepted):

```
OPENAI_KEY=<your key>
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=<model name>
```

Rules:

- Without `--env`, the bridge reads the `.env` next to `radio_bridge.py` (copy `.env.example` to `.env` and fill it
  in; this file is ignored by Git). On a server, prefer passing `--env` to a file outside the bridge folder.
- Keep the file **outside any Git repository** and outside the exchange folder, the game folder and the mod folders.
  Restrict reading to the bridge account (Linux: `chmod 600`, owned by the bridge account; Windows: a folder of that
  account only).
- **Never display it**, never paste it into a ticket or on Discord. The bridge never displays the key: its startup
  banner only says `API key: configured (hidden)`.
- If it leaks, revoke the key at the provider and create a new one.

## 5. Cost and budget

Each message accepted by the server costs **one LLM call** (up to two, three for a voice that can act, when the
provider refuses a parameter or returns an empty reply). The bridge estimates no price: it records usage.

**Game-side limits** (sandbox options, "Radio Survivor" page):

| Option | Default | Effect on cost |
|---|---|---|
| `MaxPerHour` | 60 | Radio messages per real hour, **all players together**. `0` = **unlimited**: avoid on a public server. |
| `PlayerCooldown` | 10 s | Real delay between two messages of the same player. |
| `SpontaneousCalls` | yes | General calls of the voices; they count in `MaxPerHour`. |
| `Enabled` | yes | Turns all voices off. |

Also, with no sandbox option:

- At most 8 pending radio requests; beyond that, or when the cap is reached, the player reads "Too much chatter on the
  frequency, try again later." A sentence on a frequency without a voice costs nothing.
- An optional per-voice budget in its sheet (`budget=` in `<exchange folder>/personas/<voice>.txt`, requests per real
  hour, `0` = `MaxPerHour` only).
- One mission briefing request right after a voice gives a mission, outside the hourly cap.
- Notebook dialogues with NPCs (only when an NPC engine is active): fixed cap of 60 dialogues and 12 biographies per
  real hour (`RS_Config.lua`).

**Measure**: every call is appended to `<exchange folder>/token_usage.jsonl` (or the `--usage-log` file): UTC date,
model, input, output and total tokens, totals of the bridge session. A missing counter is `null` (unknown, not zero).
Multiply by your provider's price.

**Recommended**: also set a monthly spending limit **at the key's provider**; it is the only limit that holds even if
an option is set wrong.

## 6. Starting the bridge

Example commands (adapt the paths):

```powershell
# Windows
python C:\RadioSurvivorBridge\radio_bridge.py --env C:\RadioSurvivorBridge-secret\bridge.env --exchange "D:\PZServer\cache\Lua\batman_RadioSurvivor"
```

```sh
# Linux
python3 /opt/radiosurvivor-bridge/radio_bridge.py --env /etc/radiosurvivor/bridge.env --exchange /srv/pz/cache/Lua/batman_RadioSurvivor
```

At startup the bridge prints a banner: mode, model, API address (without credentials), `API key: configured
(hidden)`, `.env` file, `Exchange directory: …`, token journal, sheets folder, then the poll interval, the number of simultaneous calls (4),
the maximum age of a request (75 s) and the budget of one LLM call (60 s). Then `Bridge ready, model …, directory …`
and `Waiting for game requests (Ctrl+C to stop)`. Keep it running while the server runs; the start order (server or
bridge first) does not matter.

### Delays and heartbeat

- **Heartbeat**: while it runs, the bridge rewrites the `bridge-alive.txt` file of the exchange folder every 5 s
  (`alive=<time in milliseconds>`) and deletes it when it stops. The server reads it: a heartbeat younger than 20 s
  means "bridge alive".
- **Bridge alive**: the server waits up to 150 s for each answer. The bridge starts a request at most 75 s after it
  was sent and limits the LLM call to 60 s, all attempts together: every answer, error included, is written within
  135 s.
- **Bridge missing or stopped** (no heartbeat): the fallbacks start after the short delay of each request, for
  example 90 s for the radio ("Only static...").
- A request older than 75 s when the bridge takes it (queue full, bridge started too late, server restarted) is
  dropped with `Expired request ignored`; this is normal after an outage. The heartbeat and the request age use the
  machine clock: run the server and the bridge on the same machine (or with synchronised clocks).

### Bridge log

The bridge writes its log to the terminal only (no file). To keep it, redirect the output, for example
`python radio_bridge.py > bridge.log 2>&1`; under systemd, `journalctl` keeps it. Useful lines: the banner
(`Exchange directory`, `Model`), `Bridge ready`, `<caller> -> <voice or NPC> : <sentence>` for each request, and the
`LLM error (…)` lines (section 9).

Options checked in `radio_bridge.py`:

| Option | Role |
|---|---|
| `--exchange PATH` | Exchange folder (section 3). Default: `~/Zomboid/Lua/batman_RadioSurvivor` of the bridge account. |
| `--env PATH` | Settings file (section 4). Ignored with `--offline`. |
| `--offline` | No LLM call, no key read, no cost: the voice echoes the sentence (in French: "Walt, hors ligne. Je reçois …"). |
| `--debug` | Full log in the terminal (see below). |
| `--usage-log PATH` | Other file for the token journal. Default: `<exchange>/token_usage.jsonl`. |
| `--poll SECONDS` | How often `requests.txt` is read (default 0.3 s, minimum 0.02 s). |
| `--test "TEXT"` | One exchange in the console, without the game (section 8). |
| `--voice ID` | Voice used by `--test` (default `walt`). |
| `--personas PATH` | Sheets folder read by `--test`. Default: `../Contents/mods/batman_RadioSurvivor/42.21/personas` relative to the bridge (development repository); elsewhere, give `<exchange folder>/personas` (filled at the first world load) or the `42.21/personas` folder of the installed mod. |
| `--help` | Full help. |

### `--offline` mode

To check the setup with no key and no spending: the voice repeats the sentence it received. The server, the exchange
files and the radio broadcast work as in real use. This mode does not read the `.env` file.

### `--debug` mode

Prints in the terminal every request and acknowledgement read from `requests.txt` (fields decoded), the full messages
sent to the LLM, the raw API answer, the replies written to `responses.txt` and the timings. The key and the HTTP
headers are never shown, but **this log contains the prompts and the players' dialogues**: do not share it as is. Use
it for troubleshooting, not permanently.

### One bridge per folder

A second bridge on the same folder refuses to start (`Another bridge is already running on …`), thanks to the folder's
`bridge.lock` lock. Two bridges would answer every message twice: double cost, duplicated history, replies overwriting
each other. The system releases the lock when the bridge stops, even after a crash; the `bridge.lock` file itself stays
and must not be deleted by hand while the bridge runs.

## 7. Automatic start

The bridge must run **under the account that has rights on the exchange folder**, with the same options as a manual
start. Always test by hand first.

### Windows: Task Scheduler

In an **administrator** command prompt (a single line):

```bat
schtasks /Create /TN "RadioSurvivor bridge" /SC ONSTART /RU <account> /RP * /TR "\"C:\Program Files\Python312\python.exe\" C:\RadioSurvivorBridge\radio_bridge.py --env C:\RadioSurvivorBridge-secret\bridge.env --exchange D:\PZServer\cache\Lua\batman_RadioSurvivor"
```

`/RP *` prompts for the account password. In the task properties, untick "Stop the task if it runs longer than
3 days" and, under "Settings", enable restart on failure. The terminal is not visible: to follow the bridge, watch
`token_usage.jsonl` and the exchange files, or start it by hand.

Game hosted from the game menu: simply start the bridge by hand before or after "Host"; keep its window open during
the game.

### Linux: systemd service

File `/etc/systemd/system/radiosurvivor-bridge.service`:

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

Then `sudo systemctl daemon-reload`, `sudo systemctl enable --now radiosurvivor-bridge`, and the log with
`journalctl -u radiosurvivor-bridge -f`. `KillSignal=SIGINT` stops the bridge like Ctrl+C (`Bridge stopped`).

### Docker

If the server runs in a container, the simplest is to run the bridge on the host, or in a second Python container,
mounting **the same volume** as the server data:

```sh
docker run -d --name rs-bridge --restart unless-stopped \
  --user <uid>:<gid> \
  -v <volume or folder of the server's Zomboid data>:/zomboid \
  -v /opt/radiosurvivor-bridge:/bridge:ro \
  -v /etc/radiosurvivor/bridge.env:/run/bridge.env:ro \
  python:3.12-slim \
  python /bridge/radio_bridge.py --env /run/bridge.env --exchange /zomboid/Lua/batman_RadioSurvivor
```

- The path of the `Zomboid` folder inside the server container depends on the image (read its documentation or look
  for the `Lua` folder in the volume).
- `--user`: the id of the account owning the server files, so that both processes can read and write each other's
  files.
- Run only **one** bridge container per server.
- Both containers share the host clock: the request age and the `bridge-alive.txt` heartbeat (section 6) are not affected.

## 8. Checking that everything works

1. **The bridge alone, without the game**: `python radio_bridge.py --env <file> --exchange <folder> --test "Hello?"
   --personas <exchange folder>/personas`. One or more lines from Walt appear: key, address and model are right. Add
   `--offline` to test without a key. (Without `--personas`, `--test` looks for the sheets in the mod's development
   repository, absent from a server.) This test adds a history in `<exchange folder>/console-test`, with no effect on
   games.
2. **The folder**: once the server has loaded the world, `<exchange folder>/personas/` holds the voice sheets. The
   bridge banner shows the same folder (`Exchange directory`).
3. **In game**: set a walkie-talkie, held in hand, switched on with the microphone open, to a voice's frequency (the
   frequencies are drawn for each game; the admin reads them in the server log when the game is first loaded, line
   `[RadioSurvivor] personas: voice '<id>' drew … MHz`), and speak in the **Transmit** section of the radio window.
   - the server creates or rewrites `requests.txt`;
   - the bridge terminal shows `<caller> -> walt : <sentence>`;
   - the bridge writes `responses.txt` and the reply goes on air a few seconds later;
   - `token_usage.jsonl` gets a line (except `--offline`).
4. **Optional, for the mod testers**: with the development mod `batman_RadioSurvivorTests` and the game in `-debug`
   mode (it is not published), `RST.server("rs.voices")` checks the installed sheets and
   `RST.server({ suite = "rs.personas", tags = { "world", "server" } })` their installation and reload in the
   exchange folder (see [tests-en-jeu.md](tests-en-jeu.md), in French).

## 9. Troubleshooting

| Message | Where | Likely cause and fix |
|---|---|---|
| "Only static..." after about 90 s, and `[RadioSurvivor] no answer from the bridge for <id> (is bridge\radio_bridge.py running?)` | player; server log | Bridge stopped, or started on **another folder** than the server's (section 3): the server reads no recent `bridge-alive.txt` there. Check `Exchange directory` in the bridge banner and that `bridge-alive.txt` exists in the server's exchange folder. |
| "Only static..." after about 150 s, bridge running | player | The LLM did not answer within its 60 s budget, or the request waited more than 75 s (queue full): look for `LLM error` or `Expired request ignored` in the bridge terminal. |
| "Only static..." immediately | player | The server could not write `requests.txt` (rights on the `Zomboid/Lua` folder, disk full). |
| "Bridge missing, invalid or expired reply. No decision applied.", and `[RS_Carnet] npc_talk <id> refused: …` | notebook; server log | Same for an NPC dialogue: bridge missing (`no reply after 150000 ms`), provider error named (`bridge error timeout`, `bridge error http_503`, `unreachable`, `bad_response`), unusable LLM output (`bridge error invalid_or_unavailable`) or request too old (`bridge error expired`). |
| "Unable to send to the bridge." | notebook | `requests.txt` cannot be written, as above. |
| "Too much chatter on the frequency, try again later." | player | `MaxPerHour` reached or 8 pending requests. Normal when busy; otherwise raise `MaxPerHour`. |
| `Missing configuration: OPENAI_KEY, … (file … or environment variables)` | bridge | Setting missing: wrong `--env` path or empty variable (section 4). |
| `Another bridge is already running on …` | bridge | A bridge already runs on this folder (scheduled task, service, other terminal). Stop it, or keep that one. |
| `LLM error (<id>): no valid sheet for voice 'walt' in …/personas` | bridge | Wrong exchange folder, or world not yet loaded by the server: the sheets are not there. |
| `LLM error (<id>): HTTP 401 …` / `HTTP 403` | bridge | Key refused or revoked. |
| `LLM error (<id>): HTTP 404 …` | bridge | Wrong model name or `OPENAI_BASE_URL`. |
| `LLM error (<id>): HTTP 429 …` | bridge | Provider quota or rate limit reached. |
| `LLM error (<id>): URLError …` / `TimeoutError` | bridge | No network access to the API, firewall, proxy, or reply slower than 60 s. |
| `Expired request ignored (<id>, <n>s)` | bridge | Request older than 75 s when the bridge takes it (bridge started late, server restarted): normal. Frequent for no reason: queue saturated (many players, slow LLM) or different clocks between server and bridge (separate machines), to avoid. |
| `reply of voice '<id>' withheld: it quotes one of its secrets` | bridge | Normal: the voice was about to reveal a secret of its sheet, replaced by static. |
| `Token usage journal write failed: …` | bridge | `--usage-log` file not writable; the bridge keeps running. |

For finer troubleshooting, restart the bridge by hand with `--debug` (full log, not to be shared as is).
