*Français : [[Dépannage|Troubleshooting-FR]]*

# Troubleshooting

## Where to look

| Log | Where |
|---|---|
| Bridge | Its terminal window. To keep it: `python radio_bridge.py > bridge.log 2>&1`; systemd: `journalctl -u radiosurvivor-bridge`. Relaunch with `--debug` for the full detail (contains the dialogues: do not share as is). |
| Game (singleplayer, host) | `%USERPROFILE%\Zomboid\console.txt`, lines `[RadioSurvivor]`, `[RS_Carnet]`, `[LK…]`. |
| Dedicated server | The server console log (`<Zomboid>/server-console.txt` or your service log). |
| Exchange folder | `requests.txt`, `responses.txt`, `bridge-alive.txt`, `token_usage.jsonl`, `personas/`. |

## Checklist: is the bridge working?

1. The bridge terminal shows `Bridge ready, model …, directory …`. If not, read the last line (missing setting, other
   bridge running).
2. `Exchange directory` in the banner is the server's folder: it holds `personas/` after the first world load, and
   `bridge-alive.txt` while the bridge runs.
3. When you speak on the radio, the terminal shows `<caller> -> walt : <sentence>`. If nothing appears, the game
   writes to another folder, or your radio is not on a voice's frequency (a sentence on an empty frequency is simply
   transmitted, nothing else happens).

## Voices silent or "Only static..."

| Symptom | Cause and fix |
|---|---|
| "Only static..." after about 90 s; server log `no answer from the bridge for <id> (is bridge\radio_bridge.py running?)` | No bridge seen: stopped, or watching another folder. Check `Exchange directory` and `bridge-alive.txt` in the server's folder. |
| "Only static..." after about 150 s, bridge running | The AI did not answer within 60 s, or the request waited more than 75 s: see `LLM error` or `Expired request ignored` in the bridge. |
| "Only static..." at once | The game could not write `requests.txt` (rights on `Zomboid/Lua`, disk full). |
| "Too much chatter on the frequency, try again later." | `MaxPerHour` reached or 8 pending requests. Raise `MaxPerHour` if needed. |
| "You need a two-way radio: in your hand or on your back (not on your belt)…", or no **Transmit** section | Transmitting needs a transmitting radio in hand or worn on the back (or set down nearby, or the radio of your vehicle), switched on, microphone open. Not from the belt or a bag. |
| NPCs never answer; notebook says "Bridge missing, invalid or expired reply. No decision applied." | Same causes for an NPC dialogue; the server log names it: `no reply after 150000 ms`, `bridge error timeout`, `http_503`, `unreachable`, `bad_response`, `invalid_or_unavailable`, `expired`. |
| "Unable to send to the bridge." | `requests.txt` cannot be written. |

## Bridge messages

| Message | Cause and fix |
|---|---|
| `Missing configuration: OPENAI_KEY, …` | `.env` not found (wrong `--env`) or empty value. See [[AI provider configuration|AI-Provider-Configuration]]. |
| `Another bridge is already running on …` | One bridge per folder: stop the other one (terminal, scheduled task, service). |
| `ModuleNotFoundError` | One of the five bridge files is missing next to `radio_bridge.py`. |
| `LLM error (<id>): no valid sheet for voice 'walt' in …/personas` | Wrong exchange folder, or the world was not loaded yet. |
| `HTTP 401` / `HTTP 403` | Key refused or revoked. |
| `HTTP 404` | Wrong model name or `OPENAI_BASE_URL`. |
| `HTTP 429` | Provider quota or rate limit reached. |
| `URLError` / `TimeoutError` / `LLM budget of 60s spent` | No network to the API, firewall, proxy, or a model slower than 60 s. |
| `LLM answer cut by the token limit` | The answer was too long; it is not shown. Occasional: normal. Constant: try another model. |
| `Expired request ignored (<id>, <n>s)` | Request older than 75 s when taken (bridge started late, server restarted): normal. Frequent: queue saturated or server and bridge on different clocks. |
| `reply of voice '<id>' withheld: it quotes one of its secrets` | Normal: the voice was about to reveal a secret; replaced by static. |
| `Token usage journal write failed` | The usage journal is not writable; the bridge keeps running. |

## Slow answers

- The bridge runs at most 4 AI calls at once; others wait. A slow model plus many players fills the queue, and
  requests older than 75 s are dropped.
- Pick a faster model, lower `InitiativeFrequency`, or keep `MaxPerHour` reasonable.
- With a live bridge the game waits up to 150 s; the answer arrives late but is not lost.
