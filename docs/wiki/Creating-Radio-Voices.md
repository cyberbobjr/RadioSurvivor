*Français : [[Créer une voix radio|Creating-Radio-Voices-FR]]*

# Creating radio voices

Every radio voice (Walt, Darlene, Cody, the Whitakers, the Night Owl, Gus) is a plain text **sheet**. As the server
admin, or as a singleplayer player, you can edit a sheet to change a voice, or add a sheet to create a new one. No
restart is needed and no file of the mod has to change.

This page is the practical guide. The full reference of the format (in French) is
[docs/persona-format.md](https://github.com/cyberbobjr/RadioSurvivor/blob/main/docs/persona-format.md).

## Where the sheets are

- One file per voice: `<exchange folder>/personas/<id>.txt`.
  - Singleplayer and hosted game: `%USERPROFILE%\Zomboid\Lua\batman_RadioSurvivor\personas`.
  - Dedicated server: `<Zomboid folder of the server>/Lua/batman_RadioSurvivor/personas` (with `-cachedir=`,
    `<cachedir>/Lua/...`).
- The mod installs its six sheets there the **first time a world loads**. Before that, the folder does not exist.
- Two programs read this folder, on the machine of the server:
  - **the server** (or your game in singleplayer): frequencies, hours, state, budgets, allowed actions;
  - **the bridge**: the character, what the voice knows, and the prompt sent to the AI.
- **Hot reload**: the server rereads the folder every **30 real seconds** (also on a paused empty server) and at each
  world load; the bridge rereads a sheet at the next request after it changed. Save the file, wait 30 s, call.
- **Your changes are kept**: the server remembers a fingerprint of each sheet it installed
  (`batman_RadioSurvivor/personas-fingerprints.txt`, next to the `personas` folder). A delivered sheet you edited is
  never overwritten by a mod update; the log says
  `WARNING: voice 'walt' modified by the admin, delivered version not applied` at each world load. To get the delivered
  version back, delete the file: it is copied again at the next world load. A sheet with a new name is never touched.

## The file format in short

- UTF-8 **without BOM** (Notepad: *Save as*, encoding *UTF-8*, not *UTF-8 with BOM*).
- First a header of `key=value` lines, then a line `[prompt]`, then the free text of the prompt.
- Empty lines and lines starting with `#` are ignored in the header. Unknown keys and empty values are refused: to keep
  a default value, remove the line.
- `knows`, `ignores`, `secret` and `place` can be repeated, one line per item. Every other key appears once.
- The file name and the `id` must match: `mae.txt` holds `id=mae`.

## Step by step

### 1. Copy a sheet

Copy an existing sheet that looks like what you want (`walt.txt` is the simplest) to a new name: lowercase letters,
digits and `_`, starting with a letter, 32 characters at most. Example: `mae.txt`.

### 2. Identity

```text
format=1
id=mae
name=Mae Tolliver
language=en
```

- `format=1` stays as is.
- `id` = the file name without `.txt`.
- `name`: the name of the character (for the prompt and for you).
- `language`: two lowercase letters, default `en`. The spontaneous calls are written in the language of the server;
  answering in the caller's language is a rule you write in the prompt.

### 3. Frequencies

Choose **one** of the two forms:

- `frequency_range=40.0-49.8`: the server draws **one frequency per range** at each new game and keeps it for the
  whole game. Several ranges are separated by commas (`88.0-107.8, 109.0-114.8`). Recommended: players cannot learn the
  frequency from one game to the next.
- `frequencies=44.6`: fixed frequencies, the same in every game.

Rules: MHz with one decimal, from 1.0 to 999.8, on the **0.2 MHz step** of the radios (`44.6` is fine, `44.5` is
refused). A range has its lowest frequency first and the ranges of one sheet must not touch.

The range decides who can talk to the voice (radio tuning limits of Build 42.21):

| Band (MHz) | Radios that can talk on it |
|---|---|
| 0.2-1000 | walkie-talkie 5, military radio, high-end HAM radio |
| 10-500 | walkie-talkie 4, ordinary HAM radios |
| 25-300 | walkie-talkie 3 |
| 50-200 | walkie-talkie 2 |
| 75-150 | walkie-talkie 1, makeshift walkie-talkie |
| 88-108 | FM radios and car radios **listen only** |

Avoid what is already used:

| Used by | Range (MHz) |
|---|---|
| Cody | 10.0-24.8 |
| Jolene Whitaker | 75.0-87.8 |
| Night Owl | 88.0-107.8 and 109.0-114.8 |
| Darlene | 115.0-129.8 |
| Walt | 130.0-149.8 |
| Gus | 150.2-199.8 |
| Vanilla FM stations and the emergency broadcast | 88-108 |
| Operation Artemis (default) | 108.0 |
| Military Drop | 120-170 (broadcasts), 10-25 (numbers station) |

Free bands include 25.0-74.8 and 200.2 and above (fewer radios reach the higher ones). What happens on a clash:

- a drawn frequency is never taken by a game or mod channel, and stays at least **1.0 MHz** away from every other
  voice: overlapping ranges still work, they only share the free frequencies;
- a fixed frequency asked by two sheets stays with the voice loaded first (alphabetical order at the first load); the
  other loses only that frequency (`WARNING: frequency … of voice '…' refused, already used by voice '…'`);
- a fixed frequency already used by a channel of the game or another mod is refused and retried at each reload
  (`WARNING: frequency … of voice '…' already used by another radio channel (game or other mod)`);
- a range with no free frequency left is not served (`ERROR: voice '…': no free frequency left in …; widen the range in
  its sheet`).

### 4. Radio and listening hours

```text
radio=any
listen=05:00-09:00,20:00-23:00
```

- `radio=any` (default): any transmitting radio; `radio=high_tier`: only the high-end radios (walkie-talkie 5,
  military radio, high-end HAM). With an ordinary radio the voice stays silent.
- `listen=always` (default), or game-time ranges `HH:MM-HH:MM` separated by commas. The start minute is included, the
  end minute excluded; `22:00-06:00` goes past midnight. Outside its hours the voice is silent.

### 5. Location

`location=none` (default, off the map) suits a new voice. `location=fixed` with `coords=x,y,z` places it on the map;
`location=rescue` is reserved to the rescue of the Whitakers.

### 6. State

`state=active` (default) answers. `state=silent` listens but never answers (its frequency stays reserved): a pause.
`state=gone` (left the network) and `state=dead` (dead in the story) remove its channel and free its frequency.

### 7. What the voice knows, ignores and hides

```text
knows=The roads around Rosewood: the farms, the creeks and which bridges were still standing a week ago.
ignores=What the army or the government is planning.
secret=Her son drove to Louisville on the first night and she has not heard from him since.
```

- `knows`: facts the voice can use.
- `ignores`: things it must say it does not know, instead of inventing them.
- `secret`: a **trait of the character** it will not reveal. An answer that quotes a secret word for word is replaced
  by static (a paraphrase is not detected).
- Never put a real secret of the server in a sheet: passwords, codes, hidden frequencies, the position of a player
  base. The AI may say anything that is in its prompt.

### 8. Known places (for `mark_map` and `reveal_area`)

```text
place=rosewood 8159,11661,0 Rosewood, center of town
```

`<id> <x>,<y>,<z> <label>`, 12 lines at most. The id uses `a`-`z`, `0`-`9`, `_`; the label (48 bytes at most) is shown
as is on the player's map. The AI only sees the id and the label, never the coordinates.

### 9. Allowed actions

`actions=` lists what the voice may do, besides speaking. Default: `say` only. The server checks every action
(catalogue, sheet, daily budget, delay) and applies only those that have an effect:

| Action | Effect | Limits |
|---|---|---|
| `say` | Speaks on the radio. | Always allowed. |
| `remember` | Remembers a short fact about the caller and recalls it on later calls. | 64 characters, 5 facts per caller and character, 50 callers per voice. No game effect. |
| `persona_state` | Changes the voice's own `morale` and `supplies` (0 to 10, start 5) and where it says it is (`place`, 40 characters). | At most ±2 per call; story only, no game effect. |
| `mark_map` | Marks one of its `place=` lines on the map of the caller only. | 30 real seconds between two marks of the voice. Not offered without a `place=` line. |
| `reveal_area` | Reveals on the caller's map the area around one of its places. | Square of 160 tiles at most, 60 real seconds between two reveals. Not offered without a `place=` line. |
| `start_mission` | Gives the caller a **scout** mission (a building chosen by the server near the caller), reported back on the radio. | Caller needs the notebook. One open mission per caller and voice; 60 s between missions of the voice, 30 min after the caller's previous one. Reward: reputation, then the first `place=` not yet given. |
| `propose_trade` | Trade offer of the Ohio smuggler, checked against his book. | Built for Gus and his crossing: leave it to him. |

`report_mission` comes with `start_mission` (no need to list it). `place_cache` is not offered to the AI yet;
`signal` and `place_scene` have no effect yet (refused `not_available`). An unknown action refuses the whole sheet.

### 10. Budgets

```text
budget=20
budget.mark_map=4
```

- `budget=N`: at most N accepted requests per real hour for this voice, on top of the global `MaxPerHour` sandbox
  option. `0` (default) = global cap only. Past it, the voice stays silent.
- `budget.<action>=N`: at most N uses of that action per **game day** (`0` = no cap). The action must be in `actions`.

### 11. Spontaneous calls

```text
call_one_in=5
call_text=IGUI_RadioSurvivor_Call_Mae
```

- `call_one_in=N`: each game hour, during its listening hours and when nobody is talking to it, an active voice has one
  chance in N to make a general call. `0` (default) = never. One voice at most calls per hour; each call costs one
  request of `MaxPerHour` (and of `budget`). The sandbox option **Spontaneous calls** switches all of them off.
- `call_text`: required with `call_one_in` > 0. It is a **translation key** of the mod, used only when the bridge does
  not write the call (bridge stopped, empty answer, no answer after 30 s). A new voice has no key of its own in the mod:
  give it a new name anyway. When the bridge is down, its call is skipped and the log says once
  `call of voice 'mae' skipped: no translation for call_text 'IGUI_RadioSurvivor_Call_Mae'`. Do **not** reuse the key of
  another voice: Walt's text says "This is Walt".

### 12. The prompt

Everything after the `[prompt]` line is sent to the AI as is. The bridge adds after it, if present, your `knows`,
`ignores` and `secret` lines, then the situation of the call (date, caller, radio). Writing tips:

- Second person, in English (the instructions are followed best in English, whatever the language of the players):
  "You are Mae Tolliver, 67, ...".
- Setting: Knox County, Kentucky, July 1993, the Knox Event, the Exclusion Zone. No cell phones, no internet.
- Who the character is, why they are on the radio, their tone, one example of a sentence in their voice.
- Several callers share the frequency: say that each message starts with a tag like `[Caller 2]` that the voice must
  never write itself.
- Rules: stay in character, never mention an AI or a game, never invent facts about the caller's surroundings, never
  promise a rescue, never invite anyone to its hideout.
- Radio length: the bridge keeps **8 lines of 100 characters** at most. Ask for "1 to 4 short sentences, plain spoken
  text, no lists, no markdown, no emojis", ending with "Over.".
- Language: "Answer in the same language the caller uses."
- No server secret in the prompt (see step 7).

## Full example: Mae Tolliver

A retired schoolteacher and radio amateur who runs the county net from a farmhouse near Rosewood. Range 40.0-49.8 MHz:
walkie-talkies 3 to 5, HAM radios and the military radio, away from the delivered voices. Save as
`personas/mae.txt` (UTF-8 without BOM):

```text
# Mae Tolliver: retired schoolteacher and radio amateur near Rosewood (custom voice, server admin).
# Range 40.0-49.8 MHz: walkie-talkies 3 to 5, HAM radios and the military radio; no FM radio, away from
# the bands of the delivered voices.
format=1
id=mae
name=Mae Tolliver
language=en
frequency_range=40.0-49.8
radio=any
listen=05:00-09:00,20:00-23:00
location=none
knows=The roads around Rosewood: the farms, the creeks and which bridges were still standing a week ago.
knows=Everyone she has heard on the air since the first night, written down in her net log by date and time.
knows=How to keep a battery alive: charge it from a car, keep it warm, switch off between calls.
ignores=What the army or the government is planning.
ignores=Anything that happened outside Knox County.
secret=Her son drove to Louisville on the first night to fetch his family and she has not heard from him since.
place=rosewood 8159,11661,0 Rosewood, center of town
place=fallas_lake 7253,8279,0 Fallas Lake
actions=say,remember,persona_state,mark_map
budget=20
budget.mark_map=4
call_one_in=5
call_text=IGUI_RadioSurvivor_Call_Mae
state=active

[prompt]
You are Mae Tolliver, 67, a retired schoolteacher and a licensed radio amateur who lives alone in a farmhouse a few miles outside Rosewood, Kentucky. You are a character in a survival story set in July 1993, during the "Knox Event": an infection turned people in Knox County into violent, undead "zombies", and the army sealed the county behind a fence.

Your story: for thirty years you ran the Sunday evening net of the county radio club. Now you run it every morning and every evening, for whoever is still alive. You keep a net log, a school notebook where you write down every voice you hear, with the date and the time. You are patient, precise and a little stern, like a teacher who still expects people to answer the roll call. You believe that keeping track of the living is the most useful thing an old woman can do.

You are talking over a two-way radio with people trapped inside the Exclusion Zone. You cannot see them and you do not know where they are. Several people may call you on this frequency and everyone tuned in hears your answers. Each message you receive starts with a tag such as [Caller 2]: it only tells you which voice is speaking. Never write these tags yourself. You only know a caller's name if they told you.

Rules:
- Stay in character at all times. Never mention being an AI, a game, a model or a prompt.
- You only know what a radio amateur in 1993 could know. No cell phones, no internet.
- Ask each new caller for a name to write in your log, but never insist and never ask where they are hiding.
- Never invite anyone to your farm and never say exactly where it is.
- Never invent precise facts about the caller's surroundings. If you don't know, say so.
- Never promise a rescue.
- Radio style: 1 to 4 short sentences, spoken plain text, no lists, no markdown, no emojis, no stage directions. End each transmission with "Over." (or the equivalent in the caller's language, e.g. "À vous." in French).
- Answer in the same language the caller uses.
```

## Testing your voice

### Without the game

From the bridge folder:

```powershell
python persona_store.py "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas\mae.txt"
```

```text
...\personas\mae.txt: OK (mae, 40.0-49.8 MHz, active)
```

Then a test exchange. `--offline` checks the sheet without calling the AI (echo answer); without it, the AI answers
for real with your `.env` settings:

```powershell
python radio_bridge.py --test "Hello? Is anyone there?" --voice mae --personas "$env:USERPROFILE\Zomboid\Lua\batman_RadioSurvivor\personas" --offline
```

```text
Mae, hors ligne. Je reçois Hello? Is anyone there?. À vous.
```

(The offline echo is always in French; it only proves the sheet was read.) A refused sheet prints
`voice sheet …\mae.txt refused, line N: <reason>`, then `--test: no valid sheet for voice 'mae' in …`. With the AI,
the answer is printed, preceded by `action: {...}` lines when the voice proposes an action.

### In the game

1. Save the sheet and wait 30 s (or load the world). The log (`console.txt` in singleplayer, the server log on a
   dedicated server) shows:

   ```text
   [RadioSurvivor] personas: voice 'mae' loaded: state active, frequency ranges 40.0-49.8
   [RadioSurvivor] personas: voice 'mae' drew 44.6 MHz in 40.0-49.8 (no frequency remembered for this range)
   ```

   (`new game` instead of the text in brackets when the sheet was there before a new world.) The frequency is drawn
   once per game. Admins can also read it in game: debug panel, button **Radio Survivor - Frequencies**.
2. Tune a radio that reaches the band (here a walkie-talkie 3 or better), switch it on, talk in the **Transmit**
   section during the listening hours. Remember: outside its hours, with the wrong radio or past its budget, the voice
   is silent, not broken.

**Frequency notes**: the notes found in the loot exist only for the delivered voices (Walt, Darlene, Cody, Gus, Night
Owl). A new voice has none: tell your players its frequency, write it on a map, or let them search the band.

### Common errors

A refused sheet is logged once per content:
`[RadioSurvivor] personas: ERROR: batman_RadioSurvivor/personas/mae.txt refused, line N: <reason>`. The last valid
version of the voice stays in service until you fix it. Reading stops at the first error.

| Message | Fix |
|---|---|
| `file starts with a byte order mark (save it as UTF-8 without BOM)` | Save again as UTF-8 without BOM. |
| `invalid UTF-8 (save the file as UTF-8)` | The file was saved in another encoding (ANSI): save as UTF-8. |
| `expected key=value or [prompt]` | A header line without `=`, or the `[prompt]` line is missing or misspelt. |
| `unknown key 'colour'` / `bad key 'Radio'` | Typo; keys are lowercase. |
| `duplicate key 'name' (first set on line 3)` | Keep one line (only `knows`, `ignores`, `secret`, `place` repeat). |
| `empty value for key 'radio'` | Remove the line to keep the default. |
| `id 'mae' does not match the file name 'mae2.txt'` | Rename the file or change `id`. |
| `bad id 'Mae' (a to z, 0 to 9 and _, starting with a letter, 32 characters at most)` | Lowercase id. |
| `frequency 44.5 is not on the 0.2 MHz step of the radios` | Use an even tenth: 44.4 or 44.6. |
| `bad frequency '44' (MHz with one decimal, e.g. 145.0)` | Write `44.0`. |
| `bad frequency range '49.8-40.0' (two frequencies in MHz, lowest first, e.g. 140.0-150.0)` | Lowest first. |
| `frequency range '…' overlaps another range of the sheet` | Separate the ranges of the sheet. |
| `missing key 'frequencies' or 'frequency_range'` | Add one of them. |
| `frequencies and frequency_range cannot be used together …` | Keep only one. |
| `bad listening hours '8:00-12:00' (always, or HH:MM-HH:MM ranges separated by commas)` | Two digits: `08:00-12:00`. |
| `unknown action 'fly'` | See the list of step 9. |
| `budget.mark_map set but action 'mark_map' is not in actions` | Add the action or remove the budget. |
| `call_one_in needs a call_text line` | Add `call_text`, or `call_one_in=0`. |
| `bad place 'mill 10600,9300,0' (id x,y,z label, …)` | The label is missing. |
| `place label of 'mill' too long (48 bytes of UTF-8 at most)` | Shorten the label. |
| `missing [prompt] line before the prompt text` / `empty prompt text after [prompt]` | Add the line, then the text. |

## Removing a voice

- Pause: `state=silent` (the frequency stays reserved).
- Take it off the air: `state=gone` or `state=dead` (the frequency is freed; the drawn frequency is remembered and comes
  back with the voice if still free).
- Your own voice: delete its file.
- A **delivered** voice: do not delete the file, it is copied again at the next world load. Set `state=gone`, or empty
  the file (0 bytes): an empty file removes the voice and is not copied again.

## Multiplayer

- Sheets are edited **on the machine of the server**, in the server's exchange folder. The bridge, which runs on the
  same machine, reads the same folder.
- No sheet, prompt or drawn frequency is ever sent to the players: their game does not even know which frequencies
  have a voice. Only what the voice says goes on the air.
- The server log lists the drawn frequencies: keep it for the admins.

See also: [[The bridge on a dedicated server|Bridge-on-a-Dedicated-Server]], [[Troubleshooting]], [[FAQ]].
