# Radio Survivor

[Version française](README_fr.md)

**Voices on the radio and very much alive survivors in Knox County.**
A mod for Project Zomboid **Build 42.21**, singleplayer and multiplayer (dedicated servers included).
Mod ID `batman_RadioSurvivor`, version **0.3.0 (test build)**.

Knox County, July 1993. The Exclusion Zone is sealed off and survivors are on their own. Radio Survivor gives them what
the base game lacks: **voices on the other end of the radio**, played by an artificial intelligence, and **other
flesh-and-blood survivors**, NPC groups living their own lives across the county. A field notebook lets you meet them,
earn their trust and take on their missions.

> **The AI bridge.** The dialogue is written by a large language model (LLM). The game cannot call it by itself: a
> small Python program, **the bridge**, acts as the go-between and must run on the machine that runs the game (your PC
> in singleplayer, the server machine in multiplayer). Without the bridge the game stays playable, but the voices and
> the NPCs go silent. Everything is explained in [The AI bridge](#the-ai-bridge).

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installing the mod](#installing-the-mod)
- [The AI bridge](#the-ai-bridge)
- [Configuration](#configuration)
- [Playing](#playing)
- [Troubleshooting](#troubleshooting)
- [Project status](#project-status)
- [Development](#development)

## Features

### The radio

- **Six voices**, each on its own frequency, rolled at random for every game: Walt, the confidant who made it out of
  the Zone; Darlene, a nurse in West Point; Cody, a National Guard deserter; the Whitakers, a family under siege; the
  Night Owl, a pirate station; Gus, a smuggler on the Ohio. Each one has its own personality, its own hours and the
  radio you need to reach it.
- **You find them by looting**: notes in the loot (diary page, patient chart, missing person notice, flyer…) give this
  game's frequencies. No list is ever sent to the players.
- **You talk to them with any radio that can transmit**: a walkie-talkie in hand or on your back, a placed HAM radio, a
  vehicle radio. A **Transmit** section is added to the game's radio window.
- **They act**, but only the server decides: a marker on your map, a revealed neighborhood, a scouting mission (Darlene,
  Cody), bartering with the smuggler. The AI picks from a closed list, the server checks.
- **Unprompted calls**, the pirate station's **evening bulletin** (server facts, a memorial for the day's dead) and
  **last pages**: when a character dies, a handwritten diary is written and left on the body.
- **Survivors to rescue**: a family calls for help from a real building, with clues; rescued in time they leave a
  stash, otherwise you find the scene.
- **The Ohio smuggler**: barter negotiated over the radio, one crossing per in-game week, a no-contact exchange at night
  on a riverbank.

### The notebook and the NPCs

- **Field notebook** (**Notebook** button on the sidebar): contacts, Radio tab (history per frequency), missions,
  reputation, notes.
- **Talking to an NPC**: walk up to them, press **Ctrl+G** to select them, then speak in local chat (`/say`). They
  answer in speech bubbles and remember you.
- **Missions**: deliver, scout, recover a missing person's papers, clear a location, retrieve a stash, make a signal
  (smoke grenade or flare, Signal Smoke mod). Once the objective is done you must **go back and report it** to whoever
  gave you the mission (or over the radio for a mission given by a voice), then **claim** the reward.
- **Relationships**: every NPC has an opinion of you that changes with real facts (help, theft, a mission succeeded or
  failed), never with mere words. Truces and alliances are negotiated with a group's leader.
- **Reputation** (bad, neutral, good), kept by the server: it rises with successful missions, drops with failures,
  abandoned missions and cheating the smuggler, and collapses if you kill whoever gave you a mission. A bad reputation
  leaves only simple missions, the smuggler charges more and the NPCs talk about it.

### Living Knox, the NPC engine

- **Three to five survivor groups** (settlers, neutrals, raiders), each with a leader, members, a backstory and a home
  set up in a real building, whose stockpile is made of real items.
- **A daily life**: sleep, guard shifts and patrols, chores, meals taken from the stockpile, generator upkeep, looting
  runs, foraging, watering and harvesting the vegetable garden.
- **A defense**: alerts, defending the home from set positions, camps that hold their ground, gradual fortification
  (barricades, walls, palisades) and repairs after an attack.
- **Facing the players**: warnings before any shot, requests for help, trading, revenge after a murder, announced raider
  raids on player bases.
- **Off-screen**: groups keep living far away from the players; a wiped-out group leaves its traces and another one
  settles somewhere else.
- The NPCs are human bodies (clothing, weapons, player gestures) driven by the server, built for multiplayer.

## Requirements

| Item | Where | Note |
|---|---|---|
| Project Zomboid **42.21** | — | Build 41 is not supported. |
| **Belt Walkie-Talkie** (`batman_BeltRadio`) | Workshop 3817018338 | Required mod (walkie-talkie on the belt, shared transmit rule). |
| **TooltipLib** (`TooltipLib`) | Workshop 3694097672 | Required by Belt Walkie-Talkie. |
| **Signal Smoke** (`batman_SignalSmoke`) | Workshop 3811010882 | Required mod (smoke grenades and flares for missions, the smuggler and rescues). |
| **Python 3.10 or newer** | on the machine running the game | For the AI bridge. No package to install. |
| **An AI API key** | from a provider | Compatible with the OpenAI API (see [AI provider](#3-the-key-and-the-ai-provider)). |

**Incompatible** with Bandits! and Project A-Life: only one NPC engine per game (the mod selector flags it).
`batman_CharacterReputation` is optional.

## Installing the mod

### In singleplayer

1. Subscribe to the required mods and to Radio Survivor on the Workshop, **or** copy the mod folders into
   `%USERPROFILE%\Zomboid\mods\` (install without the Workshop, for example from the test zip: see its
   `LISEZMOI.md`).
2. In **Mods**, enable in this order: TooltipLib, Belt Walkie-Talkie, Signal Smoke, Radio Survivor.
3. Fully restart the game after an install or an update.
4. **Start a new game**: the survivor groups settle in when the world is created.
5. Install and start the [AI bridge](#the-ai-bridge).

### On a dedicated server

In `<Zomboid>/Server/<server name>.ini`, add the four Workshop items and the four mod IDs (keeping your other entries,
separated by `;`):

```ini
WorkshopItems=<Radio Survivor Workshop ID>;3817018338;3694097672;3811010882
Mods=TooltipLib;batman_BeltRadio;batman_SignalSmoke;batman_RadioSurvivor
```

Players have nothing else to install besides the mods. The bridge runs **on the server machine**: see
[Bridge on a dedicated server](#bridge-on-a-dedicated-server).

## The AI bridge

### How it works

Project Zomboid's Lua has no network access. So the game (the server in multiplayer, your game in singleplayer) talks
to the bridge through two text files in an **exchange folder**; the bridge calls the AI's API:

```text
game ──requests.txt──▶ bridge ──HTTPS──▶ AI API
game ◀─responses.txt── bridge ◀─────────
```

- Exchange folder: `<Zomboid folder>/Lua/batman_RadioSurvivor/` (in singleplayer on Windows:
  `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor`).
- The bridge shows it is alive by rewriting `bridge-alive.txt` every 5 s. While it is alive, the game waits up to 150 s
  for a slow answer; without a bridge, it falls back after 90 s.
- The server never sends secrets to the AI (exact base positions, hidden frequencies…) and checks every action it
  proposes.
- **A Workshop mod can neither ship nor start a program**: the bridge is installed and started by hand.

| Game | Where the bridge runs |
|---|---|
| Singleplayer | On your PC |
| Game hosted from the menu ("Host") | On the host's PC |
| Dedicated server | On the server machine (or a neighboring container) |
| Players who join | **Nothing to install** |

### 1. The files

The bridge is five Python files, to be kept **together in the same folder** and updated along with the mod:

| File | Role |
|---|---|
| `radio_bridge.py` | Main program: watches the files, calls the AI, writes the answers |
| `npc_protocol.py` | Notebook NPC dialogue |
| `persona_store.py` | Reads the voices' character sheets |
| `bulletin.py` | The pirate station's evening bulletin |
| `last_pages.py` | A dead character's last pages |

Plus `.env.example`, the template for the settings file. In this repository: the [`bridge/`](bridge/) folder.

### 2. Python

Python 3.10 or newer (`python --version`, or `python3 --version` on Linux). The bridge only uses the standard library:
nothing to install with `pip`.

### 3. The key and the AI provider

The bridge talks to any provider compatible with the **OpenAI Chat Completions API**
(`POST <address>/chat/completions`): OpenAI, DeepSeek, OpenRouter, Mistral, or a local server such as Ollama or
LM Studio. Copy `.env.example` to `.env` in the bridge folder and fill in the three settings:

```ini
OPENAI_KEY=<your key>
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=<model name at this provider>
```

- `OPENAI_BASE_URL` is written **without** `/chat/completions`. Take the exact address and model name from your
  provider's documentation. A local server usually needs no key: put any value.
- An **environment variable** with the same name takes precedence over the file; another file can be given with
  `--env PATH`.
- **Never share `.env`** or a `--debug` log (it contains the prompts). The bridge banner only shows
  `API key: configured (hidden)`. If the key leaks, revoke it at your provider.

### 4. Check without the game

In a terminal opened in the bridge folder:

```powershell
python radio_bridge.py --test "Hello?"
```

A few lines from Walt appear: the key, address and model are correct. `--voice darlene` tries another voice;
`--offline` checks the install with no key and no cost (the voice repeats your sentence).

### Bridge in singleplayer

```powershell
python radio_bridge.py
```

The banner shows the effective configuration, then `Bridge ready, model …, directory …`. **Keep the window open**
while you play; the order (game or bridge first) does not matter. Stop it with **Ctrl+C**.

- Default exchange folder: `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` (created if needed).
- Game started with `-cachedir=X`: add `--exchange "X\Lua\batman_RadioSurvivor"`.
- To keep the log in a file: `python radio_bridge.py > bridge.log 2>&1`.

### Bridge in a hosted game

Same as singleplayer, on the host's PC: the server started by the game uses the same `Zomboid` folder as the host's
game.

### Bridge on a dedicated server

1. **The right exchange folder.** The bridge must watch exactly the folder the server writes to:

   | Case | Exchange folder |
   |---|---|
   | Windows, no `-cachedir` | `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` |
   | Linux, no `-cachedir` | `/home/<server account>/Zomboid/Lua/batman_RadioSurvivor` |
   | Server started with `-cachedir=X` | `X/Lua/batman_RadioSurvivor` |

   Without `--exchange`, the bridge uses the `Zomboid` folder of **its own** account: pass `--exchange` as soon as the
   server runs under another account or with `-cachedir`. The bridge creates the folder if it is missing, so a typo
   gives no error: after the world has loaded once, the right folder contains `personas/`.
2. **Install** the five files in a folder (for example `C:\RadioSurvivorBridge` or `/opt/radiosurvivor-bridge`) and the
   key file **outside** that folder and the game folders, readable only by the bridge's account (`chmod 600` on Linux).
3. **Test by hand**:

   ```sh
   python3 /opt/radiosurvivor-bridge/radio_bridge.py --env /etc/radiosurvivor/bridge.env \
     --exchange /srv/pz/cache/Lua/batman_RadioSurvivor
   ```

   and wait for `Bridge ready`.
4. **Start it with the server.** On Linux, a systemd service:

   ```ini
   # /etc/systemd/system/radiosurvivor-bridge.service
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

   then `sudo systemctl daemon-reload && sudo systemctl enable --now radiosurvivor-bridge` (log:
   `journalctl -u radiosurvivor-bridge -f`). On Windows: a scheduled task "At startup" running
   `python radio_bridge.py --env … --exchange …`. With Docker: a second `python:3.12-slim` container mounting **the
   same volume** as the server data, under the same user. Details, Windows and Docker:
   [docs/bridge-setup.md](docs/bridge-setup.md) ([français](docs/installation-pont.md)).
5. **Rules**:
   - **one bridge per exchange folder**: a second one refuses to start (`bridge.lock`); two servers on the same machine
     each get their own `-cachedir` and their own bridge;
   - the bridge runs on **the same machine** (or the same container host) as the server: the request age (75 s) and the
     heartbeat are compared against the local clock;
   - the bridge's account reads and writes the exchange folder, the server's account reads what the bridge writes.

### Bridge options

| Option | Role |
|---|---|
| `--offline` | No AI, no key, no cost: the voices repeat your sentence (to test the install). |
| `--test "TEXT"` | One exchange in the console, without the game; `--voice ID` for a voice other than `walt`. |
| `--env PATH` | Settings file other than the `.env` next to the bridge. |
| `--exchange PATH` | Another exchange folder. |
| `--personas PATH` | Voice sheet folder for `--test` (default: the sheets shipped with the mod). |
| `--usage-log PATH` | Usage log (default `<exchange>/token_usage.jsonl`). |
| `--debug` | Full log in the terminal, prompts and dialogue included. |
| `--poll SECONDS` | How often `requests.txt` is read (default 0.3). |
| `--help` | Full help. |

### Cost

- Every radio message, every NPC line, every unprompted call, bulletin or last page is **one AI call** (up to two or
  three if the provider rejects a parameter or returns an empty answer).
- In-game safeguards: the **`MaxPerHour`** option (60 radio messages per real hour for the whole server, `0` =
  unlimited, avoid it on a public server), `PlayerCooldown`, `InitiativeFrequency` for unprompted NPC speech, fixed
  caps of 60 NPC dialogues and 12 biographies per hour.
- Usage (tokens per call, totals) is written to `token_usage.jsonl`; the bridge does not estimate any price.
- **Set a monthly spending limit at your provider**: it is the only limit that holds even if an option is set wrong.

### Without the bridge

The game stays playable: the radio answers "Only static...", the evening bulletin and last pages use short fixed
texts, and the NPCs stay silent. Everything else (groups, fights, homes, notebook missions, trading) keeps going.

## Configuration

### Sandbox options

Two pages in the sandbox settings (on a dedicated server: `<Zomboid>/Server/<name>_SandboxVars.lua`).

**Radio Survivor**: `Enabled` (radio voices), `PlayerCooldown` (10 s between two messages from a player), `MaxPerHour`
(60), `SpontaneousCalls`, `CallLanguage` (language of unprompted calls), `NoteRarity` (frequency notes in the loot),
`ChronicleHour` (bulletin time, 8 PM), `LastPages`, `InitiativeFrequency` (unprompted NPC speech), `RescueDays` (time
to rescue a family).

**Living Knox**: `Enabled` (survivor groups), `Debug`, `GroupCount` (3 to 5, **set it before creating the world**),
settler / raider / neutral proportions, group size, replacement delay for a wiped-out group, `RaidsEnabled` and
`RaidDays` (raider raids), `RevengeDelayHours`, and the alert, flee, defense and warning distances.

Full list with default values: [docs/wiki/Sandbox-Options.md](docs/wiki/Sandbox-Options.md).

### Voice personalities

Each voice has a text sheet in `<exchange folder>/personas/<voice>.txt` (frequencies, hours, required radio, allowed
actions, what it knows, ignores or hides, and its prompt after `[prompt]`). The server installs it the first time the
world loads and rereads it every 30 s: editing it changes the voice without a restart. A sheet edited by the admin is
never overwritten by a mod update. Format: [docs/persona-format.md](docs/persona-format.md) (in French).

## Playing

1. **Find a frequency**: loot, read the notes ("Inspect").
2. **Talk to a voice**: a walkie-talkie turned on **in hand or on your back** (never from the belt), mic on, tuned to the
   frequency; in the radio window, **Transmit** section: type your sentence, press Enter. A placed HAM radio (within 5
   tiles) and a vehicle radio that can transmit work too.
3. **Meet a group**: approach without aiming a weapon, **Ctrl+G** to select the NPC, talk in local chat. Get to know
   them before asking for work.
4. **Mission**: accept it in the notebook (**Missions**), complete the objective (circle on the map), go back and report
   to whoever gave it, then claim the reward (**Claim shared reward**).
5. **Notebook**: Radio tab to reread conversations, Contacts for what each NPC thinks of you, Reputation for your level
   and your latest actions.

Admins and debug mode: a group admin window, an NPC sheet on right-click and an NPC debug panel (the game's debug panel
in singleplayer, the admin panel in multiplayer).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Always "Only static..." | Bridge stopped, wrong exchange folder (`--exchange`), invalid key or model (`--test`), provider too slow (over 60 s per call). |
| The bridge refuses to start | Another bridge is already watching this folder (`bridge.lock`). |
| No voice on a frequency | Nobody holds it this game, outside its hours, or the radio is not powerful enough (shortwave). |
| `Expired request ignored` | Request older than 75 s: bridge started late or clocks differ (bridge on another machine). |
| Radio Survivor missing from the game | A required mod is missing (Belt Walkie-Talkie, TooltipLib, Signal Smoke) or not in `WorkshopItems=`. |

Logs: bridge output (`bridge.log` if redirected), `token_usage.jsonl`, `%USERPROFILE%\Zomboid\console.txt`
(singleplayer), the server's `server-console.txt`. More cases: [docs/wiki/Troubleshooting.md](docs/wiki/Troubleshooting.md).

## Project status

Test build, not published on the Workshop.

- Every radio, notebook and Living Knox feature is checked **in singleplayer** by automated test campaigns (the real
  42.21 game driven by script), and a large part is also checked **in multiplayer** (dedicated server and two driven
  clients). Detailed status and development log (in French): [docs/fonctionnalites.html](docs/fonctionnalites.html);
  plan: [docs/plan/SUIVI.md](docs/plan/SUIVI.md).
- The tests run in a quiet test game; a long game with normal zombie population still has to be put through its paces.
- Known limits: NPC assaults through a window are still unreliable in multiplayer; NPC fishing is unverified; the voices
  only give scouting missions; text beyond Latin-1 ("’", "€") is not transmitted correctly.

## Development

```text
Contents/mods/batman_RadioSurvivor/42.21/   the mod (client, server, shared Lua; personas; EN/FR translations)
bridge/                                     the Python bridge
dev/batman_RadioSurvivorTests/              in-game test mod (RST), never published
tests/                                      offline test benches (lupa, Kahlua VM)
tools/                                      plan, in-game campaigns (autoclient), test zip
docs/                                       design, protocol, plan, wiki, guides
workshop/                                   Workshop descriptions (EN, FR)
```

- All offline tests: `python tests/run_all.py` (needs `lupa`; no paid AI calls).
- Automated in-game campaigns: `tools/autoclient/autoclient.py` (singleplayer, dedicated server with two clients,
  parallel slices, fake AI model); method: [docs/tests-en-jeu.md](docs/tests-en-jeu.md).
- Lua ↔ Python contract: [docs/protocole-carnet-v2.md](docs/protocole-carnet-v2.md); Living Knox API:
  [docs/api.md](docs/api.md); design: [docs/conception/README.md](docs/conception/README.md). These documents are in
  French.
- Local test zip without the Workshop: `python tools/make_test_zip.py` (writes `dist/`).
- Wiki pages ready to publish: [docs/wiki/](docs/wiki/Home.md).
- Living Knox is written independently: no code from Bandits! or Project A-Life is reused.

## License

MIT — see [LICENSE](LICENSE).
