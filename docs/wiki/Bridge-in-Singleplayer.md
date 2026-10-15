*Français : [[Le pont en solo|Bridge-in-Singleplayer-FR]]*

# The bridge in singleplayer

Project Zomboid's Lua has no network access. The game writes the requests to a text file, the bridge calls the AI and
writes the answers back:

```
game → requests.txt → bridge → AI API
game ← responses.txt ← bridge
```

In singleplayer (and in a game hosted from the menu), the bridge runs **on your PC**, in a terminal window left open
while you play.

## 1. What you need

- **Python 3.10 or newer** (`python --version`). No package to install: the bridge uses only the standard library.
- The **five bridge files**, kept together in one folder: `radio_bridge.py`, `npc_protocol.py`, `persona_store.py`,
  `bulletin.py`, `last_pages.py`, plus `.env.example`. Use the bridge of the same version as the mod.
- An **API key** from a provider compatible with the OpenAI API: see
  [[AI provider configuration|AI-Provider-Configuration]]. Not needed for `--offline`.

## 2. The key

In the bridge folder, copy `.env.example` to `.env` and fill it in:

```
OPENAI_KEY=<your key>
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=<model name>
```

Never share this file. Environment variables of the same name win over it; another file can be given with
`--env PATH`.

## 3. Check without the game

Open a terminal in the bridge folder:

```powershell
python radio_bridge.py --test "Hello?" --personas "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas"
```

A few lines from Walt appear: key, address and model are right. The `personas` folder is filled by the game the first
time a world is loaded; before that, point `--personas` to the `42.21\personas` folder of the installed mod (in the
Steam Workshop folder) or, from the mod's development repository, leave it out. Add `--offline` to check without a
key (the voice echoes your sentence).

## 4. Start it

```powershell
python radio_bridge.py
```

The banner shows the effective settings (the key stays hidden), then `Bridge ready, model …, directory …` and
`Waiting for game requests (Ctrl+C to stop)`. Load your game; the order (game or bridge first) does not matter.

- Default exchange folder: `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor` (the bridge creates it if needed). If you
  start the game with `-cachedir=X`, add `--exchange "X\Lua\batman_RadioSurvivor"`.
- While it runs, the bridge refreshes `bridge-alive.txt` in that folder every 5 s; the game then waits up to 150 s
  for a slow answer instead of falling back after 90 s.
- Stop it with **Ctrl+C** (`Bridge stopped`).
- Only **one** bridge per folder: a second one refuses to start.

## Useful options

| Option | Role |
|---|---|
| `--offline` | No AI, no key, no cost: the voices echo you. To test the setup. |
| `--debug` | Full log in the terminal, including prompts and dialogues: do not share as is. |
| `--test "TEXT"` | One exchange in the console, without the game; `--voice ID` for another voice than `walt`. |
| `--env PATH` | Another settings file. |
| `--exchange PATH` | Another exchange folder. |
| `--usage-log PATH` | Another token usage journal (default `<exchange>/token_usage.jsonl`). |
| `--poll SECONDS` | How often `requests.txt` is read (default 0.3). |
| `--help` | Full help. |

To keep the log in a file: `python radio_bridge.py > bridge.log 2>&1`.

## Without the bridge

The game stays playable: the radio answers "Only static...", the evening bulletin and the last pages use short
fixed texts written by the game, and the NPCs stay silent. See [[Troubleshooting]].
